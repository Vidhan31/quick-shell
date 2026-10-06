pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import "../theme"

// One launcher result row. Never focusable: QML focus must stay in the
// search field while the window is open, or the focus-loss guard closes us.
Item {
  id: row

  required property var modelData
  required property int index
  property bool isCurrent: false
  property var launcher: null

  width: ListView.view ? ListView.view.width : 0
  height: Theme.launcherRowHeight

  function formatHl(text: string, hl: var): string {
    if (!hl || hl.length === 0) return text;
    const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const col = "" + Theme.accent;
    let out = "";
    let cur = 0;
    for (let i = 0; i < hl.length; i++) {
      const s = Math.max(0, hl[i][0]);
      const e = Math.min(text.length, hl[i][1]);
      if (s > cur) out += esc(text.slice(cur, s));
      if (e > s) out += "<font color=\"" + col + "\">" + esc(text.slice(s, e)) + "</font>";
      cur = Math.max(cur, e);
    }
    if (cur < text.length) out += esc(text.slice(cur));
    return out;
  }

  /* Path rows carry the absolute path as their name. Segments past the theme
     cap are middle-elided, the basename is left whole because it identifies the
     result. Trimming runs before formatHl on purpose: path rows always arrive
     with an empty hlName (LauncherService.pathRowFor), so current and
     non-current rows render the same string. */
  function trimPath(path: string): string {
    const cap = Theme.launcherPathSegMax;
    if (path.length === 0) return path;
    const segs = path.split("/");
    const last = segs.length - 1;
    for (let i = 0; i < last; i++) {
      const s = segs[i];
      if (s.length <= cap) continue;
      const keep = cap - 1;
      const head = Math.ceil(keep * 0.6);
      segs[i] = s.slice(0, head) + "…" + s.slice(s.length - (keep - head));
    }
    return segs.join("/");
  }

  readonly property bool isPath: row.modelData.kind === "path" || row.modelData.kind === "file"
  readonly property bool isCommand: row.modelData.kind === "command"
  readonly property string plainName: row.modelData.name || ""
  readonly property string plainGeneric: row.isPath
    ? row.trimPath(row.modelData.generic || "")
    : (row.modelData.generic || "")

  readonly property var hlName: row.modelData.hlName || []
  readonly property var hlGeneric: row.modelData.hlGeneric || []

  readonly property string richName: formatHl(row.plainName, hlName)
  readonly property string richGeneric: formatHl(row.plainGeneric, hlGeneric)

  Rectangle {
    id: bg
    anchors.fill: parent
    anchors.leftMargin: Theme.launcherRowInset
    anchors.rightMargin: Theme.launcherRowInset
    radius: Theme.radiusBase
    color: row.isCurrent ? Theme.selected : (ma.containsMouse ? Theme.hoverFill : "transparent")
  }

  IconImage {
    id: appIcon
    anchors.left: parent.left
    anchors.leftMargin: Theme.launcherContentInset
    anchors.verticalCenter: parent.verticalCenter
    implicitSize: Theme.launcherIconSize
    asynchronous: true
    source: row.modelData.iconSrc || ""
  }

  Text {
    id: fallbackGlyph
    anchors.centerIn: appIcon
    text: row.isCommand ? ">" : (row.modelData.name || "?").charAt(0).toUpperCase()
    color: Theme.ink1
    font.family: row.isCommand ? Theme.mono : Theme.roundedFont
    font.pixelSize: Theme.fontBase
    font.bold: true
    visible: appIcon.status === Image.Error || !row.modelData.iconSrc
  }

  readonly property bool isApp: !row.isPath && !row.isCommand
  readonly property bool isPinned: row.launcher ? row.launcher.isPinned(row.modelData.id) : false
  readonly property bool hasGeneric: (row.modelData.generic || "").length > 0
  readonly property real pinSpace: row.isApp ? (pinBtn.width + Theme.spaceSm) : 0
  readonly property real textSpace: Math.max(0, row.width - (Theme.launcherContentInset * 2 + Theme.launcherIconSize + Theme.launcherRowPadX + row.pinSpace))

  Text {
    id: nameText
    anchors.left: appIcon.right
    anchors.leftMargin: Theme.launcherRowPadX
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: (row.isPath && row.hasGeneric) ? -8 : 0
    width: row.isPath
      ? row.textSpace
      : (row.hasGeneric
          ? Math.min(implicitWidth, Math.max(row.textSpace * 0.4, row.textSpace - genericText.implicitWidth - Theme.spaceMd))
          : Math.min(implicitWidth, row.textSpace))
    text: row.isCurrent ? row.richName : row.plainName
    textFormat: (row.isCurrent && row.hlName.length > 0) ? Text.StyledText : Text.PlainText
    font.family: row.isCommand ? Theme.mono : Theme.displayFont
    font.pixelSize: row.isCommand ? Theme.fontSm : Theme.fontMd
    color: Theme.ink1
    elide: Text.ElideMiddle
    maximumLineCount: 1
  }

  Text {
    id: genericText
    anchors.left: row.isPath ? nameText.left : nameText.right
    anchors.leftMargin: row.isPath ? 0 : Theme.spaceMd
    anchors.right: pinBtn.visible ? pinBtn.left : parent.right
    anchors.rightMargin: pinBtn.visible ? Theme.spaceSm : Theme.launcherContentInset
    anchors.top: row.isPath ? nameText.bottom : undefined
    anchors.topMargin: row.isPath ? 1 : 0
    anchors.baseline: row.isPath ? undefined : nameText.baseline
    text: row.isCurrent ? row.richGeneric : row.plainGeneric
    textFormat: (row.isCurrent && row.hlGeneric.length > 0) ? Text.StyledText : Text.PlainText
    visible: row.hasGeneric
    font.family: row.isCommand ? Theme.mono : Theme.textFont
    font.pixelSize: Theme.fontSm
    color: Theme.ink3
    elide: row.isPath ? Text.ElideMiddle : Text.ElideRight
    maximumLineCount: 1
  }

  Item {
    id: dragDummy
  }

  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction | Qt.LinkAction
  Drag.mimeData: (row.isPath && row.modelData.abs) ? {
    "text/uri-list": "file://" + row.modelData.abs + "\r\n",
    "text/plain": row.modelData.abs,
    "application/x-kde-cutselection": "0",
    "x-special/gnome-copied-files": "copy\nfile://" + row.modelData.abs + "\n"
  } : ({})
  Drag.imageSource: (row.isPath && row.modelData.iconSrc) ? row.modelData.iconSrc : ""
  Drag.imageSourceSize: Qt.size(Theme.launcherIconSize, Theme.launcherIconSize)
  Drag.hotSpot: Qt.point(Theme.launcherIconSize / 2, Theme.launcherIconSize / 2)
  Drag.active: row.isPath && ma.drag.active

  Drag.onDragStarted: {
    if (row.launcher) {
      row.launcher.isDragging = true;
    }
  }

  Drag.onDragFinished: {
    if (row.launcher) {
      row.launcher.isDragging = false;
      row.launcher.close();
    }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    drag.target: row.isPath ? dragDummy : undefined
    drag.threshold: 10
    onClicked: mouse => {
      if (!row.launcher) return;
      if (mouse.button === Qt.RightButton) {
        if (row.isPath) {
          row.launcher.copyIndex(row.index);
          row.launcher.close();
        }
        return;
      }
      const isCtrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
      const isShift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
      if (isCtrl && isShift) {
        row.launcher.activateIndex(row.index, "terminal");
      } else if (isShift) {
        row.launcher.activateIndex(row.index, "shift");
      } else {
        row.launcher.activateIndex(row.index, "default");
      }
    }
  }

  Rectangle {
    id: pinBtn
    z: 10
    anchors.right: parent.right
    anchors.rightMargin: Theme.launcherContentInset
    anchors.verticalCenter: parent.verticalCenter
    width: 24
    height: 24
    radius: Theme.radiusSm
    visible: row.isApp
    color: pinMa.containsMouse ? Theme.hoverFill : "transparent"
    border.color: pinMa.containsMouse ? Theme.line : "transparent"
    border.width: 1

    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

    Text {
      anchors.centerIn: parent
      text: row.isPinned ? "󰤱" : "󰐃"
      font.family: Theme.mono
      font.pixelSize: Theme.iconSm
      color: row.isPinned ? Theme.accent : (pinMa.containsMouse ? Theme.accent : Theme.ink3)
      opacity: (row.isPinned || row.isCurrent || pinMa.containsMouse || ma.containsMouse) ? 1.0 : 0.35
    }

    MouseArea {
      id: pinMa
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      preventStealing: true
      onClicked: mouse => {
        mouse.accepted = true;
        if (row.launcher) {
          if (row.isPinned) {
            row.launcher.unpinApp(row.modelData.id);
          } else {
            row.launcher.pinApp(row.modelData.id);
          }
        }
      }
    }
  }
}
