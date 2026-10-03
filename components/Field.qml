pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal edited(string text)
  property string placeholder: ""
  property string initial: ""
  property bool clearable: false

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

  Component.onCompleted: input.text = root.initial

  TextInput {
    id: input
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: (root.clearable && text.length > 0) ? 26 : 10
    verticalAlignment: TextInput.AlignVCenter
    font.family: Theme.mono
    font.pixelSize: Theme.fontBase
    color: Theme.ink1
    selectByMouse: true
    activeFocusOnTab: true
    onTextEdited: root.edited(text)

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
    visible: root.clearable && input.text.length > 0
    anchors.right: parent.right
    anchors.rightMargin: 5
    anchors.verticalCenter: parent.verticalCenter
    width: 20
    height: 20
    radius: 10
    color: clearMa.containsMouse ? Theme.pressWash : "transparent"

    Text {
      anchors.centerIn: parent
      text: "✕"
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
        input.forceActiveFocus();
      }
    }
  }
}
