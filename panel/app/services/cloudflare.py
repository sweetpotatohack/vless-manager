"""Cloudflare API v4 helpers: zones, DNS, Origin Rules, SSL mode, origin check.

Используется панелью для «из коробки»: вставил API-токен → «Подготовить домен»
→ панель сама создаёт DNS A-запись с проксированием, Origin Rule на порт xray-cf
и выставляет SSL-режим Full.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

import httpx

CF_API = "https://api.cloudflare.com/client/v4"


@dataclass
class CfResult:
    ok: bool
    message: str
    data: dict | None = None
    errors: list[str] = field(default_factory=list)


def _headers(token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def _extract_errors(payload: dict) -> list[str]:
    errs = payload.get("errors") or []
    out: list[str] = []
    for e in errs:
        if isinstance(e, dict):
            msg = e.get("message") or ""
            code = e.get("code") or ""
            out.append(f"{code}: {msg}".strip(": "))
        else:
            out.append(str(e))
    return out


async def cf_call(
    method: str,
    token: str,
    url: str,
    *,
    json: dict | None = None,
    timeout: float = 30.0,
) -> CfResult:
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.request(method, url, headers=_headers(token), json=json)
    except httpx.HTTPError as e:
        return CfResult(False, f"Cloudflare API недоступен: {e}")
    try:
        payload = resp.json()
    except ValueError:
        return CfResult(False, f"Cloudflare API: HTTP {resp.status_code}, не-JSON ответ")
    errors = _extract_errors(payload)
    if not payload.get("success"):
        msg = "; ".join(errors) if errors else f"HTTP {resp.status_code}"
        return CfResult(False, msg or "Cloudflare API error", errors=errors)
    return CfResult(True, "OK", data=payload.get("result"))


async def list_zones(token: str, name: str | None = None) -> CfResult:
    url = f"{CF_API}/zones?per_page=50"
    if name:
        url += f"&name={name}"
    return await cf_call("GET", token, url)


async def get_zone(token: str, zone_name: str) -> CfResult:
    name = zone_name.strip().lower().rstrip(".")
    res = await list_zones(token, name=name)
    if not res.ok:
        return res
    zones = res.data or []
    for z in zones:
        if (z.get("name") or "").lower().rstrip(".") == name:
            return CfResult(True, "OK", data=z)
    return CfResult(
        False,
        f"Зона «{name}» не найдена в аккаунте Cloudflare. Проверьте, что домен добавлен (Add a site).",
    )


async def zone_status(token: str, zone_id: str) -> CfResult:
    return await cf_call("GET", token, f"{CF_API}/zones/{zone_id}")


async def list_dns_records(
    token: str, zone_id: str, *, type_: str = "A", name: str | None = None
) -> CfResult:
    url = f"{CF_API}/zones/{zone_id}/dns_records?type={type_}&per_page=100"
    if name:
        url += f"&name={name}"
    return await cf_call("GET", token, url)


async def ensure_dns_record(
    token: str, zone_id: str, name: str, content: str, *, proxied: bool = True
) -> CfResult:
    fqdn = name.strip().lower().rstrip(".")
    res = await list_dns_records(token, zone_id, type_="A", name=fqdn)
    if not res.ok:
        return res
    records = res.data or []
    for r in records:
        if (r.get("name") or "").lower().rstrip(".") == fqdn:
            if (r.get("content") or "") != content or bool(r.get("proxied")) != proxied:
                upd = await cf_call(
                    "PATCH",
                    token,
                    f"{CF_API}/zones/{zone_id}/dns_records/{r['id']}",
                    json={"content": content, "proxied": proxied, "type": "A", "name": fqdn},
                )
                if not upd.ok:
                    return upd
            return CfResult(True, f"DNS A: {fqdn} → {content} (proxied={proxied})")
    create = await cf_call(
        "POST",
        token,
        f"{CF_API}/zones/{zone_id}/dns_records",
        json={"type": "A", "name": fqdn, "content": content, "proxied": proxied, "ttl": 1},
    )
    if not create.ok:
        return create
    return CfResult(True, f"DNS A создана: {fqdn} → {content} (proxied={proxied})")


async def get_ssl_mode(token: str, zone_id: str) -> CfResult:
    return await cf_call("GET", token, f"{CF_API}/zones/{zone_id}/settings/ssl")


async def set_ssl_mode(token: str, zone_id: str, mode: str) -> CfResult:
    mode = mode.strip().lower()
    if mode not in ("off", "flexible", "full", "strict", "full(strict)"):
        return CfResult(False, f"Неверный SSL-режим: {mode}")
    api_value = "strict" if mode in ("strict", "full(strict)") else mode
    return await cf_call(
        "PATCH", token, f"{CF_API}/zones/{zone_id}/settings/ssl", json={"value": api_value}
    )


async def _origin_ruleset_id(token: str, zone_id: str) -> CfResult:
    return await cf_call(
        "GET",
        token,
        f"{CF_API}/zones/{zone_id}/rulesets/phases/http_request_origin/entrypoint",
    )


async def ensure_origin_rule(token: str, zone_id: str, hostname: str, port: int) -> CfResult:
    host = hostname.strip().lower().rstrip(".")
    ep = await _origin_ruleset_id(token, zone_id)
    if not ep.ok:
        return CfResult(False, f"Не удалось получить Origin Rules entrypoint: {ep.message}")
    ruleset = ep.data or {}
    ruleset_id = ruleset.get("id")
    if not ruleset_id:
        return CfResult(False, "Cloudflare не вернул id ruleset для Origin Rules")
    full = await cf_call("GET", token, f"{CF_API}/zones/{zone_id}/rulesets/{ruleset_id}")
    if not full.ok:
        return full
    existing = (full.data or {}).get("rules") or []
    expr = f'(http.host eq "{host}")'
    new_rule = {
        "action": "route",
        "expression": expr,
        "description": f"vless-cf: origin port {port}",
        "action_parameters": {"origin": {"port": port}},
    }
    rules = [r for r in existing if (r.get("expression") or "") != expr]
    rules.append(new_rule)
    upd = await cf_call(
        "PUT",
        token,
        f"{CF_API}/zones/{zone_id}/rulesets/{ruleset_id}",
        json={"rules": rules},
    )
    if not upd.ok:
        return upd
    return CfResult(True, f"Origin Rule: {host} → порт {port}")


async def check_origin(hostname: str, path: str = "/") -> CfResult:
    """Проверка, что Cloudflare достучался до origin (без токена, обычный HTTPS)."""
    host = hostname.strip().rstrip("/")
    p = path if path.startswith("/") else f"/{path}"
    url = f"https://{host}{p}"
    try:
        async with httpx.AsyncClient(timeout=20.0, follow_redirects=False) as client:
            resp = await client.get(url, headers={"User-Agent": "vless-manager/1.0"})
        status = resp.status_code
        if status in (521, 522, 523, 524):
            return CfResult(False, f"Origin недоступен для Cloudflare (HTTP {status})")
        # 400 = xray ответил (нет WS-заголовков), 404/502/503 = достучались, но не наш путь
        return CfResult(
            True,
            f"Cloudflare достучался до origin (HTTP {status})",
            data={"status": status},
        )
    except httpx.HTTPError as e:
        return CfResult(False, f"Не удалось подключиться к {host}: {e}")


def normalize_hostname(value: str, zone: str) -> str:
    """Приводит к полному hostname: vpn → vpn.<zone>, а полный оставляет как есть."""
    v = (value or "").strip().lower().rstrip(".")
    if not v:
        return ""
    if "." in v:
        return v
    z = (zone or "").strip().lower().rstrip(".")
    return f"{v}.{z}" if z else v


def apex_of(hostname: str) -> str:
    """Грубое определение apex-домена (для подсказки зоны)."""
    h = (hostname or "").strip().lower().rstrip(".")
    parts = h.split(".")
    if len(parts) <= 2:
        return h
    return ".".join(parts[-2:])


def is_valid_token_shape(token: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_\-]{30,64}", token or ""))
