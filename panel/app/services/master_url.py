from __future__ import annotations

import os

from fastapi import Request

from app.config import BIND_PORT, DATA_DIR


def get_master_public_url(request: Request | None = None) -> str:
    env = os.environ.get("VLESS_PANEL_MASTER_URL", "").strip()
    if env:
        return env.rstrip("/")
    cached = DATA_DIR / "master.url"
    if cached.is_file():
        return cached.read_text().strip().rstrip("/")
    if request is not None:
        host = request.headers.get("host", "").split(",")[0].strip()
        if host:
            scheme = request.url.scheme
            url = f"{scheme}://{host}"
            try:
                cached.write_text(url)
            except OSError:
                pass
            return url.rstrip("/")
    return f"http://127.0.0.1:{BIND_PORT}"
