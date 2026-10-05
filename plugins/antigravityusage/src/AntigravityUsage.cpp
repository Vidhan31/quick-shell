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

// Minimal protobuf wire reader. Only what gen_metadata blobs need: varints
// and length-delimited fields. Every read is bounds checked; anything
// malformed fails the row instead of the scan.

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
    qint64 timestampMs = 0;
    QString responseId;
    QString model;
};

qint64 parseProtoTimestamp(const QByteArray &bytes) {
    if (bytes.isEmpty()) {
        return 0;
    }
    std::vector<ProtoField> fields;
    if (!parseMessage(bytes, fields)) {
        return 0;
    }
    const quint64 sec = fieldVarint(fields, 1);
    const quint64 nanos = fieldVarint(fields, 2);
    if (sec > 0) {
        return static_cast<qint64>(sec) * 1000 + static_cast<qint64>(nanos / 1000000);
    }
    return 0;
}

bool parseUsageTokens(const QByteArray &usageBytes,
                      qlonglong &input,
                      qlonglong &cacheRead,
                      qlonglong &output,
                      qlonglong &reasoning,
                      QString &responseId) {
    std::vector<ProtoField> tokens;
    if (!parseMessage(usageBytes, tokens)) {
        return false;
    }
    const qlonglong inA = static_cast<qlonglong>(fieldVarint(tokens, 1));
    const qlonglong inB = static_cast<qlonglong>(fieldVarint(tokens, 2));
    input = inA + inB;
    cacheRead = static_cast<qlonglong>(fieldVarint(tokens, 5));
    output = static_cast<qlonglong>(fieldVarint(tokens, 9));
    reasoning = static_cast<qlonglong>(fieldVarint(tokens, 10));

    const ProtoField *rid = findField(tokens, 11, 2);
    if (rid && !rid->bytes.isEmpty()) {
        responseId = QString::fromUtf8(rid->bytes).trimmed();
    }
    if (input < 0 || cacheRead < 0 || output < 0 || reasoning < 0) {
        return false;
    }
    if (input == 0 && cacheRead == 0 && output == 0 && reasoning == 0) {
        return false;
    }
    return true;
}

bool extractGenTurn(const QByteArray &data, QList<AgTurn> &outTurns) {
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
    AgTurn turn;
    if (!parseUsageTokens(usage->bytes, turn.input, turn.cacheRead, turn.output, turn.reasoning, turn.responseId)) {
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
    const ProtoField *f9 = findField(inner, 9, 2);
    if (f9) {
        std::vector<ProtoField> f9Fields;
        if (parseMessage(f9->bytes, f9Fields)) {
            const ProtoField *f4 = findField(f9Fields, 4, 2);
            if (f4) {
                turn.timestampMs = parseProtoTimestamp(f4->bytes);
            }
        }
    }
    if (turn.timestampMs == 0) {
        const ProtoField *f8 = findField(inner, 8, 2);
        if (f8) {
            turn.timestampMs = parseProtoTimestamp(f8->bytes);
        }
    }
    outTurns.append(turn);

    // Retries in gen_metadata: field 17
    for (const ProtoField &f : inner) {
        if (f.id == 17 && f.wire == 2) {
            std::vector<ProtoField> retryFields;
            if (parseMessage(f.bytes, retryFields)) {
                const ProtoField *rUsage = findField(retryFields, 2, 2);
                if (rUsage) {
                    AgTurn rTurn;
                    if (parseUsageTokens(rUsage->bytes, rTurn.input, rTurn.cacheRead, rTurn.output, rTurn.reasoning, rTurn.responseId)) {
                        rTurn.model = turn.model;
                        rTurn.timestampMs = turn.timestampMs;
                        outTurns.append(rTurn);
                    }
                }
            }
        }
    }
    return true;
}

bool extractStepTurn(const QByteArray &data, QList<AgTurn> &outTurns) {
    std::vector<ProtoField> root;
    if (!parseMessage(data, root)) {
        return false;
    }
    const ProtoField *usage = findField(root, 9, 2);
    if (!usage) {
        return false;
    }
    AgTurn turn;
    if (!parseUsageTokens(usage->bytes, turn.input, turn.cacheRead, turn.output, turn.reasoning, turn.responseId)) {
        return false;
    }
    const ProtoField *mField = findField(root, 24, 2);
    if (mField) {
        std::vector<ProtoField> mInner;
        if (parseMessage(mField->bytes, mInner)) {
            const ProtoField *nameField = findField(mInner, 12, 2);
            if (!nameField) nameField = findField(mInner, 8, 2);
            if (nameField && !nameField->bytes.isEmpty()) {
                turn.model = QString::fromUtf8(nameField->bytes).trimmed();
            }
        }
    }
    if (turn.model.isEmpty()) {
        turn.model = fallbackModel(data);
    }
    if (turn.model.isEmpty()) {
        turn.model = QStringLiteral("(unknown)");
    }
    const ProtoField *tsField = findField(root, 8, 2);
    if (!tsField) tsField = findField(root, 1, 2);
    if (tsField) {
        turn.timestampMs = parseProtoTimestamp(tsField->bytes);
    }
    outTurns.append(turn);

    // Retries in steps: field 28
    for (const ProtoField &f : root) {
        if (f.id == 28 && f.wire == 2) {
            std::vector<ProtoField> retryFields;
            if (parseMessage(f.bytes, retryFields)) {
                const ProtoField *rUsage = findField(retryFields, 2, 2);
                if (rUsage) {
                    AgTurn rTurn;
                    if (parseUsageTokens(rUsage->bytes, rTurn.input, rTurn.cacheRead, rTurn.output, rTurn.reasoning, rTurn.responseId)) {
                        rTurn.model = turn.model;
                        rTurn.timestampMs = turn.timestampMs;
                        outTurns.append(rTurn);
                    }
                }
            }
        }
    }
    return true;
}

qint64 readTrajectoryTimestamp(QSqlDatabase &db) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    if (!query.exec(QStringLiteral("SELECT data FROM trajectory_metadata_blob LIMIT 1"))) {
        return 0;
    }
    if (query.next()) {
        const QByteArray blob = query.value(0).toByteArray();
        std::vector<ProtoField> fields;
        if (parseMessage(blob, fields)) {
            const ProtoField *f2 = findField(fields, 2, 2);
            if (f2) {
                return parseProtoTimestamp(f2->bytes);
            }
        }
    }
    return 0;
}

