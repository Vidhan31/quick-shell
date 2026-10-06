pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  property var processMonitor: null

  readonly property double cpuPercent: processMonitor ? processMonitor.cpuPercent : 0
  readonly property double memPercent: processMonitor ? processMonitor.memPercent : 0
  readonly property double gpuPercent: processMonitor ? processMonitor.gpuPercent : 0
  readonly property bool gpuAvailable: processMonitor ? processMonitor.gpuAvailable : false

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono
  readonly property int valuePixelSize: Theme.fontMd

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  Row {
    id: contentRow
    spacing: 8
    anchors.verticalCenter: parent.verticalCenter

    Text {
      width: 32
      horizontalAlignment: Text.AlignHCenter
      text: Math.round(root.cpuPercent) + "%"
      color: Theme.green
      font.pixelSize: root.valuePixelSize
      font.family: root.monoFont
    }
    Text {
      width: 32
      horizontalAlignment: Text.AlignHCenter
      text: Math.round(root.memPercent) + "%"
      color: Theme.accent
      font.pixelSize: root.valuePixelSize
      font.family: root.monoFont
    }
    Text {
      visible: root.gpuAvailable
      width: visible ? 32 : 0
      horizontalAlignment: Text.AlignHCenter
      text: Math.round(root.gpuPercent) + "%"
      color: Theme.violet
      font.pixelSize: root.valuePixelSize
      font.family: root.monoFont
    }
  }
}
