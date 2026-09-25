// components/Segments.qml
import QtQuick
import "../theme"

Item {
  id: root
  property var items: []
  property int current: 0
  signal selected(int index)

  implicitHeight: 34

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusChip
    color: Theme.inset
  }

  Row {
    anchors.fill: parent
    anchors.margins: 3
    spacing: 2

    Repeater {
      model: root.items

      Item {
        id: segItem
        required property var modelData
        required property int index

        width: (parent.width - 2 * (root.items.length - 1)) / (root.items.length > 0 ? root.items.length : 1)
        height: parent.height

        Rectangle {
          anchors.fill: parent
          radius: 7
          color: root.current === segItem.index ? Theme.selected : (segMa.containsMouse || segMa.pressed ? Theme.hoverFill : "transparent")
          Behavior on color { ColorAnimation { duration: 110 } }
        }

        Row {
          anchors.centerIn: parent
          spacing: 6

          Image {
            visible: Boolean(segItem.modelData && segItem.modelData.iconSource)
            anchors.verticalCenter: parent.verticalCenter
            source: (segItem.modelData && segItem.modelData.iconSource) ? segItem.modelData.iconSource : ""
            width: 12
            height: 14
            sourceSize.width: 24
            sourceSize.height: 28
            fillMode: Image.PreserveAspectFit
            opacity: root.current === segItem.index ? 1.0 : 0.6
          }

          Text {
            visible: Boolean(segItem.modelData && segItem.modelData.icon && segItem.modelData.icon.length > 0 && !segItem.modelData.iconSource)
            anchors.verticalCenter: parent.verticalCenter
            text: (segItem.modelData && segItem.modelData.icon) ? segItem.modelData.icon : ""
            font.family: Theme.mono
            font.pixelSize: Theme.fontBase
            color: root.current === segItem.index ? Theme.ink1 : Theme.ink3
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (segItem.modelData && segItem.modelData.label) ? segItem.modelData.label : ""
            font.pixelSize: Theme.fontBase
            font.weight: root.current === segItem.index ? Font.DemiBold : Font.Normal
            color: root.current === segItem.index ? Theme.ink1 : Theme.ink2
          }

          Text {
            visible: Boolean(segItem.modelData && segItem.modelData.count && segItem.modelData.count > 0)
            anchors.verticalCenter: parent.verticalCenter
            text: (segItem.modelData && segItem.modelData.count) ? segItem.modelData.count : ""
            font.pixelSize: Theme.fontSm
            color: (segItem.modelData && segItem.modelData.alert && root.current !== segItem.index) ? Theme.amber : Theme.ink3
          }

          Rectangle {
            visible: Boolean(segItem.modelData && segItem.modelData.playing)
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 2.5
            color: Theme.green
          }
        }

        MouseArea {
          id: segMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selected(segItem.index)
        }
      }
    }
  }
}
