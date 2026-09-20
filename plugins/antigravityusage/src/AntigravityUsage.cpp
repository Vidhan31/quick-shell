#include "AntigravityUsage.hpp"

#include <QAtomicInteger>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTimeZone>
#include <QVariant>
#include <algorithm>
#include <cstdint>
#include <utility>
#include <vector>

namespace qs::plugins {

namespace {

// ---------------------------------------------------------------------------
// Minimal protobuf wire reader. Only what gen_metadata blobs need: varints
// and length-delimited fields. Every read is bounds checked; anything
// malformed fails the row instead of the scan.
// ---------------------------------------------------------------------------

struct ProtoField {
    uint32_t id = 0;
    uint8_t wire = 0;
    quint64 varint = 0;
    QByteArray bytes;
};

bool readVarint(const QByteArray &buf, int &pos, quint64 &out) {
    quint64 result = 0;
    int shift = 0;
    while (pos < buf.size()) {
        const uint8_t byte = static_cast<uint8_t>(buf.at(pos++));
        if (shift >= 64) {
            return false;
        }
        result |= static_cast<quint64>(byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) {
            out = result;
            return true;
        }
        shift += 7;
    }
    return false;
}

bool parseMessage(const QByteArray &buf, std::vector<ProtoField> &out) {
    int pos = 0;
    while (pos < buf.size()) {
        quint64 key = 0;
        if (!readVarint(buf, pos, key)) {
            return false;
        }
        ProtoField field;
        field.id = static_cast<uint32_t>(key >> 3);
        field.wire = static_cast<uint8_t>(key & 0x07);
        if (field.id == 0) {
            return false;
        }
        if (field.wire == 0) {
            if (!readVarint(buf, pos, field.varint)) {
                return false;
            }
        } else if (field.wire == 2) {
            quint64 length = 0;
            if (!readVarint(buf, pos, length)) {
                return false;
            }
            if (length > static_cast<quint64>(buf.size() - pos)) {
                return false;
            }
            field.bytes = buf.mid(pos, static_cast<qsizetype>(length));
            pos += static_cast<int>(length);
        } else if (field.wire == 5) {
            if (pos + 4 > buf.size()) {
                return false;
            }
            pos += 4;
        } else if (field.wire == 1) {
            if (pos + 8 > buf.size()) {
                return false;
            }
            pos += 8;
        } else {
            return false;
        }
        out.push_back(std::move(field));
    }
    return true;
}

const ProtoField *findField(const std::vector<ProtoField> &fields, uint32_t id, uint8_t wire) {
    for (const ProtoField &field : fields) {
        if (field.id == id && field.wire == wire) {
            return &field;
        }
    }
    return nullptr;
}

quint64 fieldVarint(const std::vector<ProtoField> &fields, uint32_t id) {
    const ProtoField *field = findField(fields, id, 0);
    return field ? field->varint : 0;
}

// Model ids are derived from the blob itself. Field #19 of the inner message
// carries the plain model string; older or placeholder rows fall back to a
// generic pattern scan so no model list is ever hardcoded.
QString fallbackModel(const QByteArray &blob) {
    static const QRegularExpression pattern(
        QStringLiteral("(gemini-[A-Za-z0-9_.\\-]+|MODEL_[A-Z0-9_]+)"));
    const QString text = QString::fromUtf8(blob);
    const QRegularExpressionMatch match = pattern.match(text);
    if (match.hasMatch()) {
        return match.captured(1).trimmed();
    }
    return {};
}

struct AgTurn {
    qlonglong input = 0;
    qlonglong cacheRead = 0;
    qlonglong output = 0;
    qlonglong reasoning = 0;
    QString responseId;
    QString model;
};

bool extractTurn(const QByteArray &data, AgTurn &turn) {
    std::vector<ProtoField> top;
    if (!parseMessage(data, top)) {
        return false;
    }
    const ProtoField *outer = findField(top, 1, 2);
    if (!outer) {
        return false;
    }
    std::vector<ProtoField> inner;
    if (!parseMessage(outer->bytes, inner)) {
        return false;
    }
    const ProtoField *usage = findField(inner, 4, 2);
    if (!usage) {
        return false;
    }
    std::vector<ProtoField> tokens;
    if (!parseMessage(usage->bytes, tokens)) {
        return false;
    }
    const qlonglong inA = static_cast<qlonglong>(fieldVarint(tokens, 1));
    const qlonglong inB = static_cast<qlonglong>(fieldVarint(tokens, 2));
    turn.input = inA + inB;
    turn.cacheRead = static_cast<qlonglong>(fieldVarint(tokens, 5));
    turn.output = static_cast<qlonglong>(fieldVarint(tokens, 9));
    turn.reasoning = static_cast<qlonglong>(fieldVarint(tokens, 10));

    const ProtoField *rid = findField(tokens, 11, 2);
    if (rid && !rid->bytes.isEmpty()) {
        turn.responseId = QString::fromUtf8(rid->bytes).trimmed();
    }
    if (turn.input < 0 || turn.cacheRead < 0 || turn.output < 0 || turn.reasoning < 0) {
        return false;
    }
    if (turn.input == 0 && turn.cacheRead == 0 && turn.output == 0 && turn.reasoning == 0) {
        return false;
    }

    const ProtoField *modelField = findField(inner, 19, 2);
    if (modelField && !modelField->bytes.isEmpty()) {
        turn.model = QString::fromUtf8(modelField->bytes).trimmed();
    }
    if (turn.model.isEmpty()) {
        turn.model = fallbackModel(data);
    }
    if (turn.model.isEmpty()) {
        turn.model = QStringLiteral("(unknown)");
    }
    return true;
}

// ---------------------------------------------------------------------------
// SQLite discovery and scanning
// ---------------------------------------------------------------------------

QAtomicInteger<int> g_agConnectionCounter = 0;

bool checkAgSchema(QSqlDatabase &db) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    if (!query.exec(QStringLiteral("SELECT name FROM sqlite_master WHERE type='table'"))) {
        return false;
    }
    bool hasGen = false;
    bool hasBlob = false;
    while (query.next()) {
        const QString name = query.value(0).toString();
        if (name == QStringLiteral("gen_metadata")) {
            hasGen = true;
        } else if (name == QStringLiteral("trajectory_metadata_blob")) {
            hasBlob = true;
        }
    }
    if (!hasGen || !hasBlob) {
        return false;
    }
    QSqlQuery cols(db);
    cols.setForwardOnly(true);
    if (!cols.exec(QStringLiteral("PRAGMA table_info(gen_metadata)"))) {
        return false;
    }
    bool hasIdx = false;
    bool hasData = false;
    while (cols.next()) {
        const QString name = cols.value(1).toString();
        if (name == QStringLiteral("idx")) {
            hasIdx = true;
        } else if (name == QStringLiteral("data")) {
            hasData = true;
        }
    }
    return hasIdx && hasData;
}

struct AgFileRows {
    QList<AgTurn> turns;
    QList<QString> dedupeKeys;
    qlonglong skipped = 0;
};

bool collectFileTurns(QSqlDatabase &db,
                      const QString &sourceId,
                      const QString &fileStem,
                      AgFileRows &rows) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    if (!query.exec(QStringLiteral("SELECT idx, data FROM gen_metadata ORDER BY idx"))) {
        return false;
    }
    while (query.next()) {
        const qlonglong idx = query.value(0).toLongLong();
        const QByteArray data = query.value(1).toByteArray();
        if (data.isEmpty()) {
            ++rows.skipped;
            continue;
        }
        AgTurn turn;
        if (!extractTurn(data, turn)) {
            ++rows.skipped;
            continue;
        }
        QString key = turn.responseId;
        if (key.isEmpty()) {
            key = fileStem + QStringLiteral(":") + QString::number(idx);
        } else {
            key = sourceId + QStringLiteral(":") + key;
        }
        rows.turns.append(std::move(turn));
        rows.dedupeKeys.append(std::move(key));
    }
    return true;
}

