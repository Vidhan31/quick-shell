pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../components"

PopupWindow {
  id: host

  property var services: null

  property Item targetItem: null
  property string currentPopup: ""

  // Debounce/race prevention for Wayland grabFocus dismissal
  property var lastClosedItem: null
  property string lastClosedPopup: ""
  property real lastClosedTime: 0

  readonly property bool isLeftAligned: currentPopup === "proc" || currentPopup === "ai"

  /* Async Loader gate: with asynchronous:true the item is null for the first
     frames. Committing a 0x0 PopupWindow is a Wayland protocol error that
     kills quickshell, so never advertise 0 size and do not flip visible until
     the content is ready. */
  property bool pendingOpen: false

  anchor.edges: isLeftAligned ? (Edges.Bottom | Edges.Left) : Edges.Bottom
  anchor.gravity: isLeftAligned ? (Edges.Bottom | Edges.Right) : Edges.Bottom
  anchor.margins.top: 6
  anchor.adjustment: PopupAdjustment.SlideX

  visible: false
  grabFocus: true
  color: "transparent"

  implicitWidth: (viewLoader.item && viewLoader.item.implicitWidth > 0) ? viewLoader.item.implicitWidth : 440
  implicitHeight: (viewLoader.item && viewLoader.item.implicitHeight > 0) ? viewLoader.item.implicitHeight : 320

  onImplicitHeightChanged: {
    if (visible) {
      anchor.updateAnchor();
    }
  }

  onImplicitWidthChanged: {
    if (visible) {
      anchor.updateAnchor();
    }
  }

  signal popupOpened()
  signal popupClosed()

  function showTip(item: Item, text: string, subtext: string): void {
    hoverTip.show(item, text, subtext);
  }

  function hideTip(): void {
    hoverTip.hide();
  }

  Timer {
    id: markReadTimer
    interval: 400
    repeat: false
    onTriggered: {
      const notif = host.services ? host.services.notification : null;
      if (host.visible && host.currentPopup === "notif" && notif) {
        notif.markAllRead();
      }
    }
  }

  function cleanupCurrent(): void {
    markReadTimer.stop();
    hoverTip.hide();
    const notif = host.services ? host.services.notification : null;
    if (currentPopup === "notif" && notif) {
      notif.markAllRead();
    }
    if (viewLoader.item && typeof viewLoader.item.hideTip === "function") {
      viewLoader.item.hideTip();
    }
  }

  function close(): void {
    if (!visible && !pendingOpen) return;
    pendingOpen = false;
    cleanupCurrent();
    lastClosedItem = targetItem;
    lastClosedPopup = currentPopup;
    lastClosedTime = Date.now();
    targetItem = null;
    currentPopup = "";
    visible = false;
    viewLoader.sourceComponent = null;
    host.popupClosed();
  }

  readonly property var registry: ({
    "proc": procComp,
    "ai": aiComp,
    "ts": tsComp,
    "bluetooth": bluetoothComp,
    "media": mediaComp,
    "vol": volComp,
    "eth": ethComp,
    "privacy": privacyComp,
    "notif": notifComp,
    "update": updateComp,
    "docker": dockerComp,
    "cal": calComp,
    "power": powerComp
  })

  function componentFor(name: string): Component {
    return registry[name] || null;
  }

  function nameForComponent(comp: Component): string {
    for (const key in registry) {
      if (registry[key] === comp) return key;
    }
    return "";
  }

  function open(item: Item, target: var, nameHint = ""): void {
    if (!item || !target) return;

    if (visible) {
      close();
    }

    lastClosedItem = null;
    lastClosedPopup = "";

    targetItem = item;
    let comp = null;
    let name = "";
    if (typeof target === "string") {
      name = target;
      comp = registry[target] || null;
    } else {
      comp = target;
      name = nameHint || nameForComponent(target);
    }
    currentPopup = name;
    pendingOpen = true;

    if (item.Window && item.Window.window && item.Window.window.screen) {
      host.screen = item.Window.window.screen;
    }

    anchor.item = item;
    viewLoader.sourceComponent = comp;

    /* Visible flip + anchor update happen in viewLoader.onLoaded once the
       async content is Ready (non-zero size). Fallback: if the loader somehow
       resolved synchronously, show immediately. */
    if (viewLoader.status === Loader.Ready && viewLoader.item) {
      pendingOpen = false;
      if (typeof viewLoader.item.syncHeight === "function") {
        viewLoader.item.syncHeight();
      }
      visible = true;
      anchor.updateAnchor();

      if (name === "notif") {
        markReadTimer.start();
      }

      host.popupOpened();
    }
  }

  function toggle(item: Item, target: var, nameHint = ""): void {
    const now = Date.now();
    const isTargetSame = (targetItem === item);
    if (pendingOpen && isTargetSame) {
      close();
      return;
    }
    if (visible && isTargetSame) {
      close();
      return;
    }
    if (!visible && !pendingOpen && lastClosedItem === item && (now - lastClosedTime < 250)) {
      return;
    }
    open(item, target, nameHint);
  }

  function isOpen(item: Item, name = ""): bool {
    const isVis = visible || pendingOpen;
    const curTarget = targetItem;
    const curName = currentPopup;
    return isVis && (item ? curTarget === item : true) && (name.length > 0 ? curName === name : true);
  }

  onVisibleChanged: {
    if (!visible) {
      pendingOpen = false;
      if (targetItem !== null || currentPopup !== "") {
        cleanupCurrent();
        lastClosedItem = targetItem;
        lastClosedPopup = currentPopup;
        lastClosedTime = Date.now();
        targetItem = null;
        currentPopup = "";
        viewLoader.sourceComponent = null;
        host.popupClosed();
      }
    }
  }

  Item {
    id: contentRoot
    anchors.fill: parent
    focus: true

    function showTip(item: Item, text: string, subtext: string): void {
      hoverTip.show(item, text, subtext);
    }

    function hideTip(): void {
      hoverTip.hide();
    }

    Keys.onEscapePressed: event => {
      host.close();
      event.accepted = true;
    }

    Loader {
      id: viewLoader
      anchors.fill: parent
      asynchronous: true
      visible: status === Loader.Ready
      onLoaded: {
        if (item && typeof item.syncHeight === "function") item.syncHeight();
        if (host.pendingOpen) {
          host.pendingOpen = false;
          host.visible = true;
          host.anchor.updateAnchor();
          if (host.currentPopup === "notif") {
            markReadTimer.start();
          }
          host.popupOpened();
        } else {
          host.anchor.updateAnchor();
        }
      }
      onStatusChanged: {
        if (status === Loader.Error) {
          console.warn("PopupHost: failed to load popup", host.currentPopup);
          host.pendingOpen = false;
        }
      }
    }

    HoverTooltip {
      id: hoverTip
    }
  }

  Component {
    id: procComp
    TopProcessesControlCenter {
      anchors.fill: parent
      monitor: host.services ? host.services.processMonitor : null
    }
  }

  Component {
    id: aiComp
    AiUsageControlCenter {
      anchors.fill: parent
      aiUsage: host.services ? host.services.aiUsage : null
      barWindow: host.targetItem ? host.targetItem.Window.window : null
      popupWindow: host
      onTriggerRefreshAll: {
        if (host.services && host.services.aiUsage) host.services.aiUsage.refreshAll();
      }
    }
  }

  Component {
    id: tsComp
    TailscaleControlCenter {
      anchors.fill: parent
      tailscale: host.services ? host.services.tailscale : null
      onTriggerRefresh: {
        if (host.services && host.services.tailscale) host.services.tailscale.refresh();
      }
    }
  }

  Component {
    id: bluetoothComp
    BluetoothControlCenter {
      anchors.fill: parent
    }
  }

  Component {
    id: mediaComp
    MediaControlCenter {
      anchors.fill: parent
      media: host.services ? host.services.media : null
    }
  }

  Component {
    id: volComp
    VolumeControlCenter {
      anchors.fill: parent
      audio: host.services ? host.services.audio : null
    }
  }

  Component {
    id: ethComp
    EthernetControlCenter {
      anchors.fill: parent
      ethernet: host.services ? host.services.ethernet : null
      onTriggerRefresh: {
        if (host.services && host.services.ethernet) host.services.ethernet.refresh();
      }
    }
  }

  Component {
    id: privacyComp
    PrivacyControlCenter {
      anchors.fill: parent
      privacy: host.services ? host.services.privacy : null
    }
  }

  Component {
    id: notifComp
    NotificationControlCenter {
      anchors.fill: parent
      service: host.services ? host.services.notification : null
      jobService: host.services ? host.services.job : null
      onCloseRequested: host.close()
    }
  }

  Component {
    id: updateComp
    UpdateControlCenter {
      anchors.fill: parent
      service: host.services ? host.services.update : null
      onCloseRequested: host.close()
    }
  }

  Component {
    id: dockerComp
    DockerControlCenter {
      anchors.fill: parent
      docker: host.services ? host.services.docker : null
      onTriggerRefresh: {
        if (host.services && host.services.docker) host.services.docker.refresh();
      }
    }
  }

  Component {
    id: calComp
    CalendarControlCenter {
      anchors.fill: parent
      today: new Date()
      holidayProvider: host.services ? host.services.holidayProvider : null
    }
  }

  Component {
    id: powerComp
    PowerControlCenter {
      anchors.fill: parent
      power: host.services ? host.services.power : null
      onCloseRequested: host.close()
    }
  }
}
