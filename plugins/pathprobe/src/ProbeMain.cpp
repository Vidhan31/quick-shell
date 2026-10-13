#include "PathProbe.hpp"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>

// Usage: pathprobe-probe <path> [path...]
// Prints one JSON object per input so classify() can be diffed without going
// through the launcher. With PATHS set it repeats the run and reports per-call
// cost, since classify() runs on every keystroke.
int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    qs::plugins::PathProbe probe;

    const int paths = static_cast<int>(app.arguments().size()) - 1;
    if (paths <= 0) {
        std::cerr << "usage: pathprobe-probe <path> [path...]" << std::endl;
        return 1;
    }
    for (const QString &arg : app.arguments().mid(1)) {
        const QJsonObject obj = QJsonObject::fromVariantMap(probe.classify(arg));
        std::cout << QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact)).toStdString()
                  << std::endl;
    }

    constexpr int ITERATIONS = 20000;
    // Accumulated so the calls cannot be optimized away and so the benchmark
    // reflects the real per-call cost of building the result map.
    int sink = 0;
    QElapsedTimer timer;
    timer.start();
    for (int i = 0; i < ITERATIONS; ++i) {
        for (const QString &arg : app.arguments().mid(1)) {
            sink += probe.classify(arg).size();
        }
    }
    const qint64 elapsed = timer.elapsed();
    std::cerr << "classify() mean " << (double(elapsed) / (ITERATIONS * paths)) * 1000.0
              << " us over " << paths << " path(s), " << sink << " keys accumulated" << std::endl;
    return 0;
}
