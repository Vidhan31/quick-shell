pragma ComponentBehavior: Bound
// NotificationWidget.qml — Compact top bar widget for notification status and unread counter.
import QtQuick

Item {
  id: root

  property var service: null
  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  readonly property bool isDnd: service ? (service.dnd === true) : false
  readonly property int unreadCount: service ? (service.unreadCount || 0) : 0
  readonly property int totalCount: service ? ((service.notifications && service.notifications.length) || 0) : 0

  // Bell icon glyph
  readonly property string iconGlyph: {
    if (root.isDnd) return "󰂛"; // Bell off
    if (root.unreadCount > 0) return "󰂚"; // Bell active
    if (root.totalCount > 0) return "󰂚";
    return "󰂜"; // Bell outline
  }

  // Bell icon color
  readonly property color iconColor: {
    if (root.isDnd) return "#fab387"; // Peach / Warning
    if (root.unreadCount > 0) return "#89b4fa"; // Blue / Active
    if (root.totalCount > 0) return "#cdd6f4";
    return "#a6adc8"; // Subdued
  }

  implicitWidth: contentRow.implicitWidth
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight

  Row {
    id: contentRow
    spacing: 5
    anchors.verticalCenter: parent.verticalCenter

    // Bell icon
    Text {
      id: bellIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: 14
      color: root.iconColor

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
    }

    // Unread count badge
    Rectangle {
      id: badge
      anchors.verticalCenter: parent.verticalCenter
      visible: root.unreadCount > 0
      width: Math.max(16, badgeText.implicitWidth + 8)
      height: 16
      radius: 8
      color: "#89b4fa"

      Text {
        id: badgeText
        anchors.centerIn: parent
        text: root.unreadCount > 99 ? "99+" : `${root.unreadCount}`
        font.family: root.monoFont
        font.pixelSize: 9
        font.bold: true
        color: "#181825"
      }
    }

    // Small indicator dot for DND if no unread badge
    Rectangle {
      id: dndDot
      anchors.verticalCenter: parent.verticalCenter
      visible: root.isDnd && root.unreadCount === 0
      width: 6
      height: 6
      radius: 3
      color: "#fab387"
    }
  }
}
