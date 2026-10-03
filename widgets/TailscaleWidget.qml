pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property var tailscale: null

  readonly property bool isConnected: tailscale ? tailscale.isConnected : false
  readonly property int serveCount: tailscale ? tailscale.serveCount : 0
  readonly property bool hasFunnel: tailscale ? tailscale.hasFunnel : false

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  readonly property color iconColor: {
    if (!root.isConnected) return Theme.inactive;
    if (root.hasFunnel) return Theme.violet;
    if (root.serveCount > 0) return Theme.accent;
    return Theme.ok;
  }

  readonly property string activeLabel: {
    if (!root.isConnected) return "";
    if (root.serveCount > 0) return root.serveCount.toString();
    return "";
  }

  Row {
    id: contentRow
    spacing: root.activeLabel !== "" ? 4 : 0
    anchors.verticalCenter: parent.verticalCenter

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "󰦝"
      font.family: Theme.mono
      font.pixelSize: Theme.iconMd
      color: root.iconColor

      Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.activeLabel !== ""
      text: root.activeLabel
      font.family: Theme.roundedFont
      font.pixelSize: Theme.fontXs
      font.weight: Font.DemiBold
      color: root.iconColor
    }
  }
}
