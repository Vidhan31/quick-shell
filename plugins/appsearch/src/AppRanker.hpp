#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

class AppRanker : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit AppRanker(QObject *parent = nullptr);
    ~AppRanker() override = default;

    Q_INVOKABLE QVariantList rank(const QVariantList &apps, const QString &query, int maxResults = 50);
};

} // namespace qs::plugins
