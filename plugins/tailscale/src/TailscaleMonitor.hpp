#pragma once

#include "TailscaleSocketClient.hpp"
#include "TailscaleState.hpp"

#include <QFileSystemWatcher>
#include <QLocalSocket>
#include <QObject>
#include <QThread>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

class TailscaleWorker : public QObject {
    Q_OBJECT

public:
    explicit TailscaleWorker(int intervalMs = 5000, QObject *parent = nullptr);
    ~TailscaleWorker() override;

public slots:
    void start();
    void stop();
    void setInterval(int intervalMs);
    void sample();
    void runAction(const QVariantList &args, const QString &successMsg);
    void runPing(const QString &ip);
    void runNetcheck();

signals:
    void stateChanged(const qs::plugins::TailscaleState &state);
    void actionFinished(bool ok, const QString &output, const QString &error, const QString &successMsg);
    void pingFinished(bool ok, const QString &targetIp, const QString &latency, const QString &output, const QString &error);
    void netcheckFinished(bool ok, const QString &report, const QString &error);
    void busyChanged(bool busy);

private slots:
    void onWatchSocketConnected();
    void onWatchSocketReadyRead();
    void onWatchSocketError(QLocalSocket::LocalSocketError socketError);
    void onWatchSocketDisconnected();
    void reconnectWatchBus();
    void onSocketDirectoryChanged(const QString &path);

private:
    void connectWatchBus();
    void triggerSampleDebounced();
    void setupFsWatcher();
    void closeFsWatcher();

    TailscaleSocketClient m_client;
    int m_intervalMs{5000};
    QTimer *m_debounceTimer{nullptr};
    QTimer *m_reconnectTimer{nullptr};
    QFileSystemWatcher *m_fsWatcher{nullptr};
    QLocalSocket *m_watchSocket{nullptr};
    QByteArray m_watchBuffer;
    bool m_watchConnected{false};
    bool m_headersParsed{false};
    bool m_isSampling{false};
    bool m_initialized{false};
    TailscaleState m_lastState;
};

class TailscaleMonitor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(TailscaleMonitor)

    // Full QVariantMap matching tailscale-bridge.py schema for 100% QML compatibility
    Q_PROPERTY(QVariantMap tsData READ tsData NOTIFY stateChanged)

    // Strongly-typed reactive properties
    Q_PROPERTY(bool ok READ isOk NOTIFY stateChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY stateChanged)
    Q_PROPERTY(QString backendState READ backendState NOTIFY stateChanged)
    Q_PROPERTY(QString version READ version NOTIFY stateChanged)
    Q_PROPERTY(QString tailnet READ tailnet NOTIFY stateChanged)
    Q_PROPERTY(QString magicDnsSuffix READ magicDnsSuffix NOTIFY stateChanged)

    // Self info
    Q_PROPERTY(QString hostname READ hostname NOTIFY stateChanged)
    Q_PROPERTY(QString dnsName READ dnsName NOTIFY stateChanged)
    Q_PROPERTY(QString ipv4 READ ipv4 NOTIFY stateChanged)
    Q_PROPERTY(QString ipv6 READ ipv6 NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap user READ user NOTIFY stateChanged)

    // Preferences & Toggles
    Q_PROPERTY(bool sshEnabled READ sshEnabled NOTIFY stateChanged)
    Q_PROPERTY(bool webclientEnabled READ webclientEnabled NOTIFY stateChanged)
    Q_PROPERTY(bool shieldsUp READ shieldsUp NOTIFY stateChanged)
    Q_PROPERTY(bool exitNodeEnabled READ exitNodeEnabled NOTIFY stateChanged)
    Q_PROPERTY(bool autoUpdate READ autoUpdate NOTIFY stateChanged)

    // Collections
    Q_PROPERTY(int serveCount READ serveCount NOTIFY stateChanged)
    Q_PROPERTY(bool hasFunnel READ hasFunnel NOTIFY stateChanged)
    Q_PROPERTY(QVariantList serveItems READ serveItems NOTIFY stateChanged)
    Q_PROPERTY(QVariantList peers READ peers NOTIFY stateChanged)
    Q_PROPERTY(QVariantList health READ health NOTIFY stateChanged)
    Q_PROPERTY(QVariantList services READ services NOTIFY stateChanged)

    // Diagnostics & UI State
    Q_PROPERTY(bool isBusy READ isBusy NOTIFY busyChanged)
    Q_PROPERTY(bool isRunningNetcheck READ isRunningNetcheck NOTIFY netcheckStatusChanged)
    Q_PROPERTY(QString pingResult READ pingResult NOTIFY pingFinished)
    Q_PROPERTY(QString pingTargetIp READ pingTargetIp NOTIFY pingFinished)
    Q_PROPERTY(QString netcheckReport READ netcheckReport NOTIFY netcheckStatusChanged)

    // Lifecycle
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)

