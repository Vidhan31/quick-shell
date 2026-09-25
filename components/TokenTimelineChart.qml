pragma ComponentBehavior: Bound
// components/TokenTimelineChart.qml — Interactive smooth line/area chart showing token usage over time.
import QtQuick
import QtQuick.Layouts
import "../theme"

Rectangle {
  id: root

  property string title: "Daily activity"
  property var rangeOptions: [1, 3, 6, 12]
  property int selectedRange: 1
  signal rangeSelected(int months)

  // Mode: "overview" (OpenCode + Antigravity) | "opencode" | "antigravity"
  property string mode: "overview"

  // Primary data array: [{date, label, weekday, dayNumber, tokens, input, output, cacheRead, cacheWrite, reasoning, cost}, ...]
  property var primaryDaily: []
  // Secondary data array (used in overview mode for Antigravity)
  property var secondaryDaily: []

  property var compactFn: function(v) {
    if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
    if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
    if (v >= 1e3) return (v / 1e3).toFixed(1) + "k";
    return Math.round(v).toString();
  }
  property var moneyFn: function(v) {
    return "$" + (v || 0).toFixed(2);
  }

  readonly property int pointCount: Math.max(root.primaryDaily ? root.primaryDaily.length : 0, root.secondaryDaily ? root.secondaryDaily.length : 0)

  // Combined totals per day
  readonly property var dailyPoints: {
    const list = [];
    const count = root.pointCount;
    for (let i = 0; i < count; ++i) {
      const p = (root.primaryDaily && i < root.primaryDaily.length) ? root.primaryDaily[i] : null;
      const s = (root.secondaryDaily && i < root.secondaryDaily.length) ? root.secondaryDaily[i] : null;

      const pTokens = p ? (p.tokens || 0) : 0;
      const sTokens = s ? (s.tokens || 0) : 0;
      const totalTokens = root.mode === "overview" ? (pTokens + sTokens) : pTokens;

      list.push({
        index: i,
        date: p ? p.date : (s ? s.date : ""),
        label: p ? p.label : (s ? s.label : ""),
        weekday: p ? p.weekday : (s ? s.weekday : ""),
        dayNumber: p ? p.dayNumber : (s ? s.dayNumber : i + 1),
        tokens: totalTokens,
        pTokens: pTokens,
        sTokens: sTokens,
        pCost: p ? (p.cost || 0) : 0,
        input: p ? (p.input || 0) : 0,
        output: p ? (p.output || 0) : 0,
        cacheRead: p ? (p.cacheRead || 0) : 0,
        cacheWrite: p ? (p.cacheWrite || 0) : 0,
        reasoning: p ? (p.reasoning || 0) : 0
      });
    }
    return list;
  }

  // Maximum value for scale
  readonly property double maxTokenVal: {
    let m = 0;
    for (let i = 0; i < root.dailyPoints.length; ++i) {
      const pt = root.dailyPoints[i];
      if (root.mode === "overview") {
        m = Math.max(m, pt.pTokens, pt.sTokens);
      } else {
        m = Math.max(m, pt.tokens);
      }
    }
    return m > 0 ? m : 1;
  }

  // Range totals and stats
  readonly property double rangeTotalSum: {
    let sum = 0;
    for (let i = 0; i < root.dailyPoints.length; ++i) {
      sum += root.dailyPoints[i].tokens;
    }
    return sum;
  }

  readonly property double dailyAverage: root.pointCount > 0 ? (root.rangeTotalSum / root.pointCount) : 0

  readonly property var peakPoint: {
    let peak = null;
    for (let i = 0; i < root.dailyPoints.length; ++i) {
      const pt = root.dailyPoints[i];
      if (!peak || pt.tokens > peak.tokens) {
        peak = pt;
      }
    }
    return peak;
  }

  property int hoverIndex: -1

  radius: 12
  color: Theme.surface
  border.color: Theme.cardBorder
  border.width: 1

  implicitHeight: cardCol.height + 24
  height: implicitHeight

  onPrimaryDailyChanged: chartCanvas.requestPaint()
  onSecondaryDailyChanged: chartCanvas.requestPaint()
  onModeChanged: chartCanvas.requestPaint()
  onHoverIndexChanged: chartCanvas.requestPaint()

  Column {
    id: cardCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 12
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    spacing: 10

    // ---- Header: Title, Peak/Avg stat, Range pills ----
    RowLayout {
      width: parent.width
      height: 24
      spacing: 8

      Text {
        text: root.title
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Theme.ink2
      }

      // Average / Peak pill badge
      Rectangle {
        visible: root.rangeTotalSum > 0
        radius: 4
        color: Qt.rgba(Theme.ink1.r, Theme.ink1.g, Theme.ink1.b, 0.06)
        border.color: Theme.line
        border.width: 1
        implicitWidth: statRow.width + 10
        implicitHeight: 20

        Row {
          id: statRow
          anchors.centerIn: parent
          spacing: 4
          Text {
            text: root.compactFn(root.rangeTotalSum)
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.family: Theme.mono
            color: Theme.ink1
          }
          Text {
            text: "· avg " + root.compactFn(root.dailyAverage) + "/d"
            font.pixelSize: 10
            font.family: Theme.mono
            color: Theme.ink2
          }
        }
      }

      Item { Layout.fillWidth: true }

      // Range Selector Pills
      Row {
        spacing: 4
        Repeater {
          model: root.rangeOptions

          Rectangle {
            id: rPill
            required property var modelData
            required property int index
            readonly property bool isSelected: rPill.modelData === root.selectedRange

            width: rPillText.implicitWidth + 14
            height: 20
            radius: 10
            color: isSelected ? Theme.selected : (rPillMouse.containsMouse ? Theme.hoverFill : "transparent")
            border.color: isSelected ? Theme.line : "transparent"
            border.width: 1

            Text {
              id: rPillText
              anchors.centerIn: parent
              text: rPill.modelData + "m"
              font.pixelSize: 11
              font.weight: rPill.isSelected ? Font.DemiBold : Font.Normal
              font.family: Theme.mono
              color: rPill.isSelected ? Theme.ink1 : (rPillMouse.containsMouse ? Theme.ink2 : Theme.ink3)
            }

            MouseArea {
              id: rPillMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: {
                root.selectedRange = rPill.modelData;
                root.rangeSelected(rPill.modelData);
              }
            }
          }
        }
      }
    }

    // ---- Legend row (Overview mode: OpenCode vs Antigravity; Single mode: summary) ----
    RowLayout {
      width: parent.width
      height: 18
      spacing: 12

      // Overview legend
      Row {
        visible: root.mode === "overview"
        spacing: 12

        Row {
          spacing: 5
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 3.5
            color: Theme.teal
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "OpenCode"
            font.pixelSize: 11
            font.family: Theme.mono
            color: Theme.teal
          }
        }

        Row {
          spacing: 5
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 3.5
            color: Theme.violet
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Antigravity"
            font.pixelSize: 11
            font.family: Theme.mono
            color: Theme.violet
          }
        }
      }

      // Single mode indicator
      Row {
        visible: root.mode !== "overview"
        spacing: 5
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 7
          height: 7
          radius: 3.5
          color: root.mode === "opencode" ? Theme.teal : Theme.violet
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.mode === "opencode" ? "OpenCode daily volume" : "Antigravity daily volume"
          font.pixelSize: 11
          font.family: Theme.mono
          color: root.mode === "opencode" ? Theme.teal : Theme.violet
        }
      }

      Item { Layout.fillWidth: true }

      // Peak info
      Text {
        visible: root.peakPoint !== null && root.peakPoint.tokens > 0
        text: root.peakPoint ? ("Peak " + root.compactFn(root.peakPoint.tokens) + " (" + root.peakPoint.label + ")") : ""
        font.pixelSize: 10
        font.family: Theme.mono
        color: Theme.ink3
      }
    }

    // ---- Chart container ----
    Item {
      id: chartArea
      width: parent.width
      height: 148

      Canvas {
        id: chartCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Threaded

        readonly property real leftPad: 48
        readonly property real rightPad: 14
        readonly property real topPad: 12
        readonly property real bottomPad: 24
        readonly property real chartW: width - leftPad - rightPad
        readonly property real chartH: height - topPad - bottomPad

        // Clean axis number formatter
        function formatAxisVal(v) {
          if (v <= 0) return "0";
          if (v >= 1e9) {
            const b = v / 1e9;
            return (b >= 10 ? Math.round(b) : b.toFixed(1)) + "B";
          }
          if (v >= 1e6) {
            const m = v / 1e6;
            return (m >= 10 ? Math.round(m) : m.toFixed(1)) + "M";
          }
          if (v >= 1e3) {
            const k = v / 1e3;
            return (k >= 10 ? Math.round(k) : k.toFixed(1)) + "k";
          }
          return Math.round(v).toString();
        }

        onPaint: {
          const ctx = chartCanvas.getContext("2d");
          ctx.reset();
          ctx.clearRect(0, 0, width, height);

          const count = root.dailyPoints.length;
          if (count === 0) return;

          const lp = leftPad;
          const rp = rightPad;
          const tp = topPad;
          const bp = height - bottomPad;
          const ch = chartH;
          const cw = chartW;
          const maxVal = root.maxTokenVal;

          // 1. Draw horizontal grid lines & Y-axis labels
          ctx.font = "9px " + Theme.mono;
          ctx.fillStyle = Theme.ink3.toString();
          ctx.textAlign = "right";
          ctx.textBaseline = "middle";

          const gridSteps = [0.0, 0.5, 1.0];
          for (let s = 0; s < gridSteps.length; ++s) {
            const frac = gridSteps[s];
            const y = bp - frac * ch;

            ctx.strokeStyle = Theme.cardBorder.toString();
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(lp, y);
            ctx.lineTo(lp + cw, y);
            ctx.stroke();

            const lblVal = frac * maxVal;
            const lbl = formatAxisVal(lblVal);
            ctx.fillText(lbl, lp - 6, y);
          }

          // Helper to calculate (x, y) coordinates for a series
          function getPoints(valGetter) {
            const pts = [];
            const step = count > 1 ? (cw / (count - 1)) : (cw / 2);
            for (let i = 0; i < count; ++i) {
              const x = lp + (count > 1 ? i * step : cw / 2);
              const v = valGetter(root.dailyPoints[i]);
              const y = bp - Math.min(1.0, Math.max(0.0, v / maxVal)) * ch;
              pts.push({ x: x, y: y, val: v });
            }
            return pts;
          }

          // Smooth Catmull-Rom to Cubic Bezier curve path
          function drawSpline(pts, strokeColor, fillColor, lineWidth) {
            if (pts.length === 0) return;

            // Area fill
            ctx.beginPath();
            ctx.moveTo(pts[0].x, bp);
            ctx.lineTo(pts[0].x, pts[0].y);

            if (pts.length === 1) {
              ctx.lineTo(pts[0].x + 4, pts[0].y);
              ctx.lineTo(pts[0].x + 4, bp);
            } else if (pts.length === 2) {
              ctx.lineTo(pts[1].x, pts[1].y);
              ctx.lineTo(pts[1].x, bp);
            } else if (pts.length > 60) {
              for (let i = 1; i < pts.length; ++i) {
                ctx.lineTo(pts[i].x, pts[i].y);
              }
              ctx.lineTo(pts[pts.length - 1].x, bp);
            } else {
              for (let i = 0; i < pts.length - 1; ++i) {
                const p0 = i > 0 ? pts[i - 1] : pts[i];
                const p1 = pts[i];
                const p2 = pts[i + 1];
                const p3 = (i + 2 < pts.length) ? pts[i + 2] : p2;

                const cp1x = p1.x + (p2.x - p0.x) / 6;
                const cp1y = Math.min(bp, Math.max(tp, p1.y + (p2.y - p0.y) / 6));
                const cp2x = p2.x - (p3.x - p1.x) / 6;
                const cp2y = Math.min(bp, Math.max(tp, p2.y - (p3.y - p1.y) / 6));

                ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y);
              }
              ctx.lineTo(pts[pts.length - 1].x, bp);
            }

            ctx.closePath();
            const grad = ctx.createLinearGradient(0, tp, 0, bp);
            grad.addColorStop(0, fillColor);
            grad.addColorStop(1, "transparent");
            ctx.fillStyle = grad;
            ctx.fill();

            // Stroke line
            ctx.beginPath();
            ctx.moveTo(pts[0].x, pts[0].y);

            if (pts.length === 1) {
              ctx.arc(pts[0].x, pts[0].y, 3, 0, Math.PI * 2);
            } else if (pts.length === 2) {
              ctx.lineTo(pts[1].x, pts[1].y);
            } else if (pts.length > 60) {
              for (let i = 1; i < pts.length; ++i) {
                ctx.lineTo(pts[i].x, pts[i].y);
              }
            } else {
              for (let i = 0; i < pts.length - 1; ++i) {
                const p0 = i > 0 ? pts[i - 1] : pts[i];
                const p1 = pts[i];
                const p2 = pts[i + 1];
                const p3 = (i + 2 < pts.length) ? pts[i + 2] : p2;

                const cp1x = p1.x + (p2.x - p0.x) / 6;
                const cp1y = Math.min(bp, Math.max(tp, p1.y + (p2.y - p0.y) / 6));
                const cp2x = p2.x - (p3.x - p1.x) / 6;
                const cp2y = Math.min(bp, Math.max(tp, p2.y - (p3.y - p1.y) / 6));

                ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y);
              }
            }

            ctx.strokeStyle = strokeColor;
            ctx.lineWidth = lineWidth;
            ctx.stroke();
          }

          // 2. Render series according to mode
          let ocPts = [];
          let agyPts = [];
          let singlePts = [];

          if (root.mode === "overview") {
            ocPts = getPoints(pt => pt.pTokens);
            agyPts = getPoints(pt => pt.sTokens);

            drawSpline(ocPts, Theme.teal.toString(), Qt.rgba(Theme.teal.r, Theme.teal.g, Theme.teal.b, 0.16).toString(), 2);
            drawSpline(agyPts, Theme.violet.toString(), Qt.rgba(Theme.violet.r, Theme.violet.g, Theme.violet.b, 0.16).toString(), 2);
          } else {
            const baseColor = root.mode === "opencode" ? Theme.teal : Theme.violet;
            singlePts = getPoints(pt => pt.tokens);
            drawSpline(singlePts, baseColor.toString(), Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.20).toString(), 2);
          }

          // 3. Draw X-axis Date ticks (clean, non-overlapping, aligned to curve coordinates)
          const tickIndices = [];
          const steps = [0.0, 0.25, 0.5, 0.75, 1.0];
          for (let s = 0; s < steps.length; ++s) {
            const idx = Math.min(count - 1, Math.round((count - 1) * steps[s]));
            if (!tickIndices.includes(idx)) tickIndices.push(idx);
          }

          const labelY = bp + 7;
          ctx.textBaseline = "top";
          const step = count > 1 ? (cw / (count - 1)) : (cw / 2);

          for (let t = 0; t < tickIndices.length; ++t) {
            const idx = tickIndices[t];
            const pt = root.dailyPoints[idx];
            const x = lp + (count > 1 ? idx * step : cw / 2);

            let txt = pt.label; // e.g. "27 Aug"
            if (count > 180 && pt.date && pt.date.length >= 10) {
              const yr = "'" + pt.date.substring(2, 4);
              txt = pt.label + " " + yr; // e.g. "26 Sep '25"
            }

            if (idx === 0) {
              ctx.textAlign = "left";
            } else if (idx === count - 1) {
              ctx.textAlign = "right";
            } else {
              ctx.textAlign = "center";
            }

            const isHovered = (root.hoverIndex === idx);
            ctx.font = (isHovered ? "bold 10px " : "10px ") + Theme.mono;
            ctx.fillStyle = isHovered ? Theme.ink1.toString() : Theme.ink3.toString();
            ctx.fillText(txt, x, labelY);
          }

          // 4. Draw hover guide line & glowing dots if hovered
          if (root.hoverIndex >= 0 && root.hoverIndex < count) {
            const hIdx = root.hoverIndex;
            const hx = lp + (count > 1 ? hIdx * step : cw / 2);

            // Vertical cursor line
            ctx.strokeStyle = Qt.rgba(Theme.ink1.r, Theme.ink1.g, Theme.ink1.b, 0.25).toString();
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(hx, tp);
            ctx.lineTo(hx, bp);
            ctx.stroke();

            // Function to draw glowing dot
            function drawDot(y, dotColor) {
              ctx.beginPath();
              ctx.arc(hx, y, 6, 0, Math.PI * 2);
              ctx.fillStyle = Qt.rgba(dotColor.r, dotColor.g, dotColor.b, 0.35).toString();
              ctx.fill();

              ctx.beginPath();
              ctx.arc(hx, y, 3, 0, Math.PI * 2);
              ctx.fillStyle = dotColor.toString();
              ctx.fill();

              ctx.beginPath();
              ctx.arc(hx, y, 1.2, 0, Math.PI * 2);
              ctx.fillStyle = "#ffffff";
              ctx.fill();
            }

            if (root.mode === "overview") {
              if (hIdx < ocPts.length) drawDot(ocPts[hIdx].y, Theme.teal);
              if (hIdx < agyPts.length) drawDot(agyPts[hIdx].y, Theme.violet);
            } else {
              const baseColor = root.mode === "opencode" ? Theme.teal : Theme.violet;
              if (hIdx < singlePts.length) drawDot(singlePts[hIdx].y, baseColor);
            }
          }
        }
      }

      // Mouse tracking area over the chart
      MouseArea {
        id: chartMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.CrossCursor

        onPositionChanged: mouse => {
          const lp = chartCanvas.leftPad;
          const cw = chartCanvas.chartW;
          const count = root.dailyPoints.length;
          if (count <= 0) return;

          const relX = mouse.x - lp;
          const step = count > 1 ? (cw / (count - 1)) : cw;
          const rawIdx = Math.round(relX / step);
          root.hoverIndex = Math.max(0, Math.min(count - 1, rawIdx));
        }

        onExited: {
          root.hoverIndex = -1;
        }
      }

      // Floating interactive tooltip box
      Rectangle {
        id: hoverTip
        visible: root.hoverIndex >= 0 && root.hoverIndex < root.dailyPoints.length
        readonly property var pt: visible ? root.dailyPoints[root.hoverIndex] : null

        width: tipLayout.implicitWidth + 16
        height: tipLayout.implicitHeight + 12
        radius: Theme.radiusSm
        color: Theme.surfaceElevated
        border.color: Theme.line
        border.width: 1

        x: {
          if (!pt) return 0;
          const count = root.pointCount;
          const step = count > 1 ? (chartCanvas.chartW / (count - 1)) : (chartCanvas.chartW / 2);
          const targetX = chartCanvas.leftPad + (count > 1 ? root.hoverIndex * step : chartCanvas.chartW / 2);
          return Math.max(8, Math.min(chartArea.width - width - 8, targetX - width / 2));
        }
        y: 4

        Column {
          id: tipLayout
          anchors.centerIn: parent
          spacing: 3

          // Date Header
          RowLayout {
            spacing: 6
            Text {
              text: {
                if (!hoverTip.pt) return "";
                let header = hoverTip.pt.weekday + ", " + hoverTip.pt.label;
                if (root.pointCount > 180 && hoverTip.pt.date && hoverTip.pt.date.length >= 10) {
                  header += " '" + hoverTip.pt.date.substring(2, 4);
                }
                return header;
              }
              font.pixelSize: 11
              font.weight: Font.DemiBold
              font.family: Theme.mono
              color: Theme.ink1
            }
            Item { Layout.fillWidth: true }
            Text {
              text: hoverTip.pt ? root.compactFn(hoverTip.pt.tokens) : ""
              font.pixelSize: 11
              font.weight: Font.DemiBold
              font.family: Theme.mono
              color: Theme.accent
            }
          }

          Hairline {
            width: tipLayout.width
            color: Theme.cardBorder
          }

          // Overview Breakdown: OpenCode vs Antigravity
          Column {
            visible: root.mode === "overview" && hoverTip.pt !== null
            spacing: 2
            width: tipLayout.width

            RowLayout {
              width: parent.width
              spacing: 6
              Rectangle {
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                radius: 3
                color: Theme.teal
              }
              Text {
                text: "OpenCode"
                font.pixelSize: 10
                font.family: Theme.mono
                color: Theme.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                text: hoverTip.pt ? root.compactFn(hoverTip.pt.pTokens) : "--"
                font.pixelSize: 10
                font.family: Theme.mono
                color: Theme.ink1
              }
              Text {
                visible: hoverTip.pt && hoverTip.pt.pCost > 0
                text: "(" + (hoverTip.pt ? root.moneyFn(hoverTip.pt.pCost) : "") + ")"
                font.pixelSize: 9
                font.family: Theme.mono
                color: Theme.ink3
              }
            }

            RowLayout {
              width: parent.width
              spacing: 6
              Rectangle {
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                radius: 3
                color: Theme.violet
              }
              Text {
                text: "Antigravity"
                font.pixelSize: 10
                font.family: Theme.mono
                color: Theme.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                text: hoverTip.pt ? root.compactFn(hoverTip.pt.sTokens) : "--"
                font.pixelSize: 10
                font.family: Theme.mono
                color: Theme.ink1
              }
            }
          }

          // Single Provider Breakdown (Input, Output, Cache read, etc.)
          Column {
            visible: root.mode !== "overview" && hoverTip.pt !== null
            spacing: 2
            width: tipLayout.width

            component TipMetricRow: RowLayout {
              id: tmr
              property color dotColor: Theme.accent
              property string labelText: ""
              property double valueTokens: 0
              visible: tmr.valueTokens > 0
              width: parent ? parent.width : 0
              spacing: 6

              Rectangle {
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                radius: 3
                color: tmr.dotColor
              }
              Text {
                text: tmr.labelText
                font.pixelSize: 10
                font.family: Theme.mono
                color: Theme.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.compactFn(tmr.valueTokens)
                font.pixelSize: 10
                font.family: Theme.mono
                color: Theme.ink1
              }
            }

            TipMetricRow {
              dotColor: Theme.accent
              labelText: "Input"
              valueTokens: hoverTip.pt ? hoverTip.pt.input : 0
            }
            TipMetricRow {
              dotColor: Theme.green
              labelText: "Output"
              valueTokens: hoverTip.pt ? hoverTip.pt.output : 0
            }
            TipMetricRow {
              dotColor: Theme.violet
              labelText: "Cache read"
              valueTokens: hoverTip.pt ? hoverTip.pt.cacheRead : 0
            }
            TipMetricRow {
              dotColor: Theme.teal
              labelText: "Cache write"
              valueTokens: hoverTip.pt ? hoverTip.pt.cacheWrite : 0
            }
            TipMetricRow {
              dotColor: Theme.amber
              labelText: "Reasoning"
              valueTokens: hoverTip.pt ? hoverTip.pt.reasoning : 0
            }
          }
        }
      }
    }
  }
}
