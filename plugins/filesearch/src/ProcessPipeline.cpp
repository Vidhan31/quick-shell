#include "ProcessPipeline.hpp"

#include <QStandardPaths>
#include <QFileInfo>
#include <QDir>
#include <QLoggingCategory>
#include <unistd.h>
#include <signal.h>
#include <ranges>
#include <string_view>

namespace qs::plugins {

Q_LOGGING_CATEGORY(lcPipeline, "qs.filesearch.pipeline")

ProcessPipeline::ProcessPipeline(QObject *parent)
    : QObject(parent),
      m_timer(std::make_unique<QTimer>(this))
{
    m_timer->setSingleShot(true);
    connect(m_timer.get(), &QTimer::timeout, this, &ProcessPipeline::onTimeout);

    detectBinaries();
    detectFdFeatures();
    detectFzfFeatures();
}

ProcessPipeline::~ProcessPipeline() {
    killProcesses();
}

bool ProcessPipeline::isAvailable() const {
    return !m_fdBin.isEmpty() && !m_fzfBin.isEmpty();
}

void ProcessPipeline::setFdBinary(const QString &bin) {
    if (!bin.isEmpty() && QFileInfo(bin).isExecutable()) {
        m_fdBin = bin;
        detectFdFeatures();
    }
}

void ProcessPipeline::setFzfBinary(const QString &bin) {
    if (!bin.isEmpty() && QFileInfo(bin).isExecutable()) {
        m_fzfBin = bin;
        detectFzfFeatures();
    }
}

void ProcessPipeline::detectBinaries() {
    m_fdBin = QStandardPaths::findExecutable(QStringLiteral("fd"));
    if (m_fdBin.isEmpty()) {
        m_fdBin = QStandardPaths::findExecutable(QStringLiteral("fdfind"));
    }
    if (m_fdBin.isEmpty()) {
        const QString home = QDir::homePath();
        const QStringList fallbackPaths = {
            home + QStringLiteral("/.local/bin/fd"),
            home + QStringLiteral("/.cargo/bin/fd"),
            home + QStringLiteral("/.local/bin/fdfind")
        };
        for (const auto &p : fallbackPaths) {
            if (QFileInfo(p).isExecutable()) {
                m_fdBin = p;
                break;
            }
        }
    }

    m_fzfBin = QStandardPaths::findExecutable(QStringLiteral("fzf"));
    if (m_fzfBin.isEmpty()) {
        const QString home = QDir::homePath();
        const QStringList fallbackPaths = {
            home + QStringLiteral("/.local/bin/fzf"),
            home + QStringLiteral("/.cargo/bin/fzf"),
            home + QStringLiteral("/.fzf/bin/fzf")
        };
        for (const auto &p : fallbackPaths) {
            if (QFileInfo(p).isExecutable()) {
                m_fzfBin = p;
                break;
            }
        }
    }

    if (m_fdBin.isEmpty()) {
        qCWarning(lcPipeline) << "Neither 'fd' nor 'fdfind' found on PATH or custom locations";
    }
    if (m_fzfBin.isEmpty()) {
        qCWarning(lcPipeline) << "'fzf' not found on PATH or custom locations";
    }
}

void ProcessPipeline::detectFdFeatures() {
    if (m_fdBin.isEmpty()) {
        return;
    }

    QProcess fdHelp;
    fdHelp.start(m_fdBin, {QStringLiteral("--help")});
    if (fdHelp.waitForFinished(2000)) {
        const QString out = QString::fromUtf8(fdHelp.readAllStandardOutput() + fdHelp.readAllStandardError());
        m_fdFeatures.searchPath = out.contains(QLatin1StringView("--search-path"));
    }
}

void ProcessPipeline::detectFzfFeatures() {
    if (m_fzfBin.isEmpty()) {
        return;
    }

    QProcess fzfHelp;
    fzfHelp.start(m_fzfBin, {QStringLiteral("--help")});
    if (fzfHelp.waitForFinished(2000)) {
        const QString out = QString::fromUtf8(fzfHelp.readAllStandardOutput() + fzfHelp.readAllStandardError());
        m_features.read0 = out.contains(QLatin1StringView("--read0"));
        m_features.print0 = out.contains(QLatin1StringView("--print0"));
        m_features.noPrintQuery = out.contains(QLatin1StringView("--print-query"));
    }
}

void ProcessPipeline::startSearch(quint64 requestId,
                                 const QStringList &searchRoots,
                                 const QString &query,
                                 const QStringList &extraFdArgs,
                                 const QStringList &extraFzfArgs,
                                 int maxResults,
                                 int timeoutMs)
{
    if (!isAvailable()) {
        if (m_fdBin.isEmpty()) {
            emit searchError(requestId, QStringLiteral("'fd' is not installed or not on PATH"));
        } else {
            emit searchError(requestId, QStringLiteral("'fzf' is not installed or not on PATH"));
        }
        return;
    }

    killProcesses();

    m_activeRequestId = requestId;
    m_maxResults = maxResults;
    m_useNullIo = m_features.read0 && m_features.print0;
    m_outputBuffer.clear();
    m_accumulatedPaths.clear();

    const QStringList validRoots = searchRoots.isEmpty() ? QStringList{QDir::homePath()} : searchRoots;

    QStringList fdArgs;
    fdArgs << QStringLiteral("--color=never");

    if (validRoots.size() == 1) {
        fdArgs << QStringLiteral("--base-directory") << validRoots.first();
    } else {
        if (m_fdFeatures.searchPath) {
            for (const QString &root : validRoots) {
                fdArgs << QStringLiteral("--search-path") << root;
            }
        } else {
            fdArgs << QStringLiteral(".");
            fdArgs.append(validRoots);
        }
    }

    if (!extraFdArgs.isEmpty()) {
        fdArgs.append(extraFdArgs);
    }
    if (m_useNullIo) {
        fdArgs << QStringLiteral("--print0");
    }

    QStringList fzfArgs;
    fzfArgs << (QStringLiteral("--filter=") + query);
    if (m_useNullIo) {
        fzfArgs << QStringLiteral("--read0") << QStringLiteral("--print0");
    }
    if (m_features.noPrintQuery) {
        fzfArgs << QStringLiteral("--no-print-query");
    }
    if (!extraFzfArgs.isEmpty()) {
        fzfArgs.append(extraFzfArgs);
    }

    m_fdProc = std::make_unique<QProcess>();
    m_fzfProc = std::make_unique<QProcess>();

    const QString workingDir = validRoots.first();
    m_fdProc->setWorkingDirectory(workingDir);
    m_fzfProc->setWorkingDirectory(workingDir);

    auto childModifier = []() {
        ::setpgid(0, 0);
    };
    m_fdProc->setChildProcessModifier(childModifier);
    m_fzfProc->setChildProcessModifier(childModifier);

    m_fdProc->setStandardOutputProcess(m_fzfProc.get());

    connect(m_fzfProc.get(), &QProcess::readyReadStandardOutput, this, &ProcessPipeline::onFzfReadyRead);
    connect(m_fzfProc.get(), &QProcess::finished, this, &ProcessPipeline::onFzfFinished);

    auto errorHandler = [this, requestId](QProcess::ProcessError error) {
        qCWarning(lcPipeline) << "Subprocess error occurred for requestId:" << requestId << "error:" << error;
        m_accumulatedPaths.clear();
        m_outputBuffer.clear();
        killProcesses();
        emit searchError(requestId, QStringLiteral("Process execution failed"));
    };
    connect(m_fdProc.get(), &QProcess::errorOccurred, this, errorHandler);
    connect(m_fzfProc.get(), &QProcess::errorOccurred, this, errorHandler);

    m_timer->start(timeoutMs > 0 ? timeoutMs : 5000);

    qCInfo(lcPipeline) << "Running:" << m_fdBin << fdArgs.join(u' ') << "|" << m_fzfBin << fzfArgs.join(u' ');
    m_fdProc->start(m_fdBin, fdArgs, QIODevice::ReadOnly);
    m_fzfProc->start(m_fzfBin, fzfArgs, QIODevice::ReadOnly);
}

void ProcessPipeline::cancel() {
    m_accumulatedPaths.clear();
    m_outputBuffer.clear();
    killProcesses();
}

void ProcessPipeline::killProcesses() {
    if (m_timer && m_timer->isActive()) {
        m_timer->stop();
    }

    auto reap = [this](std::unique_ptr<QProcess> &proc) {
        if (!proc) return;
        proc->disconnect(this);
        if (proc->state() != QProcess::NotRunning) {
            const qint64 pid = proc->processId();
            if (pid > 0) {
                ::kill(-static_cast<pid_t>(pid), SIGKILL);
            }
            auto *raw = proc.release();
            connect(raw, &QProcess::finished, raw, &QObject::deleteLater);
            return;
        }
        proc.reset();
    };

    reap(m_fdProc);
    reap(m_fzfProc);
}

void ProcessPipeline::onFzfReadyRead() {
    if (!m_fzfProc) {
        return;
    }

    m_outputBuffer.append(m_fzfProc->readAllStandardOutput());
    const char delimiter = m_useNullIo ? '\0' : '\n';

    int start = 0;
    while (true) {
        int idx = m_outputBuffer.indexOf(delimiter, start);
        if (idx == -1) {
            break;
        }

        QByteArray token = m_outputBuffer.mid(start, idx - start);
        if (!m_useNullIo && token.endsWith('\r')) {
            token.chop(1);
        }
        if (!token.isEmpty()) {
            m_accumulatedPaths.append(QString::fromUtf8(token));
            if (m_accumulatedPaths.size() >= m_maxResults) {
                const quint64 reqId = m_activeRequestId;
                const QStringList results = m_accumulatedPaths;
                m_accumulatedPaths.clear();
                m_outputBuffer.clear();
                killProcesses();
                emit searchFinished(reqId, results);
                return;
            }
        }
        start = idx + 1;
    }

    if (start > 0) {
        m_outputBuffer.remove(0, start);
    }
}

void ProcessPipeline::onFzfFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/) {
    if (m_timer) {
        m_timer->stop();
    }

    const quint64 reqId = m_activeRequestId;

    if (!m_fzfProc) {
        return;
    }

    m_outputBuffer.append(m_fzfProc->readAllStandardOutput());
    const QByteArray rawStderr = m_fzfProc->readAllStandardError();

    if (exitCode != 0 && exitCode != 1) {
        const QString err = QString::fromUtf8(rawStderr).trimmed();
        qCWarning(lcPipeline) << "fzf exited with code" << exitCode << ":" << err;
        m_accumulatedPaths.clear();
        m_outputBuffer.clear();
        killProcesses();
        emit searchError(reqId, QStringLiteral("fzf error: ") + err.left(120));
        return;
    }

    const char delimiter = m_useNullIo ? '\0' : '\n';
    int start = 0;
    while (m_accumulatedPaths.size() < m_maxResults) {
        int idx = m_outputBuffer.indexOf(delimiter, start);
        if (idx == -1) {
            if (start < m_outputBuffer.size()) {
                QByteArray token = m_outputBuffer.mid(start);
                if (!m_useNullIo && token.endsWith('\r')) {
                    token.chop(1);
                }
                if (!token.isEmpty()) {
                    m_accumulatedPaths.append(QString::fromUtf8(token));
                }
            }
            break;
        }

        QByteArray token = m_outputBuffer.mid(start, idx - start);
        if (!m_useNullIo && token.endsWith('\r')) {
            token.chop(1);
        }
        if (!token.isEmpty()) {
            m_accumulatedPaths.append(QString::fromUtf8(token));
        }
        start = idx + 1;
    }

    const QStringList results = m_accumulatedPaths;
    m_accumulatedPaths.clear();
    m_outputBuffer.clear();

    qCInfo(lcPipeline) << "Parsed" << results.size() << "paths from fzf output";
    killProcesses();
    emit searchFinished(reqId, results);
}

void ProcessPipeline::onTimeout() {
    qCWarning(lcPipeline) << "Search request" << m_activeRequestId << "timed out";
    const quint64 reqId = m_activeRequestId;
    m_accumulatedPaths.clear();
    m_outputBuffer.clear();
    killProcesses();
    emit searchFinished(reqId, QStringList());
}

} // namespace qs::plugins
