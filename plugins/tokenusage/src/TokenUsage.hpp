#pragma once

#include "UsageMonitorBase.hpp"

#include <QStringList>
#include <QtQml/qqmlregistration.h>

namespace qs::plugins {

QStringList discoverOpenCodeDbPaths();
TokenRefreshResult collectTokenUsage(const TokenWindowBounds &bounds, int lastDays = 10);

class TokenUsage : public UsageMonitorBase {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit TokenUsage(QObject *parent = nullptr);
    ~TokenUsage() override = default;
};

} // namespace qs::plugins
