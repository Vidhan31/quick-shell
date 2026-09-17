#pragma once

#include <QList>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace qs::plugins {

struct TailscaleSelf {
    QString hostname;
    QString dnsName;
    QString ipv4;
    QString ipv6;
    QString os{"linux"};
    bool online{false};
    QString relay;
    QVariantMap user;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("hostname")] = hostname;
        m[QStringLiteral("dns_name")] = dnsName;
        m[QStringLiteral("ipv4")] = ipv4;
        m[QStringLiteral("ipv6")] = ipv6;
        m[QStringLiteral("os")] = os;
        m[QStringLiteral("online")] = online;
        m[QStringLiteral("relay")] = relay;
        m[QStringLiteral("user")] = user;
        return m;
    }
};

struct TailscalePeer {
    QString hostname;
    QString dnsName;
    QString os;
    QString ipv4;
    bool online{false};
    bool active{false};
    QString relay;
    quint64 rxBytes{0};
    quint64 txBytes{0};

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("hostname")] = hostname;
        m[QStringLiteral("dns_name")] = dnsName;
        m[QStringLiteral("os")] = os;
        m[QStringLiteral("ipv4")] = ipv4;
        m[QStringLiteral("online")] = online;
        m[QStringLiteral("active")] = active;
        m[QStringLiteral("relay")] = relay;
        m[QStringLiteral("rx_bytes")] = static_cast<qulonglong>(rxBytes);
        m[QStringLiteral("tx_bytes")] = static_cast<qulonglong>(txBytes);
        return m;
    }
};

struct TailscaleServeItem {
    QString host;
    QString port;
    QString path;
    QString target;
    QString type;
    bool isFunnel{false};
    QString url;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("host")] = host;
        m[QStringLiteral("port")] = port;
        m[QStringLiteral("path")] = path;
        m[QStringLiteral("target")] = target;
        m[QStringLiteral("type")] = type;
        m[QStringLiteral("is_funnel")] = isFunnel;
        m[QStringLiteral("url")] = url;
        return m;
    }
};

struct TailscaleState {
    bool ok{false};
    bool connected{false};
    QString backendState{QStringLiteral("Unknown")};
    QString version;
    QString tailnet;
    QString magicDnsSuffix;
    TailscaleSelf self;
    QVariantList health;
    bool sshEnabled{false};
    bool webclientEnabled{false};
    bool shieldsUp{false};
    bool exitNodeEnabled{false};
    bool autoUpdate{false};
    QList<TailscaleServeItem> serveItems;
    QList<TailscalePeer> peers;
    QVariantList services;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap m;
        m[QStringLiteral("ok")] = ok;
        m[QStringLiteral("connected")] = connected;
        m[QStringLiteral("backend_state")] = backendState;
        m[QStringLiteral("version")] = version;
        m[QStringLiteral("tailnet")] = tailnet;
        m[QStringLiteral("magic_dns_suffix")] = magicDnsSuffix;
        m[QStringLiteral("self")] = self.toMap();
        m[QStringLiteral("health")] = health;
        m[QStringLiteral("ssh_enabled")] = sshEnabled;
        m[QStringLiteral("webclient_enabled")] = webclientEnabled;
        m[QStringLiteral("shields_up")] = shieldsUp;
        m[QStringLiteral("exit_node_enabled")] = exitNodeEnabled;
        m[QStringLiteral("auto_update")] = autoUpdate;

        QVariantList serveList;
        serveList.reserve(serveItems.size());
        for (const auto &item : serveItems) {
            serveList.append(item.toMap());
        }
        m[QStringLiteral("serve_items")] = serveList;

        QVariantList peerList;
        peerList.reserve(peers.size());
        for (const auto &peer : peers) {
            peerList.append(peer.toMap());
        }
        m[QStringLiteral("peers")] = peerList;

        m[QStringLiteral("services")] = services;
        return m;
    }
};

} // namespace qs::plugins
