# DNF5 Update Manager Research: dnf5daemon-server & Qt 6.11 / C++

This document details the architecture, D-Bus interfaces, workflows, edge cases, and design choices for building a Qt 6.11 / C++ Update Manager plugin on Fedora using `dnf5daemon-server`.

---

## 1. System Requirements & Compatibility Audit

Verified on target host:
- **Operating System**: Fedora Linux 44 (x86_64) on KWin / Wayland, KDE Plasma 6.7.
- **Compiler & Toolchain**: GCC 16.2.1 (supports C++20 / C++23), CMake 4.3.0.
- **Qt Version**: Qt 6.11.2 (`Qt6::Core`, `Qt6::Quick`, `Qt6::Qml`, `Qt6::DBus`, `Qt6::Gui`).
- **Qt D-Bus Code Generator**: `/usr/bin/qdbusxml2cpp-qt6` is available.
- **DNF5 Daemon**: `dnf5daemon-server-5.4.5.0-1.fc44.x86_64`, `libdnf5-5.4.5.0-1.fc44.x86_64`, `dnf5-5.4.5.0-1.fc44.x86_64`.
- **System Services & Polkit**:
  - `dnf5daemon-server.service` installed at `/usr/lib/systemd/system/dnf5daemon-server.service`.
  - D-Bus service `org.rpm.dnf.v0` registered on System Bus at `/usr/share/dbus-1/system-services/org.rpm.dnf.v0.service`.
  - Polkit rules present at `/usr/share/polkit-1/actions/org.rpm.dnf.v0.policy`.
  - KDE Polkit Agent `/usr/libexec/kf6/polkit-kde-authentication-agent-1` is active and running for interactive authorization prompts.
  - Offline update unit `/usr/lib/systemd/system/system-update.target.wants/dnf5-offline-transaction.service` is present and targets `/usr/bin/dnf5 offline _execute`.

All system requirements are fully met.

---

## 2. Core Architecture & Session Topology

`dnf5daemon-server` uses stateful, connection-bound sessions. Clients must open a session before executing operations.

```
System Bus: org.rpm.dnf.v0
Root Path:  /org/rpm/dnf/v0 (Interface: org.rpm.dnf.v0.SessionManager)
               │
               ▼ open_session(options)
Session Path: /org/rpm/dnf/v0/<32-hex-uuid>
  ├── org.rpm.dnf.v0.Base
  ├── org.rpm.dnf.v0.rpm.Repo
  ├── org.rpm.dnf.v0.rpm.Rpm
  ├── org.rpm.dnf.v0.Goal
  ├── org.rpm.dnf.v0.Offline
  ├── org.rpm.dnf.v0.Advisory
  ├── org.rpm.dnf.v0.comps.Group
  └── org.rpm.dnf.v0.History
```

### 2.1 Connection Binding & Lifecycle
- `SessionManager` listens to `org.freedesktop.DBus` `NameOwnerChanged`. If the client process drops its D-Bus connection or terminates, the daemon automatically cleans up all sessions created by that sender.
- Server has a hard limit of 10 concurrent sessions (`MAX_SESSIONS = 10`). Sessions must be closed promptly when not in use via `close_session(session_path)`.
- Method calls on a session are serialized by an internal mutex (`libdnf5_mutex`), preventing re-entrancy issues in `libsolv`.

---

## 3. Workflows & Method Signatures

### 3.1 Refreshing Metadata (`dnf update --refresh`)
1. Open session:
   ```
   org.rpm.dnf.v0.SessionManager.open_session(a{sv} options) -> (o session_path)
   options: {"load_system_repo": true, "load_available_repos": true}
   ```
2. Expire cache:
   ```
   org.rpm.dnf.v0.Base.clean(s cache_type) -> (b success, s error_msg)
   cache_type: "expire-cache"
   ```
   *Note: In `dnf5daemon-server`, `clean("expire-cache")` is explicitly exempted from Polkit authorization. Any standard user can trigger it without a password.*
3. Reset session base:
   ```
   org.rpm.dnf.v0.Base.reset() -> (b success, s error_msg)
   ```
4. Read repositories:
   ```
   org.rpm.dnf.v0.Base.read_all_repos() -> (b success)
   ```
   Emits download signals on `org.rpm.dnf.v0.Base`:
   - `download_add_new(o session, s download_id, s description, x total_to_download)`
   - `download_progress(o session, s download_id, x total_to_download, x downloaded)`
   - `download_end(o session, s download_id, u transfer_status, s message)`
   - `repo_key_import_request(...)` if a new GPG key requires confirmation.

