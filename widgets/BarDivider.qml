// widgets/BarDivider.qml — Subtle vertical hairline divider between capsule segments.
import QtQuick
import "../theme"

Rectangle {
  id: root

  implicitWidth: 1
  implicitHeight: 12
  width: implicitWidth
  height: implicitHeight
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  color: Theme.line
}
