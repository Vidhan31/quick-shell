#include "NotificationModel.hpp"
#include "NotificationTypes.hpp"

#include <QCoreApplication>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <vector>

using namespace qs::plugins::notifications;

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    std::cout << "=========================================================================\n";
    std::cout << "          NATIVE C++ NOTIFICATION PLUGIN MICRO-BENCHMARK                 \n";
    std::cout << "=========================================================================\n";

    NotificationModel model;

    // Test 1: NotificationItem insertion & capacity trimming (10,000 insertions)
    const int INSERT_ITERS = 10000;
    auto t0 = std::chrono::high_resolution_clock::now();
    for (int i = 1; i <= INSERT_ITERS; ++i) {
        NotificationItem item;
        item.id = static_cast<uint32_t>(i);
        item.appName = QStringLiteral("BenchApp_%1").arg(i % 5);
        item.summary = QStringLiteral("Notification summary %1").arg(i);
        item.body = QStringLiteral("Notification body text with details %1").arg(i);
        item.urgency = i % 3;
        item.timestamp = QDateTime::currentDateTime();
        item.actions.append(NotificationAction{QStringLiteral("action1"), QStringLiteral("Open")});
        item.actions.append(NotificationAction{QStringLiteral("action2"), QStringLiteral("Dismiss")});
        model.addOrUpdate(item, 100);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double insertTimeUs = std::chrono::duration<double, std::micro>(t1 - t0).count();
    double nsPerInsert = (insertTimeUs * 1000.0) / INSERT_ITERS;
    double insertsPerSec = (INSERT_ITERS / insertTimeUs) * 1e6;

    std::cout << std::left << std::setw(42) << "1. Model Insertion & Trimming (10k ops):"
              << std::right << std::setw(10) << std::fixed << std::setprecision(2)
              << nsPerInsert << " ns/op ("
              << std::fixed << std::setprecision(0) << insertsPerSec << " ops/sec)\n";

    // Test 2: ID Lookups in populated model (10,000 lookups)
    const int LOOKUP_ITERS = 10000;
    t0 = std::chrono::high_resolution_clock::now();
    int foundCount = 0;
    for (int i = 0; i < LOOKUP_ITERS; ++i) {
        uint32_t targetId = static_cast<uint32_t>(INSERT_ITERS - (i % 100));
        if (model.findIndexById(targetId) >= 0) {
            foundCount++;
        }
    }
    t1 = std::chrono::high_resolution_clock::now();
    double lookupTimeUs = std::chrono::duration<double, std::micro>(t1 - t0).count();
    double nsPerLookup = (lookupTimeUs * 1000.0) / LOOKUP_ITERS;
    double lookupsPerSec = (LOOKUP_ITERS / lookupTimeUs) * 1e6;

    std::cout << std::left << std::setw(42) << "2. ID Lookup in 100-item Model (10k ops):"
              << std::right << std::setw(10) << std::fixed << std::setprecision(2)
              << nsPerLookup << " ns/op ("
              << std::fixed << std::setprecision(0) << lookupsPerSec << " ops/sec)\n";

    // Test 3: Relative Time string formatting (50,000 iterations)
    const int TIME_ITERS = 50000;
    NotificationItem testItem;
    testItem.timestamp = QDateTime::currentDateTime().addSecs(-125); // ~2 min ago
    t0 = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < TIME_ITERS; ++i) {
        QString s = testItem.timeAgo();
        Q_UNUSED(s);
    }
    t1 = std::chrono::high_resolution_clock::now();
    double timeFormatUs = std::chrono::duration<double, std::micro>(t1 - t0).count();
    double nsPerFormat = (timeFormatUs * 1000.0) / TIME_ITERS;
    double formatsPerSec = (TIME_ITERS / timeFormatUs) * 1e6;

    std::cout << std::left << std::setw(42) << "3. Relative Time Formatting (50k ops):"
              << std::right << std::setw(10) << std::fixed << std::setprecision(2)
              << nsPerFormat << " ns/op ("
              << std::fixed << std::setprecision(0) << formatsPerSec << " ops/sec)\n";

    // Test 4: QVariantList Serialization for QML (1,000 full serializations of 100 items)
    const int SERIALIZE_ITERS = 1000;
    t0 = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < SERIALIZE_ITERS; ++i) {
        QVariantList v = model.toVariantList();
        Q_UNUSED(v);
    }
    t1 = std::chrono::high_resolution_clock::now();
    double serializeTimeUs = std::chrono::duration<double, std::micro>(t1 - t0).count();
    double usPerSerialize = serializeTimeUs / SERIALIZE_ITERS;
    double serializesPerSec = (SERIALIZE_ITERS / serializeTimeUs) * 1e6;

    std::cout << std::left << std::setw(42) << "4. Full 100-Item QML Export (1k ops):"
              << std::right << std::setw(10) << std::fixed << std::setprecision(2)
              << usPerSerialize << " us/op ("
              << std::fixed << std::setprecision(0) << serializesPerSec << " exports/sec)\n";

    // Test 5: Deletions (100 removals)
    t0 = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < 100; ++i) {
        uint32_t id = INSERT_ITERS - i;
        model.removeById(id);
    }
    t1 = std::chrono::high_resolution_clock::now();
    double deleteTimeUs = std::chrono::duration<double, std::micro>(t1 - t0).count();
    double nsPerDelete = (deleteTimeUs * 1000.0) / 100;

    std::cout << std::left << std::setw(42) << "5. Model Row Removal (100 ops):"
              << std::right << std::setw(10) << std::fixed << std::setprecision(2)
              << nsPerDelete << " ns/op\n";

    std::cout << "-------------------------------------------------------------------------\n";
    std::cout << "Memory footprint: sizeof(NotificationItem) = " << sizeof(NotificationItem) << " bytes\n";
    std::cout << "=========================================================================\n";

    return 0;
}
