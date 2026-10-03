#include "DockerMonitor.hpp"

#include <QFileInfo>

#include <cctype>

namespace qs::plugins {

DockerWorker::DockerWorker(std::shared_ptr<DockerSocketClient> client, QObject *parent)
    : QObject(parent)
    , m_client(std::move(client))
{
}

DockerWorker::~DockerWorker()
{
    stop();
}

void DockerWorker::start()
{
    if (!m_reconnectTimer) {
        m_reconnectTimer = new QTimer(this);
        m_reconnectTimer->setSingleShot(true);
        connect(m_reconnectTimer, &QTimer::timeout, this, &DockerWorker::reconnectEvents);
    }
    if (!m_debounceTimer) {
        m_debounceTimer = new QTimer(this);
        m_debounceTimer->setSingleShot(true);
        m_debounceTimer->setInterval(400);
        connect(m_debounceTimer, &QTimer::timeout, this, &DockerWorker::sample);
    }
    sample(); // initial full state at quickshell startup
    connectEvents(); // then stay current via the daemon's event stream
}

void DockerWorker::stop()
{
    if (m_debounceTimer) {
        m_debounceTimer->stop();
    }
    if (m_reconnectTimer) {
        m_reconnectTimer->stop();
    }
    closeEvents();
    // Unblock any request() parked in a socket read. Without this the worker
    // cannot return until SO_RCVTIMEO expires, which is longer than the
    // teardown wait in ~DockerMonitor.
    m_client->cancel();
}

void DockerWorker::connectEvents()
{
    closeEvents();

    const QString sockPath = m_client->socketPath();
    if (!QFileInfo::exists(sockPath)) {
        // Daemon down — retry; a successful (re)connect triggers a sample.
        if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
            m_reconnectTimer->start(3000);
        }
        return;
    }

    m_eventsSocket = new QLocalSocket(this);
    connect(m_eventsSocket, &QLocalSocket::connected, this, &DockerWorker::onEventsConnected);
    connect(m_eventsSocket, &QLocalSocket::readyRead, this, &DockerWorker::onEventsReadyRead);
    connect(m_eventsSocket, &QLocalSocket::errorOccurred, this, &DockerWorker::onEventsError);
    connect(m_eventsSocket, &QLocalSocket::disconnected, this, &DockerWorker::onEventsDisconnected);
    m_eventsSocket->connectToServer(sockPath);
}

void DockerWorker::closeEvents()
{
    if (m_eventsSocket) {
        m_eventsSocket->disconnect();
        m_eventsSocket->abort();
        delete m_eventsSocket;
        m_eventsSocket = nullptr;
    }
    m_eventsConnected = false;
    m_eventsHeadersParsed = false;
    m_eventsBuffer.clear();
}

void DockerWorker::reconnectEvents()
{
    connectEvents();
}

void DockerWorker::onEventsConnected()
{
    m_eventsConnected = true;
    m_eventsHeadersParsed = false;
    m_eventsBuffer.clear();

    if (m_reconnectTimer) {
        m_reconnectTimer->stop();
    }

    // Long-lived JSONL stream: one chunk per event, chunked encoding.
    const QByteArray req = "GET " + QByteArray(DockerSocketClient::kApiPrefix)
        + "/events HTTP/1.1\r\nHost: localhost\r\n\r\n";
    m_eventsSocket->write(req);
    m_eventsSocket->flush();
}

