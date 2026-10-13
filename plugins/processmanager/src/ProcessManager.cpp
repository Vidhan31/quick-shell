#include "ProcessManager.hpp"
#include "ProcessCore.hpp"

#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusReply>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusObjectPath>

#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>

#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <cstring>
#include <cstdio>
#include <cerrno>

namespace qs::plugins {

namespace {

struct UnitDbusRecord {
    QString name;
    QString description;
    QString loadState;
    QString activeState;
    QString subState;
    QString following;
    QDBusObjectPath unitPath;
    quint32 jobId{0};
    QString jobType;
    QDBusObjectPath jobPath;
};

const QDBusArgument &operator>>(const QDBusArgument &arg, UnitDbusRecord &rec) {
    arg.beginStructure();
    arg >> rec.name
        >> rec.description
        >> rec.loadState
        >> rec.activeState
        >> rec.subState
        >> rec.following
        >> rec.unitPath
        >> rec.jobId
        >> rec.jobType
        >> rec.jobPath;
    arg.endStructure();
    return arg;
}

static inline const char *skip_space(const char *p) {
    while (*p == ' ') ++p;
    return p;
}

static inline const char *skip_field(const char *p) {
    while (*p && *p != ' ') ++p;
    return skip_space(p);
}

static inline unsigned long long parse_u64(const char *&p) {
    unsigned long long val = 0;
    while (*p >= '0' && *p <= '9') {
        val = val * 10 + (*p++ - '0');
    }
    return val;
}

} // namespace

ProcessWorker::ProcessWorker(long pageSizeKb, ProcessManager *manager, QObject *parent)
    : QObject(parent)
    , m_pageSizeKb(pageSizeKb)
    , m_manager(manager)
{
}

void ProcessWorker::doRefreshProcesses() {
    auto procs = scanProcFS();
    m_manager->updateCachedProcesses(std::move(procs));
}

void ProcessWorker::doRefreshServices() {
    auto svcs = scanServicesDBus();
    m_manager->updateCachedServices(std::move(svcs));
}

void ProcessWorker::doRefreshAll() {
    doRefreshProcesses();
    doRefreshServices();
}

std::vector<ProcInfo> ProcessWorker::scanProcFS() {
    DIR *dir = opendir("/proc");
    if (!dir) return {};
    int dfd = dirfd(dir);

    std::vector<ProcInfo> raw;
    raw.reserve(512);

    struct dirent *entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
        int pid = std::atoi(entry->d_name);
        if (pid <= 1) continue;

        char statPath[32];
        snprintf(statPath, sizeof(statPath), "%d/stat", pid);
        int fd = openat(dfd, statPath, O_RDONLY | O_CLOEXEC);
        if (fd < 0) continue;

        char buf[1024];
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n <= 0) continue;
        buf[n] = '\0';

        char *openParen = strchr(buf, '(');
        char *closeParen = strrchr(buf, ')');
        if (!openParen || !closeParen || closeParen <= openParen) continue;

        std::string comm(openParen + 1, closeParen - openParen - 1);
        const char *p = skip_space(closeParen + 1);
        if (!*p) continue;
        char state = *p++;
        p = skip_space(p);

        int ppid = static_cast<int>(parse_u64(p)); p = skip_space(p);
        p = skip_field(p); // pgrp
        p = skip_field(p); // session
        p = skip_field(p); // tty_nr
        p = skip_field(p); // tpgid
        unsigned long long flags = parse_u64(p); p = skip_space(p); // flags
        p = skip_field(p); // minflt
        p = skip_field(p); // cminflt
        p = skip_field(p); // majflt
        p = skip_field(p); // cmajflt
        p = skip_field(p); // utime
        p = skip_field(p); // stime
        p = skip_field(p); // cutime
        p = skip_field(p); // cstime
        p = skip_field(p); // priority
        p = skip_field(p); // nice
        p = skip_field(p); // num_threads
        p = skip_field(p); // itrealvalue
        p = skip_field(p); // starttime
        p = skip_field(p); // vsize
        unsigned long long rssPages = parse_u64(p);

