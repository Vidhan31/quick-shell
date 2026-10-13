#include "IconResolver.hpp"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QIcon>
#include <QList>
#include <QReadWriteLock>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStringView>
#include <QTextStream>
#include <QThreadPool>
#include <atomic>

namespace qs::plugins {

namespace {

struct DesktopEntry {
    QString id;
    QString name;
    QString startupWmClass;
    QString exec;
    QString icon;
};

QReadWriteLock s_cacheLock;
QHash<QString, QString> s_iconCache;
QHash<QString, QString> s_namedCache;
QHash<QString, QString> s_stockCache;
QHash<QString, QString> s_xdgCache;

std::atomic<bool> s_indexingStarted{false};
std::atomic<bool> s_desktopIndexed{false};
QHash<QString, DesktopEntry> s_entriesById;
QHash<QString, QString> s_entriesByWmClass;
QHash<QString, QString> s_entriesByName;
QHash<QString, QString> s_entriesByBinary;
QList<DesktopEntry> s_allEntries;

void parseDesktopFile(const QString &filePath,
                      QHash<QString, DesktopEntry> &entriesById,
                      QHash<QString, QString> &entriesByWmClass,
                      QHash<QString, QString> &entriesByName,
                      QHash<QString, QString> &entriesByBinary,
                      QList<DesktopEntry> &allEntries) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }

    QFileInfo fi(filePath);
    QString id = fi.fileName();
    if (id.endsWith(QLatin1String(".desktop"), Qt::CaseInsensitive)) {
        id.chop(8);
    }
    if (id.isEmpty()) {
        return;
    }

    DesktopEntry entry;
    entry.id = id;

    QTextStream stream(&file);
    bool inDesktopEntry = false;

    while (!stream.atEnd()) {
        const QString line = stream.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        if (line.startsWith(QLatin1Char('['))) {
            if (line == QLatin1String("[Desktop Entry]")) {
                inDesktopEntry = true;
            } else if (inDesktopEntry) {
                break;
            }
            continue;
        }
        if (!inDesktopEntry) {
            continue;
        }

        const int eqIdx = line.indexOf(QLatin1Char('='));
        if (eqIdx == -1) {
            continue;
        }

        const QStringView key = QStringView(line).left(eqIdx).trimmed();
        const QStringView val = QStringView(line).mid(eqIdx + 1).trimmed();

        if (key == QLatin1String("Icon") && entry.icon.isEmpty()) {
            entry.icon = val.toString();
        } else if (key == QLatin1String("Name") && entry.name.isEmpty()) {
            entry.name = val.toString();
        } else if (key == QLatin1String("StartupWMClass") && entry.startupWmClass.isEmpty()) {
            entry.startupWmClass = val.toString();
        } else if (key == QLatin1String("Exec") && entry.exec.isEmpty()) {
            entry.exec = val.toString();
        }
    }

    if (entry.icon.isEmpty()) {
        return;
    }

    if (!entriesById.contains(id)) {
        entriesById.insert(id, entry);
    }
    const QString idLower = id.toLower();
    if (!entriesById.contains(idLower)) {
        entriesById.insert(idLower, entry);
    }

    if (!entry.startupWmClass.isEmpty()) {
        const QString wmLower = entry.startupWmClass.toLower();
        if (!entriesByWmClass.contains(wmLower)) {
            entriesByWmClass.insert(wmLower, entry.icon);
        }
    }

    if (!entry.name.isEmpty()) {
        const QString nameLower = entry.name.toLower();
        if (!entriesByName.contains(nameLower)) {
            entriesByName.insert(nameLower, entry.icon);
        }
    }

    if (!entry.exec.isEmpty()) {
        QString binary = entry.exec.section(QLatin1Char(' '), 0, 0);
        const int slash = binary.lastIndexOf(QLatin1Char('/'));
        if (slash != -1) {
            binary = binary.mid(slash + 1);
        }
        binary.remove(QLatin1Char('"'));
        if (!binary.isEmpty()) {
            const QString binLower = binary.toLower();
            if (!entriesByBinary.contains(binLower)) {
                entriesByBinary.insert(binLower, entry.icon);
            }
        }
    }

    allEntries.append(entry);
}

