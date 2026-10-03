pragma ComponentBehavior: Bound
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
  scale: message.length > 0 ? 1 : 0.92
  transformOrigin: Item.Bottom
  visible: opacity > 0
  // Render-thread animators: no GUI-thread NumberAnimation, no layout pass.
  Behavior on opacity { OpacityAnimator { duration: 160; easing.type: Easing.OutCubic } }
  Behavior on scale { ScaleAnimator { duration: 160; easing.type: Easing.OutCubic } }

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
    width: parent ? parent.width - 30 : implicitWidth
    text: root.message.length > 0 ? ("✓  " + root.message) : ""
    font.family: Theme.roundedFont
    font.pixelSize: Theme.fontSm
    font.weight: Font.Medium
    color: Theme.ink1
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
  }
}
