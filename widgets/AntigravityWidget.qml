// AntigravityWidget.qml — Antigravity token totals chip for the top bar.
// Fully separate from the OpenCode TokenWidget: own plugin, own monitor.
// Manual refresh only: one fetch on startup, then only when refresh() runs.
import QtQuick
import Quickshell.Plugins.AntigravityUsage

Item {
  id: root

  AntigravityUsage {
    id: monitor
    Component.onCompleted: monitor.refresh()
  }

  property alias monitor: monitor
  readonly property bool isBusy: monitor.busy
  readonly property bool configured: monitor.configured

  implicitWidth: contentRow.width
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight
  function refresh(): void {
    monitor.refresh();
  }

  function chipText(): string {
    if (monitor.lastRefresh === "")
      return "AGY --";
    return "AGY " + monitor.compact(monitor.todayTokens);
  }

  Row {
    id: contentRow
    spacing: 7
    anchors.verticalCenter: parent.verticalCenter

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "✦"
      font.family: "JetBrainsMono Nerd Font Mono"
      font.pixelSize: 13
      color: root.configured ? "#c4b5fd" : "#6F6F84"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.chipText()
      font.pixelSize: 12
      font.family: "JetBrainsMono Nerd Font Mono"
      color: "#C9C9D6"
    }
  }
}