QAtomicInteger<int> g_agConnectionCounter = 0;

bool checkAgSchema(QSqlDatabase &db, bool &hasGen, bool &hasSteps) {
    QSqlQuery query(db);
    query.setForwardOnly(true);
    if (!query.exec(QStringLiteral("SELECT name FROM sqlite_master WHERE type='table'"))) {
        return false;
    }
    hasGen = false;
    hasSteps = false;
    while (query.next()) {
        const QString name = query.value(0).toString();
        if (name == QStringLiteral("gen_metadata")) {
            hasGen = true;
        } else if (name == QStringLiteral("steps")) {
            hasSteps = true;
        }
    }
    if (!hasGen && !hasSteps) {
        return false;
    }
    if (hasGen) {
        QSqlQuery cols(db);
        cols.setForwardOnly(true);
        if (cols.exec(QStringLiteral("PRAGMA table_info(gen_metadata)"))) {
            bool hasData = false;
            while (cols.next()) {
                if (cols.value(1).toString() == QStringLiteral("data")) {
                    hasData = true;
                }
            }
            if (!hasData) hasGen = false;
        } else {
            hasGen = false;
        }
    }
    if (hasSteps) {
        QSqlQuery cols(db);
        cols.setForwardOnly(true);
        if (cols.exec(QStringLiteral("PRAGMA table_info(steps)"))) {
            bool hasMetadata = false;
            while (cols.next()) {
                if (cols.value(1).toString() == QStringLiteral("metadata")) {
                    hasMetadata = true;
                }
            }
            if (!hasMetadata) hasSteps = false;
        } else {
            hasSteps = false;
        }
    }
    return hasGen || hasSteps;
}

struct AgFileRows {
    QList<AgTurn> turns;
    QList<QString> dedupeKeys;
    QList<qlonglong> idxs;
    qlonglong skipped = 0;
};

struct AgScoredTurn {
    qint64 fileTimeMs = 0;
    qlonglong idx = 0;
    AgTurn turn;
};

int clampAgLastDays(int days) {
    if (days < 1) {
        return 30;
    }
    if (days > 400) {
        return 400;
    }
    return days;
}

