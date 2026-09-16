#!/usr/bin/env python3
"""
ethernet-bridge.py — Helper bridge for Ethernet and Internet connectivity status in Quickshell.

Commands:
  status               - Return JSON with interface, carrier, IP, gateway, DNS, speed, connectivity
  ping [target]        - Run quick ping test (default 1.1.1.1) and return latency
  check                - Trigger NetworkManager connectivity check and return status
  open-settings        - Open system network settings GUI
  reconnect [iface]    - Reapply/reconnect the ethernet interface
"""

import sys
import json
import os
import time
import socket
import subprocess
import re

def run_cmd(cmd, timeout=3):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return -1, "", str(e)

def find_ethernet_interfaces():
    # Fast path for primary ethernet interface on this system
    if os.path.exists("/sys/class/net/enp34s0"):
        return ["enp34s0"]
    net_dir = "/sys/class/net"
    eth_ifaces = []
    if not os.path.exists(net_dir):
        return eth_ifaces
    for iface in sorted(os.listdir(net_dir)):
        if iface == "lo" or iface.startswith(("tailscale", "docker", "br-", "veth", "virbr", "tun", "tap")):
            continue
        type_path = os.path.join(net_dir, iface, "type")
        wireless_path = os.path.join(net_dir, iface, "wireless")
        phy80211_path = os.path.join(net_dir, iface, "phy80211")
        if os.path.exists(wireless_path) or os.path.exists(phy80211_path):
            continue
        try:
            with open(type_path, "r") as f:
                dev_type = f.read().strip()
            if dev_type == "1":  # ARPHRD_ETHER
                eth_ifaces.append(iface)
        except Exception:
            pass
    return eth_ifaces

