#include "MediaPlayer.hpp"
#include "MediaTypes.hpp"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QProcess>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <vector>

using namespace qs::plugins::media;

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

    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        std::cerr << "Error: Cannot connect to session D-Bus bus." << std::endl;
        return 1;
    }

    // Find first active MPRIS service for benchmarking
    QDBusInterface dbusIface(
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"),
        bus
    );
    QDBusReply<QStringList> reply = dbusIface.call(QStringLiteral("ListNames"));
    QString targetService;
    if (reply.isValid()) {
        for (const QString &name : reply.value()) {
            if (name.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
                targetService = name;
                break;
            }
        }
    }

    if (targetService.isEmpty()) {
        std::cerr << "No active MPRIS player found on session bus for benchmark." << std::endl;
        return 1;
    }

    std::cout << "Target MPRIS Player: " << qPrintable(targetService) << "\n" << std::endl;

    constexpr int ITERS = 100;

    // Benchmark 1: Native Qt6 DBus GetAll (Retrieves all player properties & metadata in 1 call)
    std::vector<double> dbusGetAllSamples;
    dbusGetAllSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        QDBusMessage msg = QDBusMessage::createMethodCall(
            targetService,
            QStringLiteral("/org/mpris/MediaPlayer2"),
            QStringLiteral("org.freedesktop.DBus.Properties"),
            QStringLiteral("GetAll")
        );
        msg << QStringLiteral("org.mpris.MediaPlayer2.Player");
        QDBusMessage resp = bus.call(msg);
        auto t1 = std::chrono::steady_clock::now();
        dbusGetAllSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto dbusGetAllStats = computeStats(dbusGetAllSamples);

    // Benchmark 2: Native Qt6 DBus Get (Single property: PlaybackStatus)
    std::vector<double> dbusGetPropSamples;
    dbusGetPropSamples.reserve(ITERS);
    for (int i = 0; i < ITERS; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        QDBusMessage msg = QDBusMessage::createMethodCall(
            targetService,
            QStringLiteral("/org/mpris/MediaPlayer2"),
            QStringLiteral("org.freedesktop.DBus.Properties"),
            QStringLiteral("Get")
        );
        msg << QStringLiteral("org.mpris.MediaPlayer2.Player") << QStringLiteral("PlaybackStatus");
        QDBusMessage resp = bus.call(msg);
        auto t1 = std::chrono::steady_clock::now();
        dbusGetPropSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto dbusGetPropStats = computeStats(dbusGetPropSamples);

    // Benchmark 3: Native in-memory Position interpolation (zero D-Bus calls during playback)
    MediaPlayer player(targetService);
    std::vector<double> interpSamples;
    constexpr int INTERP_ITERS = 10000;
    interpSamples.reserve(INTERP_ITERS);
    for (int i = 0; i < INTERP_ITERS; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        double p = player.position();
        QString s = player.formattedPosition();
        (void)p;
        (void)s;
        auto t1 = std::chrono::steady_clock::now();
        interpSamples.push_back(std::chrono::duration<double, std::micro>(t1 - t0).count());
    }
    const auto interpStats = computeStats(interpSamples);

    // Benchmark 4: Spawning process (busctl --user get-property)
    constexpr int PROC_ITERS = 25;
    std::vector<double> procSamples;
    procSamples.reserve(PROC_ITERS);
    for (int i = 0; i < PROC_ITERS; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        QProcess proc;
        proc.start(QStringLiteral("busctl"), {
            QStringLiteral("--user"),
            QStringLiteral("get-property"),
            targetService,
            QStringLiteral("/org/mpris/MediaPlayer2"),
            QStringLiteral("org.mpris.MediaPlayer2.Player"),
            QStringLiteral("PlaybackStatus")
        });
        proc.waitForFinished();
        auto t1 = std::chrono::steady_clock::now();
        procSamples.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    const auto procStats = computeStats(procSamples);

    std::cout << "=== MEDIA C++ MICRO-BENCHMARKS ===" << std::endl;
    std::cout << "DBUS_GETALL_MS:" << dbusGetAllStats.mean << ":" << dbusGetAllStats.median << ":" << dbusGetAllStats.stddev << ":" << dbusGetAllStats.minVal << ":" << dbusGetAllStats.maxVal << std::endl;
    std::cout << "DBUS_GETPROP_MS:" << dbusGetPropStats.mean << ":" << dbusGetPropStats.median << ":" << dbusGetPropStats.stddev << ":" << dbusGetPropStats.minVal << ":" << dbusGetPropStats.maxVal << std::endl;
    std::cout << "INTERPOLATION_US:" << interpStats.mean << ":" << interpStats.median << ":" << interpStats.stddev << ":" << interpStats.minVal << ":" << interpStats.maxVal << std::endl;
    std::cout << "PROCESS_SPAWN_MS:" << procStats.mean << ":" << procStats.median << ":" << procStats.stddev << ":" << procStats.minVal << ":" << procStats.maxVal << std::endl;

    return 0;
}
