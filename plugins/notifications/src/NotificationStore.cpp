#include "NotificationStore.hpp"

#include "NotificationModel.hpp"

#include <QDateTime>
#include <limits>

namespace qs::plugins::notifications {

namespace {
constexpr qint64 kDayMs = 24LL * 3600 * 1000;
}

NotificationStore::NotificationStore(QObject *parent)
    : QObject(parent)
    , m_historyModel(new NotificationModel(this))
    , m_toastModel(new NotificationModel(this))
    , m_sweepTimer(new QTimer(this))
    , m_timeTimer(new QTimer(this)) {
    m_sweepTimer->setInterval(1000);
    connect(m_sweepTimer, &QTimer::timeout, this, &NotificationStore::onSweepTick);
    m_timeTimer->setInterval(10000);
    connect(m_timeTimer, &QTimer::timeout, this, &NotificationStore::onTimeTick);
    m_timeTimer->start();
}

int NotificationStore::normalizeUrgency(int u) noexcept {
    return (u == 0 || u == 1 || u == 2) ? u : 1;
}

qint64 NotificationStore::defaultTimeoutMs(int urgency) noexcept {
    if (urgency == 2) {
        return 10000;
    }
    if (urgency == 0) {
        return 3500;
    }
    return 5000;
}

qint64 NotificationStore::timeoutForCategory(const QString &category, int urgency) {
    const QString c = category.toLower();
    if (c.startsWith(QStringLiteral("call")) || c == QStringLiteral("incoming-call")) {
        return 15000;
    }
    if (c.startsWith(QStringLiteral("im")) || c == QStringLiteral("email") || c == QStringLiteral("message")) {
        return urgency == 2 ? 10000 : 7000;
    }
    if (c == QStringLiteral("transfer") || c == QStringLiteral("progress") || c.startsWith(QStringLiteral("presence"))) {
        return 3500;
    }
    return defaultTimeoutMs(urgency);
}

QString NotificationStore::timeAgo(const QDateTime &when) {
    return NotificationModel::timeAgo(when);
}

void NotificationStore::setDnd(bool dnd) {
    if (m_dnd == dnd) {
        return;
    }
    m_dnd = dnd;
    if (m_dnd) {
        // DND on: drop non-critical toasts (critical still shows).
        QList<NotificationEntry> keep;
        keep.reserve(m_toasts.size());
        for (const auto &t : m_toasts) {
            if (t.urgency == 2) {
                keep.append(t);
            }
        }
        m_toasts = std::move(keep);
        syncModels();
    }
    emit dndChanged();
}

void NotificationStore::setMaxNotifications(int max) {
    if (m_max == max) {
        return;
    }
    m_max = qMax(1, max);
    evictOverflow();
    emit maxNotificationsChanged();
}

QStringList NotificationStore::expandedGroups() const {
    return m_expanded.values();
}

void NotificationStore::setExpandedGroups(const QStringList &groups) {
    m_expanded = QSet<QString>(groups.begin(), groups.end());
    rebuildGrouped();
    emit expandedGroupsChanged();
}

NotificationEntry NotificationStore::entryFromMap(const QVariantMap &snap, int id) {
    NotificationEntry e;
    e.id = id;
    e.appName = snap.value(QStringLiteral("appName"), QStringLiteral("Application")).toString();
    if (e.appName.isEmpty()) {
        e.appName = QStringLiteral("Application");
    }
    e.appIcon = snap.value(QStringLiteral("appIcon")).toString();
    e.summary = snap.value(QStringLiteral("summary"), QStringLiteral("Notification")).toString();
    if (e.summary.isEmpty()) {
        e.summary = QStringLiteral("Notification");
    }
    e.body = snap.value(QStringLiteral("body")).toString();
    e.image = snap.value(QStringLiteral("image")).toString();
    e.desktopEntry = snap.value(QStringLiteral("desktopEntry")).toString();
    e.urgency = normalizeUrgency(snap.value(QStringLiteral("urgency"), 1).toInt());
    e.actions = snap.value(QStringLiteral("actions")).toList();
    e.resident = snap.value(QStringLiteral("resident"), false).toBool();
    e.transient = snap.value(QStringLiteral("transient"), false).toBool();
    e.hasInlineReply = snap.value(QStringLiteral("hasInlineReply"), false).toBool();
    e.replyPlaceholder = snap.value(QStringLiteral("inlineReplyPlaceholder")).toString();
    e.hasActionIcons = snap.value(QStringLiteral("hasActionIcons"), false).toBool();
    e.category = snap.value(QStringLiteral("category")).toString();
    e.soundName = snap.value(QStringLiteral("soundName")).toString();
    e.soundFile = snap.value(QStringLiteral("soundFile")).toString();
    e.suppressSound = snap.value(QStringLiteral("suppressSound"), false).toBool();
    return e;
}

QVariantMap NotificationStore::entryToMap(const NotificationEntry &e) {
    return {
        {QStringLiteral("id"), e.id},
        {QStringLiteral("notifId"), QString::number(e.id)},
        {QStringLiteral("appName"), e.appName},
        {QStringLiteral("appIcon"), e.appIcon},
        {QStringLiteral("summary"), e.summary},
        {QStringLiteral("body"), e.body},
        {QStringLiteral("image"), e.image},
        {QStringLiteral("desktopEntry"), e.desktopEntry},
        {QStringLiteral("urgency"), e.urgency},
        {QStringLiteral("timeout"), e.isPersistent() ? 0 : static_cast<int>(e.timeoutMs)},
        {QStringLiteral("timestamp"), e.receivedAt},
        {QStringLiteral("timeAgo"), timeAgo(e.receivedAt)},
        {QStringLiteral("read"), e.read},
        {QStringLiteral("actions"), e.actions},
        {QStringLiteral("hasInlineReply"), e.hasInlineReply},
        {QStringLiteral("inlineReplyPlaceholder"), e.replyPlaceholder.isEmpty() ? QStringLiteral("Reply…") : e.replyPlaceholder},
        {QStringLiteral("hasActionIcons"), e.hasActionIcons},
        {QStringLiteral("category"), e.category},
        {QStringLiteral("soundName"), e.soundName},
        {QStringLiteral("soundFile"), e.soundFile},
        {QStringLiteral("suppressSound"), e.suppressSound},
        {QStringLiteral("isBridge"), false},
    };
}

void NotificationStore::ingestSnapshot(const QVariantMap &snap, int id, const QVariant &expireTimeoutSec, bool carried) {
    NotificationEntry base = entryFromMap(snap, id);
    const int u = base.urgency;

    qint64 timeoutMs = timeoutForCategory(base.category, u);
    bool hasExpire = false;
    double expSec = 0.0;
    if (expireTimeoutSec.isValid() && !expireTimeoutSec.isNull()) {
        bool ok = false;
        expSec = expireTimeoutSec.toDouble(&ok);
        hasExpire = ok;
    }
    if (hasExpire) {
        if (qFuzzyIsNull(expSec)) {
            timeoutMs = kPersistTimeout;
        } else if (expSec > 0) {
            timeoutMs = static_cast<qint64>(expSec * 1000.0);
        }
    }

    const QDateTime now = QDateTime::currentDateTime();
    const qint64 expiresAt = (timeoutMs == kPersistTimeout) ? kPersistTimeout : now.toMSecsSinceEpoch() + timeoutMs;

    const int hi = findHistory(id);
    const int ti = findToast(id);
    if (hi != -1 || ti != -1) {
        // replaces_id / same-id update: replace in place, refresh recency.
        if (hi != -1) {
            NotificationEntry &h = m_history[hi];
            const bool oldRead = h.read;
            const bool oldManual = h.manual;
            h = base;
            h.receivedAt = now;
            h.timeoutMs = timeoutMs;
            h.expiresAt = expiresAt;
            h.manual = oldManual;
            h.read = carried ? oldRead : false;
            NotificationEntry moved = h;
            m_history.removeAt(hi);
            m_history.append(moved);
        }
        if (ti != -1) {
            // Refresh toast copy (or the shared entry if history missed).
            int idx = -1;
            for (int i = 0; i < m_toasts.size(); ++i) {
                if (m_toasts[i].id == id) {
                    idx = i;
                    break;
                }
            }
            if (idx != -1) {
                if (hi != -1) {
                    m_toasts[idx] = m_history.last();
                } else {
                    NotificationEntry &t = m_toasts[idx];
                    t = base;
                    t.receivedAt = now;
                    t.timeoutMs = timeoutMs;
                    t.expiresAt = expiresAt;
                    if (!carried) {
                        t.read = false;
                    }
                }
                NotificationEntry moved = m_toasts[idx];
                m_toasts.removeAt(idx);
                m_toasts.append(moved);
                while (m_toasts.size() > kMaxToasts) {
                    m_toasts.removeFirst();
                }
            }
        } else if (!carried && (!m_dnd || u == 2) && !base.transient) {
            NotificationEntry w = (hi != -1) ? m_history.last() : base;
            if (hi == -1) {
                w.receivedAt = now;
                w.timeoutMs = timeoutMs;
                w.expiresAt = expiresAt;
                w.read = false;
            }
            m_toasts.append(w);
            while (m_toasts.size() > kMaxToasts) {
                m_toasts.removeFirst();
            }
        }
        if (!carried) {
            recountUnread();
        }
        syncModels();
        return;
    }

    NotificationEntry w = base;
    w.receivedAt = now;
    w.read = carried;
    w.timeoutMs = timeoutMs;
    w.expiresAt = expiresAt;

    if (w.transient) {
        if (!m_dnd || u == 2) {
            m_toasts.append(w);
            while (m_toasts.size() > kMaxToasts) {
                m_toasts.removeFirst();
            }
        }
        syncModels();
        return;
    }

    m_history.append(w);
    evictOverflow();
    if (!carried) {
        if (!m_dnd || u == 2) {
            m_toasts.append(w);
            while (m_toasts.size() > kMaxToasts) {
                m_toasts.removeFirst();
            }
        }
        m_unread++;
        emit unreadCountChanged();
    }
    syncModels();
    emit totalCountChanged();
}

void NotificationStore::handleClosed(int id, int reason) {
    if (reason == kCloseExpired) {
        const int before = m_toasts.size();
        for (int i = m_toasts.size() - 1; i >= 0; --i) {
            if (m_toasts[i].id == id) {
                m_toasts.removeAt(i);
            }
        }
        if (m_toasts.size() != before) {
            syncModels();
        }
        return;
    }
    bool hChanged = false;
    bool tChanged = false;
    for (int i = m_history.size() - 1; i >= 0; --i) {
        if (m_history[i].id == id) {
            m_history.removeAt(i);
            hChanged = true;
        }
    }
    for (int i = m_toasts.size() - 1; i >= 0; --i) {
        if (m_toasts[i].id == id) {
            m_toasts.removeAt(i);
            tChanged = true;
        }
    }
    if (hChanged || tChanged) {
        recountUnread();
        syncModels();
        if (hChanged) {
            emit totalCountChanged();
        }
    }
}

void NotificationStore::pruneToIds(const QVariantList &liveIds) {
    QSet<int> seen;
    for (const auto &v : liveIds) {
        seen.insert(v.toInt());
    }
    const int before = m_toasts.size();
    QList<NotificationEntry> keep;
    keep.reserve(m_toasts.size());
    for (const auto &t : m_toasts) {
        if (t.manual || seen.contains(t.id)) {
            keep.append(t);
        }
    }
    if (keep.size() != before) {
        m_toasts = std::move(keep);
        syncModels();
    }
}

void NotificationStore::holdToast(int id, bool held) {
    if (held) {
        m_held.insert(id);
    } else {
        m_held.remove(id);
    }
}

void NotificationStore::dismissToast(int id) {
    const int ti = findToast(id);
    if (ti != -1 && m_toasts[ti].transient) {
        emit expireRequested(id);
    }
    bool changed = false;
    for (int i = m_toasts.size() - 1; i >= 0; --i) {
        if (m_toasts[i].id == id) {
            m_toasts.removeAt(i);
            changed = true;
        }
    }
    if (changed) {
        m_held.remove(id);
        syncModels();
    }
}

void NotificationStore::dismissNotification(int id) {
    emit dismissRequested(id);
    bool hChanged = false;
    for (int i = m_history.size() - 1; i >= 0; --i) {
        if (m_history[i].id == id) {
            m_history.removeAt(i);
            hChanged = true;
        }
    }
    for (int i = m_toasts.size() - 1; i >= 0; --i) {
        if (m_toasts[i].id == id) {
            m_toasts.removeAt(i);
        }
    }
    m_held.remove(id);
    recountUnread();
    syncModels();
    if (hChanged) {
        emit totalCountChanged();
    }
}

void NotificationStore::clearApp(const QString &appName) {
    QSet<int> ids;
    for (const auto &h : m_history) {
        if (appNameOf(h) == appName) {
            ids.insert(h.id);
        }
    }
    for (int id : ids) {
        emit dismissRequested(id);
    }
    for (int i = m_history.size() - 1; i >= 0; --i) {
        if (appNameOf(m_history[i]) == appName) {
            m_history.removeAt(i);
        }
    }
    for (int i = m_toasts.size() - 1; i >= 0; --i) {
        if (appNameOf(m_toasts[i]) == appName) {
            m_held.remove(m_toasts[i].id);
            m_toasts.removeAt(i);
        }
    }
    recountUnread();
    syncModels();
    emit totalCountChanged();
}

void NotificationStore::clearAll() {
    for (const auto &h : m_history) {
        emit dismissRequested(h.id);
    }
    m_history.clear();
    m_toasts.clear();
    m_held.clear();
    m_unread = 0;
    emit unreadCountChanged();
    syncModels();
    emit totalCountChanged();
}

void NotificationStore::markAllRead() {
    bool changed = false;
    for (auto &h : m_history) {
        if (!h.read) {
            h.read = true;
            changed = true;
        }
    }
    if (changed || m_unread != 0) {
        m_unread = 0;
        emit unreadCountChanged();
        syncModels();
    }
}

void NotificationStore::toggleDnd() {
    setDnd(!m_dnd);
}

void NotificationStore::toggleGroupExpanded(const QString &appName) {
    if (m_expanded.contains(appName)) {
        m_expanded.remove(appName);
    } else {
        m_expanded.insert(appName);
    }
    rebuildGrouped();
    emit expandedGroupsChanged();
}

bool NotificationStore::isGroupExpanded(const QString &appName) const {
    return m_expanded.contains(appName);
}

void NotificationStore::invokeAction(int id, const QString &identifier) {
    int idx = findHistory(id);
    if (idx == -1) {
        idx = findToast(id);
        if (idx == -1) {
            return;
        }
    }
    const NotificationEntry &e = (findHistory(id) != -1) ? m_history[findHistory(id)] : m_toasts[idx];
    bool matched = false;
    for (const auto &a : e.actions) {
        if (a.toMap().value(QStringLiteral("identifier")).toString() == identifier) {
            matched = true;
            break;
        }
    }
    if (matched) {
        emit invokeRequested(id, identifier);
    } else {
        emit dismissRequested(id);
    }
    if (!e.resident) {
        for (int i = m_history.size() - 1; i >= 0; --i) {
            if (m_history[i].id == id) {
                m_history.removeAt(i);
            }
        }
        for (int i = m_toasts.size() - 1; i >= 0; --i) {
            if (m_toasts[i].id == id) {
                m_toasts.removeAt(i);
            }
        }
        m_held.remove(id);
        recountUnread();
        syncModels();
        emit totalCountChanged();
    }
}

bool NotificationStore::sendInlineReply(int id, const QString &text) {
    if (text.trimmed().isEmpty()) {
        return false;
    }
    int idx = findHistory(id);
    if (idx == -1) {
        idx = findToast(id);
        if (idx == -1) {
            return false;
        }
    }
    const NotificationEntry &e = (findHistory(id) != -1) ? m_history[findHistory(id)] : m_toasts[idx];
    if (!e.hasInlineReply) {
        return false;
    }
    emit replyRequested(id, text.trimmed());
    for (int i = m_toasts.size() - 1; i >= 0; --i) {
        if (m_toasts[i].id == id) {
            m_toasts.removeAt(i);
        }
    }
    m_held.remove(id);
    for (auto &h : m_history) {
        if (h.id == id) {
            h.read = true;
        }
    }
    recountUnread();
    syncModels();
    return true;
}

void NotificationStore::addTestNotification(const QString &summary, const QString &body, const QString &appName, int urgency) {
    static int s_nextManualId = 9000;
    const int u = normalizeUrgency(urgency);
    const qint64 timeoutMs = defaultTimeoutMs(u);
    const QDateTime now = QDateTime::currentDateTime();
    NotificationEntry w;
    w.id = s_nextManualId++;
    if (s_nextManualId > 99999) {
        s_nextManualId = 9000;
    }
    w.appName = appName.isEmpty() ? QStringLiteral("Application") : appName;
    w.summary = summary.isEmpty() ? QStringLiteral("Notification") : summary;
    w.body = body;
    w.urgency = u;
    w.receivedAt = now;
    w.read = false;
    w.timeoutMs = timeoutMs;
    w.expiresAt = now.toMSecsSinceEpoch() + timeoutMs;
    w.manual = true;
    m_history.append(w);
    evictOverflow();
    if (!m_dnd || u == 2) {
        m_toasts.append(w);
        while (m_toasts.size() > kMaxToasts) {
            m_toasts.removeFirst();
        }
    }
    m_unread++;
    emit unreadCountChanged();
    syncModels();
    emit totalCountChanged();
}

void NotificationStore::onSweepTick() {
    if (m_toasts.isEmpty()) {
        return;
    }
    const qint64 now = QDateTime::currentDateTime().toMSecsSinceEpoch();
    bool changed = false;
    QList<NotificationEntry> keep;
    keep.reserve(m_toasts.size());
    for (const auto &t : m_toasts) {
        if (t.expiresAt != kPersistTimeout && now >= t.expiresAt && !m_held.contains(t.id)) {
            emit expireRequested(t.id);
            if (t.manual) {
                for (int i = m_history.size() - 1; i >= 0; --i) {
                    if (m_history[i].id == t.id) {
                        m_history.removeAt(i);
                    }
                }
            }
            m_held.remove(t.id);
            changed = true;
        } else {
            keep.append(t);
        }
    }
    if (changed) {
        m_toasts = std::move(keep);
        recountUnread();
        syncModels();
        emit totalCountChanged();
    }
}

void NotificationStore::onTimeTick() {
    m_historyModel->refreshTimeAgo();
    m_toastModel->refreshTimeAgo();
    rebuildGrouped();
}

void NotificationStore::syncModels() {
    m_historyModel->setEntries(m_history);
    m_toastModel->setEntries(m_toasts);
    m_notifications.clear();
    m_notifications.reserve(m_history.size());
    for (const auto &h : m_history) {
        m_notifications.append(entryToMap(h));
    }
    m_toastList.clear();
    m_toastList.reserve(m_toasts.size());
    for (const auto &t : m_toasts) {
        m_toastList.append(entryToMap(t));
    }
    emit listsChanged();
    rebuildGrouped();
    const bool anyTimed = std::any_of(m_toasts.cbegin(), m_toasts.cend(), [](const NotificationEntry &t) {
        return t.expiresAt != kPersistTimeout;
    });
    if (anyTimed && !m_sweepTimer->isActive()) {
        m_sweepTimer->start();
    } else if (!anyTimed && m_sweepTimer->isActive()) {
        m_sweepTimer->stop();
    }
}

void NotificationStore::rebuildGrouped() {
    QVariantList groups;
    QStringList order;
    QVariantMap byKey;
    for (const auto &h : m_history) {
        const QVariantMap m = entryToMap(h);
        QString key = m.value(QStringLiteral("appName")).toString().trimmed();
        if (key.isEmpty()) {
            key = QStringLiteral("Application");
        }
        if (!byKey.contains(key)) {
            order.append(key);
            byKey[key] = QVariantMap{
                {QStringLiteral("appName"), key},
                {QStringLiteral("appIcon"), m.value(QStringLiteral("appIcon"))},
                {QStringLiteral("desktopEntry"), m.value(QStringLiteral("desktopEntry"))},
                {QStringLiteral("notifications"), QVariantList{}},
                {QStringLiteral("totalCount"), 0},
                {QStringLiteral("expanded"), m_expanded.contains(key)},
            };
        }
        QVariantMap g = byKey[key].toMap();
        if (g.value(QStringLiteral("appIcon")).toString().isEmpty() && !m.value(QStringLiteral("appIcon")).toString().isEmpty()) {
            g[QStringLiteral("appIcon")] = m.value(QStringLiteral("appIcon"));
        }
        if (g.value(QStringLiteral("desktopEntry")).toString().isEmpty() && !m.value(QStringLiteral("desktopEntry")).toString().isEmpty()) {
            g[QStringLiteral("desktopEntry")] = m.value(QStringLiteral("desktopEntry"));
        }
        QVariantList notifs = g.value(QStringLiteral("notifications")).toList();
        notifs.append(m);
        g[QStringLiteral("notifications")] = notifs;
        g[QStringLiteral("totalCount")] = notifs.size();
        g[QStringLiteral("expanded")] = m_expanded.contains(key);
        byKey[key] = g;
    }
    for (const QString &k : order) {
        groups.append(byKey[k]);
    }
    if (groups != m_grouped) {
        m_grouped = std::move(groups);
        emit groupedListChanged();
    }
}

void NotificationStore::recountUnread() {
    int u = 0;
    for (const auto &h : m_history) {
        if (!h.read) {
            ++u;
        }
    }
    if (u != m_unread) {
        m_unread = u;
        emit unreadCountChanged();
    }
}

void NotificationStore::evictOverflow() {
    bool evicted = false;
    while (m_history.size() > m_max && !m_history.isEmpty()) {
        const NotificationEntry oldest = m_history.takeFirst();
        for (int i = m_toasts.size() - 1; i >= 0; --i) {
            if (m_toasts[i].id == oldest.id) {
                m_toasts.removeAt(i);
            }
        }
        m_held.remove(oldest.id);
        emit dismissRequested(oldest.id);
        evicted = true;
    }
    if (evicted) {
        recountUnread();
        emit totalCountChanged();
    }
}

int NotificationStore::findHistory(int id) const {
    for (int i = 0; i < m_history.size(); ++i) {
        if (m_history[i].id == id) {
            return i;
        }
    }
    return -1;
}

int NotificationStore::findToast(int id) const {
    for (int i = 0; i < m_toasts.size(); ++i) {
        if (m_toasts[i].id == id) {
            return i;
        }
    }
    return -1;
}

QString NotificationStore::appNameOf(const NotificationEntry &e) {
    return e.appName.isEmpty() ? QStringLiteral("Application") : e.appName;
}

} // namespace qs::plugins::notifications
