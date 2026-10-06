#pragma once

#include "DockerSocketClient.hpp"
#include "DockerState.hpp"

#include <QFileSystemWatcher>
#include <QLocalSocket>
#include <QObject>
#include <QThread>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <memory>

namespace qs::plugins {

// Event-driven worker: one full sample at startup / on demand, then stays
// current by listening to the daemon's GET /events stream. No polling.
class DockerWorker : public QObject {
    Q_OBJECT

public:
    // The client is shared with DockerMonitor so the monitor thread can
    // interrupt an in-flight request during teardown.
    explicit DockerWorker(std::shared_ptr<DockerSocketClient> client, QObject *parent = nullptr);
    ~DockerWorker() override;

public slots:
    void start();
    void stop();
    void sample();
    void refresh();
    void runContainerAction(const QString &action, const QString &id, int timeoutSec);
    void runRemove(const QString &kind, const QString &target, bool force);
    void runPrune(const QString &kind);
    void runFetchLogs(const QString &id, int tail);
    void runProjectAction(const QString &action, const QString &project, int timeoutSec);

signals:
    void stateChanged(const qs::plugins::DockerState &state);
    void actionFinished(bool ok, const QString &output, const QString &error, const QString &context);
    void logsReady(const QString &id, bool ok, const QString &logs, const QString &error);
    void busyChanged(bool busy, const QString &context, const QString &label);

private slots:
    void onEventsConnected();
    void onEventsReadyRead();
    void onEventsError(QLocalSocket::LocalSocketError socketError);
    void onEventsDisconnected();
    void reconnectEvents();
    void onSocketDirectoryChanged(const QString &path);

private:
    void connectEvents();
    void closeEvents();
    void triggerSampleDebounced();
    void setupFsWatcher();
    void closeFsWatcher();
    void setBusy(bool busy, const QString &context = QString(), const QString &label = QString());
    QString containerName(const QString &id) const;

    std::shared_ptr<DockerSocketClient> m_client;
    QFileSystemWatcher *m_fsWatcher{nullptr};
    QLocalSocket *m_eventsSocket{nullptr};
    QByteArray m_eventsBuffer;
    bool m_eventsHeadersParsed{false};
    bool m_eventsConnected{false};
    QTimer *m_reconnectTimer{nullptr};
    QTimer *m_debounceTimer{nullptr};
    QString m_busyContext;
    QString m_busyLabel;
    bool m_isSampling{false};
    bool m_initialized{false};
    DockerState m_lastState;
};

class DockerMonitor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(DockerMonitor)

    Q_PROPERTY(QVariantMap dockerData READ dockerData NOTIFY stateChanged)

    Q_PROPERTY(bool ok READ isOk NOTIFY stateChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY stateChanged)
    Q_PROPERTY(QString serverVersion READ serverVersion NOTIFY stateChanged)
    Q_PROPERTY(QString apiVersion READ apiVersion NOTIFY stateChanged)
    Q_PROPERTY(QString socketPath READ socketPath NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)

    Q_PROPERTY(int runningCount READ runningCount NOTIFY stateChanged)
    Q_PROPERTY(int stoppedCount READ stoppedCount NOTIFY stateChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY stateChanged)
    Q_PROPERTY(int projectCount READ projectCount NOTIFY stateChanged)

    Q_PROPERTY(QVariantList containers READ containers NOTIFY stateChanged)
    Q_PROPERTY(QVariantList projects READ projects NOTIFY stateChanged)
    Q_PROPERTY(QVariantList standalone READ standalone NOTIFY stateChanged)
    Q_PROPERTY(QVariantList images READ images NOTIFY stateChanged)
    Q_PROPERTY(QVariantList volumes READ volumes NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap df READ df NOTIFY stateChanged)
    Q_PROPERTY(QVariantList cleanup READ cleanup NOTIFY stateChanged)
    Q_PROPERTY(QString reclaimSummary READ reclaimSummary NOTIFY stateChanged)

    Q_PROPERTY(bool isBusy READ isBusy NOTIFY busyChanged)
    Q_PROPERTY(QString busyContext READ busyContext NOTIFY busyChanged)
    Q_PROPERTY(QString busyLabel READ busyLabel NOTIFY busyChanged)

    // Lifecycle: running starts the initial sample + /events stream.
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)

    Q_PROPERTY(QString logContainerId READ logContainerId NOTIFY logsReady)
    Q_PROPERTY(QString logText READ logText NOTIFY logsReady)
    Q_PROPERTY(QString logError READ logError NOTIFY logsReady)

