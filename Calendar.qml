// Calendar.qml — Clean Catppuccin Mocha calendar matching QuickShell theme.
// Docs (from every_quickshell_docs_131_url.csv):
// - https://quickshell.org/docs/v0.3.1/types/Quickshell/PopupWindow/ (hosted in shell.qml)
// - https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView/ (path, text(), loaded)
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
  id: root

  property date today: new Date()
  property date selectedDate: today
  property int shownYear: -1
  property int shownMonth: -1 // 0-11
  property var cells: []

  property string icsPath: "/home/dev/Projects/quick-shell/holidays.ics"
  property var eventsMap: ({})
  property var selectedEvents: []

  readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

  readonly property var monthNames: [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ]
  readonly property var weekDays: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

  implicitWidth: 328
  implicitHeight: root.selectedEvents.length > 0 ? 366 : 336

  Behavior on implicitHeight { NumberAnimation { duration: 140 } }

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
    radius: 16
    color: "#1e1e2e"
    border.color: "#313244"
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
      anchors.margins: 17
      spacing: 0

      // Header: Month Year + Today button + Chevrons
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 30

        Text {
          text: root.shownMonth >= 0 ? (root.monthNames[root.shownMonth] + " " + root.shownYear) : ""
          color: "#cdd6f4"
          font.pixelSize: 14
          font.bold: true
          font.family: root.monoFont
          Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        // Today button (matching QuickShell button styling: #313244 -> #45475a, radius: 6)
        Item {
          readonly property bool isTodayView: root.shownMonth === root.today.getMonth() && root.shownYear === root.today.getFullYear()
          visible: !isTodayView
          implicitWidth: todayLabel.width + 16
          implicitHeight: 26
          Layout.alignment: Qt.AlignVCenter

          Rectangle {
            anchors.fill: parent
            radius: 6
            color: todayMouse.containsMouse ? "#45475a" : "#313244"
            border.color: todayMouse.containsMouse ? "#585b70" : "transparent"
            border.width: 1

            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }
          }

          Text {
            id: todayLabel
            anchors.centerIn: parent
            text: "Today"
            font.pixelSize: 11
            font.bold: true
            font.family: root.monoFont
            color: "#89b4fa"
          }

          MouseArea {
            id: todayMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.goToday()
          }
        }

        // Chevron prev
        Item {
          width: 26
          height: 26
          Layout.alignment: Qt.AlignVCenter

          Rectangle {
            anchors.fill: parent
            radius: 6
            color: prevMouse.containsMouse ? "#45475a" : "#313244"
            border.color: prevMouse.containsMouse ? "#585b70" : "transparent"
            border.width: 1

            Behavior on color { ColorAnimation { duration: 120 } }
          }

          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: "‹"
            font.pixelSize: 17
            font.bold: true
            color: prevMouse.containsMouse ? "#ffffff" : "#cdd6f4"
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
        Item {
          width: 26
          height: 26
          Layout.alignment: Qt.AlignVCenter

          Rectangle {
            anchors.fill: parent
            radius: 6
            color: nextMouse.containsMouse ? "#45475a" : "#313244"
            border.color: nextMouse.containsMouse ? "#585b70" : "transparent"
            border.width: 1

            Behavior on color { ColorAnimation { duration: 120 } }
          }

          Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: "›"
            font.pixelSize: 17
            font.bold: true
            color: nextMouse.containsMouse ? "#ffffff" : "#cdd6f4"
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

      Item { Layout.preferredHeight: 14 }

      // Weekday initials: Mo Tu We Th Fr Sa Su
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
              color: index >= 5 ? "#f38ba8" : "#6c7086"
              font.pixelSize: 11
              font.bold: true
              font.family: root.monoFont
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

            // Day bubble: radius 8 squircle with comfortable breathing space
            Rectangle {
              anchors.centerIn: parent
              width: 34
              height: 32
              radius: 8

              color: {
                if (isToday) return "#89b4fa";
                if (isSelected) return "#313244";
                if (cellHover.containsMouse && modelData.inMonth) return "#313244";
                return "transparent";
              }

              border.color: {
                if (!isToday && isSelected) return "#89b4fa";
                if (cellHover.containsMouse && modelData.inMonth) return "#45475a";
                return "transparent";
              }
              border.width: 1

              Behavior on color { ColorAnimation { duration: 100 } }
              Behavior on border.color { ColorAnimation { duration: 100 } }

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: modelData.hasEvent ? -2 : 0
                text: modelData.day
                font.pixelSize: 13
                font.bold: isToday || isSelected
                font.family: root.monoFont
                color: {
                  if (isToday) return "#11111b";
                  if (isSelected) return "#ffffff";
                  if (!modelData.inMonth) return "#585b70";
                  if (modelData.isWeekend) return "#f38ba8";
                  return "#cdd6f4";
                }
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
                color: isToday ? "#11111b" : "#fab387"
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

      // Hairline divider (only shown when an event is selected)
      Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        height: 1
        color: "#313244"
        visible: root.selectedEvents.length > 0
      }

      // Selected event line (only event name, no date text)
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 20
        visible: root.selectedEvents.length > 0

        RowLayout {
          anchors.fill: parent
          spacing: 8

          Rectangle {
            width: 5
            height: 5
            radius: 2.5
            color: "#fab387"
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            Layout.fillWidth: true
            text: root.selectedEvents.join(", ")
            color: "#fab387"
            font.pixelSize: 12
            font.bold: true
            font.family: root.monoFont
            elide: Text.ElideRight
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }
}
