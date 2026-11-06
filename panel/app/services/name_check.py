from __future__ import annotations

from pathlib import Path

HYSTERIA_DIR = Path("/etc/vless-manager/hysteria-clients")
CLIENT_DIR = Path("/etc/vless-manager/clients")


def username_reserved_on_disk(username: str) -> tuple[bool, str]:
    if (HYSTERIA_DIR / f"{username}.cred").is_file():
        return True, f"Конфиг Hysteria2 «{username}» уже существует на сервере"
    return False, ""


def validate_new_username(username: str, *, wifi: bool = False, mobile: bool = False) -> tuple[bool, str]:
    if not username:
        return False, "Пустое имя"
    taken, msg = username_reserved_on_disk(username)
    if taken:
        return False, msg
    if wifi and (CLIENT_DIR / f"{username}-pc.json").is_file():
        return False, f"PC VLESS «{username}» уже есть"
    return True, "OK"
