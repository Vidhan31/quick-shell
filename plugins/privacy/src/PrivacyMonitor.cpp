#include "PrivacyMonitor.hpp"

#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <fcntl.h>
#include <sys/inotify.h>
#include <unistd.h>

namespace qs::plugins {

PrivacyWorker::PrivacyWorker(int intervalMs, QObject *parent)
    : QObject(parent)
    , m_intervalMs(intervalMs)
{
}

PrivacyWorker::~PrivacyWorker() {
    stop();
}

void PrivacyWorker::start() {
    setupInotify();
    setupPwProcess();
}

void PrivacyWorker::stop() {
    if (m_debounceTimer) {
        m_debounceTimer->stop();
    }
    stopPwProcess();
    closeInotify();
}

void PrivacyWorker::setInterval(int intervalMs) {
    m_intervalMs = intervalMs;
}

void PrivacyWorker::sample() {
    const auto state = PrivacyProbe::probe(true);
    if (!m_initialized || state != m_lastState) {
        m_initialized = true;
        m_lastState = state;
        emit stateChanged(state);
    }
}

void PrivacyWorker::setupPwProcess() {
    stopPwProcess();

    m_pwBuffer.clear();
    m_bracketDepth = 0;
    m_inString = false;
    m_escape = false;

    m_pwProcess = new QProcess(this);
    connect(m_pwProcess, &QProcess::readyReadStandardOutput, this, &PrivacyWorker::onPwStdoutReady);
    connect(m_pwProcess, &QProcess::errorOccurred, this, &PrivacyWorker::onPwError);
    connect(m_pwProcess, &QProcess::finished, this, &PrivacyWorker::onPwFinished);

    m_pwProcess->start(QStringLiteral("stdbuf"), QStringList{
        QStringLiteral("-oL"),
        QStringLiteral("pw-dump"),
        QStringLiteral("-m"),
        QStringLiteral("-N")
    });
}

void PrivacyWorker::stopPwProcess() {
    if (m_restartTimer) {
        m_restartTimer->stop();
    }
    if (m_pwProcess) {
        m_pwProcess->disconnect(this);
        m_pwProcess->terminate();
        if (!m_pwProcess->waitForFinished(300)) {
            m_pwProcess->kill();
            m_pwProcess->waitForFinished(200);
        }
        delete m_pwProcess;
        m_pwProcess = nullptr;
    }
    m_nodes.clear();
    m_links.clear();
    m_pwBuffer.clear();
    m_bracketDepth = 0;
    m_inString = false;
    m_escape = false;
}

void PrivacyWorker::onPwStdoutReady() {
    if (!m_pwProcess) return;
    m_pwBuffer.append(m_pwProcess->readAllStandardOutput());
    processPwBuffer();
}

void PrivacyWorker::onPwError(QProcess::ProcessError error) {
    Q_UNUSED(error);
}

void PrivacyWorker::onPwFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    Q_UNUSED(exitCode);
    Q_UNUSED(exitStatus);
    m_nodes.clear();
    m_links.clear();
    m_pwBuffer.clear();
    m_bracketDepth = 0;
    m_inString = false;
    m_escape = false;

    if (!m_restartTimer) {
        m_restartTimer = new QTimer(this);
        m_restartTimer->setSingleShot(true);
        connect(m_restartTimer, &QTimer::timeout, this, &PrivacyWorker::setupPwProcess);
    }
    m_restartTimer->start(1000);
}

