#pragma once

#include "EthernetState.hpp"
#include <QString>
#include <QStringList>

namespace qs::plugins {

struct PingResult {
    bool ok{false};
    QString target;
    double latencyMs{-1.0};
    QString output;
};

class EthernetProbe {
public:
    static EthernetState probe(bool checkInternet = true);
    static QStringList findEthernetInterfaces();
    static bool readRxTxBytes(const QString &iface, quint64 &rx, quint64 &tx);
    static PingResult pingHost(const QString &host = QStringLiteral("1.1.1.1"), int timeoutMs = 1500);
    static bool testInternetSocket(const QString &ipAddress = QString(), int timeoutMs = 800);
    static bool checkConnectivity();
    static bool reconnectDevice(const QString &iface = QString());
    static bool openSettings();

    // Low-level component probes
    static bool queryNetworkManager(EthernetState &state);
    static void querySysfsAndPosixFallback(EthernetState &state);
};

} // namespace qs::plugins
