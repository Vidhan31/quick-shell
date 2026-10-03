pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.utils
import "../theme"
import "../components"

PanelWindow {
  id: win

  property var service: null

  screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  visible: win.service !== null && win.service.isActive
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "quickshell-polkit"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  property real cardOffset: 0
  property real cardScale: 0.96
  property real cardOpacity: 0.0
  property bool showPlainPassword: false

  IconResolver {
    id: iconResolver
  }

  function resolveAuthIcon(iconName: string): string {
    if (iconName) {
      const p = iconResolver.resolveNamedOrPath(iconName);
      if (p) return p;
    }
    return iconResolver.resolveStockIcon("dialog-password")
      || iconResolver.resolveStockIcon("security-high")
      || iconResolver.fallbackIcon();
  }

  function submit(): void {
    if (!win.service) return;
    const val = passwordInput.text;
    passwordInput.text = "";
    win.service.submit(val);
  }

  function cancel(): void {
    passwordInput.text = "";
    if (win.service) {
      win.service.cancel();
    }
  }

  onVisibleChanged: {
    if (visible) {
      win.showPlainPassword = false;
      passwordInput.text = "";
      enterAnim.restart();
      armTimer.restart();
    } else {
      armTimer.stop();
      enterAnim.stop();
      win.cardScale = 0.96;
      win.cardOpacity = 0.0;
      win.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
      passwordInput.text = "";
    }
  }

  Timer {
    id: armTimer
    interval: 50
    repeat: false
    onTriggered: {
      win.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
      passwordInput.forceActiveFocus();
    }
  }

  ParallelAnimation {
    id: enterAnim
    NumberAnimation {
      target: win
      property: "cardScale"
      from: 0.96
      to: 1.0
      duration: Theme.durationNormal
      easing.type: Theme.easingStandard
    }
    NumberAnimation {
      target: win
      property: "cardOpacity"
      from: 0.0
      to: 1.0
      duration: Theme.durationFast
      easing.type: Theme.easingStandard
    }
  }

  Connections {
    target: win.service
    function onFailedChanged(): void {
      if (win.service && win.service.failed) {
        passwordInput.text = "";
        shakeAnim.restart();
        passwordInput.forceActiveFocus();
      }
    }
    function onIsResponseRequiredChanged(): void {
      if (win.service && win.service.isResponseRequired) {
        passwordInput.text = "";
        passwordInput.forceActiveFocus();
      }
    }
  }

  SequentialAnimation {
    id: shakeAnim
    NumberAnimation { target: win; property: "cardOffset"; to: -6; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: win; property: "cardOffset"; to: 6; duration: 35; easing.type: Easing.InOutQuad }
    NumberAnimation { target: win; property: "cardOffset"; to: -4; duration: 35; easing.type: Easing.InOutQuad }
    NumberAnimation { target: win; property: "cardOffset"; to: 4; duration: 35; easing.type: Easing.InOutQuad }
    NumberAnimation { target: win; property: "cardOffset"; to: 0; duration: 35; easing.type: Easing.InOutQuad }
  }

  Rectangle {
    id: backdrop
    anchors.fill: parent
    color: Qt.rgba(0.0, 0.0, 0.0, 0.5)

    MouseArea {
      anchors.fill: parent
      onClicked: shakeAnim.restart()
    }
  }

  Rectangle {
    id: card
    width: 410
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: (win.service && win.service.failed) ? Theme.err : Theme.cardBorder
    border.width: 1

    x: Math.round((parent.width - width) / 2) + win.cardOffset
    y: Math.round((parent.height - height) / 2)

    scale: win.cardScale
    opacity: win.cardOpacity

    implicitHeight: cardLayout.implicitHeight + (Theme.cardPadding * 2)

    ColumnLayout {
      id: cardLayout
      anchors.fill: parent
      anchors.margins: Theme.cardPadding
      spacing: Theme.spaceMd

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        IconImage {
          id: headerIcon
          Layout.preferredWidth: Theme.iconMd
          Layout.preferredHeight: Theme.iconMd
          source: win.resolveAuthIcon(win.service?.iconName ?? "")
          asynchronous: true
        }

        Text {
          visible: headerIcon.status === Image.Error || !win.resolveAuthIcon(win.service?.iconName ?? "")
          text: "󰌾"
          font.family: Theme.mono
          font.pixelSize: Theme.iconBase
          color: Theme.accent
        }

        Text {
          text: "Authentication Required"
          font.family: Theme.displayFont
          font.pixelSize: Theme.fontLg
          font.weight: Font.DemiBold
          color: Theme.ink1
        }

        Item { Layout.fillWidth: true }

        Rectangle {
          Layout.preferredHeight: 20
          Layout.preferredWidth: userLabel.implicitWidth + 12
          radius: Theme.radiusPill
          color: Theme.inset
          border.color: Theme.lineMuted
          border.width: 1

          Text {
            id: userLabel
            anchors.centerIn: parent
            text: {
              const ident = win.service?.selectedIdentity;
              if (ident && (ident.displayName || ident.string)) {
                return ident.displayName || ident.string;
              }
              if (win.service?.identities && win.service.identities.length > 0) {
                const first = win.service.identities[0];
                return first.displayName || first.string;
              }
              return "root";
            }
            font.family: Theme.mono
            font.pixelSize: Theme.fontXs
            color: Theme.ink2
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: win.service?.message ?? ""
        font.family: Theme.textFont
        font.pixelSize: Theme.fontBase
        color: Theme.ink2
        wrapMode: Text.Wrap
        lineHeight: 1.25
      }

      Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: win.service?.actionId ?? ""
        font.family: Theme.mono
        font.pixelSize: Theme.fontXs
        color: Theme.ink3
        elide: Text.ElideMiddle
      }

      Rectangle {
        id: inputWrap
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.inputHeight
        radius: Theme.radiusBase
        color: Theme.inset
        border.color: passwordInput.activeFocus
          ? ((win.service && win.service.failed) ? Theme.err : Theme.focusRing)
          : ((win.service && win.service.failed) ? Theme.err : Theme.line)
        border.width: passwordInput.activeFocus ? Theme.focusRingWidth : 1

        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 6
          spacing: Theme.spaceSm

          TextInput {
            id: passwordInput
            Layout.fillWidth: true
            Layout.fillHeight: true
            verticalAlignment: TextInput.AlignVCenter

            font.family: Theme.mono
            font.pixelSize: Theme.fontBase
            color: Theme.ink1
            selectionColor: Theme.accent
            selectedTextColor: Theme.darkInk
            selectByMouse: true
            activeFocusOnTab: true
            enabled: win.service?.isResponseRequired ?? false
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData | Qt.ImhHiddenText

            echoMode: win.showPlainPassword
              ? TextInput.Normal
              : ((win.service?.responseVisible ?? false) ? TextInput.Normal : TextInput.Password)

            onAccepted: win.submit()

            Keys.onEscapePressed: event => {
              win.cancel();
              event.accepted = true;
            }
          }

          Text {
            anchors.left: passwordInput.left
            anchors.verticalCenter: parent.verticalCenter
            text: win.service?.prompt || "Password"
            font.family: Theme.textFont
            font.pixelSize: Theme.fontBase
            color: Theme.ink3
            visible: passwordInput.text.length === 0 && !passwordInput.activeFocus
          }

          Rectangle {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            radius: Theme.radiusXs
            color: eyeMa.containsMouse ? Theme.hoverWash : "transparent"

            Text {
              anchors.centerIn: parent
              text: win.showPlainPassword ? "󰈈" : "󰈉"
              font.family: Theme.mono
              font.pixelSize: Theme.iconSm
              color: eyeMa.containsMouse ? Theme.ink1 : Theme.ink3
            }

            MouseArea {
              id: eyeMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: win.showPlainPassword = !win.showPlainPassword
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        visible: (win.service && win.service.failed) || (win.service && win.service.supplementaryMessage.length > 0)
        spacing: Theme.spaceXs

        Text {
          text: (win.service && (win.service.failed || win.service.supplementaryIsError)) ? "󰅚" : "󰋼"
          font.family: Theme.mono
          font.pixelSize: Theme.fontXs
          color: (win.service && (win.service.failed || win.service.supplementaryIsError)) ? Theme.err : Theme.accent
        }

        Text {
          Layout.fillWidth: true
          text: {
            if (!win.service) return "";
            if (win.service.supplementaryMessage.length > 0) return win.service.supplementaryMessage;
            if (win.service.failed) return "Authentication failed. Try again.";
            return "";
          }
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          color: (win.service && (win.service.failed || win.service.supplementaryIsError)) ? Theme.err : Theme.accent
          elide: Text.ElideRight
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spaceXs
        spacing: Theme.spaceSm

        Item { Layout.fillWidth: true }

        TextBtn {
          text: "Cancel"
          fs: Theme.fontSm
          onClicked: win.cancel()
        }

        PrimaryBtn {
          text: "Authenticate"
          enabledBtn: passwordInput.text.length > 0 || !(win.service?.isResponseRequired ?? true)
          onClicked: win.submit()
        }
      }
    }
  }
}
