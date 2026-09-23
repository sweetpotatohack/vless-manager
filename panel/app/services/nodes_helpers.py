from __future__ import annotations

from app.models import Node


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
