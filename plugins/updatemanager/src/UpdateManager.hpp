#pragma once

#include "UpdateModel.hpp"
#include "UpdateWorker.hpp"

#include <QColor>
#include <QDateTime>
#include <QObject>
#include <QString>
#include <QThread>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

namespace qs::updatemanager {

class UpdateManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(UpdateManager)

    Q_PROPERTY(QString summaryGlyph READ summaryGlyph NOTIFY summaryChanged)
    Q_PROPERTY(QString summaryText READ summaryText NOTIFY summaryChanged)
    Q_PROPERTY(QColor statusColor READ statusColor NOTIFY summaryChanged)
    Q_PROPERTY(QColor labelColor READ labelColor NOTIFY summaryChanged)
    Q_PROPERTY(bool isSpinning READ isSpinning NOTIFY summaryChanged)
    Q_PROPERTY(QString progressPercentText READ progressPercentText NOTIFY summaryChanged)
    Q_PROPERTY(QString headerStatusText READ headerStatusText NOTIFY summaryChanged)

    Q_PROPERTY(qs::updatemanager::UpdateModel* model READ model CONSTANT)
    Q_PROPERTY(bool isChecking READ isChecking NOTIFY isCheckingChanged)
    Q_PROPERTY(bool isDownloading READ isDownloading NOTIFY isDownloadingChanged)
    Q_PROPERTY(bool isApplying READ isApplying NOTIFY isApplyingChanged)
    Q_PROPERTY(bool isCleaning READ isCleaning NOTIFY isCleaningChanged)
    Q_PROPERTY(bool isAutoremoving READ isAutoremoving NOTIFY isAutoremovingChanged)
    Q_PROPERTY(bool isBusy READ isBusy NOTIFY isBusyChanged)
    Q_PROPERTY(bool hasUpdates READ hasUpdates NOTIFY hasUpdatesChanged)
    Q_PROPERTY(int updateCount READ updateCount NOTIFY updateCountChanged)
    Q_PROPERTY(int securityCount READ securityCount NOTIFY securityCountChanged)
    Q_PROPERTY(quint64 totalDownloadSize READ totalDownloadSize NOTIFY totalDownloadSizeChanged)
    Q_PROPERTY(QString formattedTotalSize READ formattedTotalSize NOTIFY totalDownloadSizeChanged)
    Q_PROPERTY(double downloadProgress READ downloadProgress NOTIFY downloadProgressChanged)
    Q_PROPERTY(double transactionProgress READ transactionProgress NOTIFY transactionProgressChanged)
    Q_PROPERTY(QString progressStage READ progressStage NOTIFY progressStageChanged)
    Q_PROPERTY(QString progressStageDisplayName READ progressStageDisplayName NOTIFY progressStageChanged)
    Q_PROPERTY(double activeProgress READ activeProgress NOTIFY activeProgressChanged)
    Q_PROPERTY(int activePercent READ activePercent NOTIFY activeProgressChanged)
    Q_PROPERTY(QString activeNevra READ activeNevra NOTIFY activeNevraChanged)
    Q_PROPERTY(quint64 activeProcessed READ activeProcessed NOTIFY activeProgressChanged)
    Q_PROPERTY(quint64 activeTotal READ activeTotal NOTIFY activeProgressChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString currentStep READ currentStep NOTIFY currentStepChanged)
    Q_PROPERTY(int checkPercent READ checkPercent NOTIFY checkPercentChanged)
    Q_PROPERTY(QString recommendedMethod READ recommendedMethod NOTIFY recommendedMethodChanged)
    Q_PROPERTY(bool offlineStagedReady READ offlineStagedReady NOTIFY offlineStagedReadyChanged)
    Q_PROPERTY(QString lastCheckedText READ lastCheckedText NOTIFY lastCheckedTextChanged)
    Q_PROPERTY(int modelRevision READ modelRevision NOTIFY modelRevisionChanged)

public:
    explicit UpdateManager(QObject *parent = nullptr);
    ~UpdateManager() override;

    [[nodiscard]] QString summaryGlyph() const;
    [[nodiscard]] QString summaryText() const;
    [[nodiscard]] QColor statusColor() const;
    [[nodiscard]] QColor labelColor() const;
    [[nodiscard]] bool isSpinning() const;
    [[nodiscard]] QString progressPercentText() const;
    [[nodiscard]] QString headerStatusText() const;

