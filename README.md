# quick-shell

Personal desktop bar and control center built on [Quickshell](https://quickshell.org).

This configuration is opinionated and tailored to my personal setup. It targets specific hardware, network interfaces, and desktop configurations on my workstation. It is not designed as a generic or multi-distro shell.

## Target system

- OS: Fedora Linux 44
- Desktop environment: KDE Plasma 6 (Wayland session)
- CPU: AMD Ryzen 5 3600 (6 cores, 12 threads)
- GPU: AMD Radeon RX 570 (4 GB)
- RAM: 16 GB
- Primary network interface: `enp34s0`
- Software stack: Quickshell 0.3.1, Qt 6.11, CMake 3.28+

## Architecture

The project pairs Quickshell QML interfaces with dedicated C++ Qt6 plugins to avoid slow process spawning for periodic system metrics.

```
quick-shell/
├── shell.qml          Main bar window and layout entrypoint
├── AGENTS.md          Repository rules and environment notes
├── assets/            Static resources (holidays.ics)
├── bridges/           External helper scripts (KWin D-Bus taskbar bridge)
├── docs/              Documentation references
├── plugins/           Native C++ Qt6 QML plugins
├── popups/            Popup dialogs and control center windows
├── services/          Background services (notifications)
├── utils/             Helpers (desktop icon resolver)
└── widgets/           Bar buttons, status indicators, and taskbar
```

### Components

- `widgets/`. Elements that sit directly on the top panel. Includes CPU, RAM, and GPU monitors, Ethernet link status, Tailscale status, current media playback, live camera and microphone privacy indicators, notification bell with unread badge, system tray, and running window taskbar items.
- `popups/`. Interactive menus opened by clicking bar widgets. Includes top process monitor with memory bars, Ethernet network diagnostics and ping tests, Tailscale peer and funnel manager, media control center with playback scrubbers, full notification center with app grouping and DND toggle, floating toast popups, camera and microphone process viewer, and calendar with holiday markers.
- `services/`. Singletons and long-running state managers, such as the desktop notification service.
- `bridges/`. External helper bridges. `kwin-taskbar-bridge.py` loads an embedded KWin scripting client over D-Bus to track running Wayland windows and dispatch activate, minimize, maximize, and close commands.
- `utils/`. Lookup tools like `IconResolver.qml`, which resolves app IDs and desktop entries to system theme icons.
- `assets/`. Static event data, including calendar holiday feeds.

### Native C++ plugins

Located in `plugins/`, each plugin builds a native Qt6 QML module:

- `ethernet`. Queries Linux Netlink sockets and Ethtool ioctl directly for link carrier, IP addresses, and live byte throughput without spawning child processes.
- `tailscale`. Connects directly to the local Tailscale Unix socket at `/var/run/tailscale/tailscaled.sock` for node status, peer lists, and serve or funnel configurations.
- `media`. MPRIS2 D-Bus client with monotonic clock interpolation for smooth track position progress bars.
- `notifications`. Implements the `org.freedesktop.Notifications` D-Bus service, maintaining active toast and notification history models.
- `privacy`. Direct V4L2 device query and PipeWire stream inspection for active camera and microphone use.
- `topprocesses`. Direct `/proc` parser sorting top CPU and memory consumers for the system stats popup.

## Building plugins

Each C++ plugin in `plugins/` builds independently with CMake:

```bash
cd plugins/<plugin_name>
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

`shell.qml` loads the built plugin imports via `QML2_IMPORT_PATH`.

## Running

Launch the configuration with Quickshell:

```bash
quickshell -p /path/to/quick-shell
```

Quickshell automatically hot-reloads when QML files change.
