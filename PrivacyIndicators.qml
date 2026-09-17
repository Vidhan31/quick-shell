// PrivacyIndicators.qml — Compact top bar indicators for active Camera and Microphone usage.
// Native C++ Qt6 QML module (Quickshell.Plugins.Privacy).
import QtQuick
import Quickshell.Plugins.Privacy

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

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  signal clicked()

  function refresh(): void {
    monitor.refresh();
  }

  implicitHeight: 24
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
      height: 24
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        id: camBg
        anchors.fill: parent
        radius: 6
        color: camMouse.containsMouse ? "#264233" : "#1a2e22"
        border.color: "#a6e3a1"
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
          color: "#a6e3a1"
        }

        // Camera text label (app name if available, else "Cam")
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.cameraApps.length > 0 ? ("Cam: " + root.cameraApps[0]) : "Camera"
          font.family: root.monoFont
          font.pixelSize: 11
          font.bold: true
          color: "#a6e3a1"
          elide: Text.ElideRight
          width: Math.min(implicitWidth, 110)
        }

        // Live Pulsing Green Status Dot
        Rectangle {
          width: 6
          height: 6
          radius: 3
          anchors.verticalCenter: parent.verticalCenter
          color: "#a6e3a1"

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
      height: 24
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        id: micBg
        anchors.fill: parent
        radius: 6
        color: micMouse.containsMouse ? "#422f24" : "#2e2119"
        border.color: "#fab387"
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
          color: "#fab387"
        }

        // Microphone text label (app name if available, else "Mic")
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.micApps.length > 0 ? ("Mic: " + root.micApps[0]) : "Microphone"
          font.family: root.monoFont
          font.pixelSize: 11
          font.bold: true
          color: "#fab387"
          elide: Text.ElideRight
          width: Math.min(implicitWidth, 110)
        }

        // Live Pulsing Peach/Orange Status Dot
        Rectangle {
          width: 6
          height: 6
          radius: 3
          anchors.verticalCenter: parent.verticalCenter
          color: "#fab387"

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
