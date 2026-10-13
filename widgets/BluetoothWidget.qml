pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import "../theme"

Item {
  id: root

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices.values
  readonly property int connectedCount: devices.filter(device => device.connected).length

  readonly property color statusColor: {
    if (!root.adapter) return Theme.inactive;
    if (root.adapter.state === BluetoothAdapterState.Blocked) return Theme.err;
    if (root.adapter.state === BluetoothAdapterState.Enabled) return (root.connectedCount > 0 ? Theme.ok : Theme.ink2);
    return Theme.inactive;
  }

  readonly property string iconGlyph: {
    if (!root.adapter || root.adapter.state === BluetoothAdapterState.Blocked) return "󰂲";
    if (root.connectedCount > 0) return "󰂱";
    return "󰂯";
  }

  Row {
    id: contentRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: Theme.mono
      font.pixelSize: Theme.iconMd
      color: root.statusColor
    }

    Text {
      id: countLabel
      anchors.verticalCenter: parent.verticalCenter
      visible: root.connectedCount > 0
      text: root.connectedCount
      font.family: Theme.roundedFont
      font.pixelSize: Theme.fontXs
      font.weight: Font.DemiBold
      color: root.statusColor
    }
  }
}
