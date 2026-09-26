pragma ComponentBehavior: Bound
// popups/UpdateControlCenter.qml — DNF5 Update Manager Control Center.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../theme"
import "../components"

Item {
  id: root

  property var service: null
  readonly property string monoFont: Theme.mono

  signal closeRequested()

  readonly property bool isChecking: service ? (service.isChecking === true) : false
  readonly property bool isDownloading: service ? (service.isDownloading === true) : false
  readonly property bool isApplying: service ? (service.isApplying === true) : false
  readonly property bool isBusy: service ? (service.isBusy === true) : false
  readonly property bool hasUpdates: service ? (service.hasUpdates === true) : false
  readonly property int updateCount: service ? (service.updateCount || 0) : 0
  readonly property int securityCount: service ? (service.securityCount || 0) : 0
  readonly property bool offlineReady: service ? (service.offlineStagedReady === true) : false
  readonly property string recommendedMethod: service ? service.recommendedMethod : "inplace"
  readonly property string formattedSize: service ? service.formattedTotalSize : "0 B"
  readonly property double downloadProgress: service ? (service.downloadProgress || 0.0) : 0.0
  readonly property string lastChecked: service ? service.lastCheckedText : "Never"
  readonly property string currentStep: service ? service.currentStep : ""
  readonly property int checkPercent: service ? (service.checkPercent || 0) : 0
  readonly property string errorMessage: service ? service.errorMessage : ""

  // Selected upgrade method: "offline" vs "inplace"
  property string selectedMethod: "offline"

  // Active grouping tab: 0 = Advisory, 1 = Repository, 2 = Category
  property int activeTab: 0

  // Expanded package name for changelog view
  property string expandedPkg: ""

  onRecommendedMethodChanged: {
    if (!root.isBusy && !root.offlineReady) {
      root.selectedMethod = root.recommendedMethod;
    }
  }

  implicitWidth: 480
  readonly property int preferredHeight: Math.min(680, Math.max(340, 32 + bodyCol.implicitHeight))
  property int popupHeight: 480

  function syncHeight() {
    popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    if (!root.visible) popupHeight = preferredHeight;
  }

  implicitHeight: popupHeight

  Rectangle {
    id: cardBg
    anchors.fill: parent
    radius: Theme.radiusCard
    color: Theme.bg
    border.width: 1
    border.color: Theme.cardBorder

    Column {
      id: bodyCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: 0

      // ─── Header ──────────────────────────────────────────────
      Item {
        width: parent.width
        height: 64

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceLg
          anchors.rightMargin: Theme.spaceLg
          spacing: Theme.spaceMd

          Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            radius: Theme.radiusBase
            color: root.offlineReady ? Qt.rgba(0.27, 0.78, 0.52, 0.15) :
                   root.securityCount > 0 ? Qt.rgba(0.88, 0.65, 0.23, 0.15) :
                   root.hasUpdates ? Qt.rgba(0.37, 0.62, 1.0, 0.15) : Theme.surfaceElevated

            Text {
              anchors.centerIn: parent
              text: root.offlineReady ? "󰜉" : (root.securityCount > 0 ? "󰒃" : "󰚰")
              font.family: root.monoFont
              font.pixelSize: 18
              color: root.offlineReady ? Theme.green :
                     root.securityCount > 0 ? Theme.amber :
                     root.hasUpdates ? Theme.accent : Theme.ink2
            }
          }

          Column {
            Layout.fillWidth: true
            spacing: 2

            Row {
              spacing: 6
              Text {
                text: "System Updates"
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Rectangle {
                visible: root.hasUpdates
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                implicitWidth: badgeText.implicitWidth + 10
                radius: Theme.radiusPill
                color: root.securityCount > 0 ? Theme.amber : Theme.accentBg

                Text {
                  id: badgeText
                  anchors.centerIn: parent
                  text: root.updateCount.toString()
                  font.family: root.monoFont
                  font.pixelSize: Theme.fontXs
                  font.weight: Font.Bold
                  color: root.securityCount > 0 ? Theme.darkInk : Theme.accent
                }
              }
            }

            Text {
              text: root.isChecking ? (root.currentStep.length > 0 ? root.currentStep : "Checking repositories…") :
                    root.offlineReady ? "Updates staged · Ready to restart" :
                    root.hasUpdates ? `${root.updateCount} updates (${root.formattedSize}) · Checked ${root.lastChecked}` :
                    `System up to date · Checked ${root.lastChecked}`
              font.pixelSize: Theme.fontSm
              color: root.offlineReady ? Theme.green : Theme.ink2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          // Header action buttons
          Row {
            spacing: 4

            // Mock toggle button (subtle dev pill)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              height: 24
              implicitWidth: mockText.implicitWidth + 12
              radius: Theme.radiusPill
              color: (root.service && root.service.mockMode) ? Theme.accentBg : "transparent"
              border.width: 1
              border.color: (root.service && root.service.mockMode) ? Theme.accent : Theme.line

              Text {
                id: mockText
                anchors.centerIn: parent
                text: "MOCK"
                font.family: root.monoFont
                font.pixelSize: 10
                font.weight: Font.Bold
                color: (root.service && root.service.mockMode) ? Theme.accent : Theme.ink3
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.service) {
                    root.service.mockMode = !root.service.mockMode;
                  }
                }
              }
            }

            // Refresh button
            IconBtn {
              glyph: "󰑐"
              spinning: root.isChecking
              dimmed: root.isBusy
              onClicked: {
                if (root.service) root.service.checkForUpdates(true);
              }
            }
          }
        }
      }

      Hairline {}

      // ─── Grouping Tabs (Advisory / Repository / Category) ─────
      Item {
        width: parent.width
        height: 44
        visible: root.hasUpdates && !root.isChecking

        Segments {
          anchors.fill: parent
          anchors.margins: 6
          items: [
            { key: "advisory", label: "By Advisory" },
            { key: "repository", label: "By Repository" },
            { key: "category", label: "By Category" }
          ]
          current: root.activeTab
          onSelected: index => {
            root.activeTab = index;
          }
        }
      }

      Hairline { visible: root.hasUpdates && !root.isChecking }

      // ─── Error Notification Banner ────────────────────────────
      Rectangle {
        visible: root.errorMessage.length > 0
        width: parent.width
        implicitHeight: errText.implicitHeight + 16
        color: Qt.rgba(0.87, 0.39, 0.39, 0.15)
        border.width: 1
        border.color: Theme.red

        RowLayout {
          anchors.fill: parent
          anchors.margins: 8
          spacing: 8

          Text {
            text: "󰅚"
            font.family: root.monoFont
            font.pixelSize: 16
            color: Theme.red
          }

          Text {
            id: errText
            Layout.fillWidth: true
            text: root.errorMessage
            font.pixelSize: Theme.fontSm
            color: Theme.ink1
            wrapMode: Text.Wrap
          }
        }
      }

      // ─── Main Content View (List / Loading / Empty) ───────────
      Item {
        width: parent.width
        height: Math.min(360, Math.max(160, root.popupHeight - (root.hasUpdates ? 220 : 120)))

        // Loading state
        Column {
          visible: root.isChecking
          anchors.centerIn: parent
          spacing: 12

          ProgressBar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220
            from: 0
            to: 100
            value: root.checkPercent
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: `${root.currentStep} (${root.checkPercent}%)`
            font.family: root.monoFont
            font.pixelSize: Theme.fontSm
            color: Theme.ink2
          }
        }

        // Empty state (all up to date)
        Column {
          visible: !root.hasUpdates && !root.isChecking && root.errorMessage.length === 0
          anchors.centerIn: parent
          spacing: 10

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 52
            height: 52
            radius: 26
            color: Qt.rgba(0.27, 0.78, 0.52, 0.12)

            Text {
              anchors.centerIn: parent
              text: "󰄬"
              font.family: root.monoFont
              font.pixelSize: 26
              color: Theme.green
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Your system is up to date"
            font.pixelSize: Theme.fontBase
            font.weight: Font.DemiBold
            color: Theme.ink1
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "All packages are synchronized with Fedora 44 repositories."
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
          }

          Item { width: 1; height: 4 }

          PrimaryBtn {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Check for Updates"
            glyph: "󰑐"
            fill: Theme.surfaceElevated
            ink: Theme.ink1
            onClicked: {
              if (root.service) root.service.checkForUpdates(true);
            }
          }
        }

        // Updates List View
        ListView {
          id: updateListView
          visible: root.hasUpdates && !root.isChecking
          anchors.fill: parent
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          spacing: 6
          topMargin: 6
          bottomMargin: 6
          leftMargin: 8
          rightMargin: 8

          model: {
            if (!root.service || !root.service.model) return 0;
            const groupBy = (root.activeTab === 0) ? "advisory" : (root.activeTab === 1) ? "repository" : "category";
            return root.service.model.getGroupKeys(groupBy);
          }

          delegate: Column {
            id: groupCol
            required property var modelData
            required property int index
            width: updateListView.width - 16
            spacing: 4

            // Group Section Header
            Item {
              width: parent.width
              height: 28

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 6
                  height: 6
                  radius: 3
                  color: (groupCol.modelData.key === "security") ? Theme.amber :
                         (groupCol.modelData.key === "kernel") ? Theme.red : Theme.accent
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: groupCol.modelData.label
                  font.pixelSize: Theme.fontSm
                  font.weight: Font.DemiBold
                  color: Theme.ink2
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: `(${groupCol.modelData.count})`
                  font.family: root.monoFont
                  font.pixelSize: Theme.fontXs
                  color: Theme.ink3
                }
              }
            }

            // Items in group repeater
            Repeater {
              model: {
                if (!root.service || !root.service.model) return [];
                const groupBy = (root.activeTab === 0) ? "advisory" : (root.activeTab === 1) ? "repository" : "category";
                return root.service.model.getItemsInGroup(groupBy, groupCol.modelData.key);
              }

              Rectangle {
                id: itemCard
                required property var modelData
                width: groupCol.width
                implicitHeight: cardContent.implicitHeight + 16
                radius: Theme.radiusBase
                color: Theme.surface
                border.width: 1
                border.color: (root.expandedPkg === itemCard.modelData.name) ? Theme.accent : Theme.cardBorder

                Column {
                  id: cardContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 8
                  spacing: 6

                  // Top row: Name, EVR transition, size, badges
                  RowLayout {
                    width: parent.width
                    spacing: 6

                    // Package icon
                    Text {
                      text: (itemCard.modelData.categoryKey === "kernel") ? "󰌢" :
                            (itemCard.modelData.categoryKey === "firmware") ? "󰋊" :
                            (itemCard.modelData.categoryKey === "shell") ? "󰍹" :
                            (itemCard.modelData.categoryKey === "app") ? "󰚰" : "󰏔"
                      font.family: root.monoFont
                      font.pixelSize: 14
                      color: (itemCard.modelData.requiresReboot) ? Theme.amber : Theme.accent
                    }

                    Text {
                      text: itemCard.modelData.name
                      font.pixelSize: Theme.fontMd
                      font.weight: Font.DemiBold
                      color: Theme.ink1
                    }

                    Text {
                      Layout.fillWidth: true
                      text: `${itemCard.modelData.oldEvr} 󰁔 ${itemCard.modelData.newEvr}`
                      font.family: root.monoFont
                      font.pixelSize: Theme.fontSm
                      color: Theme.ink3
                      elide: Text.ElideRight
                    }

                    // Size
                    Text {
                      text: itemCard.modelData.formattedSize
                      font.family: root.monoFont
                      font.pixelSize: Theme.fontSm
                      color: Theme.ink2
                    }

                    // Security / Severity pill
                    Rectangle {
                      visible: itemCard.modelData.advisoryType === "security"
                      Layout.preferredHeight: 18
                      Layout.preferredWidth: secText.implicitWidth + 8
                      radius: Theme.radiusPill
                      color: (itemCard.modelData.severity === "critical" || itemCard.modelData.severity === "important")
                             ? Qt.rgba(0.88, 0.39, 0.39, 0.2) : Qt.rgba(0.88, 0.65, 0.23, 0.2)

                      Text {
                        id: secText
                        anchors.centerIn: parent
                        text: itemCard.modelData.severity.toUpperCase()
                        font.family: root.monoFont
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: (itemCard.modelData.severity === "critical" || itemCard.modelData.severity === "important")
                               ? Theme.red : Theme.amber
                      }
                    }

                    // Reboot pill
                    Rectangle {
                      visible: itemCard.modelData.requiresReboot
                      Layout.preferredHeight: 18
                      Layout.preferredWidth: rbtText.implicitWidth + 8
                      radius: Theme.radiusPill
                      color: Qt.rgba(0.37, 0.62, 1.0, 0.15)

                      Text {
                        id: rbtText
                        anchors.centerIn: parent
                        text: "REBOOT"
                        font.family: root.monoFont
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Theme.accent
                      }
                    }

                    // Expand toggle
                    Rectangle {
                      Layout.preferredWidth: 22
                      Layout.preferredHeight: 22
                      radius: 4
                      color: expMa.containsMouse ? Theme.hoverFill : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: (root.expandedPkg === itemCard.modelData.name) ? "󰅃" : "󰅀"
                        font.family: root.monoFont
                        font.pixelSize: 14
                        color: Theme.ink2
                      }

                      MouseArea {
                        id: expMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.expandedPkg === itemCard.modelData.name) {
                            root.expandedPkg = "";
                          } else {
                            root.expandedPkg = itemCard.modelData.name;
                            if (!itemCard.modelData.changelogLoaded && root.service) {
                              root.service.fetchChangelog(itemCard.modelData.name);
                            }
                          }
                        }
                      }
                    }
                  }

                  // Summary row
                  Text {
                    width: parent.width
                    text: itemCard.modelData.summary
                    font.pixelSize: Theme.fontSm
                    color: Theme.ink2
                    elide: (root.expandedPkg === itemCard.modelData.name) ? Text.NoWrap : Text.ElideRight
                    wrapMode: (root.expandedPkg === itemCard.modelData.name) ? Text.Wrap : Text.NoWrap
                  }

                  // Expanded Details & Changelog section
                  Column {
                    visible: root.expandedPkg === itemCard.modelData.name
                    width: parent.width
                    spacing: 8

                    Hairline {}

                    // Advisory description / maintainer notes
                    Column {
                      visible: itemCard.modelData.advisoryDescription && itemCard.modelData.advisoryDescription.length > 0
                      width: parent.width
                      spacing: 3

                      Text {
                        text: "Advisory Errata:"
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                        color: Theme.ink3
                      }

                      Text {
                        width: parent.width
                        text: itemCard.modelData.advisoryDescription
                        font.pixelSize: Theme.fontSm
                        color: Theme.ink1
                        wrapMode: Text.Wrap
                      }
                    }

                    // CVE references
                    Row {
                      visible: itemCard.modelData.cveList && itemCard.modelData.cveList.length > 0
                      spacing: 4
                      Repeater {
                        model: itemCard.modelData.cveList
                        Rectangle {
                          id: cvePill
                          required property string modelData
                          height: 18
                          implicitWidth: cveLabel.implicitWidth + 8
                          radius: Theme.radiusXs
                          color: Qt.rgba(0.88, 0.39, 0.39, 0.15)
                          Text {
                            id: cveLabel
                            anchors.centerIn: parent
                            text: cvePill.modelData
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: Theme.red
                          }
                        }
                      }
                    }

                    // RPM Spec Changelog
                    Column {
                      width: parent.width
                      spacing: 4

                      Text {
                        text: "Package Changelog:"
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                        color: Theme.ink3
                      }

                      // Loading changelog placeholder
                      Text {
                        visible: !itemCard.modelData.changelogLoaded
                        text: "Loading changelog entries…"
                        font.family: root.monoFont
                        font.pixelSize: Theme.fontSm
                        color: Theme.ink3
                      }

                      Repeater {
                        visible: itemCard.modelData.changelogLoaded
                        model: (itemCard.modelData.changelogList && itemCard.modelData.changelogList.length > 0)
                               ? itemCard.modelData.changelogList.slice(0, 3) : []

                        Column {
                          id: changelogEntry
                          required property var modelData
                          width: parent.width
                          spacing: 2

                          Row {
                            spacing: 6
                            Text {
                              text: changelogEntry.modelData.date || ""
                              font.family: root.monoFont
                              font.pixelSize: Theme.fontXs
                              color: Theme.accent
                            }
                            Text {
                              text: changelogEntry.modelData.author || ""
                              font.pixelSize: Theme.fontXs
                              color: Theme.ink3
                              elide: Text.ElideRight
                              width: 320
                            }
                          }

                          Text {
                            width: parent.width
                            text: changelogEntry.modelData.text || ""
                            font.family: root.monoFont
                            font.pixelSize: Theme.fontXs
                            color: Theme.ink2
                            wrapMode: Text.Wrap
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      Hairline { visible: root.hasUpdates && !root.isChecking }

      // ─── Footer Action Bar ────────────────────────────────────
      Item {
        visible: root.hasUpdates && !root.isChecking
        width: parent.width
        implicitHeight: footerCol.implicitHeight + 16

        Column {
          id: footerCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 12
          spacing: 10

          // Mode Selection Row
          RowLayout {
            width: parent.width
            spacing: 8

            // Offline Upgrade Radio Card
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 48
              radius: Theme.radiusBase
              color: root.selectedMethod === "offline" ? Theme.selected : Theme.surface
              border.width: 1
              border.color: root.selectedMethod === "offline" ? Theme.accent : Theme.cardBorder

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                  text: root.selectedMethod === "offline" ? "󰄲" : "󰄱"
                  font.family: root.monoFont
                  font.pixelSize: 18
                  color: root.selectedMethod === "offline" ? Theme.accent : Theme.ink3
                }

                Column {
                  Layout.fillWidth: true
                  spacing: 1

                  Row {
                    spacing: 6
                    Text {
                      text: "Safe Offline Upgrade"
                      font.pixelSize: Theme.fontSm
                      font.weight: Font.DemiBold
                      color: Theme.ink1
                    }
                    Text {
                      visible: root.recommendedMethod === "offline"
                      text: "(Recommended)"
                      font.pixelSize: Theme.fontXs
                      color: Theme.accent
                    }
                  }

                  Text {
                    text: "Downloads now, applies on next restart"
                    font.pixelSize: 11
                    color: Theme.ink3
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedMethod = "offline"
              }
            }

            // In-Place Upgrade Radio Card
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 48
              radius: Theme.radiusBase
              color: root.selectedMethod === "inplace" ? Theme.selected : Theme.surface
              border.width: 1
              border.color: root.selectedMethod === "inplace" ? Theme.accent : Theme.cardBorder

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                  text: root.selectedMethod === "inplace" ? "󰄲" : "󰄱"
                  font.family: root.monoFont
                  font.pixelSize: 18
                  color: root.selectedMethod === "inplace" ? Theme.accent : Theme.ink3
                }

                Column {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Live In-Place Upgrade"
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.DemiBold
                    color: Theme.ink1
                  }

                  Text {
                    text: "Installs immediately in active session"
                    font.pixelSize: 11
                    color: Theme.ink3
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedMethod = "inplace"
              }
            }
          }

          // Progress indicator during download / in-place transaction
          Column {
            visible: root.isDownloading || root.isApplying
            width: parent.width
            spacing: 4

            ProgressBar {
              width: parent.width
              from: 0
              to: 1
              value: root.isDownloading ? root.downloadProgress : (root.service ? root.service.transactionProgress : 0)
            }

            RowLayout {
              width: parent.width
              Text {
                text: root.service ? root.service.statusMessage : ""
                font.family: root.monoFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink2
              }
              Item { Layout.fillWidth: true }
              Text {
                text: `${Math.round((root.isDownloading ? root.downloadProgress : (root.service ? root.service.transactionProgress : 0)) * 100)}%`
                font.family: root.monoFont
                font.pixelSize: Theme.fontXs
                color: Theme.accent
              }
            }
          }

          // Primary Execution Buttons
          RowLayout {
            width: parent.width
            spacing: 8

            // Cancel button when downloading
            PrimaryBtn {
              visible: root.isDownloading
              text: "Cancel"
              glyph: "󰅖"
              fill: Theme.surfaceElevated
              ink: Theme.ink1
              onClicked: {
                if (root.service) root.service.cancelOperation();
              }
            }

            // Normal idle buttons
            PrimaryBtn {
              visible: !root.isDownloading && !root.isApplying && !root.offlineReady
              Layout.fillWidth: true
              text: root.selectedMethod === "offline" ? "Download & Stage for Restart" : "Apply Updates Live"
              glyph: root.selectedMethod === "offline" ? "󰇚" : "󰚰"
              fill: Theme.accent
              ink: Theme.darkInk
              onClicked: {
                if (!root.service) return;
                if (root.selectedMethod === "offline") {
                  root.service.stageOfflineUpgrade();
                } else {
                  root.service.startInPlaceUpgrade();
                }
              }
            }

            // Offline ready buttons
            PrimaryBtn {
              visible: root.offlineReady
              Layout.fillWidth: true
              text: "Restart System & Apply Updates"
              glyph: "󰜉"
              fill: Theme.green
              ink: Theme.darkInk
              onClicked: {
                if (root.service) root.service.rebootAndApply();
              }
            }

            PrimaryBtn {
              visible: root.offlineReady
              text: "Discard Staged"
              glyph: "󰅖"
              fill: Theme.surfaceElevated
              ink: Theme.ink2
              onClicked: {
                if (root.service) root.service.cleanOffline();
              }
            }
          }
        }
      }
    }
  }
}