void PrivacyWorker::processPwBuffer() {
    int startIdx = -1;
    bool graphChanged = false;

    for (int i = 0; i < m_pwBuffer.size(); ++i) {
        char ch = m_pwBuffer.at(i);

        if (m_inString) {
            if (m_escape) {
                m_escape = false;
            } else if (ch == '\\') {
                m_escape = true;
            } else if (ch == '"') {
                m_inString = false;
            }
        } else {
            if (ch == '"') {
                m_inString = true;
            } else if (ch == '[') {
                if (m_bracketDepth == 0) {
                    startIdx = i;
                }
                m_bracketDepth++;
            } else if (ch == ']') {
                m_bracketDepth--;
                if (m_bracketDepth == 0 && startIdx != -1) {
                    const QByteArray chunk = m_pwBuffer.mid(startIdx, i - startIdx + 1);
                    if (handleJsonArray(chunk)) {
                        graphChanged = true;
                    }
                    startIdx = -1;
                    m_pwBuffer.remove(0, i + 1);
                    i = -1;
                }
            }
        }
    }

    if (graphChanged) {
        if (!m_debounceTimer) {
            m_debounceTimer = new QTimer(this);
            m_debounceTimer->setSingleShot(true);
            connect(m_debounceTimer, &QTimer::timeout, this, &PrivacyWorker::evaluatePrivacyState);
        }
        if (!m_debounceTimer->isActive()) {
            m_debounceTimer->start(40);
        }
    }
}

bool PrivacyWorker::handleJsonArray(const QByteArray &chunk) {
    QJsonParseError parseErr;
    const QJsonDocument doc = QJsonDocument::fromJson(chunk, &parseErr);
    if (!doc.isArray()) {
        return false;
    }

    const QJsonArray arr = doc.array();
    bool changed = false;

    for (const QJsonValue &val : arr) {
        if (!val.isObject()) continue;
        const QJsonObject obj = val.toObject();
        const int id = obj.value(QStringLiteral("id")).toInt();
        if (id <= 0) continue;

        const bool isRemoval = (obj.contains(QStringLiteral("info")) && obj.value(QStringLiteral("info")).isNull()) ||
                              (!obj.contains(QStringLiteral("type")) && !obj.contains(QStringLiteral("info")));

        if (isRemoval) {
            if (m_nodes.remove(id) > 0 || m_links.remove(id) > 0) {
                changed = true;
            }
            continue;
        }

        const QString type = obj.value(QStringLiteral("type")).toString();
        if (type == QLatin1String("PipeWire:Interface:Node")) {
            m_nodes.insert(id, obj);
            changed = true;
        } else if (type == QLatin1String("PipeWire:Interface:Link")) {
            m_links.insert(id, obj);
            changed = true;
        }
    }
    return changed;
}

