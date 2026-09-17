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
#include <unordered_map>
#include <algorithm>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <atomic>
#include <functional>

namespace qs::plugins {

class SimpleThreadPool {
public:
    explicit SimpleThreadPool(size_t numThreads = 6) : m_stop(false) {
        for (size_t i = 0; i < numThreads; ++i) {
            m_workers.emplace_back([this] {
                while (true) {
                    std::function<void()> task;
                    {
                        std::unique_lock<std::mutex> lock(m_queueMutex);
                        m_cv.wait(lock, [this] { return m_stop || !m_tasks.empty(); });
                        if (m_stop && m_tasks.empty()) return;
                        task = std::move(m_tasks.front());
                        m_tasks.pop();
                    }
                    task();
                }
            });
        }
    }

    ~SimpleThreadPool() {
        {
            std::unique_lock<std::mutex> lock(m_queueMutex);
            m_stop = true;
        }
        m_cv.notify_all();
        for (std::thread &worker : m_workers) {
            if (worker.joinable()) worker.join();
        }
    }

    void enqueue(std::function<void()> task) {
        {
            std::unique_lock<std::mutex> lock(m_queueMutex);
            m_tasks.push(std::move(task));
        }
        m_cv.notify_one();
    }

private:
    std::vector<std::thread> m_workers;
    std::queue<std::function<void()>> m_tasks;
    std::mutex m_queueMutex;
    std::condition_variable m_cv;
    bool m_stop;
};

static inline const char* skip_space(const char *p) {
    while (*p == ' ') ++p;
    return p;
}

static inline const char* skip_field(const char *p) {
    while (*p && *p != ' ') ++p;
    return skip_space(p);
}

static inline unsigned long long parse_u64(const char*& p) {
    unsigned long long val = 0;
    while (*p >= '0' && *p <= '9') {
        val = val * 10 + (*p++ - '0');
    }
    return val;
}

static inline QString formatRssString(double kb) {
    if (kb <= 0.0) return QStringLiteral("0K");
    if (kb < 1024.0) return QString::number(qRound(kb)) + QStringLiteral("K");
    if (kb < 1024.0 * 1024.0) return QString::number(kb / 1024.0, 'f', 1) + QStringLiteral("M");
    return QString::number(kb / (1024.0 * 1024.0), 'f', 2) + QStringLiteral("G");
}

SamplerWorker::SamplerWorker(int intervalMs, int candidateCount, QObject *parent)
    : QObject(parent)
    , m_intervalMs(intervalMs)
    , m_candidateCount(std::clamp(candidateCount, 16, 32))
{
    long sz = sysconf(_SC_PAGESIZE);
    m_pageSizeKb = (sz > 0) ? (sz / 1024) : 4;
    m_nCpu = sysconf(_SC_NPROCESSORS_ONLN);
    if (m_nCpu <= 0) {
        m_nCpu = static_cast<long>(std::thread::hardware_concurrency());
        if (m_nCpu <= 0) m_nCpu = 1;
    }

    m_memTotalKb = readMemTotalKb();

    // Initialize 6 worker threads for parallel PSS resolution on multi-core Ryzen
    size_t poolWorkers = std::clamp<size_t>(m_nCpu > 0 ? static_cast<size_t>(m_nCpu) : 4, 2, 6);
    m_pool = std::make_unique<SimpleThreadPool>(poolWorkers);

    m_rawProcs.reserve(512);
    m_pidToIndex.reserve(512);
    m_prevJiffies.reserve(512);
    m_currJiffies.reserve(512);
    m_groups.reserve(256);
    m_groupLookup.reserve(256);
    m_groupIndices.reserve(256);
    m_items.reserve(256);
}

SamplerWorker::~SamplerWorker() = default;

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

void SamplerWorker::setCandidateCount(int candidateCount) {
    m_candidateCount = std::clamp(candidateCount, 16, 32);
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

    const char *p = buf + 4;
    p = skip_space(p);
    unsigned long long sum = 0;
    for (int i = 0; i < 8; ++i) {
        sum += parse_u64(p);
        p = skip_space(p);
    }
    return sum;
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
    if (m_memTotalKb <= 1) {
        m_memTotalKb = readMemTotalKb();
    }
    unsigned long long totalJiffies = readTotalJiffies();
    unsigned long long deltaTotalJiffies = (totalJiffies > m_prevTotalJiffies && m_prevTotalJiffies > 0)
                                              ? (totalJiffies - m_prevTotalJiffies)
                                              : 0;

    DIR *procDir = opendir("/proc");
    if (!procDir) return;
    int procFd = dirfd(procDir);

    m_rawProcs.clear();
    m_pidToIndex.clear();
    m_currJiffies.clear();

    char statBuf[1024];
    char pathBuf[64];

    struct dirent *entry;
    while ((entry = readdir(procDir)) != nullptr) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
        int pid = 0;
        const char *np = entry->d_name;
        while (*np >= '0' && *np <= '9') {
            pid = pid * 10 + (*np++ - '0');
        }
        if (pid <= 0) continue;

        snprintf(pathBuf, sizeof(pathBuf), "%d/stat", pid);
        int statFd = openat(procFd, pathBuf, O_RDONLY);
        if (statFd < 0) continue;

        ssize_t statRead = read(statFd, statBuf, sizeof(statBuf) - 1);
        close(statFd);
        if (statRead <= 0) continue;
        statBuf[statRead] = '\0';

        char *openParen = strchr(statBuf, '(');
        char *closeParen = strrchr(statBuf, ')');
        if (!openParen || !closeParen || closeParen <= openParen) continue;

        RawProc proc;
        proc.pid = pid;

        size_t commLen = closeParen - openParen - 1;
        if (commLen > 15) commLen = 15;
        memcpy(proc.comm, openParen + 1, commLen);
        proc.comm[commLen] = '\0';

        const char *p = closeParen + 2;
        p = skip_field(p); // skip state

        proc.ppid = static_cast<int>(parse_u64(p));
        p = skip_space(p);

        // Skip 9 fields (5 to 13)
        for (int i = 0; i < 9; ++i) {
            p = skip_field(p);
        }

        unsigned long long utime = parse_u64(p);
        p = skip_space(p);

        unsigned long long stime = parse_u64(p);
        p = skip_space(p);

        // Skip 8 fields (16 to 23)
        for (int i = 0; i < 8; ++i) {
            p = skip_field(p);
        }

        // Field 24: rss (pages)
        unsigned long long rssPages = parse_u64(p);
        proc.rssPagesKb = rssPages * static_cast<unsigned long long>(m_pageSizeKb);
        proc.finalMemKb = proc.rssPagesKb;

        unsigned long long procJiffies = utime + stime;
        proc.jiffies = procJiffies;
        unsigned long long cpuDelta = 0;
        if (deltaTotalJiffies > 0) {
            auto itPrev = m_prevJiffies.find(pid);
            if (itPrev != m_prevJiffies.end() && procJiffies >= itPrev->second) {
                cpuDelta = procJiffies - itPrev->second;
            }
        }
        proc.cpuDelta = cpuDelta;

        m_currJiffies[pid] = procJiffies;
        m_pidToIndex[pid] = static_cast<int>(m_rawProcs.size());
        m_rawProcs.push_back(proc);
    }

