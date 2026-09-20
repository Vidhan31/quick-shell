// TokenWidget.qml — OpenCode token totals chip for the top bar.
// Manual refresh only: one fetch on startup, then only when refresh() runs.
import QtQuick
import Quickshell.Plugins.TokenUsage

Item {
  id: root

  TokenUsage {
    id: monitor
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
      return "Tokens --";
    return "Tokens " + monitor.compact(monitor.todayTokens);
  }

  Row {
    id: contentRow
    spacing: 7
    anchors.verticalCenter: parent.verticalCenter

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Σ"
      font.family: "JetBrainsMono Nerd Font Mono"
      font.pixelSize: 13
      color: root.configured ? "#94e2d5" : "#6F6F84"
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
