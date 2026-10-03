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
    return Theme.accent;
  }

  readonly property color washColor: {
    if (root.tone === "ok") return Theme.okBg;
    if (root.tone === "warn") return Theme.warnBg;
    if (root.tone === "err") return Theme.errBg;
    if (root.tone === "violet") return Theme.violetBg;
    return Theme.accentBg;
  }

  implicitWidth: pillLabel.implicitWidth + 10
  implicitHeight: 18
  radius: Theme.radiusPill
  color: root.solid ? root.toneColor : root.washColor

  Text {
    id: pillLabel
    anchors.centerIn: parent
    text: root.text
    font.family: Theme.roundedFont
    font.pixelSize: root.fs
    font.weight: Font.Bold
    color: (root.solid && (root.tone === "warn" || root.tone === "err")) ? Theme.darkInk : root.toneColor
  }
}
