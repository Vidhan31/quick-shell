#pragma once

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QThread>
#include <QTimer>
#include <QtQml/qqmlregistration.h>
#include <unordered_map>
#include <vector>
#include <string>

namespace qs::plugins {

struct GroupInfo {
    unsigned long long rss{0};
    unsigned long long cpuDelta{0};
    int count{0};
    unsigned long long maxChildRss{0};
    std::string maxChildName;
    int maxChildPid{0};
};

struct ProcessItem {
    std::string name;
    double mem{0.0};
    double cpu{0.0};
    unsigned long long rss{0};
    int count{0};
    int mpid{0};
};

class SamplerWorker : public QObject {
    Q_OBJECT

public:
    explicit SamplerWorker(int intervalMs = 2000, QObject *parent = nullptr);
    ~SamplerWorker() override = default;

public slots:
    void start();
    void stop();
    void setInterval(int intervalMs);
    void sample();

signals:
    void dataReady(const QVariantList &processes, double maxMem, const QString &updatedAt);

private:
    int m_intervalMs;
    QTimer *m_timer{nullptr};
    long m_pageSizeKb{4};
    long m_nCpu{1};
    unsigned long long m_prevTotalJiffies{0};
    std::unordered_map<int, unsigned long long> m_prevProcJiffies;

    // Persistent containers to avoid heap reallocations
    std::vector<int> m_pids;
    std::unordered_map<int, int> m_parentMap;
    std::unordered_map<int, std::string> m_commMap;
    std::unordered_map<int, unsigned long long> m_currentProcJiffies;
    std::unordered_map<int, unsigned long long> m_cpuDeltaMap;
    std::unordered_map<int, unsigned long long> m_memMap;
    std::unordered_map<int, GroupInfo> m_groups;
    std::vector<ProcessItem> m_items;

    unsigned long long readTotalJiffies();
    long readMemTotalKb();
};

class ProcessMonitor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(ProcessMonitor)

    Q_PROPERTY(QVariantList processes READ processes NOTIFY processesChanged)
    Q_PROPERTY(double maxMem READ maxMem NOTIFY processesChanged)
    Q_PROPERTY(QString updatedAt READ updatedAt NOTIFY processesChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)

public:
    explicit ProcessMonitor(QObject *parent = nullptr);
    ~ProcessMonitor() override;

    QVariantList processes() const { return m_processes; }
    double maxMem() const { return m_maxMem; }
    QString updatedAt() const { return m_updatedAt; }
    bool running() const { return m_running; }
    int interval() const { return m_interval; }

    void setRunning(bool running);
    void setInterval(int interval);

    Q_INVOKABLE void refresh();

signals:
    void processesChanged();
    void runningChanged();
    void intervalChanged();

    // Internal signals to worker thread
    void requestStart();
    void requestStop();
    void requestSetInterval(int interval);
    void requestSample();

private slots:
    void onDataReady(const QVariantList &processes, double maxMem, const QString &updatedAt);

private:
    QVariantList m_processes;
    double m_maxMem{1.0};
    QString m_updatedAt;
    bool m_running{false};
    int m_interval{2000};

    QThread m_workerThread;
    SamplerWorker *m_worker{nullptr};
};

} // namespace qs::plugins
