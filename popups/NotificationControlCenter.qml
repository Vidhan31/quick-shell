pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Plugins.IconResolver
import "../theme"
import "../components"

Item {
  id: root

  property var service: null
  property var jobService: null
  readonly property var jobsList: jobService ? (jobService.jobs || []) : []
  readonly property var activeJobsList: jobService ? (jobService.activeJobs || []) : []
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

        IconButton {
          visible: root.totalCount > 0
          glyph: "󰃢"
          fs: Theme.iconBase
          tooltip: "Clear all notifications"
          onClicked: {
            if (root.service) root.service.clearAll();
          }
        }

        ToggleSwitch {
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
          font.family: Theme.textFont
          font.pixelSize: Theme.fontSm
          color: (root.service && root.service.takeoverEnabled === true) ? root.t.accent : root.t.ink3
        }
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
        }
        Text {
          text: (root.service && root.service.takeoverEnabled === true) ? "On" : "Off"
          font.family: Theme.textFont
          font.pixelSize: Theme.fontSm
          color: root.t.ink2
        }
        ToggleSwitch {
          on: root.service && root.service.takeoverEnabled === true
          onToggled: {
            if (root.service) root.service.takeoverEnabled = !root.service.takeoverEnabled;
          }
        }
      }

      Item { width: 1; height: 10 }

      SectionCard {
        visible: root.jobsList.length > 0
        width: parent.width
        implicitHeight: jobsCol.height + 20
        height: implicitHeight
        clip: true

        Column {
          id: jobsCol
          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
          }
          spacing: 8

          RowLayout {
            width: parent.width
            height: 28
            spacing: 8

            Text {
              text: "Tasks & Transfers"
              font.family: Theme.displayFont
              font.pixelSize: Theme.fontBase
              font.weight: Font.DemiBold
              color: root.t.ink1
            }

            Rectangle {
              visible: root.activeJobsList.length > 0
              Layout.preferredHeight: 18
              implicitWidth: activeJobsCountText.implicitWidth + 10
              radius: 9
              color: root.t.accentBg

              Text {
                id: activeJobsCountText
                anchors.centerIn: parent
                text: root.activeJobsList.length.toString()
                font.family: Theme.roundedFont
                font.pixelSize: Theme.fontXs
                font.weight: Font.DemiBold
                color: root.t.accent
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              visible: root.jobService && root.activeJobsList.length > 0 && root.jobService.formattedTotalSpeed.length > 0
              text: root.jobService ? root.jobService.formattedTotalSpeed : ""
              font.family: Theme.mono
              font.pixelSize: Theme.fontXs
              color: root.t.ink3
            }

            IconButton {
              visible: root.jobsList.length > root.activeJobsList.length
              glyph: "󰃢"
              fs: 13
              btnSize: 24
              tooltip: "Clear finished tasks"
              onClicked: {
                if (root.jobService) root.jobService.clearFinished();
              }
            }
          }

          Repeater {
            model: root.jobsList

            delegate: Rectangle {
              id: jobRow
              required property var modelData
              required property int index

              readonly property var job: jobRow.modelData
              readonly property int jobId: job ? (job.id || 0) : 0
              readonly property string appName: job ? (job.appName || "Task") : "Task"
              readonly property string desktopEntry: job ? (job.desktopEntry || "") : ""
              readonly property string appIcon: job ? (job.appIcon || "") : ""
              readonly property string summaryText: job ? (job.summary || "Task Progress") : ""
              readonly property string bodyText: job ? (job.body || "") : ""
              readonly property int percentVal: job ? (job.percent || 0) : 0
              readonly property string speedText: job ? (job.formattedSpeed || "") : ""
              readonly property bool isSuspended: job ? (job.isSuspended === true) : false
              readonly property bool isStopped: job ? (job.isStopped === true) : false
              readonly property int errorCode: job ? (job.errorCode || 0) : 0
              readonly property bool canSuspend: job ? (job.suspendable === true) : false

              readonly property string resolvedAppIcon: root.resolveAppIcon(desktopEntry, appName, appIcon)

              width: parent.width
              implicitHeight: jobRowCol.implicitHeight + 14
              radius: Theme.radiusBase
              color: root.t.inset
              border.color: root.t.cardBorder
              border.width: 1

              Column {
                id: jobRowCol
                anchors {
                  top: parent.top
                  left: parent.left
                  right: parent.right
                  margins: 8
                }
                spacing: 6

                RowLayout {
                  width: parent.width
                  spacing: 8

                  Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: Theme.radiusBase
                    color: root.t.inset
                    IconImage {
                      anchors.centerIn: parent
                      width: 14
                      height: 14
                      source: jobRow.resolvedAppIcon
                      asynchronous: true
                    }
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                      width: parent.width
                      text: jobRow.summaryText
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontSm
                      font.weight: Font.DemiBold
                      color: root.t.ink1
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: jobRow.isStopped ? (jobRow.errorCode !== 0 ? "Failed" : "Finished") : (jobRow.isSuspended ? "Paused" : (jobRow.speedText.length > 0 ? (jobRow.speedText + (jobRow.bodyText.length > 0 ? " · " + jobRow.bodyText : "")) : (jobRow.bodyText.length > 0 ? jobRow.bodyText : "In progress")))
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontXs
                      color: jobRow.isStopped ? (jobRow.errorCode !== 0 ? root.t.red : root.t.ink3) : (jobRow.isSuspended ? root.t.amber : root.t.ink3)
                      elide: Text.ElideMiddle
                    }
                  }

                  IconButton {
                    visible: !jobRow.isStopped && jobRow.canSuspend
                    glyph: jobRow.isSuspended ? "󰐊" : "󰏤"
                    fs: 11
                    btnSize: 22
                    tooltip: jobRow.isSuspended ? "Resume" : "Pause"
                    onClicked: {
                      if (root.jobService) {
                        if (jobRow.isSuspended) root.jobService.resumeJob(jobRow.jobId);
                        else root.jobService.suspendJob(jobRow.jobId);
                      }
                    }
                  }

                  IconButton {
                    glyph: "󰅖"
                    fs: 11
                    btnSize: 22
                    tooltip: jobRow.isStopped ? "Remove" : "Cancel"
                    onClicked: {
                      if (root.jobService) {
                        if (jobRow.isStopped) root.jobService.removeJob(jobRow.jobId);
                        else root.jobService.cancelJob(jobRow.jobId);
                      }
                    }
                  }
                }

                Rectangle {
                  visible: !jobRow.isStopped
                  width: parent.width
                  height: 4
                  radius: 2
                  color: root.t.inset
                  clip: true

                  Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, jobRow.percentVal)) / 100
                    height: parent.height
                    radius: 2
                    color: jobRow.isSuspended ? root.t.amber : root.t.accent
                    Behavior on width { NumberAnimation { duration: 150 } }
                  }
                }
              }
            }
          }
        }
      }
      Item {
        visible: root.jobsList.length > 0 && root.totalCount > 0
        width: 1
        height: 8
      }

      Item {
        visible: root.totalCount === 0 && root.jobsList.length === 0
        width: parent.width
        height: visible ? 64 : 0
        Column {
          anchors.centerIn: parent
          spacing: 3
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No notifications"
            font.family: Theme.displayFont
            font.pixelSize: Theme.fontBase
            color: root.t.ink2
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "You're all caught up"
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: root.t.ink3
          }
        }
      }

      Column {
        id: contentCol
        visible: root.totalCount > 0
        width: parent.width
        spacing: 8

        Repeater {
          model: root.groupedList

          delegate: SectionCard {
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

            readonly property string latestTime: {
              if (!notifsList || notifsList.length === 0) return "";
              void root.service.timeTick;
              const first = notifsList[0];
              const last = notifsList[notifsList.length - 1];
              const newest = (last && last.timestamp > (first ? first.timestamp : 0)) ? last : first;
              return root.service ? root.service.timeAgo(newest.timestamp) : (newest ? (newest.timeAgo || "") : "");
            }

            width: contentCol.width
            implicitHeight: groupCol.height + 20
            height: implicitHeight
            clip: true

            Column {
              id: groupCol
              anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 10
              }
              spacing: 8

              RowLayout {
                visible: groupDelegate.totalGroupCount > 1
                width: parent.width
                height: 20
                spacing: 6

                IconImage {
                  visible: groupDelegate.resolvedAppIcon.length > 0
                  Layout.preferredWidth: 16
                  Layout.preferredHeight: 16
                  Layout.alignment: Qt.AlignVCenter
                  source: groupDelegate.resolvedAppIcon
                  asynchronous: true
                }
                Text {
                  visible: !groupDelegate.resolvedAppIcon
                  text: groupDelegate.appName.charAt(0).toUpperCase()
                  font.family: Theme.roundedFont
                  font.pixelSize: Theme.fontSm
                  font.weight: Font.DemiBold
                  color: root.t.accent
                }
                Text {
                  text: groupDelegate.appName
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontSm
                  font.weight: Font.DemiBold
                  color: root.t.ink1
                }
                Text {
                  text: "· " + groupDelegate.totalGroupCount
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontXs
                  font.weight: Font.DemiBold
                  color: root.t.ink3
                }
                Text {
                  visible: groupDelegate.latestTime.length > 0
                  text: "· " + groupDelegate.latestTime
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontXs
                  color: root.t.ink3
                }
                Item {
                  Layout.fillWidth: true
                }
                TextButton {
                  visible: groupDelegate.totalGroupCount > 2
                  text: groupDelegate.isExpanded ? "Show less" : `Show ${groupDelegate.totalGroupCount - 2} more`
                  fs: Theme.fontXs
                  fg: root.t.ink3
                  onClicked: {
                    if (root.service) root.service.toggleGroupExpanded(groupDelegate.appName);
                  }
                }
                TextButton {
                  text: "Clear"
                  fs: Theme.fontXs
                  fg: root.t.red
                  onClicked: {
                    if (root.service && groupDelegate.appName) root.service.clearApp(groupDelegate.appName);
                  }
                }
              }

              Hairline {
                visible: groupDelegate.totalGroupCount > 1
                width: parent.width
                color: root.t.lineMuted
              }

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
                  readonly property bool isSingleInGroup: groupDelegate.totalGroupCount === 1
                  readonly property bool summaryDiffersFromApp: notifItem.summaryText.length > 0 &&
                    notifItem.summaryText.trim().toLowerCase() !== groupDelegate.appName.trim().toLowerCase()
                  readonly property string displayTitle: {
                    if (notifItem.originName.length > 0 && notifItem.originName.toLowerCase() !== groupDelegate.appName.toLowerCase()) {
                      return notifItem.originName + " · " + notifItem.summaryText;
                    }
                    return notifItem.summaryText;
                  }

                  width: groupCol.width
                  spacing: 8

                  Item {
                    width: parent.width
                    implicitHeight: notifContentCol.implicitHeight
                    height: implicitHeight

                    MouseArea {
                      anchors.fill: parent
                      enabled: notifItem.hasDefaultAction
                      cursorShape: notifItem.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: {
                        if (notifItem.hasDefaultAction && root.service) {
                          root.service.invokeDefaultAction(notifItem.notif);
                        }
                      }
                    }

                    ColumnLayout {
                      id: notifContentCol
                      width: parent.width
                      spacing: 4

                      RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        spacing: 6

                        IconImage {
                          visible: notifItem.isSingleInGroup && groupDelegate.resolvedAppIcon.length > 0
                          Layout.preferredWidth: 16
                          Layout.preferredHeight: 16
                          Layout.alignment: Qt.AlignVCenter
                          source: groupDelegate.resolvedAppIcon
                          asynchronous: true
                        }
                        Text {
                          visible: notifItem.isSingleInGroup && !groupDelegate.resolvedAppIcon
                          text: groupDelegate.appName.charAt(0).toUpperCase()
                          font.family: Theme.roundedFont
                          font.pixelSize: Theme.fontSm
                          font.weight: Font.DemiBold
                          color: root.t.accent
                        }
                        Text {
                          visible: notifItem.isSingleInGroup
                          Layout.maximumWidth: 180
                          text: groupDelegate.appName
                          font.family: Theme.textFont
                          font.pixelSize: Theme.fontSm
                          font.weight: Font.DemiBold
                          color: root.t.ink1
                          elide: Text.ElideRight
                        }

                        IconImage {
                          id: subEventIcon
                          visible: !notifItem.isSingleInGroup && notifItem.showEventIcon && subEventIcon.status !== Image.Error
                          Layout.preferredWidth: 16
                          Layout.preferredHeight: 16
                          Layout.alignment: Qt.AlignVCenter
                          source: notifItem.resolvedEventIcon
                          asynchronous: true
                        }

                        Text {
                          visible: !notifItem.isSingleInGroup
                          Layout.maximumWidth: 200
                          text: notifItem.displayTitle
                          font.family: Theme.textFont
                          font.pixelSize: Theme.fontSm
                          font.weight: Font.DemiBold
                          color: notifItem.isCritical ? root.t.red : root.t.ink1
                          elide: Text.ElideRight
                        }

                        Text {
                          text: "· " + notifItem.timeStr
                          font.family: Theme.textFont
                          font.pixelSize: Theme.fontXs
                          color: root.t.ink3
                        }

                        Text {
                          visible: notifItem.isCritical
                          text: "Critical"
                          font.family: Theme.textFont
                          font.pixelSize: Theme.fontXs
                          font.weight: Font.DemiBold
                          color: root.t.red
                        }

                        Item {
                          Layout.fillWidth: true
                        }

                        IconButton {
                          Layout.preferredWidth: 20
                          Layout.preferredHeight: 20
                          Layout.alignment: Qt.AlignVCenter
                          glyph: "󰅖"
                          fs: 11
                          btnSize: 20
                          fg: root.t.ink3
                          tooltip: "Dismiss"
                          onClicked: {
                            if (root.service && notifItem.notif && notifItem.notif.id !== undefined) {
                              root.service.dismissNotification(notifItem.notif.id);
                            }
                          }
                        }
                      }

                      Text {
                        visible: notifItem.isSingleInGroup && notifItem.summaryDiffersFromApp
                        Layout.fillWidth: true
                        text: notifItem.displayTitle
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.Medium
                        color: notifItem.isCritical ? root.t.red : (notifItem.isLow ? root.t.ink2 : root.t.ink1)
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: notifItem.bodyText.length > 0
                        Layout.fillWidth: true
                        text: notifItem.bodyText
                        textFormat: Text.RichText
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontSm
                        color: root.t.ink2
                        linkColor: root.t.accent
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        onLinkActivated: link => Qt.openUrlExternally(link)
                      }

                      ClippingRectangle {
                        visible: notifItem.imageSrc.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(80, width * 0.45)
                        radius: Theme.radiusBase
                        color: "transparent"
                        Image {
                          id: notifImg
                          anchors.fill: parent
                          source: notifItem.imageSrc
                          sourceSize.width: 320
                          sourceSize.height: 160
                          fillMode: Image.PreserveAspectCrop
                          asynchronous: true
                        }
                      }

                      Row {
                        visible: notifItem.actionsList.length > 0
                        Layout.fillWidth: true
                        spacing: 6
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
                            TextButton {
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
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                          Layout.fillWidth: true
                          Layout.preferredHeight: 28
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
                            font.family: Theme.textFont
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
                              font.family: Theme.textFont
                              font.pixelSize: Theme.fontBase
                              color: root.t.ink3
                            }
                          }
                        }
                        TextButton {
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
                  }

                  Hairline {
                    visible: notifItem.index < groupDelegate.visibleItems.length - 1
                    width: parent.width
                    color: root.t.lineMuted
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

