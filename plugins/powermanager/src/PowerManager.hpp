#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

class PowerManager : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit PowerManager(QObject *parent = nullptr);
    ~PowerManager() override = default;

    Q_INVOKABLE void requestShutdown();
    Q_INVOKABLE void requestReboot();
    Q_INVOKABLE void requestLogout();
    Q_INVOKABLE void requestSuspend();
    Q_INVOKABLE void requestLock();
};

} // namespace qs::plugins