void DockerWorker::onEventsReadyRead()
{
    if (!m_eventsSocket) {
        return;
    }
    m_eventsBuffer.append(m_eventsSocket->readAll());

    if (!m_eventsHeadersParsed) {
        const int headerEnd = m_eventsBuffer.indexOf("\r\n\r\n");
        if (headerEnd == -1) {
            return;
        }
        const QByteArray headerBytes = m_eventsBuffer.left(headerEnd);
        const int firstLineEnd = headerBytes.indexOf("\r\n");
        const QByteArray statusLine = (firstLineEnd != -1) ? headerBytes.left(firstLineEnd) : headerBytes;
        if (!statusLine.contains("200")) {
            // e.g. daemon restarting mid-handshake — reconnect; it re-samples.
            closeEvents();
            if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
                m_reconnectTimer->start(3000);
            }
            return;
        }
        m_eventsBuffer.remove(0, headerEnd + 4);
        m_eventsHeadersParsed = true;
        sample(); // (re)connected — catch up on anything missed while away
    }

    // Chunked framing: "<hex size>\r\n<payload>\r\n", payload is one JSON event.
    while (m_eventsHeadersParsed) {
        const int lineEnd = m_eventsBuffer.indexOf("\r\n");
        if (lineEnd == -1) {
            break;
        }
        QByteArray line = m_eventsBuffer.left(lineEnd).trimmed();
        if (line.isEmpty()) {
            m_eventsBuffer.remove(0, lineEnd + 2);
            continue;
        }
        const int semi = line.indexOf(';'); // chunk extensions
        if (semi != -1) {
            line = line.left(semi).trimmed();
        }
        if (line.isEmpty()) {
            m_eventsBuffer.remove(0, lineEnd + 2);
            continue;
        }
        bool hexOk = true;
        for (const char c : line) {
            if (!std::isxdigit(static_cast<unsigned char>(c))) {
                hexOk = false;
                break;
            }
        }
        bool ok = false;
        const qint64 chunkSize = line.toLongLong(&ok, 16);
        if (!hexOk || !ok || chunkSize < 0) {
            // Poisoned framing: drop the partial prefix so the next stream
            // starts from a clean buffer instead of re-parsing garbage.
            closeEvents();
            if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
                m_reconnectTimer->start(3000);
            }
            return;
        }
        if (chunkSize == 0) {
            // Daemon closed the stream — reconnect; it re-samples.
            closeEvents();
            if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
                m_reconnectTimer->start(1000);
            }
            return;
        }
        const qint64 headerLen = lineEnd + 2;
        if (m_eventsBuffer.size() < headerLen + chunkSize + 2) {
            break; // partial chunk — wait for more data
        }
        if (m_eventsBuffer.mid(static_cast<int>(headerLen + chunkSize), 2) != "\r\n") {
            // Body not terminated by CRLF — the framing is desynchronised, so
            // no payload in this buffer can be trusted.
            closeEvents();
            if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
                m_reconnectTimer->start(3000);
            }
            return;
        }
        m_eventsBuffer.remove(0, static_cast<int>(headerLen + chunkSize + 2));
        triggerSampleDebounced(); // coalesce bursts (e.g. project start/stop)
    }
}

void DockerWorker::triggerSampleDebounced()
{
    if (!m_initialized) {
        sample();
        return;
    }
    if (m_debounceTimer && !m_debounceTimer->isActive()) {
        m_debounceTimer->start();
    }
}

void DockerWorker::onEventsError(QLocalSocket::LocalSocketError)
{
    const bool wasConnected = m_eventsConnected;
    closeEvents();
    if (wasConnected) {
        sample(); // connection lost — refresh once, reconnect keeps us live
    }
    if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
        m_reconnectTimer->start(3000);
    }
}

void DockerWorker::onEventsDisconnected()
{
    const bool wasConnected = m_eventsConnected;
    closeEvents();
    if (wasConnected) {
        sample();
    }
    if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
        m_reconnectTimer->start(3000);
    }
}

void DockerWorker::sample()
{
    if (m_isSampling) {
        return;
    }
    m_isSampling = true;

    DockerState state;
    m_client->fetchFullState(state);

    // A cancelled fetch leaves `state` reset, so publishing it would wipe the
    // UI to empty just because teardown interrupted the sample.
    if (!m_client->cancelled() && (!m_initialized || state != m_lastState)) {
        m_initialized = true;
        m_lastState = state;
        emit stateChanged(state);
    }

    m_isSampling = false;
}

void DockerWorker::setBusy(bool busy, const QString &context, const QString &label)
{
    m_busyContext = context;
    m_busyLabel = label;
    emit busyChanged(busy, context, label);
}

