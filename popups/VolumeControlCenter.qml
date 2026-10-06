pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import "../theme"
import "../components"
import "volume"

Item {
  id: root

  property var audio: null
  readonly property var activeAudio: root.audio

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

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

  implicitWidth: Theme.popupWidthMd
  readonly property int preferredHeight: Math.min(680, 32 + bodyCol.height)
  property int popupHeight: 360

  function syncHeight() {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (bodyCol.height > 0)
      popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

  PopupCard {
    id: card
    anchors.fill: parent

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: bodyCol.height
      clip: true

      Column {
        id: bodyCol
        width: parent.width
        spacing: 12

        PopupHeader {
          width: parent.width
          glyph: root.activeAudio ? root.activeAudio.sinkGlyph : "󰕾"
          glyphColor: (root.activeAudio && root.activeAudio.muted) ? root.t.ink3 : root.t.accent
          title: "Sound"
          subtitle: "PipeWire Audio"

          IconBtn {
            glyph: "󰒓"
            fg: root.t.ink3
            fs: Theme.iconBase
            tooltip: "Audio settings"
            onClicked: root.openAudioSettings()
          }
        }

        Hairline { width: parent.width }

        Column {
          width: parent.width
          spacing: 6

          SectionHead {
            label: "Output"
            actionGlyph: (root.activeAudio && root.activeAudio.muted) ? "󰝟" : "󰕾"
            actionColor: (root.activeAudio && root.activeAudio.muted) ? root.t.err : root.t.accent
            actionTooltip: (root.activeAudio && root.activeAudio.muted) ? "Unmute output" : "Mute output"
            onActionClicked: {
              if (root.activeAudio) root.activeAudio.toggleMute();
            }
          }

          SectionCard {
            width: parent.width
            bordered: false
            implicitHeight: masterCol.height + 20

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
                  font.family: root.t.mono
                  font.pixelSize: 15
                  color: (root.activeAudio && root.activeAudio.muted) ? root.t.ink3 : root.t.ink1
                }

                Text {
                  Layout.fillWidth: true
                  text: root.activeAudio ? root.activeAudio.sinkName : "Output"
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.Medium
                  color: root.t.ink1
                  elide: Text.ElideRight
                }

                Text {
                  text: {
                    if (!root.activeAudio) return "0%";
                    if (root.activeAudio.muted) return "Muted";
                    return Math.round(root.activeAudio.volume * 100) + "%";
                  }
                  font.family: Theme.roundedFont
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.DemiBold
                  color: (root.activeAudio && root.activeAudio.muted) ? root.t.ink3 : root.t.accent
                }
              }

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

        Column {
          width: parent.width
          spacing: 6
          visible: root.activeAudio && root.activeAudio.hasSource

          SectionHead {
            label: "Microphone"
            actionGlyph: (root.activeAudio && root.activeAudio.micMuted) ? "󰍭" : "󰍬"
            actionColor: (root.activeAudio && root.activeAudio.micMuted) ? root.t.err : root.t.accent
            actionTooltip: (root.activeAudio && root.activeAudio.micMuted) ? "Unmute microphone" : "Mute microphone"
            onActionClicked: {
              if (root.activeAudio) root.activeAudio.toggleMicMute();
            }
          }

          SectionCard {
            width: parent.width
            bordered: false
            implicitHeight: micCol.height + 20

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
                  font.family: root.t.mono
                  font.pixelSize: 15
                  color: (root.activeAudio && root.activeAudio.micMuted) ? root.t.err : root.t.ink1
                }

                Text {
                  Layout.fillWidth: true
                  text: root.activeAudio ? root.activeAudio.sourceName : "Microphone"
                  font.family: Theme.textFont
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.Medium
                  color: root.t.ink1
                  elide: Text.ElideRight
                }

                Text {
                  text: {
                    if (!root.activeAudio) return "0%";
                    if (root.activeAudio.micMuted) return "Muted";
                    return Math.round(root.activeAudio.micVolume * 100) + "%";
                  }
                  font.family: Theme.roundedFont
                  font.pixelSize: Theme.fontBase
                  font.weight: Font.DemiBold
                  color: (root.activeAudio && root.activeAudio.micMuted) ? root.t.err : root.t.accent
                }
              }

              VolumeSlider {
                width: parent.width
                value: root.activeAudio ? root.activeAudio.micVolume : 0.0
                muted: root.activeAudio ? root.activeAudio.micMuted : false
                from: 0.0
                to: 1.0
                activeColor: root.t.green
                onMoved: val => {
                  if (root.activeAudio) root.activeAudio.setMicVolume(val);
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: 6

          SectionHead {
            label: "Applications"
          }

          SectionCard {
            width: parent.width
            bordered: true
            implicitHeight: appCol.height + (appStreamsRepeater.count > 0 ? 24 : 32)

            Column {
              id: appCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 10

              Text {
                visible: appStreamsRepeater.count === 0
                text: "No active audio streams"
                font.pixelSize: Theme.fontBase
                color: root.t.ink3
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Repeater {
                id: appStreamsRepeater
                model: ScriptModel {
                  values: (root.activeAudio && root.activeAudio.streams) ? root.activeAudio.streams : []
                  objectProp: "id"
                  comparisonMode: ObjectComparison.Identity
                }

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
                      font.family: root.t.mono
                      font.pixelSize: Theme.fontLg
                      color: (streamItem.modelData?.audio?.muted) ? root.t.ink3 : root.t.accent
                    }

                    Column {
                      Layout.fillWidth: true
                      spacing: 1

                      Text {
                        text: root.activeAudio ? root.activeAudio.streamAppName(streamItem.modelData) : "App"
                        font.pixelSize: Theme.fontBase
                        font.weight: Font.Medium
                        color: root.t.ink1
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: text.length > 0
                        text: root.activeAudio ? root.activeAudio.streamDescription(streamItem.modelData) : ""
                        font.pixelSize: Theme.fontXs
                        color: root.t.ink3
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
                      font.family: root.t.mono
                      font.pixelSize: Theme.fontSm
                      color: (streamItem.modelData?.audio?.muted) ? root.t.ink3 : root.t.accent
                    }

                    IconBtn {
                      glyph: (streamItem.modelData?.audio?.muted) ? "󰝟" : "󰕾"
                      fs: Theme.iconSm
                      btnSize: 24
                      fg: (streamItem.modelData?.audio?.muted) ? root.t.err : root.t.ink3
                      tooltip: (streamItem.modelData?.audio?.muted) ? "Unmute application" : "Mute application"
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

        Column {
          width: parent.width
          spacing: 6
          visible: (root.activeAudio ? root.activeAudio.sinks.length : 0) > 1

          SectionHead {
            label: "Output Devices"
          }

          SectionCard {
            width: parent.width
            bordered: true
            implicitHeight: sinksCol.height + 16

            Column {
              id: sinksCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 8
              spacing: 2

              Repeater {
                model: ScriptModel {
                  values: (root.activeAudio && root.activeAudio.sinks) ? root.activeAudio.sinks : []
                  objectProp: "id"
                  comparisonMode: ObjectComparison.Identity
                }

                delegate: RowBase {
                  id: sinkRow
                  required property var modelData
                  required property int index
                  width: sinksCol.width
                  height: 34
                  rad: Theme.radiusSm
                  onClicked: {
                    if (root.activeAudio) root.activeAudio.setSink(sinkRow.modelData);
                  }

                  readonly property bool isCurrent: root.activeAudio && root.activeAudio.sink && root.activeAudio.sink.id === sinkRow.modelData.id

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                      text: root.deviceIcon(sinkRow.modelData.description || sinkRow.modelData.name, false)
                      font.family: root.t.mono
                      font.pixelSize: Theme.fontLg
                      color: sinkRow.isCurrent ? root.t.accent : root.t.ink3
                    }

                    Text {
                      Layout.fillWidth: true
                      text: sinkRow.modelData.description || sinkRow.modelData.name || "Output"
                      font.pixelSize: Theme.fontBase
                      font.weight: sinkRow.isCurrent ? Font.Medium : Font.Normal
                      color: sinkRow.isCurrent ? root.t.ink1 : root.t.ink2
                      elide: Text.ElideRight
                    }

                    Text {
                      visible: sinkRow.isCurrent
                      text: "󰄬"
                      font.family: root.t.mono
                      font.pixelSize: Theme.fontLg
                      color: root.t.accent
                    }
                  }
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: 6
          visible: (root.activeAudio ? root.activeAudio.sources.length : 0) > 1

          SectionHead {
            label: "Input Devices"
          }

          SectionCard {
            width: parent.width
            bordered: true
            implicitHeight: sourcesCol.height + 16

            Column {
              id: sourcesCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 8
              spacing: 2

              Repeater {
                model: ScriptModel {
                  values: (root.activeAudio && root.activeAudio.sources) ? root.activeAudio.sources : []
                  objectProp: "id"
                  comparisonMode: ObjectComparison.Identity
                }

                delegate: RowBase {
                  id: srcRow
                  required property var modelData
                  required property int index
                  width: sourcesCol.width
                  height: 34
                  rad: Theme.radiusSm
                  onClicked: {
                    if (root.activeAudio) root.activeAudio.setSource(srcRow.modelData);
                  }

                  readonly property bool isCurrent: root.activeAudio && root.activeAudio.source && root.activeAudio.source.id === srcRow.modelData.id

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                      text: root.deviceIcon(srcRow.modelData.description || srcRow.modelData.name, true)
                      font.family: root.t.mono
                      font.pixelSize: Theme.fontLg
                      color: srcRow.isCurrent ? root.t.green : root.t.ink3
                    }

                    Text {
                      Layout.fillWidth: true
                      text: srcRow.modelData.description || srcRow.modelData.name || "Microphone"
                      font.pixelSize: Theme.fontBase
                      font.weight: srcRow.isCurrent ? Font.Medium : Font.Normal
                      color: srcRow.isCurrent ? root.t.ink1 : root.t.ink2
                      elide: Text.ElideRight
                    }

                    Text {
                      visible: srcRow.isCurrent
                      text: "󰄬"
                      font.family: root.t.mono
                      font.pixelSize: Theme.fontLg
                      color: root.t.green
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
