pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"

Item {
  id: root

  property date today: new Date()
  property date selectedDate: today
  property int shownYear: -1
  property int shownMonth: -1 // 0-11
  property var cells: []

  property var holidayProvider: null
  property var eventsByDate: holidayProvider ? holidayProvider.eventsByDate : ({})
  property var selectedEvents: []

  readonly property var t: Theme

  readonly property string monoFont: root.t.mono

  readonly property var monthNames: {
    const list = [];
    for (let i = 0; i < 12; ++i) {
      list.push(Qt.locale().standaloneMonthName(i, Locale.LongFormat));
    }
    return list;
  }
  readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek
  readonly property var weekDays: {
    const list = [];
    for (let i = 0; i < 7; ++i) {
      const day = (root.firstDayOfWeek + i) % 7;
      list.push(Qt.locale().dayName(day, Locale.ShortFormat));
    }
    return list;
  }

  implicitWidth: Theme.popupWidthSm
  implicitHeight: 388

  function findHost(): var {
    let p = root.parent;
    while (p) {
      if (typeof p.showTip === "function") return p;
      if (p.barWindow && typeof p.barWindow.showTip === "function") return p.barWindow;
      p = p.parent;
    }
    return null;
  }

  Component.onDestruction: {
    const host = root.findHost();
    if (host && typeof host.hideTip === "function") {
      host.hideTip();
    }
  }

  function updateSelectedEvents(): void {
    if (!selectedDate || !root.holidayProvider) {
      selectedEvents = [];
      return;
    }
    selectedEvents = root.holidayProvider.eventsForDate(selectedDate);
  }

  onSelectedDateChanged: updateSelectedEvents()
  onEventsByDateChanged: {
    rebuild();
    updateSelectedEvents();
  }

  function daysInMonth(y: int, m: int): int {
    return new Date(y, m + 1, 0).getDate();
  }

  function monthStartOffset(y: int, m: int): int {
    const day = new Date(y, m, 1).getDay();
    return (day - root.firstDayOfWeek + 7) % 7;
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

      const evs = root.holidayProvider ? root.holidayProvider.eventsForDate(cellDate) : [];
      const dayOfWeek = cellDate.getDay();

      arr.push({
        day: cellDay,
        date: cellDate,
        inMonth: inMonth,
        isWeekend: (dayOfWeek === 0 || dayOfWeek === 6),
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
    const d = new Date();
    shownYear = d.getFullYear();
    shownMonth = d.getMonth();
    selectedDate = d;
    rebuild();
    updateSelectedEvents();
  }

  Component.onCompleted: {
    const d = today;
    shownYear = d.getFullYear();
    shownMonth = d.getMonth();
    selectedDate = d;
    rebuild();
    updateSelectedEvents();
  }

  function moveSelectedDay(delta: int): void {
    const cur = selectedDate ? new Date(selectedDate) : new Date(today);
    cur.setDate(cur.getDate() + delta);
    selectedDate = cur;
    if (cur.getMonth() !== shownMonth || cur.getFullYear() !== shownYear) {
      shownYear = cur.getFullYear();
      shownMonth = cur.getMonth();
      rebuild();
    }
  }

  activeFocusOnTab: true

  Keys.onLeftPressed: event => {
    root.moveSelectedDay(-1);
    event.accepted = true;
  }
  Keys.onRightPressed: event => {
    root.moveSelectedDay(1);
    event.accepted = true;
  }
  Keys.onUpPressed: event => {
    root.moveSelectedDay(-7);
    event.accepted = true;
  }
  Keys.onDownPressed: event => {
    root.moveSelectedDay(7);
    event.accepted = true;
  }
  Keys.onPressed: event => {
    if (event.key === Qt.Key_PageUp) {
      root.prevMonth();
      event.accepted = true;
    } else if (event.key === Qt.Key_PageDown) {
      root.nextMonth();
      event.accepted = true;
    }
  }

  onTodayChanged: rebuild()

  PopupCard {
    id: card
    anchors.fill: parent

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
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        spacing: 4

        Row {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: 6
          Text {
            text: root.shownMonth >= 0 ? root.monthNames[root.shownMonth] : ""
            color: root.t.ink1
            font.family: Theme.displayFont
            font.pixelSize: Theme.fontMd
            font.weight: Font.DemiBold
          }
          Text {
            text: root.shownYear >= 0 ? root.shownYear : ""
            color: root.t.ink3
            font.family: Theme.displayFont
            font.pixelSize: Theme.fontMd
          }
        }

        TextBtn {
          visible: !(root.shownMonth === root.today.getMonth() && root.shownYear === root.today.getFullYear())
          Layout.alignment: Qt.AlignVCenter
          text: "Today"
          bold: true
          fg: root.t.accent
          fs: 11
          onClicked: root.goToday()
        }

        IconBtn {
          Layout.alignment: Qt.AlignVCenter
          glyph: "‹"
          fs: 17
          fg: root.t.ink2
          btnSize: 30
          tooltip: "Previous month"
          onClicked: root.prevMonth()
        }

        IconBtn {
          Layout.alignment: Qt.AlignVCenter
          glyph: "›"
          fs: 17
          fg: root.t.ink2
          btnSize: 30
          tooltip: "Next month"
          onClicked: root.nextMonth()
        }
      }

      Item { Layout.preferredHeight: 12; Layout.fillWidth: true }

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
              color: root.t.ink3
              font.family: Theme.textFont
              font.pixelSize: Theme.fontSm
              font.bold: true
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 0.8
            }
          }
        }
      }

      Item { Layout.preferredHeight: 8 }

      Grid {
        columns: 7
        rows: 6
        spacing: 0
        Layout.fillWidth: true

        Repeater {
          model: root.cells
          delegate: Item {
            id: dayCell
            required property var modelData
            width: 42
            height: 36

            readonly property bool isToday: root.sameDay(dayCell.modelData.date, root.today)
            readonly property bool isSelected: root.sameDay(dayCell.modelData.date, root.selectedDate)

            // border.width stays 1 with transparent fallback so hover
            // never triggers a layout pass inside the Grid.
            Rectangle {
              anchors.centerIn: parent
              width: 34
              height: 32
              radius: Theme.radiusBase

              color: {
                if (dayCell.isToday) return root.t.accent;
                if (dayCell.isSelected) return root.t.selected;
                if (cellHover.pressed && dayCell.modelData.inMonth) return root.t.pressWash;
                if (cellHover.containsMouse && dayCell.modelData.inMonth) return root.t.hoverFill;
                return "transparent";
              }

              border.color: (dayCell.isSelected && root.activeFocus) ? root.t.focusRing : "transparent"
              border.width: (dayCell.isSelected && root.activeFocus) ? 1.5 : 0

              Behavior on color { ColorAnimation { duration: 90 } }
              Behavior on border.color { ColorAnimation { duration: 90 } }

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: dayCell.modelData.hasEvent ? -2 : 0
                text: dayCell.modelData.day
                font.pixelSize: Theme.fontMd
                font.weight: (dayCell.isToday || dayCell.isSelected) ? Font.DemiBold : Font.Normal
                font.family: Theme.roundedFont
                color: {
                  if (dayCell.isToday) return root.t.darkInk;
                  if (dayCell.isSelected) return root.t.ink1;
                  if (!dayCell.modelData.inMonth) return root.t.ink3;
                  if (dayCell.modelData.isWeekend) return root.t.red;
                  return root.t.ink1;
                }
                Behavior on color { ColorAnimation { duration: 90 } }
              }

              Rectangle {
                visible: !!dayCell.modelData.hasEvent
                width: 4
                height: 4
                radius: 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                color: dayCell.isToday ? root.t.darkInk : root.t.amber
              }
            }

            MouseArea {
              id: cellHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: {
                const host = root.findHost();
                if (containsMouse && dayCell.modelData.hasEvent) {
                  const evs = dayCell.modelData.events;
                  if (evs && evs.length > 0) {
                    if (host && typeof host.showTip === "function") {
                      const title = typeof evs[0] === "string" ? evs[0] : (evs[0].name || "");
                      const sub = typeof evs[0] === "string" ? "" : (evs[0].category || "");
                      host.showTip(parent, title, sub);
                    }
                  }
                } else {
                  if (host && typeof host.hideTip === "function") {
                    host.hideTip();
                  }
                }
              }
              onClicked: {
                const host = root.findHost();
                if (host && typeof host.hideTip === "function") {
                  host.hideTip();
                }
                root.selectedDate = dayCell.modelData.date;
                if (!dayCell.modelData.inMonth) {
                  root.shownYear = dayCell.modelData.date.getFullYear();
                  root.shownMonth = dayCell.modelData.date.getMonth();
                  root.rebuild();
                }
              }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        Layout.preferredHeight: 1
        color: root.t.line
        visible: root.selectedEvents.length > 0
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        visible: root.selectedEvents.length > 0
        radius: Theme.radiusChip
        color: root.t.surface

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 8

          Rectangle {
            Layout.preferredWidth: 5
            Layout.preferredHeight: 5
            radius: 2.5
            color: root.t.amber
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            Layout.fillWidth: true
            text: root.selectedEvents.join(", ")
            color: root.t.ink1
            font.pixelSize: Theme.fontBase
            font.weight: Font.Medium
            elide: Text.ElideRight
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }
}
