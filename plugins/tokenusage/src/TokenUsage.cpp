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

bool checkMessageSchema(QSqlDatabase &db) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    if (!query.exec(QStringLiteral("PRAGMA table_info(message)"))) {
        return false;
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
    return hasSessionId && hasTimeCreated && hasData;
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
        " COALESCE(SUM(CAST(json_extract(data,'$.cost') AS REAL)),0),"
        " COUNT(*)"
        " FROM message"
        " WHERE json_valid(data) AND time_created >= ? AND time_created < ?"
        " GROUP BY json_extract(data,'$.modelID')"));
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
        window.messages += query.value(7).toLongLong();
    }
    return true;
}
// One aggregate row per window. User rows carry no tokens or cost, so NULLs
// simply drop out of the sums and no role filter is needed.
bool queryWindow(QSqlDatabase &db, qint64 startMs, qint64 endMs, TokenWindow *out, QString *error) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    query.prepare(QStringLiteral(
        "SELECT"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.input') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.output') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.read') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.cache.write') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.tokens.reasoning') AS INTEGER)),0),"
        " COALESCE(SUM(CAST(json_extract(data,'$.cost') AS REAL)),0),"
        " COUNT(*)"
        " FROM message"
        " WHERE json_valid(data) AND time_created >= ? AND time_created < ?"));
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
    out->messages += query.value(6).toLongLong();
    return true;
}

struct LastNRow {
    qint64 time = 0;
    TokenWindow window;
};

// Most-recent rows regardless of role: user rows contribute zero tokens but
// still count toward messages, matching queryWindow's COUNT(*) semantics.
bool queryLastNRows(QSqlDatabase &db, int n, std::vector<LastNRow> *out, QString *error) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    query.prepare(QStringLiteral(
        "SELECT time_created,"
        " COALESCE(CAST(json_extract(data,'$.tokens.input') AS INTEGER),0),"
        " COALESCE(CAST(json_extract(data,'$.tokens.output') AS INTEGER),0),"
        " COALESCE(CAST(json_extract(data,'$.tokens.cache.read') AS INTEGER),0),"
        " COALESCE(CAST(json_extract(data,'$.tokens.cache.write') AS INTEGER),0),"
        " COALESCE(CAST(json_extract(data,'$.tokens.reasoning') AS INTEGER),0),"
        " COALESCE(CAST(json_extract(data,'$.cost') AS REAL),0)"
        " FROM message"
        " WHERE json_valid(data) ORDER BY time_created DESC LIMIT ?"));
    query.addBindValue(n);
    if (!query.exec()) {
        *error = query.lastError().text();
        return false;
    }
    while (query.next()) {
        LastNRow row;
        row.time = query.value(0).toLongLong();
        row.window.input = query.value(1).toLongLong();
        row.window.output = query.value(2).toLongLong();
        row.window.cacheRead = query.value(3).toLongLong();
        row.window.cacheWrite = query.value(4).toLongLong();
        row.window.reasoning = query.value(5).toLongLong();
        row.window.cost = query.value(6).toDouble();
        row.window.messages = 1;
        out->push_back(row);
    }
    return true;
}