void PrivacyWorker::evaluatePrivacyState() {
    PrivacyState state;

    // 1. Check all active PipeWire links
    for (auto it = m_links.constBegin(); it != m_links.constEnd(); ++it) {
        const QJsonObject link = it.value();
        const QJsonObject info = link.value(QStringLiteral("info")).toObject();
        const QJsonObject props = info.value(QStringLiteral("props")).toObject();
        const int outId = props.value(QStringLiteral("link.output.node")).toInt();
        const int inId = props.value(QStringLiteral("link.input.node")).toInt();

        const auto outIt = m_nodes.constFind(outId);
        const auto inIt = m_nodes.constFind(inId);
        if (outIt == m_nodes.constEnd() || inIt == m_nodes.constEnd()) {
            continue;
        }

        const QJsonObject outNode = *outIt;
        const QJsonObject inNode = *inIt;
        const QJsonObject outProps = outNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("props")).toObject();
        const QJsonObject inProps = inNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("props")).toObject();

        const QString outClass = outProps.value(QStringLiteral("media.class")).toString();
        const QString inClass = inProps.value(QStringLiteral("media.class")).toString();

        // Microphone recording stream
        if (outClass == QLatin1String("Audio/Source") && (inClass.startsWith(QLatin1String("Stream/Input")) || inClass == QLatin1String("Stream/Input/Audio"))) {
            state.micActive = true;

            QString appName = inProps.value(QStringLiteral("application.name")).toString();
            if (appName.isEmpty()) appName = inProps.value(QStringLiteral("node.name")).toString();
            if (appName.isEmpty()) appName = inNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("name")).toString();
            if (appName.isEmpty()) appName = QStringLiteral("Recording App");

            QString sourceDesc = outProps.value(QStringLiteral("node.description")).toString();
            if (sourceDesc.isEmpty()) sourceDesc = outProps.value(QStringLiteral("node.nick")).toString();
            if (sourceDesc.isEmpty()) sourceDesc = QStringLiteral("Microphone");

            if (!state.micApps.contains(appName)) state.micApps.append(appName);
            if (!state.micDevices.contains(sourceDesc)) state.micDevices.append(sourceDesc);
        }

        // Camera capture stream
        if (outClass == QLatin1String("Video/Source") || inClass.startsWith(QLatin1String("Stream/Input/Video"))) {
            state.cameraActive = true;

            QString appName = inProps.value(QStringLiteral("application.name")).toString();
            if (appName.isEmpty()) appName = inProps.value(QStringLiteral("node.name")).toString();
            if (appName.isEmpty()) appName = inNode.value(QStringLiteral("info")).toObject().value(QStringLiteral("name")).toString();
            if (appName.isEmpty()) appName = QStringLiteral("Camera App");

            QString camDesc = outProps.value(QStringLiteral("node.description")).toString();
            if (camDesc.isEmpty()) camDesc = outProps.value(QStringLiteral("node.nick")).toString();
            if (camDesc.isEmpty()) camDesc = QStringLiteral("Webcam");

            if (!state.cameraApps.contains(appName)) state.cameraApps.append(appName);
            if (!state.cameraDevices.contains(camDesc)) state.cameraDevices.append(camDesc);
        }
    }

    // 2. Check node running states
    for (auto it = m_nodes.constBegin(); it != m_nodes.constEnd(); ++it) {
        const QJsonObject node = it.value();
        const QJsonObject info = node.value(QStringLiteral("info")).toObject();
        const QString nodeState = info.value(QStringLiteral("state")).toString();
        const QJsonObject props = info.value(QStringLiteral("props")).toObject();
        const QString mediaClass = props.value(QStringLiteral("media.class")).toString();

        if (mediaClass == QLatin1String("Video/Source") && nodeState == QLatin1String("running")) {
            state.cameraActive = true;
            QString camDesc = props.value(QStringLiteral("node.description")).toString();
            if (camDesc.isEmpty()) camDesc = props.value(QStringLiteral("node.nick")).toString();
            if (camDesc.isEmpty()) camDesc = QStringLiteral("Webcam");
            if (!state.cameraDevices.contains(camDesc)) state.cameraDevices.append(camDesc);
        } else if (mediaClass == QLatin1String("Audio/Source") && nodeState == QLatin1String("running")) {
            state.micActive = true;
            QString micDesc = props.value(QStringLiteral("node.description")).toString();
            if (micDesc.isEmpty()) micDesc = props.value(QStringLiteral("node.nick")).toString();
            if (micDesc.isEmpty()) micDesc = QStringLiteral("Microphone");
            if (!state.micDevices.contains(micDesc)) state.micDevices.append(micDesc);
        }
    }

    // 3. Fallback checks for direct non-PipeWire access if not already active
    if (!state.cameraActive) {
        PrivacyProbe::checkV4L2Fast(state);
    }
    if (!state.micActive) {
        PrivacyProbe::checkAlsaCapture(state);
    }

    if (!m_initialized || state != m_lastState) {
        m_initialized = true;
        m_lastState = state;
        emit stateChanged(state);
    }
}

void PrivacyWorker::setupInotify() {
    if (m_inotifyFd >= 0) return;

    m_inotifyFd = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
    if (m_inotifyFd < 0) return;

    int wdDev = inotify_add_watch(m_inotifyFd, "/dev", IN_CREATE | IN_DELETE);
    if (wdDev >= 0) {
        m_inotifyWatches.insert(wdDev, QStringLiteral("/dev"));
    }

    QDir devDir(QStringLiteral("/dev"));
    const QStringList videoDevs = devDir.entryList(QStringList{QStringLiteral("video*")}, QDir::System);
    for (const QString &vdev : videoDevs) {
        const QString fullPath = QStringLiteral("/dev/") + vdev;
        int wd = inotify_add_watch(m_inotifyFd, fullPath.toUtf8().constData(), IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE);
        if (wd >= 0) {
            m_inotifyWatches.insert(wd, fullPath);
        }
    }

    m_inotifyNotifier = new QSocketNotifier(m_inotifyFd, QSocketNotifier::Read, this);
    connect(m_inotifyNotifier, &QSocketNotifier::activated, this, &PrivacyWorker::onInotifyActivated);
}

