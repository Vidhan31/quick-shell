#include "UnixHttpClient.hpp"

#include <cctype>
#include <cerrno>
#include <cstring>
#include <memory>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace qs {

UnixHttpClient::UnixHttpClient(QString socketPath, QString defaultHost)
    : m_socketPath(std::move(socketPath))
    , m_defaultHost(std::move(defaultHost))
{
}

UnixHttpClient::~UnixHttpClient() = default;

void UnixHttpClient::publishFd(int fd) const
{
    const std::lock_guard<std::mutex> lock(m_fdMutex);
    m_activeFd = fd;
    m_cancelRequested = false;
}

void UnixHttpClient::withdrawFd(int fd) const
{
    {
        const std::lock_guard<std::mutex> lock(m_fdMutex);
        if (m_activeFd == fd) {
            m_activeFd = -1;
        }
    }
    ::close(fd);
}

bool UnixHttpClient::cancelled() const
{
    const std::lock_guard<std::mutex> lock(m_fdMutex);
    return m_cancelRequested;
}

void UnixHttpClient::cancel() const
{
    int fd = -1;
    {
        const std::lock_guard<std::mutex> lock(m_fdMutex);
        m_cancelRequested = true;
        fd = m_activeFd;
    }
    if (fd < 0) {
        return;
    }
    ::shutdown(fd, SHUT_RDWR);
}

QString UnixHttpClient::socketPath() const
{
    if (m_socketPath.isEmpty()) {
        m_socketPath = resolveSocketPath();
    }
    return m_socketPath;
}

void UnixHttpClient::setSocketPath(const QString &path)
{
    m_socketPath = path;
}

QString UnixHttpClient::defaultHost() const
{
    return m_defaultHost;
}

void UnixHttpClient::setDefaultHost(const QString &host)
{
    m_defaultHost = host;
}

QString UnixHttpClient::resolveSocketPath() const
{
    return QString();
}

bool UnixHttpClient::isChunkedEncoding(const QByteArray &headers)
{
    for (const QByteArray &line : headers.split('\n')) {
        const QByteArray trimmed = line.trimmed();
        const int colon = trimmed.indexOf(':');
        if (colon == -1) {
            continue;
        }
        if (trimmed.left(colon).trimmed().toLower() != "transfer-encoding") {
            continue;
        }
        const auto tokens = trimmed.mid(colon + 1).split(',');
        for (const QByteArray &token : tokens) {
            if (token.trimmed().toLower() == "chunked") {
                return true;
            }
        }
    }
    return false;
}

bool UnixHttpClient::decodeChunked(const QByteArray &in, QByteArray *out, QString *error)
{
    QByteArray decoded;
    int index = 0;
    const int totalLen = in.size();
    bool sawTerminator = false;

    while (index < totalLen) {
        const int crlf = in.indexOf("\r\n", index);
        if (crlf == -1) {
            if (error) {
                *error = QStringLiteral("Truncated chunk-size line");
            }
            return false;
        }
        QByteArray line = in.mid(index, crlf - index).trimmed();
        if (line.isEmpty()) {
            index = crlf + 2;
            continue;
        }
        const int semi = line.indexOf(';');
        const QByteArray hexLen = (semi != -1) ? line.left(semi).trimmed() : line;
        if (hexLen.isEmpty()) {
            if (error) {
                *error = QStringLiteral("Empty chunk size");
            }
            return false;
        }
        for (const char c : hexLen) {
            if (!std::isxdigit(static_cast<unsigned char>(c))) {
                if (error) {
                    *error = QStringLiteral("Malformed chunk size '%1'").arg(QString::fromLatin1(hexLen));
                }
                return false;
            }
        }
        bool ok = false;
        const qlonglong chunkSize = hexLen.toLongLong(&ok, 16);
        if (!ok || chunkSize < 0) {
            if (error) {
                *error = QStringLiteral("Malformed chunk size '%1'").arg(QString::fromLatin1(hexLen));
            }
            return false;
        }
        if (chunkSize == 0) {
            sawTerminator = true;
            break;
        }
        index = crlf + 2;
        if (index + chunkSize + 2 > totalLen) {
            if (error) {
                *error = QStringLiteral("Incomplete chunk body: need %1 bytes, have %2")
                             .arg(chunkSize)
                             .arg(totalLen - index);
            }
            return false;
        }
        decoded.append(in.mid(index, static_cast<int>(chunkSize)));
        index += static_cast<int>(chunkSize);
        if (in.mid(index, 2) != "\r\n") {
            if (error) {
                *error = QStringLiteral("Missing CRLF after chunk body");
            }
            return false;
        }
        index += 2;
    }

    if (!sawTerminator) {
        if (error) {
            *error = QStringLiteral("Missing terminating zero-size chunk");
        }
        return false;
    }
    if (out) {
        *out = decoded;
    }
    return true;
}