### 3.2 Querying Upgrades
- **Fast list for UI**:
  ```
  org.rpm.dnf.v0.rpm.Rpm.list(a{sv} options) -> (aa{sv} packages)
  options: {
    "scope": "upgrades",
    "package_attrs": ["id", "name", "epoch", "version", "release", "arch", "repo_id",
                      "download_size", "install_size", "summary", "evr", "full_nevra", "vendor"]
  }
  ```
- **Advisory lookup**:
  ```
  org.rpm.dnf.v0.Advisory.list(a{sv} options) -> (aa{sv} advisories)
  options: {
    "availability": "updates",
    "advisory_attrs": ["advisoryid", "name", "title", "type", "severity", "references", "collections"]
  }
  ```
  Advisory types: `"security"`, `"bugfix"`, `"enhancement"`.
  Severities: `"critical"`, `"important"`, `"moderate"`, `"low"`, `"none"`.

### 3.3 Dependency Solving
1. Stage all upgrades:
   ```
   org.rpm.dnf.v0.rpm.Rpm.upgrade(as pkg_specs, a{sv} options)
   pkg_specs: []  // empty list stages all available upgrades
   options: {}
   ```
2. Resolve:
   ```
   org.rpm.dnf.v0.Goal.resolve(a{sv} options) -> (a(sssa{sv}a{sv}) items, u result)
   options: {"allow_erasing": false}
   ```
   Returns tuple: `(object_type, action, reason, trans_attrs, object_data)`.
   - `action`: `"Install"`, `"Upgrade"`, `"Downgrade"`, `"Remove"`, `"Replaced"`, `"Reason Change"`.
   - `result`: `0` (clean), `1` (warnings), `2` (failure).
   - If `result != 0`: call `Goal.get_transaction_problems_string() -> (as problems)`.

### 3.4 In-Place vs Offline Updates

#### Option A: In-Place Upgrade (Live Execution)
- Direct invocation:
  ```
  org.rpm.dnf.v0.Goal.do_transaction(a{sv} options)
  options: {"offline": false, "interactive": true}
  ```
- Polkit prompt: Triggers `org.rpm.dnf.v0.rpm.execute_trusted_transaction` via KDE polkit agent.
- Progress monitoring: Listen to `org.rpm.dnf.v0.rpm.Rpm` signals:
  `transaction_elem_progress`, `transaction_action_start`, `transaction_action_progress`, `transaction_action_stop`, `transaction_after_complete`.
- *Trade-off*: No reboot required, but updating glibc, kernel, graphics drivers, or compositor while running can lead to instability.

#### Option B: Offline Upgrade (Reboot-Safe)
1. Background unprivileged package download and transaction staging:
   ```
   org.rpm.dnf.v0.Goal.do_transaction(a{sv} options)
   options: {"offline": true, "downloadonly": true, "interactive": false}
   ```
   - Downloads RPMs to `/var/lib/dnf/offline/packages`.
   - Runs `tsflags=test` to verify package signatures, dependencies, and file conflicts.
   - Serializes transaction to `/usr/lib/sysimage/libdnf5/offline/transaction.json`.
   - Writes state with status `"download-complete"`.
   - *Requires no Polkit root authentication during the download phase.*
2. Schedule reboot (when user clicks "Restart & Apply"):
   ```
   org.rpm.dnf.v0.Offline.schedule_for_next_boot(a{sv} options) -> (b success, s error_msg)
   options: {"interactive": true}
   ```
   - Validates that the system hasn't changed since download (`rpmdb_cookie`).
   - Creates the systemd magic symlink: `/system-update -> /usr/lib/sysimage/libdnf5/offline`.
   - Transitions state to `"ready"`.
   - Requires Polkit authentication (`org.rpm.dnf.v0.rpm.execute_trusted_transaction`).
3. Set finish action:
   ```
   org.rpm.dnf.v0.Offline.set_finish_action(s action) -> (b success, s error_msg)
   action: "reboot" (or "poweroff")
   ```
4. Trigger reboot via Logind:
   ```
   org.freedesktop.login1.Manager.Reboot(b interactive = true)
   ```
5. Boot execution:
   `systemd-system-update-generator` redirects boot to `system-update.target`. `dnf5-offline-transaction.service` executes `/usr/bin/dnf5 offline _execute` with Plymouth progress reporting. System automatically reboots into normal desktop upon completion. If an error occurs, `dnf5-offline-transaction-cleanup.service` removes `/system-update` to prevent reboot loops.

---

## 4. Package Classification & Grouping Strategy

Fedora RPMs store `group: "Unspecified"`, making the RPM group field unusable. Classification must use package naming heuristics, repository metadata, advisory type, and desktop file presence.

