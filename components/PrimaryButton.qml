pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root
  signal clicked()
  property string text: ""
  property string glyph: ""
  property color fill: Theme.accent
  property color ink: Theme.darkInk
  property bool enabledBtn: true
  property bool circular: false
  property int btnSize: 32
  property int glyphSize: Theme.iconBase
  property int glyphOffset: 0
  property string tooltip: ""
  property string tooltipSub: ""

  implicitHeight: root.circular ? root.btnSize : 32
  implicitWidth: root.circular ? root.btnSize : (contentRow.implicitWidth + 20)
  radius: root.circular ? (root.btnSize / 2) : Theme.radiusBase
  activeFocusOnTab: root.enabledBtn

  scale: (ma.pressed && root.enabledBtn) ? 0.985 : 1.0
  Behavior on scale { NumberAnimation { duration: 80 } }
  color: !root.enabledBtn ? Theme.btnDisabled : ma.pressed ? Qt.darker(fill, 1.2) : (ma.containsMouse || root.activeFocus) ? Qt.lighter(fill, 1.07) : fill
  border.color: root.activeFocus ? Theme.ink1 : "transparent"
  border.width: root.activeFocus ? Theme.focusRingWidth : 0
  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

  Accessible.role: Accessible.Button
  Accessible.name: root.tooltip.length > 0 ? root.tooltip : (root.text.length > 0 ? root.text : root.glyph)
  Accessible.description: root.tooltipSub

  function findHost(): var {
    let p = root.parent;
    while (p) {
      if (typeof p.showTip === "function") return p;
      if (p.barWindow && typeof p.barWindow.showTip === "function") return p.barWindow;
      p = p.parent;
    }
    return null;
  }

  function updateTip(): void {
    const host = root.findHost();
    if ((ma.containsMouse || root.activeFocus) && root.tooltip.length > 0 && root.enabledBtn) {
      if (host && typeof host.showTip === "function") {
        host.showTip(root, root.tooltip, root.tooltipSub);
      }
    } else {
      if (host && typeof host.hideTip === "function") {
        host.hideTip();
      }
    }
  }

  onActiveFocusChanged: updateTip()
  onTooltipChanged: if (ma.containsMouse || root.activeFocus) updateTip()
  Component.onDestruction: {
    const host = root.findHost();
    if (host && typeof host.hideTip === "function") {
      host.hideTip();
    }
  }

  Keys.onReturnPressed: event => {
    if (root.enabledBtn) {
      root.clicked();
      event.accepted = true;
    }
  }
  Keys.onSpacePressed: event => {
    if (root.enabledBtn) {
      root.clicked();
      event.accepted = true;
    }
  }

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: 7

    Text {
      visible: root.glyph.length > 0
      anchors.verticalCenter: parent.verticalCenter
      anchors.horizontalCenterOffset: root.glyphOffset
      text: root.glyph
      font.family: Theme.mono
      font.pixelSize: root.glyphSize
      color: root.enabledBtn ? root.ink : Theme.ink3
    }

    Text {
      visible: root.text.length > 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      font.family: Theme.textFont
      font.pixelSize: Theme.fontMd
      font.weight: Font.DemiBold
      color: root.enabledBtn ? root.ink : Theme.ink3
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: root.enabledBtn
    cursorShape: root.enabledBtn ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: root.updateTip()
    onClicked: {
      const host = root.findHost();
      if (host && typeof host.hideTip === "function") {
        host.hideTip();
      }
      if (root.enabledBtn) root.clicked();
    }
  }
}
