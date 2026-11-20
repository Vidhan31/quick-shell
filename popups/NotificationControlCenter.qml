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
  readonly property string monoFont: Theme.mono

  signal closeRequested()

  property bool showSettings: false

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
    if (iconName.startsWith("image://") || iconName.startsWith("file://") || iconName.startsWith("http://") || iconName.startsWith("https://") || iconName.startsWith("/")) {
      return iconName;
    }
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

  readonly property var groupedList: service ? service.groupedList : []
  readonly property int totalCount: service ? (service.totalCount || 0) : 0
  readonly property int unreadCount: service ? (service.unreadCount || 0) : 0
  readonly property bool isDnd: service ? (service.dnd === true) : false

  readonly property string subtitleText: {
    if (root.isDnd) {
      if (root.service && root.service.dndUntil && root.service.dndUntil.isValid && root.service.dndUntil.isValid()) {
        const timeStr = Qt.formatTime(root.service.dndUntil, "hh:mm");
        return `Muted until ${timeStr}`;
      }
      return "Do Not Disturb";
    }
    return "";
  }

  implicitWidth: Theme.popupWidthMd
  property int popupHeight: 640
  implicitHeight: popupHeight

  function syncHeight(): void {}

  readonly property var t: Theme

  PopupCard {
    id: card
    anchors.fill: parent
    padding: 12

    Column {
      id: headerCol
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: 6

      // Main Header Bar
      RowLayout {
        width: parent.width
        height: 26
        spacing: 8

        Column {
          Layout.fillWidth: true
          spacing: 1

          Row {
            spacing: 6
            Text {
              text: "Notifications"
              font.family: Theme.displayFont
              font.pixelSize: Theme.fontLg
              font.weight: Font.SemiBold
              color: root.t.ink1
            }

            Rectangle {
              visible: root.totalCount > 0
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: countBadgeTxt.implicitWidth + 10
              implicitHeight: 18
              radius: 9
              color: root.unreadCount > 0 ? root.t.accentBg : root.t.hoverWash
              border.color: root.unreadCount > 0 ? root.t.tint(root.t.accent, 0.35) : root.t.lineMuted
              border.width: 1

              Text {
                id: countBadgeTxt
                anchors.centerIn: parent
                text: root.unreadCount > 0 ? `${root.totalCount} · ${root.unreadCount} new` : root.totalCount.toString()
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                font.weight: Font.SemiBold
                color: root.unreadCount > 0 ? root.t.accent : root.t.ink2
              }
            }
          }

          Text {
            visible: root.subtitleText.length > 0
            text: root.subtitleText
            font.family: Theme.textFont
            font.pixelSize: Theme.fontXs
            color: root.isDnd ? root.t.amber : root.t.ink3
            elide: Text.ElideRight
          }
        }

        // Action Toolbar
        Row {
          spacing: 2
          Layout.alignment: Qt.AlignVCenter

          IconButton {
            visible: root.totalCount > 0 || (root.jobService && (root.jobsList.length > root.activeJobsList.length))
            glyph: "󰃢"
            fs: Theme.iconSm
            btnSize: 24
            fg: root.t.ink2
            tooltip: "Clear all"
            onClicked: {
              if (root.service) root.service.clearAll();
              if (root.jobService) root.jobService.clearFinished();
            }
          }

          IconButton {
            glyph: root.isDnd ? "󰂛" : "󰂞"
            fs: Theme.iconSm
            btnSize: 24
            fg: root.isDnd ? root.t.amber : root.t.ink2
            tooltip: root.isDnd ? "Do Not Disturb (Active)" : "Do Not Disturb (Off)"
            onClicked: {
              if (root.service) root.service.toggleDnd();
            }
          }

          IconButton {
            glyph: "󰒓"
            fs: Theme.iconSm
            btnSize: 24
            fg: root.showSettings ? root.t.accent : root.t.ink3
            tooltip: "Notification settings"
            onClicked: {
              root.showSettings = !root.showSettings;
            }
          }
        }
      }

      // Collapsible DND Presets Bar
      Rectangle {
        visible: root.isDnd
        width: parent.width
        implicitHeight: dndPresetRow.implicitHeight + 8
        radius: 6
        color: root.t.tint(root.t.amber, 0.08)
        border.color: root.t.tint(root.t.amber, 0.22)
        border.width: 1

        RowLayout {
          id: dndPresetRow
          anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 8
            rightMargin: 8
          }
          spacing: 6

          Text {
            text: "Mute for:"
            font.family: Theme.textFont
            font.pixelSize: Theme.fontXs
            font.weight: Font.Medium
            color: root.t.amber
          }

          Item { Layout.fillWidth: true }

          TextButton {
            text: "1h"
            fs: Theme.fontXs
            fg: root.t.ink2
            onClicked: {
              if (root.service) root.service.setDndTimed(60);
            }
          }
          TextButton {
            text: "2h"
            fs: Theme.fontXs
            fg: root.t.ink2
            onClicked: {
              if (root.service) root.service.setDndTimed(120);
            }
          }
          TextButton {
            text: "4h"
            fs: Theme.fontXs
            fg: root.t.ink2
            onClicked: {
              if (root.service) root.service.setDndTimed(240);
            }
          }
          TextButton {
            text: "Tomorrow"
            fs: Theme.fontXs
            fg: root.t.ink2
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
            fg: root.t.amber
            onClicked: {
              if (root.service) root.service.setDndTimed(0);
            }
          }
        }
      }

      // Collapsible Settings Drawer
      Rectangle {
        visible: root.showSettings
        width: parent.width
        implicitHeight: settingsCol.implicitHeight + 14
        radius: 6
        color: root.t.surfaceElevated
        border.color: root.t.lineMuted
        border.width: 1

        Column {
          id: settingsCol
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

            Column {
              Layout.fillWidth: true
              spacing: 1

              Text {
                text: "Quickshell takeover"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSm
                font.weight: Font.Medium
                color: (root.service && root.service.takeoverEnabled === true) ? root.t.accent : root.t.ink1
              }
              Text {
                text: "Own org.freedesktop.Notifications D-Bus service"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: root.t.ink3
              }
            }

            ToggleSwitch {
              on: root.service && root.service.takeoverEnabled === true
              tooltip: "Quickshell notification server takeover"
              onToggled: {
                if (root.service) root.service.takeoverEnabled = !root.service.takeoverEnabled;
              }
            }
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
        spacing: 12

        // Tasks & Transfers Section
        Column {
          visible: root.jobsList.length > 0
          width: scrollCol.width
          spacing: 6

          // Group Header Bar
          RowLayout {
            width: parent.width
            height: 24
            spacing: 6

            IconImage {
              visible: root.resolveAppIcon("org.kde.dolphin", "system-file-manager", "folder").length > 0
              Layout.preferredWidth: 16
              Layout.preferredHeight: 16
              Layout.alignment: Qt.AlignVCenter
              source: root.resolveAppIcon("org.kde.dolphin", "system-file-manager", "folder")
              asynchronous: true
            }

            Text {
              text: "Tasks & Transfers"
              font.family: Theme.displayFont
              font.pixelSize: Theme.fontSm
              font.weight: Font.SemiBold
              font.letterSpacing: -0.1
              color: root.t.ink1
            }

            Rectangle {
              visible: root.jobsList.length > 0
              implicitWidth: jobCountTxt.implicitWidth + 8
              implicitHeight: 16
              radius: 8
              color: root.activeJobsList.length > 0 ? root.t.accentBg : root.t.hoverWash
              border.color: root.activeJobsList.length > 0 ? root.t.tint(root.t.accent, 0.35) : root.t.lineMuted
              border.width: 1

              Text {
                id: jobCountTxt
                anchors.centerIn: parent
                text: root.activeJobsList.length > 0 ? `${root.jobsList.length} · ${root.activeJobsList.length} active` : root.jobsList.length.toString()
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                font.weight: Font.SemiBold
                color: root.activeJobsList.length > 0 ? root.t.accent : root.t.ink2
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

            TextButton {
              visible: root.jobsList.length > root.activeJobsList.length
              text: "Clear"
              fs: Theme.fontXs
              fg: root.t.ink3
              onClicked: {
                if (root.jobService) root.jobService.clearFinished();
              }
            }
          }

          // Stack of Task Cards
          Column {
            width: parent.width
            spacing: 6

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
                implicitHeight: jobRowCol.implicitHeight + 18
                radius: 8
                color: jobMouse.containsMouse ? root.t.hoverFill : root.t.surfaceElevated
                border.color: jobRow.errorCode !== 0 ? root.t.red : (jobMouse.containsMouse ? root.t.cardBorder : root.t.lineMuted)
                border.width: 1

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                MouseArea {
                  id: jobMouse
                  anchors.fill: parent
                  hoverEnabled: true
                }

                Column {
                  id: jobRowCol
                  anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 9
                  }
                  spacing: 6

                  RowLayout {
                    width: parent.width
                    height: 20
                    spacing: 6

                    IconImage {
                      Layout.preferredWidth: 16
                      Layout.preferredHeight: 16
                      Layout.alignment: Qt.AlignVCenter
                      source: jobRow.resolvedAppIcon.length > 0 ? jobRow.resolvedAppIcon : root.resolveAppIcon("org.kde.dolphin", "system-file-manager", "folder")
                      asynchronous: true
                    }

                    Text {
                      Layout.maximumWidth: 220
                      text: jobRow.summaryText
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontSm
                      font.weight: Font.SemiBold
                      color: root.t.ink1
                      elide: Text.ElideRight
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      text: jobRow.isStopped ? (jobRow.errorCode !== 0 ? "Failed" : "Finished") : (jobRow.isSuspended ? "Paused" : (jobRow.speedText.length > 0 ? jobRow.speedText : "In progress"))
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontXs
                      color: jobRow.isStopped ? (jobRow.errorCode !== 0 ? root.t.red : root.t.ink3) : (jobRow.isSuspended ? root.t.amber : root.t.ink3)
                    }

                    IconButton {
                      visible: !jobRow.isStopped && jobRow.canSuspend
                      Layout.preferredWidth: 20
                      Layout.preferredHeight: 20
                      Layout.alignment: Qt.AlignVCenter
                      glyph: jobRow.isSuspended ? "󰐊" : "󰏤"
                      fs: 11
                      btnSize: 20
                      fg: root.t.ink3
                      tooltip: jobRow.isSuspended ? "Resume" : "Pause"
                      onClicked: {
                        if (root.jobService) {
                          if (jobRow.isSuspended) root.jobService.resumeJob(jobRow.jobId);
                          else root.jobService.suspendJob(jobRow.jobId);
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
                      tooltip: jobRow.isStopped ? "Remove" : "Cancel"
                      onClicked: {
                        if (root.jobService) {
                          if (jobRow.isStopped) root.jobService.removeJob(jobRow.jobId);
                          else root.jobService.cancelJob(jobRow.jobId);
                        }
                      }
                    }
                  }

                  Text {
                    visible: jobRow.bodyText.length > 0 && !jobRow.isStopped
                    width: parent.width
                    text: jobRow.bodyText
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontXs
                    color: root.t.ink2
                    elide: Text.ElideMiddle
                  }

                  ProgressBar {
                    visible: !jobRow.isStopped
                    width: parent.width
                    implicitHeight: 3
                    radius: 1.5
                    from: 0.0
                    to: 100.0
                    value: Math.max(0, Math.min(100, jobRow.percentVal))
                    fillColor: jobRow.isSuspended ? Theme.amber : Theme.accent
                    trackColor: Theme.surface
                  }
                }
              }
            }
          }
        }

        // Empty State
        Item {
          visible: root.totalCount === 0 && root.jobsList.length === 0
          width: parent.width
          height: Math.max(140, flickable.height - 24)

          Column {
            anchors.centerIn: parent
            spacing: 6

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰂜"
              font.family: root.monoFont
              font.pixelSize: 28
              color: root.t.ink3
              opacity: 0.6
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "All Caught Up"
              font.family: Theme.displayFont
              font.pixelSize: Theme.fontBase
              font.weight: Font.SemiBold
              color: root.t.ink2
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No notifications to show"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontXs
              color: root.t.ink3
            }
          }
        }

        // Notification Groups Stream
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

            readonly property string latestTime: {
              if (!notifsList || notifsList.length === 0) return "";
              void root.service.timeTick;
              const newest = notifsList[0];
              return root.service ? root.service.timeAgo(newest.timestamp) : (newest ? (newest.timeAgo || "") : "");
            }

            readonly property string groupOrigin: {
              if (!notifsList || notifsList.length === 0) return "";
              const orig = notifsList[0].originName || "";
              if (orig.length > 0 && orig.toLowerCase() !== groupDelegate.appName.toLowerCase()) {
                return orig;
              }
              return "";
            }

            width: scrollCol.width
            spacing: 6

            // Group Header Bar (Only shown when 2+ items belong to this app)
            RowLayout {
              visible: groupDelegate.totalGroupCount > 1
              width: parent.width
              height: 24
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
                font.family: Theme.displayFont
                font.pixelSize: Theme.fontSm
                font.weight: Font.SemiBold
                font.letterSpacing: -0.1
                color: root.t.ink1
              }

              // Count Badge
              Rectangle {
                implicitWidth: groupCountTxt.implicitWidth + 8
                implicitHeight: 16
                radius: 8
                color: root.t.accentBg

                Text {
                  id: groupCountTxt
                  anchors.centerIn: parent
                  text: groupDelegate.totalGroupCount.toString()
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontXs
                  font.weight: Font.SemiBold
                  color: root.t.accent
                }
              }

              // Origin Device Tag (e.g. phone via KDE Connect)
              Rectangle {
                visible: groupDelegate.groupOrigin.length > 0
                implicitWidth: origTagRow.implicitWidth + 8
                implicitHeight: 16
                radius: 4
                color: root.t.hoverWash
                border.color: root.t.lineMuted
                border.width: 1

                Row {
                  id: origTagRow
                  anchors.centerIn: parent
                  spacing: 3

                  Text {
                    text: "󰄡"
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: root.t.ink3
                  }

                  Text {
                    text: groupDelegate.groupOrigin
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontXs
                    color: root.t.ink2
                  }
                }
              }

              Text {
                visible: groupDelegate.latestTime.length > 0
                text: "· " + groupDelegate.latestTime
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: root.t.ink3
              }

              Item { Layout.fillWidth: true }

              TextButton {
                visible: groupDelegate.totalGroupCount > 2
                text: groupDelegate.isExpanded ? "Show less" : `+${groupDelegate.totalGroupCount - 2} more`
                fs: Theme.fontXs
                fg: root.t.accent
                onClicked: {
                  if (root.service) root.service.toggleGroupExpanded(groupDelegate.appName);
                }
              }

              TextButton {
                text: "Clear"
                fs: Theme.fontXs
                fg: root.t.ink3
                onClicked: {
                  if (root.service && groupDelegate.appName) root.service.clearApp(groupDelegate.appName);
                }
              }
            }

            // Stack of Notification Cards
            Column {
              width: parent.width
              spacing: 6

              Repeater {
                model: groupDelegate.visibleItems

                delegate: Rectangle {
                  id: notifCard
                  required property var modelData
                  required property int index

                  readonly property var notif: notifCard.modelData
                  readonly property string notifIcon: notif ? (notif.notifIcon || "") : ""
                  readonly property string originName: notif ? (notif.originName || "") : ""
                  readonly property bool hasDefaultAction: notif ? (notif.hasDefaultAction === true) : false
                  readonly property string summaryText: notif ? (notif.summary || "Notification") : ""
                  readonly property string bodyText: notif ? (notif.body || "") : ""
                  readonly property string imageSrc: notif ? (notif.image || "") : ""
                  readonly property var rawActionsList: notif ? (notif.actions || []) : []
                  readonly property bool hasReplyAction: {
                    for (let i = 0; i < rawActionsList.length; i++) {
                      const id = String(rawActionsList[i].identifier || "").toLowerCase();
                      const txt = String(rawActionsList[i].text || "").toLowerCase();
                      if (id === "reply" || id === "inline-reply" || txt === "reply") return true;
                    }
                    return false;
                  }
                  readonly property string replyActionIdentifier: {
                    for (let i = 0; i < rawActionsList.length; i++) {
                      const id = String(rawActionsList[i].identifier || "").toLowerCase();
                      const txt = String(rawActionsList[i].text || "").toLowerCase();
                      if (id === "reply" || id === "inline-reply" || txt === "reply") return rawActionsList[i].identifier;
                    }
                    return "inline-reply";
                  }
                  readonly property var actionsList: {
                    if (!hasReplyAction) return rawActionsList;
                    const filtered = [];
                    for (let i = 0; i < rawActionsList.length; i++) {
                      const id = String(rawActionsList[i].identifier || "").toLowerCase();
                      const txt = String(rawActionsList[i].text || "").toLowerCase();
                      if (id !== "reply" && id !== "inline-reply" && txt !== "reply") {
                        filtered.push(rawActionsList[i]);
                      }
                    }
                    return filtered;
                  }
                  readonly property string timeStr: {
                    void root.service.timeTick;
                    return root.service ? root.service.timeAgo(notif.timestamp) : "Just now";
                  }
                  readonly property int urgencyVal: notif ? (notif.urgency ?? 1) : 1
                  readonly property bool isCritical: notifCard.urgencyVal === 2
                  readonly property bool isLow: notifCard.urgencyVal === 0
                  readonly property bool showReplyField: (notif && notif.hasInlineReply === true) || hasReplyAction
                  readonly property string replyPlaceholder: notif ? (notif.inlineReplyPlaceholder || "Reply…") : "Reply…"
                  readonly property bool hasActionIcons: notif ? notif.hasActionIcons === true : false
                  readonly property string desktopEntry: notif ? (notif.desktopEntry || "") : ""
                  readonly property string categoryStr: notif ? (notif.category || "") : ""
                  readonly property var urlsList: notif ? (notif.urls || []) : []
                  readonly property string primaryUrl: notifCard.urlsList.length > 0 ? String(notifCard.urlsList[0]) : ""

                  readonly property string resolvedEventIcon: root.resolveEventIcon(notifIcon)
                  readonly property bool showEventIcon: resolvedEventIcon.length > 0 && resolvedEventIcon !== groupDelegate.resolvedAppIcon

                  readonly property bool isCommunication: {
                    if (notifCard.showReplyField) return true;
                    if (notifCard.originName.length > 0) return true;
                    const cat = notifCard.categoryStr.toLowerCase();
                    if (cat.startsWith("im") || cat === "email.arrived") return true;
                    const app = groupDelegate.appName.toLowerCase();
                    const desk = notifCard.desktopEntry.toLowerCase();
                    const known = ["whatsapp", "zapfast", "telegram", "signal", "discord", "slack", "element", "matrix", "messages", "skype", "kdeconnect"];
                    for (let i = 0; i < known.length; i++) {
                      if (app.includes(known[i]) || desk.includes(known[i])) return true;
                    }
                    return false;
                  }

                  Image {
                    id: ccMediaProbe
                    visible: false
                    source: notifCard.imageSrc
                    asynchronous: true
                  }

                  readonly property bool isWideImage: ccMediaProbe.status === Image.Ready &&
                    (ccMediaProbe.implicitWidth >= 160) &&
                    (ccMediaProbe.implicitHeight > 0) &&
                    ((ccMediaProbe.implicitWidth / ccMediaProbe.implicitHeight) >= 1.35)

                  readonly property bool hasRawImage: notifCard.imageSrc.length > 0 &&
                    (notifCard.urlsList.length === 0 || !root.isImageUrl(notifCard.primaryUrl))

                  readonly property string avatarSource: {
                    if (notifCard.notifIcon.length > 0 && notifCard.notifIcon !== groupDelegate.resolvedAppIcon) {
                      return root.resolveEventIcon(notifCard.notifIcon);
                    }
                    if (notifCard.isCommunication && notifCard.hasRawImage && !notifCard.isWideImage) {
                      return notifCard.imageSrc;
                    }
                    return "";
                  }

                  readonly property bool hasAvatar: notifCard.avatarSource.length > 0

                  readonly property bool isBannerImage: notifCard.hasRawImage &&
                    !notifCard.hasAvatar &&
                    notifCard.isWideImage

                  readonly property bool isThumbnailImage: notifCard.hasRawImage &&
                    !notifCard.hasAvatar &&
                    !notifCard.isWideImage

                  readonly property bool isSingleInGroup: groupDelegate.totalGroupCount === 1

                  // Refined title logic: cleanly distinguishes sender from device / app origin
                  readonly property string senderName: {
                    const summ = (notifCard.summaryText || "").trim();
                    const app = (groupDelegate.appName || "").trim().toLowerCase();
                    if (summ.length > 0 && summ.toLowerCase() !== app) {
                      return summ;
                    }
                    return "";
                  }

                  width: parent.width
                  implicitHeight: notifCardCol.implicitHeight + 18
                  radius: 8
                  color: notifMouse.containsMouse ? root.t.hoverFill : root.t.surfaceElevated
                  border.color: notifCard.isCritical ? root.t.red : (notifMouse.containsMouse ? root.t.cardBorder : root.t.lineMuted)
                  border.width: 1

                  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                  MouseArea {
                    id: notifMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: notifCard.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                      if (notifCard.hasDefaultAction && root.service) {
                        root.service.invokeDefaultAction(notifCard.notif);
                      }
                    }
                  }

                  Column {
                    id: notifCardCol
                    anchors {
                      top: parent.top
                      left: parent.left
                      right: parent.right
                      margins: 9
                    }
                    spacing: 6

                    // Card Top Row
                    RowLayout {
                      width: parent.width
                      height: 20
                      spacing: 6

                      // If single in group: show App Icon + App Name
                      IconImage {
                        visible: notifCard.isSingleInGroup && groupDelegate.resolvedAppIcon.length > 0
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        source: groupDelegate.resolvedAppIcon
                        asynchronous: true
                      }

                      Text {
                        visible: notifCard.isSingleInGroup && !groupDelegate.resolvedAppIcon
                        text: groupDelegate.appName.charAt(0).toUpperCase()
                        font.family: Theme.roundedFont
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.DemiBold
                        color: root.t.accent
                      }

                      Text {
                        visible: notifCard.isSingleInGroup
                        Layout.maximumWidth: 140
                        text: groupDelegate.appName
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.SemiBold
                        color: root.t.ink1
                        elide: Text.ElideRight
                      }

                      // Origin Device Tag if single (e.g. "OnePlus 13R")
                      Rectangle {
                        visible: notifCard.isSingleInGroup && notifCard.originName.length > 0 && notifCard.originName.toLowerCase() !== groupDelegate.appName.toLowerCase()
                        implicitWidth: singleOrigTag.implicitWidth + 8
                        implicitHeight: 16
                        radius: 4
                        color: root.t.hoverWash
                        border.color: root.t.lineMuted
                        border.width: 1

                        Row {
                          id: singleOrigTag
                          anchors.centerIn: parent
                          spacing: 3
                          Text {
                            text: "󰄡"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: root.t.ink3
                          }
                          Text {
                            text: notifCard.originName
                            font.family: Theme.textFont
                            font.pixelSize: Theme.fontXs
                            color: root.t.ink2
                          }
                        }
                      }

                      // If part of group: show Sender / Title directly in the top row
                      Text {
                        visible: !notifCard.isSingleInGroup
                        Layout.maximumWidth: 220
                        text: notifCard.senderName.length > 0 ? notifCard.senderName : notifCard.summaryText
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.SemiBold
                        color: notifCard.isCritical ? root.t.red : root.t.ink1
                        elide: Text.ElideRight
                      }

                      // Urgency pill
                      Rectangle {
                        visible: notifCard.isCritical
                        implicitWidth: critTxt.implicitWidth + 8
                        implicitHeight: 15
                        radius: 3
                        color: root.t.errBg

                        Text {
                          id: critTxt
                          anchors.centerIn: parent
                          text: "CRITICAL"
                          font.family: Theme.textFont
                          font.pixelSize: 9
                          font.weight: Font.Bold
                          color: root.t.red
                        }
                      }

                      Item { Layout.fillWidth: true }

                      // Timestamp
                      Text {
                        text: notifCard.timeStr
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontXs
                        color: root.t.ink3
                      }

                      // Settings / Dismiss action buttons
                      IconButton {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter
                        glyph: "󰒓"
                        fs: 11
                        btnSize: 20
                        fg: root.t.ink3
                        visible: notifCard.notif ? notifCard.notif.hasConfigureAction === true : false
                        tooltip: (notifCard.notif && notifCard.notif.configureLabel) || "Configure"
                        onClicked: {
                          if (root.service && notifCard.notif) {
                            root.service.invokeAction(notifCard.notif, "settings");
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
                          if (root.service && notifCard.notif && notifCard.notif.id !== undefined) {
                            root.service.dismissNotification(notifCard.notif.id);
                          }
                        }
                      }
                    }

                    // Content Row: Avatar + Body + Media Thumbnail
                    RowLayout {
                      width: parent.width
                      spacing: 8

                      // Circular Avatar or Event Icon
                      ClippingRectangle {
                        visible: (notifCard.hasAvatar && ccAvatarImg.status !== Image.Error) || (!notifCard.isSingleInGroup && notifCard.showEventIcon)
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: root.t.inset

                        Image {
                          id: ccAvatarImg
                          visible: notifCard.hasAvatar
                          anchors.fill: parent
                          source: notifCard.avatarSource
                          fillMode: Image.PreserveAspectCrop
                          asynchronous: true
                        }

                        IconImage {
                          visible: (!notifCard.hasAvatar || ccAvatarImg.status === Image.Error) && notifCard.showEventIcon
                          anchors.centerIn: parent
                          width: 18
                          height: 18
                          source: notifCard.resolvedEventIcon
                          asynchronous: true
                        }
                      }

                      Column {
                        Layout.fillWidth: true
                        spacing: 2

                        // For single notification: Sender title if present
                        Text {
                          visible: notifCard.isSingleInGroup && notifCard.senderName.length > 0
                          width: parent.width
                          text: notifCard.senderName
                          font.family: Theme.textFont
                          font.pixelSize: Theme.fontSm
                          font.weight: Font.SemiBold
                          color: notifCard.isCritical ? root.t.red : (notifCard.isLow ? root.t.ink2 : root.t.ink1)
                          elide: Text.ElideRight
                        }

                        TextEdit {
                          visible: notifCard.bodyText.length > 0
                          width: parent.width
                          text: notifCard.bodyText
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
                      }

                      // Thumbnail Image
                      ClippingRectangle {
                        visible: notifCard.isThumbnailImage && ccThumbImg.status === Image.Ready
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 6
                        color: root.t.inset

                        Image {
                          id: ccThumbImg
                          anchors.fill: parent
                          source: notifCard.imageSrc
                          fillMode: Image.PreserveAspectCrop
                          asynchronous: true
                        }
                      }
                    }

                    // Wide Banner Image
                    ClippingRectangle {
                      visible: notifCard.isBannerImage && notifImg.status === Image.Ready
                      width: parent.width
                      implicitHeight: Math.min(130, Math.max(64, Math.round(((parent && parent.width > 0) ? parent.width : 300) * (notifImg.implicitHeight > 0 && notifImg.implicitWidth > 0 ? (notifImg.implicitHeight / notifImg.implicitWidth) : 0.5))))
                      radius: 6
                      color: root.t.inset

                      Image {
                        id: notifImg
                        anchors.fill: parent
                        source: notifCard.imageSrc
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                      }
                    }

                    // File / URL Attachment Card
                    Rectangle {
                      visible: notifCard.urlsList.length > 0
                      width: parent.width
                      implicitHeight: ccFileCol.implicitHeight + 12
                      radius: 6
                      color: root.t.inset
                      border.color: root.t.lineMuted
                      border.width: 1

                      Column {
                        id: ccFileCol
                        anchors {
                          left: parent.left
                          right: parent.right
                          top: parent.top
                          margins: 6
                        }
                        spacing: 6

                        RowLayout {
                          width: parent.width
                          spacing: 8

                          Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 4
                            color: root.t.surface
                            clip: true

                            Image {
                              id: fileThumbImg
                              visible: root.isImageUrl(notifCard.primaryUrl) && fileThumbImg.status === Image.Ready
                              anchors.centerIn: parent
                              width: parent.width - 4
                              height: parent.height - 4
                              source: notifCard.primaryUrl
                              fillMode: Image.PreserveAspectFit
                              asynchronous: true
                            }

                            Text {
                              visible: !root.isImageUrl(notifCard.primaryUrl) || fileThumbImg.status !== Image.Ready
                              anchors.centerIn: parent
                              text: "󰈔"
                              font.family: root.monoFont
                              font.pixelSize: Theme.iconSm
                              color: root.t.accent
                            }
                          }

                          Column {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                              width: parent.width
                              text: root.fileNameOf(notifCard.primaryUrl)
                              font.family: Theme.textFont
                              font.pixelSize: Theme.fontXs
                              font.weight: Font.Medium
                              color: root.t.ink1
                              elide: Text.ElideMiddle
                            }

                            Text {
                              width: parent.width
                              text: root.fileDirOf(notifCard.primaryUrl)
                              font.family: Theme.textFont
                              font.pixelSize: 10
                              color: root.t.ink3
                              elide: Text.ElideMiddle
                            }
                          }
                        }

                        Row {
                          spacing: 6

                          Rectangle {
                            implicitWidth: openTxt.implicitWidth + 12
                            implicitHeight: 20
                            radius: 4
                            color: openMouse.containsMouse ? root.t.accentBg : root.t.surface
                            border.color: openMouse.containsMouse ? root.t.accent : root.t.lineMuted
                            border.width: 1

                            Text {
                              id: openTxt
                              anchors.centerIn: parent
                              text: "Open"
                              font.family: Theme.textFont
                              font.pixelSize: 10
                              font.weight: Font.Medium
                              color: openMouse.containsMouse ? root.t.accent : root.t.ink1
                            }

                            MouseArea {
                              id: openMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: Qt.openUrlExternally(notifCard.primaryUrl)
                            }
                          }

                          Rectangle {
                            implicitWidth: folderTxt.implicitWidth + 12
                            implicitHeight: 20
                            radius: 4
                            color: folderMouse.containsMouse ? root.t.accentBg : root.t.surface
                            border.color: folderMouse.containsMouse ? root.t.accent : root.t.lineMuted
                            border.width: 1

                            Text {
                              id: folderTxt
                              anchors.centerIn: parent
                              text: "Folder"
                              font.family: Theme.textFont
                              font.pixelSize: 10
                              font.weight: Font.Medium
                              color: folderMouse.containsMouse ? root.t.accent : root.t.ink1
                            }

                            MouseArea {
                              id: folderMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                const dir = root.fileDirOf(notifCard.primaryUrl);
                                if (dir.length > 0) Qt.openUrlExternally("file://" + dir);
                              }
                            }
                          }

                          Rectangle {
                            implicitWidth: copyTxt.implicitWidth + 12
                            implicitHeight: 20
                            radius: 4
                            color: copyMouse.containsMouse ? root.t.accentBg : root.t.surface
                            border.color: copyMouse.containsMouse ? root.t.accent : root.t.lineMuted
                            border.width: 1

                            Text {
                              id: copyTxt
                              anchors.centerIn: parent
                              text: "Copy Path"
                              font.family: Theme.textFont
                              font.pixelSize: 10
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
                                  root.service.copyToClipboard(root.cleanFilePath(notifCard.primaryUrl));
                                }
                              }
                            }
                          }
                        }
                      }
                    }

                    // Actions and Reply Row
                    RowLayout {
                      visible: notifCard.actionsList.length > 0 || notifCard.showReplyField
                      width: parent.width
                      spacing: 6

                      Item {
                        Layout.fillWidth: true
                        visible: !notifCard.showReplyField
                      }

                      // Sleek Integrated Inline Reply Capsule
                      Rectangle {
                        visible: notifCard.showReplyField
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 15
                        color: root.t.inset
                        border.color: ccReplyInput.activeFocus ? root.t.accent : root.t.lineMuted
                        border.width: 1

                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: 10
                          anchors.rightMargin: 4
                          spacing: 6

                          Text {
                            text: "󰅒"
                            font.family: root.monoFont
                            font.pixelSize: 12
                            color: ccReplyInput.activeFocus ? root.t.accent : root.t.ink3
                          }

                          TextInput {
                            id: ccReplyInput
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.textFont
                            font.pixelSize: Theme.fontSm
                            color: root.t.ink1
                            clip: true
                            onAccepted: {
                              if (root.service && text.trim().length > 0) {
                                if (notifCard.notif && notifCard.notif.hasInlineReply === true) {
                                  root.service.sendInlineReply(notifCard.notif, text);
                                } else {
                                  root.service.invokeAction(notifCard.notif, notifCard.replyActionIdentifier);
                                }
                                text = "";
                              }
                            }

                            Text {
                              visible: parent.text.length === 0
                              anchors.verticalCenter: parent.verticalCenter
                              text: notifCard.replyPlaceholder
                              font.family: Theme.textFont
                              font.pixelSize: Theme.fontSm
                              color: root.t.ink3
                            }
                          }

                          // Send Action Icon
                          Rectangle {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            radius: 11
                            color: ccReplyInput.text.trim().length > 0 ? root.t.accent : "transparent"

                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                            Text {
                              anchors.centerIn: parent
                              text: "󰏲"
                              font.family: root.monoFont
                              font.pixelSize: 11
                              color: ccReplyInput.text.trim().length > 0 ? root.t.darkInk : root.t.ink3
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: ccReplyInput.text.trim().length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                              onClicked: {
                                if (root.service && ccReplyInput.text.trim().length > 0) {
                                  if (notifCard.notif && notifCard.notif.hasInlineReply === true) {
                                    root.service.sendInlineReply(notifCard.notif, ccReplyInput.text);
                                  } else {
                                    root.service.invokeAction(notifCard.notif, notifCard.replyActionIdentifier);
                                  }
                                  ccReplyInput.text = "";
                                }
                              }
                            }
                          }
                        }
                      }

                      Repeater {
                        model: notifCard.actionsList

                        delegate: Rectangle {
                          id: ccActPill
                          required property var modelData
                          implicitWidth: ccActRow.implicitWidth + 14
                          implicitHeight: 30
                          radius: 5
                          color: ccActMouse.containsMouse ? root.t.accentBg : root.t.hoverWash
                          border.color: ccActMouse.containsMouse ? root.t.accent : root.t.lineMuted
                          border.width: 1

                          Row {
                            id: ccActRow
                            anchors.centerIn: parent
                            spacing: 4

                            IconImage {
                              visible: notifCard.hasActionIcons
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
                              if (root.service) root.service.invokeAction(notifCard.notif, ccActPill.modelData.identifier);
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
    }
  }
}
