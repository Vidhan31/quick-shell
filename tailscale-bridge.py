#!/usr/bin/env python3
"""
tailscale-bridge.py — Helper bridge for Tailscale status and actions in Quickshell.
Supports:
  status               - Fetch all status, serve, funnel, prefs, peers as JSON
  ssh-toggle <on|off>  - Enable or disable Tailscale SSH server
  serve-start <opts>   - Start serving a local service/port/dir (via serve or funnel)
  serve-stop <port>    - Stop serving a specific port
  funnel-toggle <port> <target> <is_funnel> - Switch between Serve (tailnet only) and Funnel (public)
  serve-reset          - Reset all serve/funnel configs
  up-down <up|down>    - Connect or disconnect Tailscale
  set-pref <name> <val>- Set Tailscale preference (e.g. webclient, shields-up, advertise-exit-node)
  ping <ip>            - Ping peer over Tailscale and return latency string
  netcheck             - Run tailscale netcheck and return summary
  copy <text>          - Copy text to Wayland clipboard using wl-copy
  open-url <url>       - Open URL in default browser
"""

import sys
import json
import subprocess
import os

def run_cmd(cmd, timeout=5):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)

def get_json(cmd, timeout=5):
    rc, stdout, stderr = run_cmd(cmd, timeout=timeout)
    if rc == 0 and stdout:
        try:
            return json.loads(stdout)
        except Exception:
            pass
    return None

def get_all_status():
    status = get_json("tailscale status --json") or {}
    serve = get_json("tailscale serve status --json") or {}
    _, funnel_txt, _ = run_cmd("tailscale funnel status", timeout=4)
    prefs = get_json("tailscale get --json all") or {}
    services = get_json("tailscale service list --json") or []

    allow_funnel_map = serve.get("AllowFunnel") or {}
    funnel_lower = funnel_txt.lower()
    is_funnel_global = ("funnel on" in funnel_lower) or ("available on the internet" in funnel_lower)

    items = []
    tcp_map = serve.get("TCP", {})
    web_map = serve.get("Web", {})

    for host_port, host_cfg in web_map.items():
        parts = host_port.split(":")
        host = parts[0]
        port = parts[1] if len(parts) > 1 else "443"

        is_funnel = False
        if isinstance(allow_funnel_map, dict):
            if allow_funnel_map.get(host_port, False) or allow_funnel_map.get(f"{host}:{port}", False) or allow_funnel_map.get(str(port), False):
                is_funnel = True
        elif allow_funnel_map is True:
            is_funnel = True

        if not is_funnel and is_funnel_global:
            is_funnel = True

        handlers = host_cfg.get("Handlers", {})
        for path, handler_cfg in handlers.items():
            target = handler_cfg.get("Proxy") or handler_cfg.get("Text") or handler_cfg.get("Path") or "Unknown"
            h_type = "proxy" if "Proxy" in handler_cfg else ("text" if "Text" in handler_cfg else "path")
            path_suffix = "" if path == "/" else path
            
            items.append({
                "host": host,
                "port": port,
                "path": path,
                "target": target,
                "type": h_type,
                "is_funnel": is_funnel,
                "url": "https://" + host + (":" + port if port not in ("443", "80") else "") + path_suffix
            })

    for port, port_cfg in tcp_map.items():
        if isinstance(port_cfg, dict) and "TCPForward" in port_cfg:
            dns_name = status.get("Self", {}).get("DNSName", "").rstrip(".")
            tf = port_cfg.get("TCPForward", "")
            is_tcp_funnel = False
            if isinstance(allow_funnel_map, dict):
                is_tcp_funnel = bool(allow_funnel_map.get(str(port)) or allow_funnel_map.get(f"{dns_name}:{port}"))
            elif allow_funnel_map is True:
                is_tcp_funnel = True

            if not is_tcp_funnel and is_funnel_global:
                is_tcp_funnel = True

            items.append({
                "host": dns_name,
                "port": str(port),
                "path": "",
                "target": "tcp://" + str(tf),
                "type": "tcp",
                "is_funnel": is_tcp_funnel,
                "url": "tcp://" + dns_name + ":" + str(port)
            })

    self_node = status.get("Self", {})
    self_ips = self_node.get("TailscaleIPs") or ["", ""]
    ipv4 = self_ips[0] if len(self_ips) > 0 else ""
    ipv6 = self_ips[1] if len(self_ips) > 1 else ""

    user_info = {}
    users_dict = status.get("User", {})
    if users_dict:
        user_info = list(users_dict.values())[0]

    out = {
        "ok": True,
        "connected": status.get("BackendState") == "Running",
        "backend_state": status.get("BackendState", "Unknown"),
        "version": status.get("Version", ""),
        "tailnet": status.get("CurrentTailnet", {}).get("Name", ""),
        "magic_dns_suffix": status.get("MagicDNSSuffix", ""),
        "self": {
            "hostname": self_node.get("HostName", ""),
            "dns_name": self_node.get("DNSName", "").rstrip("."),
            "ipv4": ipv4,
            "ipv6": ipv6,
            "os": self_node.get("OS", "linux"),
            "online": self_node.get("Online", False),
            "relay": self_node.get("Relay", ""),
            "user": user_info,
        },
        "health": status.get("Health") or [],
        "ssh_enabled": bool(prefs.get("ssh", False)),
        "webclient_enabled": bool(prefs.get("webclient", False)),
        "shields_up": bool(prefs.get("shields-up", False)),
        "exit_node_enabled": bool(prefs.get("advertise-exit-node", False)),
        "auto_update": bool(prefs.get("auto-update", False)),
        "serve_items": items,
        "peers": [],
        "services": services
    }

    peers_dict = status.get("Peer", {})
    for pkey, pval in peers_dict.items():
        hostname = pval.get("HostName", "")
        # Filter out internal Funnel ingress relay nodes from peer list
        if not hostname or hostname == "funnel-ingress-node":
            continue
        tags = pval.get("Tags") or []
        if any("funnel-ingress" in t for t in tags):
            continue

        pips = pval.get("TailscaleIPs") or [""]
        out["peers"].append({
            "hostname": hostname,
            "dns_name": pval.get("DNSName", "").rstrip("."),
            "os": pval.get("OS", ""),
            "ipv4": pips[0] if len(pips) > 0 else "",
            "online": pval.get("Online", False),
            "active": pval.get("Active", False),
            "relay": pval.get("Relay", ""),
            "rx_bytes": pval.get("RxBytes", 0),
            "tx_bytes": pval.get("TxBytes", 0),
        })

    return out

