pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal edited(string text)
  signal accepted()

  property string placeholder: ""
  property string initial: ""
  property bool clearable: false
  property bool passwordToggle: false
  property bool showPassword: false
  property bool enabledInput: true
  property alias text: input.text
  property alias inputItem: input
  property int echoMode: root.passwordToggle ? (root.showPassword ? TextInput.Normal : TextInput.Password) : TextInput.Normal
  property int inputMethodHints: Qt.ImhNone

  implicitHeight: Theme.inputHeight
  implicitWidth: 200
  radius: Theme.radiusBase
  color: Theme.inset
  border.color: input.activeFocus ? Theme.focusRing : Theme.line
  border.width: input.activeFocus ? Theme.focusRingWidth : 1
  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

  function setText(v: string): void {
    if (input.text !== v) input.text = v;
  }

  function forceFocus(): void {
    input.forceActiveFocus();
  }

  function forceActiveFocus(): void {
    input.forceActiveFocus();
  }

  Component.onCompleted: {
    if (root.initial.length > 0 && input.text.length === 0) {
      input.text = root.initial;
    }
  }

  TextInput {
    id: input
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: (root.clearable && text.length > 0) || root.passwordToggle ? 32 : 10
    verticalAlignment: TextInput.AlignVCenter
    font.family: Theme.mono
    font.pixelSize: Theme.fontBase
    color: Theme.ink1
    selectionColor: Theme.accent
    selectedTextColor: Theme.darkInk
    selectByMouse: true
    activeFocusOnTab: true
    enabled: root.enabledInput
    echoMode: root.echoMode
    inputMethodHints: root.inputMethodHints
    onTextEdited: root.edited(text)
    onAccepted: root.accepted()

    Accessible.role: Accessible.EditableText
    Accessible.name: root.placeholder

    Keys.onEscapePressed: event => {
      if (text.length > 0) {
        text = "";
        root.edited("");
        event.accepted = true;
      }
    }
  }

  Text {
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    verticalAlignment: Text.AlignVCenter
    visible: input.text.length === 0 && !input.activeFocus
    text: root.placeholder
    font.family: Theme.textFont
    font.pixelSize: Theme.fontBase
    color: Theme.ink3
    elide: Text.ElideRight
  }

  function findHost(): var {
    let p = root.parent;
    while (p) {
      if (typeof p.showTip === "function") return p;
      if (p.barWindow && typeof p.barWindow.showTip === "function") return p.barWindow;
      p = p.parent;
    }
    return null;
  }

  Component.onDestruction: {
    const host = root.findHost();
    if (host && typeof host.hideTip === "function") {
      host.hideTip();
    }
  }

  Rectangle {
    id: clearBtn
    visible: root.clearable && input.text.length > 0 && !root.passwordToggle
    anchors.right: parent.right
    anchors.rightMargin: 5
    anchors.verticalCenter: parent.verticalCenter
    width: 20
    height: 20
    radius: 0
    color: clearMa.containsMouse ? Theme.pressWash : "transparent"

    Text {
      anchors.centerIn: parent
      text: "✕"
      font.family: Theme.textFont
      font.pixelSize: 10
      color: Theme.ink3
    }

    MouseArea {
      id: clearMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: {
        const host = root.findHost();
        if (containsMouse) {
          if (host && typeof host.showTip === "function") {
            host.showTip(clearBtn, "Clear text", "");
          }
        } else {
          if (host && typeof host.hideTip === "function") {
            host.hideTip();
          }
        }
      }
      onClicked: {
        const host = root.findHost();
        if (host && typeof host.hideTip === "function") {
          host.hideTip();
        }
        input.text = "";
        root.edited("");
      }
    }
  }

  Rectangle {
    id: eyeBtn
    visible: root.passwordToggle
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    width: 22
    height: 22
    radius: Theme.radiusXs
    color: eyeMa.containsMouse ? Theme.hoverWash : "transparent"

    Text {
      anchors.centerIn: parent
      text: root.showPassword ? "󰈈" : "󰈉"
      font.family: Theme.mono
      font.pixelSize: Theme.iconSm
      color: eyeMa.containsMouse ? Theme.ink1 : Theme.ink3
    }

    MouseArea {
      id: eyeMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.showPassword = !root.showPassword
    }
  }
}
