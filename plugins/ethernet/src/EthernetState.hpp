#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>

namespace qs::plugins {

struct EthernetState {
    bool ok{false};
    QString iface{"enp34s0"};
    QStringList ifaces;
    bool carrier{false};
    QString operstate{"unknown"};
    int speedMbps{-1};
    QString speedLabel{"Unknown"};
    QString hwAddress;
    QString ip;
    QString ipv6;
    QString gateway;
    QStringList dns;
    QString connectionName{"Ethernet"};
    int nmConnectivity{0}; // 4 = Full, 3 = Limited, 2 = Portal, 1 = None, 0 = Unknown
    bool hasInternet{false};
    bool isDefaultRoute{false};
    QString status{"offline"};
    QString statusDesc{"Disconnected"};
    quint64 rxBytes{0};
    quint64 txBytes{0};
    double queryTimeMs{0.0};

    [[nodiscard]] bool coreEquals(const EthernetState &other) const noexcept {
        return ok == other.ok &&
               carrier == other.carrier &&
               hasInternet == other.hasInternet &&
               nmConnectivity == other.nmConnectivity &&
               speedMbps == other.speedMbps &&
               isDefaultRoute == other.isDefaultRoute &&
               iface == other.iface &&
               operstate == other.operstate &&
               ip == other.ip &&
               ipv6 == other.ipv6 &&
               gateway == other.gateway &&
               dns == other.dns &&
               hwAddress == other.hwAddress &&
               connectionName == other.connectionName &&
               status == other.status;
    }

    [[nodiscard]] bool operator==(const EthernetState &other) const noexcept {
        return coreEquals(other) &&
               rxBytes == other.rxBytes &&
               txBytes == other.txBytes;
    }

    [[nodiscard]] bool operator!=(const EthernetState &other) const noexcept {
        return !(*this == other);
    }

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap map;
        map.insert(QStringLiteral("ok"), ok);
        map.insert(QStringLiteral("interface"), iface);
        map.insert(QStringLiteral("interfaces"), ifaces);
        map.insert(QStringLiteral("carrier"), carrier);
        map.insert(QStringLiteral("operstate"), operstate);
        map.insert(QStringLiteral("speed_mbps"), speedMbps);
        map.insert(QStringLiteral("speed_label"), speedLabel);
        map.insert(QStringLiteral("hw_address"), hwAddress);
        map.insert(QStringLiteral("ip"), ip);
        map.insert(QStringLiteral("ipv6"), ipv6);
        map.insert(QStringLiteral("gateway"), gateway);
        map.insert(QStringLiteral("dns"), dns);
        map.insert(QStringLiteral("connection_name"), connectionName);
        map.insert(QStringLiteral("nm_connectivity"), nmConnectivity);
        map.insert(QStringLiteral("has_internet"), hasInternet);
        map.insert(QStringLiteral("is_default_route"), isDefaultRoute);
        map.insert(QStringLiteral("status"), status);
        map.insert(QStringLiteral("status_desc"), statusDesc);
        map.insert(QStringLiteral("rx_bytes"), static_cast<qulonglong>(rxBytes));
        map.insert(QStringLiteral("tx_bytes"), static_cast<qulonglong>(txBytes));
        map.insert(QStringLiteral("query_time_ms"), queryTimeMs);
        return map;
    }

    [[nodiscard]] QJsonObject toJsonObject() const {
        QJsonObject obj;
        obj.insert(QStringLiteral("ok"), ok);
        obj.insert(QStringLiteral("interface"), iface);
        
        QJsonArray ifacesArr;
        for (const auto &i : ifaces) {
            ifacesArr.append(i);
        }
        obj.insert(QStringLiteral("interfaces"), ifacesArr);

        obj.insert(QStringLiteral("carrier"), carrier);
        obj.insert(QStringLiteral("operstate"), operstate);
        obj.insert(QStringLiteral("speed_mbps"), speedMbps);
        obj.insert(QStringLiteral("speed_label"), speedLabel);
        obj.insert(QStringLiteral("hw_address"), hwAddress);
        obj.insert(QStringLiteral("ip"), ip);
        obj.insert(QStringLiteral("ipv6"), ipv6);
        obj.insert(QStringLiteral("gateway"), gateway);

        QJsonArray dnsArr;
        for (const auto &d : dns) {
            dnsArr.append(d);
        }
        obj.insert(QStringLiteral("dns"), dnsArr);

        obj.insert(QStringLiteral("connection_name"), connectionName);
        obj.insert(QStringLiteral("nm_connectivity"), nmConnectivity);
        obj.insert(QStringLiteral("has_internet"), hasInternet);
        obj.insert(QStringLiteral("is_default_route"), isDefaultRoute);
        obj.insert(QStringLiteral("status"), status);
        obj.insert(QStringLiteral("status_desc"), statusDesc);
        obj.insert(QStringLiteral("rx_bytes"), static_cast<qint64>(rxBytes));
        obj.insert(QStringLiteral("tx_bytes"), static_cast<qint64>(txBytes));
        obj.insert(QStringLiteral("query_time_ms"), queryTimeMs);
        return obj;
    }

    [[nodiscard]] QString toJsonString(bool compact = true) const {
        const QJsonDocument doc(toJsonObject());
        return QString::fromUtf8(doc.toJson(compact ? QJsonDocument::Compact : QJsonDocument::Indented));
    }
};

} // namespace qs::plugins
