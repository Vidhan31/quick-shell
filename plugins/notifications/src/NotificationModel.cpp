#include "NotificationModel.hpp"

namespace qs::plugins::notifications {

NotificationModel::NotificationModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int NotificationModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return static_cast<int>(m_items.size());
}

QVariant NotificationModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_items.size())) {
        return {};
    }

    const auto &item = m_items.at(index.row());

    switch (role) {
    case IdRole:
        return item.id;
    case NotifIdRole:
        return item.notifId.isEmpty() ? QString::number(item.id) : item.notifId;
    case AppNameRole:
        return item.appName;
    case AppIconRole:
        return item.appIcon;
    case SummaryRole:
        return item.summary;
    case BodyRole:
        return item.body;
    case ImageRole:
        return item.image;
    case DesktopEntryRole:
        return item.desktopEntry;
    case UrgencyRole:
        return item.urgency;
    case TimeoutRole:
        return item.timeout;
    case TimestampRole:
        return item.timestamp;
    case TimeAgoRole:
        return item.timeAgo();
    case ReadRole:
        return item.read;
    case ActionsRole:
        return item.actionsVariantList();
    case ItemDataRole:
    case Qt::DisplayRole:
        return item.toMap();
    default:
        return {};
    }
}

QHash<int, QByteArray> NotificationModel::roleNames() const {
    static const QHash<int, QByteArray> roles{
        {IdRole, "id"},
        {NotifIdRole, "notifId"},
        {AppNameRole, "appName"},
        {AppIconRole, "appIcon"},
        {SummaryRole, "summary"},
        {BodyRole, "body"},
        {ImageRole, "image"},
        {DesktopEntryRole, "desktopEntry"},
        {UrgencyRole, "urgency"},
        {TimeoutRole, "timeout"},
        {TimestampRole, "timestamp"},
        {TimeAgoRole, "timeAgo"},
        {ReadRole, "read"},
        {ActionsRole, "actions"},
        {ItemDataRole, "modelData"}
    };
    return roles;
}

int NotificationModel::findIndexById(uint32_t id) const {
    for (int i = 0; i < static_cast<int>(m_items.size()); ++i) {
        if (m_items.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

NotificationItem NotificationModel::getItem(int index) const {
    if (index >= 0 && index < static_cast<int>(m_items.size())) {
        return m_items.at(index);
    }
    return {};
}

bool NotificationModel::addOrUpdate(const NotificationItem &item, int maxItems) {
    int existingIdx = findIndexById(item.id);

    // Deduplication by summary, body, and timestamp within 1 sec if id differs
    if (existingIdx < 0) {
        for (int i = 0; i < static_cast<int>(m_items.size()); ++i) {
            const auto &n = m_items.at(i);
            if (n.summary == item.summary && n.body == item.body &&
                std::abs(n.timestamp.msecsTo(item.timestamp)) < 1000) {
                existingIdx = i;
                break;
            }
        }
    }

    if (existingIdx >= 0) {
        m_items[existingIdx] = item;
        const auto idx = index(existingIdx, 0);
        emit dataChanged(idx, idx);
        return false;
    }

    beginInsertRows(QModelIndex(), 0, 0);
    m_items.prepend(item);
    endInsertRows();
    emit countChanged();
    emit itemAdded(item.id);

    if (static_cast<int>(m_items.size()) > maxItems) {
        int excess = static_cast<int>(m_items.size()) - maxItems;
        int firstExcess = static_cast<int>(m_items.size()) - excess;
        beginRemoveRows(QModelIndex(), firstExcess, static_cast<int>(m_items.size()) - 1);
        while (static_cast<int>(m_items.size()) > maxItems) {
            m_items.removeLast();
        }
        endRemoveRows();
        emit countChanged();
    }

    return true;
}

bool NotificationModel::removeById(uint32_t id) {
    int idx = findIndexById(id);
    if (idx < 0) return false;

    beginRemoveRows(QModelIndex(), idx, idx);
    m_items.removeAt(idx);
    endRemoveRows();
    emit countChanged();
    emit itemRemoved(id);
    return true;
}

void NotificationModel::removeByAppName(const QString &appName) {
    for (int i = static_cast<int>(m_items.size()) - 1; i >= 0; --i) {
        if (m_items.at(i).appName == appName) {
            beginRemoveRows(QModelIndex(), i, i);
            uint32_t removedId = m_items.at(i).id;
            m_items.removeAt(i);
            endRemoveRows();
            emit countChanged();
            emit itemRemoved(removedId);
        }
    }
}

void NotificationModel::clear() {
    if (m_items.isEmpty()) return;
    beginResetModel();
    m_items.clear();
    endResetModel();
    emit countChanged();
}

void NotificationModel::markAllRead() {
    if (m_items.isEmpty()) return;
    for (auto &item : m_items) {
        item.read = true;
    }
    emit dataChanged(index(0, 0), index(static_cast<int>(m_items.size()) - 1, 0), {ReadRole});
}

void NotificationModel::updateRelativeTimes() {
    if (m_items.isEmpty()) return;
    emit dataChanged(index(0, 0), index(static_cast<int>(m_items.size()) - 1, 0), {TimeAgoRole});
}

QVariantMap NotificationModel::get(int index) const {
    if (index >= 0 && index < static_cast<int>(m_items.size())) {
        return m_items.at(index).toMap();
    }
    return {};
}

QVariantList NotificationModel::toVariantList() const {
    QVariantList list;
    list.reserve(m_items.size());
    for (const auto &item : m_items) {
        list.append(item.toMap());
    }
    return list;
}

int NotificationModel::unreadCount() const {
    int count = 0;
    for (const auto &item : m_items) {
        if (!item.read) ++count;
    }
    return count;
}

} // namespace qs::plugins::notifications
