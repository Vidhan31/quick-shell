pragma ComponentBehavior: Bound
// NotificationService.qml — Thin wiring over Quickshell NotificationServer.
//
// Backend: Quickshell NotificationServer (Quickshell.Services.Notifications),
// sole owner of org.freedesktop.Notifications. All policy/state (history,
// toasts, grouping, unread, DND, timeouts, expiry sweeps, relative times)
// lives in the C++ NotificationStore (Quickshell.Plugins.Notifications).
// This file only: owns the server + live Notification objects, forwards
// detached snapshots in, and executes the store's D-Bus request signals out.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Plugins.Notifications

Item {
  id: root

  // True = own org.freedesktop.Notifications. Flip off to hand it back.
  property bool takeoverEnabled: true
  // Extra capability hints advertised to clients (NotificationServer.extraHints).
  property var extraHints: []

  NotificationStore {
    id: store
    maxNotifications: 100
    onDismissRequested: id => root._execDismiss(id)
    onExpireRequested: id => root._execExpire(id)
    onInvokeRequested: (id, identifier) => root._execInvoke(id, identifier)
    onReplyRequested: (id, text) => root._execReply(id, text)
  }

  // Live QS Notification objects owned here. The store only holds detached
  // snapshots; dead refs are pruned via _gcLive().
  property var _live: ({})

  // Public read API (stable for widgets/popups)
  readonly property var notifications: store.notifications
  readonly property var activeToasts: store.activeToasts
  readonly property var groupedList: store.groupedList
  readonly property int unreadCount: store.unreadCount
  readonly property int totalCount: store.totalCount
  // Compat: relative-time refresh is now driven by the store's 10s tick.
  readonly property int timeTick: 0
  property alias dnd: store.dnd
  property alias maxNotifications: store.maxNotifications
  property alias expandedGroups: store.expandedGroups

  // Takeover server: created/destroyed via Loader (no active flag).
  Loader {
    id: qsLoader
    active: root.takeoverEnabled
    sourceComponent: qsServerComponent
    onLoaded: root._reconcileTracked()
  }

  Component {
    id: qsServerComponent
    NotificationServer {
      id: qsServer
      actionsSupported: true
      actionIconsSupported: true
      bodySupported: true
      bodyMarkupSupported: true
      bodyHyperlinksSupported: true
      bodyImagesSupported: true
      imageSupported: true
      persistenceSupported: true
      inlineReplySupported: true
      extraHints: root.extraHints
      keepOnReload: true
      onNotification: n => root._onQsNotification(n)
    }
  }

  // Persistent flags across hot-reloads
  PersistentProperties {
    id: persist
    property bool dnd: false
    property bool takeoverEnabled: true
    reloadableId: "notifications-state"
  }

  Component.onCompleted: {
    root.takeoverEnabled = persist.takeoverEnabled;
    store.dnd = persist.dnd;
  }

  onTakeoverEnabledChanged: {
    persist.takeoverEnabled = root.takeoverEnabled;
    if (!root.takeoverEnabled) {
      // Store emits dismissRequested per id; _exec* uses the live map,
      // so clear the store first, then drop stragglers.
      store.clearAll();
      root._live = {};
    } else {
      root._reconcileTracked();
    }
  }

  onDndChanged: {
    persist.dnd = root.dnd;
  }

  // ================= Snapshot (wiring): live object -> plain map ==========

  function _snapshotOf(n) {
    const acts = [];
    try {
      if (n.actions) {
        for (let i = 0; i < n.actions.length; i++) {
          const a = n.actions[i];
          acts.push({ identifier: a.identifier, text: a.text || a.identifier });
        }
      }
    } catch (e) {}
    let hints = {};
    try { if (n.hints) hints = n.hints; } catch (e) {}
    let hasInline = false;
    let inlinePh = "";
    let hasActIcons = false;
    try { hasInline = n.hasInlineReply === true; } catch (e) {}
    try { inlinePh = n.inlineReplyPlaceholder || ""; } catch (e) {}
    try { hasActIcons = n.hasActionIcons === true; } catch (e) {}
    let urg = 1;
    try {
      const v = Number(n.urgency);
      if (v === 0 || v === 1 || v === 2)
        urg = v;
    } catch (e) {}
    return {
      appName: n.appName || "Application",
      appIcon: n.appIcon || "",
      summary: n.summary || "Notification",
      body: n.body || "",
      image: n.image || "",
      desktopEntry: n.desktopEntry || "",
      urgency: urg,
      actions: acts,
      resident: n.resident === true,
      transient: n.transient === true,
      hasInlineReply: hasInline,
      inlineReplyPlaceholder: inlinePh,
      hasActionIcons: hasActIcons,
      category: (hints["category"] || hints["Category"] || ""),
      soundName: (hints["sound-name"] || ""),
      soundFile: (hints["sound-file"] || ""),
      suppressSound: (hints["suppress-sound"] === true)
    };
  }

  function _onQsNotification(n) {
    // Carried over from pre-reload generation: keep in history, no toast/unread.
    const carried = n.lastGeneration === true;
    n.tracked = true;
    // Hook close BEFORE any dismiss can happen.
    try {
      n.closed.connect(reason => root._onQsClosed(n.id, reason));
    } catch (e) {}
    let exp;
    try { exp = n.expireTimeout; } catch (e) {}
    const live = root._live;
    live[n.id] = n;
    root._live = live;
    store.ingestSnapshot(root._snapshotOf(n), n.id, exp, carried);
    root._gcLive();
  }

  function _onQsClosed(notifId, reason) {
    let r = 0;
    try { r = Number(reason); } catch (e) {}
    // Server-side object is gone either way; the store decides what persists.
    const live = root._live;
    delete live[Number(notifId)];
    root._live = live;
    store.handleClosed(Number(notifId), r);
    root._gcLive();
  }

  // Reconcile against the canonical server model (missed signals safety net).
  function _reconcileTracked() {
    try {
      const srv = qsLoader.item;
      if (!srv || !srv.trackedNotifications)
        return;
      const count = srv.trackedNotifications.count || 0;
      const ids = [];
      for (let i = 0; i < count; i++) {
        try {
          const n = srv.trackedNotifications.get(i);
          if (n)
            ids.push(n.id);
        } catch (e) {}
      }
      store.pruneToIds(ids);
      root._gcLive();
    } catch (e) {}
  }

  function _gcLive() {
    try {
      const keep = {};
      const lists = [store.notifications, store.activeToasts];
      for (let li = 0; li < lists.length; li++) {
        const arr = lists[li] || [];
        for (let i = 0; i < arr.length; i++)
          keep[arr[i].id] = true;
      }
      const live = root._live;
      for (const k in live) {
        if (!keep[k])
          delete live[k];
      }
      root._live = live;
    } catch (e) {}
  }

  // ================= Store -> D-Bus (live objects owned here) =============

  function _execDismiss(id) {
    const n = root._live[Number(id)];
    if (!n)
      return;
    try { n.dismiss(); } catch (e) {}
  }

  function _execExpire(id) {
    const n = root._live[Number(id)];
    if (!n)
      return;
    try { n.expire(); } catch (e) {}
  }

  function _execInvoke(id, identifier) {
    const n = root._live[Number(id)];
    if (!n)
      return;
    try {
      let done = false;
      if (n.actions) {
        for (let i = 0; i < n.actions.length; i++) {
          if (n.actions[i].identifier === identifier) {
            n.actions[i].invoke();
            done = true;
            break;
          }
        }
      }
      if (!done)
        n.dismiss();
    } catch (e) {
      try { n.dismiss(); } catch (e2) {}
    }
  }

  function _execReply(id, text) {
    const n = root._live[Number(id)];
    if (!n)
      return;
    try { n.sendInlineReply(text); } catch (e) {}
  }

  // ================= Public API (stable for widgets/popups) ===============

  function _normId(itemOrId) {
    if (typeof itemOrId === "number")
      return itemOrId;
    if (itemOrId && itemOrId.id !== undefined)
      return Number(itemOrId.id);
    return 0;
  }

  function dismissToast(id) {
    store.dismissToast(Number(id));
  }

  function dismissNotification(id) {
    store.dismissNotification(Number(id));
  }

  function clearApp(appName) {
    store.clearApp(appName);
  }

  function clearAll() {
    store.clearAll();
  }

  function markAllRead() {
    store.markAllRead();
  }

  function toggleDnd() {
    store.toggleDnd();
  }

  function toggleGroupExpanded(appName) {
    store.toggleGroupExpanded(appName);
  }

  function isGroupExpanded(appName) {
    return store.isGroupExpanded(appName);
  }

  function invokeAction(itemOrId, identifier) {
    store.invokeAction(root._normId(itemOrId), identifier);
  }

  function sendInlineReply(itemOrId, text) {
    return store.sendInlineReply(root._normId(itemOrId), String(text || ""));
  }

  function timeAgo(date) {
    try {
      let ms = 0;
      if (date instanceof Date) {
        ms = Math.max(0, Date.now() - date.getTime());
      } else if (typeof date === "number") {
        ms = Math.max(0, Date.now() - date);
      } else {
        return "Just now";
      }
      const secs = Math.floor(ms / 1000);
      const mins = Math.floor(secs / 60);
      const hrs = Math.floor(mins / 60);
      const days = Math.floor(hrs / 24);
      if (secs < 45)
        return "Just now";
      if (mins < 60)
        return mins + (mins === 1 ? " min ago" : " mins ago");
      if (hrs < 24)
        return hrs + (hrs === 1 ? " hr ago" : " hrs ago");
      if (days < 7)
        return days + (days === 1 ? " day ago" : " days ago");
      return Qt.formatDate(new Date(Date.now() - ms), "MMM d");
    } catch (e) {
      return "Just now";
    }
  }

  function getGroupedNotifications() {
    return root.groupedList;
  }

  // Local test hook (no D-Bus involved). Note: icon/image/actions/opts from
  // the old hook are not carried over; extend NotificationStore if needed.
  function addManualNotification(summary, body, appName, appIcon, image, urgency, actions, opts) {
    store.addTestNotification(summary || "Notification", body || "", appName || "Application", Number(urgency) || 1);
  }
}
