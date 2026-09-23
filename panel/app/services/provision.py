from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

import httpx

from app.config import QR_DIR, URL_DIR, VLESS_MANAGER_SH
from app.services.name_check import validate_new_username
from app.services.ports import ensure_can_provision


def reconcile_wifi_servers() -> None:
    """Поднять упавшие inbound после перезапуска панели (старые процессы были в её cgroup)."""
    try:
        subprocess.run(
            ["/usr/local/bin/vless-servers", "reconcile"],
            capture_output=True,
            text=True,
            timeout=600,
        )
    except (subprocess.TimeoutExpired, OSError):
        pass


def ensure_wifi_server_running(username: str) -> tuple[bool, str]:
    try:
        r = subprocess.run(
            ["/usr/local/bin/vless-servers", "start", username],
            capture_output=True,
            text=True,
            timeout=120,
        )
        out = (r.stdout + r.stderr).strip()
        if r.returncode != 0:
            return False, out[:500] or "vless-servers start failed"
        return True, "OK"
    except (subprocess.TimeoutExpired, OSError) as e:
        return False, str(e)


@dataclass
class ProvisionResult:
    ok: bool
    message: str
    wifi_vless_url: str | None = None
    mobile_vless_url: str | None = None
    hysteria_url: str | None = None
    wifi_port: int | None = None
    uuid: str | None = None


def _read_url_file(name: str, suffix: str = "") -> str | None:
    path = URL_DIR / f"{name}{suffix}.txt"
    if path.is_file():
        return path.read_text().strip()
    return None


def _extract_port_from_vless(url: str | None) -> int | None:
    if not url:
        return None
    m = re.search(r"@[^:]+:(\d+)\?", url)
    if m:
        return int(m.group(1))
    m = re.search(r"@[^:]+:(\d+)#", url)
    if m:
        return int(m.group(1))
    return None


def _extract_uuid_from_vless(url: str | None) -> str | None:
    if not url:
        return None
    m = re.search(r"vless://([^@]+)@", url)
    return m.group(1) if m else None


def provision_local(username: str, *, wifi: bool, mobile: bool) -> ProvisionResult:
    if not re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", username):
        return ProvisionResult(False, "Недопустимое имя пользователя")

    ok_name, name_msg = validate_new_username(username, wifi=wifi, mobile=mobile)
    if not ok_name:
        return ProvisionResult(False, name_msg)

    mgr = VLESS_MANAGER_SH
    if not mgr.is_file():
        mgr = Path(__file__).resolve().parents[3] / "vless_manager.sh"
    if not mgr.is_file():
        return ProvisionResult(False, f"Не найден vless_manager.sh ({mgr})")

    ok, msg = ensure_can_provision(wifi=wifi, mobile=mobile)
    if not ok:
        return ProvisionResult(False, msg)

    wifi_url = mobile_url = hy2_url = None

    if wifi:
        r = subprocess.run(
            ["/bin/bash", str(mgr), "cli", "create-wifi", username],
            capture_output=True,
            text=True,
            timeout=300,
            env={**__import__("os").environ, "VLESS_CLI": "1"},
        )
        out = r.stdout + r.stderr
        if r.returncode != 0 or "уже существует" in out:
            if "уже существует" in out:
                return ProvisionResult(False, f"Конфиг «{username}» уже существует")
            if "Выбери опцию" in out or "ГЛАВНОЕ МЕНЮ" in out:
                return ProvisionResult(
                    False,
                    "На сервере старый vless_manager.sh без cli. Запустите: "
                    "cp /root/vless-manager-pro/vless_manager.sh /opt/vless-manager/ "
                    "и перезапустите panel.",
                )
            return ProvisionResult(False, out[:2000] or "create-wifi failed")
        ok_run, run_msg = ensure_wifi_server_running(username)
        if not ok_run:
            return ProvisionResult(
                False,
                f"Конфиг создан, но inbound не слушает порт: {run_msg}",
            )
        wifi_url = _read_url_file(username)

    if mobile:
        mob_name = f"{username}-mob" if wifi else username
        r = subprocess.run(
            ["/bin/bash", str(mgr), "cli", "create-mobile", mob_name],
            capture_output=True,
            text=True,
            timeout=300,
            env={**__import__("os").environ, "VLESS_CLI": "1"},
        )
        out = r.stdout + r.stderr
        if r.returncode != 0 or "уже существует" in out:
            if "уже существует" in out:
                return ProvisionResult(False, f"Конфиг «{mob_name}» уже существует")
            if "Выбери опцию" in out or "ГЛАВНОЕ МЕНЮ" in out:
                return ProvisionResult(
                    False,
                    "vless_manager.sh без режима cli — обновите /opt/vless-manager/vless_manager.sh",
                )
            return ProvisionResult(False, out[:2000] or "create-mobile failed")
        mobile_url = _read_url_file(mob_name)
        hy2_url = _read_url_file(mob_name, "-hy2")

    uuid = _extract_uuid_from_vless(mobile_url or wifi_url)
    port = _extract_port_from_vless(wifi_url)

    return ProvisionResult(
        ok=True,
        message="OK",
        wifi_vless_url=wifi_url,
        mobile_vless_url=mobile_url,
        hysteria_url=hy2_url,
        wifi_port=port,
        uuid=uuid,
    )


