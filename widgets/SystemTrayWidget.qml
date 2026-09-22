pragma ComponentBehavior: Bound
// SystemTrayWidget.qml — System tray icons for background / minimized apps.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Item {
  id: root

  property PanelWindow barWindow: null
  property bool showPassiveInBar: false

  signal requestClosePopups()

  function closePopup(): void {
    passivePopup.visible = false;
    contextMenuPopup.visible = false;
    tooltipTimer.stop();
    trayTooltip.visible = false;
    root.hoveredItem = null;
    root.hoveredTarget = null;
  }

  // Active items count (shown directly on the bar)
  readonly property int activeCount: {
    if (!SystemTray.items) return 0;
    let cnt = 0;
    const vals = SystemTray.items.values;
    for (let i = 0; i < vals.length; i++) {
      const it = vals[i];
      if (it && (root.showPassiveInBar || it.status !== Status.Passive)) cnt++;
    }
    return cnt;
  }

  // Passive items count (accessible via chevron overflow)
  readonly property int passiveCount: {
    if (!SystemTray.items) return 0;
    if (root.showPassiveInBar) return 0;
    let cnt = 0;
    const vals = SystemTray.items.values;
    for (let i = 0; i < vals.length; i++) {
      const it = vals[i];
      if (it && it.status === Status.Passive) cnt++;
    }
    return cnt;
  }

  // Total visible dimensions
  implicitHeight: 24
  implicitWidth: contentRow.width
  height: implicitHeight
  width: implicitWidth
  visible: (activeCount > 0 || passiveCount > 0)

  // Context Menu state
  property var activeMenu: null
  property Item activeMenuTarget: null
  property bool pendingMenuOpen: false
  property int menuPopupX: 0
  property int menuPopupY: 0

  QsMenuOpener {
    id: menuOpener
    menu: root.activeMenu
    onChildrenChanged: {
      if (root.pendingMenuOpen && children && children.values.length > 0) {
        root.pendingMenuOpen = false;
        menuFallbackTimer.stop();
        contextMenuPopup.visible = true;
      }
    }
  }

  Timer {
    id: menuFallbackTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.pendingMenuOpen) {
        root.pendingMenuOpen = false;
        if (menuOpener.children && menuOpener.children.values.length > 0) {
          contextMenuPopup.visible = true;
        }
      }
    }
  }

  // Tooltip tracking state
  property SystemTrayItem hoveredItem: null
  property Item hoveredTarget: null
  property int tooltipX: 0

  Timer {
    id: tooltipTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.hoveredItem && root.hoveredTarget && !passivePopup.visible && !contextMenuPopup.visible) {
        const pt = root.hoveredTarget.mapToItem(root, 0, 0);
        root.tooltipX = root.x + pt.x + root.hoveredTarget.width / 2;
        trayTooltip.visible = true;
      }
    }
  }

  Row {
    id: contentRow
    spacing: 4
    anchors.verticalCenter: parent.verticalCenter

    // 1. Bar tray items (Active / NeedsAttention items)
    Repeater {
      id: trayRepeater
      model: SystemTray.items

      delegate: Item {
        id: delegateItem
        required property SystemTrayItem modelData
        required property int index

        readonly property SystemTrayItem item: delegateItem.modelData
        readonly property bool isPassive: item ? (item.status === Status.Passive) : false
        readonly property bool shouldShow: item ? (root.showPassiveInBar || !isPassive) : false

        visible: shouldShow
        implicitWidth: shouldShow ? 24 : 0
        implicitHeight: 24
        width: implicitWidth
        height: implicitHeight

        Rectangle {
          id: bg
          anchors.fill: parent
          radius: 6
          color: (root.activeMenuTarget === delegateItem && contextMenuPopup.visible) ? "#45475a" : (mouseArea.containsMouse ? "#3b3e52" : "transparent")
          border.color: (root.activeMenuTarget === delegateItem && contextMenuPopup.visible) ? "#89b4fa" : (mouseArea.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        IconImage {
          id: iconImg
          anchors.centerIn: parent
          width: 18
          height: 18
          asynchronous: true
          source: delegateItem.item ? delegateItem.item.icon : ""
        }

        // Fallback text if icon fails to load
        Text {
          anchors.centerIn: parent
          visible: iconImg.status === Image.Error || !delegateItem.item || !delegateItem.item.icon
          text: {
            if (!delegateItem.item) return "?";
            const s = delegateItem.item.title || delegateItem.item.id || "?";
            return s.charAt(0).toUpperCase();
          }
          color: "#cdd6f4"
          font.pixelSize: 11
          font.bold: true
          font.family: "JetBrainsMono Nerd Font Mono"
        }

        // Status indicator dot for NeedsAttention
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.bottomMargin: 2
          anchors.rightMargin: 2
          width: 5
          height: 5
          radius: 2.5
          color: "#f38ba8"
          visible: delegateItem.item ? (delegateItem.item.status === Status.NeedsAttention) : false
        }

        MouseArea {
          id: mouseArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

          onEntered: {
            if (!contextMenuPopup.visible) {
              root.hoveredItem = delegateItem.item;
              root.hoveredTarget = delegateItem;
              tooltipTimer.restart();
            }
          }

          onExited: {
            tooltipTimer.stop();
            trayTooltip.visible = false;
            if (root.hoveredTarget === delegateItem) {
              root.hoveredItem = null;
              root.hoveredTarget = null;
            }
          }

          onClicked: mouse => {
            tooltipTimer.stop();
            trayTooltip.visible = false;
            if (!delegateItem.item) return;

            if (mouse.button === Qt.LeftButton) {
              if (delegateItem.item.onlyMenu) {
                root.openItemMenu(delegateItem, delegateItem.item, false);
              } else {
                delegateItem.item.activate();
              }
            } else if (mouse.button === Qt.RightButton) {
              root.openItemMenu(delegateItem, delegateItem.item, false);
            } else if (mouse.button === Qt.MiddleButton) {
              delegateItem.item.secondaryActivate();
            }
          }

          onWheel: wheel => {
            if (delegateItem.item) {
              delegateItem.item.scroll(wheel.angleDelta.y, false);
            }
          }
        }
      }
    }

    // 2. Chevron button (appears when there are passive/hidden items)
    Item {
      id: chevronButton
      implicitWidth: root.passiveCount > 0 ? 20 : 0
      implicitHeight: 24
      width: implicitWidth
      height: implicitHeight
      visible: root.passiveCount > 0

      Rectangle {
        anchors.fill: parent
        radius: 6
        color: passivePopup.visible ? "#45475a" : (chevronMouse.containsMouse ? "#3b3e52" : "#313244")
        border.color: passivePopup.visible ? "#89b4fa" : (chevronMouse.containsMouse ? "#585b70" : "transparent")
        border.width: 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
      }

      Text {
        anchors.centerIn: parent
        text: passivePopup.visible ? "󰅀" : "󰅃"
        font.family: "JetBrainsMono Nerd Font Mono"
        font.pixelSize: 13
        color: chevronMouse.containsMouse || passivePopup.visible ? "#ffffff" : "#a6adc8"
      }

      MouseArea {
        id: chevronMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trayTooltip.visible = false;
          contextMenuPopup.visible = false;
          tooltipTimer.stop();
          if (!passivePopup.visible) {
            root.requestClosePopups();
          }
          passivePopup.visible = !passivePopup.visible;
        }
      }
    }
  }

  function openItemMenu(targetItem: Item, trayItem: SystemTrayItem, isInsidePassivePopup: bool): void {
    if (!targetItem || !trayItem) return;
    trayTooltip.visible = false;
    tooltipTimer.stop();
    root.requestClosePopups();

    if (trayItem.hasMenu && trayItem.menu) {
      if (isInsidePassivePopup) {
        const pt = targetItem.mapToItem(passiveCard, 0, 0);
        root.menuPopupX = passivePopup.anchor.rect.x + pt.x + targetItem.width / 2;
        root.menuPopupY = passivePopup.anchor.rect.y + pt.y + targetItem.height + 4;
      } else {
        const pt = targetItem.mapToItem(root, 0, 0);
        root.menuPopupX = root.x + pt.x + targetItem.width / 2;
        root.menuPopupY = root.barWindow ? (root.barWindow.implicitHeight + 6) : 38;
      }

      root.activeMenuTarget = targetItem;

      if (root.activeMenu === trayItem.menu && menuOpener.children && menuOpener.children.values.length > 0) {
        root.pendingMenuOpen = false;
        menuFallbackTimer.stop();
        contextMenuPopup.visible = true;
      } else {
        root.pendingMenuOpen = true;
        root.activeMenu = trayItem.menu;
        menuFallbackTimer.restart();
        if (menuOpener.children && menuOpener.children.values.length > 0) {
          root.pendingMenuOpen = false;
          menuFallbackTimer.stop();
          contextMenuPopup.visible = true;
        }
      }
    } else if (root.barWindow) {
      const relX = root.x + targetItem.mapToItem(root, 0, 0).x;
      trayItem.display(root.barWindow, relX, root.barWindow.height);
    }
  }

  // Hover Tooltip Popup Window
  PopupWindow {
    id: trayTooltip
    anchor.window: root.barWindow
    anchor.rect.x: root.barWindow ? Math.max(8, Math.min(root.tooltipX - tooltipBox.width / 2, root.barWindow.width - tooltipBox.width - 12)) : 0
    anchor.rect.y: root.barWindow ? (root.barWindow.implicitHeight + 6) : 38
    visible: false
    implicitWidth: tooltipBox.width
    implicitHeight: tooltipBox.height
    color: "transparent"

    Rectangle {
      id: tooltipBox
      implicitWidth: Math.max(50, tooltipCol.implicitWidth + 16)
      implicitHeight: tooltipCol.implicitHeight + 10
      radius: 10
      color: "#1F202B"
      border.color: "#2B2C3A"
      border.width: 1

      Column {
        id: tooltipCol
        anchors.centerIn: parent
        spacing: 2

        Text {
          text: {
            if (!root.hoveredItem) return "";
            return root.hoveredItem.tooltipTitle || root.hoveredItem.title || root.hoveredItem.id || "";
          }
          color: "#F1F1F6"
          font.pixelSize: 11
          font.bold: true
          font.family: "JetBrainsMono Nerd Font Mono"
        }

        Text {
          text: (root.hoveredItem && root.hoveredItem.tooltipDescription) ? root.hoveredItem.tooltipDescription : ""
          visible: text !== ""
          color: "#A6A6B8"
          font.pixelSize: 10
          font.family: "JetBrainsMono Nerd Font Mono"
        }
      }
    }
  }

  // Pure QML Context Menu Popup Window
  PopupWindow {
    id: contextMenuPopup
    anchor.window: root.barWindow
    anchor.rect.x: root.barWindow ? Math.max(8, Math.min(root.menuPopupX - contextMenuCard.implicitWidth / 2, root.barWindow.width - contextMenuCard.implicitWidth - 12)) : 0
    anchor.rect.y: root.menuPopupY
    visible: false
    grabFocus: true
    implicitWidth: contextMenuCard.implicitWidth
    implicitHeight: contextMenuCard.implicitHeight
    color: "transparent"

    onVisibleChanged: {
      if (!visible) {
        root.pendingMenuOpen = false;
        menuFallbackTimer.stop();
        root.activeMenuTarget = null;
      }
    }

    Rectangle {
      id: contextMenuCard
      implicitWidth: Math.max(160, menuCol.implicitWidth + 16)
      implicitHeight: menuCol.implicitHeight + 16
      width: implicitWidth
      height: implicitHeight
      radius: 14
      color: "#17171E"
      border.color: "#26272F"
      border.width: 1

      Column {
        id: menuCol
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 8
        spacing: 2

        Repeater {
          model: menuOpener.children

          delegate: Item {
            id: menuItem
            required property QsMenuEntry modelData
            required property int index

            readonly property QsMenuEntry entry: menuItem.modelData
            readonly property bool isSep: entry ? entry.isSeparator : false

            visible: entry ? (entry.text !== "" || isSep) : false
            implicitHeight: visible ? (isSep ? 7 : 26) : 0
            implicitWidth: visible ? (isSep ? 80 : (itemRow.implicitWidth + (entry && entry.hasChildren ? 36 : 24))) : 0
            width: parent ? parent.width : implicitWidth
            height: implicitHeight

            // Separator line
            Item {
              anchors.fill: parent
              visible: menuItem.isSep

              Rectangle {
                anchors.centerIn: parent
                width: parent.width - 8
                height: 1
                color: "#2B2C3A"
              }
            }

            // Clickable Menu Item
            Rectangle {
              anchors.fill: parent
              radius: 7
              visible: !menuItem.isSep
              color: menuMouse.containsMouse && menuItem.entry && menuItem.entry.enabled ? "#0FFFFFFF" : "transparent"

              Behavior on color { ColorAnimation { duration: 100 } }

              Row {
                id: itemRow
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Checkbox / Radio mark
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: menuItem.entry && menuItem.entry.buttonType !== QsMenuButtonType.Normal
                  text: menuItem.entry && menuItem.entry.checkState === Qt.Checked ? "✓" : " "
                  font.pixelSize: 11
                  font.bold: true
                  color: "#5E9DFF"
                }

                // Entry Icon
                IconImage {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 14
                  height: 14
                  source: menuItem.entry && menuItem.entry.icon ? menuItem.entry.icon : ""
                  visible: menuItem.entry && Boolean(menuItem.entry.icon)
                }

                // Text label
                Text {
                  id: itemLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: menuItem.entry ? menuItem.entry.text.replace(/&/g, "") : ""
                  color: menuItem.entry && menuItem.entry.enabled ? (menuMouse.containsMouse ? "#F1F1F6" : "#A6A6B8") : "#6F6F84"
                  font.pixelSize: 11
                  font.family: "JetBrainsMono Nerd Font Mono"
                }
              }

              // Submenu indicator arrow
              Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: menuMouse.containsMouse ? "#F1F1F6" : "#6F6F84"
                font.pixelSize: 13
                font.bold: true
                visible: menuItem.entry ? menuItem.entry.hasChildren : false
              }

              MouseArea {
                id: menuMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: menuItem.entry && menuItem.entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (menuItem.entry && menuItem.entry.enabled && !menuItem.isSep) {
                    contextMenuPopup.visible = false;
                    menuItem.entry.triggered();
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Passive / Hidden Items Overflow Popup Window
  PopupWindow {
    id: passivePopup
    anchor.window: root.barWindow
    anchor.rect.x: {
      if (!chevronButton.visible || !root.barWindow) return 0;
      const targetRelX = root.x + chevronButton.mapToItem(root, 0, 0).x;
      const idealX = targetRelX + chevronButton.width / 2 - passiveCard.implicitWidth / 2;
      return Math.max(8, Math.min(idealX, root.barWindow.width - passiveCard.implicitWidth - 12));
    }
    anchor.rect.y: root.barWindow ? (root.barWindow.implicitHeight + 6) : 38
    visible: false
    grabFocus: true
    implicitWidth: passiveCard.implicitWidth
    implicitHeight: passiveCard.implicitHeight
    color: "transparent"

    Rectangle {
      id: passiveCard
      implicitWidth: Math.max(140, passiveCol.implicitWidth + 24)
      implicitHeight: passiveCol.implicitHeight + 20
      radius: 14
      color: "#17171E"
      border.color: "#26272F"
      border.width: 1

      Column {
        id: passiveCol
        anchors.centerIn: parent
        spacing: 8

        Text {
          text: "Hidden Tray Icons"
          color: "#6F6F84"
          font.pixelSize: 11
          font.bold: true
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 0.8
          font.family: "JetBrainsMono Nerd Font Mono"
        }

        Row {
          spacing: 6
          Repeater {
            model: SystemTray.items
            delegate: Item {
              id: passiveDelegate
              required property SystemTrayItem modelData
              required property int index

              readonly property SystemTrayItem item: passiveDelegate.modelData
              readonly property bool isPassive: item ? (item.status === Status.Passive) : false

              visible: isPassive
              implicitWidth: isPassive ? 28 : 0
              implicitHeight: isPassive ? 28 : 0
              width: implicitWidth
              height: implicitHeight

              Rectangle {
                anchors.fill: parent
                radius: 8
                color: (root.activeMenuTarget === passiveDelegate && contextMenuPopup.visible) ? "#1AFFFFFF" : (passiveMouse.containsMouse ? "#0FFFFFFF" : "#1F202B")
                border.color: "#2B2C3A"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
              }

              IconImage {
                id: passiveIcon
                anchors.centerIn: parent
                width: 18
                height: 18
                asynchronous: true
                source: passiveDelegate.item ? passiveDelegate.item.icon : ""
              }

              Text {
                anchors.centerIn: parent
                visible: passiveIcon.status === Image.Error || !passiveDelegate.item || !passiveDelegate.item.icon
                text: {
                  if (!passiveDelegate.item) return "?";
                  const s = passiveDelegate.item.title || passiveDelegate.item.id || "?";
                  return s.charAt(0).toUpperCase();
                }
                color: "#cdd6f4"
                font.pixelSize: 11
                font.bold: true
                font.family: "JetBrainsMono Nerd Font Mono"
              }

              MouseArea {
                id: passiveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                onClicked: mouse => {
                  if (!passiveDelegate.item) return;
                  if (mouse.button === Qt.LeftButton) {
                    if (passiveDelegate.item.onlyMenu) {
                      root.openItemMenu(passiveDelegate, passiveDelegate.item, true);
                    } else {
                      passiveDelegate.item.activate();
                    }
                  } else if (mouse.button === Qt.RightButton) {
                    root.openItemMenu(passiveDelegate, passiveDelegate.item, true);
                  } else if (mouse.button === Qt.MiddleButton) {
                    passiveDelegate.item.secondaryActivate();
                  }
                }

                onWheel: wheel => {
                  if (passiveDelegate.item) {
                    passiveDelegate.item.scroll(wheel.angleDelta.y, false);
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
