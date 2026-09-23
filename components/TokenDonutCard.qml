pragma ComponentBehavior: Bound
// components/TokenDonutCard.qml — GPU-accelerated token breakdown card using KDE QuickCharts.
import QtQuick
import QtQuick.Layouts
import org.kde.quickcharts as Charts
import "../theme"

Rectangle {
  id: root

  property string title: "Token composition"
  property var periods: []
  property int selectedPeriod: 0
  signal periodSelected(int index)

  property double inputTokens: 0
  property double outputTokens: 0
  property double cacheReadTokens: 0
  property double cacheWriteTokens: 0
  property double reasoningTokens: 0
  property bool showCacheWrite: false

  property string totalFormatted: "--"
  property string totalSubtitle: "tokens"
  property var compactFn: function(v) {
    if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
    if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
    if (v >= 1e3) return (v / 1e3).toFixed(1) + "k";
    return Math.round(v).toString();
  }

  // Optional Provider comparison bar
  property bool showProviderBar: false
  property double ocTokens: 0
  property double agyTokens: 0

  readonly property color cInput: Theme.accent
  readonly property color cOutput: Theme.green
  readonly property color cCache: Theme.violet
  readonly property color cCacheWrite: Theme.teal
  readonly property color cReasoning: Theme.amber

  readonly property double totalSum: root.inputTokens + root.outputTokens + root.cacheReadTokens + (root.showCacheWrite ? root.cacheWriteTokens : 0) + root.reasoningTokens

  function pct(val: double): string {
    if (root.totalSum <= 0) return "0%";
    return Math.round((val / root.totalSum) * 100) + "%";
  }

  // KDE QuickCharts values & colors:
  // If sum is 0, render a single neutral slice so the ring displays as a subtle track
  readonly property var chartValues: root.totalSum > 0 ?
    (root.showCacheWrite ? [root.inputTokens, root.outputTokens, root.cacheReadTokens, root.cacheWriteTokens, root.reasoningTokens]
                         : [root.inputTokens, root.outputTokens, root.cacheReadTokens, root.reasoningTokens])
    : [1]

  readonly property var chartColors: root.totalSum > 0 ?
    (root.showCacheWrite ? [root.cInput, root.cOutput, root.cCache, root.cCacheWrite, root.cReasoning]
                         : [root.cInput, root.cOutput, root.cCache, root.cReasoning])
    : [Theme.cardBorder]

  // Cache efficiency metric
  readonly property double promptTotal: root.inputTokens + root.cacheReadTokens
  readonly property double cacheHitRate: root.promptTotal > 0 ? (root.cacheReadTokens / root.promptTotal) : 0
  readonly property string cacheHitPctText: Math.round(root.cacheHitRate * 100) + "%"

  // Provider bar ratios
  readonly property double providerSum: root.ocTokens + root.agyTokens
  readonly property double ocRatio: root.providerSum > 0 ? (root.ocTokens / root.providerSum) : 0.5
  readonly property double agyRatio: root.providerSum > 0 ? (root.agyTokens / root.providerSum) : 0.5
  readonly property string ocPctText: root.providerSum > 0 ? Math.round(root.ocRatio * 100) + "%" : "--"
  readonly property string agyPctText: root.providerSum > 0 ? Math.round(root.agyRatio * 100) + "%" : "--"

  radius: 12
  color: Theme.surface
  border.color: Theme.cardBorder
  border.width: 1

  implicitHeight: contentCol.height + 24
  height: implicitHeight

  Column {
    id: contentCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 12
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    spacing: 12

    // Header: title left, cache badge, period switcher right
    RowLayout {
      width: parent.width
      height: 22
      spacing: 8

      Text {
        text: root.title
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Theme.ink2
      }

      // Cache hit efficiency badge
      Rectangle {
        visible: root.cacheReadTokens > 0
        radius: 4
        color: Qt.rgba(Theme.violet.r, Theme.violet.g, Theme.violet.b, 0.12)
        border.color: Qt.rgba(Theme.violet.r, Theme.violet.g, Theme.violet.b, 0.28)
        border.width: 1
        implicitWidth: cacheRow.width + 10
        implicitHeight: 18

        Row {
          id: cacheRow
          anchors.centerIn: parent
          spacing: 3
          Text {
            text: "󱐋"
            font.pixelSize: 9
            font.family: Theme.mono
            color: Theme.violet
          }
          Text {
            text: root.cacheHitPctText + " cached"
            font.pixelSize: 10
            font.weight: Font.Medium
            font.family: Theme.mono
            color: Theme.violet
          }
        }
      }

      Item { Layout.fillWidth: true }


      Row {
        spacing: 4
        visible: root.periods.length > 0
        Repeater {
          model: root.periods
          TextBtn {
            id: pbtn
            required property var modelData
            required property int index
            text: pbtn.modelData
            fg: pbtn.index === root.selectedPeriod ? Theme.ink1 : Theme.ink3
            fs: 11
            bold: pbtn.index === root.selectedPeriod
            onClicked: {
              root.selectedPeriod = pbtn.index;
              root.periodSelected(pbtn.index);
            }
          }
        }
      }
    }

    // Body: Donut chart left, legend right
    RowLayout {
      width: parent.width
      spacing: 14

      // Donut Chart container
      Item {
        Layout.preferredWidth: 104
        Layout.preferredHeight: 104
        Layout.alignment: Qt.AlignVCenter

        Charts.PieChart {
          id: pie
          anchors.fill: parent
          filled: false
          thickness: 10
          spacing: root.totalSum > 0 ? 2 : 0
          backgroundColor: "transparent"

          valueSources: [
            Charts.ArraySource {
              array: root.chartValues
            }
          ]
          colorSource: Charts.ArraySource {
            array: root.chartColors
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: 1
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.totalFormatted
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: Theme.mono
            color: Theme.ink1
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.totalSubtitle
            font.pixelSize: 9
            font.family: Theme.mono
            color: Theme.ink3
          }
        }
      }

      // Legend breakdown
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        component LegendItem: RowLayout {
          id: li
          property color dotColor: Theme.accent
          property string labelText: ""
          property double valueTokens: 0
          Layout.fillWidth: true
          spacing: 6

          Rectangle {
            Layout.preferredWidth: 7
            Layout.preferredHeight: 7
            Layout.alignment: Qt.AlignVCenter
            radius: 3.5
            color: li.dotColor
          }

          Text {
            Layout.fillWidth: true
            text: li.labelText
            font.pixelSize: 11
            color: Theme.ink2
            elide: Text.ElideRight
          }

          Text {
            text: root.compactFn(li.valueTokens)
            font.pixelSize: 11
            font.family: Theme.mono
            font.weight: Font.Medium
            color: Theme.ink1
          }

          Text {
            Layout.preferredWidth: 32
            horizontalAlignment: Text.AlignRight
            text: root.pct(li.valueTokens)
            font.pixelSize: 10
            font.family: Theme.mono
            color: Theme.ink3
          }
        }

        LegendItem {
          dotColor: root.cInput
          labelText: "Input"
          valueTokens: root.inputTokens
        }
        LegendItem {
          dotColor: root.cOutput
          labelText: "Output"
          valueTokens: root.outputTokens
        }
        LegendItem {
          dotColor: root.cCache
          labelText: "Cache read"
          valueTokens: root.cacheReadTokens
        }
        LegendItem {
          visible: root.showCacheWrite && root.cacheWriteTokens > 0
          dotColor: root.cCacheWrite
          labelText: "Cache write"
          valueTokens: root.cacheWriteTokens
        }
        LegendItem {
          visible: root.reasoningTokens > 0
          dotColor: root.cReasoning
          labelText: "Reasoning"
          valueTokens: root.reasoningTokens
        }
      }
    }

    // Optional: Provider balance bar
    ColumnLayout {
      width: parent.width
      spacing: 5
      visible: root.showProviderBar

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
      }

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "Σ  OpenCode " + root.ocPctText
          font.pixelSize: 11
          font.family: Theme.mono
          color: Theme.teal
        }
        Item { Layout.fillWidth: true }
        Text {
          text: root.agyPctText + "  ✦ Antigravity"
          font.pixelSize: 11
          font.family: Theme.mono
          color: Theme.violet
        }
      }

      // Proportional bar
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 6

        Rectangle {
          anchors.fill: parent
          radius: 3
          color: Theme.cardBorder
          visible: root.providerSum <= 0
        }

        Row {
          anchors.fill: parent
          spacing: 2
          visible: root.providerSum > 0

          Rectangle {
            width: Math.max(3, Math.round((parent.width - 2) * root.ocRatio))
            height: parent.height
            radius: 3
            color: Theme.teal
          }
          Rectangle {
            width: Math.max(3, (parent.width - 2) - Math.max(3, Math.round((parent.width - 2) * root.ocRatio)))
            height: parent.height
            radius: 3
            color: Theme.violet
          }
        }
      }
    }
  }
}
