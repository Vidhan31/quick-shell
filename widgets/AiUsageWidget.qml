pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

Item {
  id: root

  implicitWidth: contentRow.implicitWidth
  implicitHeight: Math.max(20, contentRow.implicitHeight)

  property var aiUsage: null

  readonly property var oc: aiUsage ? aiUsage.oc : null
  readonly property var agy: aiUsage ? aiUsage.agy : null
  readonly property var pricing: aiUsage ? aiUsage.pricing : null

  readonly property bool isBusy: aiUsage ? aiUsage.isBusy : false
  readonly property bool ocConfigured: aiUsage ? aiUsage.ocConfigured : false
  readonly property bool agyConfigured: aiUsage ? aiUsage.agyConfigured : false

  readonly property var t: Theme

  function refreshAll(): void {
    if (aiUsage) aiUsage.refreshAll();
  }

  function ocText(): string {
    return aiUsage ? aiUsage.ocText() : "--";
  }

  function agyText(): string {
    return aiUsage ? aiUsage.agyText() : "--";
  }

  readonly property double totalTodayTokens: aiUsage ? aiUsage.totalTodayTokens : 0
  readonly property double ocRatio: aiUsage ? aiUsage.ocRatio : 0.5

  Row {
    id: contentRow
    spacing: 7
    anchors.verticalCenter: parent.verticalCenter

    Image {
      anchors.verticalCenter: parent.verticalCenter
      source: Qt.resolvedUrl("../assets/opencode.svg")
      width: 10
      height: 13
      sourceSize.width: 20
      sourceSize.height: 26
      fillMode: Image.PreserveAspectFit
      opacity: root.ocConfigured ? 1.0 : 0.35
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ocText()
      font.pixelSize: Theme.fontBase
      font.family: Theme.mono
      color: Theme.ink1
    }

    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: root.totalTodayTokens > 0 ? 18 : 6
      height: 14

      Text {
        anchors.centerIn: parent
        visible: root.totalTodayTokens <= 0
        text: "·"
        font.pixelSize: Theme.fontBase
        font.family: Theme.mono
        color: Theme.ink3
      }

      Row {
        anchors.centerIn: parent
        width: 18
        height: 4
        spacing: 1
        visible: root.totalTodayTokens > 0

        Rectangle {
          width: Math.max(2, Math.min(15, Math.round(17 * root.ocRatio)))
          height: parent.height
          radius: 2
          color: Theme.teal
        }
        Rectangle {
          width: Math.max(2, 17 - Math.max(2, Math.min(15, Math.round(17 * root.ocRatio))))
          height: parent.height
          radius: 2
          color: Theme.violet
        }
      }
    }


    Image {
      anchors.verticalCenter: parent.verticalCenter
      source: Qt.resolvedUrl("../assets/gemini.svg")
      width: 14
      height: 14
      sourceSize.width: 28
      sourceSize.height: 28
      fillMode: Image.PreserveAspectFit
      opacity: root.agyConfigured ? 1.0 : 0.35
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.agyText()
      font.pixelSize: Theme.fontBase
      font.family: Theme.mono
      color: Theme.ink1
    }
  }
}
