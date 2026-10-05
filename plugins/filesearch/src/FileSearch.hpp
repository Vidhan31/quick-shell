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
    Q_PROPERTY(QString prefix READ prefix CONSTANT)

public:
    explicit FileSearch(QObject *parent = nullptr);
    ~FileSearch() override;
    QString query() const { return m_query; }
    QVariantList results() const { return m_results; }
    bool searching() const { return m_searching; }
    bool available() const { return m_pipeline.isAvailable(); }
    QString prefix() const { return m_config.prefix; }

    Q_INVOKABLE bool isSearchQuery(const QString &raw) const;
    Q_INVOKABLE QString searchTerm(const QString &raw) const;
    Q_INVOKABLE void cancel();

public slots:
    void setQuery(const QString &query);

signals:
    void queryChanged();
    void resultsChanged();
    void searchingChanged();

private slots:
    void onDebounceTimeout();
    void onPipelineFinished(quint64 requestId, const QStringList &paths);
    void onPipelineError(quint64 requestId, const QString &errorMessage);

private:
    QVariantMap buildResult(const QString &relPath);
    static QString toDisplayPath(const QString &path);

    SearchConfig m_config;
    ProcessPipeline m_pipeline;
    SearchIconResolver m_iconResolver;

    QString m_query;
    QVariantList m_results;
    bool m_searching = false;

    QTimer m_debounceTimer;
    quint64 m_currentRequestId = 0;
    quint64 m_pendingRequestId = 0;
    QString m_pendingTerm;
};

} // namespace qs::plugins
