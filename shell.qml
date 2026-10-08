pragma ComponentBehavior: Bound
//@ pragma UseQApplication
//@ pragma DropExpensiveFonts
//@ pragma Env QML2_IMPORT_PATH = /home/dev/Projects/quick-shell/build/qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Plugins.UpdateManager
import Quickshell.Plugins.Docker
import Quickshell.Plugins.Tailscale
import Quickshell.Plugins.Privacy
import Quickshell.Plugins.TopProcesses

import qs.services
import qs.widgets
import qs.popups
import qs.launcher
import "theme"

ShellRoot {
  id: root

  readonly property string time: Qt.formatTime(sysClock.date, "h:mm AP")
  readonly property string date: Qt.formatDate(sysClock.date, "ddd, MMM d")
  property var primaryBar: null

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

  UpdateManager {
    id: updateService
  }

  TailscaleMonitor {
    id: tailscaleService
  }

  DockerMonitor {
    id: dockerService
  }

  EthernetService {
    id: ethernetService
    throughputTracking: root.anyEthPopupVisible
  }

  AiUsageService {
    id: aiUsageService
  }

  PrivacyMonitor {
    id: privacyService
  }

  MediaService {
    id: mediaService
    positionTracking: root.anyMediaPopupVisible
  }

  HolidayProvider {
    id: holidayProvider
  }

  LauncherService {
    id: launcherService
  }

  PolkitService {
    id: polkitService
    enabledService: false
  }

  PowerService {
    id: powerService
  }

  ProcessMonitor {
    id: processMonitor
    running: root.anyProcPopupVisible
  }

  readonly property bool anyEthPopupVisible: popupHost.visible && popupHost.currentPopup === "eth"
  readonly property bool anyMediaPopupVisible: popupHost.visible && popupHost.currentPopup === "media"
  readonly property bool anyProcPopupVisible: (popupHost.visible || popupHost.pendingOpen) && popupHost.currentPopup === "proc"

  readonly property var services: ({
    aiUsage: aiUsageService,
    audio: audioService,
    docker: dockerService,
    ethernet: ethernetService,
    holidayProvider: holidayProvider,
    media: mediaService,
    notification: notifService,
    power: powerService,
    privacy: privacyService,
    processMonitor: processMonitor,
    tailscale: tailscaleService,
    update: updateService
  })

  SystemClock {
    id: sysClock
    precision: SystemClock.Minutes
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

      Component.onCompleted: {
        if (!root.primaryBar) {
          root.primaryBar = bar;
        }
      }

      function openPopup(name: string): void {
        let item = null;
        if (name === "proc") {
          if (processMonitor.processes.length === 0) {
            processMonitor.sampleSync();
          }
          item = sysStatsHit;
        }
        else if (name === "ai") item = aiHit;
        else if (name === "cal") item = clockHit;
        else if (name === "media") item = mediaHit;
        else if (name === "docker") item = dockerHit;
        else if (name === "ts") item = tsHit;
        else if (name === "update") item = updateHit;
        else if (name === "eth") item = ethHit;
        else if (name === "bluetooth") item = bluetoothHit;
        else if (name === "vol") item = volHit;
        else if (name === "notif") item = notifSeg;
        else if (name === "power") item = powerHit;
        if (item) popupHost.open(item, name);
      }

      function closeAllPopups(): void {
        barTooltip.hide();
        trayWidget.closePopup();
        popupHost.close();
      }

      function showTip(item: Item, text: string, subtext: string): void {
        if (!popupHost.visible) {
          barTooltip.show(item, text, subtext);
        }
      }

      function hideTip(): void {
        barTooltip.hide();
      }

      Connections {
        /* PopupHost is a PopupWindow, so this is a valid QObject target.
           qmllint cannot tell because the qs.popups import does not resolve. */
        target: popupHost // qmllint disable incompatible-type
        function onPopupOpened() {
          barTooltip.hide();
          trayWidget.closePopup();
        }
      }

      BarTooltip {
        id: barTooltip
      }

      Item {
        id: barContent
        anchors.fill: parent

        function showTip(item: Item, text: string, subtext: string): void {
          bar.showTip(item, text, subtext);
        }

        function hideTip(): void {
          bar.hideTip();
        }

        RowLayout {
          id: leftBarRow
          anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
          }
          spacing: 8

          BarCapsule {
            id: trayCapsule
            visible: trayWidget.width > 0

            SystemTrayWidget {
              id: trayWidget
              barWindow: bar
              onRequestClosePopups: bar.closeAllPopups()
            }
          }

          BarItem {
            id: sysStatsHit
          active: popupHost.isOpen(sysStatsHit, "proc")
          Accessible.name: "System stats"
          onClicked: {
            if (processMonitor.processes.length === 0) {
              processMonitor.sampleSync();
            }
            popupHost.toggle(sysStatsHit, "proc");
          }

          SysStats {
            id: sysStats
            processMonitor: root.services.processMonitor
          }
        }

        BarItem {
          id: aiHit
          active: popupHost.isOpen(aiHit, "ai")
          tooltip: "AI usage till today: " + (aiUsageService ? aiUsageService.totalTokensText : "--") + " · " + (aiUsageService ? aiUsageService.totalCostText : "--")
          tooltipSub: "Click for breakdown & analytics"
          Accessible.name: "AI tokens and cost"
          onClicked: popupHost.toggle(aiHit, "ai")

          AiUsageWidget {
            id: aiBarWidget
            aiUsage: aiUsageService
          }
        }
      }

      BarCapsule {
        anchors.centerIn: parent // qmllint disable unqualified

        BarItem {
          id: clockHit
          segment: true
          active: popupHost.isOpen(clockHit, "cal")
          Accessible.name: "Clock & calendar"
          onClicked: popupHost.toggle(clockHit, "cal")

          Row {
            id: clockContent
            spacing: 8

            Text {
              text: root.date
              color: Theme.ink2
              font.pixelSize: Theme.fontMd
              font.family: Theme.roundedFont
            }

            Text {
              text: root.time
              color: Theme.ink1
              font.pixelSize: Theme.fontMd
              font.bold: true
              font.family: Theme.roundedFont
            }
          }
        }

        BarDivider {
          visible: mediaService.hasPlayer
        }

        BarItem {
          id: mediaHit
          segment: true
          visible: mediaService.hasPlayer
          active: popupHost.isOpen(mediaHit, "media")
          Accessible.name: "Media player"
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: popupHost.toggle(mediaHit, "media")
          onRightClicked: {
            if (mediaService.activePlayer && mediaService.activePlayer.canTogglePlaying) {
              mediaService.activePlayer.togglePlaying();
            }
          }

          MediaBarWidget {
            id: mediaBarWidget
            media: mediaService
          }
        }
      }

      RowLayout {
        id: rightBarRow
        anchors {
          right: parent.right
          rightMargin: 12
          verticalCenter: parent.verticalCenter
        }
        spacing: 8

        Item {
          id: privacyHit
          visible: privacyService.hasActive || implicitWidth > 0
          implicitWidth: privacyService.hasActive ? privacyWidget.implicitWidth : 0
          implicitHeight: Theme.btnHeightSm
          clip: true

          Behavior on implicitWidth {
            NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
          }

          PrivacyIndicators {
            id: privacyWidget
            privacy: privacyService
            anchors.centerIn: parent // qmllint disable unqualified
            onClicked: popupHost.toggle(privacyHit, "privacy")
          }
        }

        BarItem {
          id: dockerHit
          flat: true
          active: popupHost.isOpen(dockerHit, "docker")
          tooltip: "Docker: " + (dockerService.connected ? (dockerService.runningCount + " running · " + dockerService.totalCount + " total") : "Daemon unreachable")
          tooltipSub: "Click for containers & logs"
          onClicked: popupHost.toggle(dockerHit, "docker")

          DockerWidget {
            id: dockerBarWidget
            docker: dockerService
          }
        }

        BarItem {
          id: tsHit
          flat: true
          active: popupHost.isOpen(tsHit, "ts")
          tooltip: "Tailscale: " + (!tailscaleService.connected ? "Disconnected" : (tailscaleService.hasFunnel ? "Connected · Funnel active" : (tailscaleService.serveCount > 0 ? ("Connected · " + tailscaleService.serveCount + " shared") : "Connected")))
          tooltipSub: "Click for peers & funnel"
          onClicked: popupHost.toggle(tsHit, "ts")

          TailscaleWidget {
            id: tsBarWidget
            tailscale: tailscaleService
          }
        }

        BarItem {
          id: updateHit
          flat: true
          active: popupHost.isOpen(updateHit, "update")
          tooltip: "System Updates: " + (updateService.hasUpdates ? (updateService.updateCount + " available") : "Up to date")
          tooltipSub: "Click for update manager"
          onClicked: popupHost.toggle(updateHit, "update")

          UpdateWidget {
            id: updateBarWidget
            service: updateService
          }
        }

        BarItem {
          id: ethHit
          flat: true
          active: popupHost.isOpen(ethHit, "eth")
          Accessible.name: "Ethernet network"
          onClicked: popupHost.toggle(ethHit, "eth")

          EthernetWidget {
            id: ethBarWidget
            ethernet: ethernetService
          }
        }

        BarItem {
          id: bluetoothHit
          flat: true
          active: popupHost.isOpen(bluetoothHit, "bluetooth")
          Accessible.name: "Bluetooth"
          onClicked: popupHost.toggle(bluetoothHit, "bluetooth")

          BluetoothWidget {
            id: bluetoothBarWidget
          }
        }

        BarItem {
          id: volHit
          flat: true
          active: popupHost.isOpen(volHit, "vol")
          Accessible.name: "Audio volume"
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: popupHost.toggle(volHit, "vol")
          onRightClicked: volBarWidget.toggleMute()

          VolumeBarWidget {
            id: volBarWidget
            audio: audioService
          }
        }

        BarItem {
          id: notifSeg
          flat: true
          active: popupHost.isOpen(notifSeg, "notif")
          Accessible.name: "Notifications"
          onClicked: popupHost.toggle(notifSeg, "notif")

          NotificationWidget {
            id: notifBarWidget
            service: notifService
          }
        }

        BarItem {
          id: powerHit
          flat: true
          active: popupHost.isOpen(powerHit, "power")
          Accessible.name: "Power & session"
          tooltip: "Session & Power"
          tooltipSub: "Click for power actions"
          onClicked: popupHost.toggle(powerHit, "power")

          PowerWidget {
            id: powerBarWidget
            power: powerService
          }
        }
      }
    }

    }
  }

  PopupHost {
    id: popupHost
    services: root.services
  }

  LauncherWindow {
    id: launcherWindow
    launcher: launcherService
  }

  PolkitDialog {
    id: polkitDialog
    service: polkitService
  }

  IpcHandler {
    target: "polkit"

    function enable(): void {
      polkitService.enabledService = true;
    }
    function disable(): void {
      polkitService.enabledService = false;
    }
    function toggle(): void {
      polkitService.enabledService = !polkitService.enabledService;
    }
    function status(): string {
      return polkitService.isRegistered ? "registered" : (polkitService.enabledService ? "failed" : "disabled");
    }
  }

  IpcHandler {
    target: "launcher"

    function open(): void {
      launcherService.open();
    }
    function toggle(): void {
      launcherService.toggle();
    }
    function close(): void {
      launcherService.close();
    }
  }

  IpcHandler {
    target: "popup"

    function open(name: string): void {
      if (root.primaryBar && typeof root.primaryBar.openPopup === "function") {
        root.primaryBar.openPopup(name);
      }
    }
    function close(): void {
      popupHost.close();
    }
  }
}
