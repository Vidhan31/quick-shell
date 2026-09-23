// components/Toast.qml
import QtQuick
import "../theme"

Rectangle {
  id: root
  property string message: ""
  property int timeout: 1800

  anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
  anchors.bottom: parent ? parent.bottom : undefined
  anchors.bottomMargin: 14
  width: Math.min(toastLabel.implicitWidth + 30, parent ? (parent.width - 32) : 200)
  height: 30
  radius: 15
  color: Theme.surfaceElevated
  opacity: message.length > 0 ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: 160 } }

  Timer {
    id: timer
    interval: root.timeout
    onTriggered: root.message = ""
  }

  function show(msg: string): void {
    root.message = msg;
    timer.restart();
  }

  Text {
    id: toastLabel
    anchors.centerIn: parent
    text: root.message
    font.pixelSize: Theme.fontSm
    font.weight: Font.Medium
    color: Theme.ink1
  }
}
