#pragma once

#include "JobEntry.hpp"

#include <QDBusObjectPath>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <memory>

namespace qs::plugins::kuiserver {

class JobViewV2Adaptor;
class JobViewV3Adaptor;

class JobItem : public QObject {
    Q_OBJECT

public:
    explicit JobItem(uint id,
                     const QString &desktopEntry,
                     int capabilities,
                     const QVariantMap &hints,
                     const QString &clientService,
                     QObject *parent = nullptr);
    ~JobItem() override;

    [[nodiscard]] uint id() const { return m_entry.id; }
    [[nodiscard]] const JobEntry &entry() const { return m_entry; }
    [[nodiscard]] const QDBusObjectPath &objectPath() const { return m_objectPath; }
    [[nodiscard]] const QString &clientService() const { return m_clientService; }

    void updateProperties(const QVariantMap &properties);
    void terminate(uint errorCode, const QString &errorMessage, const QVariantMap &hints = {});

    void cancel();
    void suspend();
    void resume();

    void v2SetTotalAmount(qulonglong amount, const QString &unit);
    void v2SetProcessedAmount(qulonglong amount, const QString &unit);
    void v2SetPercent(uint percent);
    void v2SetSpeed(qulonglong bytesPerSecond);
    void v2SetInfoMessage(const QString &message);
    bool v2SetDescriptionField(uint number, const QString &name, const QString &value);
    void v2ClearDescriptionField(uint number);
    void v2SetDestUrl(const QUrl &url);
    void v2SetError(uint errorCode);
    void v2SetSuspended(bool suspended);

Q_SIGNALS:
    void updated();
    void finished();

private:
    void unregisterDbus();

    JobEntry m_entry;
    QDBusObjectPath m_objectPath;
    QString m_clientService;
    JobViewV2Adaptor *m_v2Adaptor = nullptr;
    JobViewV3Adaptor *m_v3Adaptor = nullptr;
    std::unique_ptr<QTimer> m_killTimer;
    bool m_registered = false;
};

} // namespace qs::plugins::kuiserver
