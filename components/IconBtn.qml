pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property string glyph: ""
  property int fs: Theme.iconBase
  property color fg: Theme.ink2
  property bool spinning: false
  property bool dimmed: false
  property int btnSize: 30
  property string tooltip: ""
  property string tooltipSub: ""

  implicitWidth: btnSize
  implicitHeight: btnSize
  radius: Theme.radiusBase
  activeFocusOnTab: !root.dimmed

  color: ma.pressed ? Theme.pressWash : (ma.containsMouse || root.activeFocus) ? Theme.hoverWash : "transparent"
  border.color: root.activeFocus ? Theme.focusRing : "transparent"
  border.width: root.activeFocus ? Theme.focusRingWidth : 0
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

  Accessible.role: Accessible.Button
  Accessible.name: root.tooltip.length > 0 ? root.tooltip : root.glyph
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
    if ((ma.containsMouse || root.activeFocus) && root.tooltip.length > 0 && !root.dimmed) {
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
    if (!root.dimmed) {
      root.clicked();
      event.accepted = true;
    }
  }
  Keys.onSpacePressed: event => {
    if (!root.dimmed) {
      root.clicked();
      event.accepted = true;
    }
  }

  Text {
    id: ibGlyph
    anchors.centerIn: parent
    text: root.glyph
    font.family: Theme.mono
    font.pixelSize: root.fs
    color: root.dimmed ? Theme.ink3 : ((ma.containsMouse || ma.pressed || root.activeFocus) ? Theme.ink1 : root.fg)
    opacity: root.dimmed ? 0.35 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    NumberAnimation on rotation {
      running: root.spinning
      from: 0
      to: 360
      loops: Animation.Infinite
      duration: 800
    }
  }

  onSpinningChanged: {
    if (!spinning) ibGlyph.rotation = 0;
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: !root.dimmed
    cursorShape: root.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
    onContainsMouseChanged: root.updateTip()
    onClicked: {
      if (!root.dimmed) {
        const host = root.findHost();
        if (host && typeof host.hideTip === "function") {
          host.hideTip();
        }
        root.clicked();
      }
    }
  }
}
