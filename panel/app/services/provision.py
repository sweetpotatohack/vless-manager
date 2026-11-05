from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

import httpx

from app.config import QR_DIR, URL_DIR, VLESS_MANAGER_SH
from app.services.name_check import CLIENT_DIR, MOBILE_DIR
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
    cf_vless_url: str | None = None
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


def _mobile_profile_name(username: str, *, wifi: bool, mobile: bool) -> str:
    if mobile and wifi:
        return f"{username}-mob"
    if mobile:
        return username
    return f"{username}-mob"


def _mobile_on_disk(username: str, mob_name: str) -> bool:
    return (MOBILE_DIR / f"{mob_name}.uuid").is_file() or (
        MOBILE_DIR / f"{username}.uuid"
    ).is_file()


def _resolve_mob_name(username: str, mob_name: str) -> str:
    if (MOBILE_DIR / f"{mob_name}.uuid").is_file():
        return mob_name
    if (MOBILE_DIR / f"{username}.uuid").is_file():
        return username
    return mob_name


def _cli_create_wifi(mgr: Path, username: str) -> ProvisionResult | None:
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
            return None
        if "Выбери опцию" in out or "ГЛАВНОЕ МЕНЮ" in out:
            return ProvisionResult(
                False,
                "На сервере старый vless_manager.sh без cli. Обновите /opt/vless-manager/vless_manager.sh",
            )
        return ProvisionResult(False, out[:2000] or "create-wifi failed")
    return None


def _cli_create_cf(mgr: Path, username: str) -> ProvisionResult | None:
    r = subprocess.run(
        ["/bin/bash", str(mgr), "cli", "create-cf", username],
        capture_output=True,
        text=True,
        timeout=300,
        env={**__import__("os").environ, "VLESS_CLI": "1"},
    )
    out = r.stdout + r.stderr
    if r.returncode != 0 or "уже существует" in out:
        if "уже существует" in out:
            return None
        return ProvisionResult(False, out[:2000] or "create-cf failed")
    return None


def provision_cf_local(username: str) -> ProvisionResult:
    """Cloudflare WS профиль (master). Общий inbound xray-cf :8443."""
    if not re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", username):
        return ProvisionResult(False, "Недопустимое имя пользователя")
    mgr = VLESS_MANAGER_SH
    if not mgr.is_file():
        mgr = Path(__file__).resolve().parents[3] / "vless_manager.sh"
    if not mgr.is_file():
        return ProvisionResult(False, f"Не найден vless_manager.sh ({mgr})")
    cf_url = _read_url_file(username, "-cf")
    if cf_url:
        return ProvisionResult(
            ok=True,
            message="Синхронизировано с конфигом на ноде",
            cf_vless_url=cf_url,
            uuid=_extract_uuid_from_vless(cf_url),
        )
    err = _cli_create_cf(mgr, username)
    if isinstance(err, ProvisionResult):
        return err
    cf_url = _read_url_file(username, "-cf")
    if not cf_url:
        return ProvisionResult(False, "Cloudflare WS: нет URL на ноде")
    return ProvisionResult(
        ok=True, message="OK", cf_vless_url=cf_url, uuid=_extract_uuid_from_vless(cf_url)
    )


def delete_cf_local(username: str) -> ProvisionResult:
    mgr = VLESS_MANAGER_SH
    if not mgr.is_file():
        mgr = Path(__file__).resolve().parents[3] / "vless_manager.sh"
    if not mgr.is_file():
        return ProvisionResult(False, f"Не найден vless_manager.sh ({mgr})")
    r = subprocess.run(
        ["/bin/bash", str(mgr), "cli", "delete-cf", username],
        capture_output=True,
        text=True,
        timeout=120,
        env={**__import__("os").environ, "VLESS_CLI": "1"},
    )
    if r.returncode != 0:
        return ProvisionResult(False, (r.stderr or r.stdout or "delete-cf failed")[:2000])
    return ProvisionResult(True, "Cloudflare WS конфиг удалён")


def _cli_create_mobile(mgr: Path, mob_name: str) -> ProvisionResult | None:
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
            return None
        if "Выбери опцию" in out or "ГЛАВНОЕ МЕНЮ" in out:
            return ProvisionResult(
                False,
                "vless_manager.sh без режима cli — обновите /opt/vless-manager/vless_manager.sh",
            )
        return ProvisionResult(False, out[:2000] or "create-mobile failed")
    return None


