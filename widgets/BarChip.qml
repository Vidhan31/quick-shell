// widgets/BarChip.qml — Consistent container chip for top bar widgets.
import QtQuick
import "../theme"

Item {
  id: root

  property bool active: false
  property bool hoverable: true
  property var acceptedButtons: Qt.LeftButton
  signal clicked(var mouse)
  signal rightClicked()

  default property alias content: innerContainer.data
  property alias contentItem: innerContainer
  property real horizontalPadding: 8
  property real radius: Theme.radiusSm

  implicitHeight: Theme.btnHeightSm
  implicitWidth: innerContainer.implicitWidth + (horizontalPadding * 2)

  Rectangle {
    id: bgRect
    anchors.fill: parent
    radius: root.radius
    color: root.active ? Theme.selected : (ma.containsMouse ? Theme.hoverFill : Theme.surface)
    border.color: root.active ? Theme.accent : (ma.containsMouse ? Theme.line : "transparent")
    border.width: 1

    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
    Behavior on border.color { ColorAnimation { duration: Theme.durationNormal } }
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
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        root.rightClicked();
      } else {
        root.clicked(mouse);
      }
    }
  }
}
