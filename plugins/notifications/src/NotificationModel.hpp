#pragma once

#include "NotificationEntry.hpp"

#include <QAbstractListModel>
#include <QList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins::notifications {

// Generic read-only list model over NotificationEntry. One instance backs
// history, another backs toasts; the store pushes fresh snapshots.
class NotificationModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("NotificationModel is created by NotificationStore")

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        AppNameRole,
        AppIconRole,
        SummaryRole,
        BodyRole,
        ImageRole,
        DesktopEntryRole,
        UrgencyRole,
        TimeoutRole, // ms, 0 = persist (QML compat with old _wrapMap)
        TimestampRole, // QDateTime
        TimeAgoRole,
        ReadRole,
        ActionsRole, // QVariantList of {identifier, text}
        HasInlineReplyRole,
        ReplyPlaceholderRole,
        HasActionIconsRole,
        CategoryRole,
        SoundNameRole,
        SoundFileRole,
        SuppressSoundRole,
    };
    Q_ENUM(Roles)

    explicit NotificationModel(QObject *parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    void setEntries(QList<NotificationEntry> entries);
    void refreshTimeAgo();
    [[nodiscard]] const QList<NotificationEntry> &entries() const { return m_entries; }

    static QString timeAgo(const QDateTime &when);

private:
    QList<NotificationEntry> m_entries;
};

} // namespace qs::plugins::notifications
