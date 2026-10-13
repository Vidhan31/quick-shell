#include "JobServer.hpp"
#include "ServerAdaptors.hpp"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDebug>

namespace qs::plugins::kuiserver {

namespace {
const QString kKuiServerService = QStringLiteral("org.kde.kuiserver");
const QString kJobViewServerService = QStringLiteral("org.kde.JobViewServer");
const QString kJobViewServerPath = QStringLiteral("/JobViewServer");
constexpr int kMaxFinishedHistory = 30;
}

JobServer::JobServer(QObject *parent)
    : QObject(parent) {
    m_notifyTimer.setInterval(0);
    m_notifyTimer.setSingleShot(true);
    connect(&m_notifyTimer, &QTimer::timeout, this, [this] {
        Q_EMIT jobsChanged();
        Q_EMIT activeJobsChanged();
        Q_EMIT activeJobsCountChanged();
        Q_EMIT totalPercentageChanged();
        Q_EMIT totalSpeedChanged();
    });

    m_kuiAdaptor = new KuiServerAdaptor(this);
    m_jobViewAdaptor = new JobViewServerAdaptor(this);
    m_jobViewV2Adaptor = new JobViewServerV2Adaptor(this);

    m_serviceWatcher = new QDBusServiceWatcher(this);
    m_serviceWatcher->setConnection(QDBusConnection::sessionBus());
    m_serviceWatcher->addWatchedService(kKuiServerService);
    m_serviceWatcher->addWatchedService(kJobViewServerService);
    m_serviceWatcher->setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &JobServer::onServiceOwnerChanged);

    m_clientWatcher = new QDBusServiceWatcher(this);
    m_clientWatcher->setConnection(QDBusConnection::sessionBus());
    m_clientWatcher->setWatchMode(QDBusServiceWatcher::WatchForUnregistration);
    connect(m_clientWatcher, &QDBusServiceWatcher::serviceUnregistered, this, &JobServer::onClientServiceUnregistered);

    registerDbus();
}

JobServer::~JobServer() {
    unregisterDbus();
}

void JobServer::setActive(bool active) {
    if (m_active == active) {
        return;
    }
    m_active = active;
    Q_EMIT activeChanged();

    if (m_active) {
        registerDbus();
    } else {
        unregisterDbus();
    }
}

void JobServer::registerDbus() {
    if (!m_active) {
        return;
    }

    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.registerObject(kJobViewServerPath, this);

    tryClaimServiceNames();
}

void JobServer::unregisterDbus() {
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.unregisterObject(kJobViewServerPath);

    if (m_ownsService) {
        bus.unregisterService(kKuiServerService);
        bus.unregisterService(kJobViewServerService);
        m_ownsService = false;
        Q_EMIT ownsServiceChanged();
    }
}

void JobServer::tryClaimServiceNames() {
    QDBusConnectionInterface *iface = QDBusConnection::sessionBus().interface();
    if (!iface) {
        return;
    }

    const auto queueOption = QDBusConnectionInterface::ReplaceExistingService;
    const auto replaceOption = QDBusConnectionInterface::DontAllowReplacement;

    auto reg1 = iface->registerService(kKuiServerService, queueOption, replaceOption);
    auto reg2 = iface->registerService(kJobViewServerService, queueOption, replaceOption);

    const bool owned = (reg1.value() == QDBusConnectionInterface::ServiceRegistered ||
                        reg1.value() == QDBusConnectionInterface::ServiceQueued) &&
                       (reg2.value() == QDBusConnectionInterface::ServiceRegistered ||
                        reg2.value() == QDBusConnectionInterface::ServiceQueued);

    if (m_ownsService != owned) {
        m_ownsService = owned;
        Q_EMIT ownsServiceChanged();
    }
}

void JobServer::onServiceOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner) {
    Q_UNUSED(name)
    Q_UNUSED(oldOwner)
    if (newOwner.isEmpty()) {
        tryClaimServiceNames();
    }
}

void JobServer::onClientServiceUnregistered(const QString &service) {
    m_clientWatcher->removeWatchedService(service);

    const auto items = m_items;
    for (JobItem *item : items) {
        if (item->clientService() == service && item->entry().state != JobState::Stopped) {
            item->terminate(1, QStringLiteral("Process closed unexpectedly"));
        }
    }
}

bool JobServer::dbusRequiresJobTracker() {
    return false;
}

QStringList JobServer::dbusRegisteredJobContacts() {
    return {};
}

QDBusObjectPath JobServer::dbusRequestView(const QString &appName, const QString &appIconName, int capabilities) {
    QVariantMap hints;
    hints.insert(QStringLiteral("application-display-name"), appName);
    hints.insert(QStringLiteral("application-icon-name"), appIconName);
    return dbusRequestViewV2(appName, capabilities, hints);
}

