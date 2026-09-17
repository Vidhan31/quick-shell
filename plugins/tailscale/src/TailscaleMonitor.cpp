#include "TailscaleMonitor.hpp"

#include <QJsonDocument>
#include <QJsonObject>

namespace qs::plugins {

// ============================================================================
// TailscaleWorker
// ============================================================================

TailscaleWorker::TailscaleWorker(int intervalMs, QObject *parent)
    : QObject(parent)
    , m_intervalMs(intervalMs)
{
}

TailscaleWorker::~TailscaleWorker()
{
    stop();
}

void TailscaleWorker::start()
{
    if (!m_timer) {
        m_timer = new QTimer(this);
        m_timer->setInterval(m_intervalMs);
        connect(m_timer, &QTimer::timeout, this, &TailscaleWorker::sample);
        m_timer->start();
    }

    if (!m_reconnectTimer) {
        m_reconnectTimer = new QTimer(this);
        m_reconnectTimer->setSingleShot(true);
        connect(m_reconnectTimer, &QTimer::timeout, this, &TailscaleWorker::reconnectWatchBus);
    }

    connectWatchBus();
    sample();
}

void TailscaleWorker::stop()
{
    if (m_timer) {
        m_timer->stop();
    }
    if (m_reconnectTimer) {
        m_reconnectTimer->stop();
    }
    if (m_watchSocket) {
        m_watchSocket->disconnect();
        m_watchSocket->abort();
        delete m_watchSocket;
        m_watchSocket = nullptr;
    }
}

void TailscaleWorker::setInterval(int intervalMs)
{
    m_intervalMs = intervalMs;
    if (m_timer) {
        m_timer->setInterval(intervalMs);
    }
}

void TailscaleWorker::connectWatchBus()
{
    if (m_watchSocket) {
        m_watchSocket->abort();
        delete m_watchSocket;
        m_watchSocket = nullptr;
    }

    m_watchBuffer.clear();
    m_watchConnected = false;

    m_watchSocket = new QLocalSocket(this);
    connect(m_watchSocket, &QLocalSocket::connected, this, &TailscaleWorker::onWatchSocketConnected);
    connect(m_watchSocket, &QLocalSocket::readyRead, this, &TailscaleWorker::onWatchSocketReadyRead);
    connect(m_watchSocket, &QLocalSocket::errorOccurred, this, &TailscaleWorker::onWatchSocketError);
    connect(m_watchSocket, &QLocalSocket::disconnected, this, &TailscaleWorker::onWatchSocketDisconnected);

    m_watchSocket->connectToServer(m_client.socketPath());
}

void TailscaleWorker::reconnectWatchBus()
{
    connectWatchBus();
}

void TailscaleWorker::onWatchSocketConnected()
{
    m_watchConnected = true;
    // Subscribe to IPN bus with mask 16390 (NotifyInitialState | NotifyInitialPrefs | NotifyInitialStatus)
    const QByteArray req = "GET /localapi/v0/watch-ipn-bus?mask=16390 HTTP/1.1\r\nHost: local-tailscaled.sock\r\n\r\n";
    m_watchSocket->write(req);
    m_watchSocket->flush();
}

void TailscaleWorker::onWatchSocketReadyRead()
{
    if (!m_watchSocket) {
        return;
    }

    m_watchBuffer.append(m_watchSocket->readAll());

    // Skip HTTP headers if not yet processed
    int headerEnd = m_watchBuffer.indexOf("\r\n\r\n");
    if (headerEnd != -1) {
        // Look for newline-separated JSON objects in the stream
        int newlineIdx;
        while ((newlineIdx = m_watchBuffer.indexOf('\n', headerEnd + 4)) != -1) {
            const QByteArray line = m_watchBuffer.mid(headerEnd + 4, newlineIdx - (headerEnd + 4)).trimmed();
            m_watchBuffer.remove(0, newlineIdx + 1);
            headerEnd = -4; // already past headers

            if (line.isEmpty()) {
                continue;
            }

            // If chunked length marker, skip
            bool isHex = false;
            line.toInt(&isHex, 16);
            if (isHex && line.size() <= 8) {
                continue;
            }

            // When a notification arrives, refresh the state
            QJsonParseError err{};
            const QJsonDocument doc = QJsonDocument::fromJson(line, &err);
            if (err.error == QJsonParseError::NoError && doc.isObject()) {
                sample();
            }
        }
    }
}

void TailscaleWorker::onWatchSocketError(QLocalSocket::LocalSocketError)
{
    m_watchConnected = false;
    if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
        m_reconnectTimer->start(4000);
    }
}

