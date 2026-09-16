//@ pragma UseQApplication
// Shell.qml — Main Quickshell entrypoint for the desktop bar.
// Docs:
// - PanelWindow: anchors, height, color, screen
// - WlrLayershell: layer, exclusiveZone, keyboardFocus
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: root

  property string time: ""
  property string date: ""

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      const now = new Date();
      root.time = Qt.formatTime(now, "hh:mm");
      root.date = Qt.formatDate(now, "ddd, MMM d");
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: bar
      required property ShellScreen modelData
      screen: modelData

      anchors {
        top: true
        left: true
        right: true
      }
      implicitHeight: 32
      color: "#1e1e2e"

      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.exclusiveZone: 32
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // Left: CPU / MEM / GPU stats button — clicking toggles top processes popup.
      // Background highlight behind all 3 stats.
      Item {
        id: sysStatsHit
        anchors {
          left: parent.left
          verticalCenter: parent.verticalCenter
          leftMargin: 12
        }
        width: sysStats.width + 12
        height: 24

        Rectangle {
          id: sysStatsBg
          anchors.fill: parent
          radius: 6
          color: procPopup.visible ? "#45475a" : (sysStatsMouse.containsMouse ? "#3b3e52" : "#313244")
          border.color: procPopup.visible ? "#89b4fa" : (sysStatsMouse.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        SysStats {
          id: sysStats
          anchors.centerIn: parent
        }

        MouseArea {
          id: sysStatsMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked: {
            trayWidget.closePopup();
            mediaPopup.visible = false;
            calPopup.visible = false;
            tsPopup.visible = false;
            ethPopup.visible = false;
            privacyPopup.visible = false;
            procPopup.visible = !procPopup.visible;
          }
        }
      }

      PopupWindow {
        id: procPopup
        anchor.window: bar
        anchor.rect.x: sysStatsHit.x
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: topProcesses.implicitWidth
        implicitHeight: topProcesses.implicitHeight
        color: "transparent"

        TopProcesses {
          id: topProcesses
          anchors.fill: parent
        }
      }

      // Middle: Running GUI applications (opened windows) taskbar.
      // Implicit import: Taskbar.qml in the same directory is auto-available.
      Taskbar {
        id: taskbar
        barWindow: bar
        currentScreen: bar.screen
        anchors.centerIn: parent
        width: Math.min(implicitWidth, Math.max(0, bar.width - 2 * (Math.max(sysStatsHit.x + sysStatsHit.width, bar.width - (trayWidget.visible && trayWidget.width > 0 ? trayWidget.x : mediaHit.x)) + 20)))
        height: 26
      }

      // System Tray icons for background / minimized apps
      SystemTrayWidget {
        id: trayWidget
        barWindow: bar
        anchors {
          right: mediaHit.left
          rightMargin: (visible && width > 0) ? 8 : 0
          verticalCenter: parent.verticalCenter
        }
        onRequestClosePopups: {
          procPopup.visible = false;
          mediaPopup.visible = false;
          tsPopup.visible = false;
          ethPopup.visible = false;
          privacyPopup.visible = false;
          calPopup.visible = false;
        }
      }

      // Media control center hit button
      Item {
        id: mediaHit
        anchors {
          right: tsHit.left
          rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        width: mediaBarWidget.width + 16
        height: 24

        Rectangle {
          id: mediaBg
          anchors.fill: parent
          radius: 6
          color: mediaPopup.visible ? "#45475a" : (mediaMouse.containsMouse ? "#3b3e52" : "#313244")
          border.color: mediaPopup.visible ? "#89b4fa" : (mediaMouse.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        MediaBarWidget {
          id: mediaBarWidget
          anchors.centerIn: parent
        }

        MouseArea {
          id: mediaMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
              if (mediaBarWidget.activePlayer && mediaBarWidget.activePlayer.canTogglePlaying) {
                mediaBarWidget.activePlayer.togglePlaying();
              }
            } else {
              trayWidget.closePopup();
              procPopup.visible = false;
              calPopup.visible = false;
              tsPopup.visible = false;
              ethPopup.visible = false;
              privacyPopup.visible = false;
              mediaPopup.visible = !mediaPopup.visible;
            }
          }
        }
      }

      PopupWindow {
        id: mediaPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(mediaHit.x + mediaHit.width / 2 - mediaControlCenter.implicitWidth / 2, bar.width - mediaControlCenter.implicitWidth - 12))
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: mediaControlCenter.implicitWidth
        implicitHeight: mediaControlCenter.implicitHeight
        color: "transparent"

        MediaControlCenter {
          id: mediaControlCenter
          anchors.fill: parent
        }
      }

      // Tailscale hit button
      Item {
        id: tsHit
        anchors {
          right: ethHit.left
          rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        width: tsBarWidget.width + 16
        height: 24

        Rectangle {
          id: tsBg
          anchors.fill: parent
          radius: 6
          color: tsPopup.visible ? "#45475a" : (tsMouse.containsMouse ? "#3b3e52" : "#313244")
          border.color: tsPopup.visible ? "#89b4fa" : (tsMouse.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        TailscaleWidget {
          id: tsBarWidget
          anchors.centerIn: parent
        }

        MouseArea {
          id: tsMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked: {
            trayWidget.closePopup();
            procPopup.visible = false;
            mediaPopup.visible = false;
            calPopup.visible = false;
            ethPopup.visible = false;
            privacyPopup.visible = false;
            tsPopup.visible = !tsPopup.visible;
          }
        }
      }

      PopupWindow {
        id: tsPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(tsHit.x + tsHit.width / 2 - tsControlCenter.implicitWidth / 2, bar.width - tsControlCenter.implicitWidth - 12))
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: tsControlCenter.implicitWidth
        implicitHeight: tsControlCenter.implicitHeight
        color: "transparent"

        TailscaleControlCenter {
          id: tsControlCenter
          anchors.fill: parent
          tsData: tsBarWidget.tsData
          onTriggerRefresh: tsBarWidget.refresh()
        }
      }

      // Ethernet hit button — small ethernet icon reflecting current status
      Item {
        id: ethHit
        anchors {
          right: privacyHit.left
          rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        width: ethBarWidget.width + 16
        height: 24

        Rectangle {
          id: ethBg
          anchors.fill: parent
          radius: 6
          color: ethPopup.visible ? "#45475a" : (ethMouse.containsMouse ? "#3b3e52" : "#313244")
          border.color: ethPopup.visible ? "#89b4fa" : (ethMouse.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        EthernetWidget {
          id: ethBarWidget
          anchors.centerIn: parent
        }

        MouseArea {
          id: ethMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked: {
            trayWidget.closePopup();
            procPopup.visible = false;
            mediaPopup.visible = false;
            tsPopup.visible = false;
            calPopup.visible = false;
            privacyPopup.visible = false;
            ethPopup.visible = !ethPopup.visible;
          }
        }
      }

      PopupWindow {
        id: ethPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(ethHit.x + ethHit.width / 2 - ethControlCenter.implicitWidth / 2, bar.width - ethControlCenter.implicitWidth - 12))
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: ethControlCenter.implicitWidth
        implicitHeight: ethControlCenter.implicitHeight
        color: "transparent"

        EthernetControlCenter {
          id: ethControlCenter
          anchors.fill: parent
          ethData: ethBarWidget.ethData
          onTriggerRefresh: ethBarWidget.refresh()
        }
      }

      // Privacy indicators hit button — Camera and Microphone when active
      Item {
        id: privacyHit
        anchors {
          right: clockHit.left
          rightMargin: privacyWidget.hasActive ? 8 : 0
          verticalCenter: parent.verticalCenter
        }
        visible: privacyWidget.hasActive || width > 0
        width: privacyWidget.hasActive ? privacyWidget.implicitWidth : 0
        height: 24
        clip: true

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        PrivacyIndicators {
          id: privacyWidget
          anchors.centerIn: parent
          onClicked: {
            trayWidget.closePopup();
            procPopup.visible = false;
            mediaPopup.visible = false;
            calPopup.visible = false;
            ethPopup.visible = false;
            tsPopup.visible = false;
            privacyPopup.visible = !privacyPopup.visible;
          }
        }
      }

      PopupWindow {
        id: privacyPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(privacyHit.x + privacyHit.width / 2 - privacyControlCenter.implicitWidth / 2, bar.width - privacyControlCenter.implicitWidth - 12))
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: privacyControlCenter.implicitWidth
        implicitHeight: privacyControlCenter.implicitHeight
        color: "transparent"

        PrivacyControlCenter {
          id: privacyControlCenter
          anchors.fill: parent
          privacyData: privacyWidget.privacyData
        }
      }

      // Right: Clickable date / time — toggles the calendar popup below.
      // PopupWindow anchored to the bar (docs: PopupWindow anchor.window + anchor.rect).
      Item {
        id: clockHit
        anchors {
          right: parent.right
          rightMargin: 12
          verticalCenter: parent.verticalCenter
        }
        width: clockContent.width + 16
        height: 24

        Rectangle {
          id: clockBg
          anchors.fill: parent
          radius: 6
          color: calPopup.visible ? "#45475a" : (clockMouse.containsMouse ? "#3b3e52" : "#313244")
          border.color: calPopup.visible ? "#89b4fa" : (clockMouse.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        Row {
          id: clockContent
          anchors.centerIn: parent
          spacing: 8

          Text {
            text: root.date
            color: "#a6adc8"
            font.pixelSize: 13
            font.family: "JetBrainsMono Nerd Font Mono"
          }

          Text {
            text: root.time
            color: "#ffffff"
            font.pixelSize: 13
            font.bold: true
            font.family: "JetBrainsMono Nerd Font Mono"
          }
        }

        MouseArea {
          id: clockMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked: {
            trayWidget.closePopup();
            procPopup.visible = false;
            mediaPopup.visible = false;
            tsPopup.visible = false;
            ethPopup.visible = false;
            privacyPopup.visible = false;
            calPopup.visible = !calPopup.visible;
          }
        }
      }

      PopupWindow {
        id: calPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, clockHit.x + clockHit.width - calView.implicitWidth)
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: calView.implicitWidth
        implicitHeight: calView.implicitHeight
        color: "transparent"

        Calendar {
          id: calView
          anchors.fill: parent
          today: new Date()
        }
      }
    }
  }
}
