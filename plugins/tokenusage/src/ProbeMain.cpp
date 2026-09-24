// tokenusage-probe — standalone diagnostic printing one JSON object:
// {"ok":..,"configured":..,"error":..,"today":{"tokens":..,"cost":..},...}
#include "TokenUsage.hpp"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

namespace {

QJsonObject windowToJson(const qs::plugins::TokenWindow &window) {
    QJsonObject object;
    object[QStringLiteral("tokens")] = window.total();
    object[QStringLiteral("input")] = window.input;
    object[QStringLiteral("output")] = window.output;
    object[QStringLiteral("cacheRead")] = window.cacheRead;
    object[QStringLiteral("cacheWrite")] = window.cacheWrite;
    object[QStringLiteral("reasoning")] = window.reasoning;
    object[QStringLiteral("cost")] = window.cost;
    return object;
}

QJsonObject modelToJson(const QVariantMap &model) {
    QJsonObject object;
    object[QStringLiteral("name")] = model.value(QStringLiteral("name")).toString();
    object[QStringLiteral("tokens")] = model.value(QStringLiteral("tokens")).toLongLong();
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

    const qs::plugins::TokenWindowBounds bounds = qs::plugins::computeWindowBounds();
    const qs::plugins::TokenRefreshResult result = qs::plugins::collectTokenUsage(bounds, lastDays);

    QJsonArray models;
    for (const QVariant &value : result.monthModels) {
        models.append(modelToJson(value.toMap()));
    }

    QJsonObject root;
    root[QStringLiteral("ok")] = result.ok;
    root[QStringLiteral("configured")] = result.configured;
    root[QStringLiteral("error")] = result.error;
    root[QStringLiteral("today")] = windowToJson(result.today);
    root[QStringLiteral("week")] = windowToJson(result.week);
    root[QStringLiteral("month")] = windowToJson(result.month);
    root[QStringLiteral("lastDays")] = windowToJson(result.lastDays);
    root[QStringLiteral("lastDaysRequested")] = result.lastDaysRequested;
    root[QStringLiteral("monthModels")] = models;
    root[QStringLiteral("refreshedAt")] = result.refreshedAt;

    QTextStream out(stdout);
    out << QJsonDocument(root).toJson(QJsonDocument::Compact) << '\n';
    return result.ok ? 0 : 1;
}
