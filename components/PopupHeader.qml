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
