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
    if (root.activeAudio && root.activeAudio.activePort) {
      const curDesc = (root.activeAudio.sinkName || "").toLowerCase();
      if ((desc || "").toLowerCase() === curDesc) {
        const port = (root.activeAudio.activePort || "").toLowerCase();
        if (port.indexOf("headphone") !== -1) return "󰋋";
      }
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

  Component.onCompleted: {
    if (root.activeAudio) root.activeAudio.refreshPorts();
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
        spacing: 14

        PopupHeader {
          width: parent.width
          glyph: root.activeAudio ? root.activeAudio.sinkGlyph : "󰕾"
          glyphColor: (root.activeAudio && root.activeAudio.muted) ? root.t.ink3 : root.t.accent
          title: "Audio"
          subtitle: "Easy Listening"

          IconButton {
            glyph: "󰒓"
            fg: root.t.ink3
            fs: Theme.iconBase
            tooltip: "Audio settings"
            onClicked: root.openAudioSettings()
          }
        }

        Hairline { width: parent.width }

        // Output section
        Column {
          width: parent.width
          spacing: 8

          SectionHeader {
            width: parent.width
            label: "Output"
            valueText: {
              if (!root.activeAudio) return "0%";
              if (root.activeAudio.muted) return "MUTED";
              return Math.round(root.activeAudio.volume * 100) + "%";
            }
            actionGlyph: (root.activeAudio && root.activeAudio.muted) ? "󰝟" : ""
            actionColor: root.t.err
            actionTooltip: "Unmute output"
            onActionClicked: {
              if (root.activeAudio) root.activeAudio.toggleMute();
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

          SegmentedControl {
            id: portSelector
            width: parent.width
            visible: Boolean(root.activeAudio && root.activeAudio.hasMultiplePorts)
            implicitHeight: visible ? 30 : 0
            items: {
              if (!root.activeAudio || !root.activeAudio.sinkPorts) return [];
              const res = [];
              const ports = root.activeAudio.sinkPorts;
              for (let i = 0; i < ports.length; i++) {
                const p = ports[i];
                if (!p) continue;
                const isHp = (p.name || "").indexOf("headphone") !== -1 || (p.description || "").toLowerCase().indexOf("headphone") !== -1;
                res.push({
                  icon: isHp ? "󰋋" : "󰓃",
                  label: p.description || p.name || "Port",
                  portName: p.name
                });
              }
              return res;
            }
            current: {
              if (!root.activeAudio || !root.activeAudio.sinkPorts) return 0;
              const ports = root.activeAudio.sinkPorts;
              for (let i = 0; i < ports.length; i++) {
                if (ports[i] && ports[i].name === root.activeAudio.activePort) {
                  return i;
                }
              }
              return 0;
            }
            onSelected: index => {
              if (portSelector.items && portSelector.items[index] && root.activeAudio) {
                root.activeAudio.setSinkPort(portSelector.items[index].portName);
              }
            }
          }

          Column {
            width: parent.width
            spacing: 2
            visible: (root.activeAudio ? root.activeAudio.sinks.length : 0) > 0

            Repeater {
              model: ScriptModel {
                values: (root.activeAudio && root.activeAudio.sinks) ? root.activeAudio.sinks : []
                objectProp: "id"
                comparisonMode: ObjectComparison.Identity
              }

              delegate: ActionRow {
                id: sinkRow
                required property var modelData
                required property int index
                width: parent.width
                height: 36
                rad: 0
                active: sinkRow.isCurrent
                onClicked: {
                  if (root.activeAudio) root.activeAudio.setSink(sinkRow.modelData);
                }

                readonly property bool isCurrent: root.activeAudio && root.activeAudio.sink && root.activeAudio.sink.id === sinkRow.modelData.id

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  spacing: 10

                  Text {
                    text: root.deviceIcon(sinkRow.modelData.description || sinkRow.modelData.name, false)
                    font.family: root.t.mono
                    font.pixelSize: Theme.fontLg
                    color: sinkRow.isCurrent ? root.t.accent : root.t.ink3
                  }

                  Text {
                    Layout.fillWidth: true
                    text: sinkRow.modelData.description || sinkRow.modelData.name || "Output"
                    font.family: Theme.mono
                    font.pixelSize: Theme.fontBase
                    font.weight: sinkRow.isCurrent ? Font.Medium : Font.Normal
                    color: sinkRow.isCurrent ? root.t.ink1 : root.t.ink2
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: sinkRow.isCurrent
                    text: "✓"
                    font.family: root.t.mono
                    font.pixelSize: Theme.fontBase
                    color: root.t.accent
                  }
                }
              }
            }
          }
        }

        Hairline { width: parent.width; visible: root.activeAudio && root.activeAudio.hasSource }

        // Input section
        Column {
          width: parent.width
          spacing: 8
          visible: root.activeAudio && root.activeAudio.hasSource

          SectionHeader {
            width: parent.width
            label: "Input"
            valueText: {
              if (!root.activeAudio) return "0%";
              if (root.activeAudio.micMuted) return "MUTED";
              return Math.round(root.activeAudio.micVolume * 100) + "%";
            }
            actionGlyph: (root.activeAudio && root.activeAudio.micMuted) ? "󰍭" : ""
            actionColor: root.t.err
            actionTooltip: "Unmute microphone"
            onActionClicked: {
              if (root.activeAudio) root.activeAudio.toggleMicMute();
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

          // Level meter bar beneath input slider
          Rectangle {
            width: parent.width
            height: 3
            radius: 0
            color: root.t.inset
            visible: true

            Rectangle {
              height: parent.height
              radius: 0
              width: root.activeAudio && !root.activeAudio.micMuted ? Math.round(parent.width * Math.min(1.0, root.activeAudio.micVolume * 0.7)) : 0
              color: root.t.tint(root.t.accent, 0.7)
            }
          }

          Column {
            width: parent.width
            spacing: 2
            visible: (root.activeAudio ? root.activeAudio.sources.length : 0) > 0

            Repeater {
              model: ScriptModel {
                values: (root.activeAudio && root.activeAudio.sources) ? root.activeAudio.sources : []
                objectProp: "id"
                comparisonMode: ObjectComparison.Identity
              }

              delegate: ActionRow {
                id: srcRow
                required property var modelData
                required property int index
                width: parent.width
                height: 36
                rad: 0
                active: srcRow.isCurrent
                onClicked: {
                  if (root.activeAudio) root.activeAudio.setSource(srcRow.modelData);
                }

                readonly property bool isCurrent: root.activeAudio && root.activeAudio.source && root.activeAudio.source.id === srcRow.modelData.id

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  spacing: 10

                  Text {
                    text: root.deviceIcon(srcRow.modelData.description || srcRow.modelData.name, true)
                    font.family: root.t.mono
                    font.pixelSize: Theme.fontLg
                    color: srcRow.isCurrent ? root.t.green : root.t.ink3
                  }

                  Text {
                    Layout.fillWidth: true
                    text: srcRow.modelData.description || srcRow.modelData.name || "Microphone"
                    font.family: Theme.mono
                    font.pixelSize: Theme.fontBase
                    font.weight: srcRow.isCurrent ? Font.Medium : Font.Normal
                    color: srcRow.isCurrent ? root.t.ink1 : root.t.ink2
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: srcRow.isCurrent
                    text: "✓"
                    font.family: root.t.mono
                    font.pixelSize: Theme.fontBase
                    color: root.t.green
                  }
                }
              }
            }
          }
        }

        Hairline {
          width: parent.width
          visible: Boolean(root.activeAudio && root.activeAudio.streams && root.activeAudio.streams.length > 0)
        }

        // Applications section
        Column {
          width: parent.width
          spacing: 8
          visible: Boolean(root.activeAudio && root.activeAudio.streams && root.activeAudio.streams.length > 0)

          SectionHeader {
            label: "Applications"
          }

          Column {
            width: parent.width
            spacing: 8

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
                width: parent.width
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
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontBase
                      font.weight: Font.Medium
                      color: root.t.ink1
                      elide: Text.ElideRight
                    }

                    Text {
                      visible: text.length > 0
                      text: root.activeAudio ? root.activeAudio.streamDescription(streamItem.modelData) : ""
                      font.family: Theme.mono
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

                  IconButton {
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
    }
  }
}