    [[nodiscard]] UpdateModel* model() { return &m_model; }
    [[nodiscard]] bool isChecking() const noexcept { return m_isChecking; }
    [[nodiscard]] bool isDownloading() const noexcept { return m_isDownloading; }
    [[nodiscard]] bool isApplying() const noexcept { return m_isApplying; }
    [[nodiscard]] bool isCleaning() const noexcept { return m_isCleaning; }
    [[nodiscard]] bool isAutoremoving() const noexcept { return m_isAutoremoving; }
    [[nodiscard]] bool isBusy() const noexcept {
        return m_isChecking || m_isDownloading || m_isApplying || m_isCleaning || m_isAutoremoving;
    }
    [[nodiscard]] bool hasUpdates() const noexcept { return m_model.count() > 0; }
    [[nodiscard]] int updateCount() const noexcept { return m_model.count(); }
    [[nodiscard]] int securityCount() const noexcept { return m_securityCount; }
    [[nodiscard]] quint64 totalDownloadSize() const noexcept { return m_totalDownloadSize; }
    [[nodiscard]] QString formattedTotalSize() const;
    [[nodiscard]] double downloadProgress() const noexcept { return m_downloadProgress; }
    [[nodiscard]] double transactionProgress() const noexcept { return m_transactionProgress; }
    [[nodiscard]] QString progressStage() const { return m_progressStage; }
    [[nodiscard]] QString progressStageDisplayName() const { return m_progressStageDisplayName; }
    [[nodiscard]] double activeProgress() const noexcept { return m_activeProgress; }
    [[nodiscard]] int activePercent() const noexcept { return static_cast<int>(std::round(m_activeProgress * 100.0)); }
    [[nodiscard]] QString activeNevra() const { return m_activeNevra; }
    [[nodiscard]] quint64 activeProcessed() const noexcept { return m_activeProcessed; }
    [[nodiscard]] quint64 activeTotal() const noexcept { return m_activeTotal; }
    [[nodiscard]] QString statusMessage() const;
    [[nodiscard]] QString errorMessage() const { return m_errorMessage; }
    [[nodiscard]] QString currentStep() const { return m_currentStep; }
    [[nodiscard]] int checkPercent() const noexcept { return m_checkPercent; }
    [[nodiscard]] QString recommendedMethod() const { return m_recommendedMethod; }
    [[nodiscard]] bool offlineStagedReady() const noexcept { return m_offlineStagedReady; }
    [[nodiscard]] QString lastCheckedText() const;
    [[nodiscard]] int modelRevision() const noexcept { return m_model.revision(); }

    Q_INVOKABLE void checkForUpdates(bool refresh = false);
    Q_INVOKABLE void fetchChangelog(const QString &packageName);
    Q_INVOKABLE void startInPlaceUpgrade();
    Q_INVOKABLE void stageOfflineUpgrade();
    Q_INVOKABLE void rebootAndApply();
    Q_INVOKABLE void cancelOperation();
    Q_INVOKABLE void cleanOffline();
    Q_INVOKABLE void cleanAll();
    Q_INVOKABLE void autoremove();

signals:
    void summaryChanged();
    void isCheckingChanged();
    void isDownloadingChanged();
    void isApplyingChanged();
    void isCleaningChanged();
    void isAutoremovingChanged();
    void isBusyChanged();
    void hasUpdatesChanged();
    void updateCountChanged();
    void securityCountChanged();
    void totalDownloadSizeChanged();
    void downloadProgressChanged();
    void transactionProgressChanged();
    void progressStageChanged();
    void activeProgressChanged();
    void activeNevraChanged();
    void statusMessageChanged();
    void errorMessageChanged();
    void currentStepChanged();
    void checkPercentChanged();
    void recommendedMethodChanged();
    void offlineStagedReadyChanged();
    void lastCheckedTextChanged();
    void modelRevisionChanged();
    void updatesAvailable(int count, int securityCount);
    void operationSucceeded(const QString &message);
    void operationFailed(const QString &error);

private slots:
    void handleCheckStarted();
    void handleCheckProgress(const QString &status, int percent);
    void handleCheckFinished(const QList<qs::updatemanager::UpdateItem> &items, bool success, const QString &errorMsg);
    void handleChangelogFetched(const QString &packageName, const QVariantList &entries);
    void handleDownloadProgress(quint64 downloadedBytes, quint64 totalBytes, double fraction);
    void handleInPlaceProgress(const QString &nevra, int action, quint64 processed, quint64 total, double fraction);
    void handleProgressStageUpdated(const QString &stage, const QString &stageDisplayName,
                                  const QString &nevra, quint64 processed, quint64 total, double fraction);
    void handleOperationFinished(bool success, const QString &message);
    void handleOfflineStagedReady(bool ready);
    void handleStatusMessageChanged(const QString &status);
    void handleCleanFinished(bool success, const QString &message);
    void handleAutoremoveFinished(bool success, const QString &message);

private:
    void recalculateTotals();
    [[nodiscard]] qint64 msUntilNextNoon() const;

    UpdateModel m_model;
    QThread m_workerThread;
    UpdateWorker *m_worker{nullptr};
    QTimer *m_dailyTimer{nullptr};

    bool m_isChecking{false};
    bool m_isDownloading{false};
    bool m_isApplying{false};
    bool m_isCleaning{false};
    bool m_isAutoremoving{false};
    int m_securityCount{0};
    quint64 m_totalDownloadSize{0};
    double m_downloadProgress{0.0};
    double m_transactionProgress{0.0};
    QString m_progressStage;
    QString m_progressStageDisplayName;
    double m_activeProgress{0.0};
    QString m_activeNevra;
    quint64 m_activeProcessed{0};
    quint64 m_activeTotal{0};
    QString m_statusMessage;
    QString m_errorMessage;
    QString m_currentStep;
    int m_checkPercent{0};
    QString m_recommendedMethod{QStringLiteral("inplace")};
    bool m_offlineStagedReady{false};
    QDateTime m_lastChecked;
};

} // namespace qs::updatemanager
