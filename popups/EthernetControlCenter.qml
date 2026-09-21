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

  property string toastMessage: ""

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
  // Hug the content (chrome 32 + body), capped so overflow scrolls inside
  // the card instead of growing off-screen. bodyCol.height is driven only
  // by its children (width comes from the viewport), so no binding loop.
  implicitHeight: Math.min(640, 32 + bodyCol.height)
  width: implicitWidth
  height: implicitHeight

  function showToast(msg: string): void {
    root.toastMessage = msg;
    toastTimer.restart();
  }

  Timer {
    id: toastTimer
    interval: 2500
    onTriggered: root.toastMessage = ""
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

  // ================= Design tokens (mirrors TailscaleControlCenter) =================
  QtObject {
    id: t
    readonly property color bg: "#17171E"
    readonly property color surface: "#1F202B"
    readonly property color inset: "#121217"
    readonly property color line: "#2B2C3A"
    readonly property color ink1: "#F1F1F6"
    readonly property color ink2: "#A6A6B8"
    readonly property color ink3: "#6F6F84"
    readonly property color accent: "#5E9DFF"
    readonly property color green: "#46C786"
    readonly property color amber: "#E2A63B"
    readonly property color red: "#DF6363"
    readonly property color violet: "#AE8CFF"
    readonly property color darkInk: "#101018"
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
  }

  // ================= Reusable quiet components (mirrors TailscaleControlCenter) =================
  component Hairline: Rectangle {
    color: t.line
    height: 1
  }

  // Small caps section label with an optional trailing quiet action.
  component SectionHead: Item {
    property string label: ""
    property string actionText: ""
    property color actionColor: t.ink2
    signal actionClicked
    implicitHeight: 20
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: label
      font.pixelSize: 11
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.8
      color: t.ink3
    }
    TextBtn {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: actionText.length > 0
      text: parent.actionText
      fg: parent.actionColor
      fs: 11
      onClicked: parent.actionClicked()
    }
  }

  // Base for every clickable row: same wash everywhere, no borders.
  // Set actionable: false when there is nothing to do — the row then
  // stays inert (no wash, no pointer cursor) instead of faking affordance.
  component RowBase: Rectangle {
    id: rb
    signal clicked
    property color base: "transparent"
    property color hover: "#0FFFFFFF"
    property color press: "#1AFFFFFF"
    property real rad: 0
    property bool actionable: true
    radius: rb.rad
    color: (!rb.actionable || (!ma.containsMouse && !ma.pressed)) ? base : (ma.pressed ? press : hover)
    Behavior on color { ColorAnimation { duration: 90 } }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: rb.actionable
      cursorShape: rb.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (rb.actionable) rb.clicked();
      }
    }
  }

  // Borderless text button.
  component TextBtn: Rectangle {
    id: tb
    signal clicked
    property string text: ""
    property color fg: t.ink2
    property int fs: 12
    property bool bold: false
    implicitWidth: lbl.implicitWidth + 18
    implicitHeight: 26
    radius: 7
    color: ma.pressed ? "#1CFFFFFF" : ma.containsMouse ? "#0FFFFFFF" : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }
    Text {
      id: lbl
      anchors.centerIn: parent
      text: tb.text
      font.pixelSize: tb.fs
      font.bold: tb.bold
      color: (ma.containsMouse || ma.pressed) ? t.ink1 : tb.fg
      Behavior on color { ColorAnimation { duration: 90 } }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tb.clicked()
    }
  }

  // Borderless square icon button.
  component IconBtn: Rectangle {
    id: ib
    signal clicked
    property string glyph: ""
    property int fs: 14
    property color fg: t.ink2
    property bool spinning: false
    width: 30
    height: 30
    radius: 8
    color: ma.pressed ? "#1CFFFFFF" : ma.containsMouse ? "#0FFFFFFF" : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }
    Text {
      id: ibGlyph
      anchors.centerIn: parent
      text: ib.glyph
      font.family: t.mono
      font.pixelSize: ib.fs
      color: (ma.containsMouse || ma.pressed) ? t.ink1 : ib.fg
      Behavior on color { ColorAnimation { duration: 90 } }
      NumberAnimation on rotation {
        running: ib.spinning
        from: 0
        to: 360
        loops: Animation.Infinite
        duration: 800
      }
    }
    onSpinningChanged: {
      if (!spinning) ibGlyph.rotation = 0;
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ib.clicked()
    }
  }

  // Single solid primary action. Fill darkens on press like a native button.
  component PrimaryBtn: Rectangle {
    id: pb
    signal clicked
    property string text: ""
    property string glyph: ""
    property color fill: t.accent
    property color ink: t.darkInk
    property bool enabledBtn: true
    implicitHeight: 34
    radius: 9
    scale: (ma.pressed && pb.enabledBtn) ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: 80 } }
    color: !pb.enabledBtn ? "#24252F" : ma.pressed ? Qt.darker(fill, 1.2) : ma.containsMouse ? Qt.lighter(fill, 1.07) : fill
    Behavior on color { ColorAnimation { duration: 90 } }
    Row {
      anchors.centerIn: parent
      spacing: 7
      Text {
        visible: pb.glyph.length > 0
        anchors.verticalCenter: parent.verticalCenter
        text: pb.glyph
        font.family: t.mono
        font.pixelSize: 12
        color: pb.enabledBtn ? pb.ink : t.ink3
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pb.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: pb.enabledBtn ? pb.ink : t.ink3
      }
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: pb.enabledBtn
      cursorShape: pb.enabledBtn ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (pb.enabledBtn) pb.clicked();
      }
    }
  }

  // ================= Card =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: 14
    color: t.bg
    border.color: "#26272F"
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

    // ---- Toast: one quiet overlay, fades in place ----
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 14
      width: Math.min(toastLabel.implicitWidth + 30, parent.width - 32)
      height: 30
      radius: 15
      color: "#2A2B38"
      opacity: root.toastMessage.length > 0 ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      Text {
        id: toastLabel
        anchors.centerIn: parent
        width: parent.width - 30
        text: "✓  " + root.toastMessage
        font.pixelSize: 11
        font.weight: Font.Medium
        color: t.ink1
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
