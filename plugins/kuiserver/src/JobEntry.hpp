#pragma once

#include <QDateTime>
#include <QString>
#include <QUrl>
#include <QVariantMap>

namespace qs::plugins::kuiserver {

enum class JobState {
    Running = 0,
    Suspended = 1,
    Stopped = 2
};

struct JobEntry {
    uint id = 0;
    QString desktopEntry;
    QString appName;
    QString appIcon;
    QString title;
    QString infoMessage;
    QString descriptionLabel1;
    QString descriptionValue1;
    QString descriptionLabel2;
    QString descriptionValue2;
    uint percent = 0;
    quint64 speed = 0;
    quint64 processedBytes = 0;
    quint64 totalBytes = 0;
    quint64 processedFiles = 0;
    quint64 totalFiles = 0;
    quint64 processedItems = 0;
    quint64 totalItems = 0;
    quint64 processedDirectories = 0;
    quint64 totalDirectories = 0;
    QUrl destUrl;
    bool suspended = false;
    bool killable = true;
    bool suspendable = true;
    bool transient = false;
    JobState state = JobState::Running;
    uint errorCode = 0;
    QString errorMessage;
    qint64 startTime = 0;
    qint64 endTime = 0;

    static QString formatBytes(quint64 bytes) {
        constexpr quint64 kb = 1024ULL;
        constexpr quint64 mb = 1024ULL * 1024ULL;
        constexpr quint64 gb = 1024ULL * 1024ULL * 1024ULL;
        constexpr quint64 tb = 1024ULL * 1024ULL * 1024ULL * 1024ULL;

        if (bytes >= tb) {
            return QString::asprintf("%.2f TB", static_cast<double>(bytes) / static_cast<double>(tb));
        }
        if (bytes >= gb) {
            return QString::asprintf("%.2f GB", static_cast<double>(bytes) / static_cast<double>(gb));
        }
        if (bytes >= mb) {
            return QString::asprintf("%.1f MB", static_cast<double>(bytes) / static_cast<double>(mb));
        }
        if (bytes >= kb) {
            return QString::asprintf("%.1f KB", static_cast<double>(bytes) / static_cast<double>(kb));
        }
        return QString::asprintf("%llu B", static_cast<unsigned long long>(bytes));
    }

    static QString formatSpeed(quint64 bytesPerSec) {
        if (bytesPerSec == 0) {
            return QStringLiteral("0 B/s");
        }
        return formatBytes(bytesPerSec) + QStringLiteral("/s");
    }

    static QString formatEta(quint64 processed, quint64 total, quint64 speed) {
        if (speed == 0 || total <= processed) {
            return QString();
        }
        const quint64 remainingBytes = total - processed;
        const quint64 remainingSeconds = remainingBytes / speed;

        if (remainingSeconds < 60) {
            return QString::asprintf("%llus left", static_cast<unsigned long long>(remainingSeconds));
        }
        if (remainingSeconds < 3600) {
            const quint64 mins = remainingSeconds / 60;
            const quint64 secs = remainingSeconds % 60;
            return QString::asprintf("%llum %llus left", static_cast<unsigned long long>(mins), static_cast<unsigned long long>(secs));
        }
        const quint64 hours = remainingSeconds / 3600;
        const quint64 mins = (remainingSeconds % 3600) / 60;
        return QString::asprintf("%lluh %llum left", static_cast<unsigned long long>(hours), static_cast<unsigned long long>(mins));
    }

    [[nodiscard]] QVariantMap toMap() const {
        QString summary = title;
        if (summary.isEmpty()) {
            summary = appName.isEmpty() ? QStringLiteral("Task Progress") : appName;
        }

        QString body = infoMessage;
        if (body.isEmpty()) {
            if (!descriptionValue1.isEmpty()) {
                body = descriptionValue1;
                if (!descriptionValue2.isEmpty()) {
                    body += QStringLiteral(" → ") + descriptionValue2;
                }
            } else if (totalFiles > 1) {
                body = QString::asprintf("%llu of %llu files",
                                         static_cast<unsigned long long>(processedFiles),
                                         static_cast<unsigned long long>(totalFiles));
            }
        }

        QString progressDetails;
        if (totalBytes > 0) {
            progressDetails = formatBytes(processedBytes) + QStringLiteral(" / ") + formatBytes(totalBytes);
        } else if (totalFiles > 0) {
            progressDetails = QString::asprintf("%llu / %llu files",
                                                static_cast<unsigned long long>(processedFiles),
                                                static_cast<unsigned long long>(totalFiles));
        }

        return {
            {QStringLiteral("id"), id},
            {QStringLiteral("desktopEntry"), desktopEntry},
            {QStringLiteral("appName"), appName},
            {QStringLiteral("appIcon"), appIcon},
            {QStringLiteral("title"), title},
            {QStringLiteral("summary"), summary},
            {QStringLiteral("body"), body},
            {QStringLiteral("infoMessage"), infoMessage},
            {QStringLiteral("descriptionLabel1"), descriptionLabel1},
            {QStringLiteral("descriptionValue1"), descriptionValue1},
            {QStringLiteral("descriptionLabel2"), descriptionLabel2},
            {QStringLiteral("descriptionValue2"), descriptionValue2},
            {QStringLiteral("percent"), percent},
            {QStringLiteral("speed"), speed},
            {QStringLiteral("formattedSpeed"), formatSpeed(speed)},
            {QStringLiteral("processedBytes"), processedBytes},
            {QStringLiteral("totalBytes"), totalBytes},
            {QStringLiteral("formattedBytes"), progressDetails},
            {QStringLiteral("processedFiles"), processedFiles},
            {QStringLiteral("totalFiles"), totalFiles},
            {QStringLiteral("destUrl"), destUrl.toString()},
            {QStringLiteral("destPath"), destUrl.isLocalFile() ? destUrl.toLocalFile() : destUrl.path()},
            {QStringLiteral("suspended"), suspended},
            {QStringLiteral("killable"), killable},
            {QStringLiteral("suspendable"), suspendable},
            {QStringLiteral("state"), static_cast<int>(state)},
            {QStringLiteral("isRunning"), state == JobState::Running},
            {QStringLiteral("isSuspended"), state == JobState::Suspended},
            {QStringLiteral("isStopped"), state == JobState::Stopped},
            {QStringLiteral("errorCode"), errorCode},
            {QStringLiteral("errorMessage"), errorMessage},
            {QStringLiteral("eta"), formatEta(processedBytes, totalBytes, speed)},
            {QStringLiteral("startTime"), startTime},
            {QStringLiteral("endTime"), endTime}
        };
    }
};

} // namespace qs::plugins::kuiserver