bool collectFromAgDb(const QString &path,
                     const QString &sourceId,
                     const QString &fileStem,
                     qint64 fileTimeMs,
                     const AgWindowBounds &bounds,
                     AgRefreshResult *result,
                     QMap<QString, AgTokenWindow> *monthModels,
                     QMap<QString, AgTokenWindow> *monthSources,
                     QSet<QString> *seen,
                     QString *error) {
    const QString connectionName =
        QStringLiteral("agusage-%1").arg(g_agConnectionCounter.fetchAndAddOrdered(1));
    const bool inToday = fileTimeMs >= bounds.todayStart && fileTimeMs < bounds.end;
    const bool inWeek = fileTimeMs >= bounds.weekStart && fileTimeMs < bounds.end;
    const bool inMonth = fileTimeMs >= bounds.monthStart && fileTimeMs < bounds.end;
    if (!inToday && !inWeek && !inMonth) {
        // Timestamps are session level (whole file shares its mtime), so an
        // out-of-window file contributes nothing. Still counts as scanned.
        return true;
    }
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
        if (!checkAgSchema(db)) {
            *error = QStringLiteral("Unexpected conversation layout in %1").arg(path);
            db.close();
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
        AgFileRows rows;
        if (!collectFileTurns(db, sourceId, fileStem, rows)) {
            *error = QStringLiteral("Could not read turns in %1").arg(path);
            db.close();
            QSqlDatabase::removeDatabase(connectionName);
            return false;
        }
        db.close();
        result->rowsSkipped += rows.skipped;
        for (int i = 0; i < rows.turns.size(); ++i) {
            const QString &key = rows.dedupeKeys.at(i);
            if (seen->contains(key)) {
                continue;
            }
            seen->insert(key);
            const AgTurn &turn = rows.turns.at(i);
            auto addTo = [&](AgTokenWindow &window) {
                window.input += turn.input;
                window.output += turn.output;
                window.cacheRead += turn.cacheRead;
                window.reasoning += turn.reasoning;
                window.messages += 1;
            };
            if (inToday) {
                addTo(result->today);
            }
            if (inWeek) {
                addTo(result->week);
            }
            if (inMonth) {
                addTo(result->month);
                (*monthModels)[turn.model].input += turn.input;
                (*monthModels)[turn.model].output += turn.output;
                (*monthModels)[turn.model].cacheRead += turn.cacheRead;
                (*monthModels)[turn.model].reasoning += turn.reasoning;
                (*monthModels)[turn.model].messages += 1;
                (*monthSources)[sourceId].input += turn.input;
                (*monthSources)[sourceId].output += turn.output;
                (*monthSources)[sourceId].cacheRead += turn.cacheRead;
                (*monthSources)[sourceId].reasoning += turn.reasoning;
                (*monthSources)[sourceId].messages += 1;
            }
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return true;
}

struct AgRoot {
    QString id;
    QString dir;
};

} // namespace

AgWindowBounds computeAgWindowBounds() {
    static const QTimeZone ist(QStringLiteral("Asia/Kolkata").toLatin1());
    const QTimeZone zone = ist.isValid() ? ist : QTimeZone::systemTimeZone();
    const QDate today = QDateTime::currentDateTimeUtc().toTimeZone(zone).date();
    auto dayStartMs = [&](const QDate &day) {
        return QDateTime(day, QTime(0, 0), zone).toMSecsSinceEpoch();
    };
    AgWindowBounds bounds;
    bounds.todayStart = dayStartMs(today);
    bounds.weekStart = dayStartMs(today.addDays(-(today.dayOfWeek() - 1)));
    bounds.monthStart = dayStartMs(QDate(today.year(), today.month(), 1));
    bounds.end = QDateTime::currentMSecsSinceEpoch();
    return bounds;
}

QString agRefreshedAtIst() {
    static const QTimeZone ist(QStringLiteral("Asia/Kolkata").toLatin1());
    const QTimeZone zone = ist.isValid() ? ist : QTimeZone::systemTimeZone();
    const QDateTime now = QDateTime::currentDateTimeUtc().toTimeZone(zone);
    const QString label = zone.id() == QByteArray("Asia/Kolkata")
        ? QStringLiteral(" IST")
        : QStringLiteral(" ") + QString::fromLatin1(zone.id());
    return now.toString(QStringLiteral("dd MMM yyyy, hh:mm AP")) + label;
}

QStringList discoverAgRoots() {
    QStringList roots;
    const QString geminiHome =
        QString::fromLocal8Bit(qgetenv("GEMINI_CLI_HOME")).trimmed();
    const QString base = geminiHome.isEmpty()
        ? QDir::homePath() + QStringLiteral("/.gemini")
        : geminiHome;
    roots.append(base + QStringLiteral("/antigravity/conversations"));
    roots.append(base + QStringLiteral("/antigravity-cli/conversations"));
    const QString t3base =
        QDir::homePath() + QStringLiteral("/.t3/userdata/providers/antigravity");
    QDir t3dir(t3base);
    if (t3dir.exists()) {
        const QStringList ids =
            t3dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &id : ids) {
            const QString candidate =
                t3dir.absoluteFilePath(id + QStringLiteral("/antigravity-acp/conversations"));
            if (QDir(candidate).exists()) {
                roots.append(candidate);
            }
        }
    }
    const QString extra =
        QString::fromLocal8Bit(qgetenv("ANTIGRAVITY_USAGE_ROOTS")).trimmed();
    if (!extra.isEmpty()) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        const QStringList parts = extra.split(u':', Qt::SkipEmptyParts);
#else
        const QStringList parts = extra.split(QStringLiteral(":"), QString::SkipEmptyParts);
#endif
        for (const QString &part : parts) {
            if (!roots.contains(part)) {
                roots.append(part);
            }
        }
    }
    return roots;
}