        // Kernel threads have PPID 2 or PF_KTHREAD (0x00200000), or zombie
        if (ppid == 2 || (flags & 0x00200000ULL) || state == 'Z') continue;

        ProcInfo info;
        info.pid = pid;
        info.ppid = ppid;
        info.rootPid = pid;
        info.state = state;
        info.rssKb = rssPages * static_cast<unsigned long long>(m_pageSizeKb);
        info.comm = std::move(comm);
        info.childCount = 1;
        raw.push_back(std::move(info));
    }

    std::unordered_map<int, int> pidToIndex;
    pidToIndex.reserve(raw.size());
    for (size_t i = 0; i < raw.size(); ++i) {
        pidToIndex[raw[i].pid] = static_cast<int>(i);
    }

    auto getRootFast = [&](int startPid) -> int {
        auto it = pidToIndex.find(startPid);
        if (it == pidToIndex.end()) return startPid;
        const auto &p = raw[it->second];
        return qs::processcore::getRootFast(p.pid, p.ppid, QString::fromLatin1(p.comm), [&](int ppid) -> std::pair<int, QString> {
            auto itPar = pidToIndex.find(ppid);
            if (itPar == pidToIndex.end()) return {0, QString()};
            const auto &par = raw[itPar->second];
            return {par.ppid, QString::fromLatin1(par.comm)};
        });
    };

    std::vector<ProcInfo> cachedProcs;
    cachedProcs.reserve(raw.size() / 2);
    std::unordered_map<int, size_t> rootMap;
    for (auto &p : raw) {
        int r = getRootFast(p.pid);
        p.rootPid = r;

        auto it = rootMap.find(r);
        if (it == rootMap.end()) {
            rootMap[r] = cachedProcs.size();
            auto itRoot = pidToIndex.find(r);
            const auto &rootProc = (itRoot != pidToIndex.end()) ? raw[itRoot->second] : p;
            ProcInfo group;
            group.pid = r;
            group.ppid = rootProc.ppid;
            group.rootPid = r;
            group.state = rootProc.state;
            group.rssKb = p.rssKb;
            group.comm = rootProc.comm;
            group.childCount = 1;
            cachedProcs.push_back(std::move(group));
        } else {
            auto &group = cachedProcs[it->second];
            group.rssKb += p.rssKb;
            group.childCount++;
            if (p.state == 'T') group.state = 'T';
        }
    }

    for (auto &group : cachedProcs) {
        char cmdPath[32];
        snprintf(cmdPath, sizeof(cmdPath), "%d/cmdline", group.pid);
        int cmdFd = openat(dfd, cmdPath, O_RDONLY | O_CLOEXEC);
        if (cmdFd >= 0) {
            char cmdBuf[512];
            ssize_t cn = read(cmdFd, cmdBuf, sizeof(cmdBuf) - 1);
            close(cmdFd);
            if (cn > 0) {
                for (ssize_t i = 0; i < cn; ++i) {
                    if (cmdBuf[i] == '\0') cmdBuf[i] = ' ';
                }
                cmdBuf[cn] = '\0';
                group.cmdline = cmdBuf;
            }
        }
        if (group.cmdline.empty()) {
            group.cmdline = group.comm;
        }

        group.name = QString::fromUtf8(group.comm.data(), static_cast<qsizetype>(group.comm.size()));
        group.nameLower = group.name.toLower();
        group.cmdlineLower = QString::fromUtf8(group.cmdline.data(), static_cast<qsizetype>(group.cmdline.size())).toLower();
    }
    closedir(dir);

    return cachedProcs;
}

