pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../components"

Item {
  id: root

  property var privacy: null
  property var privacyData: (privacy && privacy.privacyData) ? privacy.privacyData : ({
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

  implicitWidth: Theme.popupWidthSm
  implicitHeight: mainCol.height + 28

  PopupCard {
    id: cardBg
    anchors.fill: parent
    padding: 0
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

    Item {
      width: parent.width
      height: 32

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰒃"
          font.family: root.monoFont
          font.pixelSize: Theme.iconLg
          color: root.hasActive ? Theme.ok : Theme.ink2
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Privacy"
          font.pixelSize: Theme.fontMd
          font.weight: Font.DemiBold
          color: Theme.ink1
        }
      }

      StatusPill {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        text: root.hasActive ? "In Use" : "Idle"
        tone: root.hasActive ? (root.cameraActive ? "ok" : "warn") : "accent"
      }
    }

    Hairline {
      width: parent.width
    }

    Rectangle {
      visible: root.cameraActive
      width: parent.width
      height: camContentCol.height + 20
      radius: Theme.radiusBase
      color: Theme.tint(Theme.green, 0.12)
      border.width: 0

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
          font.pixelSize: Theme.iconLg
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
                NumberAnimation { from: 1.0; to: 0.25; duration: Theme.durationPulse; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.25; to: 1.0; duration: Theme.durationPulse; easing.type: Easing.InOutQuad }
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

    Rectangle {
      visible: root.micActive
      width: parent.width
      height: micContentCol.height + 20
      radius: Theme.radiusBase
      color: Theme.tint(Theme.amber, 0.12)
      border.width: 0

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
          font.pixelSize: Theme.iconLg
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
                NumberAnimation { from: 1.0; to: 0.25; duration: Theme.durationPulse; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.25; to: 1.0; duration: Theme.durationPulse; easing.type: Easing.InOutQuad }
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

    SectionCard {
      visible: !root.hasActive
      width: parent.width
      height: 52
      bordered: true
      color: Theme.inset

      Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
          text: "󰄬"
          font.family: root.monoFont
          font.pixelSize: Theme.fontLg
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
