pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Plugins.TopProcesses
import "../theme"
import "../components"

Item {
  id: root

  property ProcessMonitor monitor: null
  property alias processMonitor: root.monitor
  property var processes: monitor ? monitor.processes : []
  property double maxMem: monitor ? monitor.maxMem : 1.0
  property string updatedAt: monitor ? monitor.updatedAt : ""

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

  PopupCard {
    id: card
    anchors.fill: parent
    padding: Theme.cardPaddingSm

    Column {
      anchors.fill: parent
      spacing: 6

      Repeater {
        model: ScriptModel {
          values: root.processes || []
          objectProp: "mpid"
          comparisonMode: ObjectComparison.Identity
        }
        delegate: Rectangle {
          id: rowDelegate
          required property int index
          required property var modelData

          visible: rowDelegate.modelData !== null
          width: parent.width
          height: 36
          radius: Theme.radiusSm
          color: (rowMouse.containsMouse || rowDelegate.activeFocus) ? Theme.hoverFill : "transparent"
          border.width: rowDelegate.activeFocus ? Theme.focusRingWidth : 0
          border.color: Theme.focusRing
          activeFocusOnTab: true

          readonly property string procName: rowDelegate.modelData ? (rowDelegate.modelData.name + (rowDelegate.modelData.count > 1 ? " ×" + rowDelegate.modelData.count : "")) : ""
          readonly property string procPid: rowDelegate.modelData ? rowDelegate.modelData.mpid : ""
          readonly property string procRss: rowDelegate.modelData ? root.formatRss(rowDelegate.modelData.rss) : "0K"
          readonly property string procMemPct: rowDelegate.modelData ? (rowDelegate.modelData.mem ? rowDelegate.modelData.mem.toFixed(1) : "0") + "%" : "0%"
          readonly property string tipTitle: rowDelegate.modelData ? (rowDelegate.modelData.name + (rowDelegate.modelData.count > 1 ? (" (" + rowDelegate.modelData.count + " processes)") : "")) : ""
          readonly property string tipSub: "PID: " + procPid + " · RSS: " + procRss + " (" + procMemPct + " RAM)"

          Accessible.role: Accessible.ListItem
          Accessible.name: tipTitle + ", " + tipSub

          Behavior on color { ColorAnimation { duration: Theme.durationFast } }
          Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

          function findHost(): var {
            let p = rowDelegate.parent;
            while (p) {
              if (typeof p.showTip === "function") return p;
              p = p.parent;
            }
            return null;
          }

          function updateTip(): void {
            const host = rowDelegate.findHost();
            if ((rowMouse.containsMouse || rowDelegate.activeFocus) && rowDelegate.modelData) {
              if (host && typeof host.showTip === "function") {
                host.showTip(rowDelegate, tipTitle, tipSub);
              }
            } else {
              if (host && typeof host.hideTip === "function") {
                host.hideTip();
              }
            }
          }

          onActiveFocusChanged: updateTip()
          Component.onDestruction: {
            const host = rowDelegate.findHost();
            if (host && typeof host.hideTip === "function") {
              host.hideTip();
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: rowDelegate.updateTip()
          }

          Item {
            id: leftCell
            anchors {
              left: parent.left
              leftMargin: 6
              top: parent.top
              bottom: parent.bottom
              topMargin: 2
              bottomMargin: 2
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
              font.family: Theme.textFont
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

          Item {
            anchors {
              left: leftCell.right
              right: parent.right
              rightMargin: 6
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
