// modelpricing-probe — resolve model names against a models.dev payload:
//   modelpricing-probe <config.json> <api.json> <model...>
// Prints one compact JSON object to stdout.
#include "ModelPricing.hpp"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

namespace {

QJsonObject loadJsonFile(const QString &path, QString *error) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("Cannot read %1").arg(path);
        return {};
    }
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        *error = QStringLiteral("Invalid JSON in %1: %2").arg(path, parseError.errorString());
        return {};
    }
    return document.object();
}

} // namespace

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    QTextStream out(stdout);

    if (argc < 4) {
        QTextStream(stderr) << "usage: modelpricing-probe <config.json> <api.json> <model...>\n";
        return 2;
    }

    QString error;
    const QJsonObject config =
        loadJsonFile(QString::fromLocal8Bit(argv[1]), &error);
    if (!error.isEmpty()) {
        QTextStream(stderr) << error << '\n';
        return 1;
    }
    QStringList markers;
    for (const QJsonValue &value : config.value(QStringLiteral("gatewayNpmMarkers")).toArray()) {
        markers.append(value.toString());
    }
    QStringList suffixes;
    for (const QJsonValue &value : config.value(QStringLiteral("tierSuffixes")).toArray()) {
        suffixes.append(value.toString());
    }
    qs::plugins::PriceIndex overrides;
    if (config.contains(QStringLiteral("overrides")) && config.value(QStringLiteral("overrides")).isObject()) {
        const QJsonObject ovObj = config.value(QStringLiteral("overrides")).toObject();
        for (auto it = ovObj.begin(); it != ovObj.end(); ++it) {
            if (!it.value().isObject()) continue;
            const QJsonObject o = it.value().toObject();
            qs::plugins::PriceEntry entry;
            entry.providerId = o.value(QStringLiteral("provider")).toString();
            entry.family = o.value(QStringLiteral("family")).toString();
            entry.input = o.value(QStringLiteral("input")).toDouble();
            entry.output = o.value(QStringLiteral("output")).toDouble();
            entry.cacheRead = o.value(QStringLiteral("cacheRead")).toDouble();
            entry.cacheWrite = o.value(QStringLiteral("cacheWrite")).toDouble();
            overrides.insert(qs::plugins::normalizeModelId(it.key()), entry);
        }
    }

    QFile apiFile(QString::fromLocal8Bit(argv[2]));
    if (!apiFile.open(QIODevice::ReadOnly)) {
        QTextStream(stderr) << "Cannot read " << argv[2] << '\n';
        return 1;
    }
    QJsonParseError parseError{};
    const QJsonDocument api = QJsonDocument::fromJson(apiFile.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        QTextStream(stderr) << "Invalid api.json: " << parseError.errorString() << '\n';
        return 1;
    }

    int providers = 0;
    const qs::plugins::PriceIndex index =
        qs::plugins::buildPriceIndex(api, markers, &providers);

    const QStringList args = app.arguments().mid(3);

    QJsonArray results;
    for (const QString &name : args) {
        qs::plugins::PriceEntry entry;
        bool viaFallback = false;
        bool isOverride = false;
        QString matchedId;
        QJsonObject item;
        item[QStringLiteral("name")] = name;
        if (qs::plugins::resolvePrice(index, name, suffixes, &entry, &viaFallback, overrides, &isOverride, &matchedId)) {
            QJsonObject price;
            price[QStringLiteral("provider")] = entry.providerId;
            price[QStringLiteral("family")] = entry.family;
            price[QStringLiteral("input")] = entry.input;
            price[QStringLiteral("output")] = entry.output;
            price[QStringLiteral("cacheRead")] = entry.cacheRead;
            price[QStringLiteral("cacheWrite")] = entry.cacheWrite;
            price[QStringLiteral("viaFallback")] = viaFallback;
            price[QStringLiteral("isOverride")] = isOverride;
            price[QStringLiteral("matchedId")] = matchedId;
            item[QStringLiteral("found")] = true;
            item[QStringLiteral("price")] = price;
        } else {
            item[QStringLiteral("found")] = false;
        }
        results.append(item);
    }
    QJsonObject root;
    root[QStringLiteral("providers")] = providers;
    root[QStringLiteral("models")] = static_cast<int>(index.size());
    root[QStringLiteral("results")] = results;
    out << QJsonDocument(root).toJson(QJsonDocument::Indented) << '\n';
    return 0;
}