bool collectFileTurns(QSqlDatabase &db,
                      const QString &sourceId,
                      const QString &fileStem,
                      bool hasGen,
                      bool hasSteps,
                      qint64 trajectoryTimestamp,
                      AgFileRows &rows) {
    if (hasGen) {
        QSqlQuery query(db);
        query.setForwardOnly(true);
        if (query.exec(QStringLiteral("SELECT idx, data FROM gen_metadata ORDER BY idx"))) {
            while (query.next()) {
                const qlonglong idx = query.value(0).toLongLong();
                const QByteArray data = query.value(1).toByteArray();
                if (data.isEmpty()) {
                    ++rows.skipped;
                    continue;
                }
                QList<AgTurn> extracted;
                if (!extractGenTurn(data, extracted)) {
                    ++rows.skipped;
                    continue;
                }
                for (int t = 0; t < extracted.size(); ++t) {
                    AgTurn &turn = extracted[t];
                    if (turn.timestampMs == 0 && trajectoryTimestamp > 0) {
                        turn.timestampMs = trajectoryTimestamp;
                    }
                    QString key = turn.responseId;
                    if (key.isEmpty()) {
                        key = fileStem + QStringLiteral(":gen:") + QString::number(idx) + QStringLiteral(":") + QString::number(t);
                    } else {
                        key = sourceId + QStringLiteral(":") + key;
                    }
                    rows.turns.append(std::move(turn));
                    rows.dedupeKeys.append(std::move(key));
                    rows.idxs.append(idx);
                }
            }
        }
    }

    if (hasSteps) {
        QSqlQuery query(db);
        query.setForwardOnly(true);
        if (query.exec(QStringLiteral("SELECT idx, metadata FROM steps WHERE metadata IS NOT NULL ORDER BY idx"))) {
            while (query.next()) {
                const qlonglong idx = query.value(0).toLongLong();
                const QByteArray data = query.value(1).toByteArray();
                if (data.isEmpty()) {
                    continue;
                }
                QList<AgTurn> extracted;
                if (!extractStepTurn(data, extracted)) {
                    continue;
                }
                for (int t = 0; t < extracted.size(); ++t) {
                    AgTurn &turn = extracted[t];
                    if (turn.timestampMs == 0 && trajectoryTimestamp > 0) {
                        turn.timestampMs = trajectoryTimestamp;
                    }
                    QString key = turn.responseId;
                    if (key.isEmpty()) {
                        key = fileStem + QStringLiteral(":step:") + QString::number(idx) + QStringLiteral(":") + QString::number(t);
                    } else {
                        key = sourceId + QStringLiteral(":") + key;
                    }
                    rows.turns.append(std::move(turn));
                    rows.dedupeKeys.append(std::move(key));
                    rows.idxs.append(idx);
                }
            }
        }
    }
    return true;
}

struct AgDbRead {
    bool ok{false};
    qint64 trajectoryTimestamp{0};
    AgFileRows rows;
};

// Owns the whole connection lifetime so callers never hold a QSqlDatabase while
// removeDatabase() runs. Qt warns and disables the connection if any handle is
// still referenced at that point.
AgDbRead readAgRows(const QString &path,
                    const QString &sourceId,
                    const QString &fileStem,
                    QString *error) {
    const QString connectionName =
        QStringLiteral("agusage-%1").arg(g_agConnectionCounter.fetchAndAddOrdered(1));

    AgDbRead out;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
        db.setDatabaseName(path);
        // QSQLITE_OPEN_READONLY is a flag (not key=value) documented in Qt SQL:
        // https://doc.qt.io/qt-6/sql-driver.html#qsqlite
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=250"));
        if (!db.open()) {
            *error = db.lastError().text();
        } else {
            bool hasGen = false;
            bool hasSteps = false;
            if (!checkAgSchema(db, hasGen, hasSteps)) {
                *error = QStringLiteral("Unexpected conversation layout in %1").arg(path);
            } else {
                out.trajectoryTimestamp = readTrajectoryTimestamp(db);
                if (!collectFileTurns(db, sourceId, fileStem, hasGen, hasSteps, out.trajectoryTimestamp, out.rows)) {
                    *error = QStringLiteral("Could not read turns in %1").arg(path);
                } else {
                    out.ok = true;
                }
            }
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connectionName);
    return out;
}

