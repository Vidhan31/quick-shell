#include "DockerSocketClient.hpp"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>

using namespace qs::plugins;

static void printJson(const QJsonDocument &doc)
{
    std::cout << doc.toJson(QJsonDocument::Indented).toStdString() << std::endl;
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    DockerSocketClient client;

    const QString action = (argc > 1) ? QString::fromUtf8(argv[1]) : QStringLiteral("state");

    if (action == QStringLiteral("ping")) {
        QString err;
        const bool ok = client.ping(&err);
        QJsonObject o;
        o[QStringLiteral("ok")] = ok;
        o[QStringLiteral("socket")] = client.socketPath();
        o[QStringLiteral("error")] = err;
        printJson(QJsonDocument(o));
        return ok ? 0 : 1;
    }

    if (action == QStringLiteral("state")) {
        DockerState st;
        const bool ok = client.fetchFullState(st);
        printJson(QJsonDocument::fromVariant(st.toMap()));
        return ok ? 0 : 1;
    }

    if (action == QStringLiteral("logs")) {
        const QString id = (argc > 2) ? QString::fromUtf8(argv[2]) : QString();
        const int tail = (argc > 3) ? QString::fromUtf8(argv[3]).toInt() : 200;
        if (id.isEmpty()) {
            std::cerr << "usage: docker-probe logs <id> [tail]" << std::endl;
            return 2;
        }
        const LogsResult r = client.fetchLogs(id, tail);
        if (r.ok) {
            std::cout << r.logs.toStdString() << std::endl;
            return 0;
        }
        std::cerr << r.error.toStdString() << std::endl;
        return 1;
    }

    if (action == QStringLiteral("inspect")) {
        const QString id = (argc > 2) ? QString::fromUtf8(argv[2]) : QString();
        if (id.isEmpty()) {
            std::cerr << "usage: docker-probe inspect <id>" << std::endl;
            return 2;
        }
        const HttpResponse r = client.fetchInspect(id);
        std::cout << r.body.toStdString() << std::endl;
        return r.ok ? 0 : 1;
    }

    // Mutating actions are intentionally NOT in the default probe path.
    // They require explicit --i-understand flag to avoid accidents.
    const bool confirmed = (argc > 2 && QString::fromUtf8(argv[argc - 1]) == QStringLiteral("--i-understand"));
    auto needConfirm = [&](const QString &what) -> bool {
        if (!confirmed) {
            std::cerr << "Refusing to " << what.toStdString()
                      << " without --i-understand as last arg (safety)." << std::endl;
            return false;
        }
        return true;
    };

    if (action == QStringLiteral("start") || action == QStringLiteral("stop")
        || action == QStringLiteral("restart") || action == QStringLiteral("kill")) {
        const QString id = (argc > 2) ? QString::fromUtf8(argv[2]) : QString();
        if (id.isEmpty() || !needConfirm(action)) {
            return 2;
        }
        ActionResult r{false, 0, {}, {}};
        if (action == QStringLiteral("start")) {
            r = client.startContainer(id);
        } else if (action == QStringLiteral("stop")) {
            r = client.stopContainer(id);
        } else if (action == QStringLiteral("restart")) {
            r = client.restartContainer(id);
        } else {
            r = client.killContainer(id);
        }
        QJsonObject o;
        o[QStringLiteral("ok")] = r.ok;
        o[QStringLiteral("status")] = r.statusCode;
        o[QStringLiteral("output")] = r.output;
        o[QStringLiteral("error")] = r.error;
        printJson(QJsonDocument(o));
        return r.ok ? 0 : 1;
    }

    std::cerr << "Unknown action: " << action.toStdString()
              << " (ping|state|logs|inspect)" << std::endl;
    return 1;
}
