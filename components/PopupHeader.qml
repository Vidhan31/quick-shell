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

  height: 38
  Layout.preferredHeight: 38
  spacing: 10

  Text {
    visible: root.glyph.length > 0
    text: root.glyph
    font.family: Theme.mono
    font.pixelSize: 20
    color: root.glyphColor
    Layout.alignment: Qt.AlignVCenter
  }

  Column {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    spacing: 2

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
      text: root.subtitle.toUpperCase()
      font.family: Theme.mono
      font.pixelSize: Theme.fontXs
      font.letterSpacing: 1.3
      font.weight: Font.Medium
      color: Theme.ink3
      elide: Text.ElideRight
    }
  }
}
