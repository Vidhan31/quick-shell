// widgets/BarCapsule.qml — Shared capsule container for grouped bar widgets.
import QtQuick
import "../theme"

Item {
  id: root

  default property alias content: contentRow.data
  property alias spacing: contentRow.spacing
  property real padding: 2
  property real radius: Theme.radiusSm

  implicitHeight: Theme.btnHeightSm
  implicitWidth: contentRow.implicitWidth + (padding * 2)

  Rectangle {
    id: bgRect
    anchors.fill: parent
    radius: root.radius
    color: Theme.surface
    border.color: Theme.cardBorder
    border.width: 1
  }

  Row {
    id: contentRow
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: root.padding
    spacing: 0
  }
}
