#pragma once

#include "DockerState.hpp"

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>
#include <QVariantMap>

#include <mutex>

namespace qs::plugins {

struct HttpResponse {
    int statusCode{0};
    QByteArray statusText;
    QByteArray headers;
    QByteArray body;
    bool ok{false}; // 2xx only. 304/409/403 are NOT ok — caller decides.
    QString error;  // transport-level error (connect/read/malformed)

    [[nodiscard]] QJsonDocument toJson() const {
        return QJsonDocument::fromJson(body);
    }

    [[nodiscard]] QString apiMessage() const {
        // ErrorResponse: {"message": "..."}
        const QJsonDocument doc = toJson();
        if (doc.isObject()) {
            const QString msg = doc.object().value(QStringLiteral("message")).toString();
            if (!msg.isEmpty()) {
                return msg;
            }
        }
        if (!body.isEmpty()) {
            return QString::fromUtf8(body).trimmed();
        }
        return QString::fromUtf8(statusText);
    }
};

struct ActionResult {
    bool ok{false};
    int statusCode{0};
    QString output; // api message or body text
    QString error;
};

struct LogsResult {
    bool ok{false};
    int statusCode{0};
    QString logs;
    QString error;
};

class DockerSocketClient {
public:
    static constexpr const char *kApiPrefix = "/v1.56";

    explicit DockerSocketClient(QString socketPath = QString());

    [[nodiscard]] QString socketPath() const;
    void setSocketPath(const QString &path);

    // Low-level HTTP over Unix Domain Socket (blocking, Connection: close)
    HttpResponse request(const QString &method,
                         const QString &path,
                         const QByteArray &body = QByteArray(),
                         int timeoutMs = 4000) const;

    // Read-only aggregate (ping + version + info + lists + df)
    bool fetchFullState(DockerState &outState) const;
    bool ping(QString *errOut = nullptr) const;

    // Container lifecycle. 204 + 304(already) = success.
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

    // Unblocks a request() that is parked in a blocking read(), so a worker
    // thread can be stopped without waiting out the socket timeout. Safe to call
    // from another thread and when no request is in flight.
    void cancel() const;

    // True while a cancel() is in effect, i.e. the last request did not run to
    // completion. Callers use it to avoid publishing a truncated result.
    [[nodiscard]] bool cancelled() const;

private:
    static bool decodeChunked(const QByteArray &in, QByteArray *out, QString *error);
    static bool isChunkedEncoding(const QByteArray &headers);
    static QString findDockerSocket();
    static QString errorMessageFor(const HttpResponse &resp);

    void publishFd(int fd) const;
    void withdrawFd(int fd) const;

    mutable QString m_socketPath;
    mutable std::mutex m_fdMutex;
    mutable int m_activeFd{-1};
    // Latched by cancel() so a read() that returns EOF (rather than an error)
    // is still recognised as a cancellation instead of a short response.
    mutable bool m_cancelRequested{false};
};

} // namespace qs::plugins
