#include "EthernetMonitor.hpp"

#include <QDBusConnection>

namespace qs::plugins {

EthernetWorker::EthernetWorker(int intervalMs, QObject *parent)
    : QObject(parent)
    , m_intervalMs(qMax(500, intervalMs))
{
}

EthernetWorker::~EthernetWorker() {
    if (m_timer) {
        m_timer->stop();
    }
}

void EthernetWorker::setupDbusSubscriptions() {
    auto bus = QDBusConnection::systemBus();
    if (bus.isConnected()) {
        bus.connect(QStringLiteral("org.freedesktop.NetworkManager"),
                    QStringLiteral("/org/freedesktop/NetworkManager"),
                    QStringLiteral("org.freedesktop.DBus.Properties"),
                    QStringLiteral("PropertiesChanged"),
                    this,
                    SLOT(onNmSignal()));

        bus.connect(QStringLiteral("org.freedesktop.NetworkManager"),
                    QStringLiteral("/org/freedesktop/NetworkManager"),
                    QStringLiteral("org.freedesktop.NetworkManager"),
                    QStringLiteral("PropertiesChanged"),
                    this,
                    SLOT(onNmSignal()));

        bus.connect(QStringLiteral("org.freedesktop.NetworkManager"),
                    QStringLiteral("/org/freedesktop/NetworkManager"),
                    QStringLiteral("org.freedesktop.NetworkManager"),
                    QStringLiteral("CheckPermissions"),
                    this,
                    SLOT(onNmSignal()));
    }
}

void EthernetWorker::start() {
    if (!m_timer) {
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, [this]() {
            sample(false);
        });
        setupDbusSubscriptions();
    }
    sample(true);
    m_timer->start(m_intervalMs);
}

void EthernetWorker::stop() {
    if (m_timer) {
        m_timer->stop();
    }
}

void EthernetWorker::setInterval(int intervalMs) {
    m_intervalMs = qMax(500, intervalMs);
    if (m_timer && m_timer->isActive()) {
        m_timer->start(m_intervalMs);
    }
}

void EthernetWorker::sample(bool forceInternetCheck) {
    const auto state = EthernetProbe::probe(forceInternetCheck);
    const auto now = std::chrono::steady_clock::now();

    if (m_initialized && m_prevTime.time_since_epoch().count() > 0) {
        const double dtSec = std::chrono::duration<double>(now - m_prevTime).count();
        if (dtSec > 0.05) {
            const double rxBps = (state.rxBytes >= m_prevRx) ? static_cast<double>(state.rxBytes - m_prevRx) / dtSec : 0.0;
            const double txBps = (state.txBytes >= m_prevTx) ? static_cast<double>(state.txBytes - m_prevTx) / dtSec : 0.0;
            emit throughputUpdated(state.rxBytes, state.txBytes, rxBps, txBps);
        }
    }

    m_prevRx = state.rxBytes;
    m_prevTx = state.txBytes;
    m_prevTime = now;

    if (!m_initialized || !state.coreEquals(m_lastState)) {
        m_initialized = true;
        m_lastState = state;
        emit stateChanged(state);
    }
}

void EthernetWorker::onNmSignal() {
    sample(false);
}

void EthernetWorker::runPing(const QString &target) {
    const auto res = EthernetProbe::pingHost(target, 1500);
    emit pingFinished(res.ok, res.target, res.latencyMs, res.output);
}

void EthernetWorker::runCheck() {
    EthernetProbe::checkConnectivity();
    sample(true);
}

void EthernetWorker::reconnect(const QString &iface) {
    EthernetProbe::reconnectDevice(iface);
    sample(false);
}

void EthernetWorker::openSettings() {
    EthernetProbe::openSettings();
}

// ---------------- EthernetMonitor implementation ----------------