AgRefreshResult collectAgUsage(const AgWindowBounds &bounds) {
    AgRefreshResult result;
    const QStringList roots = discoverAgRoots();
    for (const QString &root : roots) {
        if (QDir(root).exists()) {
            result.roots.append(root);
        }
    }
    if (result.roots.isEmpty()) {
        result.error = QStringLiteral("No Antigravity conversations found");
        return result;
    }
    result.configured = true;

    QMap<QString, AgTokenWindow> monthModels;
    QMap<QString, AgTokenWindow> monthSources;
    QSet<QString> seen;
    // Canonical paths guard against the same file reached through a symlink
    // (the T3 skills symlink is one such case) being counted twice.
    QSet<QString> visitedFiles;
    int readable = 0;
    QString firstError;
    for (const QString &root : result.roots) {
        const QFileInfo rootInfo(root);
        const QString sourceId =
            root.contains(QStringLiteral("antigravity-cli")) && !root.contains(QStringLiteral("antigravity-acp"))
            ? QStringLiteral("cli")
            : (root.contains(QStringLiteral("antigravity-acp")) ? QStringLiteral("t3-acp")
                                                                : QStringLiteral("antigravity"));
        QDirIterator it(root,
                        QStringList{QStringLiteral("*.db")},
                        QDir::Files | QDir::Readable,
                        QDirIterator::NoIteratorFlags);
        Q_UNUSED(rootInfo);
        while (it.hasNext()) {
            const QString path = it.next();
            const QFileInfo info(path);
            const QString name = info.fileName();
            if (name.endsWith(QStringLiteral("-wal")) || name.endsWith(QStringLiteral("-shm"))
                || name.endsWith(QStringLiteral("-journal"))) {
                continue;
            }
            if (name == QStringLiteral("conversation_summaries.db")) {
                continue;
            }
            const QString canonical = info.canonicalFilePath().isEmpty()
                ? info.absoluteFilePath()
                : info.canonicalFilePath();
            if (visitedFiles.contains(canonical)) {
                continue;
            }
            visitedFiles.insert(canonical);
            qint64 mtime = info.lastModified().toMSecsSinceEpoch();
            if (mtime > bounds.end) {
                mtime = bounds.end;
            }
            QString error;
            if (collectFromAgDb(path,
                                sourceId,
                                info.completeBaseName(),
                                mtime,
                                bounds,
                                &result,
                                &monthModels,
                                &monthSources,
                                &seen,
                                &error)) {
                ++readable;
                ++result.filesScanned;
            } else if (firstError.isEmpty()) {
                firstError = error;
            }
        }
    }
    if (readable == 0) {
        result.error = firstError.isEmpty()
            ? QStringLiteral("Could not read Antigravity conversations")
            : firstError;
        return result;
    }
    auto ranked = [](QMap<QString, AgTokenWindow> &map) {
        std::vector<std::pair<QString, AgTokenWindow>> list(map.keyValueBegin(),
                                                            map.keyValueEnd());
        list.erase(std::remove_if(list.begin(),
                                  list.end(),
                                  [](const auto &entry) { return entry.second.total() <= 0; }),
                   list.end());
        std::sort(list.begin(), list.end(), [](const auto &left, const auto &right) {\
            return left.second.total() > right.second.total();
        });
        return list;
    };
    auto models = ranked(monthModels);
    if (models.size() > 8) {
        models.resize(8);
    }
    QVariantList modelItems;
    for (const auto &entry : models) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), entry.first);
        item.insert(QStringLiteral("tokens"), entry.second.total());
        item.insert(QStringLiteral("messages"), entry.second.messages);
        modelItems.append(item);
    }
    result.monthModels = modelItems;
    QVariantList sourceItems;
    for (const auto &entry : ranked(monthSources)) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), entry.first);
        item.insert(QStringLiteral("tokens"), entry.second.total());
        item.insert(QStringLiteral("messages"), entry.second.messages);
        sourceItems.append(item);
    }
    result.monthSources = sourceItems;
    result.ok = true;
    result.refreshedAt = agRefreshedAtIst();
    return result;
}

