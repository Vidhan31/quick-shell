pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Plugins.Tailscale
import "../theme"
import "../components"

Item {
  id: root

  property var tailscale: null
  property TailscaleMonitor monitor: (tailscale && tailscale.monitor) ? tailscale.monitor : tailscale
  readonly property TailscaleMonitor activeMonitor: monitor

  implicitWidth: Theme.popupWidthMd
  implicitHeight: 620

  readonly property var t: Theme

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

  property string launchTarget: "https+insecure://localhost:5137"
  property string launchPort: "443"
  property string launchPath: "/"
  property string launchMode: "serve" // "serve" or "funnel"
  property bool initialTargetSynced: false

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

  PopupCard {
    id: card
    anchors.fill: parent

    ColumnLayout {
      anchors.fill: parent
      spacing: 0

      PopupHeader {
        Layout.fillWidth: true
        glyph: "󱗼"
        glyphColor: root.connected ? root.t.accent : root.t.ink3
        title: "Tailscale"
        subtitle: {
          if (!root.connected) return (root.tsData && root.tsData.backend_state) ? root.tsData.backend_state : "Not connected";
          const self = root.tsData && root.tsData.self;
          const host = self && self.hostname ? self.hostname : "";
          const ip = self && self.ipv4 ? self.ipv4 : "";
          if (host && ip) return host + " · " + ip;
          if (host) return host;
          return (root.tsData && root.tsData.tailnet) ? root.tsData.tailnet : "Connected";
        }

        IconBtn {
          glyph: "󰑓"
          fs: Theme.iconBase
          tooltip: "Refresh status"
          spinning: root.busy
          onClicked: root.refresh()
        }

        TSwitch {
          on: root.connected
          tooltip: root.connected ? "Connected to Tailscale" : "Disconnected"
          onToggled: root.toggleConnection()
        }
      }

      Item { Layout.preferredHeight: 12; Layout.fillWidth: true }

      Segments {
        Layout.fillWidth: true
        items: root.segItems
        current: root.currentTab
        onSelected: index => root.currentTab = index
      }

      Item { Layout.preferredHeight: 10; Layout.fillWidth: true }

      StackLayout {
        id: tabStack
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: root.currentTab

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 0 ? 1 : 0
          Behavior on opacity { OpacityAnimator { duration: 110 } }

          ColumnLayout {
            anchors.fill: parent
            spacing: 10

            SectionHead {
              visible: root.serveItems.length > 0
              Layout.fillWidth: true
              label: "Active shares"
              actionGlyph: root.serveItems.length > 0 ? "󰃢" : ""
              actionColor: root.t.err
              onActionClicked: root.runAction(["serve-reset"], "Reset all serve endpoints")
            }

            SectionCard {
              visible: root.serveItems.length > 0
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: 56

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
                      id: serveRow
                      required property var modelData
                      required property int index
                      width: sharesCol.width

                      RowBase {
                        width: parent.width
                        height: 48
                        rad: (serveRow.index === 0 && root.serveItems.length === 1) ? 10 : 0
                        onClicked: {
                          targetField.setText(serveRow.modelData.target || serveRow.modelData.url);
                          root.selectTarget(serveRow.modelData.target || serveRow.modelData.url);
                        }
                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 8
                          spacing: 8
                          Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                              width: parent.width
                              text: serveRow.modelData.url
                              font.pixelSize: Theme.fontBase
                              font.weight: Font.Medium
                              color: root.t.ink1
                              elide: Text.ElideRight
                            }
                            Row {
                              width: parent.width
                              spacing: 5
                              Text {
                                text: serveRow.modelData.is_funnel ? "Public" : "Tailnet"
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.DemiBold
                                color: serveRow.modelData.is_funnel ? root.t.violet : root.t.accent
                              }
                              Text {
                                text: "·"
                                font.pixelSize: Theme.fontXs
                                color: root.t.ink3
                              }
                              Text {
                                width: parent.width - 90
                                text: ":" + serveRow.modelData.port + " → " + serveRow.modelData.target
                                font.family: root.t.mono
                                font.pixelSize: Theme.fontXs
                                color: root.t.ink3
                                elide: Text.ElideRight
                              }
                            }
                          }

                          Row {
                            spacing: 2
                            IconBtn {
                              glyph: "󰆏"
                              fs: 12
                              btnSize: 26
                              fg: root.t.ink2
                              onClicked: root.copyText(serveRow.modelData.url, "URL")
                            }
                            IconBtn {
                              glyph: "󰖟"
                              fs: 12
                              btnSize: 26
                              fg: root.t.ink2
                              onClicked: root.openUrl(serveRow.modelData.url)
                            }
                            IconBtn {
                              glyph: serveRow.modelData.is_funnel ? "󰌾" : "󰌿"
                              fs: 12
                              btnSize: 26
                              fg: serveRow.modelData.is_funnel ? root.t.violet : root.t.accent
                              onClicked: root.flipScope(serveRow.modelData)
                            }
                            IconBtn {
                              glyph: "󰅙"
                              fs: 12
                              btnSize: 26
                              fg: root.t.err
                              onClicked: root.stopEndpoint(serveRow.modelData.port)
                            }
                          }
                        }
                      }

                      Item { width: 1; height: 6 }

                      Hairline {
                        visible: serveRow.index < root.serveItems.length - 1
                        width: parent.width - 24
                        anchors.horizontalCenter: parent.horizontalCenter
                      }
                    }
                  }
                }
              }
            }

            SectionCard {
              id: composerRect
              Layout.fillWidth: true
              Layout.preferredHeight: composerCol.height + 20

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

                Row {
                  width: parent.width
                  spacing: 2
                  Repeater {
                    model: root.suggestions
                    TextBtn {
                      id: suggestionBtn
                      required property var modelData
                      property var ep: root.findActiveEndpoint(suggestionBtn.modelData.addr, "")
                      property bool selected: root.targetsMatch(root.launchTarget, suggestionBtn.modelData.addr)
                      text: suggestionBtn.modelData.name + " · " + root.extractPort(suggestionBtn.modelData.addr)
                      fs: 11
                      bold: selected
                      fg: {
                        if (selected) return root.t.ink1;
                        if (ep) return ep.is_funnel ? root.t.violet : root.t.accent;
                        return root.t.ink3;
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
                      if (root.launchButtonAction === "stop") return root.t.red;
                      if (root.launchMode === "funnel") return root.t.violet;
                      return root.t.accent;
                    }
                    onClicked: root.launchPrimary()
                  }
                }
              }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 1 ? 1 : 0
          Behavior on opacity { OpacityAnimator { duration: 110 } }

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: devicesCol.height
            clip: true

            Column {
              id: devicesCol
              width: parent.width
              spacing: 8

              SectionCard {
                visible: root.peers.length > 0
                width: parent.width
                height: peersCol.height

                Column {
                  id: peersCol
                  width: parent.width

                  Repeater {
                    model: root.peers
                    Column {
                      id: peerRow
                      required property var modelData
                      required property int index
                      width: peersCol.width

                      RowBase {
                        width: parent.width
                        height: 58
                        rad: (peerRow.index === 0 || peerRow.index === root.peers.length - 1) ? 10 : 0
                        actionable: Boolean(peerRow.modelData.ipv4)
                        onClicked: root.copyText(peerRow.modelData.ipv4, "Peer IP")
                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 10
                          spacing: 10
                          Text {
                            text: root.osIcon(peerRow.modelData.os)
                            font.family: root.t.mono
                            font.pixelSize: 15
                            color: peerRow.modelData.online ? root.t.ink2 : root.t.ink3
                          }
                          Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                              width: parent.width
                              text: peerRow.modelData.hostname || "Device"
                              font.pixelSize: Theme.fontMd
                              font.weight: Font.Medium
                              color: peerRow.modelData.online ? root.t.ink1 : root.t.ink3
                              elide: Text.ElideRight
                            }
                            Text {
                              text: peerRow.modelData.ipv4 || peerRow.modelData.dns_name
                              font.family: root.t.mono
                              font.pixelSize: Theme.fontSm
                              color: root.t.ink3
                            }
                          }
                          Text {
                            visible: !peerRow.modelData.online
                            text: "Offline"
                            font.pixelSize: Theme.fontSm
                            color: root.t.ink3
                          }
                          TextBtn {
                            visible: Boolean(peerRow.modelData.online)
                            property string pd: root.pingDisplay(peerRow.modelData.ipv4)
                            text: pd.length > 0 ? pd : "Ping"
                            fs: 11
                            fg: {
                              if (pd.length === 0 || pd === "…") return root.t.accent;
                              return pd.includes("ms") ? root.t.green : root.t.amber;
                            }
                            onClicked: root.pingPeer(peerRow.modelData.ipv4)
                          }
                        }
                      }

                      Hairline {
                        visible: peerRow.index < root.peers.length - 1
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
                    font.pixelSize: Theme.fontBase
                    color: root.t.ink2
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Devices on your tailnet will appear here."
                    font.pixelSize: Theme.fontSm
                    color: root.t.ink3
                  }
                }
              }
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 2 ? 1 : 0
          Behavior on opacity { OpacityAnimator { duration: 110 } }

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

              SectionCard {
                width: parent.width
                height: prefsCol.height

                Column {
                  id: prefsCol
                  width: parent.width

                  RowBase {
                    width: parent.width
                    height: 38
                    rad: Theme.radiusSection
                    actionable: Boolean(root.tsData.self && root.tsData.self.hostname)
                    onClicked: root.copyText((root.tsData.self && root.tsData.self.hostname) || "", "Hostname")
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      spacing: 8
                      Text {
                        text: "󰌽"
                        font.family: root.t.mono
                        font.pixelSize: Theme.fontBase
                        color: root.t.ink2
                      }
                      Text {
                        text: "Hostname"
                        font.pixelSize: Theme.fontBase
                        color: root.t.ink2
                      }
                      Item { Layout.fillWidth: true }
                      Text {
                        text: (root.tsData.self && root.tsData.self.hostname) ? root.tsData.self.hostname : "This device"
                        font.pixelSize: Theme.fontBase
                        font.weight: Font.Medium
                        color: root.t.ink1
                        elide: Text.ElideRight
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
                      spacing: 8
                      Text {
                        text: "IP address"
                        font.pixelSize: Theme.fontBase
                        color: root.t.ink2
                      }
                      Item { Layout.fillWidth: true }
                      Text {
                        text: (root.tsData.self && root.tsData.self.ipv4) ? root.tsData.self.ipv4 : "—"
                        font.family: root.t.mono
                        font.pixelSize: Theme.fontBase
                        color: root.t.ink1
                      }
                    }
                  }

                  Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

                  RowBase {
                    width: parent.width
                    height: 38
                    actionable: Boolean(root.tsData.self && root.tsData.self.dns_name)
                    onClicked: root.copyText((root.tsData.self && root.tsData.self.dns_name) || "", "Domain")
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      spacing: 8
                      Text {
                        text: "MagicDNS"
                        font.pixelSize: Theme.fontBase
                        color: root.t.ink2
                      }
                      Item { Layout.fillWidth: true }
                      Text {
                        Layout.maximumWidth: 200
                        text: (root.tsData.self && root.tsData.self.dns_name) ? root.tsData.self.dns_name : "—"
                        font.family: root.t.mono
                        font.pixelSize: Theme.fontBase
                        color: root.t.ink1
                        elide: Text.ElideMiddle
                      }
                    }
                  }

                  Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

                  Column {
                    width: parent.width
                    RowBase {
                      width: parent.width
                      height: 40
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
                          font.family: root.t.mono
                          font.pixelSize: 15
                          color: root.tsData.ssh_enabled ? root.t.green : root.t.ink3
                        }
                        Text {
                          Layout.fillWidth: true
                          text: "SSH server"
                          font.pixelSize: Theme.fontBase
                          font.weight: Font.Medium
                          color: root.t.ink1
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
                      Behavior on height { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
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
                            id: sshRow
                            required property string modelData
                            width: sshCmds.width
                            height: 28
                            base: root.t.inset
                            rad: 6
                            hover: root.t.hoverFill
                            press: root.t.selected
                            onClicked: root.copyText(modelData, "SSH command")
                            RowLayout {
                              anchors.fill: parent
                              anchors.leftMargin: 8
                              anchors.rightMargin: 8
                              Text {
                                Layout.fillWidth: true
                                text: sshRow.modelData
                                font.family: root.t.mono
                                font.pixelSize: Theme.fontXs
                                color: root.t.ink1
                                elide: Text.ElideRight
                              }
                              Text {
                                text: "Copy"
                                font.pixelSize: Theme.fontXs
                                color: root.t.accent
                              }
                            }
                          }
                        }
                        Item { width: 1; height: 2 }
                      }
                    }
                  }

                  Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

                  RowBase {
                    width: parent.width
                    height: 40
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
                        font.family: root.t.mono
                        font.pixelSize: 15
                        color: root.tsData.webclient_enabled ? root.t.accent : root.t.ink3
                      }
                      Text {
                        Layout.fillWidth: true
                        text: "Web admin"
                        font.pixelSize: Theme.fontBase
                        font.weight: Font.Medium
                        color: root.t.ink1
                      }
                      TextBtn {
                        visible: Boolean(root.tsData.webclient_enabled)
                        text: "Open"
                        fs: 11
                        fg: root.t.accent
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

                  RowBase {
                    width: parent.width
                    height: 40
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
                        font.family: root.t.mono
                        font.pixelSize: 15
                        color: root.tsData.exit_node_enabled ? root.t.accent : root.t.ink3
                      }
                      Text {
                        Layout.fillWidth: true
                        text: "Exit node"
                        font.pixelSize: Theme.fontBase
                        font.weight: Font.Medium
                        color: root.t.ink1
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

                  RowBase {
                    width: parent.width
                    height: 40
                    rad: Theme.radiusSection
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
                        font.family: root.t.mono
                        font.pixelSize: 15
                        color: root.tsData.shields_up ? root.t.red : root.t.ink3
                      }
                      Text {
                        Layout.fillWidth: true
                        text: "Shields up"
                        font.pixelSize: Theme.fontBase
                        font.weight: Font.Medium
                        color: root.t.ink1
                      }
                      TSwitch {
                        on: Boolean(root.tsData.shields_up)
                        onColor: root.t.red
                        onToggled: {
                          const next2 = !(root.tsData.shields_up);
                          root.runAction(["set-pref", "shields-up", next2 ? "true" : "false"], "Updated shields-up setting");
                        }
                      }
                    }
                  }
                }
              }

              Rectangle {
                visible: root.health.length > 0
                width: parent.width
                height: healthRow.height + 20
                radius: Theme.radiusChip
                color: Theme.tint(root.t.amber, 0.1)
                Row {
                  id: healthRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 10
                  spacing: 8
                  Text {
                    text: "!"
                    font.pixelSize: Theme.fontBase
                    font.bold: true
                    color: root.t.amber
                  }
                  Text {
                    width: parent.width - 20
                    text: root.health.join("\n")
                    font.pixelSize: Theme.fontSm
                    color: root.t.amber
                    wrapMode: Text.Wrap
                  }
                }
              }

              SectionHead {
                width: parent.width
                label: "Diagnostics"
              }

              SectionCard {
                width: parent.width
                height: netCol.height + 24

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
                        font.pixelSize: Theme.fontMd
                        font.weight: Font.Medium
                        color: root.t.ink1
                      }
                      Text {
                        text: "Relays, NAT mapping and latency"
                        font.pixelSize: Theme.fontSm
                        color: root.t.ink3
                      }
                    }
                    TextBtn {
                      text: root.netBusy ? "Testing…" : "Run"
                      fs: 11
                      bold: true
                      fg: root.t.accent
                      onClicked: root.runNetcheck()
                    }
                  }

                  Rectangle {
                    visible: root.netReport.length > 0
                    width: parent.width
                    height: 104
                    radius: Theme.radiusBase
                    color: root.t.inset
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
                        font.family: root.t.mono
                        font.pixelSize: Theme.fontXs
                        color: root.t.ink2
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
                font.pixelSize: Theme.fontSm
                color: root.t.ink3
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