public:
    explicit DockerMonitor(QObject *parent = nullptr);
    ~DockerMonitor() override;

    [[nodiscard]] QVariantMap dockerData() const { return m_cachedMap; }

    [[nodiscard]] bool isOk() const noexcept { return m_state.ok; }
    [[nodiscard]] bool isConnected() const noexcept { return m_state.connected; }
    [[nodiscard]] QString serverVersion() const { return m_state.serverVersion; }
    [[nodiscard]] QString apiVersion() const { return m_state.apiVersion; }
    [[nodiscard]] QString socketPath() const { return m_state.socketPath; }
    [[nodiscard]] QString lastError() const { return m_state.error; }

    [[nodiscard]] int runningCount() const noexcept { return m_state.running; }
    [[nodiscard]] int stoppedCount() const noexcept { return m_state.stopped; }
    [[nodiscard]] int totalCount() const noexcept { return static_cast<int>(m_state.containers.size()); }
    [[nodiscard]] int projectCount() const noexcept { return static_cast<int>(m_state.projects.size()); }

    [[nodiscard]] QVariantList containers() const;
    [[nodiscard]] QVariantList projects() const;
    [[nodiscard]] QVariantList standalone() const;
    [[nodiscard]] QVariantList images() const;
    [[nodiscard]] QVariantList volumes() const;
    [[nodiscard]] QVariantMap df() const { return m_state.df; }
    [[nodiscard]] QVariantList cleanup() const { return m_state.cleanup; }
    [[nodiscard]] QString reclaimSummary() const { return m_state.reclaimSummary; }

    [[nodiscard]] bool isBusy() const noexcept { return m_isBusy; }
    [[nodiscard]] QString busyContext() const { return m_busyContext; }
    [[nodiscard]] QString busyLabel() const { return m_busyLabel; }
    [[nodiscard]] QString logContainerId() const { return m_logId; }
    [[nodiscard]] QString logText() const { return m_logText; }
    [[nodiscard]] QString logError() const { return m_logError; }

    [[nodiscard]] bool running() const noexcept { return m_running; }
    void setRunning(bool run);

    // QML invokers — all async via worker thread
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void startContainer(const QString &id);
    Q_INVOKABLE void stopContainer(const QString &id, int timeoutSec = 10);
    Q_INVOKABLE void restartContainer(const QString &id, int timeoutSec = 10);
    Q_INVOKABLE void killContainer(const QString &id);
    Q_INVOKABLE void removeContainer(const QString &id, bool force = false);
    Q_INVOKABLE void removeImage(const QString &name, bool force = false);
    Q_INVOKABLE void removeVolume(const QString &name, bool force = false);
    Q_INVOKABLE void prune(const QString &kind);
    Q_INVOKABLE void fetchLogs(const QString &id, int tail = 200);
    Q_INVOKABLE void startProject(const QString &project);
    Q_INVOKABLE void stopProject(const QString &project, int timeoutSec = 10);
    Q_INVOKABLE void openPath(const QString &path);

signals:
    void stateChanged();
    void busyChanged();
    void actionCompleted(bool ok, const QString &output, const QString &error, const QString &context);
    void logsReady();
    void runningChanged();

    // Internal -> worker
    void requestSample();
    void requestContainerAction(const QString &action, const QString &id, int timeoutSec);
    void requestRemove(const QString &kind, const QString &target, bool force);
    void requestPrune(const QString &kind);
    void requestFetchLogs(const QString &id, int tail);
    void requestProjectAction(const QString &action, const QString &project, int timeoutSec);

private slots:
    void onStateChanged(const qs::plugins::DockerState &state);
    void onActionFinished(bool ok, const QString &output, const QString &error, const QString &context);
    void onLogsReady(const QString &id, bool ok, const QString &logs, const QString &error);
    void onWorkerBusy(bool busy, const QString &context, const QString &label);

private:
    QThread m_thread;
    DockerWorker *m_worker{nullptr};
    std::shared_ptr<DockerSocketClient> m_client;

    DockerState m_state;
    QVariantMap m_cachedMap;

    bool m_running{true};
    bool m_isBusy{false};
    QString m_busyContext;
    QString m_busyLabel;
    QString m_logId;
    QString m_logText;
    QString m_logError;
};

} // namespace qs::plugins
