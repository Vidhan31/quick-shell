pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"

Rectangle {
  id: root

  property string title: "Top models"
  // Mode: "overview" (OpenCode + Antigravity) | "opencode" | "antigravity"
  property string mode: "overview"

  // Raw model list: [{name, tokens, raw, src, input, output, cacheRead, cacheWrite, reasoning, cost}, ...]
  property var models: []
  property int selectedMonths: 1

  property int topLimit: 5
  property bool showAll: false
  property string expandedModelName: ""

  property var compactFn: function(v) {
    if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
    if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
    if (v >= 1e3) return (v / 1e3).toFixed(1) + "k";
    return Math.round(v).toString();
  }
  property var moneyFn: function(v) {
    return "$" + (v || 0).toFixed(2);
  }

  implicitWidth: 400
  implicitHeight: mainCol.implicitHeight + 24
  radius: Theme.radiusSection
  color: Theme.surface
  border.color: Theme.cardBorder
  border.width: 1

  readonly property double totalTokensSum: {
    let s = 0;
    if (root.models) {
      for (let i = 0; i < root.models.length; ++i) {
        s += (root.models[i].raw || 0);
      }
    }
    return s;
  }

  readonly property double maxIndividualTokens: {
    let m = 0;
    if (root.models) {
      for (let i = 0; i < root.models.length; ++i) {
        if (root.models[i].raw > m) m = root.models[i].raw;
      }
    }
    return m > 0 ? m : 1;
  }

  readonly property int totalCount: root.models ? root.models.length : 0
  readonly property bool hasExcess: root.totalCount > root.topLimit

  readonly property var displayItems: {
    if (!root.models || root.models.length === 0) return [];
    if (root.showAll || !root.hasExcess) {
      return root.models.map(function(m, idx) {
        return {
          rank: idx + 1,
          name: m.name,
          raw: m.raw,
          tokens: m.tokens,
          src: m.src || (root.mode === "opencode" ? "oc" : "agy"),
          input: m.input || 0,
          output: m.output || 0,
          cacheRead: m.cacheRead || 0,
          cacheWrite: m.cacheWrite || 0,
          reasoning: m.reasoning || 0,
          cost: m.cost || 0,
          isOther: false
        };
      });
    }

    const list = [];
    for (let i = 0; i < root.topLimit; ++i) {
      const m = root.models[i];
      list.push({
        rank: i + 1,
        name: m.name,
        raw: m.raw,
        tokens: m.tokens,
        src: m.src || (root.mode === "opencode" ? "oc" : "agy"),
        input: m.input || 0,
        output: m.output || 0,
        cacheRead: m.cacheRead || 0,
        cacheWrite: m.cacheWrite || 0,
        reasoning: m.reasoning || 0,
        cost: m.cost || 0,
        isOther: false
      });
    }

    let otherRaw = 0;
    let otherInput = 0;
    let otherOutput = 0;
    let otherCacheRead = 0;
    let otherCacheWrite = 0;
    let otherReasoning = 0;
    let otherCost = 0;
    const remainingCount = root.totalCount - root.topLimit;

    for (let i = root.topLimit; i < root.totalCount; ++i) {
      const m = root.models[i];
      otherRaw += (m.raw || 0);
      otherInput += (m.input || 0);
      otherOutput += (m.output || 0);
      otherCacheRead += (m.cacheRead || 0);
      otherCacheWrite += (m.cacheWrite || 0);
      otherReasoning += (m.reasoning || 0);
      otherCost += (m.cost || 0);
    }

    list.push({
      rank: 0,
      name: "Other (" + remainingCount + (remainingCount === 1 ? " model" : " models") + ")",
      raw: otherRaw,
      tokens: root.compactFn(otherRaw),
      src: "other",
      input: otherInput,
      output: otherOutput,
      cacheRead: otherCacheRead,
      cacheWrite: otherCacheWrite,
      reasoning: otherReasoning,
      cost: otherCost,
      isOther: true
    });

    return list;
  }

  readonly property double maxDisplayTokens: {
    let m = root.maxIndividualTokens;
    for (let i = 0; i < root.displayItems.length; ++i) {
      if (root.displayItems[i].raw > m) m = root.displayItems[i].raw;
    }
    return m > 0 ? m : 1;
  }

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
            text: "·  " + (root.selectedMonths === 1 ? "1 month" : (root.selectedMonths + " months"))
            font.pixelSize: 11
            font.family: Theme.mono
            color: Theme.ink3
          }
        }

        Text {
          text: root.totalCount + (root.totalCount === 1 ? " model active" : " models active")
          font.pixelSize: 10
          font.family: Theme.mono
          color: Theme.ink3
        }
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        visible: root.hasExcess
        Layout.preferredHeight: 22
        Layout.preferredWidth: toggleRow.implicitWidth + 4
        radius: 11
        color: Theme.inset
        border.color: Theme.cardBorder
        border.width: 1

        Row {
          id: toggleRow
          anchors.centerIn: parent
          spacing: 2

          Rectangle {
            height: 18
            width: topBtnText.implicitWidth + 12
            radius: 9
            color: !root.showAll ? Theme.selected : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

            Text {
              id: topBtnText
              anchors.centerIn: parent
              text: "Top " + root.topLimit
              font.pixelSize: 10
              font.weight: !root.showAll ? Font.DemiBold : Font.Normal
              font.family: Theme.mono
              color: !root.showAll ? Theme.ink1 : Theme.ink3
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showAll = false
            }
          }

          Rectangle {
            height: 18
            width: allBtnText.implicitWidth + 12
            radius: 9
            color: root.showAll ? Theme.selected : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

            Text {
              id: allBtnText
              anchors.centerIn: parent
              text: "All (" + root.totalCount + ")"
              font.pixelSize: 10
              font.weight: root.showAll ? Font.DemiBold : Font.Normal
              font.family: Theme.mono
              color: root.showAll ? Theme.ink1 : Theme.ink3
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showAll = true
            }
          }
        }
      }
    }

    Hairline {
      width: parent.width
      color: Theme.lineMuted
    }

    Item {
      visible: root.displayItems.length === 0
      width: parent.width
      height: 60

      Text {
        anchors.centerIn: parent
        text: "No model activity recorded in this period"
        font.pixelSize: 11
        font.family: Theme.mono
        color: Theme.ink3
      }
    }

    Column {
      visible: root.displayItems.length > 0
      width: parent.width
      spacing: 6

      Repeater {
        model: root.displayItems

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

          readonly property bool isExpanded: root.expandedModelName === rowBox.modelData.name

          Accessible.role: Accessible.Button
          Accessible.name: (rowBox.modelData.isOther ? "Other models" : rowBox.modelData.name) + ", " + rowBox.modelData.tokens

          Behavior on color { ColorAnimation { duration: Theme.durationFast } }
          Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

          function activate(): void {
            if (rowBox.modelData.isOther) {
              root.showAll = true;
            } else {
              root.expandedModelName = (root.expandedModelName === rowBox.modelData.name ? "" : rowBox.modelData.name);
            }
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
                text: rowBox.modelData.isOther ? "•" : ("#" + rowBox.modelData.rank)
                font.pixelSize: 11
                font.weight: rowBox.modelData.rank <= 3 && !rowBox.modelData.isOther ? Font.Bold : Font.Normal
                font.family: Theme.mono
                color: {
                  if (rowBox.modelData.isOther) return Theme.ink3;
                  if (rowBox.modelData.rank === 1) return Theme.amber;
                  if (rowBox.modelData.rank === 2) return Theme.ink1;
                  if (rowBox.modelData.rank === 3) return Theme.ink2;
                  return Theme.ink3;
                }
              }

              Rectangle {
                visible: root.mode === "overview"
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                Layout.alignment: Qt.AlignVCenter
                radius: 3
                color: {
                  if (rowBox.modelData.isOther) return Theme.ink3;
                  return rowBox.modelData.src === "oc" ? Theme.teal : Theme.violet;
                }
              }

              Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: rowBox.modelData.name
                font.pixelSize: 12
                font.weight: rowBox.modelData.rank === 1 ? Font.DemiBold : Font.Normal
                font.family: Theme.mono
                color: rowBox.modelData.isOther ? Theme.ink2 : Theme.ink1
                elide: Text.ElideMiddle
              }

              Text {
                Layout.alignment: Qt.AlignVCenter
                text: rowBox.modelData.tokens
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.family: Theme.mono
                color: Theme.ink1
              }

              Text {
                Layout.preferredWidth: 42
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                horizontalAlignment: Text.AlignRight
                text: {
                  if (root.totalTokensSum <= 0) return "0.0%";
                  const pct = (rowBox.modelData.raw / root.totalTokensSum) * 100;
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
                  id: barFill
                  height: parent.height
                  radius: parent.radius
                  width: Math.max(3, Math.round(barTrack.width * Math.min(1.0, rowBox.modelData.raw / root.maxDisplayTokens)))
                  color: {
                    if (rowBox.modelData.isOther) return Theme.ink3;
                    if (root.mode === "overview") {
                      return rowBox.modelData.src === "oc" ? Theme.teal : Theme.violet;
                    }
                    return root.mode === "opencode" ? Theme.teal : Theme.violet;
                  }

                  Behavior on width {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                  }
                }
              }
            }

            Column {
              id: detailDrawer
              visible: rowBox.isExpanded && !rowBox.modelData.isOther
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
                  Text { text: "Input:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.input); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  spacing: 4
                  Text { text: "Output:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.output); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  spacing: 4
                  Text { text: "Cache:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.cacheRead); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: rowBox.modelData.reasoning > 0
                  spacing: 4
                  Text { text: "Reasoning:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.reasoning); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: rowBox.modelData.cacheWrite > 0
                  spacing: 4
                  Text { text: "Cache W:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.compactFn(rowBox.modelData.cacheWrite); font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink2 }
                }

                Row {
                  visible: rowBox.modelData.cost > 0
                  spacing: 4
                  Text { text: "Cost:"; font.pixelSize: 10; font.family: Theme.mono; color: Theme.ink3 }
                  Text { text: root.moneyFn(rowBox.modelData.cost); font.pixelSize: 10; font.family: Theme.mono; color: Theme.green }
                }
              }
            }
          }
        }
      }
    }

    Item {
      visible: root.hasExcess
      width: parent.width
      height: 20

      Rectangle {
        id: footerPill
        anchors.centerIn: parent
        width: footerText.implicitWidth + 16
        height: 18
        radius: 9
        color: (footerMouse.containsMouse || footerPill.activeFocus) ? Theme.hoverWash : "transparent"
        border.width: footerPill.activeFocus ? Theme.focusRingWidth : 0
        border.color: Theme.focusRing
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.showAll ? ("Show top " + root.topLimit) : ("Show all " + root.totalCount + " models")

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

        Keys.onReturnPressed: event => {
          root.showAll = !root.showAll;
          event.accepted = true;
        }
        Keys.onSpacePressed: event => {
          root.showAll = !root.showAll;
          event.accepted = true;
        }

        Text {
          id: footerText
          anchors.centerIn: parent
          text: root.showAll ? ("Show top " + root.topLimit + " ▴") : ("Show all " + root.totalCount + " models ▾")
          font.pixelSize: 10
          font.family: Theme.mono
          color: (footerMouse.containsMouse || footerPill.activeFocus) ? Theme.ink1 : Theme.ink3
        }

        MouseArea {
          id: footerMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.showAll = !root.showAll
        }
      }
    }
  }
}
