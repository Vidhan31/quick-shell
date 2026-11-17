pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()

  property string text: ""
  property bool selected: false
  property string tooltip: ""
  property string tooltipSub: ""
  property string accessibleName: ""

  implicitHeight: 20
  implicitWidth: pillText.implicitWidth + 14
  radius: Theme.radiusChip
  activeFocusOnTab: true

  color: root.selected ? Theme.selected : (ma.containsMouse || root.activeFocus ? Theme.hoverFill : "transparent")
  border.width: root.activeFocus ? Theme.focusRingWidth : 0
  border.color: Theme.focusRing

  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

  Accessible.role: Accessible.Button
  Accessible.name: root.accessibleName.length > 0 ? root.accessibleName : (root.tooltip.length > 0 ? root.tooltip : root.text)
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
    if ((ma.containsMouse || root.activeFocus) && root.tooltip.length > 0) {
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
    root.clicked();
    event.accepted = true;
  }
  Keys.onSpacePressed: event => {
    root.clicked();
    event.accepted = true;
  }

  Text {
    id: pillText
    anchors.centerIn: parent
    text: root.text
    font.family: Theme.mono
    font.pixelSize: Theme.fontSm
    font.weight: root.selected ? Font.DemiBold : Font.Normal
    color: root.selected ? Theme.ink1 : Theme.ink2
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.updateTip()
    onClicked: {
      const host = root.findHost();
      if (host && typeof host.hideTip === "function") {
        host.hideTip();
      }
      root.clicked();
    }
  }
}