HttpResponse UnixHttpClient::request(const QString &method,
                                     const QString &path,
                                     const QByteArray &body,
                                     int timeoutMs,
                                     const QString &customHost) const
{
    HttpResponse res;
    const QString sock = socketPath();

    const int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        res.error = QStringLiteral("Failed to create UNIX socket: ") + QString::fromLocal8Bit(strerror(errno));
        return res;
    }
    publishFd(fd);
    const auto closeFd = [this](int *p) {
        if (p && *p >= 0) {
            withdrawFd(*p);
        }
    };
    const std::unique_ptr<int, decltype(closeFd)> fdOwner(new int(fd), closeFd);

    struct timeval tv {};
    tv.tv_sec = timeoutMs / 1000;
    tv.tv_usec = (timeoutMs % 1000) * 1000;
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_un addr {};
    addr.sun_family = AF_UNIX;
    const QByteArray sockBytes = sock.toUtf8();
    if (sockBytes.size() >= static_cast<int>(sizeof(addr.sun_path))) {
        res.error = QStringLiteral("Socket path too long: ") + sock;
        return res;
    }
    std::strncpy(addr.sun_path, sockBytes.constData(), sizeof(addr.sun_path) - 1);

    if (::connect(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) != 0) {
        res.error = QStringLiteral("Failed to connect to ") + sock + QStringLiteral(": ") + QString::fromLocal8Bit(strerror(errno));
        return res;
    }

    const QString host = customHost.isEmpty() ? m_defaultHost : customHost;
    QByteArray req;
    req.append(method.toUtf8());
    req.append(' ');
    req.append(path.toUtf8());
    req.append(" HTTP/1.1\r\nHost: ");
    req.append(host.toUtf8());
    req.append("\r\nConnection: close\r\n");
    if (!body.isEmpty()) {
        req.append("Content-Type: application/json\r\nContent-Length: ");
        req.append(QByteArray::number(body.size()));
        req.append("\r\n");
    } else if (method == QStringLiteral("POST") || method == QStringLiteral("PUT") || method == QStringLiteral("PATCH")) {
        req.append("Content-Length: 0\r\n");
    }
    req.append("\r\n");
    if (!body.isEmpty()) {
        req.append(body);
    }

    qint64 totalSent = 0;
    while (totalSent < req.size()) {
        const ssize_t n = ::send(fd, req.constData() + totalSent,
                                 static_cast<size_t>(req.size() - totalSent), MSG_NOSIGNAL);
        if (n <= 0) {
            res.error = QStringLiteral("Failed to write to socket: ") + QString::fromLocal8Bit(strerror(errno));
            return res;
        }
        totalSent += n;
    }

    QByteArray rawResponse;
    char buffer[8192];
    while (true) {
        if (cancelled()) {
            res.error = QStringLiteral("Request cancelled");
            return res;
        }
        const ssize_t n = ::read(fd, buffer, sizeof(buffer));
        if (n > 0) {
            rawResponse.append(buffer, static_cast<int>(n));
        } else if (n == 0) {
            break;
        } else {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                res.error = cancelled() ? QStringLiteral("Request cancelled")
                                        : QStringLiteral("Read timed out after %1 ms").arg(timeoutMs);
                return res;
            }
            res.error = cancelled() ? QStringLiteral("Request cancelled")
                                    : QStringLiteral("Read error: ") + QString::fromLocal8Bit(strerror(errno));
            return res;
        }
    }

    if (rawResponse.isEmpty()) {
        res.error = cancelled() ? QStringLiteral("Request cancelled")
                                : QStringLiteral("Empty response from daemon");
        return res;
    }

    const int headerEnd = rawResponse.indexOf("\r\n\r\n");
    if (headerEnd == -1) {
        res.error = QStringLiteral("Malformed HTTP response");
        return res;
    }

    res.headers = rawResponse.left(headerEnd);
    const QByteArray rawBody = rawResponse.mid(headerEnd + 4);

    const int firstLineEnd = res.headers.indexOf("\r\n");
    const QByteArray statusLine = (firstLineEnd != -1) ? res.headers.left(firstLineEnd) : res.headers;
    const QList<QByteArray> parts = statusLine.split(' ');
    if (parts.size() >= 2) {
        res.statusCode = parts[1].toInt();
        if (parts.size() >= 3) {
            res.statusText = parts[2];
        }
    }

    if (isChunkedEncoding(res.headers)) {
        if (!decodeChunked(rawBody, &res.body, &res.error)) {
            res.body.clear();
            return res;
        }
    } else {
        res.body = rawBody;
    }

    res.ok = (res.statusCode >= 200 && res.statusCode < 300);
    return res;
}

} // namespace qs
