#include "DockerSocketClient.hpp"

#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QUrl>

#include <cctype>
#include <cerrno>
#include <cstring>
#include <memory>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace qs::plugins {

DockerSocketClient::DockerSocketClient(QString socketPath)
    : m_socketPath(std::move(socketPath))
{
}

void DockerSocketClient::publishFd(int fd) const
{
    const std::lock_guard<std::mutex> lock(m_fdMutex);
    m_activeFd = fd;
    m_cancelRequested = false;
}

void DockerSocketClient::withdrawFd(int fd) const
{
    {
        const std::lock_guard<std::mutex> lock(m_fdMutex);
        if (m_activeFd == fd) {
            m_activeFd = -1;
        }
    }
    // The request thread owns the descriptor, so close it here. Doing this
    // outside the lock keeps the close off the critical path.
    ::close(fd);
}

bool DockerSocketClient::cancelled() const
{
    const std::lock_guard<std::mutex> lock(m_fdMutex);
    return m_cancelRequested;
}

void DockerSocketClient::cancel() const
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
    // shutdown() rather than close(): the descriptor stays valid so the request
    // thread still closes it exactly once. A pending read() returns EOF.
    ::shutdown(fd, SHUT_RDWR);
}

QString DockerSocketClient::socketPath() const
{
    if (m_socketPath.isEmpty()) {
        m_socketPath = findDockerSocket();
    }
    return m_socketPath;
}

void DockerSocketClient::setSocketPath(const QString &path)
{
    m_socketPath = path;
}

QString DockerSocketClient::findDockerSocket()
{
    const QByteArray xdg = qgetenv("XDG_RUNTIME_DIR");
    if (!xdg.isEmpty()) {
        const QString p = QString::fromUtf8(xdg) + QStringLiteral("/docker.sock");
        if (QFileInfo::exists(p)) {
            return p;
        }
        // Return it anyway when UID dir exists — daemon may just be down.
        // Caller reports connect error instead of silently using rootful path.
        const QFileInfo dirInfo(QString::fromUtf8(xdg));
        if (dirInfo.isDir()) {
            return p;
        }
    }

    static const QStringList fallbacks = {
        QStringLiteral("/var/run/docker.sock"),
        QStringLiteral("/run/docker.sock"),
    };
    for (const auto &p : fallbacks) {
        if (QFileInfo::exists(p)) {
            return p;
        }
    }
    // Default to rootless convention when nothing exists (error surfaces connect failure)
    const QString uidPath = QStringLiteral("/run/user/%1/docker.sock").arg(::getuid());
    if (QFileInfo::exists(uidPath)) {
        return uidPath;
    }
    if (!xdg.isEmpty()) {
        return QString::fromUtf8(xdg) + QStringLiteral("/docker.sock");
    }
    return fallbacks.first();
}

// Transfer-Encoding may be a comma-separated list ("gzip, chunked") and header
// names are case-insensitive, so match on parsed values rather than substrings.
bool DockerSocketClient::isChunkedEncoding(const QByteArray &headers)
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

