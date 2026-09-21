// AiUsageWidget.qml — Combined OpenCode + Antigravity chip for the top bar.
// Owns both monitors; manual refresh only: one fetch each on startup,
// then only when refreshAll() runs.
import QtQuick
import Quickshell.Plugins.TokenUsage
import Quickshell.Plugins.AntigravityUsage

Item {
  id: root

  TokenUsage {
    id: ocMonitor
  }

  AntigravityUsage {
    id: agyMonitor
    Component.onCompleted: agyMonitor.refresh()
  }

  property alias oc: ocMonitor
  property alias agy: agyMonitor
  readonly property bool isBusy: ocMonitor.busy || agyMonitor.busy
  readonly property bool ocConfigured: ocMonitor.configured
  readonly property bool agyConfigured: agyMonitor.configured

  implicitWidth: contentRow.width
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight

  function refreshAll(): void {
    ocMonitor.refresh();
    agyMonitor.refresh();
  }

  function ocText(): string {
    if (ocMonitor.lastRefresh === "")
      return "--";
    return ocMonitor.compact(ocMonitor.todayTokens);
  }

  function agyText(): string {
    if (agyMonitor.lastRefresh === "")
      return "--";
    return agyMonitor.compact(agyMonitor.todayTokens);
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
      color: root.ocConfigured ? "#94e2d5" : "#6F6F84"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ocText()
      font.pixelSize: 12
      font.family: "JetBrainsMono Nerd Font Mono"
      color: "#C9C9D6"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "·"
      font.pixelSize: 12
      font.family: "JetBrainsMono Nerd Font Mono"
      color: "#585b70"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "✦"
      font.family: "JetBrainsMono Nerd Font Mono"
      font.pixelSize: 13
      color: root.agyConfigured ? "#c4b5fd" : "#6F6F84"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.agyText()
      font.pixelSize: 12
      font.family: "JetBrainsMono Nerd Font Mono"
      color: "#C9C9D6"
    }
  }
}
