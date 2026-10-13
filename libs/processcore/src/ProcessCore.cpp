#include "ProcessCore.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <chrono>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace qs::processcore {

QString formatRssKb(unsigned long kb) {
    if (kb == 0) {
        return QStringLiteral("0K");
    }
    if (kb < 1024UL) {
        return QString::number(kb) + QStringLiteral("K");
    }
    if (kb < 1024UL * 1024UL) {
        return QString::number(static_cast<double>(kb) / 1024.0, 'f', 1) + QStringLiteral("M");
    }
    return QString::number(static_cast<double>(kb) / (1024.0 * 1024.0), 'f', 2) + QStringLiteral("G");
}

static inline bool isShellOrSystemd(const QString &c) {
    return c == u"systemd" || c == u"bash" || c == u"zsh" || c == u"fish" || c == u"sh";
}

int getRootFast(int pid, int ppid, const QString &comm, const std::function<std::pair<int, QString>(int)> &getParent) {
    if (pid <= 1 || ppid <= 1 || isShellOrSystemd(comm)) {
        return pid;
    }

    int curr = pid;
    int currPpid = ppid;
    int depth = 0;

    while (depth++ < 32) {
        if (currPpid <= 1) {
            break;
        }

        auto [parentOfParent, parentComm] = getParent(currPpid);
        if (parentComm.isEmpty() || isShellOrSystemd(parentComm)) {
            break;
        }

        curr = currPpid;
        currPpid = parentOfParent;
    }

    return curr;
}

static bool isProcessAlive(int pid) {
    if (pid <= 1) {
        return false;
    }
    if (::kill(static_cast<pid_t>(pid), 0) != 0) {
        return errno != ESRCH;
    }

    char statPath[64];
    snprintf(statPath, sizeof(statPath), "/proc/%d/stat", pid);
    int fd = open(statPath, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return false;
    }

    char buf[256];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) {
        return false;
    }
    buf[n] = '\0';

    char *closeParen = strrchr(buf, ')');
    if (closeParen && *(closeParen + 1) == ' ') {
        char st = *(closeParen + 2);
        if (st == 'Z' || st == 'X') {
            return false;
        }
    }
    return true;
}

bool killProcessTree(int rootPid, int signal) {
    if (rootPid <= 1) {
        return false;
    }

    DIR *procDir = opendir("/proc");
    if (!procDir) {
        return false;
    }
    int procFd = dirfd(procDir);

    std::unordered_map<int, std::vector<int>> children;
    std::unordered_map<int, char> states;

    char statBuf[512];
    char pathBuf[64];

    struct dirent *entry;
    while ((entry = readdir(procDir)) != nullptr) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') {
            continue;
        }
        int pid = 0;
        const char *np = entry->d_name;
        while (*np >= '0' && *np <= '9') {
            pid = pid * 10 + (*np++ - '0');
        }
        if (pid <= 0) {
            continue;
        }

        snprintf(pathBuf, sizeof(pathBuf), "%d/stat", pid);
        int statFd = openat(procFd, pathBuf, O_RDONLY | O_CLOEXEC);
        if (statFd < 0) {
            continue;
        }

        ssize_t statRead = read(statFd, statBuf, sizeof(statBuf) - 1);
        close(statFd);
        if (statRead <= 0) {
            continue;
        }
        statBuf[statRead] = '\0';

        char *openParen = strchr(statBuf, '(');
        char *closeParen = strrchr(statBuf, ')');
        if (!openParen || !closeParen || closeParen <= openParen) {
            continue;
        }

        const char *p = closeParen + 2;
        char state = *p;

        while (*p && *p != ' ') ++p;
        while (*p == ' ') ++p;

        int ppid = 0;
        while (*p >= '0' && *p <= '9') {
            ppid = ppid * 10 + (*p++ - '0');
        }

        children[ppid].push_back(pid);
        states[pid] = state;
    }
    closedir(procDir);

    auto rootIt = states.find(rootPid);
    if (rootIt == states.end()) {
        return false;
    }

    std::vector<int> targetPids;
    std::unordered_set<int> visited;

    std::function<void(int)> collectPostOrder = [&](int curr) {
        if (!visited.insert(curr).second) {
            return;
        }
        auto it = children.find(curr);
        if (it != children.end()) {
            for (auto childIt = it->second.rbegin(); childIt != it->second.rend(); ++childIt) {
                collectPostOrder(*childIt);
            }
        }
        targetPids.push_back(curr);
    };

    collectPostOrder(rootPid);

    // Unpause SIGSTOP processes with SIGCONT
    for (int pid : targetPids) {
        auto it = states.find(pid);
        if (it != states.end() && (it->second == 'T' || it->second == 't')) {
            ::kill(static_cast<pid_t>(pid), SIGCONT);
        }
    }

    // Signal children in reverse order (bottom-up, rootPid is last)
    for (int pid : targetPids) {
        ::kill(static_cast<pid_t>(pid), signal);
        if (signal != SIGCONT) {
            auto it = states.find(pid);
            if (it != states.end() && (it->second == 'T' || it->second == 't')) {
                ::kill(static_cast<pid_t>(pid), SIGCONT);
            }
        }
    }

    const bool isTerminationSignal = (signal == 15 || signal == 9 || signal == 2 || signal == 1 || signal == 3 || signal == 6);
    if (!isTerminationSignal) {
        return true;
    }

    bool exited = false;
    for (int attempt = 0; attempt < 30; ++attempt) {
        bool anyAlive = false;
        for (int pid : targetPids) {
            if (isProcessAlive(pid)) {
                anyAlive = true;
                break;
            }
        }
        if (!anyAlive || !isProcessAlive(rootPid)) {
            exited = true;
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }

    return exited;
}

} // namespace qs::processcore
