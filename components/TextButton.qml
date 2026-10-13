pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property string text: ""
  property color fg: Theme.ink2
  property int fs: Theme.fontBase
  property bool bold: false
  property bool enabledBtn: true

  implicitWidth: lbl.implicitWidth + 18
  implicitHeight: 26
  radius: 7
  activeFocusOnTab: root.enabledBtn

  color: !root.enabledBtn ? "transparent" : (ma.pressed ? Theme.pressWash : (ma.containsMouse || root.activeFocus) ? Theme.hoverWash : "transparent")
  border.color: root.activeFocus ? Theme.focusRing : "transparent"
  border.width: root.activeFocus ? Theme.focusRingWidth : 0
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
  opacity: root.enabledBtn ? 1.0 : 0.35

  Accessible.role: Accessible.Button
  Accessible.name: root.text

  Keys.onReturnPressed: event => {
    if (root.enabledBtn) {
      root.clicked();
      event.accepted = true;
    }
  }
  Keys.onSpacePressed: event => {
    if (root.enabledBtn) {
      root.clicked();
      event.accepted = true;
    }
  }

  Text {
    id: lbl
    anchors.centerIn: parent
    text: root.text
    font.family: Theme.textFont
    font.pixelSize: root.fs
    font.bold: root.bold
    color: !root.enabledBtn ? Theme.ink3 : ((ma.containsMouse || ma.pressed || root.activeFocus) ? Theme.ink1 : root.fg)
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: root.enabledBtn
    cursorShape: root.enabledBtn ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (root.enabledBtn)
        root.clicked();
    }
  }
}
