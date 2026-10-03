pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"

RowLayout {
  id: root

  property string glyph: ""
  property color glyphColor: Theme.accent
  property string title: ""
  property string subtitle: ""

  default property alias actions: root.data

  height: 36
  Layout.preferredHeight: 36
  spacing: 8

  Text {
    visible: root.glyph.length > 0
    Layout.alignment: Qt.AlignVCenter
    text: root.glyph
    font.family: Theme.mono
    font.pixelSize: Theme.iconLg
    color: root.glyphColor
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  }

  Column {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    spacing: 0

    Text {
      text: root.title
      font.family: Theme.displayFont
      font.pixelSize: Theme.fontMd
      font.weight: Font.DemiBold
      color: Theme.ink1
    }

    Text {
      width: parent.width
      visible: root.subtitle.length > 0
      text: root.subtitle
      font.family: Theme.textFont
      font.pixelSize: Theme.fontXs
      color: Theme.ink3
      elide: Text.ElideRight
    }
  }
}
