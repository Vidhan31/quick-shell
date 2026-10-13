#include "UsageMonitorBase.hpp"

namespace qs::plugins {

UsageWorker::UsageWorker(const QString &cacheFilePath,
                         CollectFn collector,
                         QObject *parent)
    : QObject(parent), m_cacheFilePath(cacheFilePath), m_collector(collector) {}

void UsageWorker::loadCache() {
    if (m_cacheFilePath.isEmpty()) {
        return;
    }
    TokenRefreshResult cached;
    if (loadUsageCache(m_cacheFilePath, cached)) {
        emit cacheLoaded(cached);
    }
}

void UsageWorker::refresh(const TokenWindowBounds &bounds, int lastDays) {
    if (m_collector) {
        TokenRefreshResult result = m_collector(bounds, lastDays);
        if (result.ok && !m_cacheFilePath.isEmpty()) {
            saveUsageCache(m_cacheFilePath, result);
        }
        emit refreshed(result);
    }
}

UsageMonitorBase::UsageMonitorBase(const QString &cacheRelativePath,
                                   UsageWorker::CollectFn collector,
                                   QObject *parent)
    : QObject(parent),
      m_cacheFilePath(resolveUsageCachePath(cacheRelativePath)) {
    qRegisterMetaType<TokenWindowBounds>();
    qRegisterMetaType<TokenRefreshResult>();
    m_worker = new UsageWorker(m_cacheFilePath, collector);
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(&m_thread, &QThread::started, m_worker, &UsageWorker::loadCache);
    connect(this, &UsageMonitorBase::requestRefresh, m_worker, &UsageWorker::refresh);
    connect(m_worker, &UsageWorker::cacheLoaded, this, &UsageMonitorBase::applyCachedResult);
    connect(m_worker, &UsageWorker::refreshed, this, &UsageMonitorBase::onRefreshed);
    m_thread.start();
}

UsageMonitorBase::~UsageMonitorBase() {
    m_thread.quit();
    m_thread.wait();
}

void UsageMonitorBase::applyCachedResult(const TokenRefreshResult &cached) {
    if (m_configured && !m_lastRefresh.isEmpty()) {
        return;
    }
    m_today = cached.today;
    m_week = cached.week;
    m_month = cached.month;
    m_lastDaysWindow = cached.lastDays;
    m_allTime = cached.allTime;
    m_lastDays = cached.lastDaysRequested;
    m_monthModels = cached.monthModels;
    m_allModels = cached.allModels;
    m_monthSources = cached.monthSources;
    m_dailyUsage = cached.dailyUsage;
    m_todaySplit = splitMap(m_today);
    m_weekSplit = splitMap(m_week);
    m_monthSplit = splitMap(m_month);
    m_lastDaysSplit = splitMap(m_lastDaysWindow);
    m_allSplit = splitMap(m_allTime);
    m_lastRefresh = cached.refreshedAt;
    m_configured = !m_lastRefresh.isEmpty();
    emit dataChanged();
}

void UsageMonitorBase::refresh() {
    if (m_busy) {
        return;
    }
    m_busy = true;
    emit busyChanged();
    emit requestRefresh(computeWindowBounds(), m_lastDays);
}

void UsageMonitorBase::setLastDays(int days) {
    if (days < 1) {
        days = 1;
    } else if (days > 400) {
        days = 400;
    }
    if (m_lastDays == days) {
        return;
    }
    m_lastDays = days;
    emit lastDaysChanged();
    refresh();
}

QString UsageMonitorBase::compact(qlonglong value) const {
    auto trim2 = [](double scaled) {
        QString text = QString::number(scaled, 'f', 2);
        while (text.endsWith(u'0')) {
            text.chop(1);
        }
        if (text.endsWith(u'.')) {
            text.chop(1);
        }
        return text;
    };
    const double tokens = static_cast<double>(value);
    if (tokens >= 1e9) {
        return trim2(tokens / 1e9) + QStringLiteral("B");
    }
    if (tokens >= 1e6) {
        return trim2(tokens / 1e6) + QStringLiteral("M");
    }
    if (tokens >= 1e3) {
        return trim2(tokens / 1e3) + QStringLiteral("K");
    }
    return QString::number(value);
}

void UsageMonitorBase::onRefreshed(const TokenRefreshResult &result) {
    m_busy = false;
    m_configured = result.configured;
    m_error = result.error;
    if (result.ok) {
        m_today = result.today;
        m_week = result.week;
        m_month = result.month;
        m_lastDaysWindow = result.lastDays;
        m_allTime = result.allTime;
        m_monthModels = result.monthModels;
        m_allModels = result.allModels;
        m_monthSources = result.monthSources;
        m_dailyUsage = result.dailyUsage;
        m_todaySplit = splitMap(result.today);
        m_weekSplit = splitMap(result.week);
        m_monthSplit = splitMap(result.month);
        m_lastDaysSplit = splitMap(result.lastDays);
        m_allSplit = splitMap(result.allTime);
        m_lastRefresh = result.refreshedAt;
        if (m_lastDays != result.lastDaysRequested) {
            emit busyChanged();
            emit dataChanged();
            refresh();
            return;
        }
    }
    emit busyChanged();
    emit dataChanged();
}

} // namespace qs::plugins
