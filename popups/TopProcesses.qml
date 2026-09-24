import QtQuick
import Quickshell
import Quickshell.Plugins.TopProcesses
import "../theme"
import "../components"

Item {
  id: root

  property int interval: 2000
  property int candidateCount: 24
  property var processes: monitor.processes
  property double maxMem: monitor.maxMem
  property string updatedAt: monitor.updatedAt

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  implicitWidth: 412
  implicitHeight: 442

  function formatRss(kb: double): string {
    if (!isFinite(kb) || kb <= 0)
      return "0K";
    if (kb < 1024)
      return Math.round(kb) + "K";
    if (kb < 1024 * 1024)
      return (kb / 1024).toFixed(1) + "M";
    return (kb / 1024 / 1024).toFixed(2) + "G";
  }

  ProcessMonitor {
    id: monitor
    interval: root.interval
    candidateCount: root.candidateCount
    running: root.visible
  }

  Rectangle {
    id: card
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: Theme.cardBorder
    border.width: 1

    Column {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 6

      // Rows — dynamic diffed delegates via ScriptModel
      Repeater {
        model: ScriptModel {
          values: root.processes || []
          objectProp: "mpid"
          comparisonMode: ObjectComparison.Identity
        }
        delegate: Item {
          id: rowDelegate
          required property int index
          required property var modelData

          visible: rowDelegate.modelData !== null
          width: parent.width
          height: 36

          // Left: grouped name + count on top, main pid below
          Item {
            id: leftCell
            anchors {
              left: parent.left
              top: parent.top
              bottom: parent.bottom
            }
            width: 150
            Text {
              anchors {
                left: parent.left
                right: parent.right
                top: parent.top
              }
              text: rowDelegate.modelData ? (rowDelegate.modelData.name + (rowDelegate.modelData.count > 1 ? " ×" + rowDelegate.modelData.count : "")) : ""
              elide: Text.ElideRight
              maximumLineCount: 1
              color: rowDelegate.index === 0 ? Theme.err : Theme.ink1
              font.family: root.monoFont
              font.pixelSize: Theme.fontBase
            }
            Text {
              anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
              }
              text: rowDelegate.modelData ? rowDelegate.modelData.mpid : ""
              elide: Text.ElideRight
              maximumLineCount: 1
              color: Theme.ink3
              font.family: root.monoFont
              font.pixelSize: Theme.fontXs
            }
          }

          // Proportional MEM bar with combined RSS + MEM% label
          Item {
            anchors {
              left: leftCell.right
              right: parent.right
              verticalCenter: parent.verticalCenter
              leftMargin: 8
            }
            height: 18
            readonly property string barLabel: (rowDelegate.modelData && rowDelegate.modelData.barLabel)
              ? rowDelegate.modelData.barLabel
              : (rowDelegate.modelData ? (root.formatRss(rowDelegate.modelData.rss) + " (" + (rowDelegate.modelData.mem ? rowDelegate.modelData.mem.toFixed(0) : "0") + "%)") : "")
            readonly property double fillFrac: (rowDelegate.modelData && root.maxMem > 0) ? Math.min(1, rowDelegate.modelData.mem / root.maxMem) : 0

            Rectangle {
              anchors.fill: parent
              radius: Theme.radiusXs
              color: Theme.inset
            }
            Rectangle {
              height: parent.height
              radius: Theme.radiusXs
              width: parent.width * parent.fillFrac
              color: rowDelegate.index === 0 ? Theme.err : Theme.accent
              opacity: 0.85
            }
            // Dark label on the fill (only when it fits), else light label
            // pinned to the empty track area — always exactly one is visible.
            Text {
              anchors.left: parent.left
              anchors.leftMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              text: parent.barLabel
              color: Theme.darkInk
              font.family: root.monoFont
              font.pixelSize: Theme.fontSm
              font.bold: true
              visible: (parent.width * parent.fillFrac) > 92
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: parent.barLabel
              color: Theme.ink2
              font.family: root.monoFont
              font.pixelSize: Theme.fontSm
              visible: (parent.width * parent.fillFrac) <= 92
            }
          }
        }
      }

      // Empty state (first poll)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: root.processes.length === 0
        text: "󰑓 loading…"
        color: Theme.ink3
        font.family: root.monoFont
        font.pixelSize: Theme.fontBase
      }
    }
  }
}
