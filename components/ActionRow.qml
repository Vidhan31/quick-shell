pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property bool active: false
  property color base: active ? Theme.selected : "transparent"
  property color hover: Theme.hoverWash
  property color press: Theme.pressWash
  property alias rad: root.radius
  property bool actionable: true

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
    onClicked: {
      if (root.actionable) root.clicked();
    }
  }
}
