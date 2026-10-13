#pragma once

#include <QtQml/qqmlregistration.h>

#include <QFileSystemWatcher>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace qs::plugins {

class HolidayProvider : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString icsPath READ icsPath WRITE setIcsPath NOTIFY icsPathChanged)
    Q_PROPERTY(QVariantMap eventsByDate READ eventsByDate NOTIFY eventsChanged)
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY loadedChanged)

public:
    explicit HolidayProvider(QObject *parent = nullptr);
    ~HolidayProvider() override = default;

    [[nodiscard]] QString icsPath() const { return m_icsPath; }
    void setIcsPath(const QString &path);

    [[nodiscard]] QVariantMap eventsByDate() const { return m_eventsByDate; }
    [[nodiscard]] bool isLoaded() const { return m_loaded; }

    Q_INVOKABLE QVariantList eventsForDate(const QVariant &dateVal) const;
    Q_INVOKABLE bool hasEvents(const QVariant &dateVal) const;
    Q_INVOKABLE void loadEvents();
    Q_INVOKABLE void reload();

signals:
    void icsPathChanged();
    void eventsChanged();
    void loadedChanged();

private:
    void triggerLoad();

    QString m_icsPath;
    QVariantMap m_eventsByDate;
    bool m_loaded{false};
    quint64 m_requestId{0};
    QFileSystemWatcher m_watcher;
};

} // namespace qs::plugins
