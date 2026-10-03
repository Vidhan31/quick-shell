pragma ComponentBehavior: Bound
/* Rows carry hypothetical official-API cost, not tokens:
   [{name, src, tokensText, rawTokens, hypo (NaN when unpriced),
     provider, family, viaFallback, matchedId,
     input, output, cacheRead, cacheWrite, reasoning,
     rateIn, rateOut, rateCacheRead, rateCacheWrite}, ...]
   Sorted by hypo descending (unpriced last) by the caller. */
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../../theme"
import "../../components"

Rectangle {
  id: root

  property string title: "Models by cost"
  property var models: []
  property int selectedMonths: 1
  property string emptyText: "No model activity recorded in this period"

  property var compactFn: function(v) {
    if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
    if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
    if (v >= 1e3) return (v / 1e3).toFixed(1) + "k";
    return Math.round(v).toString();
  }
  property var moneyFn: function(v) {
    return "$" + (v || 0).toFixed(2);
  }
  property var logoFn: function(providerId) { return ""; }
  property string expandedModelName: ""

  // Sum of priced rows only; unpriced (NaN) rows are excluded.
  readonly property double totalHypoSum: {
    let s = 0;
    if (root.models) {
      for (let i = 0; i < root.models.length; ++i) {
        const h = root.models[i].hypo;
        if (!isNaN(h)) s += h;
      }
    }
    return s;
  }

  readonly property double maxHypo: {
    let m = 0;
    if (root.models) {
      for (let i = 0; i < root.models.length; ++i) {
        const h = root.models[i].hypo;
        if (!isNaN(h) && h > m) m = h;
      }
    }
    return m > 0 ? m : 1;
  }

  readonly property int pricedCount: {
    let n = 0;
    if (root.models) {
      for (let i = 0; i < root.models.length; ++i) {
        if (!isNaN(root.models[i].hypo)) ++n;
      }
    }
    return n;
  }

  implicitWidth: 400
  implicitHeight: mainCol.implicitHeight + 24
  radius: Theme.radiusSection
  color: Theme.surface
  border.color: Theme.cardBorder
  border.width: 1

  Column {
    id: mainCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 12
    spacing: 10

    RowLayout {
      width: parent.width
      height: 24

      Column {
        spacing: 1
        Row {
          spacing: 6
          Text {
            text: root.title
            font.pixelSize: Theme.fontBase
            font.weight: Font.DemiBold
            font.family: Theme.sans
            color: Theme.ink1
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "· " + (root.selectedMonths === 1 ? "1 month" : (root.selectedMonths + " months"))
            font.pixelSize: 11
            font.family: Theme.mono
            color: Theme.ink3
          }
        }
        Text {
          text: {
            const total = root.models ? root.models.length : 0;
            if (root.pricedCount === total) {
              return total + (total === 1 ? " model priced" : " models priced");
            }
            return root.pricedCount + " of " + total + " models priced";
          }
          font.pixelSize: 10
          font.family: Theme.mono
          color: Theme.ink3
        }
      }

      Item { Layout.fillWidth: true }

      Text {
        Layout.alignment: Qt.AlignVCenter
        text: root.moneyFn(root.totalHypoSum)
        font.pixelSize: 14
        font.weight: Font.DemiBold
        font.family: Theme.mono
        color: Theme.green
      }
    }

    Hairline {
      width: parent.width
      color: Theme.lineMuted
    }

    Item {
      visible: !root.models || root.models.length === 0
      width: parent.width
      height: 60

      Text {
        anchors.centerIn: parent
        text: root.emptyText
        font.pixelSize: 11
        font.family: Theme.mono
        color: Theme.ink3
      }
    }

    Column {
      visible: root.models && root.models.length > 0
      width: parent.width
      spacing: 6

      Repeater {
        model: root.models

        Rectangle {
          id: rowBox
          required property var modelData
          required property int index

          width: parent.width
          implicitHeight: rowCol.implicitHeight + 8
          radius: Theme.radiusBase
          color: rowBox.isExpanded ? Theme.selected : (rowMouse.containsMouse || rowBox.activeFocus ? Theme.hoverFill : "transparent")
          border.width: rowBox.activeFocus ? Theme.focusRingWidth : 0
          border.color: Theme.focusRing
          activeFocusOnTab: true

          readonly property bool priced: !isNaN(rowBox.modelData.hypo)
          readonly property bool isExpanded: root.expandedModelName === rowBox.modelData.name + "|" + rowBox.modelData.src

          Accessible.role: Accessible.Button
          Accessible.name: rowBox.modelData.name + (rowBox.priced ? (", " + root.moneyFn(rowBox.modelData.hypo)) : ", unpriced")

          Behavior on color { ColorAnimation { duration: Theme.durationFast } }
          Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

          function activate(): void {
            const key = rowBox.modelData.name + "|" + rowBox.modelData.src;
            root.expandedModelName = (root.expandedModelName === key ? "" : key);
          }

          Keys.onReturnPressed: event => {
            rowBox.activate();
            event.accepted = true;
          }
          Keys.onSpacePressed: event => {
            rowBox.activate();
            event.accepted = true;
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rowBox.activate()
          }

          Column {
            id: rowCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 5

            RowLayout {
              width: parent.width
              height: 22
              spacing: 8

              Text {
                Layout.preferredWidth: 20
                Layout.alignment: Qt.AlignVCenter
                text: "#" + (rowBox.index + 1)
                font.pixelSize: 11
                font.weight: rowBox.index < 3 ? Font.Bold : Font.Normal
                font.family: Theme.mono
                color: {
                  if (rowBox.index === 0) return Theme.amber;
                  if (rowBox.index === 1) return Theme.ink1;
                  if (rowBox.index === 2) return Theme.ink2;
                  return Theme.ink3;
                }
              }

              Rectangle {
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                Layout.alignment: Qt.AlignVCenter
                radius: 3
                color: rowBox.modelData.src === "oc" ? Theme.teal : Theme.violet
              }

              Item {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                visible: rowBox.priced && logoImg.status === Image.Ready

                Image {
                  id: logoImg
                  anchors.fill: parent
                  visible: false
                  source: rowBox.priced ? root.logoFn(rowBox.modelData.provider) : ""
                  sourceSize.width: 28
                  sourceSize.height: 28
                  fillMode: Image.PreserveAspectFit
                }

                ColorOverlay {
                  anchors.fill: logoImg
                  source: logoImg
                  color: Theme.ink1
                }
              }

              RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                Text {
                  Layout.fillWidth: true
                  text: rowBox.modelData.name
                  font.pixelSize: 12
                  font.weight: (rowBox.priced && rowBox.index === 0) ? Font.DemiBold : Font.Normal
                  font.family: Theme.mono
                  color: rowBox.priced ? Theme.ink1 : Theme.ink3
                  elide: Text.ElideMiddle
                }

                Rectangle {
                  id: tagPill
                  visible: !rowBox.priced || (rowBox.modelData.isOverride === true) || (rowBox.modelData.viaFallback === true)
                  Layout.preferredHeight: 14
                  Layout.preferredWidth: tagText.implicitWidth + 8
                  radius: 7
                  color: {
                    if (!rowBox.priced) return Theme.surfaceElevated;
                    if (rowBox.modelData.isOverride) return Theme.accentBg;
                    return Theme.violetBg;
                  }
                  border.width: 1
                  border.color: {
                    if (!rowBox.priced) return Theme.lineMuted;
                    if (rowBox.modelData.isOverride) return Theme.accent;
                    return Theme.violet;
                  }

                  Text {
                    id: tagText
                    anchors.centerIn: parent
                    text: {
                      if (!rowBox.priced) return "unpriced";
                      if (rowBox.modelData.isOverride) return "override";
                      if (rowBox.modelData.viaFallback) return "tier";
                      return "";
                    }
                    font.pixelSize: 8
                    font.family: Theme.mono
                    color: {
                      if (!rowBox.priced) return Theme.ink3;
                      if (rowBox.modelData.isOverride) return Theme.accent;
                      return Theme.violet;
                    }
                  }
                }
              }

              Text {
                Layout.alignment: Qt.AlignVCenter
                text: rowBox.priced ? root.moneyFn(rowBox.modelData.hypo) : "—"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.family: Theme.mono
                color: rowBox.priced ? Theme.green : Theme.ink3
              }

              Text {
                Layout.preferredWidth: 42
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                horizontalAlignment: Text.AlignRight
                text: {
                  if (!rowBox.priced || root.totalHypoSum <= 0) return "";
                  const pct = (rowBox.modelData.hypo / root.totalHypoSum) * 100;
                  return (pct < 0.1 && pct > 0 ? "<0.1%" : (pct.toFixed(1) + "%"));
                }
                font.pixelSize: 11
                font.family: Theme.mono
                color: Theme.ink3
              }
            }

            Item {
              width: parent.width
              height: 5

              Rectangle {
                id: barTrack
                anchors.fill: parent
                radius: 2.5
                color: Theme.lineMuted

                Rectangle {
                  height: parent.height
                  radius: parent.radius
                  width: rowBox.priced
                    ? Math.max(3, Math.round(barTrack.width * Math.min(1.0, rowBox.modelData.hypo / root.maxHypo)))
                    : 0
                  color: rowBox.modelData.src === "oc" ? Theme.teal : Theme.violet

                  Behavior on width {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                  }
                }
              }
            }

            Column {
              visible: rowBox.isExpanded
              width: parent.width
              spacing: 4
              topPadding: 4
              bottomPadding: 2

              Hairline {
                width: parent.width
                color: Theme.cardBorder
              }

              GridLayout {
                width: parent.width
                columns: 3
                rowSpacing: 4
                columnSpacing: 8

                Row {
                  spacing: 4
                  Text { text: "Tokens:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: rowBox.modelData.tokensText; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  spacing: 4
                  Text { text: "Provider:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: rowBox.priced ? rowBox.modelData.provider : "unknown"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: rowBox.priced
                  spacing: 4
                  Text { text: "Rate:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: "$" + rowBox.modelData.rateIn + " / $" + rowBox.modelData.rateOut + " per 1M"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  spacing: 4
                  Text { text: "Input:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.input); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  spacing: 4
                  Text { text: "Output:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.output); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: Boolean(rowBox.modelData.reasoning > 0)
                  spacing: 4
                  Text { text: "Reasoning:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.reasoning); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  spacing: 4
                  Text { text: "Cache:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.cacheRead); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: Boolean(rowBox.modelData.cacheWrite > 0)
                  spacing: 4
                  Text { text: "Cache write:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.cacheWrite); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: rowBox.priced && rowBox.modelData.viaFallback
                  spacing: 4
                  Text { text: "Mapped from:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: rowBox.modelData.matchedId; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: Boolean(rowBox.modelData.savings > 0)
                  spacing: 4
                  Text { text: "Cache saved:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.moneyFn(rowBox.modelData.savings); font.pixelSize: 10; font.family: Theme.mono; color: Theme.teal }
                }

                Row {
                  visible: Boolean(rowBox.modelData.isOverride)
                  spacing: 4
                  Text { text: "Source:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: "custom override"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.accent }
                }

                Row {
                  visible: !rowBox.priced
                  spacing: 4
                  Text { text: "Status:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: "unpriced"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                }
              }
            }
          }
        }
      }
    }
  }
}