bool collectFromAgDb(const QString &path,
                     const QString &sourceId,
                     const QString &fileStem,
                     qint64 fileTimeMs,
                     const AgWindowBounds &bounds,
                     const QDate &rangeStartDay,
                     const QDate &today,
                     AgRefreshResult *result,
                     QMap<QString, AgTokenWindow> *monthModels,
                     QMap<QString, AgTokenWindow> *allModels,
                     QMap<QString, AgTokenWindow> *monthSources,
                     QMap<QDate, AgTokenWindow> *dailyMap,
                     QSet<QString> *seen,
                     QString *error) {
    const AgDbRead dbRead = readAgRows(path, sourceId, fileStem, error);
    if (!dbRead.ok) {
        return false;
    }
    const qint64 trajectoryTimestamp = dbRead.trajectoryTimestamp;
    const AgFileRows &rows = dbRead.rows;
    result->rowsSkipped += rows.skipped;

        QMap<QString, AgTurn> fileTurns;
        for (int i = 0; i < rows.turns.size(); ++i) {
            const QString &key = rows.dedupeKeys.at(i);
            const AgTurn &turn = rows.turns.at(i);
            auto it = fileTurns.find(key);
            if (it == fileTurns.end()) {
                fileTurns.insert(key, turn);
            } else {
                AgTurn &existing = it.value();
                existing.input = std::max(existing.input, turn.input);
                existing.output = std::max(existing.output, turn.output);
                existing.cacheRead = std::max(existing.cacheRead, turn.cacheRead);
                existing.reasoning = std::max(existing.reasoning, turn.reasoning);
                if (existing.model.isEmpty() || existing.model == QStringLiteral("(unknown)")) {
                    existing.model = turn.model;
                }
                if (existing.timestampMs == 0 && turn.timestampMs > 0) {
                    existing.timestampMs = turn.timestampMs;
                }
            }
        }

        static const QTimeZone ist(QStringLiteral("Asia/Kolkata").toLatin1());
        const QTimeZone zone = ist.isValid() ? ist : QTimeZone::systemTimeZone();

        for (auto it = fileTurns.constBegin(); it != fileTurns.constEnd(); ++it) {
            const QString &key = it.key();
            if (seen->contains(key)) {
                continue;
            }
            seen->insert(key);
            const AgTurn &turn = it.value();
            const qint64 actualTimeMs = turn.timestampMs > 0 ? turn.timestampMs
                : (trajectoryTimestamp > 0 ? trajectoryTimestamp : fileTimeMs);
            const bool inToday = actualTimeMs >= bounds.todayStart && actualTimeMs < bounds.end;
            const bool inWeek = actualTimeMs >= bounds.weekStart && actualTimeMs < bounds.end;
            const bool inLastDays = actualTimeMs >= bounds.lastDaysStart && actualTimeMs < bounds.end;
            const bool inMonth = actualTimeMs >= bounds.monthStart && actualTimeMs < bounds.end;
            const QDate fileDay = QDateTime::fromMSecsSinceEpoch(actualTimeMs, zone).date();
            const bool inDaily = fileDay >= rangeStartDay && fileDay <= today;

            auto addTo = [&](AgTokenWindow &window) {
                window.input += turn.input;
                window.output += turn.output;
                window.cacheRead += turn.cacheRead;
                window.reasoning += turn.reasoning;
            };
            if (inToday) {
                addTo(result->today);
            }
            if (inWeek) {
                addTo(result->week);
            }
            if (inLastDays) {
                addTo(result->lastDays);
                (*monthModels)[turn.model].input += turn.input;
                (*monthModels)[turn.model].output += turn.output;
                (*monthModels)[turn.model].cacheRead += turn.cacheRead;
                (*monthModels)[turn.model].reasoning += turn.reasoning;
                (*monthSources)[sourceId].input += turn.input;
                (*monthSources)[sourceId].output += turn.output;
                (*monthSources)[sourceId].cacheRead += turn.cacheRead;
                (*monthSources)[sourceId].reasoning += turn.reasoning;
            }
            if (inDaily) {
                AgTokenWindow &dw = (*dailyMap)[fileDay];
                dw.input += turn.input;
                dw.output += turn.output;
                dw.cacheRead += turn.cacheRead;
                dw.reasoning += turn.reasoning;
            }
            if (inMonth) {
                addTo(result->month);
            }
            if (actualTimeMs <= bounds.end) {
                addTo(result->allTime);
                if (allModels && !turn.model.isEmpty() && turn.model != QStringLiteral("(unknown)")) {
                    (*allModels)[turn.model].input += turn.input;
                    (*allModels)[turn.model].output += turn.output;
                    (*allModels)[turn.model].cacheRead += turn.cacheRead;
                    (*allModels)[turn.model].reasoning += turn.reasoning;
                }
            }
        }
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
    bounds.monthStart = dayStartMs(today.addDays(-29));
    bounds.end = QDateTime::currentMSecsSinceEpoch();
    bounds.lastDaysStart = bounds.end - qint64(10) * 24 * 60 * 60 * 1000;
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

AgRefreshResult collectAgUsage(const AgWindowBounds &bounds, int lastDays) {
    AgRefreshResult result;
    result.lastDaysRequested = clampAgLastDays(lastDays);
    AgWindowBounds rollingBounds = bounds;
    rollingBounds.lastDaysStart =
        bounds.end - qint64(result.lastDaysRequested) * 24 * 60 * 60 * 1000;
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

    static const QTimeZone ist(QStringLiteral("Asia/Kolkata").toLatin1());
    const QTimeZone zone = ist.isValid() ? ist : QTimeZone::systemTimeZone();
    const QDate today = QDateTime::currentDateTimeUtc().toTimeZone(zone).date();
    const QDate rangeStartDay = today.addDays(-(result.lastDaysRequested - 1));

    QMap<QString, AgTokenWindow> monthModels;
    QMap<QString, AgTokenWindow> allModels;
    QMap<QString, AgTokenWindow> monthSources;
    QMap<QDate, AgTokenWindow> dailyMap;
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
                                rollingBounds,
                                rangeStartDay,
                                today,
                                &result,
                                &monthModels,
                                &allModels,
                                &monthSources,
                                &dailyMap,
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
    QVariantList modelItems;
    for (const auto &entry : models) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), entry.first);
        item.insert(QStringLiteral("tokens"), entry.second.total());
        item.insert(QStringLiteral("input"), entry.second.input);
        item.insert(QStringLiteral("output"), entry.second.output);
        item.insert(QStringLiteral("cacheRead"), entry.second.cacheRead);
        item.insert(QStringLiteral("reasoning"), entry.second.reasoning);
        modelItems.append(item);
    }
    result.monthModels = modelItems;

    auto allModelsRanked = ranked(allModels);
    QVariantList allModelItems;
    for (const auto &entry : allModelsRanked) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), entry.first);
        item.insert(QStringLiteral("tokens"), entry.second.total());
        item.insert(QStringLiteral("input"), entry.second.input);
        item.insert(QStringLiteral("output"), entry.second.output);
        item.insert(QStringLiteral("cacheRead"), entry.second.cacheRead);
        item.insert(QStringLiteral("reasoning"), entry.second.reasoning);
        allModelItems.append(item);
    }
    result.allModels = allModelItems;
    QVariantList sourceItems;
    for (const auto &entry : ranked(monthSources)) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), entry.first);
        item.insert(QStringLiteral("tokens"), entry.second.total());
        sourceItems.append(item);
    }
    result.monthSources = sourceItems;

    QVariantList dailyList;
    for (int d = 0; d < result.lastDaysRequested; ++d) {
        const QDate day = rangeStartDay.addDays(d);
        const QString dayKey = day.toString(QStringLiteral("yyyy-MM-dd"));
        const AgTokenWindow window = dailyMap.value(day);
        QVariantMap point;
        point.insert(QStringLiteral("date"), dayKey);
        point.insert(QStringLiteral("label"), day.toString(QStringLiteral("d MMM")));
        point.insert(QStringLiteral("weekday"), day.toString(QStringLiteral("ddd")));
        point.insert(QStringLiteral("dayNumber"), day.day());
        point.insert(QStringLiteral("tokens"), window.total());
        point.insert(QStringLiteral("input"), window.input);
        point.insert(QStringLiteral("output"), window.output);
        point.insert(QStringLiteral("cacheRead"), window.cacheRead);
        point.insert(QStringLiteral("reasoning"), window.reasoning);
        dailyList.append(point);
    }
    result.dailyUsage = dailyList;

    result.ok = true;
    result.refreshedAt = agRefreshedAtIst();
    return result;
}

