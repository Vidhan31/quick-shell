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
  property var popupWindow: null
  property var processes: monitor ? monitor.processes : []
  property double maxMem: monitor ? monitor.maxMem : 1.0
  property string updatedAt: monitor ? monitor.updatedAt : ""

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  implicitWidth: Theme.popupWidthMd
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
          id: colNameHeader
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.right: colPrivHeader.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: "Name"
          color: Theme.ink3
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          id: colPrivHeader
          anchors.right: colRssHeader.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 70
          horizontalAlignment: Text.AlignRight
          text: "Private"
          color: Theme.ink3
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          font.weight: Font.DemiBold
        }

        Text {
          id: colRssHeader
          anchors.right: pinButton.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          width: 70
          horizontalAlignment: Text.AlignRight
          text: "RSS"
          color: Theme.ink3
          font.family: Theme.textFont
          font.pixelSize: Theme.fontXs
          font.weight: Font.DemiBold
        }

        IconButton {
          id: pinButton
          anchors.right: parent.right
          anchors.rightMargin: 2
          anchors.verticalCenter: parent.verticalCenter
          btnSize: 22
          fs: Theme.fontSm
          fg: root.popupWindow && root.popupWindow.pinned ? Theme.accent : Theme.ink2
          glyph: "󰐃"
          tooltip: root.popupWindow && root.popupWindow.pinned ? "Unpin process monitor" : "Pin process monitor"
          tooltipSub: root.popupWindow && root.popupWindow.pinned ? "Allow it to close when focus changes" : "Keep it open while using other windows"
          onClicked: {
            if (root.popupWindow)
              root.popupWindow.setPinned(!root.popupWindow.pinned);
          }
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
          readonly property string procPriv: rowDelegate.modelData ? root.formatRss(rowDelegate.modelData.priv) : "0K"
          readonly property string procRss: rowDelegate.modelData ? root.formatRss(rowDelegate.modelData.rss) : "0K"
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
            id: cellName
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: cellPriv.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: rowDelegate.procName
            color: rowDelegate.index === 0 ? Theme.err : Theme.ink1
            font.family: Theme.textFont
            font.pixelSize: Theme.fontBase
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            id: cellPriv
            anchors.right: cellRss.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            horizontalAlignment: Text.AlignRight
            text: rowDelegate.procPriv
            color: Theme.ink2
            font.family: root.monoFont
            font.pixelSize: Theme.fontSm
          }

          Text {
            id: cellRss
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            horizontalAlignment: Text.AlignRight
            text: rowDelegate.procRss
            color: Theme.ink3
            font.family: root.monoFont
            font.pixelSize: Theme.fontSm
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
}
