pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property var privacy: null

  readonly property var monitor: privacy ? privacy.monitor : null
  property var privacyData: privacy ? privacy.privacyData : null

  readonly property bool micActive: privacy ? privacy.micActive : false
  readonly property bool hasActive: privacy ? privacy.hasActive : false

  readonly property var micApps: privacy ? privacy.micApps : []
  readonly property var micDevices: privacy ? privacy.micDevices : []

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  signal clicked()

  function refresh(): void {
    if (privacy) privacy.refresh();
  }

  implicitHeight: Theme.btnHeightSm
  implicitWidth: root.hasActive ? (contentRow.implicitWidth + 16) : 0
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: capsuleBg
    anchors.fill: parent
    radius: Theme.radiusSm
    color: privacyMouse.containsMouse ? Theme.hoverFill : Theme.tint(Theme.warn, 0.15)
    border.width: 0

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: 8

    Row {
      id: micSection
      visible: root.micActive
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰍬"
        font.family: root.monoFont
        font.pixelSize: Theme.fontGlyphMd
        font.bold: true
        color: Theme.warn
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.micApps.length > 0 ? ("Mic: " + root.micApps[0]) : "Microphone"
        font.family: root.monoFont
        font.pixelSize: Theme.fontSm
        font.bold: true
        color: Theme.warn
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 110)
      }

      Rectangle {
        width: 7
        height: 7
        radius: 3.5
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.warn
      }
    }
  }

  MouseArea {
    id: privacyMouse
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onClicked: root.clicked()
  }
}
