// TailscaleWidget.qml — Quiet top-bar indicator for Tailscale.
// Single glyph + single word. No dot, no bold, no pill: the tint carries state.
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
    spacing: 7
    anchors.verticalCenter: parent.verticalCenter

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "󰖩"
      font.family: "JetBrainsMono Nerd Font Mono"
      font.pixelSize: 13
      color: {
        if (!root.isConnected) return "#6F6F84";
        if (root.hasFunnel) return "#AE8CFF";
        return "#5E9DFF";
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: {
        if (!root.isConnected) return "Offline";
        if (root.hasFunnel) return "Funnel " + root.serveCount;
        if (root.serveCount > 0) return "Serve " + root.serveCount;
        return "Tailscale";
      }
      font.pixelSize: 12
      color: root.isConnected ? "#C9C9D6" : "#6F6F84"
    }
  }
}