def provision_local(username: str, *, wifi: bool, mobile: bool) -> ProvisionResult:
    if not re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", username):
        return ProvisionResult(False, "Недопустимое имя пользователя")
    if not wifi and not mobile:
        return ProvisionResult(False, "Выберите Wi‑Fi и/или LTE")

    mgr = VLESS_MANAGER_SH
    if not mgr.is_file():
        mgr = Path(__file__).resolve().parents[3] / "vless_manager.sh"
    if not mgr.is_file():
        return ProvisionResult(False, f"Не найден vless_manager.sh ({mgr})")

    ok, msg = ensure_can_provision(wifi=wifi, mobile=mobile)
    if not ok:
        return ProvisionResult(False, msg)

    synced = False
    wifi_url = mobile_url = hy2_url = None
    has_wifi = (CLIENT_DIR / f"{username}.json").is_file()
    mob_name = _mobile_profile_name(username, wifi=wifi, mobile=mobile)

    if wifi:
        if has_wifi:
            synced = True
            ok_run, run_msg = ensure_wifi_server_running(username)
            if not ok_run:
                return ProvisionResult(
                    False,
                    f"Wi‑Fi «{username}» на диске, но inbound не поднялся: {run_msg}",
                )
            wifi_url = _read_url_file(username)
        else:
            err = _cli_create_wifi(mgr, username)
            if isinstance(err, ProvisionResult):
                return err
            ok_run, run_msg = ensure_wifi_server_running(username)
            if not ok_run:
                return ProvisionResult(
                    False,
                    f"Конфиг создан, но inbound не слушает порт: {run_msg}",
                )
            wifi_url = _read_url_file(username)

    if mobile:
        if _mobile_on_disk(username, mob_name):
            synced = True
            actual_mob = _resolve_mob_name(username, mob_name)
            mobile_url = _read_url_file(actual_mob)
            hy2_url = _read_url_file(actual_mob, "-hy2")
        else:
            err = _cli_create_mobile(mgr, mob_name)
            if isinstance(err, ProvisionResult):
                return err
            mobile_url = _read_url_file(mob_name)
            hy2_url = _read_url_file(mob_name, "-hy2")
            if not mobile_url and mob_name != username:
                mobile_url = _read_url_file(username)
                hy2_url = _read_url_file(username, "-hy2")

    if wifi and not wifi_url:
        return ProvisionResult(False, f"Wi‑Fi «{username}»: нет URL на ноде")
    if mobile and not mobile_url and not hy2_url:
        return ProvisionResult(False, f"LTE «{mob_name}»: нет URL на ноде")
    if not wifi_url and not mobile_url and not hy2_url:
        return ProvisionResult(False, "Конфиг не создан")

    uuid = _extract_uuid_from_vless(mobile_url or wifi_url)
    port = _extract_port_from_vless(wifi_url)
    message = "Синхронизировано с конфигом на ноде" if synced else "OK"

    return ProvisionResult(
        ok=True,
        message=message,
        wifi_vless_url=wifi_url,
        mobile_vless_url=mobile_url,
        hysteria_url=hy2_url,
        wifi_port=port,
        uuid=uuid,
    )


def build_client_catalog_for_master() -> list[dict]:
    from app.services.local_clients import list_grouped_local_clients, load_local_client_urls

    catalog: list[dict] = []
    for row in list_grouped_local_clients():
        username = row["username"]
        urls = load_local_client_urls(username)
        wifi_url = urls.get("wifi_vless_url")
        mobile_url = urls.get("mobile_vless_url")
        hy2 = urls.get("hysteria_url")
        cf_url = urls.get("cf_vless_url")
        has_wifi = bool(row.get("wifi_port") or wifi_url)
        has_mobile = bool(row.get("mobile_port") or mobile_url or hy2)
        if not has_wifi and not has_mobile and not cf_url:
            continue
        catalog.append(
            {
                "username": username,
                "has_wifi": has_wifi,
                "has_mobile": has_mobile,
                "wifi_vless_url": wifi_url,
                "mobile_vless_url": mobile_url,
                "hysteria_url": hy2,
                "cf_vless_url": cf_url,
                "wifi_port": _extract_port_from_vless(wifi_url),
                "uuid": _extract_uuid_from_vless(mobile_url or wifi_url or cf_url),
            }
        )
    return catalog


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


def delete_local_client(
    username: str, *, wifi: bool, mobile: bool, cf: bool = False
) -> ProvisionResult:
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
    if cf:
        return delete_cf_local(username)
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


def write_qr_png(content: str, dest: Path) -> bool:
    if not content.strip():
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        r = subprocess.run(
            ["qrencode", "-s", "8", "-o", str(dest), content.strip()],
            capture_output=True,
            timeout=30,
        )
        if r.returncode == 0 and dest.is_file():
            return True
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        import qrcode

        img = qrcode.make(content.strip())
        img.save(dest)
        return dest.is_file()
    except Exception:
        return False


def ensure_qr_codes_for_user(
    username: str,
    *,
    wifi_vless_url: str | None,
    mobile_vless_url: str | None,
    hysteria_url: str | None,
    cf_vless_url: str | None = None,
    has_wifi: bool,
    has_mobile: bool,
) -> None:
    mob_name = f"{username}-mob" if has_wifi and has_mobile else username
    if has_wifi and wifi_vless_url:
        write_qr_png(wifi_vless_url, QR_DIR / f"{username}.png")
    if has_mobile and mobile_vless_url:
        write_qr_png(mobile_vless_url, QR_DIR / f"{mob_name}.png")
    if has_mobile and hysteria_url:
        write_qr_png(hysteria_url, QR_DIR / f"{mob_name}-hy2.png")
    if cf_vless_url:
        write_qr_png(cf_vless_url, QR_DIR / f"{username}-cf.png")


def qr_png_path(username: str, kind: str = "wifi") -> Path | None:
    if kind == "wifi":
        p = QR_DIR / f"{username}.png"
    elif kind == "hy2":
        p = QR_DIR / f"{username}-mob-hy2.png"
    elif kind == "cf":
        p = QR_DIR / f"{username}-cf.png"
    else:
        p = QR_DIR / f"{username}-mob.png"
        if kind == "mobile" and not p.is_file():
            p = QR_DIR / f"{username}.png"
    return p if p.is_file() else None
