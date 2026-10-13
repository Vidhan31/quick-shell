pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Plugins.PowerManager

Item {
  id: root

  readonly property bool canSuspend: true
  readonly property bool canHibernate: false
  readonly property bool canPowerOff: true
  readonly property bool canReboot: true

  PowerManager {
    id: pm
  }

  function shutdown(): void {
    pm.requestShutdown();
  }

  function reboot(): void {
    pm.requestReboot();
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
