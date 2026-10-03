pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property var docker: null

  readonly property bool connected: docker ? docker.connected : false
  readonly property int runningCount: docker ? docker.runningCount : 0
  readonly property int totalCount: docker ? docker.totalCount : 0

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  readonly property color iconColor: {
    if (!root.connected) return Theme.inactive;
    if (root.runningCount > 0) return Theme.ok;
    return Theme.ink3;
  }

  readonly property string activeLabel: {
    if (!root.connected) return "";
    if (root.runningCount > 0) return root.runningCount.toString();
    return "";
  }

  Row {
    id: contentRow
    spacing: root.activeLabel !== "" ? 4 : 0
    anchors.verticalCenter: parent.verticalCenter

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: ""
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
