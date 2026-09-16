// PrivacyIndicators.qml — Compact top bar indicators for active Camera and Microphone usage.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var privacyData: ({
    camera: { active: false, apps: [], devices: [] },
    microphone: { active: false, apps: [], devices: [] }
  })

  readonly property bool cameraActive: privacyData && privacyData.camera && privacyData.camera.active === true
  readonly property bool micActive: privacyData && privacyData.microphone && privacyData.microphone.active === true
  readonly property bool hasActive: cameraActive || micActive

  readonly property var cameraApps: (privacyData && privacyData.camera && privacyData.camera.apps) ? privacyData.camera.apps : []
  readonly property var micApps: (privacyData && privacyData.microphone && privacyData.microphone.apps) ? privacyData.microphone.apps : []
  readonly property var cameraDevices: (privacyData && privacyData.camera && privacyData.camera.devices) ? privacyData.camera.devices : []
  readonly property var micDevices: (privacyData && privacyData.microphone && privacyData.microphone.devices) ? privacyData.microphone.devices : []

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  signal clicked()

  implicitHeight: 24
  implicitWidth: contentRow.width
  width: implicitWidth
  height: implicitHeight

  // Streaming Process running privacy-bridge.py
  Process {
    id: bridgeProc
    command: ["python3", "-u", "/home/dev/Projects/quick-shell/privacy-bridge.py", "monitor"]
    running: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: data => {
        const trimmed = data.trim();
        if (!trimmed || !trimmed.startsWith("{")) return;
        try {
          const parsed = JSON.parse(trimmed);
          if (parsed && (parsed.camera || parsed.microphone)) {
            root.privacyData = parsed;
          }
        } catch (e) {
          console.warn("PrivacyIndicators parse error:", e);
        }
      }
    }

    onExited: (code, status) => {
      restartTimer.restart();
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: {
      bridgeProc.running = true;
    }
  }

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
