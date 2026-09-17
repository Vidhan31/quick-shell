#include "EthernetProbe.hpp"

#include <QCoreApplication>
#include <QJsonObject>
#include <QJsonDocument>
#include <iostream>

using namespace qs::plugins;

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    const QString action = (argc > 1) ? QString::fromUtf8(argv[1]) : QStringLiteral("status");

    if (action == QStringLiteral("status")) {
        const auto state = EthernetProbe::probe(true);
        std::cout << state.toJsonString(true).toStdString() << std::endl;
        return state.ok ? 0 : 1;
    }

    if (action == QStringLiteral("ping")) {
        const QString target = (argc > 2) ? QString::fromUtf8(argv[2]) : QStringLiteral("1.1.1.1");
        const auto res = EthernetProbe::pingHost(target);
        QJsonObject obj;
        obj.insert(QStringLiteral("ok"), res.ok);
        obj.insert(QStringLiteral("target"), res.target);
        obj.insert(QStringLiteral("latency_ms"), res.latencyMs);
        obj.insert(QStringLiteral("output"), res.output);
        const QJsonDocument doc(obj);
        std::cout << doc.toJson(QJsonDocument::Compact).toStdString() << std::endl;
        return res.ok ? 0 : 1;
    }

    if (action == QStringLiteral("check")) {
        EthernetProbe::checkConnectivity();
        const auto state = EthernetProbe::probe(true);
        std::cout << state.toJsonString(true).toStdString() << std::endl;
        return 0;
    }

    if (action == QStringLiteral("reconnect")) {
        const QString iface = (argc > 2) ? QString::fromUtf8(argv[2]) : QString();
        const bool ok = EthernetProbe::reconnectDevice(iface);
        QJsonObject obj;
        obj.insert(QStringLiteral("ok"), ok);
        if (!iface.isEmpty()) {
            obj.insert(QStringLiteral("interface"), iface);
        }
        const QJsonDocument doc(obj);
        std::cout << doc.toJson(QJsonDocument::Compact).toStdString() << std::endl;
        return ok ? 0 : 1;
    }

    if (action == QStringLiteral("open-settings")) {
        const bool ok = EthernetProbe::openSettings();
        QJsonObject obj;
        obj.insert(QStringLiteral("ok"), ok);
        const QJsonDocument doc(obj);
        std::cout << doc.toJson(QJsonDocument::Compact).toStdString() << std::endl;
        return ok ? 0 : 1;
    }

    std::cerr << "Unknown action: " << action.toStdString() << std::endl;
    return 1;
}
