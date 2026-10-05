pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property bool segment: false
  property bool active: false
  property bool hoverable: true
  property real horizontalPadding: 8
  property real radius: root.segment ? (Theme.radiusSm - 2) : Theme.radiusSm
  property var acceptedButtons: Qt.LeftButton

  signal clicked(var mouse)
  signal rightClicked()

  property string tooltip: ""
  property string tooltipSub: ""

  default property alias content: innerContainer.data
  property alias contentItem: innerContainer

  implicitHeight: Theme.btnHeightSm
  implicitWidth: innerContainer.implicitWidth + (horizontalPadding * 2)
  activeFocusOnTab: true

  Accessible.role: Accessible.Button
  Accessible.name: root.tooltip.length > 0 ? root.tooltip : (root.segment ? "Bar segment" : "Bar item")
  Accessible.description: root.tooltipSub

  property var barWindow: null

  function findHost(): var {
    if (root.barWindow) return root.barWindow;
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
    root.clicked(null);
    event.accepted = true;
  }
  Keys.onSpacePressed: event => {
    root.clicked(null);
    event.accepted = true;
  }

  Rectangle {
    id: bgRect
    anchors.fill: parent
    anchors.margins: root.segment ? 1 : 0
    radius: root.radius
    color: root.active ? Theme.selected : (ma.containsMouse || root.activeFocus) ? Theme.hoverFill : Theme.surface
    border.color: root.activeFocus ? Theme.focusRing : "transparent"
    border.width: root.activeFocus ? Theme.focusRingWidth : 0

    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
  }

  Item {
    id: innerContainer
    anchors.centerIn: parent
    implicitWidth: children.length === 1 ? children[0].implicitWidth : (children.length > 1 ? childrenRect.width : 0)
    implicitHeight: children.length === 1 ? children[0].implicitHeight : (children.length > 1 ? childrenRect.height : 0)
    width: implicitWidth
    height: implicitHeight
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: root.hoverable
    acceptedButtons: root.acceptedButtons
    onContainsMouseChanged: root.updateTip()
    onClicked: mouse => {
      const host = root.findHost();
      if (host && typeof host.hideTip === "function") {
        host.hideTip();
      }
      if (mouse.button === Qt.RightButton) {
        root.rightClicked();
      } else {
        root.clicked(mouse);
      }
    }
  }
}
