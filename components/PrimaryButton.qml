pragma ComponentBehavior: Bound
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
  implicitWidth: contentRow.implicitWidth + 24
  radius: 9
  activeFocusOnTab: root.enabledBtn

  scale: (ma.pressed && root.enabledBtn) ? 0.985 : 1.0
  Behavior on scale { NumberAnimation { duration: 80 } }
  color: !root.enabledBtn ? Theme.btnDisabled : ma.pressed ? Qt.darker(fill, 1.2) : (ma.containsMouse || root.activeFocus) ? Qt.lighter(fill, 1.07) : fill
  border.color: root.activeFocus ? Theme.ink1 : "transparent"
  border.width: root.activeFocus ? Theme.focusRingWidth : 0
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

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

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: 7

    Text {
      visible: root.glyph.length > 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      font.family: Theme.mono
      font.pixelSize: Theme.iconBase
      color: root.enabledBtn ? root.ink : Theme.ink3
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      font.family: Theme.textFont
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
