pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"

Item {
  id: root

  property var power: null
  property string pendingAction: ""

  signal closeRequested()

  implicitWidth: Theme.popupWidthSm
  readonly property int preferredHeight: 330
  property int popupHeight: 330

  function syncHeight(): void {
    popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

  Keys.onEscapePressed: event => {
    if (root.pendingAction !== "") {
      root.pendingAction = "";
      event.accepted = true;
    } else {
      root.closeRequested();
      event.accepted = true;
    }
  }

  PopupCard {
    id: card
    anchors.fill: parent

    Column {
      id: bodyCol
      width: parent.width
      spacing: 10

      PopupHeader {
        width: parent.width
        glyph: "󰐥"
        glyphColor: Theme.accent
        title: "Session & Power"
        subtitle: "Fedora Linux · KDE Plasma"
      }

      Hairline {
        width: parent.width
      }

      Column {
        id: actionsCol
        visible: root.pendingAction === ""
        width: parent.width
        spacing: 4

        ActionRow {
          id: lockRow
          width: parent.width
          height: 42
          rad: Theme.radiusBase
          onClicked: {
            if (root.power) root.power.lock();
            root.closeRequested();
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
              text: "󰌾"
              font.family: Theme.mono
              font.pixelSize: Theme.iconMd
              color: Theme.ink2
            }

            Column {
              Layout.fillWidth: true
              spacing: 1

              Text {
                text: "Lock Screen"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Text {
                text: "Lock active graphical session"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
              }
            }
          }
        }

        ActionRow {
          id: sleepRow
          width: parent.width
          height: 42
          rad: Theme.radiusBase
          visible: root.power ? root.power.canSuspend : true
          onClicked: {
            if (root.power) root.power.suspend();
            root.closeRequested();
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
              text: "󰒲"
              font.family: Theme.mono
              font.pixelSize: Theme.iconMd
              color: Theme.ink2
            }

            Column {
              Layout.fillWidth: true
              spacing: 1

              Text {
                text: "Sleep"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Text {
                text: "Suspend computer to RAM"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
              }
            }
          }
        }

        ActionRow {
          id: logoutRow
          width: parent.width
          height: 42
          rad: Theme.radiusBase
          onClicked: {
            root.pendingAction = "logout";
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
              text: "󰍃"
              font.family: Theme.mono
              font.pixelSize: Theme.iconMd
              color: Theme.ink2
            }

            Column {
              Layout.fillWidth: true
              spacing: 1

              Text {
                text: "Log Out"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Text {
                text: "End desktop session"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
              }
            }
          }
        }

        ActionRow {
          id: rebootRow
          width: parent.width
          height: 42
          rad: Theme.radiusBase
          visible: root.power ? root.power.canReboot : true
          onClicked: {
            root.pendingAction = "reboot";
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
              text: "󰜉"
              font.family: Theme.mono
              font.pixelSize: Theme.iconMd
              color: Theme.warn
            }

            Column {
              Layout.fillWidth: true
              spacing: 1

              Text {
                text: "Restart"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Text {
                text: "Reboot operating system"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
              }
            }
          }
        }

        ActionRow {
          id: shutdownRow
          width: parent.width
          height: 42
          rad: Theme.radiusBase
          visible: root.power ? root.power.canPowerOff : true
          onClicked: {
            root.pendingAction = "shutdown";
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Text {
              text: "󰐥"
              font.family: Theme.mono
              font.pixelSize: Theme.iconMd
              color: Theme.err
            }

            Column {
              Layout.fillWidth: true
              spacing: 1

              Text {
                text: "Shut Down"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Text {
                text: "Power off the computer"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
              }
            }
          }
        }
      }

      Rectangle {
        id: confirmCard
        visible: root.pendingAction !== ""
        width: parent.width
        height: actionsCol.height
        radius: Theme.radiusCard
        color: Theme.inset
        border.color: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : Theme.accent)
        border.width: 1

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 14
          spacing: 10

          RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
              Layout.preferredWidth: 38
              Layout.preferredHeight: 38
              radius: Theme.radiusBase
              color: Qt.alpha(root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : Theme.accent), 0.15)

              Text {
                anchors.centerIn: parent
                text: root.pendingAction === "shutdown" ? "󰐥" : (root.pendingAction === "reboot" ? "󰜉" : "󰍃")
                font.family: Theme.mono
                font.pixelSize: Theme.fontGlyphLg
                color: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : Theme.accent)
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                Layout.fillWidth: true
                text: root.pendingAction === "shutdown" ? "Shut down system?" : (root.pendingAction === "reboot" ? "Restart system?" : "Log out of session?")
                font.family: Theme.displayFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                text: root.pendingAction === "shutdown" ? "Power off the computer completely." : (root.pendingAction === "reboot" ? "Reboot the operating system." : "End current user session.")
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
                wrapMode: Text.WordWrap
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: "KDE will prompt to save unsaved documents."
            font.family: Theme.textFont
            font.pixelSize: Theme.fontXs
            color: Theme.ink2
            wrapMode: Text.WordWrap
          }

          Item {
            Layout.fillHeight: true
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
              Layout.fillWidth: true
            }

            TextButton {
              text: "Cancel"
              onClicked: {
                root.pendingAction = "";
              }
            }

            PrimaryButton {
              text: root.pendingAction === "shutdown" ? "Shut Down" : (root.pendingAction === "reboot" ? "Restart" : "Log Out")
              glyph: root.pendingAction === "shutdown" ? "󰐥" : (root.pendingAction === "reboot" ? "󰜉" : "󰍃")
              fill: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : Theme.accent)
              ink: Theme.darkInk
              onClicked: {
                const action = root.pendingAction;
                root.pendingAction = "";
                root.closeRequested();
                if (action === "shutdown" && root.power) {
                  root.power.shutdown();
                } else if (action === "reboot" && root.power) {
                  root.power.reboot();
                } else if (action === "logout" && root.power) {
                  root.power.logout();
                }
              }
            }
          }
        }
      }
    }
  }
}
