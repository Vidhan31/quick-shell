#pragma once

#include "UsageMonitorBase.hpp"

#include <QStringList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

QStringList discoverAgRoots();
AgRefreshResult collectAgUsage(const AgWindowBounds &bounds, int lastDays = 10);

class AntigravityUsage : public UsageMonitorBase {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit AntigravityUsage(QObject *parent = nullptr);
    ~AntigravityUsage() override = default;
};

} // namespace qs::plugins