void PrivacyWorker::closeInotify() {
    if (m_inotifyNotifier) {
        m_inotifyNotifier->setEnabled(false);
        delete m_inotifyNotifier;
        m_inotifyNotifier = nullptr;
    }
    if (m_inotifyFd >= 0) {
        for (auto it = m_inotifyWatches.constBegin(); it != m_inotifyWatches.constEnd(); ++it) {
            inotify_rm_watch(m_inotifyFd, it.key());
        }
        m_inotifyWatches.clear();
        ::close(m_inotifyFd);
        m_inotifyFd = -1;
    }
}

void PrivacyWorker::onInotifyActivated() {
    if (m_inotifyFd < 0) return;

    char buffer[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
    bool needCheck = false;

    while (true) {
        const ssize_t len = ::read(m_inotifyFd, buffer, sizeof(buffer));
        if (len <= 0) break;

        const struct inotify_event *event = nullptr;
        for (char *ptr = buffer; ptr < buffer + len; ptr += sizeof(struct inotify_event) + event->len) {
            event = reinterpret_cast<const struct inotify_event *>(ptr);
            if (event->mask & (IN_CREATE | IN_DELETE)) {
                if (event->len > 0 && strncmp(event->name, "video", 5) == 0) {
                    const QString path = QStringLiteral("/dev/") + QString::fromUtf8(event->name);
                    if (event->mask & IN_CREATE) {
                        int wd = inotify_add_watch(m_inotifyFd, path.toUtf8().constData(), IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE);
                        if (wd >= 0) {
                            m_inotifyWatches.insert(wd, path);
                        }
                    }
                    needCheck = true;
                }
            } else if (event->mask & (IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE)) {
                needCheck = true;
            }
        }
    }

    if (needCheck) {
        if (!m_debounceTimer) {
            m_debounceTimer = new QTimer(this);
            m_debounceTimer->setSingleShot(true);
            connect(m_debounceTimer, &QTimer::timeout, this, &PrivacyWorker::evaluatePrivacyState);
        }
        if (!m_debounceTimer->isActive()) {
            m_debounceTimer->start(40);
        }
    }
}

PrivacyMonitor::PrivacyMonitor(QObject *parent)
    : QObject(parent)
{
    qRegisterMetaType<qs::plugins::PrivacyState>("qs::plugins::PrivacyState");
    m_cachedData = m_state.toMap();

    m_worker = new PrivacyWorker(m_interval);
    m_worker->moveToThread(&m_workerThread);

    connect(&m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &PrivacyMonitor::requestStart, m_worker, &PrivacyWorker::start);
    connect(this, &PrivacyMonitor::requestStop, m_worker, &PrivacyWorker::stop);
    connect(this, &PrivacyMonitor::requestSetInterval, m_worker, &PrivacyWorker::setInterval);
    connect(this, &PrivacyMonitor::requestSample, m_worker, &PrivacyWorker::sample);

    connect(m_worker, &PrivacyWorker::stateChanged, this, &PrivacyMonitor::onStateChanged);

    m_workerThread.start();
    if (m_running) {
        emit requestStart();
    }
}

PrivacyMonitor::~PrivacyMonitor() {
    emit requestStop();
    m_workerThread.quit();
    m_workerThread.wait();
}

void PrivacyMonitor::setRunning(bool running) {
    if (m_running == running) {
        return;
    }
    m_running = running;
    if (m_running) {
        emit requestStart();
    } else {
        emit requestStop();
    }
    emit runningChanged();
}

void PrivacyMonitor::setInterval(int interval) {
    if (m_interval == interval) {
        return;
    }
    m_interval = interval;
    emit requestSetInterval(interval);
    emit intervalChanged();
}

void PrivacyMonitor::refresh() {
    emit requestSample();
}

void PrivacyMonitor::onStateChanged(const PrivacyState &state) {
    m_state = state;
    m_cachedData = state.toMap();
    emit privacyChanged();
}

} // namespace qs::plugins