AgUsageWorker::AgUsageWorker(QObject *parent)
    : QObject(parent) {}

void AgUsageWorker::refresh(const AgWindowBounds &bounds, int lastDays) {
    emit refreshed(collectAgUsage(bounds, lastDays));
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
    return object;
}

AgTokenWindow agWindowFromCache(const QJsonObject &object) {
    AgTokenWindow window;
    window.input = qlonglong(object.value(QStringLiteral("input")).toDouble());
    window.output = qlonglong(object.value(QStringLiteral("output")).toDouble());
    window.cacheRead = qlonglong(object.value(QStringLiteral("cacheRead")).toDouble());
    window.reasoning = qlonglong(object.value(QStringLiteral("reasoning")).toDouble());
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
    if (root.value(QStringLiteral("version")).toInt() != 4) {
        return;
    }
    m_today = agWindowFromCache(root.value(QStringLiteral("today")).toObject());
    m_week = agWindowFromCache(root.value(QStringLiteral("week")).toObject());
    m_month = agWindowFromCache(root.value(QStringLiteral("month")).toObject());
    m_lastDaysWindow = agWindowFromCache(root.value(QStringLiteral("lastDays")).toObject());
    m_allTime = agWindowFromCache(root.value(QStringLiteral("allTime")).toObject());
    m_lastDays = root.value(QStringLiteral("lastDaysRequested")).toInt(30);
    if (m_lastDays < 1 || m_lastDays > 400) {
        m_lastDays = 30;
    }
    m_monthModels = root.value(QStringLiteral("monthModels")).toArray().toVariantList();
    m_allModels = root.value(QStringLiteral("allModels")).toArray().toVariantList();
    m_monthSources = root.value(QStringLiteral("monthSources")).toArray().toVariantList();
    m_dailyUsage = root.value(QStringLiteral("dailyUsage")).toArray().toVariantList();
    m_todaySplit = agSplitMap(m_today);
    m_weekSplit = agSplitMap(m_week);
    m_monthSplit = agSplitMap(m_month);
    m_lastDaysSplit = agSplitMap(m_lastDaysWindow);
    m_allSplit = agSplitMap(m_allTime);
    m_lastRefresh = root.value(QStringLiteral("refreshedAt")).toString();
    m_configured = !m_lastRefresh.isEmpty();
}

