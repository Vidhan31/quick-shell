#pragma once

#include <QDateTime>
#include <QString>
#include <QVariantList>
#include <limits>

namespace qs::plugins::notifications {

// Persist marker: timeout that never expires (freedesktop expire_timeout == 0).
inline constexpr qint64 kPersistTimeout = std::numeric_limits<qint64>::max();

// Pure value type: detached snapshot of a notification plus store metadata.
// The store never holds live Quickshell Notification objects; the QML
// adapter owns those and only forwards plain maps + D-Bus request signals.
struct NotificationEntry {
    int id{-1};
    QString appName{QStringLiteral("Application")};
    QString appIcon;
    QString summary{QStringLiteral("Notification")};
    QString body;
    QString image;
    QString desktopEntry;
    int urgency{1}; // 0 low, 1 normal, 2 critical
    QVariantList actions; // list of {identifier, text}
    bool resident{false};
    bool transient{false};
    bool hasInlineReply{false};
    QString replyPlaceholder;
    bool hasActionIcons{false};
    QString category;
    QString soundName;
    QString soundFile;
    bool suppressSound{false};

    QDateTime receivedAt;
    bool read{false};
    qint64 timeoutMs{5000};
    qint64 expiresAt{0}; // ms since epoch, kPersistTimeout = never
    bool manual{false};

    [[nodiscard]] bool isPersistent() const noexcept { return timeoutMs == kPersistTimeout; }
    [[nodiscard]] bool isCritical() const noexcept { return urgency == 2; }
};

} // namespace qs::plugins::notifications
