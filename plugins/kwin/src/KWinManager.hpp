#pragma once

#include "WindowModel.hpp"

#include <QtQml/qqmlregistration.h>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

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
    ~KWinManager() override;

    [[nodiscard]] QAbstractItemModel *model() const;
    [[nodiscard]] QVariantList windows() const;
    [[nodiscard]] int count() const;
    [[nodiscard]] bool available() const { return m_available; }

    Q_INVOKABLE void toggleWindow(const QString &windowId);
    Q_INVOKABLE void activateWindow(const QString &windowId);
    Q_INVOKABLE void minimizeWindow(const QString &windowId);
    Q_INVOKABLE void refresh();

    Q_INVOKABLE QVariantList mergeDockItems(const QVariantList &pinnedApps,
                                            const QVariantMap &appAliases = {}) const;

    static void handleDbusUpdatePacked(const QString &packed);

Q_SIGNALS:
    void windowsChanged();
    void availableChanged();

private:
    void dispatchAction(const QString &action, const QString &windowId);

    bool m_available{false};
};

} // namespace qs::plugins::kwin
