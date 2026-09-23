// components/TextBtn.qml
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property string text: ""
  property color fg: Theme.ink2
  property int fs: Theme.fontBase
  property bool bold: false

  implicitWidth: lbl.implicitWidth + 18
  implicitHeight: 26
  radius: 7
  color: ma.pressed ? Theme.pressWash : ma.containsMouse ? Theme.hoverWash : "transparent"
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }

  Text {
    id: lbl
    anchors.centerIn: parent
    text: root.text
    font.pixelSize: root.fs
    font.bold: root.bold
    color: (ma.containsMouse || ma.pressed) ? Theme.ink1 : root.fg
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
