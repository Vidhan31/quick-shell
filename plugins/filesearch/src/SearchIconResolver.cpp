#include "SearchIconResolver.hpp"

#include <QStringView>

namespace qs::plugins {

SearchIconResolver::SearchIconResolver() {
    m_cache.reserve(512);
}

QString SearchIconResolver::resolve(const QString &filePath, bool isDir) {
    if (isDir) {
        return QStringLiteral("folder");
    }

    const QStringView pathView(filePath);
    const qsizetype slashIdx = pathView.lastIndexOf(u'/');
    const QStringView fileName = (slashIdx == -1) ? pathView : pathView.sliced(slashIdx + 1);

    if (fileName.isEmpty()) {
        return QStringLiteral("text-x-generic");
    }

    const qsizetype dotIdx = fileName.lastIndexOf(u'.');
    const QString cacheKey = (dotIdx != -1 && dotIdx != fileName.size() - 1)
        ? fileName.sliced(dotIdx).toString().toLower()
        : fileName.toString().toLower();

    {
        QReadLocker locker(&m_lock);
        auto it = m_cache.constFind(cacheKey);
        if (it != m_cache.constEnd()) {
            return *it;
        }
    }

    QMimeType mime = m_mimeDb.mimeTypeForFile(filePath, QMimeDatabase::MatchExtension);
    QString icon = mime.iconName();
    if (icon.isEmpty() || icon == u"application-octet-stream") {
        QString generic = mime.genericIconName();
        if (!generic.isEmpty()) {
            icon = generic;
        }
    }

    if (icon.isEmpty()) {
        icon = QStringLiteral("text-x-generic");
    }

    {
        QWriteLocker locker(&m_lock);
        m_cache.insert(cacheKey, icon);
    }

    return icon;
}

} // namespace qs::plugins
