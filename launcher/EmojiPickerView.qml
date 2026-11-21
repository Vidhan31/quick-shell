pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../theme"
import "../components"

Item {
  id: root

  property var launcher: null
  property var emojiProvider: root.launcher ? root.launcher.emojiProvider : null
  property string searchTerm: root.launcher ? root.launcher.emojiSearchTerm : ""

  readonly property int columnsCount: 11
  property var categories: []
  property var rows: []
  property var hoveredEmoji: null

  property var recentEmojis: []
  readonly property var defaultRecentEmojis: [
    { "glyph": "😀", "name": "grinning face", "code": "U+1F600", "group": "Smileys & Emotion", "subgroup": "face-smiling" },
    { "glyph": "😂", "name": "face with tears of joy", "code": "U+1F602", "group": "Smileys & Emotion", "subgroup": "face-smiling" },
    { "glyph": "❤️", "name": "red heart", "code": "U+2764 U+FE0F", "group": "Smileys & Emotion", "subgroup": "heart" },
    { "glyph": "👍", "name": "thumbs up", "code": "U+1F44D", "group": "People & Body", "subgroup": "hand-fingers-closed" },
    { "glyph": "🔥", "name": "fire", "code": "U+1F525", "group": "Travel & Places", "subgroup": "sky & weather" },
    { "glyph": "🎉", "name": "party popper", "code": "U+1F389", "group": "Activities", "subgroup": "event" },
    { "glyph": "✨", "name": "sparkles", "code": "U+2728", "group": "Activities", "subgroup": "event" },
    { "glyph": "🙏", "name": "folded hands", "code": "U+1F64F", "group": "People & Body", "subgroup": "hands" },
    { "glyph": "🚀", "name": "rocket", "code": "U+1F680", "group": "Travel & Places", "subgroup": "transport-air" },
    { "glyph": "👀", "name": "eyes", "code": "U+1F440", "group": "People & Body", "subgroup": "body-parts" },
    { "glyph": "💯", "name": "hundred points", "code": "U+1F4AF", "group": "Smileys & Emotion", "subgroup": "emotion" }
  ]

  PersistentProperties {
    id: emojiPersist
    property string recentJson: ""
    reloadableId: "launcher-recent-emojis"
  }

  readonly property string recentConfigPath: Quickshell.env("HOME") + "/.config/quickshell/recent_emojis.json"

  FileView {
    id: recentConfigFile
    path: root.recentConfigPath
    onLoaded: root.loadRecentFromFile()
  }

  function loadRecentFromFile(): void {
    if (!recentConfigFile.loaded) return;
    const raw = recentConfigFile.text();
    if (!raw) return;
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) {
        root.recentEmojis = parsed;
        emojiPersist.recentJson = JSON.stringify(parsed);
      }
    } catch (e) {
      console.warn("Failed to parse recent_emojis.json:", e);
    }
  }

  function saveRecentToDisk(): void {
    const json = JSON.stringify(root.recentEmojis);
    recentConfigFile.setText(json);
  }

  function recordRecent(emoji: var): void {
    if (!emoji || !emoji.glyph) return;
    const current = root.recentEmojis ? root.recentEmojis.slice() : [];
    const idx = current.findIndex(e => e && e.glyph === emoji.glyph);
    if (idx !== -1) {
      current.splice(idx, 1);
    }
    current.unshift({
      glyph: emoji.glyph,
      name: emoji.name || "",
      code: emoji.code || "",
      group: emoji.group || "",
      subgroup: emoji.subgroup || ""
    });
    if (current.length > 11) {
      current.length = 11;
    }
    root.recentEmojis = current;
    emojiPersist.recentJson = JSON.stringify(current);
    root.saveRecentToDisk();
  }

  // Multi-Selection Staging Buffer
  property var stagedEmojis: []
  readonly property string stagedString: {
    if (!root.stagedEmojis || root.stagedEmojis.length === 0) return "";
    let s = "";
    for (let i = 0; i < root.stagedEmojis.length; i++) {
      s += root.stagedEmojis[i].glyph;
    }
    return s;
  }

  function stageEmoji(emoji: var): void {
    if (!emoji || !emoji.glyph) return;
    const next = root.stagedEmojis ? root.stagedEmojis.slice() : [];
    next.push({
      glyph: emoji.glyph,
      name: emoji.name || "",
      code: emoji.code || "",
      group: emoji.group || "",
      subgroup: emoji.subgroup || ""
    });
    root.stagedEmojis = next;
    root.recordRecent(emoji);
  }

  function removeLastStaged(): void {
    if (!root.stagedEmojis || root.stagedEmojis.length === 0) return;
    const next = root.stagedEmojis.slice();
    next.pop();
    root.stagedEmojis = next;
  }

  function clearStaged(): void {
    root.stagedEmojis = [];
  }

  function triggerSelection(emoji: var, shift: bool): void {
    let textToPaste = "";
    if (root.stagedEmojis && root.stagedEmojis.length > 0) {
      textToPaste = root.stagedString;
      if (emoji && emoji.glyph) {
        const lastStaged = root.stagedEmojis[root.stagedEmojis.length - 1];
        if (!lastStaged || lastStaged.glyph !== emoji.glyph) {
          textToPaste += emoji.glyph;
          root.recordRecent(emoji);
        }
      }
      for (let i = 0; i < root.stagedEmojis.length; i++) {
        root.recordRecent(root.stagedEmojis[i]);
      }
      root.clearStaged();
    } else if (emoji && emoji.glyph) {
      textToPaste = emoji.glyph;
      root.recordRecent(emoji);
    }
    if (!textToPaste) return;

    if (root.launcher) {
      root.launcher.close();
    }
    if (root.emojiProvider) {
      root.emojiProvider.pasteEmoji(textToPaste, shift);
    }
  }

  function triggerCopy(emoji: var): void {
    if (root.stagedEmojis && root.stagedEmojis.length > 0) {
      if (root.emojiProvider) {
        root.emojiProvider.copyEmoji(root.stagedString);
      }
      return;
    }
    if (!emoji || !emoji.glyph) return;
    root.recordRecent(emoji);
    if (root.emojiProvider) {
      root.emojiProvider.copyEmoji(emoji.glyph);
    }
  }

  property int recentIndex: 0
  property int selectedRowIndex: -1
  property int selectedColIndex: 0

  implicitHeight: stagingBar.visible ? 482 : 440

  function findNextEmojiRow(fromIndex: int): int {
    if (!root.rows) return -1;
    for (let i = fromIndex + 1; i < root.rows.length; i++) {
      if (!root.rows[i].isHeader && root.rows[i].emojis && root.rows[i].emojis.length > 0) {
        return i;
      }
    }
    return -1;
  }

  function findPrevEmojiRow(fromIndex: int): int {
    if (!root.rows) return -1;
    const start = Math.min(fromIndex - 1, root.rows.length - 1);
    for (let i = start; i >= 0; i--) {
      if (!root.rows[i].isHeader && root.rows[i].emojis && root.rows[i].emojis.length > 0) {
        return i;
      }
    }
    return -1;
  }

  function setSelected(rIdx: int, cIdx: int): void {
    root.recentIndex = -1;
    root.selectedRowIndex = rIdx;
    root.selectedColIndex = cIdx;
    if (root.rows && rIdx >= 0 && rIdx < root.rows.length) {
      const row = root.rows[rIdx];
      if (row.emojis && cIdx >= 0 && cIdx < row.emojis.length) {
        root.hoveredEmoji = row.emojis[cIdx];
      }
      listView.positionViewAtIndex(rIdx, ListView.Contain);
    }
  }

  function moveHorizontal(delta: int): bool {
    // 1. Navigation within the Recent Bar
    if (root.recentIndex >= 0) {
      if (!root.recentEmojis || root.recentEmojis.length === 0) return false;
      const nextIdx = root.recentIndex + delta;
      if (nextIdx >= 0 && nextIdx < root.recentEmojis.length) {
        root.recentIndex = nextIdx;
        root.hoveredEmoji = root.recentEmojis[nextIdx];
        return true;
      }
      return true;
    }

    // 2. Navigation within the Grid
    if (!root.rows || root.rows.length === 0) return false;
    let rIdx = root.selectedRowIndex;
    let cIdx = root.selectedColIndex;

    if (rIdx < 0 || rIdx >= root.rows.length || root.rows[rIdx].isHeader) {
      rIdx = findNextEmojiRow(-1);
      cIdx = 0;
      if (rIdx < 0) return false;
      setSelected(rIdx, cIdx);
      return true;
    }

    const curEmojis = root.rows[rIdx].emojis || [];
    const newCol = cIdx + delta;

    if (newCol >= 0 && newCol < curEmojis.length) {
      setSelected(rIdx, newCol);
      return true;
    }

    if (delta > 0) {
      const nextR = findNextEmojiRow(rIdx);
      if (nextR >= 0) {
        setSelected(nextR, 0);
        return true;
      }
    } else {
      const prevR = findPrevEmojiRow(rIdx);
      if (prevR >= 0) {
        const prevEmojis = root.rows[prevR].emojis || [];
        setSelected(prevR, Math.max(0, prevEmojis.length - 1));
        return true;
      }
    }
    return true;
  }

  function moveVertical(delta: int): bool {
    // 1. In Recent Bar moving DOWN into the Grid
    if (root.recentIndex >= 0) {
      if (delta > 0) {
        const first = findNextEmojiRow(-1);
        if (first >= 0) {
          const col = Math.min(root.recentIndex, columnsCount - 1);
          setSelected(first, col);
        }
      }
      return true;
    }

    // 2. In Grid moving UP or DOWN
    if (!root.rows || root.rows.length === 0) return false;
    let rIdx = root.selectedRowIndex;
    let cIdx = root.selectedColIndex;

    if (rIdx < 0 || rIdx >= root.rows.length || root.rows[rIdx].isHeader) {
      rIdx = findNextEmojiRow(-1);
      cIdx = 0;
      if (rIdx < 0) return false;
      setSelected(rIdx, cIdx);
      return true;
    }

    if (delta < 0) {
      const prev = findPrevEmojiRow(rIdx);
      if (prev < 0 && root.recentEmojis && root.recentEmojis.length > 0) {
        root.recentIndex = Math.min(cIdx, root.recentEmojis.length - 1);
        root.selectedRowIndex = -1;
        root.hoveredEmoji = root.recentEmojis[root.recentIndex];
        return true;
      }
    }

    let targetRow = rIdx;
    const steps = Math.abs(delta);
    const forward = delta > 0;

    for (let s = 0; s < steps; s++) {
      const next = forward ? findNextEmojiRow(targetRow) : findPrevEmojiRow(targetRow);
      if (next >= 0) {
        targetRow = next;
      } else {
        if (!forward && root.recentEmojis && root.recentEmojis.length > 0) {
          root.recentIndex = Math.min(cIdx, root.recentEmojis.length - 1);
          root.selectedRowIndex = -1;
          root.hoveredEmoji = root.recentEmojis[root.recentIndex];
          return true;
        }
        break;
      }
    }

    if (targetRow !== rIdx) {
      const targetEmojis = root.rows[targetRow].emojis || [];
      const clampedCol = Math.min(cIdx, Math.max(0, targetEmojis.length - 1));
      setSelected(targetRow, clampedCol);
      return true;
    }
    return true;
  }

  function handleKey(event: var): bool {
    // Ctrl+C: copy to clipboard (staged string if present, else hovered emoji)
    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_C)) {
      if (root.stagedEmojis.length > 0) {
        if (root.emojiProvider) root.emojiProvider.copyEmoji(root.stagedString);
        return true;
      }
      if (root.hoveredEmoji) {
        root.triggerCopy(root.hoveredEmoji);
        return true;
      }
    }

    // Ctrl+Enter: stage focused emoji
    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      if (root.hoveredEmoji) {
        root.stageEmoji(root.hoveredEmoji);
        return true;
      }
    }

    // Space: stage focused emoji
    if (event.key === Qt.Key_Space && (event.modifiers === Qt.NoModifier)) {
      if (root.hoveredEmoji) {
        root.stageEmoji(root.hoveredEmoji);
        return true;
      }
    }

    // Backspace: when search is empty and staged emojis exist, remove last staged
    if (event.key === Qt.Key_Backspace && root.searchTerm.length === 0 && root.stagedEmojis.length > 0) {
      root.removeLastStaged();
      return true;
    }

    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) {
      return false;
    }

    switch (event.key) {
    case Qt.Key_Right:
      return moveHorizontal(1);
    case Qt.Key_Left:
      return moveHorizontal(-1);
    case Qt.Key_Down:
      return moveVertical(1);
    case Qt.Key_Up:
      return moveVertical(-1);
    case Qt.Key_PageDown:
      return moveVertical(5);
    case Qt.Key_PageUp:
      return moveVertical(-5);
    case Qt.Key_Home:
      {
        if (root.recentEmojis && root.recentEmojis.length > 0) {
          root.recentIndex = 0;
          root.selectedRowIndex = -1;
          root.hoveredEmoji = root.recentEmojis[0];
        } else {
          const first = findNextEmojiRow(-1);
          if (first >= 0) setSelected(first, 0);
        }
        return true;
      }
    case Qt.Key_End:
      {
        const last = findPrevEmojiRow(root.rows ? root.rows.length : 0);
        if (last >= 0) {
          const emojis = root.rows[last].emojis || [];
          setSelected(last, Math.max(0, emojis.length - 1));
        }
        return true;
      }
    case Qt.Key_Return:
    case Qt.Key_Enter:
      {
        const isShift = (event.modifiers & Qt.ShiftModifier) !== 0;
        root.triggerSelection(root.hoveredEmoji, isShift);
        return true;
      }
    default:
      return false;
    }
  }

  function refresh(): void {
    if (!root.emojiProvider) return;
    root.categories = root.emojiProvider.getCategories(root.searchTerm, root.columnsCount);
    root.rows = root.emojiProvider.getRows(root.searchTerm, root.columnsCount);

    if (root.searchTerm.length === 0 && root.recentEmojis && root.recentEmojis.length > 0) {
      root.recentIndex = 0;
      root.selectedRowIndex = -1;
      root.hoveredEmoji = root.recentEmojis[0];
    } else {
      root.recentIndex = -1;
      const firstRow = findNextEmojiRow(-1);
      if (firstRow >= 0) {
        root.selectedRowIndex = firstRow;
        root.selectedColIndex = 0;
        const r = root.rows[firstRow];
        if (r && r.emojis && r.emojis.length > 0) {
          root.hoveredEmoji = r.emojis[0];
        }
      } else {
        root.selectedRowIndex = -1;
        root.selectedColIndex = 0;
        root.hoveredEmoji = null;
      }
    }
  }

  onSearchTermChanged: refresh()
  onEmojiProviderChanged: refresh()
  onVisibleChanged: {
    if (visible) {
      refresh();
      listView.contentY = 0;
    }
  }

  Component.onCompleted: {
    if (emojiPersist.recentJson && emojiPersist.recentJson !== "[]") {
      try {
        const parsed = JSON.parse(emojiPersist.recentJson);
        if (Array.isArray(parsed) && parsed.length > 0) {
          root.recentEmojis = parsed;
          refresh();
          return;
        }
      } catch (e) {
      }
    }
    if (recentConfigFile.loaded) {
      loadRecentFromFile();
    }
    if (!root.recentEmojis || root.recentEmojis.length === 0) {
      root.recentEmojis = root.defaultRecentEmojis;
    }
    refresh();
  }

  Column {
    anchors.fill: parent
    spacing: Theme.spaceSm

    // 1. Recently Used Array
    Item {
      id: recentBar
      anchors.left: parent.left
      anchors.right: parent.right
      height: 32
      visible: root.recentEmojis && root.recentEmojis.length > 0

      Flickable {
        id: recentFlickable
        anchors.fill: parent
        contentWidth: recentRow.width
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        clip: true

        Row {
          id: recentRow
          height: 32
          spacing: Theme.spaceSm
          anchors.verticalCenter: parent.verticalCenter

          Repeater {
            model: root.recentEmojis

            Rectangle {
              id: recentBtn
              required property var modelData
              required property int index

              readonly property bool isSelected: root.recentIndex === recentBtn.index
              readonly property bool isHovered: recentMa.containsMouse

              width: 32
              height: 30
              radius: Theme.radiusSm
              color: (recentBtn.isSelected || recentBtn.isHovered) ? Theme.hoverFill : "transparent"
              border.color: (recentBtn.isSelected || recentBtn.isHovered) ? Theme.accent : "transparent"
              border.width: (recentBtn.isSelected || recentBtn.isHovered) ? 1 : 0

              Behavior on color { ColorAnimation { duration: Theme.durationFast } }
              Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

              Text {
                anchors.centerIn: parent
                text: recentBtn.modelData.glyph || ""
                font.pixelSize: 18
              }

              HoverTooltip {
                id: recentTip
                text: recentBtn.modelData.name || ""
              }

              MouseArea {
                id: recentMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  recentTip.show();
                  root.recentIndex = recentBtn.index;
                  root.selectedRowIndex = -1;
                  root.hoveredEmoji = recentBtn.modelData;
                }
                onExited: recentTip.hide()
                onClicked: mouse => {
                  root.recentIndex = recentBtn.index;
                  root.selectedRowIndex = -1;
                  root.hoveredEmoji = recentBtn.modelData;
                  if (mouse.modifiers & Qt.ControlModifier) {
                    root.stageEmoji(recentBtn.modelData);
                  } else {
                    const isShift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                    root.triggerSelection(recentBtn.modelData, isShift);
                  }
                }
              }
            }
          }
        }
      }
    }

    Hairline {
      anchors.left: parent.left
      anchors.right: parent.right
      visible: recentBar.visible
    }

    // 2. Virtualized Emoji Grid View
    Item {
      id: listContainer
      anchors.left: parent.left
      anchors.right: parent.right
      height: 340
      clip: true

      ListView {
        id: listView
        anchors.fill: parent
        anchors.rightMargin: 10
        clip: true
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows

        ScrollBar.vertical: ScrollBar {
          id: vbar
          anchors.right: parent.right
          anchors.rightMargin: -8
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 6
          policy: ScrollBar.AlwaysOn
          active: true

          contentItem: Rectangle {
            implicitWidth: 6
            radius: Theme.radiusSm
            color: vbar.pressed ? Theme.accent : (vbar.hovered ? Theme.ink2 : Theme.surfaceElevated)
            border.color: Theme.line
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
          }
        }

        WheelHandler {
          target: listView
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: event => {
            const dy = event.angleDelta.y;
            if (dy === 0) return;
            const step = 46 * 2;
            const dir = dy > 0 ? -1 : 1;
            listView.contentY = Math.max(0, Math.min(listView.contentHeight - listView.height, listView.contentY + dir * step));
          }
        }

        delegate: Item {
          id: rowDelegate
          required property var modelData
          required property int index

          width: listView.width
          height: rowDelegate.modelData.isHeader ? 32 : 46

          // Header Delegate
          Item {
            anchors.fill: parent
            visible: rowDelegate.modelData.isHeader

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.spaceSm

              Text {
                text: rowDelegate.modelData.icon || ""
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: String(rowDelegate.modelData.category || "").toUpperCase()
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                font.letterSpacing: 1.1
                font.weight: Font.DemiBold
                color: Theme.ink3
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: "(" + (rowDelegate.modelData.count || 0) + ")"
                font.family: Theme.mono
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Hairline {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
            }
          }

          // Emoji Grid Row Delegate
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            visible: !rowDelegate.modelData.isHeader

            Repeater {
              model: rowDelegate.modelData.emojis || []

              Rectangle {
                id: cell
                required property var modelData
                required property int index

                readonly property bool isSelected: root.recentIndex === -1 && root.selectedRowIndex === rowDelegate.index && root.selectedColIndex === cell.index
                readonly property bool isHovered: cellMa.containsMouse

                width: 48
                height: 42
                radius: Theme.radiusSm
                color: (cell.isSelected || cell.isHovered) ? Theme.hoverFill : "transparent"
                border.color: cell.isSelected ? Theme.accent : (cell.isHovered ? Theme.accent : "transparent")
                border.width: 1

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                Text {
                  anchors.centerIn: parent
                  text: cell.modelData.glyph || ""
                  font.pixelSize: 24
                }

                MouseArea {
                  id: cellMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.recentIndex = -1;
                    root.selectedRowIndex = rowDelegate.index;
                    root.selectedColIndex = cell.index;
                    root.hoveredEmoji = cell.modelData;
                  }
                  onClicked: mouse => {
                    root.recentIndex = -1;
                    root.selectedRowIndex = rowDelegate.index;
                    root.selectedColIndex = cell.index;
                    root.hoveredEmoji = cell.modelData;
                    if (mouse.modifiers & Qt.ControlModifier) {
                      root.stageEmoji(cell.modelData);
                    } else {
                      const isShift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                      root.triggerSelection(cell.modelData, isShift);
                    }
                  }
                }
              }
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        text: "No matching emojis"
        font.family: Theme.textFont
        font.pixelSize: Theme.fontBase
        color: Theme.ink3
      }
    }

    // Staging Buffer Bar
    Rectangle {
      id: stagingBar
      anchors.left: parent.left
      anchors.right: parent.right
      height: 36
      radius: Theme.radiusSm
      color: Theme.tint(Theme.accent, 0.12)
      border.color: Theme.tint(Theme.accent, 0.35)
      border.width: 1
      visible: root.stagedEmojis.length > 0

      Item {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.spaceSm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "STAGED (" + root.stagedEmojis.length + "):"
            font.family: Theme.textFont
            font.pixelSize: Theme.fontXs
            font.letterSpacing: 1.1
            font.weight: Font.DemiBold
            color: Theme.accent
          }

          Flickable {
            id: stagedFlickable
            width: Math.min(stagingBar.width - 200, stagedRow.width)
            height: 28
            contentWidth: stagedRow.width
            contentHeight: height
            anchors.verticalCenter: parent.verticalCenter
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            Row {
              id: stagedRow
              spacing: 4
              anchors.verticalCenter: parent.verticalCenter

              Repeater {
                model: root.stagedEmojis

                Text {
                  required property var modelData
                  required property int index
                  text: modelData.glyph || ""
                  font.pixelSize: 18
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.spaceSm

          Rectangle {
            width: 22
            height: 22
            radius: Theme.radiusSm
            color: clearMa.containsMouse ? Theme.errBg : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: "×"
              font.family: Theme.displayFont
              font.pixelSize: 14
              font.bold: true
              color: clearMa.containsMouse ? Theme.err : Theme.ink3
            }

            MouseArea {
              id: clearMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.clearStaged()
            }
          }

          Rectangle {
            height: 24
            implicitWidth: pasteAllTxt.implicitWidth + 16
            radius: Theme.radiusSm
            color: pasteAllMa.containsMouse ? Theme.accentHover : Theme.accent
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: pasteAllTxt
              anchors.centerIn: parent
              text: "Paste All"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontSm
              font.weight: Font.DemiBold
              color: Theme.darkInk
            }

            MouseArea {
              id: pasteAllMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: mouse => {
                const isShift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                root.triggerSelection(null, isShift);
              }
            }
          }
        }
      }
    }

    Hairline {
      anchors.left: parent.left
      anchors.right: parent.right
    }

    // 3. Hover Preview & Detail Footer (No overlap, clean layout)
    Rectangle {
      id: previewFooter
      anchors.left: parent.left
      anchors.right: parent.right
      height: 42
      radius: Theme.radiusSm
      color: Theme.surfaceElevated
      border.color: Theme.cardBorder
      border.width: 1

      Item {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Text {
          id: previewGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.hoveredEmoji ? root.hoveredEmoji.glyph : "✨"
          font.pixelSize: 24
        }

        Column {
          id: previewDetails
          anchors.left: previewGlyph.right
          anchors.leftMargin: 12
          anchors.right: previewCode.visible ? previewCode.left : parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2

          Text {
            width: parent.width
            text: root.hoveredEmoji ? root.hoveredEmoji.name : "Select or hover an emoji to preview"
            font.family: Theme.textFont
            font.pixelSize: Theme.fontBase
            font.weight: Font.Medium
            color: Theme.ink1
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: root.hoveredEmoji !== null && !!root.hoveredEmoji.subgroup
            text: root.hoveredEmoji ? (root.hoveredEmoji.group + " • " + root.hoveredEmoji.subgroup) : ""
            font.family: Theme.textFont
            font.pixelSize: Theme.fontXs
            color: Theme.ink3
            elide: Text.ElideRight
          }
        }

        Text {
          id: previewCode
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.hoveredEmoji !== null && !!root.hoveredEmoji.code
          text: root.hoveredEmoji ? root.hoveredEmoji.code : ""
          font.family: Theme.mono
          font.pixelSize: Theme.fontSm
          color: Theme.ink3
        }
      }
    }
  }
}
