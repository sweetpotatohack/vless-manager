from __future__ import annotations

import os
import sqlite3
from pathlib import Path

VLESS_CONFIG_DIR = Path(os.environ.get("VLESS_CONFIG_DIR", "/etc/vless-manager"))


def list_local_vless_clients() -> list[dict]:
    """Wi‑Fi клиенты на этой машине (clients.db vless_manager)."""
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
