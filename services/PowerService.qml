pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Item {
  id: root

  readonly property bool canSuspend: true
  readonly property bool canHibernate: false
  readonly property bool canPowerOff: true
  readonly property bool canReboot: true

  function shutdown(): void {
    Quickshell.execDetached({
      command: ["qdbus-qt6", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logoutAndShutdown"],
      unbindStdout: true
    });
  }

  function reboot(): void {
    Quickshell.execDetached({
      command: ["qdbus-qt6", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logoutAndReboot"],
      unbindStdout: true
    });
  }

  function logout(): void {
    Quickshell.execDetached({
      command: ["qdbus-qt6", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout"],
      unbindStdout: true
    });
  }

  function suspend(): void {
    Quickshell.execDetached({
      command: ["systemctl", "suspend"],
      unbindStdout: true
    });
  }

  function lock(): void {
    Quickshell.execDetached({
      command: ["loginctl", "lock-session"],
      unbindStdout: true
    });
  }
}
