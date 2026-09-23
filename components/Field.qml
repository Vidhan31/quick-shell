// components/Field.qml
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal edited(string text)
  property string placeholder: ""
  property string initial: ""
  property bool clearable: false

  implicitHeight: Theme.inputHeight
  radius: Theme.radiusBase
  color: Theme.inset
  border.color: Theme.accentHover
  border.width: input.activeFocus ? 1 : 0

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
    onTextEdited: root.edited(text)
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

  Rectangle {
    visible: root.clearable && input.text.length > 0
    anchors.right: parent.right
    anchors.rightMargin: 5
    anchors.verticalCenter: parent.verticalCenter
    width: 18
    height: 18
    radius: 9
    color: clearMa.containsMouse ? Theme.pressWash : "transparent"

    Text {
      anchors.centerIn: parent
      text: "✕"
      font.pixelSize: 9
      color: Theme.ink3
    }

    MouseArea {
      id: clearMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        input.text = "";
        root.edited("");
      }
    }
  }
}
