pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Plugins.PathProbe
import Quickshell.Plugins.FileSearch
import Quickshell.Plugins.KWin
import qs.utils

/* Domain state for the application launcher.
   Owns the desktop-entry corpus, per-keystroke filtering and ranking,
   selection, and open/close lifecycle. Presentation lives in qs.launcher. */
Item {
  id: root

  property bool isOpen: false
  property string query: ""
  property var apps: []
  property var rows: []
  property int selectedIndex: 0
  property int openedAt: 0
  property var deTarget: null
  property bool corpusStarted: false
  property bool isDragging: false

  property var pinnedIds: []
  readonly property int maxPins: 15

  readonly property var pinnedApps: {
    const ids = root.pinnedIds;
    const allApps = root.apps;
    if (!ids || ids.length === 0 || !allApps || allApps.length === 0) return [];
    const map = {};
    for (let i = 0; i < allApps.length; i++) {
      map[allApps[i].id] = allApps[i];
    }
    const result = [];
    for (let j = 0; j < ids.length; j++) {
      const found = map[ids[j]];
      if (found) {
        result.push(found);
      }
    }
    return result;
  }

  KWinManager {
    id: kwinManager
  }

  readonly property var openWindows: kwinManager.windows

  function toggleWindow(winId: string): void {
    if (winId) kwinManager.toggleWindow(winId);
  }

  readonly property var dockItems: {
    const raw = kwinManager.mergeDockItems(root.pinnedApps, iconResolver.appAliases);
    for (let i = 0; i < raw.length; i++) {
      const it = raw[i];
      if (!it.iconSrc) {
        it.iconSrc = iconResolver.resolveIcon(it.appId || it.name, it.windowTitle);
      }
    }
    return raw;
  }

  PersistentProperties {
    id: persist
    property string pinnedJson: "[]"
    reloadableId: "launcher-pinned-state"
  }

  readonly property string pinnedConfigPath: Quickshell.env("HOME") + "/.config/quickshell/pinned_apps.json"

  FileView {
    id: pinnedConfigFile
    path: root.pinnedConfigPath
    onLoaded: root.loadPinnedFromFile()
  }

  function loadPinnedFromFile(): void {
    if (!pinnedConfigFile.loaded) return;
    const raw = pinnedConfigFile.text();
    if (!raw) return;
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) {
        root.pinnedIds = parsed;
        persist.pinnedJson = JSON.stringify(parsed);
      }
    } catch (e) {
      console.warn("Failed to parse pinned_apps.json:", e);
    }
  }

  Component.onCompleted: {
    if (persist.pinnedJson && persist.pinnedJson !== "[]") {
      try {
        const parsed = JSON.parse(persist.pinnedJson);
        if (Array.isArray(parsed) && parsed.length > 0) {
          root.pinnedIds = parsed;
          return;
        }
      } catch (e) {
      }
    }

    if (pinnedConfigFile.loaded) {
      loadPinnedFromFile();
    }
  }

  function savePinnedToDisk(): void {
    const json = JSON.stringify(root.pinnedIds);
    pinnedConfigFile.setText(json);
  }

  function isPinned(appId: string): bool {
    if (!appId || !root.pinnedIds) return false;
    return root.pinnedIds.indexOf(appId) !== -1;
  }

  function pinApp(appId: string): bool {
    if (!appId || isPinned(appId)) return false;
    if (root.pinnedIds.length >= root.maxPins) return false;
    const next = root.pinnedIds.slice();
    next.push(appId);
    root.pinnedIds = next;
    persist.pinnedJson = JSON.stringify(next);
    savePinnedToDisk();
    return true;
  }

  function unpinApp(appId: string): void {
    if (!appId || !root.pinnedIds) return;
    const idx = root.pinnedIds.indexOf(appId);
    if (idx === -1) return;
    const next = root.pinnedIds.slice();
    next.splice(idx, 1);
    root.pinnedIds = next;
    persist.pinnedJson = JSON.stringify(next);
    savePinnedToDisk();
  }

  function togglePin(appId: string): void {
    if (isPinned(appId)) unpinApp(appId);
    else pinApp(appId);
  }

  function toggleSelectedPin(): void {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length) return;
    const r = root.rows[root.selectedIndex];
    if (r && r.kind === "app") {
      togglePin(r.id);
    }
  }

  function launchPinned(index: int, mode: var): void {
    if (index < 0 || index >= root.dockItems.length) return;
    const item = root.dockItems[index];
    if (item.isRunning && item.windowId) {
      root.toggleWindow(item.windowId);
      close();
      return;
    }
    if (!item || !item.entry) return;
    launchEntry(item.entry, item.name, mode === "terminal" || mode === "shift");
    close();
  }

  /* Absolute path because the terminal on this system is an AppImage that is
     not on PATH. Point this at any binary accepting
     <path> [--wait-after-command] [--title=X] -e cmd args. */
  readonly property string terminalPath: "/home/dev/AppImages/ghostty.appimage"
  // Keep the terminal window open after the command exits, so its output and
  // any error stay readable. False gives stock behaviour.
  readonly property bool holdTerminal: true

  readonly property int focusGraceMs: 250
  readonly property int maxRows: 50

  signal refocusRequested()

  IconResolver {
    id: iconResolver
  }

  // All filesystem work lives here: shape detection, ~ expansion, the stat and
  // the mimetype lookup. QML only decides what to show.
  PathProbe {
    id: probe
  }

  FileSearch {
    id: fileSearch
  }

  readonly property bool isFileSearchActive: fileSearch.available && fileSearch.isSearchQuery(root.query)
  readonly property bool isFileSearching: fileSearch.searching

  Connections {
    target: fileSearch
    function onResultsChanged(): void {
      if (!root.isFileSearchActive) return;
      root.rows = root.fileSearchRowsFrom(fileSearch.results);
      root.selectedIndex = 0;
    }
  }

  /* DesktopEntries is a lazily created singleton whose constructor runs the
     .desktop scan inline on the QML thread. Touching it is the whole cost, so
     every reference goes through here rather than a startup binding. */
  function ensureCorpus(): void {
    if (root.corpusStarted)
      return;
    root.corpusStarted = true;
    root.deTarget = DesktopEntries;
    /* The scan hands its results back through a queued signal, so the model is
       still empty here. This rebuild only covers the case where something else
       already forced the singleton and the signal has been and gone. */
    rebuild();
  }

  function open(): void {
    ensureCorpus();
    resetQuery();
    root.openedAt = Date.now();
    root.isOpen = true;
  }

  function close(): void {
    root.isOpen = false;
    root.isDragging = false;
  }

  function toggle(): void {
    if (root.isOpen) close();
    else open();
  }

  function resetQuery(): void {
    root.query = "";
    if (fileSearch.query !== "") {
      fileSearch.query = "";
    }
    refilter();
  }

  function setQuery(text: string): void {
    if (root.query === text) return;
    root.query = text;
    refilter();
  }

  // Focus-loss triage for the window: a loss inside the grace window means
  // something stole focus mid-open, so re-arm instead of closing.
  function notifyFocusLost(): void {
    if (!root.isOpen || root.isDragging) return;
    if (Date.now() - root.openedAt < root.focusGraceMs) root.refocusRequested();
    else close();
  }

  function moveSelection(delta: int): void {
    const n = root.rows.length;
    if (n === 0) return;
    let i = (root.selectedIndex + delta) % n;
    if (i < 0) i += n;
    root.selectedIndex = i;
  }

  function movePage(delta: int): void {
    moveSelection(delta * 8);
  }

  function goFirst(): void {
    root.selectedIndex = 0;
  }

  function goLast(): void {
    root.selectedIndex = Math.max(0, root.rows.length - 1);
  }

  function activateSelected(action: var): void {
    activateIndex(root.selectedIndex, action);
  }

  function activateIndex(i: int, action: var): void {
    const r = root.rows[i];
    if (!r) return;
    const mode = (action === true) ? "terminal" : (typeof action === "string" ? action : "default");
    if (r.kind === "file" || r.kind === "path") {
      if (mode === "terminal") {
        launchFileTerminal(r);
      } else if (mode === "dolphin" || mode === "shift") {
        probe.reveal(r.abs, r.isDir);
      } else {
        launchFileDefault(r);
      }
      close();
      return;
    }
    if (r.kind === "command") {
      launchCommand(r.command, mode === "background" || mode === "shift");
      close();
      return;
    }
    if (!r.entry) return;
    launchEntry(r.entry, r.name, mode === "terminal" || mode === "shift");
    close();
  }

  function copyIndex(i: int): bool {
    const r = root.rows[i];
    if (!r || !r.abs) return false;
    return probe.copyFile(r.abs);
  }

  function copySelectedFile(): bool {
    return copyIndex(root.selectedIndex);
  }

  function openWithIndex(i: int): bool {
    const r = root.rows[i];
    if (!r || !r.abs) return false;
    return probe.openWith(r.abs);
  }

  function openWithSelected(): bool {
    return openWithIndex(root.selectedIndex);
  }

  function launchCommand(cmdText: string, inBackground: bool): void {
    if (!cmdText) return;
    if (inBackground) {
      launchCommandBackground(cmdText);
    } else {
      launchCommandTerminal(cmdText);
    }
  }

  function launchCommandTerminal(cmdText: string): void {
    const shell = String(Quickshell.env("SHELL") || "/usr/bin/zsh");
    const home = String(Quickshell.env("HOME") || "/home/dev");
    const cmd = [root.terminalPath];
    if (root.holdTerminal) cmd.push("--wait-after-command");
    cmd.push("--title=" + cmdText);
    cmd.push("--working-directory=" + home);
    cmd.push("-e");
    cmd.push(shell);
    cmd.push("-c");
    cmd.push(cmdText);
    Quickshell.execDetached({ command: cmd, unbindStdout: true });
  }

  function launchCommandBackground(cmdText: string): void {
    const shell = String(Quickshell.env("SHELL") || "/usr/bin/zsh");
    const home = String(Quickshell.env("HOME") || "/home/dev");
    Quickshell.execDetached({
      command: [shell, "-c", cmdText],
      workingDirectory: home,
      unbindStdout: true
    });
  }

  function launchFileTerminal(r: var): void {
    const dir = r.isDir ? r.abs : r.parent;
    const argv = terminalShellArgv(dir, r.abs);
    if (argv !== null) {
      Quickshell.execDetached({ command: argv, unbindStdout: true });
    }
  }

  function launchFileDefault(r: var): void {
    if (r.isDir) {
      probe.reveal(r.abs, true);
    } else {
      Quickshell.execDetached({ command: ["xdg-open", r.abs], unbindStdout: true });
    }
  }

  /* No -e, so the terminal starts its own configured shell instead of a
     command that would exit at once. workingDirectory goes to the terminal,
     never to ProcessContext.workingDirectory, for the same reason. */
  function terminalShellArgv(dir: string, title: string): var {
    if (!dir) return null;
    const cmd = [root.terminalPath];
    if (root.holdTerminal) cmd.push("--wait-after-command");
    if (title) cmd.push("--title=" + title);
    cmd.push("--working-directory=" + dir);
    return cmd;
  }

  /* Single launch seam. inTerminal hosts the app in a terminal window for
     one-shot runs (e.g. debugging); entries whose .desktop file says
     Terminal=true are routed there as well, because execute() ignores
     runInTerminal. */
  function launchEntry(entry: var, title: string, inTerminal: bool): void {
    if (!entry) return;
    if (inTerminal || entry.runInTerminal) {
      const argv = terminalArgv(entry, title);
      if (argv !== null) {
        Quickshell.execDetached({ command: argv, unbindStdout: true });
        return;
      }
    }
    entry.execute();
  }

  /* Builds the terminal argv for a hosted run. entry.command is the parsed
     Exec, so -e receives real argv with no shell round-trip. Returns null
     when the entry has nothing runnable and callers should fall back. */
  function terminalArgv(entry: var, title: string): var {
    const inner = entry.command;
    if (!inner || inner.length === 0) return null;
    const cmd = [root.terminalPath];
    if (root.holdTerminal) cmd.push("--wait-after-command");
    if (title) cmd.push("--title=" + title);
    // Path= is handed to ghostty, never to ProcessContext.workingDirectory:
    // a stale Path= must not make the ghostty spawn itself fail silently.
    const wd = entry.workingDirectory ? String(entry.workingDirectory) : "";
    if (wd) cmd.push("--working-directory=" + wd);
    cmd.push("-e");
    for (let i = 0; i < inner.length; i++) cmd.push(String(inner[i]));
    return cmd;
  }

  function rebuild(): void {
    const out = [];
    const model = DesktopEntries.applications;
    if (!model) {
      root.apps = out;
      refilter();
      return;
    }
    const vals = model.values;
    for (let i = 0; i < vals.length; i++) {
      const e = vals[i];
      if (!e || !e.name) continue;
      const name = String(e.name);
      const generic = e.genericName ? String(e.genericName) : "";
      const kws = Array.isArray(e.keywords) ? e.keywords : [];
      out.push({
        id: e.id ? String(e.id) : name,
        name: name,
        nameLc: name.toLowerCase(),
        generic: generic,
        genericLc: generic.toLowerCase(),
        kwLc: kws.join(" ").toLowerCase(),
        iconSrc: iconResolver.resolveNamedOrPath(e.icon ? String(e.icon) : ""),
        entry: e
      });
    }
    out.sort((a, b) => a.name < b.name ? -1 : (a.name > b.name ? 1 : 0));
    root.apps = out;
    refilter();
  }

  /* Tiered substring match: 1 exact, 2 prefix, 3 substring on the name,
     4 substring on genericName, 5 substring on keywords. Within a tier
     rows sort alphabetically, which is the only order that reads as fair.
     Returns { tier, hlName, hlGeneric } or null. */
  function matchTier(r: var, q: string): var {
    const nl = r.nameLc;
    if (nl === q) return { tier: 1, hlName: [[0, q.length]], hlGeneric: [] };
    if (nl.startsWith(q)) return { tier: 2, hlName: [[0, q.length]], hlGeneric: [] };
    const idx = nl.indexOf(q);
    if (idx > 0) {
      return { tier: 3, hlName: [[idx, idx + q.length]], hlGeneric: [] };
    }
    if (r.genericLc) {
      const gi = r.genericLc.indexOf(q);
      if (gi >= 0) return { tier: 4, hlName: [], hlGeneric: [[gi, gi + q.length]] };
    }
    if (r.kwLc && r.kwLc.includes(q)) return { tier: 5, hlName: [], hlGeneric: [] };
    return null;
  }

  function fileSearchRowsFrom(results: var): var {
    const out = [];
    for (let i = 0; i < results.length; i++) {
      const r = results[i];
      const stockIcon = iconResolver.resolveStockIcon(String(r.iconName));
      const fallback = r.isDir ? iconResolver.resolveStockIcon("folder") : iconResolver.resolveStockIcon("text-x-generic");
      out.push({
        id: r.id,
        kind: "file",
        name: r.name,
        generic: r.generic,
        iconSrc: stockIcon || fallback,
        abs: r.abs,
        parent: r.parent,
        isDir: r.isDir,
        tier: 0,
        hlName: [],
        hlGeneric: [],
        entry: null
      });
    }
    return out;
  }

  function refilter(): void {
    if (fileSearch.available && fileSearch.isSearchQuery(root.query)) {
      const term = fileSearch.searchTerm(root.query);
      fileSearch.query = term;
      if (!term) {
        root.rows = [];
        root.selectedIndex = 0;
      }
      return;
    }
    if (fileSearch.query !== "") {
      fileSearch.query = "";
    }

    const raw = root.query.trim();
    if (raw.startsWith(">")) {
      const cmd = raw.slice(1).trim();
      root.rows = cmd.length > 0 ? [commandRowFor(cmd)] : [];
      root.selectedIndex = 0;
      return;
    }
    const q = raw.toLowerCase();
    const corpus = root.apps;
    if (!q) {
      const all = [];
      const lim = Math.min(corpus.length, root.maxRows);
      for (let i = 0; i < lim; i++) {
        all.push(viewOf(corpus[i], 0, [], []));
      }
      root.rows = all;
      root.selectedIndex = 0;
      return;
    }
    /* A resolved path replaces the app results outright: no app name starts
       with '/', '~', './' or '../', and mixing them would make it ambiguous
       what Enter acts on. Classified on the raw text, never the lowercased
       copy, because paths are case-sensitive. */
    const pathRow = pathRowFor(raw);
    if (pathRow !== null) {
      root.rows = [pathRow];
      root.selectedIndex = 0;
      return;
    }
    const scored = [];
    for (let i = 0; i < corpus.length; i++) {
      const m = matchTier(corpus[i], q);
      if (m === null) continue;
      scored.push({ row: corpus[i], tier: m.tier, hlName: m.hlName, hlGeneric: m.hlGeneric });
    }
    if (scored.length === 0) {
      root.rows = [commandRowFor(raw)];
      root.selectedIndex = 0;
      return;
    }
    scored.sort((a, b) => {
      if (a.tier !== b.tier) return a.tier - b.tier;
      return a.row.nameLc < b.row.nameLc ? -1 : (a.row.nameLc > b.row.nameLc ? 1 : 0);
    });
    const out = [];
    const lim = Math.min(scored.length, root.maxRows);
    for (let i = 0; i < lim; i++) {
      const s = scored[i];
      out.push(viewOf(s.row, s.tier, s.hlName, s.hlGeneric));
    }
    root.rows = out;
    root.selectedIndex = 0;
  }

  function commandRowFor(cmdText: string): var {
    return {
      id: "cmd:" + cmdText,
      kind: "command",
      name: cmdText,
      generic: "Run in terminal (↵) · background (⇧↵)",
      iconSrc: iconResolver.resolveStockIcon("utilities-terminal"),
      command: cmdText,
      tier: 0,
      hlName: [],
      hlGeneric: [],
      entry: null
    };
  }

  function toDisplayPath(abs: string): string {
    const home = String(Quickshell.env("HOME") || "/home/dev");
    if (abs === home) return "~";
    if (abs.startsWith(home + "/")) return "~" + abs.slice(home.length);
    return abs;
  }

  /* Turns a path-shaped query into one result row, or null when the text is not
     a path or does not resolve. The id is namespaced so it cannot collide with
     a desktop-entry id under ScriptModel's identity comparison. hlName stays
     empty: the user typed the whole string, so highlighting it would just
     paint the row in accent. */
  function pathRowFor(q: string): var {
    const info = probe.classify(q);
    if (!info.pathShape || !info.exists) return null;
    const abs = String(info.abs);
    const lastSlash = abs.lastIndexOf("/");
    const base = (lastSlash >= 0 && abs.length > 1) ? abs.slice(lastSlash + 1) : abs;
    return {
      id: "path:" + info.abs,
      kind: "path",
      name: base,
      generic: root.toDisplayPath(abs),
      iconSrc: iconResolver.resolveStockIcon(String(info.iconName)),
      abs: info.abs,
      parent: info.parent,
      isDir: info.isDir,
      tier: 0,
      hlName: [],
      hlGeneric: [],
      entry: null
    };
  }

  // Fresh view objects per refilter so ScriptModel's identity diff always
  // reflects the current tier and highlight ranges.
  function viewOf(r: var, tier: int, hlName: var, hlGeneric: var): var {
    return {
      id: r.id,
      kind: "app",
      name: r.name,
      generic: r.generic,
      iconSrc: r.iconSrc,
      tier: tier,
      hlName: hlName,
      hlGeneric: hlGeneric,
      entry: r.entry
    };
  }

  /* Never target DesktopEntries literally: that binding resolves during
     component creation and would run the scan at startup. ensureCorpus()
     assigns deTarget on first open, after which installs and removals keep the
     corpus live. */
  Connections {
    target: root.deTarget
    function onApplicationsChanged(): void {
      Qt.callLater(root.rebuild);
    }
  }
}
