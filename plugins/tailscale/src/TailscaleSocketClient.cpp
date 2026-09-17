#include "TailscaleSocketClient.hpp"

#include <QClipboard>
#include <QDesktopServices>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QUrl>

#include <cerrno>
#include <chrono>
#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace qs::plugins {

TailscaleSocketClient::TailscaleSocketClient(QString socketPath)
    : m_socketPath(std::move(socketPath))
{
}

QString TailscaleSocketClient::socketPath() const
{
    if (m_socketPath.isEmpty()) {
        m_socketPath = findTailscaleSocket();
    }
    return m_socketPath;
}

void TailscaleSocketClient::setSocketPath(const QString &path)
{
    m_socketPath = path;
}

QString TailscaleSocketClient::findTailscaleSocket()
{
    static const QStringList candidates = {
        QStringLiteral("/var/run/tailscale/tailscaled.sock"),
        QStringLiteral("/run/tailscale/tailscaled.sock")
    };

    for (const auto &path : candidates) {
        if (QFileInfo::exists(path)) {
            return path;
        }
    }
    return candidates.first();
}

QByteArray TailscaleSocketClient::decodeChunked(const QByteArray &chunkedData)
{
    QByteArray result;
    int index = 0;
    const int totalLen = chunkedData.size();

    while (index < totalLen) {
        const int crlf = chunkedData.indexOf("\r\n", index);
        if (crlf == -1) {
            break;
        }

        const QByteArray line = chunkedData.mid(index, crlf - index).trimmed();
        if (line.isEmpty()) {
            index = crlf + 2;
            continue;
        }

        // Strip any chunk extensions (e.g. "1a;foo=bar")
        const int semi = line.indexOf(';');
        const QByteArray hexLen = (semi != -1) ? line.left(semi).trimmed() : line;

        bool ok = false;
        const int chunkSize = hexLen.toInt(&ok, 16);
        if (!ok || chunkSize < 0) {
            break;
        }

        if (chunkSize == 0) {
            // End of chunked stream
            break;
        }

        index = crlf + 2;
        if (index + chunkSize > totalLen) {
            result.append(chunkedData.mid(index));
            break;
        }

        result.append(chunkedData.mid(index, chunkSize));
        index += chunkSize + 2; // skip chunk data + trailing \r\n
    }

    return result;
}

