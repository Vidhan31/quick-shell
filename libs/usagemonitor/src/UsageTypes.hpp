#pragma once

#include <QDateTime>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QTimeZone>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

namespace qs::plugins {

struct TokenWindow {
    qlonglong input = 0;
    qlonglong output = 0;
    qlonglong cacheRead = 0;
    qlonglong cacheWrite = 0;
    qlonglong reasoning = 0;
    double cost = 0.0;

    [[nodiscard]] qlonglong total() const {
        return input + output + cacheRead + cacheWrite;
    }
};

struct TokenWindowBounds {
    qint64 todayStart = 0;
    qint64 weekStart = 0;
    qint64 monthStart = 0;
    qint64 end = 0;
    qint64 lastDaysStart = 0;
};

struct TokenRefreshResult {
    bool ok = false;
    bool configured = false;
    QString error;
    QStringList paths;
    QStringList dbPaths;
    QStringList roots;
    qlonglong filesScanned = 0;
    qlonglong rowsSkipped = 0;
    TokenWindow today;
    TokenWindow week;
    TokenWindow month;
    TokenWindow lastDays;
    TokenWindow allTime;
    int lastDaysRequested = 10;
    QString refreshedAt;
    QVariantList monthModels;
    QVariantList allModels;
    QVariantList monthSources;
    QVariantList dailyUsage;
};

TokenWindowBounds computeWindowBounds();
QString refreshedAtIst();
QVariantMap splitMap(const TokenWindow &window);

using AgTokenWindow = TokenWindow;
using AgWindowBounds = TokenWindowBounds;
using AgRefreshResult = TokenRefreshResult;

inline AgWindowBounds computeAgWindowBounds() { return computeWindowBounds(); }
inline QString agRefreshedAtIst() { return refreshedAtIst(); }
inline QVariantMap agSplitMap(const AgTokenWindow &window) { return splitMap(window); }

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::TokenWindowBounds)
Q_DECLARE_METATYPE(qs::plugins::TokenRefreshResult)
