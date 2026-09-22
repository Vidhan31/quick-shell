pragma ComponentBehavior: Bound
// NotificationService.qml — Central manager for desktop notifications.
//
// Backend: Quickshell 0.3.1 NotificationServer
// (Quickshell.Services.Notifications), sole owner of
// org.freedesktop.Notifications. QML-only: history, toasts, grouping,
// unread, DND (local-only) and relative times are all JS state fed by the
// server's `notification` signal / `closed` signal.
// `takeoverEnabled` (persisted) creates/destroys the server for on-demand
// testing — when off, Plasma reclaims the bus name.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Item {
  id: root

  // True = own org.freedesktop.Notifications. Flip off to hand it back.
  property bool takeoverEnabled: true

  // Local-only Do-Not-Disturb (no Plasma Inhibit sync).
  property bool dnd: false
  property var expandedGroups: ({})
  property int maxNotifications: 100
  // Extra capability hints advertised to clients (NotificationServer.extraHints).
  property var extraHints: []

  // Stores. History entry: { notif, id, receivedAt: Date, read: bool,
  //   expiresAt: ms|Infinity, timeoutMs, _manual?: bool }
  property var _history: []
  property var _toasts: []
  property int _qsUnread: 0
  property int _timeTickLocal: 0

  // Legacy-shaped maps for widgets/popups (maps, not live objects).
  property var _historyMaps: []
  property var _toastMaps: []
  property var _groupedCache: []

  // Public read API (stable for widgets/popups)
  readonly property var notifications: root._historyMaps
  readonly property var activeToasts: root._toastMaps
  readonly property var groupedList: root._groupedCache
  readonly property int unreadCount: root._qsUnread
  readonly property int totalCount: root._history.length
  readonly property int timeTick: root._timeTickLocal

  // Takeover server: created/destroyed via Loader (0.3.1 has no active flag).
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
    root.dnd = persist.dnd;
  }

  onTakeoverEnabledChanged: {
    persist.takeoverEnabled = root.takeoverEnabled;
    if (!root.takeoverEnabled)
      root._clearQsState();
    else
      root._rebuildQsMaps();
  }

  onDndChanged: {
    persist.dnd = root.dnd;
    if (root.dnd) {
      // DND on: drop non-critical toasts (critical still shows)
      root._toasts = root._toasts.filter(w => (w.snap ? w.snap.urgency : root._urgencyNum(w.notif)) === 2);
      root._rebuildQsMaps();
    }
  }

  onExpandedGroupsChanged: root._rebuildQsMaps()
  onMaxNotificationsChanged: root._evictQsOverflow()

  // Local 10s ticker for timeAgo refresh
  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: {
      root._timeTickLocal++;
      root._reconcileTracked();
      root._rebuildQsMaps();
    }
  }

  // 1s sweeper: expire toasts whose expiresAt passed
  Timer {
    interval: 1000
    running: root.takeoverEnabled && root._toasts.length > 0
    repeat: true
    onTriggered: {
      const now = Date.now();
      let changed = false;
      const keep = [];
      for (let i = 0; i < root._toasts.length; i++) {
        const w = root._toasts[i];
        if (w.expiresAt !== Infinity && now >= w.expiresAt) {
          try { w.notif.expire(); } catch (e) {}
          if (w._manual)
            root._history = root._history.filter(x => x.id !== w.id);
          changed = true;
        } else {
          keep.push(w);
        }
      }
      // notif.expire() triggers closed(Expired) which drops the toast but
      // keeps history; drop optimistically so UI hides even if close lags.
      if (changed) {
        root._toasts = keep;
        root._recountUnread();
        root._rebuildQsMaps();
      }
    }
  }

  // ================= Server internals =================

  function _urgencyNum(n) {
    try {
      const v = Number(n.urgency);
      if (v === 0 || v === 1 || v === 2)
        return v;
    } catch (e) {}
    return 1;
  }

  function _defaultTimeoutMs(urgencyNum) {
    return urgencyNum === 2 ? 10000 : (urgencyNum === 0 ? 3500 : 5000);
  }

  function _snapshotQs(n, u) {
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
    return {
      appName: n.appName || "Application",
      appIcon: n.appIcon || "",
      summary: n.summary || "Notification",
      body: n.body || "",
      image: n.image || "",
      desktopEntry: n.desktopEntry || "",
      urgency: u,
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

  // Category-aware timeout: calls/messaging ring longer, transfer/progress shorter.
  function _timeoutForCategory(category, urgencyNum) {
    const c = String(category || "").toLowerCase();
    if (c.indexOf("call") === 0 || c === "incoming-call")
      return 15000;
    if (c.indexOf("im") === 0 || c === "email" || c === "message")
      return urgencyNum === 2 ? 10000 : 7000;
    if (c === "transfer" || c === "progress" || c.indexOf("presence") === 0)
      return 3500;
    return root._defaultTimeoutMs(urgencyNum);
  }

  function _onQsNotification(n) {
    // Carried over from pre-reload generation: keep in history, no toast/unread.
    const carried = n.lastGeneration === true;
    n.tracked = true;
    const u = root._urgencyNum(n);
    // Hook close BEFORE any dismiss can happen.
    try {
      n.closed.connect(reason => root._onQsClosed(n.id, reason));
    } catch (e) {}

    const receivedAt = new Date();
    let timeoutMs = root._defaultTimeoutMs(u);
    try {
      const snap0 = root._snapshotQs(n, u);
      const catT = root._timeoutForCategory(snap0.category, u);
      if (catT !== undefined)
        timeoutMs = catT;
    } catch (e) {}
    try {
      if (n.expireTimeout !== undefined && n.expireTimeout !== null) {
        const s = Number(n.expireTimeout);
        if (s === 0)
          timeoutMs = Infinity; // persist
        else if (s > 0)
          timeoutMs = Math.round(s * 1000);
        else if (s < 0)
          timeoutMs = timeoutMs; // keep category/default
      }
    } catch (e) {}

    const snap = root._snapshotQs(n, u);
    // replaces_id / same-id update: replace in place instead of duplicating.
    const hid = root._history.findIndex(x => x.id === n.id);
    const tid = root._toasts.findIndex(x => x.id === n.id);
    if (hid !== -1 || tid !== -1) {
      const base = hid !== -1 ? root._history[hid] : root._toasts[tid];
      base.notif = n;
      base.snap = snap;
      base.receivedAt = receivedAt;
      base.timeoutMs = timeoutMs;
      base.expiresAt = timeoutMs === Infinity ? Infinity : (receivedAt.getTime() + timeoutMs);
      if (!carried)
        base.read = false;
      // Move updated entry to the end for recency in history.
      if (hid !== -1) {
        const nh = root._history.slice();
        const w0 = nh.splice(hid, 1)[0];
        nh.push(w0);
        root._history = nh;
      }
      if (tid !== -1) {
        const nt = root._toasts.slice();
        const idx = (hid !== -1 && root._toasts[tid] === base) ? tid : nt.findIndex(x => x.id === n.id);
        if (idx !== -1) {
          const w1 = nt.splice(idx, 1)[0];
          nt.push(w1);
          root._toasts = nt.slice(-10);
        }
      } else if (!carried && (!root.dnd || u === 2) && snap.transient !== true) {
        root._toasts = root._toasts.concat([base]).slice(-10);
      }
      if (!carried)
        root._recountUnread();
      root._rebuildQsMaps();
      return;
    }

    const w = {
      notif: n,
      snap: snap,
      id: n.id,
      receivedAt: receivedAt,
      read: carried ? true : false,
      expiresAt: timeoutMs === Infinity ? Infinity : (receivedAt.getTime() + timeoutMs),
      timeoutMs: timeoutMs
    };

    if (snap.transient === true) {
      // Transient: toast-only, skip history persistence (0.3.1 doc).
      if (!root.dnd || u === 2)
        root._toasts = root._toasts.concat([w]).slice(-10);
      root._rebuildQsMaps();
      return;
    }

    root._history = root._history.concat([w]);
    root._evictQsOverflow();
    if (!carried) {
      if (!root.dnd || u === 2)
        root._toasts = root._toasts.concat([w]).slice(-10);
      root._qsUnread++;
    }
    root._rebuildQsMaps();
  }

  function _isExpiredReason(reason) {
    try {
      if (reason === NotificationCloseReason.Expired)
        return true;
    } catch (e) {}
    // Fallback: Expired is value 1 in freedesktop order (Dismissed=0).
    try { if (Number(reason) === 1) return true; } catch (e2) {}
    return false;
  }

  function _onQsClosed(notifId, reason) {
    // Expired (timeout) only clears the toast; history persists.
    // Dismissed / CloseRequested clear both.
    if (root._isExpiredReason(reason)) {
      root._toasts = root._toasts.filter(w => w.id !== notifId);
      root._rebuildQsMaps();
      return;
    }
    root._history = root._history.filter(w => w.id !== notifId);
    root._toasts = root._toasts.filter(w => w.id !== notifId);
    root._recountUnread();
    root._rebuildQsMaps();
  }

  // Reconcile against the canonical server model (missed signals safety net).
  function _reconcileTracked() {
    try {
      const srv = qsLoader.item;
      if (!srv || !srv.trackedNotifications)
        return;
      const count = srv.trackedNotifications.count || 0;
      const seen = {};
      for (let i = 0; i < count; i++) {
        try {
          const n = srv.trackedNotifications.get(i);
          if (n)
            seen[n.id] = true;
        } catch (e) {}
      }
      // Drop toast entries the server no longer tracks (history keeps Expired).
      const nt = root._toasts.filter(w => w._manual === true || seen[w.id] === true);
      if (nt.length !== root._toasts.length) {
        root._toasts = nt;
        root._rebuildQsMaps();
      }
    } catch (e) {}
  }

  function _recountUnread() {
    let u = 0;
    for (let i = 0; i < root._history.length; i++)
      if (!root._history[i].read)
        u++;
    root._qsUnread = u;
  }

  function _evictQsOverflow() {
    let evicted = false;
    while (root._history.length > root.maxNotifications && root._history.length > 0) {
      const oldest = root._history[0];
      root._history = root._history.slice(1);
      root._toasts = root._toasts.filter(w => w.id !== oldest.id);
      try { oldest.notif.dismiss(); } catch (e) {}
      evicted = true;
    }
    if (evicted) {
      root._recountUnread();
      root._rebuildQsMaps();
    }
  }

  function _clearQsState() {
    // Dismiss live notifications so server + clients stay consistent.
    for (let i = 0; i < root._history.length; i++) {
      try { root._history[i].notif.dismiss(); } catch (e) {}
    }
    root._history = [];
    root._toasts = [];
    root._qsUnread = 0;
    root._rebuildQsMaps();
  }

  function _wrapMap(w) {
    const n = w.notif;
    const s = w.snap || {};
    // Prefer live values while the object is alive, fall back to snapshot
    // (Expired entries keep history after the C++ object is destroyed).
    function live(key, fb) {
      try {
        const v = n ? n[key] : undefined;
        if (v !== undefined && v !== null && v !== "")
          return v;
      } catch (e) {}
      return (s[key] !== undefined && s[key] !== null) ? s[key] : fb;
    }
    let u = 1;
    try {
      if (s.urgency === 0 || s.urgency === 1 || s.urgency === 2)
        u = s.urgency;
      else
        u = root._urgencyNum(n);
    } catch (e) {}
    let acts = s.actions || [];
    try {
      if (n && n.actions && n.actions.length !== undefined) {
        const la = [];
        for (let i = 0; i < n.actions.length; i++) {
          const a = n.actions[i];
          la.push({ identifier: a.identifier, text: a.text || a.identifier });
        }
        if (la.length > 0 || !s.actions)
          acts = la;
      }
    } catch (e) {}
    let hasInline = s.hasInlineReply === true;
    let inlinePh = s.inlineReplyPlaceholder || "Reply…";
    let hasActIcons = s.hasActionIcons === true;
    try { if (n && n.hasInlineReply === true) hasInline = true; } catch (e) {}
    try { if (n && n.inlineReplyPlaceholder) inlinePh = n.inlineReplyPlaceholder; } catch (e) {}
    try { if (n && n.hasActionIcons === true) hasActIcons = true; } catch (e) {}
    return {
      id: w.id,
      notifId: String(w.id),
      appName: live("appName", "Application") || "Application",
      appIcon: live("appIcon", ""),
      summary: live("summary", "Notification") || "Notification",
      body: live("body", ""),
      image: live("image", ""),
      desktopEntry: live("desktopEntry", ""),
      urgency: u,
      timeout: w.timeoutMs === Infinity ? 0 : w.timeoutMs,
      timestamp: w.receivedAt,
      timeAgo: root.timeAgo(w.receivedAt),
      read: w.read,
      actions: acts,
      hasInlineReply: hasInline,
      inlineReplyPlaceholder: inlinePh,
      hasActionIcons: hasActIcons,
      category: s.category || "",
      soundName: s.soundName || "",
      soundFile: s.soundFile || "",
      suppressSound: s.suppressSound === true,
      isBridge: false
    };
  }

  function _findQs(id) {
    for (let i = 0; i < root._history.length; i++)
      if (root._history[i].id === id)
        return root._history[i];
    for (let i = 0; i < root._toasts.length; i++)
      if (root._toasts[i].id === id)
        return root._toasts[i];
    return null;
  }

  function _rebuildQsMaps() {
    root._historyMaps = root._history.map(w => root._wrapMap(w));
    root._toastMaps = root._toasts.map(w => root._wrapMap(w));
    root._groupedCache = root._buildGrouped(root._historyMaps);
  }

  function _buildGrouped(maps) {
    const order = [];
    const groups = {};
    for (let i = 0; i < maps.length; i++) {
      const m = maps[i];
      const key = (m.appName || "Application").trim() || "Application";
      if (!groups[key]) {
        groups[key] = { appName: key, appIcon: m.appIcon, desktopEntry: m.desktopEntry || "", notifications: [], totalCount: 0, expanded: root.isGroupExpanded(key) };
        order.push(key);
      }
      if (!groups[key].appIcon && m.appIcon)
        groups[key].appIcon = m.appIcon;
      if (!groups[key].desktopEntry && m.desktopEntry)
        groups[key].desktopEntry = m.desktopEntry;
      groups[key].notifications.push(m);
      groups[key].totalCount++;
    }
    return order.map(k => groups[k]);
  }

  // ================= Public API =================

  function _appNameOf(w) {
    try { if (w.notif && w.notif.appName) return w.notif.appName; } catch (e) {}
    if (w.snap && w.snap.appName)
      return w.snap.appName;
    return "Application";
  }

  function _isResident(w) {
    try { if (w.notif && w.notif.resident === true) return true; } catch (e) {}
    return w.snap && w.snap.resident === true;
  }

  function _isTransient(w) {
    try { if (w.notif && w.notif.transient === true) return true; } catch (e) {}
    return w.snap && w.snap.transient === true;
  }

  function dismissToast(id) {
    const w = root._findQs(Number(id));
    if (w && root._isTransient(w)) {
      try { w.notif.expire(); } catch (e) {}
    }
    root._toasts = root._toasts.filter(x => x.id !== Number(id));
    root._rebuildQsMaps();
  }

  function dismissNotification(id) {
    const w = root._findQs(Number(id));
    if (w) {
      try { w.notif.dismiss(); } catch (e) {}
    }
    root._history = root._history.filter(x => x.id !== Number(id));
    root._toasts = root._toasts.filter(x => x.id !== Number(id));
    root._recountUnread();
    root._rebuildQsMaps();
  }

  function clearApp(appName) {
    for (let i = 0; i < root._history.length; i++) {
      if (root._appNameOf(root._history[i]) === appName) {
        try { root._history[i].notif.dismiss(); } catch (e) {}
      }
    }
    root._history = root._history.filter(w => root._appNameOf(w) !== appName);
    root._toasts = root._toasts.filter(w => root._appNameOf(w) !== appName);
    root._recountUnread();
    root._rebuildQsMaps();
  }

  function clearAll() {
    for (let i = 0; i < root._history.length; i++) {
      try { root._history[i].notif.dismiss(); } catch (e) {}
    }
    root._history = [];
    root._toasts = [];
    root._qsUnread = 0;
    root._rebuildQsMaps();
  }

  function markAllRead() {
    for (let i = 0; i < root._history.length; i++)
      root._history[i].read = true;
    root._qsUnread = 0;
    root._rebuildQsMaps();
  }

  function toggleDnd() {
    root.dnd = !root.dnd;
  }

  function toggleGroupExpanded(appName) {
    const g = Object.assign({}, root.expandedGroups);
    g[appName] = !g[appName];
    root.expandedGroups = g;
  }

  function isGroupExpanded(appName) {
    return root.expandedGroups[appName] === true;
  }

  function invokeAction(itemOrId, identifier) {
    let id = 0;
    if (typeof itemOrId === "number")
      id = itemOrId;
    else if (itemOrId && itemOrId.id !== undefined)
      id = Number(itemOrId.id);
    const w = root._findQs(id);
    if (!w)
      return;
    try {
      let done = false;
      if (w.notif.actions) {
        for (let i = 0; i < w.notif.actions.length; i++) {
          if (w.notif.actions[i].identifier === identifier) {
            w.notif.actions[i].invoke();
            done = true;
            break;
          }
        }
      }
      if (!done)
        w.notif.dismiss();
    } catch (e) {
      try { w.notif.dismiss(); } catch (e2) {}
    }
    // invoke() auto-dismisses unless resident; ensure local state follows
    const resident = root._isResident(w);
    if (!resident) {
      root._history = root._history.filter(x => x.id !== id);
      root._toasts = root._toasts.filter(x => x.id !== id);
      root._recountUnread();
      root._rebuildQsMaps();
    }
  }

  function sendInlineReply(itemOrId, text) {
    let id = 0;
    if (typeof itemOrId === "number")
      id = itemOrId;
    else if (itemOrId && itemOrId.id !== undefined)
      id = Number(itemOrId.id);
    const reply = String(text || "").trim();
    if (!reply)
      return false;
    const w = root._findQs(id);
    if (!w || !w.notif)
      return false;
    let ok = false;
    try {
      if (w.notif.hasInlineReply === true || (w.snap && w.snap.hasInlineReply === true)) {
        w.notif.sendInlineReply(reply);
        ok = true;
      }
    } catch (e) {}
    if (ok) {
      // Reply sent: clear toast, keep history, mark read.
      root._toasts = root._toasts.filter(x => x.id !== id);
      for (let i = 0; i < root._history.length; i++)
        if (root._history[i].id === id)
          root._history[i].read = true;
      root._recountUnread();
      root._rebuildQsMaps();
    }
    return ok;
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
    return root._groupedCache;
  }

  // Local test hook (no D-Bus involved). Plain-object stand-in with the
  // fields _wrapMap reads, so it flows through the same map path.
  function addManualNotification(summary, body, appName, appIcon, image, urgency, actions, opts) {
    const now = new Date();
    const u = Math.max(0, Math.min(2, Number(urgency) || 1));
    const timeoutMs = root._defaultTimeoutMs(u);
    const id = 9000 + Math.floor(Math.random() * 8999);
    const o = opts || {};
    const w = {
      notif: {
        id: id,
        appName: appName || "Application",
        appIcon: appIcon || "",
        summary: summary || "Notification",
        body: body || "",
        image: image || "",
        desktopEntry: "",
        urgency: u,
        actions: (actions || []).map(a => ({ identifier: a.identifier, text: a.text, invoke: function () {} })),
        resident: false,
        transient: false,
        tracked: true,
        hasInlineReply: o.hasInlineReply === true,
        inlineReplyPlaceholder: o.inlineReplyPlaceholder || "",
        hasActionIcons: o.hasActionIcons === true,
        hints: o.hints || {},
        dismiss: function () {},
        expire: function () {},
        sendInlineReply: function () {}
      },
      id: id,
      receivedAt: now,
      read: false,
      expiresAt: now.getTime() + timeoutMs,
      timeoutMs: timeoutMs,
      _manual: true
    };
    w.snap = root._snapshotQs(w.notif, u);
    root._history = root._history.concat([w]);
    root._evictQsOverflow();
    if (!root.dnd || u === 2)
      root._toasts = root._toasts.concat([w]).slice(-10);
    root._qsUnread++;
    root._rebuildQsMaps();
  }
}
