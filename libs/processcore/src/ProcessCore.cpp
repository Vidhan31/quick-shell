#include "ProcessCore.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <cerrno>
#include <cctype>
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
        return QString::number(kb) + u'K';
    }
    if (kb < 1024UL * 1024UL) {
        return QString::number(static_cast<double>(kb) / 1024.0, 'f', 1) + u'M';
    }
    return QString::number(static_cast<double>(kb) / (1024.0 * 1024.0), 'f', 2) + u'G';
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

bool killProcessTree(int rootPid, int signal, bool waitExited) {
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
    if (!isTerminationSignal || !waitExited) {
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

std::string resolveProcessName(int pid, std::string_view comm) {
    if (pid <= 0) {
        return std::string(comm);
    }

    char exeBuf[512];
    char exePath[64];
    snprintf(exePath, sizeof(exePath), "/proc/%d/exe", pid);
    ssize_t elen = readlink(exePath, exeBuf, sizeof(exeBuf) - 1);
    std::string exeBase;
    if (elen > 0) {
        exeBuf[elen] = '\0';
        const char *slash = strrchr(exeBuf, '/');
        exeBase = slash ? (slash + 1) : exeBuf;
    }

    char cmdPath[64];
    snprintf(cmdPath, sizeof(cmdPath), "/proc/%d/cmdline", pid);
    int fd = open(cmdPath, O_RDONLY | O_CLOEXEC);
    std::vector<std::string> args;
    if (fd >= 0) {
        char buf[2048];
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n > 0) {
            ssize_t start = 0;
            for (ssize_t i = 0; i < n; ++i) {
                if (buf[i] == '\0') {
                    if (i > start) {
                        args.emplace_back(buf + start, i - start);
                    }
                    start = i + 1;
                }
            }
            if (start < n) {
                args.emplace_back(buf + start, n - start);
            }
        }
    }

    if (comm == "AppRun") {
        if (!args.empty()) {
            const char *slash = strrchr(args[0].c_str(), '/');
            std::string base = slash ? (slash + 1) : args[0];
            if (base.size() > 9) {
                std::string ext = base.substr(base.size() - 9);
                for (char &c : ext) c = static_cast<char>(tolower(c));
                if (ext == ".appimage") {
                    return base.substr(0, base.size() - 9);
                }
            }
        }
        if (!exeBase.empty() && exeBase != "AppRun") {
            return exeBase;
        }
    }

    if (isGenericComm(comm)) {
        if (!args.empty()) {
            for (size_t i = 1; i < args.size(); ++i) {
                const auto &arg = args[i];
                if (arg.empty() || arg[0] == '-') continue;
                const char *slash = strrchr(arg.c_str(), '/');
                std::string sbase = slash ? (slash + 1) : arg;
                if (sbase.find('.') != std::string::npos) {
                    return sbase;
                }
            }
        }
        if (!exeBase.empty()) {
            return exeBase;
        }
    }

    if (comm == "bwrap") {
        bool afterDashDash = false;
        for (size_t i = 0; i < args.size(); ++i) {
            if (args[i] == "--") {
                afterDashDash = true;
                continue;
            }
            if (afterDashDash && !args[i].empty() && args[i][0] != '-') {
                const char *slash = strrchr(args[i].c_str(), '/');
                return slash ? (slash + 1) : args[i];
            }
        }
    }

    if (comm.size() == 15 && !args.empty()) {
        const char *slash = strrchr(args[0].c_str(), '/');
        const char *candidate = slash ? (slash + 1) : args[0].c_str();
        if (strncmp(candidate, comm.data(), 15) == 0) {
            return candidate;
        }
    }

    return std::string(comm);
}

} // namespace qs::processcore
