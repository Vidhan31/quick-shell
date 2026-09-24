// components/IconBtn.qml
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property string glyph: ""
  property int fs: 14
  property color fg: Theme.ink2
  property bool spinning: false
  property bool dimmed: false
  property int btnSize: 30

  implicitWidth: btnSize
  implicitHeight: btnSize
  radius: Theme.radiusBase
  color: ma.pressed ? Theme.pressWash : ma.containsMouse ? Theme.hoverWash : "transparent"
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }

  Text {
    id: ibGlyph
    anchors.centerIn: parent
    text: root.glyph
    font.family: Theme.mono
    font.pixelSize: root.fs
    color: root.dimmed ? Theme.ink3 : ((ma.containsMouse || ma.pressed) ? Theme.ink1 : root.fg)
    opacity: root.dimmed ? 0.35 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    NumberAnimation on rotation {
      running: root.spinning
      from: 0
      to: 360
      loops: Animation.Infinite
      duration: 800
    }
  }

  onSpinningChanged: {
    if (!spinning) ibGlyph.rotation = 0;
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: !root.dimmed
    cursorShape: root.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: {
      if (!root.dimmed) root.clicked();
    }
  }
}
