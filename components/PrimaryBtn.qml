// components/PrimaryBtn.qml
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property string text: ""
  property string glyph: ""
  property color fill: Theme.accent
  property color ink: Theme.darkInk
  property bool enabledBtn: true

  implicitHeight: 34
  radius: 9
  scale: (ma.pressed && root.enabledBtn) ? 0.985 : 1.0
  Behavior on scale { NumberAnimation { duration: 80 } }
  color: !root.enabledBtn ? Theme.btnDisabled : ma.pressed ? Qt.darker(fill, 1.2) : ma.containsMouse ? Qt.lighter(fill, 1.07) : fill
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }

  Row {
    anchors.centerIn: parent
    spacing: 7

    Text {
      visible: root.glyph.length > 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      font.family: Theme.mono
      font.pixelSize: Theme.fontBase
      color: root.enabledBtn ? root.ink : Theme.ink3
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      font.pixelSize: Theme.fontMd
      font.weight: Font.DemiBold
      color: root.enabledBtn ? root.ink : Theme.ink3
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: root.enabledBtn
    cursorShape: root.enabledBtn ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (root.enabledBtn) root.clicked();
    }
  }
}
