#pragma once

#include <QDateTime>
#include <QList>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include <cstdint>

namespace qs::plugins::notifications {

Q_NAMESPACE
QML_ELEMENT

enum class NotificationUrgency : int {
    Low = 0,
    Normal = 1,
    Critical = 2
};
Q_ENUM_NS(NotificationUrgency)

struct NotificationAction {
    QString identifier;
    QString text;

    [[nodiscard]] QVariantMap toMap() const {
        return {
            {QStringLiteral("identifier"), identifier},
            {QStringLiteral("text"), text.isEmpty() ? identifier : text}
        };
    }
};

struct NotificationItem {
    uint32_t id{0};
    QString notifId;
    QString appName;
    QString appIcon;
    QString summary;
    QString body;
    QString image;
    QString desktopEntry;
    int urgency{1};
    int timeout{5000};
    QDateTime timestamp;
    bool read{false};
    QList<NotificationAction> actions;

    [[nodiscard]] QString timeAgo() const {
        if (!timestamp.isValid()) return QStringLiteral("Just now");
        qint64 diffMs = std::max<qint64>(0, timestamp.msecsTo(QDateTime::currentDateTime()));
        qint64 secs = diffMs / 1000;
        qint64 mins = secs / 60;
        qint64 hrs = mins / 60;
        qint64 days = hrs / 24;

        if (secs < 45) return QStringLiteral("Just now");
        if (mins < 60) {
            return QStringLiteral("%1 min%2 ago")
                .arg(mins)
                .arg(mins == 1 ? QString() : QStringLiteral("s"));
        }
        if (hrs < 24) {
            return QStringLiteral("%1 hr%2 ago")
                .arg(hrs)
                .arg(hrs == 1 ? QString() : QStringLiteral("s"));
        }
        if (days < 7) {
            return QStringLiteral("%1 day%2 ago")
                .arg(days)
                .arg(days == 1 ? QString() : QStringLiteral("s"));
        }
        return timestamp.toString(QStringLiteral("MMM d"));
    }

    [[nodiscard]] QVariantList actionsVariantList() const {
        QVariantList list;
        list.reserve(actions.size());
        for (const auto &act : actions) {
            list.append(act.toMap());
        }
        return list;
    }

    [[nodiscard]] QVariantMap toMap() const {
        return {
            {QStringLiteral("id"), id},
            {QStringLiteral("notifId"), notifId.isEmpty() ? QString::number(id) : notifId},
            {QStringLiteral("appName"), appName.isEmpty() ? QStringLiteral("Application") : appName},
            {QStringLiteral("appIcon"), appIcon},
            {QStringLiteral("summary"), summary.isEmpty() ? QStringLiteral("Notification") : summary},
            {QStringLiteral("body"), body},
            {QStringLiteral("image"), image},
            {QStringLiteral("desktopEntry"), desktopEntry},
            {QStringLiteral("urgency"), urgency},
            {QStringLiteral("timeout"), timeout},
            {QStringLiteral("timestamp"), timestamp},
            {QStringLiteral("timeAgo"), timeAgo()},
            {QStringLiteral("read"), read},
            {QStringLiteral("actions"), actionsVariantList()},
            {QStringLiteral("isBridge"), false}
        };
    }
};

} // namespace qs::plugins::notifications

Q_DECLARE_METATYPE(qs::plugins::notifications::NotificationAction)
Q_DECLARE_METATYPE(qs::plugins::notifications::NotificationItem)
