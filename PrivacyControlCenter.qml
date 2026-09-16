// PrivacyControlCenter.qml — Detailed popup for active Camera and Microphone usage.
import QtQuick
import QtQuick.Layouts

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

  implicitWidth: 330
  implicitHeight: mainCol.height + 28
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: cardBg
    anchors.fill: parent
    color: "#1e1e2e"
    radius: 10
    border.color: "#313244"
    border.width: 1
  }

  Column {
    id: mainCol
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      margins: 14
    }
    spacing: 12

    // Header Row
    Item {
      width: parent.width
      height: 32

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
          text: "󰒃"
          font.family: root.monoFont
          font.pixelSize: 16
          color: "#89b4fa"
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "Hardware Privacy"
            font.family: root.monoFont
            font.pixelSize: 13
            font.bold: true
            color: "#cdd6f4"
          }

          Text {
            text: "Hardware Access Monitor"
            font.family: root.monoFont
            font.pixelSize: 10
            color: "#a6adc8"
          }
        }
      }

      // Status Pill
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: statusText.implicitWidth + 14
        height: 20
        radius: 10
        color: root.hasActive ? "#2b1c1c" : "#181825"
        border.color: root.hasActive ? (root.cameraActive ? "#a6e3a1" : "#fab387") : "#45475a"
        border.width: 1

        Text {
          id: statusText
          anchors.centerIn: parent
          text: root.hasActive ? "IN USE" : "IDLE"
          font.family: root.monoFont
          font.pixelSize: 9
          font.bold: true
          color: root.hasActive ? (root.cameraActive ? "#a6e3a1" : "#fab387") : "#6c7086"
        }
      }
    }

    // Divider
    Rectangle {
      width: parent.width
      height: 1
      color: "#313244"
    }

    // Camera Active Card
    Rectangle {
      visible: root.cameraActive
      width: parent.width
      height: camContentCol.height + 20
      radius: 8
      color: "#18261e"
      border.color: "#a6e3a1"
      border.width: 1

      Row {
        id: camContentRow
        anchors {
          top: parent.top
          left: parent.left
          right: parent.right
          margins: 10
        }
        spacing: 10

        Text {
          text: "󰄀"
          font.family: root.monoFont
          font.pixelSize: 22
          color: "#a6e3a1"
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: camContentCol
          width: parent.width - 32
          spacing: 3

          Row {
            spacing: 6
            Text {
              text: "Camera Active"
              font.family: root.monoFont
              font.pixelSize: 12
              font.bold: true
              color: "#ffffff"
            }

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

          Text {
            text: root.cameraDevices.length > 0 ? root.cameraDevices.join(", ") : "Lenovo FHD Webcam"
            font.family: root.monoFont
            font.pixelSize: 10
            color: "#a6adc8"
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: "Application: " + (root.cameraApps.length > 0 ? root.cameraApps.join(", ") : "Active Stream")
            font.family: root.monoFont
            font.pixelSize: 10
            font.bold: true
            color: "#a6e3a1"
            elide: Text.ElideRight
            width: parent.width
          }
        }
      }
    }

    // Microphone Active Card
    Rectangle {
      visible: root.micActive
      width: parent.width
      height: micContentCol.height + 20
      radius: 8
      color: "#2a1e17"
      border.color: "#fab387"
      border.width: 1

      Row {
        id: micContentRow
        anchors {
          top: parent.top
          left: parent.left
          right: parent.right
          margins: 10
        }
        spacing: 10

        Text {
          text: "󰍬"
          font.family: root.monoFont
          font.pixelSize: 22
          color: "#fab387"
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: micContentCol
          width: parent.width - 32
          spacing: 3

          Row {
            spacing: 6
            Text {
              text: "Microphone Active"
              font.family: root.monoFont
              font.pixelSize: 12
              font.bold: true
              color: "#ffffff"
            }

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

          Text {
            text: root.micDevices.length > 0 ? root.micDevices.join(", ") : "Default Microphone"
            font.family: root.monoFont
            font.pixelSize: 10
            color: "#a6adc8"
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: "Application: " + (root.micApps.length > 0 ? root.micApps.join(", ") : "Active Recording")
            font.family: root.monoFont
            font.pixelSize: 10
            font.bold: true
            color: "#fab387"
            elide: Text.ElideRight
            width: parent.width
          }
        }
      }
    }

    // All Idle Card (when neither is active)
    Rectangle {
      visible: !root.hasActive
      width: parent.width
      height: 52
      radius: 8
      color: "#181825"
      border.color: "#313244"
      border.width: 1

      Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
          text: "󰄬"
          font.family: root.monoFont
          font.pixelSize: 14
          color: "#a6e3a1"
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: "Camera and Microphone are idle"
          font.family: root.monoFont
          font.pixelSize: 11
          color: "#a6adc8"
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // Footer note
    Text {
      width: parent.width
      text: "Indicators automatically display in the top bar when hardware is in use."
      font.family: root.monoFont
      font.pixelSize: 9
      color: "#6c7086"
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
