#include "ProcessMonitor.hpp"

#include <QTime>
#include <QVariantMap>

#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <unordered_set>
#include <algorithm>
#include <thread>

namespace qs::plugins {

static inline const char* skip_space(const char *p) {
    while (*p == ' ') ++p;
    return p;
}

static inline const char* skip_field(const char *p) {
    while (*p && *p != ' ') ++p;
    return skip_space(p);
}

static inline QString formatRssString(double kb) {
    if (kb <= 0.0) return QStringLiteral("0K");
    if (kb < 1024.0) return QString::number(qRound(kb)) + QStringLiteral("K");
    if (kb < 1024.0 * 1024.0) return QString::number(kb / 1024.0, 'f', 1) + QStringLiteral("M");
    return QString::number(kb / (1024.0 * 1024.0), 'f', 2) + QStringLiteral("G");
}

SamplerWorker::SamplerWorker(int intervalMs, QObject *parent)
    : QObject(parent)
    , m_intervalMs(intervalMs)
{
    long sz = sysconf(_SC_PAGESIZE);
    m_pageSizeKb = (sz > 0) ? (sz / 1024) : 4;
    m_nCpu = sysconf(_SC_NPROCESSORS_ONLN);
    if (m_nCpu <= 0) {
        m_nCpu = static_cast<long>(std::thread::hardware_concurrency());
        if (m_nCpu <= 0) m_nCpu = 1;
    }

    m_pids.reserve(512);
    m_parentMap.reserve(512);
    m_commMap.reserve(512);
    m_currentProcJiffies.reserve(512);
    m_cpuDeltaMap.reserve(512);
    m_memMap.reserve(512);
    m_groups.reserve(256);
    m_items.reserve(256);
}

void SamplerWorker::start() {
    if (!m_timer) {
        m_timer = new QTimer(this);
        connect(m_timer, &QTimer::timeout, this, &SamplerWorker::sample);
    }
    if (!m_timer->isActive()) {
        m_timer->start(m_intervalMs);
        sample(); // initial sample
    }
}

void SamplerWorker::stop() {
    if (m_timer && m_timer->isActive()) {
        m_timer->stop();
    }
}

void SamplerWorker::setInterval(int intervalMs) {
    m_intervalMs = intervalMs;
    if (m_timer && m_timer->isActive()) {
        m_timer->setInterval(m_intervalMs);
    }
}

unsigned long long SamplerWorker::readTotalJiffies() {
    int fd = open("/proc/stat", O_RDONLY);
    if (fd < 0) return 0;

    char buf[512];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return 0;
    buf[n] = '\0';

    if (strncmp(buf, "cpu ", 4) != 0) return 0;

    unsigned long long user = 0, nice = 0, system = 0, idle = 0, iowait = 0, irq = 0, softirq = 0, steal = 0;
    sscanf(buf + 4, "%llu %llu %llu %llu %llu %llu %llu %llu",
           &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal);
    return user + nice + system + idle + iowait + irq + softirq + steal;
}

long SamplerWorker::readMemTotalKb() {
    int fd = open("/proc/meminfo", O_RDONLY);
    if (fd < 0) return 1;

    char buf[512];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return 1;
    buf[n] = '\0';

    const char *p = strstr(buf, "MemTotal:");
    if (!p) return 1;

    long memTotal = 0;
    sscanf(p + 9, "%ld", &memTotal);
    return (memTotal > 0) ? memTotal : 1;
}

void SamplerWorker::sample() {
    long memTotalKb = readMemTotalKb();
    unsigned long long totalJiffies = readTotalJiffies();
    unsigned long long deltaTotalJiffies = (totalJiffies > m_prevTotalJiffies && m_prevTotalJiffies > 0)
                                              ? (totalJiffies - m_prevTotalJiffies)
                                              : 0;

    DIR *procDir = opendir("/proc");
    if (!procDir) return;
    int procFd = dirfd(procDir);

    m_pids.clear();
    m_parentMap.clear();
    m_commMap.clear();
    m_currentProcJiffies.clear();
    m_cpuDeltaMap.clear();
    m_memMap.clear();

    char pathBuf[270];
    char statBuf[1024];

    struct dirent *entry;
    while ((entry = readdir(procDir)) != nullptr) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
        int pid = std::atoi(entry->d_name);
        if (pid <= 0) continue;

        // Fast openat relative to /proc
        snprintf(pathBuf, sizeof(pathBuf), "%s/stat", entry->d_name);
        int statFd = openat(procFd, pathBuf, O_RDONLY);
        if (statFd < 0) continue;

        ssize_t statRead = read(statFd, statBuf, sizeof(statBuf) - 1);
        close(statFd);
        if (statRead <= 0) continue;
        statBuf[statRead] = '\0';

        char *openParen = strchr(statBuf, '(');
        char *closeParen = strrchr(statBuf, ')');
        if (!openParen || !closeParen || closeParen <= openParen) continue;

        std::string comm(openParen + 1, closeParen - openParen - 1);

        // Fast pointer walk parsing fields from /proc/[pid]/stat
        const char *p = closeParen + 2; // skip ") "
        p = skip_field(p); // skip state (field 3)

        int ppid = std::atoi(p);
        p = skip_field(p); // skip ppid (field 4)

        // Skip 9 fields (5 to 13: pgrp, session, tty_nr, tpgid, flags, minflt, cminflt, majflt, cmajflt)
        for (int i = 0; i < 9; ++i) {
            p = skip_field(p);
        }

        // Field 14: utime
        char *endPtr = nullptr;
        unsigned long long utime = std::strtoull(p, &endPtr, 10);
        p = skip_space(endPtr);

        // Field 15: stime
        unsigned long long stime = std::strtoull(p, &endPtr, 10);
        p = skip_space(endPtr);

        // Skip 8 fields (16 to 23: cutime, cstime, priority, nice, num_threads, itrealvalue, starttime, vsize)
        for (int i = 0; i < 8; ++i) {
            p = skip_field(p);
        }

        // Field 24: rss (resident pages) fallback
        long long rssPages = std::strtoll(p, nullptr, 10);
        if (rssPages < 0) rssPages = 0;
        unsigned long long memKb = static_cast<unsigned long long>(rssPages) * static_cast<unsigned long long>(m_pageSizeKb);

        // Read proportional set size (PSS) from /proc/[pid]/smaps_rollup
        snprintf(pathBuf, sizeof(pathBuf), "%s/smaps_rollup", entry->d_name);
        int smapsFd = openat(procFd, pathBuf, O_RDONLY);
        if (smapsFd >= 0) {
            char smapsBuf[384];
            ssize_t sn = read(smapsFd, smapsBuf, sizeof(smapsBuf) - 1);
            close(smapsFd);
            if (sn > 0) {
                smapsBuf[sn] = '\0';
                const char *pssPtr = strstr(smapsBuf, "\nPss:");
                if (pssPtr) {
                    memKb = std::strtoull(pssPtr + 5, nullptr, 10);
                }
            }
        }

        unsigned long long procJiffies = utime + stime;
        unsigned long long cpuDelta = 0;
        if (deltaTotalJiffies > 0) {
            auto itPrev = m_prevProcJiffies.find(pid);
            if (itPrev != m_prevProcJiffies.end() && procJiffies >= itPrev->second) {
                cpuDelta = procJiffies - itPrev->second;
            }
        }

        m_pids.push_back(pid);
        m_parentMap[pid] = ppid;
        m_commMap[pid] = std::move(comm);
        m_currentProcJiffies[pid] = procJiffies;
        m_cpuDeltaMap[pid] = cpuDelta;
        m_memMap[pid] = memKb;
    }
    closedir(procDir);

