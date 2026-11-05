pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  property int padding: Theme.cardPadding

  default property alias content: inner.data

  radius: Theme.radiusCard
  color: Theme.popupGlass
  border.color: Theme.popupBorder
  border.width: 1

  Item {
    id: inner
    anchors.fill: parent
    anchors.margins: root.padding
  }
}
