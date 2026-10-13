#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusVariant>
#include <QVariantMap>

namespace qs::plugins::kuiserver {

class JobItem;

class JobViewV2Adaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.JobViewV2")

public:
    explicit JobViewV2Adaptor(JobItem *parent);

public Q_SLOTS:
    void terminate(const QString &errorMessage);
    void setSuspended(bool suspended);
    void setTotalAmount(qulonglong amount, const QString &unit);
    void setProcessedAmount(qulonglong amount, const QString &unit);
    void setPercent(uint percent);
    void setSpeed(qulonglong bytesPerSecond);
    void setInfoMessage(const QString &message);
    bool setDescriptionField(uint number, const QString &name, const QString &value);
    void clearDescriptionField(uint number);
    void setDestUrl(const QDBusVariant &destUrl);
    void setError(uint errorCode);

Q_SIGNALS:
    void suspendRequested();
    void resumeRequested();
    void cancelRequested();
};

class JobViewV3Adaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.JobViewV3")

public:
    explicit JobViewV3Adaptor(JobItem *parent);

public Q_SLOTS:
    void terminate(uint errorCode, const QString &errorMessage, const QVariantMap &hints);
    void update(const QVariantMap &properties);

Q_SIGNALS:
    void updateRequested();
    void suspendRequested();
    void resumeRequested();
    void cancelRequested();
};

} // namespace qs::plugins::kuiserver
