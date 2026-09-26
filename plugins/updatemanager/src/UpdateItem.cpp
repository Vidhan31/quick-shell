#include "UpdateItem.hpp"

namespace qs::updatemanager {

QString UpdateItem::formattedDownloadSize() const {
    if (downloadSize == 0) {
        return QStringLiteral("0 B");
    }
    const double bytes = static_cast<double>(downloadSize);
    if (bytes >= 1024.0 * 1024.0 * 1024.0) {
        return QString::asprintf("%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0));
    }
    if (bytes >= 1024.0 * 1024.0) {
        return QString::asprintf("%.1f MB", bytes / (1024.0 * 1024.0));
    }
    if (bytes >= 1024.0) {
        return QString::asprintf("%.0f KB", bytes / 1024.0);
    }
    return QString::asprintf("%llu B", downloadSize);
}

QVariantMap UpdateItem::toMap() const {
    QVariantMap map;
    map[QStringLiteral("name")] = name;
    map[QStringLiteral("newEvr")] = newEvr;
    map[QStringLiteral("oldEvr")] = oldEvr;
    map[QStringLiteral("arch")] = arch;
    map[QStringLiteral("summary")] = summary;
    map[QStringLiteral("repoId")] = repoId;
    map[QStringLiteral("downloadSize")] = downloadSize;
    map[QStringLiteral("formattedSize")] = formattedDownloadSize();
    map[QStringLiteral("installSize")] = installSize;
    map[QStringLiteral("vendor")] = vendor;
    map[QStringLiteral("categoryKey")] = categoryKey;
    map[QStringLiteral("category")] = category;
    map[QStringLiteral("advisoryId")] = advisoryId;
    map[QStringLiteral("advisoryType")] = advisoryType;
    map[QStringLiteral("severity")] = severity;
    map[QStringLiteral("advisoryTitle")] = advisoryTitle;
    map[QStringLiteral("advisoryDescription")] = advisoryDescription;
    map[QStringLiteral("cveList")] = cveList;
    map[QStringLiteral("requiresReboot")] = requiresReboot;
    map[QStringLiteral("requiresSessionRestart")] = requiresSessionRestart;
    map[QStringLiteral("changelogLoaded")] = changelogLoaded;
    map[QStringLiteral("changelogList")] = changelogList;
    return map;
}

QString UpdateItem::classifyCategoryKey(const QString &pkgName, const QString &pkgSummary) {
    const QString n = pkgName.toLower();
    const QString s = pkgSummary.toLower();

    if (n.startsWith(QStringLiteral("kernel")) || n == QStringLiteral("kernel")) {
        return QStringLiteral("kernel");
    }

    if (n.endsWith(QStringLiteral("-firmware")) || n.contains(QStringLiteral("firmware")) ||
        n.endsWith(QStringLiteral("-microcode")) || s.contains(QStringLiteral("firmware")) ||
        s.contains(QStringLiteral("microcode"))) {
        return QStringLiteral("firmware");
    }

    if (n.startsWith(QStringLiteral("plasma-")) || n.startsWith(QStringLiteral("kwin")) ||
        n.startsWith(QStringLiteral("qt6-")) || n.startsWith(QStringLiteral("qt5-")) ||
        n.startsWith(QStringLiteral("wayland")) || n.startsWith(QStringLiteral("pipewire")) ||
        n.startsWith(QStringLiteral("wireplumber")) || n.startsWith(QStringLiteral("mesa-")) ||
        n.startsWith(QStringLiteral("libdrm")) || n.startsWith(QStringLiteral("xwayland")) ||
        n == QStringLiteral("sddm") || n.contains(QStringLiteral("quickshell"))) {
        return QStringLiteral("shell");
    }

    if (n.endsWith(QStringLiteral("-devel")) || n.endsWith(QStringLiteral("-debuginfo")) ||
        n.startsWith(QStringLiteral("gcc")) || n.startsWith(QStringLiteral("cmake")) ||
        n.startsWith(QStringLiteral("clang")) || n.startsWith(QStringLiteral("llvm")) ||
        n.startsWith(QStringLiteral("binutils")) || n == QStringLiteral("make")) {
        return QStringLiteral("devel");
    }

    if (n == QStringLiteral("glibc") || n.startsWith(QStringLiteral("glibc-")) ||
        n == QStringLiteral("systemd") || n.startsWith(QStringLiteral("systemd-")) ||
        n == QStringLiteral("dbus") || n.startsWith(QStringLiteral("dbus-")) ||
        n == QStringLiteral("polkit") || n.startsWith(QStringLiteral("polkit-")) ||
        n == QStringLiteral("rpm") || n.startsWith(QStringLiteral("rpm-")) ||
        n == QStringLiteral("dnf5") || n.startsWith(QStringLiteral("libdnf5")) ||
        n == QStringLiteral("bash") || n == QStringLiteral("coreutils") ||
        n == QStringLiteral("util-linux") || n.startsWith(QStringLiteral("openssl")) ||
        n.startsWith(QStringLiteral("gnutls")) || n == QStringLiteral("pam") ||
        n.startsWith(QStringLiteral("dracut")) || n.startsWith(QStringLiteral("grub2")) ||
        n.startsWith(QStringLiteral("shim"))) {
        return QStringLiteral("core");
    }

    return QStringLiteral("app");
}

QString UpdateItem::categoryKeyToLabel(const QString &key) {
    if (key == QStringLiteral("kernel")) return QStringLiteral("Kernel & Hardware");
    if (key == QStringLiteral("firmware")) return QStringLiteral("Firmware & Drivers");
    if (key == QStringLiteral("shell")) return QStringLiteral("Desktop Environment");
    if (key == QStringLiteral("core")) return QStringLiteral("System Core & Libraries");
    if (key == QStringLiteral("devel")) return QStringLiteral("Development & Tools");
    return QStringLiteral("Applications");
}

bool UpdateItem::evaluateRebootRequired(const QString &pkgName, const QString &catKey) {
    if (catKey == QStringLiteral("kernel") || catKey == QStringLiteral("firmware")) {
        return true;
    }
    const QString n = pkgName.toLower();
    if (n.startsWith(QStringLiteral("glibc")) || n.startsWith(QStringLiteral("systemd")) ||
        n.startsWith(QStringLiteral("dbus")) || n.startsWith(QStringLiteral("dracut")) ||
        n.startsWith(QStringLiteral("grub2")) || n.startsWith(QStringLiteral("shim"))) {
        return true;
    }
    return false;
}

bool UpdateItem::evaluateSessionRestartRequired(const QString &pkgName, const QString &catKey) {
    if (catKey == QStringLiteral("shell")) {
        return true;
    }
    const QString n = pkgName.toLower();
    if (n.startsWith(QStringLiteral("mesa-")) || n.startsWith(QStringLiteral("kwin")) ||
        n.startsWith(QStringLiteral("plasma-")) || n.startsWith(QStringLiteral("pipewire")) ||
        n.startsWith(QStringLiteral("wireplumber"))) {
        return true;
    }
    return false;
}

} // namespace qs::updatemanager
