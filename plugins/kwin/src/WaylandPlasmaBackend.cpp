#include "WaylandPlasmaBackend.hpp"

#include <QCoreApplication>

namespace qs::plugins::kwin {

using WmState = QtWayland::org_kde_plasma_window_management;

PlasmaWindow::PlasmaWindow(const QString &uuid, struct ::org_kde_plasma_window *obj, QObject *parent)
    : QObject(parent)
    , QtWayland::org_kde_plasma_window(obj)
    , m_uuid(uuid) {
}

PlasmaWindow::~PlasmaWindow() {
    if (isInitialized() && !QCoreApplication::closingDown()) {
        destroy();
    }
}

bool PlasmaWindow::skipTaskbar() const {
    return (m_flags & WmState::state_skiptaskbar) != 0;
}

WindowRecord PlasmaWindow::toRecord() const {
    WindowRecord rec;
    rec.id = m_uuid;
    rec.appId = m_appId;
    rec.title = m_title;
    rec.icon = m_icon;
    rec.active = (m_flags & WmState::state_active) != 0;
    rec.minimized = (m_flags & WmState::state_minimized) != 0;
    rec.maximized = (m_flags & WmState::state_maximized) != 0;
    rec.fullscreen = (m_flags & WmState::state_fullscreen) != 0;
    return rec;
}

void PlasmaWindow::toggle() {
    if (m_flags & WmState::state_active) {
        set_state(WmState::state_minimized, WmState::state_minimized);
    } else {
        if (m_flags & WmState::state_minimized) {
            set_state(WmState::state_minimized, 0);
        }
        set_state(WmState::state_active, WmState::state_active);
    }
}

void PlasmaWindow::activate() {
    if (m_flags & WmState::state_minimized) {
        set_state(WmState::state_minimized, 0);
    }
    set_state(WmState::state_active, WmState::state_active);
}

void PlasmaWindow::minimize() {
    set_state(WmState::state_minimized, WmState::state_minimized);
}

void PlasmaWindow::org_kde_plasma_window_title_changed(const QString &title) {
    m_title = title;
    if (m_ready) {
        Q_EMIT changed();
    }
}

void PlasmaWindow::org_kde_plasma_window_app_id_changed(const QString &app_id) {
    m_appId = app_id;
    if (m_ready) {
        Q_EMIT changed();
    }
}

void PlasmaWindow::org_kde_plasma_window_themed_icon_name_changed(const QString &name) {
    m_icon = name;
    if (m_ready) {
        Q_EMIT changed();
    }
}

void PlasmaWindow::org_kde_plasma_window_state_changed(uint32_t flags) {
    m_flags = flags;
    if (m_ready) {
        Q_EMIT changed();
    }
}

void PlasmaWindow::org_kde_plasma_window_initial_state() {
    m_ready = true;
    Q_EMIT ready();
}

void PlasmaWindow::org_kde_plasma_window_unmapped() {
    Q_EMIT unmapped();
}

PlasmaWindowManagement::PlasmaWindowManagement(QObject *parent)
    : QWaylandClientExtensionTemplate<PlasmaWindowManagement>(18) {
    setParent(parent);
}

PlasmaWindowManagement::~PlasmaWindowManagement() = default;

void PlasmaWindowManagement::org_kde_plasma_window_management_window_with_uuid(uint32_t id, const QString &uuid) {
    Q_UNUSED(id)
    struct ::org_kde_plasma_window *rawWin = get_window_by_uuid(uuid);
    if (rawWin) {
        Q_EMIT windowCreated(uuid, rawWin);
    }
}

void PlasmaWindowManagement::org_kde_plasma_window_management_window(uint32_t id) {
    struct ::org_kde_plasma_window *rawWin = get_window(id);
    if (rawWin) {
        const QString fallbackUuid = QStringLiteral("win_%1").arg(id);
        Q_EMIT windowCreated(fallbackUuid, rawWin);
    }
}

WaylandPlasmaBackend *WaylandPlasmaBackend::instance() {
    static WaylandPlasmaBackend s_instance;
    return &s_instance;
}

WaylandPlasmaBackend::WaylandPlasmaBackend(QObject *parent)
    : QObject(parent)
    , m_model(new WindowModel(this)) {
    m_extension = new PlasmaWindowManagement(this);

    connect(m_extension, &QWaylandClientExtension::activeChanged,
            this, &WaylandPlasmaBackend::handleExtensionActiveChanged);
    connect(m_extension, &PlasmaWindowManagement::windowCreated,
            this, &WaylandPlasmaBackend::handleWindowCreated);

    if (QCoreApplication::instance()) {
        connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this]() {
            for (PlasmaWindow *win : std::as_const(m_windows)) {
                delete win;
            }
            m_windows.clear();
            m_model->clear();
        });
    }

    if (m_extension->isActive()) {
        handleExtensionActiveChanged();
    }
}

void WaylandPlasmaBackend::handleExtensionActiveChanged() {
    const bool active = m_extension->isActive();
    if (m_available == active) {
        return;
    }

    m_available = active;
    if (!m_available) {
        for (PlasmaWindow *win : std::as_const(m_windows)) {
            win->deleteLater();
        }
        m_windows.clear();
        m_model->clear();
        Q_EMIT windowsChanged();
    }
    Q_EMIT availableChanged(m_available);
}

void WaylandPlasmaBackend::handleWindowCreated(const QString &uuid, struct ::org_kde_plasma_window *rawWindow) {
    if (m_windows.contains(uuid)) {
        return;
    }

    auto *win = new PlasmaWindow(uuid, rawWindow, this);
    m_windows.insert(uuid, win);

    connect(win, &PlasmaWindow::ready, this, [this, win]() {
        handleWindowReady(win);
    });
    connect(win, &PlasmaWindow::changed, this, [this, win]() {
        handleWindowChanged(win);
    });
    connect(win, &PlasmaWindow::unmapped, this, [this, uuid]() {
        handleWindowUnmapped(uuid);
    });
}

void WaylandPlasmaBackend::handleWindowReady(PlasmaWindow *win) {
    if (!win->skipTaskbar()) {
        m_model->addRecord(win->toRecord());
        Q_EMIT windowsChanged();
    }
}

void WaylandPlasmaBackend::handleWindowChanged(PlasmaWindow *win) {
    if (win->skipTaskbar()) {
        m_model->removeRecord(win->uuid());
    } else {
        m_model->updateRecord(win->toRecord());
    }
    Q_EMIT windowsChanged();
}

void WaylandPlasmaBackend::handleWindowUnmapped(const QString &uuid) {
    PlasmaWindow *win = m_windows.take(uuid);
    m_model->removeRecord(uuid);
    Q_EMIT windowsChanged();

    if (win) {
        win->deleteLater();
    }
}

void WaylandPlasmaBackend::toggleWindow(const QString &id) {
    PlasmaWindow *win = m_windows.value(id);
    if (win) {
        win->toggle();
    }
}

void WaylandPlasmaBackend::activateWindow(const QString &id) {
    PlasmaWindow *win = m_windows.value(id);
    if (win) {
        win->activate();
    }
}

void WaylandPlasmaBackend::minimizeWindow(const QString &id) {
    PlasmaWindow *win = m_windows.value(id);
    if (win) {
        win->minimize();
    }
}

void WaylandPlasmaBackend::refresh() {
    Q_EMIT windowsChanged();
}

} // namespace qs::plugins::kwin
