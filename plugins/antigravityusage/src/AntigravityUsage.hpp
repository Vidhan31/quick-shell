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
    qlonglong messages = 0;

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
    AgTokenWindow lastN;
    int lastNRequested = 20;
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
};

AgWindowBounds computeAgWindowBounds();
QStringList discoverAgRoots();

// Synchronous collection used by both the worker thread and the probe tool.
// lastN aggregates the most-recent deduped turns (file mtime, then idx) into
// result.lastN. Ordering across files is approximate: all turns in one file
// share the file mtime, so idx only orders within a file.
AgRefreshResult collectAgUsage(const AgWindowBounds &bounds, int lastN = 20);

class AgUsageWorker : public QObject {
    Q_OBJECT

public:
    explicit AgUsageWorker(QObject *parent = nullptr);

public slots:
    void refresh(const AgWindowBounds &bounds, int lastN);

signals:
    void refreshed(const AgRefreshResult &result);
};

class AntigravityUsage : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(qlonglong todayTokens READ todayTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong weekTokens READ weekTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong monthTokens READ monthTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong todayMessages READ todayMessages NOTIFY dataChanged)
    Q_PROPERTY(qlonglong weekMessages READ weekMessages NOTIFY dataChanged)
    Q_PROPERTY(qlonglong monthMessages READ monthMessages NOTIFY dataChanged)
    Q_PROPERTY(QVariantList monthModels READ monthModels NOTIFY dataChanged)
    Q_PROPERTY(QVariantList monthSources READ monthSources NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap todaySplit READ todaySplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap weekSplit READ weekSplit NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap monthSplit READ monthSplit NOTIFY dataChanged)
    Q_PROPERTY(int lastN READ lastN WRITE setLastN NOTIFY lastNChanged)
    Q_PROPERTY(qlonglong lastNTokens READ lastNTokens NOTIFY dataChanged)
    Q_PROPERTY(qlonglong lastNMessages READ lastNMessages NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap lastNSplit READ lastNSplit NOTIFY dataChanged)
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
    [[nodiscard]] qlonglong todayMessages() const { return m_today.messages; }
    [[nodiscard]] qlonglong weekMessages() const { return m_week.messages; }
    [[nodiscard]] qlonglong monthMessages() const { return m_month.messages; }
    [[nodiscard]] QVariantList monthModels() const { return m_monthModels; }
    [[nodiscard]] QVariantList monthSources() const { return m_monthSources; }
    [[nodiscard]] QVariantMap todaySplit() const { return m_todaySplit; }
    [[nodiscard]] QVariantMap weekSplit() const { return m_weekSplit; }
    [[nodiscard]] QVariantMap monthSplit() const { return m_monthSplit; }
    [[nodiscard]] int lastN() const { return m_lastN; }
    [[nodiscard]] qlonglong lastNTokens() const { return m_lastNWindow.total(); }
    [[nodiscard]] qlonglong lastNMessages() const { return m_lastNWindow.messages; }
    [[nodiscard]] QVariantMap lastNSplit() const { return m_lastNSplit; }
    [[nodiscard]] QString lastRefresh() const { return m_lastRefresh; }
    [[nodiscard]] QString error() const { return m_error; }
    [[nodiscard]] bool isBusy() const { return m_busy; }
    [[nodiscard]] bool isConfigured() const { return m_configured; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setLastN(int n);
    Q_INVOKABLE QString compact(qlonglong value) const;

signals:
    void dataChanged();
    void busyChanged();
    void lastNChanged();
    void requestRefresh(const AgWindowBounds &bounds, int lastN);

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
    AgTokenWindow m_lastNWindow;
    int m_lastN{20};
    QVariantList m_monthModels;
    QVariantList m_monthSources;
    QVariantMap m_todaySplit;
    QVariantMap m_weekSplit;
    QVariantMap m_monthSplit;
    QVariantMap m_lastNSplit;
    QString m_lastRefresh;
    QString m_error;
    bool m_busy{false};
    bool m_configured{false};
};

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::AgWindowBounds)
Q_DECLARE_METATYPE(qs::plugins::AgRefreshResult)
