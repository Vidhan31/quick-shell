#pragma once

#include <QString>
#include <string_view>
#include <unordered_map>
#include <array>
#include <utility>

namespace qs::processcore {

QString formatRssKb(unsigned long kb);

inline bool isShellOrSystemd(std::string_view c) noexcept {
    return c == "systemd" || c == "bash" || c == "zsh" || c == "fish" || c == "sh";
}

template <typename ParentLookup>
int getRootFast(int pid, int ppid, std::string_view comm, ParentLookup &&getParent, std::unordered_map<int, int> *memo = nullptr) {
    if (memo) {
        auto it = memo->find(pid);
        if (it != memo->end()) return it->second;
    }

    if (pid <= 1 || ppid <= 1 || isShellOrSystemd(comm)) {
        if (memo) (*memo)[pid] = pid;
        return pid;
    }

    int curr = pid;
    int currPpid = ppid;
    int depth = 0;
    std::array<int, 32> visited;
    int visitedCount = 0;
    visited[visitedCount++] = pid;

    while (depth++ < 32) {
        if (currPpid <= 1) {
            break;
        }

        auto [parentOfParent, parentComm] = getParent(currPpid);
        if (parentComm.empty() || isShellOrSystemd(parentComm)) {
            break;
        }

        if (memo) {
            auto memoIt = memo->find(currPpid);
            if (memoIt != memo->end()) {
                curr = memoIt->second;
                break;
            }
        }

        curr = currPpid;
        if (visitedCount < static_cast<int>(visited.size())) {
            visited[visitedCount++] = curr;
        }
        currPpid = parentOfParent;
    }

    if (memo) {
        for (int i = 0; i < visitedCount; ++i) {
            (*memo)[visited[i]] = curr;
        }
    }

    return curr;
}

bool killProcessTree(int rootPid, int signal = 15, bool waitExited = false);

} // namespace qs::processcore
