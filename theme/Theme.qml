pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell

Singleton {
  id: theme

  readonly property color bg: "#0d1117"
  readonly property color surface: "#161b27"
  readonly property color popupGlass: Qt.rgba(0.065, 0.08, 0.115, 0.94)
  readonly property color inset: "#0b0f17"
  readonly property color barBg: "#0d1117"
  readonly property color cardBorder: Qt.rgba(0.40, 0.48, 0.65, 0.22)
  readonly property color popupBorder: Qt.rgba(0.48, 0.58, 0.92, 0.70)
  readonly property color line: Qt.rgba(0.40, 0.48, 0.65, 0.16)
  readonly property color lineMuted: Qt.rgba(0.40, 0.48, 0.65, 0.10)
  readonly property color hoverFill: "#1c2334"
  readonly property color selected: "#222a3d"
  readonly property color surfaceElevated: "#1d2334"
  readonly property color switchOff: "#1b2230"
  readonly property color btnDisabled: "#141822"
  readonly property color hoverWash: Qt.rgba(1.0, 1.0, 1.0, 0.06)
  readonly property color pressWash: Qt.rgba(1.0, 1.0, 1.0, 0.12)

  readonly property color ink1: "#f0f4fc"
  readonly property color ink2: "#94a3b8"
  readonly property color ink3: "#64748b"
  readonly property color darkInk: "#0a0d14"
  readonly property color text: ink1
  readonly property color textMuted: ink2
  readonly property color textSubtle: ink3
  readonly property color focusRing: "#7aa2f7"
  readonly property real focusRingWidth: 1.5

  readonly property color accent: "#7aa2f7"
  readonly property color accentHover: "#89b4fa"
  readonly property color accentBg: Qt.rgba(0.48, 0.64, 0.97, 0.15)
  readonly property color okBg: Qt.rgba(0.45, 0.85, 0.55, 0.15)
  readonly property color warnBg: Qt.rgba(0.88, 0.69, 0.41, 0.15)
  readonly property color errBg: Qt.rgba(0.97, 0.46, 0.56, 0.15)
  readonly property color violetBg: Qt.rgba(0.73, 0.60, 0.97, 0.15)
  function tint(c: color, alpha: real): color {
    return Qt.rgba(c.r, c.g, c.b, alpha);
  }
  readonly property color green: "#73daca"
  readonly property color ok: green
  readonly property color amber: "#e0af68"
  readonly property color warn: amber
  readonly property color red: "#f7768e"
  readonly property color err: red
  readonly property color violet: "#bb9af7"
  readonly property color teal: "#7dcfff"
  readonly property color inactive: "#475569"

  readonly property real radiusXs: 0
  readonly property real radiusSm: 0
  readonly property real radiusBase: 0
  readonly property real radiusSection: 0
  readonly property real radiusChip: 0
  readonly property real radiusCard: 0
  readonly property real radiusPill: 0

  readonly property int cardPadding: 16
  readonly property int cardPaddingSm: 10
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
  readonly property int launcherContentInset: 16
  readonly property int launcherCardPadY: 12
  // Per-segment character cap for path rows. The basename is never trimmed;
  // everything else longer than this is middle-elided to ab…yz.
  readonly property int launcherPathSegMax: 24
}
