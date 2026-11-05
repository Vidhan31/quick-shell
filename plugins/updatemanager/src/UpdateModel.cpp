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
    m_revision++;
    emit revisionChanged();
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
    m_revision++;
    emit revisionChanged();
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
        int secCount = 0;
        int bugCount = 0;
        int enhCount = 0;
        int genCount = 0;

        for (const auto &item : m_items) {
            const QStringView t(item.advisoryType);
            if (t.compare(u"security", Qt::CaseInsensitive) == 0) {
                secCount++;
            } else if (t.compare(u"bugfix", Qt::CaseInsensitive) == 0) {
                bugCount++;
            } else if (t.compare(u"enhancement", Qt::CaseInsensitive) == 0) {
                enhCount++;
            } else {
                genCount++;
            }
        }

        auto makeGroup = [](const QString &key, const QString &label, int count) {
            QVariantMap g;
            g[QStringLiteral("key")] = key;
            g[QStringLiteral("label")] = label;
            g[QStringLiteral("count")] = count;
            return g;
        };

        if (secCount > 0) {
            groups.append(makeGroup(QStringLiteral("security"), QStringLiteral("Security Updates"), secCount));
        }
        if (bugCount > 0) {
            groups.append(makeGroup(QStringLiteral("bugfix"), QStringLiteral("Bug Fixes"), bugCount));
        }
        if (enhCount > 0) {
            groups.append(makeGroup(QStringLiteral("enhancement"), QStringLiteral("Enhancements"), enhCount));
        }
        if (genCount > 0) {
            groups.append(makeGroup(QStringLiteral("general"), QStringLiteral("Package Updates"), genCount));
        }
    } else {
        QMap<QString, int> repoCounts;
        for (const auto &item : m_items) {
            const QString r = item.repoId.isEmpty() ? QStringLiteral("System Repositories") : item.repoId;
            repoCounts[r]++;
        }
        for (auto it = repoCounts.cbegin(); it != repoCounts.cend(); ++it) {
            QVariantMap g;
            g[QStringLiteral("key")] = it.key();
            g[QStringLiteral("label")] = it.key();
            g[QStringLiteral("count")] = it.value();
            groups.append(g);
        }
    }

    return groups;
}

QVariantList UpdateModel::getItemsInGroup(const QString &groupBy, const QString &groupKey) const {
    QVariantList list;
    for (const auto &item : m_items) {
        bool match = false;
        if (groupBy == QStringLiteral("advisory")) {
            const QStringView t(item.advisoryType);
            if (groupKey == QStringLiteral("general")) {
                match = (t.isEmpty() || t.compare(u"general", Qt::CaseInsensitive) == 0 ||
                         (t.compare(u"security", Qt::CaseInsensitive) != 0 &&
                          t.compare(u"bugfix", Qt::CaseInsensitive) != 0 &&
                          t.compare(u"enhancement", Qt::CaseInsensitive) != 0));
            } else {
                match = (t.compare(groupKey, Qt::CaseInsensitive) == 0);
            }
        } else {
            const QString r = item.repoId.isEmpty() ? QStringLiteral("System Repositories") : item.repoId;
            match = (r == groupKey);
        }
        if (match) {
            list.append(item.toMap());
        }
    }
    return list;
}

QVariantList UpdateModel::getChangelog(const QString &packageName) const {
    for (const auto &item : m_items) {
        if (item.name == packageName) {
            return item.changelogList;
        }
    }
    return {};
}

bool UpdateModel::isChangelogLoaded(const QString &packageName) const {
    for (const auto &item : m_items) {
        if (item.name == packageName) {
            return item.changelogLoaded;
        }
    }
    return false;
}

} // namespace qs::updatemanager
