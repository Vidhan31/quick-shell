pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  property int padding: Theme.cardPadding

  default property alias content: inner.data

  radius: Theme.radiusCard
  color: Theme.bg
  border.color: Theme.cardBorder
  border.width: 1

  Item {
    id: inner
    anchors.fill: parent
    anchors.margins: root.padding
  }
}
