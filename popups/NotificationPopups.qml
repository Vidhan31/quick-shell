pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.utils
import "../theme"
import "../components"

PanelWindow {
  id: root

  property var service: null
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

  readonly property var activeList: service ? (service.activeToasts || []) : []

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
  visible: activeList.length > 0

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
        readonly property int timeoutMs: toast && toast.timeout > 0 ? toast.timeout : (isCritical ? 10000 : (isLow ? 3500 : 5000))
        readonly property bool persistToast: toast ? toast.timeout === 0 : false
        readonly property string timeStr: {
          void root.service.timeTick;
          return (root.service && toast) ? root.service.timeAgo(toast.timestamp) : "Just now";
        }
        readonly property bool hasInlineReply: toast ? toast.hasInlineReply === true : false
        readonly property string replyPlaceholder: toast ? (toast.inlineReplyPlaceholder || "Reply…") : "Reply…"
        readonly property bool hasActionIcons: toast ? toast.hasActionIcons === true : false
        readonly property string desktopEntry: toast ? (toast.desktopEntry || "") : ""

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
                  text: toastItem.originName.length > 0 ? (toastItem.appName + " · " + toastItem.originName) : toastItem.appName
                  font.pixelSize: Theme.fontMd
                  font.weight: Font.DemiBold
                  color: root.t.ink1
                  elide: Text.ElideRight
                }
                Text {
                  text: toastItem.isCritical ? "Critical · " + toastItem.timeStr : toastItem.timeStr
                  font.pixelSize: Theme.fontXs
                  color: toastItem.isCritical ? root.t.red : root.t.ink3
                  elide: Text.ElideRight
                }
              }

              IconBtn {
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
                      font.pixelSize: Theme.fontMd
                      font.weight: Font.Medium
                      color: toastItem.isCritical ? root.t.red : (toastItem.isLow ? root.t.ink2 : root.t.ink1)
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }

                    Text {
                      visible: toastItem.bodyText.length > 0
                      width: parent.width
                      text: toastItem.bodyText
                      textFormat: Text.RichText
                      font.pixelSize: Theme.fontBase
                      color: root.t.ink2
                      linkColor: root.t.accent
                      wrapMode: Text.WordWrap
                      maximumLineCount: 3
                      elide: Text.ElideRight
                      onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                  }
                }

                ClippingRectangle {
                  visible: toastItem.imageSrc.length > 0
                  width: parent.width
                  height: Math.min(80, width * 0.45)
                  radius: Theme.radiusBase
                  color: root.t.inset

                  Image {
                    anchors.fill: parent
                    source: toastItem.imageSrc
                    sourceSize.width: 320
                    sourceSize.height: 160
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                  }
                }

                Hairline {
                  visible: toastItem.actionsList.length > 0
                  width: parent.width
                }

                Row {
                  visible: toastItem.actionsList.length > 0
                  width: parent.width
                  spacing: 2
                  Repeater {
                    model: toastItem.actionsList
                    delegate: Row {
                      id: toastActRow
                      required property var modelData
                      required property int index
                      spacing: 4
                      IconImage {
                        visible: toastItem.hasActionIcons
                        width: 14
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter
                        source: root.resolveActionIcon(toastActRow.modelData.identifier)
                        asynchronous: true
                      }
                      TextBtn {
                        text: toastActRow.modelData.text || "Action"
                        onClicked: {
                          if (root.service) {
                            const t = toastItem.toast;
                            const ident = toastActRow.modelData.identifier;
                            toastItem.requestExit(() => root.service.invokeAction(t, ident));
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
                        font.pixelSize: Theme.fontBase
                        color: root.t.ink3
                      }
                    }
                  }
                  TextBtn {
                    text: "Send"
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
