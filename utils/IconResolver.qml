// IconResolver.qml — Resolves application icons for Wayland toplevel windows.
// 
// Architecture note:
// Wayland core protocol does not provide a universal window-icon property.
// The staging xdg-toplevel-icon-v1 protocol standardizes clients setting icons
// via stock icon theme names (set_name) or buffer data.
// For taskbars and panels, icon resolution is treated as a separate concern from
// window discovery, resolving icons across:
// 1. xdg-toplevel-icon-v1 stock theme names
// 2. Quickshell.DesktopEntries (heuristicLookup and byId)
// 3. Quickshell.iconPath() system icon theme lookup
// 4. Common compositor / Wayland app ID mappings
// 5. Safe executable fallbacks
import QtQuick
import Quickshell

QtObject {
  id: resolver

  // Known app ID aliases when compositor window class doesn't match icon name
  readonly property var appAliases: ({
    "t3code": "t3_code_alpha",
    "brave-origin": "brave-origin",
    "brave-browser": "brave-browser",
    "org.kde.konsole": "utilities-terminal",
    "konsole": "utilities-terminal",
    "notify-send": "preferences-desktop-notification",
    "org.freedesktop.Notifications": "preferences-desktop-notification",
    "org.kde.xwaylandvideobridge": "org.kde.xwaylandvideobridge"
  })

  // Cache resolved icons to avoid repeated lookups
  property var _iconCache: ({})

  function resolveIcon(appId: string, title: string): string {
    const key = (appId || "") + "::" + (title || "");
    if (_iconCache[key] !== undefined) {
      return _iconCache[key];
    }

    let resolved = _doResolve(appId, title);
    _iconCache[key] = resolved;
    return resolved;
  }

  function _doResolve(appId: string, title: string): string {
    if (!appId && !title) {
      return fallbackIcon();
    }

    // 0. Check alias mapping
    let alias = appId ? appAliases[appId] : "";
    if (alias) {
      let aliasPath = resolveStockIcon(alias);
      if (aliasPath) return aliasPath;

      let aliasEntry = DesktopEntries.heuristicLookup(alias) || DesktopEntries.byId(alias);
      if (aliasEntry && aliasEntry.icon) {
        let p = resolveNamedOrPath(aliasEntry.icon);
        if (p) return p;
      }
    }

    // 1. Direct xdg-toplevel-icon-v1 / XDG theme lookup using appId directly
    if (appId) {
      let directPath = resolveStockIcon(appId);
      if (directPath) return directPath;

      // Lowercase attempt
      let lowerAppId = appId.toLowerCase();
      if (lowerAppId !== appId) {
        let lowerPath = resolveStockIcon(lowerAppId);
        if (lowerPath) return lowerPath;
      }

      // Reverse DNS last segment: e.g. "org.kde.dolphin" -> "dolphin"
      let parts = appId.split(".");
      if (parts.length > 1) {
        let lastSegment = parts[parts.length - 1].toLowerCase();
        let segPath = resolveStockIcon(lastSegment);
        if (segPath) return segPath;
      }
    }

    // 2. Quickshell.DesktopEntries lookup (heuristicLookup and byId)
    if (appId) {
      let entry = DesktopEntries.heuristicLookup(appId);
      if (!entry) {
        entry = DesktopEntries.byId(appId);
      }
      if (!entry && appId.includes(".")) {
        let lastSegment = appId.split(".").pop();
        entry = DesktopEntries.heuristicLookup(lastSegment);
      }

      if (entry && entry.icon) {
        let entryIconPath = resolveNamedOrPath(entry.icon);
        if (entryIconPath) return entryIconPath;
      }
    }

    // 3. Heuristic lookup on window title if appId lookup yielded nothing
    if (title) {
      // Try stripping common suffixes like " — Konsole", " - Brave Origin"
      let cleanTitle = title;
      if (cleanTitle.includes(" — ")) {
        let titleParts = cleanTitle.split(" — ");
        cleanTitle = titleParts[titleParts.length - 1].trim();
      } else if (cleanTitle.includes(" - ")) {
        let titleParts = cleanTitle.split(" - ");
        cleanTitle = titleParts[titleParts.length - 1].trim();
      }

      let titleEntry = DesktopEntries.heuristicLookup(cleanTitle);
      if (!titleEntry && cleanTitle !== title) {
        titleEntry = DesktopEntries.heuristicLookup(title);
      }

      if (titleEntry && titleEntry.icon) {
        let titlePath = resolveNamedOrPath(titleEntry.icon);
        if (titlePath) return titlePath;
      }

      // Also try resolving cleanTitle as a stock icon name
      let cleanTitleIcon = resolveStockIcon(cleanTitle.toLowerCase().replace(/\s+/g, "-"));
      if (cleanTitleIcon) return cleanTitleIcon;
    }

    // 4. Safe fallback
    return fallbackIcon();
  }

  // Look up a stock icon name in the system icon theme
  function resolveStockIcon(iconName: string): string {
    if (!iconName) return "";
    // check=true returns empty string if the icon does not exist in the theme
    return Quickshell.iconPath(iconName, true) || "";
  }

  // Look up either an icon name or direct path
  function resolveNamedOrPath(iconNameOrPath: string): string {
    if (!iconNameOrPath) return "";
    // Direct file path (some .desktop files specify absolute paths)
    if (iconNameOrPath.startsWith("/")) {
      return "file://" + iconNameOrPath;
    }
    if (iconNameOrPath.startsWith("file://")) {
      return iconNameOrPath;
    }
    return resolveStockIcon(iconNameOrPath);
  }

  // Fallback icon for generic GUI windows
  function fallbackIcon(): string {
    let fb = Quickshell.iconPath("application-x-executable", true);
    if (!fb) fb = Quickshell.iconPath("preferences-system-windows", true);
    if (!fb) fb = Quickshell.iconPath("system-run", true);
    if (!fb) fb = Quickshell.iconPath("application-default-icon", true);
    return fb || "";
  }
}
