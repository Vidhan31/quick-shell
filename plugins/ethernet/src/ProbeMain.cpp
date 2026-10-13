#include "EthernetProbe.hpp"

#include <QCoreApplication>
#include <QJsonObject>
#include <QJsonDocument>
#include <QProcess>
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
        // The production path is asynchronous (EthernetWorker drives nmcli and
        // reports the real exit code), so drive the same two stages here and
        // block for the outcome rather than reporting a bare spawn success.
        const QString iface = (argc > 2) ? QString::fromUtf8(argv[2]) : QString();
        const QString target = EthernetProbe::reconnectTarget(iface);
        if (target.isEmpty()) {
            QJsonObject obj;
            obj.insert(QStringLiteral("ok"), false);
            obj.insert(QStringLiteral("error"), QStringLiteral("No ethernet interface found"));
            std::cout << QJsonDocument(obj).toJson(QJsonDocument::Compact).toStdString() << std::endl;
            return 1;
        }

        bool ok = false;
        QString output;
        for (const QString &verb : {QStringLiteral("reapply"), QStringLiteral("connect")}) {
            QProcess proc;
            proc.start(QStringLiteral("nmcli"), {QStringLiteral("device"), verb, target});
            if (!proc.waitForStarted(2000) || !proc.waitForFinished(15000)) {
                proc.kill();
                proc.waitForFinished(500);
                output = QStringLiteral("nmcli device %1 timed out").arg(verb);
                continue;
            }
            output = QString::fromUtf8(proc.readAll()).trimmed();
            ok = proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
            if (ok) {
                break;
            }
        }

        QJsonObject obj;
        obj.insert(QStringLiteral("ok"), ok);
        obj.insert(QStringLiteral("interface"), target);
        if (!output.isEmpty()) {
            obj.insert(QStringLiteral("output"), output);
        }
        std::cout << QJsonDocument(obj).toJson(QJsonDocument::Compact).toStdString() << std::endl;
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