    m_prevTotalJiffies = totalJiffies;
    m_prevJiffies = std::move(m_currJiffies);

    auto get_root_fast = [&](int startPid) -> int {
        int curr = startPid;
        int depth = 0;
        while (depth++ < 32) {
            auto it = m_pidToIndex.find(curr);
            if (it == m_pidToIndex.end()) break;
            const auto &p = m_rawProcs[it->second];
            if (p.ppid <= 1) break;

            auto itPar = m_pidToIndex.find(p.ppid);
            if (itPar == m_pidToIndex.end()) break;
            const auto &parProc = m_rawProcs[itPar->second];

            if (strcmp(parProc.comm, "systemd") == 0) break;
            if (strcmp(parProc.comm, "bash") == 0 ||
                strcmp(parProc.comm, "zsh") == 0 ||
                strcmp(parProc.comm, "fish") == 0 ||
                strcmp(parProc.comm, "sh") == 0) break;

            curr = p.ppid;
        }
        return curr;
    };

    m_groups.clear();
    m_groupLookup.clear();
    for (auto &proc : m_rawProcs) {
        int r = get_root_fast(proc.pid);
        proc.rootPid = r;

        auto it = m_groupLookup.find(r);
        if (it == m_groupLookup.end()) {
            int gIdx = static_cast<int>(m_groups.size());
            m_groupLookup[r] = gIdx;
            NewGroup g;
            g.rootPid = r;
            g.rssUpperBound = proc.rssPagesKb;
            g.cpuDelta = proc.cpuDelta;
            g.count = 1;
            m_groups.push_back(g);
        } else {
            auto &g = m_groups[it->second];
            g.rssUpperBound += proc.rssPagesKb;
            g.cpuDelta += proc.cpuDelta;
            g.count++;
        }
    }

    m_groupIndices.resize(m_groups.size());
    for (size_t i = 0; i < m_groups.size(); ++i) {
        m_groupIndices[i] = static_cast<int>(i);
    }
    std::sort(m_groupIndices.begin(), m_groupIndices.end(), [&](int a, int b) {
        return m_groups[a].rssUpperBound > m_groups[b].rssUpperBound;
    });

