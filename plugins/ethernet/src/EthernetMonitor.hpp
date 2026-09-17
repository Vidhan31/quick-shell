#pragma once

#include "EthernetProbe.hpp"

#include <QObject>
#include <QStringList>
#include <QThread>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <QSocketNotifier>

namespace qs::plugins {

class EthernetWorker : public QObject {
    Q_OBJECT

public:
    explicit EthernetWorker(int intervalMs = 2000, QObject *parent = nullptr);
    ~EthernetWorker() override;

public slots:
    void start();
    void stop();
    void setInterval(int intervalMs);
    void setThroughputTracking(bool tracking);
    void sample(bool forceInternetCheck = false);
    void sampleThroughput();
    void runPing(const QString &target);
    void runCheck();
    void reconnect(const QString &iface);
    void openSettings();

signals:
    void stateChanged(const qs::plugins::EthernetState &state);
    void throughputUpdated(quint64 rxBytes, quint64 txBytes, double rxBps, double txBps);
    void pingFinished(bool ok, const QString &target, double latencyMs, const QString &output);

private slots:
    void onNmSignal();
    void onNetlinkActivated();

private:
    void setupNetlink();
    void closeNetlink();
    void setupDbusSubscriptions();
    void triggerSampleDebounced();

    int m_intervalMs{2000};
    bool m_throughputTracking{false};
    QTimer *m_throughputTimer{nullptr};
    QTimer *m_debounceTimer{nullptr};

    int m_netlinkFd{-1};
    QSocketNotifier *m_netlinkNotifier{nullptr};

    EthernetState m_lastState;
    quint64 m_prevRx{0};
    quint64 m_prevTx{0};
    std::chrono::steady_clock::time_point m_prevTime;
    bool m_initialized{false};
};

class EthernetMonitor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(EthernetMonitor)

    // Full QVariantMap matching the schema for QML backwards compatibility
    Q_PROPERTY(QVariantMap ethData READ ethData NOTIFY stateChanged)

    // Strongly-typed reactive properties
    Q_PROPERTY(bool ok READ isOk NOTIFY stateChanged)
    Q_PROPERTY(bool carrier READ carrier NOTIFY stateChanged)
    Q_PROPERTY(bool hasInternet READ hasInternet NOTIFY stateChanged)
    Q_PROPERTY(QString currentStatus READ currentStatus NOTIFY stateChanged)
    Q_PROPERTY(QString statusDesc READ statusDesc NOTIFY stateChanged)
    Q_PROPERTY(QString interfaceName READ interfaceName NOTIFY stateChanged)
    Q_PROPERTY(QStringList interfaces READ interfaces NOTIFY stateChanged)
    Q_PROPERTY(QString connectionName READ connectionName NOTIFY stateChanged)
    Q_PROPERTY(QString ip READ ip NOTIFY stateChanged)
    Q_PROPERTY(QString ipv6 READ ipv6 NOTIFY stateChanged)
    Q_PROPERTY(QString gateway READ gateway NOTIFY stateChanged)
    Q_PROPERTY(QStringList dns READ dns NOTIFY stateChanged)
    Q_PROPERTY(QString speedLabel READ speedLabel NOTIFY stateChanged)
    Q_PROPERTY(int speedMbps READ speedMbps NOTIFY stateChanged)
    Q_PROPERTY(QString hwAddress READ hwAddress NOTIFY stateChanged)
    Q_PROPERTY(int nmConnectivity READ nmConnectivity NOTIFY stateChanged)
    Q_PROPERTY(bool isDefaultRoute READ isDefaultRoute NOTIFY stateChanged)

    // Live throughput metrics
    Q_PROPERTY(qulonglong rxBytes READ rxBytes NOTIFY throughputChanged)
    Q_PROPERTY(qulonglong txBytes READ txBytes NOTIFY throughputChanged)
    Q_PROPERTY(double downloadBps READ downloadBps NOTIFY throughputChanged)
    Q_PROPERTY(double uploadBps READ uploadBps NOTIFY throughputChanged)

    // Ping diagnostic state
    Q_PROPERTY(bool isPinging READ isPinging NOTIFY pingStatusChanged)
    Q_PROPERTY(double pingLatency READ pingLatency NOTIFY pingStatusChanged)
    Q_PROPERTY(QString pingResult READ pingResult NOTIFY pingStatusChanged)

    // Lifecycle and timing
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)
    Q_PROPERTY(bool throughputTracking READ throughputTracking WRITE setThroughputTracking NOTIFY throughputTrackingChanged)
    Q_PROPERTY(bool isBusy READ isBusy NOTIFY busyChanged)