std::vector<SvcInfo> ProcessWorker::scanServicesDBus() {
    std::vector<SvcInfo> services;

    auto queryBus = [&](QDBusConnection conn, bool isUser) {
        if (!conn.isConnected()) return;

        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.systemd1"),
            QStringLiteral("/org/freedesktop/systemd1"),
            QStringLiteral("org.freedesktop.systemd1.Manager"),
            QStringLiteral("ListUnitsByPatterns")
        );
        msg << QStringList{QStringLiteral("active")}
            << QStringList{QStringLiteral("*.service")};

        QDBusMessage reply = conn.call(msg);
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
            return;
        }

        const QDBusArgument arg = reply.arguments().at(0).value<QDBusArgument>();
        arg.beginArray();
        while (!arg.atEnd()) {
            UnitDbusRecord rec;
            arg >> rec;
            if (rec.name.endsWith(QLatin1String(".service"))) {
                SvcInfo s;
                s.name = rec.name;
                QString sName = rec.name;
                if (sName.endsWith(QLatin1String(".service"))) {
                    sName.chop(8);
                }
                s.nameLower = sName.toLower();
                s.description = rec.description;
                s.descriptionLower = rec.description.toLower();
                s.activeState = rec.activeState;
                s.subState = rec.subState;
                s.isUser = isUser;
                services.push_back(std::move(s));
            }
        }
        arg.endArray();
    };

    queryBus(QDBusConnection::sessionBus(), true);
    queryBus(QDBusConnection::systemBus(), false);

    return services;
}

ProcessManager::ProcessManager(QObject *parent)
    : QObject(parent)
{
    long sz = sysconf(_SC_PAGESIZE);
    m_pageSizeKb = (sz > 0) ? (sz / 1024) : 4;

    m_cachedProcs = std::make_shared<std::vector<ProcInfo>>();
    m_cachedServices = std::make_shared<std::vector<SvcInfo>>();

    m_worker = new ProcessWorker(m_pageSizeKb, this);
    m_worker->moveToThread(&m_thread);

    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(&m_thread, &QThread::started, m_worker, &ProcessWorker::doRefreshAll);

    auto connectSystemdSignals = [this](QDBusConnection conn) {
        if (!conn.isConnected()) return;
        QDBusMessage subMsg = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.systemd1"),
            QStringLiteral("/org/freedesktop/systemd1"),
            QStringLiteral("org.freedesktop.systemd1.Manager"),
            QStringLiteral("Subscribe")
        );
        conn.asyncCall(subMsg);

        conn.connect(
            QStringLiteral("org.freedesktop.systemd1"),
            QStringLiteral("/org/freedesktop/systemd1"),
            QStringLiteral("org.freedesktop.systemd1.Manager"),
            QStringLiteral("UnitNew"),
            this, SLOT(onSystemdUnitsChanged())
        );
        conn.connect(
            QStringLiteral("org.freedesktop.systemd1"),
            QStringLiteral("/org/freedesktop/systemd1"),
            QStringLiteral("org.freedesktop.systemd1.Manager"),
            QStringLiteral("UnitRemoved"),
            this, SLOT(onSystemdUnitsChanged())
        );
        conn.connect(
            QStringLiteral("org.freedesktop.systemd1"),
            QStringLiteral("/org/freedesktop/systemd1"),
            QStringLiteral("org.freedesktop.systemd1.Manager"),
            QStringLiteral("JobRemoved"),
            this, SLOT(onSystemdUnitsChanged())
        );
        conn.connect(
            QStringLiteral("org.freedesktop.systemd1"),
            QStringLiteral("/org/freedesktop/systemd1"),
            QStringLiteral("org.freedesktop.systemd1.Manager"),
            QStringLiteral("Reloading"),
            this, SLOT(onSystemdUnitsChanged())
        );
    };

    connectSystemdSignals(QDBusConnection::sessionBus());
    connectSystemdSignals(QDBusConnection::systemBus());

    m_thread.start();
}

ProcessManager::~ProcessManager() {
    m_thread.quit();
    m_thread.wait();
}

