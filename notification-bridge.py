#!/usr/bin/env python3
"""
notification-bridge.py — Real-time Desktop Notification Bridge for Quickshell.
Captures system notifications via D-Bus monitoring, streams them as JSON lines to stdout,
and forwards action invocations and close requests from Quickshell via stdin.
"""

import sys
import os
import json
import time
import threading
import signal
import dbus
import dbus.mainloop.glib
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
session_bus = None
main_loop = None

_notif_counter = 1
_id_map = {}

def on_signal(signum, frame):
    global main_loop
    if main_loop and main_loop.is_running():
        main_loop.quit()
    sys.exit(0)

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

def emit_json(obj):
    try:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
    except Exception:
        pass

def parse_notify_message(message):
    global _notif_counter
    try:
        args = message.get_args_list()
        if len(args) < 6:
            return None

        app_name = str(args[0]) if args[0] else "Application"
        replaces_id = int(args[1]) if len(args) > 1 else 0
        app_icon = str(args[2]) if len(args) > 2 else ""
        summary = str(args[3]) if len(args) > 3 else "Notification"
        body = str(args[4]) if len(args) > 4 else ""
        
        raw_actions = [str(x) for x in args[5]] if len(args) > 5 else []
        actions = []
        for i in range(0, len(raw_actions), 2):
            if i + 1 < len(raw_actions):
                actions.append({
                    "identifier": raw_actions[i],
                    "text": raw_actions[i + 1]
                })
            elif i < len(raw_actions):
                actions.append({
                    "identifier": raw_actions[i],
                    "text": raw_actions[i]
                })

        hints = {}
        if len(args) > 6 and isinstance(args[6], dict):
            for k, v in args[6].items():
                if k == "urgency":
                    try:
                        hints["urgency"] = int(v)
                    except Exception:
                        hints["urgency"] = 1
                elif k in ("image-path", "image_path"):
                    hints["image"] = str(v)
                elif k == "desktop-entry":
                    hints["desktopEntry"] = str(v)
                elif k == "category":
                    hints["category"] = str(v)

        timeout = int(args[7]) if len(args) > 7 else 5000

        # Assign unique tracking ID
        notif_id = replaces_id if replaces_id > 0 else _notif_counter
        _notif_counter += 1

        sender = str(message.get_sender() or "")
        _id_map[notif_id] = sender

        return {
            "type": "notify",
            "id": notif_id,
            "appName": app_name,
            "appIcon": app_icon,
            "summary": summary,
            "body": body,
            "actions": actions,
            "urgency": hints.get("urgency", 1),
            "image": hints.get("image", ""),
            "desktopEntry": hints.get("desktopEntry", ""),
            "timeout": timeout,
            "timestamp": int(time.time() * 1000)
        }
    except Exception as e:
        sys.stderr.write(f"Error parsing Notify message: {e}\n")
        sys.stderr.flush()
        return None

def message_filter(bus, message):
    try:
        member = message.get_member()
        interface = message.get_interface()

        if member == "Notify":
            data = parse_notify_message(message)
            if data:
                emit_json(data)
        elif member == "NotificationClosed":
            args = message.get_args_list()
            if len(args) >= 2:
                emit_json({
                    "type": "closed",
                    "id": int(args[0]),
                    "reason": int(args[1])
                })
        elif member == "ActionInvoked":
            args = message.get_args_list()
            if len(args) >= 2:
                emit_json({
                    "type": "action_invoked",
                    "id": int(args[0]),
                    "action": str(args[1])
                })
    except Exception as e:
        sys.stderr.write(f"Error in message filter: {e}\n")
        sys.stderr.flush()

def handle_stdin_command(line):
    global session_bus
    line = line.strip()
    if not line:
        return

    parts = line.split(" ", 2)
    cmd = parts[0].upper()

    try:
        if cmd == "INVOKE" and len(parts) >= 3:
            notif_id = int(parts[1])
            action_id = parts[2]
            # Try KDE NotificationManager InvokeAction
            try:
                kde_mgr = session_bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
                kde_mgr.InvokeAction(dbus.UInt32(notif_id), dbus.String(action_id), dbus_interface="org.kde.NotificationManager")
            except Exception:
                pass
            # Also emit ActionInvoked signal on session bus if needed
        elif cmd == "CLOSE" and len(parts) >= 2:
            notif_id = int(parts[1])
            try:
                notif_obj = session_bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
                notif_obj.CloseNotification(dbus.UInt32(notif_id), dbus_interface="org.freedesktop.Notifications")
            except Exception:
                pass
    except Exception as e:
        sys.stderr.write(f"Error handling stdin command '{line}': {e}\n")
        sys.stderr.flush()

def stdin_thread():
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            handle_stdin_command(line)
        except Exception:
            break

def main():
    global session_bus, main_loop

    try:
        session_bus = dbus.SessionBus()
        dbus_obj = session_bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus")
        monitoring_iface = dbus.Interface(dbus_obj, "org.freedesktop.DBus.Monitoring")
        monitoring_iface.BecomeMonitor(["interface=org.freedesktop.Notifications"], dbus.UInt32(0))
        session_bus.add_message_filter(message_filter)
    except Exception as e:
        sys.stderr.write(f"Failed to initialize D-Bus monitor: {e}\n")
        sys.stderr.flush()

    t = threading.Thread(target=stdin_thread, daemon=True)
    t.start()

    main_loop = GLib.MainLoop()
    try:
        main_loop.run()
    except (KeyboardInterrupt, SystemExit):
        pass

if __name__ == "__main__":
    main()
