#include "EthernetProbe.hpp"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QNetworkInformation>
#include <QProcess>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <QDate>
#include <QRegularExpression>
#include <QDir>
#include <QFileInfo>
#include <QElapsedTimer>

#include <chrono>
#include <cstring>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>

#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <netinet/ip_icmp.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/ethtool.h>
#include <linux/sockios.h>

#ifndef IFF_LOWER_UP
#define IFF_LOWER_UP 0x10000
#endif

namespace qs::plugins {

namespace fs = std::filesystem;

static QString readSysfsTrimmed(const std::string &path) {
    int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return QString();
    char buf[256];
    ssize_t n = ::read(fd, buf, sizeof(buf) - 1);
    ::close(fd);
    if (n <= 0) return QString();
    buf[n] = '\0';
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' || buf[n - 1] == ' ')) {
        buf[--n] = '\0';
    }
    return QString::fromUtf8(buf, static_cast<qsizetype>(n));
}

QStringList EthernetProbe::findEthernetInterfaces() {
    if (fs::exists("/sys/class/net/enp34s0/type")) {
        const QString t = readSysfsTrimmed("/sys/class/net/enp34s0/type");
        if (t == QStringLiteral("1")) {
            return {QStringLiteral("enp34s0")};
        }
    }

    QStringList ifaces;
    const std::string netDir = "/sys/class/net";
    std::error_code ec;
    if (!fs::exists(netDir, ec)) {
        return ifaces;
    }

    for (const auto &entry : fs::directory_iterator(netDir, ec)) {
        const std::string name = entry.path().filename().string();
        if (name == "lo" ||
            name.starts_with("tailscale") ||
            name.starts_with("docker") ||
            name.starts_with("br-") ||
            name.starts_with("veth") ||
            name.starts_with("virbr") ||
            name.starts_with("tun") ||
            name.starts_with("tap")) {
            continue;
        }

        if (fs::exists(entry.path() / "wireless", ec) ||
            fs::exists(entry.path() / "phy80211", ec)) {
            continue;
        }

        const QString devType = readSysfsTrimmed((entry.path() / "type").string());
        if (devType == QStringLiteral("1")) {
            ifaces.append(QString::fromStdString(name));
        }
    }

    std::sort(ifaces.begin(), ifaces.end());
    return ifaces;
}

bool EthernetProbe::readRxTxBytes(const QString &iface, quint64 &rx, quint64 &tx) {
    rx = 0;
    tx = 0;
    const std::string rxPath = "/sys/class/net/" + iface.toStdString() + "/statistics/rx_bytes";
    const std::string txPath = "/sys/class/net/" + iface.toStdString() + "/statistics/tx_bytes";

    int fdRx = ::open(rxPath.c_str(), O_RDONLY | O_CLOEXEC);
    if (fdRx >= 0) {
        char buf[64];
        ssize_t n = ::read(fdRx, buf, sizeof(buf) - 1);
        ::close(fdRx);
        if (n > 0) {
            buf[n] = '\0';
            rx = std::strtoull(buf, nullptr, 10);
        }
    }

    int fdTx = ::open(txPath.c_str(), O_RDONLY | O_CLOEXEC);
    if (fdTx >= 0) {
        char buf[64];
        ssize_t n = ::read(fdTx, buf, sizeof(buf) - 1);
        ::close(fdTx);
        if (n > 0) {
            buf[n] = '\0';
            tx = std::strtoull(buf, nullptr, 10);
        }
    }

    return true;
}

static void parseAddressData(const QVariant &var, QString &outIp) {
    if (var.canConvert<QDBusArgument>()) {
        const QDBusArgument arg = var.value<QDBusArgument>();
        if (arg.currentType() == QDBusArgument::ArrayType) {
            arg.beginArray();
            while (!arg.atEnd()) {
                QVariantMap map;
                arg >> map;
                if (map.contains(QStringLiteral("address")) && map.contains(QStringLiteral("prefix"))) {
                    outIp = map.value(QStringLiteral("address")).toString() +
                            QStringLiteral("/") +
                            QString::number(map.value(QStringLiteral("prefix")).toUInt());
                    break;
                }
            }
            arg.endArray();
        }
    } else if (var.canConvert<QVariantList>()) {
        const auto list = var.toList();
        for (const auto &item : list) {
            if (item.canConvert<QVariantMap>()) {
                const auto map = item.toMap();
                if (map.contains(QStringLiteral("address")) && map.contains(QStringLiteral("prefix"))) {
                    outIp = map.value(QStringLiteral("address")).toString() +
                            QStringLiteral("/") +
                            QString::number(map.value(QStringLiteral("prefix")).toUInt());
                    break;
                }
            }
        }
    }
}

static void parseNameserverData(const QVariant &var, QStringList &outDns) {
    if (var.canConvert<QDBusArgument>()) {
        const QDBusArgument arg = var.value<QDBusArgument>();
        if (arg.currentType() == QDBusArgument::ArrayType) {
            arg.beginArray();
            while (!arg.atEnd()) {
                QVariantMap map;
                arg >> map;
                if (map.contains(QStringLiteral("address"))) {
                    const QString addr = map.value(QStringLiteral("address")).toString();
                    if (!addr.isEmpty() && !outDns.contains(addr)) {
                        outDns.append(addr);
                    }
                }
            }
            arg.endArray();
        }
    } else if (var.canConvert<QVariantList>()) {
        const auto list = var.toList();
        for (const auto &item : list) {
            if (item.canConvert<QVariantMap>()) {
                const auto map = item.toMap();
                if (map.contains(QStringLiteral("address"))) {
                    const QString addr = map.value(QStringLiteral("address")).toString();
                    if (!addr.isEmpty() && !outDns.contains(addr)) {
                        outDns.append(addr);
                    }
                }
            }
        }
    }
}

