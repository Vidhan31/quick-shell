pragma ComponentBehavior: Bound
// services/UpdateService.qml — Long-lived Update Manager backend service.
import QtQuick
import Quickshell.Plugins.UpdateManager

Item {
  id: root

  UpdateManager {
    id: manager
  }

  // Public read API
  readonly property alias manager: manager
  readonly property var model: manager.model
  readonly property alias isChecking: manager.isChecking
  readonly property alias isDownloading: manager.isDownloading
  readonly property alias isApplying: manager.isApplying
  readonly property alias isBusy: manager.isBusy
  readonly property alias hasUpdates: manager.hasUpdates
  readonly property alias updateCount: manager.updateCount
  readonly property alias securityCount: manager.securityCount
  readonly property alias totalDownloadSize: manager.totalDownloadSize
  readonly property alias formattedTotalSize: manager.formattedTotalSize
  readonly property alias downloadProgress: manager.downloadProgress
  readonly property alias transactionProgress: manager.transactionProgress
  readonly property alias statusMessage: manager.statusMessage
  readonly property alias errorMessage: manager.errorMessage
  readonly property alias currentStep: manager.currentStep
  readonly property alias checkPercent: manager.checkPercent
  readonly property alias recommendedMethod: manager.recommendedMethod
  readonly property alias offlineStagedReady: manager.offlineStagedReady
  property alias mockMode: manager.mockMode
  readonly property alias lastCheckedText: manager.lastCheckedText

  // Actions
  function checkForUpdates(refresh) {
    manager.checkForUpdates(refresh === true);
  }

  function fetchChangelog(pkgName) {
    manager.fetchChangelog(pkgName);
  }

  function stageOfflineUpgrade() {
    manager.stageOfflineUpgrade();
  }

  function startInPlaceUpgrade() {
    manager.startInPlaceUpgrade();
  }

  function rebootAndApply() {
    manager.rebootAndApply();
  }

  function cancelOperation() {
    manager.cancelOperation();
  }

  function cleanOffline() {
    manager.cleanOffline();
  }

  function loadMockData() {
    manager.loadMockData();
  }

  // Automatic initial check on startup after short delay
  Timer {
    id: startupCheckTimer
    interval: 8000
    running: true
    repeat: false
    onTriggered: {
      root.checkForUpdates(false);
    }
  }

  // Periodic background check every 4 hours
  Timer {
    id: periodicCheckTimer
    interval: 1000 * 60 * 60 * 4
    running: true
    repeat: true
    onTriggered: {
      root.checkForUpdates(false);
    }
  }
}
