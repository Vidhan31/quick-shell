#include "PathProbe.hpp"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QProcess>
#include <QUrl>

namespace qs::plugins {

namespace {

// QMimeDatabase initializes lazily behind a process-wide guard. Measured cold
// on this box at well under a millisecond, because Qt 6 parses glob data up
// front and loads type definitions on demand. Nothing worth warming.
QMimeDatabase &mimeDatabase() {
    static QMimeDatabase db;
    return db;
}

// Short enough that a wedged file manager is abandoned quickly, long enough
// to cover a cold Dolphin daemon answering on the bus.
constexpr int REVEAL_TIMEOUT_MS = 1500;

constexpr auto FILEMANAGER_BUS = "org.freedesktop.FileManager1";
constexpr auto FILEMANAGER_PATH = "/org/freedesktop/FileManager1";
constexpr auto FILEMANAGER_IFACE = "org.freedesktop.FileManager1";

// Leading '/' is absolute, '~' is home-relative; './' and '../' are the only
// relative forms worth honouring, because a bare "Downloads" has to stay an
// application search.
bool looksLikePath(const QString &text) {
    if (text.isEmpty()) {
        return false;
    }
    if (text.startsWith(QLatin1Char('/')) || text.startsWith(QLatin1Char('~'))) {
        return true;
    }
    return text.startsWith(QLatin1String("./")) || text.startsWith(QLatin1String("../"));
}

QString expandHome(const QString &text) {
    const QString home = QDir::homePath();
    if (text == QLatin1String("~") || text.startsWith(QLatin1String("~/"))) {
        return home + text.mid(1);
    }
    // "~user" is deliberately left unexpanded: resolving another account's
    // home needs a passwd lookup, and a half-expanded path is worse than no
    // row at all.
    return text;
}

QString iconNameFor(const QFileInfo &info) {
    if (info.isDir()) {
        // "system-folder" is a KDE 3 name that neither Breeze nor Adwaita
        // ships, so it always missed and the launcher fell back to the
        // name-initial glyph. "folder" exists in both.
        return QStringLiteral("folder");
    }
    const QMimeType type = mimeDatabase().mimeTypeForFile(info);
    QString name = type.iconName();
    if (name.isEmpty()) {
        name = type.genericIconName();
    }
    return name.isEmpty() ? QStringLiteral("text-x-generic") : name;
}

} // namespace

PathProbe::PathProbe(QObject *parent)
    : QObject(parent) {
}

PathProbe::~PathProbe() = default;

QVariantMap PathProbe::classify(const QString &text) const {
    QVariantMap out;
    const QString trimmed = text.trimmed();
    if (!looksLikePath(trimmed)) {
        return out;
    }
    out.insert(QStringLiteral("pathShape"), true);

    // Relative forms are anchored at $HOME, not at the shell's own cwd: the
    // shell may have been autostarted with an arbitrary working directory, and
    // "./x" has to resolve to the same place on every launch.
    QString expanded = expandHome(trimmed);
    if (!expanded.startsWith(QLatin1Char('/'))) {
        expanded = QDir::homePath() + QLatin1Char('/') + expanded;
    }
    // cleanPath collapses "//", resolves "a/b/../c" and drops a trailing slash.
    // Anchoring first also means the value handed to dolphin can never begin
    // with '-', so a file literally named "-rf" cannot be read as a flag.
    const QString abs = QDir::cleanPath(expanded);

    // A fresh QFileInfo per call on purpose: it memoizes its stat, so a
    // long-lived instance would answer with the state of the path as it was
    // half-typed several keystrokes ago.
    const QFileInfo info(abs);
    const bool exists = info.exists();
    out.insert(QStringLiteral("abs"), abs);
    out.insert(QStringLiteral("exists"), exists);
    if (exists) {
        out.insert(QStringLiteral("isDir"), info.isDir());
        out.insert(QStringLiteral("isFile"), info.isFile());
        out.insert(QStringLiteral("parent"), info.absolutePath());
        out.insert(QStringLiteral("iconName"), iconNameFor(info));
    }
    return out;
}

void PathProbe::reveal(const QString &absPath, bool isDir) {
    if (absPath.isEmpty()) {
        return;
    }
    if (!QCoreApplication::instance() || !QDBusConnection::sessionBus().isConnected()) {
        _fallbackToCli(absPath, isDir);
        return;
    }

    QDBusInterface iface(QLatin1String(FILEMANAGER_BUS),
                         QLatin1String(FILEMANAGER_PATH),
                         QLatin1String(FILEMANAGER_IFACE),
                         QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        _fallbackToCli(absPath, isDir);
        return;
    }
    iface.setTimeout(REVEAL_TIMEOUT_MS);

    // ShowFolders opens a directory; ShowItems selects the items inside their
    // own parent folder, which is what "dolphin --select" does.
    const QDBusPendingCall call =
        iface.asyncCall(isDir ? QStringLiteral("ShowFolders") : QStringLiteral("ShowItems"),
                        QVariant::fromValue(QStringList{QUrl::fromLocalFile(absPath).toString()}));
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, absPath, isDir]() {
        watcher->deleteLater();
        const QDBusPendingReply<void> reply = *watcher;
        // Any non-success outcome, timeout included, falls back to the CLI.
        // A duplicate reveal is harmless: the daemon simply navigates again.
        if (reply.isError()) {
            _fallbackToCli(absPath, isDir);
        }
    });
}

void PathProbe::_fallbackToCli(const QString &absPath, bool isDir) const {
    const QStringList args =
        isDir ? QStringList{absPath} : QStringList{QStringLiteral("--select"), absPath};
    QProcess::startDetached(QStringLiteral("dolphin"), args);
}

} // namespace qs::plugins
