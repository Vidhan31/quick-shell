//@ pragma UseQApplication
//@ pragma Env QML2_IMPORT_PATH = /home/dev/Projects/quick-shell/plugins/topprocesses/build/imports:/home/dev/Projects/quick-shell/plugins/privacy/build/imports:/home/dev/Projects/quick-shell/plugins/ethernet/build/imports:/home/dev/Projects/quick-shell/plugins/tailscale/build/imports:/home/dev/Projects/quick-shell/plugins/tokenusage/build/imports:/home/dev/Projects/quick-shell/plugins/antigravityusage/build/imports:/home/dev/Projects/quick-shell/plugins/notifications/build/imports
// Shell.qml — Main Quickshell entrypoint for the desktop bar.
// Docs:
// - PanelWindow: anchors, height, color, screen
// - WlrLayershell: layer, exclusiveZone, keyboardFocus
import QtQuick
import QtQuick.Layouts
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
        bluetoothPopup.visible = false;
        privacyPopup.visible = false;
        notifPopup.visible = false;
      }

      // Left: CPU/MEM/GPU, AI tokens, and Tailscale
      RowLayout {
        id: leftBarRow
        anchors {
          left: parent.left
          leftMargin: 12
          verticalCenter: parent.verticalCenter
        }
        spacing: 8

        BarChip {
          id: sysStatsHit
          active: procPopup.visible
          onClicked: bar.togglePopup(procPopup)

          SysStats {
            id: sysStats
          }
        }

        BarChip {
          id: aiHit
          active: aiPopup.visible
          onClicked: bar.togglePopup(aiPopup)

          AiUsageWidget {
            id: aiBarWidget
          }
        }

        BarChip {
          id: tsHit
          active: tsPopup.visible
          onClicked: bar.togglePopup(tsPopup)

          TailscaleWidget {
            id: tsBarWidget
          }
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

      // Right: Media, Volume, Ethernet, Privacy, Notifications, and System Tray
      RowLayout {
        id: rightBarRow
        anchors {
          right: parent.right
          rightMargin: 12
          verticalCenter: parent.verticalCenter
        }
        spacing: 8

        BarChip {
          id: mediaHit
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

        BarChip {
          id: volHit
          active: volPopup.visible
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: bar.togglePopup(volPopup)
          onRightClicked: volBarWidget.toggleMute()

          VolumeBarWidget {
            id: volBarWidget
            audio: audioService
          }
        }

        BarChip {
          id: ethHit
          active: ethPopup.visible
          onClicked: bar.togglePopup(ethPopup)

          EthernetWidget {
            id: ethBarWidget
          }
        }

        BarChip {
          id: bluetoothHit
          active: bluetoothPopup.visible
          onClicked: bar.togglePopup(bluetoothPopup)

          BluetoothWidget {
            id: bluetoothBarWidget
          }
        }

        Item {
          id: privacyHit
          visible: privacyWidget.hasActive || implicitWidth > 0
          implicitWidth: privacyWidget.hasActive ? privacyWidget.implicitWidth : 0
          implicitHeight: Theme.btnHeightSm
          clip: true

          Behavior on implicitWidth {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }

          PrivacyIndicators {
            id: privacyWidget
            anchors.centerIn: parent
            onClicked: bar.togglePopup(privacyPopup)
          }
        }

        BarChip {
          id: notifHit
          active: notifPopup.visible
          onClicked: bar.togglePopup(notifPopup)

          NotificationWidget {
            id: notifBarWidget
            service: notifService
          }
        }

        SystemTrayWidget {
          id: trayWidget
          barWindow: bar
          visible: width > 0
          onRequestClosePopups: bar.closeAllPopups()
        }
      }

      // Popups positioned declaratively via anchor.item and PopupAdjustment
      PopupWindow {
        id: procPopup
        anchor.item: sysStatsHit
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
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

      PopupWindow {
        id: aiPopup
        anchor.item: aiHit
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
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
        id: tsPopup
        anchor.item: tsHit
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
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

      PopupWindow {
        id: bluetoothPopup
        anchor.item: bluetoothHit
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
        visible: false
        grabFocus: true
        implicitWidth: bluetoothControlCenter.implicitWidth
        implicitHeight: bluetoothControlCenter.implicitHeight
        color: "transparent"

        onVisibleChanged: bluetoothControlCenter.syncHeight()

        BluetoothControlCenter {
          id: bluetoothControlCenter
          anchors.fill: parent
        }
      }

      PopupWindow {
        id: mediaPopup
        anchor.item: mediaHit
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
        visible: false
        grabFocus: true
        implicitWidth: mediaControlCenter.implicitWidth
        implicitHeight: mediaControlCenter.implicitHeight
        color: "transparent"

        onVisibleChanged: mediaControlCenter.syncHeight()

        MediaControlCenter {
          id: mediaControlCenter
          anchors.fill: parent
          media: mediaBarWidget.media
        }
      }

      PopupWindow {
        id: volPopup
        anchor.item: volHit
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
        visible: false
        grabFocus: true
        implicitWidth: volControlCenter.implicitWidth
        implicitHeight: volControlCenter.implicitHeight
        color: "transparent"

        onVisibleChanged: volControlCenter.syncHeight()

        VolumeControlCenter {
          id: volControlCenter
          anchors.fill: parent
          audio: audioService
        }
      }

      PopupWindow {
        id: ethPopup
        anchor.item: ethHit
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
        visible: false
        grabFocus: true
        implicitWidth: ethControlCenter.implicitWidth
        implicitHeight: ethControlCenter.implicitHeight
        color: "transparent"

        onVisibleChanged: ethControlCenter.syncHeight()

        EthernetControlCenter {
          id: ethControlCenter
          anchors.fill: parent
          monitor: ethBarWidget.monitor
          ethData: ethBarWidget.ethData
          onTriggerRefresh: ethBarWidget.refresh()
        }
      }

      PopupWindow {
        id: privacyPopup
        anchor.item: privacyHit
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
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
        anchor.item: notifHit
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
        visible: false
        grabFocus: true
        implicitWidth: notifControlCenter.implicitWidth
        implicitHeight: notifControlCenter.implicitHeight
        color: "transparent"

        onVisibleChanged: {
          if (visible) {
            notifControlCenter.syncHeight();
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

      PopupWindow {
        id: calPopup
        anchor.item: clockHit
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 6
        anchor.adjustment: PopupAdjustment.SlideX
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
