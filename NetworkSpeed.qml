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

    const lines = text.split("\n");
    let rx = 0;
    let tx = 0;
    // Skip 2 header lines of /proc/net/dev.
    for (let i = 2; i < lines.length; ++i) {
      const line = lines[i].trim();
      if (!line)
        continue;
      const parts = line.split(":");
      if (parts.length !== 2)
        continue;
      const iface = parts[0].trim();
      if (root.isIgnored(iface))
        continue;
      const fields = parts[1].trim().split(/\s+/);
      // rx_bytes = fields[0], tx_bytes = fields[8]
      if (fields.length < 9)
        continue;
      const r = parseInt(fields[0], 10);
      const t = parseInt(fields[8], 10);
      if (isNaN(r) || isNaN(t))
        continue;
      rx += r;
      tx += t;
    }

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