void TailscaleWorker::onWatchSocketDisconnected()
{
    m_watchConnected = false;
    if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
        m_reconnectTimer->start(4000);
    }
}

void TailscaleWorker::sample()
{
    if (m_isSampling) {
        return;
    }
    m_isSampling = true;

    TailscaleState state;
    m_client.fetchFullStatus(state);
    emit stateChanged(state);

    m_isSampling = false;
}

void TailscaleWorker::runAction(const QVariantList &args, const QString &successMsg)
{
    emit busyChanged(true);

    if (args.isEmpty()) {
        sample();
        emit actionFinished(true, QString(), QString(), successMsg);
        emit busyChanged(false);
        return;
    }

    const QString cmd = args.value(0).toString();
    bool ok = false;
    QString output;
    QString error;

    if (cmd == QStringLiteral("status")) {
        sample();
        ok = true;
    } else if (cmd == QStringLiteral("ssh-toggle")) {
        const QString enableStr = args.size() > 1 ? args.value(1).toString() : QStringLiteral("true");
        const bool enable = (enableStr.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0 ||
                             enableStr == QStringLiteral("1") ||
                             enableStr.compare(QStringLiteral("on"), Qt::CaseInsensitive) == 0);
        ok = m_client.setSSH(enable, &error);
    } else if (cmd == QStringLiteral("up-down")) {
        const QString act = args.size() > 1 ? args.value(1).toString() : QStringLiteral("up");
        const bool up = (act.compare(QStringLiteral("down"), Qt::CaseInsensitive) != 0);
        ok = m_client.setWantRunning(up, &error);
    } else if (cmd == QStringLiteral("set-pref")) {
        const QString pref = args.size() > 1 ? args.value(1).toString() : QString();
        const QString val = args.size() > 2 ? args.value(2).toString() : QString();
        const bool bVal = (val.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0 || val == QStringLiteral("1"));

        if (pref == QStringLiteral("shields-up")) {
            ok = m_client.setShieldsUp(bVal, &error);
        } else if (pref == QStringLiteral("webclient")) {
            ok = m_client.setWebClient(bVal, &error);
        } else if (pref == QStringLiteral("advertise-exit-node")) {
            ok = m_client.setAdvertiseExitNode(bVal, &error);
        } else {
            ok = m_client.setPref(pref, val, &error);
        }
    } else if (cmd == QStringLiteral("serve-start")) {
        const QString target = args.value(1).toString();
        const QString mode = args.size() > 2 ? args.value(2).toString() : QStringLiteral("serve");
        const QString port = args.size() > 3 ? args.value(3).toString() : QStringLiteral("443");
        const QString path = args.size() > 4 ? args.value(4).toString() : QStringLiteral("/");
        const ActionResult res = m_client.serveStart(target, mode, port, path);
        ok = res.ok;
        output = res.output;
        error = res.error;
    } else if (cmd == QStringLiteral("serve-stop")) {
        const QString port = args.size() > 1 ? args.value(1).toString() : QStringLiteral("443");
        const QString path = args.size() > 2 ? args.value(2).toString() : QString();
        const ActionResult res = m_client.serveStop(port, path);
        ok = res.ok;
        output = res.output;
        error = res.error;
    } else if (cmd == QStringLiteral("funnel-toggle")) {
        const QString port = args.size() > 1 ? args.value(1).toString() : QStringLiteral("443");
        const QString target = args.size() > 2 ? args.value(2).toString() : QString();
        const QString funnelStr = args.size() > 3 ? args.value(3).toString() : QStringLiteral("true");
        const bool isFunnel = (funnelStr.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0 || funnelStr == QStringLiteral("1"));
        const QString path = args.size() > 4 ? args.value(4).toString() : QStringLiteral("/");
        const ActionResult res = m_client.funnelToggle(port, target, isFunnel, path);
        ok = res.ok;
        output = res.output;
        error = res.error;
    } else if (cmd == QStringLiteral("serve-reset")) {
        const ActionResult res = m_client.serveReset();
        ok = res.ok;
        output = res.output;
        error = res.error;
    } else if (cmd == QStringLiteral("copy")) {
        QStringList textParts;
        for (int i = 1; i < args.size(); ++i) {
            textParts.append(args.value(i).toString());
        }
        ok = TailscaleSocketClient::copyToClipboard(textParts.join(' '));
    } else if (cmd == QStringLiteral("open-url")) {
        const QString url = args.value(1).toString();
        ok = TailscaleSocketClient::openUrl(url);
    } else {
        error = QStringLiteral("Unknown action: ") + cmd;
    }

    sample();

    emit actionFinished(ok, output, error, successMsg);
    emit busyChanged(false);
}