HttpResponse TailscaleSocketClient::request(const QString &method,
                                             const QString &path,
                                             const QByteArray &body,
                                             int timeoutMs) const
{
    HttpResponse res;
    const QString sock = socketPath();

    const int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        res.error = QStringLiteral("Failed to create UNIX socket: ") + QString::fromLocal8Bit(strerror(errno));
        return res;
    }

    struct timeval tv {};
    tv.tv_sec = timeoutMs / 1000;
    tv.tv_usec = (timeoutMs % 1000) * 1000;
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_un addr {};
    addr.sun_family = AF_UNIX;
    const QByteArray sockBytes = sock.toUtf8();
    if (sockBytes.size() >= static_cast<int>(sizeof(addr.sun_path))) {
        ::close(fd);
        res.error = QStringLiteral("Socket path too long: ") + sock;
        return res;
    }
    std::strncpy(addr.sun_path, sockBytes.constData(), sizeof(addr.sun_path) - 1);

    if (::connect(fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) != 0) {
        res.error = QStringLiteral("Failed to connect to ") + sock + QStringLiteral(": ") + QString::fromLocal8Bit(strerror(errno));
        ::close(fd);
        return res;
    }

    // Build HTTP request
    QByteArray req;
    req.append(method.toUtf8());
    req.append(' ');
    req.append(path.toUtf8());
    req.append(" HTTP/1.1\r\nHost: local-tailscaled.sock\r\nConnection: close\r\n");
    if (!body.isEmpty()) {
        req.append("Content-Type: application/json\r\nContent-Length: ");
        req.append(QByteArray::number(body.size()));
        req.append("\r\n");
    }
    req.append("\r\n");
    if (!body.isEmpty()) {
        req.append(body);
    }

    qint64 totalSent = 0;
    while (totalSent < req.size()) {
        const ssize_t n = ::write(fd, req.constData() + totalSent, req.size() - totalSent);
        if (n <= 0) {
            res.error = QStringLiteral("Failed to write to socket: ") + QString::fromLocal8Bit(strerror(errno));
            ::close(fd);
            return res;
        }
        totalSent += n;
    }

    // Read full response
    QByteArray rawResponse;
    char buffer[8192];
    while (true) {
        const ssize_t n = ::read(fd, buffer, sizeof(buffer));
        if (n > 0) {
            rawResponse.append(buffer, static_cast<int>(n));
        } else if (n == 0) {
            break; // Connection closed
        } else {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // Timeout
                break;
            }
            res.error = QStringLiteral("Read error: ") + QString::fromLocal8Bit(strerror(errno));
            ::close(fd);
            return res;
        }
    }
    ::close(fd);

    if (rawResponse.isEmpty()) {
        res.error = QStringLiteral("Empty response from daemon");
        return res;
    }

    const int headerEnd = rawResponse.indexOf("\r\n\r\n");
    if (headerEnd == -1) {
        res.error = QStringLiteral("Malformed HTTP response");
        return res;
    }

    res.headers = rawResponse.left(headerEnd);
    QByteArray rawBody = rawResponse.mid(headerEnd + 4);

    // Parse status line: HTTP/1.1 200 OK
    const int firstLineEnd = res.headers.indexOf("\r\n");
    const QByteArray statusLine = (firstLineEnd != -1) ? res.headers.left(firstLineEnd) : res.headers;
    const QList<QByteArray> parts = statusLine.split(' ');
    if (parts.size() >= 2) {
        res.statusCode = parts[1].toInt();
        if (parts.size() >= 3) {
            res.statusText = parts[2];
        }
    }

    if (res.headers.contains("Transfer-Encoding: chunked") || res.headers.contains("transfer-encoding: chunked")) {
        res.body = decodeChunked(rawBody);
    } else {
        res.body = rawBody;
    }

    res.ok = (res.statusCode >= 200 && res.statusCode < 300);
    return res;
}

