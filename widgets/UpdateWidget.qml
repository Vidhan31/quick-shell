pragma ComponentBehavior: Bound
// widgets/UpdateWidget.qml — Top-bar indicator for DNF5 update status.
import QtQuick
import "../theme"

Item {
  id: root

  property var service: null
  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  readonly property bool isChecking: service ? (service.isChecking === true) : false
  readonly property bool isDownloading: service ? (service.isDownloading === true) : false
  readonly property bool isApplying: service ? (service.isApplying === true) : false
  readonly property bool hasUpdates: service ? (service.hasUpdates === true) : false
  readonly property int updateCount: service ? (service.updateCount || 0) : 0
  readonly property int securityCount: service ? (service.securityCount || 0) : 0
  readonly property bool offlineReady: service ? (service.offlineStagedReady === true) : false
  readonly property double downloadProgress: service ? (service.downloadProgress || 0.0) : 0.0

  readonly property string iconGlyph: {
    if (root.offlineReady) return "󰜉"; // Reboot ready
    if (root.isDownloading) return "󰇚"; // Downloading
    if (root.isChecking) return "󰚰"; // Checking
    if (root.securityCount > 0) return "󰒃"; // Security shield
    if (root.hasUpdates) return "󰚰"; // Available updates
    return "󰚰"; // Up to date
  }

  readonly property color iconColor: {
    if (root.offlineReady) return Theme.green;
    if (root.isDownloading) return Theme.accent;
    if (root.securityCount > 0) return Theme.amber;
    if (root.hasUpdates) return Theme.accent;
    return Theme.ink3;
  }

  readonly property string labelText: {
    if (root.offlineReady) return "Restart";
    if (root.isDownloading) return `${Math.round(root.downloadProgress * 100)}%`;
    if (root.isChecking) return "Checking";
    if (root.securityCount > 0) return `${root.updateCount} (${root.securityCount} sec)`;
    if (root.hasUpdates) return `${root.updateCount}`;
    return "";
  }

  readonly property color labelColor: {
    if (root.offlineReady) return Theme.green;
    if (root.securityCount > 0) return Theme.amber;
    if (root.hasUpdates) return Theme.ink1;
    return Theme.ink3;
  }

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  Row {
    id: contentRow
    spacing: root.labelText.length > 0 ? 6 : 0
    anchors.verticalCenter: parent.verticalCenter

    Text {
      id: iconText
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: 15
      color: root.iconColor

      Behavior on color {
        ColorAnimation { duration: Theme.durationFast }
      }

      NumberAnimation on rotation {
        running: root.isChecking
        from: 0
        to: 360
        loops: Animation.Infinite
        duration: 900
      }

      onVisibleChanged: {
        if (!root.isChecking) iconText.rotation = 0;
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.labelText.length > 0
      text: root.labelText
      font.family: root.monoFont
      font.pixelSize: Theme.fontSm
      font.weight: root.securityCount > 0 || root.offlineReady ? Font.DemiBold : Font.Normal
      color: root.labelColor

      Behavior on color {
        ColorAnimation { duration: Theme.durationFast }
      }
    }
  }
}