// Fails closed on every deviation from RFC 9112 chunked framing. A partially
// decoded body must never reach a caller, or a truncated response reads as a
// successful one with a silently short payload.
bool DockerSocketClient::decodeChunked(const QByteArray &in, QByteArray *out, QString *error)
{
    QByteArray decoded;
    int index = 0;
    const int totalLen = in.size();
    bool sawTerminator = false;

    while (index < totalLen) {
        const int crlf = in.indexOf("\r\n", index);
        if (crlf == -1) {
            *error = QStringLiteral("Truncated chunk-size line");
            return false;
        }
        QByteArray line = in.mid(index, crlf - index).trimmed();
        if (line.isEmpty()) {
            // Stray CRLF between chunks; tolerate and resync.
            index = crlf + 2;
            continue;
        }
        const int semi = line.indexOf(';'); // chunk extensions are allowed
        const QByteArray hexLen = (semi != -1) ? line.left(semi).trimmed() : line;
        if (hexLen.isEmpty()) {
            *error = QStringLiteral("Empty chunk size");
            return false;
        }
        for (const char c : hexLen) {
            if (!std::isxdigit(static_cast<unsigned char>(c))) {
                *error = QStringLiteral("Malformed chunk size '%1'").arg(QString::fromLatin1(hexLen));
                return false;
            }
        }
        bool ok = false;
        const qlonglong chunkSize = hexLen.toLongLong(&ok, 16);
        if (!ok || chunkSize < 0) {
            *error = QStringLiteral("Malformed chunk size '%1'").arg(QString::fromLatin1(hexLen));
            return false;
        }
        if (chunkSize == 0) {
            sawTerminator = true;
            break;
        }
        index = crlf + 2;
        if (index + chunkSize + 2 > totalLen) {
            *error = QStringLiteral("Incomplete chunk body: need %1 bytes, have %2")
                         .arg(chunkSize)
                         .arg(totalLen - index);
            return false;
        }
        decoded.append(in.mid(index, static_cast<int>(chunkSize)));
        index += static_cast<int>(chunkSize);
        if (in.mid(index, 2) != "\r\n") {
            *error = QStringLiteral("Missing CRLF after chunk body");
            return false;
        }
        index += 2;
    }

    if (!sawTerminator) {
        *error = QStringLiteral("Missing terminating zero-size chunk");
        return false;
    }
    *out = decoded;
    return true;
}

HttpResponse DockerSocketClient::request(const QString &method,
                                         const QString &path,
                                         const QByteArray &body,
                                         int timeoutMs) const
{
    HttpResponse res;
    const QString sock = socketPath();

    // Publishes the fd for the lifetime of the request so cancel() can
    // shutdown() it out from under a blocking read. The unique_ptr guarantees
    // every exit path below deregisters and closes it exactly once.
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

    QByteArray req;
    req.append(method.toUtf8());
    req.append(' ');
    req.append(path.toUtf8());
    req.append(" HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n");
    if (!body.isEmpty()) {
        req.append("Content-Type: application/json\r\nContent-Length: ");
        req.append(QByteArray::number(body.size()));
        req.append("\r\n");
    } else if (method == QStringLiteral("POST")) {
        req.append("Content-Length: 0\r\n");
    }
    req.append("\r\n");
    if (!body.isEmpty()) {
        req.append(body);
    }

    qint64 totalSent = 0;
    while (totalSent < req.size()) {
        // send() with MSG_NOSIGNAL, not write(): nothing in this process masks
        // SIGPIPE, so writing to a socket the daemon already closed would kill
        // Quickshell outright.
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
                continue; // a signal (or cancel's wakeup) interrupted the read
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // SO_RCVTIMEO expired. Whether this is a genuine timeout or a
                // cancelled read is decided below; never parse a short body as
                // a complete one.
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
        // cancel() surfaces as EOF, not an error, so name the real cause.
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
    QByteArray rawBody = rawResponse.mid(headerEnd + 4);

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
            // Never expose a partially decoded payload as a usable body.
            res.body.clear();
            return res;
        }
    } else {
        res.body = rawBody;
    }

    res.ok = (res.statusCode >= 200 && res.statusCode < 300);
    return res;
}

QString DockerSocketClient::errorMessageFor(const HttpResponse &resp)
{
    if (!resp.error.isEmpty()) {
        return resp.error;
    }
    const QString msg = resp.apiMessage();
    if (!msg.isEmpty()) {
        return msg;
    }
    return QStringLiteral("HTTP %1").arg(resp.statusCode);
}

bool DockerSocketClient::ping(QString *errOut) const
{
    const HttpResponse r = request(QStringLiteral("GET"), QStringLiteral("/_ping"));
    if (r.statusCode == 200) {
        return true;
    }
    if (errOut) {
        *errOut = errorMessageFor(r);
    }
    return false;
}

