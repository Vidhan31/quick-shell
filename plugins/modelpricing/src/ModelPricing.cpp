#include "ModelPricing.hpp"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QSet>
#include <QTimer>
#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>
#include <vector>

namespace qs::plugins {

namespace {

constexpr int kIndexVersion = 1;
constexpr int kTransferTimeoutMs = 30000;

QString pricingCacheDir() {
    QString cacheHome = QString::fromLocal8Bit(qgetenv("XDG_CACHE_HOME")).trimmed();
    if (cacheHome.isEmpty()) {
        cacheHome = QDir::homePath() + QStringLiteral("/.cache");
    }
    return cacheHome + QStringLiteral("/quick-shell");
}

QString pricingDisplayNow() {
    return QDateTime::currentDateTime().toString(QStringLiteral("d MMM yyyy, hh:mm AP"));
}

QString sanitizeProviderId(const QString &providerId) {
    QString clean;
    clean.reserve(providerId.size());
    for (const QChar c : providerId.toLower()) {
        if (c.isLetterOrNumber() || c == u'-' || c == u'_') {
            clean.append(c);
        }
    }
    return clean;
}

bool isGatewayNpm(const QString &npm, const QStringList &markers) {
    const QString lowered = npm.toLower();
    for (const QString &marker : markers) {
        if (!marker.trimmed().isEmpty() && lowered.contains(marker.trimmed().toLower())) {
            return true;
        }
    }
    return false;
}

void parseOverrides(const QJsonObject &obj, PriceIndex &out) {
    for (auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
        if (!it.value().isObject()) continue;
        const QJsonObject item = it.value().toObject();
        PriceEntry entry;
        entry.providerId = item.value(QStringLiteral("provider")).toString(QStringLiteral("custom")).trimmed();
        entry.family = item.value(QStringLiteral("family")).toString(QStringLiteral("custom")).trimmed();
        entry.input = item.value(QStringLiteral("input")).toDouble(0.0);
        entry.output = item.value(QStringLiteral("output")).toDouble(0.0);
        entry.cacheRead = item.contains(QStringLiteral("cacheRead"))
            ? item.value(QStringLiteral("cacheRead")).toDouble(entry.input)
            : entry.input;
        entry.cacheWrite = item.contains(QStringLiteral("cacheWrite"))
            ? item.value(QStringLiteral("cacheWrite")).toDouble(entry.input)
            : entry.input;
        out.insert(it.key().trimmed().toLower(), entry);
    }
}

} // namespace

QString pricingMarkersHash(const QStringList &markers, const QStringList &suffixes) {
    const QByteArray joined = (markers.join(u',') + u'|' + suffixes.join(u',')).toUtf8();
    return QString::number(qHash(joined), 16);
}

QString normalizeModelId(const QString &name) {
    return name.trimmed().toLower();
}

bool resolvePrice(const PriceIndex &index,
                  const QString &name,
                  const QStringList &suffixes,
                  PriceEntry *out,
                  bool *viaFallback,
                  const PriceIndex &overrides,
                  bool *isOverride,
                  QString *matchedId) {
    const QString key = normalizeModelId(name);
    if (isOverride != nullptr) {
        *isOverride = false;
    }
    if (viaFallback != nullptr) {
        *viaFallback = false;
    }

    auto oExact = overrides.constFind(key);
    if (oExact != overrides.constEnd()) {
        if (out != nullptr) *out = oExact.value();
        if (isOverride != nullptr) *isOverride = true;
        if (matchedId != nullptr) *matchedId = key;
        return true;
    }

    auto exact = index.constFind(key);
    if (exact != index.constEnd()) {
        if (out != nullptr) *out = exact.value();
        if (matchedId != nullptr) *matchedId = key;
        return true;
    }

    QStringList ordered = suffixes;
    std::sort(ordered.begin(), ordered.end(), [](const QString &a, const QString &b) {
        return a.size() > b.size();
    });
    for (const QString &suffix : ordered) {
        const QString trimmed = suffix.trimmed().toLower();
        if (trimmed.isEmpty() || !key.endsWith(trimmed)) {
            continue;
        }
        const QString stripped = key.left(key.size() - trimmed.size());
        auto oHit = overrides.constFind(stripped);
        if (oHit != overrides.constEnd()) {
            if (out != nullptr) *out = oHit.value();
            if (viaFallback != nullptr) *viaFallback = true;
            if (isOverride != nullptr) *isOverride = true;
            if (matchedId != nullptr) *matchedId = stripped;
            return true;
        }
        auto hit = index.constFind(stripped);
        if (hit != index.constEnd()) {
            if (out != nullptr) *out = hit.value();
            if (viaFallback != nullptr) *viaFallback = true;
            if (matchedId != nullptr) *matchedId = stripped;
            return true;
        }
    }
    return false;
}

double priceEntryCost(const PriceEntry &entry,
                      qlonglong input,
                      qlonglong output,
                      qlonglong cacheRead,
                      qlonglong cacheWrite,
                      qlonglong reasoning) {
    const double total = static_cast<double>(input) * entry.input
        + static_cast<double>(output + reasoning) * entry.output
        + static_cast<double>(cacheRead) * entry.cacheRead
        + static_cast<double>(cacheWrite) * entry.cacheWrite;
    return total / 1e6;
}

PriceIndex buildPriceIndex(const QJsonDocument &document,
                           const QStringList &gatewayNpmMarkers,
                           int *providerCount) {
    PriceIndex index;
    if (providerCount != nullptr) {
        *providerCount = 0;
    }
    if (!document.isObject()) {
        return index;
    }
    const QJsonObject root = document.object();

    struct Owner {
        QString providerId;
        QString npm;
        QString family;
        PriceEntry entry;
    };
    QMap<QString, std::vector<Owner>> owners;
    QMap<QString, int> providerModelCount;
    QMap<QString, QMap<QString, int>> providerFamilies;

    for (auto it = root.constBegin(); it != root.constEnd(); ++it) {
        if (!it.value().isObject()) {
            continue;
        }
        const QJsonObject provider = it.value().toObject();
        const QString providerId = provider.value(QStringLiteral("id")).toString(it.key());
        const QString npm = provider.value(QStringLiteral("npm")).toString();
        const QJsonValue modelsValue = provider.value(QStringLiteral("models"));
        if (!modelsValue.isObject()) {
            continue;
        }
        const QJsonObject models = modelsValue.toObject();
        if (providerCount != nullptr) {
            *providerCount += 1;
        }
        for (auto mit = models.constBegin(); mit != models.constEnd(); ++mit) {
            if (!mit.value().isObject()) {
                continue;
            }
            const QJsonObject model = mit.value().toObject();
            const QJsonValue costValue = model.value(QStringLiteral("cost"));
            if (!costValue.isObject()) {
                continue; // Unknown pricing: unpriceable, skip the owner.
            }
            const QJsonObject cost = costValue.toObject();
            Owner owner;
            owner.providerId = providerId;
            owner.npm = npm;
            owner.family = model.value(QStringLiteral("family")).toString();
            owner.entry.providerId = providerId;
            owner.entry.family = owner.family;
            owner.entry.input = cost.value(QStringLiteral("input")).toDouble();
            owner.entry.output = cost.value(QStringLiteral("output")).toDouble();
            owner.entry.cacheRead = cost.value(QStringLiteral("cache_read")).toDouble();
            owner.entry.cacheWrite = cost.value(QStringLiteral("cache_write")).toDouble();
            providerModelCount[providerId] += 1;
            providerFamilies[providerId][owner.family] += 1;
            owners[normalizeModelId(mit.key())].push_back(std::move(owner));
        }
    }

    // Official pick per model: skip gateway mirrors, then prefer the owner
    // most concentrated in the model's own family (fewest models breaks ties).
    for (auto it = owners.constBegin(); it != owners.constEnd(); ++it) {
        const Owner *best = nullptr;
        double bestShare = -1.0;
        int bestCount = 0;
        for (const Owner &owner : it.value()) {
            if (isGatewayNpm(owner.npm, gatewayNpmMarkers)) {
                continue;
            }
            const int total = providerModelCount.value(owner.providerId, 1);
            const int familyCount = providerFamilies.value(owner.providerId).value(owner.family, 0);
            const double share = static_cast<double>(familyCount) / static_cast<double>(total);
            if (best == nullptr || share > bestShare
                || (share == bestShare && total < bestCount)) {
                best = &owner;
                bestShare = share;
                bestCount = total;
            }
        }
        if (best != nullptr) {
            index.insert(it.key(), best->entry);
        }
    }
    return index;
}

PriceEntry priceEntryFromMap(const QVariantMap &map) {
    PriceEntry entry;
    entry.providerId = map.value(QStringLiteral("provider")).toString();
    entry.family = map.value(QStringLiteral("family")).toString();
    entry.input = map.value(QStringLiteral("input")).toDouble();
    entry.output = map.value(QStringLiteral("output")).toDouble();
    entry.cacheRead = map.value(QStringLiteral("cacheRead")).toDouble();
    entry.cacheWrite = map.value(QStringLiteral("cacheWrite")).toDouble();
    return entry;
}

QVariantMap priceEntryToMap(const QString &modelId, const PriceEntry &entry, bool viaFallback) {
    QVariantMap map;
    map.insert(QStringLiteral("matchedId"), modelId);
    map.insert(QStringLiteral("provider"), entry.providerId);
    map.insert(QStringLiteral("family"), entry.family);
    map.insert(QStringLiteral("input"), entry.input);
    map.insert(QStringLiteral("output"), entry.output);
    map.insert(QStringLiteral("cacheRead"), entry.cacheRead);
    map.insert(QStringLiteral("cacheWrite"), entry.cacheWrite);
    map.insert(QStringLiteral("viaFallback"), viaFallback);
    return map;
}

PriceIndex priceIndexFromVariant(const QVariantMap &map) {
    PriceIndex index;
    for (auto it = map.constBegin(); it != map.constEnd(); ++it) {
        if (!it.value().canConvert<QVariantMap>()) {
            continue;
        }
        PriceEntry entry = priceEntryFromMap(it.value().toMap());
        if (entry.isValid()) {
            index.insert(it.key(), entry);
        }
    }
    return index;
}

QVariantMap priceIndexToVariant(const PriceIndex &index) {
    QVariantMap map;
    for (auto it = index.constBegin(); it != index.constEnd(); ++it) {
        map.insert(it.key(), priceEntryToMap(it.key(), it.value(), false));
    }
    return map;
}

PricingWorker::PricingWorker(QObject *parent)
    : QObject(parent) {}

void PricingWorker::fetch(const PricingSettings &settings, const QString &etag) {
    if (m_reply != nullptr) {
        return; // One flight at a time; the main object guards busy.
    }
    m_settings = settings;
    if (m_nam == nullptr) {
        m_nam = new QNetworkAccessManager(this);
        m_nam->setTransferTimeout(kTransferTimeoutMs);
    }
    QNetworkRequest request(settings.endpoint);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("quick-shell-modelpricing/1.0"));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    if (!etag.isEmpty()) {
        request.setRawHeader("If-None-Match", etag.toLatin1());
    }
    m_reply = m_nam->get(request);
    connect(m_reply, &QNetworkReply::finished, this, &PricingWorker::onReplyFinished);
}