```
┌────────────────────────────────────────────────────────────────────────┐
│ Categorization Heuristics                                              │
├─────────────────────────┬──────────────────────────────────────────────┤
│ Kernel & Hardware       │ Name: kernel*, *-firmware, *-microcode       │
│                         │ Summary matches "kernel" or "firmware"       │
│                         │ Impact: Requires System Reboot               │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Desktop Applications    │ Package owns /usr/share/applications/*.desktop│
│                         │ Or present in AppStream catalog              │
│                         │ Impact: Safe live restart                    │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Desktop Shell & Wayland │ Name: plasma-*, kwin*, qt6-*, wayland*,      │
│                         │ pipewire*, wireplumber, mesa-*               │
│                         │ Impact: Requires Session Logout / Restart    │
├─────────────────────────┼──────────────────────────────────────────────┤
│ System Core & Libraries │ Name: glibc*, systemd*, dbus*, rpm*, dnf5*,  │
│                         │ polkit*, coreutils*, bash, util-linux        │
│                         │ Impact: Strongly recommended Offline Upgrade │
├─────────────────────────┼──────────────────────────────────────────────┤
│ Development & Build     │ Name: *-devel, *-debuginfo, gcc*, cmake*     │
│                         │ Impact: Safe live upgrade                    │
└─────────────────────────┴──────────────────────────────────────────────┘
```

### Proposed Grouping Views for the Dashboard
The user interface can provide a selector to toggle between:
1. **By Functional Category** (Default): Kernel & Firmware, Applications, Desktop Shell, System Core, Development.
2. **By Update Severity / Errata**: Security (Critical, Important, Moderate), Bug Fixes, Enhancements, Regular Updates.
3. **By Repository**: Fedora Core, Fedora Updates, RPM Fusion Free / Nonfree, COPR.
4. **By Recommended Apply Method**: Reboot Required vs Session Restart vs Safe Live Update.

---

## 5. Edge Cases & Implementation Limitations

1. **D-Bus Call Timeouts**:
   - Qt's `QDBusAbstractInterface` defaults to 25 seconds.
   - Long downloads or solving large transactions can take multiple minutes.
   - In Qt C++, set `setTimeout(std::numeric_limits<int>::max())` or use `QDBusPendingCallWatcher` asynchronously on a worker thread.
2. **Cross-Process Transaction Locks**:
   - `libdnf5` uses `fcntl` locking on `/run/dnf/rpmtransaction.lock`.
   - If the user runs `dnf5` in a terminal while an update or download is in progress, the second process receives `TransactionRunResult::ERROR_LOCK`.
   - Plugin must catch lock errors and display a clear warning ("DNF is currently locked by another process").
3. **Polkit Prompt Timeout & Cancellation**:
   - Polkit prompts have a hardcoded 2-minute timeout in `dnf5daemon-server`.
   - If user dismisses or times out, method returns `Not authorized`.
   - Must handle `QDBusError::AccessDenied` gracefully.
4. **Transaction Cancellation**:
   - `Goal.cancel()` is only valid during the download phase.
   - Once RPM installation or the test run starts, `Goal.cancel()` is rejected (`CancelDownload::NOT_ALLOWED`) to prevent database corruption.
5. **GPG Key Import Requests**:
   - If a new third-party repo key appears, `dnf5daemon` emits `Base.repo_key_import_request` and waits up to 5 minutes.
   - Client must catch this signal, display the key fingerprint to the user, and call `Repo.confirm_key(key_id, confirmed)`.
6. **System State Mutation Between Offline Download & Reboot**:
   - If a user installs or removes a package between downloading updates and rebooting, `state->check_rpmdb_cookie()` will detect the mismatch and reject `schedule_for_next_boot()`.
   - The plugin must prompt the user to re-verify/re-download the transaction if invalidated.

---

## 6. Changelog & Release Notes Format

Testing against live `dnf5daemon-server` reveals the exact D-Bus schema for package changelogs and errata:

### 6.1 RPM Spec Changelogs
Queried via `org.rpm.dnf.v0.rpm.Rpm.list` with `package_attrs: ["changelogs"]`.
- The `changelogs` attribute returns a D-Bus array of structs with signature `a(xss)`:
  - `timestamp` (`x` / `int64`): Unix timestamp of the changelog entry.
  - `author` (`s`): Packager name, email, and release tag (e.g. `"Packit <hello@packit.dev> - 5.4.5.0-1"`).
  - `text` (`s`): Detailed bullet points and release notes (e.g. `"- Update to version 5.4.5.0\n- Fix regression..."`).
