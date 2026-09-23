pragma ComponentBehavior: Bound
// VolumeControlCenter.qml — Sound and PipeWire audio control center popup.
//
// Follows the quick-shell design system: card frame, surface containers with
// hairlines, SectionHead, VolumeSlider, IconBtn.
// Displays connected output/input device info, master controls, and per-app streams.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import "../theme"
import "../components"

Item {
  id: root

  property var audio: null

  Loader {
    id: fallbackLoader
    active: root.audio === null
    sourceComponent: AudioService {}
  }

  readonly property var activeAudio: root.audio ? root.audio : fallbackLoader.item

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  // System settings launcher for audio
  Process {
    id: settingsProc
    command: ["systemsettings", "kcm_pulseaudio"]
  }

  function openAudioSettings(): void {
    settingsProc.running = true;
  }

  function deviceIcon(desc: string, isMic: bool): string {
    if (isMic) {
      const lower = (desc || "").toLowerCase();
      if (lower.indexOf("webcam") !== -1 || lower.indexOf("camera") !== -1) return "󰄀";
      return "󰍬";
    }
    const d = (desc || "").toLowerCase();
    if (d.indexOf("headphone") !== -1 || d.indexOf("headset") !== -1 ||
        d.indexOf("tune") !== -1 || d.indexOf("earphone") !== -1 ||
        d.indexOf("buds") !== -1 || d.indexOf("airpods") !== -1) {
      return "󰋋";
    }
    if (d.indexOf("hdmi") !== -1 || d.indexOf("digital") !== -1) {
      return "󰽟";
    }
    return "󰓃";
  }

  implicitWidth: 420
  implicitHeight: Math.min(560, 32 + bodyCol.height)
  width: implicitWidth
  height: implicitHeight

  // ================= Card Frame =================
  Rectangle {
    id: card
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.color: Theme.cardBorder
    border.width: 1

    Flickable {
      anchors.fill: parent
      anchors.margins: 16
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 12

        // ---- Header: title, active device name, mute toggle, and settings button ----
        RowLayout {
          width: parent.width
          height: 40
          spacing: 10

          Text {
            text: root.activeAudio ? root.activeAudio.sinkGlyph : "󰕾"
            font.family: t.mono
            font.pixelSize: 19
            color: (root.activeAudio && root.activeAudio.muted) ? t.ink3 : t.accent
          }

          Column {
            Layout.fillWidth: true
            spacing: 1

            Text {
              text: "Sound"
              font.pixelSize: 14
              font.weight: Font.DemiBold
              color: t.ink1
            }

            Text {
              text: root.activeAudio ? root.activeAudio.sinkName : "PipeWire Audio"
              font.pixelSize: 11
              color: t.ink3
              elide: Text.ElideRight
              width: parent.width
            }
          }

          // Header Quick Mute Button
          IconBtn {
            glyph: (root.activeAudio && root.activeAudio.muted) ? "󰝟" : "󰕾"
            fg: (root.activeAudio && root.activeAudio.muted) ? t.err : t.ink2
            onClicked: {
              if (root.activeAudio) root.activeAudio.toggleMute();
            }
          }

          // Settings Button
          IconBtn {
            glyph: "󰒓"
            fg: t.ink3
            onClicked: root.openAudioSettings()
          }
        }

        Hairline { width: parent.width }

        // ================= Section 1: Connected Output Device & Volume =================
        Column {
          width: parent.width
          spacing: 6

          SectionHead {
            label: "Output"
            actionText: (root.activeAudio && root.activeAudio.muted) ? "Unmute" : "Mute"
            actionColor: (root.activeAudio && root.activeAudio.muted) ? t.accent : t.ink3
            onActionClicked: {
              if (root.activeAudio) root.activeAudio.toggleMute();
            }
          }

          Rectangle {
            width: parent.width
            radius: Theme.radiusBase
            color: Theme.surface
            border.color: Theme.line
            border.width: 1
            implicitHeight: masterCol.height + 24

            Column {
              id: masterCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 8

              RowLayout {
                width: parent.width
                spacing: 8

                Text {
                  text: root.deviceIcon(root.activeAudio ? root.activeAudio.sinkName : "", false)
                  font.family: t.mono
                  font.pixelSize: 15
                  color: (root.activeAudio && root.activeAudio.muted) ? t.ink3 : t.ink1
                }

                Text {
                  Layout.fillWidth: true
                  text: root.activeAudio ? root.activeAudio.sinkName : "Output"
                  font.pixelSize: 12
                  font.weight: Font.Medium
                  color: t.ink1
                  elide: Text.ElideRight
                }

                Text {
                  text: {
                    if (!root.activeAudio) return "0%";
                    if (root.activeAudio.muted) return "Muted";
                    return Math.round(root.activeAudio.volume * 100) + "%";
                  }
                  font.family: t.mono
                  font.pixelSize: 12
                  font.weight: Font.Medium
                  color: (root.activeAudio && root.activeAudio.muted) ? t.ink3 : t.accent
                }
              }

              // Volume Slider
              VolumeSlider {
                width: parent.width
                value: root.activeAudio ? root.activeAudio.volume : 0.0
                muted: root.activeAudio ? root.activeAudio.muted : false
                from: 0.0
                to: 1.5
                onMoved: val => {
                  if (root.activeAudio) root.activeAudio.setVolume(val);
                }
              }
            }
          }
        }

        // ================= Section 2: Connected Input / Microphone =================
        Column {
          width: parent.width
          spacing: 6
          visible: root.activeAudio && root.activeAudio.hasSource

          SectionHead {
            label: "Microphone"
            actionText: (root.activeAudio && root.activeAudio.micMuted) ? "Unmute" : "Mute"
            actionColor: (root.activeAudio && root.activeAudio.micMuted) ? t.accent : t.ink3
            onActionClicked: {
              if (root.activeAudio) root.activeAudio.toggleMicMute();
            }
          }

          Rectangle {
            width: parent.width
            radius: Theme.radiusBase
            color: Theme.surface
            border.color: Theme.line
            border.width: 1
            implicitHeight: micCol.height + 24

            Column {
              id: micCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 8

              RowLayout {
                width: parent.width
                spacing: 8

                Text {
                  text: root.deviceIcon(root.activeAudio ? root.activeAudio.sourceName : "", true)
                  font.family: t.mono
                  font.pixelSize: 15
                  color: (root.activeAudio && root.activeAudio.micMuted) ? t.err : t.ink1
                }

                Text {
                  Layout.fillWidth: true
                  text: root.activeAudio ? root.activeAudio.sourceName : "Microphone"
                  font.pixelSize: 12
                  font.weight: Font.Medium
                  color: t.ink1
                  elide: Text.ElideRight
                }

                Text {
                  text: {
                    if (!root.activeAudio) return "0%";
                    if (root.activeAudio.micMuted) return "Muted";
                    return Math.round(root.activeAudio.micVolume * 100) + "%";
                  }
                  font.family: t.mono
                  font.pixelSize: 12
                  font.weight: Font.Medium
                  color: (root.activeAudio && root.activeAudio.micMuted) ? t.err : t.accent
                }
              }

              VolumeSlider {
                width: parent.width
                value: root.activeAudio ? root.activeAudio.micVolume : 0.0
                muted: root.activeAudio ? root.activeAudio.micMuted : false
                from: 0.0
                to: 1.0
                activeColor: t.green
                onMoved: val => {
                  if (root.activeAudio) root.activeAudio.setMicVolume(val);
                }
              }
            }
          }
        }

        // ================= Section 3: Applications / Per-App Mixer =================
        Column {
          width: parent.width
          spacing: 6

          SectionHead {
            label: "Applications"
          }

          Rectangle {
            width: parent.width
            radius: Theme.radiusBase
            color: Theme.surface
            border.color: Theme.line
            border.width: 1
            implicitHeight: appCol.height + (appStreamsRepeater.count > 0 ? 24 : 32)

            Column {
              id: appCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 10

              // Empty state when no applications are outputting sound
              Text {
                visible: appStreamsRepeater.count === 0
                text: "No active audio streams"
                font.pixelSize: 12
                color: t.ink3
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Repeater {
                id: appStreamsRepeater
                model: root.activeAudio ? root.activeAudio.streams : []

                delegate: Column {
                  id: streamItem
                  required property var modelData
                  required property int index
                  width: appCol.width
                  spacing: 6

                  Hairline {
                    width: parent.width
                    visible: streamItem.index > 0
                  }

                  RowLayout {
                    width: parent.width
                    spacing: 8

                    Text {
                      text: "󰓇"
                      font.family: t.mono
                      font.pixelSize: 14
                      color: (streamItem.modelData?.audio?.muted) ? t.ink3 : t.accent
                    }

                    Column {
                      Layout.fillWidth: true
                      spacing: 1

                      Text {
                        text: root.activeAudio ? root.activeAudio.streamAppName(streamItem.modelData) : "App"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: t.ink1
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: text.length > 0
                        text: root.activeAudio ? root.activeAudio.streamDescription(streamItem.modelData) : ""
                        font.pixelSize: 10
                        color: t.ink3
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }

                    Text {
                      text: {
                        if (!streamItem.modelData?.audio) return "0%";
                        if (streamItem.modelData.audio.muted) return "Muted";
                        return Math.round(streamItem.modelData.audio.volume * 100) + "%";
                      }
                      font.family: t.mono
                      font.pixelSize: 11
                      color: (streamItem.modelData?.audio?.muted) ? t.ink3 : t.accent
                    }

                    IconBtn {
                      glyph: (streamItem.modelData?.audio?.muted) ? "󰝟" : "󰕾"
                      fs: 12
                      btnSize: 24
                      fg: (streamItem.modelData?.audio?.muted) ? t.err : t.ink3
                      onClicked: {
                        if (root.activeAudio) root.activeAudio.toggleStreamMute(streamItem.modelData);
                      }
                    }
                  }

                  VolumeSlider {
                    width: parent.width
                    value: streamItem.modelData?.audio?.volume ?? 0.0
                    muted: streamItem.modelData?.audio?.muted ?? false
                    from: 0.0
                    to: 1.5
                    onMoved: val => {
                      if (root.activeAudio) root.activeAudio.setStreamVolume(streamItem.modelData, val);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
