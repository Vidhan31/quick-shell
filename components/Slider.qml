pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property real value: 0.0
  property real from: 0.0
  property real to: 1.0
  property real stepSize: 0.02
  property bool enabledSlider: true
  property bool muted: false
  property color activeColor: Theme.accent
  property color mutedColor: Theme.ink3
  property string accessibleName: ""
  property bool isDragging: false
  property bool liveUpdate: true

  signal moved(real val)
  signal committed(real val)
  signal draggingChanged(bool dragging)

  implicitHeight: 22
  implicitWidth: 200
  activeFocusOnTab: root.enabledSlider

  Accessible.role: Accessible.Slider
  Accessible.name: root.accessibleName.length > 0 ? root.accessibleName : (Math.round(root.value * 100) + "%")

  function clamp(v: real): real {
    return Math.max(root.from, Math.min(root.to, v));
  }

  property real _lastVal: root.value

  function updateFromMouse(mouseX: real): void {
    if (!root.enabledSlider) return;
    const range = root.to - root.from;
    if (range <= 0) return;
    const ratio = Math.max(0.0, Math.min(1.0, mouseX / track.width));
    const newVal = clamp(root.from + (ratio * range));
    _lastVal = newVal;
    root.moved(newVal);
  }

  Keys.onLeftPressed: event => {
    if (root.enabledSlider) {
      const v = root.clamp(root.value - root.stepSize);
      root.moved(v);
      root.committed(v);
      event.accepted = true;
    }
  }
  Keys.onDownPressed: event => {
    if (root.enabledSlider) {
      const v = root.clamp(root.value - root.stepSize);
      root.moved(v);
      root.committed(v);
      event.accepted = true;
    }
  }
  Keys.onRightPressed: event => {
    if (root.enabledSlider) {
      const v = root.clamp(root.value + root.stepSize);
      root.moved(v);
      root.committed(v);
      event.accepted = true;
    }
  }
  Keys.onUpPressed: event => {
    if (root.enabledSlider) {
      const v = root.clamp(root.value + root.stepSize);
      root.moved(v);
      root.committed(v);
      event.accepted = true;
    }
  }
  Keys.onPressed: event => {
    if (!root.enabledSlider) return;
    const pageStep = (root.to - root.from) * 0.10;
    let v = root.value;
    if (event.key === Qt.Key_PageDown) {
      v = root.clamp(root.value - pageStep);
    } else if (event.key === Qt.Key_PageUp) {
      v = root.clamp(root.value + pageStep);
    } else if (event.key === Qt.Key_Home) {
      v = root.from;
    } else if (event.key === Qt.Key_End) {
      v = root.to;
    } else {
      return;
    }
    root.moved(v);
    root.committed(v);
    event.accepted = true;
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: 4
    radius: 0
    color: Theme.inset
    border.color: root.activeFocus ? Theme.focusRing : Theme.tint(Theme.cardBorder, 0.5)
    border.width: root.activeFocus ? Theme.focusRingWidth : 1

    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

    Rectangle {
      id: fill
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      radius: 0
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
      radius: 0
      color: root.muted ? root.mutedColor : (sliderArea.containsMouse || root.isDragging ? Theme.ink1 : Theme.sliderThumb)
      border.color: Qt.rgba(0, 0, 0, 0.3)
      border.width: 1
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(track.width - width, fill.width - (width / 2)))
      visible: true
      scale: (sliderArea.containsMouse || root.isDragging) ? 1.15 : 1.0

      Behavior on scale { NumberAnimation { duration: Theme.durationFast } }
      Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }
  }

  MouseArea {
    id: sliderArea
    anchors.fill: parent
    hoverEnabled: root.enabledSlider
    cursorShape: root.enabledSlider ? Qt.PointingHandCursor : Qt.ArrowCursor
    preventStealing: true

    onPressed: mouse => {
      if (!root.enabledSlider) return;
      root.forceActiveFocus();
      root.isDragging = true;
      root.draggingChanged(true);
      root.updateFromMouse(mouse.x);
    }

    onPositionChanged: mouse => {
      if (root.isDragging) {
        root.updateFromMouse(mouse.x);
      }
    }

    onReleased: {
      if (root.isDragging) {
        root.isDragging = false;
        root.draggingChanged(false);
        root.committed(root._lastVal);
      }
    }

    onCanceled: {
      if (root.isDragging) {
        root.isDragging = false;
        root.draggingChanged(false);
      }
    }

    onWheel: wheel => {
      if (!root.enabledSlider) return;
      const range = root.to - root.from;
      const delta = (wheel.angleDelta.y > 0 ? 0.05 : -0.05) * range;
      const v = root.clamp(root.value + delta);
      root._lastVal = v;
      root.moved(v);
      root.committed(v);
    }
  }
}
