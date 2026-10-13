#pragma once

#include "DockerState.hpp"
#include <UnixHttpClient.hpp>

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>
#include <QVariantMap>

namespace qs::plugins {

using qs::HttpResponse;
using qs::ActionResult;

struct LogsResult {
    bool ok{false};
    int statusCode{0};
    QString logs;
    QString error;
};

class DockerSocketClient : public qs::UnixHttpClient {
public:
    static constexpr const char *kApiPrefix = "/v1.56";

    explicit DockerSocketClient(QString socketPath = QString());

    bool fetchFullState(DockerState &outState) const;
    bool ping(QString *errOut = nullptr) const;

    ActionResult startContainer(const QString &id) const;
    ActionResult stopContainer(const QString &id, int timeoutSec = 10) const;
    ActionResult restartContainer(const QString &id, int timeoutSec = 10) const;
    ActionResult killContainer(const QString &id, const QString &signal = QStringLiteral("SIGKILL")) const;
    ActionResult removeContainer(const QString &id, bool force = false, bool removeVolumes = false) const;

    ActionResult removeImage(const QString &name, bool force = false) const;
    ActionResult removeVolume(const QString &name, bool force = false) const;

    ActionResult prune(const QString &kind) const; // containers|images|volumes|build

    // On-demand logs: follow=0, combined stdout+stderr => plain text (no 8-byte framing)
    LogsResult fetchLogs(const QString &id, int tail = 200) const;

    // On-demand inspect (size=0, no expensive SizeRw computation)
    HttpResponse fetchInspect(const QString &id) const;

    static bool openPath(const QString &path);
    static bool openUrl(const QString &url);

protected:
    [[nodiscard]] QString resolveSocketPath() const override;

private:
    static QString findDockerSocket();
    static QString errorMessageFor(const HttpResponse &resp);
};

} // namespace qs::plugins
