// PrivacyIndicators.qml — Compact top bar indicators for active Camera and Microphone usage.
// Native C++ Qt6 QML module (Quickshell.Plugins.Privacy).
import QtQuick
import Quickshell.Plugins.Privacy
import "../theme"

Item {
  id: root

  PrivacyMonitor {
    id: monitor
    running: true
    interval: 800
  }

  property var privacyData: monitor.privacyData

  readonly property bool cameraActive: monitor.cameraActive
  readonly property bool micActive: monitor.micActive
  readonly property bool hasActive: monitor.hasActive

  readonly property var cameraApps: monitor.cameraApps
  readonly property var micApps: monitor.micApps
  readonly property var cameraDevices: monitor.cameraDevices
  readonly property var micDevices: monitor.micDevices

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  signal clicked()

  function refresh(): void {
    monitor.refresh();
  }

  implicitHeight: Theme.btnHeightSm
  implicitWidth: contentRow.width
  width: implicitWidth
  height: implicitHeight

  Row {
    id: contentRow
    spacing: 6
    anchors.verticalCenter: parent.verticalCenter

    // -------------------------------------------------------------
    // Camera Indicator Pill
    // -------------------------------------------------------------
    Item {
      id: camPill
      visible: root.cameraActive
      width: root.cameraActive ? (camInnerRow.width + 16) : 0
      height: Theme.btnHeightSm
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        id: camBg
        anchors.fill: parent
        radius: Theme.radiusSm
        color: camMouse.containsMouse ? Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.25) : Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.15)
        border.color: Theme.ok
        border.width: 1

        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Row {
        id: camInnerRow
        anchors.centerIn: parent
        spacing: 6

        // Camera Icon
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰄀"
          font.family: root.monoFont
          font.pixelSize: 13
          font.bold: true
          color: Theme.ok
        }

        // Camera text label (app name if available, else "Cam")
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.cameraApps.length > 0 ? ("Cam: " + root.cameraApps[0]) : "Camera"
          font.family: root.monoFont
          font.pixelSize: Theme.fontSm
          font.bold: true
          color: Theme.ok
          elide: Text.ElideRight
          width: Math.min(implicitWidth, 110)
        }

        // Live Pulsing Green Status Dot
        Rectangle {
          width: 6
          height: 6
          radius: 3
          anchors.verticalCenter: parent.verticalCenter
          color: Theme.ok

          SequentialAnimation on opacity {
            running: root.cameraActive
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.25; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.25; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
          }
        }
      }

      MouseArea {
        id: camMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.clicked()
      }
    }

    // -------------------------------------------------------------
    // Microphone Indicator Pill
    // -------------------------------------------------------------
    Item {
      id: micPill
      visible: root.micActive
      width: root.micActive ? (micInnerRow.width + 16) : 0
      height: Theme.btnHeightSm
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        id: micBg
        anchors.fill: parent
        radius: Theme.radiusSm
        color: micMouse.containsMouse ? Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0.25) : Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0.15)
        border.color: Theme.warn
        border.width: 1

        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Row {
        id: micInnerRow
        anchors.centerIn: parent
        spacing: 6

        // Microphone Icon
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍬"
          font.family: root.monoFont
          font.pixelSize: 13
          font.bold: true
          color: Theme.warn
        }

        // Microphone text label (app name if available, else "Mic")
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

        // Live Pulsing Peach/Orange Status Dot
        Rectangle {
          width: 6
          height: 6
          radius: 3
          anchors.verticalCenter: parent.verticalCenter
          color: Theme.warn

          SequentialAnimation on opacity {
            running: root.micActive
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.25; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.25; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
          }
        }
      }

      MouseArea {
        id: micMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.clicked()
      }
    }
  }
}
