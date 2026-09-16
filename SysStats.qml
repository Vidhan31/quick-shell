// SysStats.qml — CPU / MEM / GPU usage widget with Nerd Font icons + %.
// Docs:
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView/ (path, text(), reload(), loaded)
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/ (command, running, stdout for GPU fallback)
// - https://quickshell.org/docs/v0.3.1/guide/qml-language/ (implicit import as `SysStats`)
import QtQuick
import Quickshell.Io

Item {
  id: root

  property int interval: 1000
  property double cpuPercent: 0
  property double memPercent: 0
  property double gpuPercent: 0
  property bool gpuAvailable: true

  // Internal CPU delta state
  property double _prevTotal: -1
  property double _prevIdle: -1

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"
  readonly property int valuePixelSize: 13

  implicitWidth: row.width
  implicitHeight: row.height
  width: implicitWidth
  height: implicitHeight

  // System specs: AMD Ryzen 3600 (12 threads), 16GB RAM (16284056 kB)
  readonly property double totalMemKb: 16284056

  function updateCpu(): void {
    const text = statFile.text();
    if (!text)
      return;
    const nl = text.indexOf("\n");
    const line = (nl !== -1) ? text.slice(0, nl) : text;
    if (line.length < 4 || line.charCodeAt(0) !== 99 /* 'c' */)
      return;
    const fields = line.trim().split(/\s+/);
    if (fields.length < 6)
      return;
    const user = parseInt(fields[1], 10);
    const nice = parseInt(fields[2], 10);
    const sys = parseInt(fields[3], 10);
    const idle = parseInt(fields[4], 10);
    const iowait = parseInt(fields[5], 10) || 0;
    const total = user + nice + sys + idle + iowait + (parseInt(fields[6], 10) || 0) + (parseInt(fields[7], 10) || 0) + (parseInt(fields[8], 10) || 0);
    const idleTotal = idle + iowait;
    if (root._prevTotal >= 0) {
      const dTotal = total - root._prevTotal;
      const dIdle = idleTotal - root._prevIdle;
      if (dTotal > 0)
        root.cpuPercent = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)));
    }
    root._prevTotal = total;
    root._prevIdle = idleTotal;
  }

  function updateMem(): void {
    const text = memFile.text();
    if (!text)
      return;
    const idx = text.indexOf("MemAvailable:");
    if (idx === -1)
      return;
    const availKb = parseInt(text.slice(idx + 13), 10);
    if (isNaN(availKb) || availKb < 0)
      return;
    root.memPercent = Math.max(0, Math.min(100, 100 * (root.totalMemKb - availKb) / root.totalMemKb));
  }

  function updateGpu(): void {
    const text = gpuFile.text();
    if (!text)
      return;
    const v = parseInt(text.trim(), 10);
    if (isNaN(v))
      return;
    root.gpuPercent = Math.max(0, Math.min(100, v));
    root.gpuAvailable = true;
  }

  FileView {
    id: statFile
    path: "/proc/stat"
    onLoaded: root.updateCpu()
    onLoadFailed: error => console.warn("SysStats: failed to read /proc/stat:", error)
  }

  FileView {
    id: memFile
    path: "/proc/meminfo"
    onLoaded: root.updateMem()
    onLoadFailed: error => console.warn("SysStats: failed to read /proc/meminfo:", error)
  }

  FileView {
    id: gpuFile
    path: "/sys/class/drm/card1/device/gpu_busy_percent"
    onLoaded: root.updateGpu()
    onLoadFailed: error => {
      root.gpuAvailable = false;
      console.warn("SysStats: failed to read GPU busy percent:", error);
    }
  }

  Timer {
    id: poll
    interval: root.interval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      statFile.reload();
      memFile.reload();
      if (root.gpuAvailable)
        gpuFile.reload();
    }
  }

  Row {
    id: row
    spacing: 8

    Text {
      width: 32
      horizontalAlignment: Text.AlignHCenter
      text: Math.round(root.cpuPercent) + "%"
      color: "#89b4fa"
      font.pixelSize: root.valuePixelSize
      font.family: root.monoFont
    }
    Text {
      width: 32
      horizontalAlignment: Text.AlignHCenter
      text: Math.round(root.memPercent) + "%"
      color: "#cba6f7"
      font.pixelSize: root.valuePixelSize
      font.family: root.monoFont
    }
    Text {
      visible: root.gpuAvailable
      width: visible ? 32 : 0
      horizontalAlignment: Text.AlignHCenter
      text: Math.round(root.gpuPercent) + "%"
      color: "#fab387"
      font.pixelSize: root.valuePixelSize
      font.family: root.monoFont
    }
  }
}
