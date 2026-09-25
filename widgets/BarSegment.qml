// widgets/BarSegment.qml — Interactive sub-segment inside a BarCapsule.
import QtQuick
import "../theme"

Item {
  id: root

  property bool active: false
  property bool hoverable: true
  property real horizontalPadding: 8
  property var acceptedButtons: Qt.LeftButton
  signal clicked(var mouse)
  signal rightClicked()

  default property alias content: innerContainer.data
  property alias contentItem: innerContainer

  implicitHeight: Theme.btnHeightSm
  implicitWidth: innerContainer.implicitWidth + (horizontalPadding * 2)

  Rectangle {
    id: segHighlight
    anchors.fill: parent
    anchors.margins: 1
    radius: Theme.radiusSm - 2
    color: root.active ? Theme.selected : (ma.containsMouse ? Theme.hoverFill : "transparent")
    border.color: root.active ? Theme.accent : (ma.containsMouse ? Theme.line : "transparent")
    border.width: 1

    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
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
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        root.rightClicked();
      } else {
        root.clicked(mouse);
      }
    }
  }
}
