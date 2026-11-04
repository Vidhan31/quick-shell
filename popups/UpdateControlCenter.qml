pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
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
  readonly property bool isCleaning: service ? (service.isCleaning === true) : false
  readonly property bool isAutoremoving: service ? (service.isAutoremoving === true) : false
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
  readonly property bool hasPendingKeyPrompt: service ? (service.hasPendingKeyPrompt === true) : false
  readonly property string pendingKeyId: service ? service.pendingKeyId : ""
  readonly property string pendingKeyFingerprint: service ? service.pendingKeyFingerprint : ""
  property bool errorDetailsExpanded: false

  onErrorMessageChanged: {
    if (root.errorMessage.length === 0) {
      root.errorDetailsExpanded = false;
    }
  }

  readonly property bool isDependencyConflict: root.errorMessage.indexOf("Problem") !== -1 || root.errorMessage.indexOf("conflict") !== -1 || root.errorMessage.indexOf("requires") !== -1
  readonly property bool isLockError: root.errorMessage.indexOf("lock") !== -1 || root.errorMessage.indexOf("Lock") !== -1

  readonly property string errorTitle: {
    if (!root.errorMessage) return "";
    if (root.isDependencyConflict) return "Dependency Conflict";
    if (root.isLockError) return "Package Database Locked";
    if (root.errorMessage.indexOf("Authentication cancelled") !== -1) return "Authentication Cancelled";
    if (root.errorMessage.indexOf("cancelled") !== -1 || root.errorMessage.indexOf("Cancelled") !== -1) return "Update Cancelled";
    if (root.errorMessage.indexOf("Resolution error") !== -1) return "Resolution Error";
    if (root.errorMessage.indexOf("Insufficient disk space") !== -1) return "Disk Space Warning";
    return "Update Failed";
  }

  readonly property string errorSummary: {
    if (!root.errorMessage) return "";
    if (root.isDependencyConflict) return "Updates are held back by conflicting upstream repository packages.";
    if (root.isLockError) return "Another package manager is currently active. Please wait for it to release the lock.";
    if (root.errorMessage.indexOf("Authentication cancelled") !== -1) return "Administrator authentication was cancelled.";
    if (root.errorMessage.indexOf("cancelled") !== -1 || root.errorMessage.indexOf("Cancelled") !== -1) return "The operation was cancelled by the user.";
    const firstLine = root.errorMessage.split("\n")[0];
    return firstLine.length > 80 ? (firstLine.substring(0, 80) + "…") : firstLine;
  }

  readonly property bool hasErrorDetails: {
    if (!root.errorMessage) return false;
    return root.isDependencyConflict || root.errorMessage.indexOf("\n") !== -1 || root.errorMessage.length > 80;
  }

  readonly property bool canSwitchMethod: !root.isBusy && !root.offlineReady

  property string selectedMethod: "offline"
  property int activeTab: 0
  property string expandedPkg: ""

  property bool hoverClean: false
  property bool hoverAutoremove: false
  property bool hoverRefresh: false

  property var changelogCache: ({})
  property int changelogCacheVersion: 0

  Connections {
    target: root.service
    function onChangelogReady(packageName: string): void {
      if (!root.service || !root.service.model) return;
      root.changelogCache[packageName] = root.service.model.getChangelog(packageName);
      root.changelogCacheVersion++;
    }
  }

  onRecommendedMethodChanged: {
    /* No check/download/apply runs concurrently with another operation, so
       the recommendation cannot change mid-transaction. Only skip the sync
       once offline updates are staged (selection is then irrelevant). */
    if (!root.offlineReady) {
      root.selectedMethod = root.recommendedMethod;
    }
  }

  implicitWidth: 480
  readonly property int preferredHeight: root.hasPendingKeyPrompt ? 620 : (root.hasUpdates ? 600 : (root.isChecking ? 260 : 280))
  property int popupHeight: preferredHeight

  function syncHeight() {
    popupHeight = preferredHeight;
  }

  onPreferredHeightChanged: {
    popupHeight = preferredHeight;
  }

  onVisibleChanged: {
    if (visible) {
      popupHeight = preferredHeight;
      // Self-correct a stale manual choice when the popup opens.
      if (!root.offlineReady) {
        root.selectedMethod = root.recommendedMethod;
      }
    }
  }

  implicitHeight: popupHeight

  PopupCard {
    id: cardBg
    anchors.fill: parent
    padding: 0

    Column {
      id: topCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: 0

      Item {
        width: parent.width
        height: 64

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.spaceLg
          anchors.rightMargin: Theme.spaceLg
          spacing: Theme.spaceMd

          Column {
            Layout.fillWidth: true
            spacing: 2

            Row {
              spacing: 6
              Text {
                text: "System Updates"
                font.family: Theme.displayFont
                font.pixelSize: Theme.fontBase
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              StatusPill {
                visible: root.hasUpdates
                anchors.verticalCenter: parent.verticalCenter
                text: root.updateCount.toString()
                tone: root.securityCount > 0 ? "warn" : "accent"
                solid: root.securityCount > 0
              }
            }

            Text {
              text: root.service ? root.service.headerStatusText : "System up to date"
              font.family: Theme.textFont
              font.pixelSize: Theme.fontSm
              color: root.offlineReady ? Theme.green : (root.isBusy ? Theme.accent : Theme.ink2)
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Row {
            spacing: 4

            IconButton {
              glyph: "󰃢"
              fs: Theme.iconBase
              spinning: root.isCleaning
              dimmed: root.isBusy
              tooltip: "Clean package cache & metadata"
              tooltipSub: "dnf clean all"
              onClicked: {
                if (root.service) root.service.cleanAll();
              }
            }

            IconButton {
              glyph: "󰆴"
              fs: Theme.iconBase
              spinning: root.isAutoremoving
              dimmed: root.isBusy
              tooltip: "Remove unneeded dependencies"
              tooltipSub: "dnf autoremove"
              onClicked: {
                if (root.service) root.service.autoremove();
              }
            }

            IconButton {
              glyph: "󰑐"
              fs: Theme.iconBase
              spinning: root.isChecking
              dimmed: root.isBusy
              tooltip: "Check for updates"
              tooltipSub: "Check Fedora repositories"
              onClicked: {
                if (root.service) root.service.checkForUpdates(true);
              }
            }
          }
        }
      }

      Hairline {}

      Item {
        width: parent.width
        height: visible ? 44 : 0
        visible: root.hasUpdates && !root.isChecking

        SegmentedControl {
          anchors.fill: parent
          anchors.margins: 6
          items: [
            { key: "advisory", label: "By Advisory" },
            { key: "repository", label: "By Repository" }
          ]
          current: root.activeTab
          onSelected: index => {
            root.activeTab = index;
          }
        }
      }

      Hairline { visible: root.hasUpdates && !root.isChecking }

      Rectangle {
        id: gpgBanner
        visible: root.hasPendingKeyPrompt
        width: parent.width
        implicitHeight: gpgCol.implicitHeight + 16
        height: visible ? implicitHeight : 0
        color: Theme.warnBg
        radius: Theme.radiusBase
        border.width: 1
        border.color: Qt.rgba(0.90, 0.63, 0.20, 0.45)

        ColumnLayout {
          id: gpgCol
          anchors.fill: parent
          anchors.margins: 8
          spacing: 6

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
              Layout.alignment: Qt.AlignTop
              text: "󰒃"
              font.family: Theme.mono
              font.pixelSize: Theme.iconBase
              color: Theme.warn
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                text: "Trust Repository GPG Key?"
                font.family: Theme.displayFont
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
                color: Theme.ink1
              }

              Text {
                Layout.fillWidth: true
                text: "Key: " + root.pendingKeyId + (root.pendingKeyFingerprint.length > 0 ? ("\nFingerprint: " + root.pendingKeyFingerprint) : "")
                font.family: root.monoFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink2
                wrapMode: Text.WrapAnywhere
              }
            }
          }

          RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8

            PrimaryButton {
              text: "Trust & Import"
              glyph: "󰄬"
              fill: Theme.accent
              ink: Theme.darkInk
              onClicked: {
                if (root.service) root.service.confirmRepoKey(true);
              }
            }

            PrimaryButton {
              text: "Reject"
              glyph: "󰅖"
              fill: Theme.surfaceElevated
              ink: Theme.ink1
              onClicked: {
                if (root.service) root.service.confirmRepoKey(false);
              }
            }
          }
        }
      }

      Rectangle {
        id: errorBanner
        visible: root.errorMessage.length > 0
        width: parent.width
        implicitHeight: errCol.implicitHeight + 16
        height: visible ? implicitHeight : 0
        color: root.isDependencyConflict ? Theme.warnBg : Theme.errBg
        radius: Theme.radiusBase
        border.width: 1
        border.color: root.isDependencyConflict ? Qt.rgba(0.90, 0.63, 0.20, 0.35) : Qt.rgba(0.91, 0.36, 0.36, 0.35)

        ColumnLayout {
          id: errCol
          anchors.fill: parent
          anchors.margins: 8
          spacing: 8

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
              Layout.alignment: Qt.AlignTop
              text: root.isDependencyConflict ? "󱈸" : "󰅚"
              font.family: root.monoFont
              font.pixelSize: Theme.fontGlyphMd
              color: root.isDependencyConflict ? Theme.amber : Theme.red
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                Layout.fillWidth: true
                text: root.errorTitle
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSm
                font.bold: true
                color: Theme.ink1
              }

              Text {
                Layout.fillWidth: true
                text: root.errorSummary
                font.family: Theme.textFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink2
                wrapMode: Text.Wrap
              }
            }

            Row {
              Layout.alignment: Qt.AlignTop
              spacing: 4

              Rectangle {
                visible: root.hasErrorDetails
                implicitWidth: detRow.implicitWidth + 12
                implicitHeight: 24
                radius: Theme.radiusPill
                color: detMa.containsMouse ? Theme.hoverWash : "transparent"
                border.width: 1
                border.color: Theme.lineMuted

                RowLayout {
                  id: detRow
                  anchors.centerIn: parent
                  spacing: 4

                  Text {
                    text: root.errorDetailsExpanded ? "󰅃" : "󰅂"
                    font.family: root.monoFont
                    font.pixelSize: Theme.fontXs
                    color: Theme.ink2
                  }

                  Text {
                    text: root.errorDetailsExpanded ? "Hide" : "Details"
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontXs
                    color: Theme.ink2
                  }
                }

                MouseArea {
                  id: detMa
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.errorDetailsExpanded = !root.errorDetailsExpanded;
                  }
                }
              }

              IconButton {
                btnSize: 24
                fs: Theme.fontSm
                glyph: "󰆏"
                tooltip: "Copy error details"
                tooltipSub: "Copy to clipboard"
                onClicked: {
                  if (root.service) root.service.copyToClipboard(root.errorMessage);
                }
              }

              IconButton {
                btnSize: 24
                fs: Theme.fontSm
                glyph: "󰅖"
                tooltip: "Dismiss"
                onClicked: {
                  if (root.service) root.service.clearErrorMessage();
                }
              }
            }
          }

          Rectangle {
            id: detailsBox
            visible: root.errorDetailsExpanded
            Layout.fillWidth: true
            Layout.maximumHeight: 140
            implicitHeight: Math.min(140, detailsText.implicitHeight + 16)
            color: Theme.inset
            radius: Theme.radiusBase
            border.width: 1
            border.color: Theme.lineMuted
            clip: true

            Flickable {
              id: detailsFlick
              anchors.fill: parent
              anchors.margins: 8
              contentWidth: width
              contentHeight: detailsText.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true

              TextEdit {
                id: detailsText
                width: detailsFlick.width
                text: root.errorMessage
                font.family: root.monoFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink2
                selectionColor: Theme.selected
                selectedTextColor: Theme.ink1
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
              }
            }
          }
        }
      }
    }

    Item {
      id: centerItem
      anchors.top: topCol.bottom
      anchors.bottom: bottomCol.visible ? bottomCol.top : parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      clip: true

        Column {
          visible: root.isChecking
          anchors.centerIn: parent
          spacing: 14

          ProgressBar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 240
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

        Column {
          visible: !root.hasUpdates && !root.isChecking && root.errorMessage.length === 0
          anchors.centerIn: parent
          spacing: 10

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 52
            height: 52
            radius: 26
            color: Theme.tint(Theme.green, 0.12)

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
            font.family: Theme.displayFont
            font.pixelSize: Theme.fontBase
            font.weight: Font.DemiBold
            color: Theme.ink1
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "All packages are synchronized with Fedora 44 repositories."
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSm
            color: Theme.ink3
          }

          Item { width: 1; height: 4 }

          PrimaryButton {
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

        Flickable {
          id: updateScrollView
          visible: root.hasUpdates && !root.isChecking
          anchors.fill: parent
          contentWidth: width
          contentHeight: listContentCol.implicitHeight + 16
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: listContentCol
            width: parent.width - 16
            x: 8
            y: 8
            spacing: 6

            Repeater {
              model: {
                if (!root.service || !root.service.model || !root.hasUpdates) return [];
                const _cnt = root.updateCount;
                const groupBy = (root.activeTab === 0) ? "advisory" : "repository";
                return root.service.model.getGroupKeys(groupBy);
              }

              delegate: Column {
                id: groupCol
                required property var modelData
                required property int index
                width: listContentCol.width
                spacing: 4

                SectionHeader {
                  width: parent.width
                  label: `${groupCol.modelData.label} · ${groupCol.modelData.count}`
                }

                Repeater {
                  model: {
                    if (!root.service || !root.service.model || !root.hasUpdates) return [];
                    const _cnt = root.updateCount;
                    const groupBy = (root.activeTab === 0) ? "advisory" : "repository";
                    return root.service.model.getItemsInGroup(groupBy, groupCol.modelData.key);
                  }

                  Rectangle {
                    id: itemCard
                    required property var modelData
                    readonly property bool changelogIsLoaded: {
                      const _v = root.changelogCacheVersion;
                      if (root.changelogCache[itemCard.modelData.name] !== undefined) return true;
                      if (root.service && root.service.model) return root.service.model.isChangelogLoaded(itemCard.modelData.name);
                      return itemCard.modelData.changelogLoaded;
                    }
                    readonly property var changelogItems: {
                      const _v = root.changelogCacheVersion;
                      if (root.changelogCache[itemCard.modelData.name] !== undefined) return root.changelogCache[itemCard.modelData.name];
                      if (root.service && root.service.model && root.service.model.isChangelogLoaded(itemCard.modelData.name)) {
                        return root.service.model.getChangelog(itemCard.modelData.name);
                      }
                      return itemCard.modelData.changelogList || [];
                    }
                    width: groupCol.width
                    implicitHeight: cardContent.implicitHeight + 16
                    height: implicitHeight
                    radius: Theme.radiusBase
                    color: (root.expandedPkg === itemCard.modelData.name) ? Theme.selected : Theme.surface
                    border.width: 0

                Column {
                  id: cardContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 8
                  spacing: 6

                  RowLayout {
                    width: parent.width
                    spacing: 6

                    Text {
                      text: (itemCard.modelData.categoryKey === "kernel") ? "󰌢" :
                            (itemCard.modelData.categoryKey === "firmware") ? "󰋊" :
                            (itemCard.modelData.categoryKey === "shell") ? "󰍹" :
                            (itemCard.modelData.categoryKey === "app") ? "󰚰" : "󰏔"
                      font.family: root.monoFont
                      font.pixelSize: Theme.fontLg
                      color: (itemCard.modelData.requiresReboot) ? Theme.amber : Theme.accent
                    }

                    Text {
                      text: itemCard.modelData.name
                      font.family: Theme.displayFont
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

                    Text {
                      text: itemCard.modelData.formattedSize
                      font.family: root.monoFont
                      font.pixelSize: Theme.fontSm
                      color: Theme.ink2
                    }

                    StatusPill {
                      visible: itemCard.modelData.advisoryType === "security"
                      text: itemCard.modelData.severity.toUpperCase()
                      tone: (itemCard.modelData.severity === "critical" || itemCard.modelData.severity === "important") ? "err" : "warn"
                      fs: 9
                    }

                    StatusPill {
                      visible: itemCard.modelData.requiresReboot
                      text: "REBOOT"
                      tone: "accent"
                      fs: 9
                    }

                    Rectangle {
                      Layout.preferredWidth: 22
                      Layout.preferredHeight: 22
                      radius: 4
                      color: expMa.containsMouse ? Theme.hoverFill : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: (root.expandedPkg === itemCard.modelData.name) ? "󰅃" : "󰅀"
                        font.family: root.monoFont
                        font.pixelSize: Theme.fontLg
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
                            if (!itemCard.changelogIsLoaded && root.service) {
                              root.service.fetchChangelog(itemCard.modelData.name);
                            }
                          }
                        }
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    text: itemCard.modelData.summary
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontSm
                    color: Theme.ink2
                    elide: (root.expandedPkg === itemCard.modelData.name) ? Text.NoWrap : Text.ElideRight
                    wrapMode: (root.expandedPkg === itemCard.modelData.name) ? Text.Wrap : Text.NoWrap
                  }

                  Column {
                    visible: root.expandedPkg === itemCard.modelData.name
                    width: parent.width
                    spacing: 8

                    Hairline {}

                    Column {
                      visible: itemCard.modelData.advisoryDescription && itemCard.modelData.advisoryDescription.length > 0
                      width: parent.width
                      spacing: 3

                      Text {
                        text: "Advisory Errata:"
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                        color: Theme.ink3
                      }

                      Text {
                        width: parent.width
                        text: itemCard.modelData.advisoryDescription
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontSm
                        color: Theme.ink1
                        wrapMode: Text.Wrap
                      }
                    }

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
                          color: Theme.errBg
                          Text {
                            id: cveLabel
                            anchors.centerIn: parent
                            text: cvePill.modelData
                            font.family: root.monoFont
                            font.pixelSize: Theme.fontXs
                            color: Theme.red
                          }
                        }
                      }
                    }

                    Column {
                      id: changelogCol
                      width: parent.width
                      spacing: 4

                      Text {
                        text: "Package Changelog:"
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontXs
                        font.weight: Font.DemiBold
                        color: Theme.ink3
                      }

                      Text {
                        visible: !itemCard.changelogIsLoaded
                        text: "Loading changelog entries…"
                        font.family: root.monoFont
                        font.pixelSize: Theme.fontSm
                        color: Theme.ink3
                      }

                      Text {
                        visible: itemCard.changelogIsLoaded && (!itemCard.changelogItems || itemCard.changelogItems.length === 0)
                        text: "No spec changelogs provided by repository."
                        font.family: Theme.textFont
                        font.pixelSize: Theme.fontXs
                        color: Theme.ink3
                      }

                      Repeater {
                        visible: itemCard.changelogIsLoaded && itemCard.changelogItems && itemCard.changelogItems.length > 0
                        model: (itemCard.changelogItems && itemCard.changelogItems.length > 0)
                               ? itemCard.changelogItems.slice(0, 5) : []

                        Column {
                          id: changelogEntry
                          required property var modelData
                          width: changelogCol.width
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
                              font.family: Theme.textFont
                              font.pixelSize: Theme.fontXs
                              color: Theme.ink3
                              elide: Text.ElideRight
                              width: 320
                            }
                          }

                          Text {
                            width: changelogCol.width
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
    }
  }

    Column {
      id: bottomCol
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      visible: root.hasUpdates && !root.isChecking
      spacing: 0

      Hairline {}

      Item {
        width: parent.width
        implicitHeight: footerCol.implicitHeight + 24
        height: implicitHeight

        Column {
          id: footerCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 12
          spacing: 10

          RowLayout {
            width: parent.width
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 50
              radius: Theme.radiusBase
              color: root.selectedMethod === "offline" ? Theme.selected : Theme.surface
              border.width: 0
              opacity: (root.selectedMethod === "offline") ? 1.0 : (root.canSwitchMethod ? 0.75 : 0.35)

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
                  spacing: 2

                  Row {
                    spacing: 4
                    Text {
                      text: "Safe Offline Upgrade"
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontSm
                      font.weight: Font.DemiBold
                      color: Theme.ink1
                    }
                    Text {
                      visible: root.recommendedMethod === "offline"
                      text: "(Recommended)"
                      font.family: Theme.textFont
                      font.pixelSize: Theme.fontXs
                      color: Theme.accent
                    }
                  }

                  Text {
                    width: parent.width
                    text: root.offlineReady ? "Downloaded & ready for reboot" : "Downloads now, applies on restart"
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontSm
                    color: root.offlineReady ? Theme.green : Theme.ink3
                    elide: Text.ElideRight
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.canSwitchMethod
                cursorShape: root.canSwitchMethod ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.canSwitchMethod) root.selectedMethod = "offline";
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 50
              radius: Theme.radiusBase
              color: root.selectedMethod === "inplace" ? Theme.selected : Theme.surface
              border.width: 0
              opacity: (root.selectedMethod === "inplace") ? 1.0 : (root.canSwitchMethod ? 0.75 : 0.35)

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
                  spacing: 2

                  Text {
                    text: "Live In-Place Upgrade"
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.DemiBold
                    color: Theme.ink1
                  }

                  Text {
                    width: parent.width
                    text: "Installs immediately in active session"
                    font.family: Theme.textFont
                    font.pixelSize: Theme.fontSm
                    color: Theme.ink3
                    elide: Text.ElideRight
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.canSwitchMethod
                cursorShape: root.canSwitchMethod ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.canSwitchMethod) root.selectedMethod = "inplace";
                }
              }
            }
          }

          Column {
            visible: root.isDownloading || root.isApplying || (root.service ? (root.service.progressStage.length > 0) : false)
            width: parent.width
            spacing: 8

            ProgressBar {
              width: parent.width
              from: 0.0
              to: 1.0
              value: {
                if (root.service && root.service.progressStage.length > 0) {
                  if (root.service.progressStage === "authenticating") return 0.0;
                  return Math.min(1.0, Math.max(0.0, root.service.activeProgress));
                }
                const frac = root.isDownloading ? root.downloadProgress : (root.service ? root.service.transactionProgress : 0.0);
                return Math.min(1.0, Math.max(0.0, frac));
              }
              fillColor: Theme.accent
              trackColor: Theme.surfaceElevated
            }

            RowLayout {
              width: parent.width
              spacing: 8

              Text {
                id: progressIcon
                text: root.service ? root.service.summaryGlyph : (root.isDownloading ? "󰇚" : "󰑐")
                font.family: root.monoFont
                font.pixelSize: Theme.fontSm
                color: root.service ? root.service.statusColor : Theme.accent

                NumberAnimation on rotation {
                  running: root.service ? root.service.isSpinning : false
                  from: 0
                  to: 360
                  loops: Animation.Infinite
                  duration: 800
                }

                onTextChanged: {
                  if (progressIcon.text !== "󰑐") progressIcon.rotation = 0;
                }
              }

              Text {
                Layout.fillWidth: true
                text: root.service ? root.service.statusMessage : ""
                font.family: root.monoFont
                font.pixelSize: Theme.fontXs
                color: Theme.ink1
                elide: Text.ElideRight
              }

              Text {
                text: root.service ? root.service.progressPercentText : ""
                font.family: root.monoFont
                font.pixelSize: Theme.fontXs
                font.weight: Font.DemiBold
                color: Theme.accent
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: 8

            PrimaryButton {
              visible: root.isDownloading
              text: "Cancel Download"
              glyph: "󰅖"
              fill: Theme.surfaceElevated
              ink: Theme.ink1
              onClicked: {
                if (root.service) root.service.cancelOperation();
              }
            }

            PrimaryButton {
              visible: root.isApplying
              Layout.fillWidth: true
              enabledBtn: false
              text: "Applying Updates…"
              glyph: "󰑐"
              fill: Theme.surfaceElevated
              ink: Theme.accent
            }

            PrimaryButton {
              visible: !root.isDownloading && !root.isApplying && !root.offlineReady
              Layout.fillWidth: true
              text: root.selectedMethod === "offline" ? "Download & Install on Restart" : "Install Updates Now"
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

            PrimaryButton {
              visible: root.offlineReady
              Layout.fillWidth: true
              text: "Restart & Apply Updates"
              glyph: "󰜉"
              fill: Theme.green
              ink: Theme.darkInk
              onClicked: {
                if (root.service) root.service.rebootAndApply();
              }
            }

            PrimaryButton {
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
