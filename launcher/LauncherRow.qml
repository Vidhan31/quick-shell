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

  signal dragStarted()
  signal dragFinished()

  width: ListView.view ? ListView.view.width : 0
  height: Theme.launcherRowHeight

  function formatHl(text: string, hl: var): string {
    if (!text || !hl || hl.length === 0) return text || "";
    let ranges = [];
    if (typeof hl[0] === "number") {
      for (let k = 0; k < hl.length; k += 2) {
        if (k + 1 < hl.length) {
          ranges.push([hl[k], hl[k + 1]]);
        }
      }
    } else if (Array.isArray(hl) || typeof hl.length === "number") {
      for (let k = 0; k < hl.length; k++) {
        const item = hl[k];
        if (item && typeof item.length === "number" && item.length >= 2) {
          ranges.push([item[0], item[1]]);
        }
      }
    }
    if (ranges.length === 0) return text;

    const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const col = "" + Theme.accent;
    let out = "";
    let cur = 0;
    for (let i = 0; i < ranges.length; i++) {
      const start = Number(ranges[i][0]);
      const end = Number(ranges[i][1]);
      if (isNaN(start) || isNaN(end) || end <= start) continue;
      const s = Math.max(0, Math.min(text.length, start));
      const e = Math.max(0, Math.min(text.length, end));
      if (s > cur) out += esc(text.slice(cur, s));
      if (e > s && e > cur) {
        const actualStart = Math.max(cur, s);
        out += "<font color=\"" + col + "\">" + esc(text.slice(actualStart, e)) + "</font>";
        cur = e;
      }
    }
    if (cur < text.length) out += esc(text.slice(cur));
    return out || text;
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
  readonly property bool isSetting: row.modelData.kind === "setting"
  readonly property bool isKill: !!row.modelData.kind && row.modelData.kind.startsWith("kill_")
  readonly property bool isKillApp: row.modelData.kind === "kill_app"
  readonly property bool isKillService: row.modelData.kind === "kill_service"
  readonly property bool isKillUserService: isKillService && !!row.modelData.isUser
  readonly property bool isKillSystemService: isKillService && !row.modelData.isUser
  readonly property bool isKillProcess: row.modelData.kind === "kill_process"
  readonly property bool isKillPaused: isKill && !!row.modelData.isPaused
  readonly property string plainName: row.modelData.name || ""
  readonly property string plainGeneric: row.isPath
    ? row.trimPath(row.modelData.generic || "")
    : (row.isSetting
        ? (row.modelData.categoryPath ? (row.modelData.categoryPath + (row.modelData.generic ? (" · " + row.modelData.generic) : "")) : (row.modelData.generic || ""))
        : (row.modelData.generic || ""))

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
    text: row.isCommand ? ">" : (row.isKillService ? "󰒓" : (row.modelData.name || "?").charAt(0).toUpperCase())
    color: Theme.ink1
    font.family: row.isCommand ? Theme.mono : Theme.roundedFont
    font.pixelSize: Theme.fontBase
    font.bold: true
    visible: appIcon.status === Image.Error || !row.modelData.iconSrc
  }

  readonly property bool isApp: !row.isPath && !row.isCommand && !row.isSetting && !row.isKill
  readonly property bool isPinned: row.launcher ? row.launcher.isPinned(row.modelData.id) : false
  readonly property bool hasGeneric: row.plainGeneric.length > 0
  readonly property string badgeLabel: {
    if (row.isKillPaused) return "Paused";
    if (row.isKillApp) return "App";
    if (row.isKillUserService) return "User Service";
    if (row.isKillSystemService) return "System Service";
    if (row.isKillProcess) return "Process";
    return "";
  }
  readonly property bool hasBadge: row.badgeLabel.length > 0
  readonly property real pinSpace: row.isApp ? (pinBtn.width + Theme.spaceSm) : (row.hasBadge ? (badgeRect.width + Theme.spaceSm) : 0)
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
    anchors.right: pinBtn.visible ? pinBtn.left : (badgeRect.visible ? badgeRect.left : parent.right)
    anchors.rightMargin: (pinBtn.visible || badgeRect.visible) ? Theme.spaceSm : Theme.launcherContentInset
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
    row.dragStarted();
  }

  Drag.onDragFinished: {
    row.dragFinished();
    if (row.launcher) {
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

  Rectangle {
    id: badgeRect
    z: 10
    anchors.right: parent.right
    anchors.rightMargin: Theme.launcherContentInset
    anchors.verticalCenter: parent.verticalCenter
    visible: row.hasBadge
    height: 18
    radius: Theme.radiusSm
    color: {
      if (row.isKillPaused) return Theme.tint(Theme.amber, 0.25);
      if (row.isKillApp) return Theme.tint(Theme.accent, 0.25);
      if (row.isKillUserService) return Theme.tint(Theme.teal, 0.25);
      if (row.isKillSystemService) return Theme.tint(Theme.violet, 0.25);
      if (row.isKillProcess) return Theme.tint(Theme.ink2, 0.18);
      if (row.isCurrent) return Theme.tint(Theme.selected, 0.5);
      return Theme.tint(Theme.surfaceElevated, 0.6);
    }
    border.color: {
      if (row.isKillPaused) return Theme.amber;
      if (row.isKillApp) return Theme.accent;
      if (row.isKillUserService) return Theme.teal;
      if (row.isKillSystemService) return Theme.violet;
      if (row.isKillProcess) return Theme.ink2;
      return Theme.line;
    }
    border.width: 1
    implicitWidth: badgeText.implicitWidth + Theme.spaceSm * 2

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: row.badgeLabel
      font.family: Theme.displayFont
      font.pixelSize: Theme.fontXs
      font.weight: Font.Medium
      color: {
        if (row.isKillPaused) return Theme.amber;
        if (row.isKillApp) return Theme.accent;
        if (row.isKillUserService) return Theme.teal;
        if (row.isKillSystemService) return Theme.violet;
        if (row.isKillProcess) return Theme.ink2;
        return Theme.ink3;
      }
    }
  }
}
