- This is my personal setup. Not intended for anyone else except me.
- Quickshell supports hot-reloading so do not abort or restart it.
- Only refer quickshell documentation for versions 0.3.1 and above.
- Git-workflow rule doesnt apply here. Do it in one branch only.
- This is personal project so writing code specific to my system is not an issue if no alternative solution is available.
- Do not execute any scripts (for testing purposes) that might affect my data, network, system functionalities.
- qmllint-qt6 is wired to the `qmllint` build target. Config lives in `.qmllint.ini`.
- Fine tuning to my system specs is allowed.
- Do not write useless comments such as decorators, steps, etc. Only important ones such as workarounds, security, limitations, hacks,etc.
- Do not build C++ plugins if you only modified QML files.
- Build the target for which files have been modified instead of everything.

## Build

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release   # all 11 plugins
cmake --build build                                       # build everything
cmake --build build --target docker                      # one plugin only
cmake -S . -B build -DQS_PLUGINS=docker;tailscale        # configure a subset
cmake --build build --target qmllint                      # lint the 69 QML files
quickshell -p /home/dev/Projects/quick-shell              # launch
```
