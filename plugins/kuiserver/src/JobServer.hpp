#pragma once

#include "JobItem.hpp"

#include <QDBusContext>
#include <QDBusObjectPath>
#include <QDBusServiceWatcher>
#include <QHash>
#include <QList>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins::kuiserver {

class KuiServerAdaptor;
class JobViewServerAdaptor;
class JobViewServerV2Adaptor;

class JobServer : public QObject, protected QDBusContext {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(JobServer)

    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool ownsService READ ownsService NOTIFY ownsServiceChanged)
    Q_PROPERTY(QVariantList jobs READ jobs NOTIFY jobsChanged)
    Q_PROPERTY(QVariantList activeJobs READ activeJobs NOTIFY activeJobsChanged)
    Q_PROPERTY(int activeJobsCount READ activeJobsCount NOTIFY activeJobsCountChanged)
    Q_PROPERTY(int totalPercentage READ totalPercentage NOTIFY totalPercentageChanged)
    Q_PROPERTY(quint64 totalSpeed READ totalSpeed NOTIFY totalSpeedChanged)
    Q_PROPERTY(QString formattedTotalSpeed READ formattedTotalSpeed NOTIFY totalSpeedChanged)

public:
    explicit JobServer(QObject *parent = nullptr);
    ~JobServer() override;

    [[nodiscard]] bool active() const { return m_active; }
    void setActive(bool active);

    [[nodiscard]] bool ownsService() const { return m_ownsService; }
    [[nodiscard]] QVariantList jobs() const;
    [[nodiscard]] QVariantList activeJobs() const;
    [[nodiscard]] int activeJobsCount() const { return m_activeCount; }
    [[nodiscard]] int totalPercentage() const { return m_totalPercentage; }
    [[nodiscard]] quint64 totalSpeed() const { return m_totalSpeed; }
    [[nodiscard]] QString formattedTotalSpeed() const { return JobEntry::formatSpeed(m_totalSpeed); }

    Q_INVOKABLE void cancelJob(uint id);
    Q_INVOKABLE void suspendJob(uint id);
    Q_INVOKABLE void resumeJob(uint id);
    Q_INVOKABLE void removeJob(uint id);
    Q_INVOKABLE void clearFinished();

    bool dbusRequiresJobTracker();
    QStringList dbusRegisteredJobContacts();
    QDBusObjectPath dbusRequestView(const QString &appName, const QString &appIconName, int capabilities);
    QDBusObjectPath dbusRequestViewV2(const QString &desktopEntry, int capabilities, const QVariantMap &hints);

Q_SIGNALS:
    void activeChanged();
    void ownsServiceChanged();
    void jobsChanged();
    void activeJobsChanged();
    void activeJobsCountChanged();
    void totalPercentageChanged();
    void totalSpeedChanged();
    void jobAdded(uint id, const QVariantMap &job);
    void jobUpdated(uint id, const QVariantMap &job);
    void jobFinished(uint id, const QVariantMap &job);

private Q_SLOTS:
    void onClientServiceUnregistered(const QString &service);
    void onServiceOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);

private:
    void registerDbus();
    void unregisterDbus();
    void tryClaimServiceNames();
    void updateLauncherProgress(const QString &desktopEntry);
    void recomputeState();
    JobItem *findJob(uint id) const;

    bool m_active = true;
    bool m_ownsService = false;
    uint m_nextJobId = 1;
    int m_activeCount = 0;
    int m_totalPercentage = 0;
    quint64 m_totalSpeed = 0;

    KuiServerAdaptor *m_kuiAdaptor = nullptr;
    JobViewServerAdaptor *m_jobViewAdaptor = nullptr;
    JobViewServerV2Adaptor *m_jobViewV2Adaptor = nullptr;
    QDBusServiceWatcher *m_serviceWatcher = nullptr;
    QDBusServiceWatcher *m_clientWatcher = nullptr;

    QList<JobItem *> m_items;
    QList<JobEntry> m_finishedHistory;
    QTimer m_notifyTimer;
    bool m_pendingNotify = false;
};

} // namespace qs::plugins::kuiserver
