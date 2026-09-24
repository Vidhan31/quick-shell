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
    if (root.adapter.state === BluetoothAdapterState.Enabled) return Theme.accent;
    return Theme.ink3;
  }

  implicitWidth: 30 + (root.connectedCount > 0 ? 14 : 0)
  implicitHeight: Theme.btnHeightSm

  Text {
    anchors.centerIn: parent
    text: "󰖲"
    font.family: Theme.mono
    font.pixelSize: 16
    color: root.statusColor
  }

  Text {
    id: countLabel
    anchors.left: parent.left
    anchors.leftMargin: 27
    anchors.verticalCenter: parent.verticalCenter
    visible: root.connectedCount > 0
    text: root.connectedCount
    font.family: Theme.mono
    font.pixelSize: Theme.fontXs
    color: root.statusColor
  }
}
