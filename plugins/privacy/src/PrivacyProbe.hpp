#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace qs::plugins {

struct PrivacyState {
    bool cameraActive{false};
    QStringList cameraApps;
    QStringList cameraDevices;

    bool micActive{false};
    QStringList micApps;
    QStringList micDevices;

    [[nodiscard]] bool hasActive() const noexcept {
        return cameraActive || micActive;
    }

    bool operator==(const PrivacyState &other) const = default;

    [[nodiscard]] QVariantMap toMap() const {
        QVariantMap cam;
        cam[QStringLiteral("active")] = cameraActive;
        cam[QStringLiteral("apps")] = QVariant::fromValue(cameraApps);
        cam[QStringLiteral("devices")] = QVariant::fromValue(cameraDevices);

        QVariantMap mic;
        mic[QStringLiteral("active")] = micActive;
        mic[QStringLiteral("apps")] = QVariant::fromValue(micApps);
        mic[QStringLiteral("devices")] = QVariant::fromValue(micDevices);

        QVariantMap root;
        root[QStringLiteral("camera")] = cam;
        root[QStringLiteral("microphone")] = mic;
        return root;
    }
};

class PrivacyProbe {
public:
    // Main high-performance probe entrypoint
    static PrivacyState probe(bool forceDeepQuery = false);

    // Fast kernel hardware checks (sub-millisecond)
    static bool checkAlsaCapture(PrivacyState &state);
    static bool checkV4L2Fast(PrivacyState &state);

    // Deep PipeWire metadata resolution (only run when active or requested)
    static void resolvePipeWireMetadata(PrivacyState &state);
    static void checkWpctl(PrivacyState &state);

    static QString getV4LDeviceName(const QString &vname);
    static bool isPipeWireRunning();
};

} // namespace qs::plugins
