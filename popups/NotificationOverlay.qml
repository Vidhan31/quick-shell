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
  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

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
     The docs warn OnDemand "may cause the shell window to retain focus over
     another window unexpectedly", so we escalate only while an inline-reply
     field is engaged and drop back to None otherwise. Clicks and dismissals
     never need focus. */
  property int _kbHolders: 0
  WlrLayershell.keyboardFocus: _kbHolders > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  color: "transparent"
  implicitWidth: Theme.popupWidthSm
  implicitHeight: toastCol.implicitHeight
  visible: activeList.length > 0 || activeJobsList.length > 0

  /* The theme alias. Elsewhere `t` is qualified as root.t because
     ComponentBehavior: Bound drops it from nested scopes, but the four
     `const t = toastItem.toast` locals in the reply handlers below shadow it,
     so a blanket `t.` -> `root.t.` rewrite is unsafe in this file. Keep those
     locals or rename them to `toast`. */
  readonly property var t: Theme

  Column {
    id: toastCol
    width: parent.width
    spacing: 8

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
          implicitHeight: jobCardCol.implicitHeight + 20
          radius: Theme.radiusCard
          color: root.t.bg
          border.color: root.t.cardBorder
          border.width: 1

          ColumnLayout {
            id: jobCardCol
            anchors {
              top: parent.top
              left: parent.left
              right: parent.right
              margins: 10
            }
            spacing: 0

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredHeight: 32
              spacing: 8

              Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: Theme.radiusBase
                color: root.t.surface
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
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.DemiBold
                  color: root.t.accent
                }
              }

              Column {
                Layout.fillWidth: true
                spacing: 0
                Text {
                  width: parent.width
                  text: jobItem.appName
                  font.family: Theme.displayFont
                  font.pixelSize: Theme.fontMd
                  font.weight: Font.DemiBold
                  color: root.t.ink1
                  elide: Text.ElideRight
                }
                Text {
                  text: jobItem.isSuspended ? "Paused" : (jobItem.speedText.length > 0 ? (jobItem.speedText + (jobItem.etaText.length > 0 ? " · " + jobItem.etaText : "")) : "In progress")
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontXs
                  color: jobItem.isSuspended ? root.t.amber : root.t.ink3
                  elide: Text.ElideRight
                }
              }

              IconButton {
                visible: jobItem.canSuspend
                glyph: jobItem.isSuspended ? "󰐊" : "󰏤"
                fs: 13
                btnSize: 26
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
                fs: 13
                btnSize: 26
                tooltip: "Cancel task"
                onClicked: {
                  if (root.jobService) root.jobService.cancelJob(jobItem.jobId);
                }
              }
            }

            Item { Layout.preferredHeight: 8; Layout.fillWidth: true }

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: jobBodyCol.implicitHeight + 16
              radius: Theme.radiusChip
              color: root.t.surface

              Column {
                id: jobBodyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 6

                Text {
                  width: parent.width
                  text: jobItem.summaryText
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.DemiBold
                  color: root.t.ink1
                  elide: Text.ElideRight
                }

                Text {
                  visible: jobItem.bodyText.length > 0
                  width: parent.width
                  text: jobItem.bodyText
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontSm
                  color: root.t.ink2
                  elide: Text.ElideMiddle
                }

                Rectangle {
                  width: parent.width
                  height: 6
                  radius: 3
                  color: root.t.inset
                  clip: true

                  Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, jobItem.percentVal)) / 100
                    height: parent.height
                    radius: 3
                    color: jobItem.isSuspended ? root.t.amber : root.t.accent
                    Behavior on width { NumberAnimation { duration: 150 } }
                  }
                }

                RowLayout {
                  width: parent.width
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
                    font.weight: Font.DemiBold
                    color: root.t.ink2
                    font.family: root.monoFont
                  }
                }
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
        readonly property var actionsList: toast ? (toast.actions || []) : []
        readonly property int urgencyVal: toast ? (toast.urgency ?? 1) : 1
        readonly property bool isCritical: toastItem.urgencyVal === 2
        readonly property bool isLow: toastItem.urgencyVal === 0
        // Service-provided timeout (category + expireTimeout aware, 0 = persist).
        readonly property int timeoutMs: isCritical ? 10000 : (toast && toast.timeout > 0 ? toast.timeout : (isLow ? 3500 : 5000))
        readonly property bool persistToast: isCritical || (toast ? toast.timeout === 0 : false)
        readonly property string timeStr: {
          void root.service.timeTick;
          return (root.service && toast) ? root.service.timeAgo(toast.timestamp) : "Just now";
        }
        readonly property bool hasInlineReply: toast ? toast.hasInlineReply === true : false
        readonly property string replyPlaceholder: toast ? (toast.inlineReplyPlaceholder || "Reply…") : "Reply…"
        readonly property bool hasActionIcons: toast ? toast.hasActionIcons === true : false
        readonly property string desktopEntry: toast ? (toast.desktopEntry || "") : ""
        readonly property var urlsList: toast ? (toast.urls || []) : []
        readonly property string primaryUrl: toastItem.urlsList.length > 0 ? String(toastItem.urlsList[0]) : ""

        readonly property string resolvedAppIcon: root.resolveAppIcon(desktopEntry, appName, appIcon)
        readonly property string resolvedEventIcon: root.resolveEventIcon(notifIcon)
        readonly property bool showEventIcon: resolvedEventIcon.length > 0 && resolvedEventIcon !== resolvedAppIcon

        property bool isHovered: false
        property bool replyActive: false
        property bool _kbHeld: false
        // Exit state: fade+slide on the render thread, then remove from model.
        property bool exiting: false

        function requestDismiss() {
          requestExit(null);
        }
        // Play the exit fade/slide, then run cb (or plain dismiss).
        // Captures ids/strings up front so delayed service calls stay valid.
        function requestExit(cb) {
          if (toastItem.exiting) return;
          toastItem.exiting = true;
          dismissTimer.stop();
          toastItem._pendingExit = cb || null;
          exitTimer.restart();
        }

        /* Hold keyboard focus only while the inline-reply field is engaged:
           acquire on hover so the click can land, release when hover leaves.
           Hover alone never moves focus, because KWin focuses OnDemand
           surfaces on click only. */
        function _syncKbHold() {
          const need = toastItem.hasInlineReply && (toastItem.isHovered || toastItem.replyActive);
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
        onHasInlineReplyChanged: _syncKbHold()
        Component.onDestruction: {
          if (toastItem._kbHeld) {
            toastItem._kbHeld = false;
            root._kbHolders = Math.max(0, root._kbHolders - 1);
          }
        }

        width: toastCol.width
        implicitHeight: toastCard.implicitHeight
        /* Render-thread entry: XAnimator/OpacityAnimator run off the GUI
           thread. Sibling displacement animates via y. Exit animates the
           inner card (see toastCard) so entry animators never fight it. */
        Behavior on y { YAnimator { duration: 200; easing.type: Easing.OutCubic } }

        XAnimator on x {
          from: 64
          to: 0
          duration: 220
          easing.type: Easing.OutCubic
        }
        OpacityAnimator on opacity {
          from: 0
          to: 1
          duration: 180
          easing.type: Easing.OutCubic
        }

        // Hover holds the toast; leaving restarts the countdown.
        // Typing a reply also holds it.
        property real progress: 1.0

        NumberAnimation on progress {
          from: 1.0
          to: 0.0
          duration: Math.max(500, toastItem.timeoutMs)
          running: !toastItem.persistToast && !toastItem.replyActive && !toastItem.exiting && !toastItem.isHovered
          paused: toastItem.isHovered || toastItem.replyActive
        }

        Timer {
          id: dismissTimer
          interval: toastItem.timeoutMs
          running: !toastItem.persistToast && !toastItem.replyActive && !toastItem.exiting
          onTriggered: toastItem.requestDismiss()
        }
        // Lets the exit fade/slide play before removing from the model.
        property var _pendingExit: null
        Timer {
          id: exitTimer
          interval: 190
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
          implicitHeight: cardCol.implicitHeight + 20
          height: implicitHeight
          x: toastItem.exiting ? 64 : 0
          opacity: toastItem.exiting ? 0 : 1
          radius: Theme.radiusCard
          color: root.t.bg
          border.color: root.t.cardBorder
          border.width: 1
          clip: true

          Behavior on x { XAnimator { duration: 190; easing.type: Easing.InOutCubic } }
          Behavior on opacity { OpacityAnimator { duration: 180; easing.type: Easing.OutCubic } }

          Rectangle {
            id: countdownBar
            visible: !toastItem.persistToast
            z: 3
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            height: 2
            width: parent.width * Math.max(0, Math.min(1.0, toastItem.progress))
            color: toastItem.isCritical ? root.t.red : root.t.accent
            opacity: 0.7
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
                const t = toastItem.toast;
                toastItem.requestExit(() => root.service.invokeDefaultAction(t));
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
                  const t = toastItem.toast;
                  toastItem.requestExit(() => root.service.invokeDefaultAction(t));
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
              margins: 10
            }
            spacing: 0

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredHeight: 32
              spacing: 8

              Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: Theme.radiusBase
                color: root.t.surface
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
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.DemiBold
                  color: root.t.accent
                }
              }

              Column {
                Layout.fillWidth: true
                spacing: 0
                Text {
                  width: parent.width
                  text: (toastItem.originName.length > 0 && toastItem.originName.toLowerCase() !== toastItem.appName.toLowerCase()) ? (toastItem.appName + " · " + toastItem.originName) : toastItem.appName
                  font.family: Theme.displayFont
                  font.pixelSize: Theme.fontMd
                  font.weight: Font.DemiBold
                  color: root.t.ink1
                  elide: Text.ElideRight
                }
                Text {
                  text: toastItem.isCritical ? "Critical · " + toastItem.timeStr : toastItem.timeStr
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontXs
                  color: toastItem.isCritical ? root.t.red : root.t.ink3
                  elide: Text.ElideRight
                }
              }

              IconButton {
                glyph: "󰒓"
                fs: 13
                btnSize: 26
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
                fs: 13
                btnSize: 26
                tooltip: "Dismiss notification"
                onClicked: toastItem.requestDismiss()
              }
            }

            Item { Layout.preferredHeight: 8; Layout.fillWidth: true }

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: bodyCol.implicitHeight + 16
              radius: Theme.radiusChip
              color: root.t.surface

              Column {
                id: bodyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 6

                RowLayout {
                  width: parent.width
                  spacing: 8

                  Rectangle {
                    visible: toastItem.showEventIcon
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.radiusBase
                    color: root.t.inset
                    IconImage {
                      anchors.centerIn: parent
                      width: 20
                      height: 20
                      source: toastItem.resolvedEventIcon
                      asynchronous: true
                    }
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                      width: parent.width
                      text: toastItem.summaryText
                      textFormat: Text.PlainText
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontMd
                      font.weight: Font.Medium
                      color: toastItem.isCritical ? root.t.red : (toastItem.isLow ? root.t.ink2 : root.t.ink1)
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }

                    TextEdit {
                      visible: toastItem.bodyText.length > 0
                      width: parent.width
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
                }

                ClippingRectangle {
                  visible: toastItem.imageSrc.length > 0 && toastImg.status === Image.Ready && (toastItem.urlsList.length === 0 || !root.isImageUrl(toastItem.primaryUrl))
                  width: parent.width
                  height: Math.min(100, Math.max(48, toastImg.implicitHeight > 0 ? toastImg.implicitHeight : 80))
                  radius: Theme.radiusBase
                  color: root.t.inset

                  Image {
                    id: toastImg
                    anchors.centerIn: parent
                    width: parent.width - 8
                    height: parent.height - 8
                    source: toastItem.imageSrc
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }
                }

                Rectangle {
                  visible: toastItem.urlsList.length > 0
                  width: parent.width
                  implicitHeight: fileRowCol.implicitHeight + 12
                  radius: Theme.radiusBase
                  color: root.t.inset
                  border.color: root.t.cardBorder
                  border.width: 1

                  Column {
                    id: fileRowCol
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
                  visible: toastItem.actionsList.length > 0
                  width: parent.width
                }

                Row {
                  visible: toastItem.actionsList.length > 0
                  width: parent.width
                  spacing: 6
                  Repeater {
                    model: toastItem.actionsList
                    delegate: Rectangle {
                      id: toastActPill
                      required property var modelData
                      implicitWidth: toastActRow.implicitWidth + 16
                      implicitHeight: 24
                      radius: Theme.radiusChip
                      color: toastActMouse.containsMouse ? root.t.accentBg : root.t.surface
                      border.color: toastActMouse.containsMouse ? root.t.accent : root.t.cardBorder
                      border.width: 1

                      Row {
                        id: toastActRow
                        anchors.centerIn: parent
                        spacing: 4
                        IconImage {
                          visible: toastItem.hasActionIcons
                          width: 12
                          height: 12
                          anchors.verticalCenter: parent.verticalCenter
                          source: root.resolveActionIcon(toastActPill.modelData.identifier)
                          asynchronous: true
                        }
                        Text {
                          text: toastActPill.modelData.text || "Action"
                          font.family: Theme.textFont
                          font.pixelSize: Theme.fontXs
                          font.weight: Font.Medium
                          color: toastActMouse.containsMouse ? root.t.accent : root.t.ink1
                        }
                      }

                      MouseArea {
                        id: toastActMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.service) {
                            const t = toastItem.toast;
                            const ident = toastActPill.modelData.identifier;
                            if (t && t.resident === true) {
                              root.service.invokeAction(t, ident);
                            } else {
                              toastItem.requestExit(() => root.service.invokeAction(t, ident));
                            }
                          }
                        }
                      }
                    }
                  }
                }

                Hairline {
                  visible: toastItem.hasInlineReply
                  width: parent.width
                }

                RowLayout {
                  visible: toastItem.hasInlineReply
                  width: parent.width
                  spacing: 6
                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: Theme.radiusBase
                    color: root.t.inset
                    border.color: replyInput.activeFocus ? root.t.accent : root.t.line
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
                    TextInput {
                      id: replyInput
                      anchors.fill: parent
                      anchors.leftMargin: 8
                      anchors.rightMargin: 8
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
                          const t = toastItem.toast;
                          const msg = text;
                          toastItem.requestExit(() => root.service.sendInlineReply(t, msg));
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
                  TextButton {
                    text: (toastItem.toast && toastItem.toast.replySubmitButtonText) ? toastItem.toast.replySubmitButtonText : "Send"
                    fg: root.t.accent
                    onClicked: {
                      if (root.service && replyInput.text.trim().length > 0) {
                        const t = toastItem.toast;
                        const msg = replyInput.text;
                        toastItem.requestExit(() => root.service.sendInlineReply(t, msg));
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
  }
}
