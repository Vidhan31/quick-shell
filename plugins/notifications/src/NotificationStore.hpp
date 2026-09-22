#pragma once

#include "NotificationEntry.hpp"

#include <QObject>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins::notifications {

class NotificationModel;

// Extra logic ported from services/NotificationService.qml. Owns history,
// toasts, unread, DND, expanded groups and timeout policy. D-Bus ownership
// and live Notification objects stay in QML: the adapter forwards snapshots
// in and executes *_requested signals out.
class NotificationStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(NotificationStore)

    Q_PROPERTY(NotificationModel *historyModel READ historyModel CONSTANT)
    Q_PROPERTY(NotificationModel *toastModel READ toastModel CONSTANT)
    // Legacy-shaped maps for widgets/popups (same shape as the old QML
    // _wrapMap/_buildGrouped output, so existing Repeaters keep working).
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY listsChanged)
    Q_PROPERTY(QVariantList activeToasts READ activeToasts NOTIFY listsChanged)
    // Grouped presentation derived from history. QVariantList (not a model)
    // so existing Repeaters keep working: [{appName, appIcon, desktopEntry,
    // notifications: [...maps...], totalCount, expanded}].
    Q_PROPERTY(QVariantList groupedList READ groupedList NOTIFY groupedListChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(bool dnd READ dnd WRITE setDnd NOTIFY dndChanged)
    Q_PROPERTY(int maxNotifications READ maxNotifications WRITE setMaxNotifications NOTIFY maxNotificationsChanged)
    Q_PROPERTY(QStringList expandedGroups READ expandedGroups WRITE setExpandedGroups NOTIFY expandedGroupsChanged)

public:
    static constexpr int kMaxToasts = 10;

    // Close reasons in freedesktop order (matches QML fallback Number==1).
    static constexpr int kCloseDismissed = 0;
    static constexpr int kCloseExpired = 1;

    explicit NotificationStore(QObject *parent = nullptr);

    [[nodiscard]] NotificationModel *historyModel() const { return m_historyModel; }
    [[nodiscard]] NotificationModel *toastModel() const { return m_toastModel; }
    [[nodiscard]] QVariantList notifications() const { return m_notifications; }
    [[nodiscard]] QVariantList activeToasts() const { return m_toastList; }
    [[nodiscard]] QVariantList groupedList() const { return m_grouped; }
    [[nodiscard]] int unreadCount() const { return m_unread; }
    [[nodiscard]] int totalCount() const { return m_history.size(); }
    [[nodiscard]] bool dnd() const { return m_dnd; }
    void setDnd(bool dnd);
    [[nodiscard]] int maxNotifications() const { return m_max; }
    void setMaxNotifications(int max);
    [[nodiscard]] QStringList expandedGroups() const;
    void setExpandedGroups(const QStringList &groups);

    static int normalizeUrgency(int u) noexcept;
    static qint64 defaultTimeoutMs(int urgency) noexcept;
    static qint64 timeoutForCategory(const QString &category, int urgency);
    static QString timeAgo(const QDateTime &when);

    // Ingest a detached snapshot built by the QML adapter from the live
    // Quickshell Notification object. expireTimeoutSec: NaN/null = not set,
    // 0 = persist, >0 seconds, <0 = keep category/default.
    Q_INVOKABLE void ingestSnapshot(const QVariantMap &snap, int id, const QVariant &expireTimeoutSec, bool carried);
    // reason: 1 = expired (toast only), anything else clears both.
    Q_INVOKABLE void handleClosed(int id, int reason);
    // Safety net: drop toasts the server no longer tracks (keeps manuals).
    Q_INVOKABLE void pruneToIds(const QVariantList &liveIds);
    Q_INVOKABLE void holdToast(int id, bool held);

    Q_INVOKABLE void dismissToast(int id);
    Q_INVOKABLE void dismissNotification(int id);
    Q_INVOKABLE void clearApp(const QString &appName);
    Q_INVOKABLE void clearAll();
    Q_INVOKABLE void markAllRead();
    Q_INVOKABLE void toggleDnd();
    Q_INVOKABLE void toggleGroupExpanded(const QString &appName);
    Q_INVOKABLE bool isGroupExpanded(const QString &appName) const;
    // State mutation + request emission; QML executes the live D-Bus call.
    Q_INVOKABLE void invokeAction(int id, const QString &identifier);
    Q_INVOKABLE bool sendInlineReply(int id, const QString &text);
    Q_INVOKABLE QString timeAgoNow(const QDateTime &when) const { return timeAgo(when); }
    Q_INVOKABLE void addTestNotification(const QString &summary, const QString &body, const QString &appName = QString(),
                                         int urgency = 1);

signals:
    void groupedListChanged();
    void listsChanged();
    void unreadCountChanged();
    void totalCountChanged();
    void dndChanged();
    void maxNotificationsChanged();
    void expandedGroupsChanged();

    // Outbound D-Bus requests for the QML adapter (owns live objects).
    void dismissRequested(int id);
    void expireRequested(int id);
    void invokeRequested(int id, const QString &identifier);
    void replyRequested(int id, const QString &text);

private slots:
    void onSweepTick();
    void onTimeTick();

private:
    static NotificationEntry entryFromMap(const QVariantMap &snap, int id);
    static QVariantMap entryToMap(const NotificationEntry &e);
    void syncModels();
    void rebuildGrouped();
    void recountUnread();
    void evictOverflow();
    int findHistory(int id) const;
    int findToast(int id) const;
    static QString appNameOf(const NotificationEntry &e);

    NotificationModel *m_historyModel{nullptr};
    NotificationModel *m_toastModel{nullptr};
    QList<NotificationEntry> m_history;
    QList<NotificationEntry> m_toasts;
    QVariantList m_notifications;
    QVariantList m_toastList;
    QVariantList m_grouped;
    QSet<QString> m_expanded;
    QSet<int> m_held;
    int m_unread{0};
    bool m_dnd{false};
    int m_max{100};
    QTimer *m_sweepTimer{nullptr};
    QTimer *m_timeTimer{nullptr};
};

} // namespace qs::plugins::notifications
