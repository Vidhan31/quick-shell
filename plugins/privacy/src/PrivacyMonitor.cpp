#include "PrivacyMonitor.hpp"

namespace qs::plugins {

PrivacyWorker::PrivacyWorker(int intervalMs, QObject *parent)
    : QObject(parent)
    , m_intervalMs(qMax(200, intervalMs))
{
}

PrivacyWorker::~PrivacyWorker() {
    if (m_timer) {
        m_timer->stop();
    }
}

void PrivacyWorker::start() {
    if (!m_timer) {
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, &PrivacyWorker::sample);
    }
    sample();
    m_timer->start(m_intervalMs);
}

void PrivacyWorker::stop() {
    if (m_timer) {
        m_timer->stop();
    }
}

void PrivacyWorker::setInterval(int intervalMs) {
    m_intervalMs = qMax(200, intervalMs);
    if (m_timer && m_timer->isActive()) {
        m_timer->start(m_intervalMs);
    }
}

void PrivacyWorker::sample() {
    const bool deepQuery = (m_tickCount++ % 10 == 0);
    const auto state = PrivacyProbe::probe(deepQuery);
    if (!m_initialized || state != m_lastState) {
        m_initialized = true;
        m_lastState = state;
        emit stateChanged(state);
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
