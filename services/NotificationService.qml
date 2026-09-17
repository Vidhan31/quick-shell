pragma ComponentBehavior: Bound
// NotificationService.qml — Central manager for desktop notifications.
// Backed by native C++ Qt6 plugin (Quickshell.Plugins.Notifications).
import QtQuick
import Quickshell
import Quickshell.Plugins.Notifications

Item {
  id: root

  NotificationManager {
    id: manager
  }

  // Native C++ QAbstractListModels
  readonly property alias model: manager.model
  readonly property alias toastModel: manager.toastModel

  // Compatibility properties for QML bindings
  readonly property alias notifications: manager.notifications
  readonly property alias activeToasts: manager.activeToasts
  readonly property alias groupedList: manager.groupedList
  readonly property alias unreadCount: manager.unreadCount
  readonly property alias totalCount: manager.totalCount
  property alias dnd: manager.dnd
  property alias expandedGroups: manager.expandedGroups
  readonly property alias timeTick: manager.timeTick
  property alias maxNotifications: manager.maxNotifications

  // Persistent properties for DND across hot-reloads
  PersistentProperties {
    id: persist
    property bool dnd: false
    reloadableId: "notifications-state"
  }

  Component.onCompleted: {
    if (persist.dnd) {
      manager.dnd = true;
    }
  }

  Connections {
    target: manager
    function onDndChanged() {
      persist.dnd = manager.dnd;
    }
  }

  // Delegated methods
  function dismissToast(id) {
    manager.dismissToast(id);
  }

  function dismissNotification(id) {
    manager.dismissNotification(id);
  }

  function clearApp(appName) {
    manager.clearApp(appName);
  }

  function clearAll() {
    manager.clearAll();
  }

  function markAllRead() {
    manager.markAllRead();
  }

  function toggleDnd() {
    manager.toggleDnd();
  }

  function toggleGroupExpanded(appName) {
    manager.toggleGroupExpanded(appName);
  }

  function isGroupExpanded(appName) {
    return manager.isGroupExpanded(appName);
  }

  function invokeAction(itemOrId, identifier) {
    manager.invokeAction(itemOrId, identifier);
  }

  function timeAgo(date) {
    return manager.timeAgo(date);
  }

  function getGroupedNotifications() {
    return manager.getGroupedNotifications();
  }

  function addManualNotification(summary, body, appName, appIcon, image, urgency, actions) {
    manager.addManualNotification(summary, body, appName, appIcon, image, urgency, actions);
  }
}