QDBusObjectPath JobServer::dbusRequestViewV2(const QString &desktopEntry, int capabilities, const QVariantMap &hints) {
    const uint id = m_nextJobId++;
    const QString clientService = message().service();

    if (!clientService.isEmpty()) {
        m_clientWatcher->addWatchedService(clientService);
    }

    auto *item = new JobItem(id, desktopEntry, capabilities, hints, clientService, this);

    connect(item, &JobItem::updated, this, [this, item] {
        recomputeState();
        Q_EMIT jobUpdated(item->id(), item->entry().toMap());
        updateLauncherProgress(item->entry().desktopEntry);
    });

    connect(item, &JobItem::finished, this, [this, item] {
        m_finishedHistory.prepend(item->entry());
        while (m_finishedHistory.size() > kMaxFinishedHistory) {
            m_finishedHistory.removeLast();
        }

        const uint finishedId = item->id();
        const QString entryDesktop = item->entry().desktopEntry;
        const QVariantMap snapshot = item->entry().toMap();

        m_items.removeOne(item);
        item->deleteLater();

        recomputeState();
        Q_EMIT jobFinished(finishedId, snapshot);
        updateLauncherProgress(entryDesktop);
    });

    m_items.append(item);
    recomputeState();
    Q_EMIT jobAdded(id, item->entry().toMap());
    updateLauncherProgress(desktopEntry);

    return item->objectPath();
}

JobItem *JobServer::findJob(uint id) const {
    for (JobItem *item : m_items) {
        if (item->id() == id) {
            return item;
        }
    }
    return nullptr;
}

void JobServer::cancelJob(uint id) {
    if (JobItem *item = findJob(id)) {
        item->cancel();
    }
}

void JobServer::suspendJob(uint id) {
    if (JobItem *item = findJob(id)) {
        item->suspend();
    }
}

void JobServer::resumeJob(uint id) {
    if (JobItem *item = findJob(id)) {
        item->resume();
    }
}

void JobServer::removeJob(uint id) {
    if (JobItem *item = findJob(id)) {
        item->cancel();
        return;
    }
    for (int i = 0; i < m_finishedHistory.size(); ++i) {
        if (m_finishedHistory[i].id == id) {
            m_finishedHistory.removeAt(i);
            recomputeState();
            break;
        }
    }
}

void JobServer::clearFinished() {
    if (!m_finishedHistory.isEmpty()) {
        m_finishedHistory.clear();
        recomputeState();
    }
}

void JobServer::recomputeState() {
    int activeCount = 0;
    quint64 totalPercent = 0;
    quint64 totalSpeed = 0;

    for (const JobItem *item : m_items) {
        if (item->entry().state != JobState::Stopped) {
            ++activeCount;
            totalPercent += item->entry().percent;
            totalSpeed += item->entry().speed;
        }
    }

    m_activeCount = activeCount;
    m_totalPercentage = activeCount > 0 ? static_cast<int>(totalPercent / activeCount) : 0;
    m_totalSpeed = totalSpeed;

    if (!m_notifyTimer.isActive()) {
        m_notifyTimer.start();
    }
}

QVariantList JobServer::jobs() const {
    QVariantList list;
    list.reserve(m_items.size() + m_finishedHistory.size());

    for (const JobItem *item : m_items) {
        list.append(item->entry().toMap());
    }
    for (const JobEntry &e : m_finishedHistory) {
        list.append(e.toMap());
    }
    return list;
}

QVariantList JobServer::activeJobs() const {
    QVariantList list;
    for (const JobItem *item : m_items) {
        if (item->entry().state != JobState::Stopped) {
            list.append(item->entry().toMap());
        }
    }
    return list;
}

void JobServer::updateLauncherProgress(const QString &desktopEntry) {
    if (desktopEntry.isEmpty()) {
        return;
    }

    int count = 0;
    quint64 percentSum = 0;

    for (const JobItem *item : m_items) {
        if (item->entry().state != JobState::Stopped && item->entry().desktopEntry == desktopEntry) {
            ++count;
            percentSum += item->entry().percent;
        }
    }

    const double progress = (count > 0) ? static_cast<double>(percentSum / count) / 100.0 : 0.0;
    const QVariantMap properties = {
        {QStringLiteral("count-visible"), count > 0},
        {QStringLiteral("count"), count},
        {QStringLiteral("progress-visible"), count > 0},
        {QStringLiteral("progress"), progress},
        {QStringLiteral("proxied-for"), QStringLiteral("kuiserver")}
    };

    QDBusMessage msg = QDBusMessage::createSignal(
        QStringLiteral("/org/kde/notificationmanager/jobs"),
        QStringLiteral("com.canonical.Unity.LauncherEntry"),
        QStringLiteral("Update")
    );
    msg.setArguments({QStringLiteral("application://") + desktopEntry, properties});
    QDBusConnection::sessionBus().send(msg);
}

} // namespace qs::plugins::kuiserver
