pragma ComponentBehavior: Bound
// NotificationControlCenter.qml — KDE Plasma 6 style Notification Center popup.
// Features app-grouped notifications, vertical thread line styling, expandable history,
// clear all/app actions, action buttons, and individual dismissals.
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.utils

Item {
  id: root

  property var service: null
  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  signal closeRequested()

  IconResolver {
    id: iconResolver
  }

  // Resolve best matching icon for app / notification
  function resolveNotifIcon(iconName, appName, desktopEntry) {
    if (iconName) {
      const p = iconResolver.resolveNamedOrPath(iconName);
      if (p) return p;
    }
    if (desktopEntry) {
      const p = iconResolver.resolveIcon(desktopEntry, "");
      if (p) return p;
    }
    if (appName) {
      const p = iconResolver.resolveIcon(appName, "");
      if (p) return p;
    }
    return iconResolver.resolveStockIcon("preferences-desktop-notification") || iconResolver.resolveStockIcon("dialog-information") || iconResolver.fallbackIcon();
  }

  // Grouped notification list from service
  readonly property var groupedList: {
    if (service) {
      const _tick = service.timeTick;
      const _notifs = service.notifications;
      const _exp = service.expandedGroups;
      return service.getGroupedNotifications();
    }
    return [];
  }

  readonly property int totalCount: service ? ((service.notifications && service.notifications.length) || 0) : 0

  implicitWidth: 380
  implicitHeight: root.totalCount > 0 ? Math.min(480, Math.max(160, mainCol.implicitHeight + 24)) : 140
  width: implicitWidth
  height: implicitHeight

  // Card Background
  Rectangle {
    id: cardBg
    anchors.fill: parent
    color: "#1e1e2e"
    radius: 10
    border.color: "#313244"
    border.width: 1
  }

  ColumnLayout {
    id: mainCol
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      margins: 12
    }
    spacing: 10

    // ═══════════════════════════════════════════════════
    // 1. HEADER ROW: Title + Clear All
    // ═══════════════════════════════════════════════════
    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: 28
      spacing: 6

      // Section Title
      Text {
        text: "Notifications"
        font.family: root.monoFont
        font.pixelSize: 13
        font.bold: true
        color: "#cdd6f4"
      }

      Item {
        Layout.fillWidth: true
      }

      // Clear all (broom)
      Rectangle {
        Layout.preferredWidth: 24
        Layout.preferredHeight: 24
        radius: 4
        color: clearMouse.containsMouse ? "#313244" : "transparent"
        visible: root.totalCount > 0

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: "󰃢" // Broom glyph
          font.family: root.monoFont
          font.pixelSize: 14
          color: clearMouse.containsMouse ? "#89b4fa" : "#a6adc8"
        }

        MouseArea {
          id: clearMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.service) root.service.clearAll();
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════
    // 2. DIVIDER
    // ═══════════════════════════════════════════════════
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: "#313244"
    }

    // ═══════════════════════════════════════════════════
    // 3. EMPTY STATE (When no notifications)
    // ═══════════════════════════════════════════════════
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 70
      visible: root.totalCount === 0

      ColumnLayout {
        anchors.centerIn: parent
        spacing: 6

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "󰂚"
          font.family: root.monoFont
          font.pixelSize: 28
          color: "#45475a"
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "No Notifications"
          font.family: root.monoFont
          font.pixelSize: 12
          font.bold: true
          color: "#a6adc8"
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "You're all caught up"
          font.family: root.monoFont
          font.pixelSize: 10
          color: "#6c7086"
        }
      }
    }

    // ═══════════════════════════════════════════════════
    // 4. NOTIFICATION GROUPS LIST (Flickable + ColumnLayout)
    // ═══════════════════════════════════════════════════
    Flickable {
      id: flickView
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(400, contentCol.implicitHeight)
      contentWidth: width
      contentHeight: contentCol.implicitHeight
      clip: true
      visible: root.totalCount > 0
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: contentCol
        width: flickView.width
        spacing: 14

        Repeater {
          model: root.groupedList

          delegate: Item {
            id: groupDelegate
            required property var modelData
            required property int index

            readonly property var group: groupDelegate.modelData
            readonly property string appName: group ? (group.appName || "Application") : "Application"
            readonly property string appIcon: group ? (group.appIcon || "") : ""
            readonly property var notifsList: group ? (group.notifications || []) : []
            readonly property int totalGroupCount: group ? (group.totalCount || 0) : 0
            readonly property bool isExpanded: group ? (group.expanded === true) : false

            // Slice to 2 items if not expanded
            readonly property var visibleItems: isExpanded ? notifsList : notifsList.slice(0, 2)

            // Resolve icon source via IconResolver
            readonly property string resolvedIcon: root.resolveNotifIcon(appIcon, appName, "")

            Layout.fillWidth: true
            implicitHeight: groupCol.implicitHeight
            height: implicitHeight

            ColumnLayout {
              id: groupCol
              anchors {
                left: parent.left
                right: parent.right
                top: parent.top
              }
              spacing: 8

              // --- App Header Row ---
              RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                spacing: 8

                // App Icon
                IconImage {
                  id: appIconImg
                  Layout.preferredWidth: 18
                  Layout.preferredHeight: 18
                  source: groupDelegate.resolvedIcon
                  asynchronous: true
                }

                // Fallback letter if icon unavailable
                Text {
                  visible: appIconImg.status === Image.Error || !groupDelegate.resolvedIcon
                  text: groupDelegate.appName.charAt(0).toUpperCase()
                  font.family: root.monoFont
                  font.pixelSize: 11
                  font.bold: true
                  color: "#89b4fa"
                }

                // App Name
                Text {
                  Layout.fillWidth: true
                  text: groupDelegate.appName
                  font.family: root.monoFont
                  font.pixelSize: 12
                  font.bold: true
                  color: "#cdd6f4"
                  elide: Text.ElideRight
                }

                // App Clear Button (Red Circle with X)
                Rectangle {
                  Layout.preferredWidth: 18
                  Layout.preferredHeight: 18
                  radius: 9
                  color: appClearMouse.containsMouse ? "#f38ba8" : "#eb4d4b"

                  Behavior on color { ColorAnimation { duration: 100 } }

                  Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.family: root.monoFont
                    font.pixelSize: 9
                    font.bold: true
                    color: "#ffffff"
                  }

                  MouseArea {
                    id: appClearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.service) root.service.clearApp(groupDelegate.appName);
                    }
                  }
                }
              }

              // --- Notification Items List ---
              Column {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                  model: groupDelegate.visibleItems

                  delegate: Item {
                    id: notifItem
                    required property var modelData
                    required property int index

                    readonly property var notif: notifItem.modelData
                    readonly property string summaryText: notif ? (notif.summary || "Notification") : ""
                    readonly property string bodyText: notif ? (notif.body || "") : ""
                    readonly property string imageSrc: notif ? (notif.image || "") : ""
                    readonly property var actionsList: notif ? (notif.actions || []) : []
                    readonly property string timeStr: root.service ? root.service.timeAgo(notif.timestamp) : "Just now"
                    readonly property int urgencyVal: notif ? (notif.urgency || 1) : 1

                    width: parent.width
                    implicitHeight: notifContentCol.implicitHeight + 4
                    height: implicitHeight

                    MouseArea {
                      id: itemHoverArea
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.NoButton
                    }

                    // Vertical Thread Accent Line (KDE Plasma 6 style)
                    Rectangle {
                      id: threadLine
                      width: 3
                      anchors {
                        left: parent.left
                        leftMargin: 4
                        top: parent.top
                        bottom: parent.bottom
                        topMargin: 2
                        bottomMargin: 2
                      }
                      radius: 1.5
                      color: notifItem.urgencyVal === 2 ? "#f38ba8" : (itemHoverArea.containsMouse ? "#89b4fa" : "#45475a")

                      Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    // Notification Content Column
                    ColumnLayout {
                      id: notifContentCol
                      anchors {
                        left: threadLine.right
                        leftMargin: 10
                        right: parent.right
                        top: parent.top
                      }
                      spacing: 3

                      // Summary + Timestamp + Close Row
                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                          Layout.fillWidth: true
                          text: notifItem.summaryText
                          font.family: root.monoFont
                          font.pixelSize: 12
                          font.bold: true
                          color: "#ffffff"
                          elide: Text.ElideRight
                        }

                        Text {
                          text: notifItem.timeStr
                          font.family: root.monoFont
                          font.pixelSize: 10
                          color: "#a6adc8"
                        }

                        // Individual Close Button (Red Circle with X)
                        Rectangle {
                          Layout.preferredWidth: 16
                          Layout.preferredHeight: 16
                          radius: 8
                          color: itemCloseMouse.containsMouse ? "#f38ba8" : "#eb4d4b"

                          Behavior on color { ColorAnimation { duration: 100 } }

                          Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: root.monoFont
                            font.pixelSize: 8
                            font.bold: true
                            color: "#ffffff"
                          }

                          MouseArea {
                            id: itemCloseMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (root.service) root.service.dismissNotification(notifItem.notif.id);
                            }
                          }
                        }
                      }

                      // Body Text (if present)
                      Text {
                        visible: notifItem.bodyText.length > 0
                        Layout.fillWidth: true
                        text: notifItem.bodyText
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#bac2de"
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                      }

                      // Attached Image (if present)
                      Rectangle {
                        visible: notifItem.imageSrc.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(80, width * 0.45)
                        radius: 6
                        color: "#181825"
                        clip: true

                        Image {
                          anchors.fill: parent
                          source: notifItem.imageSrc
                          fillMode: Image.PreserveAspectCrop
                          asynchronous: true
                        }
                      }

                      // Action Buttons Row (e.g. "View", "Open", etc.)
                      RowLayout {
                        visible: notifItem.actionsList.length > 0
                        Layout.fillWidth: true

                        Item {
                          Layout.fillWidth: true
                        }

                        Repeater {
                          model: notifItem.actionsList

                          delegate: Rectangle {
                            id: actionBtn
                            required property var modelData
                            required property int index

                            implicitWidth: actionLabel.implicitWidth + 20
                            implicitHeight: 24
                            radius: 4
                            color: actionMouse.containsMouse ? "#3b3e52" : "#2b2d3d"
                            border.color: actionMouse.containsMouse ? "#89b4fa" : "#45475a"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Text {
                              id: actionLabel
                              anchors.centerIn: parent
                              text: actionBtn.modelData.text || "Action"
                              font.family: root.monoFont
                              font.pixelSize: 11
                              color: actionMouse.containsMouse ? "#ffffff" : "#cdd6f4"
                            }

                            MouseArea {
                              id: actionMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                if (root.service) {
                                  root.service.invokeAction(notifItem.notif, actionBtn.modelData.identifier);
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

              // --- Group Footer: "Show X More" / "Show Less" ---
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                visible: groupDelegate.totalGroupCount > 2

                RowLayout {
                  anchors.left: parent.left
                  anchors.leftMargin: 16
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 4

                  Text {
                    text: groupDelegate.isExpanded ? "󰅃" : "󰅀"
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: showMoreMouse.containsMouse ? "#b4befe" : "#89b4fa"
                  }

                  Text {
                    text: groupDelegate.isExpanded ? "Show Less" : (`Show ${groupDelegate.totalGroupCount - 2} More`)
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: showMoreMouse.containsMouse ? "#b4befe" : "#89b4fa"
                  }
                }

                MouseArea {
                  id: showMoreMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.service) {
                      root.service.toggleGroupExpanded(groupDelegate.appName);
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
}
