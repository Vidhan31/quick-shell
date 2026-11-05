#include "PowerManager.hpp"

#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusError>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>
#include <QtDBus/QDBusPendingCallWatcher>
#include <QtDBus/QDBusPendingReply>

namespace qs::plugins {

PowerManager::PowerManager(QObject *parent)
    : QObject(parent)
{
    refreshBootEntries();
}

void PowerManager::refreshBootEntries() {
    auto *proc = new QProcess(this);
    connect(proc, &QProcess::finished, this, [this, proc](int exitCode, QProcess::ExitStatus exitStatus) {
        proc->deleteLater();
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            return;
        }

        const QString output = QString::fromUtf8(proc->readAllStandardOutput());
        const QStringList lines = output.split(QLatin1Char('\n'));
        const QRegularExpression re(QStringLiteral(R"(^Boot([0-9A-Fa-f]{4})\*?\s+(.*)$)"));
        QString foundEntry;

        for (const QString &line : lines) {
            const auto match = re.match(line.trimmed());
            if (match.hasMatch()) {
                const QString desc = match.captured(2);
                if (desc.contains(QStringLiteral("Windows"), Qt::CaseInsensitive) ||
                    desc.contains(QStringLiteral("BOOTMGFW.EFI"), Qt::CaseInsensitive)) {
                    foundEntry = match.captured(1);
                    break;
                }
            }
        }

        const bool canReboot = !foundEntry.isEmpty();
        if (m_windowsBootEntry != foundEntry) {
            m_windowsBootEntry = foundEntry;
            Q_EMIT windowsBootEntryChanged();
        }
        if (m_canRebootToWindows != canReboot) {
            m_canRebootToWindows = canReboot;
            Q_EMIT canRebootToWindowsChanged();
        }
    });

    connect(proc, &QProcess::errorOccurred, this, [proc](QProcess::ProcessError) {
        proc->deleteLater();
    });

    proc->start(QStringLiteral("efibootmgr"), {});
}

void PowerManager::requestRebootToWindows() {
    if (m_windowsBootEntry.isEmpty()) {
        Q_EMIT rebootToWindowsFailed(QStringLiteral("No Windows UEFI boot entry detected."));
        return;
    }

    const QString entry = m_windowsBootEntry;

    auto launchPkexec = [this, entry]() {
        auto *pkProc = new QProcess(this);
        connect(pkProc, &QProcess::finished, this, [this, pkProc](int pkExitCode, QProcess::ExitStatus pkExitStatus) {
            pkProc->deleteLater();
            if (pkExitStatus == QProcess::NormalExit && pkExitCode == 0) {
                m_isRebooting = true;
                Q_EMIT isRebootingChanged();
                requestReboot();
            } else {
                const QString err = QString::fromUtf8(pkProc->readAllStandardError()).trimmed();
                Q_EMIT rebootToWindowsFailed(err.isEmpty() ? QStringLiteral("Authentication failed or cancelled.") : err);
            }
        });

        connect(pkProc, &QProcess::errorOccurred, this, [this, pkProc](QProcess::ProcessError) {
            const QString err = pkProc->errorString();
            pkProc->deleteLater();
            Q_EMIT rebootToWindowsFailed(err);
        });

        pkProc->start(QStringLiteral("pkexec"), {
            QStringLiteral("efibootmgr"),
            QStringLiteral("-n"),
            entry
        });
    };

    auto *sudoProc = new QProcess(this);
    connect(sudoProc, &QProcess::finished, this, [this, sudoProc, launchPkexec](int exitCode, QProcess::ExitStatus exitStatus) {
        sudoProc->deleteLater();
        if (exitStatus == QProcess::NormalExit && exitCode == 0) {
            m_isRebooting = true;
            Q_EMIT isRebootingChanged();
            requestReboot();
            return;
        }
        launchPkexec();
    });

    connect(sudoProc, &QProcess::errorOccurred, this, [sudoProc, launchPkexec](QProcess::ProcessError) {
        sudoProc->deleteLater();
        launchPkexec();
    });

    sudoProc->start(QStringLiteral("sudo"), {
        QStringLiteral("-n"),
        QStringLiteral("efibootmgr"),
        QStringLiteral("-n"),
        entry
    });
}

