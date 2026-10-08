#include "SearchConfig.hpp"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QProcessEnvironment>
#include <QStringTokenizer>
#include <QStringView>
#include <QSet>
#include <QStandardPaths>

namespace qs::plugins {

QStringList splitArgs(const QString &commandLine) {
    QStringList args;
    if (commandLine.trimmed().isEmpty()) {
        return args;
    }

    args.reserve(8);
    QString current;
    current.reserve(commandLine.size());

    bool inSingleQuote = false;
    bool inDoubleQuote = false;
    bool escapeNext = false;
    bool hasToken = false;

    const QStringView view(commandLine);
    for (qsizetype i = 0; i < view.size(); ++i) {
        const QChar c = view.at(i);

        if (escapeNext) {
            current.append(c);
            escapeNext = false;
            hasToken = true;
            continue;
        }

        if (c == u'\\' && !inSingleQuote) {
            escapeNext = true;
            hasToken = true;
            continue;
        }

        if (c == u'\'' && !inDoubleQuote) {
            inSingleQuote = !inSingleQuote;
            hasToken = true;
            continue;
        }

        if (c == u'"' && !inSingleQuote) {
            inDoubleQuote = !inDoubleQuote;
            hasToken = true;
            continue;
        }

        if (c.isSpace() && !inSingleQuote && !inDoubleQuote) {
            if (hasToken) {
                args.append(current);
                current.clear();
                hasToken = false;
            }
            continue;
        }

        current.append(c);
        hasToken = true;
    }

    if (escapeNext) {
        current.append(u'\\');
    }

    if (hasToken) {
        args.append(current);
    }

    return args;
}

QStringList parseSearchRoots(const QStringList &inputs) {
    QStringList roots;
    QSet<QString> seen;
    const QString home = QDir::homePath();

    for (const QString &rawInput : inputs) {
        const QStringView inputView = QStringView(rawInput).trimmed();
        if (inputView.isEmpty()) {
            continue;
        }

        for (auto part : QStringTokenizer{inputView, u':'}) {
            for (auto subPart : QStringTokenizer{part, u';'}) {
                const QStringView tokenView = subPart.trimmed();
                if (tokenView.isEmpty()) {
                    continue;
                }

                QString token;
                if (tokenView == u"~") {
                    token = home;
                } else if (tokenView.startsWith(QLatin1StringView("~/"))) {
                    token = home + tokenView.sliced(1).toString();
                } else {
                    token = tokenView.toString();
                }

                QFileInfo fi(token);
                if (fi.exists() && fi.isDir()) {
                    const QString canonical = fi.canonicalFilePath();
                    if (!canonical.isEmpty() && !seen.contains(canonical)) {
                        seen.insert(canonical);
                        roots.append(canonical);
                    }
                }
            }
        }
    }

    if (roots.isEmpty()) {
        const QString canonicalHome = QFileInfo(home).canonicalFilePath();
        roots.append(canonicalHome.isEmpty() ? home : canonicalHome);
    }

    return roots;
}

QStringList parseSearchRoots(const QString &input) {
    if (input.isEmpty()) {
        return parseSearchRoots(QStringList{});
    }
    return parseSearchRoots(QStringList{input});
}

void SearchConfig::loadEnvironment() {
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    if (env.contains(QStringLiteral("KSEEK_PREFIX"))) {
        prefix = env.value(QStringLiteral("KSEEK_PREFIX"));
    } else if (env.contains(QStringLiteral("KSEEK_TRIGGER"))) {
        prefix = env.value(QStringLiteral("KSEEK_TRIGGER"));
    } else if (env.contains(QStringLiteral("KRUNNER_FZF_FD_PREFIX"))) {
        prefix = env.value(QStringLiteral("KRUNNER_FZF_FD_PREFIX"));
    }

    if (env.contains(QStringLiteral("KSEEK_ROOT"))) {
        searchRoots = parseSearchRoots(env.value(QStringLiteral("KSEEK_ROOT")));
    } else if (env.contains(QStringLiteral("KRUNNER_FZF_FD_ROOT"))) {
        searchRoots = parseSearchRoots(env.value(QStringLiteral("KRUNNER_FZF_FD_ROOT")));
    }

    bool ok = false;
    QString maxResultsStr;
    if (env.contains(QStringLiteral("KSEEK_MAX_RESULTS"))) {
        maxResultsStr = env.value(QStringLiteral("KSEEK_MAX_RESULTS"));
    } else if (env.contains(QStringLiteral("KRUNNER_FZF_FD_MAX_RESULTS"))) {
        maxResultsStr = env.value(QStringLiteral("KRUNNER_FZF_FD_MAX_RESULTS"));
    }
    if (!maxResultsStr.isEmpty()) {
        const int maxR = maxResultsStr.toInt(&ok);
        if (ok && maxR > 0) {
            maxResults = maxR;
        }
    }

    QString timeoutStr;
    if (env.contains(QStringLiteral("KSEEK_TIMEOUT"))) {
        timeoutStr = env.value(QStringLiteral("KSEEK_TIMEOUT"));
    } else if (env.contains(QStringLiteral("KRUNNER_FZF_FD_TIMEOUT"))) {
        timeoutStr = env.value(QStringLiteral("KRUNNER_FZF_FD_TIMEOUT"));
    }
    if (!timeoutStr.isEmpty()) {
        const double timeoutSec = timeoutStr.toDouble(&ok);
        if (ok && timeoutSec > 0.0) {
            timeoutMs = static_cast<int>(timeoutSec * 1000.0);
        }
    }

    QString debounceStr;
    if (env.contains(QStringLiteral("KSEEK_DEBOUNCE"))) {
        debounceStr = env.value(QStringLiteral("KSEEK_DEBOUNCE"));
    } else if (env.contains(QStringLiteral("KRUNNER_FZF_FD_DEBOUNCE"))) {
        debounceStr = env.value(QStringLiteral("KRUNNER_FZF_FD_DEBOUNCE"));
    }
    if (!debounceStr.isEmpty()) {
        const int deb = debounceStr.toInt(&ok);
        if (ok && deb >= 0) {
            debounceMs = deb;
        }
    }

    if (env.contains(QStringLiteral("KSEEK_FD_ARGS"))) {
        extraFdArgs = splitArgs(env.value(QStringLiteral("KSEEK_FD_ARGS")));
    }

    if (env.contains(QStringLiteral("KSEEK_FZF_ARGS"))) {
        extraFzfArgs = splitArgs(env.value(QStringLiteral("KSEEK_FZF_ARGS")));
    }

    if (env.contains(QStringLiteral("KSEEK_FD_BIN"))) {
        fdBin = env.value(QStringLiteral("KSEEK_FD_BIN"));
    }

    if (env.contains(QStringLiteral("KSEEK_FZF_BIN"))) {
        fzfBin = env.value(QStringLiteral("KSEEK_FZF_BIN"));
    }
}

SearchConfig SearchConfig::load() {
    SearchConfig cfg;
    cfg.loadEnvironment();
    if (cfg.searchRoots.isEmpty()) {
        cfg.searchRoots = parseSearchRoots(QStringList{});
    }
    return cfg;
}

} // namespace qs::plugins
