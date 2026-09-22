#include "NotificationModel.hpp"

#include <QDate>

namespace qs::plugins::notifications {

NotificationModel::NotificationModel(QObject *parent)
    : QAbstractListModel(parent) {}

int NotificationModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return m_entries.size();
}

QVariant NotificationModel::data(const QModelIndex &index, int role) const {
    const int row = index.row();
    if (row < 0 || row >= m_entries.size()) {
        return {};
    }
    const NotificationEntry &e = m_entries.at(row);
    switch (role) {
    case IdRole: return e.id;
    case AppNameRole: return e.appName;
    case AppIconRole: return e.appIcon;
    case SummaryRole: return e.summary;
    case BodyRole: return e.body;
    case ImageRole: return e.image;
    case DesktopEntryRole: return e.desktopEntry;
    case UrgencyRole: return e.urgency;
    case TimeoutRole: return e.isPersistent() ? 0 : static_cast<int>(e.timeoutMs);
    case TimestampRole: return e.receivedAt;
    case TimeAgoRole: return timeAgo(e.receivedAt);
    case ReadRole: return e.read;
    case ActionsRole: return e.actions;
    case HasInlineReplyRole: return e.hasInlineReply;
    case ReplyPlaceholderRole: return e.replyPlaceholder.isEmpty() ? QStringLiteral("Reply…") : e.replyPlaceholder;
    case HasActionIconsRole: return e.hasActionIcons;
    case CategoryRole: return e.category;
    case SoundNameRole: return e.soundName;
    case SoundFileRole: return e.soundFile;
    case SuppressSoundRole: return e.suppressSound;
    default: return {};
    }
}

QHash<int, QByteArray> NotificationModel::roleNames() const {
    return {
        {IdRole, "notifId"},
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
        {HasInlineReplyRole, "hasInlineReply"},
        {ReplyPlaceholderRole, "inlineReplyPlaceholder"},
        {HasActionIconsRole, "hasActionIcons"},
        {CategoryRole, "category"},
        {SoundNameRole, "soundName"},
        {SoundFileRole, "soundFile"},
        {SuppressSoundRole, "suppressSound"},
    };
}

void NotificationModel::setEntries(QList<NotificationEntry> entries) {
    beginResetModel();
    m_entries = std::move(entries);
    endResetModel();
}

void NotificationModel::refreshTimeAgo() {
    if (m_entries.isEmpty()) {
        return;
    }
    emit dataChanged(index(0, 0), index(m_entries.size() - 1, 0), {TimeAgoRole});
}

QString NotificationModel::timeAgo(const QDateTime &when) {
    if (!when.isValid()) {
        return QStringLiteral("Just now");
    }
    const qint64 ms = qMax<qint64>(0, QDateTime::currentDateTime().toMSecsSinceEpoch() - when.toMSecsSinceEpoch());
    const qint64 secs = ms / 1000;
    const qint64 mins = secs / 60;
    const qint64 hrs = mins / 60;
    const qint64 days = hrs / 24;
    if (secs < 45) {
        return QStringLiteral("Just now");
    }
    if (mins < 60) {
        return mins == 1 ? QStringLiteral("1 min ago") : QStringLiteral("%1 mins ago").arg(mins);
    }
    if (hrs < 24) {
        return hrs == 1 ? QStringLiteral("1 hr ago") : QStringLiteral("%1 hrs ago").arg(hrs);
    }
    if (days < 7) {
        return days == 1 ? QStringLiteral("1 day ago") : QStringLiteral("%1 days ago").arg(days);
    }
    return QLocale().toString(QDateTime::fromMSecsSinceEpoch(when.toMSecsSinceEpoch()).date(), QStringLiteral("MMM d"));
}

} // namespace qs::plugins::notifications
