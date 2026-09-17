#include "NotificationMonitor.hpp"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <csignal>
#include <iostream>

using namespace qs::plugins::notifications;

static void handleSigint(int) {
    std::cout << "\nTerminating probe...\n";
    if (qApp) {
        qApp->quit();
    }
}

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    std::signal(SIGINT, handleSigint);
    std::signal(SIGTERM, handleSigint);

    std::cout << "=======================================================\n";
    std::cout << "      NATIVE C++ NOTIFICATION PROBE (D-Bus Monitor)    \n";
    std::cout << "=======================================================\n";
    std::cout << "Monitoring org.freedesktop.Notifications in real time...\n";
    std::cout << "Press Ctrl+C to exit.\n\n";

    NotificationMonitor monitor;

    QObject::connect(&monitor, &NotificationMonitor::notificationReceived, [](const NotificationItem &item) {
        std::cout << "[" << item.timestamp.toString("hh:mm:ss.zzz").toStdString() << "] NOTIFY #"
                  << item.id << "\n"
                  << "  App:     " << item.appName.toStdString() << " (" << item.desktopEntry.toStdString() << ")\n"
                  << "  Icon:    " << item.appIcon.toStdString() << "\n"
                  << "  Summary: " << item.summary.toStdString() << "\n"
                  << "  Body:    " << item.body.toStdString() << "\n"
                  << "  Urgency: " << item.urgency << " | Timeout: " << item.timeout << "ms\n";
        if (!item.actions.isEmpty()) {
            std::cout << "  Actions: ";
            for (const auto &act : item.actions) {
                std::cout << "[" << act.identifier.toStdString() << ": " << act.text.toStdString() << "] ";
            }
            std::cout << "\n";
        }
        std::cout << "-------------------------------------------------------\n" << std::flush;
    });

    QObject::connect(&monitor, &NotificationMonitor::notificationClosed, [](uint32_t id, uint32_t reason) {
        std::cout << "--> CLOSED #" << id << " (reason: " << reason << ")\n" << std::flush;
    });

    QObject::connect(&monitor, &NotificationMonitor::actionInvoked, [](uint32_t id, const QString &actionKey) {
        std::cout << "--> ACTION INVOKED #" << id << " key: " << actionKey.toStdString() << "\n" << std::flush;
    });

    QObject::connect(&monitor, &NotificationMonitor::monitorError, [](const QString &err) {
        std::cerr << "Monitor error: " << err.toStdString() << "\n" << std::flush;
    });

    monitor.start();

    int ret = app.exec();
    monitor.stop();
    return ret;
}
