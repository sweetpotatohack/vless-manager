from __future__ import annotations

from pathlib import Path

CLIENT_DIR = Path("/etc/vless-manager/clients")
MOBILE_DIR = Path("/etc/vless-manager/mobile-reality")


def username_reserved_on_disk(username: str) -> tuple[bool, str]:
    """Имя занято, если есть Wi‑Fi json или любой mobile uuid для этой базы."""
    if (CLIENT_DIR / f"{username}.json").is_file():
        return True, f"Конфиг Wi‑Fi «{username}» уже существует на сервере"
    if (MOBILE_DIR / f"{username}.uuid").is_file():
        return True, f"Конфиг LTE «{username}» уже существует на сервере"
    if (MOBILE_DIR / f"{username}-mob.uuid").is_file():
        return True, f"Конфиг LTE «{username}-mob» уже существует на сервере"
    return False, ""


def validate_new_username(username: str, *, wifi: bool, mobile: bool) -> tuple[bool, str]:
    if not username:
        return False, "Пустое имя"
    taken, msg = username_reserved_on_disk(username)
    if taken:
        return False, msg
    if wifi and (CLIENT_DIR / f"{username}.json").is_file():
        return False, f"Wi‑Fi «{username}» уже есть"
    mob = f"{username}-mob" if wifi and mobile else (username if mobile else "")
    if mobile and mob and (MOBILE_DIR / f"{mob}.uuid").is_file():
        return False, f"LTE «{mob}» уже есть"
    return True, "OK"
