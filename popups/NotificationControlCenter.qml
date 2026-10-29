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

  function cleanFilePath(urlStr) {
    if (!urlStr) return "";
    if (urlStr.startsWith("file://")) return decodeURIComponent(urlStr.slice(7));
    return urlStr;
  }

  function fileNameOf(pathStr) {
    const p = root.cleanFilePath(pathStr);
    const idx = p.lastIndexOf("/");
    return idx !== -1 ? p.slice(idx + 1) : p;
  }

  function fileDirOf(pathStr) {
    const p = root.cleanFilePath(pathStr);
    const idx = p.lastIndexOf("/");
    return idx !== -1 ? p.slice(0, idx) : p;
  }

  function isImageUrl(urlStr) {
    if (!urlStr) return false;
    const lower = urlStr.toLowerCase();
    return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".webp") || lower.endsWith(".gif") || lower.endsWith(".svg");
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
    if (root.isDnd) {
      if (root.service && root.service.dndUntil && root.service.dndUntil.isValid && root.service.dndUntil.isValid()) {
        const timeStr = Qt.formatTime(root.service.dndUntil, "hh:mm");
        return `Muted until ${timeStr} · ${root.totalCount} stored`;
      }
      return root.totalCount > 0 ? `Muted · ${root.totalCount} stored` : "Muted · new ones held back";
    }
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
  readonly property int preferredHeight: Math.min(640, Math.max(180, headerCol.height + scrollCol.height + 24))
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
    if (!isFrozen && (headerCol.height + scrollCol.height) > 0) {
      popupHeight = Math.max(popupHeight, preferredHeight);
    }
  }

  onPreferredHeightChanged: {
    if (!isFrozen && (headerCol.height + scrollCol.height) > 0) {
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

    Column {
      id: headerCol
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
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

      RowLayout {
        visible: root.isDnd
        width: parent.width
        height: 24
        spacing: 6

        Text {
          text: "Mute for:"
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          color: root.t.ink3
        }

        Item { Layout.fillWidth: true }

        TextButton {
          text: "1h"
          fs: Theme.fontXs
          onClicked: {
            if (root.service) root.service.setDndTimed(60);
          }
        }
        TextButton {
          text: "2h"
          fs: Theme.fontXs
          onClicked: {
            if (root.service) root.service.setDndTimed(120);
          }
        }
        TextButton {
          text: "4h"
          fs: Theme.fontXs
          onClicked: {
            if (root.service) root.service.setDndTimed(240);
          }
        }
        TextButton {
          text: "Tomorrow"
          fs: Theme.fontXs
          onClicked: {
            if (root.service) {
              const now = new Date();
              const tmrw = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 8, 0, 0);
              const diffMins = Math.max(1, Math.round((tmrw.getTime() - now.getTime()) / 60000));
              root.service.setDndTimed(diffMins);
            }
          }
        }
        TextButton {
          text: "Until off"
          fs: Theme.fontXs
          onClicked: {
            if (root.service) root.service.setDndTimed(0);
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

      Hairline {
        width: parent.width
        color: root.t.lineMuted
      }
    }

    Flickable {
      id: flickable
      anchors.top: headerCol.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.topMargin: 6
      contentWidth: width
      contentHeight: scrollCol.height + 12
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      onContentHeightChanged: {
        returnToBounds();
        if (contentHeight <= height) {
          contentY = 0;
        }
      }

      Column {
        id: scrollCol
        width: parent.width
        spacing: 0

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
                  readonly property var urlsList: notif ? (notif.urls || []) : []
                  readonly property string primaryUrl: notifItem.urlsList.length > 0 ? String(notifItem.urlsList[0]) : ""

                  readonly property string resolvedEventIcon: root.resolveEventIcon(notifIcon)
                  readonly property bool showEventIcon: resolvedEventIcon.length > 0 && resolvedEventIcon !== groupDelegate.resolvedAppIcon
                  readonly property bool isSingleInGroup: groupDelegate.totalGroupCount === 1
                  readonly property bool summaryDiffersFromApp: notifItem.summaryText.length > 0 &&
                    notifItem.summaryText.trim().toLowerCase() !== groupDelegate.appName.trim().toLowerCase()
                  readonly property string displayTitle: {
                    const orig = (notifItem.originName || "").trim();
                    const summ = (notifItem.summaryText || "").trim();
                    const app = (groupDelegate.appName || "").trim().toLowerCase();

                    // If in a multi-item group and summary is identical to the app name, don't repeat the app name
                    if (!notifItem.isSingleInGroup && summ.toLowerCase() === app) {
                      if (orig.length > 0 && orig.toLowerCase() !== app) return orig;
                      return notifItem.bodyText.length > 0 ? notifItem.bodyText.split("\n")[0] : summ;
                    }

                    if (orig.length > 0 && orig.toLowerCase() !== app) {
                      if (summ.length > 0 && summ.toLowerCase() !== orig.toLowerCase()) {
                        return orig + " · " + summ;
                      }
                      return orig;
                    }
                    return summ.length > 0 ? summ : groupDelegate.appName;
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
                          glyph: "󰒓"
                          fs: 11
                          btnSize: 20
                          fg: root.t.ink3
                          visible: notifItem.notif ? notifItem.notif.hasConfigureAction === true : false
                          tooltip: (notifItem.notif && notifItem.notif.configureLabel) || "Configure"
                          onClicked: {
                            if (root.service && notifItem.notif) {
                              root.service.invokeAction(notifItem.notif, "settings");
                            }
                          }
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

                      TextEdit {
                        visible: notifItem.bodyText.length > 0
                        Layout.fillWidth: true
                        text: notifItem.bodyText
                        textFormat: TextEdit.RichText
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontSm
                        color: root.t.ink2
                        selectionColor: root.t.accentBg
                        selectedTextColor: root.t.ink1
                        readOnly: true
                        selectByMouse: true
                        activeFocusOnPress: false
                        cursorVisible: false
                        wrapMode: TextEdit.Wrap
                        onLinkActivated: link => Qt.openUrlExternally(link)
                      }

                      ClippingRectangle {
                        visible: notifItem.imageSrc.length > 0 && notifImg.status === Image.Ready && (notifItem.urlsList.length === 0 || !root.isImageUrl(notifItem.primaryUrl))
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(100, Math.max(48, notifImg.implicitHeight > 0 ? notifImg.implicitHeight : 80))
                        radius: Theme.radiusBase
                        color: root.t.inset
                        Image {
                          id: notifImg
                          anchors.centerIn: parent
                          width: parent.width - 8
                          height: parent.height - 8
                          source: notifItem.imageSrc
                          fillMode: Image.PreserveAspectFit
                          asynchronous: true
                        }
                      }

                      Rectangle {
                        visible: notifItem.urlsList.length > 0
                        Layout.fillWidth: true
                        implicitHeight: ccFileCol.implicitHeight + 12
                        radius: Theme.radiusBase
                        color: root.t.inset
                        border.color: root.t.cardBorder
                        border.width: 1

                        Column {
                          id: ccFileCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: 6
                          spacing: 6

                          RowLayout {
                            width: parent.width
                            spacing: 8

                            Rectangle {
                              Layout.preferredWidth: 32
                              Layout.preferredHeight: 32
                              radius: Theme.radiusBase
                              color: root.t.surface
                              clip: true

                              Image {
                                id: fileThumbImg
                                visible: root.isImageUrl(notifItem.primaryUrl) && fileThumbImg.status === Image.Ready
                                anchors.centerIn: parent
                                width: parent.width - 4
                                height: parent.height - 4
                                source: notifItem.primaryUrl
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                              }

                              Text {
                                visible: !root.isImageUrl(notifItem.primaryUrl) || fileThumbImg.status !== Image.Ready
                                anchors.centerIn: parent
                                text: "󰈔"
                                font.family: root.monoFont
                                font.pixelSize: Theme.iconMd
                                color: root.t.accent
                              }
                            }

                            Column {
                              Layout.fillWidth: true
                              spacing: 2
                              Text {
                                width: parent.width
                                text: root.fileNameOf(notifItem.primaryUrl)
                                font.family: Theme.textFont
                                font.pixelSize: Theme.fontSm
                                font.weight: Font.Medium
                                color: root.t.ink1
                                elide: Text.ElideMiddle
                              }
                              Text {
                                width: parent.width
                                text: root.fileDirOf(notifItem.primaryUrl)
                                font.family: Theme.textFont
                                font.pixelSize: Theme.fontXs
                                color: root.t.ink3
                                elide: Text.ElideMiddle
                              }
                            }
                          }

                          Row {
                            spacing: 6
                            Rectangle {
                              implicitWidth: openTxt.implicitWidth + 14
                              implicitHeight: 22
                              radius: Theme.radiusChip
                              color: openMouse.containsMouse ? root.t.accentBg : root.t.surface
                              border.color: openMouse.containsMouse ? root.t.accent : root.t.cardBorder
                              border.width: 1
                              Text {
                                id: openTxt
                                anchors.centerIn: parent
                                text: "Open"
                                font.family: Theme.textFont
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.Medium
                                color: openMouse.containsMouse ? root.t.accent : root.t.ink1
                              }
                              MouseArea {
                                id: openMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(notifItem.primaryUrl)
                              }
                            }
                            Rectangle {
                              implicitWidth: folderTxt.implicitWidth + 14
                              implicitHeight: 22
                              radius: Theme.radiusChip
                              color: folderMouse.containsMouse ? root.t.accentBg : root.t.surface
                              border.color: folderMouse.containsMouse ? root.t.accent : root.t.cardBorder
                              border.width: 1
                              Text {
                                id: folderTxt
                                anchors.centerIn: parent
                                text: "Folder"
                                font.family: Theme.textFont
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.Medium
                                color: folderMouse.containsMouse ? root.t.accent : root.t.ink1
                              }
                              MouseArea {
                                id: folderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                  const dir = root.fileDirOf(notifItem.primaryUrl);
                                  if (dir.length > 0) Qt.openUrlExternally("file://" + dir);
                                }
                              }
                            }
                            Rectangle {
                              implicitWidth: copyTxt.implicitWidth + 14
                              implicitHeight: 22
                              radius: Theme.radiusChip
                              color: copyMouse.containsMouse ? root.t.accentBg : root.t.surface
                              border.color: copyMouse.containsMouse ? root.t.accent : root.t.cardBorder
                              border.width: 1
                              Text {
                                id: copyTxt
                                anchors.centerIn: parent
                                text: "Copy Path"
                                font.family: Theme.textFont
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.Medium
                                color: copyMouse.containsMouse ? root.t.accent : root.t.ink1
                              }
                              MouseArea {
                                id: copyMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                  if (root.service) {
                                    root.service.copyToClipboard(root.cleanFilePath(notifItem.primaryUrl));
                                  }
                                }
                              }
                            }
                          }
                        }
                      }

                      Row {
                        visible: notifItem.actionsList.length > 0
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                          model: notifItem.actionsList
                          delegate: Rectangle {
                            id: ccActPill
                            required property var modelData
                            implicitWidth: ccActRow.implicitWidth + 16
                            implicitHeight: 24
                            radius: Theme.radiusChip
                            color: ccActMouse.containsMouse ? root.t.accentBg : root.t.surface
                            border.color: ccActMouse.containsMouse ? root.t.accent : root.t.cardBorder
                            border.width: 1

                            Row {
                              id: ccActRow
                              anchors.centerIn: parent
                              spacing: 4
                              IconImage {
                                visible: notifItem.hasActionIcons
                                width: 12
                                height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                source: root.resolveActionIcon(ccActPill.modelData.identifier)
                                asynchronous: true
                              }
                              Text {
                                text: ccActPill.modelData.text || "Action"
                                font.family: Theme.textFont
                                font.pixelSize: Theme.fontXs
                                font.weight: Font.Medium
                                color: ccActMouse.containsMouse ? root.t.accent : root.t.ink1
                              }
                            }

                            MouseArea {
                              id: ccActMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                if (root.service) root.service.invokeAction(notifItem.notif, ccActPill.modelData.identifier);
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
                          text: (notifItem.notif && notifItem.notif.replySubmitButtonText) ? notifItem.notif.replySubmitButtonText : "Send"
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

