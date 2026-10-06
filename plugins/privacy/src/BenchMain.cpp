#include "PrivacyProbe.hpp"

#include <QCoreApplication>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <vector>

struct Stats {
    double mean;
    double median;
    double min;
    double max;
    double stddev;
};

Stats computeStats(std::vector<double> &values) {
    if (values.empty()) return {0, 0, 0, 0, 0};
    std::sort(values.begin(), values.end());
    double sum = std::accumulate(values.begin(), values.end(), 0.0);
    double mean = sum / values.size();
    double median = values[values.size() / 2];
    double min = values.front();
    double max = values.back();
    double sqSum = 0.0;
    for (double d : values) sqSum += (d - mean) * (d - mean);
    double stddev = std::sqrt(sqSum / values.size());
    return {mean, median, min, max, stddev};
}

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    const int iterations = 50;

    std::vector<double> alsaTimes, pwTimes;
    alsaTimes.reserve(iterations);
    pwTimes.reserve(iterations);

    // Warm-up
    qs::plugins::PrivacyProbe::probe(true);

    for (int i = 0; i < iterations; ++i) {
        qs::plugins::PrivacyState state;

        auto t0 = std::chrono::high_resolution_clock::now();
        qs::plugins::PrivacyProbe::checkAlsaCapture(state);
        auto t1 = std::chrono::high_resolution_clock::now();

        alsaTimes.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }

    const int pwIters = 10;
    for (int i = 0; i < pwIters; ++i) {
        qs::plugins::PrivacyState state;
        auto t0 = std::chrono::high_resolution_clock::now();
        qs::plugins::PrivacyProbe::resolvePipeWireMetadata(state);
        auto t1 = std::chrono::high_resolution_clock::now();
        pwTimes.push_back(std::chrono::duration<double, std::milli>(t1 - t0).count());
    }

    auto sALSA = computeStats(alsaTimes);
    auto sPW = computeStats(pwTimes);

    std::cout << std::fixed << std::setprecision(3);
    std::cout << "=== C++ Native In-Process Benchmark (" << iterations << " iterations) ===\n";
    std::cout << "ALSA:" << sALSA.mean << "\n";
    std::cout << "PW_DEEP_QUERY:" << sPW.mean << "\n";

    return 0;
}
