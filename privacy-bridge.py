#!/usr/bin/env python3
"""
privacy-bridge.py — Real-time camera and microphone activity detector.
Outputs JSON lines to stdout when monitoring, or single JSON object on 'status'.
"""

import sys
import os
import json
import time
import subprocess
import re

def get_v4l_device_name(dev_path):
    vname = os.path.basename(dev_path)
    sys_path = f"/sys/class/video4linux/{vname}/name"
    try:
        if os.path.exists(sys_path):
            with open(sys_path, "r", encoding="utf-8") as f:
                raw = f.read().strip()
                clean = raw.split(":")[0].replace(" Audio", "").strip()
                return clean or raw
    except Exception:
        pass
    return f"Camera ({vname})"

def check_privacy():
    cam_active = False
    cam_apps = []
    cam_devices = []

    # 1. Check open file descriptors in /proc for /dev/video*
    v4l_found = []
    try:
        for entry in os.scandir("/proc"):
            if entry.name.isdigit():
                pid = entry.name
                try:
                    fd_dir = f"/proc/{pid}/fd"
                    for fd in os.scandir(fd_dir):
                        try:
                            tgt = os.readlink(fd.path)
                            if tgt.startswith("/dev/video"):
                                v4l_found.append((pid, tgt))
                        except (OSError, ValueError):
                            pass
                except (PermissionError, FileNotFoundError):
                    pass
    except Exception:
        pass

    for pid, dev in v4l_found:
        try:
            with open(f"/proc/{pid}/comm", "r", encoding="utf-8") as f:
                comm = f.read().strip()
        except Exception:
            comm = f"PID {pid}"
        if comm in ("wireplumber", "pipewire"):
            continue
        dev_name = get_v4l_device_name(dev)
        if dev_name not in cam_devices:
            cam_devices.append(dev_name)
        if comm not in cam_apps:
            cam_apps.append(comm)
        cam_active = True

    # 2. Check PipeWire via pw-dump for audio recording and video streams
    mic_active = False
    mic_apps = []
    mic_devices = []

    try:
        proc = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=1.5)
        if proc.returncode == 0 and proc.stdout:
            data = json.loads(proc.stdout)
            nodes = {item["id"]: item for item in data if item.get("type") == "PipeWire:Interface:Node"}
            links = [item for item in data if item.get("type") == "PipeWire:Interface:Link"]

            for link in links:
                props = link.get("info", {}).get("props", {})
                out_id = props.get("link.output.node")
                in_id = props.get("link.input.node")
                out_node = nodes.get(out_id, {})
                in_node = nodes.get(in_id, {})
                out_props = out_node.get("info", {}).get("props", {})
                in_props = in_node.get("info", {}).get("props", {})
                out_class = out_props.get("media.class", "")
                in_class = in_props.get("media.class", "")

                # Microphone recording link
                if out_class == "Audio/Source" and in_class == "Stream/Input/Audio":
                    mic_active = True
                    app_name = (
                        in_props.get("application.name")
                        or in_props.get("node.name")
                        or in_node.get("info", {}).get("name")
                        or "Recording App"
                    )
                    source_desc = (
                        out_props.get("node.description")
                        or out_props.get("node.nick")
                        or "Microphone"
                    )
                    if app_name not in mic_apps:
                        mic_apps.append(app_name)
                    if source_desc not in mic_devices:
                        mic_devices.append(source_desc)

                # Video capture link
                if out_class == "Video/Source":
                    cam_active = True
                    app_name = (
                        in_props.get("application.name")
                        or in_props.get("node.name")
                        or in_node.get("info", {}).get("name")
                        or "Camera App"
                    )
                    cam_desc = (
                        out_props.get("node.description")
                        or out_props.get("node.nick")
                        or "Webcam"
                    )
                    if app_name not in cam_apps:
                        cam_apps.append(app_name)
                    if cam_desc not in cam_devices:
                        cam_devices.append(cam_desc)
    except Exception:
        pass

    # Fallback to wpctl status if pw-dump didn't show mic
    if not mic_active:
        try:
            wp_proc = subprocess.run(["wpctl", "status"], capture_output=True, text=True, timeout=1.0)
            if wp_proc.returncode == 0:
                lines = wp_proc.stdout.splitlines()
                section = None
                curr_app = ""
                for line in lines:
                    stripped = line.strip()
                    if stripped.startswith("Audio"):
                        section = "audio"
                    elif stripped.startswith("Video"):
                        section = "video"
                    elif stripped.startswith("Settings"):
                        section = "settings"

                    if section == "audio":
                        m = re.match(r"^\s*([0-9]+)\.\s+([^\s].*?)\s*$", line)
                        if m:
                            curr_app = m.group(2).strip()
                        if "<" in line and "[active]" in line:
                            mic_active = True
                            if curr_app and curr_app not in mic_apps:
                                mic_apps.append(curr_app)
        except Exception:
            pass

    return {
        "camera": {
            "active": cam_active,
            "apps": cam_apps,
            "devices": cam_devices
        },
        "microphone": {
            "active": mic_active,
            "apps": mic_apps,
            "devices": mic_devices
        }
    }

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "monitor"

    if mode == "status":
        print(json.dumps(check_privacy()))
        sys.stdout.flush()
        return

    last_payload = ""
    poll_interval = 0.6  # 600 ms
    ticks_since_emit = 0

    while True:
        try:
            state = check_privacy()
            payload = json.dumps(state)
            ticks_since_emit += 1
            if payload != last_payload or ticks_since_emit >= 5:
                sys.stdout.write(payload + "\n")
                sys.stdout.flush()
                last_payload = payload
                ticks_since_emit = 0
        except Exception:
            pass
        time.sleep(poll_interval)

if __name__ == "__main__":
    main()
