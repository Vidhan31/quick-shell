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

signals:
    void checkStarted();
    void checkProgress(const QString &status, int percent);
    void checkFinished(const QList<qs::updatemanager::UpdateItem> &items, bool success, const QString &errorMsg);
    void changelogFetched(const QString &packageName, const QVariantList &entries);
    void downloadProgress(quint64 downloadedBytes, quint64 totalBytes, double fraction);
    void inPlaceProgress(const QString &nevra, int action, quint64 processed, quint64 total);
    void operationFinished(bool success, const QString &message);
    void offlineStagedReady(bool ready);
    void statusMessageChanged(const QString &status);

private slots:
    void onDownloadAddNew(const QDBusObjectPath &session, const QString &downloadId,
                          const QString &description, qint64 totalToDownload);
    void onDownloadProgress(const QDBusObjectPath &session, const QString &downloadId,
                            qint64 totalToDownload, qint64 downloaded);
    void onDownloadEnd(const QDBusObjectPath &session, const QString &downloadId,
                       uint transferStatus, const QString &message);
    void onTransactionElemProgress(const QDBusObjectPath &session, const QString &nevra,
                                   qulonglong processed, qulonglong total);
    void onTransactionActionProgress(const QDBusObjectPath &session, const QString &nevra,
                                     qulonglong processed, qulonglong total);
    void onTransactionAfterComplete(const QDBusObjectPath &session, bool success);

private:
    bool openSession(bool loadSystemRepo = true, bool loadAvailableRepos = true);
    void closeSession();

    QString m_sessionPath;
    bool m_cancelled{false};
    quint64 m_totalBytesToDownload{0};
    QMap<QString, qint64> m_downloadedPerId;
    QMap<QString, qint64> m_totalPerId;
};

} // namespace qs::updatemanager
