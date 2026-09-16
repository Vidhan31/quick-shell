pragma ComponentBehavior: Bound
// NotificationService.qml — Central manager for desktop notifications.
// Integrates D-Bus real-time monitoring bridge, Quickshell.Services.Notifications,
// notification history, DND mode, app grouping, toast queues, and action execution.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Item {
  id: root

  // Array of all stored notification objects (newest first)
  property var notifications: []

  // Array of active floating toast notifications
  property var activeToasts: []

  // Do Not Disturb mode
  property bool dnd: false

  // Dictionary tracking which app groups are expanded: { [appName: string]: bool }
  property var expandedGroups: ({})

  // Count of unread notifications
  property int unreadCount: 0

  // Maximum notifications to keep in history
  property int maxNotifications: 100

  // Default toast display timeout in milliseconds
  property int toastTimeoutMs: 5000

  // Unique ID counter
  property int _nextId: 1

  // Periodic tick for refreshing relative time strings ("1 min ago", "2h ago", etc.)
  property int timeTick: 0

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.timeTick++
  }

  // Persistent properties for DND across hot-reloads
  PersistentProperties {
    id: persist
    property bool dnd: false
    reloadableId: "notifications-state"
  }

  Component.onCompleted: {
    root.dnd = persist.dnd;
  }

  // Quickshell Notification Server (when quickshell acts as primary daemon)
  NotificationServer {
    id: server
    keepOnReload: false
    actionsSupported: true
    bodyHyperlinksSupported: true
    bodyMarkupSupported: true
    imageSupported: true
    persistenceSupported: true

    onNotification: notif => {
      notif.tracked = true;
      root.addRawNotification(notif);
    }
  }

  // Python D-Bus notification monitoring bridge process
  Process {
    id: bridgeProcess
    command: ["python3", "-u", "/home/dev/Projects/quick-shell/notification-bridge.py"]
    running: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: data => {
        const trimmed = data.trim();
        if (!trimmed || !trimmed.startsWith("{")) return;
        try {
          const obj = JSON.parse(trimmed);
          if (obj.type === "notify") {
            root.addBridgeNotification(obj);
          } else if (obj.type === "closed") {
            root.onBridgeNotificationClosed(obj.id);
          }
        } catch (e) {
          console.warn("NotificationService: parse error:", e);
        }
      }
    }

    onRunningChanged: {
      if (!running) {
        restartTimer.start();
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: bridgeProcess.running = true
  }

  // Convert raw Quickshell NotificationAction list to plain JS array
  function _parseActions(rawActions) {
    const list = [];
    if (!rawActions) return list;
    const len = (rawActions.length !== undefined) ? rawActions.length : (rawActions.count || 0);
    for (let i = 0; i < len; i++) {
      const act = rawActions[i];
      if (act) {
        list.push({
          identifier: act.identifier || `${i}`,
          text: act.text || act.identifier || "Action",
          rawAction: act
        });
      }
    }
    return list;
  }

  // Add notification captured via Python D-Bus bridge
  function addBridgeNotification(data) {
    if (!data) return;

    const notifNumId = (data.id !== undefined && data.id !== null) ? data.id : root._nextId++;

    // Check if notification already exists (deduplication)
    const existingIndex = root.notifications.findIndex(n => n.id === notifNumId || (n.summary === data.summary && n.body === data.body && (Date.now() - n.timestamp.getTime()) < 1000));
    
    const actionsList = (data.actions || []).map(a => ({
      identifier: a.identifier || "action",
      text: a.text || a.identifier || "Action",
      rawAction: null
    }));

    const item = {
      id: notifNumId,
      notifId: `${notifNumId}`,
      appName: (data.appName && data.appName.trim().length > 0) ? data.appName : "Application",
      appIcon: data.appIcon || "",
      summary: (data.summary && data.summary.trim().length > 0) ? data.summary : "Notification",
      body: data.body || "",
      image: data.image || "",
      urgency: (data.urgency !== undefined) ? data.urgency : 1,
      actions: actionsList,
      timestamp: new Date(data.timestamp || Date.now()),
      read: false,
      rawNotif: null,
      isBridge: true
    };

    let updated;
    if (existingIndex >= 0) {
      updated = [...root.notifications];
      updated[existingIndex] = item;
    } else {
      updated = [item, ...root.notifications];
    }

    root.notifications = updated.slice(0, root.maxNotifications);
    root.unreadCount = root.notifications.filter(n => !n.read).length;

    // Trigger toast popup if DND is false or notification is Critical (urgency 2)
    if (!root.dnd || item.urgency === 2) {
      const toastList = root.activeToasts.filter(t => t.id !== item.id);
      root.activeToasts = [item, ...toastList];
    }
  }

  function onBridgeNotificationClosed(id) {
    // Dismiss toast if closed externally
    root.activeToasts = root.activeToasts.filter(t => t.id !== id);
  }

  // Add notification from Quickshell native NotificationServer
  function addRawNotification(notif) {
    if (!notif) return;

    const id = root._nextId++;
    const actionsList = root._parseActions(notif.actions);

    const item = {
      id: id,
      notifId: `${notif.id}`,
      appName: (notif.appName && notif.appName.trim().length > 0) ? notif.appName : "Application",
      appIcon: notif.appIcon || "",
      summary: (notif.summary && notif.summary.trim().length > 0) ? notif.summary : "Notification",
      body: notif.body || "",
      image: notif.image || "",
      urgency: (notif.urgency !== undefined) ? notif.urgency : 1,
      actions: actionsList,
      timestamp: new Date(),
      read: false,
      rawNotif: notif,
      isBridge: false
    };

    const updated = [item, ...root.notifications];
    root.notifications = updated.slice(0, root.maxNotifications);
    root.unreadCount = root.notifications.filter(n => !n.read).length;

    if (!root.dnd || item.urgency === 2) {
      root.activeToasts = [item, ...root.activeToasts];
    }
  }

  // Add manual notification (for scripts, inotify triggers, testing)
  function addManualNotification(summary, body, appName, appIcon, image, urgency, actions) {
    const id = root._nextId++;
    const item = {
      id: id,
      notifId: `manual-${id}`,
      appName: (appName && appName.trim().length > 0) ? appName : "Application",
      appIcon: appIcon || "",
      summary: (summary && summary.trim().length > 0) ? summary : "Notification",
      body: body || "",
      image: image || "",
      urgency: (urgency !== undefined) ? urgency : 1,
      actions: actions || [],
      timestamp: new Date(),
      read: false,
      rawNotif: null,
      isBridge: false
    };

    root.notifications = [item, ...root.notifications].slice(0, root.maxNotifications);
    root.unreadCount = root.notifications.filter(n => !n.read).length;

    if (!root.dnd || item.urgency === 2) {
      root.activeToasts = [item, ...root.activeToasts];
    }
  }

  // Dismiss a floating toast (keeps it in notification history)
  function dismissToast(id) {
    root.activeToasts = root.activeToasts.filter(t => t.id !== id);
  }

  // Dismiss / delete a single notification permanently
  function dismissNotification(id) {
    const item = root.notifications.find(n => n.id === id);
    if (item && item.rawNotif) {
      try { item.rawNotif.dismiss(); } catch (e) {}
    }

    // Instant pure JS state update
    root.notifications = root.notifications.filter(n => n.id !== id);
    root.activeToasts = root.activeToasts.filter(t => t.id !== id);
    root.unreadCount = root.notifications.filter(n => !n.read).length;
  }

  // Clear all notifications for a specific app
  function clearApp(appName) {
    const appItems = root.notifications.filter(n => n.appName === appName);
    for (let i = 0; i < appItems.length; i++) {
      if (appItems[i].rawNotif) {
        try { appItems[i].rawNotif.dismiss(); } catch (e) {}
      }
    }
    
    root.notifications = root.notifications.filter(n => n.appName !== appName);
    root.activeToasts = root.activeToasts.filter(t => t.appName !== appName);
    root.unreadCount = root.notifications.filter(n => !n.read).length;
  }

  // Clear all notifications
  function clearAll() {
    for (let i = 0; i < root.notifications.length; i++) {
      if (root.notifications[i].rawNotif) {
        try { root.notifications[i].rawNotif.dismiss(); } catch (e) {}
      }
    }
    root.notifications = [];
    root.activeToasts = [];
    root.unreadCount = 0;
  }

  // Mark all notifications as read
  function markAllRead() {
    const list = root.notifications.map(n => {
      n.read = true;
      return n;
    });
    root.notifications = list;
    root.unreadCount = 0;
  }

  // Toggle Do Not Disturb
  function toggleDnd() {
    root.dnd = !root.dnd;
    persist.dnd = root.dnd;
    if (root.dnd) {
      // Clear non-critical active toasts
      root.activeToasts = root.activeToasts.filter(t => t.urgency === 2);
    }
  }

  // Toggle group expansion state
  function toggleGroupExpanded(appName) {
    const copy = Object.assign({}, root.expandedGroups);
    copy[appName] = !copy[appName];
    root.expandedGroups = copy;
  }

  // Check if a group is expanded
  function isGroupExpanded(appName) {
    return !!root.expandedGroups[appName];
  }

  // Execute a notification action
  function invokeAction(item, identifier) {
    if (!item) return;
    if (item.rawNotif && item.actions) {
      const act = item.actions.find(a => a.identifier === identifier);
      if (act && act.rawAction && typeof act.rawAction.invoke === "function") {
        try { act.rawAction.invoke(); } catch (e) {}
      }
    }
    dismissNotification(item.id);
  }

  // Format relative timestamp ("Just now", "1 min ago", "6 min ago", "2h ago", "1d ago")
  function timeAgo(date) {
    if (!date) return "Just now";
    const ts = (typeof date === "number") ? date : date.getTime();
    const diff = Math.max(0, Date.now() - ts);
    const secs = Math.floor(diff / 1000);
    const mins = Math.floor(secs / 60);
    const hrs = Math.floor(mins / 60);
    const days = Math.floor(hrs / 24);

    if (secs < 45) return "Just now";
    if (mins < 60) return `${mins} min${mins === 1 ? "" : "s"} ago`;
    if (hrs < 24) return `${hrs} hr${hrs === 1 ? "" : "s"} ago`;
    if (days < 7) return `${days} day${days === 1 ? "" : "s"} ago`;
    return Qt.formatDate(new Date(ts), "MMM d");
  }

  // Group notifications by appName for Plasma 6 styled cards
  function getGroupedNotifications() {
    const list = root.notifications;
    const groupsMap = {};
    const groupOrder = [];

    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      const key = item.appName || "Application";
      if (!groupsMap[key]) {
        groupsMap[key] = {
          appName: key,
          appIcon: item.appIcon || "",
          notifications: [],
          totalCount: 0,
          expanded: !!root.expandedGroups[key]
        };
        groupOrder.push(key);
      }
      if (!groupsMap[key].appIcon && item.appIcon) {
        groupsMap[key].appIcon = item.appIcon;
      }
      groupsMap[key].notifications.push(item);
      groupsMap[key].totalCount++;
    }

    const result = [];
    for (let i = 0; i < groupOrder.length; i++) {
      const g = groupsMap[groupOrder[i]];
      g.expanded = !!root.expandedGroups[g.appName];
      result.push(g);
    }
    return result;
  }
}
