pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root
  property string label: ""
  property string actionText: ""
  property string actionGlyph: ""
  property color actionColor: Theme.ink2
  property string actionTooltip: ""
  signal actionClicked()

  implicitHeight: 22

  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    font.family: Theme.textFont
    font.pixelSize: Theme.fontSm
    font.weight: Font.DemiBold
    color: Theme.ink2
  }

  IconBtn {
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

  TextBtn {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.actionGlyph.length === 0 && root.actionText.length > 0
    text: root.actionText
    fg: root.actionColor
    fs: Theme.fontSm
    onClicked: root.actionClicked()
  }
}
