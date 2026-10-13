#pragma once

#include "TailscaleState.hpp"
#include <UnixHttpClient.hpp>

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

namespace qs::plugins {

using qs::HttpResponse;
using qs::ActionResult;

struct PingResult {
    bool ok{false};
    QString targetIp;
    QString latency;
    double latencyMs{0.0};
    QString endpoint;
    QString output;
    QString error;
};

class TailscaleSocketClient : public qs::UnixHttpClient {
public:
    explicit TailscaleSocketClient(QString socketPath = QString());

    // Full state query (combines /status, /prefs, /serve-config, /services)
    bool fetchFullStatus(TailscaleState &outState) const;

    // Preferences and Toggles via LocalAPI (PATCH /localapi/v0/prefs)
    bool setPref(const QString &key, const QJsonValue &val, QString *errOut = nullptr) const;
    bool setWantRunning(bool up, QString *errOut = nullptr) const;
    bool setSSH(bool enable, QString *errOut = nullptr) const;
    bool setShieldsUp(bool enable, QString *errOut = nullptr) const;
    bool setWebClient(bool enable, QString *errOut = nullptr) const;
    bool setAdvertiseExitNode(bool enable, QString *errOut = nullptr) const;

    PingResult ping(const QString &ip, int timeoutMs = 4000) const;
    ActionResult runNetcheck(int timeoutMs = 10000) const;

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

    static bool copyToClipboard(const QString &text);
    static bool openUrl(const QString &url);

protected:
    [[nodiscard]] QString resolveSocketPath() const override;

private:
    static QString findTailscaleSocket();
    static ActionResult runTailscaleCli(const QStringList &args, int timeoutMs = 10000);
};

} // namespace qs::plugins
