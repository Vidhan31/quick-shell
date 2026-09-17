#pragma once

#include "NotificationTypes.hpp"

#include <QObject>
#include <QThread>
#include <atomic>

struct DBusConnection;

namespace qs::plugins::notifications {

class NotificationMonitor : public QThread {
    Q_OBJECT

public:
    explicit NotificationMonitor(QObject *parent = nullptr);
    ~NotificationMonitor() override;

    void stop();

signals:
    void notificationReceived(const qs::plugins::notifications::NotificationItem &item);
    void notificationClosed(uint32_t id, uint32_t reason);
    void actionInvoked(uint32_t id, const QString &actionKey);
    void monitorError(const QString &error);

protected:
    void run() override;

private:
    std::atomic<bool> m_running{false};
    DBusConnection *m_conn{nullptr};
    std::atomic<uint32_t> m_idCounter{1};

    bool setupMonitor();
    void cleanupConnection();
};

} // namespace qs::plugins::notifications