AgUsageWorker::AgUsageWorker(QObject *parent)
    : QObject(parent) {}

void AgUsageWorker::refresh(const AgWindowBounds &bounds) {
    emit refreshed(collectAgUsage(bounds));
}

QString agUsageCachePath() {
    QString cacheHome = QString::fromLocal8Bit(qgetenv("XDG_CACHE_HOME")).trimmed();
    if (cacheHome.isEmpty()) {
        cacheHome = QDir::homePath() + QStringLiteral("/.cache");
    }
    return cacheHome + QStringLiteral("/quick-shell/antigravity-usage.json");
}

QJsonObject agWindowToCache(const AgTokenWindow &window) {
    QJsonObject object;
    object[QStringLiteral("input")] = window.input;
    object[QStringLiteral("output")] = window.output;
    object[QStringLiteral("cacheRead")] = window.cacheRead;
    object[QStringLiteral("reasoning")] = window.reasoning;
    object[QStringLiteral("messages")] = window.messages;
    return object;
}

AgTokenWindow agWindowFromCache(const QJsonObject &object) {
    AgTokenWindow window;
    window.input = qlonglong(object.value(QStringLiteral("input")).toDouble());
    window.output = qlonglong(object.value(QStringLiteral("output")).toDouble());
    window.cacheRead = qlonglong(object.value(QStringLiteral("cacheRead")).toDouble());
    window.reasoning = qlonglong(object.value(QStringLiteral("reasoning")).toDouble());
    window.messages = qlonglong(object.value(QStringLiteral("messages")).toDouble());
    return window;
}

