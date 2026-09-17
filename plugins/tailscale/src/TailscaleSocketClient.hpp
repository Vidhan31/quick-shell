#pragma once

#include "TailscaleState.hpp"

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

namespace qs::plugins {

struct HttpResponse {
    int statusCode{0};
    QByteArray statusText;
    QByteArray headers;
    QByteArray body;
    bool ok{false};
    QString error;

    [[nodiscard]] QJsonDocument toJson() const {
        return QJsonDocument::fromJson(body);
    }
};

struct PingResult {
    bool ok{false};
    QString targetIp;
    QString latency;
    double latencyMs{0.0};
    QString endpoint;
    QString output;
    QString error;
};

struct ActionResult {
    bool ok{false};
    QString output;
    QString error;
};

class TailscaleSocketClient {
public:
    explicit TailscaleSocketClient(QString socketPath = QString());

    [[nodiscard]] QString socketPath() const;
    void setSocketPath(const QString &path);

    // Low-level HTTP over Unix Domain Socket
    HttpResponse request(const QString &method,
                         const QString &path,
                         const QByteArray &body = QByteArray(),
                         int timeoutMs = 4000) const;

    // Full state query (combines /status, /prefs, /serve-config, /services)
    bool fetchFullStatus(TailscaleState &outState) const;

    // Preferences and Toggles via LocalAPI (PATCH /localapi/v0/prefs)
    bool setPref(const QString &key, const QJsonValue &val, QString *errOut = nullptr) const;
    bool setWantRunning(bool up, QString *errOut = nullptr) const;
    bool setSSH(bool enable, QString *errOut = nullptr) const;
    bool setShieldsUp(bool enable, QString *errOut = nullptr) const;
    bool setWebClient(bool enable, QString *errOut = nullptr) const;
    bool setAdvertiseExitNode(bool enable, QString *errOut = nullptr) const;

    // Diagnostics
    PingResult ping(const QString &ip, int timeoutMs = 4000) const;
    ActionResult runNetcheck(int timeoutMs = 10000) const;

    // Serve & Funnel operations (direct CLI execution via binary)
    ActionResult serveStart(const QString &target,
                            const QString &mode = QStringLiteral("serve"),
                            const QString &port = QStringLiteral("443"),
                            const QString &path = QStringLiteral("/")) const;
    ActionResult serveStop(const QString &port = QStringLiteral("443"),
                           const QString &path = QString()) const;
    ActionResult funnelToggle(const QString &port,
                              const QString &target,
                              bool isFunnel,
                              const QString &path = QStringLiteral("/")) const;
    ActionResult serveReset() const;

    // Utility actions
    static bool copyToClipboard(const QString &text);
    static bool openUrl(const QString &url);

private:
    static QByteArray decodeChunked(const QByteArray &chunkedData);
    static QString findTailscaleSocket();
    static ActionResult runTailscaleCli(const QStringList &args, int timeoutMs = 10000);

    mutable QString m_socketPath;
};

} // namespace qs::plugins
