pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"

/* A layer-shell surface on the Top layer: KWin keeps it out of the taskbar,
   pager and Alt-Tab, and activates it when keyboardFocus flips None->OnDemand.
   Quickshell deletes layer windows on hide, so the surface is rebuilt on every
   show and focus must be re-earned each time via the arm timer. */
PanelWindow {
  id: win

  property var launcher: null

  readonly property int screenW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920
  readonly property int screenH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080
  readonly property real sideMargin: Math.max(24, (screenW - Theme.launcherWidth) / 2)
  readonly property real topMargin: Math.round(screenH * 0.14)

  visible: win.launcher !== null && win.launcher.isOpen
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  anchors {
    left: true
    right: true
    top: true
  }
  margins { // qmllint disable unqualified
    left: sideMargin
    right: sideMargin
    top: topMargin
  }

  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "quickshell-launcher"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  implicitHeight: card.implicitHeight

  function handleFocusLost(): void {
    if (!win.visible) return;
    if (win.launcher) win.launcher.notifyFocusLost();
  }

  onVisibleChanged: {
    if (visible) {
      field.text = "";
      armTimer.restart();
    } else {
      armTimer.stop();
      win.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
    }
  }

  // Flip to OnDemand one frame after show so KWin evaluates the transition
  // with a buffer already attached. Reused for the re-arm path.
  Timer {
    id: armTimer
    interval: 50
    repeat: false
    onTriggered: {
      win.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand;
      field.forceActiveFocus();
    }
  }

  Connections {
    target: win.launcher
    function onRefocusRequested(): void {
      win.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
      armTimer.restart();
    }
    function onSelectedIndexChanged(): void {
      if (win.launcher && list.count > 0) {
        list.positionViewAtIndex(win.launcher.selectedIndex, ListView.Contain);
      }
    }
    function onRowsChanged(): void {
      if (win.launcher && list.count > 0) {
        list.positionViewAtIndex(win.launcher.selectedIndex, ListView.Contain);
      }
    }
  }

  /* NOTE: Keys must live on an Item, not on the PanelWindow root.
     Attaching Keys to the window logs "Could not attach Keys property
     ... is not an Item" and silently drops every shortcut. The real
     handler is on the search field below. */

  Rectangle {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    implicitHeight: col.implicitHeight + Theme.launcherCardPadY * 2 + 2

    color: Theme.surface
    border.color: Theme.cardBorder
    border.width: 1
    radius: Theme.radiusCard

    Column {
      id: col
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Theme.cardPadding
      anchors.rightMargin: Theme.cardPadding
      anchors.topMargin: Theme.launcherCardPadY
      spacing: Theme.spaceSm

      Item {
        id: searchRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.launcherContentInset - Theme.fieldPadX
        anchors.rightMargin: Theme.launcherContentInset - Theme.fieldPadX
        height: 40

        // Behind the field: clicks on empty padding focus it.
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onClicked: field.forceActiveFocus()
        }

        TextInput {
          id: field
          anchors.fill: parent
          anchors.leftMargin: Theme.fieldPadX
          anchors.rightMargin: Theme.fieldPadX
          verticalAlignment: TextInput.AlignVCenter
          font.family: field.text.trim().startsWith(">") ? Theme.mono : Theme.displayFont
          font.pixelSize: Theme.fontXl
          color: Theme.ink1
          selectionColor: Theme.accent
          selectedTextColor: Theme.ink1
          selectByMouse: true
          maximumLength: 256
          focus: true
          inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
          onTextEdited: {
            if (win.launcher) win.launcher.setQuery(field.text);
          }
          onActiveFocusChanged: {
            if (!field.activeFocus) win.handleFocusLost();
          }

          Keys.onPressed: event => {
            if (!win.launcher || field.inputMethodComposing) return;
            switch (event.key) {
            case Qt.Key_Up:
              win.launcher.moveSelection(-1);
              event.accepted = true;
              break;
            case Qt.Key_Down:
              win.launcher.moveSelection(1);
              event.accepted = true;
              break;
            case Qt.Key_PageUp:
              win.launcher.movePage(-1);
              event.accepted = true;
              break;
            case Qt.Key_PageDown:
              win.launcher.movePage(1);
              event.accepted = true;
              break;
            case Qt.Key_Home:
              win.launcher.goFirst();
              event.accepted = true;
              break;
            case Qt.Key_End:
              win.launcher.goLast();
              event.accepted = true;
              break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
              {
                const isCtrl = (event.modifiers & Qt.ControlModifier) !== 0;
                const isShift = (event.modifiers & Qt.ShiftModifier) !== 0;
                if (isCtrl && isShift) {
                  win.launcher.activateSelected("terminal");
                } else if (isShift) {
                  win.launcher.activateSelected("shift");
                } else {
                  win.launcher.activateSelected("default");
                }
                event.accepted = true;
              }
              break;
            case Qt.Key_Escape:
              win.launcher.close();
              event.accepted = true;
              break;
            case Qt.Key_Tab:
              // Reserved for the action panel.
              event.accepted = true;
              break;
            case Qt.Key_C:
              if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
                if (win.launcher && win.launcher.openWithSelected()) {
                  win.launcher.close();
                  event.accepted = true;
                }
              } else if ((event.modifiers & Qt.ControlModifier) && field.selectedText.length === 0) {
                if (win.launcher && win.launcher.copySelectedFile()) {
                  win.launcher.close();
                  event.accepted = true;
                }
              }
              break;
            default:
              if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K) {
                // Reserved for the action panel.
                event.accepted = true;
              }
              break;
            }
          }
        }

        Text {
          anchors.fill: field
          verticalAlignment: Text.AlignVCenter
          visible: field.text.length === 0
          text: "Search applications, f <file>, paths, or > command..."
          font.family: Theme.displayFont
          font.pixelSize: Theme.fontXl
          color: Theme.ink3
          elide: Text.ElideRight
        }
      }

      Hairline {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.launcherContentInset
        anchors.rightMargin: Theme.launcherContentInset
      }

      ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(count, Theme.launcherMaxVisible) * Theme.launcherRowHeight
        visible: count > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        model: ScriptModel {
          values: win.launcher ? win.launcher.rows : []
          objectProp: "id"
          comparisonMode: ObjectComparison.Identity
        }

        /* The highlight derives directly from the service's selectedIndex,
           never from ListView.currentIndex, so it cannot desync from the
           actual selection when the model is replaced each keystroke. */
        delegate: LauncherRow {
          isCurrent: win.launcher ? index === win.launcher.selectedIndex : false
          launcher: win.launcher
        }
      }

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.launcherContentInset
        anchors.rightMargin: Theme.launcherContentInset
        visible: list.count === 0
        horizontalAlignment: Text.AlignHCenter
        text: {
          if (!win.launcher) return "No matching applications or paths";
          const q = win.launcher.query.trim();
          if (q.startsWith(">")) return "Type a shell command to execute...";
          if (win.launcher.isFileSearchActive) {
            return win.launcher.isFileSearching ? "Searching files..." : "No matching files or folders";
          }
          return "No matching applications or paths";
        }
        font.family: Theme.textFont
        font.pixelSize: Theme.fontBase
        color: Theme.ink3
      }

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.launcherContentInset
        anchors.rightMargin: Theme.launcherContentInset
        horizontalAlignment: Text.AlignHCenter
        text: {
          const sel = win.launcher && win.launcher.selectedIndex >= 0
            ? win.launcher.rows[win.launcher.selectedIndex]
            : null;
          if (!sel) return "↑↓ navigate · esc close";
          if (sel.kind === "command") {
            return "↵ run in terminal · ⇧↵ run in background · esc close";
          }
          if (sel.kind === "file" || sel.kind === "path") {
            return (sel.isDir ? "↵ open folder" : "↵ open file")
              + " · ⇧↵ dolphin · ⌃⇧↵ terminal · ⌃C copy · ⌃⇧C open with · esc close";
          }
          return "↵ open · ⇧↵ terminal · ↑↓ navigate · esc close";
        }
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSm
        color: Theme.ink3
      }
    }
  }
}
