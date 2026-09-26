#include "UpdateWorker.hpp"

#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDateTime>
#include <QDebug>
#include <limits>

namespace qs::updatemanager {

UpdateWorker::UpdateWorker(QObject *parent)
    : QObject(parent) {
    registerDbusTypes();
}

UpdateWorker::~UpdateWorker() {
    closeSession();
}

bool UpdateWorker::openSession(bool loadSystemRepo, bool loadAvailableRepos) {
    closeSession();
    m_cancelled = false;

    QDBusInterface sm(QStringLiteral("org.rpm.dnf.v0"),
                      QStringLiteral("/org/rpm/dnf/v0"),
                      QStringLiteral("org.rpm.dnf.v0.SessionManager"),
                      QDBusConnection::systemBus());
    if (!sm.isValid()) {
        qWarning() << "UpdateWorker: SessionManager interface invalid:" << sm.lastError().message();
        return false;
    }
    sm.setTimeout(60000);

    QVariantMap options;
    options[QStringLiteral("load_system_repo")] = loadSystemRepo;
    options[QStringLiteral("load_available_repos")] = loadAvailableRepos;

    QDBusReply<QDBusObjectPath> reply = sm.call(QStringLiteral("open_session"), options);
    if (!reply.isValid()) {
        qWarning() << "UpdateWorker: Failed to open session:" << reply.error().message();
        return false;
    }

    m_sessionPath = reply.value().path();

    // Connect Base download signals
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

    // Connect RPM transaction signals
    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_elem_progress"), this,
        SLOT(onTransactionElemProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_progress"), this,
        SLOT(onTransactionActionProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));

    QDBusConnection::systemBus().connect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_after_complete"), this,
        SLOT(onTransactionAfterComplete(QDBusObjectPath,bool)));

    return true;
}

