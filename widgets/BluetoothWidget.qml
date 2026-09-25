pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import "../theme"

Item {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices.values
  readonly property int connectedCount: devices.filter(device => device.connected).length

  readonly property color statusColor: {
    if (!root.adapter) return Theme.ink3;
    if (root.adapter.state === BluetoothAdapterState.Blocked) return Theme.red;
    if (root.adapter.state === BluetoothAdapterState.Enabled) return (root.connectedCount > 0 ? Theme.accent : Theme.ink2);
    return Theme.ink3;
  }

  readonly property string iconGlyph: {
    if (!root.adapter || root.adapter.state === BluetoothAdapterState.Blocked) return "󰂲";
    if (root.connectedCount > 0) return "󰂱";
    return "󰂯";
  }

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: 4

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: Theme.mono
      font.pixelSize: 16
      color: root.statusColor
    }

    Text {
      id: countLabel
      anchors.verticalCenter: parent.verticalCenter
      visible: root.connectedCount > 0
      text: root.connectedCount
      font.family: Theme.mono
      font.pixelSize: Theme.fontXs
      font.weight: Font.Medium
      color: root.statusColor
    }
  }
}
