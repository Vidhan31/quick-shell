#pragma once

#include <QObject>
#include <QStringList>
#include <QThread>
#include <QVariant>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

// Token sums for one time window. No cost and no cache write: neither is
// recorded in Antigravity conversation databases, so they are omitted
// rather than shown as permanent zeros.
struct AgTokenWindow {
    qlonglong input = 0;
    qlonglong output = 0;
    qlonglong cacheRead = 0;
    qlonglong reasoning = 0;

    [[nodiscard]] qlonglong total() const { return input + output + cacheRead; }
};

struct AgRefreshResult {
    bool ok = false;
    bool configured = false;
    QString error;
    QStringList roots;
    qlonglong filesScanned = 0;
    qlonglong rowsSkipped = 0;
    AgTokenWindow today;
    AgTokenWindow week;
    AgTokenWindow month;
    AgTokenWindow lastDays;
    int lastDaysRequested = 10;
    QString refreshedAt;
    QVariantList monthModels;
    QVariantList monthSources;
};

// Window bounds in milliseconds since epoch, Asia/Kolkata calendar days.
struct AgWindowBounds {
    qint64 todayStart = 0;
    qint64 weekStart = 0; // Monday 00:00 local
    qint64 monthStart = 0; // first of month 00:00 local
    qint64 end = 0;
    qint64 lastDaysStart = 0;
};

AgWindowBounds computeAgWindowBounds();
QStringList discoverAgRoots();

// Synchronous collection used by both the worker thread and the probe tool.
// lastDays selects a rolling window ending at the current time. Clamped to
// [1,30]; 10 when out of range.
AgRefreshResult collectAgUsage(const AgWindowBounds &bounds, int lastDays = 10);

class AgUsageWorker : public QObject {
    Q_OBJECT

public:
    explicit AgUsageWorker(QObject *parent = nullptr);

public slots:
    void refresh(const AgWindowBounds &bounds, int lastDays);

signals:
    void refreshed(const AgRefreshResult &result);
};

class AntigravityUsage : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(qlonglong todayTokens READ todayTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong weekTokens READ weekTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong monthTokens READ monthTokens NOTIFY dataChanged)
    Q_PROPERTY(QVariantList monthModels READ monthModels NOTIFY dataChanged)
    Q_PROPERTY(QVariantList monthSources READ monthSources NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap todaySplit READ todaySplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap weekSplit READ weekSplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap monthSplit READ monthSplit NOTIFY dataChanged)
    Q_PROPERTY(int lastDays READ lastDays WRITE setLastDays NOTIFY lastDaysChanged)
    Q_PROPERTY(qlonglong lastDaysTokens READ lastDaysTokens NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap lastDaysSplit READ lastDaysSplit NOTIFY dataChanged)
    Q_PROPERTY(QString lastRefresh READ lastRefresh NOTIFY dataChanged)
    Q_PROPERTY(QString error READ error NOTIFY dataChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)
    Q_PROPERTY(bool configured READ isConfigured NOTIFY dataChanged)

public:
    explicit AntigravityUsage(QObject *parent = nullptr);
    ~AntigravityUsage() override;

    [[nodiscard]] qlonglong todayTokens() const { return m_today.total(); }
    [[nodiscard]] qlonglong weekTokens() const { return m_week.total(); }
    [[nodiscard]] qlonglong monthTokens() const { return m_month.total(); }
    [[nodiscard]] QVariantList monthModels() const { return m_monthModels; }
    [[nodiscard]] QVariantList monthSources() const { return m_monthSources; }
    [[nodiscard]] QVariantMap todaySplit() const { return m_todaySplit; }
    [[nodiscard]] QVariantMap weekSplit() const { return m_weekSplit; }
    [[nodiscard]] QVariantMap monthSplit() const { return m_monthSplit; }
    [[nodiscard]] int lastDays() const { return m_lastDays; }
    [[nodiscard]] qlonglong lastDaysTokens() const { return m_lastDaysWindow.total(); }
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
    void requestRefresh(const AgWindowBounds &bounds, int lastDays);

private slots:
    void onRefreshed(const AgRefreshResult &result);

private:
    void loadCachedResult();
    void saveCachedResult(const AgRefreshResult &result);

    QThread m_thread;
    AgUsageWorker *m_worker{nullptr};

    AgTokenWindow m_today;
    AgTokenWindow m_week;
    AgTokenWindow m_month;
    AgTokenWindow m_lastDaysWindow;
    int m_lastDays{10};
    QVariantList m_monthModels;
    QVariantList m_monthSources;
    QVariantMap m_todaySplit;
    QVariantMap m_weekSplit;
    QVariantMap m_monthSplit;
    QVariantMap m_lastDaysSplit;
    QString m_lastRefresh;
    QString m_error;
    bool m_busy{false};
    bool m_configured{false};
};

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::AgWindowBounds)
Q_DECLARE_METATYPE(qs::plugins::AgRefreshResult)