    m_prevTotalJiffies = totalJiffies;
    m_prevProcJiffies = m_currentProcJiffies;

    if (deltaTotalJiffies == 0) {
        return;
    }

    auto get_root = [&](int p) -> int {
        int curr = p;
        std::unordered_set<int> visited;
        visited.insert(curr);
        while (true) {
            auto itP = m_parentMap.find(curr);
            if (itP == m_parentMap.end() || itP->second <= 1) break;
            int par = itP->second;
            auto itC = m_commMap.find(par);
            if (itC != m_commMap.end() && itC->second == "systemd") break;
            if (visited.count(par)) break;
            if (itC != m_commMap.end()) {
                const std::string &comm = itC->second;
                if (comm == "bash" || comm == "zsh" || comm == "fish" || comm == "sh") break;
            }
            curr = par;
            visited.insert(curr);
        }
        return curr;
    };

    m_groups.clear();
    for (int p : m_pids) {
        int r = get_root(p);
        auto &g = m_groups[r];
        g.rss += m_memMap[p];
        g.cpuDelta += m_cpuDeltaMap[p];
        g.count++;
        if (g.maxChildName.empty() || m_memMap[p] >= g.maxChildRss) {
            g.maxChildRss = m_memMap[p];
            g.maxChildName = m_commMap[p];
            g.maxChildPid = p;
        }
    }

