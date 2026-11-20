pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../theme"

PopupWindow {
  id: root

  property Item currentTarget: null
  property string text: ""
  property string subtext: ""
  property bool tipVisible: false

  color: "transparent"
  visible: tipVisible && currentTarget !== null
  implicitWidth: tipBox.implicitWidth
  implicitHeight: tipBox.implicitHeight

  anchor.item: currentTarget
  anchor.edges: Edges.Top | Edges.Left
  anchor.gravity: Edges.Top | Edges.Right
  anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide

  Timer {
    id: delayTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.currentTarget && root.text.length > 0) {
        root.tipVisible = true;
        Qt.callLater(() => root.anchor.updateAnchor());
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
    tipVisible = false;
    delayTimer.restart();
  }

  function hide(): void {
    delayTimer.stop();
    tipVisible = false;
    currentTarget = null;
  }

  TooltipCard {
    id: tipBox
    anchors.fill: parent
    opacity: root.tipVisible ? 1 : 0
    text: root.text
    subtext: root.subtext

    Behavior on opacity {
      OpacityAnimator { duration: Theme.durationFast }
    }
  }
}
