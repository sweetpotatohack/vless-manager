from __future__ import annotations

import os
import sqlite3
from pathlib import Path

VLESS_CONFIG_DIR = Path(os.environ.get("VLESS_CONFIG_DIR", "/etc/vless-manager"))
URL_DIR = VLESS_CONFIG_DIR / "urls"
QR_DIR = VLESS_CONFIG_DIR / "qr-codes"


def list_local_vless_clients() -> list[dict]:
    """Все строки clients.db (Wi‑Fi и *-mob отдельно)."""
    db_path = VLESS_CONFIG_DIR / "clients.db"
    if not db_path.is_file():
        return []
    try:
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        cur = conn.execute(
            "SELECT name, port, created_at FROM clients ORDER BY created_at DESC LIMIT 200"
        )
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return rows
    except sqlite3.Error:
        return []


def list_grouped_local_clients() -> list[dict]:
    """Один логический клиент (Wi‑Fi + LTE), без дубля *-mob в списке."""
    raw = list_local_vless_clients()
    by_name = {r["name"]: r for r in raw}
    grouped: list[dict] = []
    handled: set[str] = set()

    for name, row in by_name.items():
        if name in handled:
            continue
        if name.endswith("-mob"):
            base = name[: -len("-mob")]
            if base in by_name:
                continue
            handled.add(name)
            grouped.append(
                {
                    "username": base,
                    "wifi_port": None,
                    "mobile_port": row.get("port"),
                    "created_at": row.get("created_at"),
                }
            )
            continue
        handled.add(name)
        mob = by_name.get(f"{name}-mob")
        if mob:
            handled.add(f"{name}-mob")
        grouped.append(
            {
                "username": name,
                "wifi_port": row.get("port"),
                "mobile_port": mob.get("port") if mob else None,
                "created_at": row.get("created_at"),
            }
        )
    grouped.sort(key=lambda x: x.get("created_at") or "", reverse=True)
    return grouped


def count_grouped_local_clients() -> int:
    return len(list_grouped_local_clients())


def load_local_client_urls(username: str) -> dict[str, str]:
    out: dict[str, str] = {}
    wifi = URL_DIR / f"{username}.txt"
    if wifi.is_file():
        out["wifi_vless_url"] = wifi.read_text().strip()
    mob = f"{username}-mob"
    mob_v = URL_DIR / f"{mob}.txt"
    if mob_v.is_file():
        out["mobile_vless_url"] = mob_v.read_text().strip()
    hy = URL_DIR / f"{mob}-hy2.txt"
    if not hy.is_file():
        hy = URL_DIR / f"{username}-hy2.txt"
    if hy.is_file():
        out["hysteria_url"] = hy.read_text().strip()
    return out


def local_qr_filenames(username: str) -> tuple[str | None, str | None]:
    wifi_qr = QR_DIR / f"{username}.png"
    mob_qr = QR_DIR / f"{username}-mob.png"
    return (
        wifi_qr.name if wifi_qr.is_file() else None,
        mob_qr.name if mob_qr.is_file() else None,
    )