bool EthernetProbe::queryNetworkManager(EthernetState &state) {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        return false;
    }

    QDBusInterface nmIface(QStringLiteral("org.freedesktop.NetworkManager"),
                           QStringLiteral("/org/freedesktop/NetworkManager"),
                           QStringLiteral("org.freedesktop.NetworkManager"),
                           bus);
    if (!nmIface.isValid()) {
        return false;
    }

    const QVariant connVar = nmIface.property("Connectivity");
    if (connVar.isValid()) {
        state.nmConnectivity = static_cast<int>(connVar.toUInt());
    }

    const QVariant devVar = nmIface.property("Devices");
    QList<QDBusObjectPath> devPaths;
    if (devVar.canConvert<QList<QDBusObjectPath>>()) {
        devPaths = qdbus_cast<QList<QDBusObjectPath>>(devVar);
    } else if (devVar.canConvert<QDBusArgument>()) {
        const auto arg = devVar.value<QDBusArgument>();
        devPaths = qdbus_cast<QList<QDBusObjectPath>>(arg);
    }

    QString foundDevPath;
    for (const auto &dPath : devPaths) {
        QDBusInterface dev(QStringLiteral("org.freedesktop.NetworkManager"),
                           dPath.path(),
                           QStringLiteral("org.freedesktop.NetworkManager.Device"),
                           bus);
        if (!dev.isValid()) continue;

        const uint devType = dev.property("DeviceType").toUInt();
        if (devType == 1) {
            const QString ifaceName = dev.property("Interface").toString();
            if (ifaceName == state.iface || state.iface.isEmpty()) {
                state.iface = ifaceName;
                foundDevPath = dPath.path();

                const uint devState = dev.property("State").toUInt();
                Q_UNUSED(devState)

                QDBusInterface wired(QStringLiteral("org.freedesktop.NetworkManager"),
                                     foundDevPath,
                                     QStringLiteral("org.freedesktop.NetworkManager.Device.Wired"),
                                     bus);
                if (wired.isValid()) {
                    state.carrier = wired.property("Carrier").toBool();
                    state.speedMbps = static_cast<int>(wired.property("Speed").toUInt());
                    state.hwAddress = wired.property("HwAddress").toString();
                }

                const QDBusObjectPath acPath = dev.property("ActiveConnection").value<QDBusObjectPath>();
                if (!acPath.path().isEmpty() && acPath.path() != QStringLiteral("/")) {
                    QDBusInterface ac(QStringLiteral("org.freedesktop.NetworkManager"),
                                      acPath.path(),
                                      QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"),
                                      bus);
                    if (ac.isValid()) {
                        state.connectionName = ac.property("Id").toString();
                        state.isDefaultRoute = ac.property("Default").toBool();

                        auto getPropertyRaw = [&](const QString &path, const QString &iface, const QString &prop) -> QVariant {
                            QDBusMessage msg = QDBusMessage::createMethodCall(
                                QStringLiteral("org.freedesktop.NetworkManager"),
                                path,
                                QStringLiteral("org.freedesktop.DBus.Properties"),
                                QStringLiteral("Get")
                            );
                            msg << iface << prop;
                            QDBusMessage reply = bus.call(msg);
                            if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
                                const QDBusVariant dbusVar = qvariant_cast<QDBusVariant>(reply.arguments().first());
                                return dbusVar.variant();
                            }
                            return QVariant();
                        };

                        const QDBusObjectPath ip4Path = ac.property("Ip4Config").value<QDBusObjectPath>();
                        if (!ip4Path.path().isEmpty() && ip4Path.path() != QStringLiteral("/")) {
                            QDBusInterface ip4(QStringLiteral("org.freedesktop.NetworkManager"),
                                               ip4Path.path(),
                                               QStringLiteral("org.freedesktop.NetworkManager.IP4Config"),
                                               bus);
                            if (ip4.isValid()) {
                                state.gateway = ip4.property("Gateway").toString();
                                parseAddressData(getPropertyRaw(ip4Path.path(), QStringLiteral("org.freedesktop.NetworkManager.IP4Config"), QStringLiteral("AddressData")), state.ip);
                                parseNameserverData(getPropertyRaw(ip4Path.path(), QStringLiteral("org.freedesktop.NetworkManager.IP4Config"), QStringLiteral("NameserverData")), state.dns);

                                                        if (state.dns.isEmpty()) {
                                    const QVariant nsVar = ip4.property("Nameservers");
                                    if (nsVar.canConvert<QList<uint>>()) {
                                        const auto nsList = nsVar.value<QList<uint>>();
                                        for (uint ns : nsList) {
                                            struct in_addr in;
                                            in.s_addr = ns;
                                            char buf[INET_ADDRSTRLEN];
                                            if (::inet_ntop(AF_INET, &in, buf, sizeof(buf))) {
                                                const QString nsStr = QString::fromUtf8(buf);
                                                if (!state.dns.contains(nsStr)) {
                                                    state.dns.append(nsStr);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        const QDBusObjectPath ip6Path = ac.property("Ip6Config").value<QDBusObjectPath>();
                        if (!ip6Path.path().isEmpty() && ip6Path.path() != QStringLiteral("/")) {
                            parseAddressData(getPropertyRaw(ip6Path.path(), QStringLiteral("org.freedesktop.NetworkManager.IP6Config"), QStringLiteral("AddressData")), state.ipv6);
                        }
                    }
                }
                break;
            }
        }
    }

    return true;
}

void EthernetProbe::querySysfsAndPosixFallback(EthernetState &state) {
    const std::string ifaceStr = state.iface.toStdString();
    const std::string basePath = "/sys/class/net/" + ifaceStr;

    if (!state.carrier) {
        const QString c = readSysfsTrimmed(basePath + "/carrier");
        if (c == QStringLiteral("1")) {
            state.carrier = true;
        }
    }

    state.operstate = readSysfsTrimmed(basePath + "/operstate");
    if (state.operstate.isEmpty()) {
        state.operstate = state.carrier ? QStringLiteral("up") : QStringLiteral("down");
    }

    if (state.speedMbps <= 0) {
        const QString s = readSysfsTrimmed(basePath + "/speed");
        if (!s.isEmpty()) {
            state.speedMbps = s.toInt();
        }
    }

    if (state.hwAddress.isEmpty()) {
        state.hwAddress = readSysfsTrimmed(basePath + "/address");
    }

    if (state.ip.isEmpty() || state.ipv6.isEmpty()) {
        struct ifaddrs *ifap = nullptr;
        if (::getifaddrs(&ifap) == 0 && ifap) {
            for (auto ifa = ifap; ifa != nullptr; ifa = ifa->ifa_next) {
                if (!ifa->ifa_addr || state.iface != QString::fromLatin1(ifa->ifa_name)) {
                    continue;
                }

                if (ifa->ifa_addr->sa_family == AF_INET && state.ip.isEmpty()) {
                    char ipBuf[INET_ADDRSTRLEN];
                    auto *sin = reinterpret_cast<struct sockaddr_in *>(ifa->ifa_addr);
                    if (::inet_ntop(AF_INET, &sin->sin_addr, ipBuf, sizeof(ipBuf))) {
                        int prefix = 0;
                        if (ifa->ifa_netmask) {
                            auto *smask = reinterpret_cast<struct sockaddr_in *>(ifa->ifa_netmask);
                            prefix = __builtin_popcount(smask->sin_addr.s_addr);
                        }
                        state.ip = QString::fromUtf8(ipBuf) + QStringLiteral("/") + QString::number(prefix > 0 ? prefix : 24);
                    }
                } else if (ifa->ifa_addr->sa_family == AF_INET6 && state.ipv6.isEmpty()) {
                    auto *sin6 = reinterpret_cast<struct sockaddr_in6 *>(ifa->ifa_addr);
                    if (!IN6_IS_ADDR_LINKLOCAL(&sin6->sin6_addr)) {
                        char ip6Buf[INET6_ADDRSTRLEN];
                        if (::inet_ntop(AF_INET6, &sin6->sin6_addr, ip6Buf, sizeof(ip6Buf))) {
                            state.ipv6 = QString::fromUtf8(ip6Buf) + QStringLiteral("/64");
                        }
                    }
                }
            }
            ::freeifaddrs(ifap);
        }
    }

    if (state.gateway.isEmpty()) {
        std::ifstream routeFile("/proc/net/route");
        if (routeFile.is_open()) {
            std::string line;
            std::getline(routeFile, line);
            while (std::getline(routeFile, line)) {
                std::istringstream iss(line);
                std::string rIface;
                unsigned long dest = 0;
                unsigned long gw = 0;
                unsigned int flags = 0;
                if (iss >> rIface >> std::hex >> dest >> gw >> flags) {
                    if (rIface == ifaceStr && dest == 0 && (flags & 0x2)) {
                        struct in_addr gwAddr;
                        gwAddr.s_addr = static_cast<in_addr_t>(gw);
                        char gwBuf[INET_ADDRSTRLEN];
                        if (::inet_ntop(AF_INET, &gwAddr, gwBuf, sizeof(gwBuf))) {
                            state.gateway = QString::fromUtf8(gwBuf);
                            state.isDefaultRoute = true;
                            break;
                        }
                    }
                }
            }
        }
    }

    if (state.dns.isEmpty()) {
        std::ifstream resolvFile("/etc/resolv.conf");
        if (resolvFile.is_open()) {
            std::string line;
            while (std::getline(resolvFile, line)) {
                if (line.starts_with("nameserver ")) {
                    std::istringstream iss(line);
                    std::string token, ns;
                    if (iss >> token >> ns && !ns.empty()) {
                        const QString nsStr = QString::fromStdString(ns);
                        if (!state.dns.contains(nsStr)) {
                            state.dns.append(nsStr);
                        }
                    }
                }
            }
        }
    }
}

bool EthernetProbe::testInternetSocket(const QString &ipAddress, int timeoutMs) {
    auto tryConnect = [&](const char *host, int port) -> bool {
        int sock = ::socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        if (sock < 0) return false;

        if (!ipAddress.isEmpty()) {
            const QString cleanIp = ipAddress.section('/', 0, 0).trimmed();
            if (!cleanIp.isEmpty()) {
                struct sockaddr_in srcAddr{};
                srcAddr.sin_family = AF_INET;
                srcAddr.sin_port = 0;
                if (::inet_pton(AF_INET, cleanIp.toUtf8().constData(), &srcAddr.sin_addr) > 0) {
                    ::bind(sock, reinterpret_cast<struct sockaddr *>(&srcAddr), sizeof(srcAddr));
                }
            }
        }

        struct sockaddr_in dstAddr{};
        dstAddr.sin_family = AF_INET;
        dstAddr.sin_port = htons(static_cast<uint16_t>(port));
        if (::inet_pton(AF_INET, host, &dstAddr.sin_addr) <= 0) {
            ::close(sock);
            return false;
        }

        int res = ::connect(sock, reinterpret_cast<struct sockaddr *>(&dstAddr), sizeof(dstAddr));
        bool ok = false;
        if (res == 0) {
            ok = true;
        } else if (errno == EINPROGRESS) {
            struct pollfd pfd{};
            pfd.fd = sock;
            pfd.events = POLLOUT;
            int pret = ::poll(&pfd, 1, timeoutMs);
            if (pret > 0 && (pfd.revents & POLLOUT)) {
                int err = 0;
                socklen_t len = sizeof(err);
                if (::getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && err == 0) {
                    ok = true;
                }
            }
        }

        ::close(sock);
        return ok;
    };

    if (tryConnect("1.1.1.1", 53)) {
        return true;
    }
    return tryConnect("8.8.8.8", 53);
}

PingResult EthernetProbe::pingHost(const QString &host, int timeoutMs) {
    PingResult result;
    result.target = host;

    int sock = ::socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, IPPROTO_ICMP);
    if (sock >= 0) {
        struct sockaddr_in dstAddr{};
        dstAddr.sin_family = AF_INET;
        dstAddr.sin_port = 0;
        if (::inet_pton(AF_INET, host.toUtf8().constData(), &dstAddr.sin_addr) > 0) {
            struct icmphdr icmp{};
            icmp.type = ICMP_ECHO;
            icmp.code = 0;
            icmp.un.echo.id = htons(static_cast<uint16_t>(::getpid() & 0xFFFF));
            icmp.un.echo.sequence = htons(1);

            char packet[64];
            std::memset(packet, 0, sizeof(packet));
            std::memcpy(packet, &icmp, sizeof(icmp));
            std::memcpy(packet + sizeof(icmp), "QUICKSHELL_PING", 15);

            const auto t0 = std::chrono::steady_clock::now();
            ssize_t sent = ::sendto(sock, packet, sizeof(packet), 0,
                                    reinterpret_cast<struct sockaddr *>(&dstAddr), sizeof(dstAddr));
            if (sent > 0) {
                struct pollfd pfd{};
                pfd.fd = sock;
                pfd.events = POLLIN;
                int pret = ::poll(&pfd, 1, timeoutMs);
                if (pret > 0 && (pfd.revents & POLLIN)) {
                    char recvBuf[128];
                    struct sockaddr_in fromAddr{};
                    socklen_t fromLen = sizeof(fromAddr);
                    ssize_t recvd = ::recvfrom(sock, recvBuf, sizeof(recvBuf), 0,
                                               reinterpret_cast<struct sockaddr *>(&fromAddr), &fromLen);
                    if (recvd > 0) {
                        const auto t1 = std::chrono::steady_clock::now();
                        const double dt = std::chrono::duration<double, std::milli>(t1 - t0).count();
                        result.ok = true;
                        result.latencyMs = dt;
                        result.output = QStringLiteral("64 bytes from %1: seq=1 time=%2 ms (in-process ICMP)")
                                        .arg(host, QString::number(dt, 'f', 2));
                        ::close(sock);
                        return result;
                    }
                }
            }
        }
        ::close(sock);
    }

    // Fallback path: CLI ping. argv form, no shell, so `host` is never
    // interpreted as shell syntax.
    QProcess proc;
    const int timeoutSec = std::max(1, timeoutMs / 1000);
    proc.start(QStringLiteral("ping"),
               {QStringLiteral("-c"), QStringLiteral("1"), QStringLiteral("-W"),
                QString::number(timeoutSec), host});
    if (proc.waitForStarted(1000) && proc.waitForFinished(timeoutMs + 500) && proc.exitCode() == 0) {
        const QString out = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        static const QRegularExpression re(QStringLiteral("time=([\\d\\.]+)\\s*ms"));
        const auto match = re.match(out);
        if (match.hasMatch()) {
            result.ok = true;
            result.latencyMs = match.captured(1).toDouble();
            result.output = out;
            return result;
        }
    }

    result.ok = false;
    result.latencyMs = -1.0;
    result.output = QString::fromUtf8(proc.readAllStandardError()).trimmed();
    if (result.output.isEmpty()) {
        result.output = QStringLiteral("Ping timed out");
    }
    return result;
}

bool EthernetProbe::checkConnectivity() {
    if (auto *info = QNetworkInformation::instance()) {
        return info->reachability() == QNetworkInformation::Reachability::Online;
    }

    auto bus = QDBusConnection::systemBus();
    if (bus.isConnected()) {
        QDBusInterface nm(QStringLiteral("org.freedesktop.NetworkManager"),
                          QStringLiteral("/org/freedesktop/NetworkManager"),
                          QStringLiteral("org.freedesktop.NetworkManager"),
                          bus);
        if (nm.isValid()) {
            // CheckConnectivity reports NM_CONNECTIVITY_FULL (4); any other
            // value, including a portal-limited link, is not full connectivity.
            QDBusReply<uint> reply = nm.call(QStringLiteral("CheckConnectivity"));
            if (reply.isValid()) {
                return reply.value() == 4;
            }
        }
    }
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("networking"), QStringLiteral("connectivity"), QStringLiteral("check")});
    if (!proc.waitForStarted(1000) || !proc.waitForFinished(3000)) {
        proc.kill();
        proc.waitForFinished(500);
        return false;
    }
    return proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
}

QString EthernetProbe::reconnectTarget(const QString &iface) {
    if (!iface.isEmpty()) {
        return iface;
    }
    const QStringList ifaces = findEthernetInterfaces();
    return ifaces.isEmpty() ? QString() : ifaces.first();
}

bool EthernetProbe::openSettings() {
    return QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_networkmanagement")});
}

bool EthernetProbe::queryNetlinkAndEthtool(EthernetState &state) {
    if (state.iface.isEmpty()) return false;
    const std::string ifaceStr = state.iface.toStdString();
    unsigned int ifindex = ::if_nametoindex(ifaceStr.c_str());
    if (ifindex == 0) return false;

    int nl_fd = ::socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
    if (nl_fd >= 0) {
        struct {
            struct nlmsghdr n;
            struct ifinfomsg ifi;
        } req{};
        req.n.nlmsg_len = NLMSG_LENGTH(sizeof(struct ifinfomsg));
        req.n.nlmsg_flags = NLM_F_REQUEST;
        req.n.nlmsg_type = RTM_GETLINK;
        req.ifi.ifi_family = AF_UNSPEC;
        req.ifi.ifi_index = static_cast<int>(ifindex);

        if (::send(nl_fd, &req, req.n.nlmsg_len, 0) > 0) {
            char buf[8192];
            ssize_t len = ::recv(nl_fd, buf, sizeof(buf), 0);
            if (len > 0) {
                for (auto *h = reinterpret_cast<struct nlmsghdr *>(buf);
                     NLMSG_OK(h, len);
                     h = NLMSG_NEXT(h, len)) {
                    if (h->nlmsg_type == NLMSG_DONE || h->nlmsg_type == NLMSG_ERROR) break;
                    if (h->nlmsg_type == RTM_NEWLINK) {
                        auto *ifi = reinterpret_cast<struct ifinfomsg *>(NLMSG_DATA(h));
                        if (ifi->ifi_index == static_cast<int>(ifindex)) {
                            state.carrier = (ifi->ifi_flags & IFF_RUNNING) || (ifi->ifi_flags & IFF_LOWER_UP);

                            auto *rta = IFLA_RTA(ifi);
                            int rta_len = IFLA_PAYLOAD(h);
                            for (; RTA_OK(rta, rta_len); rta = RTA_NEXT(rta, rta_len)) {
                                if (rta->rta_type == IFLA_ADDRESS && RTA_PAYLOAD(rta) == 6) {
                                    const auto *macBytes = reinterpret_cast<const unsigned char *>(RTA_DATA(rta));
                                    char macBuf[18];
                                    std::snprintf(macBuf, sizeof(macBuf), "%02X:%02X:%02X:%02X:%02X:%02X",
                                                  macBytes[0], macBytes[1], macBytes[2],
                                                  macBytes[3], macBytes[4], macBytes[5]);
                                    state.hwAddress = QString::fromLatin1(macBuf);
                                } else if (rta->rta_type == IFLA_OPERSTATE && RTA_PAYLOAD(rta) == sizeof(uint8_t)) {
                                    uint8_t op = *reinterpret_cast<const uint8_t *>(RTA_DATA(rta));
                                    state.operstate = (op == 6) ? QStringLiteral("up") : QStringLiteral("down");
                                } else if (rta->rta_type == IFLA_STATS64 && RTA_PAYLOAD(rta) >= sizeof(struct rtnl_link_stats64)) {
                                    const auto *stats = reinterpret_cast<const struct rtnl_link_stats64 *>(RTA_DATA(rta));
                                    state.rxBytes = stats->rx_bytes;
                                    state.txBytes = stats->tx_bytes;
                                }
                            }
                        }
                    }
                }
            }
        }
        ::close(nl_fd);
    }

    int sock = ::socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (sock >= 0) {
        struct ifreq ifr{};
        std::strncpy(ifr.ifr_name, ifaceStr.c_str(), IFNAMSIZ - 1);
        struct ethtool_cmd edata{};
        edata.cmd = ETHTOOL_GSET;
        ifr.ifr_data = reinterpret_cast<char *>(&edata);
        if (::ioctl(sock, SIOCETHTOOL, &ifr) == 0) {
            int speed = ethtool_cmd_speed(&edata);
            if (speed > 0 && speed < 1000000) {
                state.speedMbps = speed;
            }
        }
        ::close(sock);
    }

    return true;
}

bool EthernetProbe::queryNetworkManagerFast(EthernetState &state) {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) return false;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.NetworkManager"),
        QStringLiteral("/org/freedesktop/NetworkManager"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Get")
    );
    msg << QStringLiteral("org.freedesktop.NetworkManager") << QStringLiteral("Connectivity");
    QDBusMessage reply = bus.call(msg);
    if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
        const QDBusVariant v = qvariant_cast<QDBusVariant>(reply.arguments().first());
        state.nmConnectivity = static_cast<int>(v.variant().toUInt());
    }

    static QString s_cachedConName;
    static QString s_cachedGateway;
    static QStringList s_cachedDns;
    static std::chrono::steady_clock::time_point s_lastNmQuery{};

    const auto now = std::chrono::steady_clock::now();
    const bool shouldQueryDeep = s_cachedConName.isEmpty() ||
        std::chrono::duration<double>(now - s_lastNmQuery).count() > 3.0;

    if (shouldQueryDeep) {
        s_lastNmQuery = now;
        QDBusMessage primMsg = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("/org/freedesktop/NetworkManager"),
            QStringLiteral("org.freedesktop.DBus.Properties"),
            QStringLiteral("Get")
        );
        primMsg << QStringLiteral("org.freedesktop.NetworkManager") << QStringLiteral("PrimaryConnection");
        QDBusMessage primReply = bus.call(primMsg);
        if (primReply.type() == QDBusMessage::ReplyMessage && !primReply.arguments().isEmpty()) {
            const QDBusVariant pv = qvariant_cast<QDBusVariant>(primReply.arguments().first());
            const QDBusObjectPath acPath = pv.variant().value<QDBusObjectPath>();
            if (!acPath.path().isEmpty() && acPath.path() != QStringLiteral("/")) {
                QDBusMessage idMsg = QDBusMessage::createMethodCall(
                    QStringLiteral("org.freedesktop.NetworkManager"),
                    acPath.path(),
                    QStringLiteral("org.freedesktop.DBus.Properties"),
                    QStringLiteral("Get")
                );
                idMsg << QStringLiteral("org.freedesktop.NetworkManager.Connection.Active") << QStringLiteral("Id");
                QDBusMessage idReply = bus.call(idMsg);
                if (idReply.type() == QDBusMessage::ReplyMessage && !idReply.arguments().isEmpty()) {
                    const QDBusVariant idv = qvariant_cast<QDBusVariant>(idReply.arguments().first());
                    s_cachedConName = idv.variant().toString();
                }

                QDBusMessage ip4Msg = QDBusMessage::createMethodCall(
                    QStringLiteral("org.freedesktop.NetworkManager"),
                    acPath.path(),
                    QStringLiteral("org.freedesktop.DBus.Properties"),
                    QStringLiteral("Get")
                );
                ip4Msg << QStringLiteral("org.freedesktop.NetworkManager.Connection.Active") << QStringLiteral("Ip4Config");
                QDBusMessage ip4Reply = bus.call(ip4Msg);
                if (ip4Reply.type() == QDBusMessage::ReplyMessage && !ip4Reply.arguments().isEmpty()) {
                    const QDBusVariant ip4v = qvariant_cast<QDBusVariant>(ip4Reply.arguments().first());
                    const QDBusObjectPath ip4Path = ip4v.variant().value<QDBusObjectPath>();
                    if (!ip4Path.path().isEmpty() && ip4Path.path() != QStringLiteral("/")) {
                        QDBusMessage gwMsg = QDBusMessage::createMethodCall(
                            QStringLiteral("org.freedesktop.NetworkManager"),
                            ip4Path.path(),
                            QStringLiteral("org.freedesktop.DBus.Properties"),
                            QStringLiteral("Get")
                        );
                        gwMsg << QStringLiteral("org.freedesktop.NetworkManager.IP4Config") << QStringLiteral("Gateway");
                        QDBusMessage gwReply = bus.call(gwMsg);
                        if (gwReply.type() == QDBusMessage::ReplyMessage && !gwReply.arguments().isEmpty()) {
                            const QDBusVariant gwv = qvariant_cast<QDBusVariant>(gwReply.arguments().first());
                            s_cachedGateway = gwv.variant().toString();
                        }

                        QDBusMessage nsMsg = QDBusMessage::createMethodCall(
                            QStringLiteral("org.freedesktop.NetworkManager"),
                            ip4Path.path(),
                            QStringLiteral("org.freedesktop.DBus.Properties"),
                            QStringLiteral("Get")
                        );
                        nsMsg << QStringLiteral("org.freedesktop.NetworkManager.IP4Config") << QStringLiteral("Nameservers");
                        QDBusMessage nsReply = bus.call(nsMsg);
                        if (nsReply.type() == QDBusMessage::ReplyMessage && !nsReply.arguments().isEmpty()) {
                            const QDBusVariant nsv = qvariant_cast<QDBusVariant>(nsReply.arguments().first());
                            QList<uint> nsList;
                            if (nsv.variant().canConvert<QList<uint>>()) {
                                nsList = nsv.variant().value<QList<uint>>();
                            } else if (nsv.variant().canConvert<QDBusArgument>()) {
                                const auto arg = nsv.variant().value<QDBusArgument>();
                                nsList = qdbus_cast<QList<uint>>(arg);
                            }
                            if (!nsList.isEmpty()) {
                                s_cachedDns.clear();
                                for (uint ns : nsList) {
                                    struct in_addr in;
                                    in.s_addr = ns;
                                    char buf[INET_ADDRSTRLEN];
                                    if (::inet_ntop(AF_INET, &in, buf, sizeof(buf))) {
                                        s_cachedDns.append(QString::fromUtf8(buf));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (!s_cachedConName.isEmpty()) {
        state.connectionName = s_cachedConName;
    }
    if (!s_cachedGateway.isEmpty() && state.gateway.isEmpty()) {
        state.gateway = s_cachedGateway;
    }
    if (!s_cachedDns.isEmpty() && state.dns.isEmpty()) {
        state.dns = s_cachedDns;
    }

    return true;
}

EthernetState EthernetProbe::probe(bool checkInternet) {
    const auto t0 = std::chrono::steady_clock::now();

    EthernetState state;
    state.ifaces = findEthernetInterfaces();
    if (state.ifaces.isEmpty()) {
        state.ok = false;
        state.status = QStringLiteral("not_found");
        state.statusDesc = QStringLiteral("No ethernet interface detected");
        const auto t1 = std::chrono::steady_clock::now();
        state.queryTimeMs = std::chrono::duration<double, std::milli>(t1 - t0).count();
        return state;
    }

    state.iface = state.ifaces.first();

    queryNetlinkAndEthtool(state);

    queryNetworkManagerFast(state);

    if (state.ip.isEmpty() || state.gateway.isEmpty() || state.dns.isEmpty() || state.hwAddress.isEmpty()) {
        querySysfsAndPosixFallback(state);
    }

    if (state.rxBytes == 0 && state.txBytes == 0) {
        readRxTxBytes(state.iface, state.rxBytes, state.txBytes);
    }

    if (state.speedMbps > 0) {
        if (state.speedMbps >= 1000) {
            state.speedLabel = QString::number(state.speedMbps / 1000) + QStringLiteral(" Gbps");
        } else {
            state.speedLabel = QString::number(state.speedMbps) + QStringLiteral(" Mbps");
        }
    } else {
        state.speedLabel = QStringLiteral("Unknown");
    }

    if (state.carrier && !state.ip.isEmpty()) {
        if (state.nmConnectivity == 4) {
            state.hasInternet = true;
        } else if (checkInternet) {
            state.hasInternet = testInternetSocket(state.ip, 600);
        }
    }

    if (!state.carrier) {
        state.status = QStringLiteral("unplugged");
        state.statusDesc = QStringLiteral("Cable Unplugged");
    } else if (state.ip.isEmpty()) {
        state.status = QStringLiteral("connecting");
        state.statusDesc = QStringLiteral("Connecting / Acquiring IP...");
    } else if (state.hasInternet) {
        state.status = QStringLiteral("internet");
        state.statusDesc = QStringLiteral("Connected • Internet OK");
    } else {
        state.status = QStringLiteral("no_internet");
        state.statusDesc = QStringLiteral("Connected • No Internet");
    }

    state.ok = true;
    const auto t1 = std::chrono::steady_clock::now();
    state.queryTimeMs = std::chrono::duration<double, std::milli>(t1 - t0).count();

    return state;
}

static QString formatDataBytes(quint64 bytes) {
    constexpr double KB = 1024.0;
    constexpr double MB = KB * 1024.0;
    constexpr double GB = MB * 1024.0;
    constexpr double TB = GB * 1024.0;

    if (bytes < 1024) {
        return QString::number(bytes) + QStringLiteral(" B");
    } else if (bytes < MB) {
        return QString::number(bytes / KB, 'f', 1) + QStringLiteral(" KB");
    } else if (bytes < GB) {
        return QString::number(bytes / MB, 'f', 1) + QStringLiteral(" MB");
    } else if (bytes < TB) {
        return QString::number(bytes / GB, 'f', 2) + QStringLiteral(" GB");
    } else {
        return QString::number(bytes / TB, 'f', 2) + QStringLiteral(" TB");
    }
}

QVariantMap EthernetProbe::queryVnstat(const QString &iface, int billingDay) {
    QVariantMap result;
    result.insert(QStringLiteral("hasData"), false);

    QProcess proc;
    QStringList args;
    args << QStringLiteral("--json");

    proc.start(QStringLiteral("vnstat"), args);
    if (!proc.waitForStarted(1500) || !proc.waitForFinished(3000)) {
        proc.kill();
        result.insert(QStringLiteral("error"), QStringLiteral("vnstat failed to start or timed out"));
        return result;
    }

    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        result.insert(QStringLiteral("error"), QString::fromUtf8(proc.readAllStandardError()).trimmed());
        return result;
    }

    const QByteArray rawJson = proc.readAllStandardOutput();
    QJsonParseError parseErr;
    const QJsonDocument doc = QJsonDocument::fromJson(rawJson, &parseErr);
    if (doc.isNull() || !doc.isObject()) {
        result.insert(QStringLiteral("error"), QStringLiteral("Invalid JSON from vnstat"));
        return result;
    }

    const QJsonObject rootObj = doc.object();
    const QJsonArray itfArray = rootObj.value(QStringLiteral("interfaces")).toArray();
    if (itfArray.isEmpty()) {
        result.insert(QStringLiteral("error"), QStringLiteral("No interfaces found in vnstat output"));
        return result;
    }

    QJsonObject chosenItf;
    if (!iface.isEmpty()) {
        for (const auto &val : itfArray) {
            const QJsonObject itfObj = val.toObject();
            if (itfObj.value(QStringLiteral("name")).toString() == iface) {
                chosenItf = itfObj;
                break;
            }
        }
    }
    if (chosenItf.isEmpty()) {
        chosenItf = itfArray.first().toObject();
    }

    const QJsonObject traffic = chosenItf.value(QStringLiteral("traffic")).toObject();
    const QJsonArray dayArray = traffic.value(QStringLiteral("day")).toArray();
    const QJsonArray hourArray = traffic.value(QStringLiteral("hour")).toArray();
    const QJsonArray yearArray = traffic.value(QStringLiteral("year")).toArray();

    const QDateTime now = QDateTime::currentDateTime();
    const QDate todayDate = now.date();
    const qint64 nowEpoch = now.toSecsSinceEpoch();

    auto makePeriodMap = [](quint64 rx, quint64 tx) -> QVariantMap {
        QVariantMap m;
        m.insert(QStringLiteral("rx"), static_cast<qulonglong>(rx));
        m.insert(QStringLiteral("tx"), static_cast<qulonglong>(tx));
        m.insert(QStringLiteral("total"), static_cast<qulonglong>(rx + tx));
        m.insert(QStringLiteral("rxFormatted"), formatDataBytes(rx));
        m.insert(QStringLiteral("txFormatted"), formatDataBytes(tx));
        m.insert(QStringLiteral("totalFormatted"), formatDataBytes(rx + tx));
        return m;
    };

    quint64 todayRx = 0, todayTx = 0;
    for (const auto &val : dayArray) {
        const QJsonObject d = val.toObject();
        const QJsonObject dateObj = d.value(QStringLiteral("date")).toObject();
        if (dateObj.value(QStringLiteral("year")).toInt() == todayDate.year() &&
            dateObj.value(QStringLiteral("month")).toInt() == todayDate.month() &&
            dateObj.value(QStringLiteral("day")).toInt() == todayDate.day()) {
            todayRx = static_cast<quint64>(d.value(QStringLiteral("rx")).toVariant().toULongLong());
            todayTx = static_cast<quint64>(d.value(QStringLiteral("tx")).toVariant().toULongLong());
            break;
        }
    }

    quint64 r24Rx = 0, r24Tx = 0;
    const qint64 cutoff24h = nowEpoch - 86400;
    for (const auto &val : hourArray) {
        const QJsonObject h = val.toObject();
        const qint64 ts = h.value(QStringLiteral("timestamp")).toVariant().toLongLong();
        if (ts >= cutoff24h) {
            r24Rx += static_cast<quint64>(h.value(QStringLiteral("rx")).toVariant().toULongLong());
            r24Tx += static_cast<quint64>(h.value(QStringLiteral("tx")).toVariant().toULongLong());
        }
    }
    if (r24Rx == 0 && r24Tx == 0 && (todayRx > 0 || todayTx > 0)) {
        r24Rx = todayRx;
        r24Tx = todayTx;
    }

    const int dayOfWeek = todayDate.dayOfWeek();
    const QDate mondayDate = todayDate.addDays(-(dayOfWeek - 1));
    quint64 weekRx = 0, weekTx = 0;
    for (const auto &val : dayArray) {
        const QJsonObject d = val.toObject();
        const QJsonObject dateObj = d.value(QStringLiteral("date")).toObject();
        const QDate dDate(dateObj.value(QStringLiteral("year")).toInt(),
                          dateObj.value(QStringLiteral("month")).toInt(),
                          dateObj.value(QStringLiteral("day")).toInt());
        if (dDate >= mondayDate && dDate <= todayDate) {
            weekRx += static_cast<quint64>(d.value(QStringLiteral("rx")).toVariant().toULongLong());
            weekTx += static_cast<quint64>(d.value(QStringLiteral("tx")).toVariant().toULongLong());
        }
    }

    QDate cycleStartDate;
    if (todayDate.day() >= billingDay) {
        cycleStartDate = QDate(todayDate.year(), todayDate.month(), billingDay);
    } else {
        const QDate prevMonth = todayDate.addMonths(-1);
        cycleStartDate = QDate(prevMonth.year(), prevMonth.month(), billingDay);
    }
    const QDate cycleEndDate = cycleStartDate.addMonths(1).addDays(-1);

    quint64 cycleRx = 0, cycleTx = 0;
    for (const auto &val : dayArray) {
        const QJsonObject d = val.toObject();
        const QJsonObject dateObj = d.value(QStringLiteral("date")).toObject();
        const QDate dDate(dateObj.value(QStringLiteral("year")).toInt(),
                          dateObj.value(QStringLiteral("month")).toInt(),
                          dateObj.value(QStringLiteral("day")).toInt());
        if (dDate >= cycleStartDate && dDate <= todayDate) {
            cycleRx += static_cast<quint64>(d.value(QStringLiteral("rx")).toVariant().toULongLong());
            cycleTx += static_cast<quint64>(d.value(QStringLiteral("tx")).toVariant().toULongLong());
        }
    }

    quint64 yearRx = 0, yearTx = 0;
    bool foundYear = false;
    for (const auto &val : yearArray) {
        const QJsonObject y = val.toObject();
        const QJsonObject dateObj = y.value(QStringLiteral("date")).toObject();
        if (dateObj.value(QStringLiteral("year")).toInt() == todayDate.year()) {
            yearRx = static_cast<quint64>(y.value(QStringLiteral("rx")).toVariant().toULongLong());
            yearTx = static_cast<quint64>(y.value(QStringLiteral("tx")).toVariant().toULongLong());
            foundYear = true;
            break;
        }
    }
    if (!foundYear) {
        for (const auto &val : dayArray) {
            const QJsonObject d = val.toObject();
            const QJsonObject dateObj = d.value(QStringLiteral("date")).toObject();
            if (dateObj.value(QStringLiteral("year")).toInt() == todayDate.year()) {
                yearRx += static_cast<quint64>(d.value(QStringLiteral("rx")).toVariant().toULongLong());
                yearTx += static_cast<quint64>(d.value(QStringLiteral("tx")).toVariant().toULongLong());
            }
        }
    }

    result.insert(QStringLiteral("hasData"), true);
    result.insert(QStringLiteral("interface"), chosenItf.value(QStringLiteral("name")).toString());
    result.insert(QStringLiteral("today"), makePeriodMap(todayRx, todayTx));
    result.insert(QStringLiteral("rolling24h"), makePeriodMap(r24Rx, r24Tx));
    result.insert(QStringLiteral("thisWeek"), makePeriodMap(weekRx, weekTx));
    result.insert(QStringLiteral("billingCycle"), makePeriodMap(cycleRx, cycleTx));
    result.insert(QStringLiteral("thisYear"), makePeriodMap(yearRx, yearTx));
    result.insert(QStringLiteral("cycleRange"), QStringLiteral("%1 – %2")
        .arg(cycleStartDate.toString(QStringLiteral("MMM d")), cycleEndDate.toString(QStringLiteral("MMM d"))));
    result.insert(QStringLiteral("cycleDay"), billingDay);
    result.insert(QStringLiteral("yearLabel"), QString::number(todayDate.year()));
    result.insert(QStringLiteral("updatedAt"), now.toString(QStringLiteral("hh:mm AP")));

    return result;
}

} // namespace qs::plugins