- **Performance consideration**: Fetching full changelogs across 50+ packages during the initial update check increases D-Bus payload size. The recommended approach is lazy fetching: retrieve changelogs on demand when the user selects or expands a package in the UI.

### 6.2 Bodhi / Advisory Errata Notes
Queried via `org.rpm.dnf.v0.Advisory.list` with `availability: "updates"`.
- Each advisory record contains:
  - `"title"` (`s`): Human-readable update title (e.g. `"dnf5-5.4.5.0-1.fc44 bugfix update"`).
  - `"description"` (`s`): Release notes and Bodhi update notes written by the maintainer.
  - `"type"` (`s`): `"security"`, `"bugfix"`, `"enhancement"`.
  - `"severity"` (`s`): `"critical"`, `"important"`, `"moderate"`, `"low"`.
  - `"references"` (`a(ssss)`): List of `(id, type, title, url)` tuples linking directly to CVEs and Red Hat Bugzilla tickets.

---

## 7. Extended Offline Upgrade Criteria

Beyond kernels and firmware, several system layers require offline updates to prevent session crashes or memory corruption:

1. **C Library Runtime (`glibc*`)**: Updating `libc.so.6` while processes are running causes memory corruption or crashes when running programs fork or dynamically load symbols.
2. **Init & IPC Core (`systemd*`, `dbus-broker*`, `dbus*`)**: In-place replacement of the system manager or message bus risks dropping active session seats.
3. **Graphics & Compositor Stack (`mesa-*`, `libdrm*`, `kwin*`, `plasma-*`, `wayland*`, `qt6-*`)**: Mesa driver updates cause immediate GPU context loss in KWin / Wayland, killing the graphical session and losing unsaved user data.
4. **Audio Engine (`pipewire*`, `wireplumber*`)**: Live updates disrupt active audio streams and socket routing.
5. **Core Cryptography (`openssl*`, `gnutls*`, `nss*`)**: Running daemons may crash or fail TLS negotiations after shared libraries change on disk.
6. **Package Manager Stack (`rpm*`, `dnf5*`, `libdnf5*`)**: Upgrading the package manager mid-transaction risks lock and state mismatches.

**Default Selection Rule**: If an update transaction contains any package matching these categories, default to **Offline Upgrade**. If the transaction consists entirely of standalone desktop applications (Firefox, VLC, LibreOffice) or CLI tools, default to **In-Place Upgrade**.

---

## 8. Safe Verification & Testing Without Updates or Reboots

We can verify every stage of the update manager without waiting for upstream updates or rebooting:

1. **Read-Only Solver Simulation**: Calling `Rpm.upgrade([], {})` followed by `Goal.resolve({})` runs the SAT solver entirely in memory. It tests transaction generation, conflict detection, and problem reporting without writing anything to disk.
2. **Offline Download & Test Run Without Rebooting**:
   - Call `Goal.do_transaction({"offline": true, "downloadonly": true, "interactive": false})`.
   - This downloads RPMs to `/var/lib/dnf/offline/packages` and executes `tsflags=test` (verifying RPM scriptlets, signatures, and file conflicts).
   - Inspect `Offline.get_status()` to verify it reaches `"download-complete"`.
   - Call `Offline.clean()` immediately afterward. This purges the downloaded packages and state file cleanly without creating the `/system-update` symlink or rebooting.
3. **Standalone Probe Tool (`updatemanager-probe`)**: A dedicated C++ CLI executable in `plugins/updatemanager/src/ProbeMain.cpp` can exercise the D-Bus worker, measure query latency, test error states, and dump parsed changelogs directly to the terminal.
4. **Mock Mode for UI Hot-Reloading**: A debug flag (`mock: true`) in the C++ model can inject sample updates (Kernel, Firefox, Mesa, Plasma) with varying advisory types, letting us polish the QML UI layout and animations instantly without waiting for real package updates.

---

## 9. Quickshell Lifecycle & Long Downloads

In Quickshell, popups inside `LazyLoader` can be destroyed when closed, which would cancel any operations owned by the popup.

**Architecture**:
1. Instantiate the C++ `UpdateManager` service inside `services/UpdateService.qml` at the `ShellRoot` level in `shell.qml`.
2. `ShellRoot` persists for the entire life of Quickshell. The background `QThread` and D-Bus connection remain active even if the dashboard popup is closed for hours.
3. The dashboard popup (`popups/UpdateControlCenter.qml`) merely observes the shared service state. Closing the popup has zero effect on ongoing package downloads.
4. The top panel widget (`widgets/UpdateWidget.qml`) can show a subtle badge or download progress ring even when the main dashboard is closed.

