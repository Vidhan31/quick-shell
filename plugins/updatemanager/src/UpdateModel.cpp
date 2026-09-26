#include "UpdateModel.hpp"

#include <QSet>

namespace qs::updatemanager {

UpdateModel::UpdateModel(QObject *parent)
    : QAbstractListModel(parent) {}

int UpdateModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return static_cast<int>(m_items.size());
}

QVariant UpdateModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }

    const auto &item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item.name;
    case NewEvrRole:
        return item.newEvr;
    case OldEvrRole:
        return item.oldEvr;
    case ArchRole:
        return item.arch;
    case SummaryRole:
        return item.summary;
    case RepoIdRole:
        return item.repoId;
    case DownloadSizeRole:
        return item.downloadSize;
    case FormattedSizeRole:
        return item.formattedDownloadSize();
    case InstallSizeRole:
        return item.installSize;
    case CategoryRole:
        return item.category;
    case CategoryKeyRole:
        return item.categoryKey;
    case AdvisoryIdRole:
        return item.advisoryId;
    case AdvisoryTypeRole:
        return item.advisoryType;
    case SeverityRole:
        return item.severity;
    case AdvisoryTitleRole:
        return item.advisoryTitle;
    case AdvisoryDescRole:
        return item.advisoryDescription;
    case CveListRole:
        return item.cveList;
    case RequiresRebootRole:
        return item.requiresReboot;
    case RequiresSessionRestartRole:
        return item.requiresSessionRestart;
    case ChangelogLoadedRole:
        return item.changelogLoaded;
    case ChangelogListRole:
        return item.changelogList;
    case ItemDataRole:
        return item.toMap();
    default:
        break;
    }
    return {};
}

QHash<int, QByteArray> UpdateModel::roleNames() const {
    return {
        {NameRole, "name"},
        {NewEvrRole, "newEvr"},
        {OldEvrRole, "oldEvr"},
        {ArchRole, "arch"},
        {SummaryRole, "summary"},
        {RepoIdRole, "repoId"},
        {DownloadSizeRole, "downloadSize"},
        {FormattedSizeRole, "formattedSize"},
        {InstallSizeRole, "installSize"},
        {CategoryRole, "category"},
        {CategoryKeyRole, "categoryKey"},
        {AdvisoryIdRole, "advisoryId"},
        {AdvisoryTypeRole, "advisoryType"},
        {SeverityRole, "severity"},
        {AdvisoryTitleRole, "advisoryTitle"},
        {AdvisoryDescRole, "advisoryDesc"},
        {CveListRole, "cveList"},
        {RequiresRebootRole, "requiresReboot"},
        {RequiresSessionRestartRole, "requiresSessionRestart"},
        {ChangelogLoadedRole, "changelogLoaded"},
        {ChangelogListRole, "changelogList"},
        {ItemDataRole, "itemData"}
    };
}

void UpdateModel::setItems(const QList<UpdateItem> &items) {
    beginResetModel();
    m_items = items;
    endResetModel();
    emit countChanged();
}

void UpdateModel::updateChangelog(const QString &packageName, const QVariantList &changelogs) {
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i].name == packageName) {
            m_items[i].changelogLoaded = true;
            m_items[i].changelogList = changelogs;
            const QModelIndex idx = index(i);
            emit dataChanged(idx, idx, {ChangelogLoadedRole, ChangelogListRole, ItemDataRole});
            break;
        }
    }
}

void UpdateModel::clear() {
    beginResetModel();
    m_items.clear();
    endResetModel();
    emit countChanged();
}

QVariantMap UpdateModel::get(int index) const {
    if (index >= 0 && index < m_items.size()) {
        return m_items.at(index).toMap();
    }
    return {};
}

QVariantList UpdateModel::getGroupKeys(const QString &groupBy) const {
    QVariantList groups;
    if (m_items.isEmpty()) {
        return groups;
    }

    if (groupBy == QStringLiteral("advisory")) {
        // Known advisory groups in priority order
        const QStringList order = {QStringLiteral("security"), QStringLiteral("bugfix"),
                                   QStringLiteral("enhancement"), QStringLiteral("general")};
        for (const auto &type : order) {
            int count = 0;
            for (const auto &item : m_items) {
                if (item.advisoryType == type) {
                    count++;
                }
            }
            if (count > 0) {
                QVariantMap g;
                g[QStringLiteral("key")] = type;
                if (type == QStringLiteral("security")) {
                    g[QStringLiteral("label")] = QStringLiteral("Security Updates");
                } else if (type == QStringLiteral("bugfix")) {
                    g[QStringLiteral("label")] = QStringLiteral("Bug Fixes");
                } else if (type == QStringLiteral("enhancement")) {
                    g[QStringLiteral("label")] = QStringLiteral("Enhancements");
                } else {
                    g[QStringLiteral("label")] = QStringLiteral("Package Updates");
                }
                g[QStringLiteral("count")] = count;
                groups.append(g);
            }
        }
    } else if (groupBy == QStringLiteral("repository")) {
        QMap<QString, int> repoCounts;
        for (const auto &item : m_items) {
            repoCounts[item.repoId]++;
        }
        for (auto it = repoCounts.cbegin(); it != repoCounts.cend(); ++it) {
            QVariantMap g;
            g[QStringLiteral("key")] = it.key();
            g[QStringLiteral("label")] = it.key();
            g[QStringLiteral("count")] = it.value();
            groups.append(g);
        }
    } else {
        // Group by functional category
        const QStringList order = {QStringLiteral("kernel"), QStringLiteral("firmware"),
                                   QStringLiteral("shell"), QStringLiteral("core"),
                                   QStringLiteral("app"), QStringLiteral("devel")};
        for (const auto &cat : order) {
            int count = 0;
            for (const auto &item : m_items) {
                if (item.categoryKey == cat) {
                    count++;
                }
            }
            if (count > 0) {
                QVariantMap g;
                g[QStringLiteral("key")] = cat;
                g[QStringLiteral("label")] = UpdateItem::categoryKeyToLabel(cat);
                g[QStringLiteral("count")] = count;
                groups.append(g);
            }
        }
    }

    return groups;
}

QVariantList UpdateModel::getItemsInGroup(const QString &groupBy, const QString &groupKey) const {
    QVariantList list;
    for (const auto &item : m_items) {
        bool match = false;
        if (groupBy == QStringLiteral("advisory")) {
            match = (item.advisoryType == groupKey);
        } else if (groupBy == QStringLiteral("repository")) {
            match = (item.repoId == groupKey);
        } else {
            match = (item.categoryKey == groupKey);
        }
        if (match) {
            list.append(item.toMap());
        }
    }
    return list;
}

} // namespace qs::updatemanager
