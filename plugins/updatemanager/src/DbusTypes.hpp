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

QDBusArgument &operator<<(QDBusArgument &argument, const DbusChangelogEntry &entry);
const QDBusArgument &operator>>(const QDBusArgument &argument, DbusChangelogEntry &entry);

QDBusArgument &operator<<(QDBusArgument &argument, const DbusAdvisoryRef &ref);
const QDBusArgument &operator>>(const QDBusArgument &argument, DbusAdvisoryRef &ref);

QDBusArgument &operator<<(QDBusArgument &argument, const DbusTransactionItem &item);
const QDBusArgument &operator>>(const QDBusArgument &argument, DbusTransactionItem &item);

void registerDbusTypes();

} // namespace qs::updatemanager

Q_DECLARE_METATYPE(qs::updatemanager::DbusChangelogEntry)
Q_DECLARE_METATYPE(QList<qs::updatemanager::DbusChangelogEntry>)
Q_DECLARE_METATYPE(qs::updatemanager::DbusAdvisoryRef)
Q_DECLARE_METATYPE(QList<qs::updatemanager::DbusAdvisoryRef>)
Q_DECLARE_METATYPE(qs::updatemanager::DbusTransactionItem)
Q_DECLARE_METATYPE(QList<qs::updatemanager::DbusTransactionItem>)