void UpdateWorker::closeSession() {
    if (m_sessionPath.isEmpty()) {
        return;
    }

    // Disconnect signals
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
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_elem_progress"), this,
        SLOT(onTransactionElemProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));
    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_action_progress"), this,
        SLOT(onTransactionActionProgress(QDBusObjectPath,QString,qulonglong,qulonglong)));
    QDBusConnection::systemBus().disconnect(
        QStringLiteral("org.rpm.dnf.v0"), m_sessionPath, QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"),
        QStringLiteral("transaction_after_complete"), this,
        SLOT(onTransactionAfterComplete(QDBusObjectPath,bool)));

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

    if (!openSession(true, true)) {
        emit checkFinished({}, false, QStringLiteral("Failed to connect to DNF5 daemon service."));
        return;
    }

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

    if (m_cancelled) {
        closeSession();
        emit checkFinished({}, false, QStringLiteral("Update check was cancelled."));
        return;
    }

    emit statusMessageChanged(QStringLiteral("Scanning for available updates..."));
    emit checkProgress(QStringLiteral("Querying package upgrades..."), 60);

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
        closeSession();
        emit checkFinished({}, false, upgradeMsg.errorMessage());
        return;
    }

    const QDBusArgument arg = upgradeMsg.arguments().at(0).value<QDBusArgument>();
    QList<QVariantMap> rawUpgrades;
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

    QMap<QString, QString> installedEvrMap;
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

    emit statusMessageChanged(QStringLiteral("Checking security advisories..."));
    emit checkProgress(QStringLiteral("Fetching security errata..."), 85);

    // Query advisories
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

    struct AdvInfo {
        QString id;
        QString title;
        QString type;
        QString severity;
        QString description;
        QStringList cves;
    };
    QMap<QString, AdvInfo> pkgToAdvisory;

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

            // Extract CVEs from references
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

            // Map packages in collections
            if (adv.contains(QStringLiteral("collections"))) {
                const auto colVar = adv.value(QStringLiteral("collections"));
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
                                pkgToAdvisory[val.toString()] = info;
                            }
                        }
                        colArg.endMap();
                    }
                    colArg.endArray();
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

    // Check offline status
    QDBusInterface offIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.Offline"), QDBusConnection::systemBus());
    if (offIface.isValid()) {
        QDBusMessage statusReply = offIface.call(QStringLiteral("get_status"));
        if (statusReply.type() != QDBusMessage::ErrorMessage && !statusReply.arguments().isEmpty()) {
            bool pending = statusReply.arguments().at(0).toBool();
            emit offlineStagedReady(pending);
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

    if (!openSession(false, true)) {
        emit changelogFetched(packageName, {});
        return;
    }

    QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
    rpmIface.setTimeout(60000);

    QVariantMap listOpts;
    listOpts[QStringLiteral("scope")] = QStringLiteral("upgrades");
    listOpts[QStringLiteral("patterns")] = QStringList{packageName};
    listOpts[QStringLiteral("package_attrs")] = QStringList{
        QStringLiteral("name"), QStringLiteral("changelogs"), QStringLiteral("description")
    };

    QVariantList entries;
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
                        qint64 ts;
                        QString author, text;
                        clArg >> ts >> author >> text;
                        clArg.endStructure();

                        QVariantMap entry;
                        entry[QStringLiteral("timestamp")] = ts;
                        entry[QStringLiteral("date")] = QDateTime::fromSecsSinceEpoch(ts).toString(QStringLiteral("yyyy-MM-dd"));
                        entry[QStringLiteral("author")] = author;
                        entry[QStringLiteral("text")] = text;
                        entries.append(entry);
                    }
                    clArg.endArray();
                }
            }
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

    cleanOffline();

    if (!openSession(true, true)) {
        emit operationFinished(false, QStringLiteral("Failed to open DNF5 session for offline staging."));
        return;
    }

    QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
    rpmIface.setTimeout(120000);
    rpmIface.call(QStringLiteral("upgrade"), QStringList(), QVariantMap());

    QDBusInterface goalIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                             QStringLiteral("org.rpm.dnf.v0.Goal"), QDBusConnection::systemBus());
    goalIface.setTimeout(300000);

    emit statusMessageChanged(QStringLiteral("Resolving dependencies..."));
    QVariantMap resOpts;
    resOpts[QStringLiteral("allow_erasing")] = false;
    QDBusMessage resReply = goalIface.call(QStringLiteral("resolve"), resOpts);
    if (resReply.type() == QDBusMessage::ErrorMessage) {
        closeSession();
        emit operationFinished(false, QStringLiteral("Resolution error: ") + resReply.errorMessage());
        return;
    }

    emit statusMessageChanged(QStringLiteral("Downloading packages and verifying transaction..."));
    QVariantMap transOpts;
    transOpts[QStringLiteral("offline")] = true;
    transOpts[QStringLiteral("downloadonly")] = true;
    transOpts[QStringLiteral("interactive")] = false;

    goalIface.setTimeout(std::numeric_limits<int>::max());
    QDBusMessage transReply = goalIface.call(QStringLiteral("do_transaction"), transOpts);

    if (transReply.type() == QDBusMessage::ErrorMessage) {
        closeSession();
        emit operationFinished(false, QStringLiteral("Download failed: ") + transReply.errorMessage());
        return;
    }

    closeSession();
    emit offlineStagedReady(true);
    emit statusMessageChanged(QStringLiteral("Updates downloaded. Ready to restart."));
    emit operationFinished(true, QStringLiteral("Updates successfully staged for next boot."));
}

void UpdateWorker::startInPlaceUpgrade() {
    emit statusMessageChanged(QStringLiteral("Preparing in-place upgrade..."));
    m_downloadedPerId.clear();
    m_totalPerId.clear();
    m_totalBytesToDownload = 0;

    if (!openSession(true, true)) {
        emit operationFinished(false, QStringLiteral("Failed to open DNF5 session."));
        return;
    }

    QDBusInterface rpmIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.rpm.Rpm"), QDBusConnection::systemBus());
    rpmIface.setTimeout(120000);
    rpmIface.call(QStringLiteral("upgrade"), QStringList(), QVariantMap());

    QDBusInterface goalIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                             QStringLiteral("org.rpm.dnf.v0.Goal"), QDBusConnection::systemBus());
    goalIface.setTimeout(300000);

    emit statusMessageChanged(QStringLiteral("Resolving dependencies..."));
    QVariantMap resOpts;
    resOpts[QStringLiteral("allow_erasing")] = false;
    QDBusMessage resReply = goalIface.call(QStringLiteral("resolve"), resOpts);
    if (resReply.type() == QDBusMessage::ErrorMessage) {
        closeSession();
        emit operationFinished(false, QStringLiteral("Resolution error: ") + resReply.errorMessage());
        return;
    }

    emit statusMessageChanged(QStringLiteral("Applying updates (requires authentication)..."));
    QVariantMap transOpts;
    transOpts[QStringLiteral("offline")] = false;
    transOpts[QStringLiteral("interactive")] = true;

    goalIface.setTimeout(std::numeric_limits<int>::max());
    QDBusMessage transReply = goalIface.call(QStringLiteral("do_transaction"), transOpts);

    if (transReply.type() == QDBusMessage::ErrorMessage) {
        closeSession();
        emit operationFinished(false, QStringLiteral("Transaction failed: ") + transReply.errorMessage());
        return;
    }

    closeSession();
    emit statusMessageChanged(QStringLiteral("Updates installed successfully."));
    emit operationFinished(true, QStringLiteral("In-place update finished successfully."));
}

