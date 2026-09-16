pragma ComponentBehavior: Bound
// Taskbar.qml — Running GUI applications (opened windows) taskbar for Quickshell.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Item {
  id: root

  property ShellScreen currentScreen: null
  property PanelWindow barWindow: null
  property bool filterByScreen: false

  // ListModel populated from KWin bridge
  ListModel {
    id: windowModel
  }

  implicitHeight: 26
  implicitWidth: windowModel.count > 0 ? (windowModel.count * 28 + (windowModel.count - 1) * 4) : 0
  width: implicitWidth
  height: implicitHeight

  IconResolver {
    id: iconResolver
  }

  // KWin bridge process for KDE Plasma Wayland sessions
  Process {
    id: bridgeProcess
    command: ["python3", "-u", "/home/dev/Projects/quick-shell/kwin-taskbar-bridge.py"]
    running: true
    stdinEnabled: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: data => {
        let trimmed = data.trim();
        if (!trimmed || !trimmed.startsWith("[")) return;
        try {
          let list = JSON.parse(trimmed);
          windowModel.clear();
          for (let i = 0; i < list.length; i++) {
            let it = list[i];
            windowModel.append({
              appId: it.appId || "",
              title: it.title || "",
              winId: it.id || "",
              active: !!it.active,
              minimized: !!it.minimized,
              maximized: !!it.maximized,
              fullscreen: !!it.fullscreen
            });
          }
        } catch (e) {
          console.warn("Taskbar: Failed to parse KWin window list:", e);
        }
      }
    }

    onRunningChanged: {
      if (!running) {
        restartTimer.start();
      }
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: bridgeProcess.running = true
  }

  // Live list of opened windows
  ListView {
    id: windowList
    anchors.fill: parent
    orientation: ListView.Horizontal
    clip: true
    spacing: 4
    boundsBehavior: Flickable.StopAtBounds

    model: windowModel

    delegate: Item {
      id: windowDelegate
      required property var modelData
      required property string appId
      required property string title
      required property string winId
      required property bool active
      required property bool minimized
      required property bool maximized
      required property bool fullscreen

      readonly property string winAppId: windowDelegate.appId
      readonly property string winTitle: windowDelegate.title
      readonly property string windowId: windowDelegate.winId
      readonly property bool isActivated: windowDelegate.active
      readonly property bool isMinimized: windowDelegate.minimized
      readonly property bool isMaximized: windowDelegate.maximized
      readonly property bool isFullscreen: windowDelegate.fullscreen

      readonly property string iconSrc: iconResolver.resolveIcon(windowDelegate.winAppId, windowDelegate.winTitle)

      width: 28
      height: 26

      // Transparent background, no border
      Rectangle {
        id: bg
        anchors.fill: parent
        radius: 4
        color: mouseArea.containsMouse ? "#1affffff" : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }
      }

      // Fallback text if icon fails to load
      Text {
        anchors.centerIn: parent
        text: (windowDelegate.winAppId ? windowDelegate.winAppId.charAt(0).toUpperCase() : "?")
        color: "#cdd6f4"
        font.pixelSize: 12
        font.bold: true
        opacity: appIcon.opacity
        visible: appIcon.status === Image.Error || !windowDelegate.iconSrc
      }

      // Application Icon (rendered with Quickshell.Widgets.IconImage)
      IconImage {
        id: appIcon
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        width: 18
        height: 18
        asynchronous: true
        source: windowDelegate.iconSrc
        opacity: windowDelegate.isActivated ? 1.0 : (mouseArea.containsMouse ? 1.0 : 0.85)

        Behavior on opacity { NumberAnimation { duration: 150 } }
      }

      // State indicator at the bottom (active / hovered)
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: windowDelegate.isActivated ? 14 : (mouseArea.containsMouse ? 8 : 0)
        height: 2
        radius: 1
        color: {
          if (windowDelegate.isActivated) return "#89b4fa"; // Catppuccin Blue
          if (mouseArea.containsMouse) return "#cdd6f4";
          return "transparent";
        }

        Behavior on width { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      // Small badge for Fullscreen or Maximized state
      Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 2
        anchors.rightMargin: 2
        width: 4
        height: 4
        radius: 2
        color: windowDelegate.isFullscreen ? "#f38ba8" : (windowDelegate.isMaximized ? "#a6e3a1" : "transparent")
        visible: windowDelegate.isFullscreen || windowDelegate.isMaximized
      }

      // Interaction area: Left-click (activate/minimize), Middle-click (close), Right-click (maximize)
      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: mouse => {
          if (mouse.button === Qt.LeftButton) {
            if (windowDelegate.windowId) {
              if (windowDelegate.isActivated) {
                bridgeProcess.write("MINIMIZE " + windowDelegate.windowId + "\n");
              } else {
                bridgeProcess.write("ACTIVATE " + windowDelegate.windowId + "\n");
              }
            }
          } else if (mouse.button === Qt.MiddleButton) {
            if (windowDelegate.windowId) {
              bridgeProcess.write("CLOSE " + windowDelegate.windowId + "\n");
            }
          } else if (mouse.button === Qt.RightButton) {
            if (windowDelegate.windowId) {
              bridgeProcess.write("MAXIMIZE " + windowDelegate.windowId + "\n");
            }
          }
        }
      }
    }
  }
}
