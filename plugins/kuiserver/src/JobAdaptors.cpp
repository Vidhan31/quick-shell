#include "JobAdaptors.hpp"
#include "JobItem.hpp"

namespace qs::plugins::kuiserver {

JobViewV2Adaptor::JobViewV2Adaptor(JobItem *parent)
    : QDBusAbstractAdaptor(parent) {
    setAutoRelaySignals(true);
}

void JobViewV2Adaptor::terminate(const QString &errorMessage) {
    static_cast<JobItem *>(parent())->terminate(errorMessage.isEmpty() ? 0 : 1, errorMessage);
}

void JobViewV2Adaptor::setSuspended(bool suspended) {
    static_cast<JobItem *>(parent())->v2SetSuspended(suspended);
}

void JobViewV2Adaptor::setTotalAmount(qulonglong amount, const QString &unit) {
    static_cast<JobItem *>(parent())->v2SetTotalAmount(amount, unit);
}

void JobViewV2Adaptor::setProcessedAmount(qulonglong amount, const QString &unit) {
    static_cast<JobItem *>(parent())->v2SetProcessedAmount(amount, unit);
}

void JobViewV2Adaptor::setPercent(uint percent) {
    static_cast<JobItem *>(parent())->v2SetPercent(percent);
}

void JobViewV2Adaptor::setSpeed(qulonglong bytesPerSecond) {
    static_cast<JobItem *>(parent())->v2SetSpeed(bytesPerSecond);
}

void JobViewV2Adaptor::setInfoMessage(const QString &message) {
    static_cast<JobItem *>(parent())->v2SetInfoMessage(message);
}

bool JobViewV2Adaptor::setDescriptionField(uint number, const QString &name, const QString &value) {
    return static_cast<JobItem *>(parent())->v2SetDescriptionField(number, name, value);
}

void JobViewV2Adaptor::clearDescriptionField(uint number) {
    static_cast<JobItem *>(parent())->v2ClearDescriptionField(number);
}

void JobViewV2Adaptor::setDestUrl(const QDBusVariant &destUrl) {
    static_cast<JobItem *>(parent())->v2SetDestUrl(destUrl.variant().toUrl());
}

void JobViewV2Adaptor::setError(uint errorCode) {
    static_cast<JobItem *>(parent())->v2SetError(errorCode);
}

JobViewV3Adaptor::JobViewV3Adaptor(JobItem *parent)
    : QDBusAbstractAdaptor(parent) {
    setAutoRelaySignals(true);
}

void JobViewV3Adaptor::terminate(uint errorCode, const QString &errorMessage, const QVariantMap &hints) {
    static_cast<JobItem *>(parent())->terminate(errorCode, errorMessage, hints);
}

void JobViewV3Adaptor::update(const QVariantMap &properties) {
    static_cast<JobItem *>(parent())->updateProperties(properties);
}

} // namespace qs::plugins::kuiserver