void triggerDesktopIndexLoading() {
    bool expected = false;
    if (!s_indexingStarted.compare_exchange_strong(expected, true)) {
        return;
    }

    QThreadPool::globalInstance()->start([]() {
        QHash<QString, DesktopEntry> localEntriesById;
        QHash<QString, QString> localEntriesByWmClass;
        QHash<QString, QString> localEntriesByName;
        QHash<QString, QString> localEntriesByBinary;
        QList<DesktopEntry> localAllEntries;

        const QStringList appDirs = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
        for (const QString &dirPath : appDirs) {
            if (!QDir(dirPath).exists()) {
                continue;
            }
            QDirIterator it(dirPath, {QStringLiteral("*.desktop")}, QDir::Files, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                it.next();
                parseDesktopFile(it.filePath(), localEntriesById, localEntriesByWmClass, localEntriesByName, localEntriesByBinary, localAllEntries);
            }
        }

        {
            QWriteLocker locker(&s_cacheLock);
            s_entriesById = std::move(localEntriesById);
            s_entriesByWmClass = std::move(localEntriesByWmClass);
            s_entriesByName = std::move(localEntriesByName);
            s_entriesByBinary = std::move(localEntriesByBinary);
            s_allEntries = std::move(localAllEntries);
            s_desktopIndexed.store(true, std::memory_order_release);
        }
    });
}

QString lookupDesktopEntryIcon(const QString &query) {
    if (query.isEmpty()) {
        return QString();
    }

    if (!s_desktopIndexed.load(std::memory_order_acquire)) {
        triggerDesktopIndexLoading();
        return QString();
    }

    QReadLocker locker(&s_cacheLock);

    auto it = s_entriesById.constFind(query);
    if (it != s_entriesById.constEnd() && !it->icon.isEmpty()) {
        return it->icon;
    }

    const QString queryLower = query.toLower();
    it = s_entriesById.constFind(queryLower);
    if (it != s_entriesById.constEnd() && !it->icon.isEmpty()) {
        return it->icon;
    }

    if (query.endsWith(QLatin1String(".desktop"), Qt::CaseInsensitive)) {
        QString stripped = query;
        stripped.chop(8);
        it = s_entriesById.constFind(stripped);
        if (it != s_entriesById.constEnd() && !it->icon.isEmpty()) {
            return it->icon;
        }
        it = s_entriesById.constFind(stripped.toLower());
        if (it != s_entriesById.constEnd() && !it->icon.isEmpty()) {
            return it->icon;
        }
    }

    auto wmIt = s_entriesByWmClass.constFind(queryLower);
    if (wmIt != s_entriesByWmClass.constEnd() && !wmIt->isEmpty()) {
        return *wmIt;
    }

    auto nameIt = s_entriesByName.constFind(queryLower);
    if (nameIt != s_entriesByName.constEnd() && !nameIt->isEmpty()) {
        return *nameIt;
    }

    auto binIt = s_entriesByBinary.constFind(queryLower);
    if (binIt != s_entriesByBinary.constEnd() && !binIt->isEmpty()) {
        return *binIt;
    }

    return QString();
}

QString lookupXdgIconFile(const QString &iconName) {
    if (iconName.isEmpty()) {
        return QString();
    }

    {
        QReadLocker locker(&s_cacheLock);
        auto it = s_xdgCache.constFind(iconName);
        if (it != s_xdgCache.constEnd()) {
            return *it;
        }
    }

    static const QStringList searchRoots = []() {
        QStringList valid;
        const QStringList candidates = {
            QDir::homePath() + QStringLiteral("/.local/share/icons"),
            QStringLiteral("/usr/share/pixmaps"),
            QStringLiteral("/usr/share/icons"),
            QStringLiteral("/usr/local/share/pixmaps"),
            QStringLiteral("/usr/local/share/icons")
        };
        for (const QString &root : candidates) {
            if (QDir(root).exists()) {
                valid.append(root);
            }
        }
        return valid;
    }();

    static const QStringList extensions = {
        QStringLiteral(".svg"),
        QStringLiteral(".png"),
        QStringLiteral(".xpm")
    };

    const bool hasExt = iconName.endsWith(QLatin1String(".png"), Qt::CaseInsensitive)
                     || iconName.endsWith(QLatin1String(".svg"), Qt::CaseInsensitive)
                     || iconName.endsWith(QLatin1String(".xpm"), Qt::CaseInsensitive);

    QString result;
    for (const QString &root : searchRoots) {
        if (hasExt) {
            const QString direct = root + QLatin1Char('/') + iconName;
            if (QFile::exists(direct)) {
                result = direct;
                break;
            }
        } else {
            bool found = false;
            for (const QString &ext : extensions) {
                const QString candidate = root + QLatin1Char('/') + iconName + ext;
                if (QFile::exists(candidate)) {
                    result = candidate;
                    found = true;
                    break;
                }
            }
            if (found) break;

            for (const QString &sub : {QStringLiteral("hicolor/scalable/apps/"),
                                       QStringLiteral("hicolor/48x48/apps/"),
                                       QStringLiteral("hicolor/32x32/apps/")}) {
                for (const QString &ext : extensions) {
                    const QString candidate = root + QLatin1Char('/') + sub + iconName + ext;
                    if (QFile::exists(candidate)) {
                        result = candidate;
                        found = true;
                        break;
                    }
                }
                if (found) break;
            }
            if (found) break;
        }
    }

    {
        QWriteLocker locker(&s_cacheLock);
        s_xdgCache.insert(iconName, result);
    }
    return result;
}

} // namespace

