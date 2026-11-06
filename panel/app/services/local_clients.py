from __future__ import annotations

import os
from pathlib import Path

VLESS_CONFIG_DIR = Path(os.environ.get("VLESS_CONFIG_DIR", "/etc/vless-manager"))
URL_DIR = VLESS_CONFIG_DIR / "urls"
QR_DIR = VLESS_CONFIG_DIR / "qr-codes"
HYSTERIA_DIR = VLESS_CONFIG_DIR / "hysteria-clients"


def list_local_hy2_clients() -> list[dict]:
    """Клиенты Hysteria2 на этой ноде (по файлам *.cred)."""
    rows: list[dict] = []
    if not HYSTERIA_DIR.is_dir():
        return rows
    for cred in sorted(HYSTERIA_DIR.glob("*.cred"), key=lambda p: p.stat().st_mtime, reverse=True):
        username = cred.stem
        if not username or username.startswith("_"):
            continue
        rows.append(
            {
                "username": username,
                "created_at": _mtime_iso(cred),
            }
        )
    return rows


def _mtime_iso(path: Path) -> str:
    try:
        return path.stat().st_mtime.__str__()
    except OSError:
        return ""


def count_grouped_local_clients() -> int:
    return len(list_local_hy2_clients())


def list_grouped_local_clients() -> list[dict]:
    return list_local_hy2_clients()


def load_local_client_urls(username: str) -> dict[str, str]:
    out: dict[str, str] = {}
    url = URL_DIR / f"{username}.txt"
    if url.is_file():
        content = url.read_text().strip()
        if content.startswith("hysteria2://"):
            out["hysteria_url"] = content
    pc = URL_DIR / f"{username}-pc.txt"
    if pc.is_file():
        content = pc.read_text().strip()
        if content.startswith("vless://"):
            out["wifi_vless_url"] = content
    return out


def local_qr_filenames(username: str) -> tuple[str | None, str | None]:
    qr = QR_DIR / f"{username}.png"
    pc_qr = QR_DIR / f"{username}-pc.png"
    return (qr.name if qr.is_file() else None, pc_qr.name if pc_qr.is_file() else None)
