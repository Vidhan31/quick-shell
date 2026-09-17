#include "EthernetProbe.hpp"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QProcess>
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
    // Trim trailing newline or whitespace
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' || buf[n - 1] == ' ')) {
        buf[--n] = '\0';
    }
    return QString::fromUtf8(buf, static_cast<qsizetype>(n));
}

QStringList EthernetProbe::findEthernetInterfaces() {
    // Fast path: primary interface on this hardware
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

        // Skip wireless interfaces
        if (fs::exists(entry.path() / "wireless", ec) ||
            fs::exists(entry.path() / "phy80211", ec)) {
            continue;
        }

        const QString devType = readSysfsTrimmed((entry.path() / "type").string());
        if (devType == QStringLiteral("1")) { // ARPHRD_ETHER
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
        if (devType == 1) { // NM_DEVICE_TYPE_ETHERNET
            const QString ifaceName = dev.property("Interface").toString();
            if (ifaceName == state.iface || state.iface.isEmpty()) {
                state.iface = ifaceName;
                foundDevPath = dPath.path();

                const uint devState = dev.property("State").toUInt();
                Q_UNUSED(devState)

                // Query Wired device interface
                QDBusInterface wired(QStringLiteral("org.freedesktop.NetworkManager"),
                                     foundDevPath,
                                     QStringLiteral("org.freedesktop.NetworkManager.Device.Wired"),
                                     bus);
                if (wired.isValid()) {
                    state.carrier = wired.property("Carrier").toBool();
                    state.speedMbps = static_cast<int>(wired.property("Speed").toUInt());
                    state.hwAddress = wired.property("HwAddress").toString();
                }

                // Active connection
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

                        // IPv4 Config
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

                                // If dns is still empty, check Nameservers (au)
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

                        // IPv6 Config
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

    // Carrier
    if (!state.carrier) {
        const QString c = readSysfsTrimmed(basePath + "/carrier");
        if (c == QStringLiteral("1")) {
            state.carrier = true;
        }
    }

    // Operstate
    state.operstate = readSysfsTrimmed(basePath + "/operstate");
    if (state.operstate.isEmpty()) {
        state.operstate = state.carrier ? QStringLiteral("up") : QStringLiteral("down");
    }

    // Speed
    if (state.speedMbps <= 0) {
        const QString s = readSysfsTrimmed(basePath + "/speed");
        if (!s.isEmpty()) {
            state.speedMbps = s.toInt();
        }
    }

    // MAC Address
    if (state.hwAddress.isEmpty()) {
        state.hwAddress = readSysfsTrimmed(basePath + "/address");
    }

    // IP Address via getifaddrs()
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
                    // Skip link-local fe80::
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

    // Gateway via /proc/net/route
    if (state.gateway.isEmpty()) {
        std::ifstream routeFile("/proc/net/route");
        if (routeFile.is_open()) {
            std::string line;
            std::getline(routeFile, line); // Skip header
            while (std::getline(routeFile, line)) {
                std::istringstream iss(line);
                std::string rIface;
                unsigned long dest = 0;
                unsigned long gw = 0;
                unsigned int flags = 0;
                if (iss >> rIface >> std::hex >> dest >> gw >> flags) {
                    if (rIface == ifaceStr && dest == 0 && (flags & 0x2)) { // RTF_GATEWAY
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

    // DNS fallback from /etc/resolv.conf
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

    // Primary: 1.1.1.1:53 (Cloudflare DNS)
    if (tryConnect("1.1.1.1", 53)) {
        return true;
    }
    // Secondary fallback: 8.8.8.8:53 (Google DNS)
    return tryConnect("8.8.8.8", 53);
}

PingResult EthernetProbe::pingHost(const QString &host, int timeoutMs) {
    PingResult result;
    result.target = host;

    // Fast path: In-process ICMP socket (IPPROTO_ICMP)
    int sock = ::socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, IPPROTO_ICMP);
    if (sock >= 0) {
        struct sockaddr_in dstAddr{};
        dstAddr.sin_family = AF_INET;
        dstAddr.sin_port = 0;
        if (::inet_pton(AF_INET, host.toUtf8().constData(), &dstAddr.sin_addr) > 0) {
            // Build ICMP Echo Request
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

    // Fallback path: CLI ping execution
    QProcess proc;
    const int timeoutSec = std::max(1, timeoutMs / 1000);
    const QString cmd = QStringLiteral("ping -c 1 -W %1 %2").arg(QString::number(timeoutSec), host);
    proc.start(QStringLiteral("sh"), {QStringLiteral("-c"), cmd});
    if (proc.waitForFinished(timeoutMs + 500) && proc.exitCode() == 0) {
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
    auto bus = QDBusConnection::systemBus();
    if (bus.isConnected()) {
        QDBusInterface nm(QStringLiteral("org.freedesktop.NetworkManager"),
                          QStringLiteral("/org/freedesktop/NetworkManager"),
                          QStringLiteral("org.freedesktop.NetworkManager"),
                          bus);
        if (nm.isValid()) {
            QDBusReply<uint> reply = nm.call(QStringLiteral("CheckConnectivity"));
            if (reply.isValid()) {
                return true;
            }
        }
    }
    return QProcess::execute(QStringLiteral("nmcli"), {QStringLiteral("networking"), QStringLiteral("connectivity"), QStringLiteral("check")}) == 0;
}

bool EthernetProbe::reconnectDevice(const QString &iface) {
    const QString target = iface.isEmpty() ? findEthernetInterfaces().value(0, QStringLiteral("enp34s0")) : iface;
    const QString cmd = QStringLiteral("nmcli device reapply '%1' || nmcli device connect '%1'").arg(target);
    return QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"), cmd});
}

bool EthernetProbe::openSettings() {
    return QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_networkmanagement")});
}

bool EthernetProbe::queryNetlinkAndEthtool(EthernetState &state) {
    if (state.iface.isEmpty()) return false;
    const std::string ifaceStr = state.iface.toStdString();
    unsigned int ifindex = ::if_nametoindex(ifaceStr.c_str());
    if (ifindex == 0) return false;

    // 1. Direct Netlink RTM_GETLINK kernel request
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

    // 2. Ethtool SIOCETHTOOL query for link speed in 1 microsecond
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

    // Fast call to get Connectivity
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

    // Cache connection profile name and DNS across rapid queries
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
                // Get Id
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

                // Get Ip4Config
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
                        // Gateway
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

                        // Nameservers (au)
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

    // 1. Direct Kernel Netlink & Ethtool (carrier, speed, MAC, stats in ~0.05 ms)
    queryNetlinkAndEthtool(state);

    // 2. Fast NetworkManager DBus check (connectivity flag, connection profile, DNS)
    queryNetworkManagerFast(state);

    // 3. POSIX getifaddrs & /proc/net/route fallback (IP, route, resolv.conf)
    querySysfsAndPosixFallback(state);

    // 4. Read RX/TX bytes from sysfs if netlink stats were not populated
    if (state.rxBytes == 0 && state.txBytes == 0) {
        readRxTxBytes(state.iface, state.rxBytes, state.txBytes);
    }

    // Speed label
    if (state.speedMbps > 0) {
        if (state.speedMbps >= 1000) {
            state.speedLabel = QString::number(state.speedMbps / 1000) + QStringLiteral(" Gbps");
        } else {
            state.speedLabel = QString::number(state.speedMbps) + QStringLiteral(" Mbps");
        }
    } else {
        state.speedLabel = QStringLiteral("Unknown");
    }

    // Determine internet connectivity
    if (state.carrier && !state.ip.isEmpty()) {
        if (state.nmConnectivity == 4) {
            state.hasInternet = true;
        } else if (checkInternet) {
            state.hasInternet = testInternetSocket(state.ip, 600);
        }
    }

    // State string representation
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

} // namespace qs::plugins
