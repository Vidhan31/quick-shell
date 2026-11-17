pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property Item currentTarget: null
  property string text: ""
  property string subtext: ""

  anchors.fill: parent
  z: 9999
  visible: tipBox.opacity > 0.01

  Timer {
    id: delayTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.currentTarget && root.text.length > 0) {
        root.reposition();
        tipBox.opacity = 1.0;
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
    tipBox.opacity = 0.0;
    currentTarget = null;
  }

  function reposition(): void {
    if (!currentTarget) return;
    const pt = currentTarget.mapToItem(root, 0, 0);
    let tx = pt.x + (currentTarget.width / 2) - (tipBox.width / 2);
    tx = Math.max(8, Math.min(tx, root.width - tipBox.width - 8));

    let ty = pt.y + currentTarget.height + 6;
    if (ty + tipBox.height > root.height - 8) {
      ty = pt.y - tipBox.height - 6;
    }
    tipBox.x = Math.round(tx);
    tipBox.y = Math.round(ty);
  }

  TooltipCard {
    id: tipBox
    opacity: 0.0
    text: root.text
    subtext: root.subtext

    Behavior on opacity {
      OpacityAnimator { duration: Theme.durationFast }
    }
  }
}
