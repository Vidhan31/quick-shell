#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QString>
#include <QVariantMap>

namespace qs::plugins {

class IconResolver : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantMap appAliases READ appAliases CONSTANT)

public:
    explicit IconResolver(QObject *parent = nullptr);
    ~IconResolver() override = default;

    [[nodiscard]] QVariantMap appAliases() const { return m_appAliases; }

    Q_INVOKABLE QString resolveIcon(const QString &appId, const QString &title = QString());
    Q_INVOKABLE QString resolveStockIcon(const QString &iconName);
    Q_INVOKABLE QString resolveNamedOrPath(const QString &iconNameOrPath);
    Q_INVOKABLE QString fallbackIcon();

private:
    QString doResolve(const QString &appId, const QString &title);
    QString doResolveStockIcon(const QString &iconName) const;
    QString doResolveNamedOrPath(const QString &iconNameOrPath);

    QVariantMap m_appAliases;
};

} // namespace qs::plugins
