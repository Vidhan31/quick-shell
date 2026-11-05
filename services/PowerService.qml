pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Plugins.PowerManager

Item {
  id: root

  readonly property bool canSuspend: true
  readonly property bool canHibernate: false
  readonly property bool canPowerOff: true
  readonly property bool canReboot: true
  readonly property bool canRebootToWindows: pm.canRebootToWindows
  readonly property string windowsBootEntry: pm.windowsBootEntry
  readonly property bool isRebooting: pm.isRebooting

  signal rebootToWindowsFailed(string error)
  signal operationFailed(string operation, string error)

  PowerManager {
    id: pm
    onRebootToWindowsFailed: error => root.rebootToWindowsFailed(error)
    onOperationFailed: (operation, reason) => root.operationFailed(operation, reason)
  }

  function shutdown(): void {
    pm.requestShutdown();
  }

  function reboot(): void {
    pm.requestReboot();
  }

  function rebootToWindows(): void {
    pm.requestRebootToWindows();
  }

  function refreshBootEntries(): void {
    pm.refreshBootEntries();
  }

  function logout(): void {
    pm.requestLogout();
  }

  function suspend(): void {
    pm.requestSuspend();
  }

  function lock(): void {
    pm.requestLock();
  }
}