EthernetMonitor::EthernetMonitor(QObject *parent)
    : QObject(parent)
{
    qRegisterMetaType<qs::plugins::EthernetState>("qs::plugins::EthernetState");
    m_cachedMap = m_state.toMap();

    m_worker = new EthernetWorker(m_interval);
    m_worker->moveToThread(&m_workerThread);

    connect(&m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);

    connect(this, &EthernetMonitor::requestStart, m_worker, &EthernetWorker::start);
    connect(this, &EthernetMonitor::requestStop, m_worker, &EthernetWorker::stop);
    connect(this, &EthernetMonitor::requestSetInterval, m_worker, &EthernetWorker::setInterval);
    connect(this, &EthernetMonitor::requestSample, m_worker, &EthernetWorker::sample);
    connect(this, &EthernetMonitor::requestPing, m_worker, &EthernetWorker::runPing);
    connect(this, &EthernetMonitor::requestCheck, m_worker, &EthernetWorker::runCheck);
    connect(this, &EthernetMonitor::requestReconnect, m_worker, &EthernetWorker::reconnect);
    connect(this, &EthernetMonitor::requestOpenSettings, m_worker, &EthernetWorker::openSettings);

    connect(m_worker, &EthernetWorker::stateChanged, this, &EthernetMonitor::onStateChanged);
    connect(m_worker, &EthernetWorker::throughputUpdated, this, &EthernetMonitor::onThroughputUpdated);
    connect(m_worker, &EthernetWorker::pingFinished, this, &EthernetMonitor::onPingFinished);

    m_workerThread.start();
    if (m_running) {
        emit requestStart();
    }
}

EthernetMonitor::~EthernetMonitor() {
    emit requestStop();
    m_workerThread.quit();
    m_workerThread.wait();
}

void EthernetMonitor::setRunning(bool running) {
    if (m_running == running) return;
    m_running = running;
    if (m_running) {
        emit requestStart();
    } else {
        emit requestStop();
    }
    emit runningChanged();
}

void EthernetMonitor::setInterval(int interval) {
    if (m_interval == interval) return;
    m_interval = interval;
    emit requestSetInterval(interval);
    emit intervalChanged();
}

void EthernetMonitor::refresh() {
    m_isBusy = true;
    emit busyChanged();
    emit requestSample(false);
}

void EthernetMonitor::runPing(const QString &host) {
    m_isPinging = true;
    m_pingResult = QStringLiteral("Testing...");
    emit pingStatusChanged();
    emit requestPing(host.isEmpty() ? QStringLiteral("1.1.1.1") : host);
}

void EthernetMonitor::runCheck() {
    m_isBusy = true;
    emit busyChanged();
    emit requestCheck();
}

void EthernetMonitor::reconnect(const QString &iface) {
    emit requestReconnect(iface);
}

void EthernetMonitor::openSettings() {
    emit requestOpenSettings();
}

void EthernetMonitor::onStateChanged(const EthernetState &state) {
    m_state = state;
    m_cachedMap = state.toMap();
    m_rxBytes = state.rxBytes;
    m_txBytes = state.txBytes;
    m_isBusy = false;
    emit stateChanged();
    emit busyChanged();
}

void EthernetMonitor::onThroughputUpdated(quint64 rxBytes, quint64 txBytes, double rxBps, double txBps) {
    m_rxBytes = rxBytes;
    m_txBytes = txBytes;
    m_downloadBps = rxBps;
    m_uploadBps = txBps;
    emit throughputChanged();
}

void EthernetMonitor::onPingFinished(bool ok, const QString &target, double latencyMs, const QString &output) {
    Q_UNUSED(target)
    m_isPinging = false;
    m_pingLatency = latencyMs;
    if (ok && latencyMs >= 0) {
        m_pingResult = QString::number(latencyMs, 'f', 1) + QStringLiteral(" ms");
    } else {
        m_pingResult = QStringLiteral("Failed");
    }
    emit pingStatusChanged();
    emit pingCompleted(ok, latencyMs, output);
}

} // namespace qs::plugins