void ProcessManager::onSystemdUnitsChanged() {
    m_servicesDirty.store(true);
    triggerServiceRefresh();
}

void ProcessManager::invalidateCache() {
    m_procsDirty.store(true);
    m_servicesDirty.store(true);
    triggerProcessRefresh();
    triggerServiceRefresh();
}

void ProcessManager::triggerProcessRefresh() {
    bool expected = false;
    if (m_procRefreshPending.compare_exchange_strong(expected, true)) {
        QMetaObject::invokeMethod(m_worker, &ProcessWorker::doRefreshProcesses, Qt::QueuedConnection);
    }
}

void ProcessManager::triggerServiceRefresh() {
    bool expected = false;
    if (m_servicesRefreshPending.compare_exchange_strong(expected, true)) {
        QMetaObject::invokeMethod(m_worker, &ProcessWorker::doRefreshServices, Qt::QueuedConnection);
    }
}

void ProcessManager::updateCachedProcesses(std::vector<ProcInfo> &&procs) {
    {
        std::unique_lock<std::mutex> lock(m_cacheMutex);
        m_cachedProcs = std::make_shared<std::vector<ProcInfo>>(std::move(procs));
        m_procsTimestamp = std::chrono::steady_clock::now();
        m_procsDirty.store(false);
    }
    m_procRefreshPending.store(false);
    m_initCv.notify_all();
    QMetaObject::invokeMethod(this, &ProcessManager::cacheRefreshed, Qt::QueuedConnection);
}

void ProcessManager::updateCachedServices(std::vector<SvcInfo> &&services) {
    {
        std::unique_lock<std::mutex> lock(m_cacheMutex);
        m_cachedServices = std::make_shared<std::vector<SvcInfo>>(std::move(services));
        m_servicesTimestamp = std::chrono::steady_clock::now();
        m_servicesDirty.store(false);
    }
    m_servicesRefreshPending.store(false);
    m_initCv.notify_all();
    QMetaObject::invokeMethod(this, &ProcessManager::cacheRefreshed, Qt::QueuedConnection);
}

bool ProcessManager::isKillQuery(const QString &raw) const {
    const QString trimmed = raw.trimmed();
    if (trimmed.isEmpty()) return false;
    if (raw.startsWith(QLatin1String("k "), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1String("k:"), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1String("kill "), Qt::CaseInsensitive) ||
        raw.startsWith(QLatin1String("kill:"), Qt::CaseInsensitive)) {
        return true;
    }
    if (trimmed.compare(QLatin1String("k"), Qt::CaseInsensitive) == 0 ||
        trimmed.compare(QLatin1String("kill"), Qt::CaseInsensitive) == 0) {
        return true;
    }
    return false;
}

QString ProcessManager::searchTerm(const QString &raw) const {
    QString rest;
    if (raw.startsWith(QLatin1String("kill:"), Qt::CaseInsensitive)) {
        rest = raw.mid(5).trimmed();
    } else if (raw.startsWith(QLatin1String("kill "), Qt::CaseInsensitive)) {
        rest = raw.mid(5).trimmed();
    } else if (raw.startsWith(QLatin1String("k:"), Qt::CaseInsensitive)) {
        rest = raw.mid(2).trimmed();
    } else if (raw.startsWith(QLatin1String("k "), Qt::CaseInsensitive)) {
        rest = raw.mid(2).trimmed();
    } else if (raw.trimmed().compare(QLatin1String("k"), Qt::CaseInsensitive) == 0 ||
               raw.trimmed().compare(QLatin1String("kill"), Qt::CaseInsensitive) == 0) {
        return QString();
    } else {
        return QString();
    }

    if (rest.startsWith(QLatin1Char('-'))) {
        int spaceIdx = rest.indexOf(QLatin1Char(' '));
        if (spaceIdx > 0) {
            return rest.mid(spaceIdx + 1).trimmed();
        }
        return QString();
    }
    return rest;
}

