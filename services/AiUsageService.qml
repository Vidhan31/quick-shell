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

  readonly property double totalAllTokens: (ocMonitor ? ocMonitor.allTokens : 0) + (agyMonitor ? agyMonitor.allTokens : 0)

  readonly property double totalAllCost: {
    const tick = pricingMonitor ? pricingMonitor.modelCount : 0;
    let sum = 0;

    if (ocMonitor && ocMonitor.allModels && pricingMonitor) {
      const ocList = ocMonitor.allModels;
      for (let i = 0; i < ocList.length; ++i) {
        const m = ocList[i];
        const inp = Number(m.input) || 0, out = Number(m.output) || 0;
        const cr = Number(m.cacheRead) || 0, cw = Number(m.cacheWrite) || 0, rz = Number(m.reasoning) || 0;
        const hypo = pricingMonitor.costForModel(String(m.name), inp, out, cr, cw, rz);
        if (!isNaN(hypo)) {
          sum += hypo;
        } else if (m.cost && !isNaN(m.cost)) {
          sum += Number(m.cost);
        }
      }
    }

    if (agyMonitor && agyMonitor.allModels && pricingMonitor) {
      const agyList = agyMonitor.allModels;
      for (let i = 0; i < agyList.length; ++i) {
        const m = agyList[i];
        const inp = Number(m.input) || 0, out = Number(m.output) || 0;
        const cr = Number(m.cacheRead) || 0, rz = Number(m.reasoning) || 0;
        const hypo = pricingMonitor.costForModel(String(m.name), inp, out, cr, 0, rz);
        if (!isNaN(hypo)) {
          sum += hypo;
        }
      }
    }

    return sum;
  }

  function compactTokens(value: double): string {
    if (ocMonitor && typeof ocMonitor.compact === "function") {
      return ocMonitor.compact(value);
    }
    const v = Number(value);
    if (v >= 1e9) {
      return (v / 1e9).toFixed(2).replace(/\.?0+$/, "") + "B";
    }
    if (v >= 1e6) {
      return (v / 1e6).toFixed(2).replace(/\.?0+$/, "") + "M";
    }
    if (v >= 1e3) {
      return (v / 1e3).toFixed(2).replace(/\.?0+$/, "") + "K";
    }
    return String(Math.round(v));
  }

  readonly property string totalTokensText: {
    if (ocMonitor.lastRefresh === "" && agyMonitor.lastRefresh === "")
      return "--";
    return root.compactTokens(root.totalAllTokens);
  }

  readonly property string totalCostText: {
    if (ocMonitor.lastRefresh === "" && agyMonitor.lastRefresh === "")
      return "--";
    return "$" + root.totalAllCost.toFixed(2);
  }

  Component.onCompleted: {
    if (pricingMonitor && !pricingMonitor.ready && !pricingMonitor.busy) {
      pricingMonitor.refresh();
    }
  }

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
