from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

VLESS_MIN = 25000
VLESS_MAX = 45000
NEVER = {80, 443, 8080, 8443, 8000, 8888, 3000, 5000, 3333, 53, 853, 4443, 9443, 9444}
CLIENT_DIR = Path("/etc/vless-manager/clients")


def _listening_tcp_udp_ports() -> set[int]:
    ports: set[int] = set()
    try:
        out = subprocess.run(
            ["ss", "-H", "-tuln"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        for line in out.stdout.splitlines():
            m = re.search(r":(\d+)\s", line)
            if m:
                ports.add(int(m.group(1)))
    except OSError:
        pass
    return ports


def _assigned_vless_ports() -> set[int]:
    ports: set[int] = set()
    if not CLIENT_DIR.is_dir():
        return ports
    for cfg in CLIENT_DIR.glob("*.json"):
        if cfg.name.startswith("_"):
            continue
        try:
            data = json.loads(cfg.read_text())
            for ib in data.get("inbounds", []):
                p = ib.get("port")
                if isinstance(p, int):
                    ports.add(p)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
    return ports


def _port_blocked(p: int, listening: set[int], assigned: set[int]) -> bool:
    if p in NEVER or p < 1024:
        return True
    if p in listening or p in assigned:
        return True
    return False


def find_free_wifi_port() -> int | None:
    listening = _listening_tcp_udp_ports()
    assigned = _assigned_vless_ports()
    for p in range(VLESS_MIN, VLESS_MAX + 1):
        if not _port_blocked(p, listening, assigned):
            return p
    return None


def port_status() -> dict:
    listening = sorted(_listening_tcp_udp_ports())
    assigned = sorted(_assigned_vless_ports())
    free = find_free_wifi_port()
    hy = 25001
    hy_busy = hy in listening
    reality_busy = 443 in listening
    return {
        "listening": listening,
        "assigned_vless": assigned,
        "free_wifi_port": free,
        "wifi_port_available": free is not None,
        "hysteria_udp_port": hy,
        "hysteria_port_listening": hy_busy,
        "reality_tcp_port": 443,
        "reality_port_listening": reality_busy,
    }


def ensure_can_provision(*, wifi: bool, mobile: bool) -> tuple[bool, str]:
    st = port_status()
    if wifi and not st["wifi_port_available"]:
        return False, (
            f"Нет свободного порта Wi‑Fi ({VLESS_MIN}-{VLESS_MAX}). "
            f"Занято: {st['assigned_vless'][:15]}{'…' if len(st['assigned_vless']) > 15 else ''}"
        )
    if mobile and not st["reality_port_listening"] and not st["hysteria_port_listening"]:
        # mobile setup may start services — allow if at least one path possible
        pass
    return True, "OK"
