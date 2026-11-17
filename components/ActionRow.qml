pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property bool active: false
  property color base: active ? Theme.selected : "transparent"
  property color hover: Theme.hoverFill
  property color press: Theme.pressWash
  property alias rad: root.radius
  property bool actionable: true
  property string tooltip: ""
  property string tooltipSub: ""
  readonly property bool containsMouse: ma.containsMouse
  readonly property bool pressed: ma.pressed

  activeFocusOnTab: root.actionable
  radius: Theme.radiusSm
  color: (!root.actionable || (!ma.containsMouse && !ma.pressed && !root.activeFocus))
    ? (root.active ? Theme.selected : root.base)
    : (ma.pressed ? press : (root.active ? Theme.selected : hover))
  border.color: root.activeFocus ? Theme.focusRing : (root.active ? Theme.cardBorder : "transparent")
  border.width: root.activeFocus ? Theme.focusRingWidth : (root.active ? 1 : 0)
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

  Accessible.role: root.actionable ? Accessible.ListItem : Accessible.NoRole
  Accessible.name: root.tooltip.length > 0 ? root.tooltip : ""
  Accessible.description: root.tooltipSub

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
    if ((ma.containsMouse || root.activeFocus) && root.tooltip.length > 0 && root.actionable) {
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
    if (root.actionable) {
      root.clicked();
      event.accepted = true;
    }
  }
  Keys.onSpacePressed: event => {
    if (root.actionable) {
      root.clicked();
      event.accepted = true;
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: root.actionable
    cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: root.updateTip()
    onClicked: {
      const host = root.findHost();
      if (host && typeof host.hideTip === "function") {
        host.hideTip();
      }
      if (root.actionable) root.clicked();
    }
  }
}
