#include "KWinManager.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QStringView>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>
#include <QtDBus/QDBusPendingCallWatcher>
#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusReply>
#include <atomic>

namespace qs::plugins::kwin {

namespace {

QString serviceName() {
    return QStringLiteral("org.quickshell.KWinManager_%1").arg(QCoreApplication::applicationPid());
}

const QString kObjectPath = QStringLiteral("/Manager");

const QString kTrackerScriptTemplate = QStringLiteral(R"(
var service = "%1";
var iface = "org.quickshell.KWinManager";
var path = "/Manager";

function sendWindows() {
    var wins = workspace.windowList();
    var out = "";
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        if (w.normalWindow && !w.skipTaskbar) {
            var id = w.internalId ? w.internalId.toString() : ("win_" + i);
            var appId = (w.desktopFileName || w.resourceClass || "").toString();
            var flags = (w.active ? 1 : 0) | (w.minimized ? 2 : 0) | (w.maximized ? 4 : 0) | (w.fullScreen ? 8 : 0);
            var title = (w.caption || "").toString().replace(/[\t\n\r]/g, " ");
            var icon = (w.icon ? (w.icon.name || "") : "").toString().replace(/[\t\n\r]/g, " ");
            out += id + "\t" + appId + "\t" + flags + "\t" + title + "\t" + icon + "\n";
        }
    }
    callDBus(service, path, iface, "updateWindowsPacked", out);
}

function hookWindow(w) {
    if (w.captionChanged) w.captionChanged.connect(sendWindows);
    if (w.minimizedChanged) w.minimizedChanged.connect(sendWindows);
    if (w.activeChanged) w.activeChanged.connect(sendWindows);
    if (w.desktopFileNameChanged) w.desktopFileNameChanged.connect(sendWindows);
    if (w.windowClassChanged) w.windowClassChanged.connect(sendWindows);
}

for (var i = 0; i < workspace.windowList().length; i++) {
    hookWindow(workspace.windowList()[i]);
}

workspace.windowAdded.connect(function(w) {
    hookWindow(w);
    sendWindows();
});
workspace.windowRemoved.connect(sendWindows);
workspace.windowActivated.connect(sendWindows);

sendWindows();
)");

class Bridge : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.quickshell.KWinManager")
public:
    explicit Bridge(QObject *parent = nullptr) : QObject(parent) {}
public Q_SLOTS:
    Q_SCRIPTABLE void updateWindowsPacked(const QString &packed) {
        KWinManager::handleDbusUpdatePacked(packed);
    }
};

static QList<KWinManager *> s_instances;
static WindowModel *s_sharedModel = nullptr;
static Bridge *s_bridge = nullptr;
static int s_trackerScriptId = -1;
static QString s_trackerScriptPath;
static std::atomic<quint64> s_actionSeq{0};

void cleanupStaleScriptFiles(const QString &tempDir) {
    QDir dir(tempDir);
    const QFileInfoList entries = dir.entryInfoList({QStringLiteral("quickshell_kwin_*.js")}, QDir::Files);
    for (const QFileInfo &info : entries) {
        const QString base = info.baseName();
        const auto parts = QStringView(base).split(QLatin1Char('_'));
        if (parts.size() >= 4) {
            bool ok = false;
            const qint64 pid = parts[3].toLongLong(&ok);
            if (ok && pid > 0 && !QFile::exists(QStringLiteral("/proc/%1").arg(pid))) {
                QFile::remove(info.absoluteFilePath());
            }
        }
    }
}

void unloadActionScriptAndRemove(const QString &actionPath) {
    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             QDBusConnection::sessionBus());
    if (scripting.isValid()) {
        auto *unloadWatcher = new QDBusPendingCallWatcher(
            scripting.asyncCall(QStringLiteral("unloadScript"), actionPath));
        QObject::connect(unloadWatcher, &QDBusPendingCallWatcher::finished, [unloadWatcher, actionPath]() {
            unloadWatcher->deleteLater();
            QFile::remove(actionPath);
        });
    } else {
        QFile::remove(actionPath);
    }
}

