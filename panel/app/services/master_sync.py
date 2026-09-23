from __future__ import annotations

import os
from pathlib import Path

import httpx

PANEL_DATA = Path("/etc/vless-manager/panel")


def _read_master_url() -> str:
    url = os.environ.get("VLESS_PANEL_MASTER_URL", "").strip()
    if url:
        return url.rstrip("/")
    f = PANEL_DATA / "master.url"
    if f.is_file():
        return f.read_text().strip().rstrip("/")
    return ""


def _read_agent_token() -> str:
    token = os.environ.get("VLESS_PANEL_AGENT_TOKEN", "").strip()
    if token:
        return token
    f = PANEL_DATA / "agent.env"
    if not f.is_file():
        return ""
    for line in f.read_text().splitlines():
        if line.startswith("VLESS_PANEL_AGENT_TOKEN="):
            return line.split("=", 1)[1].strip()
    return ""


async def master_unregister_proxy_user(username: str) -> tuple[bool, str]:
    master = _read_master_url()
    token = _read_agent_token()
    if not master or not token:
        return False, "master.url или agent token не настроены"
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{master}/api/v1/agent/unregister-proxy-user",
                headers={"Authorization": f"Bearer {token}"},
                json={"username": username},
            )
            if resp.status_code >= 400:
                return False, resp.text[:300]
            return True, "OK"
    except Exception as e:
        return False, str(e)
