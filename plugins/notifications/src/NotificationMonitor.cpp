#include "NotificationMonitor.hpp"

#include <dbus/dbus.h>
#include <QDebug>
#include <cstring>

namespace qs::plugins::notifications {

namespace {

void parseHints(DBusMessageIter *dictIter, NotificationItem &item) {
    while (dbus_message_iter_get_arg_type(dictIter) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entryIter, varIter;
        dbus_message_iter_recurse(dictIter, &entryIter);

        const char *key = nullptr;
        dbus_message_iter_get_basic(&entryIter, &key);
        dbus_message_iter_next(&entryIter);

        dbus_message_iter_recurse(&entryIter, &varIter);
        int valType = dbus_message_iter_get_arg_type(&varIter);

        if (key) {
            if (std::strcmp(key, "urgency") == 0) {
                if (valType == DBUS_TYPE_BYTE) {
                    unsigned char b = 1;
                    dbus_message_iter_get_basic(&varIter, &b);
                    item.urgency = b;
                } else if (valType == DBUS_TYPE_INT32 || valType == DBUS_TYPE_UINT32) {
                    int u = 1;
                    dbus_message_iter_get_basic(&varIter, &u);
                    item.urgency = u;
                }
            } else if (std::strcmp(key, "image-path") == 0 || std::strcmp(key, "image_path") == 0) {
                if (valType == DBUS_TYPE_STRING) {
                    const char *val = nullptr;
                    dbus_message_iter_get_basic(&varIter, &val);
                    if (val) item.image = QString::fromUtf8(val);
                }
            } else if (std::strcmp(key, "desktop-entry") == 0) {
                if (valType == DBUS_TYPE_STRING) {
                    const char *val = nullptr;
                    dbus_message_iter_get_basic(&varIter, &val);
                    if (val) item.desktopEntry = QString::fromUtf8(val);
                }
            }
        }

        dbus_message_iter_next(dictIter);
    }
}

bool parseNotifyMessage(DBusMessage *msg, NotificationItem &item, std::atomic<uint32_t> &idCounter) {
    DBusMessageIter iter;
    if (!dbus_message_iter_init(msg, &iter)) return false;

    // 0: app_name (string)
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_STRING) {
        const char *s = nullptr;
        dbus_message_iter_get_basic(&iter, &s);
        item.appName = s ? QString::fromUtf8(s) : QStringLiteral("Application");
    }
    dbus_message_iter_next(&iter);

    // 1: replaces_id (uint32)
    uint32_t replacesId = 0;
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_UINT32) {
        dbus_message_iter_get_basic(&iter, &replacesId);
    }
    dbus_message_iter_next(&iter);

    // 2: app_icon (string)
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_STRING) {
        const char *s = nullptr;
        dbus_message_iter_get_basic(&iter, &s);
        if (s) item.appIcon = QString::fromUtf8(s);
    }
    dbus_message_iter_next(&iter);

    // 3: summary (string)
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_STRING) {
        const char *s = nullptr;
        dbus_message_iter_get_basic(&iter, &s);
        item.summary = s ? QString::fromUtf8(s) : QStringLiteral("Notification");
    }
    dbus_message_iter_next(&iter);

    // 4: body (string)
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_STRING) {
        const char *s = nullptr;
        dbus_message_iter_get_basic(&iter, &s);
        if (s) item.body = QString::fromUtf8(s);
    }
    dbus_message_iter_next(&iter);

    // 5: actions (array of strings)
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_ARRAY) {
        DBusMessageIter arrIter;
        dbus_message_iter_recurse(&iter, &arrIter);
        QList<QString> rawActions;
        while (dbus_message_iter_get_arg_type(&arrIter) == DBUS_TYPE_STRING) {
            const char *act = nullptr;
            dbus_message_iter_get_basic(&arrIter, &act);
            if (act) rawActions.append(QString::fromUtf8(act));
            dbus_message_iter_next(&arrIter);
        }
        for (qsizetype i = 0; i + 1 < rawActions.size(); i += 2) {
            item.actions.append(NotificationAction{rawActions[i], rawActions[i + 1]});
        }
    }
    dbus_message_iter_next(&iter);

    // 6: hints (dict of string->variant)
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_ARRAY) {
        DBusMessageIter dictIter;
        dbus_message_iter_recurse(&iter, &dictIter);
        parseHints(&dictIter, item);
    }
    dbus_message_iter_next(&iter);

    // 7: expire_timeout (int32)
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_INT32) {
        dbus_message_iter_get_basic(&iter, &item.timeout);
        if (item.timeout <= 0) {
            item.timeout = item.urgency == 2 ? 10000 : (item.urgency == 0 ? 3500 : 5000);
        }
    }

    item.id = (replacesId > 0) ? replacesId : ++idCounter;
    item.notifId = QString::number(item.id);
    item.timestamp = QDateTime::currentDateTime();
    item.read = false;

    return true;
}

} // anonymous namespace

