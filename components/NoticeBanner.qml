pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"

Rectangle {
  id: root

  property string tone: "warn"
  property string glyph: ""
  property int glyphSize: Theme.iconMd
  property string title: ""
  property string message: ""

  default property alias extraContent: extraCol.data

  readonly property color toneColor: {
    if (root.tone === "ok") return Theme.green;
    if (root.tone === "warn") return Theme.amber;
    if (root.tone === "err") return Theme.red;
    if (root.tone === "violet") return Theme.violet;
    if (root.tone === "teal") return Theme.teal;
    return Theme.accent;
  }

  readonly property color washColor: {
    if (root.tone === "ok") return Theme.okBg;
    if (root.tone === "warn") return Theme.warnBg;
    if (root.tone === "err") return Theme.errBg;
    if (root.tone === "violet") return Theme.violetBg;
    return Theme.accentBg;
  }

  radius: Theme.radiusBase
  color: washColor
  border.width: 1
  border.color: Theme.tint(toneColor, 0.4)
  implicitHeight: mainCol.implicitHeight + 16

  ColumnLayout {
    id: mainCol
    anchors.fill: parent
    anchors.margins: 8
    spacing: 6

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        visible: root.glyph.length > 0
        Layout.alignment: Qt.AlignTop
        text: root.glyph
        font.family: Theme.mono
        font.pixelSize: root.glyphSize
        color: root.toneColor
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
          visible: root.title.length > 0
          Layout.fillWidth: true
          text: root.title
          font.family: Theme.textFont
          font.pixelSize: Theme.fontBase
          font.weight: Font.DemiBold
          color: Theme.ink1
        }

        Text {
          visible: root.message.length > 0
          Layout.fillWidth: true
          text: root.message
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          color: Theme.ink2
          wrapMode: Text.WordWrap
        }
      }
    }

    ColumnLayout {
      id: extraCol
      Layout.fillWidth: true
      spacing: 6
    }
  }
}