public:
    explicit TailscaleMonitor(QObject *parent = nullptr);
    ~TailscaleMonitor() override;

    [[nodiscard]] QVariantMap tsData() const { return m_cachedMap; }

    [[nodiscard]] bool isOk() const noexcept { return m_state.ok; }
    [[nodiscard]] bool isConnected() const noexcept { return m_state.connected; }
    [[nodiscard]] QString backendState() const { return m_state.backendState; }
    [[nodiscard]] QString version() const { return m_state.version; }
    [[nodiscard]] QString tailnet() const { return m_state.tailnet; }
    [[nodiscard]] QString magicDnsSuffix() const { return m_state.magicDnsSuffix; }

    [[nodiscard]] QString hostname() const { return m_state.self.hostname; }
    [[nodiscard]] QString dnsName() const { return m_state.self.dnsName; }
    [[nodiscard]] QString ipv4() const { return m_state.self.ipv4; }
    [[nodiscard]] QString ipv6() const { return m_state.self.ipv6; }
    [[nodiscard]] QVariantMap user() const { return m_state.self.user; }

    [[nodiscard]] bool sshEnabled() const noexcept { return m_state.sshEnabled; }
    [[nodiscard]] bool webclientEnabled() const noexcept { return m_state.webclientEnabled; }
    [[nodiscard]] bool shieldsUp() const noexcept { return m_state.shieldsUp; }
    [[nodiscard]] bool exitNodeEnabled() const noexcept { return m_state.exitNodeEnabled; }
    [[nodiscard]] bool autoUpdate() const noexcept { return m_state.autoUpdate; }

    [[nodiscard]] int serveCount() const noexcept { return m_state.serveItems.size(); }
    [[nodiscard]] bool hasFunnel() const noexcept;
    [[nodiscard]] QVariantList serveItems() const;
    [[nodiscard]] QVariantList peers() const;
    [[nodiscard]] QVariantList health() const { return m_state.health; }
    [[nodiscard]] QVariantList services() const { return m_state.services; }

    [[nodiscard]] bool isBusy() const noexcept { return m_isBusy; }
    [[nodiscard]] bool isRunningNetcheck() const noexcept { return m_isRunningNetcheck; }
    [[nodiscard]] QString pingResult() const { return m_pingResult; }
    [[nodiscard]] QString pingTargetIp() const { return m_pingTargetIp; }
    [[nodiscard]] QString netcheckReport() const { return m_netcheckReport; }

    [[nodiscard]] bool running() const noexcept { return m_running; }
    void setRunning(bool run);

    [[nodiscard]] int interval() const noexcept { return m_interval; }
    void setInterval(int ms);

    // QML Action Invokers
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void runAction(const QVariantList &args, const QString &successMsg = QString());
    Q_INVOKABLE void ping(const QString &ip);
    Q_INVOKABLE void netcheck();

    // Direct typed helpers
    Q_INVOKABLE void setUp(bool up);
    Q_INVOKABLE void setSSH(bool enable);
    Q_INVOKABLE void setShieldsUp(bool enable);
    Q_INVOKABLE void setWebClient(bool enable);
    Q_INVOKABLE void setAdvertiseExitNode(bool enable);

    Q_INVOKABLE void serveStart(const QString &target,
                                const QString &mode = QStringLiteral("serve"),
                                const QString &port = QStringLiteral("443"),
                                const QString &path = QStringLiteral("/"));
    Q_INVOKABLE void serveStop(const QString &port = QStringLiteral("443"),
                               const QString &path = QString());
    Q_INVOKABLE void funnelToggle(const QString &port,
                                  const QString &target,
                                  bool isFunnel,
                                  const QString &path = QStringLiteral("/"));
    Q_INVOKABLE void serveReset();

    Q_INVOKABLE void copy(const QString &text);
    Q_INVOKABLE void openUrl(const QString &url);

signals:
    void stateChanged();
    void busyChanged();
    void pingFinished(bool ok, const QString &targetIp, const QString &latency);
    void netcheckStatusChanged();
    void actionCompleted(bool ok, const QString &output, const QString &error, const QString &successMsg);
    void runningChanged();
    void intervalChanged();

    // Internal signals routed to worker
    void requestSample();
    void requestAction(const QVariantList &args, const QString &successMsg);
    void requestPing(const QString &ip);
    void requestNetcheck();

private slots:
    void onStateChanged(const qs::plugins::TailscaleState &state);
    void onActionFinished(bool ok, const QString &output, const QString &error, const QString &successMsg);
    void onPingFinished(bool ok, const QString &targetIp, const QString &latency, const QString &output, const QString &error);
    void onNetcheckFinished(bool ok, const QString &report, const QString &error);

private:
    QThread m_thread;
    TailscaleWorker *m_worker{nullptr};

    TailscaleState m_state;
    QVariantMap m_cachedMap;

    bool m_running{true};
    int m_interval{5000};
    bool m_isBusy{false};
    bool m_isRunningNetcheck{false};
    QString m_pingResult;
    QString m_pingTargetIp;
    QString m_netcheckReport;
};

} // namespace qs::plugins
