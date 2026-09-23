//@ pragma UseQApplication
//@ pragma Env QML2_IMPORT_PATH = /home/dev/Projects/quick-shell/plugins/topprocesses/build/imports:/home/dev/Projects/quick-shell/plugins/privacy/build/imports:/home/dev/Projects/quick-shell/plugins/ethernet/build/imports:/home/dev/Projects/quick-shell/plugins/tailscale/build/imports:/home/dev/Projects/quick-shell/plugins/tokenusage/build/imports:/home/dev/Projects/quick-shell/plugins/antigravityusage/build/imports:/home/dev/Projects/quick-shell/plugins/notifications/build/imports
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
import "theme"
import "components"

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

  AudioService {
    id: audioService
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
      implicitHeight: Theme.barHeight
      color: Theme.barBg

      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.exclusiveZone: Theme.barHeight
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      function togglePopup(popup): void {
        const wasVisible = popup.visible;
        closeAllPopups();
        if (!wasVisible) {
          popup.visible = true;
        }
      }

      function closeAllPopups(): void {
        trayWidget.closePopup();
        procPopup.visible = false;
        aiPopup.visible = false;
        mediaPopup.visible = false;
        volPopup.visible = false;
        calPopup.visible = false;
        tsPopup.visible = false;
        ethPopup.visible = false;
        privacyPopup.visible = false;
        notifPopup.visible = false;
      }

      // Left: CPU / MEM / GPU stats button — clicking toggles top processes popup.
      BarChip {
        id: sysStatsHit
        anchors {
          left: parent.left
          verticalCenter: parent.verticalCenter
          leftMargin: 12
        }
        active: procPopup.visible
        onClicked: bar.togglePopup(procPopup)

        SysStats {
          id: sysStats
        }
      }

      // Combined AI usage chip (OpenCode Σ + Antigravity ✦)
      BarChip {
        id: aiHit
        anchors {
          left: sysStatsHit.right
          leftMargin: 8
          verticalCenter: parent.verticalCenter
        }
        active: aiPopup.visible
        onClicked: bar.togglePopup(aiPopup)

        AiUsageWidget {
          id: aiBarWidget
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
        onRequestClosePopups: bar.closeAllPopups()
      }

      // Volume hit button
      BarChip {
        id: volHit
        anchors {
          right: ethHit.left
          rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        active: volPopup.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: bar.togglePopup(volPopup)
        onRightClicked: volBarWidget.toggleMute()

        VolumeBarWidget {
          id: volBarWidget
          audio: audioService
        }
      }

      PopupWindow {
        id: volPopup
        anchor.window: bar
        anchor.rect.x: Math.max(8, Math.min(volHit.x + volHit.width / 2 - volControlCenter.implicitWidth / 2, bar.width - volControlCenter.implicitWidth - 12))
        anchor.rect.y: bar.implicitHeight + 6
        visible: false
        grabFocus: true
        implicitWidth: volControlCenter.implicitWidth
        implicitHeight: volControlCenter.implicitHeight
        color: "transparent"

        VolumeControlCenter {
          id: volControlCenter
          anchors.fill: parent
          audio: audioService
        }
      }

      // Media control center hit button
      BarChip {
        id: mediaHit
        anchors {
          right: volHit.left
          rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        active: mediaPopup.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: bar.togglePopup(mediaPopup)
        onRightClicked: {
          if (mediaBarWidget.activePlayer && mediaBarWidget.activePlayer.canTogglePlaying) {
            mediaBarWidget.activePlayer.togglePlaying();
          }
        }

        MediaBarWidget {
          id: mediaBarWidget
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
      BarChip {
        id: tsHit
        anchors {
          left: aiHit.right
          leftMargin: 8
          verticalCenter: parent.verticalCenter
        }
        active: tsPopup.visible
        onClicked: bar.togglePopup(tsPopup)

        TailscaleWidget {
          id: tsBarWidget
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
      BarChip {
        id: ethHit
        anchors {
          right: privacyHit.left
          rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        active: ethPopup.visible
        onClicked: bar.togglePopup(ethPopup)

        EthernetWidget {
          id: ethBarWidget
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
        height: Theme.btnHeightSm
        clip: true

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        PrivacyIndicators {
          id: privacyWidget
          anchors.centerIn: parent
          onClicked: bar.togglePopup(privacyPopup)
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
      BarChip {
        id: notifHit
        anchors {
          right: (trayWidget.visible && trayWidget.width > 0) ? trayWidget.left : parent.right
          rightMargin: (trayWidget.visible && trayWidget.width > 0) ? 8 : 12
          verticalCenter: parent.verticalCenter
        }
        active: notifPopup.visible
        onClicked: bar.togglePopup(notifPopup)

        NotificationWidget {
          id: notifBarWidget
          service: notifService
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
      BarChip {
        id: clockHit
        anchors.centerIn: parent
        active: calPopup.visible
        onClicked: bar.togglePopup(calPopup)

        Row {
          id: clockContent
          spacing: 8

          Text {
            text: root.date
            color: Theme.ink2
            font.pixelSize: Theme.fontMd
            font.family: Theme.mono
          }

          Text {
            text: root.time
            color: Theme.ink1
            font.pixelSize: Theme.fontMd
            font.bold: true
            font.family: Theme.mono
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
