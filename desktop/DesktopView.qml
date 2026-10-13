pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"

PanelWindow {
  id: desktopWindow

  property ShellScreen targetScreen: null
  screen: desktopWindow.targetScreen

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  color: Theme.bg
  exclusionMode: ExclusionMode.Ignore
  focusable: false

  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "desktop"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  signal contextMenuRequested(real mouseX, real mouseY)
  signal clicked(real mouseX, real mouseY)

  Wallpaper {
    id: wallpaper
    anchors.fill: parent
    screenName: desktopWindow.targetScreen ? desktopWindow.targetScreen.name : ""

    onClicked: (mouseX, mouseY) => {
      desktopWindow.clicked(mouseX, mouseY);
    }

    onContextMenuRequested: (mouseX, mouseY) => {
      desktopWindow.contextMenuRequested(mouseX, mouseY);
    }
  }
}
