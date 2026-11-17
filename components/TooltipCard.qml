pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  property string text: ""
  property string subtext: ""

  implicitWidth: Math.max(48, tipCol.implicitWidth + 16)
  implicitHeight: tipCol.implicitHeight + 10
  width: implicitWidth
  height: implicitHeight
  radius: 0
  color: Theme.inset
  border.color: Theme.tooltipBorder
  border.width: 1

  Column {
    id: tipCol
    anchors.centerIn: parent
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.text
      color: Theme.ink1
      font.pixelSize: Theme.fontSm
      font.weight: Font.Medium
      font.family: Theme.mono
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.subtext.length > 0
      text: root.subtext
      color: Theme.ink2
      font.pixelSize: Theme.fontXs
      font.family: Theme.mono
    }
  }
}
