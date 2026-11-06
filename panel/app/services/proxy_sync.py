from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import Node, ProxyUser
from app.services.nodes_helpers import node_vpn_host
from app.services.provision import ensure_qr_codes_for_user


def upsert_proxy_user_from_agent(
    db: Session,
    node: Node,
    entry: dict,
) -> ProxyUser:
    username = (entry.get("username") or "").strip()
    if not username:
        raise ValueError("empty username")
    hy2 = entry.get("hysteria_url")
    pc_url = entry.get("wifi_vless_url")
    has_wifi = bool(entry.get("has_wifi") or pc_url)
    wifi_port = entry.get("wifi_port")
    if wifi_port is None and pc_url:
        from app.services.provision import _extract_port_from_vless

        wifi_port = _extract_port_from_vless(pc_url)
    uuid = entry.get("uuid") or username

    pu = (
        db.query(ProxyUser)
        .filter(ProxyUser.node_id == node.id, ProxyUser.username == username)
        .first()
    )
    if not pu:
        pu = ProxyUser(node_id=node.id, username=username)
        db.add(pu)
    pu.has_wifi = has_wifi
    pu.has_mobile = False
    pu.has_hy2 = bool(hy2)
    pu.wifi_vless_url = pc_url
    pu.mobile_vless_url = None
    pu.hysteria_url = hy2
    pu.cf_vless_url = None
    pu.wifi_port = wifi_port
    pu.uuid = uuid
    pu.exit_country = node.country or node.region or ""
    pu.exit_ip = node_vpn_host(node) or node.public_ip or ""
    db.flush()
    ensure_qr_codes_for_user(username, hysteria_url=hy2, wifi_vless_url=pc_url)
    return pu


def apply_imported_clients(
    db: Session,
    node: Node,
    clients: list[dict],
) -> int:
    n = 0
    for entry in clients:
        if not isinstance(entry, dict):
            continue
        upsert_proxy_user_from_agent(db, node, entry)
        n += 1
    return n
