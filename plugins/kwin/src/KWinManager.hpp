#pragma once

#include "WindowModel.hpp"

#include <QtQml/qqmlregistration.h>
#include <QObject>
#include <QString>
#include <QVariantList>

namespace qs::plugins::kwin {

class KWinManager : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QAbstractItemModel* model READ model CONSTANT)
    Q_PROPERTY(QVariantList windows READ windows NOTIFY windowsChanged)
    Q_PROPERTY(int count READ count NOTIFY windowsChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit KWinManager(QObject *parent = nullptr);
    ~KWinManager() override = default;

    [[nodiscard]] QAbstractItemModel *model() const;
    [[nodiscard]] QVariantList windows() const;
    [[nodiscard]] int count() const;
    [[nodiscard]] bool available() const;

    Q_INVOKABLE void toggleWindow(const QString &windowId);
    Q_INVOKABLE void activateWindow(const QString &windowId);
    Q_INVOKABLE void minimizeWindow(const QString &windowId);
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void windowsChanged();
    void availableChanged();
};

} // namespace qs::plugins::kwin
