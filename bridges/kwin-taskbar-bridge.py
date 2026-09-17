#!/usr/bin/env python3
import atexit
import json
import os
import signal
import sys
import tempfile
import threading
import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
session_bus = dbus.SessionBus()

script_id = None
script_iface = None
script_file = None
kwin_scripting = None

KWIN_JS_TEMPLATE = """
function sendWindows() {
    var wins = workspace.windowList();
    var res = [];
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        if (w.normalWindow && !w.skipTaskbar) {
            res.push({
                id: w.internalId ? w.internalId.toString() : ("win_" + i),
                title: w.caption || "",
                appId: (w.desktopFileName || w.resourceClass || "").toString(),
                active: !!w.active,
                minimized: !!w.minimized,
                maximized: !!w.maximized,
                fullscreen: !!w.fullScreen,
                icon: (w.icon ? (w.icon.name || "") : "")
            });
        }
    }
    callDBus("org.quickshell.KWinBridge", "/Bridge", "org.quickshell.KWinBridge", "Update", JSON.stringify(res));
}

for (var i = 0; i < workspace.windowList().length; i++) {
    var win = workspace.windowList()[i];
    if (win.captionChanged) win.captionChanged.connect(sendWindows);
    if (win.minimizedChanged) win.minimizedChanged.connect(sendWindows);
    if (win.activeChanged) win.activeChanged.connect(sendWindows);
}

workspace.windowAdded.connect(function(w) {
    if (w.captionChanged) w.captionChanged.connect(sendWindows);
    if (w.minimizedChanged) w.minimizedChanged.connect(sendWindows);
    if (w.activeChanged) w.activeChanged.connect(sendWindows);
    sendWindows();
});
workspace.windowRemoved.connect(sendWindows);
workspace.windowActivated.connect(sendWindows);

sendWindows();
"""

def cleanup():
    global script_id, script_iface, script_file, kwin_scripting
    if script_iface is not None:
        try:
            script_iface.stop()
        except Exception:
            pass
        script_iface = None
    if kwin_scripting is not None and script_file is not None:
        try:
            kwin_scripting.unloadScript(script_file)
        except Exception:
            pass
    if script_file is not None and os.path.exists(script_file):
        try:
            os.remove(script_file)
        except Exception:
            pass
        script_file = None

atexit.register(cleanup)

def on_signal(signum, frame):
    cleanup()
    sys.exit(0)

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

class BridgeReceiver(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, "/Bridge")

    @dbus.service.method("org.quickshell.KWinBridge", in_signature="s")
    def Update(self, data):
        try:
            sys.stdout.write(data + "\n")
            sys.stdout.flush()
        except Exception:
            pass

def run_kwin_one_shot(js_code):
    try:
        scripting_obj = session_bus.get_object("org.kde.KWin", "/Scripting")
        iface = dbus.Interface(scripting_obj, "org.kde.kwin.Scripting")
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(js_code)
            tmp_path = f.name
        try:
            s_id = iface.loadScript(tmp_path)
            s_obj = session_bus.get_object("org.kde.KWin", f"/Scripting/Script{s_id}")
            s_iface = dbus.Interface(s_obj, "org.kde.kwin.Script")
            s_iface.run()
            s_iface.stop()
            iface.unloadScript(tmp_path)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
    except Exception as e:
        sys.stderr.write(f"Error running KWin command: {e}\\n")
        sys.stderr.flush()

def handle_command(cmd_line):
    cmd_line = cmd_line.strip()
    if not cmd_line:
        return
    parts = cmd_line.split(" ", 1)
    action = parts[0].upper()
    win_id = parts[1].strip() if len(parts) > 1 else ""
    if not win_id:
        return

    # Escape quotes in win_id to prevent injection
    safe_win_id = win_id.replace('"', '\\"')

    if action == "ACTIVATE":
        js = f'''
        var wins = workspace.windowList();
        for (var i = 0; i < wins.length; i++) {{
            if (wins[i].internalId && wins[i].internalId.toString() === "{safe_win_id}") {{
                workspace.activeWindow = wins[i];
                break;
            }}
        }}
        '''
        run_kwin_one_shot(js)
    elif action == "MINIMIZE":
        js = f'''
        var wins = workspace.windowList();
        for (var i = 0; i < wins.length; i++) {{
            if (wins[i].internalId && wins[i].internalId.toString() === "{safe_win_id}") {{
                wins[i].minimized = !wins[i].minimized;
                break;
            }}
        }}
        '''
        run_kwin_one_shot(js)
    elif action == "MAXIMIZE":
        js = f'''
        var wins = workspace.windowList();
        for (var i = 0; i < wins.length; i++) {{
            if (wins[i].internalId && wins[i].internalId.toString() === "{safe_win_id}") {{
                wins[i].setMaximize(!wins[i].maximized, !wins[i].maximized);
                break;
            }}
        }}
        '''
        run_kwin_one_shot(js)
    elif action == "CLOSE":
        js = f'''
        var wins = workspace.windowList();
        for (var i = 0; i < wins.length; i++) {{
            if (wins[i].internalId && wins[i].internalId.toString() === "{safe_win_id}") {{
                wins[i].closeWindow();
                break;
            }}
        }}
        '''
        run_kwin_one_shot(js)

def stdin_reader_thread():
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            handle_command(line)
        except Exception:
            break

def poll_fallback():
    # Ping KWin to re-send window list periodically
    try:
        run_kwin_one_shot("sendWindows();")
    except Exception:
        pass
    return True

def main():
    global script_id, script_iface, script_file, kwin_scripting

    try:
        bus_name = dbus.service.BusName("org.quickshell.KWinBridge", session_bus)
        receiver = BridgeReceiver(session_bus)
    except Exception as e:
        sys.stderr.write(f"Failed to claim D-Bus name org.quickshell.KWinBridge: {e}\\n")

    try:
        scripting_obj = session_bus.get_object("org.kde.KWin", "/Scripting")
        kwin_scripting = dbus.Interface(scripting_obj, "org.kde.kwin.Scripting")

        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(KWIN_JS_TEMPLATE)
            script_file = f.name

        script_id = kwin_scripting.loadScript(script_file)
        script_obj = session_bus.get_object("org.kde.KWin", f"/Scripting/Script{script_id}")
        script_iface = dbus.Interface(script_obj, "org.kde.kwin.Script")
        script_iface.run()
    except Exception as e:
        sys.stderr.write(f"Failed to load KWin tracking script: {e}\\n")
        sys.stderr.flush()

    # Start stdin reader thread
    t = threading.Thread(target=stdin_reader_thread, daemon=True)
    t.start()

    loop = GLib.MainLoop()
    try:
        loop.run()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        cleanup()

if __name__ == "__main__":
    main()
