// NetworkSpeed.qml — download / upload speed widget.
// Docs:
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView/ (path, text(), reload(), loaded)
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Networking/NetworkDevice/ (no byte counters, so we read /proc/net/dev)
// - https://quickshell.org/docs/v0.3.1/guide/qml-language/ (implicit imports: this file is auto-available as `NetworkSpeed` in shell.qml)
import QtQuick
import Quickshell.Io

Item {
  id: root

  // Public API
  property int interval: 1000
  property double downloadBps: 0
  property double uploadBps: 0
  readonly property string downloadText: formatSpeed(downloadBps)
  readonly property string uploadText: formatSpeed(uploadBps)
  // Interfaces to ignore (loopback always noise).
  property var ignoredInterfaces: ["lo"]

  // Internal state
  property double _prevRx: -1
  property double _prevTx: -1
  property double _prevTime: -1

  implicitWidth: row.width
  implicitHeight: row.height
  width: implicitWidth
  height: implicitHeight

  function formatSpeed(bps: double): string {
    if (!isFinite(bps) || bps < 0)
      return "0 B/s";
    if (bps < 1024)
      return Math.round(bps) + " B/s";
    if (bps < 1024 * 1024)
      return (bps / 1024).toFixed(1) + " KB/s";
    if (bps < 1024 * 1024 * 1024)
      return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    return (bps / 1024 / 1024 / 1024).toFixed(2) + " GB/s";
  }

  function isIgnored(iface: string): bool {
    return ignoredInterfaces.indexOf(iface) !== -1;
  }

  function updateStats(): void {
    const text = netFile.text();
    if (!text)
      return;

    // Hardcoded primary network interface: enp34s0
    const idx = text.indexOf("enp34s0:");
    if (idx === -1)
      return;
    const lineEnd = text.indexOf("\n", idx);
    const line = (lineEnd !== -1) ? text.slice(idx + 8, lineEnd) : text.slice(idx + 8);
    const fields = line.trim().split(/\s+/);
    if (fields.length < 9)
      return;
    const rx = parseInt(fields[0], 10);
    const tx = parseInt(fields[8], 10);
    if (isNaN(rx) || isNaN(tx))
      return;

    const now = Date.now();
    if (root._prevRx >= 0 && root._prevTime > 0) {
      const dt = (now - root._prevTime) / 1000;
      if (dt > 0) {
        // Counters can wrap / reset (reboot, suspend) — clamp to 0.
        const dRx = rx >= root._prevRx ? rx - root._prevRx : 0;
        const dTx = tx >= root._prevTx ? tx - root._prevTx : 0;
        root.downloadBps = dRx / dt;
        root.uploadBps = dTx / dt;
      }
    }
    root._prevRx = rx;
    root._prevTx = tx;
    root._prevTime = now;
  }

  FileView {
    id: netFile
    path: "/proc/net/dev"
    // `reload()` is async — parse when the new content arrives.
    onLoaded: root.updateStats()
    onLoadFailed: error => console.warn("NetworkSpeed: failed to read /proc/net/dev:", error)
  }

  Timer {
    id: poll
    interval: root.interval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: netFile.reload()
  }

  Row {
    id: row
    spacing: 12

    Text {
      text: "↓ " + root.downloadText
      color: "#a6e3a1"
      font.pixelSize: 12
      font.family: "JetBrainsMono Nerd Font Mono"
    }
    Text {
      text: "↑ " + root.uploadText
      color: "#f9e2af"
      font.pixelSize: 12
      font.family: "JetBrainsMono Nerd Font Mono"
    }
  }
}
