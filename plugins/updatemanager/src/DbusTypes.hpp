#pragma once

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QList>
#include <QMetaType>
#include <QString>
#include <QVariantMap>

namespace qs::updatemanager {

struct DbusChangelogEntry {
    qint64 timestamp{0};
    QString author;
    QString text;
};

struct DbusAdvisoryRef {
    QString id;
    QString type;
    QString title;
    QString url;
};

struct DbusTransactionItem {
    QString objectType;
    QString action;
    QString reason;
    QVariantMap transAttrs;
    QVariantMap objectData;
};

void registerDbusTypes();

} // namespace qs::updatemanager

Q_DECLARE_METATYPE(qs::updatemanager::DbusChangelogEntry)
Q_DECLARE_METATYPE(QList<qs::updatemanager::DbusChangelogEntry>)
Q_DECLARE_METATYPE(qs::updatemanager::DbusAdvisoryRef)
Q_DECLARE_METATYPE(QList<qs::updatemanager::DbusAdvisoryRef>)
Q_DECLARE_METATYPE(qs::updatemanager::DbusTransactionItem)
Q_DECLARE_METATYPE(QList<qs::updatemanager::DbusTransactionItem>)
