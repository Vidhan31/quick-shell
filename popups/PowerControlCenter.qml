pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../components"

Item {
  id: root

  property var power: null
  property string pendingAction: ""

  signal closeRequested()

  implicitWidth: Theme.popupWidthSm
  readonly property int preferredHeight: root.pendingAction !== "" ? 258 : 320
  property int popupHeight: preferredHeight
  implicitHeight: popupHeight

  function syncHeight(): void {
    popupHeight = preferredHeight;
  }

  onPendingActionChanged: root.syncHeight()
  onPowerChanged: root.syncHeight()
  onPreferredHeightChanged: root.syncHeight()

  function actionAvailable(key: string): bool {
    if (!root.power) return key !== "windows";
    if (key === "sleep") return root.power.canSuspend;
    if (key === "reboot") return root.power.canReboot;
    if (key === "windows") return root.power.canRebootToWindows;
    if (key === "shutdown") return root.power.canPowerOff;
    return true;
  }

  function activateAction(key: string): void {
    if (key === "lock") {
      if (root.power) root.power.lock();
      root.closeRequested();
    } else if (key === "sleep") {
      if (root.power) root.power.suspend();
      root.closeRequested();
    } else if (key === "quickshell") {
      root.closeRequested();
      if (root.power && typeof root.power.restartQuickshell === "function") {
        root.power.restartQuickshell();
      } else {
        Quickshell.execDetached({
          command: [
            "sh", "-c",
            "if systemctl --user is-active --quiet quickshell.service; then systemctl --user restart quickshell.service; else quickshell -p \"" + Quickshell.shellPath(".") + "\" & fi"
          ],
          unbindStdout: true
        });
      }
    } else {
      root.pendingAction = key;
    }
  }

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
      spacing: 8

      PopupHeader {
        width: parent.width
        glyph: "󰐥"
        glyphColor: Theme.accent
        title: "Session & Power"
        subtitle: "Fedora Linux · KDE Plasma"
      }

      Hairline { width: parent.width }

      GridLayout {
        id: actionsCol
        visible: root.pendingAction === ""
        width: parent.width
        columns: 2
        rowSpacing: 6
        columnSpacing: 8

        Repeater {
          model: [
            { key: "shutdown", title: "Shut Down", glyph: "󰐥", color: Theme.err },
            { key: "reboot", title: "Restart", glyph: "󰜉", color: Theme.warn },
            { key: "windows", title: "Windows 11", glyph: "󰍲", color: Theme.teal },
            { key: "sleep", title: "Sleep", glyph: "󰒲", color: Theme.accent }
          ]

          delegate: ActionRow {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            visible: root.actionAvailable(modelData.key)
            base: Theme.surface
            hover: Theme.surfaceElevated
            press: Theme.hoverFill
            rad: 10
            onClicked: root.activateAction(modelData.key)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 7
              spacing: 8

              Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 8
                color: Theme.tint(modelData.color, 0.13)

                Text {
                  anchors.centerIn: parent
                  text: modelData.glyph
                  font.family: Theme.mono
                  font.pixelSize: Theme.iconMd
                  color: modelData.color
                }
              }

              Text {
                Layout.fillWidth: true
                text: modelData.title
                font.family: Theme.textFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      Hairline {
        visible: root.pendingAction === ""
        width: parent.width
      }

      Column {
        id: secondaryActions
        visible: root.pendingAction === ""
        width: parent.width
        spacing: 2

        Repeater {
          model: [
            { key: "lock", title: "Lock Screen", glyph: "󰌾", color: Theme.ink2 },
            { key: "logout", title: "Log Out", glyph: "󰍃", color: Theme.ink2 },
            { key: "quickshell", title: "Restart Quickshell", glyph: "󰑓", color: Theme.accent }
          ]

          delegate: ActionRow {
            required property var modelData
            width: secondaryActions.width
            height: 30
            rad: 7
            onClicked: root.activateAction(modelData.key)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 9
              anchors.rightMargin: 9
              spacing: 10

              Text {
                text: modelData.glyph
                font.family: Theme.mono
                font.pixelSize: Theme.iconSm
                color: modelData.color
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                Layout.fillWidth: true
                text: modelData.title
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSm
                font.weight: Font.Medium
                color: Theme.ink2
                verticalAlignment: Text.AlignVCenter
              }
            }
          }
        }
      }

      Rectangle {
        id: confirmCard
        visible: root.pendingAction !== ""
        width: parent.width
        height: 170
        radius: Theme.radiusCard
        color: Theme.inset
        border.color: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : (root.pendingAction === "windows" ? Theme.teal : Theme.accent))
        border.width: 1

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 8

          RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
              Layout.preferredWidth: 24
              Layout.alignment: Qt.AlignTop
              text: root.pendingAction === "shutdown" ? "󰐥" : (root.pendingAction === "reboot" ? "󰜉" : (root.pendingAction === "windows" ? "󰍲" : "󰍃"))
              font.family: Theme.mono
              font.pixelSize: Theme.iconLg
              color: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : (root.pendingAction === "windows" ? Theme.teal : Theme.accent))
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 3

              Text {
                Layout.fillWidth: true
                text: root.pendingAction === "shutdown" ? "Shut down system?" : (root.pendingAction === "reboot" ? "Restart system?" : (root.pendingAction === "windows" ? "Reboot to Windows 11?" : "Log out of session?"))
                font.family: Theme.displayFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                text: root.pendingAction === "shutdown" ? "Power off the computer." : (root.pendingAction === "reboot" ? "Restart the operating system." : (root.pendingAction === "windows" ? "Boot Windows 11 once." : "End the current session."))
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
                wrapMode: Text.WordWrap
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.pendingAction === "windows" ? "The next boot will return to Fedora Linux." : "KDE will prompt to save unsaved documents."
            font.family: Theme.textFont
            font.pixelSize: Theme.fontXs
            color: Theme.ink2
            wrapMode: Text.WordWrap
          }

          Item { Layout.fillHeight: true }

          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Item { Layout.fillWidth: true }

            TextButton {
              text: "Cancel"
              onClicked: root.pendingAction = ""
            }

            PrimaryButton {
              text: root.pendingAction === "shutdown" ? "Shut Down" : (root.pendingAction === "reboot" ? "Restart" : (root.pendingAction === "windows" ? "Reboot to Windows" : "Log Out"))
              glyph: root.pendingAction === "shutdown" ? "󰐥" : (root.pendingAction === "reboot" ? "󰜉" : (root.pendingAction === "windows" ? "󰍲" : "󰍃"))
              fill: root.pendingAction === "shutdown" ? Theme.err : (root.pendingAction === "reboot" ? Theme.warn : (root.pendingAction === "windows" ? Theme.teal : Theme.accent))
              ink: Theme.darkInk
              onClicked: {
                const action = root.pendingAction;
                root.pendingAction = "";
                root.closeRequested();
                if (action === "shutdown" && root.power) {
                  root.power.shutdown();
                } else if (action === "reboot" && root.power) {
                  root.power.reboot();
                } else if (action === "windows" && root.power) {
                  root.power.rebootToWindows();
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
