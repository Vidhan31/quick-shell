#include "ProcessManager.hpp"

#include <QCoreApplication>
#include <iostream>
#include <unistd.h>

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    qs::plugins::ProcessManager pm;

    std::cout << "Testing ProcessManager:\n\n";

    std::cout << "Query detection tests:\n";
    for (const QString &q : {QStringLiteral("k "), QStringLiteral("k firefox"), QStringLiteral("k -9 node"), QStringLiteral("kill"), QStringLiteral("kate")}) {
        std::cout << "  \"" << q.toStdString() << "\" -> isKillQuery: "
                  << (pm.isKillQuery(q) ? "true" : "false")
                  << ", term: \"" << pm.searchTerm(q).toStdString() << "\""
                  << ", sig: " << pm.parseSignalFlag(q) << "\n";
    }

    std::cout << "\nEmpty search results (top candidates):\n";
    QVariantList topList = pm.search(QString(), 0, 8);
    for (int i = 0; i < topList.size(); ++i) {
        QVariantMap m = topList.at(i).toMap();
        std::cout << "  [" << (i + 1) << "] "
                  << m.value(QStringLiteral("kind")).toString().toStdString() << ": "
                  << m.value(QStringLiteral("name")).toString().toStdString()
                  << " (" << m.value(QStringLiteral("generic")).toString().toStdString() << ")\n";
    }

    std::cout << "\nSearch for 'system' or 'sh':\n";
    QVariantList shList = pm.search(QStringLiteral("sh"), 0, 5);
    for (int i = 0; i < shList.size(); ++i) {
        QVariantMap m = shList.at(i).toMap();
        std::cout << "  [" << (i + 1) << "] "
                  << m.value(QStringLiteral("kind")).toString().toStdString() << ": "
                  << m.value(QStringLiteral("name")).toString().toStdString()
                  << " (" << m.value(QStringLiteral("generic")).toString().toStdString() << ")\n";
    }

    std::cout << "\nTesting signal dispatch on test dummy process:\n";
    pid_t child = fork();
    if (child == 0) {
        execlp("sleep", "sleep", "60", nullptr);
        _exit(1);
    }
    if (child > 0) {
        std::cout << "  Spawned sleep with PID " << child << "\n";
        QVariantList sleepSearch = pm.search(QString::number(child), 0, 5);
        if (!sleepSearch.isEmpty()) {
            std::cout << "  Found test process in search: "
                      << sleepSearch.first().toMap().value(QStringLiteral("name")).toString().toStdString() << "\n";
        }

        QVariantMap stopRes = pm.sendSignal(child, 19);
        std::cout << "  SIGSTOP (19): " << stopRes.value(QStringLiteral("message")).toString().toStdString() << "\n";

        QVariantMap contRes = pm.sendSignal(child, 18);
        std::cout << "  SIGCONT (18): " << contRes.value(QStringLiteral("message")).toString().toStdString() << "\n";

        QVariantMap termRes = pm.sendSignal(child, 15);
        std::cout << "  SIGTERM (15): " << termRes.value(QStringLiteral("message")).toString().toStdString() << "\n";
    }

    return 0;
}
