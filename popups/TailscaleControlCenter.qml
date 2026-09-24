// TailscaleControlCenter.qml — Quiet control surface for Tailscale.
// Grouped rows with hairlines, one segmented switcher, words instead of badges.
// Every pressable surface shares the same hover/pressed wash so clicks feel native.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Plugins.Tailscale
import "../theme"
import "../components"

Item {
  id: root

  property TailscaleMonitor monitor: null
  TailscaleMonitor {
    id: fallbackMonitor
    running: root.monitor === null
  }
  readonly property TailscaleMonitor activeMonitor: root.monitor ? root.monitor : fallbackMonitor

  implicitWidth: 440
  implicitHeight: 620

  property var tsData: activeMonitor ? activeMonitor.tsData : ({
    connected: false,
    backend_state: "Unknown",
    version: "",
    tailnet: "",
    magic_dns_suffix: "",
    self: { hostname: "", dns_name: "", ipv4: "", ipv6: "", os: "linux", online: false, relay: "", user: {} },
    health: [],
    ssh_enabled: false,
    webclient_enabled: false,
    shields_up: false,
    exit_node_enabled: false,
    auto_update: false,
    serve_items: [],
    peers: [],
    services: []
  })

  signal triggerRefresh()

  property int currentTab: 0 // 0: Sharing, 1: Devices, 2: Settings
  property string pingingIp: ""

  // Launcher state
  property string launchTarget: "https+insecure://localhost:5137"
  property string launchPort: "443"
  property string launchPath: "/"
  property string launchMode: "serve" // "serve" or "funnel"
  property bool initialTargetSynced: false

  // ---- Derived state (all read from tsData, same schema as before) ----
  readonly property bool connected: Boolean(root.tsData && root.tsData.connected)
  readonly property var serveItems: (root.tsData && root.tsData.serve_items) ? root.tsData.serve_items : []
  readonly property var peers: (root.tsData && root.tsData.peers) ? root.tsData.peers : []
  readonly property var health: (root.tsData && root.tsData.health) ? root.tsData.health : []
  readonly property bool busy: root.activeMonitor ? root.activeMonitor.isBusy : false
  readonly property bool netBusy: root.activeMonitor ? root.activeMonitor.isRunningNetcheck : false
  readonly property string netReport: root.activeMonitor ? root.activeMonitor.netcheckReport : ""
  readonly property string pingResult: root.activeMonitor ? root.activeMonitor.pingResult : ""
  readonly property string pingTargetIp: root.activeMonitor ? root.activeMonitor.pingTargetIp : ""

  readonly property var segItems: [
    { icon: "󰖟", label: "Sharing", count: root.serveItems.length, alert: false },
    { icon: "󰀲", label: "Devices", count: root.peers.length, alert: false },
    { icon: "󰒢", label: "Settings", count: root.health.length, alert: root.health.length > 0 }
  ]

  readonly property var suggestions: [
    { name: "Frontend", addr: "https+insecure://localhost:5137" },
    { name: "API", addr: "8080" },
    { name: "API · alt", addr: "3000" }
  ]

  // ---- Logic (unchanged semantics) ----
  function normalizeTarget(str: string): string {
    if (!str) return "";
    const s = str.trim().toLowerCase();
    return s.replace(/\/+$/, "");
  }

  function extractPort(str: string): string {
    if (!str) return "";
    const s = root.normalizeTarget(str);
    if (/^\d+$/.test(s)) return s;
    const m = s.match(/(?::)(\d+)(?:\/|$)/);
    if (m) return m[1];
    return "";
  }

  function targetsMatch(a: string, b: string): bool {
    if (!a || !b) return false;
    const s1 = root.normalizeTarget(a);
    const s2 = root.normalizeTarget(b);
    if (s1 === s2) return true;

    const n1 = s1.replace("127.0.0.1", "localhost");
    const n2 = s2.replace("127.0.0.1", "localhost");
    if (n1 === n2) return true;

    const stripped1 = n1.replace(/^https?\+?[a-z]*:\/\//, "");
    const stripped2 = n2.replace(/^https?\+?[a-z]*:\/\//, "");
    if (stripped1 === stripped2) return true;

    const p1 = root.extractPort(s1);
    const p2 = root.extractPort(s2);
    if (p1 && p2 && p1 === p2) {
      const isLocal1 = /^(https?\+?[a-z]*:\/\/)?(localhost|127\.0\.0\.1)?(:\d+)?$/.test(n1) || /^\d+$/.test(s1);
      const isLocal2 = /^(https?\+?[a-z]*:\/\/)?(localhost|127\.0\.0\.1)?(:\d+)?$/.test(n2) || /^\d+$/.test(s2);
      if (isLocal1 && isLocal2) return true;
    }

    return false;
  }

  function findActiveEndpoint(target: string, port: string): var {
    const items = root.serveItems;
    if (!target || !items || items.length === 0) return null;

    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      if (root.targetsMatch(target, it.target) || root.targetsMatch(target, it.url)) {
        if (!port || port === "" || it.port === port) {
          return it;
        }
      }
    }

    for (let j = 0; j < items.length; j++) {
      const it2 = items[j];
      if (root.targetsMatch(target, it2.target) || root.targetsMatch(target, it2.url)) {
        return it2;
      }
    }

    return null;
  }

  function selectTarget(target: string): void {
    root.launchTarget = target;
    const ep = root.findActiveEndpoint(target, "");
    if (ep) {
      root.launchMode = ep.is_funnel ? "funnel" : "serve";
      if (ep.port) root.launchPort = ep.port;
      if (ep.path) root.launchPath = ep.path;
    }
    targetField.setText(root.launchTarget);
    portField.setText(root.launchPort);
  }

  readonly property var activeEndpoint: {
    const t = root.launchTarget;
    const p = root.launchPort;
    const _dep = root.tsData;
    return root.findActiveEndpoint(t, p);
  }

  readonly property bool isTargetActiveInCurrentMode: {
    if (!root.activeEndpoint) return false;
    const isFunnel = root.launchMode === "funnel";
    return root.activeEndpoint.is_funnel === isFunnel;
  }

  readonly property bool isTargetActiveInOtherMode: {
    if (!root.activeEndpoint) return false;
    const isFunnel = root.launchMode === "funnel";
    return root.activeEndpoint.is_funnel !== isFunnel;
  }

  readonly property string launchButtonAction: {
    if (!root.launchTarget || root.launchTarget.trim().length === 0) return "empty";
    if (root.isTargetActiveInCurrentMode) return "stop";
    if (root.isTargetActiveInOtherMode) return "switch";
    return "start";
  }

  readonly property string launchButtonText: {
    if (root.launchButtonAction === "empty") {
      return "Enter a target to begin";
    }
    if (root.launchButtonAction === "stop") {
      return "Stop sharing · :" + ((root.activeEndpoint && root.activeEndpoint.port) ? root.activeEndpoint.port : root.launchPort);
    }
    if (root.launchButtonAction === "switch") {
      return root.launchMode === "funnel" ? "Switch to Public" : "Switch to Tailnet";
    }
    return root.launchMode === "funnel" ? "Share Publicly" : "Share on Tailnet";
  }

  readonly property string launchButtonGlyph: {
    if (root.launchButtonAction === "empty") return "";
    if (root.launchButtonAction === "stop") return "✕";
    if (root.launchButtonAction === "switch") return "⇄";
    return "󰐊";
  }

  function osIcon(os: string): string {
    const s = (os || "").toLowerCase();
    if (s.includes("android")) return "󰀲";
    if (s.includes("linux")) return "󰌽";
    if (s.includes("mac") || s.includes("ios")) return "󰀵";
    if (s.includes("win")) return "󰖳";
    return "󰛳";
  }

  function pingDisplay(ip: string): string {
    if (!ip || root.pingTargetIp !== ip) return "";
    if (root.pingResult && root.pingResult.length > 0) return root.pingResult;
    if (root.pingingIp === ip) return "…";
    return "";
  }

  function sshCommands(): var {
    const self = (root.tsData && root.tsData.self) ? root.tsData.self : {};
    return [
      "ssh dev@" + (self.hostname || "fedora"),
      "ssh dev@" + (self.ipv4 || "100.72.40.125"),
      "ssh dev@" + (self.dns_name || "fedora.ts.net")
    ];
  }

  function showToast(msg: string): void {
    toast.show(msg);
  }

  function refresh(): void {
    root.triggerRefresh();
    if (root.activeMonitor) {
      root.activeMonitor.refresh();
    }
  }

  function runAction(args: var, successMsg: string): void {
    if (root.activeMonitor) {
      root.activeMonitor.runAction(args, successMsg || "");
    }
  }

  function copyText(text: string, label: string): void {
    if (!text) return;
    if (root.activeMonitor) {
      root.activeMonitor.copy(text);
      root.showToast("Copied " + (label ? label : text));
    }
  }

  function openUrl(url: string): void {
    if (!url) return;
    if (root.activeMonitor) {
      root.activeMonitor.openUrl(url);
      root.showToast("Opening " + url);
    }
  }

  function toggleConnection(): void {
    const action = root.connected ? "down" : "up";
    root.runAction(["up-down", action], root.connected ? "Disconnecting…" : "Connecting…");
  }

  function pingPeer(ip: string): void {
    if (!ip) return;
    root.pingingIp = ip;
    if (root.activeMonitor) {
      root.activeMonitor.ping(ip);
    }
  }

  function runNetcheck(): void {
    if (root.activeMonitor) {
      root.activeMonitor.netcheck();
    }
  }

  function stopEndpoint(port: string): void {
    root.runAction(["serve-stop", port], "Stopped port " + port);
  }

  function flipScope(item: var): void {
    const makeFunnel = !item.is_funnel;
    root.runAction(["funnel-toggle", item.port, item.target, makeFunnel ? "true" : "false", item.path || "/"],
                   makeFunnel ? "Switched to Public Funnel" : "Switched to Tailnet Only");
  }

  function launchPrimary(): void {
    if (root.launchButtonAction === "stop") {
      const stopPort = (root.activeEndpoint && root.activeEndpoint.port) ? root.activeEndpoint.port : (root.launchPort || "443");
      const stopPath = (root.activeEndpoint && root.activeEndpoint.path) ? root.activeEndpoint.path : (root.launchPath || "/");
      root.runAction(
        ["serve-stop", stopPort, stopPath],
        "Stopped " + (root.launchMode === "funnel" ? "funnel" : "serve") + " on port " + stopPort
      );
    } else if (root.launchButtonAction === "switch") {
      const port = (root.activeEndpoint && root.activeEndpoint.port) ? root.activeEndpoint.port : (root.launchPort || "443");
      const target = (root.activeEndpoint && root.activeEndpoint.target) ? root.activeEndpoint.target : root.launchTarget;
      const path = (root.activeEndpoint && root.activeEndpoint.path) ? root.activeEndpoint.path : (root.launchPath || "/");
      const makeFunnel = root.launchMode === "funnel";
      root.runAction(
        ["funnel-toggle", port, target, makeFunnel ? "true" : "false", path],
        makeFunnel ? ("Switched " + target + " to Public Funnel") : ("Switched " + target + " to Tailnet Only")
      );
    } else if (root.launchButtonAction === "start") {
      root.runAction(
        ["serve-start", root.launchTarget, root.launchMode, root.launchPort, root.launchPath],
        "Started " + root.launchMode + " for " + root.launchTarget
      );
    }
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: root.activeMonitor
    function onActionCompleted(ok, output, error, successMsg) {
      if (successMsg) {
        root.showToast(successMsg);
      }
    }
    function onPingFinished(ok, targetIp, latency) {
      if (root.pingingIp === targetIp) {
        root.pingingIp = "";
      }
    }
    function onStateChanged() {
      if (!root.initialTargetSynced && root.serveItems.length > 0) {
        root.initialTargetSynced = true;
        root.selectTarget(root.launchTarget);
      }
    }
  }

  readonly property var t: Theme

  // ================= Card =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: Theme.cardBorder
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 0

      // ---- Header: identity left, refresh + connection switch right ----
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        spacing: 10

        Text {
          text: "󰖩"
          font.family: t.mono
          font.pixelSize: 19
          color: root.connected ? t.accent : t.ink3
        }

        Column {
          Layout.fillWidth: true
          spacing: 1
          Text {
            text: "Tailscale"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: t.ink1
          }
          Text {
            text: {
              if (!root.connected) return (root.tsData && root.tsData.backend_state) ? root.tsData.backend_state : "Not connected";
              let s = (root.tsData && root.tsData.tailnet) ? root.tsData.tailnet : "";
              const relay = (root.tsData && root.tsData.self && root.tsData.self.relay) ? root.tsData.self.relay : "";
              if (relay.length > 0) s += " · " + relay;
              return s.length > 0 ? s : "Connected";
            }
            font.pixelSize: 11
            color: t.ink3
            elide: Text.ElideRight
          }
        }

        IconBtn {
          glyph: "󰑓"
          fs: 14
          spinning: root.busy
          onClicked: root.refresh()
        }

        TSwitch {
          on: root.connected
          onToggled: root.toggleConnection()
        }
      }

      Item { Layout.preferredHeight: 14; Layout.fillWidth: true }

      // ---- This device: grouped rows, tap a value to copy it ----
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: deviceCol.height
        radius: 12
        color: t.surface

        Column {
          id: deviceCol
          width: parent.width

          RowBase {
            width: parent.width
            height: 42
            rad: 12
            actionable: Boolean(root.tsData.self && root.tsData.self.hostname)
            onClicked: root.copyText((root.tsData.self && root.tsData.self.hostname) || "", "Hostname")
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 10
              Text {
                text: "󰌽"
                font.family: t.mono
                font.pixelSize: 14
                color: t.ink2
              }
              Text {
                Layout.fillWidth: true
                text: (root.tsData.self && root.tsData.self.hostname) ? root.tsData.self.hostname : "This device"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: t.ink1
                elide: Text.ElideRight
              }
              Text {
                text: (root.tsData.self && root.tsData.self.os) ? root.tsData.self.os : ""
                font.pixelSize: 11
                color: t.ink3
              }
            }
          }

          Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

          RowBase {
            width: parent.width
            height: 38
            actionable: Boolean(root.tsData.self && root.tsData.self.ipv4)
            onClicked: root.copyText((root.tsData.self && root.tsData.self.ipv4) || "", "IP address")
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              Text {
                text: "IP address"
                font.pixelSize: 12
                color: t.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                text: (root.tsData.self && root.tsData.self.ipv4) ? root.tsData.self.ipv4 : "—"
                font.family: t.mono
                font.pixelSize: 12
                color: t.ink1
              }
            }
          }

          Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

          RowBase {
            width: parent.width
            height: 38
            rad: 12
            actionable: Boolean(root.tsData.self && root.tsData.self.dns_name)
            onClicked: root.copyText((root.tsData.self && root.tsData.self.dns_name) || "", "Domain")
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              Text {
                text: "MagicDNS"
                font.pixelSize: 12
                color: t.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                Layout.maximumWidth: 220
                text: (root.tsData.self && root.tsData.self.dns_name) ? root.tsData.self.dns_name : "—"
                font.family: t.mono
                font.pixelSize: 12
                color: t.ink1
                elide: Text.ElideMiddle
              }
            }
          }
        }
      }

      Item { Layout.preferredHeight: 14; Layout.fillWidth: true }

      Segments {
        Layout.fillWidth: true
        items: root.segItems
        current: root.currentTab
        onSelected: index => root.currentTab = index
      }

      Item { Layout.preferredHeight: 12; Layout.fillWidth: true }

      StackLayout {
        id: tabStack
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: root.currentTab

        // ============ TAB 0: SHARING ============
        // No outer scroll: the shares list flexes, the composer stays pinned.
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 0 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 110 } }

          ColumnLayout {
            anchors.fill: parent
            spacing: 10

            SectionHead {
              Layout.fillWidth: true
              label: "Active shares"
              actionText: root.serveItems.length > 0 ? "Reset all" : ""
              actionColor: t.red
              onActionClicked: root.runAction(["serve-reset"], "Reset all serve endpoints")
            }

            // Grouped share rows; tap to expand actions.
            // Flexes to leftover space, scrolls internally past 2 rows.
            Rectangle {
              visible: root.serveItems.length > 0
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: 56
              radius: 12
              color: t.surface

              Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: sharesCol.height
                clip: true

                Column {
                  id: sharesCol
                  width: parent.width

                  Repeater {
                    model: root.serveItems
                    Column {
                      required property var modelData
                      required property int index
                      width: sharesCol.width

                      RowBase {
                        width: parent.width
                        height: 50
                        rad: (index === 0 && root.serveItems.length === 1) ? 10 : 0
                        onClicked: {
                          targetField.setText(modelData.target || modelData.url);
                          root.selectTarget(modelData.target || modelData.url);
                        }
                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 12
                          spacing: 8
                          Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                              width: parent.width
                              text: modelData.url
                              font.pixelSize: 13
                              font.weight: Font.Medium
                              color: t.ink1
                              elide: Text.ElideRight
                            }
                            Row {
                              width: parent.width
                              spacing: 5
                              Text {
                                text: modelData.is_funnel ? "Public" : "Tailnet"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: modelData.is_funnel ? t.violet : t.accent
                              }
                              Text {
                                text: "·"
                                font.pixelSize: 11
                                color: t.ink3
                              }
                              Text {
                                width: parent.width - 90
                                text: ":" + modelData.port + " → " + modelData.target
                                font.family: t.mono
                                font.pixelSize: 11
                                color: t.ink3
                                elide: Text.ElideRight
                              }
                            }
                          }
                        }
                      }

                      Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 4
                        TextBtn {
                          text: "Copy link"
                          fs: 11
                          onClicked: root.copyText(modelData.url, "URL")
                        }
                        TextBtn {
                          text: "Open"
                          fs: 11
                          onClicked: root.openUrl(modelData.url)
                        }
                        TextBtn {
                          text: modelData.is_funnel ? "Make private" : "Make public"
                          fs: 11
                          bold: true
                          fg: modelData.is_funnel ? t.accent : t.violet
                          onClicked: root.flipScope(modelData)
                        }
                        TextBtn {
                          text: "Stop"
                          fs: 11
                          fg: t.red
                          onClicked: root.stopEndpoint(modelData.port)
                        }
                      }

                      Item { width: 1; height: 6 }

                      Hairline {
                        visible: index < root.serveItems.length - 1
                        width: parent.width - 24
                        anchors.horizontalCenter: parent.horizontalCenter
                      }
                    }
                  }
                }
              }
            }

            // Empty state flexes to absorb slack; nothing to box.
            Item {
              visible: root.serveItems.length === 0
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: 44
              Text {
                anchors.centerIn: parent
                text: "Nothing shared yet"
                font.pixelSize: 12
                color: t.ink3
              }
            }

            SectionHead {
              Layout.fillWidth: true
              label: "New share"
            }

            Rectangle {
              id: composerRect
              Layout.fillWidth: true
              height: composerCol.height + 20
              radius: 12
              color: t.surface

              Column {
                id: composerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 8

                Field {
                  id: targetField
                  width: parent.width
                  initial: root.launchTarget
                  clearable: true
                  placeholder: "Local address or port · e.g. 8080"
                  onEdited: text => root.selectTarget(text)
                }

                // Presets in one quiet line; color carries state, no chips.
                Row {
                  width: parent.width
                  spacing: 2
                  Repeater {
                    model: root.suggestions
                    TextBtn {
                      required property var modelData
                      property var ep: root.findActiveEndpoint(modelData.addr, "")
                      property bool selected: root.targetsMatch(root.launchTarget, modelData.addr)
                      text: modelData.name + " · " + root.extractPort(modelData.addr)
                      fs: 11
                      bold: selected
                      fg: {
                        if (selected) return t.ink1;
                        if (ep) return ep.is_funnel ? t.violet : t.accent;
                        return t.ink3;
                      }
                      onClicked: {
                        targetField.setText(modelData.addr);
                        root.selectTarget(modelData.addr);
                      }
                    }
                  }
                }

                  RowLayout {
                    width: parent.width
                    spacing: 8
                    Segments {
                      Layout.fillWidth: true
                      Layout.preferredHeight: 32
                      items: [{ icon: "", label: "Tailnet", count: 0 }, { icon: "", label: "Public", count: 0 }]
                      current: root.launchMode === "funnel" ? 1 : 0
                      onSelected: index => root.launchMode = index === 1 ? "funnel" : "serve"
                    }
                    Field {
                      id: portField
                      Layout.preferredWidth: 84
                      initial: root.launchPort
                      placeholder: "443"
                      onEdited: text => root.launchPort = text
                    }
                  }

                  PrimaryBtn {
                    width: parent.width
                    enabledBtn: root.launchButtonAction !== "empty"
                    text: root.launchButtonText
                    glyph: root.launchButtonGlyph
                    fill: {
                      if (root.launchButtonAction === "stop") return t.red;
                      if (root.launchMode === "funnel") return t.violet;
                      return t.accent;
                    }
                    onClicked: root.launchPrimary()
                  }
                }
              }
          }
        }

        // ============ TAB 1: DEVICES ============
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 1 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 110 } }

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: devicesCol.height
            clip: true

            Column {
              id: devicesCol
              width: parent.width
              spacing: 12

              SectionHead {
                width: parent.width
                label: "Devices on this tailnet"
              }

              Rectangle {
                visible: root.peers.length > 0
                width: parent.width
                height: peersCol.height
                radius: 12
                color: t.surface

                Column {
                  id: peersCol
                  width: parent.width

                  Repeater {
                    model: root.peers
                    Column {
                      required property var modelData
                      required property int index
                      width: peersCol.width

                      RowBase {
                        width: parent.width
                        height: 58
                        rad: (index === 0 || index === root.peers.length - 1) ? 10 : 0
                        actionable: Boolean(modelData.ipv4)
                        onClicked: root.copyText(modelData.ipv4, "Peer IP")
                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 10
                          spacing: 10
                          Text {
                            text: root.osIcon(modelData.os)
                            font.family: t.mono
                            font.pixelSize: 15
                            color: modelData.online ? t.ink2 : t.ink3
                          }
                          Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                              width: parent.width
                              text: modelData.hostname || "Device"
                              font.pixelSize: 13
                              font.weight: Font.Medium
                              color: modelData.online ? t.ink1 : t.ink3
                              elide: Text.ElideRight
                            }
                            Text {
                              text: modelData.ipv4 || modelData.dns_name
                              font.family: t.mono
                              font.pixelSize: 11
                              color: t.ink3
                            }
                          }
                          Text {
                            visible: !modelData.online
                            text: "Offline"
                            font.pixelSize: 11
                            color: t.ink3
                          }
                          TextBtn {
                            visible: Boolean(modelData.online)
                            property string pd: root.pingDisplay(modelData.ipv4)
                            text: pd.length > 0 ? pd : "Ping"
                            fs: 11
                            fg: {
                              if (pd.length === 0 || pd === "…") return t.accent;
                              return pd.includes("ms") ? t.green : t.amber;
                            }
                            onClicked: root.pingPeer(modelData.ipv4)
                          }
                        }
                      }

                      Hairline {
                        visible: index < root.peers.length - 1
                        width: parent.width - 24
                        anchors.horizontalCenter: parent.horizontalCenter
                      }
                    }
                  }
                }
              }

              Item {
                visible: root.peers.length === 0
                width: parent.width
                height: 64
                Column {
                  anchors.centerIn: parent
                  spacing: 3
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No devices nearby"
                    font.pixelSize: 12
                    color: t.ink2
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Devices on your tailnet will appear here."
                    font.pixelSize: 11
                    color: t.ink3
                  }
                }
              }
            }
          }
        }

        // ============ TAB 2: SETTINGS ============
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 2 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 110 } }

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: settingsCol.height
            clip: true

            Column {
              id: settingsCol
              width: parent.width
              spacing: 12

              SectionHead {
                width: parent.width
                label: "This device"
              }

              Rectangle {
                width: parent.width
                height: prefsCol.height
                radius: 12
                color: t.surface

                Column {
                  id: prefsCol
                  width: parent.width

                  // SSH
                  Column {
                    width: parent.width
                    RowBase {
                      width: parent.width
                      height: 54
                      rad: 12
                      onClicked: {
                        const next = !(root.tsData.ssh_enabled);
                        root.runAction(["ssh-toggle", next ? "true" : "false"], next ? "Tailscale SSH Enabled" : "Tailscale SSH Disabled");
                      }
                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        Text {
                          text: "󰒍"
                          font.family: t.mono
                          font.pixelSize: 15
                          color: root.tsData.ssh_enabled ? t.green : t.ink3
                        }
                        Column {
                          Layout.fillWidth: true
                          spacing: 1
                          Text {
                            text: "Secure shell"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: t.ink1
                          }
                          Text {
                            text: root.tsData.ssh_enabled ? "Tailnet devices can sign in over SSH" : "Let tailnet devices sign in over SSH"
                            font.pixelSize: 11
                            color: t.ink3
                          }
                        }
                        TSwitch {
                          on: Boolean(root.tsData.ssh_enabled)
                          onToggled: {
                            const next2 = !(root.tsData.ssh_enabled);
                            root.runAction(["ssh-toggle", next2 ? "true" : "false"], next2 ? "Tailscale SSH Enabled" : "Tailscale SSH Disabled");
                          }
                        }
                      }
                    }

                    Item {
                      visible: Boolean(root.tsData.ssh_enabled)
                      width: parent.width
                      height: visible ? sshCmds.height + 12 : 0
                      clip: true
                      Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                      Column {
                        id: sshCmds
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 4
                        Repeater {
                          model: root.sshCommands()
                          RowBase {
                            required property string modelData
                            width: sshCmds.width
                            height: 30
                            base: t.inset
                            rad: 8
                            hover: t.hoverFill
                            press: t.selected
                            onClicked: root.copyText(modelData, "SSH command")
                            RowLayout {
                              anchors.fill: parent
                              anchors.leftMargin: 10
                              anchors.rightMargin: 10
                              Text {
                                Layout.fillWidth: true
                                text: modelData
                                font.family: t.mono
                                font.pixelSize: 11
                                color: t.ink1
                                elide: Text.ElideRight
                              }
                              Text {
                                text: "Copy"
                                font.pixelSize: 11
                                color: t.ink3
                              }
                            }
                          }
                        }
                        Item { width: 1; height: 2 }
                      }
                    }
                  }

                  Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

                  // Web admin
                  RowBase {
                    width: parent.width
                    height: 54
                    onClicked: {
                      const next = !(root.tsData.webclient_enabled);
                      root.runAction(["set-pref", "webclient", next ? "true" : "false"], "Updated Web UI setting");
                    }
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      spacing: 10
                      Text {
                        text: "󰖟"
                        font.family: t.mono
                        font.pixelSize: 15
                        color: root.tsData.webclient_enabled ? t.accent : t.ink3
                      }
                      Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                          text: "Web admin"
                          font.pixelSize: 13
                          font.weight: Font.Medium
                          color: t.ink1
                        }
                        Text {
                          text: "Local dashboard on port 5252"
                          font.pixelSize: 11
                          color: t.ink3
                        }
                      }
                      TextBtn {
                        visible: Boolean(root.tsData.webclient_enabled)
                        text: "Open"
                        fs: 11
                        fg: t.accent
                        onClicked: root.openUrl("http://localhost:5252")
                      }
                      TSwitch {
                        on: Boolean(root.tsData.webclient_enabled)
                        onToggled: {
                          const next2 = !(root.tsData.webclient_enabled);
                          root.runAction(["set-pref", "webclient", next2 ? "true" : "false"], "Updated Web UI setting");
                        }
                      }
                    }
                  }

                  Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

                  // Exit node
                  RowBase {
                    width: parent.width
                    height: 54
                    onClicked: {
                      const next = !(root.tsData.exit_node_enabled);
                      root.runAction(["set-pref", "advertise-exit-node", next ? "true" : "false"], "Updated exit node setting");
                    }
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      spacing: 10
                      Text {
                        text: "󰌽"
                        font.family: t.mono
                        font.pixelSize: 15
                        color: root.tsData.exit_node_enabled ? t.accent : t.ink3
                      }
                      Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                          text: "Exit node"
                          font.pixelSize: 13
                          font.weight: Font.Medium
                          color: t.ink1
                        }
                        Text {
                          text: "Route tailnet traffic through this device"
                          font.pixelSize: 11
                          color: t.ink3
                        }
                      }
                      TSwitch {
                        on: Boolean(root.tsData.exit_node_enabled)
                        onToggled: {
                          const next2 = !(root.tsData.exit_node_enabled);
                          root.runAction(["set-pref", "advertise-exit-node", next2 ? "true" : "false"], "Updated exit node setting");
                        }
                      }
                    }
                  }

                  Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

                  // Shields up
                  RowBase {
                    width: parent.width
                    height: 54
                    rad: 12
                    onClicked: {
                      const next = !(root.tsData.shields_up);
                      root.runAction(["set-pref", "shields-up", next ? "true" : "false"], "Updated shields-up setting");
                    }
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      spacing: 10
                      Text {
                        text: "󰒃"
                        font.family: t.mono
                        font.pixelSize: 15
                        color: root.tsData.shields_up ? t.red : t.ink3
                      }
                      Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                          text: "Shields up"
                          font.pixelSize: 13
                          font.weight: Font.Medium
                          color: t.ink1
                        }
                        Text {
                          text: "Block incoming tailnet connections"
                          font.pixelSize: 11
                          color: t.ink3
                        }
                      }
                      TSwitch {
                        on: Boolean(root.tsData.shields_up)
                        onColor: t.red
                        onToggled: {
                          const next2 = !(root.tsData.shields_up);
                          root.runAction(["set-pref", "shields-up", next2 ? "true" : "false"], "Updated shields-up setting");
                        }
                      }
                    }
                  }
                }
              }

              // Health notice: tinted wash, no border shouting.
              Rectangle {
                visible: root.health.length > 0
                width: parent.width
                height: healthRow.height + 20
                radius: 10
                color: Qt.rgba(t.amber.r, t.amber.g, t.amber.b, 0.1)
                Row {
                  id: healthRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 10
                  spacing: 8
                  Text {
                    text: "!"
                    font.pixelSize: 12
                    font.bold: true
                    color: t.amber
                  }
                  Text {
                    width: parent.width - 20
                    text: root.health.join("\n")
                    font.pixelSize: 11
                    color: t.amber
                    wrapMode: Text.Wrap
                  }
                }
              }

              SectionHead {
                width: parent.width
                label: "Diagnostics"
              }

              Rectangle {
                width: parent.width
                height: netCol.height + 24
                radius: 12
                color: t.surface

                Column {
                  id: netCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 12
                  spacing: 10

                  RowLayout {
                    width: parent.width
                    Column {
                      Layout.fillWidth: true
                      spacing: 1
                      Text {
                        text: "Connection test"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: t.ink1
                      }
                      Text {
                        text: "Relays, NAT mapping and latency"
                        font.pixelSize: 11
                        color: t.ink3
                      }
                    }
                    TextBtn {
                      text: root.netBusy ? "Testing…" : "Run"
                      fs: 11
                      bold: true
                      fg: t.accent
                      onClicked: root.runNetcheck()
                    }
                  }

                  Rectangle {
                    visible: root.netReport.length > 0
                    width: parent.width
                    height: 104
                    radius: 8
                    color: t.inset
                    Flickable {
                      anchors.fill: parent
                      anchors.margins: 8
                      contentWidth: width
                      contentHeight: reportText.implicitHeight
                      clip: true
                      Text {
                        id: reportText
                        width: parent.width
                        text: root.netReport
                        font.family: t.mono
                        font.pixelSize: 10
                        color: t.ink2
                        wrapMode: Text.Wrap
                      }
                    }
                  }
                }
              }

              Text {
                visible: Boolean(root.tsData.version && root.tsData.version.length > 0)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Tailscale " + root.tsData.version
                font.pixelSize: 11
                color: t.ink3
              }
            }
          }
        }
      }
    }

    Toast {
      id: toast
      timeout: 2500
    }
  }
}
