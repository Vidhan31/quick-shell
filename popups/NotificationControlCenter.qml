pragma ComponentBehavior: Bound
// NotificationControlCenter.qml — Quiet control surface for notifications.
// Grouped rows with hairlines, borderless buttons, words instead of badges.
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

  function resolveActionIcon(identifier) {
    if (!identifier) return "";
    return iconResolver.resolveNamedOrPath(identifier);
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

  // Grouped notification list from service. The service assigns new array
  // identities on every rebuild (including the 10s timeAgo tick), so a
  // direct bind is sufficient — no manual dep tickling (that caused a
  // binding loop against the QML-owned cache).
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

  implicitWidth: 440
  // Hug the content (chrome 32 + body), capped so overflow scrolls inside
  // the card instead of growing off-screen. bodyCol.height is driven only
  // by its children (width comes from the viewport), so no binding loop.
  // Previously this used ColumnLayout + Layout.fillHeight with a
  // Layout.preferredHeight bound to content height — clearing the list
  // collapsed the content while the layout still tried to fill, leaving
  // the popover stuck at the wrong height.
  implicitHeight: Math.min(620, 32 + bodyCol.height)
  width: implicitWidth
  height: implicitHeight

  // ================= Design tokens (mirrors TailscaleControlCenter) =================
  QtObject {
    id: t
    readonly property color bg: "#17171E"
    readonly property color surface: "#1F202B"
    readonly property color inset: "#121217"
    readonly property color line: "#2B2C3A"
    readonly property color ink1: "#F1F1F6"
    readonly property color ink2: "#A6A6B8"
    readonly property color ink3: "#6F6F84"
    readonly property color accent: "#5E9DFF"
    readonly property color green: "#46C786"
    readonly property color amber: "#E2A63B"
    readonly property color red: "#DF6363"
    readonly property color violet: "#AE8CFF"
    readonly property color darkInk: "#101018"
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
  }

  // ================= Reusable quiet components (mirrors TailscaleControlCenter) =================
  component Hairline: Rectangle {
    color: t.line
    height: 1
  }

  // Small caps section label with an optional trailing quiet action.
  component SectionHead: Item {
    property string label: ""
    property string actionText: ""
    property color actionColor: t.ink2
    signal actionClicked
    implicitHeight: 20
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: label
      font.pixelSize: 11
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.8
      color: t.ink3
    }
    TextBtn {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: actionText.length > 0
      text: parent.actionText
      fg: parent.actionColor
      fs: 11
      onClicked: parent.actionClicked()
    }
  }

  // Base for every clickable row: same wash everywhere, no borders.
  component RowBase: Rectangle {
    id: rb
    signal clicked
    property color base: "transparent"
    property color hover: "#0FFFFFFF"
    property color press: "#1AFFFFFF"
    property real rad: 0
    property bool actionable: true
    radius: rb.rad
    color: (!rb.actionable || (!ma.containsMouse && !ma.pressed)) ? base : (ma.pressed ? press : hover)
    Behavior on color { ColorAnimation { duration: 90 } }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: rb.actionable
      cursorShape: rb.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (rb.actionable) rb.clicked();
      }
    }
  }

  // Borderless text button.
  component TextBtn: Rectangle {
    id: tb
    signal clicked
    property string text: ""
    property color fg: t.ink2
    property int fs: 12
    property bool bold: false
    implicitWidth: lbl.implicitWidth + 18
    implicitHeight: 26
    radius: 7
    color: ma.pressed ? "#1CFFFFFF" : ma.containsMouse ? "#0FFFFFFF" : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }
    Text {
      id: lbl
      anchors.centerIn: parent
      text: tb.text
      font.pixelSize: tb.fs
      font.bold: tb.bold
      color: (ma.containsMouse || ma.pressed) ? t.ink1 : tb.fg
      Behavior on color { ColorAnimation { duration: 90 } }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tb.clicked()
    }
  }

  // Borderless square icon button.
  component IconBtn: Rectangle {
    id: ib
    signal clicked
    property string glyph: ""
    property int fs: 14
    property color fg: t.ink2
    property int btnSize: 30
    width: btnSize
    height: btnSize
    radius: 8
    color: ma.pressed ? "#1CFFFFFF" : ma.containsMouse ? "#0FFFFFFF" : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }
    Text {
      id: ibGlyph
      anchors.centerIn: parent
      text: ib.glyph
      font.family: t.mono
      font.pixelSize: ib.fs
      color: (ma.containsMouse || ma.pressed) ? t.ink1 : ib.fg
      Behavior on color { ColorAnimation { duration: 90 } }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ib.clicked()
    }
  }

  // macOS-style switch. Track carries the color, thumb just slides.
  component TSwitch: Item {
    id: sw
    signal toggled
    property bool on: false
    property color onColor: t.green
    width: 42
    height: 24
    Rectangle {
      anchors.fill: parent
      radius: 12
      color: sw.on ? sw.onColor : "#3B3C4C"
      Behavior on color { ColorAnimation { duration: 140 } }
      Rectangle {
        width: 20
        height: 20
        radius: 10
        y: 2
        x: sw.on ? parent.width - width - 2 : 2
        color: "#F4F4F8"
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }

  // ================= Card =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: 14
    color: t.bg
    border.color: "#26272F"
    border.width: 1

    Flickable {
      anchors.fill: parent
      anchors.margins: 16
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 0

      // ---- Header: identity left, clear + mute switch right ----
      RowLayout {
        width: parent.width
        height: 40
        spacing: 10

        Text {
          text: root.isDnd ? "󰂛" : "󰂚"
          font.family: t.mono
          font.pixelSize: 19
          color: root.totalCount > 0 ? (root.isDnd ? t.amber : t.accent) : t.ink3
        }

        Column {
          Layout.fillWidth: true
          spacing: 1
          Text {
            text: "Notifications"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: t.ink1
          }
          Text {
            text: root.subtitleText
            font.pixelSize: 11
            color: t.ink3
            elide: Text.ElideRight
          }
        }

        IconBtn {
          visible: root.totalCount > 0
          glyph: "󰃢"
          fs: 14
          onClicked: {
            if (root.service) root.service.clearAll();
          }
        }

        TSwitch {
          on: root.isDnd
          onColor: t.amber
          onToggled: {
            if (root.service) root.service.toggleDnd();
          }
        }
      }

      // Quickshell 0.3.1 takeover switch (testing): when on, the
      // NotificationServer owns org.freedesktop.Notifications; when off,
      // the legacy passive monitor feeds the same UI.
      RowLayout {
        visible: root.service != null
        width: parent.width
        height: 28
        spacing: 8

        Text {
          text: "Quickshell takeover"
          font.pixelSize: 11
          color: (root.service && root.service.takeoverEnabled === true) ? t.accent : t.ink3
        }
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
        }
        Text {
          text: (root.service && root.service.takeoverEnabled === true) ? "On" : "Off"
          font.pixelSize: 11
          color: t.ink2
        }
        TSwitch {
          on: root.service && root.service.takeoverEnabled === true
          onToggled: {
            if (root.service) root.service.takeoverEnabled = !root.service.takeoverEnabled;
          }
        }
      }

      Item { width: 1; height: 14 }

      // ---- Empty state: nothing to box, like "Nothing shared yet" ----
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
            font.pixelSize: 12
            color: t.ink2
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "You're all caught up"
            font.pixelSize: 11
            color: t.ink3
          }
        }
      }

      // ---- Grouped app sections (scrolls in the outer Flickable) ----
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

            // Slice to 2 items if not expanded
            readonly property var visibleItems: isExpanded ? notifsList : notifsList.slice(0, 2)

            // Resolve icon source via IconResolver
            readonly property string groupDesktopEntry: group ? (group.desktopEntry || "") : ""
            readonly property string resolvedIcon: root.resolveNotifIcon(appIcon, appName, groupDelegate.groupDesktopEntry)

            width: contentCol.width
            spacing: 10

            SectionHead {
              width: parent.width
              label: groupDelegate.appName + (groupDelegate.totalGroupCount > 1 ? ` · ${groupDelegate.totalGroupCount}` : "")
              actionText: "Clear"
              actionColor: t.red
              onActionClicked: {
                if (root.service) root.service.clearApp(groupDelegate.appName);
              }
            }

            Rectangle {
              width: parent.width
              height: groupCol.height
              radius: 12
              color: t.surface

              Column {
                id: groupCol
                width: parent.width

                  // App identity row; tap to expand when collapsed.
                  RowBase {
                    width: parent.width
                    height: 42
                    rad: 12
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
                        source: groupDelegate.resolvedIcon
                        asynchronous: true
                      }
                      Text {
                        visible: appIconImg.status === Image.Error || !groupDelegate.resolvedIcon
                        text: groupDelegate.appName.charAt(0).toUpperCase()
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: t.accent
                      }
                      Text {
                        Layout.fillWidth: true
                        text: groupDelegate.appName
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: t.ink1
                        elide: Text.ElideRight
                      }
                      Text {
                        visible: groupDelegate.totalGroupCount > 2
                        text: groupDelegate.isExpanded ? "Show less" : `Show ${groupDelegate.totalGroupCount - 2} more`
                        font.pixelSize: 11
                        color: t.ink3
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
                      readonly property string summaryText: notif ? (notif.summary || "Notification") : ""
                      readonly property string bodyText: notif ? (notif.body || "") : ""
                      readonly property string imageSrc: notif ? (notif.image || "") : ""
                      readonly property var actionsList: notif ? (notif.actions || []) : []
                      readonly property string timeStr: root.service ? root.service.timeAgo(notif.timestamp) : "Just now"
                      readonly property int urgencyVal: notif ? (notif.urgency ?? 1) : 1
                      readonly property bool isCritical: notifItem.urgencyVal === 2
                      readonly property bool isLow: notifItem.urgencyVal === 0
                      readonly property bool hasInlineReply: notif ? notif.hasInlineReply === true : false
                      readonly property string replyPlaceholder: notif ? (notif.inlineReplyPlaceholder || "Reply…") : "Reply…"
                      readonly property bool hasActionIcons: notif ? notif.hasActionIcons === true : false
                      readonly property string desktopEntry: notif ? (notif.desktopEntry || "") : ""

                      width: groupCol.width

                      RowBase {
                        width: parent.width
                        height: notifBody.height + 20
                        rad: (notifItem.index === groupDelegate.visibleItems.length - 1) ? 12 : 0
                        actionable: false
                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 12
                          anchors.rightMargin: 8
                          anchors.topMargin: 10
                          anchors.bottomMargin: 10
                          spacing: 8
                          Column {
                            id: notifBody
                            Layout.fillWidth: true
                            spacing: 3

                            Row {
                              width: parent.width
                              spacing: 6
                              Text {
                                width: Math.min(implicitWidth, parent.width - 130)
                                text: notifItem.summaryText
                                textFormat: Text.PlainText
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: notifItem.isCritical ? t.red : (notifItem.isLow ? t.ink2 : t.ink1)
                                elide: Text.ElideRight
                              }
                              Text {
                                visible: notifItem.isCritical
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Critical"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: t.red
                              }
                              Item { width: 1; height: 1 }
                            }

                            Text {
                              visible: notifItem.bodyText.length > 0
                              width: parent.width
                              text: notifItem.bodyText
                              textFormat: Text.RichText
                              font.pixelSize: 12
                              color: t.ink2
                              linkColor: t.accent
                              wrapMode: Text.WordWrap
                              maximumLineCount: 4
                              elide: Text.ElideRight
                              onLinkActivated: link => Qt.openUrlExternally(link)
                            }

                            Text {
                              text: notifItem.timeStr
                              font.pixelSize: 11
                              color: t.ink3
                            }

                            Rectangle {
                              visible: notifItem.imageSrc.length > 0
                              width: parent.width
                              height: Math.min(80, width * 0.45)
                              radius: 8
                              color: t.inset
                              clip: true
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
                                radius: 8
                                color: t.inset
                                border.color: ccReplyInput.activeFocus ? t.accent : t.line
                                border.width: 1
                                TextInput {
                                  id: ccReplyInput
                                  anchors.fill: parent
                                  anchors.leftMargin: 8
                                  anchors.rightMargin: 8
                                  verticalAlignment: TextInput.AlignVCenter
                                  font.pixelSize: 12
                                  color: t.ink1
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
                                    font.pixelSize: 12
                                    color: t.ink3
                                  }
                                }
                              }
                              TextBtn {
                                text: "Send"
                                fs: 11
                                fg: t.accent
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
                            fg: t.ink3
                            onClicked: {
                              if (root.service) root.service.dismissNotification(notifItem.notif.id);
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
