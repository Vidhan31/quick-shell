#include "DbusTypes.hpp"
#include "UpdateItem.hpp"
#include "UpdateManager.hpp"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QTextStream>
#include <QTimer>

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    qs::updatemanager::registerDbusTypes();

    QTextStream out(stdout);
    out << "========================================================\n";
    out << "   Quickshell DNF5 Update Manager Diagnostic Probe     \n";
    out << "========================================================\n\n";
    out.flush();

    bool refresh = false;
    bool mock = false;

    for (int i = 1; i < argc; ++i) {
        QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == QStringLiteral("--refresh")) {
            refresh = true;
        } else if (arg == QStringLiteral("--mock")) {
            mock = true;
        }
    }

    auto *mgr = new qs::updatemanager::UpdateManager(&app);

    if (mock) {
        out << "[Mode] Testing Mock Data Provider...\n";
        mgr->setMockMode(true);
        out << "Total Updates: " << mgr->updateCount() << "\n";
        out << "Security Updates: " << mgr->securityCount() << "\n";
        out << "Total Download Size: " << mgr->formattedTotalSize() << "\n";
        out << "Recommended Method: " << mgr->recommendedMethod() << "\n\n";

        auto *model = mgr->model();
        for (int i = 0; i < model->count(); ++i) {
            auto m = model->get(i);
            out << QStringLiteral("  [%1] %2 %3 -> %4 (%5) - %6 [%7]\n")
                       .arg(m[QStringLiteral("categoryKey")].toString().toUpper())
                       .arg(m[QStringLiteral("name")].toString())
                       .arg(m[QStringLiteral("oldEvr")].toString())
                       .arg(m[QStringLiteral("newEvr")].toString())
                       .arg(m[QStringLiteral("formattedSize")].toString())
                       .arg(m[QStringLiteral("advisoryType")].toString())
                       .arg(m[QStringLiteral("severity")].toString());
        }
        out << "\n[Success] Mock test completed cleanly.\n";
        out.flush();
        return 0;
    }

    out << "[Mode] Querying live dnf5daemon-server over system D-Bus...\n";
    if (refresh) {
        out << "[Info] Refresh requested: will expire cache first.\n";
    }
    out.flush();

    QObject::connect(mgr, &qs::updatemanager::UpdateManager::currentStepChanged, [&]() {
        out << "  -> " << mgr->currentStep() << " (" << mgr->checkPercent() << "%)\n";
        out.flush();
    });

    QObject::connect(mgr, &qs::updatemanager::UpdateManager::checkPercentChanged, [&]() {
        // Progress update
    });

    QObject::connect(mgr, &qs::updatemanager::UpdateManager::updatesAvailable, [&](int count, int secCount) {
        out << "\n[Result] Check finished: " << count << " updates available (" << secCount << " security).\n";
        out << "Total download size: " << mgr->formattedTotalSize() << "\n";
        out << "Recommended method: " << mgr->recommendedMethod() << "\n\n";

        auto *model = mgr->model();
        for (int i = 0; i < model->count(); ++i) {
            auto m = model->get(i);
            out << QStringLiteral("  * %1: %2 -> %3 | %4 | %5 | Reboot: %6\n")
                       .arg(m[QStringLiteral("name")].toString())
                       .arg(m[QStringLiteral("oldEvr")].toString())
                       .arg(m[QStringLiteral("newEvr")].toString())
                       .arg(m[QStringLiteral("category")].toString())
                       .arg(m[QStringLiteral("formattedSize")].toString())
                       .arg(m[QStringLiteral("requiresReboot")].toBool() ? "YES" : "No");
        }
        out.flush();
        QTimer::singleShot(100, &app, &QCoreApplication::quit);
    });

    QObject::connect(mgr, &qs::updatemanager::UpdateManager::operationFailed, [&](const QString &err) {
        out << "\n[Error] Operation failed: " << err << "\n";
        out.flush();
        app.exit(1);
    });

    mgr->checkForUpdates(refresh);

    return app.exec();
}
