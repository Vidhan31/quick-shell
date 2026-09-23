pragma ComponentBehavior: Bound
// components/VolumeSlider.qml — Smooth interactive slider for volume and audio levels.
import QtQuick
import "../theme"

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

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: (sliderArea.containsMouse || root.isDragging) ? 8 : 6
    radius: height / 2
    color: Theme.inset

    Behavior on height { NumberAnimation { duration: Theme.durationFast } }

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
      visible: sliderArea.containsMouse || root.isDragging
      opacity: visible ? 1.0 : 0.0

      Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
    }
  }

  MouseArea {
    id: sliderArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    preventStealing: true

    onPressed: mouse => {
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
