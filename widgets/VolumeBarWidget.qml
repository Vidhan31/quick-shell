pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import "../theme"

Item {
  id: root

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  property var audio: null
  readonly property var activeAudio: root.audio

  readonly property var t: Theme
  readonly property string monoFont: Theme.mono

  readonly property real volume: activeAudio ? activeAudio.volume : 0.0
  readonly property bool muted: activeAudio ? activeAudio.muted : false
  readonly property string glyph: activeAudio ? activeAudio.sinkGlyph : "󰕾"
  readonly property int volumePercent: Math.round(volume * 100)

  readonly property bool micMuted: activeAudio ? activeAudio.micMuted : false
  readonly property bool hasMic: activeAudio ? activeAudio.hasSource : false

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

    Text {
      id: volIcon
      anchors.verticalCenter: parent.verticalCenter
      text: root.muted ? "󰝟" : root.glyph
      font.family: root.monoFont
      font.pixelSize: Theme.iconMd
      color: root.muted ? Theme.err : (root.volumePercent > 100 ? Theme.warn : Theme.ink1)

      Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    Text {
      id: volText
      visible: !root.muted
      anchors.verticalCenter: parent.verticalCenter
      text: root.volumePercent + "%"
      font.family: Theme.roundedFont
      font.pixelSize: Theme.fontSm
      font.weight: Font.DemiBold
      color: Theme.ink2

      Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    Text {
      id: micIcon
      visible: root.hasMic && root.micMuted
      anchors.verticalCenter: parent.verticalCenter
      text: "󰍭"
      font.family: root.monoFont
      font.pixelSize: Theme.iconMd
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
