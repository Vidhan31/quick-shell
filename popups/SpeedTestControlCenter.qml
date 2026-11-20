pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"

Item {
  id: root

  implicitWidth: Theme.popupWidthLg
  implicitHeight: 520

  readonly property string downloadUrl: "https://speed.cloudflare.com/__down"
  readonly property string uploadUrl: "https://speed.cloudflare.com/__up"
  readonly property int phaseDurationMs: 20000

  property bool running: false
  property bool hasResult: false
  property string phase: "idle"
  property string statusText: "Ready when you are"
  property string downloadText: "—"
  property string uploadText: "—"
  property string latencyText: "—"
  property string currentSpeedText: "—"
  property real phaseProgress: 0
  property real phaseStartedAt: 0
  property int phaseElapsedMs: 0
  property int bytesTransferred: 0
  property int nextChunkBytes: 16384
  property var activeRequest: null
  property var uploadPayload: null

  readonly property color phaseColor: phase === "download" ? Theme.green : (phase === "upload" ? Theme.accent : Theme.ink3)
  readonly property string phaseLabel: phase === "download" ? "Download" : (phase === "upload" ? "Upload" : (hasResult ? "Test complete" : "Ready"))
  readonly property string elapsedLabel: Math.min(20, Math.floor(phaseElapsedMs / 1000)) + " / 20 seconds"

  function startTest(): void {
    if (root.running) return;
    root.running = true;
    root.hasResult = false;
    root.phase = "latency";
    root.phaseProgress = 0;
    root.phaseElapsedMs = 0;
    root.currentSpeedText = "0.0";
    root.downloadText = "—";
    root.uploadText = "—";
    root.latencyText = "—";
    root.statusText = "Checking latency…";

    const startedAt = Date.now();
    root.issueRequest("GET", root.downloadUrl + "?bytes=0&nonce=" + startedAt, null, "", function() {
      root.latencyText = Date.now() - startedAt + " ms";
      root.beginPhase("download");
    });
  }

  function cancelTest(): void {
    if (!root.running) return;
    requestTimeout.stop();
    phaseClock.stop();
    const request = root.activeRequest;
    root.activeRequest = null;
    if (request) request.abort();
    root.running = false;
    root.phase = "cancelled";
    root.statusText = "Test cancelled";
  }

  function failTest(message: string): void {
    requestTimeout.stop();
    phaseClock.stop();
    const request = root.activeRequest;
    root.activeRequest = null;
    if (request) request.abort();
    root.running = false;
    root.phase = "failed";
    root.statusText = message;
  }

  function formatMbps(bytes: int, elapsedMs: int): string {
    if (elapsedMs <= 0) return "0.0";
    return (bytes * 8 / elapsedMs / 1000).toFixed(1);
  }

  function issueRequest(method: string, url: string, body: var, responseType: string, onComplete: var): void {
    const request = new XMLHttpRequest();
    root.activeRequest = request;
    if (responseType.length > 0) request.responseType = responseType;
    request.onreadystatechange = function() {
      if (request.readyState !== XMLHttpRequest.DONE) return;
      requestTimeout.stop();
      root.activeRequest = null;
      if (request.status < 200 || request.status >= 300) {
        const phaseName = root.phase === "upload" ? "Upload" : (root.phase === "download" ? "Download" : "Latency check");
        const detail = request.statusText ? (" " + request.statusText) : "";
        root.failTest(phaseName + " request failed (HTTP " + request.status + detail + ").");
        return;
      }
      onComplete(request);
    };
    request.open(method, url);
    if (method === "POST") request.setRequestHeader("Content-Type", "application/octet-stream");
    requestTimeout.restart();
    request.send(body);
  }

  function beginPhase(name: string): void {
    if (name === "upload") {
      const payload = new Uint8Array(5000000);
      let seed = (Date.now() ^ 0x5f3759df) >>> 0;
      if (seed === 0) seed = 1;
      for (let i = 0; i < payload.length; i++) {
        seed ^= seed << 13;
        seed ^= seed >>> 17;
        seed ^= seed << 5;
        payload[i] = seed & 0xff;
      }
      root.uploadPayload = payload.buffer;
    }

    root.phase = name;
    root.phaseStartedAt = Date.now();
    root.phaseElapsedMs = 0;
    root.phaseProgress = 0;
    root.bytesTransferred = 0;
    root.nextChunkBytes = 16384;
    root.currentSpeedText = "0.0";
    root.statusText = name === "download" ? "Measuring download…" : "Measuring upload…";
    phaseClock.start();
    root.queueSample();
  }

  function queueSample(): void {
    if (!root.running || (root.phase !== "download" && root.phase !== "upload")) return;

    const now = Date.now();
    root.phaseElapsedMs = now - root.phaseStartedAt;
    if (root.phaseElapsedMs >= root.phaseDurationMs) {
      root.finishPhase();
      return;
    }

    const bytes = root.nextChunkBytes;
    const nonce = now + Math.floor(Math.random() * 1000000);
    if (root.phase === "download") {
      const url = root.downloadUrl + "?bytes=" + bytes + "&nonce=" + nonce;
      root.issueRequest("GET", url, null, "arraybuffer", function(request) {
        const receivedBytes = request.response ? request.response.byteLength : 0;
        if (receivedBytes <= 0) {
          root.failTest("Cloudflare returned an empty download sample.");
          return;
        }
        root.bytesTransferred += receivedBytes;
        root.afterSample();
      });
      return;
    }

    const uploadUrl = root.uploadUrl + "?bytes=" + bytes + "&nonce=" + nonce;
    root.issueRequest("POST", uploadUrl, root.uploadPayload.slice(0, bytes), "", function() {
      root.bytesTransferred += bytes;
      root.afterSample();
    });
  }

  function afterSample(): void {
    const elapsed = Date.now() - root.phaseStartedAt;
    root.phaseElapsedMs = elapsed;
    root.currentSpeedText = root.formatMbps(root.bytesTransferred, elapsed);
    if (root.phase === "download") root.downloadText = root.currentSpeedText + " Mbps";
    else root.uploadText = root.currentSpeedText + " Mbps";

    root.nextChunkBytes = Math.max(8192, Math.min(5000000, Math.round(Number(root.currentSpeedText) * 31250)));
    if (elapsed >= root.phaseDurationMs) root.finishPhase();
    else root.queueSample();
  }

  function finishPhase(): void {
    phaseClock.stop();
    root.phaseProgress = 1;
    root.phaseElapsedMs = Date.now() - root.phaseStartedAt;
    const finalSpeed = root.formatMbps(root.bytesTransferred, root.phaseElapsedMs) + " Mbps";
    if (root.phase === "download") {
      root.downloadText = finalSpeed;
      root.beginPhase("upload");
      return;
    }

    root.uploadText = finalSpeed;
    root.currentSpeedText = finalSpeed.replace(" Mbps", "");
    root.running = false;
    root.hasResult = true;
    root.phase = "complete";
    root.statusText = "Download and upload measured";
  }

  Timer {
    id: phaseClock
    interval: 100
    repeat: true
    onTriggered: {
      if (root.phase !== "download" && root.phase !== "upload") return;
      root.phaseElapsedMs = Date.now() - root.phaseStartedAt;
      root.phaseProgress = Math.min(1, root.phaseElapsedMs / root.phaseDurationMs);
    }
  }

  Timer {
    id: requestTimeout
    interval: 45000
    repeat: false
    onTriggered: {
      const phaseName = root.phase === "upload" ? "Upload" : (root.phase === "download" ? "Download" : "Latency check");
      root.failTest(phaseName + " request timed out. Check your connection and try again.");
    }
  }

  Component.onDestruction: {
    requestTimeout.stop();
    phaseClock.stop();
    const request = root.activeRequest;
    root.activeRequest = null;
    if (request) request.abort();
  }

  PopupCard {
    anchors.fill: parent

    Column {
      id: content
      anchors.fill: parent
      spacing: Theme.spaceXl

      PopupHeader {
        width: parent.width
        title: "Connection speed"
        subtitle: root.statusText

        Text {
          text: "󰓅"
          font.family: Theme.mono
          font.pixelSize: 22
          color: root.phaseColor
          Layout.alignment: Qt.AlignVCenter
        }
      }

      Hairline { width: parent.width }

      Item {
        width: 250
        height: 250
        anchors.horizontalCenter: parent.horizontalCenter

        Canvas {
          id: speedRing
          anchors.fill: parent
          onPaint: {
            const ctx = getContext("2d");
            const center = width / 2;
            const radius = width / 2 - 12;
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath();
            ctx.lineWidth = 8;
            ctx.strokeStyle = Theme.cardBorder;
            ctx.arc(center, center, radius, 0, Math.PI * 2);
            ctx.stroke();
            if (root.phaseProgress > 0) {
              ctx.beginPath();
              ctx.lineWidth = 8;
              ctx.lineCap = "round";
              ctx.strokeStyle = root.phaseColor;
              ctx.arc(center, center, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.phaseProgress);
              ctx.stroke();
            }
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: 2

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.currentSpeedText
            font.family: Theme.displayFont
            font.pixelSize: 42
            font.weight: Font.DemiBold
            color: Theme.ink1
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Mbps"
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.phaseLabel
            font.family: Theme.textFont
            font.pixelSize: Theme.fontMd
            font.weight: Font.Medium
            color: root.phaseColor
          }

          Text {
            visible: root.phase === "download" || root.phase === "upload"
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.elapsedLabel
            font.family: Theme.mono
            font.pixelSize: Theme.fontXs
            color: Theme.ink3
          }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Theme.spaceMd

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 62
          color: Theme.inset
          border.color: Theme.cardBorder
          border.width: 1

          Column {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceXl
            anchors.rightMargin: Theme.spaceXl
            spacing: 4

            Text {
              text: "Download"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontXs
              color: Theme.ink3
            }
            Text {
              text: root.downloadText
              font.family: Theme.mono
              font.pixelSize: Theme.fontXl
              font.weight: Font.DemiBold
              color: Theme.green
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 62
          color: Theme.inset
          border.color: Theme.cardBorder
          border.width: 1

          Column {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceXl
            anchors.rightMargin: Theme.spaceXl
            spacing: 4

            Text {
              text: "Upload"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontXs
              color: Theme.ink3
            }
            Text {
              text: root.uploadText
              font.family: Theme.mono
              font.pixelSize: Theme.fontXl
              font.weight: Font.DemiBold
              color: Theme.accent
            }
          }
        }
      }

      RowLayout {
        width: parent.width
        Text {
          text: "Latency"
          font.family: Theme.textFont
          font.pixelSize: Theme.fontSm
          color: Theme.ink3
        }
        Item { Layout.fillWidth: true }
        Text {
          text: root.latencyText
          font.family: Theme.mono
          font.pixelSize: Theme.fontSm
          color: Theme.ink2
        }
      }

      Text {
        width: parent.width
        text: "20 seconds each way · Cloudflare edge network"
        font.family: Theme.textFont
        font.pixelSize: Theme.fontXs
        color: Theme.ink3
      }

      PrimaryButton {
        width: parent.width
        text: root.running ? "Cancel test" : (root.hasResult ? "Run again" : "Run speed test")
        glyph: root.running ? "󰜺" : "󰓅"
        fill: root.running ? Theme.selected : Theme.accent
        ink: root.running ? Theme.ink1 : Theme.darkInk
        onClicked: root.running ? root.cancelTest() : root.startTest()
      }
    }
  }

  onPhaseProgressChanged: speedRing.requestPaint()
}
