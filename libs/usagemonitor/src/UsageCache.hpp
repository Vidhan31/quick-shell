#pragma once

#include "UsageTypes.hpp"

#include <QJsonObject>
#include <QString>

namespace qs::plugins {

QString resolveUsageCachePath(const QString &relativePath);

QJsonObject windowToCache(const TokenWindow &window);
TokenWindow windowFromCache(const QJsonObject &object);

bool loadUsageCache(const QString &filePath, TokenRefreshResult &result);
bool saveUsageCache(const QString &filePath, const TokenRefreshResult &result);

} // namespace qs::plugins
