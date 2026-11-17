pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root
  property var items: []
  property int current: 0
  signal selected(int index)

  implicitHeight: 34
  activeFocusOnTab: true

  Accessible.role: Accessible.PageTabList

  Keys.onLeftPressed: event => {
    if (root.current > 0) {
      root.selected(root.current - 1);
      event.accepted = true;
    }
  }
  Keys.onRightPressed: event => {
    if (root.current < root.items.length - 1) {
      root.selected(root.current + 1);
      event.accepted = true;
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusSm
    color: Theme.inset
    border.color: root.activeFocus ? Theme.focusRing : Theme.cardBorder
    border.width: root.activeFocus ? Theme.focusRingWidth : 1
    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
  }

  Row {
    anchors.fill: parent
    anchors.margins: 2
    spacing: 1

    Repeater {
      model: root.items

      Item {
        id: segItem
        required property var modelData
        required property int index

        width: (parent.width - (root.items.length - 1)) / (root.items.length > 0 ? root.items.length : 1)
        height: parent.height

        Rectangle {
          anchors.fill: parent
          radius: 0
          color: root.current === segItem.index ? Theme.selected : (segMa.containsMouse || segMa.pressed ? Theme.hoverFill : "transparent")
          border.color: root.current === segItem.index ? Qt.rgba(1.0, 1.0, 1.0, 0.15) : "transparent"
          border.width: root.current === segItem.index ? 1 : 0
          Behavior on color { ColorAnimation { duration: 110 } }
        }

        Rectangle {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: 4
          anchors.bottomMargin: 4
          width: 1
          color: Theme.cardBorder
          visible: segItem.index < root.items.length - 1 && root.current !== segItem.index && root.current !== segItem.index + 1
        }

        Row {
          anchors.centerIn: parent
          spacing: 6

          Image {
            visible: Boolean(segItem.modelData && segItem.modelData.iconSource)
            anchors.verticalCenter: parent.verticalCenter
            source: (segItem.modelData && segItem.modelData.iconSource) ? segItem.modelData.iconSource : ""
            width: 14
            height: 14
            sourceSize.width: 28
            sourceSize.height: 28
            fillMode: Image.PreserveAspectFit
            opacity: root.current === segItem.index ? 1.0 : 0.6
          }

          Text {
            visible: Boolean(segItem.modelData && segItem.modelData.icon && segItem.modelData.icon.length > 0 && !segItem.modelData.iconSource)
            anchors.verticalCenter: parent.verticalCenter
            text: (segItem.modelData && segItem.modelData.icon) ? segItem.modelData.icon : ""
            font.family: Theme.mono
            font.pixelSize: Theme.iconBase
            color: root.current === segItem.index ? Theme.ink1 : Theme.ink3
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (segItem.modelData && segItem.modelData.label) ? segItem.modelData.label : ""
            font.family: Theme.mono
            font.pixelSize: Theme.fontSm
            font.weight: root.current === segItem.index ? Font.Medium : Font.Normal
            color: root.current === segItem.index ? Theme.ink1 : Theme.ink2
          }

          Text {
            visible: Boolean(segItem.modelData && segItem.modelData.count && segItem.modelData.count > 0)
            anchors.verticalCenter: parent.verticalCenter
            text: (segItem.modelData && segItem.modelData.count) ? segItem.modelData.count : ""
            font.family: Theme.mono
            font.pixelSize: Theme.fontXs
            color: (segItem.modelData && segItem.modelData.alert && root.current !== segItem.index) ? Theme.amber : Theme.ink3
          }

          Rectangle {
            visible: Boolean(segItem.modelData && segItem.modelData.playing)
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 0
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
