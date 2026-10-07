#pragma once

#include "DbusTypes.hpp"
#include "UpdateItem.hpp"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusObjectPath>
#include <QList>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace qs::updatemanager {

class UpdateWorker : public QObject {
    Q_OBJECT

public:
    explicit UpdateWorker(QObject *parent = nullptr);
    ~UpdateWorker() override;

public slots:
    void checkForUpdates(bool refresh);
    void fetchChangelog(const QString &packageName);
    void startInPlaceUpgrade();
    void stageOfflineUpgrade();
    void rebootAndApply();
    void cancelOperation();
    void cleanOffline();
    void cleanAll();
    void autoremove();

signals:
    void checkStarted();
    void checkProgress(const QString &status, int percent);
    void checkFinished(const QList<qs::updatemanager::UpdateItem> &items, bool success, const QString &errorMsg);
    void changelogFetched(const QString &packageName, const QVariantList &entries);
    void downloadProgress(quint64 downloadedBytes, quint64 totalBytes, double fraction);
    void inPlaceProgress(const QString &nevra, int action, quint64 processed, quint64 total, double fraction);
    void progressStageUpdated(const QString &stage, const QString &stageDisplayName,
                              const QString &nevra, quint64 processed, quint64 total, double fraction);
    void operationFinished(bool success, const QString &message);
    void offlineStagedReady(bool ready);
    void statusMessageChanged(const QString &status);
    void cleanFinished(bool success, const QString &message);
    void autoremoveFinished(bool success, const QString &message);

private slots:
    void onDownloadAddNew(const QDBusObjectPath &session, const QString &downloadId,
                          const QString &description, qint64 totalToDownload);
    void onDownloadProgress(const QDBusObjectPath &session, const QString &downloadId,
                            qint64 totalToDownload, qint64 downloaded);
    void onDownloadEnd(const QDBusObjectPath &session, const QString &downloadId,
                       uint transferStatus, const QString &message);
    void onDownloadMirrorFailure(const QDBusObjectPath &session, const QString &downloadId,
                                 const QString &message, const QString &url, const QString &metadata);
    void onRepoKeyImportRequest(const QDBusObjectPath &session, const QString &keyId,
                                const QStringList &userIds, const QString &keyFingerprint,
                                const QString &keyUrl, qint64 timestamp);
    void onTransactionBeforeBegin(const QDBusObjectPath &session, qulonglong total);
    void onTransactionTransactionStart(const QDBusObjectPath &session, qulonglong total);
    void onTransactionTransactionProgress(const QDBusObjectPath &session, qulonglong processed, qulonglong total);
    void onTransactionTransactionStop(const QDBusObjectPath &session, qulonglong total);
    void onTransactionVerifyStart(const QDBusObjectPath &session, qulonglong total);
    void onTransactionVerifyProgress(const QDBusObjectPath &session, qulonglong processed, qulonglong total);
    void onTransactionVerifyStop(const QDBusObjectPath &session, qulonglong total);
    void onTransactionElemProgress(const QDBusObjectPath &session, const QString &nevra,
                                   qulonglong processed, qulonglong total);
    void onTransactionActionStart(const QDBusObjectPath &session, const QString &nevra,
                                  uint action, qulonglong total);
    void onTransactionActionProgress(const QDBusObjectPath &session, const QString &nevra,
                                     qulonglong processed, qulonglong total);
    void onTransactionActionStop(const QDBusObjectPath &session, const QString &nevra,
                                 qulonglong total);
    void onTransactionScriptStart(const QDBusObjectPath &session, const QString &nevra,
                                  uint scriptletType);
    void onTransactionScriptStop(const QDBusObjectPath &session, const QString &nevra,
                                 uint scriptletType, qulonglong returnCode);
    void onTransactionScriptError(const QDBusObjectPath &session, const QString &nevra,
                                  uint scriptletType, qulonglong returnCode);
    void onTransactionUnpackError(const QDBusObjectPath &session, const QString &nevra);
    void onTransactionAfterComplete(const QDBusObjectPath &session, bool success);

private:
    bool openSession(bool loadSystemRepo = true, bool loadAvailableRepos = true, QString *errOut = nullptr);
    bool ensureDaemonActive(int timeoutMs = 30000);
    void closeSession();
    void connectTransactionSignals();
    void disconnectTransactionSignals();
    void verifyTransactionResult(const QString &fallbackErrMsg, const QString &errStr);

    QString m_sessionPath;
    bool m_cancelled{false};
    bool m_transactionSignalsConnected{false};
    quint64 m_totalBytesToDownload{0};
    QMap<QString, qint64> m_downloadedPerId;
    QMap<QString, qint64> m_totalPerId;
    QString m_currentNevra;
    uint m_currentAction{0};
    quint64 m_pkgTotalCount{0};
    quint64 m_currentPkgIndex{0};
    quint64 m_pkgItemProcessed{0};
    quint64 m_pkgItemTotal{0};
    quint64 m_verifyTotal{0};
    quint64 m_verifyProcessed{0};
    quint64 m_prepTotal{0};
    quint64 m_prepProcessed{0};
};

} // namespace qs::updatemanager
