// TopProcesses.qml — top 10 processes by memory with proportional MEM bar + CPU.
// Native C++ Qt6 QML module (Quickshell.Plugins.TopProcesses).
import QtQuick
import Quickshell.Plugins.TopProcesses

Item {
  id: root

  property int interval: 2000
  property int candidateCount: 24
  property var processes: monitor.processes
  property double maxMem: monitor.maxMem
  property string updatedAt: monitor.updatedAt

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

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
    radius: 16
    color: "#1e1e2e"
    border.color: "#313244"
    border.width: 1

    Column {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 6

      // Rows — fixed 10 delegates to avoid destroying and recreating 90 scene graph items every tick
      Repeater {
        model: 10
        delegate: Item {
          id: rowDelegate
          required property int index
          readonly property var modelData: (root.processes && rowDelegate.index < root.processes.length) ? root.processes[rowDelegate.index] : null

          visible: rowDelegate.modelData !== null
          width: parent.width
          height: visible ? 36 : 0

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
              color: rowDelegate.index === 0 ? "#f38ba8" : "#cdd6f4"
              font.family: root.monoFont
              font.pixelSize: 12
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
              color: "#6c7086"
              font.family: root.monoFont
              font.pixelSize: 10
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
              radius: 4
              color: "#313244"
            }
            Rectangle {
              height: parent.height
              radius: 4
              width: parent.width * parent.fillFrac
              color: rowDelegate.index === 0 ? "#f38ba8" : "#89b4fa"
              opacity: 0.85
            }
            // Dark label on the fill (only when it fits), else light label
            // pinned to the empty track area — always exactly one is visible.
            Text {
              anchors.left: parent.left
              anchors.leftMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              text: parent.barLabel
              color: "#11111b"
              font.family: root.monoFont
              font.pixelSize: 11
              font.bold: true
              visible: (parent.width * parent.fillFrac) > 92
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: parent.barLabel
              color: "#a6adc8"
              font.family: root.monoFont
              font.pixelSize: 11
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
        color: "#6c7086"
        font.family: root.monoFont
        font.pixelSize: 12
      }
    }
  }
}
