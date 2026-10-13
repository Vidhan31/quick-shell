#pragma once

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

#include <mutex>

namespace qs {

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

    ActionResult() = default;
    ActionResult(bool ok, int statusCode, QString output, QString error = QString())
        : ok(ok), statusCode(statusCode), output(std::move(output)), error(std::move(error)) {}
    ActionResult(bool ok, QString output, QString error = QString())
        : ok(ok), statusCode(0), output(std::move(output)), error(std::move(error)) {}
};

class UnixHttpClient {
public:
    explicit UnixHttpClient(QString socketPath = QString(), QString defaultHost = QStringLiteral("localhost"));
    virtual ~UnixHttpClient();

    [[nodiscard]] QString socketPath() const;
    void setSocketPath(const QString &path);

    [[nodiscard]] QString defaultHost() const;
    void setDefaultHost(const QString &host);

    // Low-level HTTP over Unix Domain Socket (blocking, Connection: close)
    HttpResponse request(const QString &method,
                         const QString &path,
                         const QByteArray &body = QByteArray(),
                         int timeoutMs = 4000,
                         const QString &customHost = QString()) const;

    // Unblocks a request() that is parked in a blocking read(), so a worker
    // thread can be stopped without waiting out the socket timeout. Safe to call
    // from another thread and when no request is in flight.
    void cancel() const;

    // True while a cancel() is in effect, i.e. the last request did not run to
    // completion.
    [[nodiscard]] bool cancelled() const;

    static bool isChunkedEncoding(const QByteArray &headers);
    static bool decodeChunked(const QByteArray &in, QByteArray *out, QString *error);

protected:
    [[nodiscard]] virtual QString resolveSocketPath() const;

    void publishFd(int fd) const;
    void withdrawFd(int fd) const;

    mutable QString m_socketPath;
    QString m_defaultHost;
    mutable std::mutex m_fdMutex;
    mutable int m_activeFd{-1};
    mutable bool m_cancelRequested{false};
};

} // namespace qs
