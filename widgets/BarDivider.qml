pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  implicitWidth: 1
  implicitHeight: 14
  width: implicitWidth
  height: implicitHeight
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  color: Theme.line
}
