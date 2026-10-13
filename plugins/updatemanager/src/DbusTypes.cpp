#include "DbusTypes.hpp"

namespace qs::updatemanager {

QDBusArgument &operator<<(QDBusArgument &argument, const DbusChangelogEntry &entry) {
    argument.beginStructure();
    argument << entry.timestamp << entry.author << entry.text;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, DbusChangelogEntry &entry) {
    argument.beginStructure();
    argument >> entry.timestamp >> entry.author >> entry.text;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const DbusAdvisoryRef &ref) {
    argument.beginStructure();
    argument << ref.id << ref.type << ref.title << ref.url;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, DbusAdvisoryRef &ref) {
    argument.beginStructure();
    argument >> ref.id >> ref.type >> ref.title >> ref.url;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const DbusTransactionItem &item) {
    argument.beginStructure();
    argument << item.objectType << item.action << item.reason << item.transAttrs << item.objectData;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, DbusTransactionItem &item) {
    argument.beginStructure();
    argument >> item.objectType >> item.action >> item.reason >> item.transAttrs >> item.objectData;
    argument.endStructure();
    return argument;
}

void registerDbusTypes() {
    static bool registered = false;
    if (registered) {
        return;
    }
    registered = true;

    qRegisterMetaType<DbusChangelogEntry>("DbusChangelogEntry");
    qRegisterMetaType<QList<DbusChangelogEntry>>("QList<DbusChangelogEntry>");
    qDBusRegisterMetaType<DbusChangelogEntry>();
    qDBusRegisterMetaType<QList<DbusChangelogEntry>>();

    qRegisterMetaType<DbusAdvisoryRef>("DbusAdvisoryRef");
    qRegisterMetaType<QList<DbusAdvisoryRef>>("QList<DbusAdvisoryRef>");
    qDBusRegisterMetaType<DbusAdvisoryRef>();
    qDBusRegisterMetaType<QList<DbusAdvisoryRef>>();

    qRegisterMetaType<DbusTransactionItem>("DbusTransactionItem");
    qRegisterMetaType<QList<DbusTransactionItem>>("QList<DbusTransactionItem>");
    qDBusRegisterMetaType<DbusTransactionItem>();
    qDBusRegisterMetaType<QList<DbusTransactionItem>>();
}

} // namespace qs::updatemanager