bool TailscaleSocketClient::fetchFullStatus(TailscaleState &outState) const
{
    outState = TailscaleState{};

    // 1. Fetch Status
    const HttpResponse statusResp = request(QStringLiteral("GET"), QStringLiteral("/localapi/v0/status"));
    if (!statusResp.ok) {
        outState.ok = false;
        outState.connected = false;
        outState.backendState = QStringLiteral("Offline");
        return false;
    }

    const QJsonDocument statusDoc = statusResp.toJson();
    if (!statusDoc.isObject()) {
        outState.ok = false;
        outState.backendState = QStringLiteral("Unknown");
        return false;
    }

    const QJsonObject statusObj = statusDoc.object();
    outState.backendState = statusObj.value(QStringLiteral("BackendState")).toString(QStringLiteral("Unknown"));
    outState.connected = (outState.backendState == QStringLiteral("Running"));
    outState.version = statusObj.value(QStringLiteral("Version")).toString();
    outState.magicDnsSuffix = statusObj.value(QStringLiteral("MagicDNSSuffix")).toString();

    const QJsonObject tailnetObj = statusObj.value(QStringLiteral("CurrentTailnet")).toObject();
    outState.tailnet = tailnetObj.value(QStringLiteral("Name")).toString();

    // Self node
    const QJsonObject selfObj = statusObj.value(QStringLiteral("Self")).toObject();
    outState.self.hostname = selfObj.value(QStringLiteral("HostName")).toString();
    QString dnsName = selfObj.value(QStringLiteral("DNSName")).toString();
    while (dnsName.endsWith('.')) {
        dnsName.chop(1);
    }
    outState.self.dnsName = dnsName;
    outState.self.os = selfObj.value(QStringLiteral("OS")).toString(QStringLiteral("linux"));
    outState.self.online = selfObj.value(QStringLiteral("Online")).toBool();
    outState.self.relay = selfObj.value(QStringLiteral("Relay")).toString();

    const QJsonArray selfIps = selfObj.value(QStringLiteral("TailscaleIPs")).toArray();
    if (!selfIps.isEmpty()) {
        outState.self.ipv4 = selfIps.at(0).toString();
        if (selfIps.size() > 1) {
            outState.self.ipv6 = selfIps.at(1).toString();
        }
    }

    // User info
    const QJsonObject usersObj = statusObj.value(QStringLiteral("User")).toObject();
    if (!usersObj.isEmpty()) {
        outState.self.user = usersObj.begin().value().toObject().toVariantMap();
    }

    // Health
    outState.health = statusObj.value(QStringLiteral("Health")).toArray().toVariantList();

    // Peers
    const QJsonObject peerMap = statusObj.value(QStringLiteral("Peer")).toObject();
    outState.peers.reserve(peerMap.size());

    for (auto it = peerMap.begin(); it != peerMap.end(); ++it) {
        const QJsonObject pval = it.value().toObject();
        const QString pHost = pval.value(QStringLiteral("HostName")).toString();
        if (pHost.isEmpty() || pHost == QStringLiteral("funnel-ingress-node")) {
            continue;
        }

        const QJsonArray pTags = pval.value(QStringLiteral("Tags")).toArray();
        bool isFunnelIngress = false;
        for (const auto &tagVal : pTags) {
            if (tagVal.toString().contains(QStringLiteral("funnel-ingress"))) {
                isFunnelIngress = true;
                break;
            }
        }
        if (isFunnelIngress) {
            continue;
        }

        TailscalePeer peer;
        peer.hostname = pHost;
        QString pDns = pval.value(QStringLiteral("DNSName")).toString();
        while (pDns.endsWith('.')) {
            pDns.chop(1);
        }
        peer.dnsName = pDns;
        peer.os = pval.value(QStringLiteral("OS")).toString();
        peer.online = pval.value(QStringLiteral("Online")).toBool();
        peer.active = pval.value(QStringLiteral("Active")).toBool();
        peer.relay = pval.value(QStringLiteral("Relay")).toString();
        peer.rxBytes = static_cast<quint64>(pval.value(QStringLiteral("RxBytes")).toDouble(0.0));
        peer.txBytes = static_cast<quint64>(pval.value(QStringLiteral("TxBytes")).toDouble(0.0));

        const QJsonArray pIps = pval.value(QStringLiteral("TailscaleIPs")).toArray();
        if (!pIps.isEmpty()) {
            peer.ipv4 = pIps.at(0).toString();
        }

        outState.peers.append(peer);
    }

    // 2. Fetch Preferences
    const HttpResponse prefsResp = request(QStringLiteral("GET"), QStringLiteral("/localapi/v0/prefs"));
    if (prefsResp.ok) {
        const QJsonObject prefsObj = prefsResp.toJson().object();
        outState.sshEnabled = prefsObj.value(QStringLiteral("RunSSH")).toBool(false);
        outState.webclientEnabled = prefsObj.value(QStringLiteral("RunWebClient")).toBool(false);
        outState.shieldsUp = prefsObj.value(QStringLiteral("ShieldsUp")).toBool(false);

        const QJsonObject autoUpdateObj = prefsObj.value(QStringLiteral("AutoUpdate")).toObject();
        outState.autoUpdate = autoUpdateObj.value(QStringLiteral("Apply")).toBool(false);

        const QJsonArray advRoutes = prefsObj.value(QStringLiteral("AdvertiseRoutes")).toArray();
        bool hasExitRoute = false;
        for (const auto &r : advRoutes) {
            const QString rs = r.toString();
            if (rs == QStringLiteral("0.0.0.0/0") || rs == QStringLiteral("::/0")) {
                hasExitRoute = true;
                break;
            }
        }
        outState.exitNodeEnabled = hasExitRoute || !prefsObj.value(QStringLiteral("ExitNodeID")).toString().isEmpty();
    }

    // 3. Fetch Serve Config
    const HttpResponse serveResp = request(QStringLiteral("GET"), QStringLiteral("/localapi/v0/serve-config"));
    if (serveResp.ok) {
        const QJsonObject serveObj = serveResp.toJson().object();
        const QJsonValue allowFunnelVal = serveObj.value(QStringLiteral("AllowFunnel"));
        const QJsonObject allowFunnelMap = allowFunnelVal.isObject() ? allowFunnelVal.toObject() : QJsonObject();
        const bool isFunnelAll = allowFunnelVal.isBool() ? allowFunnelVal.toBool() : false;

        const QJsonObject webMap = serveObj.value(QStringLiteral("Web")).toObject();
        for (auto it = webMap.begin(); it != webMap.end(); ++it) {
            const QString hostPort = it.key();
            const QStringList parts = hostPort.split(':');
            const QString host = parts.value(0);
            const QString port = parts.size() > 1 ? parts.value(1) : QStringLiteral("443");

            bool isFunnel = isFunnelAll;
            if (!isFunnel && !allowFunnelMap.isEmpty()) {
                if (allowFunnelMap.value(hostPort).toBool() ||
                    allowFunnelMap.value(host + ':' + port).toBool() ||
                    allowFunnelMap.value(port).toBool()) {
                    isFunnel = true;
                }
            }

            const QJsonObject hostCfg = it.value().toObject();
            const QJsonObject handlers = hostCfg.value(QStringLiteral("Handlers")).toObject();
            for (auto hIt = handlers.begin(); hIt != handlers.end(); ++hIt) {
                const QString path = hIt.key();
                const QJsonObject hCfg = hIt.value().toObject();

                QString target = QStringLiteral("Unknown");
                QString hType = QStringLiteral("proxy");
                if (hCfg.contains(QStringLiteral("Proxy"))) {
                    target = hCfg.value(QStringLiteral("Proxy")).toString();
                    hType = QStringLiteral("proxy");
                } else if (hCfg.contains(QStringLiteral("Text"))) {
                    target = hCfg.value(QStringLiteral("Text")).toString();
                    hType = QStringLiteral("text");
                } else if (hCfg.contains(QStringLiteral("Path"))) {
                    target = hCfg.value(QStringLiteral("Path")).toString();
                    hType = QStringLiteral("path");
                }

                const QString pathSuffix = (path == QStringLiteral("/")) ? QString() : path;
                const QString portSuffix = (port != QStringLiteral("443") && port != QStringLiteral("80")) ? (':' + port) : QString();

                TailscaleServeItem item;
                item.host = host;
                item.port = port;
                item.path = path;
                item.target = target;
                item.type = hType;
                item.isFunnel = isFunnel;
                item.url = QStringLiteral("https://") + host + portSuffix + pathSuffix;
                outState.serveItems.append(item);
            }
        }

        const QJsonObject tcpMap = serveObj.value(QStringLiteral("TCP")).toObject();
        for (auto it = tcpMap.begin(); it != tcpMap.end(); ++it) {
            const QString port = it.key();
            const QJsonObject portCfg = it.value().toObject();
            if (portCfg.contains(QStringLiteral("TCPForward"))) {
                const QString tf = portCfg.value(QStringLiteral("TCPForward")).toString();
                const QString dnsNameStr = outState.self.dnsName;

                bool isTcpFunnel = isFunnelAll;
                if (!isTcpFunnel && !allowFunnelMap.isEmpty()) {
                    if (allowFunnelMap.value(port).toBool() ||
                        allowFunnelMap.value(dnsNameStr + ':' + port).toBool()) {
                        isTcpFunnel = true;
                    }
                }

                TailscaleServeItem item;
                item.host = dnsNameStr;
                item.port = port;
                item.path = QString();
                item.target = QStringLiteral("tcp://") + tf;
                item.type = QStringLiteral("tcp");
                item.isFunnel = isTcpFunnel;
                item.url = QStringLiteral("tcp://") + dnsNameStr + ':' + port;
                outState.serveItems.append(item);
            }
        }
    }

    // 4. Fetch Services
    const HttpResponse servicesResp = request(QStringLiteral("GET"), QStringLiteral("/localapi/v0/services"));
    if (servicesResp.ok) {
        const QJsonDocument servDoc = servicesResp.toJson();
        if (servDoc.isArray()) {
            outState.services = servDoc.array().toVariantList();
        } else if (servDoc.isObject()) {
            outState.services = servDoc.object().toVariantMap().values();
        }
    }

    outState.ok = true;
    return true;
}

