#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QList>
#include <QString>
#include <QVariantMap>

namespace qs::plugins::kwin {

struct WindowRecord {
    QString id;
    QString appId;
    QString title;
    QString icon;
    bool active{false};
    bool minimized{false};
    bool maximized{false};
    bool fullscreen{false};

    [[nodiscard]] bool operator==(const WindowRecord &other) const {
        return id == other.id &&
               appId == other.appId &&
               title == other.title &&
               icon == other.icon &&
               active == other.active &&
               minimized == other.minimized &&
               maximized == other.maximized &&
               fullscreen == other.fullscreen;
    }
};

class WindowModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum WindowRoles {
        IdRole = Qt::UserRole + 1,
        AppIdRole,
        TitleRole,
        IconRole,
        ActiveRole,
        MinimizedRole,
        MaximizedRole,
        FullscreenRole,
        WindowDataRole
    };
    Q_ENUM(WindowRoles)

    explicit WindowModel(QObject *parent = nullptr);
    ~WindowModel() override = default;

    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] const QList<WindowRecord> &windows() const { return m_windows; }
    [[nodiscard]] QVariantList toVariantList() const;

    void updateRecords(const QList<WindowRecord> &newRecords);

private:
    QList<WindowRecord> m_windows;
};

} // namespace qs::plugins::kwin
