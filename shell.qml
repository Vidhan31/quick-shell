//@ pragma UseQApplication
//@ pragma Env QML2_IMPORT_PATH = /home/dev/Projects/quick-shell/plugins/topprocesses/build/imports:/home/dev/Projects/quick-shell/plugins/privacy/build/imports:/home/dev/Projects/quick-shell/plugins/ethernet/build/imports:/home/dev/Projects/quick-shell/plugins/tailscale/build/imports:/home/dev/Projects/quick-shell/plugins/media/build/imports:/home/dev/Projects/quick-shell/plugins/tokenusage/build/imports:/home/dev/Projects/quick-shell/plugins/antigravityusage/build/imports:/home/dev/Projects/quick-shell/plugins/notifications/build/imports
// Shell.qml — Main Quickshell entrypoint for the desktop bar.
// Docs:
// - PanelWindow: anchors, height, color, screen
// - WlrLayershell: layer, exclusiveZone, keyboardFocus
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.services
import qs.widgets
import qs.popups

ShellRoot {
  id: root

  property string time: ""
  property string date: ""

  NotificationService {
    id: notifService
  }

  NotificationPopups {
    id: notifPopups
    service: notifService
  }

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
            notifPopup.visible = false;
            aiPopup.visible = false;
            procPopup.visible = !procPopup.visible;
          }
        }
      }

      // Combined AI usage chip (OpenCode Σ + Antigravity ✦) — manual
      // refresh only, single tabbed popup below.
      Item {
        id: aiHit
        anchors {
          left: sysStatsHit.right
          leftMargin: 8
          verticalCenter: parent.verticalCenter
        }
        width: aiBarWidget.width + 16
        height: 24

        Rectangle {
          id: aiBg
          anchors.fill: parent
          radius: 6
          color: aiPopup.visible ? "#45475a" : (aiMouse.containsMouse ? "#3b3e52" : "#313244")
          border.color: aiPopup.visible ? "#89b4fa" : (aiMouse.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        AiUsageWidget {
          id: aiBarWidget
          anchors.centerIn: parent
        }

        MouseArea {
          id: aiMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked: {
            trayWidget.closePopup();
            procPopup.visible = false;
            mediaPopup.visible = false;
            calPopup.visible = false;
            tsPopup.visible = false;
            ethPopup.visible = false;
            privacyPopup.visible = false;
            notifPopup.visible = false;
            aiPopup.visible = !aiPopup.visible;
          }
        }
      }

      PopupWindow {
        id: aiPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(aiHit.x + aiHit.width / 2 - aiControlCenter.implicitWidth / 2, bar.width - aiControlCenter.implicitWidth - 12))
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: aiControlCenter.implicitWidth
        implicitHeight: aiControlCenter.implicitHeight
        color: "transparent"

        onVisibleChanged: {
          if (!visible)
            aiControlCenter.hideTip();
        }

        AiUsageControlCenter {
          id: aiControlCenter
          anchors.fill: parent
          ocMonitor: aiBarWidget.oc
          agyMonitor: aiBarWidget.agy
          barWindow: bar
          popupWindow: aiPopup
          onTriggerRefreshAll: aiBarWidget.refreshAll()
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
          visible: procPopup.visible
        }
      }


      // System Tray icons for background / minimized apps
      SystemTrayWidget {
        id: trayWidget
        barWindow: bar
        anchors {
          right: parent.right
          rightMargin: (visible && width > 0) ? 12 : 0
          verticalCenter: parent.verticalCenter
        }
        onRequestClosePopups: {
          procPopup.visible = false;
          mediaPopup.visible = false;
          tsPopup.visible = false;
          ethPopup.visible = false;
          privacyPopup.visible = false;
          notifPopup.visible = false;
          calPopup.visible = false;
          aiPopup.visible = false;
        }
      }

      // Media control center hit button
      Item {
        id: mediaHit
        anchors {
          right: ethHit.left
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
              notifPopup.visible = false;
              aiPopup.visible = false;
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
          media: mediaBarWidget.media
        }
      }

      // Tailscale hit button
      Item {
        id: tsHit
        anchors {
          left: aiHit.right
          leftMargin: 8
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
            notifPopup.visible = false;
            aiPopup.visible = false;
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
          monitor: tsBarWidget.monitor
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
            notifPopup.visible = false;
            aiPopup.visible = false;
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
          monitor: ethBarWidget.monitor
          ethData: ethBarWidget.ethData
          onTriggerRefresh: ethBarWidget.refresh()
        }
      }

      // Privacy indicators hit button — Camera and Microphone when active
      Item {
        id: privacyHit
        anchors {
          right: notifHit.left
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
            notifPopup.visible = false;
            aiPopup.visible = false;
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

      // Notification center hit button
      Item {
        id: notifHit
        anchors {
          right: (trayWidget.visible && trayWidget.width > 0) ? trayWidget.left : parent.right
          rightMargin: (trayWidget.visible && trayWidget.width > 0) ? 8 : 12
          verticalCenter: parent.verticalCenter
        }
        width: notifBarWidget.width + 16
        height: 24

        Rectangle {
          id: notifBg
          anchors.fill: parent
          radius: 6
          color: notifPopup.visible ? "#45475a" : (notifMouse.containsMouse ? "#3b3e52" : "#313244")
          border.color: notifPopup.visible ? "#89b4fa" : (notifMouse.containsMouse ? "#585b70" : "transparent")
          border.width: 1

          Behavior on color { ColorAnimation { duration: 120 } }
          Behavior on border.color { ColorAnimation { duration: 120 } }
        }

        NotificationWidget {
          id: notifBarWidget
          anchors.centerIn: parent
          service: notifService
        }

        MouseArea {
          id: notifMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          hoverEnabled: true
          onClicked: {
            trayWidget.closePopup();
            procPopup.visible = false;
            mediaPopup.visible = false;
            calPopup.visible = false;
            tsPopup.visible = false;
            ethPopup.visible = false;
            privacyPopup.visible = false;
            aiPopup.visible = false;
            notifPopup.visible = !notifPopup.visible;
          }
        }
      }

      Timer {
        id: markReadTimer
        interval: 400
        repeat: false
        onTriggered: {
          if (notifPopup.visible) {
            notifService.markAllRead();
          }
        }
      }

      PopupWindow {
        id: notifPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(notifHit.x + notifHit.width / 2 - notifControlCenter.implicitWidth / 2, bar.width - notifControlCenter.implicitWidth - 12))
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: notifControlCenter.implicitWidth
        implicitHeight: notifControlCenter.implicitHeight
        color: "transparent"

        onVisibleChanged: {
          if (visible) {
            markReadTimer.start();
          } else {
            markReadTimer.stop();
            notifService.markAllRead();
          }
        }

        NotificationControlCenter {
          id: notifControlCenter
          anchors.fill: parent
          service: notifService
          onCloseRequested: notifPopup.visible = false
        }
      }

      // Center: Clickable date / time — toggles the calendar popup below.
      // PopupWindow anchored to the bar (docs: PopupWindow anchor.window + anchor.rect).
      Item {
        id: clockHit
        anchors.centerIn: parent
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
            notifPopup.visible = false;
            aiPopup.visible = false;
            calPopup.visible = !calPopup.visible;
          }
        }
      }

      PopupWindow {
        id: calPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(clockHit.x + clockHit.width / 2 - calView.implicitWidth / 2, bar.width - calView.implicitWidth - 12))
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