int ProcessManager::parseSignalFlag(const QString &raw) const {
    QString rest;
    if (raw.startsWith(QLatin1String("kill:"), Qt::CaseInsensitive)) {
        rest = raw.mid(5).trimmed();
    } else if (raw.startsWith(QLatin1String("kill "), Qt::CaseInsensitive)) {
        rest = raw.mid(5).trimmed();
    } else if (raw.startsWith(QLatin1String("k:"), Qt::CaseInsensitive)) {
        rest = raw.mid(2).trimmed();
    } else if (raw.startsWith(QLatin1String("k "), Qt::CaseInsensitive)) {
        rest = raw.mid(2).trimmed();
    } else {
        return 0;
    }

    if (rest.startsWith(QLatin1Char('-'))) {
        int spaceIdx = rest.indexOf(QLatin1Char(' '));
        QString flag = (spaceIdx > 0 ? rest.left(spaceIdx) : rest).mid(1).toUpper();
        if (flag == QLatin1String("9") || flag == QLatin1String("KILL") || flag == QLatin1String("SIGKILL")) return 9;
        if (flag == QLatin1String("15") || flag == QLatin1String("TERM") || flag == QLatin1String("SIGTERM")) return 15;
        if (flag == QLatin1String("1") || flag == QLatin1String("HUP") || flag == QLatin1String("SIGHUP")) return 1;
        if (flag == QLatin1String("2") || flag == QLatin1String("INT") || flag == QLatin1String("SIGINT")) return 2;
        if (flag == QLatin1String("19") || flag == QLatin1String("STOP") || flag == QLatin1String("SIGSTOP")) return 19;
        if (flag == QLatin1String("18") || flag == QLatin1String("CONT") || flag == QLatin1String("SIGCONT")) return 18;
    }
    return 0;
}

void ProcessManager::scanProcesses(std::vector<ProcInfo> &outProcs, bool forceFresh) {
    auto now = std::chrono::steady_clock::now();
    long long elapsed = 0;
    {
        std::lock_guard<std::mutex> lock(m_cacheMutex);
        elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_procsTimestamp).count();
    }

    if (forceFresh) {
        if (QThread::currentThread() == &m_thread) {
            m_worker->doRefreshProcesses();
        } else {
            m_procRefreshPending.store(true);
            QMetaObject::invokeMethod(m_worker, &ProcessWorker::doRefreshProcesses, Qt::BlockingQueuedConnection);
        }
    } else if (m_procsDirty.load() || elapsed >= 350) {
        triggerProcessRefresh();
    }

    std::unique_lock<std::mutex> lock(m_cacheMutex);
    if (m_cachedProcs->empty()) {
        m_initCv.wait_for(lock, std::chrono::milliseconds(500), [this]() {
            return !m_cachedProcs->empty();
        });
    }
    outProcs = *m_cachedProcs;
}

void ProcessManager::scanServices(std::vector<SvcInfo> &outServices, bool forceFresh) {
    auto now = std::chrono::steady_clock::now();
    long long elapsed = 0;
    {
        std::lock_guard<std::mutex> lock(m_cacheMutex);
        elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_servicesTimestamp).count();
    }

    if (forceFresh) {
        if (QThread::currentThread() == &m_thread) {
            m_worker->doRefreshServices();
        } else {
            m_servicesRefreshPending.store(true);
            QMetaObject::invokeMethod(m_worker, &ProcessWorker::doRefreshServices, Qt::BlockingQueuedConnection);
        }
    } else if (m_servicesDirty.load() || elapsed >= 5000) {
        triggerServiceRefresh();
    }

    std::unique_lock<std::mutex> lock(m_cacheMutex);
    if (m_cachedServices->empty()) {
        m_initCv.wait_for(lock, std::chrono::milliseconds(500), [this]() {
            return !m_cachedServices->empty();
        });
    }
    outServices = *m_cachedServices;
}

