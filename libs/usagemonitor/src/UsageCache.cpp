#include "UsageCache.hpp"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace qs::plugins {

QString resolveUsageCachePath(const QString &relativePath) {
    if (relativePath.startsWith(u'/')) {
        return relativePath;
    }
    QString cacheHome = QString::fromLocal8Bit(qgetenv("XDG_CACHE_HOME")).trimmed();
    if (cacheHome.isEmpty()) {
        cacheHome = QDir::homePath() + QStringLiteral("/.cache");
    }
    return cacheHome + QStringLiteral("/") + relativePath;
}

QJsonObject windowToCache(const TokenWindow &window) {
    QJsonObject object;
    object[QStringLiteral("input")] = window.input;
    object[QStringLiteral("output")] = window.output;
    object[QStringLiteral("cacheRead")] = window.cacheRead;
    object[QStringLiteral("cacheWrite")] = window.cacheWrite;
    object[QStringLiteral("reasoning")] = window.reasoning;
    object[QStringLiteral("cost")] = window.cost;
    return object;
}

TokenWindow windowFromCache(const QJsonObject &object) {
    TokenWindow window;
    window.input = qlonglong(object.value(QStringLiteral("input")).toDouble());
    window.output = qlonglong(object.value(QStringLiteral("output")).toDouble());
    window.cacheRead = qlonglong(object.value(QStringLiteral("cacheRead")).toDouble());
    window.cacheWrite = qlonglong(object.value(QStringLiteral("cacheWrite")).toDouble());
    window.reasoning = qlonglong(object.value(QStringLiteral("reasoning")).toDouble());
    window.cost = object.value(QStringLiteral("cost")).toDouble();
    return window;
}

bool loadUsageCache(const QString &filePath, TokenRefreshResult &result) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return false;
    }
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        return false;
    }
    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("version")).toInt() != 4) {
        return false;
    }
    result.today = windowFromCache(root.value(QStringLiteral("today")).toObject());
    result.week = windowFromCache(root.value(QStringLiteral("week")).toObject());
    result.month = windowFromCache(root.value(QStringLiteral("month")).toObject());
    result.lastDays = windowFromCache(root.value(QStringLiteral("lastDays")).toObject());
    result.allTime = windowFromCache(root.value(QStringLiteral("allTime")).toObject());
    result.lastDaysRequested = root.value(QStringLiteral("lastDaysRequested")).toInt(30);
    if (result.lastDaysRequested < 1 || result.lastDaysRequested > 400) {
        result.lastDaysRequested = 30;
    }
    result.monthModels = root.value(QStringLiteral("monthModels")).toArray().toVariantList();
    result.allModels = root.value(QStringLiteral("allModels")).toArray().toVariantList();
    result.monthSources = root.value(QStringLiteral("monthSources")).toArray().toVariantList();
    result.dailyUsage = root.value(QStringLiteral("dailyUsage")).toArray().toVariantList();
    result.refreshedAt = root.value(QStringLiteral("refreshedAt")).toString();
    result.configured = !result.refreshedAt.isEmpty();
    result.ok = true;
    return true;
}

bool saveUsageCache(const QString &filePath, const TokenRefreshResult &result) {
    const int slash = filePath.lastIndexOf(u'/');
    if (slash > 0 && !QDir().mkpath(filePath.left(slash))) {
        return false;
    }
    QJsonObject root;
    root[QStringLiteral("version")] = 4;
    root[QStringLiteral("today")] = windowToCache(result.today);
    root[QStringLiteral("week")] = windowToCache(result.week);
    root[QStringLiteral("month")] = windowToCache(result.month);
    root[QStringLiteral("lastDays")] = windowToCache(result.lastDays);
    root[QStringLiteral("allTime")] = windowToCache(result.allTime);
    root[QStringLiteral("lastDaysRequested")] = result.lastDaysRequested;
    root[QStringLiteral("monthModels")] = QJsonArray::fromVariantList(result.monthModels);
    root[QStringLiteral("allModels")] = QJsonArray::fromVariantList(result.allModels);
    if (!result.monthSources.isEmpty()) {
        root[QStringLiteral("monthSources")] = QJsonArray::fromVariantList(result.monthSources);
    }
    root[QStringLiteral("dailyUsage")] = QJsonArray::fromVariantList(result.dailyUsage);
    root[QStringLiteral("refreshedAt")] = result.refreshedAt;
    QSaveFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    return file.commit();
}

} // namespace qs::plugins
