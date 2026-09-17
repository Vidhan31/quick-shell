pragma ComponentBehavior: Bound
// NotificationPopups.qml — Quiet floating toast popups.
// Same card, washes and type scale as the control centers:
// icon tile + title/subtitle header, content grouped in a surface block,
// hairline-separated actions, no progress chrome (hover holds the toast).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.utils

PanelWindow {
  id: root

  property var service: null
  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  IconResolver {
    id: iconResolver
  }

  function resolveNotifIcon(iconName, appName) {
    if (iconName) {
      const p = iconResolver.resolveNamedOrPath(iconName);
      if (p) return p;
    }
    if (appName) {
      const p = iconResolver.resolveIcon(appName, "");
      if (p) return p;
    }
    return iconResolver.resolveStockIcon("preferences-desktop-notification") || iconResolver.resolveStockIcon("dialog-information") || iconResolver.fallbackIcon();
  }

  readonly property var activeList: service ? (service.activeToasts || []) : []

  screen: Quickshell.screens[0]
  anchors {
    top: true
    right: true
  }
  margins.top: 38
  margins.right: 12

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.exclusiveZone: 0
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  color: "transparent"
  implicitWidth: 340
  implicitHeight: toastCol.implicitHeight
  visible: activeList.length > 0

  Behavior on implicitHeight {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

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
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
  }

  component Hairline: Rectangle {
    color: t.line
    height: 1
  }

  // Borderless text button.
  component TextBtn: Rectangle {
    id: tb
    signal clicked
    property string text: ""
    property color fg: t.ink2
    property int fs: 11
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

  Column {
    id: toastCol
    width: parent.width
    spacing: 8

    Repeater {
      model: root.activeList

      delegate: Item {
        id: toastItem
        required property var modelData
        required property int index

        readonly property var toast: toastItem.modelData
        readonly property string appName: toast ? (toast.appName || "Application") : "Application"
        readonly property string appIcon: toast ? (toast.appIcon || "") : ""
        readonly property string summaryText: toast ? (toast.summary || "Notification") : ""
        readonly property string bodyText: toast ? (toast.body || "") : ""
        readonly property string imageSrc: toast ? (toast.image || "") : ""
        readonly property var actionsList: toast ? (toast.actions || []) : []
        readonly property int urgencyVal: toast ? (toast.urgency || 1) : 1
        readonly property bool isCritical: toastItem.urgencyVal === 2
        readonly property int timeoutMs: isCritical ? 10000 : (urgencyVal === 0 ? 3500 : 5000)
        readonly property string timeStr: (root.service && toast) ? root.service.timeAgo(toast.timestamp) : "Just now"

        readonly property string resolvedIcon: root.resolveNotifIcon(appIcon, appName)

        property real dragOffset: 0
        property bool isDragging: false
        property bool isHovered: false

        width: toastCol.width
        implicitHeight: toastCard.implicitHeight
        height: implicitHeight

        // Smooth slide-in entrance
        NumberAnimation on x {
          from: 80
          to: 0
          duration: 200
          easing.type: Easing.OutCubic
        }

        OpacityAnimator on opacity {
          from: 0
          to: 1
          duration: 180
        }

        // Hover holds the toast; leaving restarts the countdown.
        Timer {
          id: dismissTimer
          interval: toastItem.timeoutMs
          running: true
          onTriggered: {
            if (root.service) root.service.dismissToast(toastItem.toast.id);
          }
        }

        Rectangle {
          id: toastCard
          width: parent.width
          implicitHeight: cardCol.implicitHeight + 20
          height: implicitHeight
          x: toastItem.dragOffset
          radius: 14
          color: t.bg
          border.color: "#26272F"
          border.width: 1
          clip: true

          Behavior on x {
            enabled: !toastItem.isDragging
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
          }

          MouseArea {
            id: toastHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.MiddleButton

            onEntered: {
              toastItem.isHovered = true;
              dismissTimer.stop();
            }

            onExited: {
              toastItem.isHovered = false;
              dismissTimer.restart();
            }

            onClicked: mouse => {
              if (mouse.button === Qt.MiddleButton) {
                if (root.service) root.service.dismissToast(toastItem.toast.id);
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

            // Header: icon tile + title/subtitle left, dismiss right.
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredHeight: 32
              spacing: 8

              Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 8
                color: t.surface
                IconImage {
                  id: toastAppIcon
                  anchors.centerIn: parent
                  width: 16
                  height: 16
                  source: toastItem.resolvedIcon
                  asynchronous: true
                }
                Text {
                  visible: toastAppIcon.status === Image.Error || !toastItem.resolvedIcon
                  anchors.centerIn: parent
                  text: toastItem.appName.charAt(0).toUpperCase()
                  font.pixelSize: 12
                  font.weight: Font.DemiBold
                  color: t.accent
                }
              }

              Column {
                Layout.fillWidth: true
                spacing: 0
                Text {
                  width: parent.width
                  text: toastItem.appName
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                  color: t.ink1
                  elide: Text.ElideRight
                }
                Text {
                  text: toastItem.isCritical ? "Critical · " + toastItem.timeStr : toastItem.timeStr
                  font.pixelSize: 10
                  color: toastItem.isCritical ? t.red : t.ink3
                  elide: Text.ElideRight
                }
              }

              IconBtn {
                glyph: "󰅖"
                fs: 13
                btnSize: 26
                onClicked: {
                  if (root.service) root.service.dismissToast(toastItem.toast.id);
                }
              }
            }

            Item { Layout.preferredHeight: 8; Layout.fillWidth: true }

            // Content grouped in a surface block.
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: bodyCol.implicitHeight + 16
              radius: 10
              color: t.surface

              Column {
                id: bodyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 3

                Text {
                  width: parent.width
                  text: toastItem.summaryText
                  font.pixelSize: 13
                  font.weight: Font.Medium
                  color: toastItem.isCritical ? t.red : t.ink1
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                Text {
                  visible: toastItem.bodyText.length > 0
                  width: parent.width
                  text: toastItem.bodyText
                  font.pixelSize: 12
                  color: t.ink2
                  wrapMode: Text.WordWrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                }

                Rectangle {
                  visible: toastItem.imageSrc.length > 0
                  width: parent.width
                  height: Math.min(80, width * 0.45)
                  radius: 8
                  color: t.inset
                  clip: true

                  Image {
                    anchors.fill: parent
                    source: toastItem.imageSrc
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
                    TextBtn {
                      required property var modelData
                      required property int index
                      text: modelData.text || "Action"
                      onClicked: {
                        if (root.service) {
                          root.service.invokeAction(toastItem.toast, modelData.identifier);
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
