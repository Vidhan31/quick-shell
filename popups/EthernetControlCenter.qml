// EthernetControlCenter.qml — Detailed Ethernet & Internet status and diagnostics popup.
// Native C++ Qt6 QML module (Quickshell.Plugins.Ethernet).
import QtQuick
import QtQuick.Layouts
import Quickshell.Plugins.Ethernet

Item {
  id: root

  property EthernetMonitor monitor: null
  EthernetMonitor {
    id: fallbackMonitor
    running: root.monitor === null
  }
  readonly property EthernetMonitor activeMonitor: root.monitor ? root.monitor : fallbackMonitor

  // Throughput tracking: enable live throughput metrics only when popup is visible
  Binding {
    target: root.activeMonitor
    property: "throughputTracking"
    value: root.visible
    when: root.activeMonitor !== null
  }

  property var ethData: activeMonitor ? activeMonitor.ethData : null
  signal triggerRefresh()

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property bool hasInternet: activeMonitor ? activeMonitor.hasInternet : false
  readonly property bool isCarrier: activeMonitor ? activeMonitor.carrier : false
  readonly property string currentStatus: activeMonitor ? activeMonitor.currentStatus : "offline"
  readonly property string ifaceName: activeMonitor ? activeMonitor.interfaceName : "enp34s0"

  // Ping test state from native C++ monitor
  readonly property string pingResult: activeMonitor ? activeMonitor.pingResult : ""
  readonly property double pingLatency: activeMonitor ? activeMonitor.pingLatency : -1
  readonly property bool isPinging: activeMonitor ? activeMonitor.isPinging : false

  // Live throughput metrics from native C++ monitor
  readonly property double downloadBps: activeMonitor ? activeMonitor.downloadBps : 0
  readonly property double uploadBps: activeMonitor ? activeMonitor.uploadBps : 0

  function formatSpeed(bps: double): string {
    if (!isFinite(bps) || bps < 0) return "0 B/s";
    if (bps < 1024) return Math.round(bps) + " B/s";
    if (bps < 1024 * 1024) return (bps / 1024).toFixed(1) + " KB/s";
    if (bps < 1024 * 1024 * 1024) return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    return (bps / 1024 / 1024 / 1024).toFixed(2) + " GB/s";
  }

  implicitWidth: 380
  implicitHeight: 460
  width: implicitWidth
  height: implicitHeight

  function runPing(): void {
    if (activeMonitor) {
      activeMonitor.runPing("1.1.1.1");
    }
  }

  function runCheck(): void {
    if (activeMonitor) {
      activeMonitor.runCheck();
      root.triggerRefresh();
    }
  }

  function openSettings(): void {
    if (activeMonitor) {
      activeMonitor.openSettings();
    }
  }

  function reconnectDevice(): void {
    if (activeMonitor) {
      activeMonitor.reconnect(root.ifaceName);
      checkTimer.start();
    }
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
