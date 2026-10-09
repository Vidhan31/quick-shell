pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../theme"
import "../components"

/* A layer-shell surface on the Top layer: KWin keeps it out of the taskbar,
   pager and Alt-Tab, and activates it when keyboardFocus flips None->OnDemand.
   Quickshell deletes layer windows on hide, so the surface is rebuilt on every
   show and focus must be re-earned each time via the arm timer. */
PanelWindow {
  id: win

  property var launcher: null
  property int pinnedIndex: -1

  readonly property var shortcuts: {
    const l = win.launcher;
    if (win.pinnedIndex >= 0 && l && l.dockItems && win.pinnedIndex < l.dockItems.length) {
      const item = l.dockItems[win.pinnedIndex];
      if (item && item.isRunning) {
        return [
          { key: "↵", label: "switch" },
          { key: "←→", label: "cycle" },
          { key: "↓", label: "list" },
          { key: "Esc", label: "close" }
        ];
      }
      return [
        { key: "↵", label: "open" },
        { key: "⇧↵", label: "terminal" },
        { key: "←→", label: "cycle" },
        { key: "↓", label: "list" },
        { key: "Esc", label: "close" }
      ];
    }
    const sel = l && l.selectedIndex >= 0 && l.rows && l.selectedIndex < l.rows.length
      ? l.rows[l.selectedIndex]
      : null;
    if (!sel) {
      return [
        { key: "↑↓", label: "navigate" },
        { key: "Esc", label: "close" }
      ];
    }
    if (sel.kind === "command") {
      return [
        { key: "↵", label: "run in terminal" },
        { key: "⇧↵", label: "run in background" },
        { key: "Esc", label: "close" }
      ];
    }
    if (sel.kind === "file" || sel.kind === "path") {
      return [
        { key: "↵", label: sel.isDir ? "open folder" : "open file" },
        { key: "⇧↵", label: "dolphin" },
        { key: "Ctrl+⇧+↵", label: "terminal" },
        { key: "Ctrl+C", label: "copy" },
        { key: "Ctrl+⇧+C", label: "open with" },
        { key: "Esc", label: "close" }
      ];
    }
    return [
      { key: "↵", label: "open" },
      { key: "⇧↵", label: "terminal" },
      { key: "↑↓", label: "navigate" },
      { key: "Esc", label: "close" }
    ];
  }

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

  BackgroundEffect.blurRegion: Region {
    item: card // qmllint disable unqualified
    radius: Theme.radiusCard
  }

  implicitHeight: card.implicitHeight

  function handleFocusLost(): void {
    if (!win.visible) return;
    if (win.launcher) win.launcher.notifyFocusLost();
  }

  onVisibleChanged: {
    if (visible) {
      field.text = "";
      if (win.launcher) {
        win.launcher.setQuery("");
        win.pinnedIndex = (win.launcher.dockItems && win.launcher.dockItems.length > 0) ? 0 : -1;
      } else {
        win.pinnedIndex = -1;
      }
      armTimer.restart();
    } else {
      armTimer.stop();
      win.pinnedIndex = -1;
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
    function onDockItemsChanged(): void {
      if (field.text.length === 0 && win.launcher) {
        if (!win.launcher.dockItems || win.launcher.dockItems.length === 0) {
          win.pinnedIndex = -1;
        } else if (win.pinnedIndex < 0 || win.pinnedIndex >= win.launcher.dockItems.length) {
          win.pinnedIndex = 0;
        }
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

    color: Theme.tint(Theme.surface, 0.75)
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
            if (field.text.length > 0) {
              win.pinnedIndex = -1;
            } else {
              win.pinnedIndex = (win.launcher && win.launcher.dockItems && win.launcher.dockItems.length > 0) ? 0 : -1;
            }
            if (win.launcher) {
              win.launcher.setQuery(field.text);
              if (field.text.length > 0) {
                win.launcher.selectedIndex = 0;
              }
            }
          }
          onActiveFocusChanged: {
            if (!field.activeFocus) win.handleFocusLost();
          }

          Keys.onPressed: event => {
            if (!win.launcher || field.inputMethodComposing) return;
            switch (event.key) {
            case Qt.Key_Right:
              if (field.text.length === 0 && win.launcher && win.launcher.dockItems && win.launcher.dockItems.length > 0) {
                if (win.pinnedIndex < 0) {
                  win.pinnedIndex = 0;
                } else {
                  win.pinnedIndex = (win.pinnedIndex + 1) % win.launcher.dockItems.length;
                }
                event.accepted = true;
              }
              break;
            case Qt.Key_Left:
              if (field.text.length === 0 && win.launcher && win.launcher.dockItems && win.launcher.dockItems.length > 0) {
                if (win.pinnedIndex < 0) {
                  win.pinnedIndex = win.launcher.dockItems.length - 1;
                } else {
                  win.pinnedIndex = (win.pinnedIndex - 1 + win.launcher.dockItems.length) % win.launcher.dockItems.length;
                }
                event.accepted = true;
              }
              break;
            case Qt.Key_Up:
              if (win.pinnedIndex >= 0) {
                event.accepted = true;
              } else if (win.launcher && win.launcher.selectedIndex === 0 && field.text.length === 0 && win.launcher.dockItems && win.launcher.dockItems.length > 0) {
                win.pinnedIndex = 0;
                event.accepted = true;
              } else {
                win.launcher.moveSelection(-1);
                event.accepted = true;
              }
              break;
            case Qt.Key_Down:
              if (win.pinnedIndex >= 0) {
                win.pinnedIndex = -1;
                if (win.launcher) win.launcher.selectedIndex = 0;
                event.accepted = true;
              } else {
                win.launcher.moveSelection(1);
                event.accepted = true;
              }
              break;
            case Qt.Key_PageUp:
              if (win.pinnedIndex >= 0) {
                event.accepted = true;
              } else {
                win.launcher.movePage(-1);
                event.accepted = true;
              }
              break;
            case Qt.Key_PageDown:
              if (win.pinnedIndex >= 0) {
                event.accepted = true;
              } else {
                win.launcher.movePage(1);
                event.accepted = true;
              }
              break;
            case Qt.Key_Home:
              if (win.pinnedIndex >= 0) {
                win.pinnedIndex = 0;
                event.accepted = true;
              } else {
                win.launcher.goFirst();
                event.accepted = true;
              }
              break;
            case Qt.Key_End:
              if (win.pinnedIndex >= 0 && win.launcher && win.launcher.dockItems) {
                win.pinnedIndex = Math.max(0, win.launcher.dockItems.length - 1);
                event.accepted = true;
              } else {
                win.launcher.goLast();
                event.accepted = true;
              }
              break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
              {
                const isCtrl = (event.modifiers & Qt.ControlModifier) !== 0;
                const isShift = (event.modifiers & Qt.ShiftModifier) !== 0;
                if (win.pinnedIndex >= 0 && win.launcher && win.launcher.dockItems && win.pinnedIndex < win.launcher.dockItems.length) {
                  win.launcher.launchPinned(win.pinnedIndex, (isCtrl && isShift) ? "terminal" : (isShift ? "shift" : "default"));
                  event.accepted = true;
                  break;
                }
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
            case Qt.Key_P:
              if ((event.modifiers & Qt.ControlModifier) && win.launcher) {
                if (win.pinnedIndex >= 0 && win.launcher.dockItems && win.pinnedIndex < win.launcher.dockItems.length) {
                  const targetItem = win.launcher.dockItems[win.pinnedIndex];
                  if (targetItem && targetItem.isPinned) {
                    win.launcher.unpinApp(targetItem.id);
                    if (win.launcher.dockItems.length === 0) {
                      win.pinnedIndex = -1;
                    } else if (win.pinnedIndex >= win.launcher.dockItems.length) {
                      win.pinnedIndex = win.launcher.dockItems.length - 1;
                    }
                  }
                } else {
                  win.launcher.toggleSelectedPin();
                }
                event.accepted = true;
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

      Item {
        id: pinnedSection
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.launcherContentInset
        anchors.rightMargin: Theme.launcherContentInset
        height: 40
        visible: win.launcher && win.launcher.dockItems && win.launcher.dockItems.length > 0 && field.text.length === 0

        Row {
          id: pinnedRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.spaceSm

          Repeater {
            model: win.launcher ? win.launcher.dockItems : []

            Rectangle {
              id: pinTile
              required property var modelData
              required property int index

              width: 36
              height: 36
              radius: Theme.radiusBase
              anchors.verticalCenter: parent.verticalCenter

              readonly property bool isSelected: win.pinnedIndex === pinTile.index
              readonly property bool isHovered: tileMa.containsMouse

              color: pinTile.isSelected ? Theme.selected : (pinTile.isHovered ? Theme.hoverFill : "transparent")

              Behavior on color { ColorAnimation { duration: Theme.durationFast } }

              MouseArea {
                id: tileMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                  if (!win.launcher) return;
                  if (mouse.button === Qt.RightButton && pinTile.modelData.isPinned) {
                    win.launcher.unpinApp(pinTile.modelData.id);
                    if (win.launcher.dockItems.length === 0) {
                      win.pinnedIndex = -1;
                    } else if (win.pinnedIndex >= win.launcher.dockItems.length) {
                      win.pinnedIndex = win.launcher.dockItems.length - 1;
                    }
                    field.forceActiveFocus();
                    return;
                  }
                  win.launcher.launchPinned(pinTile.index, mouse.modifiers & Qt.ShiftModifier ? "shift" : "default");
                }
              }

              IconImage {
                id: pinIcon
                anchors.centerIn: parent
                implicitSize: Theme.launcherIconSize
                asynchronous: true
                source: pinTile.modelData.iconSrc || ""
                opacity: pinTile.modelData.isMinimized ? 0.75 : 1.0
              }

              Text {
                anchors.centerIn: parent
                visible: pinIcon.status === Image.Error || !pinTile.modelData.iconSrc
                text: (pinTile.modelData.name || "?").charAt(0).toUpperCase()
                color: Theme.ink1
                font.family: Theme.roundedFont
                font.pixelSize: Theme.fontSm
                font.bold: true
              }

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: pinTile.modelData.isActive ? 14 : 4
                height: pinTile.modelData.isActive ? 3 : 4
                radius: pinTile.modelData.isActive ? 1.5 : 2
                color: pinTile.modelData.isActive ? Theme.accent : Theme.ink2
                visible: !!pinTile.modelData.isRunning

                Behavior on width { NumberAnimation { duration: Theme.durationFast } }
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
              }

              Rectangle {
                id: unpinBadge
                z: 10
                width: 16
                height: 16
                radius: 8
                anchors.top: parent.top
                anchors.topMargin: -3
                anchors.right: parent.right
                anchors.rightMargin: -3
                color: unpinMa.containsMouse ? Theme.red : Theme.surfaceElevated
                border.color: Theme.line
                border.width: 1
                visible: pinTile.modelData.isPinned && (pinTile.isHovered || unpinMa.containsMouse)

                Text {
                  anchors.centerIn: parent
                  text: "×"
                  font.family: Theme.displayFont
                  font.pixelSize: 12
                  font.bold: true
                  color: unpinMa.containsMouse ? Theme.ink1 : Theme.ink2
                }

                MouseArea {
                  id: unpinMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  preventStealing: true
                  onClicked: mouse => {
                    mouse.accepted = true;
                    if (win.launcher && pinTile.modelData.isPinned) {
                      win.launcher.unpinApp(pinTile.modelData.id);
                      if (win.launcher.dockItems.length === 0) {
                        win.pinnedIndex = -1;
                      } else if (win.pinnedIndex >= win.launcher.dockItems.length) {
                        win.pinnedIndex = win.launcher.dockItems.length - 1;
                      }
                    }
                    field.forceActiveFocus();
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
        anchors.leftMargin: Theme.launcherContentInset
        anchors.rightMargin: Theme.launcherContentInset
        visible: pinnedSection.visible
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
          isCurrent: win.launcher ? (win.pinnedIndex < 0 && index === win.launcher.selectedIndex) : false
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
        topPadding: Theme.spaceLg
        bottomPadding: Theme.spaceLg
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

      Hairline {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.launcherContentInset
        anchors.rightMargin: Theme.launcherContentInset
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spaceLg

        Repeater {
          model: win.shortcuts

          Row {
            id: shortcutItem
            required property var modelData

            spacing: Theme.spaceXs
            anchors.verticalCenter: parent.verticalCenter

            Kbd {
              text: shortcutItem.modelData.key
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: shortcutItem.modelData.label
              anchors.verticalCenter: parent.verticalCenter
              font.family: Theme.textFont
              font.pixelSize: Theme.fontSm
              color: Theme.ink3
            }
          }
        }
      }
    }
  }
}
