#include "SearchIconResolver.hpp"

#include <QStringView>

namespace qs::plugins {

SearchIconResolver::SearchIconResolver() {
    m_cache.reserve(512);

    static const struct { const char *ext; const char *icon; } s_commonIcons[] = {
        {".pdf", "application-pdf"},
        {".png", "image-png"},
        {".jpg", "image-jpeg"},
        {".jpeg", "image-jpeg"},
        {".svg", "image-svg+xml"},
        {".webp", "image-webp"},
        {".gif", "image-gif"},
        {".mp4", "video-mp4"},
        {".mkv", "video-x-matroska"},
        {".webm", "video-webm"},
        {".mp3", "audio-mpeg"},
        {".flac", "audio-flac"},
        {".wav", "audio-wav"},
        {".zip", "application-zip"},
        {".tar", "application-x-tar"},
        {".gz", "application-gzip"},
        {".xz", "application-x-xz"},
        {".7z", "application-x-7z-compressed"},
        {".txt", "text-plain"},
        {".md", "text-markdown"},
        {".json", "application-json"},
        {".yaml", "application-yaml"},
        {".yml", "application-yaml"},
        {".xml", "application-xml"},
        {".html", "text-html"},
        {".css", "text-css"},
        {".js", "text-javascript"},
        {".ts", "application-typescript"},
        {".rs", "text-rust"},
        {".py", "text-x-python"},
        {".cpp", "text-x-c++src"},
        {".c", "text-x-csrc"},
        {".h", "text-x-chdr"},
        {".hpp", "text-x-c++hdr"},
        {".qml", "text-x-qml"},
        {".sh", "text-x-script"},
        {".zsh", "text-x-script"},
        {".bash", "text-x-script"},
        {".desktop", "application-x-desktop"}
    };

    for (const auto &item : s_commonIcons) {
        m_cache.insert(QString::fromUtf8(item.ext), QString::fromUtf8(item.icon));
    }
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
