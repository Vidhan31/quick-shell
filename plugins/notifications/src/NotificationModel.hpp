#pragma once

#include "NotificationTypes.hpp"

#include <QAbstractListModel>
#include <QList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins::notifications {

class NotificationModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(NotificationModel)

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum NotificationRoles {
        IdRole = Qt::UserRole + 1,
        NotifIdRole,
        AppNameRole,
        AppIconRole,
        SummaryRole,
        BodyRole,
        ImageRole,
        DesktopEntryRole,
        UrgencyRole,
        TimeoutRole,
        TimestampRole,
        TimeAgoRole,
        ReadRole,
        ActionsRole,
        ItemDataRole
    };
    Q_ENUM(NotificationRoles)

    explicit NotificationModel(QObject *parent = nullptr);
    ~NotificationModel() override = default;

    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    // Direct C++ mutations
    bool addOrUpdate(const NotificationItem &item, int maxItems = 100);
    bool removeById(uint32_t id);
    void removeByAppName(const QString &appName);
    void clear();
    void markAllRead();
    void updateRelativeTimes();

    [[nodiscard]] const QList<NotificationItem>& items() const noexcept { return m_items; }
    [[nodiscard]] int findIndexById(uint32_t id) const;
    [[nodiscard]] NotificationItem getItem(int index) const;

    // QML-accessible helpers
    Q_INVOKABLE [[nodiscard]] QVariantMap get(int index) const;
    Q_INVOKABLE [[nodiscard]] QVariantList toVariantList() const;
    Q_INVOKABLE [[nodiscard]] int unreadCount() const;

signals:
    void countChanged();
    void itemAdded(uint32_t id);
    void itemRemoved(uint32_t id);

private:
    QList<NotificationItem> m_items;
};

} // namespace qs::plugins::notifications
