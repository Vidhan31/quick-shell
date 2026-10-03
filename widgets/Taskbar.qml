pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.utils
import "../theme"

Item {
  id: root

  property ShellScreen currentScreen: null
  property PanelWindow barWindow: null
  property bool filterByScreen: false

  property var rawWindows: []

  implicitHeight: 26
  implicitWidth: root.rawWindows.length > 0 ? (root.rawWindows.length * 28 + (root.rawWindows.length - 1) * 4) : 0

  IconResolver {
    id: iconResolver
  }

  Process {
    id: bridgeProcess
    command: ["python3", "-u", Quickshell.shellPath("bridges/kwin-taskbar-bridge.py")]
    running: true
    stdinEnabled: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: data => {
        let trimmed = data.trim();
        if (!trimmed || !trimmed.startsWith("[")) return;
        try {
          let list = JSON.parse(trimmed);
          root.rawWindows = Array.isArray(list) ? list : [];
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

  ListView {
    id: windowList
    anchors.fill: parent
    orientation: ListView.Horizontal
    clip: true
    spacing: 4
    boundsBehavior: Flickable.StopAtBounds

    model: ScriptModel {
      values: root.rawWindows
      comparisonMode: ObjectComparison.Structure
    }

    delegate: Item {
      id: windowDelegate
      required property var modelData

      readonly property var it: windowDelegate.modelData
      readonly property string winAppId: it ? (it.appId || "") : ""
      readonly property string winTitle: it ? (it.title || "") : ""
      readonly property string windowId: it ? (it.id || it.winId || "") : ""
      readonly property bool isActivated: it ? !!it.active : false
      readonly property bool isMinimized: it ? !!it.minimized : false
      readonly property bool isMaximized: it ? !!it.maximized : false
      readonly property bool isFullscreen: it ? !!it.fullscreen : false

      readonly property string iconSrc: iconResolver.resolveIcon(windowDelegate.winAppId, windowDelegate.winTitle)

      width: 28
      height: 26

      Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radiusBase
        color: mouseArea.pressed ? Theme.pressWash : (mouseArea.containsMouse ? Theme.hoverWash : "transparent")

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
      }

      Text {
        anchors.centerIn: parent
        text: (windowDelegate.winAppId ? windowDelegate.winAppId.charAt(0).toUpperCase() : "?")
        color: Theme.ink1
        font.pixelSize: Theme.fontBase
        font.bold: true
        opacity: appIcon.opacity
        visible: appIcon.status === Image.Error || !windowDelegate.iconSrc
      }

      IconImage {
        id: appIcon
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        implicitSize: 18
        asynchronous: true
        source: windowDelegate.iconSrc
        opacity: windowDelegate.isActivated ? 1.0 : (mouseArea.containsMouse ? 1.0 : 0.85)

        Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }
      }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: windowDelegate.isActivated ? 14 : (mouseArea.containsMouse ? 8 : 0)
        height: 2
        radius: 1
        color: {
          if (windowDelegate.isActivated) return Theme.accent;
          if (mouseArea.containsMouse) return Theme.ink2;
          return "transparent";
        }

        Behavior on width { NumberAnimation { duration: Theme.durationFast } }
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
      }

      Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 2
        anchors.rightMargin: 2
        width: 4
        height: 4
        radius: 2
        color: windowDelegate.isFullscreen ? Theme.red : (windowDelegate.isMaximized ? Theme.green : "transparent")
        visible: windowDelegate.isFullscreen || windowDelegate.isMaximized
      }

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
