pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../theme"

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

  implicitHeight: 24
  implicitWidth: contentRow.width
  height: implicitHeight
  width: implicitWidth
  visible: (activeCount > 0 || passiveCount > 0)

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

  property SystemTrayItem hoveredItem: null
  property Item hoveredTarget: null
  property int tooltipX: 0

  Timer {
    id: tooltipTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.hoveredItem && root.hoveredTarget && !passivePopup.visible && !contextMenuPopup.visible) {
        if (root.hoveredTarget.Window && root.hoveredTarget.Window.window && root.hoveredTarget.Window.window.screen) {
          trayTooltip.screen = root.hoveredTarget.Window.window.screen;
        }
        trayTooltip.anchor.item = root.hoveredTarget;
        trayTooltip.visible = true;
        trayTooltip.anchor.updateAnchor();
      }
    }
  }

  Row {
    id: contentRow
    spacing: 4
    anchors.verticalCenter: parent.verticalCenter

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
        implicitWidth: shouldShow ? Theme.btnHeightSm : 0
        implicitHeight: Theme.btnHeightSm
        width: implicitWidth
        height: implicitHeight

        Rectangle {
          id: bg
          anchors.fill: parent
          radius: Theme.radiusSm
          color: (root.activeMenuTarget === delegateItem && contextMenuPopup.visible) ? Theme.selected : (mouseArea.containsMouse ? Theme.hoverFill : "transparent")
          border.width: 0

          Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        }

        IconImage {
          id: iconImg
          anchors.centerIn: parent
          width: 20
          height: 20
          asynchronous: true
          source: delegateItem.item ? delegateItem.item.icon : ""
        }

        Text {
          anchors.centerIn: parent
          visible: iconImg.status === Image.Error || !delegateItem.item || !delegateItem.item.icon
          text: {
            if (!delegateItem.item) return "?";
            const s = delegateItem.item.title || delegateItem.item.id || "?";
            return s.charAt(0).toUpperCase();
          }
          color: Theme.ink1
          font.pixelSize: Theme.fontSm
          font.bold: true
          font.family: Theme.roundedFont
        }

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.bottomMargin: 2
          anchors.rightMargin: 2
          width: 5
          height: 5
          radius: 2.5
          color: Theme.red
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

    Item {
      id: chevronButton
      implicitWidth: root.passiveCount > 0 ? 20 : 0
      implicitHeight: Theme.btnHeightSm
      width: implicitWidth
      height: implicitHeight
      visible: root.passiveCount > 0

      Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: passivePopup.visible ? Theme.selected : (chevronMouse.containsMouse ? Theme.hoverFill : Theme.surface)
        border.width: 0

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
      }

      Text {
        anchors.centerIn: parent
        text: passivePopup.visible ? "󰅀" : "󰅃"
        font.family: Theme.mono
        font.pixelSize: Theme.fontGlyphMd
        color: chevronMouse.containsMouse || passivePopup.visible ? Theme.ink1 : Theme.ink2
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
        const pt = targetItem.mapToItem(null, 0, 0);
        root.menuPopupX = pt.x + targetItem.width / 2;
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
      const relX = targetItem.mapToItem(null, 0, 0).x;
      trayItem.display(root.barWindow, relX, root.barWindow.height);
    }
  }

  PopupWindow {
    id: trayTooltip
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6
    anchor.adjustment: PopupAdjustment.SlideX
    visible: false
    implicitWidth: tooltipBox.implicitWidth
    implicitHeight: tooltipBox.implicitHeight
    color: "transparent"

    Rectangle {
      id: tooltipBox
      implicitWidth: Math.max(50, tooltipCol.implicitWidth + 16)
      implicitHeight: tooltipCol.implicitHeight + 10
      width: implicitWidth
      height: implicitHeight
      radius: Theme.radiusChip
      color: Theme.surface
      border.color: Theme.line
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
          color: Theme.ink1
          font.pixelSize: Theme.fontSm
          font.weight: Font.Medium
          font.family: Theme.textFont
        }

        Text {
          text: (root.hoveredItem && root.hoveredItem.tooltipDescription) ? root.hoveredItem.tooltipDescription : ""
          visible: text !== ""
          color: Theme.ink2
          font.pixelSize: Theme.fontXs
          font.family: Theme.textFont
        }
      }
    }
  }

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
      radius: Theme.radiusCard
      color: Theme.bg
      border.color: Theme.cardBorder
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

            Item {
              anchors.fill: parent
              visible: menuItem.isSep

              Rectangle {
                anchors.centerIn: parent
                width: parent.width - 8
                height: 1
                color: Theme.line
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: 7
              visible: !menuItem.isSep
              color: menuMouse.containsMouse && menuItem.entry && menuItem.entry.enabled ? Theme.hoverWash : "transparent"

              Behavior on color { ColorAnimation { duration: Theme.durationFast } }

              Row {
                id: itemRow
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: menuItem.entry && menuItem.entry.buttonType !== QsMenuButtonType.Normal
                  text: menuItem.entry && menuItem.entry.checkState === Qt.Checked ? "✓" : " "
                  font.pixelSize: Theme.fontSm
                  font.bold: true
                  color: Theme.accent
                }

                IconImage {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 14
                  height: 14
                  source: menuItem.entry && menuItem.entry.icon ? menuItem.entry.icon : ""
                  visible: menuItem.entry && Boolean(menuItem.entry.icon)
                }

                Text {
                  id: itemLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: menuItem.entry ? menuItem.entry.text.replace(/&/g, "") : ""
                  color: menuItem.entry && menuItem.entry.enabled ? (menuMouse.containsMouse ? Theme.ink1 : Theme.ink2) : Theme.ink3
                  font.pixelSize: Theme.fontSm
                  font.family: Theme.textFont
                }
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: menuMouse.containsMouse ? Theme.ink1 : Theme.ink3
                font.pixelSize: Theme.fontMd
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

  PopupWindow {
    id: passivePopup
    anchor.window: root.barWindow
    anchor.rect.x: {
      if (!chevronButton.visible || !root.barWindow) return 0;
      const targetX = chevronButton.mapToItem(null, 0, 0).x;
      const idealX = targetX + chevronButton.width / 2 - passiveCard.implicitWidth / 2;
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
      radius: Theme.radiusCard
      color: Theme.bg
      border.color: Theme.cardBorder
      border.width: 1

      Column {
        id: passiveCol
        anchors.centerIn: parent
        spacing: 8

        Text {
          text: "Hidden Tray Icons"
          color: Theme.ink3
          font.pixelSize: Theme.fontSm
          font.bold: true
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 0.8
          font.family: Theme.textFont
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
                radius: Theme.radiusBase
                color: (root.activeMenuTarget === passiveDelegate && contextMenuPopup.visible) ? Theme.selected : (passiveMouse.containsMouse ? Theme.hoverWash : Theme.surface)
                border.width: 0

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
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
                color: Theme.ink1
                font.pixelSize: Theme.fontSm
                font.bold: true
                font.family: Theme.roundedFont
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