public:
    explicit EthernetMonitor(QObject *parent = nullptr);
    ~EthernetMonitor() override;

    [[nodiscard]] QVariantMap ethData() const { return m_cachedMap; }

    [[nodiscard]] bool isOk() const noexcept { return m_state.ok; }
    [[nodiscard]] bool carrier() const noexcept { return m_state.carrier; }
    [[nodiscard]] bool hasInternet() const noexcept { return m_state.hasInternet; }
    [[nodiscard]] QString currentStatus() const { return m_state.status; }
    [[nodiscard]] QString statusDesc() const { return m_state.statusDesc; }
    [[nodiscard]] QString interfaceName() const { return m_state.iface; }
    [[nodiscard]] QStringList interfaces() const { return m_state.ifaces; }
    [[nodiscard]] QString connectionName() const { return m_state.connectionName; }
    [[nodiscard]] QString ip() const { return m_state.ip; }
    [[nodiscard]] QString ipv6() const { return m_state.ipv6; }
    [[nodiscard]] QString gateway() const { return m_state.gateway; }
    [[nodiscard]] QStringList dns() const { return m_state.dns; }
    [[nodiscard]] QString speedLabel() const { return m_state.speedLabel; }
    [[nodiscard]] int speedMbps() const noexcept { return m_state.speedMbps; }
    [[nodiscard]] QString hwAddress() const { return m_state.hwAddress; }
    [[nodiscard]] int nmConnectivity() const noexcept { return m_state.nmConnectivity; }
    [[nodiscard]] bool isDefaultRoute() const noexcept { return m_state.isDefaultRoute; }

    [[nodiscard]] qulonglong rxBytes() const noexcept { return m_rxBytes; }
    [[nodiscard]] qulonglong txBytes() const noexcept { return m_txBytes; }
    [[nodiscard]] double downloadBps() const noexcept { return m_downloadBps; }
    [[nodiscard]] double uploadBps() const noexcept { return m_uploadBps; }

    [[nodiscard]] bool isPinging() const noexcept { return m_isPinging; }
    [[nodiscard]] double pingLatency() const noexcept { return m_pingLatency; }
    [[nodiscard]] QString pingResult() const { return m_pingResult; }

    [[nodiscard]] bool running() const noexcept { return m_running; }
    [[nodiscard]] int interval() const noexcept { return m_interval; }
    [[nodiscard]] bool throughputTracking() const noexcept { return m_throughputTracking; }
    [[nodiscard]] bool isBusy() const noexcept { return m_isBusy; }

    void setRunning(bool running);
    void setInterval(int interval);
    void setThroughputTracking(bool tracking);

    // QML invokable actions
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void runPing(const QString &host = QStringLiteral("1.1.1.1"));
    Q_INVOKABLE void runCheck();
    Q_INVOKABLE void reconnect(const QString &iface = QString());
    Q_INVOKABLE void openSettings();

signals:
    void stateChanged();
    void throughputChanged();
    void pingStatusChanged();
    void runningChanged();
    void intervalChanged();
    void throughputTrackingChanged();
    void busyChanged();
    void pingCompleted(bool ok, double latencyMs, const QString &output);

    // Signals to worker
    void requestStart();
    void requestStop();
    void requestSetInterval(int interval);
    void requestSetThroughputTracking(bool tracking);
    void requestSample(bool forceInternetCheck);
    void requestPing(const QString &target);
    void requestCheck();
    void requestReconnect(const QString &iface);
    void requestOpenSettings();

private slots:
    void onStateChanged(const qs::plugins::EthernetState &state);
    void onThroughputUpdated(quint64 rxBytes, quint64 txBytes, double rxBps, double txBps);
    void onPingFinished(bool ok, const QString &target, double latencyMs, const QString &output);

private:
    EthernetState m_state;
    QVariantMap m_cachedMap;

    quint64 m_rxBytes{0};
    quint64 m_txBytes{0};
    double m_downloadBps{0.0};
    double m_uploadBps{0.0};

    bool m_isPinging{false};
    double m_pingLatency{-1.0};
    QString m_pingResult;

    bool m_running{true};
    int m_interval{2000};
    bool m_throughputTracking{false};
    bool m_isBusy{false};

    QThread m_workerThread;
    EthernetWorker *m_worker{nullptr};
};

} // namespace qs::plugins

Q_DECLARE_METATYPE(qs::plugins::EthernetState)
