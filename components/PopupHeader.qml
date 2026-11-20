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

  height: root.subtitle.length > 0 ? 30 : 24
  Layout.preferredHeight: root.subtitle.length > 0 ? 30 : 24
  spacing: 8

  Text {
    visible: root.glyph.length > 0
    text: root.glyph
    font.family: Theme.mono
    font.pixelSize: 18
    color: root.glyphColor
    Layout.alignment: Qt.AlignVCenter
  }

  Column {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    spacing: 1

    Text {
      text: root.title
      font.family: Theme.displayFont
      font.pixelSize: Theme.fontLg
      font.weight: Font.SemiBold
      color: Theme.ink1
    }

    Text {
      width: parent.width
      visible: root.subtitle.length > 0
      text: root.subtitle
      font.family: Theme.textFont
      font.pixelSize: Theme.fontXs
      font.weight: Font.Medium
      color: Theme.ink3
      elide: Text.ElideRight
    }
  }
}
