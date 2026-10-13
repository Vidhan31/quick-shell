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
import Quickshell.Plugins.KuiServer
import Quickshell.Plugins.Ethernet
import Quickshell.Plugins.HolidayProvider

import qs.services
import qs.widgets
import qs.popups
import qs.launcher
import "theme"
import "desktop"

ShellRoot {
  id: root

  readonly property string time: Qt.formatTime(sysClock.date, "h:mm AP")
  readonly property string date: Qt.formatDate(sysClock.date, "ddd, MMM d")
  property var primaryBar: null

  signal requestClosePopups()

  function closeAllPopups(): void {
    root.requestClosePopups();
    popupHost.close();
    if (launcherService.isOpen) {
      launcherService.close();
    }
  }

  NotificationService {
    id: notifService
  }

  JobServer {
    id: jobService
  }

  NotificationOverlay {
    id: notifPopups
    service: notifService
    jobService: jobService
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

  EthernetMonitor {
    id: ethernetService
    interval: 2500
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
    icsPath: Quickshell.shellPath("assets/holidays.ics")
  }

  LauncherService {
    id: launcherService
  }

  PolkitService {
    id: polkitService
    enabledService: true
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
    job: jobService,
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

    DesktopView {
      required property ShellScreen modelData
      targetScreen: modelData

      onClicked: {
        root.closeAllPopups();
      }

      onContextMenuRequested: {
        root.requestClosePopups();
        popupHost.close();
        launcherService.toggle();
      }
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

      Component.onCompleted: {
        if (!root.primaryBar) {
          root.primaryBar = bar;
        }
      }

      readonly property var itemMap: ({
        "proc": sysStatsHit,
        "ai": aiHit,
        "cal": clockHit,
        "media": mediaHit,
        "docker": dockerHit,
        "ts": tsHit,
        "update": updateHit,
        "eth": ethHit,
        "bluetooth": bluetoothHit,
        "vol": volHit,
        "notif": notifSeg,
        "power": powerHit,
        "privacy": privacyHit
      })

      function openPopup(name: string): void {
        const item = itemMap[name];
        if (item) {
          popupHost.open(item, name);
        }
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
          if (launcherService.isOpen) {
            launcherService.close();
          }
        }
      }

      Connections {
        target: root
        function onRequestClosePopups(): void {
          bar.closeAllPopups();
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

        MouseArea {
          anchors.fill: parent
          z: -1
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onPressed: {
            root.closeAllPopups();
          }
        }

        RowLayout {
          id: leftBarRow
          anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
          }
          spacing: 8

          BarItem {
            id: launcherHit
            noBackground: true
            active: launcherService.isOpen
            Accessible.name: "Application launcher"
            onClicked: {
              root.requestClosePopups();
              popupHost.close();
              launcherService.toggle();
            }

            LauncherWidget {
              id: launcherBarWidget
              active: launcherService.isOpen
              hovered: launcherHit.containsMouse
            }
          }

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
          active: popupHost.isOpen(sysStatsHit)
          Accessible.name: "System stats"
          onClicked: {
            popupHost.toggle(sysStatsHit, "proc");
          }

          SystemStatsWidget {
            id: sysStats
            processMonitor: root.services.processMonitor
          }
        }

        BarItem {
          id: aiHit
          active: popupHost.isOpen(aiHit)
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
          active: popupHost.isOpen(clockHit)
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
          active: popupHost.isOpen(mediaHit)
          Accessible.name: "Media player"
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: popupHost.toggle(mediaHit, "media")
          onRightClicked: {
            if (mediaService.activePlayer && mediaService.activePlayer.canTogglePlaying) {
              mediaService.activePlayer.togglePlaying();
            }
          }

          MediaWidget {
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

          PrivacyWidget {
            id: privacyWidget
            privacy: privacyService
            anchors.centerIn: parent // qmllint disable unqualified
            onClicked: popupHost.toggle(privacyHit, "privacy")
          }
        }

        BarItem {
          id: dockerHit
          flat: true
          active: popupHost.isOpen(dockerHit)
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
          active: popupHost.isOpen(tsHit)
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
          active: popupHost.isOpen(updateHit)
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
          active: popupHost.isOpen(ethHit)
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
          active: popupHost.isOpen(bluetoothHit)
          Accessible.name: "Bluetooth"
          onClicked: popupHost.toggle(bluetoothHit, "bluetooth")

          BluetoothWidget {
            id: bluetoothBarWidget
          }
        }

        BarItem {
          id: volHit
          flat: true
          active: popupHost.isOpen(volHit)
          Accessible.name: "Audio volume"
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: popupHost.toggle(volHit, "vol")
          onRightClicked: volBarWidget.toggleMute()

          VolumeWidget {
            id: volBarWidget
            audio: audioService
          }
        }

        BarItem {
          id: notifSeg
          flat: true
          active: popupHost.isOpen(notifSeg)
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
          active: popupHost.isOpen(powerHit)
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
      root.closeAllPopups();
    }
  }
}
