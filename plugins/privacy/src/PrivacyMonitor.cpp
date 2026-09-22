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

    if (!m_pollTimer) {
        m_pollTimer = new QTimer(this);
        connect(m_pollTimer, &QTimer::timeout, this, [this]() {
            if (!m_pwProcess || m_pwProcess->state() == QProcess::NotRunning) {
                setupPwProcess();
            } else if (m_lastState.micActive || m_lastState.cameraActive) {
                // Periodically re-evaluate active state to ensure no stale flags
                evaluatePrivacyState();
            }
        });
    }
    m_pollTimer->start(m_intervalMs > 0 ? m_intervalMs : 800);
}

void PrivacyWorker::stop() {
    if (m_pollTimer) {
        m_pollTimer->stop();
    }
    if (m_debounceTimer) {
        m_debounceTimer->stop();
    }
    stopPwProcess();
    closeInotify();
}

void PrivacyWorker::setInterval(int intervalMs) {
    m_intervalMs = intervalMs;
    if (m_pollTimer && m_pollTimer->isActive()) {
        m_pollTimer->start(m_intervalMs > 0 ? m_intervalMs : 800);
    }
}

void PrivacyWorker::sample() {
    // Serve from the cached monitor graph: it holds the same data a one-shot
    // pw-dump would return, without fork + full-parse (~330 KB). Only fall
    // back to a synchronous probe when the monitor has no graph yet
    // (startup / daemon restart). evaluatePrivacyState() still runs the fast
    // /proc fallbacks itself when the graph shows nothing active.
    if (m_nodes.isEmpty() && m_links.isEmpty()) {
        const auto state = PrivacyProbe::probe(true);
        if (!m_initialized || state != m_lastState) {
            m_initialized = true;
            m_lastState = state;
            emit stateChanged(state);
        }
        return;
    }
    evaluatePrivacyState();
}

void PrivacyWorker::setupPwProcess() {
    stopPwProcess();

    m_pwBuffer.clear();
    m_scannedIdx = 0;
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
    m_scannedIdx = 0;
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
    if (!m_restartTimer) {
        m_restartTimer = new QTimer(this);
        m_restartTimer->setSingleShot(true);
        connect(m_restartTimer, &QTimer::timeout, this, &PrivacyWorker::setupPwProcess);
    }
    if (!m_restartTimer->isActive()) {
        m_restartTimer->start(1000);
    }
}

void PrivacyWorker::onPwFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    Q_UNUSED(exitCode);
    Q_UNUSED(exitStatus);
    m_nodes.clear();
    m_links.clear();
    m_pwBuffer.clear();
    m_scannedIdx = 0;
    m_bracketDepth = 0;
    m_inString = false;
    m_escape = false;

    evaluatePrivacyState();

    if (!m_restartTimer) {
        m_restartTimer = new QTimer(this);
        m_restartTimer->setSingleShot(true);
        connect(m_restartTimer, &QTimer::timeout, this, &PrivacyWorker::setupPwProcess);
    }
    m_restartTimer->start(1000);
}