QString DockerWorker::containerName(const QString &id) const
{
    for (const auto &c : m_lastState.containers) {
        if (c.id == id || (!id.isEmpty() && c.id.startsWith(id)) || (!c.id.isEmpty() && id.startsWith(c.id))) {
            return c.name.isEmpty() ? c.shortId : c.name;
        }
    }
    return id.left(12);
}

void DockerWorker::refresh()
{
    // Explicit user refresh (button): same sample, but with a busy pulse so
    // the UI can spin. Internal/event samples stay silent.
    setBusy(true, QStringLiteral("refresh"), QStringLiteral("Refreshing…"));
    sample();
    setBusy(false);
}

void DockerWorker::runContainerAction(const QString &action, const QString &id, int timeoutSec)
{
    QString verb = QStringLiteral("Working on");
    if (action == QStringLiteral("start")) {
        verb = QStringLiteral("Starting");
    } else if (action == QStringLiteral("stop")) {
        verb = QStringLiteral("Stopping");
    } else if (action == QStringLiteral("restart")) {
        verb = QStringLiteral("Restarting");
    } else if (action == QStringLiteral("kill")) {
        verb = QStringLiteral("Stopping");
    }
    setBusy(true, action + QStringLiteral(":") + id, verb + QStringLiteral(" ") + containerName(id) + QStringLiteral("…"));
    ActionResult res{false, 0, QString(), QStringLiteral("Unknown action")};

    if (action == QStringLiteral("start")) {
        res = m_client->startContainer(id);
    } else if (action == QStringLiteral("stop")) {
        res = m_client->stopContainer(id, timeoutSec);
    } else if (action == QStringLiteral("restart")) {
        res = m_client->restartContainer(id, timeoutSec);
    } else if (action == QStringLiteral("kill")) {
        res = m_client->killContainer(id);
    } else {
        res.error = QStringLiteral("Unknown container action: ") + action;
    }

    sample();
    emit actionFinished(res.ok, res.output, res.error, action + QStringLiteral(":") + id);
    setBusy(false);
}

void DockerWorker::runRemove(const QString &kind, const QString &target, bool force)
{
    QString display = target;
    if (kind == QStringLiteral("container")) {
        display = containerName(target);
    } else if (target.startsWith(QStringLiteral("sha256:"))) {
        display = target.sliced(7, 12);
    }
    setBusy(true, QStringLiteral("remove-") + kind + QStringLiteral(":") + target,
            QStringLiteral("Removing ") + display + QStringLiteral("…"));
    ActionResult res{false, 0, QString(), QString()};

    if (kind == QStringLiteral("container")) {
        res = m_client->removeContainer(target, force, false);
    } else if (kind == QStringLiteral("image")) {
        res = m_client->removeImage(target, force);
    } else if (kind == QStringLiteral("volume")) {
        res = m_client->removeVolume(target, force);
    } else {
        res.error = QStringLiteral("Unknown remove kind: ") + kind;
    }

    sample();
    emit actionFinished(res.ok, res.output, res.error, QStringLiteral("remove-") + kind + QStringLiteral(":") + target);
    setBusy(false);
}

void DockerWorker::runPrune(const QString &kind)
{
    setBusy(true, QStringLiteral("prune:") + kind, QStringLiteral("Pruning ") + kind + QStringLiteral("…"));
    const ActionResult res = m_client->prune(kind);
    sample();
    emit actionFinished(res.ok, res.output, res.error, QStringLiteral("prune:") + kind);
    setBusy(false);
}

void DockerWorker::runFetchLogs(const QString &id, int tail)
{
    setBusy(true, QStringLiteral("logs:") + id, QStringLiteral("Fetching logs…"));
    const LogsResult res = m_client->fetchLogs(id, tail);
    emit logsReady(id, res.ok, res.logs, res.error);
    setBusy(false);
}

