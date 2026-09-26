#pragma once

#include "DbusTypes.hpp"

#include <QDateTime>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace qs::updatemanager {

class UpdateItem {
public:
    UpdateItem() = default;

    QString name;
    QString newEvr;
    QString oldEvr;
    QString arch;
    QString summary;
    QString repoId;
    quint64 downloadSize{0};
    quint64 installSize{0};
    QString vendor;

    QString categoryKey; // "kernel", "firmware", "app", "shell", "core", "devel", "other"
    QString category;    // Human-readable
    QString advisoryId;
    QString advisoryType{"general"}; // "security", "bugfix", "enhancement", "general"
    QString severity{"none"};        // "critical", "important", "moderate", "low", "none"
    QString advisoryTitle;
    QString advisoryDescription;
    QStringList cveList;

    bool requiresReboot{false};
    bool requiresSessionRestart{false};

    bool changelogLoaded{false};
    QVariantList changelogList; // List of { "timestamp": ..., "date": "...", "author": "...", "text": "..." }

    [[nodiscard]] QString formattedDownloadSize() const;
    [[nodiscard]] QVariantMap toMap() const;

    static QString classifyCategoryKey(const QString &pkgName, const QString &pkgSummary);
    static QString categoryKeyToLabel(const QString &key);
    static bool evaluateRebootRequired(const QString &pkgName, const QString &catKey);
    static bool evaluateSessionRestartRequired(const QString &pkgName, const QString &catKey);
};

} // namespace qs::updatemanager
