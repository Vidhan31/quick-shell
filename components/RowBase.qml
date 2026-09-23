// components/RowBase.qml
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property color base: "transparent"
  property color hover: Theme.hoverWash
  property color press: Theme.pressWash
  property alias rad: root.radius
  property bool actionable: true

  color: (!root.actionable || (!ma.containsMouse && !ma.pressed)) ? base : (ma.pressed ? press : hover)
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }

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
