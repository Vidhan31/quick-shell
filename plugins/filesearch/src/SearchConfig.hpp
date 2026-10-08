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
    int maxResults = 10;
    int timeoutMs = 5000;
    int debounceMs = 75;
    QStringList extraFdArgs = {
        QStringLiteral("--hidden"),
        QStringLiteral("--no-ignore-vcs"),
        QStringLiteral("--one-file-system"),
        QStringLiteral("--strip-cwd-prefix=always")
    };
    QStringList extraFzfArgs = {
        QStringLiteral("--scheme=path")
    };
    QString fdBin;
    QString fzfBin;

    void loadEnvironment();
    static SearchConfig load();
};

} // namespace qs::plugins
