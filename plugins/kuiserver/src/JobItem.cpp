#include "JobItem.hpp"
#include "JobAdaptors.hpp"

#include <QDBusConnection>
#include <QDebug>

namespace qs::plugins::kuiserver {

JobItem::JobItem(uint id,
                 const QString &desktopEntry,
                 int capabilities,
                 const QVariantMap &hints,
                 const QString &clientService,
                 QObject *parent)
    : QObject(parent)
    , m_clientService(clientService) {
    m_entry.id = id;
    m_entry.desktopEntry = desktopEntry;
    m_entry.killable = (capabilities & 0x0001) != 0;
    m_entry.suspendable = (capabilities & 0x0002) != 0;
    m_entry.startTime = QDateTime::currentMSecsSinceEpoch();

    m_entry.appName = hints.value(QStringLiteral("application-display-name")).toString();
    m_entry.appIcon = hints.value(QStringLiteral("application-icon-name")).toString();
    if (m_entry.appName.isEmpty() && !desktopEntry.isEmpty()) {
        m_entry.appName = desktopEntry;
        if (m_entry.appName.endsWith(QStringLiteral(".desktop"))) {
            m_entry.appName.chop(8);
        }
    }
    if (m_entry.appIcon.isEmpty()) {
        m_entry.appIcon = desktopEntry;
    }

    if (hints.value(QStringLiteral("transient")).toBool()) {
        m_entry.transient = true;
    }

    m_objectPath.setPath(QStringLiteral("/JobViewServer/Job_%1").arg(id));

    m_v2Adaptor = new JobViewV2Adaptor(this);
    m_v3Adaptor = new JobViewV3Adaptor(this);

    m_registered = QDBusConnection::sessionBus().registerObject(m_objectPath.path(), this);

    updateProperties(hints);
}

JobItem::~JobItem() {
    unregisterDbus();
}

void JobItem::unregisterDbus() {
    if (m_registered) {
        QDBusConnection::sessionBus().unregisterObject(m_objectPath.path());
        m_registered = false;
    }
}

void JobItem::updateProperties(const QVariantMap &properties) {
    if (properties.isEmpty()) {
        return;
    }

    if (properties.contains(QStringLiteral("title"))) {
        m_entry.title = properties.value(QStringLiteral("title")).toString();
    }
    if (properties.contains(QStringLiteral("infoMessage"))) {
        m_entry.infoMessage = properties.value(QStringLiteral("infoMessage")).toString();
    }
    if (properties.contains(QStringLiteral("percent"))) {
        m_entry.percent = properties.value(QStringLiteral("percent")).toUInt();
    }
    if (properties.contains(QStringLiteral("speed"))) {
        m_entry.speed = properties.value(QStringLiteral("speed")).toULongLong();
    }
    if (properties.contains(QStringLiteral("processedBytes"))) {
        m_entry.processedBytes = properties.value(QStringLiteral("processedBytes")).toULongLong();
    }
    if (properties.contains(QStringLiteral("totalBytes"))) {
        m_entry.totalBytes = properties.value(QStringLiteral("totalBytes")).toULongLong();
    }
    if (properties.contains(QStringLiteral("processedFiles"))) {
        m_entry.processedFiles = properties.value(QStringLiteral("processedFiles")).toULongLong();
    }
    if (properties.contains(QStringLiteral("totalFiles"))) {
        m_entry.totalFiles = properties.value(QStringLiteral("totalFiles")).toULongLong();
    }
    if (properties.contains(QStringLiteral("processedItems"))) {
        m_entry.processedItems = properties.value(QStringLiteral("processedItems")).toULongLong();
    }
    if (properties.contains(QStringLiteral("totalItems"))) {
        m_entry.totalItems = properties.value(QStringLiteral("totalItems")).toULongLong();
    }
    if (properties.contains(QStringLiteral("processedDirectories"))) {
        m_entry.processedDirectories = properties.value(QStringLiteral("processedDirectories")).toULongLong();
    }
    if (properties.contains(QStringLiteral("totalDirectories"))) {
        m_entry.totalDirectories = properties.value(QStringLiteral("totalDirectories")).toULongLong();
    }
    if (properties.contains(QStringLiteral("descriptionLabel1"))) {
        m_entry.descriptionLabel1 = properties.value(QStringLiteral("descriptionLabel1")).toString();
    }
    if (properties.contains(QStringLiteral("descriptionValue1"))) {
        m_entry.descriptionValue1 = properties.value(QStringLiteral("descriptionValue1")).toString();
    }
    if (properties.contains(QStringLiteral("descriptionLabel2"))) {
        m_entry.descriptionLabel2 = properties.value(QStringLiteral("descriptionLabel2")).toString();
    }
    if (properties.contains(QStringLiteral("descriptionValue2"))) {
        m_entry.descriptionValue2 = properties.value(QStringLiteral("descriptionValue2")).toString();
    }
    if (properties.contains(QStringLiteral("destUrl"))) {
        const QVariant v = properties.value(QStringLiteral("destUrl"));
        if (v.userType() == QMetaType::QUrl) {
            m_entry.destUrl = v.toUrl();
        } else {
            m_entry.destUrl = QUrl(v.toString());
        }
    }
    if (properties.contains(QStringLiteral("suspended"))) {
        m_entry.suspended = properties.value(QStringLiteral("suspended")).toBool();
        m_entry.state = m_entry.suspended ? JobState::Suspended : JobState::Running;
    }

    Q_EMIT updated();
}

void JobItem::terminate(uint errorCode, const QString &errorMessage, const QVariantMap &hints) {
    Q_UNUSED(hints)
    if (m_killTimer) {
        m_killTimer->stop();
    }

    m_entry.errorCode = errorCode;
    m_entry.errorMessage = errorMessage;
    m_entry.state = JobState::Stopped;
    m_entry.endTime = QDateTime::currentMSecsSinceEpoch();

    unregisterDbus();
    Q_EMIT finished();
}

void JobItem::cancel() {
    Q_EMIT m_v2Adaptor->cancelRequested();
    Q_EMIT m_v3Adaptor->cancelRequested();

    if (!m_killTimer) {
        m_killTimer = std::make_unique<QTimer>(this);
        m_killTimer->setSingleShot(true);
        connect(m_killTimer.get(), &QTimer::timeout, this, [this] {
            terminate(1, QStringLiteral("Operation canceled"));
        });
    }
    if (!m_killTimer->isActive()) {
        m_killTimer->start(3000);
    }
}

void JobItem::suspend() {
    Q_EMIT m_v2Adaptor->suspendRequested();
    Q_EMIT m_v3Adaptor->suspendRequested();
}

void JobItem::resume() {
    Q_EMIT m_v2Adaptor->resumeRequested();
    Q_EMIT m_v3Adaptor->resumeRequested();
}

void JobItem::v2SetTotalAmount(qulonglong amount, const QString &unit) {
    if (unit == QLatin1String("bytes")) {
        m_entry.totalBytes = amount;
    } else if (unit == QLatin1String("files")) {
        m_entry.totalFiles = amount;
    } else if (unit == QLatin1String("dirs")) {
        m_entry.totalDirectories = amount;
    } else if (unit == QLatin1String("items")) {
        m_entry.totalItems = amount;
    }
    Q_EMIT updated();
}

void JobItem::v2SetProcessedAmount(qulonglong amount, const QString &unit) {
    if (unit == QLatin1String("bytes")) {
        m_entry.processedBytes = amount;
    } else if (unit == QLatin1String("files")) {
        m_entry.processedFiles = amount;
    } else if (unit == QLatin1String("dirs")) {
        m_entry.processedDirectories = amount;
    } else if (unit == QLatin1String("items")) {
        m_entry.processedItems = amount;
    }
    Q_EMIT updated();
}

void JobItem::v2SetPercent(uint percent) {
    m_entry.percent = percent;
    Q_EMIT updated();
}

void JobItem::v2SetSpeed(qulonglong bytesPerSecond) {
    m_entry.speed = bytesPerSecond;
    Q_EMIT updated();
}

void JobItem::v2SetInfoMessage(const QString &message) {
    m_entry.infoMessage = message;
    Q_EMIT updated();
}

bool JobItem::v2SetDescriptionField(uint number, const QString &name, const QString &value) {
    if (number == 0) {
        m_entry.descriptionLabel1 = name;
        m_entry.descriptionValue1 = value;
    } else if (number == 1) {
        m_entry.descriptionLabel2 = name;
        m_entry.descriptionValue2 = value;
    }
    Q_EMIT updated();
    return true;
}

void JobItem::v2ClearDescriptionField(uint number) {
    v2SetDescriptionField(number, QString(), QString());
}

void JobItem::v2SetDestUrl(const QUrl &url) {
    m_entry.destUrl = url;
    Q_EMIT updated();
}

void JobItem::v2SetError(uint errorCode) {
    m_entry.errorCode = errorCode;
    Q_EMIT updated();
}

void JobItem::v2SetSuspended(bool suspended) {
    m_entry.suspended = suspended;
    m_entry.state = suspended ? JobState::Suspended : JobState::Running;
    Q_EMIT updated();
}

} // namespace qs::plugins::kuiserver