void PricingWorker::onReplyFinished() {
    QNetworkReply *reply = m_reply;
    m_reply = nullptr;
    PricingFetchResult result;
    if (reply == nullptr) {
        return;
    }
    reply->deleteLater();
    if (reply->error() != QNetworkReply::NoError) {
        result.error = reply->errorString();
        emit fetched(result);
        return;
    }
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status == 304) {
        result.ok = true;
        result.notModified = true;
        result.fetchedAtIso = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
        emit fetched(result);
        return;
    }
    if (status != 200) {
        result.error = QStringLiteral("HTTP %1").arg(status);
        emit fetched(result);
        return;
    }
    const QByteArray payload = reply->readAll();
    const QString newEtag =
        QString::fromLatin1(reply->rawHeader("ETag")).trimmed().remove(u'"');
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        result.error = parseError.errorString();
        emit fetched(result);
        return;
    }
    int providers = 0;
    const PriceIndex index = buildPriceIndex(document, m_settings.gatewayNpmMarkers, &providers);
    if (index.isEmpty()) {
        result.error = QStringLiteral("No priced models in response");
        emit fetched(result);
        return;
    }
    // Persist the raw payload + etag so a config change can re-derive
    // without another download, and 304s stay download-free.
    QDir().mkpath(pricingCacheDir());
    {
        QSaveFile rawFile(m_settings.rawCachePath);
        if (rawFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            rawFile.write(payload);
            rawFile.commit();
        }
    }
    if (!newEtag.isEmpty()) {
        QSaveFile etagFile(m_settings.etagPath);
        if (etagFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            etagFile.write(newEtag.toLatin1());
            etagFile.commit();
        }
    }
    result.ok = true;
    result.index = priceIndexToVariant(index);
    result.providerCount = providers;
    result.fetchedAtIso = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    result.etag = newEtag;
    emit fetched(result);
}