    m_items.clear();
    for (const auto &[rootPid, g] : m_groups) {
        double memPct = (memTotalKb > 0) ? (100.0 * static_cast<double>(g.rss) / static_cast<double>(memTotalKb)) : 0.0;
        double cpuPct = (deltaTotalJiffies > 0) ? (100.0 * static_cast<double>(g.cpuDelta) * static_cast<double>(m_nCpu) / static_cast<double>(deltaTotalJiffies)) : 0.0;

        ProcessItem item;
        item.name = g.maxChildName;
        item.mem = memPct;
        item.cpu = cpuPct;
        item.rss = g.rss;
        item.count = g.count;
        item.mpid = g.maxChildPid;
        m_items.push_back(std::move(item));
    }

    size_t topN = std::min<size_t>(10, m_items.size());
    std::partial_sort(m_items.begin(), m_items.begin() + topN, m_items.end(),
                      [](const ProcessItem &a, const ProcessItem &b) {
                          return a.mem > b.mem;
                      });

    QVariantList outList;
    outList.reserve(static_cast<qsizetype>(topN));
    double maxMem = 1.0;

    for (size_t i = 0; i < topN; ++i) {
        const auto &item = m_items[i];
        if (i == 0 && item.mem > 0) {
            maxMem = item.mem;
        }
        QString formattedRss = formatRssString(static_cast<double>(item.rss));
        QString barLabel = formattedRss + QStringLiteral(" (") + QString::number(item.mem, 'f', 0) + QStringLiteral("%)");

        QVariantMap map;
        map[QStringLiteral("name")] = QString::fromUtf8(item.name.data(), static_cast<qsizetype>(item.name.size()));
        map[QStringLiteral("mem")] = item.mem;
        map[QStringLiteral("cpu")] = item.cpu;
        map[QStringLiteral("rss")] = static_cast<qint64>(item.rss);
        map[QStringLiteral("formattedRss")] = formattedRss;
        map[QStringLiteral("barLabel")] = barLabel;
        map[QStringLiteral("count")] = item.count;
        map[QStringLiteral("mpid")] = item.mpid;
        outList.append(map);
    }

    QString updatedAt = QTime::currentTime().toString(QStringLiteral("hh:mm:ss"));
    emit dataReady(outList, maxMem, updatedAt);
}

// ---------------- ProcessMonitor ----------------

ProcessMonitor::ProcessMonitor(QObject *parent)
    : QObject(parent)
    , m_running(false)
{
    m_worker = new SamplerWorker(m_interval);
    m_worker->moveToThread(&m_workerThread);

    connect(&m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &ProcessMonitor::requestStart, m_worker, &SamplerWorker::start);
    connect(this, &ProcessMonitor::requestStop, m_worker, &SamplerWorker::stop);
    connect(this, &ProcessMonitor::requestSetInterval, m_worker, &SamplerWorker::setInterval);
    connect(this, &ProcessMonitor::requestSample, m_worker, &SamplerWorker::sample);

    connect(m_worker, &SamplerWorker::dataReady, this, &ProcessMonitor::onDataReady, Qt::QueuedConnection);

    m_workerThread.start();

    if (m_running) {
        emit requestStart();
    }
}

ProcessMonitor::~ProcessMonitor() {
    emit requestStop();
    m_workerThread.quit();
    m_workerThread.wait();
}

void ProcessMonitor::setRunning(bool running) {
    if (m_running == running) return;
    m_running = running;
    emit runningChanged();

    if (m_running) {
        emit requestStart();
    } else {
        emit requestStop();
    }
}

void ProcessMonitor::setInterval(int interval) {
    if (m_interval == interval || interval <= 0) return;
    m_interval = interval;
    emit intervalChanged();
    emit requestSetInterval(m_interval);
}

void ProcessMonitor::refresh() {
    emit requestSample();
}

void ProcessMonitor::onDataReady(const QVariantList &processes, double maxMem, const QString &updatedAt) {
    m_processes = processes;
    m_maxMem = maxMem;
    m_updatedAt = updatedAt;
    emit processesChanged();
}

} // namespace qs::plugins
