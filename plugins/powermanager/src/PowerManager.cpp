#include "PowerManager.hpp"

#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>

namespace qs::plugins {

PowerManager::PowerManager(QObject *parent)
    : QObject(parent)
{
}

void PowerManager::requestShutdown() {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("/Shutdown"),
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("logoutAndShutdown")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void PowerManager::requestReboot() {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("/Shutdown"),
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("logoutAndReboot")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void PowerManager::requestLogout() {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("/Shutdown"),
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("logout")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

void PowerManager::requestSuspend() {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"),
        QStringLiteral("/org/freedesktop/login1"),
        QStringLiteral("org.freedesktop.login1.Manager"),
        QStringLiteral("Suspend")
    );
    msg << true;
    QDBusConnection::systemBus().asyncCall(msg);
}

void PowerManager::requestLock() {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("/ScreenSaver"),
        QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("Lock")
    );
    QDBusConnection::sessionBus().asyncCall(msg);
}

} // namespace qs::plugins
