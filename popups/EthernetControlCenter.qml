pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Plugins.Ethernet
import "../theme"
import "../components"

Item {
  id: root

  property var ethernet: null
  property EthernetMonitor monitor: (ethernet && ethernet.monitor) ? ethernet.monitor : (ethernet || null)
  readonly property EthernetMonitor activeMonitor: monitor

  property var ethData: activeMonitor ? activeMonitor.ethData : null
  signal triggerRefresh()

  readonly property var vnstatData: activeMonitor ? activeMonitor.vnstatData : null
  readonly property bool hasVnstat: activeMonitor ? activeMonitor.hasVnstat : false
  readonly property var todayData: (vnstatData && vnstatData.today) ? vnstatData.today : null
  readonly property var r24Data: (vnstatData && vnstatData.rolling24h) ? vnstatData.rolling24h : null
  readonly property var weekData: (vnstatData && vnstatData.thisWeek) ? vnstatData.thisWeek : null
  readonly property var cycleData: (vnstatData && vnstatData.billingCycle) ? vnstatData.billingCycle : null
  readonly property var yearData: (vnstatData && vnstatData.thisYear) ? vnstatData.thisYear : null

  readonly property string monoFont: Theme.mono
  readonly property bool hasInternet: activeMonitor ? activeMonitor.hasInternet : false
  readonly property bool isCarrier: activeMonitor ? activeMonitor.carrier : false
  readonly property string currentStatus: activeMonitor ? activeMonitor.currentStatus : "offline"
  readonly property string ifaceName: activeMonitor ? activeMonitor.interfaceName : "enp34s0"
  readonly property bool busy: activeMonitor ? activeMonitor.isBusy : false

  readonly property string pingResult: activeMonitor ? activeMonitor.pingResult : ""
  readonly property double pingLatency: activeMonitor ? activeMonitor.pingLatency : -1
  readonly property bool isPinging: activeMonitor ? activeMonitor.isPinging : false

  readonly property string downloadSpeedLabel: activeMonitor ? activeMonitor.downloadSpeedLabel : "0 B/s"
  readonly property string uploadSpeedLabel: activeMonitor ? activeMonitor.uploadSpeedLabel : "0 B/s"
  property int usagePeriod: 0

  readonly property var usagePeriods: [
    { label: "Today", data: root.todayData, range: "Since 12:00 AM" },
    { label: "24 hours", data: root.r24Data, range: "Rolling window" },
    { label: "Week", data: root.weekData, range: "Since Monday" },
    { label: "Cycle", data: root.cycleData, range: (root.vnstatData && root.vnstatData.cycleRange) ? root.vnstatData.cycleRange : "Since 25th" },
    { label: "Year", data: root.yearData, range: (root.vnstatData && root.vnstatData.yearLabel) ? ("Year " + root.vnstatData.yearLabel) : "Since Jan 1" }
  ]

  readonly property color statusColor: {
    if (!root.isCarrier) return root.t.red;
    if (root.currentStatus === "connecting") return root.t.accent;
    if (root.hasInternet) return root.t.green;
    return root.t.amber;
  }
  readonly property string statusWord: {
    if (!root.isCarrier) return "Unplugged";
    if (root.currentStatus === "connecting") return "Connecting…";
    if (root.hasInternet) return "Online";
    return "No internet";
  }
  readonly property string statusGlyph: {
    if (!root.isCarrier) return "󰤭";
    if (root.currentStatus === "connecting") return "󰤫";
    return "󰖩";
  }

  implicitWidth: Theme.popupWidthMd
  readonly property int preferredHeight: 32 + bodyCol.height
  property int popupHeight: 390

  function syncHeight(): void {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

  function showToast(msg: string): void {
    toast.show(msg);
  }

  function runPing(): void {
    if (activeMonitor) {
      activeMonitor.runPing("1.1.1.1");
    }
  }

  function runCheck(): void {
    if (activeMonitor) {
      activeMonitor.runCheck();
      root.triggerRefresh();
      root.showToast("Checking connection…");
    }
  }

  /* Local progress flag: the backend clears isBusy only when a fresh sample
     differs from the last one, so an uneventful re-check would latch it true
     and leave the UI stuck on "Checking…". Drive progress locally instead,
     with a watchdog as backstop. */
  property bool checking: false
  property bool autoPinged: false

  Timer {
    id: checkingWatchdog
    interval: 6000
    repeat: false
    onTriggered: root.checking = false
  }

  onBusyChanged: {
    if (!root.busy) root.checking = false;
  }

  // Ping once the link is known-online: Component.onCompleted fires before
  // the worker's first sample, so hasInternet is still false there.
  onHasInternetChanged: {
    if (root.hasInternet && root.pingLatency < 0 && !root.autoPinged) {
      root.autoPinged = true;
      root.runPing();
    }
  }

  // Full verification: ping first so the latency result is not queued behind
  // the blocking connectivity check on the monitor's worker thread.
  function runDiagnostics(): void {
    root.checking = true;
    checkingWatchdog.restart();
    root.runPing();
    root.runCheck();
  }

  function openSettings(): void {
    if (activeMonitor) {
      activeMonitor.openSettings();
    }
  }

  Component.onCompleted: {
    if (root.activeMonitor) {
      root.activeMonitor.throughputTracking = true;
      if (!root.hasVnstat) {
        root.activeMonitor.refreshVnstat();
      }
    }
    if (root.hasInternet && root.pingLatency < 0 && !root.autoPinged) {
      root.autoPinged = true;
      root.runPing();
    }
  }

  Component.onDestruction: {
    if (root.activeMonitor) {
      root.activeMonitor.throughputTracking = false;
    }
  }

  readonly property var t: Theme

  PopupCard {
    id: card
    anchors.fill: parent

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 6

        PopupHeader {
          width: parent.width
          glyph: root.statusGlyph
          glyphColor: root.statusColor
          title: "Ethernet"
          subtitle: (root.ethData && root.ethData.connection_name) ? (root.ethData.connection_name + " · " + root.ifaceName) : root.ifaceName

          Text {
            text: root.statusWord
            font.family: Theme.textFont
            font.pixelSize: Theme.fontBase
            font.weight: Font.Medium
            color: root.statusColor
          }

          IconButton {
            glyph: "󰑓"
            fs: Theme.iconBase
            tooltip: "Run diagnostics"
            spinning: root.checking || root.isPinging
            onClicked: root.runDiagnostics()
          }

          IconButton {
            glyph: "󰒓"
            fs: Theme.iconBase
            tooltip: "Open network settings"
            onClicked: root.openSettings()
          }
        }

        Hairline { width: parent.width }

        SectionCard {
          width: parent.width
          height: connectionRows.height
          Column {
            id: connectionRows
            width: parent.width
            ActionRow {
              width: parent.width
              height: 30
              actionable: Boolean(root.ethData && root.ethData.ip)
              onClicked: {
                if (root.ethData && root.ethData.ip && root.activeMonitor) {
                  root.activeMonitor.copy(root.ethData.ip);
                  root.showToast("Copied IP address");
                }
              }
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text { text: "IP address"; font.family: Theme.textFont; font.pixelSize: Theme.fontBase; color: root.t.ink2 }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 230
                  text: (root.ethData && root.ethData.ip) ? root.ethData.ip : "Not assigned"
                  font.family: root.t.mono; font.pixelSize: Theme.fontBase
                  color: (root.ethData && root.ethData.ip) ? root.t.ink1 : root.t.ink3
                  elide: Text.ElideRight
                }
                Text { visible: Boolean(root.ethData && root.ethData.ip); text: "󰆏"; font.family: root.t.mono; font.pixelSize: Theme.iconSm; color: root.t.ink3 }
              }
            }
            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }
            ActionRow {
              width: parent.width; height: 30; actionable: false
              RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                Text { text: "Link speed"; font.family: Theme.textFont; font.pixelSize: Theme.fontBase; color: root.t.ink2 }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.isCarrier ? ((root.ethData && root.ethData.speed_label) ? root.ethData.speed_label + " · Full duplex" : "Carrier detected") : "No carrier"
                  font.family: root.t.mono; font.pixelSize: Theme.fontBase
                  color: root.isCarrier ? root.t.ink1 : root.t.ink3
                  elide: Text.ElideRight
                }
              }
            }
            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }
            ActionRow {
              width: parent.width; height: 30; actionable: false
              RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                Text { text: "Gateway"; font.family: Theme.textFont; font.pixelSize: Theme.fontBase; color: root.t.ink2 }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 230
                  text: (root.ethData && root.ethData.gateway) ? root.ethData.gateway : "—"
                  font.family: root.t.mono; font.pixelSize: Theme.fontBase; color: root.t.ink1; elide: Text.ElideRight
                }
              }
            }
            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }
            ActionRow {
              width: parent.width; height: 30; actionable: false
              RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                Text { text: "DNS"; font.family: Theme.textFont; font.pixelSize: Theme.fontBase; color: root.t.ink2 }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 230
                  text: (root.ethData && root.ethData.dns && root.ethData.dns.length > 0) ? root.ethData.dns.join(", ") : "Default"
                  font.family: root.t.mono; font.pixelSize: Theme.fontBase; color: root.t.ink1; elide: Text.ElideRight
                }
              }
            }
            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }
            ActionRow {
              width: parent.width; height: 30
              actionable: Boolean(root.ethData && root.ethData.hw_address)
              onClicked: {
                if (root.ethData && root.ethData.hw_address && root.activeMonitor) {
                  root.activeMonitor.copy(root.ethData.hw_address);
                  root.showToast("Copied MAC address");
                }
              }
              RowLayout {
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                Text { text: "MAC address"; font.family: Theme.textFont; font.pixelSize: Theme.fontBase; color: root.t.ink2 }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 230
                  text: (root.ethData && root.ethData.hw_address) ? root.ethData.hw_address : "—"
                  font.family: root.t.mono; font.pixelSize: Theme.fontBase; color: root.t.ink2; elide: Text.ElideMiddle
                }
              }
            }
          }
        }

        SectionCard {
          width: parent.width
          height: 68
          Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 0
            readonly property real cellWidth: (width - 2) / 3
            Item {
              width: parent.cellWidth
              height: parent.height
              Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                  width: parent.parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "DOWNLOAD"
                  font.family: root.t.mono; font.pixelSize: Theme.fontXs; color: root.t.ink3
                }
                Text {
                  width: parent.parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.downloadSpeedLabel
                  font.family: root.t.mono; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold; color: root.t.green
                }
              }
            }
            Rectangle {
              width: 1; height: 32; anchors.verticalCenter: parent.verticalCenter; color: root.t.line
            }
            Item {
              width: parent.cellWidth
              height: parent.height
              Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                  width: parent.parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "UPLOAD"
                  font.family: root.t.mono; font.pixelSize: Theme.fontXs; color: root.t.ink3
                }
                Text {
                  width: parent.parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.uploadSpeedLabel
                  font.family: root.t.mono; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold; color: root.t.amber
                }
              }
            }
            Rectangle {
              width: 1; height: 32; anchors.verticalCenter: parent.verticalCenter; color: root.t.line
            }
            ActionRow {
              width: parent.cellWidth
              height: parent.height
              actionable: true
              onClicked: root.runPing()
              Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                  width: parent.parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "LATENCY"
                  font.family: root.t.mono; font.pixelSize: Theme.fontXs; color: root.t.ink3
                }
                Text {
                  width: parent.parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.pingResult ? root.pingResult : (root.isPinging ? "…" : "Test ping")
                  font.family: root.t.mono; font.pixelSize: Theme.fontBase
                  color: root.pingResult ? root.t.ink1 : root.t.accent
                }
              }
            }
          }
        }

        SectionHeader {
          width: parent.width
          label: "DATA USAGE"
          actionGlyph: "󰑓"
          actionTooltip: "Refresh vnstat"
          onActionClicked: {
            if (root.activeMonitor) {
              root.activeMonitor.refreshVnstat();
              root.showToast("Refreshing vnstat…");
            }
          }
        }

        SectionCard {
          width: parent.width
          height: root.hasVnstat ? 92 : 48
          Column {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            spacing: 6
            SegmentedControl {
              visible: root.hasVnstat
              width: parent.width
              items: root.usagePeriods.map(period => ({ label: period.label }))
              current: root.usagePeriod
              onSelected: index => root.usagePeriod = index
            }
            RowLayout {
              visible: root.hasVnstat
              width: parent.width
              height: 36
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                  text: root.usagePeriods[root.usagePeriod].data ? root.usagePeriods[root.usagePeriod].data.totalFormatted : "0 B"
                  font.family: root.t.mono; font.pixelSize: Theme.fontXl; font.weight: Font.DemiBold; color: root.t.ink1
                }
                Text { text: root.usagePeriods[root.usagePeriod].range; font.family: Theme.textFont; font.pixelSize: Theme.fontXs; color: root.t.ink3 }
              }
              Text {
                text: "↓ " + (root.usagePeriods[root.usagePeriod].data ? root.usagePeriods[root.usagePeriod].data.rxFormatted : "0 B")
                font.family: root.t.mono; font.pixelSize: Theme.fontSm; color: root.t.green
              }
              Text {
                text: "↑ " + (root.usagePeriods[root.usagePeriod].data ? root.usagePeriods[root.usagePeriod].data.txFormatted : "0 B")
                font.family: root.t.mono; font.pixelSize: Theme.fontSm; color: root.t.amber
              }
            }
            Text {
              visible: !root.hasVnstat
              width: parent.width
              height: 28
              verticalAlignment: Text.AlignVCenter
              text: "No vnstat data recorded yet"
              font.family: Theme.textFont; font.pixelSize: Theme.fontBase; color: root.t.ink3
            }
          }
        }
      }
    }

    Toast {
      id: toast
      timeout: 2500
    }
  }
}
