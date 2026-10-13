pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property string screenName: ""
  property string wallpaperSource: "file:///home/dev/Pictures/Wallpapers/a_man_and_a_robot_standing_in_a_parking_lot.jpg"

  signal clicked(real mouseX, real mouseY)
  signal contextMenuRequested(real mouseX, real mouseY)

  Rectangle {
    id: fallbackBg
    anchors.fill: parent
    color: Theme.bg
  }

  Image {
    id: bgImage
    anchors.fill: parent
    visible: root.wallpaperSource !== "" && status === Image.Ready
    source: root.wallpaperSource
    sourceSize: Qt.size(1920, 1080)
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onPressed: mouse => {
      if (mouse.button !== Qt.RightButton) {
        root.clicked(mouse.x, mouse.y);
      }
    }

    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        root.contextMenuRequested(mouse.x, mouse.y);
      }
    }
  }
}
