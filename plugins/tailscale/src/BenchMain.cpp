#include "TailscaleSocketClient.hpp"

#include <QCoreApplication>
#include <QJsonObject>
#include <QJsonDocument>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <vector>

using namespace qs::plugins;

struct Stats {
    double mean{0.0};
    double median{0.0};
    double p95{0.0};
    double stddev{0.0};
    double minVal{0.0};
    double maxVal{0.0};
};

static Stats computeStats(std::vector<double> &samples)
{
    Stats s;
    if (samples.empty()) {
        return s;
    }
    std::sort(samples.begin(), samples.end());
    s.minVal = samples.front();
    s.maxVal = samples.back();
    s.median = samples[samples.size() / 2];
    const size_t p95Idx = static_cast<size_t>(samples.size() * 0.95);
    s.p95 = samples[std::min(p95Idx, samples.size() - 1)];

    double sum = std::accumulate(samples.begin(), samples.end(), 0.0);
    s.mean = sum / static_cast<double>(samples.size());
    double var = 0.0;
    for (double v : samples) {
        var += (v - s.mean) * (v - s.mean);
    }
    s.stddev = std::sqrt(var / static_cast<double>(samples.size()));
    return s;
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    TailscaleSocketClient client;

    const bool jsonMode = (argc > 1 && QString::fromUtf8(argv[1]) == QStringLiteral("--json"));
    constexpr int ITERS = 50;

    // Warmup
    TailscaleState warmupState;
    client.fetchFullStatus(warmupState);

    // 1. Benchmark status endpoint
    std::vector<double> statusSamples;
    statusSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        const auto t0 = std::chrono::steady_clock::now();
        const auto resp = client.request(QStringLiteral("GET"), QStringLiteral("/localapi/v0/status"));
        const auto t1 = std::chrono::steady_clock::now();
        if (resp.ok) {
            statusSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
        }
    }
    const auto statusStats = computeStats(statusSamples);

    // 2. Benchmark prefs endpoint
    std::vector<double> prefsSamples;
    prefsSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        const auto t0 = std::chrono::steady_clock::now();
        const auto resp = client.request(QStringLiteral("GET"), QStringLiteral("/localapi/v0/prefs"));
        const auto t1 = std::chrono::steady_clock::now();
        if (resp.ok) {
            prefsSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
        }
    }
    const auto prefsStats = computeStats(prefsSamples);

    // 3. Benchmark serve-config endpoint
    std::vector<double> serveSamples;
    serveSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        const auto t0 = std::chrono::steady_clock::now();
        const auto resp = client.request(QStringLiteral("GET"), QStringLiteral("/localapi/v0/serve-config"));
        const auto t1 = std::chrono::steady_clock::now();
        if (resp.ok) {
            serveSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
        }
    }
    const auto serveStats = computeStats(serveSamples);

    // 4. Benchmark full fetchFullStatus (combining status, prefs, serve-config, services + parsing)
    std::vector<double> fullSamples;
    fullSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        TailscaleState st;
        const auto t0 = std::chrono::steady_clock::now();
        const bool ok = client.fetchFullStatus(st);
        const auto t1 = std::chrono::steady_clock::now();
        if (ok) {
            fullSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
        }
    }
    const auto fullStats = computeStats(fullSamples);

    if (jsonMode) {
        QJsonObject root;
        auto addStat = [&](const QString &name, const Stats &s) {
            QJsonObject o;
            o[QStringLiteral("mean_ms")] = s.mean;
            o[QStringLiteral("median_ms")] = s.median;
            o[QStringLiteral("p95_ms")] = s.p95;
            o[QStringLiteral("min_ms")] = s.minVal;
            o[QStringLiteral("max_ms")] = s.maxVal;
            o[QStringLiteral("stddev_ms")] = s.stddev;
            root[name] = o;
        };
        addStat(QStringLiteral("status_endpoint"), statusStats);
        addStat(QStringLiteral("prefs_endpoint"), prefsStats);
        addStat(QStringLiteral("serve_config_endpoint"), serveStats);
        addStat(QStringLiteral("full_status_combined"), fullStats);

        std::cout << QJsonDocument(root).toJson(QJsonDocument::Indented).toStdString() << std::endl;
    } else {
        std::cout << "\n================================================================================\n";
        std::cout << "        TAILSCALE NATIVE C++ LOCALAPI MICRO-BENCHMARK (" << ITERS << " iterations)\n";
        std::cout << "================================================================================\n";
        std::cout << std::fixed << std::setprecision(3);
        std::cout << "Endpoint / Action                 Min(ms)  Median(ms)  p95(ms)   Mean(ms)  StdDev(ms)\n";
        std::cout << "--------------------------------------------------------------------------------\n";
        std::cout << "1. GET /localapi/v0/status       "
                  << std::setw(8) << statusStats.minVal
                  << std::setw(11) << statusStats.median
                  << std::setw(10) << statusStats.p95
                  << std::setw(11) << statusStats.mean
                  << std::setw(11) << statusStats.stddev << "\n";
        std::cout << "2. GET /localapi/v0/prefs        "
                  << std::setw(8) << prefsStats.minVal
                  << std::setw(11) << prefsStats.median
                  << std::setw(10) << prefsStats.p95
                  << std::setw(11) << prefsStats.mean
                  << std::setw(11) << prefsStats.stddev << "\n";
        std::cout << "3. GET /localapi/v0/serve-config "
                  << std::setw(8) << serveStats.minVal
                  << std::setw(11) << serveStats.median
                  << std::setw(10) << serveStats.p95
                  << std::setw(11) << serveStats.mean
                  << std::setw(11) << serveStats.stddev << "\n";
        std::cout << "4. fetchFullStatus() (4 endpoints)"
                  << std::setw(8) << fullStats.minVal
                  << std::setw(11) << fullStats.median
                  << std::setw(10) << fullStats.p95
                  << std::setw(11) << fullStats.mean
                  << std::setw(11) << fullStats.stddev << "\n";
        std::cout << "================================================================================\n\n";
    }

    return 0;
}
