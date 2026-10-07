pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property var ethernet: null

  readonly property var monitor: ethernet ? ethernet.monitor : null
  readonly property var t: Theme
  readonly property string monoFont: Theme.mono
  readonly property string currentStatus: ethernet ? ethernet.currentStatus : "offline"
  readonly property bool hasInternet: ethernet ? ethernet.hasInternet : false
  readonly property bool isCarrier: ethernet ? ethernet.carrier : false
  readonly property bool hasIp: Boolean(ethernet && ethernet.ip)

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  readonly property string iconGlyph: {
    if (!root.isCarrier) return "󰤭";
    if (root.currentStatus === "connecting") return "󰤫";
    if (root.hasInternet) return "󰖩";
    return "󰖩";
  }

  readonly property color statusColor: {
    if (!root.isCarrier) return Theme.err;
    if (root.currentStatus === "connecting") return Theme.accent;
    if (root.hasInternet) return Theme.ok;
    return Theme.warn;
  }

  readonly property string tooltipText: {
    if (!root.monitor || !root.monitor.ok) return "Ethernet: Not Detected";
    const iface = root.monitor.interfaceName || "eth";
    if (!root.isCarrier) return "Ethernet (" + iface + "): Cable Unplugged";
    if (root.currentStatus === "connecting") return "Ethernet (" + iface + "): Connecting...";
    if (root.hasInternet) {
      const ipStr = root.monitor.ip ? (" • " + root.monitor.ip.split("/")[0]) : "";
      return "Ethernet: Internet OK (" + iface + ipStr + ")";
    }
    return "Ethernet (" + iface + "): No Internet (Local Only)";
  }

  Row {
    id: contentRow
    anchors.verticalCenter: parent.verticalCenter

    Text {
      id: ethIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: Theme.fontGlyphMd
      color: root.statusColor

      Behavior on color {
        ColorAnimation { duration: Theme.durationNormal }
      }

      SequentialAnimation on opacity {
        running: (root.currentStatus === "connecting" || root.currentStatus === "no_internet")
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.3; duration: Theme.durationPulse; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.3; to: 1.0; duration: Theme.durationPulse; easing.type: Easing.InOutQuad }
      }
    }
  }
}
