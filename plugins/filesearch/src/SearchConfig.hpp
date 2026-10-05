#pragma once

#include <QString>
#include <QStringList>

namespace qs::plugins {

QStringList splitArgs(const QString &commandLine);
QStringList parseSearchRoots(const QStringList &inputs);
QStringList parseSearchRoots(const QString &input);

struct SearchConfig {
    QString prefix = QStringLiteral("f");
    QStringList searchRoots;
    int maxResults = 20;
    int timeoutMs = 2500;
    int debounceMs = 75;
    QStringList extraFdArgs;
    QStringList extraFzfArgs;
    QString fdBin;
    QString fzfBin;

    static QString defaultUserConfigPath();
    bool loadFromFile(const QString &filePath = QString());
    void loadEnvironment();
    static SearchConfig load(const QString &configFilePath = QString());
};

} // namespace qs::plugins
