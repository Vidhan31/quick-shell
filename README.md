# quick-shell

Personal desktop bar and control center built on [Quickshell](https://quickshell.org).

This configuration is tailored to my personal setup and workflow on Fedora Linux with KDE Plasma and KWin Wayland. It is not designed as a generic or multi-distro shell.

## Architecture

The project pairs Quickshell QML interfaces with dedicated C++ Qt6 plugins to avoid slow process spawning for periodic system metrics and hardware queries.

```
quick-shell/
├── shell.qml          Main bar window, services, and dynamic popup host
├── assets/            Static resources, holiday ICS feeds, and model pricing configuration
├── bridges/           External helper scripts (KWin D-Bus taskbar bridge)
├── components/        Reusable QML UI controls (buttons, cards, switches, progress bars)
├── plugins/           Native C++ Qt6 QML plugins
├── popups/            Control center views and shared PopupHost loader window
├── services/          Single-instance domain services instantiated at root
├── theme/             Centralized palette, font metrics, and sizing tokens
├── utils/             Helpers (desktop icon resolver)
└── widgets/           Top panel widgets, status chips, and capsules
```

### Structure and layers

- `services/` & Native Monitors. Single-instance domain managers and native C++ monitors instantiated at `ShellRoot` in `shell.qml`. Native monitors (`DockerMonitor`, `TailscaleMonitor`, `PrivacyMonitor`, `UpdateManager`, `ProcessMonitor`) expose direct deep interfaces, while domain services (`AiUsageService`, `EthernetService`, `AudioService`, `MediaService`, `NotificationService`, `LauncherService`, `PolkitService`, `HolidayProvider`) coordinate higher-level subsystems. High-frequency tracking runs on demand only when relevant views are open.
- `widgets/`. Top panel UI components arranged into left, center, and right sections using a unified deep `BarItem` presenter. Includes system monitor chips (CPU, RAM, GPU), AI token tracking, clock and calendar trigger, media controls, hardware privacy indicators, status capsules (Docker, Tailscale, DNF5 updates, Ethernet, Bluetooth, Volume, Notifications), and the system tray.
- `popups/`. Flyouts and control centers managed by `PopupHost.qml`. A single shared host window dynamically loads views via `Loader` on demand and anchors to whichever bar item was clicked, keeping memory low and avoiding duplicate popup instances across screens. Popups include:
  - `DockerControlCenter`. Container status, start and stop actions, compose project grouping, and resource metrics.
  - `UpdateControlCenter`. DNF5 package update checker, package lists, advisories, and upgrade transactions.
  - `AiUsageControlCenter`. OpenCode and Antigravity token usage, daily usage charts, model distribution, and model pricing cost estimates.
  - `BluetoothControlCenter`. Controller toggles, paired device list, battery indicators, and connection actions.
  - `VolumeControlCenter`. PipeWire default sink and source selectors, volume sliders, and per-app stream volume controls.
  - `EthernetControlCenter`. Interface link status, IP addresses, ping latency checks, and live throughput graphs.
  - `TailscaleControlCenter`. Node status, peer devices, exit nodes, and serve or funnel configurations.
  - `MediaControlCenter`. MPRIS player switcher, playback controls, and track scrubbers.
  - `NotificationControlCenter` and `NotificationPopups`. Notification history, app grouping, DND toggle, and floating toast banners.
  - `PrivacyControlCenter`. Active camera and microphone device usage and process names.
  - `TopProcesses`. Live process table sorted by CPU or memory consumption.
  - `Calendar`. Month view with holiday markers parsed from local ICS data.
- `components/`. Reusable UI building blocks shared across popups, including `PopupCard`, `PopupHeader`, `SectionCard`, `SectionHead`, `StatusPill`, `TSwitch`, `Field`, `Hairline`, `IconBtn`, `PrimaryBtn`, `TextBtn`, `ProgressBar`, `Segments`, `Toast`, and `RowBase`.
- `theme/`. Central design tokens in `Theme.qml`, specifying the dark color palette, font sizes, button dimensions, and animation timings.
- `bridges/`. External helper bridges. `kwin-taskbar-bridge.py` connects to KWin over D-Bus to track running Wayland windows for `Taskbar.qml`.
- `utils/`. Helpers such as `IconResolver.qml` for resolving app IDs and desktop entries to system theme icons.
- `assets/`. Static resources including `holidays.ics`, model pricing configuration (`model-pricing-config.json`), and provider icons.

### Native C++ plugins

Located in `plugins/`, each plugin compiles into a Qt6 QML module:

- `docker`. Communicates with `/var/run/docker.sock` over HTTP via a Unix domain socket for container states, compose project grouping, CPU and memory usage, and lifecycle actions.
- `updatemanager`. Connects to DNF5 over D-Bus to inspect pending Fedora package updates, parse advisories, and run update operations with live progress reporting.
- `notifications`. Provides `NotificationStore` and `NotificationModel` for persistent notification storage, unread counts, and action handling.
- `ethernet`. Queries Linux Netlink sockets and Ethtool ioctl directly for link carrier, IP addresses, and live byte throughput without spawning external processes.
- `tailscale`. Connects directly to the local Tailscale Unix socket at `/var/run/tailscale/tailscaled.sock` for node status, peer lists, and serve or funnel configurations.
- `privacy`. Inspects V4L2 devices and PipeWire audio streams for active camera and microphone use.
- `topprocesses`. Reads `/proc` directly to extract and sort top CPU and memory consumers for the process monitor popup.
- `tokenusage`. Reads the local OpenCode SQLite database for session and daily token counts.
- `antigravityusage`. Reads the local Antigravity database for session and daily token metrics.
- `modelpricing`. Loads pricing configuration (`assets/model-pricing-config.json`), fetches current rates from models.dev, caches with ETag in `~/.cache/quick-shell/`, and maps local model IDs to official pricing.
- `pathprobe`. Classifies launcher input as a filesystem path (shape detection, `~` expansion, one `stat()`, mimetype→icon lookup) and hands directories and files to the running file manager over the `org.freedesktop.FileManager1` D-Bus interface, falling back to the `dolphin` CLI.

## Building plugins

Each plugin in `plugins/` builds with CMake:

```bash
cd plugins/<plugin_name>
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

To build all plugins:

```bash
for d in plugins/*/; do
  if [ -f "$d/CMakeLists.txt" ]; then
    echo "Building $d..."
    cmake -B "$d/build" -S "$d" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$d/build" -j$(nproc)
  fi
done
```

`shell.qml` loads built plugins via `QML2_IMPORT_PATH`.

## Running

Launch the shell with Quickshell:

```bash
quickshell -p /path/to/quick-shell
```

Quickshell automatically hot-reloads when QML files change.