void TailscaleWorker::runPing(const QString &ip)
{
    const PingResult res = m_client.ping(ip);
    emit pingFinished(res.ok, res.targetIp, res.latency, res.output, res.error);
}

void TailscaleWorker::runNetcheck()
{
    const ActionResult res = m_client.runNetcheck();
    emit netcheckFinished(res.ok, res.output, res.error);
}

// ============================================================================
// TailscaleMonitor
// ============================================================================

TailscaleMonitor::TailscaleMonitor(QObject *parent)
    : QObject(parent)
{
    m_worker = new TailscaleWorker(m_interval);
    m_worker->moveToThread(&m_thread);

    connect(&m_thread, &QThread::started, m_worker, &TailscaleWorker::start);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);

    // Cross-thread signal connections
    connect(m_worker, &TailscaleWorker::stateChanged, this, &TailscaleMonitor::onStateChanged, Qt::QueuedConnection);
    connect(m_worker, &TailscaleWorker::actionFinished, this, &TailscaleMonitor::onActionFinished, Qt::QueuedConnection);
    connect(m_worker, &TailscaleWorker::pingFinished, this, &TailscaleMonitor::onPingFinished, Qt::QueuedConnection);
    connect(m_worker, &TailscaleWorker::netcheckFinished, this, &TailscaleMonitor::onNetcheckFinished, Qt::QueuedConnection);
    connect(m_worker, &TailscaleWorker::busyChanged, this, [this](bool busy) {
        if (m_isBusy != busy) {
            m_isBusy = busy;
            emit busyChanged();
        }
    }, Qt::QueuedConnection);

    // Monitor to Worker requests
    connect(this, &TailscaleMonitor::requestSample, m_worker, &TailscaleWorker::sample, Qt::QueuedConnection);
    connect(this, &TailscaleMonitor::requestAction, m_worker, &TailscaleWorker::runAction, Qt::QueuedConnection);
    connect(this, &TailscaleMonitor::requestPing, m_worker, &TailscaleWorker::runPing, Qt::QueuedConnection);
    connect(this, &TailscaleMonitor::requestNetcheck, m_worker, &TailscaleWorker::runNetcheck, Qt::QueuedConnection);

    m_thread.start(QThread::LowPriority);
}

TailscaleMonitor::~TailscaleMonitor()
{
    m_thread.quit();
    m_thread.wait(3000);
}

void TailscaleMonitor::setRunning(bool run)
{
    if (m_running != run) {
        m_running = run;
        if (m_running) {
            QMetaObject::invokeMethod(m_worker, "start", Qt::QueuedConnection);
        } else {
            QMetaObject::invokeMethod(m_worker, "stop", Qt::QueuedConnection);
        }
        emit runningChanged();
    }
}

void TailscaleMonitor::setInterval(int ms)
{
    if (m_interval != ms && ms >= 500) {
        m_interval = ms;
        QMetaObject::invokeMethod(m_worker, "setInterval", Qt::QueuedConnection, Q_ARG(int, ms));
        emit intervalChanged();
    }
}

