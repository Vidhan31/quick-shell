pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  property string text: ""

  implicitHeight: 18
  implicitWidth: Math.max(18, Math.ceil(label.implicitWidth) + 8)
  radius: Theme.radiusSm
  color: Theme.inset
  border.color: Theme.line
  border.width: 1

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    font.family: Theme.mono
    font.pixelSize: Theme.fontXs
    font.weight: Font.DemiBold
    color: Theme.ink2
  }
}
