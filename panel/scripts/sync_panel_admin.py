#!/usr/bin/env python3
"""Create or update panel admin; on agent role copy password hash from master."""
from __future__ import annotations

import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from app.auth import hash_password
from app.database import SessionLocal
from app.models import AdminUser

DATA = Path("/etc/vless-manager/panel")


def _read_agent_token() -> str:
    token = os.environ.get("VLESS_PANEL_AGENT_TOKEN", "").strip()
    if token:
        return token
    env_file = DATA / "agent.env"
    if not env_file.is_file():
        return ""
    for line in env_file.read_text().splitlines():
        if line.startswith("VLESS_PANEL_AGENT_TOKEN="):
            return line.split("=", 1)[1].strip()
    return ""


def _read_master_url() -> str:
    url = os.environ.get("VLESS_PANEL_MASTER_URL", "").strip()
    if url:
        return url
    master_file = DATA / "master.url"
    if master_file.is_file():
        return master_file.read_text().strip()
    return ""


def _fetch_master_admin_hash(master_url: str, token: str) -> tuple[str, str] | None:
    q = urllib.parse.urlencode({"token": token})
    url = f"{master_url.rstrip('/')}/api/v1/agent/admin-sync?{q}"
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(url, timeout=30, context=ctx) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError, OSError) as exc:
        print(f"WARN: не удалось получить пароль admin с master: {exc}")
        return None
    username = (data.get("username") or "admin").strip() or "admin"
    password_hash = (data.get("password_hash") or "").strip()
    if not password_hash.startswith("$2"):
        print("WARN: master вернул некорректный password_hash")
        return None
    return username, password_hash


def main() -> None:
    role = os.environ.get("VLESS_PANEL_ROLE", "master")
    db = SessionLocal()
    try:
        sync: tuple[str, str] | None = None
        if role == "agent":
            master_url = _read_master_url()
            token = _read_agent_token()
            if master_url and token:
                sync = _fetch_master_admin_hash(master_url, token)
            else:
                print("WARN: agent без master.url или agent token — sync пароля пропущен")

        if sync:
            username, password_hash = sync
            admin = db.query(AdminUser).filter(AdminUser.username == username).first()
            if not admin:
                admin = AdminUser(username=username, password_hash=password_hash)
                db.add(admin)
            else:
                admin.password_hash = password_hash
            db.commit()
            print(f"Admin: пароль синхронизирован с master (логин: {username})")
            return

        admin = db.query(AdminUser).filter(AdminUser.username == "admin").first()
        if not admin:
            db.add(AdminUser(username="admin", password_hash=hash_password("admin")))
            db.commit()
            print("Admin: admin / admin (первый запуск)")
        else:
            print(f"Admin: логин {admin.username}, пароль без изменений")
    finally:
        db.close()


if __name__ == "__main__":
    main()
