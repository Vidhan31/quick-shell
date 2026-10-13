pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../theme"

PopupWindow {
  id: root

  property Item currentTarget: null
  property string text: ""
  property string subtext: ""

  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6
  anchor.adjustment: PopupAdjustment.SlideX

  visible: false
  color: "transparent"

  implicitWidth: tipCard.implicitWidth
  implicitHeight: tipCard.implicitHeight

  Timer {
    id: delayTimer
    interval: 200
    repeat: false
    onTriggered: {
      if (root.currentTarget && root.text.length > 0) {
        if (root.currentTarget.Window && root.currentTarget.Window.window && root.currentTarget.Window.window.screen) {
          root.screen = root.currentTarget.Window.window.screen;
        }
        root.anchor.item = root.currentTarget;
        root.visible = true;
        root.anchor.updateAnchor();
      }
    }
  }

  function show(item: Item, mainText: string, sub: string): void {
    if (!item || !mainText) {
      hide();
      return;
    }
    currentTarget = item;
    text = mainText;
    subtext = sub || "";
    delayTimer.restart();
  }

  function hide(): void {
    delayTimer.stop();
    root.visible = false;
    currentTarget = null;
  }

  Rectangle {
    id: tipCard
    implicitWidth: Math.max(48, tipCol.implicitWidth + 16)
    implicitHeight: tipCol.implicitHeight + 10
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radiusSm
    color: Theme.surfaceElevated
    border.color: Theme.cardBorder
    border.width: 1

    Column {
      id: tipCol
      anchors.centerIn: parent
      spacing: 2

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.text
        color: Theme.ink1
        font.pixelSize: Theme.fontSm
        font.weight: Font.Medium
        font.family: Theme.textFont
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.subtext.length > 0
        text: root.subtext
        color: Theme.ink2
        font.pixelSize: Theme.fontXs
        font.family: Theme.textFont
      }
    }
  }
}
