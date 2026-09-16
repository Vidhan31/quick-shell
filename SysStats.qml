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

  function updateCpu(): void {
    const text = statFile.text();
    if (!text)
      return;
    const line = text.split("\n")[0];
    if (!line || line.slice(0, 3) !== "cpu")
      return;
    const fields = line.trim().split(/\s+/).slice(1).map(x => parseInt(x, 10));
    if (fields.length < 4 || fields.some(x => isNaN(x)))
      return;
    let total = 0;
    for (let i = 0; i < fields.length; ++i)
      total += fields[i];
    const idle = fields[3] + (fields.length > 4 ? fields[4] : 0);
    if (root._prevTotal >= 0) {
      const dTotal = total - root._prevTotal;
      const dIdle = idle - root._prevIdle;
      if (dTotal > 0)
        root.cpuPercent = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)));
    }
    root._prevTotal = total;
    root._prevIdle = idle;
  }

  function updateMem(): void {
    const text = memFile.text();
    if (!text)
      return;
    let total = -1;
    let avail = -1;
    let free = -1;
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; ++i) {
      const parts = lines[i].split(":");
      if (parts.length !== 2)
        continue;
      const key = parts[0].trim();
      const val = parseInt(parts[1].trim().split(/\s+/)[0], 10);
      if (isNaN(val))
        continue;
      if (key === "MemTotal")
        total = val;
      else if (key === "MemAvailable")
        avail = val;
      else if (key === "MemFree")
        free = val;
    }
    if (total <= 0)
      return;
    // Prefer MemAvailable (accounts for cache/buffers); fall back to MemFree.
    const freeKb = avail >= 0 ? avail : free;
    if (freeKb < 0)
      return;
    root.memPercent = Math.max(0, Math.min(100, 100 * (total - freeKb) / total));
  }

  function updateGpu(text: string): void {
    if (!text)
      return;
    const v = parseInt(text.trim().split("\n")[0].trim(), 10);
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

  // GPU: AMD/Intel via sysfs, NVIDIA via nvidia-smi — first hit wins.
  Process {
    id: gpuProc
    command: ["sh", "-c", "cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1; nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1"]
    stdout: StdioCollector {
      onStreamFinished: root.updateGpu(text)
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
    }
  }

  Timer {
    id: gpuPoll
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!gpuProc.running)
        gpuProc.running = true;
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
