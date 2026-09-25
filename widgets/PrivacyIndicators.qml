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
  implicitWidth: root.hasActive ? (contentRow.implicitWidth + 16) : 0
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: capsuleBg
    anchors.fill: parent
    radius: Theme.radiusSm
    color: privacyMouse.containsMouse ? Theme.hoverFill : Theme.surface
    border.color: (root.cameraActive && root.micActive) ? Theme.warn : (root.cameraActive ? Theme.ok : Theme.warn)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
  }

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: 8

    // Camera Section
    Row {
      id: camSection
      visible: root.cameraActive
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰄀"
        font.family: root.monoFont
        font.pixelSize: 16
        font.bold: true
        color: Theme.ok
      }

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

      Rectangle {
        width: 7
        height: 7
        radius: 3.5
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

    // Divider between camera and mic if both active
    Rectangle {
      visible: root.cameraActive && root.micActive
      width: 1
      height: 12
      anchors.verticalCenter: parent.verticalCenter
      color: Theme.line
    }

    // Microphone Section
    Row {
      id: micSection
      visible: root.micActive
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰍬"
        font.family: root.monoFont
        font.pixelSize: 16
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

        SequentialAnimation on opacity {
          running: root.micActive
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.25; duration: 600; easing.type: Easing.InOutQuad }
          NumberAnimation { from: 0.25; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
        }
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
