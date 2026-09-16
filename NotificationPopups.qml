pragma ComponentBehavior: Bound
// NotificationPopups.qml — Floating on-screen notification toast popups.
// Renders active toast notifications in the top-right corner with smooth entrance animations,
// auto-dismiss progress timers (pauses on hover), drag/swipe dismiss, and action triggers.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

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
  implicitWidth: 360
  implicitHeight: toastCol.implicitHeight
  visible: activeList.length > 0

  Behavior on implicitHeight {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Column {
    id: toastCol
    width: parent.width
    spacing: 10

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
        readonly property int timeoutMs: urgencyVal === 2 ? 10000 : (urgencyVal === 0 ? 3500 : 5000)

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

        Rectangle {
          id: toastCard
          width: parent.width
          implicitHeight: cardCol.implicitHeight + 24
          height: implicitHeight
          x: toastItem.dragOffset
          radius: 10
          color: "#1e1e2e"
          border.color: toastItem.urgencyVal === 2 ? "#f38ba8" : (toastItem.isHovered ? "#585b70" : "#313244")
          border.width: 1
          clip: true

          Behavior on border.color { ColorAnimation { duration: 120 } }
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
              if (progressBar.progressAnim.running) progressBar.progressAnim.paused = true;
            }

            onExited: {
              toastItem.isHovered = false;
              if (progressBar.progressAnim.running) progressBar.progressAnim.paused = false;
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
              margins: 12
            }
            spacing: 6

            // Header: App icon + App name + Close button
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredHeight: 20
              spacing: 6

              IconImage {
                id: toastAppIcon
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: toastItem.resolvedIcon
                asynchronous: true
              }

              Text {
                visible: toastAppIcon.status === Image.Error || !toastItem.resolvedIcon
                text: toastItem.appName.charAt(0).toUpperCase()
                font.family: root.monoFont
                font.pixelSize: 11
                font.bold: true
                color: "#89b4fa"
              }

              Text {
                Layout.fillWidth: true
                text: toastItem.appName
                font.family: root.monoFont
                font.pixelSize: 11
                font.bold: true
                color: "#a6adc8"
                elide: Text.ElideRight
              }

              // Close button (Red Circle with X)
              Rectangle {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                radius: 8
                color: closeBtnMouse.containsMouse ? "#f38ba8" : "#eb4d4b"

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
                  id: closeBtnMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.service) root.service.dismissToast(toastItem.toast.id);
                  }
                }
              }
            }

            // Summary
            Text {
              Layout.fillWidth: true
              text: toastItem.summaryText
              font.family: root.monoFont
              font.pixelSize: 12
              font.bold: true
              color: "#ffffff"
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }

            // Body
            Text {
              visible: toastItem.bodyText.length > 0
              Layout.fillWidth: true
              text: toastItem.bodyText
              font.family: root.monoFont
              font.pixelSize: 11
              color: "#bac2de"
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }

            // Image Preview
            Rectangle {
              visible: toastItem.imageSrc.length > 0
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(80, width * 0.45)
              radius: 6
              color: "#181825"
              clip: true

              Image {
                anchors.fill: parent
                source: toastItem.imageSrc
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
            }

            // Action Buttons
            RowLayout {
              visible: toastItem.actionsList.length > 0
              Layout.fillWidth: true

              Item {
                Layout.fillWidth: true
              }

              Repeater {
                model: toastItem.actionsList

                delegate: Rectangle {
                  id: toastActionBtn
                  required property var modelData
                  required property int index

                  implicitWidth: toastActionLabel.implicitWidth + 18
                  implicitHeight: 24
                  radius: 4
                  color: toastActionMouse.containsMouse ? "#3b3e52" : "#2b2d3d"
                  border.color: toastActionMouse.containsMouse ? "#89b4fa" : "#45475a"
                  border.width: 1

                  Behavior on color { ColorAnimation { duration: 120 } }
                  Behavior on border.color { ColorAnimation { duration: 120 } }

                  Text {
                    id: toastActionLabel
                    anchors.centerIn: parent
                    text: toastActionBtn.modelData.text || "Action"
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: toastActionMouse.containsMouse ? "#ffffff" : "#cdd6f4"
                  }

                  MouseArea {
                    id: toastActionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.service) {
                        root.service.invokeAction(toastItem.toast, toastActionBtn.modelData.identifier);
                      }
                    }
                  }
                }
              }
            }
          }

          // Timeout Progress Bar at bottom of card
          Rectangle {
            id: progressBar
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            height: 2
            color: toastItem.urgencyVal === 2 ? "#f38ba8" : "#89b4fa"
            opacity: 0.8
            width: parent.width * progressFraction

            property real progressFraction: 1.0
            property alias progressAnim: anim

            NumberAnimation on progressFraction {
              id: anim
              from: 1.0
              to: 0.0
              duration: toastItem.timeoutMs
              running: true
              onFinished: {
                if (root.service) root.service.dismissToast(toastItem.toast.id);
              }
            }
          }
        }
      }
    }
  }
}
