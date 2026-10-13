pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

Item {
  id: root

  property real value: 0.0
  property real from: 0.0
  property real to: 1.0
  property real stepSize: 0.01
  property bool muted: false
  property color activeColor: Theme.accent
  property color mutedColor: Theme.ink3

  signal moved(real val)

  readonly property var t: Theme
  property bool isDragging: false

  implicitHeight: 24
  implicitWidth: 200
  activeFocusOnTab: true

  Accessible.role: Accessible.Slider
  Accessible.name: Math.round(root.value * 100) + "%"

  function clamp(v: real): real {
    return Math.max(root.from, Math.min(root.to, v));
  }

  function updateFromMouse(mouseX: real): void {
    const range = root.to - root.from;
    if (range <= 0) return;
    const ratio = Math.max(0.0, Math.min(1.0, mouseX / track.width));
    const newVal = root.from + (ratio * range);
    root.moved(clamp(newVal));
  }

  Keys.onLeftPressed: event => {
    root.moved(root.clamp(root.value - 0.02));
    event.accepted = true;
  }
  Keys.onDownPressed: event => {
    root.moved(root.clamp(root.value - 0.02));
    event.accepted = true;
  }
  Keys.onRightPressed: event => {
    root.moved(root.clamp(root.value + 0.02));
    event.accepted = true;
  }
  Keys.onUpPressed: event => {
    root.moved(root.clamp(root.value + 0.02));
    event.accepted = true;
  }
  Keys.onPressed: event => {
    if (event.key === Qt.Key_PageDown) {
      root.moved(root.clamp(root.value - 0.10));
      event.accepted = true;
    } else if (event.key === Qt.Key_PageUp) {
      root.moved(root.clamp(root.value + 0.10));
      event.accepted = true;
    } else if (event.key === Qt.Key_Home) {
      root.moved(root.from);
      event.accepted = true;
    } else if (event.key === Qt.Key_End) {
      root.moved(root.to);
      event.accepted = true;
    }
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: (sliderArea.containsMouse || root.isDragging || root.activeFocus) ? 8 : 6
    radius: height / 2
    color: Theme.inset
    border.color: root.activeFocus ? Theme.focusRing : "transparent"
    border.width: root.activeFocus ? Theme.focusRingWidth : 0

    Behavior on height { NumberAnimation { duration: Theme.durationFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

    Rectangle {
      id: fill
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      radius: parent.radius
      width: {
        const range = root.to - root.from;
        if (range <= 0) return 0;
        const norm = Math.max(0.0, Math.min(1.0, (root.value - root.from) / range));
        return Math.round(track.width * norm);
      }
      color: root.muted ? root.mutedColor : root.activeColor

      Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
    }

    Rectangle {
      id: thumb
      width: 12
      height: 12
      radius: 6
      color: Theme.ink1
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(track.width - width, fill.width - (width / 2)))
      visible: sliderArea.containsMouse || root.isDragging || root.activeFocus
      opacity: visible ? 1.0 : 0.0

      Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }
    }
  }

  MouseArea {
    id: sliderArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    preventStealing: true

    onPressed: mouse => {
      root.forceActiveFocus();
      root.isDragging = true;
      root.updateFromMouse(mouse.x);
    }

    onPositionChanged: mouse => {
      if (root.isDragging) {
        root.updateFromMouse(mouse.x);
      }
    }

    onReleased: {
      root.isDragging = false;
    }

    onCanceled: {
      root.isDragging = false;
    }

    onWheel: wheel => {
      const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
      root.moved(root.clamp(root.value + delta));
    }
  }
}
