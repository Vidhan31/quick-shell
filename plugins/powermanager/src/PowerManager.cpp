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
    QDBusMessage login1Msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"),
        QStringLiteral("/org/freedesktop/login1"),
        QStringLiteral("org.freedesktop.login1.Manager"),
        QStringLiteral("PowerOff")
    );
    login1Msg << true;
    QDBusConnection::systemBus().asyncCall(login1Msg);

    QDBusMessage kdeMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("/Shutdown"),
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("logoutAndShutdown")
    );
    QDBusConnection::sessionBus().asyncCall(kdeMsg);
}

void PowerManager::requestReboot() {
    QDBusMessage login1Msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"),
        QStringLiteral("/org/freedesktop/login1"),
        QStringLiteral("org.freedesktop.login1.Manager"),
        QStringLiteral("Reboot")
    );
    login1Msg << true;
    QDBusConnection::systemBus().asyncCall(login1Msg);

    QDBusMessage kdeMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("/Shutdown"),
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("logoutAndReboot")
    );
    QDBusConnection::sessionBus().asyncCall(kdeMsg);
}

void PowerManager::requestLogout() {
    QDBusMessage kdeMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("/Shutdown"),
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("logout")
    );
    QDBusConnection::sessionBus().asyncCall(kdeMsg);

    QDBusMessage ksmMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.ksmserver"),
        QStringLiteral("/KSMServer"),
        QStringLiteral("org.kde.KSMServerInterface"),
        QStringLiteral("closeSession")
    );
    QDBusConnection::sessionBus().asyncCall(ksmMsg);
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

    QDBusMessage msgPath = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("/org/freedesktop/ScreenSaver"),
        QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("Lock")
    );
    QDBusConnection::sessionBus().asyncCall(msgPath);

    QDBusMessage login1Msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"),
        QStringLiteral("/org/freedesktop/login1"),
        QStringLiteral("org.freedesktop.login1.Manager"),
        QStringLiteral("LockSessions")
    );
    QDBusConnection::systemBus().asyncCall(login1Msg);
}

} // namespace qs::plugins
