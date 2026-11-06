from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

import httpx

from app.config import QR_DIR, URL_DIR, VLESS_MANAGER_SH


def _mgr_path() -> Path:
    mgr = VLESS_MANAGER_SH
    if not mgr.is_file():
        mgr = Path(__file__).resolve().parents[3] / "vless_manager.sh"
    return mgr


@dataclass
class ProvisionResult:
    ok: bool
    message: str
    hysteria_url: str | None = None
    wifi_vless_url: str | None = None
    mobile_vless_url: str | None = None
    cf_vless_url: str | None = None
    wifi_port: int | None = None
    uuid: str | None = None
    extra: dict = field(default_factory=dict)


def _read_url_file(name: str, suffix: str = "") -> str | None:
    path = URL_DIR / f"{name}{suffix}.txt"
    if path.is_file():
        return path.read_text().strip()
    return None


def _extract_uuid_from_hysteria(url: str | None) -> str | None:
    # hysteria2://user:pass@host:port/...  -> username
    if not url:
        return None
    m = re.search(r"hysteria2://([^:@/]+)(?::[^@/]+)?@", url)
    return m.group(1) if m else None


def _extract_uuid_from_vless(url: str | None) -> str | None:
    if not url:
        return None
    m = re.search(r"vless://([^@]+)@", url)
    return m.group(1) if m else None


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


def validate_username(username: str) -> str | None:
    if not re.match(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", username):
        return "Недопустимое имя: латиница, цифры, точка, дефис, подчёркивание (до 63)"
    return None


def _run_cli(*args: str, timeout: int = 300) -> ProvisionResult | None:
    mgr = _mgr_path()
    if not mgr.is_file():
        return ProvisionResult(False, f"Не найден vless_manager.sh ({mgr})")
    try:
        r = subprocess.run(
            ["/bin/bash", str(mgr), "cli", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**__import__("os").environ, "VLESS_CLI": "1"},
        )
    except subprocess.TimeoutExpired:
        return ProvisionResult(False, "Таймаут выполнения команды на ноде")
    out = r.stdout + r.stderr
    if r.returncode != 0 or "уже существует" in out:
        if "уже существует" in out:
            return None
        return ProvisionResult(False, out[:2000] or f"cli {' '.join(args)} failed")
    return None


def provision_local(username: str) -> ProvisionResult:
    """Создать Hysteria2 (телефон) + PC VLESS TCP+TLS (NekoRay) на ноде."""
    if err := validate_username(username):
        return ProvisionResult(False, err)

    hy2 = _read_url_file(username)
    if not hy2:
        err = _run_cli("create-hy2", username)
        if isinstance(err, ProvisionResult):
            return err
        hy2 = _read_url_file(username)
        if not hy2:
            return ProvisionResult(False, "Hysteria2: нет URL на ноде")

    pc_url = _read_url_file(username, "-pc")
    if not pc_url:
        err = _run_cli("create-pc", username)
        if isinstance(err, ProvisionResult):
            return err
        pc_url = _read_url_file(username, "-pc")

    return ProvisionResult(
        ok=True,
        message="OK",
        hysteria_url=hy2,
        wifi_vless_url=pc_url,
        wifi_port=_extract_port_from_vless(pc_url),
        uuid=_extract_uuid_from_vless(pc_url) or _extract_uuid_from_hysteria(hy2),
    )


def provision_pc_local(username: str) -> ProvisionResult:
    """Создать только PC VLESS TCP+TLS, не трогая Hysteria2."""
    if err := validate_username(username):
        return ProvisionResult(False, err)

    pc_url = _read_url_file(username, "-pc")
    if pc_url:
        return ProvisionResult(
            ok=True,
            message="Синхронизировано с конфигом на ноде",
            wifi_vless_url=pc_url,
            wifi_port=_extract_port_from_vless(pc_url),
            uuid=_extract_uuid_from_vless(pc_url),
        )

    err = _run_cli("create-pc", username)
    if isinstance(err, ProvisionResult):
        return err
    pc_url = _read_url_file(username, "-pc")
    if not pc_url:
        return ProvisionResult(False, "PC VLESS: нет URL на ноде")
    return ProvisionResult(
        ok=True,
        message="OK",
        wifi_vless_url=pc_url,
        wifi_port=_extract_port_from_vless(pc_url),
        uuid=_extract_uuid_from_vless(pc_url),
    )


# Обратная совместимость для старых вызовов и API-агентов
provision_hy2_local = provision_local


def _delete_cli(username: str, cmd: str) -> ProvisionResult | None:
    mgr = _mgr_path()
    if not mgr.is_file():
        return ProvisionResult(False, f"Не найден vless_manager.sh ({mgr})")
    try:
        r = subprocess.run(
            ["/bin/bash", str(mgr), "cli", cmd, username],
            capture_output=True,
            text=True,
            timeout=120,
            env={**__import__("os").environ, "VLESS_CLI": "1"},
        )
    except subprocess.TimeoutExpired:
        return ProvisionResult(False, "Таймаут удаления на ноде")
    if r.returncode != 0:
        return ProvisionResult(False, (r.stderr or r.stdout or "delete failed")[:2000])
    return None


def delete_local(username: str) -> ProvisionResult:
    """Удалить и Hysteria2, и PC VLESS для пользователя на ноде."""
    err = _delete_cli(username, "delete-hy2")
    if err:
        return err
    err = _delete_cli(username, "delete-pc")
    if err:
        return err
    return ProvisionResult(True, "Конфиги Hysteria2 и PC VLESS удалены")


def delete_hy2_local(username: str) -> ProvisionResult:
    return delete_local(username)


def build_client_catalog_for_master() -> list[dict]:
    """Каталог Hysteria2-клиентов на ноде — для импорта на master."""
    catalog: list[dict] = []
    creds_dir = Path("/etc/vless-manager/hysteria-clients")
    if not creds_dir.is_dir():
        return catalog
    for cred in sorted(creds_dir.glob("*.cred")):
        username = cred.stem
        if not username or username.startswith("_"):
            continue
        hy2 = _read_url_file(username)
        if not hy2:
            continue
        pc_url = _read_url_file(username, "-pc")
        has_wifi = bool(pc_url)
        catalog.append(
            {
                "username": username,
                "has_hy2": True,
                "has_wifi": has_wifi,
                "has_mobile": False,
                "hysteria_url": hy2,
                "wifi_vless_url": pc_url,
                "mobile_vless_url": None,
                "cf_vless_url": None,
                "wifi_port": _extract_port_from_vless(pc_url),
                "uuid": _extract_uuid_from_vless(pc_url)
                or _extract_uuid_from_hysteria(hy2),
            }
        )
    return catalog


async def check_username_remote(
    api_base: str, token: str, username: str
) -> ProvisionResult:
    url = api_base.rstrip("/") + "/api/v1/username-available"
    headers = {"Authorization": f"Bearer {token}"}
    params = {"username": username, "wifi": "true", "mobile": "false"}
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, headers=headers, params=params)
            data = resp.json()
            if resp.status_code >= 400 or not data.get("available"):
                return ProvisionResult(False, data.get("reason", resp.text)[:500])
            return ProvisionResult(True, "OK")
    except Exception as e:
        return ProvisionResult(False, str(e))