void PowerManager::callLogindMethod(const QString &method, const QVariantList &args, const QString &actionName) {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        const QString err = QStringLiteral("System bus is not connected.");
        qWarning() << "PowerManager: Cannot perform" << actionName << "-" << err;
        if (m_isRebooting && actionName == QLatin1String("Reboot")) {
            m_isRebooting = false;
            Q_EMIT isRebootingChanged();
            Q_EMIT rebootToWindowsFailed(err);
        }
        Q_EMIT operationFailed(actionName, err);
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"),
        QStringLiteral("/org/freedesktop/login1"),
        QStringLiteral("org.freedesktop.login1.Manager"),
        method
    );
    msg.setArguments(args);

    const QDBusPendingCall pcall = bus.asyncCall(msg);
    if (pcall.isError()) {
        const QString err = pcall.error().message();
        qWarning() << "PowerManager: Failed to dispatch" << actionName << ":" << err;
        if (m_isRebooting && actionName == QLatin1String("Reboot")) {
            m_isRebooting = false;
            Q_EMIT isRebootingChanged();
            Q_EMIT rebootToWindowsFailed(err);
        }
        Q_EMIT operationFailed(actionName, err);
        return;
    }

    auto *watcher = new QDBusPendingCallWatcher(pcall, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, actionName]() {
        watcher->deleteLater();
        const QDBusPendingReply<void> reply = *watcher;
        if (reply.isError()) {
            const QDBusError error = reply.error();
            const QString err = error.message().isEmpty() ? error.name() : error.message();
            qWarning() << "PowerManager:" << actionName << "failed:" << error.name() << err;
            if (m_isRebooting && actionName == QLatin1String("Reboot")) {
                m_isRebooting = false;
                Q_EMIT isRebootingChanged();
                Q_EMIT rebootToWindowsFailed(err);
            }
            Q_EMIT operationFailed(actionName, err);
        }
    });
}

void PowerManager::requestShutdown() {
    callLogindMethod(QStringLiteral("PowerOff"), {true}, QStringLiteral("Shutdown"));
}

void PowerManager::requestReboot() {
    callLogindMethod(QStringLiteral("Reboot"), {true}, QStringLiteral("Reboot"));
}

void PowerManager::requestLogout() {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        const QString err = QStringLiteral("Session bus is not connected.");
        qWarning() << "PowerManager: Cannot perform Logout -" << err;
        Q_EMIT operationFailed(QStringLiteral("Logout"), err);
        return;
    }

    QDBusMessage kdeMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("/Shutdown"),
        QStringLiteral("org.kde.Shutdown"),
        QStringLiteral("logout")
    );

    const QDBusPendingCall pcall = bus.asyncCall(kdeMsg);
    if (pcall.isError()) {
        const QString err = pcall.error().message();
        qWarning() << "PowerManager: Failed to dispatch Logout:" << err;
        Q_EMIT operationFailed(QStringLiteral("Logout"), err);
        return;
    }

    auto *watcher = new QDBusPendingCallWatcher(pcall, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        watcher->deleteLater();
        const QDBusPendingReply<void> reply = *watcher;
        if (reply.isError()) {
            const QDBusError error = reply.error();
            const QString err = error.message().isEmpty() ? error.name() : error.message();
            qWarning() << "PowerManager: Logout failed:" << error.name() << err;
            Q_EMIT operationFailed(QStringLiteral("Logout"), err);
        }
    });
}

void PowerManager::requestSuspend() {
    callLogindMethod(QStringLiteral("Suspend"), {true}, QStringLiteral("Suspend"));
}

void PowerManager::requestLock() {
    callLogindMethod(QStringLiteral("LockSessions"), {}, QStringLiteral("Lock"));
}

} // namespace qs::plugins
