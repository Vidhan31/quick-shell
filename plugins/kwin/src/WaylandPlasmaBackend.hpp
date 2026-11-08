#pragma once

#include "WindowModel.hpp"
#include "qwayland-plasma-window-management.h"

#include <QtWaylandClient/qwaylandclientextension.h>
#include <QHash>
#include <QObject>
#include <QString>
#include <memory>

namespace qs::plugins::kwin {

class PlasmaWindow : public QObject, public QtWayland::org_kde_plasma_window {
    Q_OBJECT

public:
    PlasmaWindow(const QString &uuid, struct ::org_kde_plasma_window *obj, QObject *parent = nullptr);
    ~PlasmaWindow() override;

    [[nodiscard]] QString uuid() const { return m_uuid; }
    [[nodiscard]] QString appId() const { return m_appId; }
    [[nodiscard]] QString title() const { return m_title; }
    [[nodiscard]] QString icon() const { return m_icon; }
    [[nodiscard]] uint32_t flags() const { return m_flags; }
    [[nodiscard]] bool isReady() const { return m_ready; }
    [[nodiscard]] bool skipTaskbar() const;

    [[nodiscard]] WindowRecord toRecord() const;

    void toggle();
    void activate();
    void minimize();

Q_SIGNALS:
    void ready();
    void changed();
    void unmapped();

protected:
    void org_kde_plasma_window_title_changed(const QString &title) override;
    void org_kde_plasma_window_app_id_changed(const QString &app_id) override;
    void org_kde_plasma_window_themed_icon_name_changed(const QString &name) override;
    void org_kde_plasma_window_state_changed(uint32_t flags) override;
    void org_kde_plasma_window_initial_state() override;
    void org_kde_plasma_window_unmapped() override;

private:
    QString m_uuid;
    QString m_appId;
    QString m_title;
    QString m_icon;
    uint32_t m_flags{0};
    bool m_ready{false};
};

class PlasmaWindowManagement : public QWaylandClientExtensionTemplate<PlasmaWindowManagement>
                             , public QtWayland::org_kde_plasma_window_management {
    Q_OBJECT

public:
    explicit PlasmaWindowManagement(QObject *parent = nullptr);
    ~PlasmaWindowManagement() override;

Q_SIGNALS:
    void windowCreated(const QString &uuid, struct ::org_kde_plasma_window *rawWindow);

protected:
    void org_kde_plasma_window_management_window_with_uuid(uint32_t id, const QString &uuid) override;
    void org_kde_plasma_window_management_window(uint32_t id) override;
};

class WaylandPlasmaBackend : public QObject {
    Q_OBJECT

public:
    static WaylandPlasmaBackend *instance();

    [[nodiscard]] WindowModel *model() const { return m_model; }
    [[nodiscard]] bool isAvailable() const { return m_available; }

    void toggleWindow(const QString &id);
    void activateWindow(const QString &id);
    void minimizeWindow(const QString &id);
    void refresh();

Q_SIGNALS:
    void availableChanged(bool available);
    void windowsChanged();

private:
    explicit WaylandPlasmaBackend(QObject *parent = nullptr);
    ~WaylandPlasmaBackend() override = default;

    void handleWindowCreated(const QString &uuid, struct ::org_kde_plasma_window *rawWindow);
    void handleWindowReady(PlasmaWindow *win);
    void handleWindowChanged(PlasmaWindow *win);
    void handleWindowUnmapped(const QString &uuid);
    void handleExtensionActiveChanged();

    PlasmaWindowManagement *m_extension{nullptr};
    WindowModel *m_model{nullptr};
    QHash<QString, PlasmaWindow *> m_windows;
    bool m_available{false};
};

} // namespace qs::plugins::kwin
