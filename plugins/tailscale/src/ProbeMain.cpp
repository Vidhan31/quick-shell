#include "TailscaleSocketClient.hpp"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>

using namespace qs::plugins;

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    TailscaleSocketClient client;

    const QString action = (argc > 1) ? QString::fromUtf8(argv[1]) : QStringLiteral("status");

    if (action == QStringLiteral("status")) {
        TailscaleState state;
        const bool ok = client.fetchFullStatus(state);
        const QJsonDocument doc = QJsonDocument::fromVariant(state.toMap());
        std::cout << doc.toJson(QJsonDocument::Indented).toStdString() << std::endl;
        return ok ? 0 : 1;
    }

    if (action == QStringLiteral("ping")) {
        const QString ip = (argc > 2) ? QString::fromUtf8(argv[2]) : QString();
        const PingResult res = client.ping(ip);
        QJsonObject obj;
        obj[QStringLiteral("ok")] = res.ok;
        obj[QStringLiteral("ip")] = res.targetIp;
        obj[QStringLiteral("latency")] = res.latency;
        obj[QStringLiteral("latency_ms")] = res.latencyMs;
        obj[QStringLiteral("endpoint")] = res.endpoint;
        obj[QStringLiteral("output")] = res.output;
        obj[QStringLiteral("error")] = res.error;
        std::cout << QJsonDocument(obj).toJson(QJsonDocument::Indented).toStdString() << std::endl;
        return res.ok ? 0 : 1;
    }

    if (action == QStringLiteral("ssh-toggle")) {
        const QString enableStr = (argc > 2) ? QString::fromUtf8(argv[2]) : QStringLiteral("true");
        const bool enable = (enableStr.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0 ||
                             enableStr == QStringLiteral("1") ||
                             enableStr.compare(QStringLiteral("on"), Qt::CaseInsensitive) == 0);
        QString err;
        const bool ok = client.setSSH(enable, &err);
        QJsonObject obj;
        obj[QStringLiteral("ok")] = ok;
        obj[QStringLiteral("error")] = err;
        std::cout << QJsonDocument(obj).toJson(QJsonDocument::Indented).toStdString() << std::endl;
        return ok ? 0 : 1;
    }

    if (action == QStringLiteral("up-down")) {
        const QString act = (argc > 2) ? QString::fromUtf8(argv[2]) : QStringLiteral("up");
        const bool up = (act.compare(QStringLiteral("down"), Qt::CaseInsensitive) != 0);
        QString err;
        const bool ok = client.setWantRunning(up, &err);
        QJsonObject obj;
        obj[QStringLiteral("ok")] = ok;
        obj[QStringLiteral("error")] = err;
        std::cout << QJsonDocument(obj).toJson(QJsonDocument::Indented).toStdString() << std::endl;
        return ok ? 0 : 1;
    }

    if (action == QStringLiteral("netcheck")) {
        const ActionResult res = client.runNetcheck();
        QJsonObject obj;
        obj[QStringLiteral("ok")] = res.ok;
        obj[QStringLiteral("report")] = res.output;
        obj[QStringLiteral("error")] = res.error;
        std::cout << QJsonDocument(obj).toJson(QJsonDocument::Indented).toStdString() << std::endl;
        return res.ok ? 0 : 1;
    }

    std::cerr << "Unknown action: " << action.toStdString() << std::endl;
    return 1;
}