bool TailscaleSocketClient::setPref(const QString &key, const QJsonValue &val, QString *errOut) const
{
    QJsonObject patch;
    patch[key] = val;
    patch[key + QStringLiteral("Set")] = true;

    const QByteArray body = QJsonDocument(patch).toJson(QJsonDocument::Compact);
    const HttpResponse resp = request(QStringLiteral("PATCH"), QStringLiteral("/localapi/v0/prefs"), body);
    if (!resp.ok) {
        if (errOut) {
            *errOut = resp.error.isEmpty() ? QString::fromUtf8(resp.body) : resp.error;
        }
        return false;
    }
    return true;
}

bool TailscaleSocketClient::setWantRunning(bool up, QString *errOut) const
{
    return setPref(QStringLiteral("WantRunning"), up, errOut);
}

bool TailscaleSocketClient::setSSH(bool enable, QString *errOut) const
{
    return setPref(QStringLiteral("RunSSH"), enable, errOut);
}

bool TailscaleSocketClient::setShieldsUp(bool enable, QString *errOut) const
{
    return setPref(QStringLiteral("ShieldsUp"), enable, errOut);
}

bool TailscaleSocketClient::setWebClient(bool enable, QString *errOut) const
{
    return setPref(QStringLiteral("RunWebClient"), enable, errOut);
}

