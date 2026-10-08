#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>

#include "ProcessPipeline.hpp"
#include "SearchConfig.hpp"
#include "SearchIconResolver.hpp"

namespace qs::plugins {

class FileSearch : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QString prefix READ prefix WRITE setPrefix NOTIFY prefixChanged)
    Q_PROPERTY(QStringList searchRoots READ searchRoots WRITE setSearchRoots NOTIFY searchRootsChanged)
    Q_PROPERTY(int maxResults READ maxResults WRITE setMaxResults NOTIFY maxResultsChanged)
    Q_PROPERTY(int timeoutMs READ timeoutMs WRITE setTimeoutMs NOTIFY timeoutMsChanged)
    Q_PROPERTY(int debounceMs READ debounceMs WRITE setDebounceMs NOTIFY debounceMsChanged)
    Q_PROPERTY(QStringList extraFdArgs READ extraFdArgs WRITE setExtraFdArgs NOTIFY extraFdArgsChanged)
    Q_PROPERTY(QStringList extraFzfArgs READ extraFzfArgs WRITE setExtraFzfArgs NOTIFY extraFzfArgsChanged)

public:
    explicit FileSearch(QObject *parent = nullptr);
    ~FileSearch() override;
    QString query() const { return m_query; }
    QVariantList results() const { return m_results; }
    bool searching() const { return m_searching; }
    bool available() const { return m_pipeline.isAvailable(); }

    QString prefix() const { return m_config.prefix; }
    void setPrefix(const QString &p);

    QStringList searchRoots() const { return m_config.searchRoots; }
    void setSearchRoots(const QStringList &r);

    int maxResults() const { return m_config.maxResults; }
    void setMaxResults(int m);

    int timeoutMs() const { return m_config.timeoutMs; }
    void setTimeoutMs(int t);

    int debounceMs() const { return m_config.debounceMs; }
    void setDebounceMs(int d);

    QStringList extraFdArgs() const { return m_config.extraFdArgs; }
    void setExtraFdArgs(const QStringList &a);

    QStringList extraFzfArgs() const { return m_config.extraFzfArgs; }
    void setExtraFzfArgs(const QStringList &a);

    Q_INVOKABLE bool isSearchQuery(const QString &raw) const;
    Q_INVOKABLE QString searchTerm(const QString &raw) const;
    Q_INVOKABLE void cancel();

public slots:
    void setQuery(const QString &query);

signals:
    void queryChanged();
    void resultsChanged();
    void searchingChanged();
    void prefixChanged();
    void searchRootsChanged();
    void maxResultsChanged();
    void timeoutMsChanged();
    void debounceMsChanged();
    void extraFdArgsChanged();
    void extraFzfArgsChanged();

private slots:
    void onDebounceTimeout();
    void onPipelineFinished(quint64 requestId, const QStringList &paths);
    void onPipelineError(quint64 requestId, const QString &errorMessage);

private:
    QVariantMap buildResult(const QString &relPath);
    static QString toDisplayPath(const QString &path);
    int computeDebounceMs(const QString &term, const QString &prevTerm) const;
    bool tryInMemoryNarrowing(const QString &term);

    SearchConfig m_config;
    ProcessPipeline m_pipeline;
    SearchIconResolver m_iconResolver;

    QString m_query;
    QVariantList m_results;
    bool m_searching = false;

    QString m_lastCompletedTerm;
    int m_lastCompletedCount = 0;



    QTimer m_debounceTimer;
    quint64 m_currentRequestId = 0;
    quint64 m_pendingRequestId = 0;
    QString m_pendingTerm;
};

} // namespace qs::plugins
