#pragma once

#include "PrivacyProbe.hpp"

#include <QObject>
#include <QStringList>
#include <QThread>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

class PrivacyWorker : public QObject {
    Q_OBJECT

public:
    explicit PrivacyWorker(int intervalMs = 800, QObject *parent = nullptr);
    ~PrivacyWorker() override;

public slots:
    void start();
    void stop();
    void setInterval(int intervalMs);
    void sample();

signals:
    void stateChanged(const qs::plugins::PrivacyState &state);

private:
    int m_intervalMs;
    int m_tickCount{0};
    QTimer *m_timer{nullptr};
    PrivacyState m_lastState;
    bool m_initialized{false};
};

class PrivacyMonitor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(PrivacyMonitor)

    Q_PROPERTY(bool cameraActive READ cameraActive NOTIFY privacyChanged)
    Q_PROPERTY(bool micActive READ micActive NOTIFY privacyChanged)
    Q_PROPERTY(bool hasActive READ hasActive NOTIFY privacyChanged)
    Q_PROPERTY(QStringList cameraApps READ cameraApps NOTIFY privacyChanged)
    Q_PROPERTY(QStringList micApps READ micApps NOTIFY privacyChanged)
    Q_PROPERTY(QStringList cameraDevices READ cameraDevices NOTIFY privacyChanged)
    Q_PROPERTY(QStringList micDevices READ micDevices NOTIFY privacyChanged)
    Q_PROPERTY(QVariantMap privacyData READ privacyData NOTIFY privacyChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)

public:
    explicit PrivacyMonitor(QObject *parent = nullptr);
    ~PrivacyMonitor() override;

    [[nodiscard]] bool cameraActive() const noexcept { return m_state.cameraActive; }
    [[nodiscard]] bool micActive() const noexcept { return m_state.micActive; }
    [[nodiscard]] bool hasActive() const noexcept { return m_state.hasActive(); }
    [[nodiscard]] QStringList cameraApps() const { return m_state.cameraApps; }
    [[nodiscard]] QStringList micApps() const { return m_state.micApps; }
    [[nodiscard]] QStringList cameraDevices() const { return m_state.cameraDevices; }
    [[nodiscard]] QStringList micDevices() const { return m_state.micDevices; }
    [[nodiscard]] QVariantMap privacyData() const { return m_cachedData; }

    [[nodiscard]] bool running() const noexcept { return m_running; }
    [[nodiscard]] int interval() const noexcept { return m_interval; }

    void setRunning(bool running);
    void setInterval(int interval);

    Q_INVOKABLE void refresh();

signals:
    void privacyChanged();
    void runningChanged();
    void intervalChanged();

    void requestStart();
    void requestStop();
    void requestSetInterval(int interval);
    void requestSample();

private slots:
    void onStateChanged(const qs::plugins::PrivacyState &state);

private:
    PrivacyState m_state;
    QVariantMap m_cachedData;
    bool m_running{true};
    int m_interval{800};

    QThread m_workerThread;
    PrivacyWorker *m_worker{nullptr};
};

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::PrivacyState)