async def provision_remote(
    api_base: str, token: str, username: str
) -> ProvisionResult:
    name_pre = await check_username_remote(api_base, token, username)
    if not name_pre.ok:
        return name_pre
    url = api_base.rstrip("/") + "/api/v1/provision"
    headers = {"Authorization": f"Bearer {token}"}
    payload = {"username": username, "wifi": True, "mobile": False}
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(url, json=payload, headers=headers)
            data = resp.json()
            if resp.status_code >= 400:
                return ProvisionResult(False, data.get("detail", resp.text)[:2000])
            return ProvisionResult(
                ok=True,
                message="OK",
                hysteria_url=data.get("hysteria_url"),
                wifi_vless_url=data.get("wifi_vless_url"),
                wifi_port=data.get("wifi_port"),
                uuid=data.get("uuid"),
            )
    except Exception as e:
        return ProvisionResult(False, str(e))


async def delete_remote_client(
    api_base: str, token: str, username: str
) -> ProvisionResult:
    url = api_base.rstrip("/") + "/api/v1/delete"
    headers = {"Authorization": f"Bearer {token}"}
    payload = {"username": username, "wifi": True, "mobile": False}
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(url, json=payload, headers=headers)
            if resp.status_code >= 400:
                detail = (
                    resp.json().get("detail", resp.text)
                    if resp.headers.get("content-type", "").startswith("application/json")
                    else resp.text
                )
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
    hysteria_url: str | None,
    wifi_vless_url: str | None = None,
) -> None:
    if hysteria_url:
        write_qr_png(hysteria_url, QR_DIR / f"{username}.png")
    if wifi_vless_url:
        write_qr_png(wifi_vless_url, QR_DIR / f"{username}-pc.png")


def qr_png_path(username: str, kind: str = "hy2") -> Path | None:
    if kind == "pc":
        p = QR_DIR / f"{username}-pc.png"
    else:
        p = QR_DIR / f"{username}.png"
    return p if p.is_file() else None