def test_internet_socket(ip_address="", host="1.1.1.1", port=53, timeout=1.0):
    """Test actual WAN connectivity by connecting to public DNS."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        if ip_address:
            # Strip CIDR prefix if present
            clean_ip = ip_address.split("/")[0].strip()
            if clean_ip:
                try:
                    s.bind((clean_ip, 0))
                except Exception:
                    pass
        s.connect((host, port))
        s.close()
        return True
    except Exception:
        # Fallback to secondary endpoint (8.8.8.8)
        try:
            s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s2.settimeout(timeout)
            s2.connect(("8.8.8.8", 53))
            s2.close()
            return True
        except Exception:
            return False

def ping_target(host="1.1.1.1", timeout=1.5):
    """Run ping and return (ok, latency_ms, raw_output)."""
    try:
        res = subprocess.run(
            f"ping -c 1 -W {int(timeout)} {host}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout + 0.5
        )
        if res.returncode == 0:
            m = re.search(r"time=([\d\.]+)\s*ms", res.stdout)
            lat = float(m.group(1)) if m else 0.0
            return True, lat, res.stdout.strip()
        return False, -1.0, res.stderr.strip() or res.stdout.strip()
    except Exception as e:
        return False, -1.0, str(e)

def read_rx_tx_bytes(iface):
    rx, tx = 0, 0
    try:
        rx_path = f"/sys/class/net/{iface}/statistics/rx_bytes"
        tx_path = f"/sys/class/net/{iface}/statistics/tx_bytes"
        if os.path.exists(rx_path) and os.path.exists(tx_path):
            with open(rx_path, "r") as f:
                rx = int(f.read().strip())
            with open(tx_path, "r") as f:
                tx = int(f.read().strip())
    except Exception:
        pass
    return rx, tx

def get_status():
    t0 = time.time()
    ifaces = find_ethernet_interfaces()
    if not ifaces:
        return {
            "ok": False,
            "error": "No ethernet interface detected",
            "status": "not_found",
            "carrier": False,
            "has_internet": False
        }

    target_iface = ifaces[0]

    # Try DBus first for NetworkManager metadata
    carrier = False
    operstate = "unknown"
    speed = -1
    hw_addr = ""
    con_name = ""
    ip4 = ""
    ipv6 = ""
    gateway = ""
    dns_list = []
    nm_connectivity = 0  # 4 = full
    is_active = False

    try:
        import dbus
        bus = dbus.SystemBus()
        nm = bus.get_object("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager")
        nm_props = dbus.Interface(nm, "org.freedesktop.DBus.Properties")
        nm_connectivity = int(nm_props.Get("org.freedesktop.NetworkManager", "Connectivity"))
        devices = nm_props.Get("org.freedesktop.NetworkManager", "Devices")

        for d_path in devices:
            d = bus.get_object("org.freedesktop.NetworkManager", d_path)
            d_props = dbus.Interface(d, "org.freedesktop.DBus.Properties")
            dtype = int(d_props.Get("org.freedesktop.NetworkManager.Device", "DeviceType"))
            if dtype == 1:  # Ethernet
                cur_iface = str(d_props.Get("org.freedesktop.NetworkManager.Device", "Interface"))
                if cur_iface in ifaces:
                    target_iface = cur_iface
                    state = int(d_props.Get("org.freedesktop.NetworkManager.Device", "State"))
                    is_active = (state == 100)
                    carrier = bool(d_props.Get("org.freedesktop.NetworkManager.Device.Wired", "Carrier"))
                    speed = int(d_props.Get("org.freedesktop.NetworkManager.Device.Wired", "Speed"))
                    hw_addr = str(d_props.Get("org.freedesktop.NetworkManager.Device.Wired", "HwAddress"))

                    ac_path = d_props.Get("org.freedesktop.NetworkManager.Device", "ActiveConnection")
                    if ac_path and ac_path != "/":
                        ac = bus.get_object("org.freedesktop.NetworkManager", ac_path)
                        ac_props = dbus.Interface(ac, "org.freedesktop.DBus.Properties")
                        con_name = str(ac_props.Get("org.freedesktop.NetworkManager.Connection.Active", "Id"))
                        ip4_path = ac_props.Get("org.freedesktop.NetworkManager.Connection.Active", "Ip4Config")
                        if ip4_path and ip4_path != "/":
                            ip4_obj = bus.get_object("org.freedesktop.NetworkManager", ip4_path)
                            ip4_props = dbus.Interface(ip4_obj, "org.freedesktop.DBus.Properties")
                            gateway = str(ip4_props.Get("org.freedesktop.NetworkManager.IP4Config", "Gateway"))
                            addr_data = ip4_props.Get("org.freedesktop.NetworkManager.IP4Config", "AddressData")
                            if addr_data:
                                ip4 = str(addr_data[0].get("address")) + "/" + str(addr_data[0].get("prefix"))
                            nameservers = ip4_props.Get("org.freedesktop.NetworkManager.IP4Config", "NameserverData")
                            if nameservers:
                                for ns in nameservers:
                                    dns_list.append(str(ns.get("address")))
                    break
    except Exception:
        pass

    # Sysfs & ip route fallback / augmentation
    if not carrier:
        carrier_path = f"/sys/class/net/{target_iface}/carrier"
        if os.path.exists(carrier_path):
            try:
                with open(carrier_path, "r") as f:
                    carrier = (f.read().strip() == "1")
            except Exception:
                pass

    oper_path = f"/sys/class/net/{target_iface}/operstate"
    if os.path.exists(oper_path):
        try:
            with open(oper_path, "r") as f:
                operstate = f.read().strip()
        except Exception:
            pass

    if speed <= 0:
        speed_path = f"/sys/class/net/{target_iface}/speed"
        if os.path.exists(speed_path):
            try:
                with open(speed_path, "r") as f:
                    speed = int(f.read().strip())
            except Exception:
                pass

    if not hw_addr:
        addr_path = f"/sys/class/net/{target_iface}/address"
        if os.path.exists(addr_path):
            try:
                with open(addr_path, "r") as f:
                    hw_addr = f.read().strip()
            except Exception:
                pass

    if not ip4:
        rc, out, _ = run_cmd(f"ip -4 -j addr show dev {target_iface}", timeout=1)
        if rc == 0 and out:
            try:
                data = json.loads(out)
                for d in data:
                    for ai in d.get("addr_info", []):
                        if ai.get("family") == "inet":
                            ip4 = str(ai.get("local")) + "/" + str(ai.get("prefixlen"))
                            break
            except Exception:
                pass

    # Check IPv6
    rc, out6, _ = run_cmd(f"ip -6 -j addr show dev {target_iface} scope global", timeout=1)
    if rc == 0 and out6:
        try:
            data6 = json.loads(out6)
            for d in data6:
                for ai in d.get("addr_info", []):
                    if ai.get("family") == "inet6":
                        ipv6 = str(ai.get("local")) + "/" + str(ai.get("prefixlen"))
                        break
        except Exception:
            pass

    # Check default route
    is_default_dev = False
    if not gateway:
        rc, rout, _ = run_cmd("ip -4 -j route show default", timeout=1)
        if rc == 0 and rout:
            try:
                rdata = json.loads(rout)
                for r in rdata:
                    if r.get("dev") == target_iface:
                        is_default_dev = True
                        gateway = r.get("gateway", "")
                        break
            except Exception:
                pass
    else:
        is_default_dev = True

    if not dns_list:
        rc, d_out, _ = run_cmd(f"resolvectl dns {target_iface} 2>/dev/null", timeout=1)
        if rc == 0 and d_out:
            parts = d_out.split(":")
            if len(parts) > 1:
                dns_list = [x.strip() for x in parts[1].split() if x.strip()]

    rx_b, tx_b = read_rx_tx_bytes(target_iface)

    # Determine internet connectivity
    # NM connectivity: 4 = FULL, 3 = LIMITED, 2 = PORTAL, 1 = NONE, 0 = UNKNOWN
    has_internet = False
    if carrier and ip4:
        if nm_connectivity == 4:
            has_internet = True
        else:
            # Direct socket test to confirm
            has_internet = test_internet_socket(ip_address=ip4, timeout=0.8)

    # Compute status string
    status_str = "offline"
    status_desc = "Disconnected"
    if not carrier:
        status_str = "unplugged"
        status_desc = "Cable Unplugged"
    elif not ip4:
        status_str = "connecting"
        status_desc = "Connecting / Acquiring IP..."
    elif has_internet:
        status_str = "internet"
        status_desc = "Connected • Internet OK"
    else:
        status_str = "no_internet"
        status_desc = "Connected • No Internet"

    # Human readable speed
    speed_label = "Unknown"
    if speed > 0:
        if speed >= 1000:
            speed_label = f"{speed // 1000} Gbps"
        else:
            speed_label = f"{speed} Mbps"

    query_ms = round((time.time() - t0) * 1000, 1)

    return {
        "ok": True,
        "interface": target_iface,
        "interfaces": ifaces,
        "carrier": carrier,
        "operstate": operstate,
        "speed_mbps": speed,
        "speed_label": speed_label,
        "hw_address": hw_addr,
        "ip": ip4,
        "ipv6": ipv6,
        "gateway": gateway,
        "dns": dns_list,
        "connection_name": con_name or "Wired connection",
        "nm_connectivity": nm_connectivity,
        "has_internet": has_internet,
        "is_default_route": is_default_dev,
        "status": status_str,
        "status_desc": status_desc,
        "rx_bytes": rx_b,
        "tx_bytes": tx_b,
        "query_time_ms": query_ms
    }

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"

    if action == "status":
        print(json.dumps(get_status()))
    elif action == "ping":
        target = sys.argv[2] if len(sys.argv) > 2 else "1.1.1.1"
        ok, lat, out = ping_target(target)
        print(json.dumps({
            "ok": ok,
            "target": target,
            "latency_ms": lat,
            "output": out
        }))
    elif action == "check":
        # Force NM connectivity check
        run_cmd("nmcli networking connectivity check", timeout=2)
        print(json.dumps(get_status()))
    elif action == "open-settings":
        # Launch KDE network management or fallback
        cmd = "kcmshell6 kcm_networkmanagement &"
        run_cmd(cmd, timeout=1)
        print(json.dumps({"ok": True}))
    elif action == "reconnect":
        iface = sys.argv[2] if len(sys.argv) > 2 else ""
        if not iface:
            ifaces = find_ethernet_interfaces()
            iface = ifaces[0] if ifaces else ""
        if iface:
            run_cmd(f"nmcli device reapply {iface} || nmcli device connect {iface}", timeout=5)
            print(json.dumps({"ok": True, "interface": iface}))
        else:
            print(json.dumps({"ok": False, "error": "No interface specified"}))
    else:
        print(json.dumps({"ok": False, "error": f"Unknown action: {action}"}))

if __name__ == "__main__":
    main()