async def fetch_remote_port_status(api_base: str, token: str) -> tuple[bool, dict | str]:
    url = api_base.rstrip("/") + "/api/v1/ports"
    headers = {"Authorization": f"Bearer {token}"}
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code >= 400:
                return False, resp.text
            return True, resp.json()
    except Exception as e:
        return False, str(e)


async def check_username_remote(
    api_base: str, token: str, username: str, *, wifi: bool, mobile: bool
) -> ProvisionResult:
    url = api_base.rstrip("/") + "/api/v1/username-available"
    headers = {"Authorization": f"Bearer {token}"}
    params = {"username": username, "wifi": str(wifi).lower(), "mobile": str(mobile).lower()}
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, headers=headers, params=params)
            data = resp.json()
            if resp.status_code >= 400 or not data.get("available"):
                return ProvisionResult(False, data.get("reason", resp.text)[:500])
            return ProvisionResult(True, "OK")
    except Exception as e:
        return ProvisionResult(False, str(e))


async def ensure_remote_can_provision(
    api_base: str, token: str, *, wifi: bool, mobile: bool
) -> ProvisionResult:
    ok, data = await fetch_remote_port_status(api_base, token)
    if not ok:
        return ProvisionResult(False, f"Нода недоступна или порты не проверены: {data}")
    if wifi and not data.get("wifi_port_available"):
        assigned = data.get("assigned_vless") or []
        return ProvisionResult(
            False,
            f"На удалённой ноде нет свободного порта Wi‑Fi. Занято: {assigned[:20]}",
        )
    return ProvisionResult(True, "OK")


async def provision_remote(
    api_base: str,
    token: str,
    username: str,
    *,
    wifi: bool,
    mobile: bool,
) -> ProvisionResult:
    name_pre = await check_username_remote(
        api_base, token, username, wifi=wifi, mobile=mobile
    )
    if not name_pre.ok:
        return name_pre
    pre = await ensure_remote_can_provision(api_base, token, wifi=wifi, mobile=mobile)
    if not pre.ok:
        return pre
    url = api_base.rstrip("/") + "/api/v1/provision"
    headers = {"Authorization": f"Bearer {token}"}
    payload = {"username": username, "wifi": wifi, "mobile": mobile}
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(url, json=payload, headers=headers)
            data = resp.json()
            if resp.status_code >= 400:
                return ProvisionResult(False, data.get("detail", resp.text))
            return ProvisionResult(
                ok=True,
                message="OK",
                wifi_vless_url=data.get("wifi_vless_url"),
                mobile_vless_url=data.get("mobile_vless_url"),
                hysteria_url=data.get("hysteria_url"),
                wifi_port=data.get("wifi_port"),
                uuid=data.get("uuid"),
            )
    except Exception as e:
        return ProvisionResult(False, str(e))


def delete_local_client(username: str, *, wifi: bool, mobile: bool) -> ProvisionResult:
    mgr = VLESS_MANAGER_SH
    if not mgr.is_file():
        mgr = Path(__file__).resolve().parents[3] / "vless_manager.sh"
    if not mgr.is_file():
        return ProvisionResult(False, f"Не найден vless_manager.sh ({mgr})")
    w = "1" if wifi else "0"
    m = "1" if mobile else "0"
    r = subprocess.run(
        ["/bin/bash", str(mgr), "cli", "delete-client", username, w, m],
        capture_output=True,
        text=True,
        timeout=120,
        env={**__import__("os").environ, "VLESS_CLI": "1"},
    )
    if r.returncode != 0:
        return ProvisionResult(False, (r.stderr or r.stdout or "delete failed")[:2000])
    return ProvisionResult(True, "Конфиг удалён")


async def delete_remote_client(
    api_base: str, token: str, username: str, *, wifi: bool, mobile: bool
) -> ProvisionResult:
    url = api_base.rstrip("/") + "/api/v1/delete"
    headers = {"Authorization": f"Bearer {token}"}
    payload = {"username": username, "wifi": wifi, "mobile": mobile}
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(url, json=payload, headers=headers)
            if resp.status_code >= 400:
                detail = resp.json().get("detail", resp.text) if resp.headers.get(
                    "content-type", ""
                ).startswith("application/json") else resp.text
                return ProvisionResult(False, str(detail)[:2000])
            return ProvisionResult(True, "Конфиг удалён на удалённой ноде")
    except Exception as e:
        return ProvisionResult(False, str(e))


def qr_png_path(username: str, kind: str = "wifi") -> Path | None:
    base = username if kind == "wifi" else f"{username}-mob"
    if kind == "mobile" and not (QR_DIR / f"{base}.png").is_file():
        base = username
    p = QR_DIR / f"{base}.png"
    return p if p.is_file() else None