IconResolver::IconResolver(QObject *parent)
    : QObject(parent) {
    triggerDesktopIndexLoading();
    m_appAliases = {
        {QStringLiteral("t3code"), QStringLiteral("t3_code_alpha")},
        {QStringLiteral("brave-origin"), QStringLiteral("brave-origin")},
        {QStringLiteral("brave-browser"), QStringLiteral("brave-browser")},
        {QStringLiteral("org.kde.konsole"), QStringLiteral("utilities-terminal")},
        {QStringLiteral("konsole"), QStringLiteral("utilities-terminal")},
        {QStringLiteral("notify-send"), QStringLiteral("preferences-desktop-notification")},
        {QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("preferences-desktop-notification")},
        {QStringLiteral("org.kde.xwaylandvideobridge"), QStringLiteral("org.kde.xwaylandvideobridge")}
    };
}

QString IconResolver::resolveIcon(const QString &appId, const QString &title) {
    const QString key = appId + QStringLiteral("::") + title;

    {
        QReadLocker locker(&s_cacheLock);
        auto it = s_iconCache.constFind(key);
        if (it != s_iconCache.constEnd()) {
            return *it;
        }
    }

    const QString resolved = doResolve(appId, title);

    {
        QWriteLocker locker(&s_cacheLock);
        s_iconCache.insert(key, resolved);
    }
    return resolved;
}

QString IconResolver::resolveStockIcon(const QString &iconName) {
    if (iconName.isEmpty()) {
        return QString();
    }

    {
        QReadLocker locker(&s_cacheLock);
        auto it = s_stockCache.constFind(iconName);
        if (it != s_stockCache.constEnd()) {
            return *it;
        }
    }

    const QString resolved = doResolveStockIcon(iconName);

    {
        QWriteLocker locker(&s_cacheLock);
        s_stockCache.insert(iconName, resolved);
    }
    return resolved;
}

QString IconResolver::doResolveStockIcon(const QString &iconName) const {
    if (iconName.startsWith(QLatin1Char('/'))) {
        return QStringLiteral("file://") + iconName;
    }
    if (iconName.startsWith(QLatin1String("file://"))) {
        return iconName;
    }

    if (QIcon::hasThemeIcon(iconName)) {
        return QStringLiteral("image://icon/") + iconName;
    }

    const int dotIdx = iconName.lastIndexOf(QLatin1Char('.'));
    if (dotIdx > 0) {
        const QString baseName = iconName.left(dotIdx);
        if (QIcon::hasThemeIcon(baseName)) {
            return QStringLiteral("image://icon/") + baseName;
        }
    }

    const QString xdgPath = lookupXdgIconFile(iconName);
    if (!xdgPath.isEmpty()) {
        return QStringLiteral("file://") + xdgPath;
    }

    return QString();
}

QString IconResolver::resolveNamedOrPath(const QString &iconNameOrPath) {
    if (iconNameOrPath.isEmpty()) {
        return QString();
    }

    {
        QReadLocker locker(&s_cacheLock);
        auto it = s_namedCache.constFind(iconNameOrPath);
        if (it != s_namedCache.constEnd()) {
            return *it;
        }
    }

    const QString resolved = doResolveNamedOrPath(iconNameOrPath);

    {
        QWriteLocker locker(&s_cacheLock);
        s_namedCache.insert(iconNameOrPath, resolved);
    }
    return resolved;
}

