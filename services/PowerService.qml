pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
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

  function restartQuickshell(): void {
    const shellPath = Quickshell.shellPath(".");
    const pid = String(Quickshell.processId);
    Quickshell.execDetached({
      command: [
        "sh", "-c",
        "if systemctl --user is-active --quiet quickshell.service; then systemctl --user restart quickshell.service; else (sleep 0.2; kill -TERM " + pid + "; sleep 0.3; quickshell -p \"" + shellPath + "\") >/dev/null 2>&1 & fi"
      ],
      unbindStdout: true
    });
  }
}