ModelPricing::ModelPricing(QObject *parent)
    : QObject(parent) {
    qRegisterMetaType<PricingSettings>();
    qRegisterMetaType<PricingFetchResult>();
    m_worker = new PricingWorker();
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &ModelPricing::requestFetch, m_worker, &PricingWorker::fetch);
    connect(m_worker, &PricingWorker::fetched, this, &ModelPricing::onFetched);
    m_thread.start();
}

ModelPricing::~ModelPricing() {
    m_thread.quit();
    m_thread.wait();
}

void ModelPricing::setConfigSource(const QUrl &url) {
    if (m_configSource == url) {
        return;
    }
    m_configSource = url;
    emit configSourceChanged();
    loadConfig();
}

void ModelPricing::loadConfig() {
    m_settingsOk = false;
    if (!m_configSource.isLocalFile()) {
        m_error = QStringLiteral("Pricing config is not a local file");
        emit dataChanged();
        return;
    }
    QFile file(m_configSource.toLocalFile());
    if (!file.open(QIODevice::ReadOnly)) {
        m_error = QStringLiteral("Cannot read pricing config");
        emit dataChanged();
        return;
    }
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        m_error = QStringLiteral("Pricing config is not valid JSON");
        emit dataChanged();
        return;
    }
    const QJsonObject config = document.object();
    PricingSettings settings;
    settings.endpoint = config.value(QStringLiteral("endpoint")).toString().trimmed();
    for (const QJsonValue &value : config.value(QStringLiteral("gatewayNpmMarkers")).toArray()) {
        settings.gatewayNpmMarkers.append(value.toString());
    }
    for (const QJsonValue &value : config.value(QStringLiteral("tierSuffixes")).toArray()) {
        settings.tierSuffixes.append(value.toString());
    }
    settings.logoBase = config.value(QStringLiteral("logoBase")).toString().trimmed();
    settings.ttlHours = config.value(QStringLiteral("ttlHours")).toInt(24);
    if (settings.endpoint.isEmpty() || settings.logoBase.isEmpty()) {
        m_error = QStringLiteral("Pricing config is incomplete");
        emit dataChanged();
        return;
    }
    if (!settings.logoBase.endsWith(u'/')) {
        settings.logoBase.append(u'/');
    }
    const QString dir = pricingCacheDir();
    settings.rawCachePath = dir + QStringLiteral("/model-pricing-api.json");
    settings.etagPath = dir + QStringLiteral("/model-pricing.etag");
    settings.indexCachePath = dir + QStringLiteral("/model-pricing-index.json");
    settings.logoDir = dir + QStringLiteral("/model-pricing-logos");
    m_settings = settings;
    m_settingsOk = true;
    m_overrides.clear();
    parseOverrides(config.value(QStringLiteral("overrides")).toObject(), m_overrides);
    const QString userOverridesPath = QDir::homePath() + QStringLiteral("/.config/quick-shell/pricing-overrides.json");
    QFile userOverridesFile(userOverridesPath);
    if (userOverridesFile.open(QIODevice::ReadOnly)) {
        const QJsonDocument uDoc = QJsonDocument::fromJson(userOverridesFile.readAll());
        if (uDoc.isObject()) {
            parseOverrides(uDoc.object(), m_overrides);
        }
    }
    loadIndexCache();
    if (m_ready) {
        maybeAutoRefresh();
    }
}

