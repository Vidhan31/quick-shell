#include "KWinManager.hpp"
#include "WaylandPlasmaBackend.hpp"

namespace qs::plugins::kwin {

KWinManager::KWinManager(QObject *parent)
    : QObject(parent) {
    auto *backend = WaylandPlasmaBackend::instance();

    connect(backend, &WaylandPlasmaBackend::windowsChanged,
            this, &KWinManager::windowsChanged);
    connect(backend, &WaylandPlasmaBackend::availableChanged,
            this, &KWinManager::availableChanged);
}

QAbstractItemModel *KWinManager::model() const {
    return WaylandPlasmaBackend::instance()->model();
}

QVariantList KWinManager::windows() const {
    auto *m = WaylandPlasmaBackend::instance()->model();
    return m ? m->toVariantList() : QVariantList();
}

int KWinManager::count() const {
    auto *m = WaylandPlasmaBackend::instance()->model();
    return m ? m->rowCount() : 0;
}

bool KWinManager::available() const {
    return WaylandPlasmaBackend::instance()->isAvailable();
}

void KWinManager::toggleWindow(const QString &windowId) {
    WaylandPlasmaBackend::instance()->toggleWindow(windowId);
}

void KWinManager::activateWindow(const QString &windowId) {
    WaylandPlasmaBackend::instance()->activateWindow(windowId);
}

void KWinManager::minimizeWindow(const QString &windowId) {
    WaylandPlasmaBackend::instance()->minimizeWindow(windowId);
}

void KWinManager::refresh() {
    WaylandPlasmaBackend::instance()->refresh();
}

} // namespace qs::plugins::kwin
