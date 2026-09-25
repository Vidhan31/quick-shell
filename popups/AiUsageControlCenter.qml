pragma ComponentBehavior: Bound
// AiUsageControlCenter.qml — Combined OpenCode + Antigravity usage.
// Tailscale visual system: same tokens, Segments, RowBase, SectionHead,
// IconBtn, Hairline. All tabs use a fixed 620 height and scroll internally,
// so switching tabs never resizes the mapped Wayland popup surface.
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

  onSelectedMonthsChanged: root.syncRange()
  onOcMonitorChanged: root.syncRange()
  onAgyMonitorChanged: root.syncRange()
  Component.onCompleted: root.syncRange()

  implicitWidth: 440
  implicitHeight: 620

  // ---- Derived state ----
  readonly property bool busy: (root.ocMonitor ? root.ocMonitor.busy : false) || (root.agyMonitor ? root.agyMonitor.busy : false)
  readonly property string ocError: root.ocMonitor ? root.ocMonitor.error : ""
  readonly property string agyError: root.agyMonitor ? root.agyMonitor.error : ""
  readonly property bool hasError: root.ocError !== "" || root.agyError !== ""
  readonly property string ocUpdated: (root.ocMonitor && root.ocMonitor.lastRefresh !== "") ? root.ocMonitor.lastRefresh : "never"
  readonly property string agyUpdated: (root.agyMonitor && root.agyMonitor.lastRefresh !== "") ? root.agyMonitor.lastRefresh : "never"

  function money(value: double): string {

    return "$" + value.toFixed(2);
  }



  // ---- Models, tagged by source and merged for the Overview tab ----
  readonly property var ocModelRows: root.ocMonitor === null ? [] : root.ocMonitor.monthModels.map(function (m) {
    return {
      name: m.name,
      tokens: root.ocMonitor.compact(m.tokens),
      raw: m.tokens,
      src: "oc"
    };
  })

  readonly property var agyModelRows: root.agyMonitor === null ? [] : root.agyMonitor.monthModels.map(function (m) {
    return {
      name: m.name,
      tokens: root.agyMonitor.compact(m.tokens),
      raw: m.tokens,
      src: "agy"
    };
  })


  readonly property var combinedModels: root.ocModelRows.concat(root.agyModelRows).slice().sort(function (a, b) { return b.raw - a.raw; }).slice(0, 12)

  readonly property var agySourceRows: root.agyMonitor === null ? [] : root.agyMonitor.monthSources.map(function (s) {
    return { name: s.name, tokens: root.agyMonitor.compact(s.tokens), raw: s.tokens };
  })
  readonly property double maxAgySourceTokens: (root.agySourceRows.length > 0 && root.agySourceRows[0].raw > 0) ? root.agySourceRows[0].raw : 1


  // ---- Chart data and period selection ----
  property int overviewChartPeriod: 0 // 0: Today, 1: Week, 2: Month
  property int ocChartPeriod: 0 // 0: Today, 1: Week, 2: Month
  property int agyChartPeriod: 0 // 0: Today, 1: Week, 2: Month

  readonly property var overviewChartData: {
    if (root.ocMonitor === null || root.agyMonitor === null) {
      return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, totalText: "--", totalSub: "tokens", ocTokens: 0, agyTokens: 0 };
    }
    const ocS = root.overviewChartPeriod === 0 ? root.ocMonitor.todaySplit
              : (root.overviewChartPeriod === 1 ? root.ocMonitor.weekSplit : root.ocMonitor.monthSplit);
    const agyS = root.overviewChartPeriod === 0 ? root.agyMonitor.todaySplit
               : (root.overviewChartPeriod === 1 ? root.agyMonitor.weekSplit : root.agyMonitor.monthSplit);

    const ocT = root.overviewChartPeriod === 0 ? root.ocMonitor.todayTokens
              : (root.overviewChartPeriod === 1 ? root.ocMonitor.weekTokens : root.ocMonitor.monthTokens);
    const agyT = root.overviewChartPeriod === 0 ? root.agyMonitor.todayTokens
               : (root.overviewChartPeriod === 1 ? root.agyMonitor.weekTokens : root.agyMonitor.monthTokens);

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
      totalSub: root.overviewChartPeriod === 0 ? "today" : (root.overviewChartPeriod === 1 ? "this week" : "this month"),
      ocTokens: ocT,
      agyTokens: agyT
    };
  }

  readonly property var ocChartData: {
    if (root.ocMonitor === null) {
      return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, totalText: "--", totalSub: "tokens" };
    }
    const s = root.ocChartPeriod === 0 ? root.ocMonitor.todaySplit
            : (root.ocChartPeriod === 1 ? root.ocMonitor.weekSplit : root.ocMonitor.monthSplit);
    const t = root.ocChartPeriod === 0 ? root.ocMonitor.todayTokens
            : (root.ocChartPeriod === 1 ? root.ocMonitor.weekTokens : root.ocMonitor.monthTokens);
    return {
      input: s ? (s.input || 0) : 0,
      output: s ? (s.output || 0) : 0,
      cacheRead: s ? (s.cacheRead || 0) : 0,
      cacheWrite: s ? (s.cacheWrite || 0) : 0,
      reasoning: s ? (s.reasoning || 0) : 0,
      totalText: root.ocMonitor.compact(t),
      totalSub: root.ocChartPeriod === 0 ? "today" : (root.ocChartPeriod === 1 ? "this week" : "this month")
    };
  }

  readonly property var agyChartData: {
    if (root.agyMonitor === null) {
      return { input: 0, output: 0, cacheRead: 0, reasoning: 0, totalText: "--", totalSub: "tokens" };
    }
    const s = root.agyChartPeriod === 0 ? root.agyMonitor.todaySplit
            : (root.agyChartPeriod === 1 ? root.agyMonitor.weekSplit : root.agyMonitor.monthSplit);
    const t = root.agyChartPeriod === 0 ? root.agyMonitor.todayTokens
            : (root.agyChartPeriod === 1 ? root.agyMonitor.weekTokens : root.agyMonitor.monthTokens);
    return {
      input: s ? (s.input || 0) : 0,
      output: s ? (s.output || 0) : 0,
      cacheRead: s ? (s.cacheRead || 0) : 0,
      reasoning: s ? (s.reasoning || 0) : 0,
      totalText: root.agyMonitor.compact(t),
      totalSub: root.agyChartPeriod === 0 ? "today" : (root.agyChartPeriod === 1 ? "this week" : "this month")
    };
  }

  readonly property double maxCombinedModelTokens: (root.combinedModels.length > 0 && root.combinedModels[0].raw > 0) ? root.combinedModels[0].raw : 1
  readonly property double maxOcModelTokens: (root.ocModelRows.length > 0 && root.ocModelRows[0].raw > 0) ? root.ocModelRows[0].raw : 1
  readonly property double maxAgyModelTokens: (root.agyModelRows.length > 0 && root.agyModelRows[0].raw > 0) ? root.agyModelRows[0].raw : 1

  readonly property var segItems: [
    { icon: "", label: "Overview", count: 0, alert: root.hasError },
    { iconSource: Qt.resolvedUrl("../assets/opencode.svg"), label: "OpenCode", count: root.ocModelRows.length, alert: root.ocError !== "" },
    { iconSource: Qt.resolvedUrl("../assets/gemini.svg"), label: "Antigravity", count: root.agyModelRows.length, alert: root.agyError !== "" }
  ]

  readonly property var t: Theme





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

      // ---- Navigation & Actions ----
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
          onClicked: root.triggerRefreshAll()
        }
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
              label: "Token distribution"
            }

            TokenDonutCard {
              width: parent.width
              title: "Composition"
               periods: ["Today", "Week", "Month"]

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
                      Column {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                          width: parent.width
                          text: modelData.name
                          font.pixelSize: 12
                          font.family: t.mono
                          color: t.ink2
                          elide: Text.ElideMiddle
                        }
                        Rectangle {
                          width: parent.width
                          height: 3
                          radius: 1.5
                          color: t.cardBorder
                          Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: Math.max(3, Math.round(parent.width * Math.min(1.0, modelData.raw / root.maxCombinedModelTokens)))
                            color: modelData.src === "oc" ? t.teal : t.violet
                          }
                        }
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
                label: "Token composition"
              }

              TokenDonutCard {
                width: parent.width
                title: "OpenCode breakdown"
                periods: ["Today", "Week", "Month"]
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
                        Column {
                          Layout.fillWidth: true
                          spacing: 3
                          Text {
                            width: parent.width
                            text: modelData.name
                            font.pixelSize: 12
                            font.family: t.mono
                            color: t.ink2
                            elide: Text.ElideMiddle
                          }
                          Rectangle {
                            width: parent.width
                            height: 3
                            radius: 1.5
                            color: t.cardBorder
                            Rectangle {
                              height: parent.height
                              radius: parent.radius
                              width: Math.max(3, Math.round(parent.width * Math.min(1.0, modelData.raw / root.maxOcModelTokens)))
                              color: t.teal
                            }
                          }
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
                label: "Token composition"
              }

              TokenDonutCard {
                width: parent.width
                title: "Antigravity breakdown"
                periods: ["Today", "Week", "Month"]
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
                        Column {
                          Layout.fillWidth: true
                          spacing: 3
                          Text {
                            width: parent.width
                            text: modelData.name
                            font.pixelSize: 12
                            font.family: t.mono
                            color: t.ink2
                            elide: Text.ElideMiddle
                          }
                          Rectangle {
                            width: parent.width
                            height: 3
                            radius: 1.5
                            color: t.cardBorder
                            Rectangle {
                              height: parent.height
                              radius: parent.radius
                              width: Math.max(3, Math.round(parent.width * Math.min(1.0, (modelData.raw !== undefined ? modelData.raw : 1) / root.maxAgySourceTokens)))
                              color: t.violet
                            }
                          }
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
                        Column {
                          Layout.fillWidth: true
                          spacing: 3
                          Text {
                            width: parent.width
                            text: modelData.name
                            font.pixelSize: 12
                            font.family: t.mono
                            color: t.ink2
                            elide: Text.ElideMiddle
                          }
                          Rectangle {
                            width: parent.width
                            height: 3
                            radius: 1.5
                            color: t.cardBorder
                            Rectangle {
                              height: parent.height
                              radius: parent.radius
                              width: Math.max(3, Math.round(parent.width * Math.min(1.0, modelData.raw / root.maxAgyModelTokens)))
                              color: t.violet
                            }
                          }
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
  }
}
