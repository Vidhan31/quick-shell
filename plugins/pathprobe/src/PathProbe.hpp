#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace qs::plugins {

class PathProbe : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantMap result READ result NOTIFY resultChanged)
    Q_PROPERTY(QString query READ query NOTIFY queryChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)

public:
    explicit PathProbe(QObject *parent = nullptr);
    ~PathProbe() override;

    [[nodiscard]] QVariantMap result() const { return m_result; }
    [[nodiscard]] QString query() const { return m_query; }
    [[nodiscard]] bool isBusy() const { return m_busy; }

    [[nodiscard]] Q_INVOKABLE bool looksLikePath(const QString &text) const;
    [[nodiscard]] Q_INVOKABLE QVariantMap classify(const QString &text) const;
    Q_INVOKABLE void classifyAsync(const QString &text);

    Q_INVOKABLE void reveal(const QString &absPath, bool isDir);
    Q_INVOKABLE bool copyFile(const QString &absPath);
    Q_INVOKABLE bool openWith(const QString &absPath);

signals:
    void resultChanged();
    void queryChanged();
    void busyChanged();

private:
    void _fallbackToCli(const QString &absPath, bool isDir) const;

    quint64 m_requestId{0};
    QString m_query;
    QVariantMap m_result;
    bool m_busy{false};
};

} // namespace qs::plugins
