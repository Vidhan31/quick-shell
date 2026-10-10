#include "UpdateManager.hpp"

#include <algorithm>
#include <QColor>
#include <QDateTime>
#include <QMetaObject>
#include <QTimer>

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
    connect(m_worker, &UpdateWorker::progressStageUpdated, this, &UpdateManager::handleProgressStageUpdated);
    connect(m_worker, &UpdateWorker::operationFinished, this, &UpdateManager::handleOperationFinished);
    connect(m_worker, &UpdateWorker::offlineStagedReady, this, &UpdateManager::handleOfflineStagedReady);
    connect(m_worker, &UpdateWorker::statusMessageChanged, this, &UpdateManager::handleStatusMessageChanged);
    connect(m_worker, &UpdateWorker::cleanFinished, this, &UpdateManager::handleCleanFinished);
    connect(m_worker, &UpdateWorker::autoremoveFinished, this, &UpdateManager::handleAutoremoveFinished);
    connect(&m_model, &UpdateModel::revisionChanged, this, &UpdateManager::modelRevisionChanged);

    m_workerThread.start();

    // Automatic check once a day at 12:00 PM local time. Otherwise strictly manual.
    m_dailyTimer = new QTimer(this);
    m_dailyTimer->setSingleShot(true);
    connect(m_dailyTimer, &QTimer::timeout, this, [this]() {
        checkForUpdates(false);
        m_dailyTimer->start(msUntilNextNoon());
    });
    m_dailyTimer->start(msUntilNextNoon());
}

UpdateManager::~UpdateManager() {
    if (m_dailyTimer) {
        m_dailyTimer->stop();
    }
    m_workerThread.quit();
    m_workerThread.wait();
    delete m_worker;
}

