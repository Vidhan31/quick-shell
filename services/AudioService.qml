pragma ComponentBehavior: Bound
// Uses PwObjectTracker to bind nodes so volume, mute, and properties stay reactive.
import QtQuick
import Quickshell.Services.Pipewire
import Quickshell.Io

Item {
  id: root

  readonly property bool ready: Pipewire.ready
  onReadyChanged: {
    if (root.ready) root.refreshPorts();
  }

  Component.onCompleted: {
    root.refreshPorts();
  }

  readonly property PwNode sink: Pipewire.defaultAudioSink
  onSinkChanged: root.refreshPorts()

  readonly property PwNode source: Pipewire.defaultAudioSource

  property var sinkPorts: []
  property string activePort: ""
  readonly property bool hasMultiplePorts: root.sinkPorts.length > 1

  readonly property string activePortDescription: {
    const list = root.sinkPorts;
    for (let i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === root.activePort) {
        return list[i].description || list[i].name;
      }
    }
    return "";
  }

  readonly property bool hasSink: root.sink !== null && root.sink.audio !== null
  readonly property bool hasSource: root.source !== null && root.source.audio !== null

  readonly property var allNodes: Pipewire.nodes.values

  readonly property var sinks: {
    const res = [];
    const list = root.allNodes;
    for (let i = 0; i < list.length; i++) {
      const n = list[i];
      if (n && n.audio && n.isSink && !n.isStream) {
        res.push(n);
      }
    }
    return res;
  }

  readonly property var sources: {
    const res = [];
    const list = root.allNodes;
    for (let i = 0; i < list.length; i++) {
      const n = list[i];
      if (n && n.audio && !n.isSink && !n.isStream) {
        res.push(n);
      }
    }
    return res;
  }

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

  readonly property real volume: (root.hasSink && root.sink.audio) ? root.sink.audio.volume : 0.0
  readonly property bool muted: (root.hasSink && root.sink.audio) ? root.sink.audio.muted : false
  readonly property string sinkName: {
    if (!root.sink) return "No Output";
    return root.sink.description || root.sink.nickname || root.sink.name || "Default Output";
  }

  readonly property string sinkGlyph: {
    if (!root.hasSink || root.muted || root.volume <= 0.001) return "󰝟";
    const port = root.activePort.toLowerCase();
    const portDesc = root.activePortDescription.toLowerCase();
    if (port.indexOf("headphone") !== -1 || portDesc.indexOf("headphone") !== -1) {
      return "󰋋";
    }
    if (root.volume < 0.33) return "󰕿";
    if (root.volume < 0.66) return "󰖀";
    return "󰕾";
  }

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

  function setVolume(val: real): void {
    if (root.hasSink && root.sink.audio) {
      root.sink.audio.volume = Math.max(0.0, Math.min(1.5, Math.round(val * 100) / 100));
    }
  }

  function stepVolume(delta: real): void {
    if (root.hasSink && root.sink.audio) {
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

  function setSink(node: PwNode): void {
    if (node) {
      Pipewire.preferredDefaultAudioSink = node;
    }
  }

  function setSource(node: PwNode): void {
    if (node) {
      Pipewire.preferredDefaultAudioSource = node;
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

  Process {
    id: pactlListProc
    command: ["pactl", "-f", "json", "list", "sinks"]
    stdout: StdioCollector {
      id: listCollector
      onStreamFinished: {
        if (listCollector.text.length > 0) {
          root._parseSinksJson(listCollector.text);
        }
      }
    }
  }

  Process {
    id: pactlSetProc
    property bool _setPending: false
    onRunningChanged: {
      if (!running && _setPending) {
        _setPending = false;
        root.refreshPorts();
      }
    }
  }

  function _parseSinksJson(jsonStr: string): void {
    try {
      const sinks = JSON.parse(jsonStr);
      if (!Array.isArray(sinks)) return;
      const curSinkName = root.sink ? root.sink.name : "";
      let targetSink = null;
      for (let i = 0; i < sinks.length; i++) {
        const s = sinks[i];
        if (curSinkName.length > 0 && s && s.name === curSinkName) {
          targetSink = s;
          break;
        }
      }
      if (!targetSink && sinks.length > 0) {
        targetSink = sinks[0];
      }
      if (targetSink && Array.isArray(targetSink.ports)) {
        root.activePort = targetSink.active_port || "";
        root.sinkPorts = targetSink.ports;
      } else {
        root.activePort = "";
        root.sinkPorts = [];
      }
    } catch (e) {
      root.activePort = "";
      root.sinkPorts = [];
    }
  }

  function refreshPorts(): void {
    pactlListProc.running = false;
    pactlListProc.running = true;
  }

  function setSinkPort(portName: string): void {
    if (!portName || portName.length === 0) return;
    root.activePort = portName;
    const target = root.sink ? root.sink.name : "@DEFAULT_SINK@";
    pactlSetProc.command = ["pactl", "set-sink-port", target, portName];
    pactlSetProc._setPending = true;
    pactlSetProc.running = false;
    pactlSetProc.running = true;
  }

  function toggleOutputPort(): void {
    if (root.sinkPorts && root.sinkPorts.length >= 2) {
      let hpPort = "";
      let linePort = "";
      for (let i = 0; i < root.sinkPorts.length; i++) {
        const p = root.sinkPorts[i];
        if (!p) continue;
        const nameLower = (p.name || "").toLowerCase();
        const descLower = (p.description || "").toLowerCase();
        if (nameLower.indexOf("headphone") !== -1 || descLower.indexOf("headphone") !== -1) {
          hpPort = p.name;
        } else if (nameLower.indexOf("line") !== -1 || descLower.indexOf("line") !== -1) {
          linePort = p.name;
        }
      }

      if (hpPort.length > 0 && linePort.length > 0) {
        if (root.activePort === hpPort) {
          root.setSinkPort(linePort);
        } else {
          root.setSinkPort(hpPort);
        }
        return;
      }

      let curIdx = -1;
      for (let i = 0; i < root.sinkPorts.length; i++) {
        if (root.sinkPorts[i] && root.sinkPorts[i].name === root.activePort) {
          curIdx = i;
          break;
        }
      }
      const nextIdx = (curIdx + 1) % root.sinkPorts.length;
      root.setSinkPort(root.sinkPorts[nextIdx].name);
      return;
    }

    if (root.sinks && root.sinks.length >= 2) {
      let hpSink = null;
      let otherSink = null;
      for (let i = 0; i < root.sinks.length; i++) {
        const s = root.sinks[i];
        if (!s) continue;
        const dLower = (s.description || s.name || "").toLowerCase();
        if (dLower.indexOf("headphone") !== -1 || dLower.indexOf("headset") !== -1) {
          hpSink = s;
        } else if (!otherSink) {
          otherSink = s;
        }
      }
      if (hpSink && otherSink) {
        if (root.sink && root.sink.id === hpSink.id) {
          root.setSink(otherSink);
        } else {
          root.setSink(hpSink);
        }
        return;
      }
      let curSinkIdx = -1;
      for (let i = 0; i < root.sinks.length; i++) {
        if (root.sink && root.sinks[i] && root.sinks[i].id === root.sink.id) {
          curSinkIdx = i;
          break;
        }
      }
      const nextSinkIdx = (curSinkIdx + 1) % root.sinks.length;
      root.setSink(root.sinks[nextSinkIdx]);
      return;
    }

    root.refreshPorts();
  }
}
