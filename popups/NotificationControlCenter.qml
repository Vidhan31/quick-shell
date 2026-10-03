pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.utils
import "../theme"
import "../components"

Item {
  id: root

  property var service: null
  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  signal closeRequested()

  IconResolver {
    id: iconResolver
  }

  function resolveActionIcon(identifier) {
    if (!identifier) return "";
    return iconResolver.resolveNamedOrPath(identifier);
  }

  function resolveAppIcon(desktopEntry, appName, fallbackIcon) {
    if (desktopEntry) {
      const p = iconResolver.resolveIcon(desktopEntry, "");
      if (p) return p;
    }
    if (appName) {
      const p = iconResolver.resolveIcon(appName, "");
      if (p) return p;
    }
    if (fallbackIcon) {
      const p = iconResolver.resolveNamedOrPath(fallbackIcon);
      if (p) return p;
    }
    return iconResolver.resolveStockIcon("preferences-desktop-notification") || iconResolver.resolveStockIcon("dialog-information") || iconResolver.fallbackIcon();
  }

  function resolveEventIcon(iconName) {
    if (!iconName) return "";
    return iconResolver.resolveNamedOrPath(iconName);
  }

  /* Grouped notification list from service. The service assigns new array
     identities on every rebuild, including the 10s timeAgo tick, so a direct
     bind suffices. Manual dep tickling here caused a binding loop against the
     QML-owned cache. */
  readonly property var groupedList: service ? service.groupedList : []

  readonly property int totalCount: service ? ((service.notifications && service.notifications.length) || 0) : 0
  readonly property int unreadCount: service ? (service.unreadCount || 0) : 0
  readonly property bool isDnd: service ? (service.dnd === true) : false

  readonly property string subtitleText: {
    if (root.isDnd) return root.totalCount > 0 ? `Muted · ${root.totalCount} stored` : "Muted · new ones held back";
    if (root.totalCount === 0) return "You're all caught up";
    if (root.unreadCount > 0) return `${root.totalCount} stored · ${root.unreadCount} new`;
    return `${root.totalCount} stored`;
  }

  implicitWidth: Theme.popupWidthMd
  /* Hug the content when closed / opened, capped so overflow scrolls inside the card.
     CRITICAL (Wayland / KWin): never shrink the height while the popup is
     visible. Resizing an active xdg_popup makes KWin squish the surface buffer
     and corrupt the input region grab, so popupHeight stays frozen while
     visible and moves only when closed or opened. */
  readonly property int preferredHeight: Math.min(620, Math.max(180, 32 + bodyCol.height))
  property int popupHeight: 180
  property bool isFrozen: false

  Timer {
    id: freezeTimer
    interval: 150
    repeat: false
    onTriggered: {
      root.isFrozen = true;
    }
  }

  function syncHeight() {
    if (!isFrozen && bodyCol.height > 0) {
      popupHeight = Math.max(popupHeight, preferredHeight);
    }
  }

  onPreferredHeightChanged: {
    if (!isFrozen && bodyCol.height > 0) {
      popupHeight = Math.max(popupHeight, preferredHeight);
    }
  }

  Component.onCompleted: {
    syncHeight();
    freezeTimer.start();
  }

  implicitHeight: popupHeight

  readonly property var t: Theme

  PopupCard {
    id: card
    anchors.fill: parent

    Flickable {
      id: flickable
      anchors.fill: parent
      contentWidth: width
      contentHeight: bodyCol.height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      onContentHeightChanged: {
        returnToBounds();
        if (contentHeight <= height) {
          contentY = 0;
        }
      }

      Column {
        id: bodyCol
        width: parent.width
        spacing: 0

      PopupHeader {
        width: parent.width
        glyph: root.isDnd ? "󰂛" : "󰂚"
        glyphColor: root.totalCount > 0 ? (root.isDnd ? root.t.amber : root.t.accent) : root.t.ink3
        title: "Notifications"
        subtitle: root.subtitleText

        IconBtn {
          visible: root.totalCount > 0
          glyph: "󰃢"
          fs: Theme.iconBase
          tooltip: "Clear all notifications"
          onClicked: {
            if (root.service) root.service.clearAll();
          }
        }

        TSwitch {
          on: root.isDnd
          onColor: root.t.amber
          tooltip: root.isDnd ? "Do Not Disturb (Active)" : "Do Not Disturb (Off)"
          onToggled: {
            if (root.service) root.service.toggleDnd();
          }
        }
      }

      /* Quickshell 0.3.1 takeover switch: when on, the
         NotificationServer owns org.freedesktop.Notifications; when off,
         the legacy passive monitor feeds the same UI. */
      RowLayout {
        visible: root.service != null
        width: parent.width
        height: 28
        spacing: 8

        Text {
          text: "Quickshell takeover"
          font.pixelSize: Theme.fontSm
          color: (root.service && root.service.takeoverEnabled === true) ? root.t.accent : root.t.ink3
        }
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
        }
        Text {
          text: (root.service && root.service.takeoverEnabled === true) ? "On" : "Off"
          font.pixelSize: Theme.fontSm
          color: root.t.ink2
        }
        TSwitch {
          on: root.service && root.service.takeoverEnabled === true
          onToggled: {
            if (root.service) root.service.takeoverEnabled = !root.service.takeoverEnabled;
          }
        }
      }

      Item { width: 1; height: 14 }

      Item {
        visible: root.totalCount === 0
        width: parent.width
        height: visible ? 64 : 0
        Column {
          anchors.centerIn: parent
          spacing: 3
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No notifications"
            font.pixelSize: Theme.fontBase
            color: root.t.ink2
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "You're all caught up"
            font.pixelSize: Theme.fontSm
            color: root.t.ink3
          }
        }
      }

      Column {
        id: contentCol
        visible: root.totalCount > 0
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: 12

        Repeater {
          model: root.groupedList

          delegate: Column {
            id: groupDelegate
            required property var modelData
            required property int index

            readonly property var group: groupDelegate.modelData
            readonly property string appName: group ? (group.appName || "Application") : "Application"
            readonly property string appIcon: group ? (group.appIcon || "") : ""
            readonly property var notifsList: group ? (group.notifications || []) : []
            readonly property int totalGroupCount: group ? (group.totalCount || 0) : 0
            readonly property bool isExpanded: group ? (group.expanded === true) : false

            readonly property var visibleItems: isExpanded ? notifsList : notifsList.slice(0, 2)

            readonly property string groupDesktopEntry: group ? (group.desktopEntry || "") : ""
            readonly property string resolvedAppIcon: root.resolveAppIcon(groupDesktopEntry, appName, appIcon)

            width: contentCol.width
            spacing: 10

            SectionHead {
              width: parent.width
              label: groupDelegate.appName + (groupDelegate.totalGroupCount > 1 ? ` · ${groupDelegate.totalGroupCount}` : "")
              actionText: "Clear"
              actionColor: root.t.red
              onActionClicked: {
                if (root.service && groupDelegate.appName) root.service.clearApp(groupDelegate.appName);
              }
            }

            SectionCard {
              width: parent.width
              height: groupCol.height

              Column {
                id: groupCol
                width: parent.width

                  RowBase {
                    width: parent.width
                    height: 42
                    rad: Theme.radiusSection
                    actionable: groupDelegate.totalGroupCount > 1
                    onClicked: {
                      if (root.service) root.service.toggleGroupExpanded(groupDelegate.appName);
                    }
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      spacing: 10
                      IconImage {
                        id: appIconImg
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        source: groupDelegate.resolvedAppIcon
                        asynchronous: true
                      }
                      Text {
                        visible: appIconImg.status === Image.Error || !groupDelegate.resolvedAppIcon
                        text: groupDelegate.appName.charAt(0).toUpperCase()
                        font.pixelSize: Theme.fontMd
                        font.weight: Font.DemiBold
                        color: root.t.accent
                      }
                      Text {
                        Layout.fillWidth: true
                        text: groupDelegate.appName
                        font.pixelSize: Theme.fontMd
                        font.weight: Font.DemiBold
                        color: root.t.ink1
                        elide: Text.ElideRight
                      }
                      Text {
                        visible: groupDelegate.totalGroupCount > 2
                        text: groupDelegate.isExpanded ? "Show less" : `Show ${groupDelegate.totalGroupCount - 2} more`
                        font.pixelSize: Theme.fontSm
                        color: root.t.ink3
                      }
                    }
                  }

                  Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

                  Repeater {
                    model: groupDelegate.visibleItems

                    delegate: Column {
                      id: notifItem
                      required property var modelData
                      required property int index

                      readonly property var notif: notifItem.modelData
                      readonly property string notifIcon: notif ? (notif.notifIcon || "") : ""
                      readonly property string originName: notif ? (notif.originName || "") : ""
                      readonly property bool hasDefaultAction: notif ? (notif.hasDefaultAction === true) : false
                      readonly property string summaryText: notif ? (notif.summary || "Notification") : ""
                      readonly property string bodyText: notif ? (notif.body || "") : ""
                      readonly property string imageSrc: notif ? (notif.image || "") : ""
                      readonly property var actionsList: notif ? (notif.actions || []) : []
                      // timeTick forces re-evaluation every 10s; without it this
                      // binding only re-runs when the delegate is rebuilt.
                      readonly property string timeStr: {
                        void root.service.timeTick;
                        return root.service ? root.service.timeAgo(notif.timestamp) : "Just now";
                      }
                      readonly property int urgencyVal: notif ? (notif.urgency ?? 1) : 1
                      readonly property bool isCritical: notifItem.urgencyVal === 2
                      readonly property bool isLow: notifItem.urgencyVal === 0
                      readonly property bool hasInlineReply: notif ? notif.hasInlineReply === true : false
                      readonly property string replyPlaceholder: notif ? (notif.inlineReplyPlaceholder || "Reply…") : "Reply…"
                      readonly property bool hasActionIcons: notif ? notif.hasActionIcons === true : false
                      readonly property string desktopEntry: notif ? (notif.desktopEntry || "") : ""

                      readonly property string resolvedEventIcon: root.resolveEventIcon(notifIcon)
                      readonly property bool showEventIcon: resolvedEventIcon.length > 0 && resolvedEventIcon !== groupDelegate.resolvedAppIcon

                      width: groupCol.width

                      RowBase {
                        width: parent.width
                        height: Math.max(24, notifBody.height) + 20
                        rad: (notifItem.index === groupDelegate.visibleItems.length - 1) ? 12 : 0
                        actionable: notifItem.hasDefaultAction
                        onClicked: {
                          if (notifItem.hasDefaultAction && root.service) {
                            root.service.invokeDefaultAction(notifItem.notif);
                          }
                        }
                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 8
                          anchors.topMargin: 10
                          anchors.bottomMargin: 10
                          spacing: 8

                          Rectangle {
                            visible: notifItem.showEventIcon
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 6
                            color: root.t.inset
                            IconImage {
                              anchors.centerIn: parent
                              width: 16
                              height: 16
                              source: notifItem.resolvedEventIcon
                              asynchronous: true
                            }
                          }

                          Column {
                            id: notifBody
                            Layout.fillWidth: true
                            spacing: 3

                            Row {
                              width: parent.width
                              spacing: 6
                              Text {
                                width: Math.min(implicitWidth, parent.width - 130)
                                text: notifItem.originName.length > 0 ? (notifItem.originName + " · " + notifItem.summaryText) : notifItem.summaryText
                                textFormat: Text.PlainText
                                font.pixelSize: Theme.fontMd
                                font.weight: Font.Medium
                                color: notifItem.isCritical ? root.t.red : (notifItem.isLow ? root.t.ink2 : root.t.ink1)
                                elide: Text.ElideRight
                              }
                              Text {
                                visible: notifItem.isCritical
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Critical"
                                font.pixelSize: Theme.fontSm
                                font.weight: Font.DemiBold
                                color: root.t.red
                              }
                              Item { width: 1; height: 1 }
                            }

                            Text {
                              visible: notifItem.bodyText.length > 0
                              width: parent.width
                              text: notifItem.bodyText
                              textFormat: Text.RichText
                              font.pixelSize: Theme.fontBase
                              color: root.t.ink2
                              linkColor: root.t.accent
                              wrapMode: Text.WordWrap
                              maximumLineCount: 4
                              elide: Text.ElideRight
                              onLinkActivated: link => Qt.openUrlExternally(link)
                            }

                            Text {
                              text: notifItem.timeStr
                              font.pixelSize: Theme.fontSm
                              color: root.t.ink3
                            }

                            ClippingRectangle {
                              visible: notifItem.imageSrc.length > 0
                              width: parent.width
                              height: Math.min(80, width * 0.45)
                              radius: Theme.radiusBase
                              color: root.t.inset
                              Image {
                                anchors.fill: parent
                                source: notifItem.imageSrc
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                              }
                            }

                            Row {
                              visible: notifItem.actionsList.length > 0
                              width: parent.width
                              spacing: 2
                              Repeater {
                                model: notifItem.actionsList
                                delegate: Row {
                                  id: ccActRow
                                  required property var modelData
                                  spacing: 4
                                  IconImage {
                                    visible: notifItem.hasActionIcons
                                    width: 14
                                    height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: root.resolveActionIcon(ccActRow.modelData.identifier)
                                    asynchronous: true
                                  }
                                  TextBtn {
                                    text: ccActRow.modelData.text || "Action"
                                    fs: 11
                                    onClicked: {
                                      if (root.service) root.service.invokeAction(notifItem.notif, ccActRow.modelData.identifier);
                                    }
                                  }
                                }
                              }
                            }

                            RowLayout {
                              visible: notifItem.hasInlineReply
                              width: parent.width
                              spacing: 6
                              Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: Theme.radiusBase
                                color: root.t.inset
                                border.color: ccReplyInput.activeFocus ? root.t.accent : root.t.line
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
                                TextInput {
                                  id: ccReplyInput
                                  anchors.fill: parent
                                  anchors.leftMargin: 8
                                  anchors.rightMargin: 8
                                  verticalAlignment: TextInput.AlignVCenter
                                  font.pixelSize: Theme.fontBase
                                  color: root.t.ink1
                                  clip: true
                                  onAccepted: {
                                    if (root.service && text.trim().length > 0) {
                                      root.service.sendInlineReply(notifItem.notif, text);
                                      text = "";
                                    }
                                  }
                                  Text {
                                    visible: parent.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: notifItem.replyPlaceholder
                                    font.pixelSize: Theme.fontBase
                                    color: root.t.ink3
                                  }
                                }
                              }
                              TextBtn {
                                text: "Send"
                                fs: 11
                                fg: root.t.accent
                                onClicked: {
                                  if (root.service && ccReplyInput.text.trim().length > 0) {
                                    root.service.sendInlineReply(notifItem.notif, ccReplyInput.text);
                                    ccReplyInput.text = "";
                                  }
                                }
                              }
                            }
                          }

                          IconBtn {
                            Layout.alignment: Qt.AlignTop
                            glyph: "󰅖"
                            fs: 13
                            btnSize: 24
                            fg: root.t.ink3
                            onClicked: {
                              if (root.service && notifItem.notif && notifItem.notif.id !== undefined) {
                                root.service.dismissNotification(notifItem.notif.id);
                              }
                            }
                          }
                        }
                      }

                      Hairline {
                        visible: notifItem.index < groupDelegate.visibleItems.length - 1
                        width: parent.width - 24
                        anchors.horizontalCenter: parent.horizontalCenter
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
}
