pragma ComponentBehavior: Bound
// widgets/VolumeBarWidget.qml — Compact top bar widget for Volume and PipeWire status.
import QtQuick
import Quickshell
import qs.services
import "../theme"

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

  readonly property real volume: activeAudio ? activeAudio.volume : 0.0
  readonly property bool muted: activeAudio ? activeAudio.muted : false
  readonly property string glyph: activeAudio ? activeAudio.sinkGlyph : "󰕾"
  readonly property int volumePercent: Math.round(volume * 100)

  readonly property bool micMuted: activeAudio ? activeAudio.micMuted : false
  readonly property bool hasMic: activeAudio ? activeAudio.hasSource : false

  implicitWidth: contentRow.width
  implicitHeight: 20
  width: implicitWidth
  height: implicitHeight

  function stepVolume(delta: real): void {
    if (activeAudio) activeAudio.stepVolume(delta);
  }

  function toggleMute(): void {
    if (activeAudio) activeAudio.toggleMute();
  }

  Row {
    id: contentRow
    spacing: 5
    anchors.verticalCenter: parent.verticalCenter

    // Volume icon glyph
    Text {
      id: volIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      font.family: root.monoFont
      font.pixelSize: 13
      color: root.muted ? Theme.ink3 : Theme.ink1

      Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    // Volume percentage
    Text {
      id: volText
      anchors.verticalCenter: parent.verticalCenter
      text: root.muted ? "Muted" : (root.volumePercent + "%")
      font.family: root.monoFont
      font.pixelSize: Theme.fontSm
      font.weight: Font.Medium
      color: root.muted ? Theme.ink3 : Theme.ink2

      Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    // Small subtle indicator if microphone is muted
    Text {
      id: micIcon
      visible: root.hasMic && root.micMuted
      anchors.verticalCenter: parent.verticalCenter
      text: "󰍭"
      font.family: root.monoFont
      font.pixelSize: 11
      color: Theme.err
    }
  }

  WheelHandler {
    id: wheelHandler
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      const delta = event.angleDelta.y > 0 ? 0.05 : -0.05;
      root.stepVolume(delta);
    }
  }
}
