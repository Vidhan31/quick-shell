pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Plugins.TokenUsage
import Quickshell.Plugins.AntigravityUsage
import Quickshell.Plugins.ModelPricing

Item {
  id: root

  TokenUsage {
    id: ocMonitor
  }

  AntigravityUsage {
    id: agyMonitor
  }

  ModelPricing {
    id: pricingMonitor
    configSource: Qt.resolvedUrl("../assets/model-pricing-config.json")
  }

  readonly property alias oc: ocMonitor
  readonly property alias agy: agyMonitor
  readonly property alias pricing: pricingMonitor

  readonly property bool isBusy: ocMonitor.busy || agyMonitor.busy
  readonly property bool ocConfigured: ocMonitor.configured
  readonly property bool agyConfigured: agyMonitor.configured

  readonly property double totalTodayTokens: ocMonitor.todayTokens + agyMonitor.todayTokens
  readonly property double ocRatio: root.totalTodayTokens > 0 ? (ocMonitor.todayTokens / root.totalTodayTokens) : 0.5

  function refreshAll(): void {
    ocMonitor.refresh();
    agyMonitor.refresh();
    pricingMonitor.refresh();
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
}
