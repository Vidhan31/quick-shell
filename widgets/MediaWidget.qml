pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  property var media: null

  readonly property var activePlayer: media ? media.activePlayer : null
  readonly property bool hasPlayer: media ? media.hasPlayer : false
  readonly property bool isPlaying: media ? media.isPlaying : false

  readonly property string title: media ? media.title : "Media"
  readonly property string artist: media ? media.artist : ""

  Row {
    id: contentRow
    spacing: 6
    anchors.verticalCenter: parent.verticalCenter

    Row {
      id: eqRow
      width: 13
      height: 16
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      visible: root.isPlaying

      Repeater {
        model: [
          { minH: 4, maxH: 13, dur: 420 },
          { minH: 6, maxH: 15, dur: 320 },
          { minH: 3, maxH: 12, dur: 480 }
        ]

        Rectangle {
          id: eqBar
          required property var modelData
          required property int index

          width: 3
          height: modelData.minH
          radius: 1.5
          color: Theme.ok

          SequentialAnimation on height {
            running: root.isPlaying
            loops: Animation.Infinite

            NumberAnimation {
              to: eqBar.modelData.maxH
              duration: eqBar.modelData.dur
              easing.type: Easing.InOutQuad
            }
            NumberAnimation {
              to: eqBar.modelData.minH
              duration: eqBar.modelData.dur
              easing.type: Easing.InOutQuad
            }
          }
        }
      }
    }

    Text {
      visible: !root.isPlaying
      anchors.verticalCenter: parent.verticalCenter
      text: root.hasPlayer ? "󰏤" : "󰝚"
      font.family: root.monoFont
      font.pixelSize: Theme.fontGlyphMd
      color: root.hasPlayer ? Theme.warn : Theme.ink2
    }

    Text {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      text: {
        if (!root.hasPlayer) return "Media";
        if (root.artist) return root.title + " • " + root.artist;
        return root.title;
      }
      font.family: Theme.textFont
      font.pixelSize: Theme.fontBase
      font.bold: root.isPlaying
      color: root.isPlaying ? Theme.ink1 : Theme.ink2
      elide: Text.ElideRight
      width: Math.min(implicitWidth, 160)
    }
  }
}
