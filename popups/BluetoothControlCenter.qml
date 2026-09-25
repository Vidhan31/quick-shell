pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../theme"
import "../components"

Item {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices.values || []
  property bool advancedOpen: false

  implicitWidth: 440
  readonly property int preferredHeight: Math.min(680, 32 + bodyCol.height)
  property int popupHeight: 360

  Process {
    id: settingsProcess
    command: ["systemsettings", "kcm_bluetooth"]
  }

  function syncHeight(): void {
    popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (!root.visible) root.popupHeight = root.preferredHeight;
  }

  implicitHeight: popupHeight

  function adapterStateText(value: var): string {
    if (!root.adapter) return "Unavailable";
    if (value === BluetoothAdapterState.Disabled) return "Disabled";
    if (value === BluetoothAdapterState.Enabled) return "Enabled";
    if (value === BluetoothAdapterState.Enabling) return "Enabling";
    if (value === BluetoothAdapterState.Disabling) return "Disabling";
    if (value === BluetoothAdapterState.Blocked) return "Blocked by rfkill";
    return "Unknown";
  }

  function adapterStateColor(): color {
    if (!root.adapter) return Theme.red;
    if (root.adapter.state === BluetoothAdapterState.Enabled) return Theme.green;
    if (root.adapter.state === BluetoothAdapterState.Enabling || root.adapter.state === BluetoothAdapterState.Disabling) return Theme.amber;
    if (root.adapter.state === BluetoothAdapterState.Blocked) return Theme.red;
    return Theme.ink3;
  }

  function deviceStateText(value: var): string {
    if (value === BluetoothDeviceState.Disconnected) return "Disconnected";
    if (value === BluetoothDeviceState.Connected) return "Connected";
    if (value === BluetoothDeviceState.Connecting) return "Connecting";
    if (value === BluetoothDeviceState.Disconnecting) return "Disconnecting";
    return "Unknown";
  }

  function deviceStateColor(value: var): color {
    if (value === BluetoothDeviceState.Connected) return Theme.green;
    if (value === BluetoothDeviceState.Connecting || value === BluetoothDeviceState.Disconnecting) return Theme.amber;
    return Theme.ink3;
  }

  function deviceName(device: var): string {
    if (device.name && device.name.length > 0) return device.name;
    if (device.deviceName && device.deviceName.length > 0) return device.deviceName;
    return "Bluetooth device";
  }

  function deviceSubtitle(device: var): string {
    if (device.name && device.name.length > 0 && device.deviceName && device.deviceName.length > 0) return device.deviceName + " · " + device.address;
    return device.address;
  }

  function batteryText(device: var): string {
    return Math.round(device.battery * 100) + "%";
  }

  function openSettings(): void {
    settingsProcess.running = true;
    toast.show("Bluetooth settings requested");
  }

  function connectDevice(device: var): void {
    if (device.blocked) {
      toast.show("Device is blocked");
      return;
    }
    device.connect();
    toast.show("Connection requested");
  }

  function disconnectDevice(device: var): void {
    device.disconnect();
    toast.show("Disconnect requested");
  }

  function pairDevice(device: var): void {
    device.pair();
    toast.show("Pairing requested");
  }

  function cancelPairDevice(device: var): void {
    device.cancelPair();
    toast.show("Pairing cancellation requested");
  }

  function forgetDevice(device: var, row: var): void {
    device.forget();
    row.confirmingForget = false;
    toast.show("Forget requested");
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: Theme.cardBorder
    border.width: 1

    Flickable {
      anchors.fill: parent
      anchors.margins: 16
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 12

        RowLayout {
          width: parent.width
          height: 40
          spacing: 10

          Text {
            text: {
              if (!root.adapter || root.adapter.state === BluetoothAdapterState.Blocked) return "󰂲";
              if (root.adapter.state === BluetoothAdapterState.Enabled) {
                return (root.devices && root.devices.filter(d => d.connected).length > 0) ? "󰂱" : "󰂯";
              }
              return "󰂲";
            }
            font.family: Theme.mono
            font.pixelSize: 19
            color: root.adapterStateColor()
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
              text: "Bluetooth"
              font.pixelSize: 14
              font.weight: Font.DemiBold
              color: Theme.ink1
            }

            Text {
              Layout.fillWidth: true
              text: root.adapter ? root.adapter.name : "BlueZ unavailable"
              font.pixelSize: 11
              color: Theme.ink3
              elide: Text.ElideRight
            }
          }

          TextBtn {
            text: "Settings"
            fg: Theme.ink2
            onClicked: root.openSettings()
          }
        }

        Hairline { width: parent.width }

        Rectangle {
          width: parent.width
          radius: Theme.radiusBase
          color: Theme.surface
          border.color: Theme.line
          border.width: 1
          implicitHeight: adapterContent.implicitHeight + 24
          visible: root.adapter !== null && root.adapter !== undefined

          ColumnLayout {
            id: adapterContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                  text: root.adapter ? root.adapter.name : "Bluetooth adapter"
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.DemiBold
                  color: Theme.ink1
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  text: root.adapter ? root.adapter.adapterId : ""
                  font.family: Theme.mono
                  font.pixelSize: Theme.fontSm
                  color: Theme.ink3
                }
              }

              TSwitch {
                on: root.adapter ? root.adapter.enabled : false
                enabledSwitch: root.adapter ? root.adapter.state !== BluetoothAdapterState.Blocked : false
                onToggled: {
                  if (root.adapter) root.adapter.enabled = !root.adapter.enabled;
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Text {
                text: root.adapterStateText(root.adapter ? root.adapter.state : null)
                font.pixelSize: Theme.fontSm
                color: root.adapterStateColor()
              }

              Text {
                Layout.fillWidth: true
                text: root.adapter ? (root.adapter.discovering ? "Scanning for devices" : "Not scanning") : ""
                font.pixelSize: Theme.fontSm
                color: Theme.ink3
                elide: Text.ElideRight
              }
            }

            Text {
              Layout.fillWidth: true
              text: root.adapter && root.adapter.state === BluetoothAdapterState.Blocked
                ? "The adapter is blocked by rfkill. Enable it from system settings or remove the hardware block."
                : ""
              visible: text.length > 0
              font.pixelSize: Theme.fontSm
              color: Theme.amber
              wrapMode: Text.WordWrap
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.adapter !== null && root.adapter !== undefined
          spacing: 8

          Text {
            text: "Scan for devices"
            Layout.fillWidth: true
            font.pixelSize: Theme.fontSm
            color: Theme.ink2
          }

          TSwitch {
            on: root.adapter ? root.adapter.discovering : false
            enabledSwitch: root.adapter !== null && root.adapter !== undefined
            onToggled: {
              if (root.adapter) root.adapter.discovering = !root.adapter.discovering;
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.adapter !== null && root.adapter !== undefined
          spacing: 8

          Text {
            text: "Accept new pairings"
            Layout.fillWidth: true
            font.pixelSize: Theme.fontSm
            color: Theme.ink2
          }

          TSwitch {
            on: root.adapter ? root.adapter.pairable : false
            enabledSwitch: root.adapter !== null && root.adapter !== undefined
            onToggled: {
              if (root.adapter) root.adapter.pairable = !root.adapter.pairable;
            }
          }
        }

        SectionHead {
          width: parent.width
          label: "Devices"
          actionText: root.devices.length > 0 ? root.devices.length + " tracked" : ""
          actionColor: Theme.ink3
        }

        Repeater {
          model: root.devices

          delegate: Rectangle {
            id: deviceCard
            required property var modelData

            property bool editingAlias: false
            property bool confirmingForget: false

            width: bodyCol.width
            radius: Theme.radiusBase
            color: Theme.surface
            border.color: Theme.line
            border.width: 1
            implicitHeight: deviceContent.implicitHeight + 24

            ColumnLayout {
              id: deviceContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 8

              RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Image {
                  Layout.preferredWidth: 28
                  Layout.preferredHeight: 28
                  visible: deviceCard.modelData.icon && deviceCard.modelData.icon.length > 0
                  source: deviceCard.modelData.icon && deviceCard.modelData.icon.length > 0 ? Quickshell.iconPath(deviceCard.modelData.icon) : ""
                  fillMode: Image.PreserveAspectFit
                  cache: true
                }

                Text {
                  visible: !deviceCard.modelData.icon || deviceCard.modelData.icon.length === 0
                  text: deviceCard.modelData.connected ? "󰂱" : "󰂯"
                  font.family: Theme.mono
                  font.pixelSize: 18
                  color: Theme.accent
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  Text {
                    Layout.fillWidth: true
                    text: deviceCard.editingAlias ? aliasInput.text : root.deviceName(deviceCard.modelData)
                    font.pixelSize: Theme.fontBase
                    font.weight: Font.DemiBold
                    color: Theme.ink1
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: root.deviceSubtitle(deviceCard.modelData)
                    font.pixelSize: Theme.fontSm
                    color: Theme.ink3
                    elide: Text.ElideRight
                  }
                }

                Text {
                  text: deviceCard.modelData.batteryAvailable ? root.batteryText(deviceCard.modelData) : ""
                  visible: deviceCard.modelData.batteryAvailable
                  font.family: Theme.mono
                  font.pixelSize: Theme.fontSm
                  color: Theme.ink2
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                  text: root.deviceStateText(deviceCard.modelData.state)
                  font.pixelSize: Theme.fontSm
                  color: root.deviceStateColor(deviceCard.modelData.state)
                }

                Text {
                  text: deviceCard.modelData.pairing ? "Pairing" : (deviceCard.modelData.paired ? "Paired" : "Not paired")
                  font.pixelSize: Theme.fontSm
                  color: deviceCard.modelData.pairing ? Theme.amber : (deviceCard.modelData.paired ? Theme.green : Theme.ink3)
                }

                Text {
                  Layout.fillWidth: true
                  text: (deviceCard.modelData.bonded ? "Bonded" : "")
                    + (deviceCard.modelData.adapter ? " · " + deviceCard.modelData.adapter.adapterId : "")
                  font.pixelSize: Theme.fontSm
                  color: Theme.ink3
                  elide: Text.ElideRight
                }
              }

              RowLayout {
                Layout.fillWidth: true
                visible: deviceCard.editingAlias
                spacing: 8

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Theme.inputHeight
                  radius: Theme.radiusBase
                  color: Theme.inset
                  border.color: aliasInput.activeFocus ? Theme.accentHover : "transparent"
                  border.width: aliasInput.activeFocus ? 1 : 0

                  TextInput {
                    id: aliasInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    text: deviceCard.modelData.name
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.mono
                    font.pixelSize: Theme.fontBase
                    color: Theme.ink1
                    selectByMouse: true
                    onAccepted: {
                      deviceCard.modelData.name = text;
                    deviceCard.editingAlias = false;
                    toast.show("Alias saved");
                    }
                  }
                }

                TextBtn {
                  text: "Save"
                  fg: Theme.green
                  onClicked: {
                    deviceCard.modelData.name = aliasInput.text;
                    deviceCard.editingAlias = false;
                      toast.show("Alias saved");
                  }
                }

                TextBtn {
                  text: "Cancel"
                  onClicked: deviceCard.editingAlias = false
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 2

                TextBtn {
                  text: deviceCard.modelData.connected ? "Disconnect" : "Connect"
                  fg: deviceCard.modelData.connected ? Theme.ink2 : Theme.accent
                  onClicked: {
                    if (deviceCard.modelData.connected) root.disconnectDevice(deviceCard.modelData);
                    else root.connectDevice(deviceCard.modelData);
                  }
                }

                TextBtn {
                  text: deviceCard.modelData.pairing ? "Cancel pairing" : (deviceCard.modelData.paired ? "Paired" : "Pair")
                  fg: deviceCard.modelData.pairing ? Theme.amber : (deviceCard.modelData.paired ? Theme.ink3 : Theme.accent)
                  onClicked: {
                    if (deviceCard.modelData.pairing) root.cancelPairDevice(deviceCard.modelData);
                    else if (!deviceCard.modelData.paired) root.pairDevice(deviceCard.modelData);
                  }
                }

                TextBtn {
                  text: deviceCard.editingAlias ? "Editing" : "Rename"
                  fg: deviceCard.editingAlias ? Theme.ink3 : Theme.ink2
                  onClicked: deviceCard.editingAlias = !deviceCard.editingAlias
                }

                TextBtn {
                  text: deviceCard.confirmingForget ? "Confirm forget" : "Forget"
                  fg: deviceCard.confirmingForget ? Theme.red : Theme.ink3
                  onClicked: {
                    if (deviceCard.confirmingForget) root.forgetDevice(deviceCard.modelData, deviceCard);
                    else deviceCard.confirmingForget = true;
                  }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                  text: "Trusted"
                  Layout.fillWidth: true
                  font.pixelSize: Theme.fontSm
                  color: Theme.ink2
                }

                TSwitch {
                  on: deviceCard.modelData.trusted
                  onToggled: deviceCard.modelData.trusted = !deviceCard.modelData.trusted
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                  text: "Allowed to wake host"
                  Layout.fillWidth: true
                  font.pixelSize: Theme.fontSm
                  color: Theme.ink2
                }

                TSwitch {
                  on: deviceCard.modelData.wakeAllowed
                  onToggled: deviceCard.modelData.wakeAllowed = !deviceCard.modelData.wakeAllowed
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                  text: deviceCard.modelData.blocked ? "Blocked from connecting" : "Allowed to connect"
                  Layout.fillWidth: true
                  font.pixelSize: Theme.fontSm
                  color: deviceCard.modelData.blocked ? Theme.red : Theme.ink2
                }

                TSwitch {
                  on: deviceCard.modelData.blocked
                  onColor: Theme.red
                  onToggled: deviceCard.modelData.blocked = !deviceCard.modelData.blocked
                }
              }

              Text {
                Layout.fillWidth: true
                text: deviceCard.modelData.dbusPath
                font.family: Theme.mono
                font.pixelSize: Theme.fontXs
                color: Theme.ink3
                elide: Text.ElideMiddle
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          radius: Theme.radiusBase
          color: Theme.surface
          border.color: Theme.line
          border.width: 1
          implicitHeight: unavailableContent.implicitHeight + 24
          visible: root.devices.length === 0

          ColumnLayout {
            id: unavailableContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            Text {
              Layout.fillWidth: true
              text: root.adapter ? "No Bluetooth devices found" : "Bluetooth is unavailable"
              font.pixelSize: Theme.fontBase
              font.weight: Font.DemiBold
              color: Theme.ink1
            }

            Text {
              Layout.fillWidth: true
              text: root.adapter ? "Start a scan or pair a device from system settings." : "Start BlueZ or check the system Bluetooth service."
              font.pixelSize: Theme.fontSm
              color: Theme.ink3
              wrapMode: Text.WordWrap
            }

            TextBtn {
              text: "Open Bluetooth settings"
              fg: Theme.accent
              onClicked: root.openSettings()
            }
          }
        }

        Rectangle {
          width: parent.width
          radius: Theme.radiusBase
          color: Theme.surface
          border.color: Theme.line
          border.width: 1
          implicitHeight: advancedContent.implicitHeight + 24
          visible: root.advancedOpen && (root.adapter !== null && root.adapter !== undefined)

          ColumnLayout {
            id: advancedContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            Text {
              text: "Adapter options"
              font.pixelSize: Theme.fontBase
              font.weight: Font.DemiBold
              color: Theme.ink1
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Text {
                text: "Discoverable"
                Layout.fillWidth: true
                font.pixelSize: Theme.fontSm
                color: Theme.ink2
              }

              TSwitch {
                on: root.adapter ? root.adapter.discoverable : false
                onToggled: {
                  if (root.adapter) root.adapter.discoverable = !root.adapter.discoverable;
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Text {
                text: "Discoverable timeout (s)"
                Layout.fillWidth: true
                font.pixelSize: Theme.fontSm
                color: Theme.ink2
              }

              Rectangle {
                Layout.preferredWidth: 72
                Layout.preferredHeight: Theme.inputHeight
                radius: Theme.radiusBase
                color: Theme.inset

                TextInput {
                  id: discoverableTimeoutInput
                  anchors.fill: parent
                  anchors.leftMargin: 8
                  anchors.rightMargin: 8
                  text: root.adapter ? root.adapter.discoverableTimeout : 0
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Theme.mono
                  font.pixelSize: Theme.fontSm
                  color: Theme.ink1
                  selectByMouse: true
                  validator: IntValidator { bottom: 0; top: 2147483647 }
                  onActiveFocusChanged: {
                    if (!activeFocus && root.adapter) root.adapter.discoverableTimeout = parseInt(text) || 0;
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              Text {
                text: "Pairable timeout (s)"
                Layout.fillWidth: true
                font.pixelSize: Theme.fontSm
                color: Theme.ink2
              }

              Rectangle {
                Layout.preferredWidth: 72
                Layout.preferredHeight: Theme.inputHeight
                radius: Theme.radiusBase
                color: Theme.inset

                TextInput {
                  id: pairableTimeoutInput
                  anchors.fill: parent
                  anchors.leftMargin: 8
                  anchors.rightMargin: 8
                  text: root.adapter ? root.adapter.pairableTimeout : 0
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: Theme.mono
                  font.pixelSize: Theme.fontSm
                  color: Theme.ink1
                  selectByMouse: true
                  validator: IntValidator { bottom: 0; top: 2147483647 }
                  onActiveFocusChanged: {
                    if (!activeFocus && root.adapter) root.adapter.pairableTimeout = parseInt(text) || 0;
                  }
                }
              }
            }

            Text {
              Layout.fillWidth: true
              text: "0 means the adapter remains discoverable or pairable indefinitely."
              font.pixelSize: Theme.fontSm
              color: Theme.ink3
              wrapMode: Text.WordWrap
            }

            Hairline { Layout.fillWidth: true }

            Text {
              Layout.fillWidth: true
              text: root.adapter ? root.adapter.dbusPath : ""
              font.family: Theme.mono
              font.pixelSize: Theme.fontXs
              color: Theme.ink3
              elide: Text.ElideMiddle
            }
          }
        }

        TextBtn {
          Layout.alignment: Qt.AlignHCenter
          text: root.advancedOpen ? "Hide adapter options" : "Show adapter options"
          fg: Theme.ink2
          visible: root.adapter !== null && root.adapter !== undefined
          onClicked: root.advancedOpen = !root.advancedOpen
        }
      }
    }
  }

  Toast {
    id: toast
  }

  Component.onCompleted: root.syncHeight()
}
