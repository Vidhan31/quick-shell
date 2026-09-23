// components/TSwitch.qml
import QtQuick
import "../theme"

Item {
  id: root
  signal toggled()
  property bool on: false
  property color onColor: Theme.green
  property bool enabledSwitch: true

  width: 42
  height: 24
  opacity: root.enabledSwitch ? 1.0 : 0.35

  Rectangle {
    anchors.fill: parent
    radius: 12
    color: root.on ? root.onColor : Theme.switchOff
    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }

    Rectangle {
      width: 20
      height: 20
      radius: 10
      y: 2
      x: root.on ? parent.width - width - 2 : 2
      color: Theme.ink1
      Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: root.enabledSwitch
    cursorShape: root.enabledSwitch ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (root.enabledSwitch) root.toggled();
    }
  }
}