QString ProcessManager::signalName(int sig) {
    switch (sig) {
        case 9: return QStringLiteral("SIGKILL");
        case 15: return QStringLiteral("SIGTERM");
        case 1: return QStringLiteral("SIGHUP");
        case 2: return QStringLiteral("SIGINT");
        case 19: return QStringLiteral("SIGSTOP");
        case 18: return QStringLiteral("SIGCONT");
        default: return QStringLiteral("Signal ") + QString::number(sig);
    }
}

QVariantList ProcessManager::search(const QString &term, int explicitSignal, int maxResults) {
    QString q = term.trimmed().toLower();
    int defaultSig = (explicitSignal > 0) ? explicitSignal : 15;

    auto now = std::chrono::steady_clock::now();
    long long pElapsed = 0;
    long long sElapsed = 0;
    {
        std::lock_guard<std::mutex> lock(m_cacheMutex);
        pElapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_procsTimestamp).count();
        sElapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_servicesTimestamp).count();
    }

    if (m_procsDirty.load() || pElapsed >= 350) {
        triggerProcessRefresh();
    }

    if (m_servicesDirty.load() || sElapsed >= 5000) {
        triggerServiceRefresh();
    }

    std::shared_ptr<const std::vector<ProcInfo>> procs;
    std::shared_ptr<const std::vector<SvcInfo>> services;
    {
        std::unique_lock<std::mutex> lock(m_cacheMutex);
        procs = m_cachedProcs;
        services = m_cachedServices;
    }

    struct Candidate {
        const ProcInfo *proc{nullptr};
        const SvcInfo *svc{nullptr};
        int tier{4};
        unsigned long long sortKey{0};
        int hlStart{-1};
        int hlLen{0};
        bool hlIsGeneric{false};
    };
    std::vector<Candidate> candidates;
    candidates.reserve(procs->size() + services->size());

    bool isNumeric = false;
    int numericPid = q.toInt(&isNumeric);

    for (const auto &p : *procs) {
        int tier = -1;
        int hlStart = -1;
        int hlLen = 0;
        bool hlIsGeneric = false;

        if (q.isEmpty()) {
            tier = 3;
        } else if (isNumeric && p.pid == numericPid) {
            tier = 1;
            hlStart = 0;
            hlLen = q.length();
            hlIsGeneric = true;
        } else if (p.nameLower == q) {
            tier = 1;
            hlStart = 0;
            hlLen = q.length();
        } else if (p.nameLower.startsWith(q)) {
            tier = 2;
            hlStart = 0;
            hlLen = q.length();
        } else {
            int idx = p.nameLower.indexOf(q);
            if (idx >= 0) {
                tier = 3;
                hlStart = idx;
                hlLen = q.length();
            } else {
                int cidx = p.cmdlineLower.indexOf(q);
                if (cidx >= 0) {
                    tier = 4;
                }
            }
        }

        if (tier >= 0) {
            Candidate c;
            c.proc = &p;
            c.tier = tier;
            c.sortKey = p.rssKb;
            c.hlStart = hlStart;
            c.hlLen = hlLen;
            c.hlIsGeneric = hlIsGeneric;
            candidates.push_back(c);
        }
    }

    for (const auto &s : *services) {
        int tier = -1;
        int hlStart = -1;
        int hlLen = 0;
        bool hlIsGeneric = false;

        if (q.isEmpty()) {
            if (s.isUser) tier = 4;
        } else if (s.nameLower == q) {
            tier = 1;
            hlStart = 0;
            hlLen = q.length();
        } else if (s.nameLower.startsWith(q)) {
            tier = 2;
            hlStart = 0;
            hlLen = q.length();
        } else {
            int idx = s.nameLower.indexOf(q);
            if (idx >= 0) {
                tier = 3;
                hlStart = idx;
                hlLen = q.length();
            } else {
                int didx = s.descriptionLower.indexOf(q);
                if (didx >= 0) {
                    tier = 4;
                    hlStart = didx;
                    hlLen = q.length();
                    hlIsGeneric = true;
                }
            }
        }

        if (tier >= 0) {
            Candidate c;
            c.svc = &s;
            c.tier = tier;
            c.sortKey = s.isUser ? 1000 : 500;
            c.hlStart = hlStart;
            c.hlLen = hlLen;
            c.hlIsGeneric = hlIsGeneric;
            candidates.push_back(c);
        }
    }

    int limit = std::min(maxResults, static_cast<int>(candidates.size()));
    std::partial_sort(candidates.begin(), candidates.begin() + limit, candidates.end(),
        [](const Candidate &a, const Candidate &b) {
            if (a.tier != b.tier) return a.tier < b.tier;
            return a.sortKey > b.sortKey;
        });

    QVariantList results;
    results.reserve(limit);
    for (int i = 0; i < limit; ++i) {
        const auto &c = candidates[i];
        QVariantMap m;
        if (c.proc) {
            const auto &p = *c.proc;
            QString desc;
            if (p.childCount > 1) {
                desc = QStringLiteral("PID %1 · %2 processes · %3")
                           .arg(p.pid)
                           .arg(p.childCount)
                           .arg(qs::processcore::formatRssKb(p.rssKb));
            } else {
                desc = QStringLiteral("PID %1 · %2")
                           .arg(p.pid)
                           .arg(qs::processcore::formatRssKb(p.rssKb));
            }

            QVariantList hlName;
            QVariantList hlGeneric;
            if (c.hlStart >= 0) {
                if (c.hlIsGeneric) {
                    hlGeneric.append(QVariantList{c.hlStart, c.hlStart + c.hlLen});
                } else {
                    hlName.append(QVariantList{c.hlStart, c.hlStart + c.hlLen});
                }
            }

            m[QStringLiteral("id")] = QStringLiteral("proc:") + QString::number(p.pid);
            m[QStringLiteral("kind")] = QStringLiteral("kill_process");
            m[QStringLiteral("name")] = p.name;
            m[QStringLiteral("generic")] = desc;
            m[QStringLiteral("iconName")] = QStringLiteral("utilities-terminal");
            m[QStringLiteral("pid")] = p.pid;
            m[QStringLiteral("unitName")] = QString();
            m[QStringLiteral("isUser")] = true;
            m[QStringLiteral("isPaused")] = (p.state == 'T');
            m[QStringLiteral("count")] = p.childCount;
            m[QStringLiteral("rssKb")] = static_cast<qulonglong>(p.rssKb);
            m[QStringLiteral("defaultSignal")] = defaultSig;
            m[QStringLiteral("hlName")] = hlName;
            m[QStringLiteral("hlGeneric")] = hlGeneric;
        } else if (c.svc) {
            const auto &s = *c.svc;
            QString typeStr = s.isUser ? QStringLiteral("systemd user service") : QStringLiteral("systemd system service");
            QString desc = s.description.isEmpty() ? typeStr : (s.description + QStringLiteral(" · ") + typeStr);

            QVariantList hlName;
            QVariantList hlGeneric;
            if (c.hlStart >= 0) {
                if (c.hlIsGeneric) {
                    hlGeneric.append(QVariantList{c.hlStart, c.hlStart + c.hlLen});
                } else {
                    hlName.append(QVariantList{c.hlStart, c.hlStart + c.hlLen});
                }
            }

            m[QStringLiteral("id")] = QStringLiteral("svc:") + s.name;
            m[QStringLiteral("kind")] = QStringLiteral("kill_service");
            m[QStringLiteral("name")] = s.name;
            m[QStringLiteral("generic")] = desc;
            m[QStringLiteral("iconName")] = QStringLiteral("preferences-system-services");
            m[QStringLiteral("pid")] = 0;
            m[QStringLiteral("unitName")] = s.name;
            m[QStringLiteral("isUser")] = s.isUser;
            m[QStringLiteral("isPaused")] = false;
            m[QStringLiteral("count")] = 1;
            m[QStringLiteral("rssKb")] = 0;
            m[QStringLiteral("defaultSignal")] = defaultSig;
            m[QStringLiteral("hlName")] = hlName;
            m[QStringLiteral("hlGeneric")] = hlGeneric;
        }
        results.append(m);
    }
    return results;
}

