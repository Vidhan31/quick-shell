pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property var power: null

  implicitWidth: iconText.implicitWidth
  implicitHeight: Math.max(20, iconText.implicitHeight)

  Text {
    id: iconText
    anchors.centerIn: parent
    text: "󰐥"
    font.family: Theme.mono
    font.pixelSize: Theme.iconMd
    color: Theme.ink2

    Behavior on color {
      ColorAnimation { duration: Theme.durationFast }
    }
  }
}
