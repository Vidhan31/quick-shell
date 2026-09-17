#include "NotificationManager.hpp"

#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDebug>

namespace qs::plugins::notifications {

NotificationManager::NotificationManager(QObject *parent)
    : QObject(parent)
    , m_model(new NotificationModel(this))
    , m_toastModel(new NotificationModel(this))
    , m_monitor(new NotificationMonitor(this))
    , m_tickTimer(new QTimer(this))
{
    connect(m_monitor, &NotificationMonitor::notificationReceived,
            this, &NotificationManager::onNotificationReceived);
    connect(m_monitor, &NotificationMonitor::notificationClosed,
            this, &NotificationManager::onNotificationClosed);
    connect(m_monitor, &NotificationMonitor::actionInvoked,
            this, &NotificationManager::onActionInvoked);

    connect(m_model, &NotificationModel::itemAdded, this, [this](uint32_t) {
        m_groupedCacheDirty = true;
        updateCountsAndState();
    });
    connect(m_model, &NotificationModel::itemRemoved, this, [this](uint32_t) {
        m_groupedCacheDirty = true;
        updateCountsAndState();
    });

    connect(m_tickTimer, &QTimer::timeout, this, &NotificationManager::onTick);
    m_tickTimer->start(10000);

    setupDbusSync();
    m_monitor->start();
}

NotificationManager::~NotificationManager() {
    if (m_monitor) {
        m_monitor->stop();
    }
}

void NotificationManager::setupDbusSync() {
    // Connect to PropertiesChanged on org.freedesktop.Notifications for DND sync
    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onDbusPropertiesChanged(QString,QVariantMap,QStringList)));

    // Query initial Inhibited property
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Get"));
    msg << QStringLiteral("org.freedesktop.Notifications") << QStringLiteral("Inhibited");

    QDBusPendingCall pcall = QDBusConnection::sessionBus().asyncCall(msg);
    auto *watcher = new QDBusPendingCallWatcher(pcall, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QDBusVariant> reply = *w;
        if (reply.isValid()) {
            bool currentInhibited = reply.value().variant().toBool();
            if (m_dnd != currentInhibited) {
                m_dnd = currentInhibited;
                emit dndChanged();
            }
        }
        w->deleteLater();
    });
}

void NotificationManager::onDbusPropertiesChanged(const QString &interface,
                                                 const QVariantMap &changedProperties,
                                                 const QStringList &) {
    if (interface == QLatin1String("org.freedesktop.Notifications")) {
        auto it = changedProperties.constFind(QStringLiteral("Inhibited"));
        if (it != changedProperties.constEnd()) {
            bool newDnd = it.value().toBool();
            if (m_dnd != newDnd) {
                m_dnd = newDnd;
                emit dndChanged();
                if (m_dnd) {
                    // Dismiss non-critical toasts
                    const auto items = m_toastModel->items();
                    for (const auto &item : items) {
                        if (item.urgency < 2) {
                            m_toastModel->removeById(item.id);
                        }
                    }
                    emit activeToastsChanged();
                }
            }
        }
    }
}

void NotificationManager::onNotificationReceived(const NotificationItem &item) {
    m_model->addOrUpdate(item, m_maxNotifications);

    // Toast is added if DND is off or urgency is Critical (2)
    if (!m_dnd || item.urgency == 2) {
        m_toastModel->addOrUpdate(item, 10);
        emit activeToastsChanged();
    }

    m_groupedCacheDirty = true;
    updateCountsAndState();
    emit notificationsChanged();
    emit groupedNotificationsChanged();
}

void NotificationManager::onNotificationClosed(uint32_t id, uint32_t) {
    if (m_toastModel->removeById(id)) {
        emit activeToastsChanged();
    }
}

void NotificationManager::onActionInvoked(uint32_t id, const QString &actionKey) {
    Q_UNUSED(actionKey);
    dismissToast(id);
}

void NotificationManager::onTick() {
    ++m_timeTick;
    m_model->updateRelativeTimes();
    m_toastModel->updateRelativeTimes();
    emit timeTickChanged();
}

void NotificationManager::updateCountsAndState() {
    int unread = m_model->unreadCount();
    if (m_unreadCount != unread) {
        m_unreadCount = unread;
        emit unreadCountChanged();
    }
    emit totalCountChanged();
}

QVariantList NotificationManager::notifications() const {
    return m_model->toVariantList();
}

QVariantList NotificationManager::activeToasts() const {
    return m_toastModel->toVariantList();
}

QVariantList NotificationManager::groupedNotifications() const {
    return getGroupedNotifications();
}

