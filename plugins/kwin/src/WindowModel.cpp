#include "WindowModel.hpp"

namespace qs::plugins::kwin {

WindowModel::WindowModel(QObject *parent)
    : QAbstractListModel(parent) {
}

int WindowModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return static_cast<int>(m_windows.size());
}

QVariant WindowModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_windows.size()) {
        return {};
    }

    const WindowRecord &win = m_windows.at(index.row());
    switch (role) {
    case IdRole:
        return win.id;
    case AppIdRole:
        return win.appId;
    case TitleRole:
        return win.title;
    case IconRole:
        return win.icon;
    case ActiveRole:
        return win.active;
    case MinimizedRole:
        return win.minimized;
    case MaximizedRole:
        return win.maximized;
    case FullscreenRole:
        return win.fullscreen;
    case WindowDataRole: {
        QVariantMap map;
        map.insert(QStringLiteral("id"), win.id);
        map.insert(QStringLiteral("appId"), win.appId);
        map.insert(QStringLiteral("title"), win.title);
        map.insert(QStringLiteral("icon"), win.icon);
        map.insert(QStringLiteral("active"), win.active);
        map.insert(QStringLiteral("minimized"), win.minimized);
        map.insert(QStringLiteral("maximized"), win.maximized);
        map.insert(QStringLiteral("fullscreen"), win.fullscreen);
        return map;
    }
    case Qt::DisplayRole:
        return win.title;
    default:
        return {};
    }
}

QHash<int, QByteArray> WindowModel::roleNames() const {
    return {
        {IdRole, "id"},
        {AppIdRole, "appId"},
        {TitleRole, "title"},
        {IconRole, "icon"},
        {ActiveRole, "active"},
        {MinimizedRole, "minimized"},
        {MaximizedRole, "maximized"},
        {FullscreenRole, "fullscreen"},
        {WindowDataRole, "modelData"}
    };
}

QVariantList WindowModel::toVariantList() const {
    QVariantList list;
    list.reserve(m_windows.size());
    for (const WindowRecord &win : m_windows) {
        QVariantMap map;
        map.insert(QStringLiteral("id"), win.id);
        map.insert(QStringLiteral("appId"), win.appId);
        map.insert(QStringLiteral("title"), win.title);
        map.insert(QStringLiteral("icon"), win.icon);
        map.insert(QStringLiteral("active"), win.active);
        map.insert(QStringLiteral("minimized"), win.minimized);
        map.insert(QStringLiteral("maximized"), win.maximized);
        map.insert(QStringLiteral("fullscreen"), win.fullscreen);
        list.append(map);
    }
    return list;
}

void WindowModel::updateRecords(const QList<WindowRecord> &newRecords) {
    if (m_windows.size() == newRecords.size()) {
        bool sameIds = true;
        for (int i = 0; i < m_windows.size(); ++i) {
            if (m_windows.at(i).id != newRecords.at(i).id) {
                sameIds = false;
                break;
            }
        }

        if (sameIds) {
            for (int i = 0; i < m_windows.size(); ++i) {
                const WindowRecord &oldWin = m_windows.at(i);
                const WindowRecord &newWin = newRecords.at(i);
                if (oldWin == newWin) {
                    continue;
                }

                QList<int> changedRoles;
                if (oldWin.active != newWin.active) changedRoles.append(ActiveRole);
                if (oldWin.minimized != newWin.minimized) changedRoles.append(MinimizedRole);
                if (oldWin.maximized != newWin.maximized) changedRoles.append(MaximizedRole);
                if (oldWin.fullscreen != newWin.fullscreen) changedRoles.append(FullscreenRole);
                if (oldWin.title != newWin.title) changedRoles.append(TitleRole);
                if (oldWin.icon != newWin.icon) changedRoles.append(IconRole);
                if (oldWin.appId != newWin.appId) changedRoles.append(AppIdRole);
                changedRoles.append(WindowDataRole);

                m_windows[i] = newWin;
                const QModelIndex idx = index(i, 0);
                Q_EMIT dataChanged(idx, idx, changedRoles);
            }
            return;
        }
    }

    beginResetModel();
    m_windows = newRecords;
    endResetModel();
}

} // namespace qs::plugins::kwin
