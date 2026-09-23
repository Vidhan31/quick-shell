// PrivacyControlCenter.qml — Detailed popup for active Camera and Microphone usage.
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"

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

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  implicitWidth: 330
  implicitHeight: mainCol.height + 28
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: cardBg
    anchors.fill: parent
    color: Theme.bg
    radius: Theme.radiusCard
    border.color: Theme.cardBorder
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
          color: Theme.accent
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "Hardware Privacy"
            font.family: root.monoFont
            font.pixelSize: Theme.fontMd
            font.bold: true
            color: Theme.ink1
          }

          Text {
            text: "Hardware Access Monitor"
            font.family: root.monoFont
            font.pixelSize: Theme.fontXs
            color: Theme.ink2
          }
        }
      }

      // Status Pill
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: statusText.implicitWidth + 14
        height: 20
        radius: Theme.radiusChip
        color: root.hasActive ? Qt.rgba(0.87, 0.39, 0.39, 0.15) : Theme.inset
        border.color: root.hasActive ? (root.cameraActive ? Theme.ok : Theme.warn) : Theme.line
        border.width: 1

        Text {
          id: statusText
          anchors.centerIn: parent
          text: root.hasActive ? "IN USE" : "IDLE"
          font.family: root.monoFont
          font.pixelSize: 9
          font.bold: true
          color: root.hasActive ? (root.cameraActive ? Theme.ok : Theme.warn) : Theme.ink3
        }
      }
    }

    // Divider
    Hairline {
      width: parent.width
    }

    // Camera Active Card
    Rectangle {
      visible: root.cameraActive
      width: parent.width
      height: camContentCol.height + 20
      radius: Theme.radiusBase
      color: Qt.rgba(0.27, 0.78, 0.53, 0.12)
      border.color: Theme.ok
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
          color: Theme.ok
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
              font.pixelSize: Theme.fontBase
              font.bold: true
              color: Theme.ink1
            }

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

          Text {
            text: root.cameraDevices.length > 0 ? root.cameraDevices.join(", ") : "Lenovo FHD Webcam"
            font.family: root.monoFont
            font.pixelSize: Theme.fontXs
            color: Theme.ink2
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: "Application: " + (root.cameraApps.length > 0 ? root.cameraApps.join(", ") : "Active Stream")
            font.family: root.monoFont
            font.pixelSize: Theme.fontXs
            font.bold: true
            color: Theme.ok
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
      radius: Theme.radiusBase
      color: Qt.rgba(0.89, 0.65, 0.23, 0.12)
      border.color: Theme.warn
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
          color: Theme.warn
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
              font.pixelSize: Theme.fontBase
              font.bold: true
              color: Theme.ink1
            }

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

          Text {
            text: root.micDevices.length > 0 ? root.micDevices.join(", ") : "Default Microphone"
            font.family: root.monoFont
            font.pixelSize: Theme.fontXs
            color: Theme.ink2
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: "Application: " + (root.micApps.length > 0 ? root.micApps.join(", ") : "Active Recording")
            font.family: root.monoFont
            font.pixelSize: Theme.fontXs
            font.bold: true
            color: Theme.warn
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
      radius: Theme.radiusBase
      color: Theme.inset
      border.color: Theme.line
      border.width: 1

      Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
          text: "󰄬"
          font.family: root.monoFont
          font.pixelSize: 14
          color: Theme.ok
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: "Camera and Microphone are idle"
          font.family: root.monoFont
          font.pixelSize: Theme.fontSm
          color: Theme.ink2
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
      color: Theme.ink3
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
