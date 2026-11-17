pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"

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

  BackgroundEffect.blurRegion: Region {
    item: tipCard
    radius: Theme.radiusChip
  }

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

  TooltipCard {
    id: tipCard
    text: root.text
    subtext: root.subtext
  }
}