static DockerContainer containerFromSummary(const QJsonObject &o)
{
    DockerContainer c;
    c.id = o.value(QStringLiteral("Id")).toString();
    c.shortId = c.id.left(12);
    const QJsonArray names = o.value(QStringLiteral("Names")).toArray();
    if (!names.isEmpty()) {
        c.name = names.at(0).toString();
        if (c.name.startsWith('/')) {
            c.name = c.name.sliced(1);
        }
    } else {
        c.name = c.shortId;
    }
    c.image = o.value(QStringLiteral("Image")).toString();
    c.command = o.value(QStringLiteral("Command")).toString();
    // Created is Unix seconds (double in JSON); keep as int64
    c.created = static_cast<qint64>(o.value(QStringLiteral("Created")).toDouble(0));
    c.state = o.value(QStringLiteral("State")).toString();
    c.status = o.value(QStringLiteral("Status")).toString();
    c.health = o.value(QStringLiteral("Health")).toString();

    const QJsonObject labels = o.value(QStringLiteral("Labels")).toObject();
    for (auto it = labels.begin(); it != labels.end(); ++it) {
        c.labels.insert(it.key(), it.value().toString());
    }
    c.project = c.labels.value(QStringLiteral("com.docker.compose.project")).toString();
    c.service = c.labels.value(QStringLiteral("com.docker.compose.service")).toString();
    c.workingDir = c.labels.value(QStringLiteral("com.docker.compose.project.working_dir")).toString();
    c.configFiles = c.labels.value(QStringLiteral("com.docker.compose.project.config_files")).toString();
    c.containerNumber = c.labels.value(QStringLiteral("com.docker.compose.container-number")).toString().toLongLong();
    return c;
}

