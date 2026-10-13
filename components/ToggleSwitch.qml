pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root
  signal toggled()
  property bool on: false
  property color onColor: Theme.green
  property bool enabledSwitch: true
  property string tooltip: ""
  property string tooltipSub: ""
  property string accessibleName: tooltip.length > 0 ? tooltip : "Toggle"

  implicitWidth: 38
  implicitHeight: 22
  opacity: root.enabledSwitch ? 1.0 : 0.35
  activeFocusOnTab: root.enabledSwitch

  Accessible.role: Accessible.CheckBox
  Accessible.name: root.accessibleName
  Accessible.checked: root.on

  function findHost(): var {
    let p = root.parent;
    while (p) {
      if (typeof p.showTip === "function") return p;
      if (p.barWindow && typeof p.barWindow.showTip === "function") return p.barWindow;
      p = p.parent;
    }
    return null;
  }

  function updateTip(): void {
    const host = root.findHost();
    if ((ma.containsMouse || root.activeFocus) && root.tooltip.length > 0 && root.enabledSwitch) {
      if (host && typeof host.showTip === "function") {
        host.showTip(root, root.tooltip, root.tooltipSub);
      }
    } else {
      if (host && typeof host.hideTip === "function") {
        host.hideTip();
      }
    }
  }

  onActiveFocusChanged: updateTip()
  onTooltipChanged: if (ma.containsMouse || root.activeFocus) updateTip()
  Component.onDestruction: {
    const host = root.findHost();
    if (host && typeof host.hideTip === "function") {
      host.hideTip();
    }
  }

  Keys.onReturnPressed: event => {
    if (root.enabledSwitch) {
      root.toggled();
      event.accepted = true;
    }
  }
  Keys.onSpacePressed: event => {
    if (root.enabledSwitch) {
      root.toggled();
      event.accepted = true;
    }
  }
  Keys.onLeftPressed: event => {
    if (root.enabledSwitch && root.on) {
      root.toggled();
      event.accepted = true;
    }
  }
  Keys.onRightPressed: event => {
    if (root.enabledSwitch && !root.on) {
      root.toggled();
      event.accepted = true;
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: root.on ? root.onColor : (ma.containsMouse ? Theme.hoverFill : Theme.switchOff)
    border.color: root.activeFocus ? Theme.focusRing : (root.on ? Qt.rgba(0, 0, 0, 0.15) : Theme.cardBorder)
    border.width: root.activeFocus ? Theme.focusRingWidth : 1
    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

    Rectangle {
      id: knob
      width: 16
      height: 16
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      x: root.on ? parent.width - width - 3 : 3
      color: root.on ? "#ffffff" : Theme.ink2
      scale: ma.pressed && root.enabledSwitch ? 0.92 : 1.0

      Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
      Behavior on scale { NumberAnimation { duration: Theme.durationFast } }
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: root.enabledSwitch
    cursorShape: root.enabledSwitch ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: root.updateTip()
    onClicked: {
      if (root.enabledSwitch) {
        const host = root.findHost();
        if (host && typeof host.hideTip === "function") {
          host.hideTip();
        }
        root.toggled();
      }
    }
  }
}
