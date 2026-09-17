#include <iostream>
#include <chrono>
#include <vector>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cstring>
#include <climits>

int main() {
    uid_t myUid = getuid();

    auto t0 = std::chrono::high_resolution_clock::now();
    int count = 0;
    for (int iter = 0; iter < 100; ++iter) {
        DIR *procDir = opendir("/proc");
        if (!procDir) continue;

        int procFd = dirfd(procDir);
        struct dirent *procEntry;

        while ((procEntry = readdir(procDir)) != nullptr) {
            if (procEntry->d_name[0] < '0' || procEntry->d_name[0] > '9') continue;

            // Check UID of /proc/[pid]
            struct stat st;
            if (fstatat(procFd, procEntry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) continue;
            if (st.st_uid != myUid) continue;

            char fdPath[64];
            snprintf(fdPath, sizeof(fdPath), "%s/fd", procEntry->d_name);
            int fdDir = openat(procFd, fdPath, O_RDONLY | O_DIRECTORY);
            if (fdDir < 0) continue;

            DIR *d = fdopendir(fdDir);
            if (!d) {
                close(fdDir);
                continue;
            }

            struct dirent *fe;
            char target[PATH_MAX];
            while ((fe = readdir(d)) != nullptr) {
                if (fe->d_name[0] == '.') continue;
                ssize_t len = readlinkat(fdDir, fe->d_name, target, sizeof(target) - 1);
                if (len > 10 && strncmp(target, "/dev/video", 10) == 0) {
                    count++;
                }
            }
            closedir(d);
        }
        closedir(procDir);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count() / 100.0;
    std::cout << "Mean V4L2 scan time (UID-filtered): " << ms << " ms per scan\n";
    return 0;
}
