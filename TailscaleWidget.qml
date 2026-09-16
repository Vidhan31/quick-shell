// TailscaleWidget.qml — Minimal Top bar widget for Tailscale
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property int pollInterval: 3000
  property var tsData: ({
    connected: false,
    backend_state: "Unknown",
    ssh_enabled: false,
    serve_items: [],
    self: { hostname: "", ipv4: "", dns_name: "" },
    peers: []
  })
  property bool isBusy: false

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property bool isConnected: tsData && tsData.connected === true
  readonly property int serveCount: (tsData && tsData.serve_items) ? tsData.serve_items.length : 0
  readonly property bool hasFunnel: {
    if (!tsData || !tsData.serve_items) return false;
    for (let i = 0; i < tsData.serve_items.length; i++) {
      if (tsData.serve_items[i].is_funnel) return true;
    }
    return false;
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

  Component.onCompleted: root.refresh()

  Process {
    id: statusProc
    command: ["sh", "-c", "/usr/bin/python3 /home/dev/Projects/quick-shell/tailscale-bridge.py status"]
    stdout: StdioCollector {
      id: widgetCollector
      onStreamFinished: {
        root.isBusy = false;
        const raw = widgetCollector.text;
        if (!raw) return;
        try {
          const data = JSON.parse(raw);
          if (data && data.ok) {
            root.tsData = data;
          }
        } catch (e) {
          console.warn("TailscaleWidget parse error:", e);
        }
      }
    }
    onExited: error => {
      root.isBusy = false;
      if (error !== 0) {
        console.warn("TailscaleWidget: status process exited with", error);
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
    spacing: 6
    anchors.verticalCenter: parent.verticalCenter

    // Status Icon
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "󰖩"
      font.family: root.monoFont
      font.pixelSize: 13
      color: root.isConnected ? (root.hasFunnel ? "#cba6f7" : "#89b4fa") : "#f38ba8"
    }

    // Status Label
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: {
        if (!root.isConnected) return "TS Offline";
        if (root.serveCount > 0) {
          return (root.hasFunnel ? "Funnel" : "Serve") + " (" + root.serveCount + ")";
        }
        if (root.tsData.ssh_enabled) return "TS (SSH)";
        return "Tailscale";
      }
      font.family: root.monoFont
      font.pixelSize: 12
      font.bold: root.isConnected
      color: root.isConnected ? "#cdd6f4" : "#a6adc8"
    }

    // Status Dot Indicator
    Rectangle {
      width: 6
      height: 6
      radius: 3
      anchors.verticalCenter: parent.verticalCenter
      color: root.isConnected ? "#a6e3a1" : "#f38ba8"
    }
  }
}
