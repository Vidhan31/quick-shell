pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Rectangle {
  id: root

  property string text: ""
  property string tone: "accent"
  property bool solid: false
  property int fs: Theme.fontXs

  readonly property color toneColor: {
    if (root.tone === "ok") return Theme.green;
    if (root.tone === "warn") return Theme.amber;
    if (root.tone === "err") return Theme.red;
    if (root.tone === "violet") return Theme.violet;
    if (root.tone === "teal") return Theme.teal;
    if (root.tone === "muted") return Theme.ink2;
    return Theme.accent;
  }

  readonly property color washColor: {
    if (root.tone === "ok") return Theme.okBg;
    if (root.tone === "warn") return Theme.warnBg;
    if (root.tone === "err") return Theme.errBg;
    if (root.tone === "violet") return Theme.violetBg;
    if (root.tone === "teal") return Theme.tint(Theme.teal, 0.15);
    if (root.tone === "muted") return Theme.tint(Theme.ink2, 0.15);
    return Theme.accentBg;
  }

  implicitWidth: pillLabel.implicitWidth + 12
  implicitHeight: 18
  radius: Theme.radiusPill
  color: root.solid ? root.toneColor : root.washColor
  border.color: root.solid ? "transparent" : Theme.tint(toneColor, 0.25)
  border.width: root.solid ? 0 : 1

  Text {
    id: pillLabel
    anchors.centerIn: parent
    text: root.text
    font.family: Theme.mono
    font.pixelSize: root.fs
    font.letterSpacing: 0.5
    font.weight: Font.SemiBold
    color: (root.solid && (root.tone === "warn" || root.tone === "err")) ? Theme.darkInk : root.toneColor
  }
}
