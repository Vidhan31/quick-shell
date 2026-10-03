pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property string icsPath: Quickshell.shellPath("assets/holidays.ics")
  property var eventsByDate: ({})

  readonly property alias fileView: icsFile
  readonly property bool loaded: icsFile.loaded

  FileView {
    id: icsFile
    path: root.icsPath
    onLoaded: root.loadEvents()
    onLoadFailed: error => {
      console.warn("HolidayProvider: failed to load ics file:", error);
    }
  }

  function dateKey(d: date): string {
    if (!d) return "";
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

  function eventsForDate(d: date): var {
    if (!d) return [];
    const k = dateKey(d);
    return (eventsByDate && eventsByDate[k]) ? eventsByDate[k] : [];
  }

  function hasEvents(d: date): bool {
    return eventsForDate(d).length > 0;
  }

  function loadEvents(): void {
    eventsByDate = parseIcs(icsFile.text());
  }

  Component.onCompleted: {
    if (icsFile.loaded) {
      loadEvents();
    }
  }
}
