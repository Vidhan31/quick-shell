#include "KWinManager.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSet>
#include <QStandardPaths>
#include <QStringView>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusReply>

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

void runActionScript(const QString &code) {
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (tempDir.isEmpty()) {
        tempDir = QDir::tempPath();
    }
    const QString actionPath = tempDir + QStringLiteral("/quickshell_kwin_act_%1.js").arg(QCoreApplication::applicationPid());

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
        return;
    }

    QDBusReply<int> reply = scripting.call(QStringLiteral("loadScript"), actionPath);
    if (!reply.isValid()) {
        return;
    }

    const int sId = reply.value();
    const QString scriptObjPath = QStringLiteral("/Scripting/Script%1").arg(sId);
    QDBusInterface scriptObj(QStringLiteral("org.kde.KWin"),
                             scriptObjPath,
                             QStringLiteral("org.kde.kwin.Script"),
                             QDBusConnection::sessionBus());
    if (scriptObj.isValid()) {
        scriptObj.call(QStringLiteral("run"));
    }
    scripting.call(QStringLiteral("unloadScript"), actionPath);
}

void installTrackingScript() {
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (tempDir.isEmpty()) {
        tempDir = QDir::tempPath();
    }
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
        return;
    }

    scripting.call(QStringLiteral("unloadScript"), s_trackerScriptPath);

    QDBusReply<int> reply = scripting.call(QStringLiteral("loadScript"), s_trackerScriptPath);
    if (reply.isValid()) {
        s_trackerScriptId = reply.value();
        QString scriptObjPath = QStringLiteral("/Scripting/Script%1").arg(s_trackerScriptId);
        QDBusInterface scriptObj(QStringLiteral("org.kde.KWin"),
                                 scriptObjPath,
                                 QStringLiteral("org.kde.kwin.Script"),
                                 QDBusConnection::sessionBus());
        if (scriptObj.isValid()) {
            scriptObj.call(QStringLiteral("run"));
        }
    }
}

void uninstallTrackingScript() {
    if (s_trackerScriptId >= 0) {
        QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                                 QStringLiteral("/Scripting"),
                                 QStringLiteral("org.kde.kwin.Scripting"),
                                 QDBusConnection::sessionBus());
        if (scripting.isValid()) {
            scripting.call(QStringLiteral("unloadScript"), s_trackerScriptPath);
        }
        s_trackerScriptId = -1;
    }

    if (!s_trackerScriptPath.isEmpty() && QFile::exists(s_trackerScriptPath)) {
        QFile::remove(s_trackerScriptPath);
    }
}

static QString stripDesktop(QString str) {
    if (str.endsWith(QLatin1String(".desktop"), Qt::CaseInsensitive)) {
        str.chop(8);
    }
    return str.toLower();
}

static QString normalizeName(const QString &str) {
    QString res;
    res.reserve(str.size());
    for (const QChar ch : str) {
        if (!ch.isSpace() && ch != QLatin1Char('-') && ch != QLatin1Char('_')) {
            res.append(ch.toLower());
        }
    }
    return res;
}

static bool matchesApp(const QString &winAppIdRaw,
                       const QString &appIdRaw,
                       const QString &appNameRaw,
                       const QVariantMap &appAliases) {
    if (winAppIdRaw.isEmpty()) return false;
    const QString w = stripDesktop(winAppIdRaw);

    if (!appIdRaw.isEmpty()) {
        const QString p = stripDesktop(appIdRaw);
        if (w == p || w.endsWith(QLatin1Char('.') + p) || p.endsWith(QLatin1Char('.') + w)) {
            return true;
        }
        const QString alias = appAliases.value(w).toString().toLower();
        if (!alias.isEmpty() && (alias == p || alias.endsWith(QLatin1Char('.') + p) || p.endsWith(QLatin1Char('.') + alias))) {
            return true;
        }
    }

    if (!appNameRaw.isEmpty()) {
        const QString n = appNameRaw.toLower();
        if (w == n || normalizeName(w) == normalizeName(appNameRaw)) {
            return true;
        }
    }

    return false;
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

QVariantList KWinManager::mergeDockItems(const QVariantList &pinnedApps, const QVariantMap &appAliases) const {
    if (!s_sharedModel) {
        return pinnedApps;
    }

    const QList<WindowRecord> &wins = s_sharedModel->windows();
    QVariantList closedPins;
    QVariantList openedPins;
    closedPins.reserve(pinnedApps.size());
    openedPins.reserve(pinnedApps.size());
    QSet<QString> claimedWinIds;

    for (const QVariant &pinVar : pinnedApps) {
        const QVariantMap p = pinVar.toMap();
        const QString pId = p.value(QStringLiteral("id")).toString();
        const QString pName = p.value(QStringLiteral("name")).toString();

        const WindowRecord *matchedWin = nullptr;
        for (const WindowRecord &w : wins) {
            if (!claimedWinIds.contains(w.id) && matchesApp(w.appId, pId, pName, appAliases)) {
                if (w.active) {
                    matchedWin = &w;
                    break;
                } else if (!matchedWin) {
                    matchedWin = &w;
                }
            }
        }
        if (matchedWin) {
            claimedWinIds.insert(matchedWin->id);
        }

        QVariantMap item;
        item.insert(QStringLiteral("id"), pId);
        item.insert(QStringLiteral("name"), pName);
        item.insert(QStringLiteral("iconSrc"), p.value(QStringLiteral("iconSrc")));
        item.insert(QStringLiteral("isPinned"), true);
        item.insert(QStringLiteral("isRunning"), matchedWin != nullptr);
        item.insert(QStringLiteral("isActive"), matchedWin ? matchedWin->active : false);
        item.insert(QStringLiteral("isMinimized"), matchedWin ? matchedWin->minimized : false);
        item.insert(QStringLiteral("windowId"), matchedWin ? matchedWin->id : QString());
        item.insert(QStringLiteral("windowTitle"), matchedWin ? (matchedWin->title.isEmpty() ? pName : matchedWin->title) : pName);
        item.insert(QStringLiteral("entry"), p.value(QStringLiteral("entry")));

        if (matchedWin) {
            openedPins.append(item);
        } else {
            closedPins.append(item);
        }
    }

    QVariantList items;
    items.reserve(pinnedApps.size() + wins.size());
    items.append(closedPins);
    items.append(openedPins);

    for (const WindowRecord &w : wins) {
        if (claimedWinIds.contains(w.id)) {
            continue;
        }
        const QString title = w.title.isEmpty() ? (w.appId.isEmpty() ? QStringLiteral("Window") : w.appId) : w.title;
        QVariantMap item;
        item.insert(QStringLiteral("id"), QStringLiteral("win:") + w.id);
        item.insert(QStringLiteral("name"), title);
        item.insert(QStringLiteral("iconSrc"), QString());
        item.insert(QStringLiteral("appId"), w.appId);
        item.insert(QStringLiteral("isPinned"), false);
        item.insert(QStringLiteral("isRunning"), true);
        item.insert(QStringLiteral("isActive"), w.active);
        item.insert(QStringLiteral("isMinimized"), w.minimized);
        item.insert(QStringLiteral("windowId"), w.id);
        item.insert(QStringLiteral("windowTitle"), w.title);
        item.insert(QStringLiteral("entry"), QVariant());
        items.append(item);
    }

    return items;
}

} // namespace qs::plugins::kwin

#include "KWinManager.moc"
