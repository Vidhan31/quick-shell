pragma ComponentBehavior: Bound
// TokenControlCenter.qml — past OpenCode usage grouped by day, week, month.
// Plain numbers, one manual refresh button, no polling.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Plugins.TokenUsage

Item {
  id: root

  property TokenUsage monitor: null
  property var barWindow: null
  property var popupWindow: null

  signal triggerRefresh()

  implicitWidth: 360
  implicitHeight: card.height

  // Hover tooltip state, same pattern as the system tray tooltip: arm on
  // enter, show after a short delay, hide on exit. The tooltip is its own
  // window so showing it never resizes this popup.
  property var tipDetails: null
  property Item tipTarget: null
  property int tipX: 0
  property int tipY: 0

  Timer {
    id: tipTimer
    interval: 350
    repeat: false
    onTriggered: root.showTip()
  }

  function showTip(): void {
    if (root.tipDetails === null || root.tipTarget === null) {
      return;
    }
    if (root.barWindow === null || root.popupWindow === null) {
      return;
    }
    const pt = root.tipTarget.mapToItem(root, root.tipTarget.width / 2, root.tipTarget.height);
    const frame = root.popupWindow.anchor.rect;
    root.tipX = frame.x + pt.x;
    root.tipY = frame.y + pt.y;
    tip.visible = true;
  }

  function hideTip(): void {
    tipTimer.stop();
    tip.visible = false;
    root.tipDetails = null;
    root.tipTarget = null;
  }

  readonly property bool busy: root.monitor ? root.monitor.busy : false
  readonly property string errorText: root.monitor ? root.monitor.error : ""
  readonly property string updatedText: (root.monitor && root.monitor.lastRefresh !== "") ? root.monitor.lastRefresh : "never"

  function money(value: double): string {
    return "$" + value.toFixed(2);
  }

  // Model rows, preformatted for the same delegate reason.
  readonly property var modelRows: root.monitor === null ? [] : root.monitor.monthModels.map(function (m) {
    return {
      name: m.name,
      tokens: root.monitor.compact(m.tokens),
      sub: root.monitor.compact(m.messages) + " msgs"
    };
  })

  // Preformatted rows: the delegate only reads its own modelData, so no
  // outer id leaks into the Repeater scope.
  function splitDetails(split: var, cost: double, messages: double): var {
    return [
      { k: "Input", v: root.monitor.compact(split.input) },
      { k: "Output", v: root.monitor.compact(split.output) },
      { k: "Cache read", v: root.monitor.compact(split.cacheRead) },
      { k: "Cache write", v: root.monitor.compact(split.cacheWrite) },
      { k: "Reasoning", v: root.monitor.compact(split.reasoning) },
      { k: "Messages", v: root.monitor.compact(messages) },
      { k: "Cost", v: root.money(cost) }
    ];
  }

  readonly property var rows: root.monitor === null ? [] : [
    {
      label: "Today",
      tokens: root.monitor.compact(root.monitor.todayTokens),
      details: root.splitDetails(root.monitor.todaySplit, root.monitor.todayCost, root.monitor.todayMessages)
    },
    {
      label: "This week",
      tokens: root.monitor.compact(root.monitor.weekTokens),
      details: root.splitDetails(root.monitor.weekSplit, root.monitor.weekCost, root.monitor.weekMessages)
    },
    {
      label: "This month",
      tokens: root.monitor.compact(root.monitor.monthTokens),
      details: root.splitDetails(root.monitor.monthSplit, root.monitor.monthCost, root.monitor.monthMessages)
    }
  ]

  Rectangle {
    id: card
    width: root.implicitWidth
    height: content.height + 28
    radius: 12
    color: "#1e1e2e"
    border.color: "#313244"
    border.width: 1

    ColumnLayout {
      id: content
      x: 16
      y: 14
      width: parent.width - 32
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 6

        Text {
          text: "OpenCode usage"
          color: "#ffffff"
          font.pixelSize: 14
          font.bold: true
          font.family: "JetBrainsMono Nerd Font Mono"
          Layout.fillWidth: true
        }

        Rectangle {
          id: refreshButton
          implicitWidth: 86
          implicitHeight: 26
          radius: 6
          color: refreshMouse.containsMouse ? "#45475a" : "#313244"
          opacity: (root.busy || root.monitor === null) ? 0.5 : 1.0

          Text {
            anchors.centerIn: parent
            text: root.busy ? "Working" : "Refresh"
            color: "#C9C9D6"
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font Mono"
          }

          MouseArea {
            id: refreshMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            enabled: !root.busy && root.monitor !== null
            onClicked: root.triggerRefresh()
          }
        }
      }

      Repeater {
        model: root.rows

          delegate: ColumnLayout {
            id: rowDelegate
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 0

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 1
              color: "#313244"
              visible: rowDelegate.index > 0
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.topMargin: 10
              Layout.bottomMargin: 10

              Text {
                text: rowDelegate.modelData.label
                color: "#a6adc8"
                font.pixelSize: 13
                font.family: "JetBrainsMono Nerd Font Mono"
                Layout.fillWidth: true
              }

              Item {
                id: infoParent
                implicitWidth: 20
                implicitHeight: 20

                Rectangle {
                  anchors.fill: parent
                  radius: 10
                  color: infoMouse.containsMouse ? "#45475a" : "transparent"
                  border.color: infoMouse.containsMouse ? "#89b4fa" : "#585b70"
                  border.width: 1

                  Text {
                    anchors.centerIn: parent
                    text: "i"
                    color: "#a6adc8"
                    font.pixelSize: 11
                    font.family: "JetBrainsMono Nerd Font Mono"
                  }
                }

                MouseArea {
                  id: infoMouse
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true
                  onEntered: {
                    root.tipDetails = { label: rowDelegate.modelData.label, rows: rowDelegate.modelData.details };
                    root.tipTarget = infoParent;
                    tipTimer.restart();
                  }
                  onExited: root.hideTip()
                  onClicked: root.showTip()
                }
              }

            ColumnLayout {
              spacing: 2

              Text {
                text: rowDelegate.modelData.tokens
                color: "#ffffff"
                font.pixelSize: 14
                font.bold: true
                font.family: "JetBrainsMono Nerd Font Mono"
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
              }
            }
          }
        }
      }

      PopupWindow {
        id: tip
        anchor.window: root.barWindow
        anchor.rect.x: root.barWindow ? Math.max(8, Math.min(root.tipX - tipBox.width / 2, root.barWindow.width - tipBox.width - 12)) : 0
        anchor.rect.y: root.tipY
        visible: false
        implicitWidth: tipBox.width
        implicitHeight: tipBox.height
        color: "transparent"

        Rectangle {
          id: tipBox
          implicitWidth: Math.max(50, tipCol.implicitWidth + 16)
          implicitHeight: tipCol.implicitHeight + 10
          radius: 6
          color: "#181825"
          border.color: "#45475a"
          border.width: 1

          Column {
            id: tipCol
            anchors.centerIn: parent
            spacing: 3

            Text {
              text: root.tipDetails ? root.tipDetails.label : ""
              color: "#cdd6f4"
              font.pixelSize: 11
              font.bold: true
              font.family: "JetBrainsMono Nerd Font Mono"
            }

            Repeater {
              model: root.tipDetails ? root.tipDetails.rows : []

              delegate: Row {
                id: tipDelegate
                required property var modelData
                required property int index
                spacing: 12

                Text {
                  width: 78
                  text: tipDelegate.modelData.k
                  color: "#6F6F84"
                  font.pixelSize: 11
                  font.family: "JetBrainsMono Nerd Font Mono"
                }

                Text {
                  text: tipDelegate.modelData.v
                  color: "#C9C9D6"
                  font.pixelSize: 11
                  font.family: "JetBrainsMono Nerd Font Mono"
                }
              }
            }
          }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        visible: root.modelRows.length > 0

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          Layout.topMargin: 4
          color: "#313244"
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 10
          Layout.bottomMargin: 2
          text: "Models · this month"
          color: "#a6adc8"
          font.pixelSize: 13
          font.family: "JetBrainsMono Nerd Font Mono"
        }

        Repeater {
          model: root.modelRows

          delegate: ColumnLayout {
            id: modelDelegate
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
              Layout.fillWidth: true
              Layout.topMargin: 8
              Layout.bottomMargin: 8

              Text {
                text: modelDelegate.modelData.name
                color: "#a6adc8"
                font.pixelSize: 12
                font.family: "JetBrainsMono Nerd Font Mono"
                elide: Text.ElideMiddle
                Layout.fillWidth: true
              }

              ColumnLayout {
                spacing: 2

                Text {
                  text: modelDelegate.modelData.tokens
                  color: "#ffffff"
                  font.pixelSize: 13
                  font.family: "JetBrainsMono Nerd Font Mono"
                  horizontalAlignment: Text.AlignRight
                  Layout.fillWidth: true
                }

                Text {
                  text: modelDelegate.modelData.sub
                  color: "#6F6F84"
                  font.pixelSize: 11
                  font.family: "JetBrainsMono Nerd Font Mono"
                  horizontalAlignment: Text.AlignRight
                  Layout.fillWidth: true
                }
              }
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.topMargin: 8
        text: "Updated " + root.updatedText
        color: "#6F6F84"
        font.pixelSize: 11
        font.family: "JetBrainsMono Nerd Font Mono"
      }

      Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        visible: root.errorText !== ""
        text: root.errorText
        color: "#f38ba8"
        font.pixelSize: 11
        font.family: "JetBrainsMono Nerd Font Mono"
        wrapMode: Text.Wrap
      }
    }
  }
}
