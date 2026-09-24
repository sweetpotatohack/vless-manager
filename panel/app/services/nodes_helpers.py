from __future__ import annotations

import re

from app.models import Node

_PRIVATE_IP_RE = re.compile(
    r"^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)"
)


def is_private_ip(ip: str) -> bool:
    return bool(_PRIVATE_IP_RE.match((ip or "").strip()))


def apply_agent_public_ip(node: Node, ip: str) -> None:
    """В колонке «IP» — белый egress; LAN не затирает уже известный public."""
    ip = (ip or "").strip()
    if not ip or not re.match(r"^\d+\.\d+\.\d+\.\d+$", ip):
        return
    if is_private_ip(ip):
        if not node.public_ip or is_private_ip(node.public_ip):
            node.public_ip = ip
        return
    node.public_ip = ip


def node_region_display(node: Node | None) -> str:
    if not node:
        return "—"
    if (node.country or "").strip():
        return node.country.strip()
    if node.role == "local":
        return "Germany (EU)"
    return (node.region or "—").strip() or "—"


def node_role_display(node: Node | None) -> str:
    if not node:
        return "—"
    if node.role == "local":
        return "master"
    if node.role == "remote":
        return "agent"
    return node.role or "—"


def node_vpn_host(node: Node | None) -> str:
    """DNS для клиентских ссылок (из формы «Домен VPN»), иначе public IP."""
    if not node:
        return ""
    domain = (node.domain or "").strip()
    if domain and not domain.endswith(".local"):
        return domain
    return (node.public_ip or domain or "").strip()