void DockerWorker::runProjectAction(const QString &action, const QString &project, int timeoutSec)
{
    setBusy(true, action + QStringLiteral("-project:") + project,
            (action == QStringLiteral("start") ? QStringLiteral("Starting project ") : QStringLiteral("Stopping project ")) + project
                + QStringLiteral("…"));

    // Enumerate project containers from last known state (refresh first if empty)
    if (m_lastState.containers.isEmpty()) {
        DockerState fresh;
        m_client->fetchFullState(fresh);
        m_lastState = fresh;
    }

    int okCount = 0;
    int failCount = 0;
    QStringList errors;
    for (const auto &c : m_lastState.containers) {
        if (c.project != project) {
            continue;
        }
        ActionResult r{false, 0, QString(), QString()};
        if (action == QStringLiteral("start")) {
            r = m_client->startContainer(c.id);
        } else if (action == QStringLiteral("stop")) {
            r = m_client->stopContainer(c.id, timeoutSec);
        } else {
            r.error = QStringLiteral("Unknown project action");
        }
        if (r.ok) {
            okCount++;
        } else {
            failCount++;
            errors.append(c.name + QStringLiteral(": ") + r.error);
        }
    }

    sample();
    const bool ok = (failCount == 0);
    const QString summary = QStringLiteral("%1 %2: %3 ok, %4 failed").arg(action, project).arg(okCount).arg(failCount);
    emit actionFinished(ok, summary, errors.join('\n'), action + QStringLiteral("-project:") + project);
    setBusy(false);
}

DockerMonitor::DockerMonitor(QObject *parent)
    : QObject(parent)
{
    // Shared with the worker so teardown can interrupt an in-flight read:
    // stop() is a queued call and cannot run while the worker thread is blocked
    // reading. Sharing is also the only reason cancellation works at all.
    // TailscaleMonitor has the same shape but keeps its fd private, so its
    // destructor can still destroy a QThread that is still running.
    m_client = std::make_shared<DockerSocketClient>();
    m_worker = new DockerWorker(m_client);
    m_worker->moveToThread(&m_thread);

    // Only auto-start when the monitor is meant to run (e.g. the popup's
    // fallback monitor is constructed with running=false and must stay idle).
    connect(&m_thread, &QThread::started, this, [this]() {
        if (m_running) {
            QMetaObject::invokeMethod(m_worker, &DockerWorker::start, Qt::QueuedConnection);
        }
    });
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);

    connect(m_worker, &DockerWorker::stateChanged, this, &DockerMonitor::onStateChanged, Qt::QueuedConnection);
    connect(m_worker, &DockerWorker::actionFinished, this, &DockerMonitor::onActionFinished, Qt::QueuedConnection);
    connect(m_worker, &DockerWorker::logsReady, this, &DockerMonitor::onLogsReady, Qt::QueuedConnection);
    connect(m_worker, &DockerWorker::busyChanged, this, &DockerMonitor::onWorkerBusy, Qt::QueuedConnection);

    connect(this, &DockerMonitor::requestSample, m_worker, &DockerWorker::refresh, Qt::QueuedConnection);
    connect(this, &DockerMonitor::requestContainerAction, m_worker, &DockerWorker::runContainerAction, Qt::QueuedConnection);
    connect(this, &DockerMonitor::requestRemove, m_worker, &DockerWorker::runRemove, Qt::QueuedConnection);
    connect(this, &DockerMonitor::requestPrune, m_worker, &DockerWorker::runPrune, Qt::QueuedConnection);
    connect(this, &DockerMonitor::requestFetchLogs, m_worker, &DockerWorker::runFetchLogs, Qt::QueuedConnection);
    connect(this, &DockerMonitor::requestProjectAction, m_worker, &DockerWorker::runProjectAction, Qt::QueuedConnection);

    m_thread.start(QThread::LowPriority);
}

DockerMonitor::~DockerMonitor()
{
    // Interrupt first: quit() only sets the event loop's exit flag, so a worker
    // parked in a blocking socket read would otherwise keep running past the
    // wait below and get its QThread destroyed underneath it.
    if (m_client) {
        m_client->cancel();
    }
    m_thread.quit();
    if (!m_thread.wait(3000)) {
        qWarning("DockerMonitor: worker thread did not stop within 3s; forcing");
        m_thread.terminate();
        m_thread.wait();
    }
}

