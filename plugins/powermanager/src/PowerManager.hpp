#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

class PowerManager : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool canRebootToWindows READ canRebootToWindows NOTIFY canRebootToWindowsChanged FINAL)
    Q_PROPERTY(QString windowsBootEntry READ windowsBootEntry NOTIFY windowsBootEntryChanged FINAL)
    Q_PROPERTY(bool isRebooting READ isRebooting NOTIFY isRebootingChanged FINAL)

public:
    explicit PowerManager(QObject *parent = nullptr);
    ~PowerManager() override = default;

    [[nodiscard]] bool canRebootToWindows() const { return m_canRebootToWindows; }
    [[nodiscard]] QString windowsBootEntry() const { return m_windowsBootEntry; }
    [[nodiscard]] bool isRebooting() const { return m_isRebooting; }

    Q_INVOKABLE void requestShutdown();
    Q_INVOKABLE void requestReboot();
    Q_INVOKABLE void requestRebootToWindows();
    Q_INVOKABLE void requestLogout();
    Q_INVOKABLE void requestSuspend();
    Q_INVOKABLE void requestLock();
    Q_INVOKABLE void refreshBootEntries();

signals:
    void canRebootToWindowsChanged();
    void windowsBootEntryChanged();
    void isRebootingChanged();
    void rebootToWindowsFailed(const QString &reason);
    void operationFailed(const QString &operation, const QString &reason);

private:
    void callLogindMethod(const QString &method, const QVariantList &args, const QString &actionName);

    bool m_canRebootToWindows{false};
    QString m_windowsBootEntry;
    bool m_isRebooting{false};
};

} // namespace qs::plugins