bool TailscaleSocketClient::setAdvertiseExitNode(bool enable, QString *errOut) const
{
    const ActionResult res = runTailscaleCli({QStringLiteral("set"),
                                             QStringLiteral("--advertise-exit-node=") + (enable ? QStringLiteral("true") : QStringLiteral("false"))});
    if (!res.ok && errOut) {
        *errOut = res.error;
    }
    return res.ok;
}

PingResult TailscaleSocketClient::ping(const QString &ip, int timeoutMs) const
{
    PingResult res;
    res.targetIp = ip;

    if (ip.isEmpty()) {
        res.error = QStringLiteral("Missing IP address");
        return res;
    }

    // 1. Try LocalAPI ping endpoint
    const QString path = QStringLiteral("/localapi/v0/ping?ip=") + QUrl::toPercentEncoding(ip) + QStringLiteral("&type=disco");
    const HttpResponse resp = request(QStringLiteral("POST"), path, QByteArray(), timeoutMs);

    if (resp.ok) {
        const QJsonDocument doc = resp.toJson();
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            const QString errStr = obj.value(QStringLiteral("Err")).toString();
            const double latencySec = obj.value(QStringLiteral("LatencySeconds")).toDouble(0.0);

            if (errStr.isEmpty() && latencySec > 0.0) {
                res.ok = true;
                res.latencyMs = latencySec * 1000.0;
                res.latency = QString::asprintf("%.2f ms", res.latencyMs);
                res.endpoint = obj.value(QStringLiteral("Endpoint")).toString();
                res.output = QStringLiteral("Ping to ") + ip + QStringLiteral(" in ") + res.latency;
                return res;
            }
        }
    }

    // 2. Fallback to tailscale ping CLI command
    const ActionResult cliRes = runTailscaleCli({QStringLiteral("ping"), QStringLiteral("-c"), QStringLiteral("1"), ip}, timeoutMs);
    res.output = cliRes.output;
    res.error = cliRes.error;
    res.ok = cliRes.ok;

    if (cliRes.output.contains(QStringLiteral("in "))) {
        const QStringList parts = cliRes.output.split(QStringLiteral("in "));
        if (parts.size() > 1) {
            res.latency = parts.last().trimmed();
        }
    }

    return res;
}

ActionResult TailscaleSocketClient::runNetcheck(int timeoutMs) const
{
    return runTailscaleCli({QStringLiteral("netcheck")}, timeoutMs);
}

