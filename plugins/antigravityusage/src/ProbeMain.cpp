// antigravity-probe — standalone diagnostic printing one JSON object:
// {"ok":..,"configured":..,"error":..,"today":{"tokens":..},...}
#include "AntigravityUsage.hpp"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

namespace {

QJsonObject windowToJson(const qs::plugins::AgTokenWindow &window) {
    QJsonObject object;
    object[QStringLiteral("tokens")] = window.total();
    object[QStringLiteral("input")] = window.input;
    object[QStringLiteral("output")] = window.output;
    object[QStringLiteral("cacheRead")] = window.cacheRead;
    object[QStringLiteral("reasoning")] = window.reasoning;
    return object;
}

QJsonObject namedToJson(const QVariantMap &item) {
    QJsonObject object;
    object[QStringLiteral("name")] = item.value(QStringLiteral("name")).toString();
    object[QStringLiteral("tokens")] = item.value(QStringLiteral("tokens")).toLongLong();
    return object;
}

} // namespace

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    int lastDays = 10;
    if (argc > 1) {
        bool ok = false;
        const int parsed = QString::fromLocal8Bit(argv[1]).toInt(&ok);
        if (ok) {
            lastDays = parsed;
        }
    }

    const qs::plugins::AgWindowBounds bounds = qs::plugins::computeAgWindowBounds();
    const qs::plugins::AgRefreshResult result = qs::plugins::collectAgUsage(bounds, lastDays);

    QJsonArray models;
    for (const QVariant &value : result.monthModels) {
        models.append(namedToJson(value.toMap()));
    }
    QJsonArray sources;
    for (const QVariant &value : result.monthSources) {
        sources.append(namedToJson(value.toMap()));
    }

    QJsonObject root;
    root[QStringLiteral("ok")] = result.ok;
    root[QStringLiteral("configured")] = result.configured;
    root[QStringLiteral("error")] = result.error;
    root[QStringLiteral("filesScanned")] = result.filesScanned;
    root[QStringLiteral("rowsSkipped")] = result.rowsSkipped;
    root[QStringLiteral("today")] = windowToJson(result.today);
    root[QStringLiteral("week")] = windowToJson(result.week);
    root[QStringLiteral("month")] = windowToJson(result.month);
    root[QStringLiteral("lastDays")] = windowToJson(result.lastDays);
    root[QStringLiteral("lastDaysRequested")] = result.lastDaysRequested;
    root[QStringLiteral("monthModels")] = models;
    root[QStringLiteral("monthSources")] = sources;
    root[QStringLiteral("dailyUsage")] = QJsonArray::fromVariantList(result.dailyUsage);
    root[QStringLiteral("refreshedAt")] = result.refreshedAt;

    QTextStream out(stdout);
    out << QJsonDocument(root).toJson(QJsonDocument::Compact) << '\n';
    return result.ok ? 0 : 1;
}