NotificationMonitor::NotificationMonitor(QObject *parent)
    : QThread(parent)
{
}

NotificationMonitor::~NotificationMonitor() {
    stop();
}

void NotificationMonitor::stop() {
    m_running.store(false, std::memory_order_release);
    if (isRunning()) {
        wait(1000);
        if (isRunning()) {
            terminate();
            wait(200);
        }
    }
    cleanupConnection();
}

bool NotificationMonitor::setupMonitor() {
    DBusError err;
    dbus_error_init(&err);

    m_conn = dbus_bus_get_private(DBUS_BUS_SESSION, &err);
    if (!m_conn) {
        emit monitorError(QStringLiteral("Failed to connect to D-Bus session: %1").arg(err.message));
        dbus_error_free(&err);
        return false;
    }

    dbus_connection_set_exit_on_disconnect(m_conn, FALSE);

    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus.Monitoring",
        "BecomeMonitor");

    if (!msg) {
        emit monitorError(QStringLiteral("Failed to allocate BecomeMonitor call"));
        cleanupConnection();
        return false;
    }

    DBusMessageIter iter, sub;
    dbus_message_iter_init_append(msg, &iter);

    const char *match = "interface='org.freedesktop.Notifications'";
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "s", &sub);
    dbus_message_iter_append_basic(&sub, DBUS_TYPE_STRING, &match);
    dbus_message_iter_close_container(&iter, &sub);

    dbus_uint32_t flags = 0;
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &flags);

    if (!dbus_connection_send(m_conn, msg, nullptr)) {
        emit monitorError(QStringLiteral("Failed to send BecomeMonitor message"));
        dbus_message_unref(msg);
        cleanupConnection();
        return false;
    }

    dbus_connection_flush(m_conn);
    dbus_message_unref(msg);
    return true;
}

void NotificationMonitor::cleanupConnection() {
    if (m_conn) {
        dbus_connection_close(m_conn);
        dbus_connection_unref(m_conn);
        m_conn = nullptr;
    }
}

void NotificationMonitor::run() {
    if (!setupMonitor()) {
        return;
    }

    m_running.store(true, std::memory_order_release);

    while (m_running.load(std::memory_order_acquire)) {
        if (!dbus_connection_read_write(m_conn, 100)) {
            // Connection lost
            break;
        }

        DBusMessage *msg = nullptr;
        while ((msg = dbus_connection_pop_message(m_conn)) != nullptr) {
            const char *member = dbus_message_get_member(msg);
            if (member) {
                if (std::strcmp(member, "Notify") == 0) {
                    NotificationItem item;
                    if (parseNotifyMessage(msg, item, m_idCounter)) {
                        emit notificationReceived(item);
                    }
                } else if (std::strcmp(member, "NotificationClosed") == 0) {
                    uint32_t id = 0, reason = 0;
                    DBusMessageIter cIter;
                    if (dbus_message_iter_init(msg, &cIter) &&
                        dbus_message_iter_get_arg_type(&cIter) == DBUS_TYPE_UINT32) {
                        dbus_message_iter_get_basic(&cIter, &id);
                        dbus_message_iter_next(&cIter);
                        if (dbus_message_iter_get_arg_type(&cIter) == DBUS_TYPE_UINT32) {
                            dbus_message_iter_get_basic(&cIter, &reason);
                            emit notificationClosed(id, reason);
                        }
                    }
                } else if (std::strcmp(member, "ActionInvoked") == 0) {
                    uint32_t id = 0;
                    const char *actionKey = nullptr;
                    DBusMessageIter aIter;
                    if (dbus_message_iter_init(msg, &aIter) &&
                        dbus_message_iter_get_arg_type(&aIter) == DBUS_TYPE_UINT32) {
                        dbus_message_iter_get_basic(&aIter, &id);
                        dbus_message_iter_next(&aIter);
                        if (dbus_message_iter_get_arg_type(&aIter) == DBUS_TYPE_STRING) {
                            dbus_message_iter_get_basic(&aIter, &actionKey);
                            if (actionKey) {
                                emit actionInvoked(id, QString::fromUtf8(actionKey));
                            }
                        }
                    }
                }
            }
            dbus_message_unref(msg);
        }
    }

    cleanupConnection();
}

} // namespace qs::plugins::notifications
