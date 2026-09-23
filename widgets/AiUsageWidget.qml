// AiUsageWidget.qml — Combined OpenCode + Antigravity chip for the top bar.
// Owns both monitors; manual refresh only: one fetch each on startup,
// then only when refreshAll() runs.
import QtQuick
import Quickshell.Plugins.TokenUsage
import Quickshell.Plugins.AntigravityUsage
import "../theme"

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

  readonly property var t: Theme

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

  readonly property double totalTodayTokens: ocMonitor.todayTokens + agyMonitor.todayTokens
  readonly property double ocRatio: root.totalTodayTokens > 0 ? (ocMonitor.todayTokens / root.totalTodayTokens) : 0.5

  Row {
    id: contentRow
    spacing: 7
    anchors.verticalCenter: parent.verticalCenter

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Σ"
      font.family: Theme.mono
      font.pixelSize: 13
      color: root.ocConfigured ? Theme.teal : Theme.ink3
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ocText()
      font.pixelSize: Theme.fontBase
      font.family: Theme.mono
      color: Theme.ink1
    }

    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: root.totalTodayTokens > 0 ? 18 : 6
      height: 14

      Text {
        anchors.centerIn: parent
        visible: root.totalTodayTokens <= 0
        text: "·"
        font.pixelSize: Theme.fontBase
        font.family: Theme.mono
        color: Theme.ink3
      }

      Row {
        anchors.centerIn: parent
        width: 18
        height: 4
        spacing: 1
        visible: root.totalTodayTokens > 0

        Rectangle {
          width: Math.max(2, Math.min(15, Math.round(17 * root.ocRatio)))
          height: parent.height
          radius: 2
          color: Theme.teal
        }
        Rectangle {
          width: Math.max(2, 17 - Math.max(2, Math.min(15, Math.round(17 * root.ocRatio))))
          height: parent.height
          radius: 2
          color: Theme.violet
        }
      }
    }


    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "✦"
      font.family: Theme.mono
      font.pixelSize: 13
      color: root.agyConfigured ? Theme.violet : Theme.ink3
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.agyText()
      font.pixelSize: Theme.fontBase
      font.family: Theme.mono
      color: Theme.ink1
    }
  }
}
