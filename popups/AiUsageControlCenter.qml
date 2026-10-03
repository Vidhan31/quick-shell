pragma ComponentBehavior: Bound
// Fixed 620 height avoids resizing the mapped Wayland popup surface on tab change.
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"
import "ai"

Item {
  id: root

  property var aiUsage: null
  property var ocMonitor: aiUsage ? aiUsage.oc : null
  property var agyMonitor: aiUsage ? aiUsage.agy : null
  property var pricing: aiUsage ? aiUsage.pricing : null
  property var barWindow: null
  property var popupWindow: null

  function findHost(): var {
    let p = root.parent;
    while (p) {
      if (typeof p.showTip === "function") return p;
      if (p.barWindow && typeof p.barWindow.showTip === "function") return p.barWindow;
      p = p.parent;
    }
    return null;
  }

  Component.onDestruction: {
    const host = root.findHost();
    if (host && typeof host.hideTip === "function") {
      host.hideTip();
    }
  }

  signal triggerRefreshAll()

  property int currentTab: 0 // 0: Overview, 1: OpenCode, 2: Antigravity, 3: Cost

  onCurrentTabChanged: {
    /* First visit to the Cost tab kicks the pricing fetch when there is
       nothing to show yet (no cache); otherwise the plugin
       refreshes itself only when its TTL expires. */
    if (root.currentTab === 3 && root.pricing && !root.pricing.ready && !root.pricing.busy)
      root.pricing.refresh();
  }

  property int selectedMonths: 1
  readonly property var monthOptions: [1, 3, 6, 12]

  function monthsToDays(m: int): int {
    switch (m) {
      case 1: return 30;
      case 3: return 90;
      case 6: return 180;
      case 12: return 365;
      default: return m * 30;
    }
  }

  function syncRange(): void {
    const days = root.monthsToDays(root.selectedMonths);
    if (root.ocMonitor && root.ocMonitor.lastDays !== undefined && root.ocMonitor.lastDays !== days)
      root.ocMonitor.setLastDays(days);
    if (root.agyMonitor && root.agyMonitor.lastDays !== undefined && root.agyMonitor.lastDays !== days)
      root.agyMonitor.setLastDays(days);
  }

  function hideTip(): void {
    // Retained for popup dismissal lifecycle compatibility
  }

  onSelectedMonthsChanged: root.syncRange()
  onOcMonitorChanged: root.syncRange()
  onAgyMonitorChanged: root.syncRange()
  Component.onCompleted: root.syncRange()

  implicitWidth: Theme.popupWidthMd
  implicitHeight: 620

  readonly property bool busy: (root.ocMonitor ? root.ocMonitor.busy : false) || (root.agyMonitor ? root.agyMonitor.busy : false)
  readonly property string ocError: root.ocMonitor ? root.ocMonitor.error : ""
  readonly property string agyError: root.agyMonitor ? root.agyMonitor.error : ""
  readonly property bool hasError: root.ocError !== "" || root.agyError !== ""
  readonly property string ocUpdated: (root.ocMonitor && root.ocMonitor.lastRefresh !== "") ? root.ocMonitor.lastRefresh : "never"
  readonly property string agyUpdated: (root.agyMonitor && root.agyMonitor.lastRefresh !== "") ? root.agyMonitor.lastRefresh : "never"

  function money(value: double): string {

    return "$" + value.toFixed(2);
  }

  readonly property var ocModelRows: root.ocMonitor === null ? [] : root.ocMonitor.monthModels.map(function (m) {
    return {
      name: m.name,
      tokens: root.ocMonitor.compact(m.tokens),
      raw: m.tokens,
      input: m.input || 0,
      output: m.output || 0,
      cacheRead: m.cacheRead || 0,
      cacheWrite: m.cacheWrite || 0,
      reasoning: m.reasoning || 0,
      cost: m.cost || 0,
      src: "oc"
    };
  })

  readonly property var agyModelRows: root.agyMonitor === null ? [] : root.agyMonitor.monthModels.map(function (m) {
    return {
      name: m.name,
      tokens: root.agyMonitor.compact(m.tokens),
      raw: m.tokens,
      input: m.input || 0,
      output: m.output || 0,
      cacheRead: m.cacheRead || 0,
      cacheWrite: 0,
      reasoning: m.reasoning || 0,
      cost: 0,
      src: "agy"
    };
  })

  readonly property var combinedModels: root.ocModelRows.concat(root.agyModelRows).slice().sort(function (a, b) { return b.raw - a.raw; })

  readonly property var agySourceRows: root.agyMonitor === null ? [] : root.agyMonitor.monthSources.map(function (s) {
    return { name: s.name, tokens: root.agyMonitor.compact(s.tokens), raw: s.tokens };
  })
  readonly property double maxAgySourceTokens: (root.agySourceRows.length > 0 && root.agySourceRows[0].raw > 0) ? root.agySourceRows[0].raw : 1

  property int overviewChartPeriod: 2 // 0: Today, 1: Week, 2: Month / Window
  property int ocChartPeriod: 2 // 0: Today, 1: Week, 2: Month / Window
  property int agyChartPeriod: 2 // 0: Today, 1: Week, 2: Month / Window

  readonly property var donutPeriods: ["Today", "Week", root.selectedMonths === 1 ? "Month" : (root.selectedMonths + "m")]

  readonly property var overviewChartData: {
    if (root.ocMonitor === null || root.agyMonitor === null) {
      return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, totalText: "--", totalSub: "tokens", ocTokens: 0, agyTokens: 0 };
    }
    const ocS = root.overviewChartPeriod === 0 ? root.ocMonitor.todaySplit
              : (root.overviewChartPeriod === 1 ? root.ocMonitor.weekSplit : root.ocMonitor.lastDaysSplit);
    const agyS = root.overviewChartPeriod === 0 ? root.agyMonitor.todaySplit
               : (root.overviewChartPeriod === 1 ? root.agyMonitor.weekSplit : root.agyMonitor.lastDaysSplit);

    const ocT = root.overviewChartPeriod === 0 ? root.ocMonitor.todayTokens
              : (root.overviewChartPeriod === 1 ? root.ocMonitor.weekTokens : root.ocMonitor.lastDaysTokens);
    const agyT = root.overviewChartPeriod === 0 ? root.agyMonitor.todayTokens
               : (root.overviewChartPeriod === 1 ? root.agyMonitor.weekTokens : root.agyMonitor.lastDaysTokens);

    const inp = (ocS ? (ocS.input || 0) : 0) + (agyS ? (agyS.input || 0) : 0);
    const out = (ocS ? (ocS.output || 0) : 0) + (agyS ? (agyS.output || 0) : 0);
    const cr = (ocS ? (ocS.cacheRead || 0) : 0) + (agyS ? (agyS.cacheRead || 0) : 0);
    const cw = (ocS ? (ocS.cacheWrite || 0) : 0);
    const rz = (ocS ? (ocS.reasoning || 0) : 0) + (agyS ? (agyS.reasoning || 0) : 0);
    const total = ocT + agyT;

    return {
      input: inp,
      output: out,
      cacheRead: cr,
      cacheWrite: cw,
      reasoning: rz,
      totalText: root.ocMonitor.compact(total),
      totalSub: root.overviewChartPeriod === 0 ? "today" : (root.overviewChartPeriod === 1 ? "this week" : (root.selectedMonths === 1 ? "past 30 days" : ("past " + (root.selectedMonths * 30) + " days"))),
      ocTokens: ocT,
      agyTokens: agyT
    };
  }

  readonly property var ocChartData: {
    if (root.ocMonitor === null) {
      return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, totalText: "--", totalSub: "tokens" };
    }
    const s = root.ocChartPeriod === 0 ? root.ocMonitor.todaySplit
            : (root.ocChartPeriod === 1 ? root.ocMonitor.weekSplit : root.ocMonitor.lastDaysSplit);
    const t = root.ocChartPeriod === 0 ? root.ocMonitor.todayTokens
            : (root.ocChartPeriod === 1 ? root.ocMonitor.weekTokens : root.ocMonitor.lastDaysTokens);
    return {
      input: s ? (s.input || 0) : 0,
      output: s ? (s.output || 0) : 0,
      cacheRead: s ? (s.cacheRead || 0) : 0,
      cacheWrite: s ? (s.cacheWrite || 0) : 0,
      reasoning: s ? (s.reasoning || 0) : 0,
      totalText: root.ocMonitor.compact(t),
      totalSub: root.ocChartPeriod === 0 ? "today" : (root.ocChartPeriod === 1 ? "this week" : (root.selectedMonths === 1 ? "past 30 days" : ("past " + (root.selectedMonths * 30) + " days")))
    };
  }

  readonly property var agyChartData: {
    if (root.agyMonitor === null) {
      return { input: 0, output: 0, cacheRead: 0, reasoning: 0, totalText: "--", totalSub: "tokens" };
    }
    const s = root.agyChartPeriod === 0 ? root.agyMonitor.todaySplit
            : (root.agyChartPeriod === 1 ? root.agyMonitor.weekSplit : root.agyMonitor.lastDaysSplit);
    const t = root.agyChartPeriod === 0 ? root.agyMonitor.todayTokens
            : (root.agyChartPeriod === 1 ? root.agyMonitor.weekTokens : root.agyMonitor.lastDaysTokens);
    return {
      input: s ? (s.input || 0) : 0,
      output: s ? (s.output || 0) : 0,
      cacheRead: s ? (s.cacheRead || 0) : 0,
      reasoning: s ? (s.reasoning || 0) : 0,
      totalText: root.agyMonitor.compact(t),
      totalSub: root.agyChartPeriod === 0 ? "today" : (root.agyChartPeriod === 1 ? "this week" : (root.selectedMonths === 1 ? "past 30 days" : ("past " + (root.selectedMonths * 30) + " days")))
    };
  }

  readonly property double maxCombinedModelTokens: (root.combinedModels.length > 0 && root.combinedModels[0].raw > 0) ? root.combinedModels[0].raw : 1
  readonly property double maxOcModelTokens: (root.ocModelRows.length > 0 && root.ocModelRows[0].raw > 0) ? root.ocModelRows[0].raw : 1
  readonly property double maxAgyModelTokens: (root.agyModelRows.length > 0 && root.agyModelRows[0].raw > 0) ? root.agyModelRows[0].raw : 1

  // Reading pricing.modelCount subscribes this block to the pricing
  // plugin's dataChanged, so rows recompute when the index loads/refreshes.
  readonly property var costRows: {
    const tick = root.pricing ? root.pricing.modelCount : 0;
    if (root.pricing === null) return [];
    const rows = [];
    const all = root.ocModelRows.concat(root.agyModelRows);
    for (let i = 0; i < all.length; ++i) {
      const m = all[i];
      const inp = m.input || 0, out = m.output || 0;
      const cr = m.cacheRead || 0, cw = m.cacheWrite || 0, rz = m.reasoning || 0;
      const hypo = root.pricing.costForModel(m.name, inp, out, cr, cw, rz);
      const isPriced = !isNaN(hypo);
      const meta = root.pricing.priceForModel(m.name);
      const savings = (isPriced && typeof root.pricing.savingsForModel === "function")
        ? root.pricing.savingsForModel(m.name, cr)
        : 0;
      rows.push({
        name: m.name,
        src: m.src,
        tokensText: m.tokens,
        rawTokens: m.raw,
        hypo: isPriced ? hypo : NaN,
        isPriced: isPriced,
        savings: savings,
        provider: meta.provider || "",
        family: meta.family || "",
        viaFallback: meta.viaFallback === true,
        isOverride: meta.isOverride === true,
        costSource: meta.costSource || (isPriced ? "official" : "unpriced"),
        matchedId: meta.matchedId || m.name,
        input: inp, output: out, cacheRead: cr, cacheWrite: cw, reasoning: rz,
        rateIn: meta.input || 0, rateOut: meta.output || 0,
        rateCacheRead: meta.cacheRead || 0, rateCacheWrite: meta.cacheWrite || 0
      });
    }
    rows.sort(function(a, b) {
      if (a.isPriced && b.isPriced) return b.hypo - a.hypo;
      if (a.isPriced && !b.isPriced) return -1;
      if (!a.isPriced && b.isPriced) return 1;
      return b.rawTokens - a.rawTokens;
    });
    return rows;
  }

  function sumHypo(src: string): double {
    let s = 0;
    for (let i = 0; i < root.costRows.length; ++i) {
      const h = root.costRows[i].hypo;
      if (root.costRows[i].src === src && !isNaN(h)) s += h;
    }
    return s;
  }

  function sumSavings(src: string): double {
    let s = 0;
    for (let i = 0; i < root.costRows.length; ++i) {
      const r = root.costRows[i];
      if ((src === "all" || r.src === src) && r.savings && !isNaN(r.savings)) s += r.savings;
    }
    return s;
  }

  readonly property double ocHypo: root.sumHypo("oc")
  readonly property double agyHypo: root.sumHypo("agy")
  readonly property double totalHypo: root.ocHypo + root.agyHypo
  readonly property double totalSavings: root.sumSavings("all")
  readonly property int pricedCostCount: root.costRows.filter(function(r) { return !isNaN(r.hypo); }).length
  readonly property string pricingStatus: {
    if (root.pricing === null) return "pricing unavailable";
    if (root.pricing.busy) return "updating official rates…";
    if (root.pricing.ready && root.pricing.lastRefresh !== "") return "official rates · updated " + root.pricing.lastRefresh;
    if (root.pricing.error !== "") return root.pricing.error;
    return "loading official rates…";
  }

  readonly property var segItems: [
    { label: "Overview" },
    { label: "OpenCode" },
    { label: "Antigravity" },
    { label: "Cost" }
  ]

  readonly property var t: Theme

  PopupCard {
    id: card
    anchors.fill: parent

    ColumnLayout {
      anchors.fill: parent
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        spacing: 8

        Segments {
          Layout.fillWidth: true
          items: root.segItems
          current: root.currentTab
          onSelected: index => root.currentTab = index
        }

        IconBtn {
          glyph: "󰑓"
          fs: 14
          spinning: root.busy
          tooltip: "Refresh AI usage"
          tooltipSub: "Fetch latest token counters"
          onClicked: root.triggerRefreshAll()
        }
      }


      Item { Layout.preferredHeight: 6; Layout.fillWidth: true }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        spacing: 6

        Row {
          spacing: 6
          Layout.alignment: Qt.AlignVCenter

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Rolling window"
            font.pixelSize: Theme.fontSm
            font.family: root.t.mono
            color: Theme.ink3
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "· " + (root.selectedMonths === 1 ? "30 days" : (root.selectedMonths * 30 + " days"))
            font.pixelSize: Theme.fontSm
            font.family: root.t.mono
            color: Theme.ink2
          }
        }

        Item { Layout.fillWidth: true }

        Row {
          spacing: 3
          Layout.alignment: Qt.AlignVCenter

          Repeater {
            model: root.monthOptions

            Rectangle {
              id: uPill
              required property var modelData
              required property int index
              readonly property bool isSelected: uPill.modelData === root.selectedMonths

              width: uPillText.implicitWidth + 14
              height: 20
              radius: Theme.radiusChip
              color: isSelected ? Theme.selected : (uPillMouse.containsMouse || uPill.activeFocus ? Theme.hoverFill : "transparent")
              border.width: uPill.activeFocus ? Theme.focusRingWidth : 0
              border.color: Theme.focusRing
              activeFocusOnTab: true

              Accessible.role: Accessible.Button
              Accessible.name: uPill.modelData + " month rolling window"

              Behavior on color { ColorAnimation { duration: Theme.durationFast } }
              Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

              function updateTip(): void {
                const host = root.findHost();
                if ((uPillMouse.containsMouse || uPill.activeFocus) && host && typeof host.showTip === "function") {
                  host.showTip(uPill, uPill.modelData + " month window", "Show usage for last " + (uPill.modelData * 30) + " days");
                } else if (host && typeof host.hideTip === "function") {
                  host.hideTip();
                }
              }

              onActiveFocusChanged: updateTip()
              Component.onDestruction: {
                const host = root.findHost();
                if (host && typeof host.hideTip === "function") {
                  host.hideTip();
                }
              }

              Keys.onReturnPressed: event => {
                root.selectedMonths = uPill.modelData;
                event.accepted = true;
              }
              Keys.onSpacePressed: event => {
                root.selectedMonths = uPill.modelData;
                event.accepted = true;
              }

              Text {
                id: uPillText
                anchors.centerIn: parent
                text: uPill.modelData + "m"
                font.pixelSize: 11
                font.weight: uPill.isSelected ? Font.DemiBold : Font.Normal
                font.family: Theme.mono
                color: uPill.isSelected ? Theme.ink1 : (uPillMouse.containsMouse ? Theme.ink2 : Theme.ink3)
              }

              MouseArea {
                id: uPillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: uPill.updateTip()
                onClicked: root.selectedMonths = uPill.modelData
              }
            }
          }
        }
      }

      Item { Layout.preferredHeight: 8; Layout.fillWidth: true }

      StackLayout {
        id: tabStack
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: root.currentTab

        Flickable {
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: overviewCol.height
          clip: true
          interactive: contentHeight > height

          Column {
            id: overviewCol
            width: parent.width
            spacing: 10

            SectionHead {
              width: parent.width
              label: "Token distribution"
            }

            TokenDonutCard {
              width: parent.width
              title: "Composition"
              periods: root.donutPeriods

              selectedPeriod: root.overviewChartPeriod
              onPeriodSelected: idx => root.overviewChartPeriod = idx

              inputTokens: root.overviewChartData.input
              outputTokens: root.overviewChartData.output
              cacheReadTokens: root.overviewChartData.cacheRead
              cacheWriteTokens: root.overviewChartData.cacheWrite
              reasoningTokens: root.overviewChartData.reasoning
              showCacheWrite: true

              totalFormatted: root.overviewChartData.totalText
              totalSubtitle: root.overviewChartData.totalSub

              showProviderBar: true
              ocTokens: root.overviewChartData.ocTokens
              agyTokens: root.overviewChartData.agyTokens
              compactFn: v => root.ocMonitor ? root.ocMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
            }

            SectionHead {
              width: parent.width
              label: "Usage timeline"
            }

            TokenTimelineChart {
              width: parent.width
              mode: "overview"
              rangeOptions: root.monthOptions
              selectedRange: root.selectedMonths
              onRangeSelected: months => root.selectedMonths = months
              primaryDaily: root.ocMonitor ? root.ocMonitor.dailyUsage : []
              secondaryDaily: root.agyMonitor ? root.agyMonitor.dailyUsage : []
              compactFn: v => root.ocMonitor ? root.ocMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
              moneyFn: v => root.money(v)
            }


            SectionHead {
              width: overviewCol.width
              visible: root.combinedModels.length > 0
              label: "Top models"
            }

            TopModelsChart {
              width: overviewCol.width
              visible: root.combinedModels.length > 0
              title: "Combined models"
              mode: "overview"
              models: root.combinedModels
              selectedMonths: root.selectedMonths
              compactFn: v => root.ocMonitor ? root.ocMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
              moneyFn: v => root.money(v)
            }


            Text {
              width: overviewCol.width
              text: "OpenCode updated " + root.ocUpdated + "  ·  Antigravity updated " + root.agyUpdated
              font.pixelSize: Theme.fontSm
              font.family: root.t.mono
              color: root.t.ink3
              wrapMode: Text.Wrap
            }

            Text {
              width: overviewCol.width
              visible: root.ocError !== ""
              text: "OpenCode: " + root.ocError
              font.pixelSize: Theme.fontSm
              font.family: root.t.mono
              color: root.t.red
              wrapMode: Text.Wrap
            }

            Text {
              width: overviewCol.width
              visible: root.agyError !== ""
              text: "Antigravity: " + root.agyError
              font.pixelSize: Theme.fontSm
              font.family: root.t.mono
              color: root.t.red
              wrapMode: Text.Wrap
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 1 ? 1 : 0
          Behavior on opacity { OpacityAnimator { duration: 110 } }

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: ocCol.height
            clip: true

            Column {
              id: ocCol
              width: parent.width
              spacing: 12

              SectionHead {
                width: parent.width
                label: "Token composition"
              }

              TokenDonutCard {
                width: parent.width
                title: "OpenCode breakdown"
                periods: root.donutPeriods
                selectedPeriod: root.ocChartPeriod
                onPeriodSelected: idx => root.ocChartPeriod = idx

                inputTokens: root.ocChartData.input
                outputTokens: root.ocChartData.output
                cacheReadTokens: root.ocChartData.cacheRead
                cacheWriteTokens: root.ocChartData.cacheWrite
                reasoningTokens: root.ocChartData.reasoning
                showCacheWrite: true

                totalFormatted: root.ocChartData.totalText
                totalSubtitle: root.ocChartData.totalSub
                compactFn: v => root.ocMonitor ? root.ocMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
              }

              SectionHead {
                width: parent.width
                label: "Usage timeline"
              }

              TokenTimelineChart {
                width: parent.width
                mode: "opencode"
                rangeOptions: root.monthOptions
                selectedRange: root.selectedMonths
                onRangeSelected: months => root.selectedMonths = months
                primaryDaily: root.ocMonitor ? root.ocMonitor.dailyUsage : []
                compactFn: v => root.ocMonitor ? root.ocMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
                moneyFn: v => root.money(v)
              }


              SectionHead {
                width: parent.width
                visible: root.ocModelRows.length > 0
                label: "Top models"
              }

              TopModelsChart {
                width: parent.width
                visible: root.ocModelRows.length > 0
                title: "OpenCode models"
                mode: "opencode"
                models: root.ocModelRows
                selectedMonths: root.selectedMonths
                compactFn: v => root.ocMonitor ? root.ocMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
                moneyFn: v => root.money(v)
              }

              Text {
                width: parent.width
                text: "Updated " + root.ocUpdated
                font.pixelSize: Theme.fontSm
                font.family: root.t.mono
                color: root.t.ink3
              }

              Text {
                width: parent.width
                visible: root.ocError !== ""
                text: root.ocError
                font.pixelSize: Theme.fontSm
                font.family: root.t.mono
                color: root.t.red
                wrapMode: Text.Wrap
              }
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 2 ? 1 : 0
          Behavior on opacity { OpacityAnimator { duration: 110 } }

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: agyCol.height
            clip: true

            Column {
              id: agyCol
              width: parent.width
              spacing: 12

              SectionHead {
                width: parent.width
                label: "Token composition"
              }

              TokenDonutCard {
                width: parent.width
                title: "Antigravity breakdown"
                periods: root.donutPeriods
                selectedPeriod: root.agyChartPeriod
                onPeriodSelected: idx => root.agyChartPeriod = idx

                inputTokens: root.agyChartData.input
                outputTokens: root.agyChartData.output
                cacheReadTokens: root.agyChartData.cacheRead
                reasoningTokens: root.agyChartData.reasoning
                showCacheWrite: false

                totalFormatted: root.agyChartData.totalText
                totalSubtitle: root.agyChartData.totalSub
                compactFn: v => root.agyMonitor ? root.agyMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
              }

              SectionHead {
                width: parent.width
                label: "Usage timeline"
              }

              TokenTimelineChart {
                width: parent.width
                mode: "antigravity"
                rangeOptions: root.monthOptions
                selectedRange: root.selectedMonths
                onRangeSelected: months => root.selectedMonths = months
                primaryDaily: root.agyMonitor ? root.agyMonitor.dailyUsage : []
                compactFn: v => root.agyMonitor ? root.agyMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
              }

              SectionHead {
                width: parent.width
                visible: root.agySourceRows.length > 0
                label: "Sources"
              }

              SectionCard {
                visible: root.agySourceRows.length > 0
                width: parent.width
                height: agySourcesCol.height + 8

                Column {
                  id: agySourcesCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.topMargin: 4
                  anchors.leftMargin: 12
                  anchors.rightMargin: 12

                  Repeater {
                    model: root.agySourceRows
                    Column {
                      id: agySourceRow
                      required property var modelData
                      required property int index
                      width: agySourcesCol.width

                      Hairline {
                        visible: agySourceRow.index > 0
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                      }

                      RowLayout {
                        width: parent.width
                        height: 46
                        Column {
                          Layout.fillWidth: true
                          spacing: 3
                          Text {
                            width: parent.width
                            text: agySourceRow.modelData.name
                            font.pixelSize: Theme.fontBase
                            font.family: root.t.mono
                            color: root.t.ink2
                            elide: Text.ElideMiddle
                          }
                          Rectangle {
                            width: parent.width
                            height: 3
                            radius: 1.5
                            color: root.t.cardBorder
                            Rectangle {
                              height: parent.height
                              radius: parent.radius
                              width: Math.max(3, Math.round(parent.width * Math.min(1.0, (agySourceRow.modelData.raw !== undefined ? agySourceRow.modelData.raw : 1) / root.maxAgySourceTokens)))
                              color: root.t.violet
                            }
                          }
                        }

                         ColumnLayout {
                           spacing: 2
                           Text {
                             Layout.alignment: Qt.AlignRight
                             text: agySourceRow.modelData.tokens
                             font.pixelSize: Theme.fontMd
                             font.family: root.t.mono
                             color: root.t.ink1
                           }
                         }

                      }
                    }
                  }
                }
              }

              SectionHead {
                width: parent.width
                visible: root.agyModelRows.length > 0
                label: "Top models"
              }

              TopModelsChart {
                width: parent.width
                visible: root.agyModelRows.length > 0
                title: "Antigravity models"
                mode: "antigravity"
                models: root.agyModelRows
                selectedMonths: root.selectedMonths
                compactFn: v => root.agyMonitor ? root.agyMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
              }

              Text {
                width: parent.width
                text: "Updated " + root.agyUpdated
                font.pixelSize: Theme.fontSm
                font.family: root.t.mono
                color: root.t.ink3
              }

              Text {
                width: parent.width
                visible: root.agyError !== ""
                text: root.agyError
                font.pixelSize: Theme.fontSm
                font.family: root.t.mono
                color: root.t.red
                wrapMode: Text.Wrap
              }
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 3 ? 1 : 0
          Behavior on opacity { OpacityAnimator { duration: 110 } }

          Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: costCol.height
            clip: true

            Column {
              id: costCol
              width: parent.width
              spacing: 12

              SectionHead {
                width: parent.width
                label: "Hypothetical cost"
              }

              SectionCard {
                width: parent.width
                height: costSummaryCol.height + 8
                Column {
                  id: costSummaryCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.topMargin: 4
                  anchors.leftMargin: 12
                  anchors.rightMargin: 12
                  spacing: 2

                  RowLayout {
                    width: parent.width
                    height: 30
                    Text {
                      Layout.fillWidth: true
                      text: "OpenCode"
                      font.pixelSize: Theme.fontBase
                      font.family: root.t.mono
                      color: root.t.ink2
                    }
                    Text {
                      text: root.money(root.ocHypo)
                      font.pixelSize: Theme.fontMd
                      font.weight: Font.DemiBold
                      font.family: root.t.mono
                      color: root.t.green
                    }
                  }

                  Hairline { width: parent.width }

                  RowLayout {
                    width: parent.width
                    height: 30
                    Text {
                      Layout.fillWidth: true
                      text: "Antigravity"
                      font.pixelSize: Theme.fontBase
                      font.family: root.t.mono
                      color: root.t.ink2
                    }
                    Text {
                      text: root.money(root.agyHypo)
                      font.pixelSize: Theme.fontMd
                      font.weight: Font.DemiBold
                      font.family: root.t.mono
                      color: root.t.green
                    }
                  }

                  Hairline { width: parent.width }

                  RowLayout {
                    width: parent.width
                    height: 34
                    Text {
                      Layout.fillWidth: true
                      text: "Combined"
                      font.pixelSize: Theme.fontBase
                      font.weight: Font.DemiBold
                      font.family: root.t.sans
                      color: root.t.ink1
                    }
                    Text {
                      text: root.money(root.totalHypo)
                      font.pixelSize: 16
                      font.weight: Font.DemiBold
                      font.family: root.t.mono
                      color: root.t.green
                    }
                  }

                  Hairline {
                    visible: root.totalSavings > 0
                    width: parent.width
                  }

                  RowLayout {
                    visible: root.totalSavings > 0
                    width: parent.width
                    height: 30
                    Row {
                      spacing: 6
                      Layout.fillWidth: true
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Cache savings"
                        font.pixelSize: Theme.fontBase
                        font.family: root.t.mono
                        color: root.t.ink2
                      }
                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 16
                        width: savingsBadgeText.implicitWidth + 8
                        radius: 8
                        color: Theme.accentBg
                        Text {
                          id: savingsBadgeText
                          anchors.centerIn: parent
                          text: "prompt cache"
                          font.pixelSize: 9
                          font.family: root.t.mono
                          color: Theme.accent
                        }
                      }
                    }
                    Text {
                      text: "-" + root.money(root.totalSavings)
                      font.pixelSize: Theme.fontMd
                      font.weight: Font.DemiBold
                      font.family: root.t.mono
                      color: root.t.teal
                    }
                  }

                  Text {
                    width: parent.width
                    text: root.pricingStatus
                    font.pixelSize: Theme.fontSm
                    font.family: root.t.mono
                    color: root.t.ink3
                    wrapMode: Text.Wrap
                  }
                }
              }

              SectionHead {
                width: parent.width
                visible: root.costRows.length > 0
                label: "Models by cost"
              }

              CostModelsChart {
                width: parent.width
                visible: root.costRows.length > 0
                title: "Official API rates"
                selectedMonths: root.selectedMonths
                models: root.costRows
                emptyText: root.pricing && !root.pricing.ready ? "Loading official pricing…" : "No model activity recorded in this period"
                compactFn: v => root.ocMonitor ? root.ocMonitor.compact(v) : (v >= 1e6 ? (v/1e6).toFixed(1) + "M" : v.toString())
                moneyFn: v => root.money(v)
                logoFn: p => root.pricing ? root.pricing.logoForProvider(p) : ""
              }

              Text {
                width: parent.width
                text: "What this usage would cost at official provider rates (Gemini → Google, Claude → Anthropic, Muse → Meta). Free-tier variants map to their paid counterpart; models without an official entry show unpriced. Cache savings show cost avoided by prompt caching."
                font.pixelSize: Theme.fontSm
                font.family: root.t.mono
                color: root.t.ink3
                wrapMode: Text.Wrap
              }
            }
          }
        }
      }
    }
  }
}
