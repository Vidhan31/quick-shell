pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  property bool bordered: false
  property alias rad: root.radius

  radius: Theme.radiusSection
  color: Theme.surface
  border.color: Theme.lineMuted
  border.width: root.bordered ? 1 : 0
}