void ModelPricing::loadIndexCache() {
    if (!m_settingsOk) {
        return;
    }
    QFile file(m_settings.indexCachePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        return;
    }
    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("version")).toInt() != kIndexVersion) {
        return;
    }
    const QJsonValue models = root.value(QStringLiteral("models"));
    if (!models.isObject()) {
        return;
    }
    m_index = priceIndexFromVariant(models.toObject().toVariantMap());
    if (m_index.isEmpty()) {
        return;
    }
    m_providerCount = root.value(QStringLiteral("providers")).toInt();
    m_fetchedAtIso = root.value(QStringLiteral("fetchedAt")).toString();
    m_lastRefresh = displayTime(m_fetchedAtIso);
    m_ready = true;
    emit dataChanged();
}

void ModelPricing::saveIndexCache(const QString &fetchedAtIso) const {
    if (!m_settingsOk) {
        return;
    }
    QDir().mkpath(pricingCacheDir());
    QJsonObject root;
    root[QStringLiteral("version")] = kIndexVersion;
    root[QStringLiteral("fetchedAt")] = fetchedAtIso;
    root[QStringLiteral("markersHash")] =
        pricingMarkersHash(m_settings.gatewayNpmMarkers, m_settings.tierSuffixes);
    root[QStringLiteral("providers")] = m_providerCount;
    root[QStringLiteral("models")] = QJsonObject::fromVariantMap(priceIndexToVariant(m_index));
    QSaveFile file(m_settings.indexCachePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    file.commit();
}

bool ModelPricing::indexStale() const {
    if (m_fetchedAtIso.isEmpty()) {
        return true;
    }
    const QDateTime fetched = QDateTime::fromString(m_fetchedAtIso, Qt::ISODate);
    if (!fetched.isValid()) {
        return true;
    }
    const int ttl = m_settingsOk && m_settings.ttlHours > 0 ? m_settings.ttlHours : 24;
    return fetched.secsTo(QDateTime::currentDateTimeUtc()) > static_cast<qint64>(ttl) * 3600;
}

void ModelPricing::maybeAutoRefresh() {
    if (!m_ready || m_busy || !m_settingsOk || !indexStale()) {
        return;
    }
    refresh();
}

QString ModelPricing::readEtag() const {
    if (!m_settingsOk) {
        return {};
    }
    QFile file(m_settings.etagPath);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QString etag = QString::fromLatin1(file.readAll()).trimmed().remove(u'"');
    // A config change invalidates conditional requests: without the raw
    // re-derive path a 304 could not apply the new markers.
    QFile indexFile(m_settings.indexCachePath);
    if (indexFile.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(indexFile.readAll());
        if (document.isObject()) {
            const QString cachedHash =
                document.object().value(QStringLiteral("markersHash")).toString();
            if (!cachedHash.isEmpty()
                && cachedHash
                    != pricingMarkersHash(m_settings.gatewayNpmMarkers,
                                           m_settings.tierSuffixes)) {
                return {};
            }
        }
    }
    return etag;
}

QString ModelPricing::displayTime(const QString &iso) {
    const QDateTime parsed = QDateTime::fromString(iso, Qt::ISODate);
    if (!parsed.isValid()) {
        return iso;
    }
    return parsed.toLocalTime().toString(QStringLiteral("d MMM yyyy, hh:mm AP"));
}

QVariantMap ModelPricing::priceForModel(const QString &name) const {
    PriceEntry entry;
    bool viaFallback = false;
    bool isOverride = false;
    QString matchedId;
    if (!resolvePrice(m_index, name, m_settings.tierSuffixes, &entry, &viaFallback, m_overrides, &isOverride, &matchedId)) {
        QVariantMap empty;
        empty.insert(QStringLiteral("isValid"), false);
        empty.insert(QStringLiteral("costSource"), QStringLiteral("unpriced"));
        return empty;
    }
    QVariantMap map = priceEntryToMap(matchedId.isEmpty() ? normalizeModelId(name) : matchedId, entry, viaFallback);
    map.insert(QStringLiteral("isValid"), true);
    map.insert(QStringLiteral("isOverride"), isOverride);
    QString costSource = QStringLiteral("official");
    if (isOverride) {
        costSource = QStringLiteral("override");
    } else if (viaFallback) {
        costSource = QStringLiteral("fallbackTier");
    }
    map.insert(QStringLiteral("costSource"), costSource);
    if (m_settingsOk) {
        map.insert(QStringLiteral("logo"),
                   m_settings.logoBase + sanitizeProviderId(entry.providerId)
                       + QStringLiteral(".svg"));
    }
    return map;
}

double ModelPricing::costForModel(const QString &name,
                                  qlonglong input,
                                  qlonglong output,
                                  qlonglong cacheRead,
                                  qlonglong cacheWrite,
                                  qlonglong reasoning) const {
    PriceEntry entry;
    bool viaFallback = false;
    if (!resolvePrice(m_index, name, m_settings.tierSuffixes, &entry, &viaFallback, m_overrides)) {
        return std::numeric_limits<double>::quiet_NaN();
    }
    return priceEntryCost(entry, input, output, cacheRead, cacheWrite, reasoning);
}

double ModelPricing::savingsForModel(const QString &name, qlonglong cacheRead) const {
    if (cacheRead <= 0) {
        return 0.0;
    }
    PriceEntry entry;
    bool viaFallback = false;
    if (!resolvePrice(m_index, name, m_settings.tierSuffixes, &entry, &viaFallback, m_overrides)) {
        return 0.0;
    }
    const double diff = entry.input - entry.cacheRead;
    if (diff <= 0.0) {
        return 0.0;
    }
    return (static_cast<double>(cacheRead) * diff) / 1e6;
}

QString ModelPricing::logoForProvider(const QString &providerId) {
    const QString clean = sanitizeProviderId(providerId);
    if (clean.isEmpty() || !m_settingsOk) {
        return {};
    }
    const QString localPath = m_settings.logoDir + u'/' + clean + QStringLiteral(".svg");
    if (QFile::exists(localPath)) {
        return QStringLiteral("file://") + localPath;
    }
    const QString remote = m_settings.logoBase + clean + QStringLiteral(".svg");
    // Fetch in the background for next time; serve the remote URL meanwhile.
    static QSet<QString> inFlight;
    if (!inFlight.contains(clean)) {
        if (m_logoNam == nullptr) {
            m_logoNam = new QNetworkAccessManager(this);
            m_logoNam->setTransferTimeout(kTransferTimeoutMs);
        }
        inFlight.insert(clean);
        QNetworkRequest request(remote);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                             QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply *reply = m_logoNam->get(request);
        connect(reply, &QNetworkReply::finished, this, [this, reply, clean]() {
            reply->deleteLater();
            inFlight.remove(clean);
            if (reply->error() != QNetworkReply::NoError) {
                return;
            }
            const QByteArray data = reply->readAll();
            if (!data.trimmed().startsWith("<svg") && !data.contains("<svg")) {
                return;
            }
            QDir().mkpath(m_settings.logoDir);
            QSaveFile file(m_settings.logoDir + u'/' + clean + QStringLiteral(".svg"));
            if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                file.write(data);
                file.commit();
                emit dataChanged();
            }
        });
    }
    return remote;
}

void ModelPricing::refresh() {
    if (m_busy) {
        return;
    }
    if (!m_settingsOk) {
        m_error = QStringLiteral("Pricing config not loaded");
        emit dataChanged();
        return;
    }
    m_busy = true;
    emit busyChanged();
    emit requestFetch(m_settings, readEtag());
}

void ModelPricing::onFetched(const PricingFetchResult &result) {
    m_busy = false;
    if (!result.ok) {
        m_error = result.error.isEmpty() ? QStringLiteral("Pricing refresh failed") : result.error;
        emit busyChanged();
        emit dataChanged();
        return;
    }
    m_error.clear();
    if (!result.notModified) {
        m_index = priceIndexFromVariant(result.index);
        m_providerCount = result.providerCount;
    }
    m_fetchedAtIso = result.fetchedAtIso;
    m_lastRefresh = pricingDisplayNow();
    m_ready = !m_index.isEmpty();
    saveIndexCache(m_fetchedAtIso);
    emit busyChanged();
    emit dataChanged();
}

} // namespace qs::plugins
