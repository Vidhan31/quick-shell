pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell

Singleton {
  id: theme

  readonly property color bg: "#0e1f1c"
  readonly property color surface: "#172e2b"
  readonly property color inset: "#0b1816"
  readonly property color barBg: "#0e1f1c"
  readonly property color cardBorder: "#1e3732"
  readonly property color line: "#25403b"
  readonly property color lineMuted: Qt.rgba(0.24, 0.40, 0.36, 0.25)
  readonly property color hoverFill: "#223b36"
  readonly property color selected: "#2b423e"
  readonly property color surfaceElevated: "#223b36"
  readonly property color switchOff: "#263f3a"
  readonly property color btnDisabled: "#182c29"
  readonly property color hoverWash: Qt.rgba(1.0, 1.0, 1.0, 0.06)
  readonly property color pressWash: Qt.rgba(1.0, 1.0, 1.0, 0.12)

  readonly property color ink1: "#e2e8e7"
  readonly property color ink2: "#9fb5b1"
  readonly property color ink3: "#7f9e98"
  readonly property color darkInk: "#0a1715"
  readonly property color text: ink1
  readonly property color textMuted: ink2
  readonly property color textSubtle: ink3
  readonly property color focusRing: "#4ecaa0"
  readonly property real focusRingWidth: 1.5

  readonly property color accent: "#4ecaa0"
  readonly property color accentHover: "#5fdda8"
  readonly property color accentBg: Qt.rgba(0.31, 0.79, 0.63, 0.15)
  readonly property color okBg: Qt.rgba(0.27, 0.83, 0.60, 0.15)
  readonly property color warnBg: Qt.rgba(0.90, 0.63, 0.20, 0.15)
  readonly property color errBg: Qt.rgba(0.91, 0.36, 0.36, 0.15)
  readonly property color violetBg: Qt.rgba(0.65, 0.55, 0.98, 0.15)
  function tint(c: color, alpha: real): color {
    return Qt.rgba(c.r, c.g, c.b, alpha);
  }
  readonly property color green: "#46d39a"
  readonly property color ok: green
  readonly property color amber: "#e5a134"
  readonly property color warn: amber
  readonly property color red: "#e85d5d"
  readonly property color err: red
  readonly property color violet: "#a78bfa"
  readonly property color teal: "#2dd4bf"
  readonly property color inactive: "#5c7570"

  readonly property real radiusXs: 3
  readonly property real radiusSm: 5
  readonly property real radiusBase: 6
  readonly property real radiusSection: 8
  readonly property real radiusChip: 8
  readonly property real radiusCard: 10
  readonly property real radiusPill: 999

  readonly property int cardPadding: 12
  readonly property int cardPaddingSm: 8
  readonly property int fieldPadX: 4

  readonly property int popupWidthSm: 340
  readonly property int popupWidthMd: 440
  readonly property int popupWidthLg: 520

  readonly property int spaceXs: 4
  readonly property int spaceSm: 6
  readonly property int spaceMd: 8
  readonly property int spaceLg: 10
  readonly property int spaceXl: 12

  readonly property int barHeight: 31
  readonly property int rowHeight: 31
  readonly property int btnHeight: 28
  readonly property int btnHeightSm: 25
  readonly property int inputHeight: 32

  readonly property string mono: "JetBrainsMono Nerd Font Mono"
  readonly property string sans: "SF Pro"
  readonly property string textFont: "SF Pro Text"
  readonly property string displayFont: "SF Pro Display"
  readonly property string roundedFont: "SF Pro Rounded"

  readonly property int fontXs: 10
  readonly property int fontSm: 11
  readonly property int fontBase: 12
  readonly property int fontMd: 13
  readonly property int fontLg: 14
  readonly property int fontXl: 16
  readonly property int fontDisplay: 20
  readonly property int fontGlyphMd: 18
  readonly property int fontGlyphLg: 22

  readonly property int iconXs: 11
  readonly property int iconSm: 13
  readonly property int iconBase: 14
  readonly property int iconMd: 16
  readonly property int iconLg: 18
  readonly property int iconXl: 22
  readonly property int iconDisplay: 28
  readonly property int barIconSize: 20

  readonly property int durationFast: 90
  readonly property int durationNormal: 140
  readonly property int durationSlow: 200
  readonly property int durationPulse: 600
  readonly property int easingStandard: Easing.OutCubic

  readonly property int launcherWidth: 680
  readonly property int launcherRowHeight: 44
  readonly property int launcherMaxVisible: 8
  readonly property int launcherIconSize: 28
  readonly property int launcherRowPadX: 10
  readonly property int launcherRowInset: 4
  // Shared by the icon, the text and the search field so one line runs down
  // the card.
  readonly property int launcherContentInset: 16
  readonly property int launcherCardPadY: 12
  // Per-segment character cap for path rows. The basename is never trimmed;
  // everything else longer than this is middle-elided to ab…yz.
  readonly property int launcherPathSegMax: 24
}
