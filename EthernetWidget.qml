// EthernetWidget.qml — Compact top bar widget for Ethernet & Internet status.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Item {
  id: root

  property int pollInterval: 2500
  property var ethData: ({
    ok: true,
    interface: "enp34s0",
    carrier: true,
    operstate: "up",
    speed_mbps: 100,
    speed_label: "100 Mbps",
    hw_address: "",
    ip: "",
    ipv6: "",
    gateway: "",
    dns: [],
    connection_name: "Ethernet",
    nm_connectivity: 4,
    has_internet: true,
    is_default_route: true,
    status: "internet",
    status_desc: "Connected • Internet OK",
    rx_bytes: 0,
    tx_bytes: 0,
    query_time_ms: 0
  })
  property bool isBusy: false

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property string currentStatus: ethData ? (ethData.status || "offline") : "offline"
  readonly property bool hasInternet: ethData ? (ethData.has_internet === true) : false
  readonly property bool isCarrier: ethData ? (ethData.carrier === true) : false
  readonly property bool hasIp: ethData ? (Boolean(ethData.ip)) : false

  // Status-derived icon glyph
  readonly property string iconGlyph: {
    if (!root.isCarrier) return "󰈂"; // Cable disconnected
    if (root.currentStatus === "connecting") return "󰌗"; // Pending / DHCP
    if (root.hasInternet) return "󰈀"; // Connected & Internet OK
    return "󰈀"; // Connected LAN, no WAN
  }

  // Status-derived color
  readonly property color statusColor: {
    if (!root.isCarrier) return "#f38ba8"; // Red (unplugged)
    if (root.currentStatus === "connecting") return "#89dceb"; // Cyan (connecting)
    if (root.hasInternet) return "#a6e3a1"; // Green (internet online)
    return "#f9e2af"; // Yellow (LAN only, no internet)
  }

  // Status description for tooltip
  readonly property string tooltipText: {
    if (!ethData || !ethData.ok) return "Ethernet: Not Detected";
    const iface = ethData.interface || "eth";
    if (!root.isCarrier) return "Ethernet (" + iface + "): Cable Unplugged";
    if (root.currentStatus === "connecting") return "Ethernet (" + iface + "): Connecting...";
    if (root.hasInternet) {
      const ipStr = ethData.ip ? (" • " + ethData.ip.split("/")[0]) : "";
      return "Ethernet: Internet OK (" + iface + ipStr + ")";
    }
    return "Ethernet (" + iface + "): No Internet (Local Only)";
  }

  implicitWidth: contentRow.width
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight

  function refresh(): void {
    if (!statusProc.running) {
      root.isBusy = true;
      statusProc.running = true;
    }
  }

  // Instant reactive trigger when Quickshell.Networking connectivity changes
  Connections {
    target: Networking
    function onConnectivityChanged() {
      root.refresh();
    }
  }

  Component.onCompleted: root.refresh()

  Process {
    id: statusProc
    command: ["sh", "-c", "/usr/bin/python3 /home/dev/Projects/quick-shell/ethernet-bridge.py status"]
    stdout: StdioCollector {
      id: widgetCollector
      onStreamFinished: {
        root.isBusy = false;
        const raw = widgetCollector.text;
        if (!raw) return;
        try {
          const data = JSON.parse(raw);
          if (data && data.ok) {
            root.ethData = data;
          }
        } catch (e) {
          console.warn("EthernetWidget parse error:", e);
        }
      }
    }
    onExited: error => {
      root.isBusy = false;
      if (error !== 0) {
        console.warn("EthernetWidget: status process exited with", error);
      }
    }
  }

  Timer {
    id: pollTimer
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Row {
    id: contentRow
    spacing: 5
    anchors.verticalCenter: parent.verticalCenter

    // Small Ethernet status icon
    Text {
      id: ethIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: 13
      color: root.statusColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
    }

    // Small status dot indicator
    Rectangle {
      id: statusDot
      width: 6
      height: 6
      radius: 3
      anchors.verticalCenter: parent.verticalCenter
      color: root.statusColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }

      // Gentle pulsing animation when connecting or no internet
      SequentialAnimation on opacity {
        running: (root.currentStatus === "connecting" || root.currentStatus === "no_internet")
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
      }
    }
  }
}
