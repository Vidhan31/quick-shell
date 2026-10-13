#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QStringList>
#include <QVariantMap>

namespace qs::plugins::kuiserver {

class JobServer;

class KuiServerAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kuiserver")

public:
    explicit KuiServerAdaptor(JobServer *parent);

public Q_SLOTS:
    bool requiresJobTracker();
    void emitJobUrlsChanged();
    QStringList registeredJobContacts();
    void registerService(const QString &service, const QString &objectPath);

Q_SIGNALS:
    void requiresJobTrackerChanged(bool req);
    void jobUrlsChanged(const QStringList &urls);
};

class JobViewServerAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.JobViewServer")

public:
    explicit JobViewServerAdaptor(JobServer *parent);

public Q_SLOTS:
    QDBusObjectPath requestView(const QString &appName, const QString &appIconName, int capabilities);
};

class JobViewServerV2Adaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.JobViewServerV2")

public:
    explicit JobViewServerV2Adaptor(JobServer *parent);

public Q_SLOTS:
    QDBusObjectPath requestView(const QString &desktopEntry, int capabilities, const QVariantMap &hints);
};

} // namespace qs::plugins::kuiserver
