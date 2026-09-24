// EthernetWidget.qml — Compact top bar widget for Ethernet & Internet status.
// Native C++ Qt6 QML module (Quickshell.Plugins.Ethernet).
import QtQuick
import Quickshell.Plugins.Ethernet
import "../theme"

Item {
  id: root

  property int pollInterval: 2500

  EthernetMonitor {
    id: monitor
    running: true
    interval: root.pollInterval
  }

  property alias monitor: monitor
  property var ethData: monitor.ethData
  readonly property bool isBusy: monitor.isBusy

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono
  readonly property string currentStatus: monitor.currentStatus
  readonly property bool hasInternet: monitor.hasInternet
  readonly property bool isCarrier: monitor.carrier
  readonly property bool hasIp: Boolean(monitor.ip)

  // Status-derived icon glyph
  readonly property string iconGlyph: {
    if (!root.isCarrier) return "󰈂"; // Cable disconnected
    if (root.currentStatus === "connecting") return "󰌗"; // Pending / DHCP
    if (root.hasInternet) return "󰈀"; // Connected & Internet OK
    return "󰈀"; // Connected LAN, no WAN
  }

  // Status-derived color
  readonly property color statusColor: {
    if (!root.isCarrier) return Theme.err; // Red (unplugged)
    if (root.currentStatus === "connecting") return Theme.accent; // Connecting
    if (root.hasInternet) return Theme.ok; // Green (internet online)
    return Theme.warn; // Amber (LAN only, no internet)
  }

  // Status description for tooltip
  readonly property string tooltipText: {
    if (!monitor.ok) return "Ethernet: Not Detected";
    const iface = monitor.interfaceName || "eth";
    if (!root.isCarrier) return "Ethernet (" + iface + "): Cable Unplugged";
    if (root.currentStatus === "connecting") return "Ethernet (" + iface + "): Connecting...";
    if (root.hasInternet) {
      const ipStr = monitor.ip ? (" • " + monitor.ip.split("/")[0]) : "";
      return "Ethernet: Internet OK (" + iface + ipStr + ")";
    }
    return "Ethernet (" + iface + "): No Internet (Local Only)";
  }

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  function refresh(): void {
    monitor.refresh();
  }

  Row {
    id: contentRow
    spacing: 5
    anchors.verticalCenter: parent.verticalCenter

    // Small Ethernet status icon
    Text {
      id: ethIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: 13
      color: root.statusColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
    }

    // Small status dot indicator
    Rectangle {
      id: statusDot
      width: 6
      height: 6
      radius: 3
      anchors.verticalCenter: parent.verticalCenter
      color: root.statusColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }

      // Gentle pulsing animation when connecting or no internet
      SequentialAnimation on opacity {
        running: (root.currentStatus === "connecting" || root.currentStatus === "no_internet")
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
      }
    }
  }
}
