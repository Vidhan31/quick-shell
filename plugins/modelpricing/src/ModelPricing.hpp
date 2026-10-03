#pragma once

#include <QMap>
#include <QObject>
#include <QThread>
#include <QUrl>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QJsonDocument;
class QJsonObject;
class QNetworkAccessManager;
class QNetworkReply;

namespace qs::plugins {

// Official API price for one model, USD per million tokens.
// Missing upstream keys default to 0 (e.g. models without cache pricing).
struct PriceEntry {
    QString providerId;
    QString family;
    double input = 0.0;
    double output = 0.0;
    double cacheRead = 0.0;
    double cacheWrite = 0.0;

    [[nodiscard]] bool isValid() const { return !providerId.isEmpty(); }
};

using PriceIndex = QMap<QString, PriceEntry>;

// Everything the worker needs; all strings come from assets config,
// never from compiled-in tables.
struct PricingSettings {
    QString endpoint;
    QStringList gatewayNpmMarkers;
    QStringList tierSuffixes;
    QString logoBase;
    QString rawCachePath;
    QString etagPath;
    QString indexCachePath;
    QString logoDir;
    int ttlHours = 24;
};

// Worker result. The index travels as QVariant data so no custom
// metatype registration is needed for the queued signal.
struct PricingFetchResult {
    bool ok = false;
    bool notModified = false;
    QString error;
    QVariantMap index; // normalized model id -> entry map
    int providerCount = 0;
    QString fetchedAtIso;
    QString etag;
};

// Lowercase + trim. The only normalization: no per-model special cases.
QString normalizeModelId(const QString &name);

// Exact match first, then one trailing tier-suffix strip. Returns false
// when no official entry exists; the caller then shows no cost.
bool resolvePrice(const PriceIndex &index,
                  const QString &name,
                  const QStringList &suffixes,
                  PriceEntry *out,
                  bool *viaFallback,
                  const PriceIndex &overrides = {},
                  bool *isOverride = nullptr,
                  QString *matchedId = nullptr);

// (input*in + output*out + cacheRead*cr + cacheWrite*cw + reasoning*out)/1e6.
// Reasoning bills at the output rate: upstream rarely prices it separately.
double priceEntryCost(const PriceEntry &entry,
                      qlonglong input,
                      qlonglong output,
                      qlonglong cacheRead,
                      qlonglong cacheWrite,
                      qlonglong reasoning);

// Reverse index over a models.dev api.json document. Providers whose npm
// handle contains a gateway marker are excluded as non-official mirrors;
// among the remaining owners the most family-concentrated one wins.
PriceIndex buildPriceIndex(const QJsonDocument &document,
                           const QStringList &gatewayNpmMarkers,
                           int *providerCount);

QString pricingMarkersHash(const QStringList &markers, const QStringList &suffixes);

PriceEntry priceEntryFromMap(const QVariantMap &map);
QVariantMap priceEntryToMap(const QString &modelId, const PriceEntry &entry, bool viaFallback);
PriceIndex priceIndexFromVariant(const QVariantMap &map);
QVariantMap priceIndexToVariant(const PriceIndex &index);

class PricingWorker : public QObject {
    Q_OBJECT

public:
    explicit PricingWorker(QObject *parent = nullptr);

public slots:
    void fetch(const PricingSettings &settings, const QString &etag);

signals:
    void fetched(const PricingFetchResult &result);

private:
    void onReplyFinished();

    ::QNetworkAccessManager *m_nam{nullptr};
    ::QNetworkReply *m_reply{nullptr};
    PricingSettings m_settings;
};

class ModelPricing : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QUrl configSource READ configSource WRITE setConfigSource NOTIFY configSourceChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)
    Q_PROPERTY(bool ready READ isReady NOTIFY dataChanged)
    Q_PROPERTY(int modelCount READ modelCount NOTIFY dataChanged)
    Q_PROPERTY(int providerCount READ providerCount NOTIFY dataChanged)
    Q_PROPERTY(QString lastRefresh READ lastRefresh NOTIFY dataChanged)
    Q_PROPERTY(QString error READ error NOTIFY dataChanged)

public:
    explicit ModelPricing(QObject *parent = nullptr);
    ~ModelPricing() override;

    [[nodiscard]] QUrl configSource() const { return m_configSource; }
    [[nodiscard]] bool isBusy() const { return m_busy; }
    [[nodiscard]] bool isReady() const { return m_ready; }
    [[nodiscard]] int modelCount() const { return m_index.size(); }
    [[nodiscard]] int providerCount() const { return m_providerCount; }
    [[nodiscard]] QString lastRefresh() const { return m_lastRefresh; }
    [[nodiscard]] QString error() const { return m_error; }

    void setConfigSource(const QUrl &url);

    // Empty map when no official entry exists (caller shows no cost).
    Q_INVOKABLE QVariantMap priceForModel(const QString &name) const;
    // NaN when no official entry exists.
    Q_INVOKABLE double costForModel(const QString &name,
                                    qlonglong input,
                                    qlonglong output,
                                    qlonglong cacheRead,
                                    qlonglong cacheWrite,
                                    qlonglong reasoning) const;
    // Estimated USD saved through prompt caching for this model.
    Q_INVOKABLE double savingsForModel(const QString &name, qlonglong cacheRead) const;
    // Local cached logo file when present, else the remote URL (which also
    // enqueues a background download for next time).
    Q_INVOKABLE QString logoForProvider(const QString &providerId);

    Q_INVOKABLE void refresh();

signals:
    void dataChanged();
    void busyChanged();
    void configSourceChanged();
    void requestFetch(const PricingSettings &settings, const QString &etag);

private slots:
    void onFetched(const PricingFetchResult &result);

private:
    void loadConfig();
    void loadIndexCache();
    void saveIndexCache(const QString &fetchedAtIso) const;
    void maybeAutoRefresh();
    [[nodiscard]] bool indexStale() const;
    [[nodiscard]] QString readEtag() const;
    static QString displayTime(const QString &iso);

    QThread m_thread;
    PricingWorker *m_worker{nullptr};
    ::QNetworkAccessManager *m_logoNam{nullptr};

    QUrl m_configSource;
    PricingSettings m_settings;
    bool m_settingsOk{false};
    PriceIndex m_index;
    PriceIndex m_overrides;
    int m_providerCount{0};
    QString m_fetchedAtIso;
    QString m_lastRefresh;
    QString m_error;
    bool m_busy{false};
    bool m_ready{false};
};

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::PricingSettings)
Q_DECLARE_METATYPE(qs::plugins::PricingFetchResult)
