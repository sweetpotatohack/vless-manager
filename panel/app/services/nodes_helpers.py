from __future__ import annotations

from app.models import Node


def node_vpn_host(node: Node | None) -> str:
    """DNS для клиентских ссылок (из формы «Домен VPN»), иначе public IP."""
    if not node:
        return ""
    domain = (node.domain or "").strip()
    if domain and not domain.endswith(".local"):
        return domain
    return (node.public_ip or domain or "").strip()
