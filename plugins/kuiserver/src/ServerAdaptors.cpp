#include "ServerAdaptors.hpp"
#include "JobServer.hpp"

namespace qs::plugins::kuiserver {

KuiServerAdaptor::KuiServerAdaptor(JobServer *parent)
    : QDBusAbstractAdaptor(parent) {
    setAutoRelaySignals(true);
}

bool KuiServerAdaptor::requiresJobTracker() {
    return static_cast<JobServer *>(parent())->dbusRequiresJobTracker();
}

void KuiServerAdaptor::emitJobUrlsChanged() {
    // No-op for modern KIO
}

QStringList KuiServerAdaptor::registeredJobContacts() {
    return static_cast<JobServer *>(parent())->dbusRegisteredJobContacts();
}

void KuiServerAdaptor::registerService(const QString &service, const QString &objectPath) {
    Q_UNUSED(service)
    Q_UNUSED(objectPath)
}

JobViewServerAdaptor::JobViewServerAdaptor(JobServer *parent)
    : QDBusAbstractAdaptor(parent) {
    setAutoRelaySignals(true);
}

QDBusObjectPath JobViewServerAdaptor::requestView(const QString &appName, const QString &appIconName, int capabilities) {
    return static_cast<JobServer *>(parent())->dbusRequestView(appName, appIconName, capabilities);
}

JobViewServerV2Adaptor::JobViewServerV2Adaptor(JobServer *parent)
    : QDBusAbstractAdaptor(parent) {
    setAutoRelaySignals(true);
}

QDBusObjectPath JobViewServerV2Adaptor::requestView(const QString &desktopEntry, int capabilities, const QVariantMap &hints) {
    return static_cast<JobServer *>(parent())->dbusRequestViewV2(desktopEntry, capabilities, hints);
}

} // namespace qs::plugins::kuiserver