def handle_action(args):
    if not args:
        print(json.dumps(get_all_status(), indent=2))
        return

    cmd_type = args[0]

    if cmd_type == "status":
        print(json.dumps(get_all_status(), indent=2))
        return

    if cmd_type == "ssh-toggle":
        enable = args[1] if len(args) > 1 else "true"
        flag = "true" if enable.lower() in ("true", "1", "on", "yes") else "false"
        rc, out, err = run_cmd(f"tailscale set --ssh={flag}")
        print(json.dumps({"ok": rc == 0, "output": out, "error": err}))
        return

    if cmd_type == "up-down":
        action = args[1] if len(args) > 1 else "up"
        if action.lower() == "down":
            rc, out, err = run_cmd("tailscale down")
        else:
            rc, out, err = run_cmd("tailscale up")
        print(json.dumps({"ok": rc == 0, "output": out, "error": err}))
        return

    if cmd_type == "set-pref":
        pref = args[1] if len(args) > 1 else ""
        val = args[2] if len(args) > 2 else ""
        if not pref:
            print(json.dumps({"ok": False, "error": "Missing pref name"}))
            return
        rc, out, err = run_cmd(f"tailscale set --{pref}={val}")
        print(json.dumps({"ok": rc == 0, "output": out, "error": err}))
        return

    if cmd_type == "serve-start":
        target = args[1] if len(args) > 1 else ""
        mode = args[2] if len(args) > 2 else "serve"
        port = args[3] if len(args) > 3 else "443"
        path = args[4] if len(args) > 4 else "/"

        if not target:
            print(json.dumps({"ok": False, "error": "Missing target"}))
            return

        cmd_parts = ["tailscale", mode, "--bg", "--yes"]
        if port == "80":
            cmd_parts.append(f"--http={port}")
        else:
            cmd_parts.append(f"--https={port}")

        if path and path != "/":
            cmd_parts.append(f"--set-path={path}")

        cmd_parts.append(f"'{target}'")
        full_cmd = " ".join(cmd_parts)
        rc, out, err = run_cmd(full_cmd, timeout=10)
        print(json.dumps({"ok": rc == 0, "output": out, "error": err, "cmd": full_cmd}))
        return

    if cmd_type == "serve-stop":
        port = args[1] if len(args) > 1 else "443"
        path = args[2] if len(args) > 2 else ""
        proto = "http" if port == "80" else "https"
        cmd1 = f"tailscale serve --{proto}={port} off" if not (path and path != "/") else f"tailscale serve --{proto}={port} --set-path={path} off"
        cmd2 = f"tailscale funnel --{proto}={port} off" if not (path and path != "/") else f"tailscale funnel --{proto}={port} --set-path={path} off"
        rc1, out1, err1 = run_cmd(cmd1)
        rc2, out2, err2 = run_cmd(cmd2)
        print(json.dumps({"ok": rc1 == 0 or rc2 == 0, "output": out1 + " " + out2, "error": err1 + " " + err2}))
        return

    if cmd_type == "funnel-toggle":
        port = args[1] if len(args) > 1 else "443"
        target = args[2] if len(args) > 2 else ""
        make_funnel = (args[3].lower() in ("true", "1", "yes")) if len(args) > 3 else True
        path = args[4] if len(args) > 4 else "/"

        mode = "funnel" if make_funnel else "serve"
        port_flag = f"--http={port}" if port == "80" else f"--https={port}"
        cmd_parts = ["tailscale", mode, "--bg", "--yes", port_flag]
        if path and path != "/":
            cmd_parts.append(f"--set-path={path}")
        if target:
            cmd_parts.append(f"'{target}'")

        full_cmd = " ".join(cmd_parts)
        rc, out, err = run_cmd(full_cmd, timeout=10)
        print(json.dumps({"ok": rc == 0, "output": out, "error": err, "cmd": full_cmd}))
        return

    if cmd_type == "serve-reset":
        rc, out, err = run_cmd("tailscale serve reset")
        print(json.dumps({"ok": rc == 0, "output": out, "error": err}))
        return

    if cmd_type == "ping":
        target_ip = args[1] if len(args) > 1 else ""
        if not target_ip:
            print(json.dumps({"ok": False, "error": "Missing IP"}))
            return
        rc, out, err = run_cmd(f"tailscale ping -c 1 {target_ip}", timeout=4)
        latency = ""
        if "in " in out:
            latency = out.split("in ")[-1].strip()
        print(json.dumps({"ok": rc == 0, "output": out, "latency": latency, "error": err}))
        return

    if cmd_type == "netcheck":
        rc, out, err = run_cmd("tailscale netcheck", timeout=8)
        print(json.dumps({"ok": rc == 0, "report": out, "error": err}))
        return

    if cmd_type == "copy":
        text = " ".join(args[1:])
        try:
            p = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE, text=True)
            p.communicate(input=text)
            print(json.dumps({"ok": True, "copied": text}))
        except Exception as e:
            print(json.dumps({"ok": False, "error": str(e)}))
        return

    if cmd_type == "open-url":
        url = args[1] if len(args) > 1 else ""
        if url:
            subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(json.dumps({"ok": True, "url": url}))
        else:
            print(json.dumps({"ok": False, "error": "Missing url"}))
        return

    print(json.dumps({"ok": False, "error": f"Unknown action {cmd_type}"}))

if __name__ == "__main__":
    handle_action(sys.argv[1:])