void PrivacyWorker::processPwBuffer() {
    bool graphChanged = false;

    while (!m_pwBuffer.isEmpty()) {
        if (m_bracketDepth == 0) {
            int firstBracket = -1;
            for (int i = 0; i < m_pwBuffer.size(); ++i) {
                if (m_pwBuffer.at(i) == '[') {
                    firstBracket = i;
                    break;
                }
            }
            if (firstBracket < 0) {
                m_pwBuffer.clear();
                m_scannedIdx = 0;
                m_inString = false;
                m_escape = false;
                break;
            }
            if (firstBracket > 0) {
                m_pwBuffer.remove(0, firstBracket);
            }
            m_scannedIdx = 0;
            m_bracketDepth = 0;
            m_inString = false;
            m_escape = false;
        }

        int matchEnd = -1;
        for (int i = m_scannedIdx; i < m_pwBuffer.size(); ++i) {
            const char ch = m_pwBuffer.at(i);

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
                    m_bracketDepth++;
                } else if (ch == ']') {
                    m_bracketDepth--;
                    if (m_bracketDepth == 0) {
                        matchEnd = i;
                        break;
                    }
                }
            }
        }

        if (matchEnd >= 0) {
            const QByteArray chunk = m_pwBuffer.left(matchEnd + 1);
            // Fast pre-filter: only Node/Link add/updates and removals can
            // affect privacy state. Removals arrive as {"id": N, "info": null}
            // with no "type" field, so "null" must also pass through (as must
            // tiny chunks, defensively). Port/Client/Device/Module/Factory/
            // Metadata traffic skips the JSON parse entirely.
            const bool relevant = chunk.size() < 64
                                  || chunk.contains("PipeWire:Interface:Node")
                                  || chunk.contains("PipeWire:Interface:Link")
                                  || chunk.contains("null");
            if (relevant && handleJsonArray(chunk)) {
                graphChanged = true;
            }
            m_pwBuffer.remove(0, matchEnd + 1);
            m_scannedIdx = 0;
            m_bracketDepth = 0;
            m_inString = false;
            m_escape = false;
        } else {
            m_scannedIdx = m_pwBuffer.size();
            break;
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
                              (obj.contains(QStringLiteral("props")) && obj.value(QStringLiteral("props")).isNull()) ||
                              (!obj.contains(QStringLiteral("type")) && !obj.contains(QStringLiteral("info")));

        if (isRemoval) {
            if (m_nodes.remove(id) > 0) {
                changed = true;
                for (auto it = m_links.begin(); it != m_links.end();) {
                    const QJsonObject lInfo = it.value().value(QStringLiteral("info")).toObject();
                    const QJsonObject lProps = lInfo.value(QStringLiteral("props")).toObject();
                    int outId = lProps.value(QStringLiteral("link.output.node")).toInt();
                    if (outId <= 0) outId = lInfo.value(QStringLiteral("output-node-id")).toInt();
                    int inId = lProps.value(QStringLiteral("link.input.node")).toInt();
                    if (inId <= 0) inId = lInfo.value(QStringLiteral("input-node-id")).toInt();

                    if (outId == id || inId == id) {
                        it = m_links.erase(it);
                    } else {
                        ++it;
                    }
                }
            }
            if (m_links.remove(id) > 0) {
                changed = true;
            }
            continue;
        }

        const QString type = obj.value(QStringLiteral("type")).toString();
        if (type == QLatin1String("PipeWire:Interface:Node")) {
            // Drop the "params" blob (v4l2 controls, format lists, …): it is
            // ~80% of a Node's bytes and never read by evaluatePrivacyState.
            // Keeps the resident graph small and re-emits cheap.
            QJsonObject node = obj;
            QJsonObject info = node.value(QStringLiteral("info")).toObject();
            if (info.contains(QStringLiteral("params"))) {
                info.remove(QStringLiteral("params"));
                node[QStringLiteral("info")] = info;
            }
            m_nodes.insert(id, node);
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

    auto isCameraSource = [](const QJsonObject &props) -> bool {
        const QString deviceApi = props.value(QStringLiteral("device.api")).toString().toLower();
        if (deviceApi == QLatin1String("v4l2") || deviceApi == QLatin1String("libcamera")) {
            return true;
        }
        const QString factory = props.value(QStringLiteral("factory.name")).toString().toLower();
        if (factory.contains(QLatin1String("v4l2")) || factory.contains(QLatin1String("libcamera"))) {
            return true;
        }
        if (!props.value(QStringLiteral("api.v4l2.path")).toString().isEmpty()
            || !props.value(QStringLiteral("api.libcamera.path")).toString().isEmpty()) {
            return true;
        }
        const QString nodeName = props.value(QStringLiteral("node.name")).toString().toLower();
        if (nodeName.startsWith(QLatin1String("v4l2_input"))
            || nodeName.startsWith(QLatin1String("libcamera_input"))) {
            return true;
        }
        // Explicit camera role (real cameras set media.role=Camera).
        // KWin screencast / portal streams never set this.
        const QString mediaRole = props.value(QStringLiteral("media.role")).toString().toLower();
        if (mediaRole == QLatin1String("camera")) {
            return true;
        }
        return false;
    };

    auto isScreencastConsumer = [](const QJsonObject &props) -> bool {
        const QString app = props.value(QStringLiteral("application.name")).toString().toLower();
        const QString bin = props.value(QStringLiteral("application.process.binary")).toString().toLower();
        const QString node = props.value(QStringLiteral("node.name")).toString().toLower();
        static const QStringList owners = {
            QStringLiteral("plasmashell"),
            QStringLiteral("kwin_wayland"),
            QStringLiteral("kwin"),
            QStringLiteral("xdg-desktop-portal"),
            QStringLiteral("xdg-desktop-portal-kde"),
            QStringLiteral("xdg-desktop-portal-wlr"),
            QStringLiteral("xdg-desktop-portal-gtk"),
        };
        for (const auto &o : owners) {
            if (app == o || bin == o || app.contains(o) || bin.contains(o)) {
                return true;
            }
        }
        if (node.startsWith(QLatin1String("kwin-screencast"))
            || node.contains(QLatin1String("screencast"))) {
            return true;
        }
        return false;
    };

    // 1. Check all active PipeWire links
    for (auto it = m_links.constBegin(); it != m_links.constEnd(); ++it) {
        const QJsonObject link = it.value();
        const QJsonObject linkInfo = link.value(QStringLiteral("info")).toObject();
        const QString linkState = linkInfo.value(QStringLiteral("state")).toString();
        const QJsonObject linkProps = linkInfo.value(QStringLiteral("props")).toObject();

        int outId = linkProps.value(QStringLiteral("link.output.node")).toInt();
        if (outId <= 0) outId = linkInfo.value(QStringLiteral("output-node-id")).toInt();

        int inId = linkProps.value(QStringLiteral("link.input.node")).toInt();
        if (inId <= 0) inId = linkInfo.value(QStringLiteral("input-node-id")).toInt();

        const auto outIt = m_nodes.constFind(outId);
        const auto inIt = m_nodes.constFind(inId);
        if (outIt == m_nodes.constEnd() || inIt == m_nodes.constEnd()) {
            continue;
        }

        const QJsonObject outNode = *outIt;
        const QJsonObject inNode = *inIt;
        const QJsonObject outInfo = outNode.value(QStringLiteral("info")).toObject();
        const QJsonObject inInfo = inNode.value(QStringLiteral("info")).toObject();

        const QJsonObject outProps = outInfo.value(QStringLiteral("props")).toObject();
        const QJsonObject inProps = inInfo.value(QStringLiteral("props")).toObject();

        const QString outClass = outProps.value(QStringLiteral("media.class")).toString();
        const QString inClass = inProps.value(QStringLiteral("media.class")).toString();
        const QString inNodeState = inInfo.value(QStringLiteral("state")).toString();
        const QString outNodeState = outInfo.value(QStringLiteral("state")).toString();

        const bool linkIsActive = (linkState == QLatin1String("active"));
        const bool inIsRunning = (inNodeState == QLatin1String("running"));
        const bool outIsRunning = (outNodeState == QLatin1String("running"));

        // Microphone recording stream
        if (outClass == QLatin1String("Audio/Source") &&
            (inClass.startsWith(QLatin1String("Stream/Input/Audio")) || inClass == QLatin1String("Stream/Input"))) {

            // Exclude monitor sources (e.g. system playback capture)
            const bool isMonitor = (outProps.value(QStringLiteral("device.class")).toString() == QLatin1String("monitor")) ||
                                   outProps.value(QStringLiteral("node.name")).toString().endsWith(QLatin1String(".monitor")) ||
                                   inProps.value(QStringLiteral("stream.is-monitor")).toBool() ||
                                   inProps.value(QStringLiteral("node.name")).toString().endsWith(QLatin1String(".monitor"));

            if (!isMonitor) {
                const bool isActiveCapture = linkIsActive && (inIsRunning || inNodeState.isEmpty()) &&
                                             (inNodeState != QLatin1String("paused")) &&
                                             (inNodeState != QLatin1String("suspended"));

                if (isActiveCapture) {
                    QString appName = inProps.value(QStringLiteral("application.name")).toString();
                    if (appName.isEmpty()) appName = inProps.value(QStringLiteral("pipewire.access.portal.app_id")).toString();
                    if (appName.isEmpty()) appName = inProps.value(QStringLiteral("application.process.binary")).toString();
                    if (appName.isEmpty()) appName = inProps.value(QStringLiteral("node.name")).toString();
                    if (appName.isEmpty()) appName = inInfo.value(QStringLiteral("name")).toString();
                    if (appName.isEmpty()) appName = QStringLiteral("Recording App");

                    static const QStringList ignoredApps = {
                        QStringLiteral("pavucontrol"),
                        QStringLiteral("plasma-pa"),
                        QStringLiteral("systemsettings"),
                        QStringLiteral("gnome-control-center")
                    };

                    bool ignoreApp = false;
                    for (const auto &ign : ignoredApps) {
                        if (appName.compare(ign, Qt::CaseInsensitive) == 0) {
                            ignoreApp = true;
                            break;
                        }
                    }

                    if (!ignoreApp) {
                        state.micActive = true;

                        QString sourceDesc = outProps.value(QStringLiteral("node.description")).toString();
                        if (sourceDesc.isEmpty()) sourceDesc = outProps.value(QStringLiteral("node.nick")).toString();
                        if (sourceDesc.isEmpty()) sourceDesc = QStringLiteral("Microphone");

                        if (!state.micApps.contains(appName)) state.micApps.append(appName);
                        if (!state.micDevices.contains(sourceDesc)) state.micDevices.append(sourceDesc);
                    }
                }
            }
        }

        // Camera capture stream — only real v4l2/libcamera sources.
        // Plasma task-manager hover previews create transient KWin screencast
        // PipeWire streams (Stream/Input/Video consumed by plasmashell) which
        // must NOT be treated as camera use.
        if (outClass == QLatin1String("Video/Source")
            && (inClass.startsWith(QLatin1String("Stream/Input/Video"))
                || inClass == QLatin1String("Stream/Input"))) {
            if (!isCameraSource(outProps) || isScreencastConsumer(inProps)) {
                continue;
            }
            const bool isActiveVideo = (linkIsActive || inIsRunning || outIsRunning) &&
                                       (linkState != QLatin1String("paused")) &&
                                       (inNodeState != QLatin1String("paused"));

            if (isActiveVideo) {
                state.cameraActive = true;

                QString appName = inProps.value(QStringLiteral("application.name")).toString();
                if (appName.isEmpty()) appName = inProps.value(QStringLiteral("pipewire.access.portal.app_id")).toString();
                if (appName.isEmpty()) appName = inProps.value(QStringLiteral("application.process.binary")).toString();
                if (appName.isEmpty()) appName = inProps.value(QStringLiteral("node.name")).toString();
                if (appName.isEmpty()) appName = inInfo.value(QStringLiteral("name")).toString();
                if (appName.isEmpty()) appName = QStringLiteral("Camera App");

                QString camDesc = outProps.value(QStringLiteral("node.description")).toString();
                if (camDesc.isEmpty()) camDesc = outProps.value(QStringLiteral("node.nick")).toString();
                if (camDesc.isEmpty()) camDesc = QStringLiteral("Webcam");

                if (!state.cameraApps.contains(appName)) state.cameraApps.append(appName);
                if (!state.cameraDevices.contains(camDesc)) state.cameraDevices.append(camDesc);
            }
        }
    }

    // 2. Check direct Video/Source node running state (cameras only, not screencast)
    for (auto it = m_nodes.constBegin(); it != m_nodes.constEnd(); ++it) {
        const QJsonObject node = it.value();
        const QJsonObject info = node.value(QStringLiteral("info")).toObject();
        const QString nodeState = info.value(QStringLiteral("state")).toString();
        const QJsonObject props = info.value(QStringLiteral("props")).toObject();
        const QString mediaClass = props.value(QStringLiteral("media.class")).toString();

        if (mediaClass == QLatin1String("Video/Source") && nodeState == QLatin1String("running")
            && isCameraSource(props)) {
            state.cameraActive = true;
            QString camDesc = props.value(QStringLiteral("node.description")).toString();
            if (camDesc.isEmpty()) camDesc = props.value(QStringLiteral("node.nick")).toString();
            if (camDesc.isEmpty()) camDesc = QStringLiteral("Webcam");
            if (!state.cameraDevices.contains(camDesc)) state.cameraDevices.append(camDesc);
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
