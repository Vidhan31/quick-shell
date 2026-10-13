pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  property real from: 0.0
  property real to: 1.0
  property real value: 0.0
  property color fillColor: Theme.accent
  property color trackColor: Theme.inset
  property bool animated: true

  implicitWidth: 120
  implicitHeight: 6
  radius: 3
  color: trackColor
  border.width: 1
  border.color: Theme.tint(Theme.cardBorder, 0.6)
  clip: true

  readonly property real normalized: {
    const span = root.to - root.from;
    if (span <= 0) return 0.0;
    return Math.max(0.0, Math.min(1.0, (root.value - root.from) / span));
  }

  Rectangle {
    id: fill
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    radius: root.radius
    color: root.fillColor
    width: Math.max(0, Math.min(root.width, Math.round(root.width * root.normalized)))

    Behavior on width {
      enabled: root.animated
      NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
  }
}