bool TailscaleMonitor::hasFunnel() const noexcept
{
    for (const auto &item : m_state.serveItems) {
        if (item.isFunnel) {
            return true;
        }
    }
    return false;
}

QVariantList TailscaleMonitor::serveItems() const
{
    QVariantList list;
    list.reserve(m_state.serveItems.size());
    for (const auto &item : m_state.serveItems) {
        list.append(item.toMap());
    }
    return list;
}

QVariantList TailscaleMonitor::peers() const
{
    QVariantList list;
    list.reserve(m_state.peers.size());
    for (const auto &peer : m_state.peers) {
        list.append(peer.toMap());
    }
    return list;
}

void TailscaleMonitor::refresh()
{
    emit requestSample();
}

void TailscaleMonitor::runAction(const QVariantList &args, const QString &successMsg)
{
    emit requestAction(args, successMsg);
}

void TailscaleMonitor::ping(const QString &ip)
{
    m_pingTargetIp = ip;
    m_pingResult.clear();
    emit requestPing(ip);
}

void TailscaleMonitor::netcheck()
{
    m_isRunningNetcheck = true;
    emit netcheckStatusChanged();
    emit requestNetcheck();
}

void TailscaleMonitor::setUp(bool up)
{
    runAction({QStringLiteral("up-down"), up ? QStringLiteral("up") : QStringLiteral("down")});
}

void TailscaleMonitor::setSSH(bool enable)
{
    runAction({QStringLiteral("ssh-toggle"), enable ? QStringLiteral("true") : QStringLiteral("false")});
}

void TailscaleMonitor::setShieldsUp(bool enable)
{
    runAction({QStringLiteral("set-pref"), QStringLiteral("shields-up"), enable ? QStringLiteral("true") : QStringLiteral("false")});
}

void TailscaleMonitor::setWebClient(bool enable)
{
    runAction({QStringLiteral("set-pref"), QStringLiteral("webclient"), enable ? QStringLiteral("true") : QStringLiteral("false")});
}

void TailscaleMonitor::setAdvertiseExitNode(bool enable)
{
    runAction({QStringLiteral("set-pref"), QStringLiteral("advertise-exit-node"), enable ? QStringLiteral("true") : QStringLiteral("false")});
}

void TailscaleMonitor::serveStart(const QString &target, const QString &mode, const QString &port, const QString &path)
{
    runAction({QStringLiteral("serve-start"), target, mode, port, path});
}

void TailscaleMonitor::serveStop(const QString &port, const QString &path)
{
    runAction({QStringLiteral("serve-stop"), port, path});
}

void TailscaleMonitor::funnelToggle(const QString &port, const QString &target, bool isFunnel, const QString &path)
{
    runAction({QStringLiteral("funnel-toggle"), port, target, isFunnel ? QStringLiteral("true") : QStringLiteral("false"), path});
}

void TailscaleMonitor::serveReset()
{
    runAction({QStringLiteral("serve-reset")});
}

void TailscaleMonitor::copy(const QString &text)
{
    runAction({QStringLiteral("copy"), text});
}

void TailscaleMonitor::openUrl(const QString &url)
{
    runAction({QStringLiteral("open-url"), url});
}

void TailscaleMonitor::onStateChanged(const qs::plugins::TailscaleState &state)
{
    m_state = state;
    m_cachedMap = state.toMap();
    emit stateChanged();
}

void TailscaleMonitor::onActionFinished(bool ok, const QString &output, const QString &error, const QString &successMsg)
{
    emit actionCompleted(ok, output, error, successMsg);
}

void TailscaleMonitor::onPingFinished(bool ok, const QString &targetIp, const QString &latency, const QString &, const QString &error)
{
    m_pingTargetIp = targetIp;
    m_pingResult = ok ? latency : (error.isEmpty() ? QStringLiteral("Timed out") : error);
    emit pingFinished(ok, targetIp, m_pingResult);
}

void TailscaleMonitor::onNetcheckFinished(bool ok, const QString &report, const QString &error)
{
    m_isRunningNetcheck = false;
    m_netcheckReport = ok ? report : error;
    emit netcheckStatusChanged();
}

} // namespace qs::plugins
