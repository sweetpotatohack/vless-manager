"""Локальная серверная часть Cloudflare обхода: cf.env + xray-cf.service.

Панель хранит настройки CF в panel_settings, но CLI (vless_manager.sh) читает
/etc/vless-manager/cf.env. Эти функции синхронизируют два источника и управляют
xray-cf (VLESS + WebSocket на порту 8443, клиент подключается через Cloudflare:443).
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from app.config import VLESS_CONFIG_DIR, VLESS_MANAGER_SH

CF_ENV = VLESS_CONFIG_DIR / "cf.env"


def read_cf_env() -> dict[str, str]:
    out: dict[str, str] = {
        "CF_HOST": "",
        "CF_PATH": "/ws-akuma67",
        "CF_PORT": "8443",
        "CF_ZONE": "",
    }
    if CF_ENV.is_file():
        for line in CF_ENV.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def write_cf_env(*, host: str, path: str, port: int, zone: str) -> None:
    CF_ENV.parent.mkdir(parents=True, exist_ok=True)
    p = path.strip()
    if p and not p.startswith("/"):
        p = "/" + p
    CF_ENV.write_text(
        f"CF_HOST={host.strip()}\n"
        f"CF_PATH={p or '/ws-akuma67'}\n"
        f"CF_PORT={int(port)}\n"
        f"CF_ZONE={zone.strip()}\n"
    )
    CF_ENV.chmod(0o600)


def _mgr() -> Path:
    mgr = VLESS_MANAGER_SH
    if not mgr.is_file():
        mgr = Path(__file__).resolve().parents[3] / "vless_manager.sh"
    return mgr


def _run_cli(*args: str, timeout: int = 120) -> tuple[int, str]:
    try:
        r = subprocess.run(
            ["/bin/bash", str(_mgr()), "cli", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return r.returncode, (r.stdout + r.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def ensure_cf_server() -> tuple[bool, str]:
    code, out = _run_cli("ensure-cf")
    return code == 0, out


def cf_server_status() -> dict[str, str]:
    code, out = _run_cli("cf-status", timeout=60)
    status: dict[str, str] = {}
    if code == 0:
        for line in out.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                status[k.strip()] = v.strip()
    return status
