pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root
  property string label: ""
  property string valueText: ""
  property string actionText: ""
  property string actionGlyph: ""
  property color actionColor: Theme.ink2
  property string actionTooltip: ""
  signal actionClicked()

  implicitHeight: 24

  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label.toUpperCase()
    font.family: Theme.textFont
    font.pixelSize: Theme.fontXs
    font.letterSpacing: 1.1
    font.weight: Font.SemiBold
    color: Theme.ink3
  }

  Text {
    anchors.right: (actionIcon.visible || actionTxt.visible) ? (actionIcon.visible ? actionIcon.left : actionTxt.left) : parent.right
    anchors.rightMargin: (actionIcon.visible || actionTxt.visible) ? 6 : 0
    anchors.verticalCenter: parent.verticalCenter
    visible: root.valueText.length > 0
    text: root.valueText
    font.family: Theme.mono
    font.pixelSize: Theme.fontSm
    font.weight: Font.SemiBold
    color: Theme.ink3
  }

  IconButton {
    id: actionIcon
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.actionGlyph.length > 0
    glyph: root.actionGlyph
    fg: root.actionColor
    tooltip: root.actionTooltip
    btnSize: 24
    fs: Theme.iconSm
    onClicked: root.actionClicked()
  }

  TextButton {
    id: actionTxt
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.actionGlyph.length === 0 && root.actionText.length > 0
    text: root.actionText
    fg: root.actionColor
    fs: Theme.fontSm
    onClicked: root.actionClicked()
  }
}
