#pragma once

#include <QString>
#include <functional>
#include <utility>

namespace qs::processcore {

QString formatRssKb(unsigned long kb);

int getRootFast(int pid, int ppid, const QString &comm, const std::function<std::pair<int, QString>(int)> &getParent);

bool killProcessTree(int rootPid, int signal = 15);

} // namespace qs::processcore
