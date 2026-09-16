// TopProcesses.qml — top 10 processes by memory with proportional MEM bar + CPU.
// Docs:
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/ (command, running, stdout)
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/StdioCollector/ (onStreamFinished -> text)
// - https://quickshell.org/docs/v0.3.1/guide/qml-language/ (implicit import as `TopProcesses`)
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
  id: root

  property int interval: 2000
  property var processes: []
  property double maxMem: 1
  property string updatedAt: ""

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  implicitWidth: 412
  implicitHeight: 480

  function formatRss(kb: double): string {
    if (!isFinite(kb) || kb <= 0)
      return "0K";
    if (kb < 1024)
      return Math.round(kb) + "K";
    if (kb < 1024 * 1024)
      return (kb / 1024).toFixed(1) + "M";
    return (kb / 1024 / 1024).toFixed(2) + "G";
  }

  // Sampler output (tab-separated): NAME\tMEM%\tCPU%\tRSS_KB\tCOUNT\tMAINPID
  // MEM/RSS are instantaneous; CPU is a live 1s delta sample (ps %CPU is a
  // lifetime average and looks frozen, which is why we sample /proc ourselves).
  // MAINPID = pid with the largest RSS inside the group.
  function parsePs(text: string): void {
    if (!text)
      return;
    const lines = text.trim().split("\n");
    const out = [];
    for (let i = 0; i < lines.length; ++i) {
      const parts = lines[i].split("\t");
      if (parts.length < 6 || !parts[0])
        continue;
      const mem = parseFloat(parts[1]);
      const cpu = parseFloat(parts[2]);
      const rss = parseInt(parts[3], 10);
      const count = parseInt(parts[4], 10);
      const mpid = parseInt(parts[5], 10);
      if (isNaN(mem) || isNaN(cpu) || isNaN(rss))
        continue;
      out.push({
        name: parts[0],
        mem: mem,
        cpu: cpu,
        rss: rss,
        count: isNaN(count) ? 1 : count,
        mpid: isNaN(mpid) ? 0 : mpid
      });
    }
    out.sort((a, b) => b.mem - a.mem);
    const top = out.slice(0, 10);
    root.processes = top;
    root.maxMem = top.length > 0 && top[0].mem > 0 ? top[0].mem : 1;
    root.updatedAt = Qt.formatTime(new Date(), "hh:mm:ss");
  }

  Process {
    id: psProc
    command: ["sh", "-c", "{ grep MemTotal /proc/meminfo; echo @@CPU1; grep '^cpu ' /proc/stat; echo @@P1; cat /proc/[0-9]*/stat 2>/dev/null; sleep 1; echo @@CPU2; grep '^cpu ' /proc/stat; echo @@P2; cat /proc/[0-9]*/stat 2>/dev/null; } | awk -v NCPU=$(nproc) -v PAGEKB=$(($(getconf PAGESIZE)/1024)) 'BEGIN { phase=0 } /^@@CPU1$/ { phase=1; next } /^@@P1$/ { phase=2; next } /^@@CPU2$/ { phase=3; next } /^@@P2$/ { phase=4; next } phase==0 && /^MemTotal:/ { MEMKB=$2; next } phase==1 && /^cpu / { T1=$2+$3+$4+$5+$6+$7+$8; next } phase==3 && /^cpu / { T2=$2+$3+$4+$5+$6+$7+$8; next } phase==2 { pid=$1+0; if (match($0, /\\(.*\\)/)) { rest=substr($0, RSTART+RLENGTH+1); split(rest, f, \" \"); J1[pid]=f[12]+f[13]; } next } phase==4 { pid=$1+0; if (match($0, /\\(.*\\)/)) { comm=substr($0, RSTART+1, RLENGTH-2); rest=substr($0, RSTART+RLENGTH+1); split(rest, f, \" \"); P[pid]=f[2]+0; C[pid]=comm; t=f[12]+f[13]; CPUD[pid]=(pid in J1)?(t-J1[pid]):0; MEM[pid]=realmem(pid, f[22]); } next } function realmem(pid, rss_pages, f2, line, a, n, pss, priv, hp) { pid=pid+0; f2=\"/proc/\" pid \"/smaps_rollup\"; pss=-1; priv=0; hp=0; while ((getline line < f2) > 0) { n=split(line, a, \" \"); if (a[1] == \"Pss:\") pss=a[2]+0; else if (a[1] == \"Private_Clean:\" || a[1] == \"Private_Dirty:\") { priv+=a[2]; hp=1; } } close(f2); if (pss >= 0) return pss; if (hp) return priv+0; return rss_pages*PAGEKB; } function get_root(p, curr, par, visited) { curr=p; visited[curr]=1; while ((curr in P) && P[curr]>1 && C[P[curr]]!=\"systemd\") { par=P[curr]; if (par in visited) break; if (C[par] ~ /^(bash|zsh|fish|sh)$/) break; curr=par; visited[curr]=1; } return curr; } END { DT=T2-T1; if (DT<=0) DT=1; for (p in P) { r=get_root(p); RSS[r]+=MEM[p]; DC[r]+=CPUD[p]; CNT[r]++; if (!(r in MRSS) || MEM[p]>MRSS[r]) { MRSS[r]=MEM[p]; MNAME[r]=C[p]; MPID[r]=p; } } for (r in RSS) { mem=100*RSS[r]/MEMKB; cpu=100*(DC[r]+0)*NCPU/DT; printf \"%s\\t%.2f\\t%.1f\\t%d\\t%d\\t%d\\n\", MNAME[r], mem, cpu, RSS[r], CNT[r], MPID[r]; } }'"]
    stdout: StdioCollector {
      onStreamFinished: root.parsePs(text)
    }
    onExited: error => {
      if (error !== 0)
        console.warn("TopProcesses: ps exited with", error);
    }
  }

  Timer {
    id: poll
    interval: root.interval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!psProc.running)
        psProc.running = true;
    }
  }

  Rectangle {
    id: card
    anchors.fill: parent
    radius: 16
    color: "#1e1e2e"
    border.color: "#313244"
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 6

      // Header: title on left, live Network Speed on right
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 22

        Text {
          text: "Top Processes"
          color: "#cdd6f4"
          font.family: root.monoFont
          font.pixelSize: 12
          font.bold: true
        }

        Item { Layout.fillWidth: true }

        NetworkSpeed {
          Layout.alignment: Qt.AlignVCenter
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: "#313244"
      }

      // Rows — plain Items with anchors (no nested layouts: deterministic, no overlap)
      Repeater {
        model: root.processes
        delegate: Item {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          Layout.preferredHeight: 36

          // Left: grouped name + count on top, main pid below (no serial numbers)
          Item {
            id: leftCell
            anchors {
              left: parent.left
              top: parent.top
              bottom: parent.bottom
            }
            width: 150
            Text {
              anchors {
                left: parent.left
                right: parent.right
                top: parent.top
              }
              text: modelData.name + (modelData.count > 1 ? " ×" + modelData.count : "")
              elide: Text.ElideRight
              maximumLineCount: 1
              color: index === 0 ? "#f38ba8" : "#cdd6f4"
              font.family: root.monoFont
              font.pixelSize: 12
            }
            Text {
              anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
              }
              text: modelData.mpid
              elide: Text.ElideRight
              maximumLineCount: 1
              color: "#6c7086"
              font.family: root.monoFont
              font.pixelSize: 10
            }
          }

          // Proportional MEM bar with combined RSS + MEM% label, e.g. 3.00G (18%)
          Item {
            anchors {
              left: leftCell.right
              right: parent.right
              verticalCenter: parent.verticalCenter
              leftMargin: 8
            }
            height: 18
            readonly property string barLabel: root.formatRss(modelData.rss) + " (" + modelData.mem.toFixed(0) + "%)"
            readonly property double fillFrac: Math.min(1, modelData.mem / root.maxMem)
            Rectangle {
              anchors.fill: parent
              radius: 4
              color: "#313244"
            }
            Rectangle {
              height: parent.height
              radius: 4
              width: parent.width * parent.fillFrac
              color: index === 0 ? "#f38ba8" : "#89b4fa"
              opacity: 0.85
            }
            // Dark label on the fill (only when it fits), else light label
            // pinned to the empty track area — always exactly one is visible.
            Text {
              anchors.left: parent.left
              anchors.leftMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              text: parent.barLabel
              color: "#11111b"
              font.family: root.monoFont
              font.pixelSize: 11
              font.bold: true
              visible: (parent.width * parent.fillFrac) > 92
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: parent.barLabel
              color: "#a6adc8"
              font.family: root.monoFont
              font.pixelSize: 11
              visible: (parent.width * parent.fillFrac) <= 92
            }
          }
        }
      }

      // Empty state (first poll)
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: root.processes.length === 0
        text: "󰑓 loading…"
        color: "#6c7086"
        font.family: root.monoFont
        font.pixelSize: 12
      }
    }
  }
}