QString IconResolver::doResolveNamedOrPath(const QString &iconNameOrPath) {
    const QString clean = iconNameOrPath.startsWith(QLatin1String("file://"))
        ? iconNameOrPath.mid(7)
        : iconNameOrPath;

    if (clean.startsWith(QLatin1String("/app/"))) {
        const int slashIdx = clean.lastIndexOf(QLatin1Char('/'));
        const QString last = (slashIdx == -1) ? clean : clean.mid(slashIdx + 1);
        const int dotIdx = last.lastIndexOf(QLatin1Char('.'));
        const QString baseName = (dotIdx > 0) ? last.left(dotIdx) : last;
        if (!baseName.isEmpty()) {
            const QString stock = resolveStockIcon(baseName);
            if (!stock.isEmpty()) {
                return stock;
            }
        }
        return QString();
    }

    if (iconNameOrPath.startsWith(QLatin1Char('/'))) {
        return QStringLiteral("file://") + iconNameOrPath;
    }
    if (iconNameOrPath.startsWith(QLatin1String("file://"))) {
        return iconNameOrPath;
    }

    return resolveStockIcon(iconNameOrPath);
}

QString IconResolver::fallbackIcon() {
    static const QString cachedFallback = [this]() {
        static const QString candidates[] = {
            QStringLiteral("application-x-executable"),
            QStringLiteral("preferences-system-windows"),
            QStringLiteral("system-run"),
            QStringLiteral("application-default-icon")
        };
        for (const auto &cand : candidates) {
            const QString path = resolveStockIcon(cand);
            if (!path.isEmpty()) {
                return path;
            }
        }
        return QString();
    }();
    return cachedFallback;
}

QString IconResolver::doResolve(const QString &appId, const QString &title) {
    if (appId.isEmpty() && title.isEmpty()) {
        return fallbackIcon();
    }

    const QString alias = !appId.isEmpty() ? m_appAliases.value(appId).toString() : QString();
    if (!alias.isEmpty()) {
        const QString aliasPath = resolveStockIcon(alias);
        if (!aliasPath.isEmpty()) {
            return aliasPath;
        }

        const QString aliasIcon = lookupDesktopEntryIcon(alias);
        if (!aliasIcon.isEmpty()) {
            const QString p = resolveNamedOrPath(aliasIcon);
            if (!p.isEmpty()) {
                return p;
            }
        }
    }

    if (!appId.isEmpty()) {
        const QString directPath = resolveStockIcon(appId);
        if (!directPath.isEmpty()) {
            return directPath;
        }

        const QString lowerAppId = appId.toLower();
        if (lowerAppId != appId) {
            const QString lowerPath = resolveStockIcon(lowerAppId);
            if (!lowerPath.isEmpty()) {
                return lowerPath;
            }
        }

        const QStringList parts = appId.split(QLatin1Char('.'));
        if (parts.size() > 1) {
            const QString lastSegment = parts.last().toLower();
            const QString segPath = resolveStockIcon(lastSegment);
            if (!segPath.isEmpty()) {
                return segPath;
            }
        }
    }

    if (!appId.isEmpty()) {
        QString entryIcon = lookupDesktopEntryIcon(appId);
        if (entryIcon.isEmpty() && appId.contains(QLatin1Char('.'))) {
            const QString lastSegment = appId.split(QLatin1Char('.')).last();
            entryIcon = lookupDesktopEntryIcon(lastSegment);
        }

        if (!entryIcon.isEmpty()) {
            const QString entryIconPath = resolveNamedOrPath(entryIcon);
            if (!entryIconPath.isEmpty()) {
                return entryIconPath;
            }
        }
    }

    if (!title.isEmpty()) {
        QString cleanTitle = title;
        if (cleanTitle.contains(QStringLiteral(" — "))) {
            cleanTitle = cleanTitle.split(QStringLiteral(" — ")).last().trimmed();
        } else if (cleanTitle.contains(QStringLiteral(" - "))) {
            cleanTitle = cleanTitle.split(QStringLiteral(" - ")).last().trimmed();
        }

        QString titleIcon = lookupDesktopEntryIcon(cleanTitle);
        if (titleIcon.isEmpty() && cleanTitle != title) {
            titleIcon = lookupDesktopEntryIcon(title);
        }

        if (!titleIcon.isEmpty()) {
            const QString titlePath = resolveNamedOrPath(titleIcon);
            if (!titlePath.isEmpty()) {
                return titlePath;
            }
        }

        static const QRegularExpression wsRe(QStringLiteral("\\s+"));
        const QString cleanTitleSlug = cleanTitle.toLower().replace(wsRe, QStringLiteral("-"));
        const QString cleanTitleIcon = resolveStockIcon(cleanTitleSlug);
        if (!cleanTitleIcon.isEmpty()) {
            return cleanTitleIcon;
        }
    }

    return fallbackIcon();
}

} // namespace qs::plugins
