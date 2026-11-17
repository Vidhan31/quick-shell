pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Plugins.IconResolver
import "../theme"
import "../components"

PanelWindow {
  id: root

  property var service: null
  property var jobService: null
  readonly property string monoFont: Theme.mono
  readonly property int overlayWidth: 384

  IconResolver {
    id: iconResolver
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

  function resolveActionIcon(identifier) {
    if (!identifier) return "";
    return iconResolver.resolveNamedOrPath(identifier);
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

  readonly property var activeList: service ? (service.activeToasts || []) : []
  readonly property var activeJobsList: jobService ? (jobService.activeJobs || []) : []

  screen: Quickshell.screens[0]
  anchors {
    top: true
    right: true
  }
  margins.top: 38 // qmllint disable unqualified
  margins.right: 12

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.exclusiveZone: 0
  /* None by default, so toasts never steal keyboard focus from the active app.
     Escalate only while an inline-reply field is engaged and drop back to None otherwise. */
  property int _kbHolders: 0
  WlrLayershell.keyboardFocus: _kbHolders > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  color: "transparent"
  readonly property Item toastColItem: toastCol
  BackgroundEffect.blurRegion: Region {
    item: toastCol // qmllint disable unqualified
    radius: Theme.radiusCard
  }
  implicitWidth: root.overlayWidth
  implicitHeight: toastCol.implicitHeight
  visible: activeList.length > 0 || activeJobsList.length > 0

  readonly property var t: Theme

  Column {
    id: toastCol
    width: parent.width
    spacing: 10

    Repeater {
      model: ScriptModel {
        values: root.activeJobsList
        objectProp: "id"
        comparisonMode: ObjectComparison.Identity
      }

      delegate: Item {
        id: jobItem
        required property var modelData
        required property int index

        readonly property var job: jobItem.modelData
        readonly property int jobId: job ? (job.id || 0) : 0
        readonly property string appName: job ? (job.appName || "Task") : "Task"
        readonly property string desktopEntry: job ? (job.desktopEntry || "") : ""
        readonly property string appIcon: job ? (job.appIcon || "") : ""
        readonly property string summaryText: job ? (job.summary || "Task Progress") : ""
        readonly property string bodyText: job ? (job.body || "") : ""
        readonly property int percentVal: job ? (job.percent || 0) : 0
        readonly property string speedText: job ? (job.formattedSpeed || "") : ""
        readonly property string bytesText: job ? (job.formattedBytes || "") : ""
        readonly property string etaText: job ? (job.eta || "") : ""
        readonly property bool isSuspended: job ? (job.isSuspended === true) : false
        readonly property bool canCancel: job ? (job.killable !== false) : true
        readonly property bool canSuspend: job ? (job.suspendable === true) : false

        readonly property string resolvedAppIcon: root.resolveAppIcon(desktopEntry, appName, appIcon)

        width: parent.width
        implicitHeight: jobCard.implicitHeight

        Rectangle {
          id: jobCard
          width: parent.width
          implicitHeight: jobCardCol.implicitHeight + 24
          radius: Theme.radiusCard
          color: root.t.popupGlass
          border.color: root.t.cardBorder
          border.width: 1.5
          clip: true

          ColumnLayout {
            id: jobCardCol
            anchors {
              top: parent.top
              left: parent.left
              right: parent.right
              margins: 12
            }
            spacing: 8

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredHeight: 24
              spacing: 8

              Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: Theme.radiusBase
                color: root.t.surfaceElevated
                IconImage {
                  id: jobAppIcon
                  anchors.centerIn: parent
                  width: 16
                  height: 16
                  source: jobItem.resolvedAppIcon
                  asynchronous: true
                }
                Text {
                  visible: jobAppIcon.status === Image.Error || !jobItem.resolvedAppIcon
                  anchors.centerIn: parent
                  text: jobItem.appName.charAt(0).toUpperCase()
                  font.family: Theme.roundedFont
                  font.pixelSize: Theme.fontSm
                  font.weight: Font.DemiBold
                  color: root.t.accent
                }
              }

              Text {
                text: jobItem.appName
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSm
                font.weight: Font.SemiBold
                color: root.t.ink1
                elide: Text.ElideRight
                Layout.maximumWidth: 160
              }

              Text {
                text: "·"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: root.t.ink3
              }

              Text {
                text: jobItem.isSuspended ? "Paused" : (jobItem.speedText.length > 0 ? (jobItem.speedText + (jobItem.etaText.length > 0 ? " · " + jobItem.etaText : "")) : "In progress")
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: jobItem.isSuspended ? root.t.amber : root.t.ink3
                elide: Text.ElideRight
              }

              Item { Layout.fillWidth: true }

              IconButton {
                visible: jobItem.canSuspend
                glyph: jobItem.isSuspended ? "󰐊" : "󰏤"
                fs: 12
                btnSize: 22
                tooltip: jobItem.isSuspended ? "Resume task" : "Pause task"
                onClicked: {
                  if (root.jobService) {
                    if (jobItem.isSuspended) root.jobService.resumeJob(jobItem.jobId);
                    else root.jobService.suspendJob(jobItem.jobId);
                  }
                }
              }

              IconButton {
                visible: jobItem.canCancel
                glyph: "󰅖"
                fs: 12
                btnSize: 22
                fg: root.t.ink3
                tooltip: "Cancel task"
                onClicked: {
                  if (root.jobService) root.jobService.cancelJob(jobItem.jobId);
                }
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 3

              Text {
                Layout.fillWidth: true
                text: jobItem.summaryText
                font.family: Theme.textFont
                font.pixelSize: Theme.fontMd
                font.weight: Font.SemiBold
                color: root.t.ink1
                elide: Text.ElideRight
              }

              Text {
                visible: jobItem.bodyText.length > 0
                Layout.fillWidth: true
                text: jobItem.bodyText
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSm
                color: root.t.ink2
                elide: Text.ElideMiddle
              }
            }

            ProgressBar {
              Layout.fillWidth: true
              implicitHeight: 6
              from: 0.0
              to: 100.0
              value: Math.max(0, Math.min(100, jobItem.percentVal))
              fillColor: jobItem.isSuspended ? Theme.amber : Theme.accent
              trackColor: Theme.inset
            }

            RowLayout {
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: jobItem.bytesText.length > 0 ? jobItem.bytesText : (jobItem.percentVal + "%")
                font.pixelSize: Theme.fontXs
                color: root.t.ink3
                font.family: root.monoFont
              }
              Text {
                text: jobItem.percentVal + "%"
                font.pixelSize: Theme.fontXs
                font.weight: Font.SemiBold
                color: root.t.ink2
                font.family: root.monoFont
              }
            }
          }
        }
      }
    }

    Repeater {
      model: ScriptModel {
        values: root.activeList
        objectProp: "id"
        comparisonMode: ObjectComparison.Identity
      }

      delegate: Item {
        id: toastItem
        required property var modelData
        required property int index

        readonly property var toast: toastItem.modelData
        readonly property string appName: toast ? (toast.appName || "Application") : "Application"
        readonly property string appIcon: toast ? (toast.appIcon || "") : ""
        readonly property string notifIcon: toast ? (toast.notifIcon || "") : ""
        readonly property string originName: toast ? (toast.originName || "") : ""
        readonly property bool hasDefaultAction: toast ? (toast.hasDefaultAction === true) : false
        readonly property string summaryText: toast ? (toast.summary || "Notification") : ""
        readonly property string bodyText: toast ? (toast.body || "") : ""
        readonly property string imageSrc: toast ? (toast.image || "") : ""
        readonly property var rawActionsList: toast ? (toast.actions || []) : []
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
        readonly property int urgencyVal: toast ? (toast.urgency ?? 1) : 1
        readonly property bool isCritical: toastItem.urgencyVal === 2
        readonly property bool isLow: toastItem.urgencyVal === 0
        readonly property int timeoutMs: isCritical ? 10000 : (toast && toast.timeout > 0 ? toast.timeout : (isLow ? 3500 : 5000))
        readonly property bool persistToast: isCritical || (toast ? toast.timeout === 0 : false)
        readonly property string timeStr: {
          void root.service.timeTick;
          return (root.service && toast) ? root.service.timeAgo(toast.timestamp) : "Just now";
        }
        readonly property bool showReplyField: (toast && toast.hasInlineReply === true) || hasReplyAction
        readonly property string replyPlaceholder: toast ? (toast.inlineReplyPlaceholder || "Reply…") : "Reply…"
        readonly property bool hasActionIcons: toast ? toast.hasActionIcons === true : false
        readonly property string desktopEntry: toast ? (toast.desktopEntry || "") : ""
        readonly property string categoryStr: toast ? (toast.category || "") : ""
        readonly property var urlsList: toast ? (toast.urls || []) : []
        readonly property string primaryUrl: toastItem.urlsList.length > 0 ? String(toastItem.urlsList[0]) : ""

        readonly property string resolvedAppIcon: root.resolveAppIcon(desktopEntry, appName, appIcon)
        readonly property string resolvedEventIcon: root.resolveEventIcon(notifIcon)
        readonly property bool showEventIcon: resolvedEventIcon.length > 0 && resolvedEventIcon !== resolvedAppIcon

        readonly property bool isCommunication: {
          if (toastItem.showReplyField) return true;
          if (toastItem.originName.length > 0) return true;
          const cat = toastItem.categoryStr.toLowerCase();
          if (cat.startsWith("im") || cat === "email.arrived") return true;
          const app = toastItem.appName.toLowerCase();
          const desk = toastItem.desktopEntry.toLowerCase();
          const known = ["whatsapp", "zapfast", "telegram", "signal", "discord", "slack", "element", "matrix", "messages", "skype", "kdeconnect"];
          for (let i = 0; i < known.length; i++) {
            if (app.includes(known[i]) || desk.includes(known[i])) return true;
          }
          return false;
        }

        Image {
          id: toastMediaProbe
          visible: false
          source: toastItem.imageSrc
          asynchronous: true
        }

        readonly property bool isWideImage: toastMediaProbe.status === Image.Ready &&
          (toastMediaProbe.implicitWidth >= 160) &&
          (toastMediaProbe.implicitHeight > 0) &&
          ((toastMediaProbe.implicitWidth / toastMediaProbe.implicitHeight) >= 1.35)

        readonly property bool hasRawImage: toastItem.imageSrc.length > 0 &&
          (toastItem.urlsList.length === 0 || !root.isImageUrl(toastItem.primaryUrl))

        readonly property string avatarSource: {
          if (toastItem.notifIcon.length > 0 && toastItem.notifIcon !== toastItem.appIcon) {
            return root.resolveEventIcon(toastItem.notifIcon);
          }
          if (toastItem.isCommunication && toastItem.hasRawImage && !toastItem.isWideImage) {
            return toastItem.imageSrc;
          }
          return "";
        }

        readonly property bool hasAvatar: toastItem.avatarSource.length > 0

        readonly property bool isBannerImage: toastItem.hasRawImage &&
          !toastItem.hasAvatar &&
          toastItem.isWideImage

        readonly property bool isThumbnailImage: toastItem.hasRawImage &&
          !toastItem.hasAvatar &&
          !toastItem.isWideImage

        property bool isHovered: false
        property bool replyActive: false
        property bool _kbHeld: false
        property bool exiting: false

        function requestDismiss() {
          requestExit(null);
        }
        function requestExit(cb) {
          if (toastItem.exiting) return;
          toastItem.exiting = true;
          dismissTimer.stop();
          toastItem._pendingExit = cb || null;
          exitTimer.restart();
        }

        function _syncKbHold() {
          const need = toastItem.showReplyField && (toastItem.isHovered || toastItem.replyActive);
          if (need && !toastItem._kbHeld) {
            toastItem._kbHeld = true;
            root._kbHolders++;
          } else if (!need && toastItem._kbHeld) {
            toastItem._kbHeld = false;
            root._kbHolders = Math.max(0, root._kbHolders - 1);
          }
        }
        onIsHoveredChanged: _syncKbHold()
        onReplyActiveChanged: _syncKbHold()
        onShowReplyFieldChanged: _syncKbHold()
        Component.onDestruction: {
          if (toastItem._kbHeld) {
            toastItem._kbHeld = false;
            root._kbHolders = Math.max(0, root._kbHolders - 1);
          }
        }

        width: toastCol.width
        implicitHeight: toastItem.exiting ? 0 : toastCard.implicitHeight
        clip: true

        Behavior on implicitHeight {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on y {
          YAnimator { duration: 180; easing.type: Easing.OutCubic }
        }

        XAnimator on x {
          from: 48
          to: 0
          duration: 200
          easing.type: Easing.OutCubic
        }
        OpacityAnimator on opacity {
          from: 0
          to: 1
          duration: 160
          easing.type: Easing.OutCubic
        }

        property real progress: 1.0

        NumberAnimation on progress {
          from: 1.0
          to: 0.0
          duration: Math.max(500, toastItem.timeoutMs)
          running: !toastItem.persistToast && !toastItem.replyActive && !toastItem.exiting && !toastItem.isHovered
        }

        Timer {
          id: dismissTimer
          interval: toastItem.timeoutMs
          running: !toastItem.persistToast && !toastItem.replyActive && !toastItem.exiting
          onTriggered: toastItem.requestDismiss()
        }
        property var _pendingExit: null
        Timer {
          id: exitTimer
          interval: 180
          repeat: false
          onTriggered: {
            const cb = toastItem._pendingExit;
            toastItem._pendingExit = null;
            if (cb) cb();
            else if (root.service) root.service.dismissToast(toastItem.toast.id);
          }
        }

        Rectangle {
          id: toastCard
          width: parent.width
          implicitHeight: cardCol.implicitHeight + 24
          height: implicitHeight
          x: toastItem.exiting ? 48 : 0
          opacity: toastItem.exiting ? 0 : 1
          radius: Theme.radiusCard
          color: root.t.popupGlass
          border.color: toastItem.isCritical ? root.t.red : (toastItem.isHovered ? root.t.popupBorder : root.t.cardBorder)
          border.width: 1.5
          clip: true

          Behavior on x { XAnimator { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on opacity { OpacityAnimator { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

          readonly property int _borderInset: Math.ceil(toastCard.border.width)

          Rectangle {
            id: countdownBar
            visible: !toastItem.persistToast
            anchors.bottom: parent.bottom
            anchors.bottomMargin: toastCard._borderInset
            anchors.left: parent.left
            anchors.leftMargin: toastCard._borderInset
            width: Math.max(0, Math.min(parent.width - (toastCard._borderInset * 2), Math.round((parent.width - (toastCard._borderInset * 2)) * toastItem.progress)))
            height: 2
            color: toastItem.isCritical ? root.t.red : root.t.accent
            opacity: 0.9
            z: 10
          }

          DropArea {
            anchors.fill: parent
            onEntered: {
              if (toastItem.hasDefaultAction) {
                dropActivationTimer.restart();
              }
            }
            onExited: dropActivationTimer.stop()
          }

          Timer {
            id: dropActivationTimer
            interval: 350
            repeat: false
            onTriggered: {
              if (toastItem.hasDefaultAction && root.service) {
                const toast = toastItem.toast;
                toastItem.requestExit(() => root.service.invokeDefaultAction(toast));
              }
            }
          }

          MouseArea {
            id: toastHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: toastItem.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor

            onEntered: {
              toastItem.isHovered = true;
              dismissTimer.stop();
            }

            onExited: {
              toastItem.isHovered = false;
              if (!toastItem.replyActive && !toastItem.persistToast && !toastItem.exiting) dismissTimer.restart();
            }

            onClicked: mouse => {
              if (mouse.button === Qt.MiddleButton) {
                toastItem.requestDismiss();
              } else if (mouse.button === Qt.LeftButton) {
                if (toastItem.hasDefaultAction && root.service) {
                  const toast = toastItem.toast;
                  toastItem.requestExit(() => root.service.invokeDefaultAction(toast));
                }
              }
            }
          }

          ColumnLayout {
            id: cardCol
            z: 2
            anchors {
              top: parent.top
              left: parent.left
              right: parent.right
              margins: 12
            }
            spacing: 8

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredHeight: 24
              spacing: 8

              Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: Theme.radiusBase
                color: root.t.surfaceElevated

                IconImage {
                  id: toastAppIcon
                  anchors.centerIn: parent
                  width: 16
                  height: 16
                  source: toastItem.resolvedAppIcon
                  asynchronous: true
                }
                Text {
                  visible: toastAppIcon.status === Image.Error || !toastItem.resolvedAppIcon
                  anchors.centerIn: parent
                  text: toastItem.appName.charAt(0).toUpperCase()
                  font.family: Theme.roundedFont
                  font.pixelSize: Theme.fontSm
                  font.weight: Font.DemiBold
                  color: root.t.accent
                }
              }

              Text {
                text: toastItem.appName
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSm
                font.weight: Font.SemiBold
                color: root.t.ink1
                elide: Text.ElideRight
                Layout.maximumWidth: 160
              }

              Rectangle {
                visible: toastItem.originName.length > 0 && toastItem.originName.toLowerCase() !== toastItem.appName.toLowerCase()
                implicitWidth: origRow.implicitWidth + 8
                implicitHeight: 18
                radius: Theme.radiusBase
                color: root.t.hoverWash
                border.color: root.t.lineMuted
                border.width: 1

                Row {
                  id: origRow
                  anchors.centerIn: parent
                  spacing: 4
                  Text {
                    text: "󰄡"
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: root.t.ink3
                  }
                  Text {
                    text: toastItem.originName
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontXs
                    color: root.t.ink2
                  }
                }
              }

              Text {
                text: "·"
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: root.t.ink3
              }

              Text {
                text: toastItem.isCritical ? "Critical" : toastItem.timeStr
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                font.weight: toastItem.isCritical ? Font.SemiBold : Font.Normal
                color: toastItem.isCritical ? root.t.red : root.t.ink3
                elide: Text.ElideRight
              }

              Item { Layout.fillWidth: true }

              IconButton {
                glyph: "󰒓"
                fs: 12
                btnSize: 22
                visible: toastItem.toast ? toastItem.toast.hasConfigureAction === true : false
                tooltip: (toastItem.toast && toastItem.toast.configureLabel) || "Configure"
                onClicked: {
                  if (root.service && toastItem.toast) {
                    root.service.invokeAction(toastItem.toast, "settings");
                  }
                }
              }

              IconButton {
                glyph: "󰅖"
                fs: 12
                btnSize: 22
                fg: root.t.ink3
                tooltip: "Dismiss notification"
                onClicked: toastItem.requestDismiss()
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 12

              ClippingRectangle {
                visible: (toastItem.hasAvatar && toastAvatarImg.status !== Image.Error) || toastItem.showEventIcon
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: Theme.radiusBase
                color: root.t.surfaceElevated

                Image {
                  id: toastAvatarImg
                  visible: toastItem.hasAvatar
                  anchors.fill: parent
                  source: toastItem.avatarSource
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }

                IconImage {
                  visible: (!toastItem.hasAvatar || toastAvatarImg.status === Image.Error) && toastItem.showEventIcon
                  anchors.centerIn: parent
                  width: 24
                  height: 24
                  source: toastItem.resolvedEventIcon
                  asynchronous: true
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 3

                Text {
                  Layout.fillWidth: true
                  text: toastItem.summaryText
                  textFormat: Text.PlainText
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontMd
                  font.weight: Font.SemiBold
                  color: toastItem.isCritical ? root.t.red : (toastItem.isLow ? root.t.ink2 : root.t.ink1)
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                TextEdit {
                  visible: toastItem.bodyText.length > 0
                  Layout.fillWidth: true
                  text: toastItem.bodyText
                  textFormat: TextEdit.RichText
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontBase
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

              ClippingRectangle {
                visible: toastItem.isThumbnailImage && toastThumbImg.status === Image.Ready
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: Theme.radiusBase
                color: root.t.surfaceElevated

                Image {
                  id: toastThumbImg
                  anchors.fill: parent
                  source: toastItem.imageSrc
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
              }
            }

            ClippingRectangle {
              visible: toastItem.isBannerImage && toastBannerImg.status === Image.Ready
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(140, Math.max(72, Math.round(width * (toastBannerImg.implicitHeight > 0 && toastBannerImg.implicitWidth > 0 ? (toastBannerImg.implicitHeight / toastBannerImg.implicitWidth) : 0.5))))
              radius: Theme.radiusBase
              color: root.t.surfaceElevated

              Image {
                id: toastBannerImg
                anchors.fill: parent
                source: toastItem.imageSrc
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
            }

            Rectangle {
              visible: toastItem.urlsList.length > 0
              Layout.fillWidth: true
              implicitHeight: fileRowCol.implicitHeight + 16
              radius: Theme.radiusBase
              color: root.t.surfaceElevated
              border.color: root.t.cardBorder
              border.width: 1

              Column {
                id: fileRowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 8

                RowLayout {
                  width: parent.width
                  spacing: 8

                  Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.radiusBase
                    color: root.t.inset
                    clip: true

                    Image {
                      id: toastFileThumb
                      visible: root.isImageUrl(toastItem.primaryUrl) && toastFileThumb.status === Image.Ready
                      anchors.centerIn: parent
                      width: parent.width - 4
                      height: parent.height - 4
                      source: toastItem.primaryUrl
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                    }

                    Text {
                      visible: !root.isImageUrl(toastItem.primaryUrl) || toastFileThumb.status !== Image.Ready
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
                      text: root.fileNameOf(toastItem.primaryUrl)
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontSm
                      font.weight: Font.Medium
                      color: root.t.ink1
                      elide: Text.ElideMiddle
                    }
                    Text {
                      width: parent.width
                      text: root.fileDirOf(toastItem.primaryUrl)
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
                    implicitWidth: toastOpenTxt.implicitWidth + 14
                    implicitHeight: 22
                    radius: Theme.radiusChip
                    color: toastOpenMouse.containsMouse ? root.t.accentBg : root.t.surface
                    border.color: toastOpenMouse.containsMouse ? root.t.accent : root.t.cardBorder
                    border.width: 1
                    Text {
                      id: toastOpenTxt
                      anchors.centerIn: parent
                      text: "Open"
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontXs
                      font.weight: Font.Medium
                      color: toastOpenMouse.containsMouse ? root.t.accent : root.t.ink1
                    }
                    MouseArea {
                      id: toastOpenMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Qt.openUrlExternally(toastItem.primaryUrl)
                    }
                  }
                  Rectangle {
                    implicitWidth: toastFolderTxt.implicitWidth + 14
                    implicitHeight: 22
                    radius: Theme.radiusChip
                    color: toastFolderMouse.containsMouse ? root.t.accentBg : root.t.surface
                    border.color: toastFolderMouse.containsMouse ? root.t.accent : root.t.cardBorder
                    border.width: 1
                    Text {
                      id: toastFolderTxt
                      anchors.centerIn: parent
                      text: "Folder"
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontXs
                      font.weight: Font.Medium
                      color: toastFolderMouse.containsMouse ? root.t.accent : root.t.ink1
                    }
                    MouseArea {
                      id: toastFolderMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        const dir = root.fileDirOf(toastItem.primaryUrl);
                        if (dir.length > 0) Qt.openUrlExternally("file://" + dir);
                      }
                    }
                  }
                  Rectangle {
                    implicitWidth: toastCopyTxt.implicitWidth + 14
                    implicitHeight: 22
                    radius: Theme.radiusChip
                    color: toastCopyMouse.containsMouse ? root.t.accentBg : root.t.surface
                    border.color: toastCopyMouse.containsMouse ? root.t.accent : root.t.cardBorder
                    border.width: 1
                    Text {
                      id: toastCopyTxt
                      anchors.centerIn: parent
                      text: "Copy Path"
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontXs
                      font.weight: Font.Medium
                      color: toastCopyMouse.containsMouse ? root.t.accent : root.t.ink1
                    }
                    MouseArea {
                      id: toastCopyMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.service) {
                          root.service.copyToClipboard(root.cleanFilePath(toastItem.primaryUrl));
                        }
                      }
                    }
                  }
                }
              }
            }

            Hairline {
              visible: toastItem.actionsList.length > 0 || toastItem.showReplyField
              Layout.fillWidth: true
            }

            RowLayout {
              visible: toastItem.actionsList.length > 0 || toastItem.showReplyField
              Layout.fillWidth: true
              spacing: 6

              Repeater {
                model: toastItem.actionsList
                delegate: Rectangle {
                  id: toastActPill
                  required property var modelData
                  required property int index

                  implicitWidth: toastActContent.implicitWidth + 16
                  implicitHeight: 32
                  radius: Theme.radiusBase
                  color: toastActMouse.pressed ? root.t.pressWash : (toastActMouse.containsMouse ? root.t.hoverWash : root.t.surfaceElevated)
                  border.color: toastActMouse.containsMouse ? root.t.accent : root.t.cardBorder
                  border.width: 1
                  Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                  Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                  Row {
                    id: toastActContent
                    anchors.centerIn: parent
                    spacing: 5
                    IconImage {
                      visible: toastItem.hasActionIcons
                      width: 13
                      height: 13
                      anchors.verticalCenter: parent.verticalCenter
                      source: root.resolveActionIcon(toastActPill.modelData.identifier)
                      asynchronous: true
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: toastActPill.modelData.text || "Action"
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontSm
                      font.weight: Font.Medium
                      color: toastActMouse.containsMouse ? root.t.accent : root.t.ink1
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                  }

                  MouseArea {
                    id: toastActMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.service) {
                        const toast = toastItem.toast;
                        const ident = toastActPill.modelData.identifier;
                        if (toast && toast.resident === true) {
                          root.service.invokeAction(toast, ident);
                        } else {
                          toastItem.requestExit(() => root.service.invokeAction(toast, ident));
                        }
                      }
                    }
                  }
                }
              }

              Rectangle {
                visible: toastItem.showReplyField
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Theme.radiusBase
                color: root.t.surfaceElevated
                border.color: replyInput.activeFocus ? root.t.accent : root.t.cardBorder
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                TextInput {
                  id: replyInput
                  anchors.fill: parent
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink1
                  clip: true
                  text: ""
                  onActiveFocusChanged: toastItem.replyActive = activeFocus || text.length > 0
                  onTextChanged: toastItem.replyActive = activeFocus || text.length > 0
                  onAccepted: {
                    if (root.service && text.trim().length > 0) {
                      const toast = toastItem.toast;
                      const msg = text;
                      toastItem.requestExit(() => {
                        if (toast && toast.hasInlineReply === true) {
                          root.service.sendInlineReply(toast, msg);
                        } else {
                          root.service.invokeAction(toast, toastItem.replyActionIdentifier);
                        }
                      });
                      text = "";
                      toastItem.replyActive = false;
                    }
                  }
                  Text {
                    visible: parent.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: toastItem.replyPlaceholder
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontBase
                    color: root.t.ink3
                  }
                }
              }

              PrimaryButton {
                visible: toastItem.showReplyField
                text: (toastItem.toast && toastItem.toast.replySubmitButtonText) ? toastItem.toast.replySubmitButtonText : "Send"
                glyph: "󰒭"
                glyphSize: 12
                btnSize: 32
                onClicked: {
                  if (root.service && replyInput.text.trim().length > 0) {
                    const toast = toastItem.toast;
                    const msg = replyInput.text;
                    toastItem.requestExit(() => {
                      if (toast && toast.hasInlineReply === true) {
                        root.service.sendInlineReply(toast, msg);
                      } else {
                        root.service.invokeAction(toast, toastItem.replyActionIdentifier);
                      }
                    });
                    replyInput.text = "";
                    toastItem.replyActive = false;
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
