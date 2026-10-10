#include "UpdateWorker.hpp"

#include <QDBusArgument>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QThread>
#include <QTimer>
#include <limits>

namespace qs::updatemanager {

UpdateWorker::UpdateWorker(QObject *parent)
    : QObject(parent) {
    registerDbusTypes();
}

UpdateWorker::~UpdateWorker() {
    closeSession();
}

bool UpdateWorker::ensureDaemonActive(int timeoutMs) {
    QDBusConnectionInterface *busIface = QDBusConnection::systemBus().interface();
    if (!busIface) {
        return false;
    }
    if (busIface->isServiceRegistered(QStringLiteral("org.rpm.dnf.v0"))) {
        return true;
    }

    // Trigger D-Bus activation (daemon runs as root via systemd; this needs no extra auth).
    {
        QDBusInterface dbusCtl(QStringLiteral("org.freedesktop.DBus"),
                               QStringLiteral("/org/freedesktop/DBus"),
                               QStringLiteral("org.freedesktop.DBus"),
                               QDBusConnection::systemBus());
        dbusCtl.setTimeout(30000);
        // Best-effort: ignore result, poll below for actual registration.
        dbusCtl.call(QStringLiteral("StartServiceByName"), QStringLiteral("org.rpm.dnf.v0"),
                     static_cast<uint>(0));
    }

    const int stepMs = 500;
    int waited = 0;
    while (waited < timeoutMs) {
        QThread::msleep(static_cast<unsigned long>(stepMs));
        waited += stepMs;
        if (busIface->isServiceRegistered(QStringLiteral("org.rpm.dnf.v0"))) {
            return true;
        }
    }
    return busIface->isServiceRegistered(QStringLiteral("org.rpm.dnf.v0"));
}

bool UpdateWorker::openSession(bool loadSystemRepo, bool loadAvailableRepos, QString *errOut) {
    closeSession();
    m_cancelled = false;

    // dnf5daemon-server is D-Bus activated with a runtime limit, so it is
    // routinely stopped when idle. The first call after that needs a cold
    // start (hundreds of MB of repo cache), so retry instead of failing fast.
    QString lastErr;
    for (int attempt = 0; attempt < 3; ++attempt) {
        ensureDaemonActive(30000);

        QDBusInterface sm(QStringLiteral("org.rpm.dnf.v0"),
                          QStringLiteral("/org/rpm/dnf/v0"),
                          QStringLiteral("org.rpm.dnf.v0.SessionManager"),
                          QDBusConnection::systemBus());
        // Cold start after idle timeout is slow; allow ample time.
        sm.setTimeout(120000);

        if (!sm.isValid()) {
            lastErr = sm.lastError().message();
            qWarning() << "UpdateWorker: SessionManager interface invalid (attempt"
                       << (attempt + 1) << "):" << lastErr;
        } else {
            QVariantMap options;
            options[QStringLiteral("load_system_repo")] = loadSystemRepo;
            options[QStringLiteral("load_available_repos")] = loadAvailableRepos;

            QDBusReply<QDBusObjectPath> reply = sm.call(QStringLiteral("open_session"), options);
            if (reply.isValid()) {
                m_sessionPath = reply.value().path();
                return true;
            }
            lastErr = reply.error().message();
            qWarning() << "UpdateWorker: Failed to open session (attempt" << (attempt + 1)
                       << "):" << lastErr;
        }

        if (attempt < 2) {
            QThread::msleep(2000);
        }
    }

    if (errOut) {
        *errOut = lastErr;
    }
    return false;
}

void UpdateWorker::connectTransactionSignals() {
    if (m_sessionPath.isEmpty() || m_transactionSignalsConnected) {
        return;
    }

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_add_new"), this,
        SLOT(onDownloadAddNew(QDBusObjectPath,QString,QString,qint64)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_progress"), this,
        SLOT(onDownloadProgress(QDBusObjectPath,QString,qint64,qint64)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_end"), this,
        SLOT(onDownloadEnd(QDBusObjectPath,QString,uint,QString)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_mirror_failure"), this,
        SLOT(onDownloadMirrorFailure(QDBusObjectPath,QString,QString,QString,QString)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("repo_key_import_request"), this,
        SLOT(onRepoKeyImportRequest(QDBusObjectPath,QString,QStringList,QString,QString,qint64)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_before_begin"), this,
        SLOT(onTransactionBeforeBegin(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_transaction_start"), this,
        SLOT(onTransactionTransactionStart(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_transaction_progress"), this,
        SLOT(onTransactionTransactionProgress(QDBusObjectPath,qulonglong,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_transaction_stop"), this,
        SLOT(onTransactionTransactionStop(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_verify_start"), this,
        SLOT(onTransactionVerifyStart(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_verify_progress"), this,
        SLOT(onTransactionVerifyProgress(QDBusObjectPath,qulonglong,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_verify_stop"), this,
        SLOT(onTransactionVerifyStop(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_elem_progress"), this,
        SLOT(onTransactionElemProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_start"), this,
        SLOT(onTransactionActionStart(QDBusObjectPath,QString,uint,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_progress"), this,
        SLOT(onTransactionActionProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_stop"), this,
        SLOT(onTransactionActionStop(QDBusObjectPath,QString,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_script_start"), this,
        SLOT(onTransactionScriptStart(QDBusObjectPath,QString,uint)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_script_stop"), this,
        SLOT(onTransactionScriptStop(QDBusObjectPath,QString,uint,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_script_error"), this,
        SLOT(onTransactionScriptError(QDBusObjectPath,QString,uint,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_unpack_error"), this,
        SLOT(onTransactionUnpackError(QDBusObjectPath,QString)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_after_complete"), this,
        SLOT(onTransactionAfterComplete(QDBusObjectPath,bool)));

    m_transactionSignalsConnected = true;
}

void UpdateWorker::disconnectTransactionSignals() {
    if (m_sessionPath.isEmpty() || !m_transactionSignalsConnected) {
        return;
    }

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_add_new"), this,
        SLOT(onDownloadAddNew(QDBusObjectPath,QString,QString,qint64)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_progress"), this,
        SLOT(onDownloadProgress(QDBusObjectPath,QString,qint64,qint64)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_end"), this,
        SLOT(onDownloadEnd(QDBusObjectPath,QString,uint,QString)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("download_mirror_failure"), this,
        SLOT(onDownloadMirrorFailure(QDBusObjectPath,QString,QString,QString,QString)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.Base"),
        QStringLiteral("repo_key_import_request"), this,
        SLOT(onRepoKeyImportRequest(QDBusObjectPath,QString,QStringList,QString,QString,qint64)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_before_begin"), this,
        SLOT(onTransactionBeforeBegin(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_transaction_start"), this,
        SLOT(onTransactionTransactionStart(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_transaction_progress"), this,
        SLOT(onTransactionTransactionProgress(QDBusObjectPath,qulonglong,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_transaction_stop"), this,
        SLOT(onTransactionTransactionStop(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_verify_start"), this,
        SLOT(onTransactionVerifyStart(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_verify_progress"), this,
        SLOT(onTransactionVerifyProgress(QDBusObjectPath,qulonglong,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_verify_stop"), this,
        SLOT(onTransactionVerifyStop(QDBusObjectPath,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_elem_progress"), this,
        SLOT(onTransactionElemProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_start"), this,
        SLOT(onTransactionActionStart(QDBusObjectPath,QString,uint,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_progress"), this,
        SLOT(onTransactionActionProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_stop"), this,
        SLOT(onTransactionActionStop(QDBusObjectPath,QString,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_script_start"), this,
        SLOT(onTransactionScriptStart(QDBusObjectPath,QString,uint)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_script_stop"), this,
        SLOT(onTransactionScriptStop(QDBusObjectPath,QString,uint,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_script_error"), this,
        SLOT(onTransactionScriptError(QDBusObjectPath,QString,uint,qulonglong)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_unpack_error"), this,
        SLOT(onTransactionUnpackError(QDBusObjectPath,QString)));

    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_after_complete"), this,
        SLOT(onTransactionAfterComplete(QDBusObjectPath,bool)));

    m_transactionSignalsConnected = false;
}

void UpdateWorker::closeSession() {
    if (m_sessionPath.isEmpty()) {
        return;
    }

    disconnectTransactionSignals();

    QDBusInterface sm(QStringLiteral("org.rpm.dnf.v0"),
                      QStringLiteral("/org/rpm/dnf/v0"),
                      QStringLiteral("org.rpm.dnf.v0.SessionManager"),
                      QDBusConnection::systemBus());
    if (sm.isValid()) {
        sm.call(QStringLiteral("close_session"), QVariant::fromValue(QDBusObjectPath(m_sessionPath)));
    }
    m_sessionPath.clear();
}

void UpdateWorker::checkForUpdates(bool refresh) {
    emit checkStarted();
    emit statusMessageChanged(QStringLiteral("Initializing update check..."));
    emit checkProgress(QStringLiteral("Connecting to DNF5 daemon..."), 10);

    QString sessErr;
    if (!openSession(true, true, &sessErr)) {
        const QString detail = sessErr.isEmpty()
            ? QStringLiteral("Failed to connect to DNF5 daemon service.")
            : QStringLiteral("Failed to connect to DNF5 daemon service: %1").arg(sessErr);
        emit checkFinished({}, false, detail);
        return;
    }

    {
        QDBusInterface baseIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                 QStringLiteral("org.rpm.dnf.v0.Base"), QDBusConnection::systemBus());
        baseIface.setTimeout(600000); // 10 minutes max for metadata sync

        if (refresh) {
            emit statusMessageChanged(QStringLiteral("Expiring repository cache..."));
            emit checkProgress(QStringLiteral("Expiring metadata cache..."), 20);
            baseIface.call(QStringLiteral("clean"), QStringLiteral("expire-cache"));
            baseIface.call(QStringLiteral("reset"));
        }

        emit statusMessageChanged(QStringLiteral("Refreshing repository metadata..."));
        emit checkProgress(QStringLiteral("Synchronizing repositories..."), 35);
        QDBusReply<bool> repoReply = baseIface.call(QStringLiteral("read_all_repos"));
        if (!repoReply.isValid() || !repoReply.value()) {
            QString err = repoReply.isValid() ? QStringLiteral("Failed to load repositories.")
                                              : repoReply.error().message();
            closeSession();
            emit checkFinished({}, false, err);
            return;
        }
    }

    if (m_cancelled) {
        closeSession();
        emit checkFinished({}, false, QStringLiteral("Update check was cancelled."));
        return;
    }

    emit statusMessageChanged(QStringLiteral("Scanning for available updates..."));
    emit checkProgress(QStringLiteral("Querying package upgrades..."), 60);

    QList<QVariantMap> rawUpgrades;
    QMap<QString, QString> installedEvrMap;
    {
        QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
        rpmIface.setTimeout(300000);

        QVariantMap listOpts;
        listOpts[QStringLiteral("scope")] = QStringLiteral("upgrades");
        listOpts[QStringLiteral("package_attrs")] = QStringList{
            QStringLiteral("name"), QStringLiteral("evr"), QStringLiteral("arch"),
            QStringLiteral("summary"), QStringLiteral("repo_id"), QStringLiteral("download_size"),
            QStringLiteral("install_size"), QStringLiteral("vendor")
        };

        QDBusMessage upgradeMsg = rpmIface.call(QStringLiteral("list"), listOpts);
        if (upgradeMsg.type() == QDBusMessage::ErrorMessage) {
            QString err = upgradeMsg.errorMessage();
            closeSession();
            emit checkFinished({}, false, err);
            return;
        }

        const QDBusArgument arg = upgradeMsg.arguments().at(0).value<QDBusArgument>();
        arg >> rawUpgrades;

        if (rawUpgrades.isEmpty()) {
            closeSession();
            emit checkProgress(QStringLiteral("System is up to date"), 100);
            emit statusMessageChanged(QStringLiteral("Your system is completely up to date."));
            emit checkFinished({}, true, QString());
            return;
        }

        emit statusMessageChanged(QStringLiteral("Resolving installed package versions..."));
        emit checkProgress(QStringLiteral("Matching installed versions..."), 75);

        // Query installed versions for these packages to obtain oldEvr
        QStringList pkgNames;
        pkgNames.reserve(rawUpgrades.size());
        for (const auto &p : rawUpgrades) {
            pkgNames.append(p.value(QStringLiteral("name")).toString());
        }

        QVariantMap installedOpts;
        installedOpts[QStringLiteral("scope")] = QStringLiteral("installed");
        installedOpts[QStringLiteral("patterns")] = pkgNames;
        installedOpts[QStringLiteral("package_attrs")] = QStringList{
            QStringLiteral("name"), QStringLiteral("evr")
        };

        QDBusMessage instMsg = rpmIface.call(QStringLiteral("list"), installedOpts);
        if (instMsg.type() != QDBusMessage::ErrorMessage && !instMsg.arguments().isEmpty()) {
            const QDBusArgument instArg = instMsg.arguments().at(0).value<QDBusArgument>();
            QList<QVariantMap> rawInstalled;
            instArg >> rawInstalled;
            for (const auto &p : rawInstalled) {
                installedEvrMap[p.value(QStringLiteral("name")).toString()] =
                    p.value(QStringLiteral("evr")).toString();
            }
        }
    }

    emit statusMessageChanged(QStringLiteral("Checking security advisories..."));
    emit checkProgress(QStringLiteral("Fetching security errata..."), 85);

    struct AdvInfo {
        QString id;
        QString title;
        QString type;
        QString severity;
        QString description;
        QStringList cves;
    };
    QMap<QString, AdvInfo> pkgToAdvisory;

    {
        QDBusInterface advIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                QStringLiteral("org.rpm.dnf.v0.Advisory"), QDBusConnection::systemBus());
        advIface.setTimeout(300000);

        QVariantMap advOpts;
        advOpts[QStringLiteral("availability")] = QStringLiteral("updates");
        advOpts[QStringLiteral("advisory_attrs")] = QStringList{
            QStringLiteral("advisoryid"), QStringLiteral("title"), QStringLiteral("type"),
            QStringLiteral("severity"), QStringLiteral("description"), QStringLiteral("references"),
            QStringLiteral("collections")
        };

        QDBusMessage advMsg = advIface.call(QStringLiteral("list"), advOpts);
        if (advMsg.type() != QDBusMessage::ErrorMessage && !advMsg.arguments().isEmpty()) {
            const QDBusArgument advArg = advMsg.arguments().at(0).value<QDBusArgument>();
            QList<QVariantMap> rawAdvisories;
            advArg >> rawAdvisories;

            for (const auto &adv : rawAdvisories) {
                AdvInfo info;
                info.id = adv.value(QStringLiteral("advisoryid")).toString();
                info.title = adv.value(QStringLiteral("title")).toString();
                info.type = adv.value(QStringLiteral("type")).toString();
                info.severity = adv.value(QStringLiteral("severity")).toString();
                info.description = adv.value(QStringLiteral("description")).toString();

                if (adv.contains(QStringLiteral("references"))) {
                    const auto refsVar = adv.value(QStringLiteral("references"));
                    if (refsVar.canConvert<QDBusArgument>()) {
                        const auto refArg = refsVar.value<QDBusArgument>();
                        refArg.beginArray();
                        while (!refArg.atEnd()) {
                            refArg.beginStructure();
                            QString refId, refType, refTitle, refUrl;
                            refArg >> refId >> refType >> refTitle >> refUrl;
                            refArg.endStructure();
                            if (refType.toLower() == QStringLiteral("cve")) {
                                info.cves.append(refId);
                            }
                        }
                        refArg.endArray();
                    }
                }

                if (adv.contains(QStringLiteral("collections"))) {
                    const auto colVar = adv.value(QStringLiteral("collections"));
                    auto addPkg = [&](const QString &pName) {
                        if (!pName.isEmpty()) {
                            pkgToAdvisory[pName] = info;
                        }
                    };

                    auto processPackagesArg = [&](const QDBusArgument &pkgArg) {
                        pkgArg.beginArray();
                        while (!pkgArg.atEnd()) {
                            pkgArg.beginMap();
                            while (!pkgArg.atEnd()) {
                                pkgArg.beginMapEntry();
                                QString pKey;
                                QVariant pVal;
                                pkgArg >> pKey >> pVal;
                                pkgArg.endMapEntry();
                                if (pKey == QStringLiteral("name") || pKey == QStringLiteral("n")) {
                                    addPkg(pVal.toString());
                                }
                            }
                            pkgArg.endMap();
                        }
                        pkgArg.endArray();
                    };

                    if (colVar.canConvert<QDBusArgument>()) {
                        const auto colArg = colVar.value<QDBusArgument>();
                        colArg.beginArray();
                        while (!colArg.atEnd()) {
                            colArg.beginMap();
                            while (!colArg.atEnd()) {
                                colArg.beginMapEntry();
                                QString key;
                                QVariant val;
                                colArg >> key >> val;
                                colArg.endMapEntry();
                                if (key == QStringLiteral("name") || key == QStringLiteral("n")) {
                                    addPkg(val.toString());
                                } else if (key == QStringLiteral("packages")) {
                                    if (val.canConvert<QDBusArgument>()) {
                                        processPackagesArg(val.value<QDBusArgument>());
                                    } else if (val.canConvert<QVariantList>()) {
                                        for (const auto &pItem : val.toList()) {
                                            const auto pMap = pItem.toMap();
                                            QString n = pMap.value(QStringLiteral("n")).toString();
                                            if (n.isEmpty()) n = pMap.value(QStringLiteral("name")).toString();
                                            addPkg(n);
                                        }
                                    }
                                }
                            }
                            colArg.endMap();
                        }
                        colArg.endArray();
                    } else if (colVar.canConvert<QVariantList>()) {
                        for (const auto &colItem : colVar.toList()) {
                            const auto colMap = colItem.toMap();
                            const auto pkgsVar = colMap.value(QStringLiteral("packages"));
                            if (pkgsVar.canConvert<QDBusArgument>()) {
                                processPackagesArg(pkgsVar.value<QDBusArgument>());
                            } else if (pkgsVar.canConvert<QVariantList>()) {
                                for (const auto &pItem : pkgsVar.toList()) {
                                    const auto pMap = pItem.toMap();
                                    QString n = pMap.value(QStringLiteral("n")).toString();
                                    if (n.isEmpty()) n = pMap.value(QStringLiteral("name")).toString();
                                    addPkg(n);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    emit checkProgress(QStringLiteral("Processing update items..."), 95);

    QList<UpdateItem> items;
    items.reserve(rawUpgrades.size());

    for (const auto &p : rawUpgrades) {
        UpdateItem item;
        item.name = p.value(QStringLiteral("name")).toString();
        item.newEvr = p.value(QStringLiteral("evr")).toString();
        item.oldEvr = installedEvrMap.value(item.name, QStringLiteral("unknown"));
        item.arch = p.value(QStringLiteral("arch")).toString();
        item.summary = p.value(QStringLiteral("summary")).toString();
        item.repoId = p.value(QStringLiteral("repo_id")).toString();
        item.downloadSize = p.value(QStringLiteral("download_size")).toULongLong();
        item.installSize = p.value(QStringLiteral("install_size")).toULongLong();
        item.vendor = p.value(QStringLiteral("vendor")).toString();

        item.categoryKey = UpdateItem::classifyCategoryKey(item.name, item.summary);
        item.category = UpdateItem::categoryKeyToLabel(item.categoryKey);

        if (pkgToAdvisory.contains(item.name)) {
            const auto &adv = pkgToAdvisory.value(item.name);
            item.advisoryId = adv.id;
            item.advisoryType = adv.type.isEmpty() ? QStringLiteral("general") : adv.type;
            item.severity = adv.severity.isEmpty() ? QStringLiteral("none") : adv.severity;
            item.advisoryTitle = adv.title;
            item.advisoryDescription = adv.description;
            item.cveList = adv.cves;
        }

        item.requiresReboot = UpdateItem::evaluateRebootRequired(item.name, item.categoryKey);
        item.requiresSessionRestart = UpdateItem::evaluateSessionRestartRequired(item.name, item.categoryKey);

        items.append(item);
    }

    {
        QDBusInterface offIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                QStringLiteral("org.rpm.dnf.v0.Offline"), QDBusConnection::systemBus());
        if (offIface.isValid()) {
            QDBusMessage statusReply = offIface.call(QStringLiteral("get_status"));
            if (statusReply.type() != QDBusMessage::ErrorMessage && !statusReply.arguments().isEmpty()) {
                bool pending = statusReply.arguments().at(0).toBool();
                if (!pending && statusReply.arguments().size() > 1) {
                    const auto stateArg = statusReply.arguments().at(1);
                    if (stateArg.canConvert<QDBusArgument>()) {
                        QVariantMap stateMap;
                        stateArg.value<QDBusArgument>() >> stateMap;
                        QString st = stateMap.value(QStringLiteral("status")).toString();
                        if (st == QLatin1String("download-complete") || st == QLatin1String("ready")) {
                            pending = true;
                        }
                    } else if (stateArg.canConvert<QVariantMap>()) {
                        QVariantMap stateMap = stateArg.toMap();
                        QString st = stateMap.value(QStringLiteral("status")).toString();
                        if (st == QLatin1String("download-complete") || st == QLatin1String("ready")) {
                            pending = true;
                        }
                    }
                }
                emit offlineStagedReady(pending);
            }
        }
    }

    closeSession();

    emit checkProgress(QStringLiteral("Done"), 100);
    emit statusMessageChanged(QStringLiteral("%1 updates available.").arg(items.size()));
    emit checkFinished(items, true, QString());
}

void UpdateWorker::fetchChangelog(const QString &packageName) {
    if (packageName.isEmpty()) {
        return;
    }

    if (!openSession(true, true)) {
        emit changelogFetched(packageName, {});
        return;
    }

    QVariantList entries;
    {
        QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
        rpmIface.setTimeout(60000);

        auto queryChangelogForScope = [&](const QString &scope) -> QVariantList {
            QVariantMap listOpts;
            listOpts[QStringLiteral("scope")] = scope;
            listOpts[QStringLiteral("patterns")] = QStringList{packageName};
            listOpts[QStringLiteral("package_attrs")] = QStringList{
                QStringLiteral("name"), QStringLiteral("changelogs"), QStringLiteral("description")
            };

            QVariantList resultEntries;
            QDBusMessage msg = rpmIface.call(QStringLiteral("list"), listOpts);
            if (msg.type() != QDBusMessage::ErrorMessage && !msg.arguments().isEmpty()) {
                const QDBusArgument arg = msg.arguments().at(0).value<QDBusArgument>();
                QList<QVariantMap> pkgs;
                arg >> pkgs;
                if (!pkgs.isEmpty()) {
                    const auto &p = pkgs.first();
                    if (p.contains(QStringLiteral("changelogs"))) {
                        const auto clVar = p.value(QStringLiteral("changelogs"));
                        if (clVar.canConvert<QDBusArgument>()) {
                            const auto clArg = clVar.value<QDBusArgument>();
                            clArg.beginArray();
                            while (!clArg.atEnd()) {
                                clArg.beginStructure();
                                qint64 ts{0};
                                QString author, text;
                                clArg >> ts >> author >> text;
                                clArg.endStructure();

                                QVariantMap entry;
                                entry[QStringLiteral("timestamp")] = ts;
                                entry[QStringLiteral("date")] = QDateTime::fromSecsSinceEpoch(ts).toString(QStringLiteral("yyyy-MM-dd"));
                                entry[QStringLiteral("author")] = author;
                                entry[QStringLiteral("text")] = text;
                                resultEntries.append(entry);
                            }
                            clArg.endArray();
                        }
                    }
                }
            }
            return resultEntries;
        };

        entries = queryChangelogForScope(QStringLiteral("upgrades"));
        // If upgrades has no changelogs (common in Fedora when other.xml is not cached), fallback to installed rpmdb
        if (entries.isEmpty()) {
            entries = queryChangelogForScope(QStringLiteral("installed"));
        }
    }

    closeSession();
    emit changelogFetched(packageName, entries);
}

void UpdateWorker::stageOfflineUpgrade() {
    emit statusMessageChanged(QStringLiteral("Preparing offline upgrade staging..."));
    m_downloadedPerId.clear();
    m_totalPerId.clear();
    m_totalBytesToDownload = 0;

    emit statusMessageChanged(QStringLiteral("Starting update service if needed..."));
    QString sessErr;
    if (!openSession(true, true, &sessErr)) {
        const QString detail = sessErr.isEmpty()
            ? QStringLiteral("Failed to open DNF5 session for offline staging.")
            : QStringLiteral("Failed to open DNF5 session for offline staging: %1").arg(sessErr);
        emit operationFinished(false, detail);
        return;
    }

    connectTransactionSignals();

    QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
    rpmIface.setTimeout(120000);
    rpmIface.call(QStringLiteral("upgrade"), QStringList(), QVariantMap());

    QDBusInterface goalIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                             QStringLiteral("org.rpm.dnf.v0.Goal"), QDBusConnection::systemBus());
    goalIface.setTimeout(300000);

    emit statusMessageChanged(QStringLiteral("Resolving dependencies..."));
    emit progressStageUpdated(QStringLiteral("resolving"), QStringLiteral("Resolving"), QString(), 0, 0, 0.0);
    QVariantMap resOpts;
    resOpts[QStringLiteral("allow_erasing")] = false;
    resOpts[QStringLiteral("interactive")] = false;
    QDBusMessage resReply = goalIface.call(QStringLiteral("resolve"), resOpts);
    if (resReply.type() == QDBusMessage::ErrorMessage) {
        QString errMsg = QStringLiteral("Resolution error: ") + resReply.errorMessage();
        closeSession();
        emit operationFinished(false, errMsg);
        return;
    }
    if (resReply.arguments().size() >= 2) {
        uint resCode = resReply.arguments().at(1).toUInt();
        if (resCode == 2) {
            QDBusMessage probMsg = goalIface.call(QStringLiteral("get_transaction_problems_string"));
            QString errMsg;
            if (probMsg.type() != QDBusMessage::ErrorMessage && !probMsg.arguments().isEmpty()) {
                QStringList problems = probMsg.arguments().at(0).toStringList();
                if (!problems.isEmpty()) {
                    errMsg = QStringLiteral("Dependency resolution failed:\n") + problems.join(QLatin1Char('\n'));
                }
            }
            if (errMsg.isEmpty()) {
                errMsg = QStringLiteral("Dependency resolution failed (broken dependencies or conflicts).");
            }
            closeSession();
            emit operationFinished(false, errMsg);
            return;
        }
    }

    m_downloadedPerId.clear();
    m_totalPerId.clear();
    m_totalBytesToDownload = 0;
    emit downloadProgress(0, 0, 0.0);
    emit progressStageUpdated(QStringLiteral("downloading"), QStringLiteral("Downloading"), QString(), 0, 0, 0.0);
    emit statusMessageChanged(QStringLiteral("Downloading packages and verifying transaction..."));
    QVariantMap transOpts;
    transOpts[QStringLiteral("offline")] = true;
    transOpts[QStringLiteral("downloadonly")] = true;
    transOpts[QStringLiteral("interactive")] = false;

    goalIface.setTimeout(7200000);
    QDBusPendingCall pcall = goalIface.asyncCall(QStringLiteral("do_transaction"), transOpts);
    auto *watcher = new QDBusPendingCallWatcher(pcall, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        bool success = !w->isError();
        QString errMsg;
        if (!success) {
            errMsg = QStringLiteral("Download failed: ") + w->error().message();
        }
        closeSession();
        if (!success) {
            emit operationFinished(false, errMsg);
        } else {
            emit offlineStagedReady(true);
            emit statusMessageChanged(QStringLiteral("Updates downloaded. Ready to restart."));
            emit operationFinished(true, QStringLiteral("Updates successfully staged for next boot."));
        }
    });
}

void UpdateWorker::startInPlaceUpgrade() {
    emit statusMessageChanged(QStringLiteral("Preparing in-place upgrade..."));
    m_downloadedPerId.clear();
    m_totalPerId.clear();
    m_totalBytesToDownload = 0;
    m_pkgTotalCount = 0;
    m_currentPkgIndex = 0;
    m_pkgItemProcessed = 0;
    m_pkgItemTotal = 0;
    m_currentNevra.clear();

    emit downloadProgress(0, 0, 0.0);
    emit progressStageUpdated(QStringLiteral("preparing"), QStringLiteral("Preparing"), QString(), 0, 0, 0.0);

    QString sessErr;
    if (!openSession(true, true, &sessErr)) {
        const QString detail = sessErr.isEmpty()
            ? QStringLiteral("Failed to open DNF5 session.")
            : QStringLiteral("Failed to open DNF5 session: %1").arg(sessErr);
        emit operationFinished(false, detail);
        return;
    }

    connectTransactionSignals();

    QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
    rpmIface.setTimeout(120000);
    rpmIface.call(QStringLiteral("upgrade"), QStringList(), QVariantMap());

    QDBusInterface goalIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                             QStringLiteral("org.rpm.dnf.v0.Goal"), QDBusConnection::systemBus());
    goalIface.setTimeout(300000);

    emit statusMessageChanged(QStringLiteral("Resolving dependencies..."));
    emit progressStageUpdated(QStringLiteral("resolving"), QStringLiteral("Resolving"), QString(), 0, 0, 0.0);
    QVariantMap resOpts;
    resOpts[QStringLiteral("allow_erasing")] = false;
    resOpts[QStringLiteral("interactive")] = true;
    QDBusMessage resReply = goalIface.call(QStringLiteral("resolve"), resOpts);
    if (resReply.type() == QDBusMessage::ErrorMessage) {
        QString errMsg = QStringLiteral("Resolution error: ") + resReply.errorMessage();
        closeSession();
        emit operationFinished(false, errMsg);
        return;
    }
    if (resReply.arguments().size() >= 2) {
        uint resCode = resReply.arguments().at(1).toUInt();
        if (resCode == 2) {
            QDBusMessage probMsg = goalIface.call(QStringLiteral("get_transaction_problems_string"));
            QString errMsg;
            if (probMsg.type() != QDBusMessage::ErrorMessage && !probMsg.arguments().isEmpty()) {
                QStringList problems = probMsg.arguments().at(0).toStringList();
                if (!problems.isEmpty()) {
                    errMsg = QStringLiteral("Dependency resolution failed:\n") + problems.join(QLatin1Char('\n'));
                }
            }
            if (errMsg.isEmpty()) {
                errMsg = QStringLiteral("Dependency resolution failed (broken dependencies or conflicts).");
            }
            closeSession();
            emit operationFinished(false, errMsg);
            return;
        }
    }

    m_downloadedPerId.clear();
    m_totalPerId.clear();
    m_totalBytesToDownload = 0;
    emit downloadProgress(0, 0, 0.0);
    emit progressStageUpdated(QStringLiteral("authenticating"), QStringLiteral("Authenticating"), QString(), 0, 0, 0.0);
    emit statusMessageChanged(QStringLiteral("Waiting for authentication (Polkit prompt)..."));
    QVariantMap transOpts;
    transOpts[QStringLiteral("offline")] = false;
    transOpts[QStringLiteral("interactive")] = true;

    goalIface.setTimeout(7200000);
    QDBusPendingCall pcall = goalIface.asyncCall(QStringLiteral("do_transaction"), transOpts);
    auto *watcher = new QDBusPendingCallWatcher(pcall, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        bool success = !w->isError();
        QString errMsg;
        QString errStr;
        if (!success) {
            errStr = w->error().message();
            if (errStr.contains(QStringLiteral("Not authorized"), Qt::CaseInsensitive) ||
                w->error().name().contains(QStringLiteral("PolicyKit"), Qt::CaseInsensitive)) {
                errMsg = QStringLiteral("Authentication cancelled.");
            } else {
                errMsg = QStringLiteral("Transaction failed: ") + errStr;
            }
        }
        closeSession();
        if (!success) {
            if (errMsg == QStringLiteral("Authentication cancelled.")) {
                emit statusMessageChanged(errMsg);
                emit operationFinished(false, errMsg);
                return;
            }

            // In-place upgrade error (e.g. code 5 from dnf5daemon-server restarting itself, or transient D-Bus disconnect).
            // Verify actual package status before concluding failure.
            emit statusMessageChanged(QStringLiteral("Verifying update status..."));
            QTimer::singleShot(1500, this, [this, errMsg, errStr]() {
                verifyTransactionResult(errMsg, errStr);
            });
        } else {
            emit inPlaceProgress(QString(), 0, 1, 1, 1.0);
            emit statusMessageChanged(QStringLiteral("Updates installed successfully."));
            emit operationFinished(true, QStringLiteral("In-place update finished successfully."));
            // Refreshes the model and clears installed items.
            QMetaObject::invokeMethod(this, &UpdateWorker::checkForUpdates, Qt::QueuedConnection, false);
        }
    });
}

void UpdateWorker::rebootAndApply() {
    emit statusMessageChanged(QStringLiteral("Scheduling reboot..."));

    QString sessErr;
    if (!openSession(true, false, &sessErr)) {
        const QString detail = sessErr.isEmpty()
            ? QStringLiteral("Failed to open session to schedule reboot.")
            : QStringLiteral("Failed to open session to schedule reboot: %1").arg(sessErr);
        emit operationFinished(false, detail);
        return;
    }

    bool schedOk = false;
    QString err;
    {
        QDBusInterface offIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                QStringLiteral("org.rpm.dnf.v0.Offline"), QDBusConnection::systemBus());
        offIface.setTimeout(120000);

        QVariantMap schedOpts;
        schedOpts[QStringLiteral("interactive")] = true;
        QDBusMessage schedReply = offIface.call(QStringLiteral("schedule_for_next_boot"), schedOpts);
        if (schedReply.type() == QDBusMessage::ErrorMessage) {
            err = schedReply.errorMessage();
        } else if (!schedReply.arguments().isEmpty()) {
            bool success = schedReply.arguments().at(0).toBool();
            if (!success) {
                if (schedReply.arguments().size() > 1) {
                    err = schedReply.arguments().at(1).toString();
                }
                if (err.isEmpty()) {
                    err = QStringLiteral("Failed to schedule offline update.");
                }
            } else {
                offIface.call(QStringLiteral("set_finish_action"), QStringLiteral("reboot"));
                schedOk = true;
            }
        }
    }
    closeSession();

    if (!schedOk) {
        emit operationFinished(false, err);
        return;
    }

    QDBusInterface logind(QStringLiteral("org.freedesktop.login1"),
                          QStringLiteral("/org/freedesktop/login1"),
                          QStringLiteral("org.freedesktop.login1.Manager"),
                          QDBusConnection::systemBus());
    if (logind.isValid()) {
        logind.call(QStringLiteral("Reboot"), true);
    }
}

void UpdateWorker::cancelOperation() {
    m_cancelled = true;
    if (!m_sessionPath.isEmpty()) {
        QDBusInterface goalIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                 QStringLiteral("org.rpm.dnf.v0.Goal"), QDBusConnection::systemBus());
        if (goalIface.isValid()) {
            QDBusMessage rep = goalIface.call(QStringLiteral("cancel"));
            if (rep.type() == QDBusMessage::ReplyMessage && !rep.arguments().isEmpty()) {
                bool ok = rep.arguments().at(0).toBool();
                if (!ok && rep.arguments().size() > 1) {
                    qWarning() << "UpdateWorker: Cancel rejected:" << rep.arguments().at(1).toString();
                }
            }
        }
    }
}

void UpdateWorker::cleanOffline() {
    if (!openSession(true, false)) {
        return;
    }
    {
        QDBusInterface offIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                QStringLiteral("org.rpm.dnf.v0.Offline"), QDBusConnection::systemBus());
        if (offIface.isValid()) {
            QVariantMap cleanOpts;
            cleanOpts[QStringLiteral("interactive")] = true;
            offIface.call(QStringLiteral("clean_with_options"), cleanOpts);
        }
    }
    closeSession();
    emit offlineStagedReady(false);
}

void UpdateWorker::cleanAll() {
    cleanCache(QStringLiteral("all"));
}

void UpdateWorker::cleanCache(const QString &cacheType) {
    const QString type = cacheType.trimmed().toLower();
    static const QStringList validTypes = {
        QStringLiteral("all"),
        QStringLiteral("packages"),
        QStringLiteral("metadata"),
        QStringLiteral("dbcache"),
        QStringLiteral("expire-cache")
    };

    if (!validTypes.contains(type)) {
        const QString err = QStringLiteral("Unsupported cache type: %1").arg(cacheType);
        emit statusMessageChanged(err);
        emit cleanFinished(false, err);
        emit operationFinished(false, err);
        return;
    }

    emit statusMessageChanged(QStringLiteral("Cleaning cache (%1)...").arg(type));

    QString sessErr;
    if (!openSession(false, false, &sessErr)) {
        const QString detail = sessErr.isEmpty()
            ? QStringLiteral("Failed to connect to DNF5 daemon service.")
            : QStringLiteral("Failed to connect to DNF5 daemon service: %1").arg(sessErr);
        emit statusMessageChanged(detail);
        emit cleanFinished(false, detail);
        emit operationFinished(false, detail);
        return;
    }

    QDBusInterface baseIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                             QStringLiteral("org.rpm.dnf.v0.Base"), QDBusConnection::systemBus());
    baseIface.setTimeout(60000);

    QVariantMap cleanOpts;
    cleanOpts[QStringLiteral("interactive")] = true;

    QDBusMessage reply = baseIface.call(QStringLiteral("clean_with_options"), type, cleanOpts);
    if (reply.type() == QDBusMessage::ErrorMessage &&
        reply.errorName() == QStringLiteral("org.freedesktop.DBus.Error.UnknownMethod")) {
        reply = baseIface.call(QStringLiteral("clean"), type);
    }

    closeSession();

    if (reply.type() == QDBusMessage::ErrorMessage) {
        const QString errStr = reply.errorMessage();
        QString errMsg;
        if (errStr.contains(QStringLiteral("Not authorized"), Qt::CaseInsensitive) ||
            reply.errorName().contains(QStringLiteral("PolicyKit"), Qt::CaseInsensitive)) {
            errMsg = QStringLiteral("Authentication cancelled.");
        } else {
            errMsg = QStringLiteral("Failed to clean cache: ") + errStr;
        }
        emit statusMessageChanged(errMsg);
        emit cleanFinished(false, errMsg);
        emit operationFinished(false, errMsg);
        return;
    }

    bool success = false;
    QString errorMsg;
    if (!reply.arguments().isEmpty()) {
        success = reply.arguments().at(0).toBool();
        if (reply.arguments().size() > 1) {
            errorMsg = reply.arguments().at(1).toString();
        }
    }

    // dnf5daemon reports missing cache directory as failure; for clean operation a nonexistent directory is already clean.
    if (!success && errorMsg.contains(QStringLiteral("Cannot iterate the cache directory"), Qt::CaseInsensitive)) {
        success = true;
        errorMsg.clear();
    }

    if (!success) {
        if (errorMsg.isEmpty()) {
            errorMsg = QStringLiteral("Failed to clean cache.");
        }
        emit statusMessageChanged(errorMsg);
        emit cleanFinished(false, errorMsg);
        emit operationFinished(false, errorMsg);
        return;
    }

    // Best-effort cleanup of unprivileged user cache (~/.cache/libdnf5)
    QProcess proc;
    proc.start(QStringLiteral("dnf5"), {QStringLiteral("clean"), type});
    proc.waitForFinished(5000);

    emit statusMessageChanged(QStringLiteral("Cache cleaned."));
    emit cleanFinished(true, QStringLiteral("Cache successfully cleaned."));
    emit operationFinished(true, QStringLiteral("Cache successfully cleaned."));

    checkForUpdates(true);
}

void UpdateWorker::autoremove() {
    emit statusMessageChanged(QStringLiteral("Checking for unused packages..."));

    // Fast, locale-independent query using libdnf5's filter_unneeded via JSON output
    QProcess checkProc;
    checkProc.start(QStringLiteral("dnf5"), {QStringLiteral("list"), QStringLiteral("--autoremove"), QStringLiteral("--json")});
    if (!checkProc.waitForFinished(10000)) {
        checkProc.kill();
        const QString err = QStringLiteral("Failed to query unused packages (timeout).");
        emit statusMessageChanged(err);
        emit autoremoveFinished(false, err);
        emit operationFinished(false, err);
        return;
    }

    if (checkProc.exitStatus() != QProcess::NormalExit || checkProc.exitCode() != 0) {
        const QString err = QStringLiteral("Failed to query unused packages (dnf5 exit code %1).").arg(checkProc.exitCode());
        emit statusMessageChanged(err);
        emit autoremoveFinished(false, err);
        emit operationFinished(false, err);
        return;
    }

    const QByteArray jsonOut = checkProc.readAllStandardOutput();
    QJsonParseError parseErr;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonOut, &parseErr);
    QStringList specs;
    if (doc.isObject()) {
        const QJsonObject rootObj = doc.object();
        const QJsonArray pkgs = rootObj.value(QStringLiteral("autoremove_packages")).toArray();
        specs.reserve(pkgs.size());
        for (const auto &val : pkgs) {
            const QJsonObject pObj = val.toObject();
            const QString name = pObj.value(QStringLiteral("name")).toString();
            const QString evr = pObj.value(QStringLiteral("evr")).toString();
            const QString arch = pObj.value(QStringLiteral("arch")).toString();
            if (!name.isEmpty()) {
                if (!evr.isEmpty() && !arch.isEmpty()) {
                    specs.append(QStringLiteral("%1-%2.%3").arg(name, evr, arch));
                } else {
                    specs.append(name);
                }
            }
        }
    }

    if (specs.isEmpty()) {
        emit statusMessageChanged(QStringLiteral("No unused packages found."));
        emit autoremoveFinished(true, QStringLiteral("No unused packages found."));
        emit operationFinished(true, QStringLiteral("No unused packages found."));
        return;
    }

    emit statusMessageChanged(QStringLiteral("Preparing removal of %1 unused package(s)...").arg(specs.size()));
    m_downloadedPerId.clear();
    m_totalPerId.clear();
    m_totalBytesToDownload = 0;
    m_pkgTotalCount = specs.size();
    m_currentPkgIndex = 0;
    m_pkgItemProcessed = 0;
    m_pkgItemTotal = 0;
    m_currentNevra.clear();

    emit inPlaceProgress(QString(), 0, 0, specs.size(), 0.0);
    emit progressStageUpdated(QStringLiteral("preparing"), QStringLiteral("Preparing"), QString(), 0, specs.size(), 0.0);

    QString sessErr;
    if (!openSession(true, false, &sessErr)) {
        const QString detail = sessErr.isEmpty()
            ? QStringLiteral("Failed to open DNF5 session for autoremove.")
            : QStringLiteral("Failed to open DNF5 session for autoremove: %1").arg(sessErr);
        emit statusMessageChanged(detail);
        emit autoremoveFinished(false, detail);
        emit operationFinished(false, detail);
        return;
    }

    connectTransactionSignals();

    QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
    rpmIface.setTimeout(120000);
    QDBusMessage removeReply = rpmIface.call(QStringLiteral("remove"), specs, QVariantMap());
    if (removeReply.type() == QDBusMessage::ErrorMessage) {
        QString errMsg = QStringLiteral("Failed to stage package removal: ") + removeReply.errorMessage();
        closeSession();
        emit statusMessageChanged(errMsg);
        emit autoremoveFinished(false, errMsg);
        emit operationFinished(false, errMsg);
        return;
    }

    QDBusInterface goalIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                             QStringLiteral("org.rpm.dnf.v0.Goal"), QDBusConnection::systemBus());
    goalIface.setTimeout(300000);

    emit statusMessageChanged(QStringLiteral("Resolving dependencies..."));
    emit progressStageUpdated(QStringLiteral("resolving"), QStringLiteral("Resolving"), QString(), 0, specs.size(), 0.0);
    QVariantMap resOpts;
    resOpts[QStringLiteral("allow_erasing")] = false;
    resOpts[QStringLiteral("interactive")] = true;
    QDBusMessage resReply = goalIface.call(QStringLiteral("resolve"), resOpts);
    if (resReply.type() == QDBusMessage::ErrorMessage) {
        QString errMsg = QStringLiteral("Resolution error: ") + resReply.errorMessage();
        closeSession();
        emit statusMessageChanged(errMsg);
        emit autoremoveFinished(false, errMsg);
        emit operationFinished(false, errMsg);
        return;
    }
    if (resReply.arguments().size() >= 2) {
        uint resCode = resReply.arguments().at(1).toUInt();
        if (resCode == 2) {
            QDBusMessage probMsg = goalIface.call(QStringLiteral("get_transaction_problems_string"));
            QString errMsg;
            if (probMsg.type() != QDBusMessage::ErrorMessage && !probMsg.arguments().isEmpty()) {
                QStringList problems = probMsg.arguments().at(0).toStringList();
                if (!problems.isEmpty()) {
                    errMsg = QStringLiteral("Dependency resolution failed:\n") + problems.join(QLatin1Char('\n'));
                }
            }
            if (errMsg.isEmpty()) {
                errMsg = QStringLiteral("Dependency resolution failed (broken dependencies or conflicts).");
            }
            closeSession();
            emit statusMessageChanged(errMsg);
            emit autoremoveFinished(false, errMsg);
            emit operationFinished(false, errMsg);
            return;
        }
    }

    emit progressStageUpdated(QStringLiteral("authenticating"), QStringLiteral("Authenticating"), QString(), 0, specs.size(), 0.0);
    emit statusMessageChanged(QStringLiteral("Waiting for authentication (Polkit prompt)..."));
    QVariantMap transOpts;
    transOpts[QStringLiteral("offline")] = false;
    transOpts[QStringLiteral("interactive")] = true;

    goalIface.setTimeout(7200000);
    QDBusPendingCall pcall = goalIface.asyncCall(QStringLiteral("do_transaction"), transOpts);
    auto *watcher = new QDBusPendingCallWatcher(pcall, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        bool success = !w->isError();
        QString errMsg;
        if (!success) {
            const QString errStr = w->error().message();
            if (errStr.contains(QStringLiteral("Not authorized"), Qt::CaseInsensitive) ||
                w->error().name().contains(QStringLiteral("PolicyKit"), Qt::CaseInsensitive)) {
                errMsg = QStringLiteral("Authentication cancelled.");
            } else {
                errMsg = QStringLiteral("Transaction failed: ") + errStr;
            }
        }
        closeSession();
        if (!success) {
            emit statusMessageChanged(errMsg);
            emit autoremoveFinished(false, errMsg);
            emit operationFinished(false, errMsg);
        } else {
            emit inPlaceProgress(QString(), 0, 1, 1, 1.0);
            emit statusMessageChanged(QStringLiteral("Unused packages removed."));
            emit autoremoveFinished(true, QStringLiteral("Unused packages removed."));
            emit operationFinished(true, QStringLiteral("Unused packages removed."));
            QMetaObject::invokeMethod(this, &UpdateWorker::checkForUpdates, Qt::QueuedConnection, false);
        }
    });
}

void UpdateWorker::onDownloadAddNew(const QDBusObjectPath &session, const QString &downloadId,
                                    const QString &description, qint64 totalToDownload) {
    Q_UNUSED(session);
    m_totalPerId[downloadId] = totalToDownload;
    m_downloadedPerId[downloadId] = 0;
    if (!description.isEmpty()) {
        emit statusMessageChanged(QStringLiteral("Downloading %1...").arg(description));
    }
}

static QString actionToStageName(uint action) {
    switch (action) {
        case 0: return QStringLiteral("installing");
        case 1: return QStringLiteral("removing");
        case 2: return QStringLiteral("upgrading");
        case 3: return QStringLiteral("downgrading");
        case 4: return QStringLiteral("reinstalling");
        case 5: return QStringLiteral("cleanup");
        default: return QStringLiteral("installing");
    }
}

static QString actionToDisplayName(uint action) {
    switch (action) {
        case 0: return QStringLiteral("Installing");
        case 1: return QStringLiteral("Removing");
        case 2: return QStringLiteral("Upgrading");
        case 3: return QStringLiteral("Downgrading");
        case 4: return QStringLiteral("Reinstalling");
        case 5: return QStringLiteral("Cleanup");
        default: return QStringLiteral("Processing");
    }
}

void UpdateWorker::onDownloadProgress(const QDBusObjectPath &session, const QString &downloadId,
                                      qint64 totalToDownload, qint64 downloaded) {
    Q_UNUSED(session);
    m_totalPerId[downloadId] = totalToDownload;
    m_downloadedPerId[downloadId] = downloaded;

    quint64 totalAll = 0;
    quint64 downloadedAll = 0;
    for (auto it = m_totalPerId.cbegin(); it != m_totalPerId.cend(); ++it) {
        totalAll += qMax(0LL, it.value());
    }
    for (auto it = m_downloadedPerId.cbegin(); it != m_downloadedPerId.cend(); ++it) {
        downloadedAll += qMax(0LL, it.value());
    }

    double frac = (totalAll > 0) ? (static_cast<double>(downloadedAll) / static_cast<double>(totalAll)) : 0.0;
    frac = qBound(0.0, frac, 1.0);
    emit downloadProgress(downloadedAll, totalAll, frac);
    emit progressStageUpdated(QStringLiteral("downloading"), QStringLiteral("Downloading"), QString(),
                              downloadedAll, totalAll, frac);
}

void UpdateWorker::onDownloadEnd(const QDBusObjectPath &session, const QString &downloadId,
                                 uint transferStatus, const QString &message) {
    Q_UNUSED(session);
    if (transferStatus == 2) { // 2 = ERROR
        qWarning() << "UpdateWorker: Download error for" << downloadId << ":" << message;
        if (!message.isEmpty()) {
            emit statusMessageChanged(QStringLiteral("Download failed for %1: %2").arg(downloadId, message));
        }
        return;
    }
    if (m_totalPerId.contains(downloadId)) {
        m_downloadedPerId[downloadId] = m_totalPerId[downloadId];
    }
}

void UpdateWorker::onDownloadMirrorFailure(const QDBusObjectPath &session, const QString &downloadId,
                                           const QString &message, const QString &url, const QString &metadata) {
    Q_UNUSED(session);
    Q_UNUSED(downloadId);
    Q_UNUSED(url);
    Q_UNUSED(metadata);
    if (!message.isEmpty()) {
        emit statusMessageChanged(QStringLiteral("Mirror failover: %1").arg(message));
    }
}

void UpdateWorker::onRepoKeyImportRequest(const QDBusObjectPath &session, const QString &keyId,
                                          const QStringList &userIds, const QString &keyFingerprint,
                                          const QString &keyUrl, qint64 timestamp) {
    Q_UNUSED(session);
    Q_UNUSED(userIds);
    Q_UNUSED(keyFingerprint);
    Q_UNUSED(keyUrl);
    Q_UNUSED(timestamp);
    emit statusMessageChanged(QStringLiteral("Confirming repository GPG key: %1...").arg(keyId));
    if (!m_sessionPath.isEmpty()) {
        QDBusInterface repoIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                 QStringLiteral("org.rpm.dnf.v0.rpm.Repo"), QDBusConnection::systemBus());
        if (repoIface.isValid()) {
            QVariantMap opts;
            opts[QStringLiteral("interactive")] = true;
            repoIface.call(QStringLiteral("confirm_key_with_options"), keyId, true, opts);
        }
    }
}

void UpdateWorker::verifyTransactionResult(const QString &fallbackErrMsg, const QString &errStr) {
    Q_UNUSED(errStr);
    if (!openSession(true, false)) {
        emit statusMessageChanged(fallbackErrMsg);
        emit operationFinished(false, fallbackErrMsg);
        return;
    }

    QList<QVariantMap> rawUpgrades;
    {
        QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                                QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
        rpmIface.setTimeout(60000);

        QVariantMap listOpts;
        listOpts[QStringLiteral("scope")] = QStringLiteral("upgrades");
        listOpts[QStringLiteral("package_attrs")] = QStringList{QStringLiteral("name")};

        QDBusMessage upgradeMsg = rpmIface.call(QStringLiteral("list"), listOpts);
        if (upgradeMsg.type() != QDBusMessage::ErrorMessage && !upgradeMsg.arguments().isEmpty()) {
            const QDBusArgument arg = upgradeMsg.arguments().at(0).value<QDBusArgument>();
            arg >> rawUpgrades;
        }
    }
    closeSession();

    if (rawUpgrades.isEmpty()) {
        // System is completely up to date: transaction actually succeeded and all packages installed cleanly!
        emit inPlaceProgress(QString(), 0, 1, 1, 1.0);
        emit progressStageUpdated(QString(), QString(), QString(), 1, 1, 1.0);
        emit statusMessageChanged(QStringLiteral("Updates installed successfully."));
        emit operationFinished(true, QStringLiteral("In-place update finished successfully."));
        QMetaObject::invokeMethod(this, &UpdateWorker::checkForUpdates, Qt::QueuedConnection, false);
    } else {
        // Some or all updates are still pending - genuine transaction failure
        emit statusMessageChanged(fallbackErrMsg);
        emit operationFinished(false, fallbackErrMsg);
        QMetaObject::invokeMethod(this, &UpdateWorker::checkForUpdates, Qt::QueuedConnection, false);
    }
}

void UpdateWorker::onTransactionBeforeBegin(const QDBusObjectPath &session, qulonglong total) {
    Q_UNUSED(session);
    m_pkgTotalCount = total;
    m_currentPkgIndex = 0;
    m_pkgItemProcessed = 0;
    m_pkgItemTotal = 0;
    m_currentAction = 0;
    emit inPlaceProgress(QString(), 0, 0, total, 0.0);
    emit progressStageUpdated(QStringLiteral("installing"), QStringLiteral("Installing"), QString(), 0, total, 0.0);
}

void UpdateWorker::onTransactionTransactionStart(const QDBusObjectPath &session, qulonglong total) {
    Q_UNUSED(session);
    m_prepTotal = total;
    m_prepProcessed = 0;
    emit progressStageUpdated(QStringLiteral("preparing"), QStringLiteral("Preparing"), QString(), 0, total, 0.0);
    emit statusMessageChanged(QStringLiteral("Preparing transaction..."));
}

void UpdateWorker::onTransactionTransactionProgress(const QDBusObjectPath &session, qulonglong processed, qulonglong total) {
    Q_UNUSED(session);
    m_prepProcessed = processed;
    m_prepTotal = total;
    double frac = (total > 0) ? (static_cast<double>(processed) / static_cast<double>(total)) : 0.0;
    frac = qBound(0.0, frac, 1.0);
    emit progressStageUpdated(QStringLiteral("preparing"), QStringLiteral("Preparing"), QString(), processed, total, frac);
    emit statusMessageChanged(QStringLiteral("Preparing transaction (%1/%2)...").arg(processed).arg(total));
}

void UpdateWorker::onTransactionTransactionStop(const QDBusObjectPath &session, qulonglong total) {
    Q_UNUSED(session);
    emit progressStageUpdated(QStringLiteral("preparing"), QStringLiteral("Preparing"), QString(), total, total, 1.0);
}

void UpdateWorker::onTransactionVerifyStart(const QDBusObjectPath &session, qulonglong total) {
    Q_UNUSED(session);
    m_verifyTotal = total;
    m_verifyProcessed = 0;
    emit progressStageUpdated(QStringLiteral("verifying"), QStringLiteral("Verifying"), QString(), 0, total, 0.0);
    emit statusMessageChanged(QStringLiteral("Verifying package files..."));
}

void UpdateWorker::onTransactionVerifyProgress(const QDBusObjectPath &session, qulonglong processed, qulonglong total) {
    Q_UNUSED(session);
    m_verifyProcessed = processed;
    m_verifyTotal = total;
    double frac = (total > 0) ? (static_cast<double>(processed) / static_cast<double>(total)) : 0.0;
    frac = qBound(0.0, frac, 1.0);
    emit progressStageUpdated(QStringLiteral("verifying"), QStringLiteral("Verifying"), QString(), processed, total, frac);
    emit statusMessageChanged(QStringLiteral("Verifying (%1/%2)...").arg(processed).arg(total));
}

void UpdateWorker::onTransactionVerifyStop(const QDBusObjectPath &session, qulonglong total) {
    Q_UNUSED(session);
    emit progressStageUpdated(QStringLiteral("verifying"), QStringLiteral("Verifying"), QString(), total, total, 1.0);
    emit statusMessageChanged(QStringLiteral("Verification completed."));
}

void UpdateWorker::onTransactionElemProgress(const QDBusObjectPath &session, const QString &nevra,
                                             qulonglong processed, qulonglong total) {
    Q_UNUSED(session);
    m_currentNevra = nevra;
    m_currentPkgIndex = processed;
    if (total > 0) {
        m_pkgTotalCount = total;
    }
    m_pkgItemProcessed = 0;
    m_pkgItemTotal = 0;

    double frac = 0.0;
    if (m_pkgTotalCount > 0 && processed > 0) {
        frac = static_cast<double>(processed - 1) / static_cast<double>(m_pkgTotalCount);
    }
    frac = qBound(0.0, frac, 1.0);
    QString stage = actionToStageName(m_currentAction);
    QString stageDisplay = actionToDisplayName(m_currentAction);

    emit inPlaceProgress(nevra, m_currentAction, processed, m_pkgTotalCount, frac);
    emit progressStageUpdated(stage, stageDisplay, nevra, processed, m_pkgTotalCount, frac);
    emit statusMessageChanged(QStringLiteral("%1 (%2/%3): %4").arg(stageDisplay).arg(processed).arg(m_pkgTotalCount).arg(nevra));
}

void UpdateWorker::onTransactionActionStart(const QDBusObjectPath &session, const QString &nevra,
                                            uint action, qulonglong total) {
    Q_UNUSED(session);
    m_currentAction = action;
    m_currentNevra = nevra;
    m_pkgItemTotal = total;
    m_pkgItemProcessed = 0;

    double overallFrac = 0.0;
    if (m_pkgTotalCount > 0 && m_currentPkgIndex > 0) {
        overallFrac = static_cast<double>(m_currentPkgIndex - 1) / static_cast<double>(m_pkgTotalCount);
    }
    overallFrac = qBound(0.0, overallFrac, 1.0);
    QString stage = actionToStageName(action);
    QString stageDisplay = actionToDisplayName(action);

    emit inPlaceProgress(nevra, action, m_currentPkgIndex, m_pkgTotalCount, overallFrac);
    emit progressStageUpdated(stage, stageDisplay, nevra, m_currentPkgIndex, m_pkgTotalCount, overallFrac);
    emit statusMessageChanged(QStringLiteral("%1 (%2/%3): %4").arg(stageDisplay).arg(m_currentPkgIndex).arg(m_pkgTotalCount).arg(nevra));
}

void UpdateWorker::onTransactionActionProgress(const QDBusObjectPath &session, const QString &nevra,
                                               qulonglong processed, qulonglong total) {
    Q_UNUSED(session);
    m_currentNevra = nevra;
    m_pkgItemProcessed = processed;
    m_pkgItemTotal = total;

    double itemFrac = (total > 0) ? (static_cast<double>(processed) / static_cast<double>(total)) : 0.0;
    itemFrac = qBound(0.0, itemFrac, 1.0);

    double overallFrac = 0.0;
    if (m_pkgTotalCount > 0) {
        double base = (m_currentPkgIndex > 0) ? (m_currentPkgIndex - 1) : 0;
        overallFrac = (base + itemFrac) / static_cast<double>(m_pkgTotalCount);
    }
    overallFrac = qBound(0.0, overallFrac, 1.0);
    QString stage = actionToStageName(m_currentAction);
    QString stageDisplay = actionToDisplayName(m_currentAction);

    emit inPlaceProgress(nevra, m_currentAction, m_currentPkgIndex, m_pkgTotalCount, overallFrac);
    emit progressStageUpdated(stage, stageDisplay, nevra, m_currentPkgIndex, m_pkgTotalCount, overallFrac);
}

void UpdateWorker::onTransactionActionStop(const QDBusObjectPath &session, const QString &nevra,
                                           qulonglong total) {
    Q_UNUSED(session);
    Q_UNUSED(nevra);
    Q_UNUSED(total);
    double overallFrac = 0.0;
    if (m_pkgTotalCount > 0 && m_currentPkgIndex > 0) {
        overallFrac = static_cast<double>(m_currentPkgIndex) / static_cast<double>(m_pkgTotalCount);
    }
    overallFrac = qBound(0.0, overallFrac, 1.0);
    QString stage = actionToStageName(m_currentAction);
    QString stageDisplay = actionToDisplayName(m_currentAction);

    emit inPlaceProgress(m_currentNevra, m_currentAction, m_currentPkgIndex, m_pkgTotalCount, overallFrac);
    emit progressStageUpdated(stage, stageDisplay, m_currentNevra, m_currentPkgIndex, m_pkgTotalCount, overallFrac);
}

void UpdateWorker::onTransactionScriptStart(const QDBusObjectPath &session, const QString &nevra,
                                            uint scriptletType) {
    Q_UNUSED(session);
    Q_UNUSED(scriptletType);
    double overallFrac = 0.0;
    if (m_pkgTotalCount > 0 && m_currentPkgIndex > 0) {
        overallFrac = static_cast<double>(m_currentPkgIndex) / static_cast<double>(m_pkgTotalCount);
    }
    emit progressStageUpdated(QStringLiteral("configuring"), QStringLiteral("Configuring"), nevra,
                              m_currentPkgIndex, m_pkgTotalCount, qBound(0.0, overallFrac, 1.0));
    if (!nevra.isEmpty()) {
        emit statusMessageChanged(QStringLiteral("Configuring %1...").arg(nevra));
    }
}

void UpdateWorker::onTransactionScriptStop(const QDBusObjectPath &session, const QString &nevra,
                                           uint scriptletType, qulonglong returnCode) {
    Q_UNUSED(session);
    Q_UNUSED(nevra);
    Q_UNUSED(scriptletType);
    Q_UNUSED(returnCode);
}

void UpdateWorker::onTransactionScriptError(const QDBusObjectPath &session, const QString &nevra,
                                            uint scriptletType, qulonglong returnCode) {
    Q_UNUSED(session);
    Q_UNUSED(scriptletType);
    if (!nevra.isEmpty()) {
        emit statusMessageChanged(QStringLiteral("Scriptlet error in %1 (code %2)").arg(nevra).arg(returnCode));
    }
}

void UpdateWorker::onTransactionUnpackError(const QDBusObjectPath &session, const QString &nevra) {
    Q_UNUSED(session);
    if (!nevra.isEmpty()) {
        emit statusMessageChanged(QStringLiteral("Unpack error in %1").arg(nevra));
    }
}

void UpdateWorker::onTransactionAfterComplete(const QDBusObjectPath &session, bool success) {
    Q_UNUSED(session);
    if (success) {
        emit inPlaceProgress(QString(), 0, m_pkgTotalCount, m_pkgTotalCount, 1.0);
        emit progressStageUpdated(QString(), QString(), QString(), m_pkgTotalCount, m_pkgTotalCount, 1.0);
        emit statusMessageChanged(QStringLiteral("Transaction completed successfully."));
    }
}

} // namespace qs::updatemanager
