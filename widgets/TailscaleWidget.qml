// TailscaleWidget.qml — Quiet top-bar indicator for Tailscale.
// Single glyph + single word. No dot, no bold, no pill: the tint carries state.
import QtQuick
import Quickshell
import Quickshell.Plugins.Tailscale
import "../theme"

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

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

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
      font.family: Theme.mono
      font.pixelSize: 13
      color: {
        if (!root.isConnected) return Theme.ink3;
        if (root.hasFunnel) return Theme.violet;
        return Theme.accent;
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
      font.pixelSize: Theme.fontBase
      color: root.isConnected ? Theme.ink1 : Theme.ink3
    }
  }
}