bool DockerSocketClient::fetchFullState(DockerState &outState) const
{
    outState = DockerState{};
    outState.socketPath = socketPath();

    const HttpResponse pingResp = request(QStringLiteral("GET"), QStringLiteral("/_ping"));
    if (pingResp.statusCode != 200) {
        outState.ok = false;
        outState.connected = false;
        outState.error = errorMessageFor(pingResp);
        return false;
    }
    outState.connected = true;

    const HttpResponse verResp = request(QStringLiteral("GET"), QByteArray(kApiPrefix) + "/version");
    if (verResp.ok) {
        const QJsonObject vo = verResp.toJson().object();
        outState.serverVersion = vo.value(QStringLiteral("Version")).toString();
        outState.apiVersion = vo.value(QStringLiteral("ApiVersion")).toString();
    }

    // Chunked on this daemon, so the decoder is required.
    const HttpResponse infoResp = request(QStringLiteral("GET"), QByteArray(kApiPrefix) + "/info");
    if (infoResp.ok) {
        const QJsonObject io = infoResp.toJson().object();
        outState.running = io.value(QStringLiteral("ContainersRunning")).toInt();
        outState.paused = io.value(QStringLiteral("ContainersPaused")).toInt();
        outState.stopped = io.value(QStringLiteral("ContainersStopped")).toInt();
        outState.imagesCount = io.value(QStringLiteral("Images")).toInt();
    }

    // No size=1 in the list view, because it is expensive by design.
    const HttpResponse cResp = request(QStringLiteral("GET"), QByteArray(kApiPrefix) + "/containers/json?all=1");
    if (cResp.ok) {
        const QJsonArray arr = cResp.toJson().array();
        outState.containers.reserve(arr.size());
        QMap<QString, DockerProject> projMap;
        for (const auto &v : arr) {
            DockerContainer c = containerFromSummary(v.toObject());
            outState.containers.append(c);
            if (c.project.isEmpty()) {
                outState.standalone.append(c);
            } else {
                auto &p = projMap[c.project];
                if (p.name.isEmpty()) {
                    p.name = c.project;
                    p.workingDir = c.workingDir;
                    p.configFiles = c.configFiles;
                }
                p.total++;
                if (c.isRunning()) {
                    p.running++;
                }
                p.members.append(c);
            }
        }
        outState.projects.reserve(projMap.size());
        for (auto it = projMap.begin(); it != projMap.end(); ++it) {
            outState.projects.append(it.value());
        }
        std::sort(outState.projects.begin(), outState.projects.end(),
                  [](const DockerProject &a, const DockerProject &b) { return a.name < b.name; });
    }

    const HttpResponse iResp = request(QStringLiteral("GET"), QByteArray(kApiPrefix) + "/images/json");
    if (iResp.ok) {
        const QJsonArray arr = iResp.toJson().array();
        for (const auto &v : arr) {
            const QJsonObject o = v.toObject();
            DockerImage im;
            im.id = o.value(QStringLiteral("Id")).toString();
            im.shortId = im.id.startsWith(QStringLiteral("sha256:")) ? im.id.sliced(7, 12) : im.id.left(12);
            im.repoTags = o.value(QStringLiteral("RepoTags")).toArray().toVariantList();
            im.size = static_cast<qint64>(o.value(QStringLiteral("Size")).toDouble(0));
            im.created = static_cast<qint64>(o.value(QStringLiteral("Created")).toDouble(0));
            outState.images.append(im);
        }
    }

    const HttpResponse vResp = request(QStringLiteral("GET"), QByteArray(kApiPrefix) + "/volumes");
    if (vResp.ok) {
        const QJsonObject o = vResp.toJson().object();
        const QJsonArray arr = o.value(QStringLiteral("Volumes")).toArray();
        for (const auto &v : arr) {
            const QJsonObject vo = v.toObject();
            DockerVolume vol;
            vol.name = vo.value(QStringLiteral("Name")).toString();
            vol.driver = vo.value(QStringLiteral("Driver")).toString();
            vol.mountpoint = vo.value(QStringLiteral("Mountpoint")).toString();
            vol.scope = vo.value(QStringLiteral("Scope")).toString();
            outState.volumes.append(vol);
        }
    }

    // Items shape is empty in the spec, so keep it raw for the header stats and
    // derive the C++-computed cleanup rows QML displays verbatim.
    const HttpResponse dfResp = request(QStringLiteral("GET"), QByteArray(kApiPrefix) + "/system/df");
    qint64 imageReclaim = 0;
    qint64 buildReclaim = 0;
    qint64 volumeTotal = 0;
    if (dfResp.ok) {
        const QJsonDocument doc = dfResp.toJson();
        if (doc.isObject()) {
            outState.df = doc.object().toVariantMap();
            const QJsonObject root = doc.object();
            imageReclaim = static_cast<qint64>(root.value(QStringLiteral("ImageUsage")).toObject().value(QStringLiteral("Reclaimable")).toDouble(0));
            buildReclaim = static_cast<qint64>(root.value(QStringLiteral("BuildCacheUsage")).toObject().value(QStringLiteral("Reclaimable")).toDouble(0));
            volumeTotal = static_cast<qint64>(root.value(QStringLiteral("VolumeUsage")).toObject().value(QStringLiteral("TotalSize")).toDouble(0));
        }
    }

    auto cleanupRow = [](const QString &kind, const QString &label, const QString &detail) {
        QVariantMap r;
        r[QStringLiteral("kind")] = kind;
        r[QStringLiteral("label")] = label;
        r[QStringLiteral("detail")] = detail;
        return r;
    };
    outState.cleanup = QVariantList{
        cleanupRow(QStringLiteral("containers"), QStringLiteral("Containers"),
                   outState.stopped > 0 ? QStringLiteral("%1 stopped").arg(outState.stopped) : QStringLiteral("none stopped")),
        cleanupRow(QStringLiteral("images"), QStringLiteral("Images"),
                   imageReclaim > 0 ? formatBytes(imageReclaim) + QStringLiteral(" reclaimable") : QStringLiteral("nothing unused")),
        cleanupRow(QStringLiteral("volumes"), QStringLiteral("Volumes"),
                   volumeTotal > 0 ? formatBytes(volumeTotal) + QStringLiteral(" total") : QStringLiteral("no volumes")),
        cleanupRow(QStringLiteral("build"), QStringLiteral("Build cache"),
                   buildReclaim > 0 ? formatBytes(buildReclaim) + QStringLiteral(" reclaimable") : QStringLiteral("nothing unused")),
    };
    const qint64 totalReclaim = imageReclaim + buildReclaim;
    outState.reclaimSummary = totalReclaim > 0 ? formatBytes(totalReclaim) + QStringLiteral(" reclaimable") : QString();

    outState.ok = true;
    return true;
}

