#include "TokenUsage.hpp"

#include <QAtomicInteger>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTimeZone>
#include <QVariant>
#include <algorithm>
#include <utility>
#include <vector>

namespace qs::plugins {

namespace {

QAtomicInteger<int> g_connectionCounter = 0;

// Matches opencode.db and opencode-<channel>.db, never WAL/SHM sidecars.
const QRegularExpression kDbNamePattern(QStringLiteral("^opencode(?:-[A-Za-z0-9._-]+)?\\.db$"));

QString openCodeDataDir() {
    const QString xdg = QString::fromLocal8Bit(qgetenv("XDG_DATA_HOME")).trimmed();
    const QString base = xdg.isEmpty() ? QDir::homePath() + QStringLiteral("/.local/share") : xdg;
    return base + QStringLiteral("/opencode");
}

bool checkMessageSchema(QSqlDatabase &db, QString &tableName) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    for (const char *tbl : {"message", "session_message"}) {
        if (!query.exec(QStringLiteral("PRAGMA table_info(%1)").arg(QLatin1String(tbl)))) {
            continue;
        }
        bool hasSessionId = false;
        bool hasTimeCreated = false;
        bool hasData = false;
        while (query.next()) {
            const QString name = query.value(1).toString();
            if (name == QStringLiteral("session_id")) {
                hasSessionId = true;
            } else if (name == QStringLiteral("time_created")) {
                hasTimeCreated = true;
            } else if (name == QStringLiteral("data")) {
                hasData = true;
            }
        }
        if (hasSessionId && hasTimeCreated && hasData) {
            tableName = QLatin1String(tbl);
            return true;
        }
    }
    return false;
}

bool checkJsonSupport(QSqlDatabase &db) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    if (!query.exec(QStringLiteral("SELECT json_extract('{\"a\":1}','$.a')"))) {
        return false;
    }
    return query.next() && query.value(0).toInt() == 1;
}

// Per-model sums for one window. Zero-token models (plain user rows with
// no model recorded) are skipped by the caller.
bool queryModels(QSqlDatabase &db,
                 const QString &tableName,
                 qint64 startMs,
                 qint64 endMs,
                 QMap<QString, TokenWindow> *out,
                 QString *error) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    query.prepare(QStringLiteral(
        "SELECT json_extract(data,'$.modelID'),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.input') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.output') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.read') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.write') AS INTEGER)),0),"
         " COALESCE(SUM(CAST(json_extract(data,'$.tokens.reasoning') AS INTEGER)),0),"
         " COALESCE(SUM(CAST(json_extract(data,'$.cost') AS REAL)),0)"
         " FROM %1"
         " WHERE json_valid(data) AND time_created >= ? AND time_created < ?"
         " GROUP BY json_extract(data,'$.modelID')").arg(tableName));
    query.addBindValue(startMs);
    query.addBindValue(endMs);
    if (!query.exec()) {
        *error = query.lastError().text();
        return false;
    }
    while (query.next()) {
        QString name = query.value(0).toString().trimmed();
        if (name.isEmpty()) {
            name = QStringLiteral("(unknown)");
        }
        TokenWindow &window = (*out)[name];
        window.input += query.value(1).toLongLong();
        window.output += query.value(2).toLongLong();
        window.cacheRead += query.value(3).toLongLong();
        window.cacheWrite += query.value(4).toLongLong();
        window.reasoning += query.value(5).toLongLong();
        window.cost += query.value(6).toDouble();
    }
    return true;
}
bool queryWindow(QSqlDatabase &db, const QString &tableName, qint64 startMs, qint64 endMs, TokenWindow *out, QString *error) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    query.prepare(QStringLiteral(
        "SELECT"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.input') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.output') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.read') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.write') AS INTEGER)),0),"
         " COALESCE(SUM(CAST(json_extract(data,'$.tokens.reasoning') AS INTEGER)),0),"
         " COALESCE(SUM(CAST(json_extract(data,'$.cost') AS REAL)),0)"
         " FROM %1"
         " WHERE json_valid(data) AND time_created >= ? AND time_created < ?").arg(tableName));
    query.addBindValue(startMs);
    query.addBindValue(endMs);
    if (!query.exec()) {
        *error = query.lastError().text();
        return false;
    }
    if (!query.next()) {
        *error = QStringLiteral("Aggregate query returned no rows");
        return false;
    }
    out->input += query.value(0).toLongLong();
    out->output += query.value(1).toLongLong();
    out->cacheRead += query.value(2).toLongLong();
    out->cacheWrite += query.value(3).toLongLong();
    out->reasoning += query.value(4).toLongLong();
    out->cost += query.value(5).toDouble();
    return true;
}

