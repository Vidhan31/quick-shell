// TailscaleControlCenter.qml — Control center for Tailscale SSH, Serve, Funnel, Peers & Diagnostics.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Plugins.Tailscale

Item {
  id: root

  property TailscaleMonitor monitor: null
  TailscaleMonitor {
    id: fallbackMonitor
    running: root.monitor === null
  }
  readonly property TailscaleMonitor activeMonitor: root.monitor ? root.monitor : fallbackMonitor

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  implicitWidth: 440
  implicitHeight: 520
  width: implicitWidth
  height: implicitHeight

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

  property int currentTab: 0 // 0: Serve & Funnel, 1: SSH Access, 2: Peers, 3: Settings & Diag
  property string toastMessage: ""
  property bool isBusy: false
  property string pingResult: ""
  property string pingTargetIp: ""
  property string netcheckReport: ""
  property bool isRunningNetcheck: false

  // Launcher input properties
  property string launchTarget: "https+insecure://localhost:5137"
  property string launchPort: "443"
  property string launchPath: "/"
  property string launchMode: "serve" // "serve" or "funnel"
  property bool initialTargetSynced: false

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
    if (!target) return null;
    const items = (root.tsData && root.tsData.serve_items) ? root.tsData.serve_items : [];
    if (!items || items.length === 0) return null;

    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      if (root.targetsMatch(target, it.target) || root.targetsMatch(target, it.url)) {
        if (!port || port === "" || it.port === port) {
          return it;
        }
      }
    }

    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      if (root.targetsMatch(target, it.target) || root.targetsMatch(target, it.url)) {
        return it;
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
      return "Enter URL or Port to Start";
    }
    if (root.launchButtonAction === "stop") {
      return "Stop " + (root.launchMode === "funnel" ? "Funnel Service" : "Serve Service");
    }
    if (root.launchButtonAction === "switch") {
      return root.launchMode === "funnel" ? "Switch to Public (Funnel)" : "Switch to Tailnet (Serve)";
    }
    return "Start " + (root.launchMode === "funnel" ? "Funnel Service" : "Serve Service");
  }

  readonly property string launchButtonIcon: {
    if (root.launchButtonAction === "empty") return "✎";
    if (root.launchButtonAction === "stop") return "⏹";
    if (root.launchButtonAction === "switch") return root.launchMode === "funnel" ? "󱂛" : "󰈡";
    return "▶";
  }

  function showToast(msg: string): void {
    root.toastMessage = msg;
    toastTimer.restart();
  }

  Timer {
    id: toastTimer
    interval: 2500
    onTriggered: root.toastMessage = ""
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

  function pingPeer(ip: string): void {
    if (!ip) return;
    root.pingTargetIp = ip;
    root.pingResult = "Pinging…";
    if (root.activeMonitor) {
      root.activeMonitor.ping(ip);
    }
  }

  function runNetcheck(): void {
    root.isRunningNetcheck = true;
    root.netcheckReport = "Running diagnostic netcheck…";
    if (root.activeMonitor) {
      root.activeMonitor.netcheck();
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
      if (root.pingTargetIp === targetIp) {
        root.pingResult = ok ? latency : (latency ? latency : "No reply");
      }
    }
    function onNetcheckStatusChanged() {
      if (root.activeMonitor) {
        root.isRunningNetcheck = root.activeMonitor.isRunningNetcheck;
        root.netcheckReport = root.activeMonitor.netcheckReport;
      }
    }
    function onStateChanged() {
      if (!root.initialTargetSynced && root.tsData && root.tsData.serve_items && root.tsData.serve_items.length > 0) {
        root.initialTargetSynced = true;
        root.selectTarget(root.launchTarget);
      }
    }
  }

  Rectangle {
    id: card
    anchors.fill: parent
    radius: 16
    color: "#1e1e2e"
    border.color: "#313244"
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 10

      // Header row: Logo, Title, Status pill, Refresh button
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28

        Row {
          spacing: 8
          Layout.alignment: Qt.AlignVCenter

          Text {
            text: "󰖩"
            font.family: root.monoFont
            font.pixelSize: 18
            color: root.tsData.connected ? "#89b4fa" : "#f38ba8"
          }

          Text {
            text: "Tailscale"
            font.family: root.monoFont
            font.pixelSize: 15
            font.bold: true
            color: "#cdd6f4"
          }
        }

        Item { Layout.fillWidth: true }

        // Up/Down connect toggle pill
        Rectangle {
          id: connectPill
          width: connectPillRow.width + 16
          height: 26
          radius: 13
          color: root.tsData.connected ? "#1e382b" : "#3b2229"
          border.color: root.tsData.connected ? "#a6e3a1" : "#f38ba8"
          border.width: 1

          Row {
            id: connectPillRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
              width: 7
              height: 7
              radius: 3.5
              anchors.verticalCenter: parent.verticalCenter
              color: root.tsData.connected ? "#a6e3a1" : "#f38ba8"
            }

            Text {
              text: root.tsData.connected ? "Connected" : "Disconnected"
              font.family: root.monoFont
              font.pixelSize: 11
              font.bold: true
              color: root.tsData.connected ? "#a6e3a1" : "#f38ba8"
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: {
              const action = root.tsData.connected ? "down" : "up";
              root.runAction(["up-down", action], root.tsData.connected ? "Disconnecting…" : "Connecting…");
            }
          }
        }

        // Refresh button
        Rectangle {
          width: 26
          height: 26
          radius: 6
          color: refreshMouse.containsMouse ? "#45475a" : "#313244"

          Text {
            anchors.centerIn: parent
            text: "󰑓"
            font.family: root.monoFont
            font.pixelSize: 13
            color: root.isBusy ? "#89b4fa" : "#cdd6f4"
            rotation: root.isBusy ? 360 : 0
            Behavior on rotation { NumberAnimation { duration: 600; loops: Animation.Infinite } }
          }

          MouseArea {
            id: refreshMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.refresh()
          }
        }
      }

      // Self device banner
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: selfInfoCol.height + 16
        radius: 10
        color: "#181825"
        border.color: "#313244"
        border.width: 1

        Column {
          id: selfInfoCol
          anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 8
          }
          spacing: 8

          // Node host + User + Tailnet
          RowLayout {
            width: parent.width

            Row {
              spacing: 6
              Text {
                text: "󰌽"
                font.family: root.monoFont
                font.pixelSize: 12
                color: "#89b4fa"
              }
              Text {
                text: (root.tsData.self && root.tsData.self.hostname) ? root.tsData.self.hostname : "This Device"
                font.family: root.monoFont
                font.pixelSize: 12
                font.bold: true
                color: "#cdd6f4"
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              text: (root.tsData.tailnet ? root.tsData.tailnet : "") + (root.tsData.self && root.tsData.self.relay ? " (" + root.tsData.self.relay + ")" : "")
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#a6adc8"
            }
          }

          // IP and DNS row with copy buttons
          RowLayout {
            width: parent.width
            spacing: 8

            // IPv4 chip
            Rectangle {
              Layout.preferredWidth: 150
              Layout.fillWidth: false
              height: 26
              radius: 6
              color: ipMouse.containsMouse ? "#3b3e52" : "#313244"

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Text {
                  text: "IP: " + ((root.tsData.self && root.tsData.self.ipv4) ? root.tsData.self.ipv4 : "—")
                  font.family: root.monoFont
                  font.pixelSize: 11
                  color: "#a6e3a1"
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }

                Text {
                  text: "󰆏"
                  font.family: root.monoFont
                  font.pixelSize: 10
                  color: "#a6adc8"
                }
              }

              MouseArea {
                id: ipMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: root.copyText(root.tsData.self.ipv4, "IP Address")
              }
            }

            // MagicDNS domain chip
            Rectangle {
              Layout.fillWidth: true
              height: 26
              radius: 6
              color: dnsMouse.containsMouse ? "#3b3e52" : "#313244"

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Text {
                  text: (root.tsData.self && root.tsData.self.dns_name) ? root.tsData.self.dns_name : "MagicDNS"
                  elide: Text.ElideMiddle
                  Layout.fillWidth: true
                  font.family: root.monoFont
                  font.pixelSize: 11
                  color: "#89b4fa"
                }

                Text {
                  text: "󰆏"
                  font.family: root.monoFont
                  font.pixelSize: 10
                  color: "#a6adc8"
                }
              }

              MouseArea {
                id: dnsMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: root.copyText(root.tsData.self.dns_name, "Domain")
              }
            }
          }
        }
      }

      // Toast feedback banner
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        radius: 6
        color: "#1e382b"
        border.color: "#a6e3a1"
        border.width: 1
        visible: root.toastMessage.length > 0

        Text {
          anchors.centerIn: parent
          text: "✓ " + root.toastMessage
          font.family: root.monoFont
          font.pixelSize: 11
          font.bold: true
          color: "#a6e3a1"
        }
      }

      // Tab selector row
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 6

        Repeater {
          model: [
            { name: "Serve", icon: "󰖟", count: root.tsData.serve_items ? root.tsData.serve_items.length : 0 },
            { name: "SSH", icon: "󰒍", count: root.tsData.ssh_enabled ? 1 : 0 },
            { name: "Peers", icon: "󰀲", count: root.tsData.peers ? root.tsData.peers.length : 0 },
            { name: "Settings", icon: "󰒢", count: 0 }
          ]

          Rectangle {
            required property var modelData
            required property int index

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: root.currentTab === index ? "#45475a" : (tabMouse.containsMouse ? "#3b3e52" : "#313244")
            border.color: root.currentTab === index ? "#89b4fa" : "transparent"
            border.width: 1

            Row {
              anchors.centerIn: parent
              spacing: 5

              Text {
                text: modelData.icon
                font.family: root.monoFont
                font.pixelSize: 12
                color: root.currentTab === index ? "#89b4fa" : "#a6adc8"
              }

              Text {
                text: modelData.name + (modelData.count > 0 ? " (" + modelData.count + ")" : "")
                font.family: root.monoFont
                font.pixelSize: 11
                font.bold: root.currentTab === index
                color: root.currentTab === index ? "#cdd6f4" : "#a6adc8"
              }
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: root.currentTab = index
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: "#313244"
      }

      // STACK OF TABS
      StackLayout {
        id: tabStack
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: root.currentTab

        // TAB 0: SERVE & FUNNEL
        Item {
          id: tab0
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: tab0Col.height
            clip: true

            Column {
              id: tab0Col
              width: parent.width
              spacing: 10

              // Active Endpoints Section Header
              RowLayout {
                width: parent.width

                Text {
                  text: "Active Endpoints (" + (root.tsData.serve_items ? root.tsData.serve_items.length : 0) + ")"
                  font.family: root.monoFont
                  font.pixelSize: 12
                  font.bold: true
                  color: "#cdd6f4"
                }

                Item { Layout.fillWidth: true }

                // Reset All button
                Rectangle {
                  visible: root.tsData.serve_items && root.tsData.serve_items.length > 0
                  width: resetText.width + 12
                  height: 22
                  radius: 4
                  color: resetMouse.containsMouse ? "#585b70" : "#313244"

                  Text {
                    id: resetText
                    anchors.centerIn: parent
                    text: "Reset All"
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: "#f38ba8"
                  }

                  MouseArea {
                    id: resetMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.runAction(["serve-reset"], "Reset all serve endpoints")
                  }
                }
              }

              // List of Active Serve / Funnel Endpoints
              Repeater {
                model: root.tsData.serve_items || []

                Rectangle {
                  required property var modelData
                  required property int index

                  readonly property bool isSelected: root.targetsMatch(root.launchTarget, modelData.target) || root.targetsMatch(root.launchTarget, modelData.url)

                  width: tab0Col.width
                  height: itemCol.height + 16
                  radius: 8
                  color: isSelected ? "#212234" : "#181825"
                  border.color: isSelected
                    ? (modelData.is_funnel ? "#f5c2e7" : "#b4befe")
                    : (modelData.is_funnel ? "#cba6f7" : "#89b4fa")
                  border.width: isSelected ? 2 : 1

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    z: 0
                    onClicked: root.selectTarget(modelData.target || modelData.url)
                  }

                  Column {
                    id: itemCol
                    z: 1
                    anchors {
                      left: parent.left
                      right: parent.right
                      top: parent.top
                      margins: 8
                    }
                    spacing: 6

                    // Top row: Scope badge, Port badge, Target info
                    RowLayout {
                      width: parent.width

                      // Scope badge
                      Rectangle {
                        width: scopeLabel.width + 10
                        height: 18
                        radius: 4
                        color: modelData.is_funnel ? "#4a2958" : "#22384f"
                        border.color: modelData.is_funnel ? "#cba6f7" : "#89b4fa"
                        border.width: 1

                        Text {
                          id: scopeLabel
                          anchors.centerIn: parent
                          text: modelData.is_funnel ? "🌍 FUNNEL (PUBLIC)" : "🔒 TAILNET ONLY"
                          font.family: root.monoFont
                          font.pixelSize: 9
                          font.bold: true
                          color: modelData.is_funnel ? "#cba6f7" : "#89b4fa"
                        }
                      }

                      // Port badge
                      Rectangle {
                        width: portLabel.width + 8
                        height: 18
                        radius: 4
                        color: "#313244"

                        Text {
                          id: portLabel
                          anchors.centerIn: parent
                          text: ":" + modelData.port + " HTTPS"
                          font.family: root.monoFont
                          font.pixelSize: 9
                          color: "#a6adc8"
                        }
                      }

                      Item { Layout.fillWidth: true }

                      // Stop endpoint button
                      Rectangle {
                        width: 22
                        height: 22
                        radius: 4
                        color: stopMouse.containsMouse ? "#f38ba8" : "#313244"

                        Text {
                          anchors.centerIn: parent
                          text: "✕"
                          font.family: root.monoFont
                          font.pixelSize: 11
                          color: stopMouse.containsMouse ? "#11111b" : "#f38ba8"
                        }

                        MouseArea {
                          id: stopMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: root.runAction(["serve-stop", modelData.port], "Stopped port " + modelData.port)
                        }
                      }
                    }

                    // Endpoint URL & Target info
                    Column {
                      width: parent.width
                      spacing: 2

                      Text {
                        text: modelData.url
                        font.family: root.monoFont
                        font.pixelSize: 12
                        font.bold: true
                        color: "#cdd6f4"
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        text: "↳ Proxying to " + modelData.target + (modelData.path && modelData.path !== "/" ? " (path " + modelData.path + ")" : "")
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#a6adc8"
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }

                    // Action buttons row: Copy URL, Open browser, Switch to Funnel/Serve
                    RowLayout {
                      width: parent.width
                      spacing: 6

                      // Copy URL button
                      Rectangle {
                        Layout.fillWidth: true
                        height: 24
                        radius: 4
                        color: copyUrlMouse.containsMouse ? "#45475a" : "#313244"

                        Row {
                          anchors.centerIn: parent
                          spacing: 4
                          Text { text: "󰆏"; font.family: root.monoFont; font.pixelSize: 10; color: "#cdd6f4" }
                          Text { text: "Copy URL"; font.family: root.monoFont; font.pixelSize: 10; color: "#cdd6f4" }
                        }

                        MouseArea {
                          id: copyUrlMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: root.copyText(modelData.url, "URL")
                        }
                      }

                      // Open in browser button
                      Rectangle {
                        Layout.fillWidth: true
                        height: 24
                        radius: 4
                        color: openBrowserMouse.containsMouse ? "#45475a" : "#313244"

                        Row {
                          anchors.centerIn: parent
                          spacing: 4
                          Text { text: "󰖟"; font.family: root.monoFont; font.pixelSize: 10; color: "#cdd6f4" }
                          Text { text: "Open"; font.family: root.monoFont; font.pixelSize: 10; color: "#cdd6f4" }
                        }

                        MouseArea {
                          id: openBrowserMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: root.openUrl(modelData.url)
                        }
                      }

                      // Switch Scope button (Tailnet <-> Funnel)
                      Rectangle {
                        Layout.fillWidth: true
                        height: 24
                        radius: 4
                        color: switchMouse.containsMouse ? (modelData.is_funnel ? "#22384f" : "#4a2958") : "#313244"
                        border.color: modelData.is_funnel ? "#89b4fa" : "#cba6f7"
                        border.width: 1

                        Row {
                          anchors.centerIn: parent
                          spacing: 4
                          Text {
                            text: modelData.is_funnel ? "󰈡 Make Private" : "󱂛 Make Public"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            font.bold: true
                            color: modelData.is_funnel ? "#89b4fa" : "#cba6f7"
                          }
                        }

                        MouseArea {
                          id: switchMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: {
                            const newIsFunnel = !modelData.is_funnel;
                            root.runAction(["funnel-toggle", modelData.port, modelData.target, newIsFunnel ? "true" : "false", modelData.path || "/"],
                                           newIsFunnel ? "Switched to Public Funnel" : "Switched to Tailnet Only");
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Empty state when no serve items
              Rectangle {
                visible: !root.tsData.serve_items || root.tsData.serve_items.length === 0
                width: parent.width
                height: 50
                radius: 8
                color: "#181825"

                Column {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    text: "No active serve or funnel endpoints."
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: "#6c7086"
                    anchors.horizontalCenter: parent.horizontalCenter
                  }
                  Text {
                    text: "Launch a service below to share a web app or port."
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: "#585b70"
                    anchors.horizontalCenter: parent.horizontalCenter
                  }
                }
              }

              // Quick Service Launcher Card
              Rectangle {
                width: parent.width
                height: launchCol.height + 16
                radius: 10
                color: "#181825"
                border.color: "#313244"
                border.width: 1

                Column {
                  id: launchCol
                  anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                  }
                  spacing: 8

                  RowLayout {
                    width: parent.width

                    Text {
                      text: root.activeEndpoint ? "Manage Serve / Funnel" : "Start New Serve / Funnel"
                      font.family: root.monoFont
                      font.pixelSize: 12
                      font.bold: true
                      color: "#cdd6f4"
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                      visible: root.activeEndpoint !== null
                      width: statusBadgeText.width + 10
                      height: 18
                      radius: 4
                      color: root.activeEndpoint && root.activeEndpoint.is_funnel ? "#4a2958" : "#22384f"
                      border.color: root.activeEndpoint && root.activeEndpoint.is_funnel ? "#cba6f7" : "#89b4fa"
                      border.width: 1

                      Text {
                        id: statusBadgeText
                        anchors.centerIn: parent
                        text: root.activeEndpoint ? (root.activeEndpoint.is_funnel ? "● FUNNEL ACTIVE" : "● SERVE ACTIVE") : ""
                        font.family: root.monoFont
                        font.pixelSize: 9
                        font.bold: true
                        color: root.activeEndpoint && root.activeEndpoint.is_funnel ? "#cba6f7" : "#89b4fa"
                      }
                    }
                  }

                  // Quick Preset chips & Manual option
                  Flow {
                    spacing: 6
                    width: parent.width

                    Repeater {
                      model: [
                        { label: "Frontend (5137)", target: "https+insecure://localhost:5137", isManual: false },
                        { label: "Backend (8080)", target: "8080", isManual: false },
                        { label: "Backend (3000)", target: "3000", isManual: false },
                        { label: "Manual URL", target: "", isManual: true }
                      ]

                      Rectangle {
                        required property var modelData
                        readonly property var ep: modelData.isManual ? null : root.findActiveEndpoint(modelData.target, "")
                        readonly property bool isSelected: modelData.isManual
                          ? (!root.targetsMatch(root.launchTarget, "https+insecure://localhost:5137") &&
                             !root.targetsMatch(root.launchTarget, "8080") &&
                             !root.targetsMatch(root.launchTarget, "3000"))
                          : root.targetsMatch(root.launchTarget, modelData.target)

                        width: chipRow.width + 14
                        height: 22
                        radius: 4
                        color: isSelected ? "#45475a" : (chipMouse.containsMouse ? "#3b3e52" : "#313244")
                        border.color: isSelected
                          ? (ep ? (ep.is_funnel ? "#cba6f7" : "#89b4fa") : "#89b4fa")
                          : (ep ? (ep.is_funnel ? "#cba6f7" : "#89b4fa") : "transparent")
                        border.width: 1

                        Row {
                          id: chipRow
                          anchors.centerIn: parent
                          spacing: 4

                          // Status dot for active presets
                          Rectangle {
                            visible: ep !== null
                            width: 6
                            height: 6
                            radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: ep ? (ep.is_funnel ? "#cba6f7" : "#a6e3a1") : "transparent"
                          }

                          Text {
                            id: chipText
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: isSelected ? "#89b4fa" : "#a6adc8"
                          }
                        }

                        MouseArea {
                          id: chipMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: {
                            if (modelData.isManual) {
                              if (root.targetsMatch(root.launchTarget, "https+insecure://localhost:5137") ||
                                  root.targetsMatch(root.launchTarget, "8080") ||
                                  root.targetsMatch(root.launchTarget, "3000")) {
                                root.selectTarget("");
                              }
                              targetInput.forceActiveFocus();
                            } else {
                              root.selectTarget(modelData.target);
                            }
                          }
                        }
                      }
                    }
                  }

                  // Target Input Row
                  RowLayout {
                    width: parent.width
                    spacing: 6

                    Text {
                      text: "Target URL:"
                      font.family: root.monoFont
                      font.pixelSize: 11
                      color: "#a6adc8"
                    }

                    Rectangle {
                      Layout.fillWidth: true
                      height: 26
                      radius: 4
                      color: "#313244"
                      border.color: targetInput.activeFocus ? "#89b4fa" : "transparent"
                      border.width: 1

                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 4

                        Item {
                          Layout.fillWidth: true
                          Layout.fillHeight: true

                          TextInput {
                            id: targetInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.launchTarget
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: "#cdd6f4"
                            selectByMouse: true
                            onTextEdited: root.selectTarget(text)
                          }

                          Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !targetInput.text && !targetInput.activeFocus
                            text: "Enter custom URL or port (e.g. http://localhost:8000)"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: "#6c7086"
                          }
                        }

                        // Clear button when text present
                        Rectangle {
                          visible: targetInput.text.length > 0
                          width: 14
                          height: 14
                          radius: 7
                          color: clearMouse.containsMouse ? "#585b70" : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: root.monoFont
                            font.pixelSize: 9
                            color: "#a6adc8"
                          }

                          MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                              root.selectTarget("");
                              targetInput.forceActiveFocus();
                            }
                          }
                        }
                      }
                    }
                  }

                  // Scope selection (Serve vs Funnel) & Port
                  RowLayout {
                    width: parent.width
                    spacing: 6

                    // Mode selector: Serve (Tailnet) vs Funnel (Public)
                    Rectangle {
                      Layout.fillWidth: true
                      height: 26
                      radius: 4
                      color: root.launchMode === "serve" ? "#22384f" : "#313244"
                      border.color: root.launchMode === "serve" ? "#89b4fa" : "transparent"
                      border.width: 1

                      Text {
                        anchors.centerIn: parent
                        text: "🔒 Tailnet (Serve)"
                        font.family: root.monoFont
                        font.pixelSize: 10
                        font.bold: root.launchMode === "serve"
                        color: root.launchMode === "serve" ? "#89b4fa" : "#a6adc8"
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launchMode = "serve"
                      }
                    }

                    Rectangle {
                      Layout.fillWidth: true
                      height: 26
                      radius: 4
                      color: root.launchMode === "funnel" ? "#4a2958" : "#313244"
                      border.color: root.launchMode === "funnel" ? "#cba6f7" : "transparent"
                      border.width: 1

                      Text {
                        anchors.centerIn: parent
                        text: "🌍 Public (Funnel)"
                        font.family: root.monoFont
                        font.pixelSize: 10
                        font.bold: root.launchMode === "funnel"
                        color: root.launchMode === "funnel" ? "#cba6f7" : "#a6adc8"
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launchMode = "funnel"
                      }
                    }

                    // Port input
                    Text {
                      text: "Port:"
                      font.family: root.monoFont
                      font.pixelSize: 11
                      color: "#a6adc8"
                    }

                    Rectangle {
                      width: 48
                      height: 26
                      radius: 4
                      color: "#313244"

                      TextInput {
                        anchors.fill: parent
                        anchors.margins: 4
                        text: root.launchPort
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#cdd6f4"
                        selectByMouse: true
                        onTextEdited: root.launchPort = text
                      }
                    }
                  }

                  // Active endpoint live URL banner
                  Rectangle {
                    visible: root.activeEndpoint !== null
                    width: parent.width
                    height: 26
                    radius: 4
                    color: root.activeEndpoint && root.activeEndpoint.is_funnel ? "#291d36" : "#1b283d"
                    border.color: root.activeEndpoint && root.activeEndpoint.is_funnel ? "#cba6f7" : "#89b4fa"
                    border.width: 1

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 8
                      anchors.rightMargin: 8
                      spacing: 6

                      Text {
                        text: root.activeEndpoint && root.activeEndpoint.is_funnel ? "🌍" : "🔒"
                        font.pixelSize: 10
                      }

                      Text {
                        Layout.fillWidth: true
                        text: root.activeEndpoint ? root.activeEndpoint.url : ""
                        font.family: root.monoFont
                        font.pixelSize: 10
                        font.bold: true
                        color: "#cdd6f4"
                        elide: Text.ElideRight
                      }

                      Rectangle {
                        width: copyBannerText.width + 8
                        height: 18
                        radius: 3
                        color: copyBannerMouse.containsMouse ? "#45475a" : "#313244"

                        Text {
                          id: copyBannerText
                          anchors.centerIn: parent
                          text: "Copy"
                          font.family: root.monoFont
                          font.pixelSize: 9
                          color: "#cdd6f4"
                        }

                        MouseArea {
                          id: copyBannerMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: {
                            if (root.activeEndpoint) root.copyText(root.activeEndpoint.url, "URL");
                          }
                        }
                      }

                      Rectangle {
                        width: openBannerText.width + 8
                        height: 18
                        radius: 3
                        color: openBannerMouse.containsMouse ? "#45475a" : "#313244"

                        Text {
                          id: openBannerText
                          anchors.centerIn: parent
                          text: "Open"
                          font.family: root.monoFont
                          font.pixelSize: 9
                          color: "#cdd6f4"
                        }

                        MouseArea {
                          id: openBannerMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: {
                            if (root.activeEndpoint) root.openUrl(root.activeEndpoint.url);
                          }
                        }
                      }
                    }
                  }

                  // Launch Action button
                  Rectangle {
                    width: parent.width
                    height: 28
                    radius: 6
                    color: {
                      if (root.launchButtonAction === "empty") {
                        return "#313244";
                      }
                      if (root.launchButtonAction === "stop") {
                        return launchMouse.containsMouse ? "#eba0ac" : "#f38ba8";
                      }
                      if (root.launchMode === "funnel") {
                        return launchMouse.containsMouse ? "#b48ead" : "#cba6f7";
                      }
                      return launchMouse.containsMouse ? "#74c7ec" : "#89b4fa";
                    }

                    Row {
                      anchors.centerIn: parent
                      spacing: 6
                      Text {
                        text: root.launchButtonIcon
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: root.launchButtonAction === "empty" ? "#6c7086" : "#11111b"
                      }
                      Text {
                        text: root.launchButtonText
                        font.family: root.monoFont
                        font.pixelSize: 11
                        font.bold: true
                        color: root.launchButtonAction === "empty" ? "#a6adc8" : "#11111b"
                      }
                    }

                    MouseArea {
                      id: launchMouse
                      anchors.fill: parent
                      cursorShape: root.launchButtonAction === "empty" ? Qt.ArrowCursor : Qt.PointingHandCursor
                      hoverEnabled: root.launchButtonAction !== "empty"
                      enabled: root.launchButtonAction !== "empty"
                      onClicked: {
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
                        } else {
                          root.runAction(
                            ["serve-start", root.launchTarget, root.launchMode, root.launchPort, root.launchPath],
                            "Started " + root.launchMode + " for " + root.launchTarget
                          );
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // TAB 1: SSH & REMOTE ACCESS
        Item {
          id: tab1
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: tab1Col.height
            clip: true

            Column {
              id: tab1Col
              width: parent.width
              spacing: 10

              // SSH Server Toggle Card
              Rectangle {
                width: parent.width
                height: sshCol.height + 16
                radius: 10
                color: "#181825"
                border.color: root.tsData.ssh_enabled ? "#a6e3a1" : "#313244"
                border.width: 1

                Column {
                  id: sshCol
                  anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                  }
                  spacing: 8

                  RowLayout {
                    width: parent.width

                    Row {
                      spacing: 6
                      Text { text: "󰒍"; font.family: root.monoFont; font.pixelSize: 14; color: root.tsData.ssh_enabled ? "#a6e3a1" : "#6c7086" }
                      Text { text: "Tailscale SSH Server"; font.family: root.monoFont; font.pixelSize: 12; font.bold: true; color: "#cdd6f4" }
                    }

                    Item { Layout.fillWidth: true }

                    // Toggle button
                    Rectangle {
                      width: 44
                      height: 22
                      radius: 11
                      color: root.tsData.ssh_enabled ? "#a6e3a1" : "#45475a"

                      Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: root.tsData.ssh_enabled ? undefined : parent.left
                        anchors.right: root.tsData.ssh_enabled ? parent.right : undefined
                        anchors.margins: 2
                        color: "#11111b"
                        Behavior on x { NumberAnimation { duration: 150 } }
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          const newState = !root.tsData.ssh_enabled;
                          root.runAction(["ssh-toggle", newState ? "true" : "false"], newState ? "Tailscale SSH Enabled" : "Tailscale SSH Disabled");
                        }
                      }
                    }
                  }

                  Text {
                    text: root.tsData.ssh_enabled
                          ? "✓ Port 22 managed by Tailscale. Authenticated tailnet devices can SSH directly."
                          : "Tailscale SSH is currently inactive on this node."
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: root.tsData.ssh_enabled ? "#a6e3a1" : "#a6adc8"
                    wrapMode: Text.Wrap
                    width: parent.width
                  }

                  // Quick SSH commands to copy
                  Column {
                    width: parent.width
                    spacing: 4
                    visible: root.tsData.ssh_enabled

                    Text {
                      text: "Click to copy SSH connection command:"
                      font.family: root.monoFont
                      font.pixelSize: 10
                      color: "#6c7086"
                    }

                    Repeater {
                      model: [
                        "ssh dev@" + ((root.tsData.self && root.tsData.self.hostname) || "fedora"),
                        "ssh dev@" + ((root.tsData.self && root.tsData.self.ipv4) || "100.72.40.125"),
                        "ssh dev@" + ((root.tsData.self && root.tsData.self.dns_name) || "fedora.ts.net")
                      ]

                      Rectangle {
                        required property string modelData
                        width: parent.width
                        height: 26
                        radius: 4
                        color: sshCmdMouse.containsMouse ? "#3b3e52" : "#313244"

                        RowLayout {
                          anchors.fill: parent
                          anchors.margins: 6

                          Text {
                            text: modelData
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: "#89b4fa"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                          }

                          Text {
                            text: "󰆏 Copy"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: "#a6adc8"
                          }
                        }

                        MouseArea {
                          id: sshCmdMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: root.copyText(modelData, "SSH Command")
                        }
                      }
                    }
                  }

                  // Health alert (SELinux notice)
                  Rectangle {
                    visible: Boolean(root.tsData.health && root.tsData.health.length > 0)
                    width: parent.width
                    height: healthText.implicitHeight + 14
                    radius: 6
                    color: "#3b2e22"
                    border.color: "#fab387"
                    border.width: 1

                    Text {
                      id: healthText
                      anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 7
                      }
                      text: "ℹ " + (root.tsData.health ? root.tsData.health.join("\n") : "")
                      font.family: root.monoFont
                      font.pixelSize: 10
                      color: "#fab387"
                      wrapMode: Text.Wrap
                    }
                  }
                }
              }
            }
          }
        }

        // TAB 2: PEERS & DEVICES
        Item {
          id: tab2
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: tab2Col.height
            clip: true

            Column {
              id: tab2Col
              width: parent.width
              spacing: 8

              RowLayout {
                width: parent.width
                Text {
                  text: "Tailnet Devices (" + (root.tsData.peers ? root.tsData.peers.length : 0) + ")"
                  font.family: root.monoFont
                  font.pixelSize: 12
                  font.bold: true
                  color: "#cdd6f4"
                }
                Item { Layout.fillWidth: true }
              }

              Repeater {
                model: root.tsData.peers || []

                Rectangle {
                  required property var modelData
                  required property int index

                  width: tab2Col.width
                  height: peerCol.height + 16
                  radius: 8
                  color: "#181825"
                  border.color: "#313244"
                  border.width: 1

                  Column {
                    id: peerCol
                    anchors {
                      left: parent.left
                      right: parent.right
                      top: parent.top
                      margins: 8
                    }
                    spacing: 6

                    RowLayout {
                      width: parent.width

                      // OS Icon
                      Text {
                        text: {
                          const os = (modelData.os || "").toLowerCase();
                          if (os.includes("android")) return "󰀲";
                          if (os.includes("linux")) return "󰌽";
                          if (os.includes("mac") || os.includes("ios")) return "󰀵";
                          if (os.includes("win")) return "󰖳";
                          return "󰛳";
                        }
                        font.family: root.monoFont
                        font.pixelSize: 14
                        color: "#89b4fa"
                      }

                      // Device Hostname
                      Text {
                        text: modelData.hostname || "Device"
                        font.family: root.monoFont
                        font.pixelSize: 12
                        font.bold: true
                        color: "#cdd6f4"
                      }

                      // Online indicator
                      Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: modelData.online ? "#a6e3a1" : "#6c7086"
                      }

                      Item { Layout.fillWidth: true }

                      Text {
                        text: modelData.os
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: "#6c7086"
                      }
                    }

                    RowLayout {
                      width: parent.width

                      Text {
                        text: modelData.ipv4 || modelData.dns_name
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#a6e3a1"
                      }

                      Item { Layout.fillWidth: true }

                      // Ping result if this peer was pinged
                      Text {
                        visible: root.pingTargetIp === modelData.ipv4 && root.pingResult.length > 0
                        text: root.pingResult
                        font.family: root.monoFont
                        font.pixelSize: 10
                        font.bold: true
                        color: root.pingResult.includes("ms") ? "#a6e3a1" : "#fab387"
                      }

                      // Ping action
                      Rectangle {
                        width: 44
                        height: 20
                        radius: 4
                        color: pingMouse.containsMouse ? "#45475a" : "#313244"

                        Text {
                          anchors.centerIn: parent
                          text: "Ping"
                          font.family: root.monoFont
                          font.pixelSize: 10
                          color: "#89b4fa"
                        }

                        MouseArea {
                          id: pingMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: root.pingPeer(modelData.ipv4)
                        }
                      }

                      // Copy IP action
                      Rectangle {
                        width: 44
                        height: 20
                        radius: 4
                        color: copyPeerIpMouse.containsMouse ? "#45475a" : "#313244"

                        Text {
                          anchors.centerIn: parent
                          text: "Copy"
                          font.family: root.monoFont
                          font.pixelSize: 10
                          color: "#cdd6f4"
                        }

                        MouseArea {
                          id: copyPeerIpMouse
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          hoverEnabled: true
                          onClicked: root.copyText(modelData.ipv4, "Peer IP")
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // TAB 3: SETTINGS & DIAGNOSTICS
        Item {
          id: tab3
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: tab3Col.height
            clip: true

            Column {
              id: tab3Col
              width: parent.width
              spacing: 10

              // Preferences Toggles Card
              Rectangle {
                width: parent.width
                height: prefCol.height + 16
                radius: 10
                color: "#181825"
                border.color: "#313244"
                border.width: 1

                Column {
                  id: prefCol
                  anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                  }
                  spacing: 8

                  Text {
                    text: "Tailnet Settings & Preferences"
                    font.family: root.monoFont
                    font.pixelSize: 12
                    font.bold: true
                    color: "#cdd6f4"
                  }

                  // Webclient Toggle
                  RowLayout {
                    width: parent.width

                    Column {
                      Layout.fillWidth: true
                      spacing: 1
                      Text { text: "Tailscale Web UI (:5252)"; font.family: root.monoFont; font.pixelSize: 11; font.bold: true; color: "#cdd6f4" }
                      Text { text: "Background web portal for managing node"; font.family: root.monoFont; font.pixelSize: 10; color: "#6c7086" }
                    }

                    Rectangle {
                      visible: Boolean(root.tsData.webclient_enabled)
                      width: 42
                      height: 20
                      radius: 4
                      color: "#313244"
                      Text { anchors.centerIn: parent; text: "Open"; font.family: root.monoFont; font.pixelSize: 9; color: "#89b4fa" }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openUrl("http://localhost:5252")
                      }
                    }

                    Rectangle {
                      width: 36
                      height: 18
                      radius: 9
                      color: root.tsData.webclient_enabled ? "#a6e3a1" : "#45475a"
                      Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: root.tsData.webclient_enabled ? undefined : parent.left
                        anchors.right: root.tsData.webclient_enabled ? parent.right : undefined
                        anchors.margins: 2; color: "#11111b"
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAction(["set-pref", "webclient", !root.tsData.webclient_enabled ? "true" : "false"], "Updated Web UI setting")
                      }
                    }
                  }

                  // Exit Node Advertisement
                  RowLayout {
                    width: parent.width

                    Column {
                      Layout.fillWidth: true
                      spacing: 1
                      Text { text: "Advertise Exit Node"; font.family: root.monoFont; font.pixelSize: 11; font.bold: true; color: "#cdd6f4" }
                      Text { text: "Allow routing tailnet traffic through this machine"; font.family: root.monoFont; font.pixelSize: 10; color: "#6c7086" }
                    }

                    Rectangle {
                      width: 36
                      height: 18
                      radius: 9
                      color: root.tsData.exit_node_enabled ? "#a6e3a1" : "#45475a"
                      Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: root.tsData.exit_node_enabled ? undefined : parent.left
                        anchors.right: root.tsData.exit_node_enabled ? parent.right : undefined
                        anchors.margins: 2; color: "#11111b"
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAction(["set-pref", "advertise-exit-node", !root.tsData.exit_node_enabled ? "true" : "false"], "Updated exit node setting")
                      }
                    }
                  }

                  // Shields Up
                  RowLayout {
                    width: parent.width

                    Column {
                      Layout.fillWidth: true
                      spacing: 1
                      Text { text: "Shields Up"; font.family: root.monoFont; font.pixelSize: 11; font.bold: true; color: "#cdd6f4" }
                      Text { text: "Block all incoming connections from tailnet"; font.family: root.monoFont; font.pixelSize: 10; color: "#6c7086" }
                    }

                    Rectangle {
                      width: 36
                      height: 18
                      radius: 9
                      color: root.tsData.shields_up ? "#f38ba8" : "#45475a"
                      Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: root.tsData.shields_up ? undefined : parent.left
                        anchors.right: root.tsData.shields_up ? parent.right : undefined
                        anchors.margins: 2; color: "#11111b"
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAction(["set-pref", "shields-up", !root.tsData.shields_up ? "true" : "false"], "Updated shields-up setting")
                      }
                    }
                  }
                }
              }

              // Netcheck Diagnostics Card
              Rectangle {
                width: parent.width
                height: netcheckCol.height + 16
                radius: 10
                color: "#181825"
                border.color: "#313244"
                border.width: 1

                Column {
                  id: netcheckCol
                  anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                  }
                  spacing: 8

                  RowLayout {
                    width: parent.width

                    Text {
                      text: "Network Diagnostics (Netcheck)"
                      font.family: root.monoFont
                      font.pixelSize: 12
                      font.bold: true
                      color: "#cdd6f4"
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                      width: netcheckBtnText.width + 12
                      height: 22
                      radius: 4
                      color: netcheckMouse.containsMouse ? "#74c7ec" : "#89b4fa"

                      Text {
                        id: netcheckBtnText
                        anchors.centerIn: parent
                        text: root.isRunningNetcheck ? "Testing…" : "Run Test"
                        font.family: root.monoFont
                        font.pixelSize: 10
                        font.bold: true
                        color: "#11111b"
                      }

                      MouseArea {
                        id: netcheckMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.runNetcheck()
                      }
                    }
                  }

                  Rectangle {
                    visible: root.netcheckReport.length > 0
                    width: parent.width
                    height: Math.min(120, reportText.implicitHeight + 14)
                    radius: 6
                    color: "#11111b"

                    Flickable {
                      anchors.fill: parent
                      anchors.margins: 7
                      contentWidth: width
                      contentHeight: reportText.implicitHeight
                      clip: true

                      Text {
                        id: reportText
                        width: parent.width
                        text: root.netcheckReport
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: "#a6adc8"
                        wrapMode: Text.Wrap
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