static ActionResult toAction(const HttpResponse &r)
{
    ActionResult a;
    a.statusCode = r.statusCode;
    if (r.statusCode == 204 || r.statusCode == 200) {
        a.ok = true;
        a.output = r.apiMessage();
        return a;
    }
    if (r.statusCode == 304) {
        // Idempotent "already in that state" — treat as success, keep note.
        a.ok = true;
        a.output = QStringLiteral("Already in that state (304)");
        return a;
    }
    a.ok = false;
    a.output = r.apiMessage();
    if (!r.error.isEmpty()) {
        a.error = r.error;
    } else if (a.error.isEmpty()) {
        a.error = QStringLiteral("HTTP %1").arg(r.statusCode);
    }
    if (a.output.isEmpty()) {
        a.output = a.error;
    }
    return a;
}

ActionResult DockerSocketClient::startContainer(const QString &id) const
{
    const HttpResponse r = request(QStringLiteral("POST"),
                                   QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/") + id + QStringLiteral("/start"));
    return toAction(r);
}

ActionResult DockerSocketClient::stopContainer(const QString &id, int timeoutSec) const
{
    const HttpResponse r = request(QStringLiteral("POST"),
                                   QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/") + id
                                       + QStringLiteral("/stop?t=") + QString::number(timeoutSec));
    return toAction(r);
}

ActionResult DockerSocketClient::restartContainer(const QString &id, int timeoutSec) const
{
    const HttpResponse r = request(QStringLiteral("POST"),
                                   QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/") + id
                                       + QStringLiteral("/restart?t=") + QString::number(timeoutSec));
    // restart has no 304 — 204 only
    ActionResult a;
    a.statusCode = r.statusCode;
    if (r.statusCode == 204 || r.statusCode == 200) {
        a.ok = true;
        return a;
    }
    a.ok = false;
    a.error = r.error.isEmpty() ? r.apiMessage() : r.error;
    a.output = a.error;
    return a;
}

ActionResult DockerSocketClient::killContainer(const QString &id, const QString &signal) const
{
    const HttpResponse r = request(QStringLiteral("POST"),
                                   QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/") + id
                                       + QStringLiteral("/kill?signal=") + QUrl::toPercentEncoding(signal));
    ActionResult a;
    a.statusCode = r.statusCode;
    if (r.statusCode == 204 || r.statusCode == 200) {
        a.ok = true;
        return a;
    }
    // 409 container is not running — surface as info
    a.ok = false;
    a.error = r.error.isEmpty() ? r.apiMessage() : r.error;
    a.output = a.error;
    return a;
}

ActionResult DockerSocketClient::removeContainer(const QString &id, bool force, bool removeVolumes) const
{
    QString q = QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/") + id + QStringLiteral("?force=")
        + (force ? QStringLiteral("1") : QStringLiteral("0")) + QStringLiteral("&v=")
        + (removeVolumes ? QStringLiteral("1") : QStringLiteral("0"));
    const HttpResponse r = request(QStringLiteral("DELETE"), q);
    ActionResult a;
    a.statusCode = r.statusCode;
    if (r.statusCode == 204 || r.statusCode == 200) {
        a.ok = true;
        return a;
    }
    a.ok = false;
    a.error = r.error.isEmpty() ? r.apiMessage() : r.error;
    a.output = a.error;
    return a;
}

ActionResult DockerSocketClient::removeImage(const QString &name, bool force) const
{
    const QString q = QString::fromUtf8(kApiPrefix) + QStringLiteral("/images/") + QUrl::toPercentEncoding(name)
        + QStringLiteral("?force=") + (force ? QStringLiteral("1") : QStringLiteral("0"));
    const HttpResponse r = request(QStringLiteral("DELETE"), q);
    ActionResult a;
    a.statusCode = r.statusCode;
    a.ok = (r.statusCode == 200);
    a.error = r.error.isEmpty() ? r.apiMessage() : r.error;
    a.output = a.error;
    return a;
}

ActionResult DockerSocketClient::removeVolume(const QString &name, bool force) const
{
    const QString q = QString::fromUtf8(kApiPrefix) + QStringLiteral("/volumes/") + QUrl::toPercentEncoding(name)
        + QStringLiteral("?force=") + (force ? QStringLiteral("1") : QStringLiteral("0"));
    const HttpResponse r = request(QStringLiteral("DELETE"), q);
    ActionResult a;
    a.statusCode = r.statusCode;
    a.ok = (r.statusCode == 204);
    a.error = r.error.isEmpty() ? r.apiMessage() : r.error;
    a.output = a.error;
    return a;
}

ActionResult DockerSocketClient::prune(const QString &kind) const
{
    QString endpoint;
    if (kind == QStringLiteral("containers")) {
        endpoint = QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/prune");
    } else if (kind == QStringLiteral("images")) {
        endpoint = QString::fromUtf8(kApiPrefix) + QStringLiteral("/images/prune");
    } else if (kind == QStringLiteral("volumes")) {
        endpoint = QString::fromUtf8(kApiPrefix) + QStringLiteral("/volumes/prune");
    } else if (kind == QStringLiteral("build")) {
        endpoint = QString::fromUtf8(kApiPrefix) + QStringLiteral("/build/prune");
    } else {
        return {false, 0, QString(), QStringLiteral("Unknown prune kind: ") + kind};
    }
    const HttpResponse r = request(QStringLiteral("POST"), endpoint);
    ActionResult a;
    a.statusCode = r.statusCode;
    a.ok = r.ok;
    // Keep raw JSON for SpaceReclaimed + deleted lists; QML parses it.
    a.output = QString::fromUtf8(r.body);
    a.error = r.ok ? QString() : (r.error.isEmpty() ? r.apiMessage() : r.error);
    return a;
}

LogsResult DockerSocketClient::fetchLogs(const QString &id, int tail) const
{
    LogsResult out;
    const QString q = QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/") + id
        + QStringLiteral("/logs?stdout=1&stderr=1&follow=0&tail=") + QString::number(tail);
    const HttpResponse r = request(QStringLiteral("GET"), q, QByteArray(), 8000);
    out.statusCode = r.statusCode;
    if (r.statusCode == 200) {
        out.ok = true;
        out.logs = QString::fromUtf8(r.body);
        return out;
    }
    out.ok = false;
    out.error = r.error.isEmpty() ? r.apiMessage() : r.error;
    return out;
}

HttpResponse DockerSocketClient::fetchInspect(const QString &id) const
{
    return request(QStringLiteral("GET"),
                   QString::fromUtf8(kApiPrefix) + QStringLiteral("/containers/") + id + QStringLiteral("/json"));
}

bool DockerSocketClient::openPath(const QString &path)
{
    if (path.isEmpty()) {
        return false;
    }
    const QUrl u = QUrl::fromLocalFile(path);
    if (QDesktopServices::openUrl(u)) {
        return true;
    }
    return QProcess::startDetached(QStringLiteral("xdg-open"), {path});
}

bool DockerSocketClient::openUrl(const QString &url)
{
    if (url.isEmpty()) {
        return false;
    }
    const QUrl qurl(url);
    if (qurl.isValid() && QDesktopServices::openUrl(qurl)) {
        return true;
    }
    return QProcess::startDetached(QStringLiteral("xdg-open"), {url});
}

} // namespace qs::plugins