QVariantList NotificationManager::getGroupedNotifications() const {
    if (!m_groupedCacheDirty) {
        return m_groupedCache;
    }

    const auto &list = m_model->items();
    struct Group {
        QString appName;
        QString appIcon;
        QVariantList notifications;
        int totalCount{0};
    };

    QList<QString> groupOrder;
    QHash<QString, Group> groupsMap;

    for (const auto &item : list) {
        QString key = item.appName.trimmed().isEmpty() ? QStringLiteral("Application") : item.appName;
        auto it = groupsMap.find(key);
        if (it == groupsMap.end()) {
            groupOrder.append(key);
            Group g;
            g.appName = key;
            g.appIcon = item.appIcon;
            g.notifications.append(item.toMap());
            g.totalCount = 1;
            groupsMap.insert(key, g);
        } else {
            if (it->appIcon.isEmpty() && !item.appIcon.isEmpty()) {
                it->appIcon = item.appIcon;
            }
            it->notifications.append(item.toMap());
            it->totalCount++;
        }
    }

    m_groupedCache.clear();
    m_groupedCache.reserve(groupOrder.size());

    for (const auto &key : groupOrder) {
        const auto &g = groupsMap[key];
        bool expanded = isGroupExpanded(g.appName);
        QVariantMap map{
            {QStringLiteral("appName"), g.appName},
            {QStringLiteral("appIcon"), g.appIcon},
            {QStringLiteral("notifications"), g.notifications},
            {QStringLiteral("totalCount"), g.totalCount},
            {QStringLiteral("expanded"), expanded}
        };
        m_groupedCache.append(map);
    }

    m_groupedCacheDirty = false;
    return m_groupedCache;
}

void NotificationManager::setDnd(bool dnd) {
    if (m_dnd == dnd) return;
    m_dnd = dnd;
    emit dndChanged();

    if (m_dnd) {
        const auto items = m_toastModel->items();
        for (const auto &item : items) {
            if (item.urgency < 2) {
                m_toastModel->removeById(item.id);
            }
        }
        emit activeToastsChanged();
    }

    // Call KDE Plasma Inhibit/UnInhibit to sync system DND
    if (m_dnd) {
        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("Inhibit"));
        QVariantMap hints;
        hints.insert(QStringLiteral("reason"), QStringLiteral("Quickshell DND"));
        msg << QStringLiteral("Quickshell") << QStringLiteral("Do Not Disturb") << hints;
        QDBusPendingReply<uint32_t> reply = QDBusConnection::sessionBus().asyncCall(msg);
        auto *watcher = new QDBusPendingCallWatcher(reply, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
            QDBusPendingReply<uint32_t> r = *w;
            if (r.isValid()) {
                m_inhibitCookie = r.value();
            }
            w->deleteLater();
        });
    } else {
        if (m_inhibitCookie > 0) {
            QDBusMessage msg = QDBusMessage::createMethodCall(
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("/org/freedesktop/Notifications"),
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("UnInhibit"));
            msg << m_inhibitCookie;
            QDBusConnection::sessionBus().send(msg);
            m_inhibitCookie = 0;
        }
    }
}

void NotificationManager::setExpandedGroups(const QVariantMap &groups) {
    m_expandedGroups = groups;
    m_groupedCacheDirty = true;
    emit expandedGroupsChanged();
    emit groupedNotificationsChanged();
}

void NotificationManager::dismissToast(uint32_t id) {
    if (m_toastModel->removeById(id)) {
        emit activeToastsChanged();
    }
}

void NotificationManager::dismissNotification(uint32_t id) {
    m_toastModel->removeById(id);
    m_model->removeById(id);
    sendDbusClose(id);

    m_groupedCacheDirty = true;
    updateCountsAndState();
    emit notificationsChanged();
    emit activeToastsChanged();
    emit groupedNotificationsChanged();
}

void NotificationManager::clearApp(const QString &appName) {
    const auto &items = m_model->items();
    for (const auto &item : items) {
        if (item.appName == appName) {
            sendDbusClose(item.id);
        }
    }

    m_toastModel->removeByAppName(appName);
    m_model->removeByAppName(appName);

    m_groupedCacheDirty = true;
    updateCountsAndState();
    emit notificationsChanged();
    emit activeToastsChanged();
    emit groupedNotificationsChanged();
}

void NotificationManager::clearAll() {
    const auto &items = m_model->items();
    for (const auto &item : items) {
        sendDbusClose(item.id);
    }

    m_toastModel->clear();
    m_model->clear();

    m_groupedCacheDirty = true;
    updateCountsAndState();
    emit notificationsChanged();
    emit activeToastsChanged();
    emit groupedNotificationsChanged();
}

