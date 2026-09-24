pragma ComponentBehavior: Bound
// EthernetControlCenter.qml — Ethernet link status and internet diagnostics popup.
// Tailscale visual system: same tokens, card, grouped surface rows with hairlines,
// SectionHead, RowBase, TextBtn, IconBtn, PrimaryBtn. Words + tint carry state,
// no badge pills or boxed banners. Content hugs bodyCol.height (capped) so the
// popover never clips or leaves empty space; overflow scrolls inside the card.
// Native C++ Qt6 QML module (Quickshell.Plugins.Ethernet).
import QtQuick
import QtQuick.Layouts
import Quickshell.Plugins.Ethernet
import "../theme"
import "../components"

Item {
  id: root

  property EthernetMonitor monitor: null
  EthernetMonitor {
    id: fallbackMonitor
    running: root.monitor === null
  }
  readonly property EthernetMonitor activeMonitor: root.monitor ? root.monitor : fallbackMonitor

  // Throughput tracking: enable live throughput metrics only when popup is visible
  Binding {
    target: root.activeMonitor
    property: "throughputTracking"
    value: root.visible
    when: root.activeMonitor !== null
  }

  property var ethData: activeMonitor ? activeMonitor.ethData : null
  signal triggerRefresh()

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property bool hasInternet: activeMonitor ? activeMonitor.hasInternet : false
  readonly property bool isCarrier: activeMonitor ? activeMonitor.carrier : false
  readonly property string currentStatus: activeMonitor ? activeMonitor.currentStatus : "offline"
  readonly property string ifaceName: activeMonitor ? activeMonitor.interfaceName : "enp34s0"
  readonly property bool busy: activeMonitor ? activeMonitor.isBusy : false

  // Ping test state from native C++ monitor
  readonly property string pingResult: activeMonitor ? activeMonitor.pingResult : ""
  readonly property double pingLatency: activeMonitor ? activeMonitor.pingLatency : -1
  readonly property bool isPinging: activeMonitor ? activeMonitor.isPinging : false

  // Live throughput metrics from native C++ monitor
  readonly property double downloadBps: activeMonitor ? activeMonitor.downloadBps : 0
  readonly property double uploadBps: activeMonitor ? activeMonitor.uploadBps : 0


  function formatSpeed(bps: double): string {
    if (!isFinite(bps) || bps < 0) return "0 B/s";
    if (bps < 1024) return Math.round(bps) + " B/s";
    if (bps < 1024 * 1024) return (bps / 1024).toFixed(1) + " KB/s";
    if (bps < 1024 * 1024 * 1024) return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    return (bps / 1024 / 1024 / 1024).toFixed(2) + " GB/s";
  }

  // Status tint carries state everywhere — no pills, no boxes.
  readonly property color statusColor: {
    if (!root.isCarrier) return t.red;
    if (root.currentStatus === "connecting") return t.accent;
    if (root.hasInternet) return t.green;
    return t.amber;
  }
  readonly property string statusWord: {
    if (!root.isCarrier) return "Unplugged";
    if (root.currentStatus === "connecting") return "Connecting…";
    if (root.hasInternet) return "Online";
    return "No internet";
  }
  readonly property string statusGlyph: {
    if (!root.isCarrier) return "󰈂";
    if (root.currentStatus === "connecting") return "󰌗";
    return "󰈀";
  }

  implicitWidth: 440
  readonly property int preferredHeight: Math.min(640, 32 + bodyCol.height)
  property int popupHeight: 360

  function syncHeight() {
    popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (!root.visible)
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

  // Local progress flag: the backend clears isBusy only when a fresh sample
  // differs from the previous one, so an uneventful re-check would leave
  // isBusy latched true and the UI stuck on "Checking…". Drive user-facing
  // progress locally instead: clear early when the backend reports idle,
  // watchdog as backstop.
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

  // ================= Card =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: Theme.cardBorder
    border.width: 1

    Flickable {
      anchors.fill: parent
      anchors.margins: 16
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 0

        // ---- Header: identity left, status word + refresh right ----
        RowLayout {
          width: parent.width
          height: 40
          spacing: 10

          Text {
            text: root.statusGlyph
            font.family: t.mono
            font.pixelSize: 19
            color: root.statusColor
          }

          Column {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: "Ethernet"
              font.pixelSize: 14
              font.weight: Font.DemiBold
              color: t.ink1
            }
            Text {
              width: parent.width
              text: (root.ethData && root.ethData.connection_name) ? (root.ethData.connection_name + " · " + root.ifaceName) : root.ifaceName
              font.pixelSize: 11
              color: t.ink3
              elide: Text.ElideRight
            }
          }

          Text {
            text: root.statusWord
            font.pixelSize: 12
            font.weight: Font.Medium
            color: root.statusColor
          }

          IconBtn {
            glyph: "󰑓"
            fs: 14
            spinning: root.checking || root.isPinging
            onClicked: root.runDiagnostics()
          }

          IconBtn {
            glyph: "󰒓"
            fs: 14
            onClicked: root.openSettings()
          }
        }

        Item { width: 1; height: 14 }

        // ---- Connection: live link state, one row per metric ----
        SectionHead {
          width: parent.width
          label: "Connection"
          actionText: root.isPinging ? "Testing…" : "Test ping"
          actionColor: t.accent
          onActionClicked: root.runPing()
        }

        Item { width: 1; height: 6 }

        Rectangle {
          width: parent.width
          height: connCol.height
          radius: 12
          color: t.surface

          Column {
            id: connCol
            width: parent.width

            RowBase {
              width: parent.width
              height: 42
              rad: 12
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "Link speed"
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.isCarrier ? ((root.ethData && root.ethData.speed_label) ? root.ethData.speed_label + " · Full duplex" : "Carrier detected") : "No carrier"
                  font.family: t.mono
                  font.pixelSize: 12
                  color: root.isCarrier ? t.ink1 : t.ink3
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
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.formatSpeed(root.downloadBps)
                  font.family: t.mono
                  font.pixelSize: 12
                  color: t.green
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
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.formatSpeed(root.uploadBps)
                  font.family: t.mono
                  font.pixelSize: 12
                  color: t.amber
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              rad: 12
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "Latency · 1.1.1.1"
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.pingResult ? root.pingResult : (root.isPinging ? "…" : "Not measured")
                  font.family: t.mono
                  font.pixelSize: 12
                  color: root.pingResult ? t.ink1 : t.ink3
                }
              }
            }
          }
        }

        Item { width: 1; height: 14 }

        // ---- Details: inert rows, tap-free like Tailscale's non-actionable rows ----
        SectionHead {
          width: parent.width
          label: "Details"
        }

        Item { width: 1; height: 6 }

        Rectangle {
          width: parent.width
          height: detailsCol.height
          radius: 12
          color: t.surface

          Column {
            id: detailsCol
            width: parent.width

            RowBase {
              width: parent.width
              height: 38
              rad: 12
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "IP address"
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 220
                  text: (root.ethData && root.ethData.ip) ? root.ethData.ip : "Not assigned"
                  font.family: t.mono
                  font.pixelSize: 12
                  color: (root.ethData && root.ethData.ip) ? t.ink1 : t.ink3
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
                  text: "Default gateway"
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 220
                  text: (root.ethData && root.ethData.gateway) ? root.ethData.gateway : "—"
                  font.family: t.mono
                  font.pixelSize: 12
                  color: t.ink1
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
                  text: "DNS server"
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 220
                  text: (root.ethData && root.ethData.dns && root.ethData.dns.length > 0) ? root.ethData.dns.join(", ") : "Default"
                  font.family: t.mono
                  font.pixelSize: 12
                  color: t.ink1
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
                  text: "MAC address"
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  Layout.maximumWidth: 220
                  text: (root.ethData && root.ethData.hw_address) ? root.ethData.hw_address : "—"
                  font.family: t.mono
                  font.pixelSize: 12
                  color: t.ink2
                  elide: Text.ElideMiddle
                }
              }
            }

            Hairline { width: parent.width - 24; anchors.horizontalCenter: parent.horizontalCenter }

            RowBase {
              width: parent.width
              height: 38
              rad: 12
              actionable: false
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                Text {
                  text: "Cable status"
                  font.pixelSize: 12
                  color: t.ink2
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.isCarrier ? "Connected" : "Unplugged"
                  font.pixelSize: 12
                  font.weight: Font.Medium
                  color: root.isCarrier ? t.green : t.red
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
