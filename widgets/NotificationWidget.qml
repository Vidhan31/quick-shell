pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  property var service: null
  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  readonly property bool isDnd: service ? (service.dnd === true) : false
  readonly property int unreadCount: service ? (service.unreadCount || 0) : 0
  readonly property int totalCount: service ? ((service.notifications && service.notifications.length) || 0) : 0

  readonly property string iconGlyph: {
    if (root.isDnd) return "󰂛";
    if (root.unreadCount > 0) return "󰂚";
    if (root.totalCount > 0) return "󰂚";
    return "󰂜";
  }

  readonly property color iconColor: {
    if (root.isDnd) return Theme.warn;
    if (root.unreadCount > 0) return Theme.accent;
    if (root.totalCount > 0) return Theme.ink2;
    return Theme.inactive;
  }

  readonly property string labelText: {
    if (root.unreadCount > 0) return root.unreadCount > 99 ? "99+" : root.unreadCount.toString();
    return "";
  }

  readonly property color labelColor: root.isDnd ? Theme.warn : Theme.accent

  Row {
    id: contentRow
    spacing: root.labelText !== "" ? 4 : 0
    anchors.verticalCenter: parent.verticalCenter

    Text {
      id: bellIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconGlyph
      font.family: root.monoFont
      font.pixelSize: 18
      color: root.iconColor

      Behavior on color {
        ColorAnimation { duration: Theme.durationNormal }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.labelText !== ""
      text: root.labelText
      font.family: Theme.roundedFont
      font.pixelSize: Theme.fontXs
      font.weight: Font.DemiBold
      color: root.labelColor

      Behavior on color {
        ColorAnimation { duration: Theme.durationNormal }
      }
    }
  }
}