bool queryDaily(QSqlDatabase &db,
                const QString &tableName,
                qint64 startMs,
                qint64 endMs,
                const QString &tzModifier,
                QMap<QString, TokenWindow> *out,
                QString *error) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    const QString sql = QStringLiteral(
        "SELECT strftime('%Y-%m-%d', time_created / 1000, 'unixepoch', '%1') AS day,"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.input') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.output') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.read') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.write') AS INTEGER)),0),"
         " COALESCE(SUM(CAST(json_extract(data,'$.tokens.reasoning') AS INTEGER)),0),"
         " COALESCE(SUM(CAST(json_extract(data,'$.cost') AS REAL)),0)"
         " FROM %2"
         " WHERE json_valid(data) AND time_created >= ? AND time_created < ?"
         " GROUP BY day").arg(tzModifier, tableName);
    query.prepare(sql);
    query.addBindValue(startMs);
    query.addBindValue(endMs);
    if (!query.exec()) {
        *error = query.lastError().text();
        return false;
    }
    while (query.next()) {
        const QString day = query.value(0).toString();
        if (day.isEmpty()) {
            continue;
        }
        TokenWindow &window = (*out)[day];
        window.input += query.value(1).toLongLong();
        window.output += query.value(2).toLongLong();
        window.cacheRead += query.value(3).toLongLong();
        window.cacheWrite += query.value(4).toLongLong();
        window.reasoning += query.value(5).toLongLong();
        window.cost += query.value(6).toDouble();
    }
    return true;
}

bool collectFromDb(const QString &path,
                   const TokenWindowBounds &bounds,
                   qint64 dailyStartMs,
                   const QString &tzModifier,
                   TokenRefreshResult *result,
                   QMap<QString, TokenWindow> *monthModels,
                   QMap<QString, TokenWindow> *allModels,
                   QMap<QString, TokenWindow> *dailyMap,
                   QString *error) {
    const QString connectionName = QStringLiteral("tokenusage-%1").arg(g_connectionCounter.fetchAndAddOrdered(1));
    bool ok = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(path);
        // QSQLITE_OPEN_READONLY is a flag (not key=value) documented in Qt SQL:
        // https://doc.qt.io/qt-6/sql-driver.html#qsqlite
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=250"));
        if (!db.open()) {
            *error = db.lastError().text();
        } else {
            QString tableName;
            if (!checkMessageSchema(db, tableName)) {
                *error = QStringLiteral("Unexpected message table layout in %1").arg(path);
            } else if (!checkJsonSupport(db)) {
                *error = QStringLiteral("SQLite JSON functions unavailable");
            } else {
                const bool todayOk = queryWindow(db, tableName, bounds.todayStart, bounds.end, &result->today, error);
                const bool weekOk = todayOk && queryWindow(db, tableName, bounds.weekStart, bounds.end, &result->week, error);
                const bool monthOk = weekOk && queryWindow(db, tableName, bounds.monthStart, bounds.end, &result->month, error);
                const bool lastDaysOk = monthOk && queryWindow(db, tableName, bounds.lastDaysStart, bounds.end, &result->lastDays, error);
                const bool allTimeOk = lastDaysOk && queryWindow(db, tableName, 0, bounds.end, &result->allTime, error);
                const bool modelsOk =
                    allTimeOk && queryModels(db, tableName, bounds.lastDaysStart, bounds.end, monthModels, error);
                const bool allModelsOk =
                    modelsOk && queryModels(db, tableName, 0, bounds.end, allModels, error);
                ok = allModelsOk && queryDaily(db, tableName, dailyStartMs, bounds.end, tzModifier, dailyMap, error);
            }
            db.close();
        }
    }
    // Must run after the QSqlDatabase above is destroyed: Qt warns and leaves the
    // connection disabled while any handle still references it.
    QSqlDatabase::removeDatabase(connectionName);
    return ok;
}

} // namespace

QStringList discoverOpenCodeDbPaths() {
    const QString override = QString::fromLocal8Bit(qgetenv("OPENCODE_DB")).trimmed();
    if (!override.isEmpty()) {
        const QFileInfo info(override);
        if (info.isFile()) {
            return {info.absoluteFilePath()};
        }
    }
    const QDir dir(openCodeDataDir());
    if (!dir.exists()) {
        return {};
    }
    QStringList paths;
    const QStringList entries = dir.entryList(QDir::Files, QDir::Name);
    for (const QString &entry : entries) {
        if (kDbNamePattern.match(entry).hasMatch()) {
            paths.append(dir.absoluteFilePath(entry));
        }
    }
    return paths;
}

int clampLastDays(int days) {
    if (days < 1) {
        return 30;
    }
    if (days > 400) {
        return 400;
    }
    return days;
}

