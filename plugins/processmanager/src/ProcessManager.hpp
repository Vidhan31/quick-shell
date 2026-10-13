#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QThread>
#include <QtQml/qqmlregistration.h>

#include <vector>
#include <string>
#include <chrono>
#include <mutex>
#include <condition_variable>
#include <memory>
#include <atomic>

namespace qs::plugins {

struct ProcInfo {
    int pid{0};
    int ppid{0};
    int rootPid{0};
    char state{'R'};
    unsigned long long rssKb{0};
    std::string comm;
    std::string cmdline;
    QString name;
    QString nameLower;
    QString cmdlineLower;
    int childCount{1};
};

struct SvcInfo {
    QString name;
    QString nameLower;
    QString description;
    QString descriptionLower;
    QString activeState;
    QString subState;
    bool isUser{true};
};

class ProcessManager;

class ProcessWorker : public QObject {
    Q_OBJECT

public:
    explicit ProcessWorker(long pageSizeKb, ProcessManager *manager, QObject *parent = nullptr);
    ~ProcessWorker() override = default;

public slots:
    void doRefreshProcesses();
    void doRefreshServices();
    void doRefreshAll();

private:
    long m_pageSizeKb{4};
    ProcessManager *m_manager{nullptr};

    std::vector<ProcInfo> scanProcFS();
    std::vector<SvcInfo> scanServicesDBus();
};

class ProcessManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(ProcessManager)

    friend class ProcessWorker;

public:
    explicit ProcessManager(QObject *parent = nullptr);
    ~ProcessManager() override;

    Q_INVOKABLE bool isKillQuery(const QString &raw) const;
    Q_INVOKABLE QString searchTerm(const QString &raw) const;
    Q_INVOKABLE int parseSignalFlag(const QString &raw) const;
    Q_INVOKABLE QVariantList search(const QString &term, int explicitSignal = 0, int maxResults = 50);
    Q_INVOKABLE QVariantMap sendSignal(int pid, int signal = 15, bool killTree = true);
    Q_INVOKABLE QVariantMap controlService(const QString &unitName, const QString &action, int signal = 15, bool isUser = true);
    Q_INVOKABLE void invalidateCache();

    void scanProcesses(std::vector<ProcInfo> &outProcs, bool forceFresh = false);
    void scanServices(std::vector<SvcInfo> &outServices, bool forceFresh = false);

signals:
    void cacheRefreshed();

private slots:
    void onSystemdUnitsChanged();

private:
    void triggerProcessRefresh();
    void triggerServiceRefresh();
    void updateCachedProcesses(std::vector<ProcInfo> &&procs);
    void updateCachedServices(std::vector<SvcInfo> &&services);

    long m_pageSizeKb{4};

    QThread m_thread;
    ProcessWorker *m_worker{nullptr};

    mutable std::mutex m_cacheMutex;
    std::condition_variable m_initCv;

    std::shared_ptr<const std::vector<ProcInfo>> m_cachedProcs;
    std::chrono::steady_clock::time_point m_procsTimestamp;
    std::atomic<bool> m_procsDirty{true};
    std::atomic<bool> m_procRefreshPending{false};

    std::shared_ptr<const std::vector<SvcInfo>> m_cachedServices;
    std::chrono::steady_clock::time_point m_servicesTimestamp;
    std::atomic<bool> m_servicesDirty{true};
    std::atomic<bool> m_servicesRefreshPending{false};

    static QString signalName(int sig);
};

} // namespace qs::plugins
