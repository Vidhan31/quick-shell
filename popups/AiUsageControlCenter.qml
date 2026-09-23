pragma ComponentBehavior: Bound
// AiUsageControlCenter.qml — Combined OpenCode + Antigravity usage.
// Tailscale visual system: same tokens, Segments, RowBase, SectionHead,
// IconBtn, Hairline. Fixed 620 height on detail tabs (internal scroll);
// the Overview tab hugs its content like the Tailscale Sharing tab:
// outer height is derived from content height (overviewCol.height),
// never from the viewport, so no binding loop is possible.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../components"

Item {
  id: root

  // var (not typed): if a plugin ever fails to load, the popover still
  // instantiates and degrades to "--" instead of breaking the whole bar.
  property var ocMonitor: null
  property var agyMonitor: null
  property var barWindow: null
  property var popupWindow: null

  signal triggerRefreshAll()

  property int currentTab: 0 // 0: Overview, 1: OpenCode, 2: Antigravity

  // Last-N filter: number of most-recent messages to aggregate. Synced to
  // both monitors (each clamps to [1,500] and refreshes on change).
  property int lastN: 20
  readonly property var lastNOptions: [10, 20, 50, 100]

  function syncLastN(): void {
    if (root.ocMonitor && root.ocMonitor.lastN !== undefined && root.ocMonitor.lastN !== root.lastN)
      root.ocMonitor.setLastN(root.lastN);
    if (root.agyMonitor && root.agyMonitor.lastN !== undefined && root.agyMonitor.lastN !== root.lastN)
      root.agyMonitor.setLastN(root.lastN);
  }

  onLastNChanged: root.syncLastN()
  onOcMonitorChanged: root.syncLastN()
  onAgyMonitorChanged: root.syncLastN()
  Component.onCompleted: root.syncLastN()

  implicitWidth: 440
  // Chrome: card margins 32 + header 40 + gap 14 + segments 34 + gap 12 = 132.
  implicitHeight: root.currentTab === 0 ? Math.min(620, Math.max(380, 132 + overviewCol.height)) : 620
  width: implicitWidth
  height: implicitHeight

  // ---- Shared tooltip state (one system for all tabs) ----
  property var tipDetails: null
  property Item tipTarget: null
  property int tipX: 0
  property int tipY: 0

  Timer {
    id: tipTimer
    interval: 350
    repeat: false
    onTriggered: root.showTip()
  }

  function showTip(): void {
    if (root.tipDetails === null || root.tipTarget === null) {
      return;
    }
    if (root.barWindow === null || root.popupWindow === null) {
      return;
    }
    const pt = root.tipTarget.mapToItem(root, root.tipTarget.width / 2, root.tipTarget.height);
    const frame = root.popupWindow.anchor.rect;
    root.tipX = frame.x + pt.x;
    root.tipY = frame.y + pt.y;
    tip.visible = true;
  }

  function hideTip(): void {
    tipTimer.stop();
    tip.visible = false;
    root.tipDetails = null;
    root.tipTarget = null;
  }

  onCurrentTabChanged: root.hideTip()

  // ---- Derived state ----
  readonly property bool busy: (root.ocMonitor ? root.ocMonitor.busy : false) || (root.agyMonitor ? root.agyMonitor.busy : false)
  readonly property string ocError: root.ocMonitor ? root.ocMonitor.error : ""
  readonly property string agyError: root.agyMonitor ? root.agyMonitor.error : ""
  readonly property bool hasError: root.ocError !== "" || root.agyError !== ""
  readonly property string ocUpdated: (root.ocMonitor && root.ocMonitor.lastRefresh !== "") ? root.ocMonitor.lastRefresh : "never"
  readonly property string agyUpdated: (root.agyMonitor && root.agyMonitor.lastRefresh !== "") ? root.agyMonitor.lastRefresh : "never"

  readonly property string combinedToday: {
    if (root.ocMonitor === null || root.agyMonitor === null) return "--";
    if (root.ocMonitor.lastRefresh === "" && root.agyMonitor.lastRefresh === "") return "--";
    return root.ocMonitor.compact(root.ocMonitor.todayTokens + root.agyMonitor.todayTokens);
  }

  readonly property string subtitleText: {
    if (root.ocMonitor === null || root.agyMonitor === null) return "Not connected";
    return "Today " + root.combinedToday + " · Σ " + root.ocText(root.ocMonitor.todayTokens, root.ocMonitor.lastRefresh) + " + ✦ " + root.agyText(root.agyMonitor.todayTokens, root.agyMonitor.lastRefresh);
  }

  function ocText(tokens: double, stamp: string): string {
    if (root.ocMonitor === null || stamp === "") return "--";
    return root.ocMonitor.compact(tokens);
  }

  function agyText(tokens: double, stamp: string): string {
    if (root.agyMonitor === null || stamp === "") return "--";
    return root.agyMonitor.compact(tokens);
  }

  function money(value: double): string {
    return "$" + value.toFixed(2);
  }

  // ---- Per-source detail rows (same semantics as the old separate cards) ----
  function ocSplitDetails(split: var, cost: double, messages: double): var {
    return [
      { k: "Input", v: root.ocMonitor.compact(split.input) },
      { k: "Output", v: root.ocMonitor.compact(split.output) },
      { k: "Cache read", v: root.ocMonitor.compact(split.cacheRead) },
      { k: "Cache write", v: root.ocMonitor.compact(split.cacheWrite) },
      { k: "Reasoning", v: root.ocMonitor.compact(split.reasoning) },
      { k: "Messages", v: root.ocMonitor.compact(messages) },
      { k: "Cost", v: root.money(cost) }
    ];
  }

  function agySplitDetails(split: var, messages: double): var {
    return [
      { k: "Input", v: root.agyMonitor.compact(split.input) },
      { k: "Output", v: root.agyMonitor.compact(split.output) },
      { k: "Cache read", v: root.agyMonitor.compact(split.cacheRead) },
      { k: "Reasoning", v: root.agyMonitor.compact(split.reasoning) },
      { k: "Messages", v: root.agyMonitor.compact(messages) }
    ];
  }

  readonly property var ocRows: root.ocMonitor === null ? [] : [
    { label: "Today", tokens: root.ocMonitor.compact(root.ocMonitor.todayTokens), details: root.ocSplitDetails(root.ocMonitor.todaySplit, root.ocMonitor.todayCost, root.ocMonitor.todayMessages) },
    { label: "This week", tokens: root.ocMonitor.compact(root.ocMonitor.weekTokens), details: root.ocSplitDetails(root.ocMonitor.weekSplit, root.ocMonitor.weekCost, root.ocMonitor.weekMessages) },
    { label: "This month", tokens: root.ocMonitor.compact(root.ocMonitor.monthTokens), details: root.ocSplitDetails(root.ocMonitor.monthSplit, root.ocMonitor.monthCost, root.ocMonitor.monthMessages) }
  ]

  readonly property var agyRows: root.agyMonitor === null ? [] : [
    { label: "Today", tokens: root.agyMonitor.compact(root.agyMonitor.todayTokens), details: root.agySplitDetails(root.agyMonitor.todaySplit, root.agyMonitor.todayMessages) },
    { label: "This week", tokens: root.agyMonitor.compact(root.agyMonitor.weekTokens), details: root.agySplitDetails(root.agyMonitor.weekSplit, root.agyMonitor.weekMessages) },
    { label: "This month", tokens: root.agyMonitor.compact(root.agyMonitor.monthTokens), details: root.agySplitDetails(root.agyMonitor.monthSplit, root.agyMonitor.monthMessages) }
  ]

  // ---- Overview: combined period cards ----
  function periodTotal(ocTokens: double, agyTokens: double): string {
    if (root.ocMonitor === null || root.agyMonitor === null) return "--";
    return root.ocMonitor.compact(ocTokens + agyTokens);
  }

  readonly property var overviewPeriods: (root.ocMonitor === null || root.agyMonitor === null) ? [] : [
    {
      label: "Today",
      oc: root.ocMonitor.compact(root.ocMonitor.todayTokens),
      ocSub: root.money(root.ocMonitor.todayCost),
      agy: root.agyMonitor.compact(root.agyMonitor.todayTokens),
      agySub: root.agyMonitor.compact(root.agyMonitor.todayMessages) + " msgs",
      total: root.periodTotal(root.ocMonitor.todayTokens, root.agyMonitor.todayTokens)
    },
    {
      label: "This week",
      oc: root.ocMonitor.compact(root.ocMonitor.weekTokens),
      ocSub: root.money(root.ocMonitor.weekCost),
      agy: root.agyMonitor.compact(root.agyMonitor.weekTokens),
      agySub: root.agyMonitor.compact(root.agyMonitor.weekMessages) + " msgs",
      total: root.periodTotal(root.ocMonitor.weekTokens, root.agyMonitor.weekTokens)
    },
    {
      label: "This month",
      oc: root.ocMonitor.compact(root.ocMonitor.monthTokens),
      ocSub: root.money(root.ocMonitor.monthCost),
      agy: root.agyMonitor.compact(root.agyMonitor.monthTokens),
      agySub: root.agyMonitor.compact(root.agyMonitor.monthMessages) + " msgs",
      total: root.periodTotal(root.ocMonitor.monthTokens, root.agyMonitor.monthTokens)
    }
  ]

  // Last-N card: most-recent message rows, not a calendar window. OpenCode
  // counts user+assistant rows (valid JSON); Antigravity counts deduped
  // assistant turns ordered by file mtime then idx (approximate across
  // sessions). Actual rows can be < N when history is short.
  readonly property var lastNCard: (root.ocMonitor === null || root.agyMonitor === null) ? null : ({
    oc: root.ocMonitor.lastNTokens !== undefined ? root.ocMonitor.compact(root.ocMonitor.lastNTokens) : "--",
    ocSub: (root.ocMonitor.lastNCost !== undefined ? root.money(root.ocMonitor.lastNCost) : "--") + " · " + (root.ocMonitor.lastNMessages !== undefined ? root.ocMonitor.compact(root.ocMonitor.lastNMessages) : "?") + " msgs",
    ocDetails: root.ocMonitor.lastNSplit !== undefined ? root.ocSplitDetails(root.ocMonitor.lastNSplit, root.ocMonitor.lastNCost, root.ocMonitor.lastNMessages) : [],
    agy: root.agyMonitor.lastNTokens !== undefined ? root.agyMonitor.compact(root.agyMonitor.lastNTokens) : "--",
    agySub: (root.agyMonitor.lastNMessages !== undefined ? root.agyMonitor.compact(root.agyMonitor.lastNMessages) : "?") + " msgs",
    agyDetails: root.agyMonitor.lastNSplit !== undefined ? root.agySplitDetails(root.agyMonitor.lastNSplit, root.agyMonitor.lastNMessages) : [],
    total: root.periodTotal(
      root.ocMonitor.lastNTokens !== undefined ? root.ocMonitor.lastNTokens : 0,
      root.agyMonitor.lastNTokens !== undefined ? root.agyMonitor.lastNTokens : 0)
  })

  // ---- Models, tagged by source and merged for the Overview tab ----
  readonly property var ocModelRows: root.ocMonitor === null ? [] : root.ocMonitor.monthModels.map(function (m) {
    return { name: m.name, tokens: root.ocMonitor.compact(m.tokens), sub: root.ocMonitor.compact(m.messages) + " msgs", raw: m.tokens, src: "oc" };
  })

  readonly property var agyModelRows: root.agyMonitor === null ? [] : root.agyMonitor.monthModels.map(function (m) {
    return { name: m.name, tokens: root.agyMonitor.compact(m.tokens), sub: root.agyMonitor.compact(m.messages) + " msgs", raw: m.tokens, src: "agy" };
  })

  readonly property var combinedModels: root.ocModelRows.concat(root.agyModelRows).slice().sort(function (a, b) { return b.raw - a.raw; }).slice(0, 12)

  readonly property var agySourceRows: root.agyMonitor === null ? [] : root.agyMonitor.monthSources.map(function (s) {
    return { name: s.name, tokens: root.agyMonitor.compact(s.tokens), sub: root.agyMonitor.compact(s.messages) + " msgs" };
  })

  readonly property var segItems: [
    { icon: "", label: "Overview", count: 0, alert: root.hasError },
    { icon: "Σ", label: "OpenCode", count: root.ocModelRows.length, alert: root.ocError !== "" },
    { icon: "✦", label: "Antigravity", count: root.agyModelRows.length, alert: root.agyError !== "" }
  ]

  readonly property var t: Theme

  // Small "i" affordance shared by both detail tabs; arms the shared tooltip.
  component InfoDot: Item {
    id: inf
    property var details: null
    implicitWidth: 20
    implicitHeight: 20
    Rectangle {
      anchors.fill: parent
      radius: 10
      color: infoMouse.containsMouse ? t.hoverFill : "transparent"
      border.color: infoMouse.containsMouse ? t.accent : t.line
      border.width: 1
      Text {
        anchors.centerIn: parent
        text: "i"
        color: infoMouse.containsMouse ? t.ink1 : t.ink3
        font.pixelSize: 11
        font.family: t.mono
      }
    }
    MouseArea {
      id: infoMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onEntered: {
        root.tipDetails = { label: "", rows: inf.details };
        root.tipTarget = inf;
        tipTimer.restart();
      }
      onExited: root.hideTip()
      onClicked: root.showTip()
    }
  }

  // One period row inside a detail-tab surface card.
  component PeriodRow: Item {
    id: prow
    property string label: ""
    property string tokens: ""
    property var details: []
    property bool first: false
    width: parent ? parent.width : 0
    height: innerCol.height
    Column {
      id: innerCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      Hairline {
        width: parent.width - 24
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !prow.first
      }
      RowLayout {
        width: parent.width
        height: 46
        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 12
          text: prow.label
          color: t.ink2
          font.pixelSize: 13
          font.family: t.mono
          verticalAlignment: Text.AlignVCenter
        }
        InfoDot {
          Layout.alignment: Qt.AlignVCenter
          details: prow.details
        }
        Text {
          Layout.rightMargin: 12
          text: prow.tokens
          color: t.ink1
          font.pixelSize: 14
          font.weight: Font.DemiBold
          font.family: t.mono
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }

  // ================= Card =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: Theme.cardBorder
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 0

      // ---- Header: identity left, refresh right ----
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        spacing: 10

        Text {
          text: "󰚩"
          font.family: t.mono
          font.pixelSize: 19
          color: root.hasError ? t.amber : t.teal
        }

        Column {
          Layout.fillWidth: true
          spacing: 1
          Text {
            text: "AI usage"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: t.ink1
          }
          Text {
            width: parent.width
            text: root.subtitleText
            font.family: t.mono
            font.pixelSize: 11
            color: t.ink3
            elide: Text.ElideRight
          }
        }

        IconBtn {
          glyph: "󰑓"
          fs: 14
          spinning: root.busy
          onClicked: root.triggerRefreshAll()
        }
      }

      Item { Layout.preferredHeight: 14; Layout.fillWidth: true }

      Segments {
        Layout.fillWidth: true
        items: root.segItems
        current: root.currentTab
        onSelected: index => root.currentTab = index
      }

      Item { Layout.preferredHeight: 12; Layout.fillWidth: true }

      StackLayout {
        id: tabStack
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: root.currentTab

        // ============ TAB 0: OVERVIEW ============
        // Content-sized column; outer height hugs overviewCol.height.
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
              label: "Last " + root.lastN + " messages"
            }

            Row {
              width: parent.width
              spacing: 6
              Repeater {
                model: root.lastNOptions
                TextBtn {
                  required property var modelData
                  required property int index
                  text: modelData
                  fg: modelData === root.lastN ? t.ink1 : t.ink3
                  fs: 11
                  bold: modelData === root.lastN
                  onClicked: root.lastN = modelData
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.busy ? "updating…" : ""
                font.pixelSize: 11
                font.family: t.mono
                color: t.ink3
              }
            }

            Rectangle {
              visible: root.lastNCard !== null
              width: parent.width
              height: lastNInner.height + 8
              radius: 12
              color: t.surface

              Column {
                id: lastNInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                RowLayout {
                  width: parent.width
                  height: 38
                  Text {
                    Layout.fillWidth: true
                    text: "Σ  OpenCode"
                    font.pixelSize: 12
                    font.family: t.mono
                    color: t.teal
                  }
                  InfoDot {
                    Layout.alignment: Qt.AlignVCenter
                    details: root.lastNCard ? root.lastNCard.ocDetails : []
                  }
                  ColumnLayout {
                    spacing: 0
                    Text {
                      Layout.alignment: Qt.AlignRight
                      text: root.lastNCard ? root.lastNCard.oc : "--"
                      font.pixelSize: 13
                      font.weight: Font.Medium
                      font.family: t.mono
                      color: t.ink1
                    }
                    Text {
                      Layout.alignment: Qt.AlignRight
                      text: root.lastNCard ? root.lastNCard.ocSub : ""
                      font.pixelSize: 10
                      font.family: t.mono
                      color: t.ink3
                    }
                  }
                }

                Hairline { width: parent.width; anchors.horizontalCenter: parent.horizontalCenter }

                RowLayout {
                  width: parent.width
                  height: 38
                  Text {
                    Layout.fillWidth: true
                    text: "✦  Antigravity"
                    font.pixelSize: 12
                    font.family: t.mono
                    color: t.violet
                  }
                  InfoDot {
                    Layout.alignment: Qt.AlignVCenter
                    details: root.lastNCard ? root.lastNCard.agyDetails : []
                  }
                  ColumnLayout {
                    spacing: 0
                    Text {
                      Layout.alignment: Qt.AlignRight
                      text: root.lastNCard ? root.lastNCard.agy : "--"
                      font.pixelSize: 13
                      font.weight: Font.Medium
                      font.family: t.mono
                      color: t.ink1
                    }
                    Text {
                      Layout.alignment: Qt.AlignRight
                      text: root.lastNCard ? root.lastNCard.agySub : ""
                      font.pixelSize: 10
                      font.family: t.mono
                      color: t.ink3
                    }
                  }
                }

                Hairline { width: parent.width; anchors.horizontalCenter: parent.horizontalCenter }

                RowLayout {
                  width: parent.width
                  height: 34
                  Text {
                    Layout.fillWidth: true
                    text: "Combined"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: t.ink2
                  }
                  Text {
                    text: root.lastNCard ? root.lastNCard.total : "--"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.family: t.mono
                    color: t.ink1
                  }
                }
              }
            }

            Repeater {
              model: root.overviewPeriods
              Column {
                required property var modelData
                required property int index
                width: overviewCol.width
                spacing: 0

                SectionHead {
                  width: parent.width
                  label: modelData.label
                }

                Item { width: 1; height: 6 }

                Rectangle {
                  width: parent.width
                  height: periodInner.height + 8
                  radius: 12
                  color: t.surface

                  Column {
                    id: periodInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    RowLayout {
                      width: parent.width
                      height: 38
                      Text {
                        Layout.fillWidth: true
                        text: "Σ  OpenCode"
                        font.pixelSize: 12
                        font.family: t.mono
                        color: t.teal
                      }
                      ColumnLayout {
                        spacing: 0
                        Text {
                          Layout.alignment: Qt.AlignRight
                          text: modelData.oc
                          font.pixelSize: 13
                          font.weight: Font.Medium
                          font.family: t.mono
                          color: t.ink1
                        }
                        Text {
                          Layout.alignment: Qt.AlignRight
                          text: modelData.ocSub
                          font.pixelSize: 10
                          font.family: t.mono
                          color: t.ink3
                        }
                      }
                    }

                    Hairline { width: parent.width; anchors.horizontalCenter: parent.horizontalCenter }

                    RowLayout {
                      width: parent.width
                      height: 38
                      Text {
                        Layout.fillWidth: true
                        text: "✦  Antigravity"
                        font.pixelSize: 12
                        font.family: t.mono
                        color: t.violet
                      }
                      ColumnLayout {
                        spacing: 0
                        Text {
                          Layout.alignment: Qt.AlignRight
                          text: modelData.agy
                          font.pixelSize: 13
                          font.weight: Font.Medium
                          font.family: t.mono
                          color: t.ink1
                        }
                        Text {
                          Layout.alignment: Qt.AlignRight
                          text: modelData.agySub
                          font.pixelSize: 10
                          font.family: t.mono
                          color: t.ink3
                        }
                      }
                    }

                    Hairline { width: parent.width; anchors.horizontalCenter: parent.horizontalCenter }

                    RowLayout {
                      width: parent.width
                      height: 34
                      Text {
                        Layout.fillWidth: true
                        text: "Combined"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: t.ink2
                      }
                      Text {
                        text: modelData.total
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.family: t.mono
                        color: t.ink1
                      }
                    }
                  }
                }
              }
            }

            SectionHead {
              width: overviewCol.width
              visible: root.combinedModels.length > 0
              label: "Top models · this month"
            }

            Rectangle {
              visible: root.combinedModels.length > 0
              width: overviewCol.width
              height: modelsCol.height + 8
              radius: 12
              color: t.surface

              Column {
                id: modelsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Repeater {
                  model: root.combinedModels
                  Column {
                    required property var modelData
                    required property int index
                    width: modelsCol.width

                    Hairline {
                      visible: index > 0
                      width: parent.width
                      anchors.horizontalCenter: parent.horizontalCenter
                    }

                    RowLayout {
                      width: parent.width
                      height: 44
                      spacing: 8
                      Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: modelData.src === "oc" ? t.teal : t.violet
                      }
                      Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        font.pixelSize: 12
                        font.family: t.mono
                        color: t.ink2
                        elide: Text.ElideMiddle
                      }
                      ColumnLayout {
                        spacing: 0
                        Text {
                          Layout.alignment: Qt.AlignRight
                          text: modelData.tokens
                          font.pixelSize: 12
                          font.family: t.mono
                          color: t.ink1
                        }
                        Text {
                          Layout.alignment: Qt.AlignRight
                          text: modelData.sub
                          font.pixelSize: 10
                          font.family: t.mono
                          color: t.ink3
                        }
                      }
                    }
                  }
                }
              }
            }

            Text {
              width: overviewCol.width
              text: "OpenCode updated " + root.ocUpdated + "  ·  Antigravity updated " + root.agyUpdated
              font.pixelSize: 11
              font.family: t.mono
              color: t.ink3
              wrapMode: Text.Wrap
            }

            Text {
              width: overviewCol.width
              visible: root.ocError !== ""
              text: "OpenCode: " + root.ocError
              font.pixelSize: 11
              font.family: t.mono
              color: t.red
              wrapMode: Text.Wrap
            }

            Text {
              width: overviewCol.width
              visible: root.agyError !== ""
              text: "Antigravity: " + root.agyError
              font.pixelSize: 11
              font.family: t.mono
              color: t.red
              wrapMode: Text.Wrap
            }
          }
        }

        // ============ TAB 1: OPENCODE ============
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 1 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 110 } }

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
                label: "Usage"
              }

              Rectangle {
                width: parent.width
                height: ocPeriods.height
                radius: 12
                color: t.surface

                Column {
                  id: ocPeriods
                  width: parent.width
                  Repeater {
                    model: root.ocRows
                    PeriodRow {
                      required property var modelData
                      required property int index
                      label: modelData.label
                      tokens: modelData.tokens
                      details: modelData.details
                      first: index === 0
                    }
                  }
                }
              }

              SectionHead {
                width: parent.width
                visible: root.ocModelRows.length > 0
                label: "Models · this month"
              }

              Rectangle {
                visible: root.ocModelRows.length > 0
                width: parent.width
                height: ocModelsCol.height + 8
                radius: 12
                color: t.surface

                Column {
                  id: ocModelsCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.topMargin: 4
                  anchors.leftMargin: 12
                  anchors.rightMargin: 12

                  Repeater {
                    model: root.ocModelRows
                    Column {
                      required property var modelData
                      required property int index
                      width: ocModelsCol.width

                      Hairline {
                        visible: index > 0
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                      }

                      RowLayout {
                        width: parent.width
                        height: 46
                        Text {
                          Layout.fillWidth: true
                          text: modelData.name
                          font.pixelSize: 12
                          font.family: t.mono
                          color: t.ink2
                          elide: Text.ElideMiddle
                        }
                        ColumnLayout {
                          spacing: 2
                          Text {
                            Layout.alignment: Qt.AlignRight
                            text: modelData.tokens
                            font.pixelSize: 13
                            font.family: t.mono
                            color: t.ink1
                          }
                          Text {
                            Layout.alignment: Qt.AlignRight
                            text: modelData.sub
                            font.pixelSize: 11
                            font.family: t.mono
                            color: t.ink3
                          }
                        }
                      }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                text: "Updated " + root.ocUpdated
                font.pixelSize: 11
                font.family: t.mono
                color: t.ink3
              }

              Text {
                width: parent.width
                visible: root.ocError !== ""
                text: root.ocError
                font.pixelSize: 11
                font.family: t.mono
                color: t.red
                wrapMode: Text.Wrap
              }
            }
          }
        }

        // ============ TAB 2: ANTIGRAVITY ============
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          opacity: root.currentTab === 2 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 110 } }

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
                label: "Usage"
              }

              Rectangle {
                width: parent.width
                height: agyPeriods.height
                radius: 12
                color: t.surface

                Column {
                  id: agyPeriods
                  width: parent.width
                  Repeater {
                    model: root.agyRows
                    PeriodRow {
                      required property var modelData
                      required property int index
                      label: modelData.label
                      tokens: modelData.tokens
                      details: modelData.details
                      first: index === 0
                    }
                  }
                }
              }

              SectionHead {
                width: parent.width
                visible: root.agySourceRows.length > 0
                label: "Sources · this month"
              }

              Rectangle {
                visible: root.agySourceRows.length > 0
                width: parent.width
                height: agySourcesCol.height + 8
                radius: 12
                color: t.surface

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
                      required property var modelData
                      required property int index
                      width: agySourcesCol.width

                      Hairline {
                        visible: index > 0
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                      }

                      RowLayout {
                        width: parent.width
                        height: 46
                        Text {
                          Layout.fillWidth: true
                          text: modelData.name
                          font.pixelSize: 12
                          font.family: t.mono
                          color: t.ink2
                          elide: Text.ElideMiddle
                        }
                        ColumnLayout {
                          spacing: 2
                          Text {
                            Layout.alignment: Qt.AlignRight
                            text: modelData.tokens
                            font.pixelSize: 13
                            font.family: t.mono
                            color: t.ink1
                          }
                          Text {
                            Layout.alignment: Qt.AlignRight
                            text: modelData.sub
                            font.pixelSize: 11
                            font.family: t.mono
                            color: t.ink3
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
                label: "Models · this month"
              }

              Rectangle {
                visible: root.agyModelRows.length > 0
                width: parent.width
                height: agyModelsCol.height + 8
                radius: 12
                color: t.surface

                Column {
                  id: agyModelsCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.topMargin: 4
                  anchors.leftMargin: 12
                  anchors.rightMargin: 12

                  Repeater {
                    model: root.agyModelRows
                    Column {
                      required property var modelData
                      required property int index
                      width: agyModelsCol.width

                      Hairline {
                        visible: index > 0
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                      }

                      RowLayout {
                        width: parent.width
                        height: 46
                        Text {
                          Layout.fillWidth: true
                          text: modelData.name
                          font.pixelSize: 12
                          font.family: t.mono
                          color: t.ink2
                          elide: Text.ElideMiddle
                        }
                        ColumnLayout {
                          spacing: 2
                          Text {
                            Layout.alignment: Qt.AlignRight
                            text: modelData.tokens
                            font.pixelSize: 13
                            font.family: t.mono
                            color: t.ink1
                          }
                          Text {
                            Layout.alignment: Qt.AlignRight
                            text: modelData.sub
                            font.pixelSize: 11
                            font.family: t.mono
                            color: t.ink3
                          }
                        }
                      }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                text: "Updated " + root.agyUpdated
                font.pixelSize: 11
                font.family: t.mono
                color: t.ink3
              }

              Text {
                width: parent.width
                visible: root.agyError !== ""
                text: root.agyError
                font.pixelSize: 11
                font.family: t.mono
                color: t.red
                wrapMode: Text.Wrap
              }
            }
          }
        }
      }
    }

    // ---- Shared hover tooltip (same pattern as the old separate cards) ----
    PopupWindow {
      id: tip
      anchor.window: root.barWindow
      anchor.rect.x: root.barWindow ? Math.max(8, Math.min(root.tipX - tipBox.width / 2, root.barWindow.width - tipBox.width - 12)) : 0
      anchor.rect.y: root.tipY
      visible: false
      implicitWidth: tipBox.width
      implicitHeight: tipBox.height
      color: "transparent"

      Rectangle {
        id: tipBox
        implicitWidth: Math.max(50, tipCol.implicitWidth + 16)
        implicitHeight: tipCol.implicitHeight + 10
        radius: t.radiusSm
        color: t.surfaceElevated
        border.color: t.line
        border.width: 1

        Column {
          id: tipCol
          anchors.centerIn: parent
          spacing: 3

          Repeater {
            model: root.tipDetails ? root.tipDetails.rows : []

            delegate: Row {
              id: tipDelegate
              required property var modelData
              required property int index
              spacing: 12

              Text {
                width: 78
                text: tipDelegate.modelData.k
                color: t.ink3
                font.pixelSize: 11
                font.family: t.mono
              }

              Text {
                text: tipDelegate.modelData.v
                color: t.ink1
                font.pixelSize: 11
                font.family: t.mono
              }
            }
          }
        }
      }
    }
  }
}