qint64 UpdateManager::msUntilNextNoon() const {
    const QDateTime now = QDateTime::currentDateTime();
    QDateTime noon(now.date(), QTime(12, 0, 0, 0));
    if (now >= noon) {
        noon = noon.addDays(1);
    }
    const qint64 diff = now.msecsTo(noon);
    return std::max<qint64>(1000, diff);
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

QString UpdateManager::summaryGlyph() const {
    if (m_offlineStagedReady) return QString::fromUtf8("󰜉"); // Reboot ready
    if (m_progressStage == QLatin1String("authenticating")) return QString::fromUtf8("󰒃"); // Polkit shield
    if (m_progressStage == QLatin1String("downloading") || m_isDownloading) return QString::fromUtf8("󰇚"); // Downloading
    if (m_progressStage == QLatin1String("verifying")) return QString::fromUtf8("󰒃"); // Shield / verifying check
    if (m_progressStage == QLatin1String("installing")) return QString::fromUtf8("󰚰"); // Installing package
    if (m_progressStage == QLatin1String("upgrading")) return QString::fromUtf8("󰑐"); // Upgrading sync
    if (m_progressStage == QLatin1String("removing")) return QString::fromUtf8("󰆴"); // Removing
    if (m_progressStage == QLatin1String("downgrading")) return QString::fromUtf8("󰜉"); // Downgrading
    if (m_progressStage == QLatin1String("reinstalling")) return QString::fromUtf8("󰑐"); // Reinstalling
    if (m_progressStage == QLatin1String("cleanup") || m_isCleaning) return QString::fromUtf8("󰃢"); // Cleanup / broom
    if (m_progressStage == QLatin1String("configuring")) return QString::fromUtf8("󰌢"); // Configuring / scriptlet
    if (m_progressStage == QLatin1String("preparing") || m_progressStage == QLatin1String("resolving")) return QString::fromUtf8("󰑐"); // Preparing
    if (m_isApplying) return QString::fromUtf8("󰑐"); // In-place upgrade
    if (m_isAutoremoving) return QString::fromUtf8("󰆴"); // Autoremoving
    if (m_isChecking) return QString::fromUtf8("󰑐"); // Checking
    if (m_securityCount > 0) return QString::fromUtf8("󰒃"); // Security shield
    if (hasUpdates()) return QString::fromUtf8("󰚰"); // Available updates
    return QString::fromUtf8("󰚰"); // Up to date
}

QColor UpdateManager::statusColor() const {
    static const QColor colGreen(QStringLiteral("#46C786"));
    static const QColor colAmber(QStringLiteral("#E2A63B"));
    static const QColor colTeal(QStringLiteral("#94E2D5"));
    static const QColor colAccent(QStringLiteral("#5E9DFF"));
    static const QColor colInk3(QStringLiteral("#6F6F84"));

    if (m_offlineStagedReady) return colGreen;
    if (m_progressStage == QLatin1String("authenticating")) return colAmber;
    if (m_progressStage == QLatin1String("verifying")) return colTeal;
    if (m_progressStage == QLatin1String("removing") || m_progressStage == QLatin1String("cleanup")
        || m_isCleaning || m_isAutoremoving) return colAmber;
    if (!m_progressStage.isEmpty() || m_isApplying || m_isDownloading || m_isChecking) return colAccent;
    if (m_securityCount > 0) return colAmber;
    if (hasUpdates()) return colAccent;
    return colInk3;
}

QColor UpdateManager::labelColor() const {
    static const QColor colGreen(QStringLiteral("#46C786"));
    static const QColor colAmber(QStringLiteral("#E2A63B"));
    static const QColor colAccent(QStringLiteral("#5E9DFF"));
    static const QColor colInk1(QStringLiteral("#F1F1F6"));
    static const QColor colInk3(QStringLiteral("#6F6F84"));

    if (m_offlineStagedReady) return colGreen;
    if (m_progressStage == QLatin1String("authenticating")) return colAmber;
    if (!m_progressStage.isEmpty() || m_isApplying || m_isDownloading || m_isCleaning || m_isAutoremoving || m_isChecking) return colAccent;
    if (m_securityCount > 0) return colAmber;
    if (hasUpdates()) return colInk1;
    return colInk3;
}

QString UpdateManager::summaryText() const {
    if (m_offlineStagedReady) return QStringLiteral("Restart");
    if (!m_progressStage.isEmpty()) {
        if (m_progressStage == QLatin1String("authenticating")) return QStringLiteral("Authenticating");
        if (m_progressStage == QLatin1String("checking")) return QStringLiteral("Checking");
        if (m_progressStage == QLatin1String("cleaning")) return QStringLiteral("Cleaning");
        if (m_progressStage == QLatin1String("autoremoving")) return QStringLiteral("Autoremoving");
        if (m_progressStage == QLatin1String("resolving")) return QStringLiteral("Resolving");
        if (m_progressStage == QLatin1String("configuring")) return QStringLiteral("Configuring");
        const int p = std::clamp(activePercent(), 0, 100);
        return QStringLiteral("%1 %2%").arg(m_progressStageDisplayName).arg(p);
    }
    if (m_isApplying) {
        const int p = std::clamp(static_cast<int>(std::round(m_transactionProgress * 100.0)), 0, 100);
        return QStringLiteral("Applying %1%").arg(p);
    }
    if (m_isDownloading) {
        const int p = std::clamp(static_cast<int>(std::round(m_downloadProgress * 100.0)), 0, 100);
        return QStringLiteral("Downloading %1%").arg(p);
    }
    if (m_isCleaning) return QStringLiteral("Cleaning");
    if (m_isAutoremoving) return QStringLiteral("Autoremoving");
    if (m_isChecking) return QStringLiteral("Checking");
    if (m_securityCount > 0) return QStringLiteral("%1 (%2 sec)").arg(m_model.count()).arg(m_securityCount);
    if (hasUpdates()) return QString::number(m_model.count());
    return QString();
}

bool UpdateManager::isSpinning() const {
    return summaryGlyph() == QString::fromUtf8("󰑐")
        && (m_isChecking || m_isApplying || !m_progressStage.isEmpty());
}

QString UpdateManager::progressPercentText() const {
    if (m_progressStage == QLatin1String("authenticating")) {
        return QString();
    }
    if (!m_progressStage.isEmpty()) {
        const int p = std::clamp(activePercent(), 0, 100);
        return QStringLiteral("%1%").arg(p);
    }
    const double frac = m_isDownloading ? m_downloadProgress : (m_isApplying ? m_transactionProgress : 0.0);
    const int p = std::clamp(static_cast<int>(std::round(frac * 100.0)), 0, 100);
    return QStringLiteral("%1%").arg(p);
}

QString UpdateManager::headerStatusText() const {
    if (m_isCleaning) return QStringLiteral("Cleaning all package caches…");
    if (m_isAutoremoving) return QStringLiteral("Checking and removing unused dependencies…");
    if (m_isChecking) return m_currentStep.isEmpty() ? QStringLiteral("Checking repositories…") : m_currentStep;
    if (m_offlineStagedReady) return QStringLiteral("Updates staged · Ready to restart");
    if (hasUpdates()) return QStringLiteral("%1 updates (%2) · Checked %3").arg(m_model.count()).arg(formattedTotalSize()).arg(lastCheckedText());
    return QStringLiteral("System up to date · Checked %1").arg(lastCheckedText());
}

QString UpdateManager::statusMessage() const {
    if (!m_statusMessage.isEmpty()) {
        return m_statusMessage;
    }
    if (m_progressStage == QLatin1String("authenticating")) {
        return QStringLiteral("Waiting for authentication (Polkit prompt)…");
    }
    if (m_isDownloading) {
        return QStringLiteral("Downloading updates…");
    }
    if (m_isApplying) {
        return QStringLiteral("Applying updates (requires authentication)…");
    }
    if (m_isCleaning) {
        return QStringLiteral("Cleaning all package caches…");
    }
    if (m_isAutoremoving) {
        return QStringLiteral("Checking and removing unused dependencies…");
    }
    if (m_isChecking) {
        return m_currentStep.isEmpty() ? QStringLiteral("Checking repositories…") : m_currentStep;
    }
    return QString();
}

void UpdateManager::checkForUpdates(bool refresh) {
    if (isBusy()) {
        return;
    }

    m_isChecking = true;
    m_progressStage = QStringLiteral("checking");
    m_progressStageDisplayName = QStringLiteral("Checking");
    m_errorMessage.clear();
    emit isCheckingChanged();
    emit isBusyChanged();
    emit errorMessageChanged();
    emit progressStageChanged();
    emit summaryChanged();

    QMetaObject::invokeMethod(m_worker, &UpdateWorker::checkForUpdates, Qt::QueuedConnection, refresh);
}

void UpdateManager::fetchChangelog(const QString &packageName) {
    QMetaObject::invokeMethod(m_worker, &UpdateWorker::fetchChangelog, Qt::QueuedConnection, packageName);
}

void UpdateManager::stageOfflineUpgrade() {
    if (isBusy()) return;
    m_isDownloading = true;
    m_downloadProgress = 0.0;
    m_progressStage = QStringLiteral("downloading");
    m_progressStageDisplayName = QStringLiteral("Downloading");
    m_activeProgress = 0.0;
    m_activeProcessed = 0;
    m_activeTotal = 0;
    emit isDownloadingChanged();
    emit isBusyChanged();
    emit downloadProgressChanged();
    emit progressStageChanged();
    emit activeProgressChanged();
    emit summaryChanged();

    QMetaObject::invokeMethod(m_worker, &UpdateWorker::stageOfflineUpgrade, Qt::QueuedConnection);
}

void UpdateManager::startInPlaceUpgrade() {
    if (isBusy()) return;
    m_isApplying = true;
    m_downloadProgress = 0.0;
    m_transactionProgress = 0.0;
    m_progressStage = QStringLiteral("authenticating");
    m_progressStageDisplayName = QStringLiteral("Authenticating");
    m_activeProgress = 0.0;
    m_activeProcessed = 0;
    m_activeTotal = 0;
    m_errorMessage.clear();
    emit isApplyingChanged();
    emit isBusyChanged();
    emit downloadProgressChanged();
    emit transactionProgressChanged();
    emit progressStageChanged();
    emit activeProgressChanged();
    emit errorMessageChanged();
    emit summaryChanged();

    QMetaObject::invokeMethod(m_worker, &UpdateWorker::startInPlaceUpgrade, Qt::QueuedConnection);
}

void UpdateManager::rebootAndApply() {
    QMetaObject::invokeMethod(m_worker, &UpdateWorker::rebootAndApply, Qt::QueuedConnection);
}

void UpdateManager::cancelOperation() {
    QMetaObject::invokeMethod(m_worker, &UpdateWorker::cancelOperation, Qt::QueuedConnection);
}

void UpdateManager::cleanOffline() {
    QMetaObject::invokeMethod(m_worker, &UpdateWorker::cleanOffline, Qt::QueuedConnection);
}

void UpdateManager::cleanAll() {
    cleanCache(QStringLiteral("all"));
}

void UpdateManager::cleanCache(const QString &cacheType) {
    if (isBusy()) return;
    m_isCleaning = true;
    m_progressStage = QStringLiteral("cleaning");
    m_progressStageDisplayName = QStringLiteral("Cleaning");
    m_errorMessage.clear();
    emit isCleaningChanged();
    emit isBusyChanged();
    emit errorMessageChanged();
    emit progressStageChanged();
    emit summaryChanged();

    QMetaObject::invokeMethod(m_worker, [this, cacheType]() {
        m_worker->cleanCache(cacheType);
    }, Qt::QueuedConnection);
}

void UpdateManager::autoremove() {
    if (isBusy()) return;
    m_isAutoremoving = true;
    m_progressStage = QStringLiteral("autoremoving");
    m_progressStageDisplayName = QStringLiteral("Autoremoving");
    m_errorMessage.clear();
    emit isAutoremovingChanged();
    emit isBusyChanged();
    emit errorMessageChanged();
    emit progressStageChanged();
    emit summaryChanged();

    QMetaObject::invokeMethod(m_worker, &UpdateWorker::autoremove, Qt::QueuedConnection);
}

void UpdateManager::handleCheckStarted() {
    bool wasChecking = m_isChecking;
    m_isChecking = true;
    m_checkPercent = 0;
    m_currentStep = QStringLiteral("Starting check...");
    if (m_progressStage.isEmpty()) {
        m_progressStage = QStringLiteral("checking");
        m_progressStageDisplayName = QStringLiteral("Checking");
        emit progressStageChanged();
    }
    if (!wasChecking) {
        emit isCheckingChanged();
        emit isBusyChanged();
    }
    emit checkPercentChanged();
    emit currentStepChanged();
    emit summaryChanged();
}

void UpdateManager::handleCheckProgress(const QString &status, int percent) {
    m_currentStep = status;
    m_checkPercent = percent;
    emit currentStepChanged();
    emit checkPercentChanged();
    emit summaryChanged();
}

void UpdateManager::handleCheckFinished(const QList<UpdateItem> &items, bool success, const QString &errorMsg) {
    m_isChecking = false;
    m_progressStage.clear();
    m_progressStageDisplayName.clear();
    m_lastChecked = QDateTime::currentDateTime();

    // Clear busy state first: QML auto-syncs selectedMethod on
    // recommendedMethodChanged only when not busy, and recalculateTotals()
    // below emits that signal. Emitting busy-state first guarantees the
    // guard observes isBusy == false.
    emit isCheckingChanged();
    emit isBusyChanged();

    if (!success) {
        m_errorMessage = errorMsg;
        emit errorMessageChanged();
        emit operationFailed(errorMsg);
    } else {
        m_model.setItems(items);
        recalculateTotals();
        emit updatesAvailable(m_model.count(), m_securityCount);
    }

    emit progressStageChanged();
    emit lastCheckedTextChanged();
    emit summaryChanged();
}

void UpdateManager::handleChangelogFetched(const QString &packageName, const QVariantList &entries) {
    m_model.updateChangelog(packageName, entries);
}

void UpdateManager::handleDownloadProgress(quint64 downloadedBytes, quint64 totalBytes, double fraction) {
    m_downloadProgress = fraction;
    emit downloadProgressChanged();
    if (totalBytes > 0) {
        const double dlMb = static_cast<double>(downloadedBytes) / (1024.0 * 1024.0);
        const double totMb = static_cast<double>(totalBytes) / (1024.0 * 1024.0);
        m_statusMessage = QString::asprintf("Downloading: %.1f MB / %.1f MB (%d%%)", dlMb, totMb, static_cast<int>(fraction * 100.0));
        emit statusMessageChanged();
    }
    emit summaryChanged();
}

void UpdateManager::handleInPlaceProgress(const QString &nevra, int action, quint64 processed, quint64 total, double fraction) {
    m_transactionProgress = qBound(0.0, fraction, 1.0);
    emit transactionProgressChanged();

    QString actionStr;
    switch (action) {
        case 0: actionStr = QStringLiteral("Installing"); break;
        case 1: actionStr = QStringLiteral("Removing"); break;
        case 2: actionStr = QStringLiteral("Upgrading"); break;
        case 3: actionStr = QStringLiteral("Downgrading"); break;
        case 4: actionStr = QStringLiteral("Reinstalling"); break;
        case 5: actionStr = QStringLiteral("Cleanup"); break;
        default: actionStr = QStringLiteral("Installing"); break;
    }

    if (!nevra.isEmpty()) {
        if (total > 0 && processed > 0) {
            m_statusMessage = QStringLiteral("%1 (%2/%3): %4").arg(actionStr).arg(processed).arg(total).arg(nevra);
        } else {
            m_statusMessage = QStringLiteral("%1: %2").arg(actionStr).arg(nevra);
        }
    } else if (total > 0 && processed > 0) {
        m_statusMessage = QStringLiteral("%1 (%2/%3)...").arg(actionStr).arg(processed).arg(total);
    }
    emit statusMessageChanged();
    emit summaryChanged();
}

void UpdateManager::handleProgressStageUpdated(const QString &stage, const QString &stageDisplayName,
                                              const QString &nevra, quint64 processed, quint64 total, double fraction) {
    bool stageChanged = (m_progressStage != stage || m_progressStageDisplayName != stageDisplayName);
    m_progressStage = stage;
    m_progressStageDisplayName = stageDisplayName;

    if (m_activeNevra != nevra) {
        m_activeNevra = nevra;
        emit activeNevraChanged();
    }

    m_activeProcessed = processed;
    m_activeTotal = total;
    m_activeProgress = qBound(0.0, fraction, 1.0);

    if (stageChanged) {
        emit progressStageChanged();
    }
    emit activeProgressChanged();
    emit summaryChanged();
}

void UpdateManager::handleOperationFinished(bool success, const QString &message) {
    bool wasApplying = m_isApplying;
    m_isDownloading = false;
    m_isApplying = false;
    m_isCleaning = false;
    m_isAutoremoving = false;
    m_progressStage.clear();
    m_progressStageDisplayName.clear();
    m_activeNevra.clear();
    m_activeProgress = 0.0;
    m_activeProcessed = 0;
    m_activeTotal = 0;
    emit isDownloadingChanged();
    emit isApplyingChanged();
    emit isCleaningChanged();
    emit isAutoremovingChanged();
    emit isBusyChanged();
    emit progressStageChanged();
    emit activeProgressChanged();
    emit activeNevraChanged();

    if (success) {
        if (wasApplying) {
            m_model.clear();
            recalculateTotals();
        }
        emit operationSucceeded(message);
    } else {
        m_errorMessage = message;
        emit errorMessageChanged();
        emit operationFailed(message);
    }
    emit summaryChanged();
}

void UpdateManager::handleCleanFinished(bool success, const QString &message) {
    m_isCleaning = false;
    m_progressStage.clear();
    m_progressStageDisplayName.clear();
    emit isCleaningChanged();
    emit isBusyChanged();
    emit progressStageChanged();

    if (success) {
        emit operationSucceeded(message);
    } else {
        m_errorMessage = message;
        emit errorMessageChanged();
        emit operationFailed(message);
    }
    emit summaryChanged();
}

void UpdateManager::handleAutoremoveFinished(bool success, const QString &message) {
    m_isAutoremoving = false;
    m_progressStage.clear();
    m_progressStageDisplayName.clear();
    emit isAutoremovingChanged();
    emit isBusyChanged();
    emit progressStageChanged();

    if (success) {
        emit operationSucceeded(message);
    } else {
        m_errorMessage = message;
        emit errorMessageChanged();
        emit operationFailed(message);
    }
    emit summaryChanged();
}

void UpdateManager::handleOfflineStagedReady(bool ready) {
    if (m_offlineStagedReady != ready) {
        m_offlineStagedReady = ready;
        emit offlineStagedReadyChanged();
        emit summaryChanged();
    }
}

void UpdateManager::handleStatusMessageChanged(const QString &status) {
    m_statusMessage = status;
    emit statusMessageChanged();
    emit summaryChanged();
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
    emit summaryChanged();
}

} // namespace qs::updatemanager
