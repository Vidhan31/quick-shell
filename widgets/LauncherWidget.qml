pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property bool active: false
  property bool hovered: false
  property string glyph: ""
  property int iconSize: 26

  implicitWidth: iconText.implicitWidth
  implicitHeight: Math.max(20, iconText.implicitHeight)

  Text {
    id: iconText
    anchors.centerIn: parent
    text: root.glyph
    font.family: Theme.mono
    font.pixelSize: root.iconSize
    color: root.active ? Theme.accent : (root.hovered ? Theme.accentHover : Theme.ink1)

    Behavior on color {
      ColorAnimation { duration: Theme.durationFast }
    }
  }
}
