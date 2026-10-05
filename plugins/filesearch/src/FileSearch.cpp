#include "FileSearch.hpp"

#include <QDir>
#include <QFileInfo>
#include <QStringView>

namespace qs::plugins {

FileSearch::FileSearch(QObject *parent)
    : QObject(parent),
      m_config(SearchConfig::load()),
      m_pipeline(this)
{
    if (!m_config.fdBin.isEmpty()) {
        m_pipeline.setFdBinary(m_config.fdBin);
    }
    if (!m_config.fzfBin.isEmpty()) {
        m_pipeline.setFzfBinary(m_config.fzfBin);
    }

    m_debounceTimer.setSingleShot(true);
    connect(&m_debounceTimer, &QTimer::timeout, this, &FileSearch::onDebounceTimeout);

    connect(&m_pipeline, &ProcessPipeline::searchFinished, this, &FileSearch::onPipelineFinished);
    connect(&m_pipeline, &ProcessPipeline::searchError, this, &FileSearch::onPipelineError);
}

FileSearch::~FileSearch() {
    m_debounceTimer.stop();
    m_pipeline.cancel();
}

bool FileSearch::isSearchQuery(const QString &raw) const {
    const QString trimmed = raw.trimmed();
    if (trimmed.isEmpty()) {
        return false;
    }

    if (m_config.prefix.isEmpty()) {
        return true;
    }

    if (trimmed.size() < m_config.prefix.size()) {
        return false;
    }

    if (!trimmed.startsWith(m_config.prefix, Qt::CaseInsensitive)) {
        return false;
    }

    if (raw.size() > m_config.prefix.size()) {
        const QChar sep = raw.at(m_config.prefix.size());
        if (sep == u' ' || sep == u'\t' || sep == u':') {
            return true;
        }
    }

    return false;
}

QString FileSearch::searchTerm(const QString &raw) const {
    if (m_config.prefix.isEmpty()) {
        return raw.trimmed();
    }

    if (!raw.startsWith(m_config.prefix, Qt::CaseInsensitive)) {
        return QString();
    }

    QStringView rem = QStringView(raw).sliced(m_config.prefix.size());
    if (rem.startsWith(u':')) {
        rem = rem.sliced(1);
    }
    while (!rem.isEmpty() && rem.at(0).isSpace()) {
        rem = rem.sliced(1);
    }

    return rem.toString().trimmed();
}

void FileSearch::setQuery(const QString &query) {
    if (m_query == query) {
        return;
    }
    m_query = query;
    emit queryChanged();

    m_debounceTimer.stop();
    m_pipeline.cancel();

    const QString term = m_query.trimmed();
    if (term.isEmpty()) {
        m_searching = false;
        emit searchingChanged();
        if (!m_results.isEmpty()) {
            m_results.clear();
            emit resultsChanged();
        }
        return;
    }

    const quint64 reqId = ++m_currentRequestId;
    m_pendingRequestId = reqId;
    m_pendingTerm = term;

    if (m_config.debounceMs <= 0) {
        m_searching = true;
        emit searchingChanged();
        m_pipeline.startSearch(reqId, m_config.searchRoots, term, m_config.extraFdArgs, m_config.extraFzfArgs, m_config.maxResults, m_config.timeoutMs);
    } else {
        m_debounceTimer.start(m_config.debounceMs);
    }
}

void FileSearch::cancel() {
    m_debounceTimer.stop();
    m_pipeline.cancel();
    if (m_searching) {
        m_searching = false;
        emit searchingChanged();
    }
}

void FileSearch::onDebounceTimeout() {
    if (m_pendingRequestId != m_currentRequestId || m_pendingTerm.isEmpty()) {
        return;
    }
    m_searching = true;
    emit searchingChanged();
    m_pipeline.startSearch(m_pendingRequestId, m_config.searchRoots, m_pendingTerm, m_config.extraFdArgs, m_config.extraFzfArgs, m_config.maxResults, m_config.timeoutMs);
}

void FileSearch::onPipelineFinished(quint64 requestId, const QStringList &paths) {
    if (requestId != m_currentRequestId) {
        return;
    }
    m_searching = false;
    emit searchingChanged();

    QVariantList list;
    list.reserve(paths.size());

    for (const QString &p : paths) {
        QVariantMap item = buildResult(p);
        if (!item.isEmpty()) {
            list.append(item);
        }
    }

    m_results = list;
    emit resultsChanged();
}

void FileSearch::onPipelineError(quint64 requestId, const QString &/*errorMessage*/) {
    if (requestId != m_currentRequestId) {
        return;
    }
    m_searching = false;
    emit searchingChanged();
    m_results.clear();
    emit resultsChanged();
}

QString FileSearch::toDisplayPath(const QString &path) {
    const QString home = QDir::homePath();
    if (path == home) {
        return QStringLiteral("~");
    }
    if (path.startsWith(home + u'/')) {
        return QStringLiteral("~") + path.sliced(home.size());
    }

    const QString canonicalHome = QFileInfo(home).canonicalFilePath();
    if (!canonicalHome.isEmpty() && canonicalHome != home) {
        if (path == canonicalHome) {
            return QStringLiteral("~");
        }
        if (path.startsWith(canonicalHome + u'/')) {
            return QStringLiteral("~") + path.sliced(canonicalHome.size());
        }
    }

    return path;
}

QVariantMap FileSearch::buildResult(const QString &relPath) {
    QString cleanRel = relPath;
    if (cleanRel.startsWith(QLatin1StringView("./"))) {
        cleanRel.remove(0, 2);
    }
    while (cleanRel.endsWith(u'/') && cleanRel.size() > 1) {
        cleanRel.chop(1);
    }

    QString fullPath;
    if (cleanRel.startsWith(u'/')) {
        fullPath = cleanRel;
    } else {
        const QString base = m_config.searchRoots.isEmpty() ? QDir::homePath() : m_config.searchRoots.first();
        fullPath = base.endsWith(u'/')
            ? (base + cleanRel)
            : (base + u'/' + cleanRel);
    }

    QFileInfo fi(fullPath);
    if (!fi.exists()) {
        return {};
    }

    const bool isDir = fi.isDir();
    const qsizetype lastSlash = cleanRel.lastIndexOf(u'/');
    QString name = (lastSlash == -1) ? cleanRel : cleanRel.sliced(lastSlash + 1);
    if (name.isEmpty()) {
        name = toDisplayPath(fullPath);
    }

    const QString parent = fi.absolutePath();
    const QString displayPath = toDisplayPath(fullPath);
    const QString iconName = m_iconResolver.resolve(fullPath, isDir);

    QVariantMap res;
    res.insert(QStringLiteral("id"), QStringLiteral("file:") + fullPath);
    res.insert(QStringLiteral("kind"), QStringLiteral("file"));
    res.insert(QStringLiteral("name"), name);
    res.insert(QStringLiteral("generic"), displayPath);
    res.insert(QStringLiteral("iconName"), iconName);
    res.insert(QStringLiteral("abs"), fullPath);
    res.insert(QStringLiteral("parent"), parent);
    res.insert(QStringLiteral("isDir"), isDir);
    return res;
}

} // namespace qs::plugins