    std::vector<int> nextMember(m_rawProcs.size(), -1);
    std::vector<int> groupHead(m_groups.size(), -1);
    for (size_t i = 0; i < m_rawProcs.size(); ++i) {
        int gIdx = m_groupLookup[m_rawProcs[i].rootPid];
        nextMember[i] = groupHead[gIdx];
        groupHead[gIdx] = static_cast<int>(i);
    }

    std::vector<int> groupsToResolve;
    groupsToResolve.reserve(32);

    size_t candidateN = std::min<size_t>(static_cast<size_t>(m_candidateCount), m_groupIndices.size());
    for (size_t i = 0; i < candidateN; ++i) {
        groupsToResolve.push_back(m_groupIndices[i]);
    }

    std::vector<int> procIndicesToResolve;
    procIndicesToResolve.reserve(128);

    for (int gIdx : groupsToResolve) {
        m_groups[gIdx].pssResolved = true;
        int pIdx = groupHead[gIdx];
        while (pIdx != -1) {
            procIndicesToResolve.push_back(pIdx);
            pIdx = nextMember[pIdx];
        }
    }

    if (!procIndicesToResolve.empty()) {
        std::atomic<int> remaining(static_cast<int>(procIndicesToResolve.size()));
        std::mutex doneMutex;
        std::condition_variable doneCv;

        for (int pIdx : procIndicesToResolve) {
            m_pool->enqueue([&, pIdx, procFd] {
                char pbuf[64];
                snprintf(pbuf, sizeof(pbuf), "%d/smaps_rollup", m_rawProcs[pIdx].pid);
                int smapsFd = openat(procFd, pbuf, O_RDONLY);
                if (smapsFd >= 0) {
                    char smapsBuf[384];
                    ssize_t sn = read(smapsFd, smapsBuf, sizeof(smapsBuf) - 1);
                    close(smapsFd);
                    if (sn > 0) {
                        smapsBuf[sn] = '\0';
                        const char *pssPtr = strstr(smapsBuf, "\nPss:");
                        if (pssPtr) {
                            m_rawProcs[pIdx].finalMemKb = std::strtoull(pssPtr + 5, nullptr, 10);
                        }
                    }
                }
                if (--remaining == 0) {
                    std::unique_lock<std::mutex> lk(doneMutex);
                    doneCv.notify_one();
                }
            });
        }

        {
            std::unique_lock<std::mutex> lk(doneMutex);
            doneCv.wait(lk, [&] { return remaining.load() == 0; });
        }
    }

    for (int gIdx : groupsToResolve) {
        auto &g = m_groups[gIdx];
        g.actualMem = 0;
        g.maxChildMem = 0;
        g.maxChildPid = 0;
        g.maxChildComm = nullptr;

        int pIdx = groupHead[gIdx];
        while (pIdx != -1) {
            const auto &proc = m_rawProcs[pIdx];
            g.actualMem += proc.finalMemKb;
            if (g.maxChildComm == nullptr || proc.finalMemKb >= g.maxChildMem) {
                g.maxChildMem = proc.finalMemKb;
                g.maxChildComm = proc.comm;
                g.maxChildPid = proc.pid;
            }
            pIdx = nextMember[pIdx];
        }
    }

    closedir(procDir);

    m_items.clear();
    for (const auto &g : m_groups) {
        if (!g.pssResolved) continue;
        double memPct = (m_memTotalKb > 0) ? (100.0 * static_cast<double>(g.actualMem) / static_cast<double>(m_memTotalKb)) : 0.0;
        double cpuPct = (deltaTotalJiffies > 0) ? (100.0 * static_cast<double>(g.cpuDelta) * static_cast<double>(m_nCpu) / static_cast<double>(deltaTotalJiffies)) : 0.0;

        ProcessItem item;
        item.name = g.maxChildComm ? g.maxChildComm : "";
        item.mem = memPct;
        item.cpu = cpuPct;
        item.rss = g.actualMem;
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
    m_worker = new SamplerWorker(m_interval, m_candidateCount);
    m_worker->moveToThread(&m_workerThread);

    connect(&m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &ProcessMonitor::requestStart, m_worker, &SamplerWorker::start);
    connect(this, &ProcessMonitor::requestStop, m_worker, &SamplerWorker::stop);
    connect(this, &ProcessMonitor::requestSetInterval, m_worker, &SamplerWorker::setInterval);
    connect(this, &ProcessMonitor::requestSetCandidateCount, m_worker, &SamplerWorker::setCandidateCount);
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

void ProcessMonitor::setCandidateCount(int candidateCount) {
    int clamped = std::clamp(candidateCount, 16, 32);
    if (m_candidateCount == clamped) return;
    m_candidateCount = clamped;
    emit candidateCountChanged();
    emit requestSetCandidateCount(m_candidateCount);
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
