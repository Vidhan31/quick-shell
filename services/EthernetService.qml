pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Plugins.Ethernet

Item {
  id: root

  property int pollInterval: 2500
  property alias throughputTracking: monitor.throughputTracking

  EthernetMonitor {
    id: monitor
    running: true
    interval: root.pollInterval
  }

  readonly property alias monitor: monitor
  readonly property var ethData: monitor.ethData
  readonly property bool isBusy: monitor.isBusy
  readonly property bool ok: monitor.ok
  readonly property bool carrier: monitor.carrier
  readonly property bool hasInternet: monitor.hasInternet
  readonly property string currentStatus: monitor.currentStatus
  readonly property string statusDesc: monitor.statusDesc
  readonly property string interfaceName: monitor.interfaceName
  readonly property var interfaces: monitor.interfaces
  readonly property string connectionName: monitor.connectionName
  readonly property string ip: monitor.ip
  readonly property string ipv6: monitor.ipv6
  readonly property string gateway: monitor.gateway
  readonly property var dns: monitor.dns
  readonly property string speedLabel: monitor.speedLabel
  readonly property int speedMbps: monitor.speedMbps
  readonly property string hwAddress: monitor.hwAddress

  readonly property double downloadBps: monitor.downloadBps
  readonly property double uploadBps: monitor.uploadBps
  readonly property string downloadSpeedLabel: formatSpeed(downloadBps)
  readonly property string uploadSpeedLabel: formatSpeed(uploadBps)
  readonly property bool isPinging: monitor.isPinging
  readonly property double pingLatency: monitor.pingLatency
  readonly property string pingResult: monitor.pingResult

  function formatSpeed(bps: double): string {
    if (!isFinite(bps) || bps < 0) return "0 B/s";
    if (bps < 1024) return Math.round(bps) + " B/s";
    if (bps < 1024 * 1024) return (bps / 1024).toFixed(1) + " KB/s";
    if (bps < 1024 * 1024 * 1024) return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    return (bps / 1024 / 1024 / 1024).toFixed(2) + " GB/s";
  }

  function refresh(): void {
    monitor.refresh();
  }

  function runPing(target: string): void {
    monitor.runPing(target);
  }

  function runCheck(): void {
    monitor.runCheck();
  }

  function reconnect(iface: string): void {
    monitor.reconnect(iface);
  }

  function openSettings(): void {
    monitor.openSettings();
  }

  Component.onCompleted: root.refresh()
}
