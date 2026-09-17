#include <iostream>
#include <chrono>
#include <vector>
#include <thread>
#include <atomic>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cstring>
#include <climits>

int main() {
    uid_t myUid = getuid();

    auto t0 = std::chrono::high_resolution_clock::now();
    for (int iter = 0; iter < 100; ++iter) {
        DIR *procDir = opendir("/proc");
        if (!procDir) continue;

        int procFd = dirfd(procDir);
        struct dirent *procEntry;
        std::vector<int> pids;

        while ((procEntry = readdir(procDir)) != nullptr) {
            if (procEntry->d_name[0] < '0' || procEntry->d_name[0] > '9') continue;
            struct stat st;
            if (fstatat(procFd, procEntry->d_name, &st, AT_SYMLINK_NOFOLLOW) == 0 && st.st_uid == myUid) {
                pids.push_back(atoi(procEntry->d_name));
            }
        }
        closedir(procDir);

        const size_t numThreads = 6;
        std::vector<std::thread> workers;
        std::atomic<int> found(0);

        for (size_t t = 0; t < numThreads; ++t) {
            workers.emplace_back([&, t] {
                char target[PATH_MAX];
                for (size_t i = t; i < pids.size(); i += numThreads) {
                    char fdPath[64];
                    snprintf(fdPath, sizeof(fdPath), "/proc/%d/fd", pids[i]);
                    DIR *d = opendir(fdPath);
                    if (!d) continue;

                    int dfd = dirfd(d);
                    struct dirent *fe;
                    while ((fe = readdir(d)) != nullptr) {
                        if (fe->d_name[0] == '.') continue;
                        ssize_t len = readlinkat(dfd, fe->d_name, target, sizeof(target) - 1);
                        if (len > 10 && strncmp(target, "/dev/video", 10) == 0) {
                            found++;
                        }
                    }
                    closedir(d);
                }
            });
        }
        for (auto &w : workers) w.join();
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / 100.0;
    std::cout << "Mean V4L2 scan time (6 threads): " << ms << " ms per scan\n";
    return 0;
}
