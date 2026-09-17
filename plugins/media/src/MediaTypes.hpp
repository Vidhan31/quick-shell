#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <cmath>

namespace qs::plugins::media {

Q_NAMESPACE

enum class PlaybackState {
    Stopped = 0,
    Paused = 1,
    Playing = 2
};
Q_ENUM_NS(PlaybackState)

enum class LoopState {
    None = 0,
    Track = 1,
    Playlist = 2
};
Q_ENUM_NS(LoopState)

inline QString formatSeconds(double sec) {
    if (!std::isfinite(sec) || sec <= 0.0) {
        return QStringLiteral("0:00");
    }
    const qint64 total = static_cast<qint64>(std::floor(sec));
    const qint64 hrs = total / 3600;
    const qint64 mins = (total % 3600) / 60;
    const qint64 secs = total % 60;

    const QString secsStr = (secs < 10) ? (QStringLiteral("0") + QString::number(secs)) : QString::number(secs);

    if (hrs > 0) {
        const QString minsStr = (mins < 10) ? (QStringLiteral("0") + QString::number(mins)) : QString::number(mins);
        return QString::number(hrs) + QStringLiteral(":") + minsStr + QStringLiteral(":") + secsStr;
    }
    return QString::number(mins) + QStringLiteral(":") + secsStr;
}

inline QString formatArtUrl(const QString &url) {
    if (url.isEmpty()) {
        return QString();
    }
    if (url.startsWith(QLatin1String("/")) && !url.startsWith(QLatin1String("//"))) {
        return QStringLiteral("file://") + url;
    }
    return url;
}

} // namespace qs::plugins::media
