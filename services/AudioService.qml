pragma ComponentBehavior: Bound
// AudioService.qml — Audio state adapter over Quickshell.Services.Pipewire.
//
// Manages system master sink (output), master source (input / mic),
// device switching, and per-application audio streams.
// Uses PwObjectTracker to bind nodes so volume, mute, and properties stay reactive.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Item {
  id: root

  readonly property bool ready: Pipewire.ready

  // Active default sink and source
  readonly property PwNode sink: Pipewire.defaultAudioSink
  readonly property PwNode source: Pipewire.defaultAudioSource

  readonly property bool hasSink: root.sink !== null && root.sink.audio !== null
  readonly property bool hasSource: root.source !== null && root.source.audio !== null

  // All nodes from PipeWire graph
  readonly property var allNodes: Pipewire.nodes.values

  // Streams: application playback audio streams (Brave, Spotify, Discord, etc.)
  readonly property var streams: {
    const res = [];
    const list = root.allNodes;
    for (let i = 0; i < list.length; i++) {
      const n = list[i];
      if (n && n.audio && n.isStream && n.isSink) {
        res.push(n);
      }
    }
    return res;
  }

  // Keep active sink, source, and all app streams bound so audio properties stay valid
  PwObjectTracker {
    objects: {
      const objs = [];
      if (root.sink) objs.push(root.sink);
      if (root.source) objs.push(root.source);
      const strList = root.streams;
      for (let i = 0; i < strList.length; i++) {
        if (strList[i]) objs.push(strList[i]);
      }
      return objs;
    }
  }

  // Master output properties
  readonly property real volume: (root.hasSink && root.sink.audio) ? root.sink.audio.volume : 0.0
  readonly property bool muted: (root.hasSink && root.sink.audio) ? root.sink.audio.muted : false
  readonly property string sinkName: {
    if (!root.sink) return "No Output";
    return root.sink.description || root.sink.nickname || root.sink.name || "Default Output";
  }

  // Output glyph based on volume and mute
  readonly property string sinkGlyph: {
    if (!root.hasSink || root.muted || root.volume <= 0.001) return "󰝟";
    if (root.volume < 0.33) return "󰕿";
    if (root.volume < 0.66) return "󰖀";
    return "󰕾";
  }

  // Master input (microphone) properties
  readonly property real micVolume: (root.hasSource && root.source.audio) ? root.source.audio.volume : 0.0
  readonly property bool micMuted: (root.hasSource && root.source.audio) ? root.source.audio.muted : false
  readonly property string sourceName: {
    if (!root.source) return "No Microphone";
    return root.source.description || root.source.nickname || root.source.name || "Default Microphone";
  }

  readonly property string micGlyph: {
    if (!root.hasSource || root.micMuted) return "󰍭";
    return "󰍬";
  }

  // Controls
  function setVolume(val: real): void {
    if (root.hasSink && root.sink.audio) {
      root.sink.audio.volume = Math.max(0.0, Math.min(1.5, Math.round(val * 100) / 100));
    }
  }

  function stepVolume(delta: real): void {
    if (root.hasSink && root.sink.audio) {
      // If unmuting when raising volume
      if (delta > 0 && root.sink.audio.muted) {
        root.sink.audio.muted = false;
      }
      setVolume(root.sink.audio.volume + delta);
    }
  }

  function toggleMute(): void {
    if (root.hasSink && root.sink.audio) {
      root.sink.audio.muted = !root.sink.audio.muted;
    }
  }

  function setMicVolume(val: real): void {
    if (root.hasSource && root.source.audio) {
      root.source.audio.volume = Math.max(0.0, Math.min(1.0, Math.round(val * 100) / 100));
    }
  }

  function stepMicVolume(delta: real): void {
    if (root.hasSource && root.source.audio) {
      if (delta > 0 && root.source.audio.muted) {
        root.source.audio.muted = false;
      }
      setMicVolume(root.source.audio.volume + delta);
    }
  }

  function toggleMicMute(): void {
    if (root.hasSource && root.source.audio) {
      root.source.audio.muted = !root.source.audio.muted;
    }
  }

  function setStreamVolume(node: PwNode, val: real): void {
    if (node && node.audio) {
      node.audio.volume = Math.max(0.0, Math.min(1.5, Math.round(val * 100) / 100));
    }
  }

  function toggleStreamMute(node: PwNode): void {
    if (node && node.audio) {
      node.audio.muted = !node.audio.muted;
    }
  }

  function streamAppName(node: PwNode): string {
    if (!node) return "Unknown";
    const props = node.properties || {};
    return props["application.name"] || props["media.name"] || node.description || node.name || "App";
  }

  function streamDescription(node: PwNode): string {
    if (!node) return "";
    const props = node.properties || {};
    return props["media.title"] || props["media.name"] || "";
  }

  function streamIconName(node: PwNode): string {
    if (!node) return "audio-volume-high";
    const props = node.properties || {};
    return props["application.icon-name"] || "audio-volume-high";
  }
}
