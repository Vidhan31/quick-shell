#pragma once

#include "UsageCache.hpp"
#include "UsageTypes.hpp"

#include <QObject>
#include <QThread>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

class UsageWorker : public QObject {
    Q_OBJECT

public:
    using CollectFn = TokenRefreshResult (*)(const TokenWindowBounds &, int);

    explicit UsageWorker(const QString &cacheFilePath,
                         CollectFn collector,
                         QObject *parent = nullptr);

public slots:
    void loadCache();
    void refresh(const TokenWindowBounds &bounds, int lastDays);

signals:
    void cacheLoaded(const TokenRefreshResult &result);
    void refreshed(const TokenRefreshResult &result);

private:
    QString m_cacheFilePath;
    CollectFn m_collector{nullptr};
};

class UsageMonitorBase : public QObject {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(qlonglong todayTokens READ todayTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong weekTokens READ weekTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong monthTokens READ monthTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong allTokens READ allTokens NOTIFY dataChanged)
    Q_PROPERTY(double todayCost READ todayCost NOTIFY dataChanged)
    Q_PROPERTY(double weekCost READ weekCost NOTIFY dataChanged)
    Q_PROPERTY(double monthCost READ monthCost NOTIFY dataChanged)
    Q_PROPERTY(double allCost READ allCost NOTIFY dataChanged)
    Q_PROPERTY(QVariantList monthModels READ monthModels NOTIFY dataChanged)
    Q_PROPERTY(QVariantList allModels READ allModels NOTIFY dataChanged)
    Q_PROPERTY(QVariantList monthSources READ monthSources NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap todaySplit READ todaySplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap weekSplit READ weekSplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap monthSplit READ monthSplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap allSplit READ allSplit NOTIFY dataChanged)
    Q_PROPERTY(int lastDays READ lastDays WRITE setLastDays NOTIFY lastDaysChanged)
    Q_PROPERTY(qlonglong lastDaysTokens READ lastDaysTokens NOTIFY dataChanged)
    Q_PROPERTY(double lastDaysCost READ lastDaysCost NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap lastDaysSplit READ lastDaysSplit NOTIFY dataChanged)
    Q_PROPERTY(QString lastRefresh READ lastRefresh NOTIFY dataChanged)
    Q_PROPERTY(QVariantList dailyUsage READ dailyUsage NOTIFY dataChanged)
    Q_PROPERTY(QString error READ error NOTIFY dataChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)
    Q_PROPERTY(bool configured READ isConfigured NOTIFY dataChanged)

public:
    explicit UsageMonitorBase(const QString &cacheRelativePath,
                              UsageWorker::CollectFn collector,
                              QObject *parent = nullptr);
    ~UsageMonitorBase() override;

    [[nodiscard]] qlonglong todayTokens() const { return m_today.total(); }
    [[nodiscard]] qlonglong weekTokens() const { return m_week.total(); }
    [[nodiscard]] qlonglong monthTokens() const { return m_month.total(); }
    [[nodiscard]] qlonglong allTokens() const { return m_allTime.total(); }
    [[nodiscard]] double todayCost() const { return m_today.cost; }
    [[nodiscard]] double weekCost() const { return m_week.cost; }
    [[nodiscard]] double monthCost() const { return m_month.cost; }
    [[nodiscard]] double allCost() const { return m_allTime.cost; }
    [[nodiscard]] QVariantList monthModels() const { return m_monthModels; }
    [[nodiscard]] QVariantList allModels() const { return m_allModels; }
    [[nodiscard]] QVariantList monthSources() const { return m_monthSources; }
    [[nodiscard]] QVariantList dailyUsage() const { return m_dailyUsage; }
    [[nodiscard]] QVariantMap todaySplit() const { return m_todaySplit; }
    [[nodiscard]] QVariantMap weekSplit() const { return m_weekSplit; }
    [[nodiscard]] QVariantMap monthSplit() const { return m_monthSplit; }
    [[nodiscard]] QVariantMap allSplit() const { return m_allSplit; }
    [[nodiscard]] int lastDays() const { return m_lastDays; }
    [[nodiscard]] qlonglong lastDaysTokens() const { return m_lastDaysWindow.total(); }
    [[nodiscard]] double lastDaysCost() const { return m_lastDaysWindow.cost; }
    [[nodiscard]] QVariantMap lastDaysSplit() const { return m_lastDaysSplit; }
    [[nodiscard]] QString lastRefresh() const { return m_lastRefresh; }
    [[nodiscard]] QString error() const { return m_error; }
    [[nodiscard]] bool isBusy() const { return m_busy; }
    [[nodiscard]] bool isConfigured() const { return m_configured; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setLastDays(int days);
    Q_INVOKABLE QString compact(qlonglong value) const;

signals:
    void dataChanged();
    void busyChanged();
    void lastDaysChanged();
    void requestRefresh(const TokenWindowBounds &bounds, int lastDays);

private slots:
    void applyCachedResult(const TokenRefreshResult &cached);
    void onRefreshed(const TokenRefreshResult &result);

private:
    QString m_cacheFilePath;
    QThread m_thread;
    UsageWorker *m_worker{nullptr};

    TokenWindow m_today;
    TokenWindow m_week;
    TokenWindow m_month;
    TokenWindow m_lastDaysWindow;
    TokenWindow m_allTime;
    int m_lastDays{10};
    QVariantList m_monthModels;
    QVariantList m_allModels;
    QVariantList m_monthSources;
    QVariantList m_dailyUsage;
    QVariantMap m_todaySplit;
    QVariantMap m_weekSplit;
    QVariantMap m_monthSplit;
    QVariantMap m_lastDaysSplit;
    QVariantMap m_allSplit;
    QString m_lastRefresh;
    QString m_error;
    bool m_busy{false};
    bool m_configured{false};
};

} // namespace qs::plugins
