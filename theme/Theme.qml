// theme/Theme.qml — Centralized design tokens for quick-shell.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
  id: theme

  // --- Backgrounds & surfaces ---
  readonly property color bg: "#17171E"
  readonly property color surface: "#1F202B"
  readonly property color inset: "#121217"
  readonly property color barBg: "#17171E"
  readonly property color cardBorder: "#26272F"
  readonly property color line: "#2B2C3A"
  readonly property color lineMuted: Qt.rgba(0.17, 0.17, 0.23, 0.4)
  readonly property color hoverFill: "#22232F"
  readonly property color selected: "#2E2F42"
  readonly property color surfaceElevated: "#2A2B38"
  readonly property color switchOff: "#3B3C4C"
  readonly property color btnDisabled: "#24252F"
  readonly property color hoverWash: "#0FFFFFFF"
  readonly property color pressWash: "#1CFFFFFF"

  // --- Content & text ---
  readonly property color ink1: "#F1F1F6"
  readonly property color ink2: "#A6A6B8"
  readonly property color ink3: "#6F6F84"
  readonly property color darkInk: "#101018"
  readonly property color text: ink1
  readonly property color textMuted: ink2
  readonly property color textSubtle: ink3

  // --- Accents & status ---
  readonly property color accent: "#5E9DFF"
  readonly property color accentHover: "#7AAEFF"
  readonly property color accentBg: Qt.rgba(0.37, 0.62, 1.0, 0.15)
  readonly property color green: "#46C786"
  readonly property color ok: green
  readonly property color amber: "#E2A63B"
  readonly property color warn: amber
  readonly property color red: "#DF6363"
  readonly property color err: red
  readonly property color violet: "#AE8CFF"
  readonly property color teal: "#94E2D5"
  readonly property color inactive: "#6F6F84"

  // --- Domain semantics ---
  readonly property color cpu: green
  readonly property color mem: accent
  readonly property color temp: amber
  readonly property color gpu: violet
  readonly property color tailscale: accent
  readonly property color ethernet: green
  readonly property color privacyActive: red

  // --- Geometry ---
  readonly property real radiusXs: 4
  readonly property real radiusSm: 6
  readonly property real radiusBase: 8
  readonly property real radiusChip: 10
  readonly property real radiusCard: 14
  readonly property real radiusPill: 999

  readonly property int spaceXs: 4
  readonly property int spaceSm: 6
  readonly property int spaceMd: 8
  readonly property int spaceLg: 12
  readonly property int spaceXl: 16

  readonly property int barHeight: 32
  readonly property int rowHeight: 34
  readonly property int btnHeight: 28
  readonly property int btnHeightSm: 24
  readonly property int inputHeight: 32

  // --- Typography ---
  readonly property string mono: "JetBrainsMono Nerd Font Mono"
  readonly property string sans: "Inter, sans-serif"

  readonly property int fontXs: 10
  readonly property int fontSm: 11
  readonly property int fontBase: 12
  readonly property int fontMd: 13
  readonly property int fontLg: 14
  readonly property int fontXl: 16
  readonly property int fontDisplay: 20

  // --- Animation ---
  readonly property int durationFast: 90
  readonly property int durationNormal: 140
  readonly property int durationSlow: 200
  readonly property int easingStandard: Easing.OutCubic
}
