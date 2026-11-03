#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <vector>

namespace qs::plugins {

struct AppEntry {
    QString id;
    QString name;
    QString nameLc;
    QString generic;
    QString genericLc;
    QString category;
    QString categoryLc;
    QString kwLc;
    QVariantMap rawMap;
};

class AppRanker : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit AppRanker(QObject *parent = nullptr);
    ~AppRanker() override = default;

    Q_INVOKABLE void setApps(const QVariantList &apps);
    Q_INVOKABLE QVariantList rank(const QString &query, int maxResults = 50);
    Q_INVOKABLE QVariantList rank(const QVariantList &apps, const QString &query, int maxResults = 50);

private:
    std::vector<AppEntry> m_apps;
};

} // namespace qs::plugins
