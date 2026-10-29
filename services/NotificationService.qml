pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Plugins.Notifications
import Quickshell.Plugins.KWin

Item {
  id: root

  property bool takeoverEnabled: true
  property var extraHints: [
    "sound",
    "x-kde-urls",
    "x-kde-origin-name",
    "x-kde-display-appname",
    "x-kde-skip-grouping",
    "x-kde-user-action-feedback",
    "x-kde-reply-placeholder-text",
    "x-kde-reply-submit-button-text",
    "x-kde-reply-submit-button-icon-name",
    "inhibitions"
  ]

  Process {
    id: soundProc
  }

  KWinManager {
    id: kwinManager
  }

  NotificationStore {
    id: store
    maxNotifications: 100
    onDismissRequested: id => root._execDismiss(id)
    onExpireRequested: id => root._execExpire(id)
    onInvokeRequested: (id, identifier) => root._execInvoke(id, identifier)
    onReplyRequested: (id, text) => root._execReply(id, text)
    onInhibitionSummaryRequested: count => {
      const id = -Math.floor(Date.now() % 1000000);
      store.ingestSnapshot({
        appName: "Do Not Disturb",
        summary: "Do Not Disturb Ended",
        body: count === 1 ? "1 notification arrived while Do Not Disturb was active." : `${count} notifications arrived while Do Not Disturb was active.`,
        urgency: 1,
        transient: true
      }, id, 5, false);
    }
  }

  property var _live: ({})

  readonly property var notifications: store.notifications
  readonly property var activeToasts: store.activeToasts
  readonly property var groupedList: store.groupedList
  readonly property int unreadCount: store.unreadCount
  readonly property int totalCount: store.totalCount
  readonly property int timeTick: store.timeTick
  readonly property var dndUntil: store.dndUntil
  readonly property int silencedDuringDndCount: store.silencedDuringDndCount
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

  function _snapshotOf(n) {
    const acts = [];
    let hasDef = false;
    try {
      if (n.actions) {
        for (let i = 0; i < n.actions.length; i++) {
          const a = n.actions[i];
          if (a.identifier === "default") {
            hasDef = true;
          }
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

    if (!hasInline) {
      if (hints["x-kde-reply-placeholder-text"] || hints["inline-reply"] === true || hints["inline-reply"] === "true") {
        hasInline = true;
      } else {
        for (let i = 0; i < acts.length; i++) {
          if (acts[i].identifier === "inline-reply") {
            hasInline = true;
            break;
          }
        }
      }
    }
    if (!inlinePh && hints["x-kde-reply-placeholder-text"]) {
      inlinePh = String(hints["x-kde-reply-placeholder-text"]);
    }
    if (!hasActIcons && (hints["action-icons"] === true || hints["action-icons"] === "true")) {
      hasActIcons = true;
    }

    let hasConf = false;
    let confLabel = "";
    const filteredActs = [];
    for (let i = 0; i < acts.length; i++) {
      const ident = acts[i].identifier;
      if (ident === "default") {
        hasDef = true;
        continue;
      }
      if (ident === "settings") {
        hasConf = true;
        confLabel = acts[i].text || "Configure";
        continue;
      }
      if (hasInline && ident === "inline-reply") {
        continue;
      }
      filteredActs.push(acts[i]);
    }
    const replySubmitText = hints["x-kde-reply-submit-button-text"] ? String(hints["x-kde-reply-submit-button-text"]) : "";
    const replySubmitIcon = hints["x-kde-reply-submit-button-icon-name"] ? String(hints["x-kde-reply-submit-button-icon-name"]) : "";
    let urg = 1;
    try {
      const v = Number(n.urgency);
      if (v === 0 || v === 1 || v === 2)
        urg = v;
    } catch (e) {}

    const desktopEntry = n.desktopEntry || hints["desktop-entry"] || "";
    const displayAppName = hints["x-kde-display-appname"] || "";
    const effectiveAppName = displayAppName || n.appName || "Application";
    const originName = hints["x-kde-origin-name"] || hints["origin-name"] || "";

    let urls = [];
    const rawUrls = hints["x-kde-urls"];
    if (rawUrls) {
      if (Array.isArray(rawUrls)) {
        for (let i = 0; i < rawUrls.length; i++) {
          if (rawUrls[i]) urls.push(String(rawUrls[i]));
        }
      } else if (typeof rawUrls === "string" && rawUrls.length > 0) {
        urls.push(rawUrls);
      }
    }

    const skipGrouping = hints["x-kde-skip-grouping"] === true || hints["x-kde-skip-grouping"] === "true";
    const userActionFeedback = hints["x-kde-user-action-feedback"] === true || hints["x-kde-user-action-feedback"] === "true";

    let appIcon = "";
    if (desktopEntry) {
      try {
        const entry = DesktopEntries.byId(desktopEntry) || DesktopEntries.heuristicLookup(desktopEntry);
        if (entry && entry.icon) {
          appIcon = entry.icon;
        }
      } catch (e) {}
    }
    if (!appIcon && n.appName) {
      try {
        const entry = DesktopEntries.heuristicLookup(n.appName);
        if (entry && entry.icon) {
          appIcon = entry.icon;
        }
      } catch (e) {}
    }

    const rawNotifIcon = n.appIcon || "";
    let notifIcon = "";
    const imageSrc = n.image || "";

    if (rawNotifIcon) {
      if (!appIcon) {
        if (imageSrc) {
          // If a rich image is attached, rawNotifIcon is the app icon (KDE rule)
          appIcon = rawNotifIcon;
        } else {
          const lowerApp = (effectiveAppName || "").toLowerCase();
          const lowerRaw = rawNotifIcon.toLowerCase();
          if (lowerRaw.includes(lowerApp) || (desktopEntry && lowerRaw.includes(desktopEntry.toLowerCase()))) {
            appIcon = rawNotifIcon;
          } else {
            notifIcon = rawNotifIcon;
          }
        }
      } else if (rawNotifIcon !== appIcon) {
        const lowerApp = (effectiveAppName || "").toLowerCase();
        const lowerRaw = rawNotifIcon.toLowerCase();
        const isAppIcon = (lowerApp && lowerRaw.includes(lowerApp)) ||
                          (desktopEntry && lowerRaw.includes(desktopEntry.toLowerCase())) ||
                          (desktopEntry && desktopEntry.toLowerCase().includes(lowerRaw));
        if (!isAppIcon && !rawNotifIcon.startsWith("/app/") && !rawNotifIcon.startsWith("file:///app/")) {
          notifIcon = rawNotifIcon;
        }
      }
    }

    if (!appIcon) {
      appIcon = rawNotifIcon || desktopEntry || "";
    }

    return {
      appName: effectiveAppName,
      appIcon: appIcon,
      notifIcon: notifIcon,
      originName: originName,
      hasDefaultAction: hasDef,
      summary: n.summary || "Notification",
      body: n.body || "",
      image: imageSrc,
      desktopEntry: desktopEntry,
      urgency: urg,
      actions: filteredActs,
      resident: n.resident === true,
      transient: n.transient === true,
      hasInlineReply: hasInline,
      inlineReplyPlaceholder: inlinePh,
      hasActionIcons: hasActIcons,
      category: (hints["category"] || hints["Category"] || ""),
      soundName: (hints["sound-name"] || ""),
      soundFile: (hints["sound-file"] || ""),
      suppressSound: (hints["suppress-sound"] === true),
      urls: urls,
      skipGrouping: skipGrouping,
      userActionFeedback: userActionFeedback,
      hasConfigureAction: hasConf,
      configureLabel: confLabel,
      replySubmitButtonText: replySubmitText,
      replySubmitButtonIconName: replySubmitIcon
    };
  }

  function _playSound(soundName, soundFile) {
    if (store.dnd) return;
    try {
      if (soundFile && soundFile.length > 0) {
        soundProc.command = ["canberra-gtk-play", "-f", soundFile];
        soundProc.running = false;
        soundProc.running = true;
      } else if (soundName && soundName.length > 0) {
        soundProc.command = ["canberra-gtk-play", "-i", soundName];
        soundProc.running = false;
        soundProc.running = true;
      }
    } catch (e) {}
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
    const snap = root._snapshotOf(n);
    store.ingestSnapshot(snap, n.id, exp, carried);
    if (!carried && !snap.suppressSound && (snap.soundName || snap.soundFile)) {
      root._playSound(snap.soundName, snap.soundFile);
    }
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

    try {
      const targetApp = (n.desktopEntry || n.appName || "").toLowerCase();
      if (targetApp.length > 0 && kwinManager.available) {
        const wins = kwinManager.windows;
        for (let i = 0; i < wins.length; i++) {
          const w = wins[i];
          const appId = (w.appId || "").toLowerCase();
          if (appId.length > 0 && (appId.includes(targetApp) || targetApp.includes(appId))) {
            kwinManager.activateWindow(w.id);
            break;
          }
        }
      }
    } catch (e) {}
  }

  function _execReply(id, text) {
    const n = root._live[Number(id)];
    if (!n)
      return;
    try { n.sendInlineReply(text); } catch (e) {}
  }

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

  function setDndTimed(minutes) {
    store.setDndTimed(minutes);
  }

  function cancelDnd() {
    store.cancelDnd();
  }

  function copyToClipboard(text) {
    store.copyToClipboard(text);
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

  function invokeDefaultAction(itemOrId) {
    store.invokeDefaultAction(root._normId(itemOrId));
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
}
