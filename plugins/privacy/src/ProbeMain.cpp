#include "PrivacyProbe.hpp"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    const auto state = qs::plugins::PrivacyProbe::probe();
    const QJsonDocument doc(QJsonObject::fromVariantMap(state.toMap()));
    std::cout << doc.toJson(QJsonDocument::Compact).toStdString() << std::endl;
    return 0;
}
