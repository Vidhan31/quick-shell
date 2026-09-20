// antigravity-probe — standalone diagnostic printing one JSON object:
// {"ok":..,"configured":..,"error":..,"today":{"tokens":..,"messages":..},...}
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
    object[QStringLiteral("messages")] = window.messages;
    return object;
}

QJsonObject namedToJson(const QVariantMap &item) {
    QJsonObject object;
    object[QStringLiteral("name")] = item.value(QStringLiteral("name")).toString();
    object[QStringLiteral("tokens")] = item.value(QStringLiteral("tokens")).toLongLong();
    object[QStringLiteral("messages")] = item.value(QStringLiteral("messages")).toLongLong();
    return object;
}

} // namespace

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    Q_UNUSED(argc);
    Q_UNUSED(argv);

    const qs::plugins::AgWindowBounds bounds = qs::plugins::computeAgWindowBounds();
    const qs::plugins::AgRefreshResult result = qs::plugins::collectAgUsage(bounds);

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
    root[QStringLiteral("monthModels")] = models;
    root[QStringLiteral("monthSources")] = sources;
    root[QStringLiteral("refreshedAt")] = result.refreshedAt;

    QTextStream out(stdout);
    out << QJsonDocument(root).toJson(QJsonDocument::Compact) << '\n';
    return result.ok ? 0 : 1;
}
