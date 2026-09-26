#include "UpdateManager.hpp"

#include <QDateTime>
#include <QMetaObject>

namespace qs::updatemanager {

UpdateManager::UpdateManager(QObject *parent)
    : QObject(parent) {
    registerDbusTypes();

    m_worker = new UpdateWorker();
    m_worker->moveToThread(&m_workerThread);

    connect(m_worker, &UpdateWorker::checkStarted, this, &UpdateManager::handleCheckStarted);
    connect(m_worker, &UpdateWorker::checkProgress, this, &UpdateManager::handleCheckProgress);
    connect(m_worker, &UpdateWorker::checkFinished, this, &UpdateManager::handleCheckFinished);
    connect(m_worker, &UpdateWorker::changelogFetched, this, &UpdateManager::handleChangelogFetched);
    connect(m_worker, &UpdateWorker::downloadProgress, this, &UpdateManager::handleDownloadProgress);
    connect(m_worker, &UpdateWorker::inPlaceProgress, this, &UpdateManager::handleInPlaceProgress);
    connect(m_worker, &UpdateWorker::operationFinished, this, &UpdateManager::handleOperationFinished);
    connect(m_worker, &UpdateWorker::offlineStagedReady, this, &UpdateManager::handleOfflineStagedReady);
    connect(m_worker, &UpdateWorker::statusMessageChanged, this, &UpdateManager::handleStatusMessageChanged);

    m_workerThread.start();
}

UpdateManager::~UpdateManager() {
    m_workerThread.quit();
    m_workerThread.wait();
    delete m_worker;
}

QString UpdateManager::formattedTotalSize() const {
    if (m_totalDownloadSize == 0) {
        return QStringLiteral("0 B");
    }
    const double bytes = static_cast<double>(m_totalDownloadSize);
    if (bytes >= 1024.0 * 1024.0 * 1024.0) {
        return QString::asprintf("%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0));
    }
    if (bytes >= 1024.0 * 1024.0) {
        return QString::asprintf("%.1f MB", bytes / (1024.0 * 1024.0));
    }
    if (bytes >= 1024.0) {
        return QString::asprintf("%.0f KB", bytes / 1024.0);
    }
    return QString::asprintf("%llu B", m_totalDownloadSize);
}

QString UpdateManager::lastCheckedText() const {
    if (!m_lastChecked.isValid()) {
        return QStringLiteral("Never");
    }
    const qint64 diffSecs = m_lastChecked.secsTo(QDateTime::currentDateTime());
    if (diffSecs < 60) {
        return QStringLiteral("Just now");
    }
    if (diffSecs < 3600) {
        return QStringLiteral("%1m ago").arg(diffSecs / 60);
    }
    if (diffSecs < 86400) {
        return QStringLiteral("%1h ago").arg(diffSecs / 3600);
    }
    return m_lastChecked.toString(QStringLiteral("MMM d, hh:mm"));
}

void UpdateManager::setMockMode(bool enabled) {
    if (m_mockMode == enabled) return;
    m_mockMode = enabled;
    emit mockModeChanged();
    if (m_mockMode) {
        loadMockData();
    } else {
        m_model.clear();
        recalculateTotals();
    }
}

void UpdateManager::checkForUpdates(bool refresh) {
    if (m_mockMode) {
        loadMockData();
        return;
    }

    if (m_isChecking || m_isDownloading || m_isApplying) {
        return;
    }

    m_isChecking = true;
    m_errorMessage.clear();
    emit isCheckingChanged();
    emit isBusyChanged();
    emit errorMessageChanged();

    QMetaObject::invokeMethod(m_worker, "checkForUpdates", Qt::QueuedConnection, Q_ARG(bool, refresh));
}

void UpdateManager::fetchChangelog(const QString &packageName) {
    if (m_mockMode) {
        // Mock changelog entries
        QVariantList list;
        QVariantMap e1, e2;
        e1[QStringLiteral("date")] = QStringLiteral("2026-09-24");
        e1[QStringLiteral("author")] = QStringLiteral("Maintainer <maintainer@fedoraproject.org>");
        e1[QStringLiteral("text")] = QStringLiteral("- Upstream security patch CVE-2026-1182\n- Fix buffer bounds check in parser");
        e2[QStringLiteral("date")] = QStringLiteral("2026-09-10");
        e2[QStringLiteral("author")] = QStringLiteral("Release Bot <bot@fedoraproject.org>");
        e2[QStringLiteral("text")] = QStringLiteral("- Update to upstream release version\n- Enable Wayland fractional scaling flags");
        list.append(e1);
        list.append(e2);
        m_model.updateChangelog(packageName, list);
        return;
    }

    QMetaObject::invokeMethod(m_worker, "fetchChangelog", Qt::QueuedConnection, Q_ARG(QString, packageName));
}

void UpdateManager::stageOfflineUpgrade() {
    if (m_isDownloading || m_isApplying) return;
    m_isDownloading = true;
    m_downloadProgress = 0.0;
    emit isDownloadingChanged();
    emit isBusyChanged();
    emit downloadProgressChanged();

    if (m_mockMode) {
        // Simulate download
        m_statusMessage = QStringLiteral("Mock download complete. Ready to restart.");
        m_offlineStagedReady = true;
        m_isDownloading = false;
        emit isDownloadingChanged();
        emit isBusyChanged();
        emit offlineStagedReadyChanged();
        emit statusMessageChanged();
        emit operationSucceeded(QStringLiteral("Updates staged for next boot."));
        return;
    }

    QMetaObject::invokeMethod(m_worker, "stageOfflineUpgrade", Qt::QueuedConnection);
}

void UpdateManager::startInPlaceUpgrade() {
    if (m_isDownloading || m_isApplying) return;
    m_isApplying = true;
    m_transactionProgress = 0.0;
    emit isApplyingChanged();
    emit isBusyChanged();
    emit transactionProgressChanged();

    if (m_mockMode) {
        m_isApplying = false;
        m_model.clear();
        recalculateTotals();
        emit isApplyingChanged();
        emit isBusyChanged();
        emit operationSucceeded(QStringLiteral("Mock updates applied successfully."));
        return;
    }

    QMetaObject::invokeMethod(m_worker, "startInPlaceUpgrade", Qt::QueuedConnection);
}

void UpdateManager::rebootAndApply() {
    if (m_mockMode) {
        m_statusMessage = QStringLiteral("Mock reboot triggered.");
        emit statusMessageChanged();
        return;
    }
    QMetaObject::invokeMethod(m_worker, "rebootAndApply", Qt::QueuedConnection);
}

void UpdateManager::cancelOperation() {
    if (m_mockMode) {
        m_isChecking = false;
        m_isDownloading = false;
        m_isApplying = false;
        emit isCheckingChanged();
        emit isDownloadingChanged();
        emit isApplyingChanged();
        emit isBusyChanged();
        return;
    }
    QMetaObject::invokeMethod(m_worker, "cancelOperation", Qt::QueuedConnection);
}

void UpdateManager::cleanOffline() {
    if (m_mockMode) {
        m_offlineStagedReady = false;
        emit offlineStagedReadyChanged();
        return;
    }
    QMetaObject::invokeMethod(m_worker, "cleanOffline", Qt::QueuedConnection);
}

void UpdateManager::loadMockData() {
    QList<UpdateItem> mockList;

    // 1. Kernel update (Reboot required)
    UpdateItem k;
    k.name = QStringLiteral("kernel-core");
    k.oldEvr = QStringLiteral("7.2.5-200.fc44");
    k.newEvr = QStringLiteral("7.2.8-200.fc44");
    k.arch = QStringLiteral("x86_64");
    k.summary = QStringLiteral("The Linux kernel core image and modules");
    k.repoId = QStringLiteral("updates");
    k.downloadSize = 184549120; // ~176 MB
    k.installSize = 314572800;
    k.vendor = QStringLiteral("Fedora Project");
    k.categoryKey = QStringLiteral("kernel");
    k.category = UpdateItem::categoryKeyToLabel(k.categoryKey);
    k.advisoryId = QStringLiteral("FEDORA-2026-9812");
    k.advisoryType = QStringLiteral("security");
    k.severity = QStringLiteral("important");
    k.advisoryTitle = QStringLiteral("Linux Kernel 7.2.8 security and stability update");
    k.advisoryDescription = QStringLiteral("Fixes memory leak in btrfs and security vulnerability in packet filter.");
    k.cveList = QStringList{QStringLiteral("CVE-2026-3829"), QStringLiteral("CVE-2026-3830")};
    k.requiresReboot = true;
    mockList.append(k);

    // 2. Firmware update (Reboot required)
    UpdateItem fw;
    fw.name = QStringLiteral("linux-firmware");
    fw.oldEvr = QStringLiteral("20260901-1.fc44");
    fw.newEvr = QStringLiteral("20260920-1.fc44");
    fw.arch = QStringLiteral("noarch");
    fw.summary = QStringLiteral("Firmware files used by the Linux kernel");
    fw.repoId = QStringLiteral("updates");
    fw.downloadSize = 429916160; // ~410 MB
    fw.installSize = 980000000;
    fw.vendor = QStringLiteral("Fedora Project");
    fw.categoryKey = QStringLiteral("firmware");
    fw.category = UpdateItem::categoryKeyToLabel(fw.categoryKey);
    fw.advisoryType = QStringLiteral("bugfix");
    fw.severity = QStringLiteral("moderate");
    fw.advisoryTitle = QStringLiteral("Updated firmware binaries for AMD GPU and Intel Wi-Fi");
    fw.requiresReboot = true;
    mockList.append(fw);

    // 3. Mesa Drivers (Session restart required)
    UpdateItem mesa;
    mesa.name = QStringLiteral("mesa-dri-drivers");
    mesa.oldEvr = QStringLiteral("25.1.2-1.fc44");
    mesa.newEvr = QStringLiteral("25.2.0-1.fc44");
    mesa.arch = QStringLiteral("x86_64");
    mesa.summary = QStringLiteral("Mesa-based DRI drivers for 3D hardware acceleration");
    mesa.repoId = QStringLiteral("updates");
    mesa.downloadSize = 34500000;
    mesa.installSize = 95000000;
    mesa.vendor = QStringLiteral("Fedora Project");
    mesa.categoryKey = QStringLiteral("shell");
    mesa.category = UpdateItem::categoryKeyToLabel(mesa.categoryKey);
    mesa.advisoryType = QStringLiteral("enhancement");
    mesa.severity = QStringLiteral("none");
    mesa.advisoryTitle = QStringLiteral("Mesa 25.2 graphics stack update");
    mesa.requiresSessionRestart = true;
    mockList.append(mesa);

    // 4. Firefox (Desktop App - safe live upgrade)
    UpdateItem ff;
    ff.name = QStringLiteral("firefox");
    ff.oldEvr = QStringLiteral("134.0.2-1.fc44");
    ff.newEvr = QStringLiteral("135.0.0-1.fc44");
    ff.arch = QStringLiteral("x86_64");
    ff.summary = QStringLiteral("Mozilla Firefox Web Browser");
    ff.repoId = QStringLiteral("updates");
    ff.downloadSize = 71303168; // ~68 MB
    ff.installSize = 250000000;
    ff.vendor = QStringLiteral("Fedora Project");
    ff.categoryKey = QStringLiteral("app");
    ff.category = UpdateItem::categoryKeyToLabel(ff.categoryKey);
    ff.advisoryId = QStringLiteral("FEDORA-2026-4411");
    ff.advisoryType = QStringLiteral("security");
    ff.severity = QStringLiteral("critical");
    ff.advisoryTitle = QStringLiteral("Firefox 135.0 security advisory");
    ff.advisoryDescription = QStringLiteral("Multiple security vulnerabilities addressed including canvas exploit.");
    ff.cveList = QStringList{QStringLiteral("CVE-2026-2101"), QStringLiteral("CVE-2026-2102"), QStringLiteral("CVE-2026-2103")};
    mockList.append(ff);

    // 5. Plasma Workspace (Desktop Environment)
    UpdateItem pw;
    pw.name = QStringLiteral("plasma-workspace");
    pw.oldEvr = QStringLiteral("6.7.4-1.fc44");
    pw.newEvr = QStringLiteral("6.7.5-1.fc44");
    pw.arch = QStringLiteral("x86_64");
    pw.summary = QStringLiteral("KDE Plasma Workspace runtime components and shell");
    pw.repoId = QStringLiteral("updates");
    pw.downloadSize = 18900000;
    pw.installSize = 48000000;
    pw.vendor = QStringLiteral("Fedora Project");
    pw.categoryKey = QStringLiteral("shell");
    pw.category = UpdateItem::categoryKeyToLabel(pw.categoryKey);
    pw.advisoryType = QStringLiteral("bugfix");
    pw.severity = QStringLiteral("moderate");
    pw.advisoryTitle = QStringLiteral("KDE Plasma 6.7.5 bugfix release");
    pw.requiresSessionRestart = true;
    mockList.append(pw);

    m_model.setItems(mockList);
    m_lastChecked = QDateTime::currentDateTime();
    recalculateTotals();

    m_statusMessage = QStringLiteral("%1 updates available (Mock Mode)").arg(mockList.size());
    emit lastCheckedTextChanged();
    emit statusMessageChanged();
}

void UpdateManager::handleCheckStarted() {
    m_checkPercent = 0;
    m_currentStep = QStringLiteral("Starting check...");
    emit checkPercentChanged();
    emit currentStepChanged();
}

void UpdateManager::handleCheckProgress(const QString &status, int percent) {
    m_currentStep = status;
    m_checkPercent = percent;
    emit currentStepChanged();
    emit checkPercentChanged();
}

void UpdateManager::handleCheckFinished(const QList<UpdateItem> &items, bool success, const QString &errorMsg) {
    m_isChecking = false;
    m_lastChecked = QDateTime::currentDateTime();

    if (!success) {
        m_errorMessage = errorMsg;
        emit errorMessageChanged();
        emit operationFailed(errorMsg);
    } else {
        m_model.setItems(items);
        recalculateTotals();
        emit updatesAvailable(m_model.count(), m_securityCount);
    }

    emit isCheckingChanged();
    emit isBusyChanged();
    emit lastCheckedTextChanged();
}

void UpdateManager::handleChangelogFetched(const QString &packageName, const QVariantList &entries) {
    m_model.updateChangelog(packageName, entries);
}

void UpdateManager::handleDownloadProgress(quint64 downloadedBytes, quint64 totalBytes, double fraction) {
    Q_UNUSED(downloadedBytes);
    Q_UNUSED(totalBytes);
    m_downloadProgress = fraction;
    emit downloadProgressChanged();
}

void UpdateManager::handleInPlaceProgress(const QString &nevra, int action, quint64 processed, quint64 total) {
    Q_UNUSED(action);
    if (total > 0) {
        m_transactionProgress = static_cast<double>(processed) / static_cast<double>(total);
        emit transactionProgressChanged();
    }
    m_statusMessage = QStringLiteral("Processing (%1/%2): %3").arg(processed).arg(total).arg(nevra);
    emit statusMessageChanged();
}

void UpdateManager::handleOperationFinished(bool success, const QString &message) {
    m_isDownloading = false;
    m_isApplying = false;
    emit isDownloadingChanged();
    emit isApplyingChanged();
    emit isBusyChanged();

    if (success) {
        emit operationSucceeded(message);
    } else {
        m_errorMessage = message;
        emit errorMessageChanged();
        emit operationFailed(message);
    }
}

void UpdateManager::handleOfflineStagedReady(bool ready) {
    if (m_offlineStagedReady != ready) {
        m_offlineStagedReady = ready;
        emit offlineStagedReadyChanged();
    }
}

void UpdateManager::handleStatusMessageChanged(const QString &status) {
    m_statusMessage = status;
    emit statusMessageChanged();
}

void UpdateManager::recalculateTotals() {
    int secCount = 0;
    quint64 totalBytes = 0;
    bool needsReboot = false;

    for (const auto &item : m_model.items()) {
        totalBytes += item.downloadSize;
        if (item.advisoryType == QStringLiteral("security")) {
            secCount++;
        }
        if (item.requiresReboot) {
            needsReboot = true;
        }
    }

    m_securityCount = secCount;
    m_totalDownloadSize = totalBytes;
    m_recommendedMethod = needsReboot ? QStringLiteral("offline") : QStringLiteral("inplace");

    emit updateCountChanged();
    emit hasUpdatesChanged();
    emit securityCountChanged();
    emit totalDownloadSizeChanged();
    emit recommendedMethodChanged();
}

} // namespace qs::updatemanager
