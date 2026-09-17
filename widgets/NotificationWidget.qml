pragma ComponentBehavior: Bound
// NotificationWidget.qml — Quiet top-bar indicator for notifications.
// Single glyph + single word. No badge pill, no dot: the tint carries state.
import QtQuick

Item {
  id: root

  property var service: null
  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

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
    if (root.isDnd) return "#E2A63B";
    if (root.unreadCount > 0) return "#5E9DFF";
    if (root.totalCount > 0) return "#A6A6B8";
    return "#6F6F84";
  }

  readonly property string labelText: {
    if (root.isDnd) return root.unreadCount > 0 ? `Muted ${root.unreadCount}` : "Muted";
    if (root.unreadCount > 0) return root.unreadCount > 99 ? "99+ new" : `${root.unreadCount} new`;
    return "Notifications";
  }

  readonly property color labelColor: {
    if (root.isDnd) return "#6F6F84";
    if (root.unreadCount > 0) return "#C9C9D6";
    return "#6F6F84";
  }

  implicitWidth: contentRow.width
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight

  Row {
    id: contentRow
    spacing: 7
    anchors.verticalCenter: parent.verticalCenter

    Text {
      id: bellIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: 13
      color: root.iconColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.labelText
      font.pixelSize: 12
      color: root.labelColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
    }
  }
}
