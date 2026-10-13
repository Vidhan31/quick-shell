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

  readonly property string totalTokensText: aiUsage ? aiUsage.totalTokensText : "--"
  readonly property string totalCostText: aiUsage ? aiUsage.totalCostText : "--"

  function refreshAll(): void {
    if (aiUsage) aiUsage.refreshAll();
  }

  Row {
    id: contentRow
    spacing: 6
    anchors.verticalCenter: parent.verticalCenter

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.totalTokensText
      font.pixelSize: Theme.fontBase
      font.family: Theme.mono
      color: Theme.ink1
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "·"
      font.pixelSize: Theme.fontBase
      font.family: Theme.mono
      color: Theme.ink3
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.totalCostText
      font.pixelSize: Theme.fontBase
      font.family: Theme.mono
      font.weight: Font.DemiBold
      color: Theme.green
    }
  }
}
