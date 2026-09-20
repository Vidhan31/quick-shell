#pragma once

#include <QObject>
#include <QStringList>
#include <QThread>
#include <QVariant>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

// Token sums for one time window. Total deliberately excludes reasoning:
// it is informational only and most clients already fold it into output.
struct TokenWindow {
    qlonglong input = 0;
    qlonglong output = 0;
    qlonglong cacheRead = 0;
    qlonglong cacheWrite = 0;
    qlonglong reasoning = 0;
    double cost = 0.0;
    qlonglong messages = 0;

    [[nodiscard]] qlonglong total() const { return input + output + cacheRead + cacheWrite; }
};

struct TokenRefreshResult {
    bool ok = false;
    bool configured = false;
    QString error;
    QStringList dbPaths;
    TokenWindow today;
    TokenWindow week;
    TokenWindow month;
    QString refreshedAt;
    QVariantList monthModels;
};

// Window bounds in milliseconds since epoch, local time.
struct TokenWindowBounds {
    qint64 todayStart = 0;
    qint64 weekStart = 0; // Monday 00:00 local
    qint64 monthStart = 0; // first of month 00:00 local
    qint64 end = 0;
};

TokenWindowBounds computeWindowBounds();
QStringList discoverOpenCodeDbPaths();

// Synchronous collection used by both the worker thread and the probe tool.
TokenRefreshResult collectTokenUsage(const TokenWindowBounds &bounds);

class TokenUsageWorker : public QObject {
    Q_OBJECT

public:
    explicit TokenUsageWorker(QObject *parent = nullptr);

public slots:
    void refresh(const TokenWindowBounds &bounds);

signals:
    void refreshed(const TokenRefreshResult &result);
};

class TokenUsage : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(qlonglong todayTokens READ todayTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong weekTokens READ weekTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong monthTokens READ monthTokens NOTIFY dataChanged)
    Q_PROPERTY(double todayCost READ todayCost NOTIFY dataChanged)
    Q_PROPERTY(double weekCost READ weekCost NOTIFY dataChanged)
    Q_PROPERTY(double monthCost READ monthCost NOTIFY dataChanged)
    Q_PROPERTY(qlonglong todayMessages READ todayMessages NOTIFY dataChanged)
    Q_PROPERTY(qlonglong weekMessages READ weekMessages NOTIFY dataChanged)
    Q_PROPERTY(qlonglong monthMessages READ monthMessages NOTIFY dataChanged)
    Q_PROPERTY(QVariantList monthModels READ monthModels NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap todaySplit READ todaySplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap weekSplit READ weekSplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap monthSplit READ monthSplit NOTIFY dataChanged)
    Q_PROPERTY(QString lastRefresh READ lastRefresh NOTIFY dataChanged)
    Q_PROPERTY(QString error READ error NOTIFY dataChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)
    Q_PROPERTY(bool configured READ isConfigured NOTIFY dataChanged)

public:
    explicit TokenUsage(QObject *parent = nullptr);
    ~TokenUsage() override;

    [[nodiscard]] qlonglong todayTokens() const { return m_today.total(); }
    [[nodiscard]] qlonglong weekTokens() const { return m_week.total(); }
    [[nodiscard]] qlonglong monthTokens() const { return m_month.total(); }
    [[nodiscard]] double todayCost() const { return m_today.cost; }
    [[nodiscard]] double weekCost() const { return m_week.cost; }
    [[nodiscard]] double monthCost() const { return m_month.cost; }
    [[nodiscard]] qlonglong todayMessages() const { return m_today.messages; }
    [[nodiscard]] qlonglong weekMessages() const { return m_week.messages; }
    [[nodiscard]] qlonglong monthMessages() const { return m_month.messages; }
    [[nodiscard]] QVariantList monthModels() const { return m_monthModels; }
    [[nodiscard]] QVariantMap todaySplit() const { return m_todaySplit; }
    [[nodiscard]] QVariantMap weekSplit() const { return m_weekSplit; }
    [[nodiscard]] QVariantMap monthSplit() const { return m_monthSplit; }
    [[nodiscard]] QString lastRefresh() const { return m_lastRefresh; }
    [[nodiscard]] QString error() const { return m_error; }
    [[nodiscard]] bool isBusy() const { return m_busy; }
    [[nodiscard]] bool isConfigured() const { return m_configured; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QString compact(qlonglong value) const;

signals:
    void dataChanged();
    void busyChanged();
    void requestRefresh(const TokenWindowBounds &bounds);

private slots:
    void onRefreshed(const TokenRefreshResult &result);

private:
    void loadCachedResult();
    void saveCachedResult(const TokenRefreshResult &result);

    QThread m_thread;
    TokenUsageWorker *m_worker{nullptr};

    TokenWindow m_today;
    TokenWindow m_week;
    TokenWindow m_month;
    QVariantList m_monthModels;
    QVariantMap m_todaySplit;
    QVariantMap m_weekSplit;
    QVariantMap m_monthSplit;
    QString m_lastRefresh;
    QString m_error;
    bool m_busy{false};
    bool m_configured{false};
};

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::TokenWindowBounds)
Q_DECLARE_METATYPE(qs::plugins::TokenRefreshResult)