QVariantMap agSplitMap(const AgTokenWindow &window);

void AntigravityUsage::loadCachedResult() {
    QFile file(agUsageCachePath());
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
    m_today = agWindowFromCache(root.value(QStringLiteral("today")).toObject());
    m_week = agWindowFromCache(root.value(QStringLiteral("week")).toObject());
    m_month = agWindowFromCache(root.value(QStringLiteral("month")).toObject());
    m_monthModels = root.value(QStringLiteral("monthModels")).toArray().toVariantList();
    m_monthSources = root.value(QStringLiteral("monthSources")).toArray().toVariantList();
    m_todaySplit = agSplitMap(m_today);
    m_weekSplit = agSplitMap(m_week);
    m_monthSplit = agSplitMap(m_month);
    m_lastRefresh = root.value(QStringLiteral("refreshedAt")).toString();
    m_configured = !m_lastRefresh.isEmpty();
}

void AntigravityUsage::saveCachedResult(const AgRefreshResult &result) {
    const int slash = agUsageCachePath().lastIndexOf(u'/');
    if (slash > 0 && !QDir().mkpath(agUsageCachePath().left(slash))) {
        return;
    }
    QJsonObject root;
    root[QStringLiteral("version")] = 1;
    root[QStringLiteral("today")] = agWindowToCache(result.today);
    root[QStringLiteral("week")] = agWindowToCache(result.week);
    root[QStringLiteral("month")] = agWindowToCache(result.month);
    root[QStringLiteral("monthModels")] = QJsonArray::fromVariantList(result.monthModels);
    root[QStringLiteral("monthSources")] = QJsonArray::fromVariantList(result.monthSources);
    root[QStringLiteral("refreshedAt")] = result.refreshedAt;
    QSaveFile file(agUsageCachePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    file.commit();
}

QVariantMap agSplitMap(const AgTokenWindow &window) {
    QVariantMap map;
    map.insert(QStringLiteral("input"), window.input);
    map.insert(QStringLiteral("output"), window.output);
    map.insert(QStringLiteral("cacheRead"), window.cacheRead);
    map.insert(QStringLiteral("reasoning"), window.reasoning);
    return map;
}

AntigravityUsage::AntigravityUsage(QObject *parent)
    : QObject(parent) {
    qRegisterMetaType<AgWindowBounds>();
    qRegisterMetaType<AgRefreshResult>();
    loadCachedResult();
    m_worker = new AgUsageWorker();
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &AntigravityUsage::requestRefresh, m_worker, &AgUsageWorker::refresh);
    connect(m_worker, &AgUsageWorker::refreshed, this, &AntigravityUsage::onRefreshed);
    m_thread.start();
}

AntigravityUsage::~AntigravityUsage() {
    m_thread.quit();
    m_thread.wait();
}

void AntigravityUsage::refresh() {
    if (m_busy) {
        return;
    }
    m_busy = true;
    emit busyChanged();
    emit requestRefresh(computeAgWindowBounds());
}

QString AntigravityUsage::compact(qlonglong value) const {
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

void AntigravityUsage::onRefreshed(const AgRefreshResult &result) {
    m_busy = false;
    m_configured = result.configured;
    m_error = result.error;
    if (result.ok) {
        m_today = result.today;
        m_week = result.week;
        m_month = result.month;
        m_monthModels = result.monthModels;
        m_monthSources = result.monthSources;
        m_todaySplit = agSplitMap(result.today);
        m_weekSplit = agSplitMap(result.week);
        m_monthSplit = agSplitMap(result.month);
        m_lastRefresh = result.refreshedAt;
        saveCachedResult(result);
    }
    emit busyChanged();
    emit dataChanged();
}

} // namespace qs::plugins
