// components/SectionHead.qml
import QtQuick
import "../theme"

Item {
  id: root
  property string label: ""
  property string actionText: ""
  property color actionColor: Theme.ink2
  signal actionClicked()

  implicitHeight: 20

  Text {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    font.pixelSize: Theme.fontSm
    font.bold: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.8
    color: Theme.ink3
  }

  TextBtn {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: root.actionText.length > 0
    text: root.actionText
    fg: root.actionColor
    fs: Theme.fontSm
    onClicked: root.actionClicked()
  }
}