void runActionScript(const QString &code) {
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (tempDir.isEmpty()) {
        tempDir = QDir::tempPath();
    }
    const QString actionPath = tempDir + QStringLiteral("/quickshell_kwin_act_%1_%2.js")
                                             .arg(QCoreApplication::applicationPid())
                                             .arg(++s_actionSeq);

    QFile file(actionPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        return;
    }
    file.write(code.toUtf8());
    file.close();

    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             QDBusConnection::sessionBus());
    if (!scripting.isValid()) {
        QFile::remove(actionPath);
        return;
    }

    auto *loadWatcher = new QDBusPendingCallWatcher(
        scripting.asyncCall(QStringLiteral("loadScript"), actionPath));
    QObject::connect(loadWatcher, &QDBusPendingCallWatcher::finished, [loadWatcher, actionPath]() {
        loadWatcher->deleteLater();
        QDBusPendingReply<int> reply = *loadWatcher;
        if (!reply.isValid() || reply.isError() || reply.value() < 0) {
            QFile::remove(actionPath);
            return;
        }

        const int sId = reply.value();
        const QString scriptObjPath = QStringLiteral("/Scripting/Script%1").arg(sId);
        QDBusInterface scriptObj(QStringLiteral("org.kde.KWin"),
                                 scriptObjPath,
                                 QStringLiteral("org.kde.kwin.Script"),
                                 QDBusConnection::sessionBus());
        if (!scriptObj.isValid()) {
            unloadActionScriptAndRemove(actionPath);
            return;
        }

        auto *runWatcher = new QDBusPendingCallWatcher(
            scriptObj.asyncCall(QStringLiteral("run")));
        QObject::connect(runWatcher, &QDBusPendingCallWatcher::finished, [runWatcher, actionPath]() {
            runWatcher->deleteLater();
            unloadActionScriptAndRemove(actionPath);
        });
    });
}

void installTrackingScript() {
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (tempDir.isEmpty()) {
        tempDir = QDir::tempPath();
    }
    cleanupStaleScriptFiles(tempDir);

    s_trackerScriptPath = tempDir + QStringLiteral("/quickshell_kwin_bridge_%1.js").arg(QCoreApplication::applicationPid());

    QFile file(s_trackerScriptPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        file.write(kTrackerScriptTemplate.arg(serviceName()).toUtf8());
        file.close();
    } else {
        return;
    }

    QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                             QStringLiteral("/Scripting"),
                             QStringLiteral("org.kde.kwin.Scripting"),
                             QDBusConnection::sessionBus());
    if (!scripting.isValid()) {
        QFile::remove(s_trackerScriptPath);
        return;
    }

    auto *loadWatcher = new QDBusPendingCallWatcher(
        scripting.asyncCall(QStringLiteral("loadScript"), s_trackerScriptPath));
    QObject::connect(loadWatcher, &QDBusPendingCallWatcher::finished, [loadWatcher]() {
        loadWatcher->deleteLater();
        if (s_instances.isEmpty()) {
            QFile::remove(s_trackerScriptPath);
            return;
        }

        QDBusPendingReply<int> reply = *loadWatcher;
        if (!reply.isValid() || reply.isError() || reply.value() < 0) {
            QFile::remove(s_trackerScriptPath);
            return;
        }

        s_trackerScriptId = reply.value();
        const QString scriptObjPath = QStringLiteral("/Scripting/Script%1").arg(s_trackerScriptId);
        QDBusInterface scriptObj(QStringLiteral("org.kde.KWin"),
                                 scriptObjPath,
                                 QStringLiteral("org.kde.kwin.Script"),
                                 QDBusConnection::sessionBus());
        if (scriptObj.isValid()) {
            auto *runWatcher = new QDBusPendingCallWatcher(
                scriptObj.asyncCall(QStringLiteral("run")));
            QObject::connect(runWatcher, &QDBusPendingCallWatcher::finished, [runWatcher]() {
                runWatcher->deleteLater();
            });
        }
    });
}

void uninstallTrackingScript() {
    if (s_trackerScriptId >= 0) {
        QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                                 QStringLiteral("/Scripting"),
                                 QStringLiteral("org.kde.kwin.Scripting"),
                                 QDBusConnection::sessionBus());
        if (scripting.isValid()) {
            scripting.asyncCall(QStringLiteral("unloadScript"), s_trackerScriptPath);
        }
        s_trackerScriptId = -1;
    }

    if (!s_trackerScriptPath.isEmpty() && QFile::exists(s_trackerScriptPath)) {
        QFile::remove(s_trackerScriptPath);
    }
}

} // namespace

