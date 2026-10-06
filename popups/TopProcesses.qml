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

  implicitWidth: 430
  readonly property int preferredHeight: Math.max(120, contentCol.height + (card.padding * 2))
  property int popupHeight: 404

  function syncHeight(): void {
    if (contentCol.height > 0)
      popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (contentCol.height > 0)
      popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

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
      id: contentCol
      width: parent.width
      spacing: 4

      Item {
        id: headerRow
        width: parent.width
        height: 22

        Text {
          id: colPidHeader
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          width: 52
          text: "PID"
          color: Theme.ink3
          font.family: root.monoFont
          font.pixelSize: Theme.fontXs
          font.weight: Font.DemiBold
        }

        Text {
          id: colNameHeader
          anchors.left: colPidHeader.right
          anchors.leftMargin: 8
          anchors.right: colMemHeader.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: "Name"
          color: Theme.ink3
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          id: colMemHeader
          anchors.right: colKillHeader.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: 105
          horizontalAlignment: Text.AlignRight
          text: "Memory Usage"
          color: Theme.ink3
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          font.weight: Font.DemiBold
        }

        Text {
          id: colKillHeader
          anchors.right: parent.right
          anchors.rightMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          width: 32
          horizontalAlignment: Text.AlignHCenter
          text: "Kill"
          color: Theme.ink3
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          font.weight: Font.DemiBold
        }
      }

      Hairline {
        width: parent.width
      }

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
          height: 32
          radius: Theme.radiusSm
          color: (rowMouse.containsMouse || rowDelegate.activeFocus) ? Theme.hoverFill : "transparent"
          border.width: rowDelegate.activeFocus ? Theme.focusRingWidth : 0
          border.color: Theme.focusRing
          activeFocusOnTab: true

          readonly property string procName: rowDelegate.modelData ? rowDelegate.modelData.name : ""
          readonly property string procPid: rowDelegate.modelData ? String(rowDelegate.modelData.mpid || rowDelegate.modelData.pid || "") : ""
          readonly property int procRootPid: rowDelegate.modelData ? (rowDelegate.modelData.rootPid || rowDelegate.modelData.mpid || 0) : 0
          readonly property string procRss: rowDelegate.modelData ? root.formatRss(rowDelegate.modelData.rss) : "0K"
          readonly property string procMemPct: rowDelegate.modelData ? (rowDelegate.modelData.mem ? rowDelegate.modelData.mem.toFixed(1) : "0") + "%" : "0%"
          readonly property string procMemText: procRss + " (" + procMemPct + ")"
          readonly property string tipTitle: rowDelegate.modelData ? (rowDelegate.modelData.name + (rowDelegate.modelData.count > 1 ? (" (" + rowDelegate.modelData.count + " processes)") : "")) : ""
          readonly property string tipSub: ""

          Accessible.role: Accessible.ListItem
          Accessible.name: tipTitle

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

          Text {
            id: cellPid
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            text: rowDelegate.procPid
            color: Theme.ink3
            font.family: root.monoFont
            font.pixelSize: Theme.fontXs
            elide: Text.ElideRight
          }

          Text {
            id: cellName
            anchors.left: cellPid.right
            anchors.leftMargin: 8
            anchors.right: cellMem.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: rowDelegate.procName
            color: rowDelegate.index === 0 ? Theme.err : Theme.ink1
            font.family: Theme.textFont
            font.pixelSize: Theme.fontBase
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            id: cellMem
            anchors.right: cellKill.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 105
            horizontalAlignment: Text.AlignRight
            text: rowDelegate.procMemText
            color: Theme.ink2
            font.family: root.monoFont
            font.pixelSize: Theme.fontSm
          }

          Item {
            id: cellKill
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: parent.height

            IconBtn {
              anchors.centerIn: parent
              btnSize: 22
              fs: Theme.iconXs
              glyph: "󰅖"
              fg: Theme.ink3
              tooltip: "Kill " + (rowDelegate.modelData ? rowDelegate.modelData.name : "")
              tooltipSub: "Topmost parent PID: " + rowDelegate.procRootPid
              onClicked: {
                if (root.monitor && rowDelegate.procRootPid > 1) {
                  root.monitor.kill(rowDelegate.procRootPid);
                }
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        height: 356
        visible: root.processes.length === 0

        Text {
          anchors.centerIn: parent
          text: "󰑓 loading…"
          color: Theme.ink3
          font.family: root.monoFont
          font.pixelSize: Theme.fontBase
        }
      }
    }
  }

  Component.onCompleted: {
    if (root.monitor && root.processes.length === 0) {
      root.monitor.sampleSync();
    }
  }
}