void AntigravityUsage::saveCachedResult(const AgRefreshResult &result) {
    const int slash = agUsageCachePath().lastIndexOf(u'/');
    if (slash > 0 && !QDir().mkpath(agUsageCachePath().left(slash))) {
        return;
    }
    QJsonObject root;
    root[QStringLiteral("version")] = 4;
    root[QStringLiteral("today")] = agWindowToCache(result.today);
    root[QStringLiteral("week")] = agWindowToCache(result.week);
    root[QStringLiteral("month")] = agWindowToCache(result.month);
    root[QStringLiteral("lastDays")] = agWindowToCache(result.lastDays);
    root[QStringLiteral("allTime")] = agWindowToCache(result.allTime);
    root[QStringLiteral("lastDaysRequested")] = result.lastDaysRequested;
    root[QStringLiteral("monthModels")] = QJsonArray::fromVariantList(result.monthModels);
    root[QStringLiteral("allModels")] = QJsonArray::fromVariantList(result.allModels);
    root[QStringLiteral("monthSources")] = QJsonArray::fromVariantList(result.monthSources);
    root[QStringLiteral("dailyUsage")] = QJsonArray::fromVariantList(result.dailyUsage);
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
    emit requestRefresh(computeAgWindowBounds(), m_lastDays);
}

void AntigravityUsage::setLastDays(int days) {
    if (days < 1) {
        days = 1;
    } else if (days > 400) {
        days = 400;
    }
    if (m_lastDays == days) {
        return;
    }
    m_lastDays = days;
    emit lastDaysChanged();
    refresh();
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
        m_lastDaysWindow = result.lastDays;
        m_allTime = result.allTime;
        m_monthModels = result.monthModels;
        m_allModels = result.allModels;
        m_monthSources = result.monthSources;
        m_dailyUsage = result.dailyUsage;
        m_todaySplit = agSplitMap(result.today);
        m_weekSplit = agSplitMap(result.week);
        m_monthSplit = agSplitMap(result.month);
        m_lastDaysSplit = agSplitMap(result.lastDays);
        m_allSplit = agSplitMap(result.allTime);
        m_lastRefresh = result.refreshedAt;
        saveCachedResult(result);
        if (m_lastDays != result.lastDaysRequested) {
            // Days changed mid-flight: keep desired days and re-request.
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