KWinManager::KWinManager(QObject *parent)
    : QObject(parent) {
    s_instances.append(this);

    if (!s_sharedModel) {
        s_sharedModel = new WindowModel();
    }

    if (s_instances.size() == 1) {
        s_bridge = new Bridge();
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.registerService(serviceName());
        bus.registerObject(kObjectPath, s_bridge, QDBusConnection::ExportAllSlots);
        installTrackingScript();
    } else {
        m_available = s_instances.first()->m_available;
    }
}

KWinManager::~KWinManager() {
    s_instances.removeOne(this);

    if (s_instances.isEmpty()) {
        uninstallTrackingScript();
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.unregisterObject(kObjectPath);
        bus.unregisterService(serviceName());
        delete s_bridge;
        s_bridge = nullptr;
        delete s_sharedModel;
        s_sharedModel = nullptr;
    }
}

QAbstractItemModel *KWinManager::model() const {
    return s_sharedModel;
}

QVariantList KWinManager::windows() const {
    return s_sharedModel ? s_sharedModel->toVariantList() : QVariantList();
}

int KWinManager::count() const {
    return s_sharedModel ? s_sharedModel->rowCount() : 0;
}

void KWinManager::dispatchAction(const QString &action, const QString &windowId) {
    if (windowId.trimmed().isEmpty()) {
        return;
    }

    QString safeId = windowId.trimmed();
    safeId.replace(QLatin1Char('\\'), QStringLiteral("\\\\")).replace(QLatin1Char('"'), QStringLiteral("\\\""));

    QString actionLogic;
    if (action == QLatin1String("toggle")) {
        actionLogic = QStringLiteral(R"(
            if (w.active) {
                w.minimized = true;
            } else {
                w.minimized = false;
                workspace.activeWindow = w;
            }
        )");
    } else if (action == QLatin1String("activate")) {
        actionLogic = QStringLiteral(R"(
            w.minimized = false;
            workspace.activeWindow = w;
        )");
    } else if (action == QLatin1String("minimize")) {
        actionLogic = QStringLiteral(R"(
            w.minimized = true;
        )");
    }

    const QString code = QStringLiteral(R"(
        var wins = workspace.windowList();
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (w.internalId && w.internalId.toString() === "%1") {
                %2
                break;
            }
        }
    )").arg(safeId, actionLogic);

    runActionScript(code);
}

void KWinManager::toggleWindow(const QString &windowId) {
    dispatchAction(QStringLiteral("toggle"), windowId);
}

void KWinManager::activateWindow(const QString &windowId) {
    dispatchAction(QStringLiteral("activate"), windowId);
}

void KWinManager::minimizeWindow(const QString &windowId) {
    dispatchAction(QStringLiteral("minimize"), windowId);
}

void KWinManager::refresh() {
    runActionScript(QStringLiteral("sendWindows();"));
}

void KWinManager::handleDbusUpdatePacked(const QString &packed) {
    if (!s_sharedModel) {
        return;
    }

    QList<WindowRecord> records;
    const auto lines = QStringView(packed).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    records.reserve(lines.size());

    for (const auto &line : lines) {
        const auto parts = line.split(QLatin1Char('\t'));
        if (parts.size() < 4) {
            continue;
        }
        WindowRecord rec;
        rec.id = parts[0].toString();
        rec.appId = parts[1].toString();
        int flags = parts[2].toInt();
        rec.active = (flags & 1) != 0;
        rec.minimized = (flags & 2) != 0;
        rec.maximized = (flags & 4) != 0;
        rec.fullscreen = (flags & 8) != 0;
        rec.title = parts[3].toString();
        if (parts.size() >= 5) {
            rec.icon = parts[4].toString();
        }
        records.append(rec);
    }

    s_sharedModel->updateRecords(records);

    for (KWinManager *inst : std::as_const(s_instances)) {
        Q_EMIT inst->windowsChanged();
        if (!inst->m_available) {
            inst->m_available = true;
            Q_EMIT inst->availableChanged();
        }
    }
}

} // namespace qs::plugins::kwin

#include "KWinManager.moc"