QVariantMap ProcessManager::sendSignal(int pid, int signal, bool killTree) {
    QVariantMap res;
    if (pid <= 1) {
        res[QStringLiteral("success")] = false;
        res[QStringLiteral("message")] = QStringLiteral("Invalid PID: %1").arg(pid);
        return res;
    }

    bool ok = false;
    if (killTree) {
        ok = qs::processcore::killProcessTree(pid, signal);
    } else {
        ok = (::kill(static_cast<pid_t>(pid), signal) == 0);
    }

    invalidateCache();

    QString sigName = signalName(signal);
    QString actionVerb;
    if (signal == 19) actionVerb = QStringLiteral("Frozen");
    else if (signal == 18) actionVerb = QStringLiteral("Resumed");
    else if (signal == 9) actionVerb = QStringLiteral("Killed");
    else if (signal == 1) actionVerb = QStringLiteral("Reloaded");
    else actionVerb = QStringLiteral("Terminated");

    QString msg = ok
        ? QStringLiteral("%1 PID %2 (%3)").arg(actionVerb).arg(pid).arg(sigName)
        : QStringLiteral("Failed to send %1 to PID %2").arg(sigName).arg(pid);

    res[QStringLiteral("success")] = ok;
    res[QStringLiteral("message")] = msg;
    res[QStringLiteral("signal")] = signal;
    return res;
}

