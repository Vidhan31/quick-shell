// EthernetControlCenter.qml — Detailed Ethernet & Internet status and diagnostics popup.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
  id: root

  property var ethData: ({
    ok: true,
    interface: "enp34s0",
    carrier: true,
    operstate: "up",
    speed_mbps: 100,
    speed_label: "100 Mbps",
    hw_address: "",
    ip: "",
    ipv6: "",
    gateway: "",
    dns: [],
    connection_name: "Ethernet",
    nm_connectivity: 4,
    has_internet: true,
    is_default_route: true,
    status: "internet",
    status_desc: "Connected • Internet OK",
    rx_bytes: 0,
    tx_bytes: 0,
    query_time_ms: 0
  })

  signal triggerRefresh()

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property bool hasInternet: ethData ? (ethData.has_internet === true) : false
  readonly property bool isCarrier: ethData ? (ethData.carrier === true) : false
  readonly property string currentStatus: ethData ? (ethData.status || "offline") : "offline"
  readonly property string ifaceName: ethData ? (ethData.interface || "enp34s0") : "enp34s0"

  // Ping test state
  property string pingResult: ""
  property double pingLatency: -1
  property bool isPinging: false

  // Live throughput tracking
  property double _prevRx: -1
  property double _prevTx: -1
  property double _prevTime: -1
  property double downloadBps: 0
  property double uploadBps: 0

  function formatSpeed(bps: double): string {
    if (!isFinite(bps) || bps < 0) return "0 B/s";
    if (bps < 1024) return Math.round(bps) + " B/s";
    if (bps < 1024 * 1024) return (bps / 1024).toFixed(1) + " KB/s";
    if (bps < 1024 * 1024 * 1024) return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    return (bps / 1024 / 1024 / 1024).toFixed(2) + " GB/s";
  }

  function updateThroughput(rx: double, tx: double): void {
    const now = Date.now();
    if (root._prevRx >= 0 && root._prevTime > 0) {
      const dt = (now - root._prevTime) / 1000;
      if (dt > 0) {
        const dRx = rx >= root._prevRx ? rx - root._prevRx : 0;
        const dTx = tx >= root._prevTx ? tx - root._prevTx : 0;
        root.downloadBps = dRx / dt;
        root.uploadBps = dTx / dt;
      }
    }
    root._prevRx = rx;
    root._prevTx = tx;
    root._prevTime = now;
  }

  onEthDataChanged: {
    if (ethData && typeof ethData.rx_bytes === "number") {
      updateThroughput(ethData.rx_bytes, ethData.tx_bytes);
    }
  }

  implicitWidth: 380
  implicitHeight: 460
  width: implicitWidth
  height: implicitHeight

  // Ping test process
  Process {
    id: pingProc
    command: ["sh", "-c", "/usr/bin/python3 /home/dev/Projects/quick-shell/ethernet-bridge.py ping 1.1.1.1"]
    stdout: StdioCollector {
      id: pingCollector
      onStreamFinished: {
        root.isPinging = false;
        const raw = pingCollector.text;
        if (!raw) return;
        try {
          const res = JSON.parse(raw);
          if (res && res.ok) {
            root.pingLatency = res.latency_ms;
            root.pingResult = res.latency_ms.toFixed(1) + " ms";
          } else {
            root.pingLatency = -1;
            root.pingResult = "Failed";
          }
        } catch (e) {
          root.pingResult = "Error";
        }
      }
    }
    onExited: {
      root.isPinging = false;
    }
  }

  // Force check connectivity process
  Process {
    id: checkProc
    command: ["sh", "-c", "/usr/bin/python3 /home/dev/Projects/quick-shell/ethernet-bridge.py check"]
    stdout: StdioCollector {
      id: checkCollector
      onStreamFinished: {
        const raw = checkCollector.text;
        if (!raw) return;
        try {
          const res = JSON.parse(raw);
          if (res && res.ok) {
            root.ethData = res;
          }
        } catch (e) {}
      }
    }
  }

  // Actions process (settings, reconnect)
  Process {
    id: actionProc
  }

  function runPing(): void {
    if (!pingProc.running) {
      root.isPinging = true;
      root.pingResult = "Testing...";
      pingProc.running = true;
    }
  }

  function runCheck(): void {
    if (!checkProc.running) {
      checkProc.running = true;
      root.triggerRefresh();
    }
  }

  function openSettings(): void {
    actionProc.command = ["sh", "-c", "/usr/bin/python3 /home/dev/Projects/quick-shell/ethernet-bridge.py open-settings"];
    actionProc.running = true;
  }

  function reconnectDevice(): void {
    actionProc.command = ["sh", "-c", "/usr/bin/python3 /home/dev/Projects/quick-shell/ethernet-bridge.py reconnect '" + root.ifaceName + "'"];
    actionProc.running = true;
    checkTimer.start();
  }

  Timer {
    id: checkTimer
    interval: 1500
    repeat: false
    onTriggered: root.runCheck()
  }

  // Automatically trigger ping when popup opens if latency is unknown
  Component.onCompleted: {
    if (root.hasInternet && root.pingLatency < 0) {
      root.runPing();
    }
  }

  // Main Card container
  Rectangle {
    anchors.fill: parent
    radius: 12
    color: "#1e1e2e" // Catppuccin Base
    border.color: "#313244"
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 12

      // Top Header
      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        // Large Status Icon Box
        Rectangle {
          Layout.preferredWidth: 36
          Layout.preferredHeight: 36
          radius: 8
          color: root.hasInternet ? "#1c2b29" : (!root.isCarrier ? "#2c1c22" : "#2d281f")
          border.color: root.hasInternet ? "#a6e3a1" : (!root.isCarrier ? "#f38ba8" : "#f9e2af")
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: !root.isCarrier ? "󰈂" : (root.currentStatus === "connecting" ? "󰌗" : "󰈀")
            font.family: root.monoFont
            font.pixelSize: 18
            color: root.hasInternet ? "#a6e3a1" : (!root.isCarrier ? "#f38ba8" : "#f9e2af")
          }
        }

        // Title and Subtitle
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            text: "Ethernet Network"
            font.family: root.monoFont
            font.pixelSize: 14
            font.bold: true
            color: "#cdd6f4"
          }

          Text {
            text: (root.ethData && root.ethData.connection_name) ? (root.ethData.connection_name + " (" + root.ifaceName + ")") : root.ifaceName
            font.family: root.monoFont
            font.pixelSize: 11
            color: "#a6adc8"
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        // Status Badge Pill
        Rectangle {
          radius: 12
          Layout.preferredHeight: 24
          Layout.preferredWidth: badgeRow.width + 16
          color: root.hasInternet ? "#263f35" : (!root.isCarrier ? "#3f262e" : "#3f3926")
          border.color: root.hasInternet ? "#a6e3a1" : (!root.isCarrier ? "#f38ba8" : "#f9e2af")
          border.width: 1

          Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 5

            Rectangle {
              width: 6
              height: 6
              radius: 3
              anchors.verticalCenter: parent.verticalCenter
              color: root.hasInternet ? "#a6e3a1" : (!root.isCarrier ? "#f38ba8" : "#f9e2af")
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.hasInternet ? "Online" : (!root.isCarrier ? "Unplugged" : "No Internet")
              font.family: root.monoFont
              font.pixelSize: 11
              font.bold: true
              color: root.hasInternet ? "#a6e3a1" : (!root.isCarrier ? "#f38ba8" : "#f9e2af")
            }
          }
        }
      }

      // Banner: Internet connectivity highlight
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        radius: 8
        color: root.hasInternet ? "#182622" : (!root.isCarrier ? "#26181d" : "#262318")
        border.color: root.hasInternet ? "#2a4a3e" : (!root.isCarrier ? "#4a2a35" : "#4a422a")
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 8

          Text {
            text: root.hasInternet ? "󰄬" : (!root.isCarrier ? "󰅖" : "󰀪")
            font.family: root.monoFont
            font.pixelSize: 16
            font.bold: true
            color: root.hasInternet ? "#a6e3a1" : (!root.isCarrier ? "#f38ba8" : "#f9e2af")
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
              text: root.hasInternet ? "Internet Connected" : (!root.isCarrier ? "Physical Cable Unplugged" : "No Internet Connection")
              font.family: root.monoFont
              font.pixelSize: 12
              font.bold: true
              color: root.hasInternet ? "#a6e3a1" : (!root.isCarrier ? "#f38ba8" : "#f9e2af")
            }

            Text {
              text: root.hasInternet ? "Full WAN route active via " + root.ifaceName : (!root.isCarrier ? "Plug in an Ethernet cable to connect" : "Local LAN active, gateway unreachable")
              font.family: root.monoFont
              font.pixelSize: 10
              color: "#a6adc8"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Live Latency badge
          Rectangle {
            visible: root.hasInternet
            radius: 4
            Layout.preferredHeight: 22
            Layout.preferredWidth: pingText.width + 10
            color: "#313244"

            Text {
              id: pingText
              anchors.centerIn: parent
              text: root.pingResult ? root.pingResult : (root.isPinging ? "..." : "1.1.1.1")
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#89b4fa"
            }
          }
        }
      }

      // Live Throughput & Ping Test Bar
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 6
        color: "#181825"
        border.color: "#313244"
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10

          // Download
          Text {
            text: "↓ " + root.formatSpeed(root.downloadBps)
            font.family: root.monoFont
            font.pixelSize: 11
            color: "#a6e3a1"
          }

          // Upload
          Text {
            text: "↑ " + root.formatSpeed(root.uploadBps)
            font.family: root.monoFont
            font.pixelSize: 11
            color: "#f9e2af"
          }

          Item { Layout.fillWidth: true }

          // Test Ping button
          Rectangle {
            Layout.preferredHeight: 22
            Layout.preferredWidth: pingBtnText.width + 12
            radius: 4
            color: pingMouse.containsMouse ? "#45475a" : "#313244"
            border.color: pingMouse.containsMouse ? "#89b4fa" : "transparent"

            Text {
              id: pingBtnText
              anchors.centerIn: parent
              text: root.isPinging ? "Testing..." : "Test Ping"
              font.family: root.monoFont
              font.pixelSize: 10
              color: root.isPinging ? "#89b4fa" : "#cdd6f4"
            }

            MouseArea {
              id: pingMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: root.runPing()
            }
          }
        }
      }

      // Details Card
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 8
        color: "#181825"
        border.color: "#313244"
        border.width: 1

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 6

          // Row 1: IPv4
          RowLayout {
            Layout.fillWidth: true
            Text { text: "IP Address:"; font.family: root.monoFont; font.pixelSize: 11; color: "#6c7086"; Layout.preferredWidth: 105 }
            Text {
              text: (root.ethData && root.ethData.ip) ? root.ethData.ip : "Not Assigned"
              font.family: root.monoFont
              font.pixelSize: 11
              font.bold: true
              color: (root.ethData && root.ethData.ip) ? "#cdd6f4" : "#f38ba8"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Row 2: Default Gateway
          RowLayout {
            Layout.fillWidth: true
            Text { text: "Gateway:"; font.family: root.monoFont; font.pixelSize: 11; color: "#6c7086"; Layout.preferredWidth: 105 }
            Text {
              text: (root.ethData && root.ethData.gateway) ? root.ethData.gateway : "--"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#cdd6f4"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Row 3: Link Speed
          RowLayout {
            Layout.fillWidth: true
            Text { text: "Link Speed:"; font.family: root.monoFont; font.pixelSize: 11; color: "#6c7086"; Layout.preferredWidth: 105 }
            Text {
              text: (root.ethData && root.ethData.speed_label) ? (root.ethData.speed_label + " (Full Duplex)") : "Unknown"
              font.family: root.monoFont
              font.pixelSize: 11
              color: root.isCarrier ? "#89b4fa" : "#6c7086"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Row 4: DNS Server
          RowLayout {
            Layout.fillWidth: true
            Text { text: "DNS Servers:"; font.family: root.monoFont; font.pixelSize: 11; color: "#6c7086"; Layout.preferredWidth: 105 }
            Text {
              text: (root.ethData && root.ethData.dns && root.ethData.dns.length > 0) ? root.ethData.dns.join(", ") : "Default (System)"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#cdd6f4"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Row 5: MAC Address
          RowLayout {
            Layout.fillWidth: true
            Text { text: "Hardware MAC:"; font.family: root.monoFont; font.pixelSize: 11; color: "#6c7086"; Layout.preferredWidth: 105 }
            Text {
              text: (root.ethData && root.ethData.hw_address) ? root.ethData.hw_address : "--"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#a6adc8"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Row 6: Physical Cable
          RowLayout {
            Layout.fillWidth: true
            Text { text: "Cable Status:"; font.family: root.monoFont; font.pixelSize: 11; color: "#6c7086"; Layout.preferredWidth: 105 }
            Text {
              text: root.isCarrier ? "Connected (Carrier link detected)" : "Unplugged (No carrier link)"
              font.family: root.monoFont
              font.pixelSize: 11
              font.bold: true
              color: root.isCarrier ? "#a6e3a1" : "#f38ba8"
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }
      }

      // Bottom Actions
      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        // Check Internet button
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 30
          radius: 6
          color: checkMouse.containsMouse ? "#45475a" : "#313244"
          border.color: checkMouse.containsMouse ? "#a6e3a1" : "#585b70"

          Row {
            anchors.centerIn: parent
            spacing: 6
            Text {
              text: "󰑐"
              font.family: root.monoFont
              font.pixelSize: 12
              color: "#a6e3a1"
            }
            Text {
              text: "Check Internet"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#cdd6f4"
            }
          }

          MouseArea {
            id: checkMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: {
              root.runCheck();
              root.runPing();
            }
          }
        }

        // Reconnect button
        Rectangle {
          Layout.preferredHeight: 30
          Layout.preferredWidth: 90
          radius: 6
          color: reconMouse.containsMouse ? "#45475a" : "#313244"
          border.color: reconMouse.containsMouse ? "#89b4fa" : "#585b70"

          Row {
            anchors.centerIn: parent
            spacing: 5
            Text {
              text: "󰌗"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#89b4fa"
            }
            Text {
              text: "Reapply"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#cdd6f4"
            }
          }

          MouseArea {
            id: reconMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.reconnectDevice()
          }
        }

        // Network Settings button
        Rectangle {
          Layout.preferredHeight: 30
          Layout.preferredWidth: 90
          radius: 6
          color: setMouse.containsMouse ? "#45475a" : "#313244"
          border.color: setMouse.containsMouse ? "#cba6f7" : "#585b70"

          Row {
            anchors.centerIn: parent
            spacing: 5
            Text {
              text: "󰒓"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#cba6f7"
            }
            Text {
              text: "Settings"
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#cdd6f4"
            }
          }

          MouseArea {
            id: setMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.openSettings()
          }
        }
      }
    }
  }
}
