// Calendar.qml — Quiet calendar matching TailscaleControlCenter.
// Quickshell constraints respected:
// - Root exposes only implicitWidth/implicitHeight; PopupWindow drives size
//   (anchors.fill: parent inside, no width/height bindings -> no resize loops).
// - border.width stays constant (1) so hover never changes layout.
// - Hover uses borderless washes, same as Tailscale RowBase/IconBtn/TextBtn.
// Docs:
// - https://quickshell.org/docs/v0.3.1/types/Quickshell/PopupWindow/ (hosted in shell.qml)
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView/ (path, text(), loaded)
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
  id: root

  property date today: new Date()
  property date selectedDate: today
  property int shownYear: -1
  property int shownMonth: -1 // 0-11
  property var cells: []

  property string icsPath: Quickshell.shellPath("assets/holidays.ics")
  property var eventsMap: ({})
  property var selectedEvents: []

  // ---- Design tokens (mirrors TailscaleControlCenter) ----
  QtObject {
    id: t
    readonly property color bg: "#17171E"
    readonly property color surface: "#1F202B"
    readonly property color inset: "#121217"
    readonly property color line: "#2B2C3A"
    readonly property color cardBorder: "#26272F"
    readonly property color ink1: "#F1F1F6"
    readonly property color ink2: "#A6A6B8"
    readonly property color ink3: "#6F6F84"
    readonly property color accent: "#5E9DFF"
    readonly property color amber: "#E2A63B"
    readonly property color red: "#DF6363"
    readonly property color darkInk: "#101018"
    readonly property color selected: "#2E2F42"
    readonly property color hoverFill: "#22232F"
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
  }

  readonly property string monoFont: t.mono

  readonly property var monthNames: [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ]
  readonly property var weekDays: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

  implicitWidth: 328
  implicitHeight: root.selectedEvents.length > 0 ? 388 : 336

  Behavior on implicitHeight { NumberAnimation { duration: 110 } }

  FileView {
    id: icsFile
    path: root.icsPath
    onLoaded: root.loadEvents()
    onLoadFailed: error => {
      console.warn("Calendar: failed to load ics file:", error);
      if (root.icsPath !== "/home/dev/Downloads/maharashtra_holidays_2026.ics") {
        root.icsPath = "/home/dev/Downloads/maharashtra_holidays_2026.ics";
      }
    }
  }

  function dateKey(d: date): string {
    const y = d.getFullYear();
    const m = (d.getMonth() + 1 < 10 ? "0" : "") + (d.getMonth() + 1);
    const day = (d.getDate() < 10 ? "0" : "") + d.getDate();
    return y + "-" + m + "-" + day;
  }

  function parseIcs(text: string): var {
    if (!text)
      return {};
    const clean = text.replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "");
    const lines = clean.split(/\r?\n/);
    const map = {};

    let inEvent = false;
    let startDate = "";
    let summary = "";

    for (let i = 0; i < lines.length; ++i) {
      const line = lines[i].trim();
      if (line === "BEGIN:VEVENT") {
        inEvent = true;
        startDate = "";
        summary = "";
      } else if (line === "END:VEVENT") {
        if (inEvent && startDate && summary) {
          if (!map[startDate])
            map[startDate] = [];
          map[startDate].push(summary);
        }
        inEvent = false;
      } else if (inEvent) {
        if (line.startsWith("DTSTART")) {
          const colon = line.indexOf(":");
          if (colon !== -1) {
            const raw = line.slice(colon + 1).trim();
            if (raw.length >= 8) {
              const y = raw.slice(0, 4);
              const m = raw.slice(4, 6);
              const d = raw.slice(6, 8);
              startDate = y + "-" + m + "-" + d;
            }
          }
        } else if (line.startsWith("SUMMARY")) {
          const colon = line.indexOf(":");
          if (colon !== -1) {
            summary = line.slice(colon + 1)
              .replace(/\\,/g, ",")
              .replace(/\\;/g, ";")
              .replace(/\\n/g, " ")
              .replace(/\\\\/g, "\\")
              .trim();
          }
        }
      }
    }
    return map;
  }

  function updateSelectedEvents(): void {
    if (!selectedDate) {
      selectedEvents = [];
      return;
    }
    const key = dateKey(selectedDate);
    selectedEvents = eventsMap[key] || [];
  }

  function loadEvents(): void {
    eventsMap = parseIcs(icsFile.text());
    rebuild();
    updateSelectedEvents();
  }

  onSelectedDateChanged: updateSelectedEvents()

  function daysInMonth(y: int, m: int): int {
    return new Date(y, m + 1, 0).getDate();
  }

  function monthStartOffset(y: int, m: int): int {
    // Monday-first: Mo=0 .. Su=6
    return (new Date(y, m, 1).getDay() + 6) % 7;
  }

  function sameDay(a: date, b: date): bool {
    if (!a || !b) return false;
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  }

  function rebuild(): void {
    if (shownYear < 0 || shownMonth < 0)
      return;
    const dim = daysInMonth(shownYear, shownMonth);
    const offset = monthStartOffset(shownYear, shownMonth);
    const prevDim = daysInMonth(shownYear, (shownMonth + 11) % 12);
    const arr = [];
    for (let i = 0; i < 42; ++i) {
      const d = i - offset + 1;
      let cellDay = 0;
      let cellDate;
      let inMonth = false;

      if (d < 1) {
        const pm = (shownMonth + 11) % 12;
        const py = shownMonth === 0 ? shownYear - 1 : shownYear;
        cellDay = prevDim + d;
        cellDate = new Date(py, pm, cellDay);
        inMonth = false;
      } else if (d > dim) {
        const nm = (shownMonth + 1) % 12;
        const ny = shownMonth === 11 ? shownYear + 1 : shownYear;
        cellDay = d - dim;
        cellDate = new Date(ny, nm, cellDay);
        inMonth = false;
      } else {
        cellDay = d;
        cellDate = new Date(shownYear, shownMonth, cellDay);
        inMonth = true;
      }

      const key = dateKey(cellDate);
      const evs = eventsMap[key] || [];

      arr.push({
        day: cellDay,
        date: cellDate,
        inMonth: inMonth,
        isWeekend: (i % 7 === 5 || i % 7 === 6),
        hasEvent: evs.length > 0,
        events: evs
      });
    }
    cells = arr;
  }

  function prevMonth(): void {
    if (shownMonth === 0) {
      shownMonth = 11;
      shownYear -= 1;
    } else {
      shownMonth -= 1;
    }
    rebuild();
  }

  function nextMonth(): void {
    if (shownMonth === 11) {
      shownMonth = 0;
      shownYear += 1;
    } else {
      shownMonth += 1;
    }
    rebuild();
  }

  function goToday(): void {
    const t = new Date();
    shownYear = t.getFullYear();
    shownMonth = t.getMonth();
    selectedDate = t;
    rebuild();
    updateSelectedEvents();
  }

  Component.onCompleted: {
    const t = today;
    shownYear = t.getFullYear();
    shownMonth = t.getMonth();
    selectedDate = t;
    rebuild();
    updateSelectedEvents();
  }

  onTodayChanged: rebuild()

  Rectangle {
    id: card
    anchors.fill: parent
    radius: 14
    color: t.bg
    border.color: t.cardBorder
    border.width: 1

    WheelHandler {
      onWheel: event => {
        if (event.angleDelta.y > 0) {
          root.prevMonth();
        } else if (event.angleDelta.y < 0) {
          root.nextMonth();
        }
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 0

      // Header: identity left (Tailscale header pattern), quiet actions right.
      // Borderless washes only — no bordered pills, so hover never shifts layout.
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        spacing: 4

        Column {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: 1
          Text {
            text: root.shownMonth >= 0 ? root.monthNames[root.shownMonth] : ""
            color: t.ink1
            font.pixelSize: 14
            font.weight: Font.DemiBold
          }
          Text {
            text: root.shownYear >= 0 ? root.shownYear : ""
            color: t.ink3
            font.pixelSize: 11
          }
        }

        // Today: borderless text button (Tailscale TextBtn pattern)
        Rectangle {
          readonly property bool isTodayView: root.shownMonth === root.today.getMonth() && root.shownYear === root.today.getFullYear()
          visible: !isTodayView
          implicitWidth: todayLabel.implicitWidth + 18
          implicitHeight: 30
          Layout.alignment: Qt.AlignVCenter
          radius: 7
          color: todayMouse.pressed ? "#1CFFFFFF" : todayMouse.containsMouse ? "#0FFFFFFF" : "transparent"
          Behavior on color { ColorAnimation { duration: 90 } }

          Text {
            id: todayLabel
            anchors.centerIn: parent
            text: "Today"
            font.pixelSize: 11
            font.bold: true
            color: todayMouse.containsMouse || todayMouse.pressed ? t.ink1 : t.accent
            Behavior on color { ColorAnimation { duration: 90 } }
          }

          MouseArea {
            id: todayMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.goToday()
          }
        }

        // Chevron prev: borderless square icon button (Tailscale IconBtn pattern)
        Rectangle {
          Layout.preferredWidth: 30
          Layout.preferredHeight: 30
          Layout.alignment: Qt.AlignVCenter
          radius: 8
          color: prevMouse.pressed ? "#1CFFFFFF" : prevMouse.containsMouse ? "#0FFFFFFF" : "transparent"
          Behavior on color { ColorAnimation { duration: 90 } }

          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: "‹"
            font.pixelSize: 17
            font.bold: true
            color: prevMouse.containsMouse || prevMouse.pressed ? t.ink1 : t.ink2
            Behavior on color { ColorAnimation { duration: 90 } }
          }

          MouseArea {
            id: prevMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.prevMonth()
          }
        }

        // Chevron next
        Rectangle {
          Layout.preferredWidth: 30
          Layout.preferredHeight: 30
          Layout.alignment: Qt.AlignVCenter
          radius: 8
          color: nextMouse.pressed ? "#1CFFFFFF" : nextMouse.containsMouse ? "#0FFFFFFF" : "transparent"
          Behavior on color { ColorAnimation { duration: 90 } }

          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: "›"
            font.pixelSize: 17
            font.bold: true
            color: nextMouse.containsMouse || nextMouse.pressed ? t.ink1 : t.ink2
            Behavior on color { ColorAnimation { duration: 90 } }
          }

          MouseArea {
            id: nextMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.nextMonth()
          }
        }
      }

      Item { Layout.preferredHeight: 12; Layout.fillWidth: true }

      // Weekday initials: small-caps section label pattern (Tailscale SectionHead)
      Row {
        Layout.fillWidth: true
        Layout.preferredHeight: 20

        Repeater {
          model: root.weekDays
          Item {
            required property string modelData
            required property int index
            width: 42
            height: 20

            Text {
              anchors.centerIn: parent
              text: parent.modelData
              color: t.ink3
              font.pixelSize: 11
              font.bold: true
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 0.8
            }
          }
        }
      }

      Item { Layout.preferredHeight: 8 }

      // Days Grid
      Grid {
        columns: 7
        rows: 6
        spacing: 0
        Layout.fillWidth: true

        Repeater {
          model: root.cells
          delegate: Item {
            required property var modelData
            width: 42
            height: 36

            readonly property bool isToday: root.sameDay(modelData.date, root.today)
            readonly property bool isSelected: root.sameDay(modelData.date, root.selectedDate)

            // Day bubble: quiet wash pattern (Tailscale RowBase/Segments).
            // border.width stays 1 with transparent fallback so hover
            // never triggers a layout pass inside the Grid.
            Rectangle {
              anchors.centerIn: parent
              width: 34
              height: 32
              radius: 8

              color: {
                if (isToday) return t.accent;
                if (isSelected) return t.selected;
                if (cellHover.pressed && modelData.inMonth) return "#1AFFFFFF";
                if (cellHover.containsMouse && modelData.inMonth) return t.hoverFill;
                return "transparent";
              }

              border.color: "transparent"
              border.width: 1

              Behavior on color { ColorAnimation { duration: 90 } }

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: modelData.hasEvent ? -2 : 0
                text: modelData.day
                font.pixelSize: 13
                font.weight: (isToday || isSelected) ? Font.DemiBold : Font.Normal
                font.family: root.monoFont
                color: {
                  if (isToday) return t.darkInk;
                  if (isSelected) return t.ink1;
                  if (!modelData.inMonth) return t.ink3;
                  if (modelData.isWeekend) return t.red;
                  return t.ink1;
                }
                Behavior on color { ColorAnimation { duration: 90 } }
              }

              // Event dot
              Rectangle {
                visible: !!modelData.hasEvent
                width: 4
                height: 4
                radius: 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                color: isToday ? t.darkInk : t.amber
              }
            }

            MouseArea {
              id: cellHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.selectedDate = modelData.date;
                if (!modelData.inMonth) {
                  root.shownYear = modelData.date.getFullYear();
                  root.shownMonth = modelData.date.getMonth();
                  root.rebuild();
                }
              }
            }
          }
        }
      }

      // Hairline divider (Tailscale Hairline: inset via layout margins,
      // fixed height + constant visibility binding so the grid never shifts)
      Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        Layout.preferredHeight: 1
        color: t.line
        visible: root.selectedEvents.length > 0
      }

      // Selected event: grouped surface row (Tailscale grouped-row pattern)
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        visible: root.selectedEvents.length > 0
        radius: 10
        color: t.surface

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 8

          Rectangle {
            Layout.preferredWidth: 5
            Layout.preferredHeight: 5
            radius: 2.5
            color: t.amber
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            Layout.fillWidth: true
            text: root.selectedEvents.join(", ")
            color: t.ink1
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }
}
