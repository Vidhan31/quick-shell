pragma ComponentBehavior: Bound
// NotificationWidget.qml — Quiet top-bar indicator for notifications.
// Single glyph + single word. No badge pill, no dot: the tint carries state.
import QtQuick
import "../theme"

Item {
  id: root

  property var service: null
  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  readonly property bool isDnd: service ? (service.dnd === true) : false
  readonly property int unreadCount: service ? (service.unreadCount || 0) : 0
  readonly property int totalCount: service ? ((service.notifications && service.notifications.length) || 0) : 0

  // Bell glyph mirrors TailscaleWidget's single-glyph approach.
  readonly property string iconGlyph: {
    if (root.isDnd) return "󰂛"; // Bell off
    if (root.unreadCount > 0) return "󰂚"; // Bell active
    if (root.totalCount > 0) return "󰂚";
    return "󰂜"; // Bell outline
  }

  // Tint carries state: amber when muted, accent when new, quiet grey otherwise.
  readonly property color iconColor: {
    if (root.isDnd) return Theme.amber;
    if (root.unreadCount > 0) return Theme.accent;
    if (root.totalCount > 0) return Theme.ink2;
    return Theme.ink3;
  }

  readonly property string labelText: {
    if (root.isDnd) return root.unreadCount > 0 ? `Muted ${root.unreadCount}` : "Muted";
    if (root.unreadCount > 0) return root.unreadCount > 99 ? "99+ new" : `${root.unreadCount} new`;
    return "";
  }

  readonly property color labelColor: {
    if (root.isDnd) return Theme.ink3;
    if (root.unreadCount > 0) return Theme.ink1;
    return Theme.ink3;
  }

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  Row {
    id: contentRow
    spacing: (root.unreadCount > 0 || root.isDnd) ? 7 : 0
    anchors.verticalCenter: parent.verticalCenter

    Text {
      id: bellIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: 16
      color: root.iconColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.unreadCount > 0 || root.isDnd
      text: root.labelText
      font.pixelSize: 12
      color: root.labelColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
    }
  }
}
