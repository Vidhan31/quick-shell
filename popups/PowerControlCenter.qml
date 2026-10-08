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
  readonly property int preferredHeight: Math.max(160, bodyCol.height + (card.padding * 2))
  property int popupHeight: 330

  function syncHeight(): void {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (bodyCol.height > 0)
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

        RowBase {
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

        RowBase {
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

        RowBase {
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

        RowBase {
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

        RowBase {
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
        implicitHeight: confirmCol.implicitHeight + 20
        radius: Theme.radiusCard
        color: Theme.inset
        border.color: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : Theme.cardBorder)
        border.width: 1

        Column {
          id: confirmCol
          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
          }
          spacing: 10

          RowLayout {
            width: parent.width
            spacing: 8

            Text {
              text: root.pendingAction === "shutdown" ? "󰐥" : (root.pendingAction === "reboot" ? "󰜉" : "󰍃")
              font.family: Theme.mono
              font.pixelSize: Theme.fontGlyphLg
              color: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : Theme.accent)
            }

            Column {
              Layout.fillWidth: true
              spacing: 2

              Text {
                text: root.pendingAction === "shutdown" ? "Shut down system?" : (root.pendingAction === "reboot" ? "Restart system?" : "Log out of session?")
                font.family: Theme.displayFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Text {
                text: "KDE will prompt to save unsaved documents."
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: 8

            Item {
              Layout.fillWidth: true
            }

            TextBtn {
              text: "Cancel"
              onClicked: {
                root.pendingAction = "";
              }
            }

            PrimaryBtn {
              text: root.pendingAction === "shutdown" ? "Shut Down" : (root.pendingAction === "reboot" ? "Restart" : "Log Out")
              glyph: root.pendingAction === "shutdown" ? "󰐥" : (root.pendingAction === "reboot" ? "󰜉" : "󰍃")
              fill: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : Theme.accent)
              ink: Theme.darkInk
              onClicked: {
                const action = root.pendingAction;
                root.pendingAction = "";
                if (action === "shutdown" && root.power) {
                  root.power.shutdown();
                } else if (action === "reboot" && root.power) {
                  root.power.reboot();
                } else if (action === "logout" && root.power) {
                  root.power.logout();
                }
                root.closeRequested();
              }
            }
          }
        }
      }
    }
  }
}