QVariantMap ProcessManager::controlService(const QString &unitName, const QString &action, int signal, bool isUser) {
    QVariantMap res;
    QDBusConnection conn = isUser ? QDBusConnection::sessionBus() : QDBusConnection::systemBus();
    if (!conn.isConnected()) {
        res[QStringLiteral("success")] = false;
        res[QStringLiteral("message")] = QStringLiteral("D-Bus connection unavailable");
        return res;
    }

    invalidateCache();

    QString methodName;
    QList<QVariant> args;

    if (action == QLatin1String("stop")) {
        methodName = QStringLiteral("StopUnit");
        args << unitName << QStringLiteral("replace");
    } else if (action == QLatin1String("restart")) {
        methodName = QStringLiteral("RestartUnit");
        args << unitName << QStringLiteral("replace");
    } else if (action == QLatin1String("kill")) {
        methodName = QStringLiteral("KillUnit");
        args << unitName << QStringLiteral("all") << signal;
    } else {
        res[QStringLiteral("success")] = false;
        res[QStringLiteral("message")] = QStringLiteral("Unknown action: %1").arg(action);
        return res;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.systemd1"),
        QStringLiteral("/org/freedesktop/systemd1"),
        QStringLiteral("org.freedesktop.systemd1.Manager"),
        methodName
    );
    msg.setArguments(args);

    QDBusMessage reply = conn.call(msg);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        res[QStringLiteral("success")] = false;
        res[QStringLiteral("message")] = reply.errorMessage();
        return res;
    }

    QString label = action.toUpper();
    if (action == QLatin1String("kill")) {
        label = QStringLiteral("Killed (%1)").arg(signalName(signal));
    } else if (action == QLatin1String("stop")) {
        label = QStringLiteral("Stopped");
    } else if (action == QLatin1String("restart")) {
        label = QStringLiteral("Restarted");
    }

    res[QStringLiteral("success")] = true;
    res[QStringLiteral("message")] = QStringLiteral("%1 service %2").arg(label, unitName);
    return res;
}

} // namespace qs::plugins
