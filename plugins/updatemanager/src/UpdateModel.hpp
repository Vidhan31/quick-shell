#pragma once

#include "UpdateItem.hpp"

#include <QAbstractListModel>
#include <QList>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace qs::updatemanager {

class UpdateModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("UpdateModel cannot be instantiated directly")
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum UpdateRoles {
        NameRole = Qt::UserRole + 1,
        NewEvrRole,
        OldEvrRole,
        ArchRole,
        SummaryRole,
        RepoIdRole,
        DownloadSizeRole,
        FormattedSizeRole,
        InstallSizeRole,
        CategoryRole,
        CategoryKeyRole,
        AdvisoryIdRole,
        AdvisoryTypeRole,
        SeverityRole,
        AdvisoryTitleRole,
        AdvisoryDescRole,
        CveListRole,
        RequiresRebootRole,
        RequiresSessionRestartRole,
        ChangelogLoadedRole,
        ChangelogListRole,
        ItemDataRole
    };

    explicit UpdateModel(QObject *parent = nullptr);
    ~UpdateModel() override = default;

    [[nodiscard]] int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] int count() const { return static_cast<int>(m_items.size()); }

    void setItems(const QList<UpdateItem> &items);
    void updateChangelog(const QString &packageName, const QVariantList &changelogs);
    void clear();

    [[nodiscard]] const QList<UpdateItem> &items() const { return m_items; }

    Q_INVOKABLE [[nodiscard]] QVariantMap get(int index) const;
    Q_INVOKABLE [[nodiscard]] QVariantList getGroupKeys(const QString &groupBy) const;
    Q_INVOKABLE [[nodiscard]] QVariantList getItemsInGroup(const QString &groupBy, const QString &groupKey) const;

signals:
    void countChanged();

private:
    QList<UpdateItem> m_items;
};

} // namespace qs::updatemanager
