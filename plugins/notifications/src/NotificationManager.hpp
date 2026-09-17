#pragma once

#include "NotificationModel.hpp"
#include "NotificationMonitor.hpp"

#include <QDBusConnection>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins::notifications {

class NotificationManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(NotificationManager)

    // Models
    Q_PROPERTY(qs::plugins::notifications::NotificationModel* model READ model CONSTANT)
    Q_PROPERTY(qs::plugins::notifications::NotificationModel* toastModel READ toastModel CONSTANT)

    // Compatibility properties matching NotificationService.qml
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(QVariantList activeToasts READ activeToasts NOTIFY activeToastsChanged)
    Q_PROPERTY(QVariantList groupedList READ groupedNotifications NOTIFY groupedNotificationsChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(bool dnd READ dnd WRITE setDnd NOTIFY dndChanged)
    Q_PROPERTY(QVariantMap expandedGroups READ expandedGroups WRITE setExpandedGroups NOTIFY expandedGroupsChanged)
    Q_PROPERTY(int timeTick READ timeTick NOTIFY timeTickChanged)
    Q_PROPERTY(int maxNotifications READ maxNotifications WRITE setMaxNotifications NOTIFY maxNotificationsChanged)

public:
    explicit NotificationManager(QObject *parent = nullptr);
    ~NotificationManager() override;

    [[nodiscard]] NotificationModel* model() const noexcept { return m_model; }
    [[nodiscard]] NotificationModel* toastModel() const noexcept { return m_toastModel; }

    [[nodiscard]] QVariantList notifications() const;
    [[nodiscard]] QVariantList activeToasts() const;
    [[nodiscard]] QVariantList groupedNotifications() const;

    [[nodiscard]] int unreadCount() const noexcept { return m_unreadCount; }
    [[nodiscard]] int totalCount() const noexcept { return m_model->rowCount(); }
    [[nodiscard]] bool dnd() const noexcept { return m_dnd; }
    void setDnd(bool dnd);

    [[nodiscard]] QVariantMap expandedGroups() const noexcept { return m_expandedGroups; }
    void setExpandedGroups(const QVariantMap &groups);

    [[nodiscard]] int timeTick() const noexcept { return m_timeTick; }
    [[nodiscard]] int maxNotifications() const noexcept { return m_maxNotifications; }
    void setMaxNotifications(int max) noexcept { m_maxNotifications = max; }

    // QML-accessible actions
    Q_INVOKABLE void dismissToast(uint32_t id);
    Q_INVOKABLE void dismissNotification(uint32_t id);
    Q_INVOKABLE void clearApp(const QString &appName);
    Q_INVOKABLE void clearAll();
    Q_INVOKABLE void markAllRead();
    Q_INVOKABLE void toggleDnd();
    Q_INVOKABLE void toggleGroupExpanded(const QString &appName);
    Q_INVOKABLE [[nodiscard]] bool isGroupExpanded(const QString &appName) const;
    Q_INVOKABLE void invokeAction(const QVariant &itemOrId, const QString &identifier);
    Q_INVOKABLE [[nodiscard]] QString timeAgo(const QVariant &dateOrTimestamp) const;
    Q_INVOKABLE [[nodiscard]] QVariantList getGroupedNotifications() const;
    Q_INVOKABLE void addManualNotification(const QString &summary,
                                           const QString &body = {},
                                           const QString &appName = {},
                                           const QString &appIcon = {},
                                           const QString &image = {},
                                           int urgency = 1,
                                           const QVariantList &actions = {});

signals:
    void notificationsChanged();
    void activeToastsChanged();
    void groupedNotificationsChanged();
    void unreadCountChanged();
    void totalCountChanged();
    void dndChanged();
    void expandedGroupsChanged();
    void timeTickChanged();
    void maxNotificationsChanged();

private slots:
    void onNotificationReceived(const qs::plugins::notifications::NotificationItem &item);
    void onNotificationClosed(uint32_t id, uint32_t reason);
    void onActionInvoked(uint32_t id, const QString &actionKey);
    void onTick();
    void onDbusPropertiesChanged(const QString &interface,
                                 const QVariantMap &changedProperties,
                                 const QStringList &invalidatedProperties);

private:
    void setupDbusSync();
    void updateCountsAndState();
    void sendDbusClose(uint32_t id);
    void sendDbusInvokeAction(uint32_t id, const QString &actionKey);

    NotificationModel *m_model{nullptr};
    NotificationModel *m_toastModel{nullptr};
    NotificationMonitor *m_monitor{nullptr};

    QTimer *m_tickTimer{nullptr};
    int m_timeTick{0};
    int m_maxNotifications{100};
    int m_unreadCount{0};
    bool m_dnd{false};
    QVariantMap m_expandedGroups;
    uint32_t m_manualIdCounter{9000};
    uint32_t m_inhibitCookie{0};

    mutable bool m_groupedCacheDirty{true};
    mutable QVariantList m_groupedCache;
};

} // namespace qs::plugins::notifications