void DockerMonitor::setRunning(bool run)
{
    if (m_running != run) {
        m_running = run;
        if (m_running) {
            QMetaObject::invokeMethod(m_worker, &DockerWorker::start, Qt::QueuedConnection);
        } else {
            QMetaObject::invokeMethod(m_worker, &DockerWorker::stop, Qt::QueuedConnection);
        }
        emit runningChanged();
    }
}

QVariantList DockerMonitor::containers() const
{
    QVariantList l;
    l.reserve(m_state.containers.size());
    for (const auto &c : m_state.containers) {
        l.append(c.toMap());
    }
    return l;
}

QVariantList DockerMonitor::projects() const
{
    QVariantList l;
    l.reserve(m_state.projects.size());
    for (const auto &p : m_state.projects) {
        l.append(p.toMap());
    }
    return l;
}

QVariantList DockerMonitor::standalone() const
{
    QVariantList l;
    l.reserve(m_state.standalone.size());
    for (const auto &c : m_state.standalone) {
        l.append(c.toMap());
    }
    return l;
}

QVariantList DockerMonitor::images() const
{
    QVariantList l;
    l.reserve(m_state.images.size());
    for (const auto &i : m_state.images) {
        l.append(i.toMap());
    }
    return l;
}

QVariantList DockerMonitor::volumes() const
{
    QVariantList l;
    l.reserve(m_state.volumes.size());
    for (const auto &v : m_state.volumes) {
        l.append(v.toMap());
    }
    return l;
}

void DockerMonitor::refresh()
{
    emit requestSample();
}

void DockerMonitor::startContainer(const QString &id)
{
    emit requestContainerAction(QStringLiteral("start"), id, 10);
}

void DockerMonitor::stopContainer(const QString &id, int timeoutSec)
{
    emit requestContainerAction(QStringLiteral("stop"), id, timeoutSec);
}

void DockerMonitor::restartContainer(const QString &id, int timeoutSec)
{
    emit requestContainerAction(QStringLiteral("restart"), id, timeoutSec);
}

void DockerMonitor::killContainer(const QString &id)
{
    emit requestContainerAction(QStringLiteral("kill"), id, 0);
}

void DockerMonitor::removeContainer(const QString &id, bool force)
{
    emit requestRemove(QStringLiteral("container"), id, force);
}

void DockerMonitor::removeImage(const QString &name, bool force)
{
    emit requestRemove(QStringLiteral("image"), name, force);
}

void DockerMonitor::removeVolume(const QString &name, bool force)
{
    emit requestRemove(QStringLiteral("volume"), name, force);
}

void DockerMonitor::prune(const QString &kind)
{
    emit requestPrune(kind);
}

void DockerMonitor::fetchLogs(const QString &id, int tail)
{
    m_logId = id;
    emit requestFetchLogs(id, tail);
}

void DockerMonitor::startProject(const QString &project)
{
    emit requestProjectAction(QStringLiteral("start"), project, 10);
}

void DockerMonitor::stopProject(const QString &project, int timeoutSec)
{
    emit requestProjectAction(QStringLiteral("stop"), project, timeoutSec);
}

void DockerMonitor::openPath(const QString &path)
{
    DockerSocketClient::openPath(path);
}

void DockerMonitor::onStateChanged(const qs::plugins::DockerState &state)
{
    m_state = state;
    m_cachedMap = state.toMap();
    emit stateChanged();
}

void DockerMonitor::onActionFinished(bool ok, const QString &output, const QString &error, const QString &context)
{
    emit actionCompleted(ok, output, error, context);
}

void DockerMonitor::onLogsReady(const QString &id, bool ok, const QString &logs, const QString &error)
{
    m_logId = id;
    m_logText = ok ? logs : QString();
    m_logError = ok ? QString() : error;
    emit logsReady();
}

void DockerMonitor::onWorkerBusy(bool busy, const QString &context, const QString &label)
{
    // The worker/thread outlive the popup: the monitor is owned by the bar
    // widget, so closing the popup mid-operation never cancels anything.
    // Results land here regardless and are picked up when it reopens.
    m_isBusy = busy;
    m_busyContext = context;
    m_busyLabel = label;
    emit busyChanged();
}

} // namespace qs::plugins
