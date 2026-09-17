#include "EthernetProbe.hpp"

#include <QCoreApplication>
#include <iostream>
#include <vector>
#include <numeric>
#include <algorithm>
#include <cmath>
#include <chrono>

using namespace qs::plugins;

struct Stats {
    double mean{0.0};
    double median{0.0};
    double stddev{0.0};
    double minVal{0.0};
    double maxVal{0.0};
};

static Stats computeStats(std::vector<double> &samples) {
    Stats s;
    if (samples.empty()) return s;
    std::sort(samples.begin(), samples.end());
    s.minVal = samples.front();
    s.maxVal = samples.back();
    s.median = samples[samples.size() / 2];
    double sum = std::accumulate(samples.begin(), samples.end(), 0.0);
    s.mean = sum / static_cast<double>(samples.size());
    double var = 0.0;
    for (double v : samples) {
        var += (v - s.mean) * (v - s.mean);
    }
    s.stddev = std::sqrt(var / static_cast<double>(samples.size()));
    return s;
}

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    constexpr int ITERS = 100;

    // Warmup
    auto wState = EthernetProbe::probe(false);
    (void)wState;

    // Benchmark 1: Linux Netlink & Ethtool (kernel link, carrier, speed, MAC, stats)
    std::vector<double> netlinkSamples;
    netlinkSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        EthernetState st;
        st.iface = QStringLiteral("enp34s0");
        auto t0 = std::chrono::steady_clock::now();
        EthernetProbe::queryNetlinkAndEthtool(st);
        auto t1 = std::chrono::steady_clock::now();
        netlinkSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto netlinkStats = computeStats(netlinkSamples);

    // Benchmark 2: POSIX kernel calls (getifaddrs + /proc/net/route)
    std::vector<double> posixSamples;
    posixSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        EthernetState st;
        st.iface = QStringLiteral("enp34s0");
        auto t0 = std::chrono::steady_clock::now();
        EthernetProbe::querySysfsAndPosixFallback(st);
        auto t1 = std::chrono::steady_clock::now();
        posixSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto posixStats = computeStats(posixSamples);

    // Benchmark 3: Fast DBus query (without XML introspection)
    std::vector<double> dbusFastSamples;
    dbusFastSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        EthernetState st;
        st.iface = QStringLiteral("enp34s0");
        auto t0 = std::chrono::steady_clock::now();
        EthernetProbe::queryNetworkManagerFast(st);
        auto t1 = std::chrono::steady_clock::now();
        dbusFastSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto dbusFastStats = computeStats(dbusFastSamples);

    // Benchmark 4: Sysfs interface + RX/TX byte stats
    std::vector<double> sysfsSamples;
    sysfsSamples.reserve(ITERS);
    quint64 rx = 0, tx = 0;
    for (int i = 0; i < ITERS; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        auto ifaces = EthernetProbe::findEthernetInterfaces();
        if (!ifaces.isEmpty()) {
            EthernetProbe::readRxTxBytes(ifaces.first(), rx, tx);
        }
        auto t1 = std::chrono::steady_clock::now();
        sysfsSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto sysfsStats = computeStats(sysfsSamples);

    // Benchmark 5: Full Native Probe (Netlink + Ethtool + POSIX + fast DBus)
    std::vector<double> fullSamples;
    fullSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        auto st = EthernetProbe::probe(false);
        auto t1 = std::chrono::steady_clock::now();
        fullSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto fullStats = computeStats(fullSamples);

    // Benchmark 6: Socket Internet Connectivity Test (10 iterations)
    std::vector<double> sockSamples;
    sockSamples.reserve(10);
    for (int i = 0; i < 10; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        bool ok = EthernetProbe::testInternetSocket(QString(), 400);
        (void)ok;
        auto t1 = std::chrono::steady_clock::now();
        sockSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto sockStats = computeStats(sockSamples);

    // Benchmark 7: In-process ICMP Ping (5 iterations)
    std::vector<double> pingSamples;
    pingSamples.reserve(5);
    for (int i = 0; i < 5; ++i) {
        auto res = EthernetProbe::pingHost(QStringLiteral("1.1.1.1"), 1000);
        if (res.ok && res.latencyMs > 0) {
            pingSamples.push_back(res.latencyMs);
        }
    }
    const auto pingStats = computeStats(pingSamples);

    std::cout << "=== ETHERNET C++ MICRO-BENCHMARKS ===" << std::endl;
    std::cout << "NETLINK_ETHTOOL:" << netlinkStats.mean << ":" << netlinkStats.median << ":" << netlinkStats.stddev << ":" << netlinkStats.minVal << ":" << netlinkStats.maxVal << std::endl;
    std::cout << "POSIX_FALLBACK:" << posixStats.mean << ":" << posixStats.median << ":" << posixStats.stddev << ":" << posixStats.minVal << ":" << posixStats.maxVal << std::endl;
    std::cout << "DBUS_FAST:" << dbusFastStats.mean << ":" << dbusFastStats.median << ":" << dbusFastStats.stddev << ":" << dbusFastStats.minVal << ":" << dbusFastStats.maxVal << std::endl;
    std::cout << "SYSFS_STATS:" << sysfsStats.mean << ":" << sysfsStats.median << ":" << sysfsStats.stddev << ":" << sysfsStats.minVal << ":" << sysfsStats.maxVal << std::endl;
    std::cout << "FULL_PROBE:" << fullStats.mean << ":" << fullStats.median << ":" << fullStats.stddev << ":" << fullStats.minVal << ":" << fullStats.maxVal << std::endl;
    std::cout << "SOCKET_TEST:" << sockStats.mean << ":" << sockStats.median << ":" << sockStats.stddev << ":" << sockStats.minVal << ":" << sockStats.maxVal << std::endl;
    std::cout << "ICMP_PING:" << pingStats.mean << ":" << pingStats.median << ":" << pingStats.stddev << ":" << pingStats.minVal << ":" << pingStats.maxVal << std::endl;

    return 0;
}