TokenRefreshResult collectTokenUsage(const TokenWindowBounds &bounds, int lastDays) {
    TokenRefreshResult result;
    result.lastDaysRequested = clampLastDays(lastDays);
    TokenWindowBounds rollingBounds = bounds;
    rollingBounds.lastDaysStart =
        bounds.end - qint64(result.lastDaysRequested) * 24 * 60 * 60 * 1000;
    result.dbPaths = discoverOpenCodeDbPaths();
    if (result.dbPaths.isEmpty()) {
        result.error = QStringLiteral("No OpenCode database found");
        return result;
    }
    result.configured = true;

    static const QTimeZone ist(QStringLiteral("Asia/Kolkata").toLatin1());
    const QTimeZone zone = ist.isValid() ? ist : QTimeZone::systemTimeZone();
    const QDateTime now = QDateTime::currentDateTimeUtc().toTimeZone(zone);
    const QDate today = now.date();
    const int offsetSec = zone.offsetFromUtc(now);
    const QString tzModifier = QStringLiteral("%1%2 seconds")
        .arg(offsetSec >= 0 ? QStringLiteral("+") : QStringLiteral("-"))
        .arg(qAbs(offsetSec));

    const QDate rangeStartDay = today.addDays(-(result.lastDaysRequested - 1));
    const qint64 dailyStartMs = QDateTime(rangeStartDay, QTime(0, 0), zone).toMSecsSinceEpoch();

    int readable = 0;
    QString firstError;
    QMap<QString, TokenWindow> monthModels;
    QMap<QString, TokenWindow> allModels;
    QMap<QString, TokenWindow> dailyMap;
    for (const QString &path : result.dbPaths) {
        QString error;
        if (collectFromDb(path, rollingBounds, dailyStartMs, tzModifier, &result, &monthModels, &allModels, &dailyMap, &error)) {
            ++readable;
        } else if (firstError.isEmpty()) {
            firstError = error;
        }
    }
    if (readable == 0) {
        result.error = firstError.isEmpty() ? QStringLiteral("Could not read OpenCode database") : firstError;
        return result;
    }
    // Month models for the UI, largest first, capped.
    std::vector<std::pair<QString, TokenWindow>> ranked(monthModels.keyValueBegin(), monthModels.keyValueEnd());
    ranked.erase(std::remove_if(ranked.begin(),
                                ranked.end(),
                                [](const auto &entry) { return entry.second.total() <= 0; }),
                 ranked.end());
    std::sort(ranked.begin(), ranked.end(), [](const auto &left, const auto &right) {
        return left.second.total() > right.second.total();
    });
    if (ranked.size() > 8) {
        ranked.resize(8);
    }
    QVariantList models;
    for (const auto &entry : ranked) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), entry.first);
        item.insert(QStringLiteral("tokens"), entry.second.total());
        item.insert(QStringLiteral("input"), entry.second.input);
        item.insert(QStringLiteral("output"), entry.second.output);
        item.insert(QStringLiteral("cacheRead"), entry.second.cacheRead);
        item.insert(QStringLiteral("cacheWrite"), entry.second.cacheWrite);
        item.insert(QStringLiteral("reasoning"), entry.second.reasoning);
        item.insert(QStringLiteral("cost"), entry.second.cost);
        models.append(item);
    }
    result.monthModels = models;
    std::vector<std::pair<QString, TokenWindow>> rankedAll(allModels.keyValueBegin(), allModels.keyValueEnd());
    rankedAll.erase(std::remove_if(rankedAll.begin(),
                                   rankedAll.end(),
                                   [](const auto &entry) { return entry.second.total() <= 0; }),
                    rankedAll.end());
    std::sort(rankedAll.begin(), rankedAll.end(), [](const auto &left, const auto &right) {
        return left.second.total() > right.second.total();
    });
    QVariantList allModelList;
    for (const auto &entry : rankedAll) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), entry.first);
        item.insert(QStringLiteral("tokens"), entry.second.total());
        item.insert(QStringLiteral("input"), entry.second.input);
        item.insert(QStringLiteral("output"), entry.second.output);
        item.insert(QStringLiteral("cacheRead"), entry.second.cacheRead);
        item.insert(QStringLiteral("cacheWrite"), entry.second.cacheWrite);
        item.insert(QStringLiteral("reasoning"), entry.second.reasoning);
        item.insert(QStringLiteral("cost"), entry.second.cost);
        allModelList.append(item);
    }
    result.allModels = allModelList;

    QVariantList dailyList;
    for (int d = 0; d < result.lastDaysRequested; ++d) {
        const QDate day = rangeStartDay.addDays(d);
        const QString dayKey = day.toString(QStringLiteral("yyyy-MM-dd"));
        const TokenWindow window = dailyMap.value(dayKey);
        QVariantMap point;
        point.insert(QStringLiteral("date"), dayKey);
        point.insert(QStringLiteral("label"), day.toString(QStringLiteral("d MMM")));
        point.insert(QStringLiteral("weekday"), day.toString(QStringLiteral("ddd")));
        point.insert(QStringLiteral("dayNumber"), day.day());
        point.insert(QStringLiteral("tokens"), window.total());
        point.insert(QStringLiteral("input"), window.input);
        point.insert(QStringLiteral("output"), window.output);
        point.insert(QStringLiteral("cacheRead"), window.cacheRead);
        point.insert(QStringLiteral("cacheWrite"), window.cacheWrite);
        point.insert(QStringLiteral("reasoning"), window.reasoning);
        point.insert(QStringLiteral("cost"), window.cost);
        dailyList.append(point);
    }
    result.dailyUsage = dailyList;

    result.ok = true;
    result.refreshedAt = refreshedAtIst();
    return result;
}

TokenUsage::TokenUsage(QObject *parent)
    : UsageMonitorBase(QStringLiteral("quick-shell/token-usage.json"),
                       &collectTokenUsage,
                       parent) {}

} // namespace qs::plugins
