from __future__ import annotations

import re
import subprocess

from sqlalchemy.orm import Session

from app.auth import hash_password
from app.config import DATA_DIR, VLESS_CONFIG_DIR
from app.models import AdminUser, Node


def _default_local_country() -> str:
    override = DATA_DIR / "local-country.txt"
    if override.is_file():
        t = override.read_text().strip()
        if t:
            return t
    return "Germany (EU)"


def _read_public_host() -> str:
    tls_env = VLESS_CONFIG_DIR / "tls.env"
    if tls_env.is_file():
        text = tls_env.read_text()
        for line in text.splitlines():
            if line.startswith("PUBLIC_HOST="):
                val = line.split("=", 1)[1].strip().strip('"').strip("'")
                if val:
                    return val
    return "localhost"


def _detect_public_ip() -> str:
    for url in (
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
    ):
        try:
            out = subprocess.run(
                ["curl", "-4", "-fsS", "--max-time", "8", url],
                capture_output=True,
                text=True,
                check=False,
            )
            ip = out.stdout.strip()
            if re.match(r"^\d+\.\d+\.\d+\.\d+$", ip):
                return ip
        except OSError:
            pass
    return ""


def ensure_default_admin(db: Session) -> None:
    if db.query(AdminUser).count() > 0:
        return
    db.add(
        AdminUser(
            username="admin",
            password_hash=hash_password("admin"),
        )
    )
    db.commit()


def ensure_local_node(db: Session) -> Node:
    host = _read_public_host()
    slug = re.sub(r"[^a-z0-9]+", "-", host.lower()).strip("-") or "local"
    pub_ip = _detect_public_ip()
    node = db.query(Node).filter(Node.role == "local").first()
    if node:
        changed = False
        if node.domain != host:
            node.domain = host
            node.name = host
            changed = True
        if pub_ip and node.public_ip != pub_ip:
            node.public_ip = pub_ip
            changed = True
        if not node.country or node.country == "Master (local)":
            node.country = _default_local_country()
            changed = True
        if not node.agent_status:
            node.agent_status = "online"
            changed = True
        if changed:
            db.commit()
        return node
    node = Node(
        name=host,
        slug=slug,
        domain=host,
        region="local",
        country=_default_local_country(),
        public_ip=pub_ip or "",
        role="local",
        api_base=f"http://127.0.0.1:8765",
        api_token=None,
        agent_status="online",
        is_active=True,
    )
    db.add(node)
    db.commit()
    db.refresh(node)
    return node
