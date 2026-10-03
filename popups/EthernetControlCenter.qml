pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Plugins.Ethernet
import "../theme"
import "../components"

Item {
  id: root

  property var ethernet: null
  property EthernetMonitor monitor: ethernet ? ethernet.monitor : null
  readonly property EthernetMonitor activeMonitor: monitor

  property var ethData: activeMonitor ? activeMonitor.ethData : null
  signal triggerRefresh()

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property bool hasInternet: activeMonitor ? activeMonitor.hasInternet : false
  readonly property bool isCarrier: activeMonitor ? activeMonitor.carrier : false
  readonly property string currentStatus: activeMonitor ? activeMonitor.currentStatus : "offline"
  readonly property string ifaceName: activeMonitor ? activeMonitor.interfaceName : "enp34s0"
  readonly property bool busy: activeMonitor ? activeMonitor.isBusy : false

  readonly property string pingResult: activeMonitor ? activeMonitor.pingResult : ""
  readonly property double pingLatency: activeMonitor ? activeMonitor.pingLatency : -1
  readonly property bool isPinging: activeMonitor ? activeMonitor.isPinging : false

  readonly property string downloadSpeedLabel: ethernet ? ethernet.downloadSpeedLabel : "0 B/s"
  readonly property string uploadSpeedLabel: ethernet ? ethernet.uploadSpeedLabel : "0 B/s"

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
  readonly property int preferredHeight: Math.min(640, 32 + bodyCol.height)
  property int popupHeight: 360

  function syncHeight() {
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
    if (root.hasInternet && root.pingLatency < 0 && !root.autoPinged) {
      root.autoPinged = true;
      root.runPing();
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
        spacing: 0

        PopupHeader {
          width: parent.width
          glyph: root.statusGlyph
          glyphColor: root.statusColor
          title: "Ethernet"
          subtitle: (root.ethData && root.ethData.connection_name) ? (root.ethData.connection_name + " · " + root.ifaceName) : root.ifaceName

          Text {
            text: root.statusWord
            font.pixelSize: Theme.fontBase
            font.weight: Font.Medium
            color: root.statusColor
          }

          IconBtn {
            glyph: "󰑓"
            fs: Theme.iconBase
            tooltip: "Run diagnostics"
            spinning: root.checking || root.isPinging
            onClicked: root.runDiagnostics()
          }

          IconBtn {
            glyph: "󰒓"
            fs: Theme.iconBase
            tooltip: "Open network settings"
            onClicked: root.openSettings()
          }
        }

        Item { width: 1; height: 12 }

        SectionCard {
          width: parent.width
          height: netInfoCol.height

          Column {
            id: netInfoCol
            width: parent.width

            RowBase {
              width: parent.width
              height: 38
              rad: Theme.radiusSection
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
                Text {
                  text: "IP address"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 200
                  text: (root.ethData && root.ethData.ip) ? root.ethData.ip : "Not assigned"
                  font.family: root.t.mono
                  font.pixelSize: Theme.fontBase
                  color: (root.ethData && root.ethData.ip) ? root.t.ink1 : root.t.ink3
                  elide: Text.ElideRight
                }
                Text {
                  visible: Boolean(root.ethData && root.ethData.ip)
                  text: "󰆏"
                  font.family: root.t.mono
                  font.pixelSize: Theme.iconSm
                  color: root.t.ink3
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "Gateway"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 220
                  text: (root.ethData && root.ethData.gateway) ? root.ethData.gateway : "—"
                  font.family: root.t.mono
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink1
                  elide: Text.ElideRight
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "DNS"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 220
                  text: (root.ethData && root.ethData.dns && root.ethData.dns.length > 0) ? root.ethData.dns.join(", ") : "Default"
                  font.family: root.t.mono
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink1
                  elide: Text.ElideRight
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "Link speed"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.isCarrier ? ((root.ethData && root.ethData.speed_label) ? root.ethData.speed_label + " · Full duplex" : "Carrier detected") : "No carrier"
                  font.family: root.t.mono
                  font.pixelSize: Theme.fontBase
                  color: root.isCarrier ? root.t.ink1 : root.t.ink3
                  elide: Text.ElideRight
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "Download"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.downloadSpeedLabel
                  font.family: root.t.mono
                  font.pixelSize: Theme.fontBase
                  color: root.t.green
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "Upload"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.uploadSpeedLabel
                  font.family: root.t.mono
                  font.pixelSize: Theme.fontBase
                  color: root.t.amber
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              actionable: true
              onClicked: root.runPing()
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                Text {
                  text: "Latency · 1.1.1.1"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Row {
                  spacing: 6
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pingResult ? root.pingResult : (root.isPinging ? "…" : "Test ping")
                    font.family: root.t.mono
                    font.pixelSize: Theme.fontBase
                    color: root.pingResult ? root.t.ink1 : root.t.accent
                  }
                  IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰑓"
                    fs: 11
                    btnSize: 24
                    spinning: root.isPinging
                    onClicked: root.runPing()
                  }
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              rad: Theme.radiusSection
              actionable: Boolean(root.ethData && root.ethData.hw_address)
              onClicked: {
                if (root.ethData && root.ethData.hw_address && root.activeMonitor) {
                  root.activeMonitor.copy(root.ethData.hw_address);
                  root.showToast("Copied MAC address");
                }
              }
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "MAC address"
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 220
                  text: (root.ethData && root.ethData.hw_address) ? root.ethData.hw_address : "—"
                  font.family: root.t.mono
                  font.pixelSize: Theme.fontBase
                  color: root.t.ink2
                  elide: Text.ElideMiddle
                }
              }
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
