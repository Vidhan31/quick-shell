pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property var service: null
  readonly property string monoFont: Theme.mono

  readonly property string summaryGlyph: service ? service.summaryGlyph : "󰚰"
  readonly property string summaryText: service ? service.summaryText : ""
  readonly property color statusColor: service ? service.statusColor : Theme.ink3
  readonly property color labelColor: service ? service.labelColor : Theme.ink3
  readonly property bool isSpinning: service ? (service.isSpinning === true) : false
  readonly property bool isUrgent: service ? (service.securityCount > 0 || service.offlineStagedReady) : false

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  Row {
    id: contentRow
    spacing: root.summaryText.length > 0 ? 4 : 0
    anchors.verticalCenter: parent.verticalCenter

    Text {
      id: iconText
      anchors.verticalCenter: parent.verticalCenter
      text: root.summaryGlyph
      font.family: root.monoFont
      font.pixelSize: Theme.iconMd
      color: root.statusColor

      Behavior on color {
        ColorAnimation { duration: Theme.durationFast }
      }

      NumberAnimation on rotation {
        running: root.isSpinning
        from: 0
        to: 360
        loops: Animation.Infinite
        duration: 900
      }

      onTextChanged: {
        if (!root.isSpinning) iconText.rotation = 0;
      }

      onVisibleChanged: {
        if (!root.isSpinning) iconText.rotation = 0;
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.summaryText.length > 0
      text: root.summaryText
      font.family: Theme.roundedFont
      font.pixelSize: Theme.fontXs
      font.weight: root.isUrgent ? Font.DemiBold : Font.Normal
      color: root.labelColor

      Behavior on color {
        ColorAnimation { duration: Theme.durationFast }
      }
    }
  }
}