void UpdateWorker::rebootAndApply() {
    emit statusMessageChanged(QStringLiteral("Scheduling reboot..."));

    if (!openSession(true, false)) {
        emit operationFinished(false, QStringLiteral("Failed to open session to schedule reboot."));
        return;
    }

    QDBusInterface offIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.Offline"), QDBusConnection::systemBus());
    offIface.setTimeout(120000);

    QVariantMap schedOpts;
    schedOpts[QStringLiteral("interactive")] = true;
    QDBusReply<bool> schedReply = offIface.call(QStringLiteral("schedule_for_next_boot"), schedOpts);
    if (!schedReply.isValid() || !schedReply.value()) {
        QString err = schedReply.isValid() ? QStringLiteral("Failed to schedule offline update.")
                                           : schedReply.error().message();
        closeSession();
        emit operationFinished(false, err);
        return;
    }

    offIface.call(QStringLiteral("set_finish_action"), QStringLiteral("reboot"));
    closeSession();

    // Trigger reboot via systemd-logind
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
            goalIface.call(QStringLiteral("cancel"));
        }
    }
}

void UpdateWorker::cleanOffline() {
    if (!openSession(true, false)) {
        return;
    }
    QDBusInterface offIface(QStringLiteral("org.rpm.dnf.v0"), m_sessionPath,
                            QStringLiteral("org.rpm.dnf.v0.Offline"), QDBusConnection::systemBus());
    if (offIface.isValid()) {
        offIface.call(QStringLiteral("clean"));
    }
    closeSession();
    emit offlineStagedReady(false);
}

void UpdateWorker::onDownloadAddNew(const QDBusObjectPath &session, const QString &downloadId,
                                    const QString &description, qint64 totalToDownload) {
    Q_UNUSED(session);
    Q_UNUSED(description);
    m_totalPerId[downloadId] = totalToDownload;
    m_downloadedPerId[downloadId] = 0;
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
    emit downloadProgress(downloadedAll, totalAll, qBound(0.0, frac, 1.0));
}

void UpdateWorker::onDownloadEnd(const QDBusObjectPath &session, const QString &downloadId,
                                 uint transferStatus, const QString &message) {
    Q_UNUSED(session);
    Q_UNUSED(transferStatus);
    Q_UNUSED(message);
    if (m_totalPerId.contains(downloadId)) {
        m_downloadedPerId[downloadId] = m_totalPerId[downloadId];
    }
}

void UpdateWorker::onTransactionElemProgress(const QDBusObjectPath &session, const QString &nevra,
                                             qulonglong processed, qulonglong total) {
    Q_UNUSED(session);
    emit inPlaceProgress(nevra, 0, processed, total);
}

void UpdateWorker::onTransactionActionProgress(const QDBusObjectPath &session, const QString &nevra,
                                               qulonglong processed, qulonglong total) {
    Q_UNUSED(session);
    emit inPlaceProgress(nevra, 2, processed, total);
}

void UpdateWorker::onTransactionAfterComplete(const QDBusObjectPath &session, bool success) {
    Q_UNUSED(session);
    emit statusMessageChanged(success ? QStringLiteral("Transaction completed successfully.")
                                      : QStringLiteral("Transaction finished with issues."));
}

} // namespace qs::updatemanager
