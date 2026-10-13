#include "KWinManager.hpp"

#include <QCoreApplication>
#include <QTimer>
#include <iostream>

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    qs::plugins::kwin::KWinManager manager;

    std::cout << "KWinManager initialized, waiting for window update..." << std::endl;

    QObject::connect(&manager, &qs::plugins::kwin::KWinManager::windowsChanged, [&manager, &app]() {
        const QVariantList list = manager.windows();
        std::cout << "--- Window list updated (" << list.size() << " windows) ---" << std::endl;
        for (int i = 0; i < list.size(); ++i) {
            const QVariantMap w = list.at(i).toMap();
            std::cout << "[" << i << "] "
                      << "id=" << w.value(QStringLiteral("id")).toString().toStdString() << " "
                      << "appId=" << w.value(QStringLiteral("appId")).toString().toStdString() << " "
                      << "active=" << (w.value(QStringLiteral("active")).toBool() ? "true" : "false") << " "
                      << "minimized=" << (w.value(QStringLiteral("minimized")).toBool() ? "true" : "false") << " "
                      << "title=" << w.value(QStringLiteral("title")).toString().toStdString()
                      << std::endl;
        }
        app.quit();
    });

    QTimer::singleShot(3000, [&app]() {
        std::cerr << "Timed out waiting for KWin window list" << std::endl;
        app.quit();
    });

    return app.exec();
}