bool collectLastNFromDb(const QString &path,
                        int n,
                        std::vector<LastNRow> *out,
                        QString *error) {
    const QString connectionName = QStringLiteral("tokenusage-lastn-%1").arg(g_connectionCounter.fetchAndAddOrdered(1));
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(path);
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=250"));
        if (!db.open()) {
            *error = db.lastError().text();
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
        const bool ok = checkMessageSchema(db) && checkJsonSupport(db)
            && queryLastNRows(db, n, out, error);
        db.close();
        if (!ok) {
            if (error->isEmpty()) {
                *error = QStringLiteral("Could not read recent messages in %1").arg(path);
            }
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return true;
}

bool collectFromDb(const QString &path,
                   const TokenWindowBounds &bounds,
                   TokenRefreshResult *result,
                   QMap<QString, TokenWindow> *monthModels,
                   QString *error) {
    const QString connectionName = QStringLiteral("tokenusage-%1").arg(g_connectionCounter.fetchAndAddOrdered(1));
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(path);
        // QSQLITE_OPEN_READONLY is a flag (not key=value) documented in Qt SQL:
        // https://doc.qt.io/qt-6/sql-driver.html#qsqlite
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=250"));
        if (!db.open()) {
            *error = db.lastError().text();
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
        if (!checkMessageSchema(db)) {
            *error = QStringLiteral("Unexpected message table layout in %1").arg(path);
            db.close();
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
        if (!checkJsonSupport(db)) {
            *error = QStringLiteral("SQLite JSON functions unavailable");
            db.close();
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
        const bool todayOk = queryWindow(db, bounds.todayStart, bounds.end, &result->today, error);
        const bool weekOk = todayOk && queryWindow(db, bounds.weekStart, bounds.end, &result->week, error);
        const bool monthOk = weekOk && queryWindow(db, bounds.monthStart, bounds.end, &result->month, error);
        const bool modelsOk =
            monthOk && queryModels(db, bounds.monthStart, bounds.end, monthModels, error);
        db.close();
        if (!modelsOk) {
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return true;
}

} // namespace

TokenWindowBounds computeWindowBounds() {
    // Pin calendar math to IST so grouping never depends on the system zone.
    static const QTimeZone ist(QStringLiteral("Asia/Kolkata").toLatin1());
    const QTimeZone zone = ist.isValid() ? ist : QTimeZone::systemTimeZone();
    const QDate today = QDateTime::currentDateTimeUtc().toTimeZone(zone).date();
    auto dayStartMs = [&](const QDate &day) {
        return QDateTime(day, QTime(0, 0), zone).toMSecsSinceEpoch();
    };
    TokenWindowBounds bounds;
    bounds.todayStart = dayStartMs(today);
    bounds.weekStart = dayStartMs(today.addDays(-(today.dayOfWeek() - 1)));
    bounds.monthStart = dayStartMs(QDate(today.year(), today.month(), 1));
    bounds.end = QDateTime::currentMSecsSinceEpoch();
    return bounds;
}

QString refreshedAtIst() {
    static const QTimeZone ist(QStringLiteral("Asia/Kolkata").toLatin1());
    const QTimeZone zone = ist.isValid() ? ist : QTimeZone::systemTimeZone();
    const QDateTime now = QDateTime::currentDateTimeUtc().toTimeZone(zone);
    const QString label = zone.id() == QByteArray("Asia/Kolkata")
        ? QStringLiteral(" IST")
        : QStringLiteral(" ") + QString::fromLatin1(zone.id());
    return now.toString(QStringLiteral("dd MMM yyyy, hh:mm AP")) + label;
}

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

int clampLastN(int n) {
    if (n < 1) {
        return 20;
    }
    if (n > 500) {
        return 500;
    }
    return n;
}

TokenRefreshResult collectTokenUsage(const TokenWindowBounds &bounds, int lastN) {
    TokenRefreshResult result;
    result.lastNRequested = clampLastN(lastN);
    result.dbPaths = discoverOpenCodeDbPaths();
    if (result.dbPaths.isEmpty()) {
        result.error = QStringLiteral("No OpenCode database found");
        return result;
    }
    result.configured = true;

    int readable = 0;
    QString firstError;
    QMap<QString, TokenWindow> monthModels;
    for (const QString &path : result.dbPaths) {
        QString error;
        if (collectFromDb(path, bounds, &result, &monthModels, &error)) {
            ++readable;
        } else if (firstError.isEmpty()) {
            firstError = error;
        }
    }
    if (readable == 0) {
        result.error = firstError.isEmpty() ? QStringLiteral("Could not read OpenCode database") : firstError;
        return result;
    }
    // Global last-N: up to N rows per DB, then merge by timestamp.
    {
        std::vector<LastNRow> all;
        for (const QString &path : result.dbPaths) {
            QString error;
            std::vector<LastNRow> rows;
            if (collectLastNFromDb(path, result.lastNRequested, &rows, &error)) {
                all.insert(all.end(), rows.begin(), rows.end());
            }
        }
        std::sort(all.begin(), all.end(), [](const LastNRow &a, const LastNRow &b) {
            return a.time > b.time;
        });
        if (static_cast<int>(all.size()) > result.lastNRequested) {
            all.resize(result.lastNRequested);
        }
        for (const LastNRow &row : all) {
            result.lastN.input += row.window.input;
            result.lastN.output += row.window.output;
            result.lastN.cacheRead += row.window.cacheRead;
            result.lastN.cacheWrite += row.window.cacheWrite;
            result.lastN.reasoning += row.window.reasoning;
            result.lastN.cost += row.window.cost;
            result.lastN.messages += 1;
        }
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
        item.insert(QStringLiteral("messages"), entry.second.messages);
        models.append(item);
    }
    result.monthModels = models;
    result.ok = true;
    result.refreshedAt = refreshedAtIst();
    return result;
}

TokenUsageWorker::TokenUsageWorker(QObject *parent)
    : QObject(parent) {}

void TokenUsageWorker::refresh(const TokenWindowBounds &bounds, int lastN) {
    emit refreshed(collectTokenUsage(bounds, lastN));
}

QString usageCachePath() {
    QString cacheHome = QString::fromLocal8Bit(qgetenv("XDG_CACHE_HOME")).trimmed();
    if (cacheHome.isEmpty()) {
        cacheHome = QDir::homePath() + QStringLiteral("/.cache");
    }
    return cacheHome + QStringLiteral("/quick-shell/token-usage.json");
}

QJsonObject windowToCache(const TokenWindow &window) {
    QJsonObject object;
    object[QStringLiteral("input")] = window.input;
    object[QStringLiteral("output")] = window.output;
    object[QStringLiteral("cacheRead")] = window.cacheRead;
    object[QStringLiteral("cacheWrite")] = window.cacheWrite;
    object[QStringLiteral("reasoning")] = window.reasoning;
    object[QStringLiteral("cost")] = window.cost;
    object[QStringLiteral("messages")] = window.messages;
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
    window.messages = qlonglong(object.value(QStringLiteral("messages")).toDouble());
    return window;
}

QVariantMap splitMap(const TokenWindow &window);

void TokenUsage::loadCachedResult() {
    QFile file(usageCachePath());
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        return;
    }
    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("version")).toInt() != 1) {
        return;
    }
    m_today = windowFromCache(root.value(QStringLiteral("today")).toObject());
    m_week = windowFromCache(root.value(QStringLiteral("week")).toObject());
    m_month = windowFromCache(root.value(QStringLiteral("month")).toObject());
    m_lastNWindow = windowFromCache(root.value(QStringLiteral("lastN")).toObject());
    m_lastN = root.value(QStringLiteral("lastNRequested")).toInt(20);
    if (m_lastN < 1 || m_lastN > 500) {
        m_lastN = 20;
    }
    m_monthModels = root.value(QStringLiteral("monthModels")).toArray().toVariantList();
    m_todaySplit = splitMap(m_today);
    m_weekSplit = splitMap(m_week);
    m_monthSplit = splitMap(m_month);
    m_lastNSplit = splitMap(m_lastNWindow);
    m_lastRefresh = root.value(QStringLiteral("refreshedAt")).toString();
    m_configured = !m_lastRefresh.isEmpty();
}

void TokenUsage::saveCachedResult(const TokenRefreshResult &result) {
    const int slash = usageCachePath().lastIndexOf(u'/');
    if (slash > 0 && !QDir().mkpath(usageCachePath().left(slash))) {
        return;
    }
    QJsonObject root;
    root[QStringLiteral("version")] = 1;
    root[QStringLiteral("today")] = windowToCache(result.today);
    root[QStringLiteral("week")] = windowToCache(result.week);
    root[QStringLiteral("month")] = windowToCache(result.month);
    root[QStringLiteral("lastN")] = windowToCache(result.lastN);
    root[QStringLiteral("lastNRequested")] = result.lastNRequested;
    root[QStringLiteral("monthModels")] = QJsonArray::fromVariantList(result.monthModels);
    root[QStringLiteral("refreshedAt")] = result.refreshedAt;
    QSaveFile file(usageCachePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    file.commit();
}

QVariantMap splitMap(const TokenWindow &window) {
    QVariantMap map;
    map.insert(QStringLiteral("input"), window.input);
    map.insert(QStringLiteral("output"), window.output);
    map.insert(QStringLiteral("cacheRead"), window.cacheRead);
    map.insert(QStringLiteral("cacheWrite"), window.cacheWrite);
    map.insert(QStringLiteral("reasoning"), window.reasoning);
    return map;
}

TokenUsage::TokenUsage(QObject *parent)
    : QObject(parent) {
    qRegisterMetaType<TokenWindowBounds>();
    qRegisterMetaType<TokenRefreshResult>();
    loadCachedResult();
    m_worker = new TokenUsageWorker();
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &TokenUsage::requestRefresh, m_worker, &TokenUsageWorker::refresh);
    connect(m_worker, &TokenUsageWorker::refreshed, this, &TokenUsage::onRefreshed);
    m_thread.start();
}

TokenUsage::~TokenUsage() {
    m_thread.quit();
    m_thread.wait();
}

void TokenUsage::refresh() {
    if (m_busy) {
        return;
    }
    m_busy = true;
    emit busyChanged();
    emit requestRefresh(computeWindowBounds(), m_lastN);
}

void TokenUsage::setLastN(int n) {
    if (n < 1) {
        n = 1;
    } else if (n > 500) {
        n = 500;
    }
    if (m_lastN == n) {
        return;
    }
    m_lastN = n;
    emit lastNChanged();
    refresh();
}

QString TokenUsage::compact(qlonglong value) const {
    // Two decimals with trailing zeros trimmed: 345760 -> 345.76K,
    // 22500000 -> 22.5M, 1500 -> 1.5K, 999 -> 999.
    auto trim2 = [](double scaled) {
        QString text = QString::number(scaled, 'f', 2);
        while (text.endsWith(u'0')) {
            text.chop(1);
        }
        if (text.endsWith(u'.')) {
            text.chop(1);
        }
        return text;
    };
    const double tokens = static_cast<double>(value);
    if (tokens >= 1e9) {
        return trim2(tokens / 1e9) + QStringLiteral("B");
    }
    if (tokens >= 1e6) {
        return trim2(tokens / 1e6) + QStringLiteral("M");
    }
    if (tokens >= 1e3) {
        return trim2(tokens / 1e3) + QStringLiteral("K");
    }
    return QString::number(value);
}

void TokenUsage::onRefreshed(const TokenRefreshResult &result) {
    m_busy = false;
    m_configured = result.configured;
    m_error = result.error;
    if (result.ok) {
        m_today = result.today;
        m_week = result.week;
        m_month = result.month;
        m_lastNWindow = result.lastN;
        m_monthModels = result.monthModels;
        m_todaySplit = splitMap(result.today);
        m_weekSplit = splitMap(result.week);
        m_monthSplit = splitMap(result.month);
        m_lastNSplit = splitMap(result.lastN);
        m_lastRefresh = result.refreshedAt;
        saveCachedResult(result);
        if (m_lastN != result.lastNRequested) {
            // N changed mid-flight (setLastN while busy dropped its
            // refresh): keep desired N and re-request.
            emit busyChanged();
            emit dataChanged();
            refresh();
            return;
        }
    }
    emit busyChanged();
    emit dataChanged();
}

} // namespace qs::plugins
