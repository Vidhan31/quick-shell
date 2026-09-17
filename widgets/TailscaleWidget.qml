// TailscaleWidget.qml — Minimal Top bar widget for Tailscale
import QtQuick
import Quickshell
import Quickshell.Plugins.Tailscale

Item {
  id: root

  property int pollInterval: 5000

  TailscaleMonitor {
    id: monitor
    running: true
    interval: root.pollInterval
  }

  property alias monitor: monitor
  property var tsData: monitor.tsData
  readonly property bool isBusy: monitor.isBusy

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property bool isConnected: monitor.connected
  readonly property int serveCount: monitor.serveCount
  readonly property bool hasFunnel: monitor.hasFunnel

  implicitWidth: contentRow.width
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight

  function refresh(): void {
    monitor.refresh();
  }

  Component.onCompleted: root.refresh()

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