void NotificationManager::markAllRead() {
    m_model->markAllRead();
    m_unreadCount = 0;
    m_groupedCacheDirty = true;
    emit unreadCountChanged();
    emit notificationsChanged();
    emit groupedNotificationsChanged();
}

void NotificationManager::toggleDnd() {
    setDnd(!m_dnd);
}

void NotificationManager::toggleGroupExpanded(const QString &appName) {
    bool current = isGroupExpanded(appName);
    m_expandedGroups[appName] = !current;
    m_groupedCacheDirty = true;
    emit expandedGroupsChanged();
    emit groupedNotificationsChanged();
}

bool NotificationManager::isGroupExpanded(const QString &appName) const {
    return m_expandedGroups.value(appName, false).toBool();
}

void NotificationManager::invokeAction(const QVariant &itemOrId, const QString &identifier) {
    uint32_t notifId = 0;
    if (itemOrId.canConvert<uint32_t>()) {
        notifId = itemOrId.value<uint32_t>();
    } else if (itemOrId.canConvert<QVariantMap>()) {
        QVariantMap map = itemOrId.toMap();
        notifId = map.value(QStringLiteral("id")).toUInt();
    }

    if (notifId > 0 && !identifier.isEmpty()) {
        sendDbusInvokeAction(notifId, identifier);
    }
    dismissNotification(notifId);
}

void NotificationManager::sendDbusClose(uint32_t id) {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("CloseNotification"));
    msg << id;
    QDBusConnection::sessionBus().send(msg);
}

void NotificationManager::sendDbusInvokeAction(uint32_t id, const QString &actionKey) {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.kde.NotificationManager"),
        QStringLiteral("InvokeAction"));
    msg << id << actionKey;
    QDBusConnection::sessionBus().send(msg);
}

QString NotificationManager::timeAgo(const QVariant &dateOrTimestamp) const {
    if (!dateOrTimestamp.isValid()) return QStringLiteral("Just now");

    qint64 diffMs = 0;
    if (dateOrTimestamp.canConvert<QDateTime>()) {
        QDateTime dt = dateOrTimestamp.toDateTime();
        if (dt.isValid()) {
            diffMs = std::max<qint64>(0, dt.msecsTo(QDateTime::currentDateTime()));
        }
    } else if (dateOrTimestamp.canConvert<qint64>()) {
        qint64 ts = dateOrTimestamp.toLongLong();
        diffMs = std::max<qint64>(0, QDateTime::currentMSecsSinceEpoch() - ts);
    } else {
        return QStringLiteral("Just now");
    }

    qint64 secs = diffMs / 1000;
    qint64 mins = secs / 60;
    qint64 hrs = mins / 60;
    qint64 days = hrs / 24;

    if (secs < 45) return QStringLiteral("Just now");
    if (mins < 60) {
        return QStringLiteral("%1 min%2 ago")
            .arg(mins)
            .arg(mins == 1 ? QString() : QStringLiteral("s"));
    }
    if (hrs < 24) {
        return QStringLiteral("%1 hr%2 ago")
            .arg(hrs)
            .arg(hrs == 1 ? QString() : QStringLiteral("s"));
    }
    if (days < 7) {
        return QStringLiteral("%1 day%2 ago")
            .arg(days)
            .arg(days == 1 ? QString() : QStringLiteral("s"));
    }
    return QDateTime::fromMSecsSinceEpoch(QDateTime::currentMSecsSinceEpoch() - diffMs).toString(QStringLiteral("MMM d"));
}

void NotificationManager::addManualNotification(const QString &summary,
                                               const QString &body,
                                               const QString &appName,
                                               const QString &appIcon,
                                               const QString &image,
                                               int urgency,
                                               const QVariantList &actions) {
    NotificationItem item;
    item.id = ++m_manualIdCounter;
    item.notifId = QString::number(item.id);
    item.summary = summary.isEmpty() ? QStringLiteral("Notification") : summary;
    item.body = body;
    item.appName = appName.isEmpty() ? QStringLiteral("Application") : appName;
    item.appIcon = appIcon;
    item.image = image;
    item.urgency = std::clamp(urgency, 0, 2);
    item.timestamp = QDateTime::currentDateTime();
    item.read = false;
    item.timeout = item.urgency == 2 ? 10000 : (item.urgency == 0 ? 3500 : 5000);

    for (const auto &actVar : actions) {
        if (actVar.canConvert<QVariantMap>()) {
            QVariantMap m = actVar.toMap();
            item.actions.append(NotificationAction{
                m.value(QStringLiteral("identifier")).toString(),
                m.value(QStringLiteral("text")).toString()
            });
        }
    }

    onNotificationReceived(item);
}

} // namespace qs::plugins::notifications
