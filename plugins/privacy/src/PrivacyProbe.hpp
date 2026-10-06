#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace qs::plugins {

struct PrivacyState {
    bool micActive{false};
    QStringList micApps;
    QStringList micDevices;

    [[nodiscard]] bool hasActive() const noexcept {
        return micActive;
    }

    bool operator==(const PrivacyState &other) const = default;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap mic;
        mic[QStringLiteral("active")] = micActive;
        mic[QStringLiteral("apps")] = QVariant::fromValue(micApps);
        mic[QStringLiteral("devices")] = QVariant::fromValue(micDevices);

        QVariantMap root;
        root[QStringLiteral("microphone")] = mic;
        return root;
    }
};

class PrivacyProbe {
public:
    static PrivacyState probe(bool forceDeepQuery = false);

    static bool checkAlsaCapture(PrivacyState &state);
    static void resolvePipeWireMetadata(PrivacyState &state);
    static void checkWpctl(PrivacyState &state);

    static bool isPipeWireRunning();
};

} // namespace qs::plugins