ActionResult TailscaleSocketClient::runTailscaleCli(const QStringList &args, int timeoutMs)
{
    ActionResult res;
    QProcess proc;
    proc.start(QStringLiteral("tailscale"), args);

    if (!proc.waitForStarted(2000)) {
        res.error = QStringLiteral("Failed to execute tailscale CLI binary");
        return res;
    }

    if (!proc.waitForFinished(timeoutMs)) {
        proc.kill();
        proc.waitForFinished(1000);
        res.error = QStringLiteral("Command timed out");
        return res;
    }

    res.output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    res.error = QString::fromUtf8(proc.readAllStandardError()).trimmed();
    res.ok = (proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0);
    return res;
}

ActionResult TailscaleSocketClient::serveStart(const QString &target,
                                              const QString &mode,
                                              const QString &port,
                                              const QString &path) const
{
    if (target.isEmpty()) {
        return {false, QString(), QStringLiteral("Missing target")};
    }

    QStringList args = {mode, QStringLiteral("--bg"), QStringLiteral("--yes")};
    if (port == QStringLiteral("80")) {
        args.append(QStringLiteral("--http=80"));
    } else {
        args.append(QStringLiteral("--https=") + port);
    }

    if (!path.isEmpty() && path != QStringLiteral("/")) {
        args.append(QStringLiteral("--set-path=") + path);
    }

    args.append(target);
    return runTailscaleCli(args);
}

ActionResult TailscaleSocketClient::serveStop(const QString &port, const QString &path) const
{
    const QString proto = (port == QStringLiteral("80")) ? QStringLiteral("http") : QStringLiteral("https");
    const QString portFlag = QStringLiteral("--") + proto + QStringLiteral("=") + port;

    QStringList args1 = {QStringLiteral("serve"), portFlag};
    QStringList args2 = {QStringLiteral("funnel"), portFlag};

    if (!path.isEmpty() && path != QStringLiteral("/")) {
        args1.append(QStringLiteral("--set-path=") + path);
        args2.append(QStringLiteral("--set-path=") + path);
    }
    args1.append(QStringLiteral("off"));
    args2.append(QStringLiteral("off"));

    const ActionResult r1 = runTailscaleCli(args1);
    const ActionResult r2 = runTailscaleCli(args2);

    ActionResult out;
    out.ok = (r1.ok || r2.ok);
    out.output = (r1.output + ' ' + r2.output).trimmed();
    out.error = (r1.error + ' ' + r2.error).trimmed();
    return out;
}

ActionResult TailscaleSocketClient::funnelToggle(const QString &port,
                                                const QString &target,
                                                bool isFunnel,
                                                const QString &path) const
{
    const QString mode = isFunnel ? QStringLiteral("funnel") : QStringLiteral("serve");
    const QString protoFlag = (port == QStringLiteral("80")) ? QStringLiteral("--http=80") : (QStringLiteral("--https=") + port);

    QStringList args = {mode, QStringLiteral("--bg"), QStringLiteral("--yes"), protoFlag};
    if (!path.isEmpty() && path != QStringLiteral("/")) {
        args.append(QStringLiteral("--set-path=") + path);
    }
    if (!target.isEmpty()) {
        args.append(target);
    }

    return runTailscaleCli(args);
}

ActionResult TailscaleSocketClient::serveReset() const
{
    return runTailscaleCli({QStringLiteral("serve"), QStringLiteral("reset")});
}

bool TailscaleSocketClient::copyToClipboard(const QString &text)
{
    if (text.isEmpty()) {
        return false;
    }

    if (QGuiApplication::clipboard()) {
        QGuiApplication::clipboard()->setText(text);
    }

    // Also run wl-copy to ensure persistence on Wayland compositor
    QProcess proc;
    proc.start(QStringLiteral("wl-copy"), QStringList());
    if (proc.waitForStarted(1000)) {
        proc.write(text.toUtf8());
        proc.closeWriteChannel();
        proc.waitForFinished(1000);
    }
    return true;
}

bool TailscaleSocketClient::openUrl(const QString &url)
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
