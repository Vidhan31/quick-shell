pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

QtObject {
  id: resolver

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

  property var _iconCache: ({})
  property var _namedCache: ({})
  property var _stockCache: ({})

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

    if (appId) {
      let directPath = resolveStockIcon(appId);
      if (directPath) return directPath;

      let lowerAppId = appId.toLowerCase();
      if (lowerAppId !== appId) {
        let lowerPath = resolveStockIcon(lowerAppId);
        if (lowerPath) return lowerPath;
      }

      let parts = appId.split(".");
      if (parts.length > 1) {
        let lastSegment = parts[parts.length - 1].toLowerCase();
        let segPath = resolveStockIcon(lastSegment);
        if (segPath) return segPath;
      }
    }

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

    if (title) {
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

      let cleanTitleIcon = resolveStockIcon(cleanTitle.toLowerCase().replace(/\s+/g, "-"));
      if (cleanTitleIcon) return cleanTitleIcon;
    }

    return fallbackIcon();
  }

  function resolveStockIcon(iconName: string): string {
    if (!iconName) return "";
    const cached = resolver._stockCache[iconName];
    if (cached !== undefined) return cached;
    // check=true returns empty string if the icon does not exist in the theme
    const resolved = Quickshell.iconPath(iconName, true) || "";
    resolver._stockCache[iconName] = resolved;
    return resolved;
  }

  function resolveNamedOrPath(iconNameOrPath: string): string {
    if (!iconNameOrPath) return "";
    const cached = resolver._namedCache[iconNameOrPath];
    if (cached !== undefined) return cached;
    let resolved = _resolveNamedOrPath(iconNameOrPath);
    // Misses are not cached: an icon theme that gains the name later (an app
    // install) must still resolve on the next rebuild.
    if (resolved !== "")
      resolver._namedCache[iconNameOrPath] = resolved;
    return resolved;
  }

  function _resolveNamedOrPath(iconNameOrPath: string): string {
    // Direct file path (some .desktop files specify absolute paths)
    if (iconNameOrPath.startsWith("/")) {
      return "file://" + iconNameOrPath;
    }
    if (iconNameOrPath.startsWith("file://")) {
      return iconNameOrPath;
    }
    return resolveStockIcon(iconNameOrPath);
  }

  function fallbackIcon(): string {
    let fb = Quickshell.iconPath("application-x-executable", true);
    if (!fb) fb = Quickshell.iconPath("preferences-system-windows", true);
    if (!fb) fb = Quickshell.iconPath("system-run", true);
    if (!fb) fb = Quickshell.iconPath("application-default-icon", true);
    return fb || "";
  }
}
