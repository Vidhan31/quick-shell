#include "SystemSettings.hpp"

#include <QCoreApplication>
#include <iostream>

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    qs::plugins::SystemSettings settings;
    settings.waitForLoaded();

    std::cout << "Discovered " << settings.count() << " system settings modules:\n\n";

    const auto list = settings.modules();
    for (int i = 0; i < list.size(); ++i) {
        const QVariantMap m = list.at(i).toMap();
        std::cout << "[" << (i + 1) << "] "
                  << m.value(QStringLiteral("name")).toString().toStdString()
                  << " (" << m.value(QStringLiteral("id")).toString().toStdString() << ")\n"
                  << "    Category: " << m.value(QStringLiteral("categoryPath")).toString().toStdString() << "\n"
                  << "    Desc:     " << m.value(QStringLiteral("description")).toString().toStdString() << "\n"
                  << "    Icon:     " << m.value(QStringLiteral("iconName")).toString().toStdString() << "\n";
    }

    std::cout << "\nTesting query detection:\n";
    for (const QString &q : {QStringLiteral("s "), QStringLiteral("s display"), QStringLiteral("settings bluetooth"), QStringLiteral("spotify")}) {
        std::cout << "  \"" << q.toStdString() << "\" -> isSettingsQuery: "
                  << (settings.isSettingsQuery(q) ? "true" : "false")
                  << ", term: \"" << settings.searchTerm(q).toStdString() << "\"\n";
    }

    return 0;
}
