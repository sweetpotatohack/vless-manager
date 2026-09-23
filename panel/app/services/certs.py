from __future__ import annotations

import datetime as dt
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class CertInfo:
    name: str
    domains: list[str]
    expiry: dt.datetime | None
    days_left: int | None
    cert_path: str
    valid: bool
    source: str  # letsencrypt | hysteria_copy | other


def _parse_openssl_subject_cn(pem_path: Path) -> str | None:
    try:
        out = subprocess.run(
            ["openssl", "x509", "-noout", "-subject", "-in", str(pem_path)],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if out.returncode != 0:
            return None
        m = re.search(r"CN\s*=\s*([^,/]+)", out.stdout)
        return m.group(1).strip() if m else None
    except OSError:
        return None


def _parse_expiry_string(raw: str) -> dt.datetime | None:
    raw = raw.strip()
    if not raw:
        return None
    for fmt in (
        "%Y-%m-%d %H:%M:%S%z",
        "%Y-%m-%d %H:%M:%S",
    ):
        try:
            s = re.sub(r"(\+\d{2}):(\d{2})$", r"\1\2", raw)
            exp = dt.datetime.strptime(s, fmt)
            return exp.replace(tzinfo=None) if exp.tzinfo else exp
        except ValueError:
            continue
    return None


def _parse_openssl_end(pem_path: Path) -> dt.datetime | None:
    try:
        out = subprocess.run(
            ["openssl", "x509", "-enddate", "-noout", "-in", str(pem_path)],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if out.returncode != 0:
            return None
        m = re.search(r"notAfter=(.+)", out.stdout.strip())
        if not m:
            return None
        # e.g. Sep 23 12:00:00 2026 GMT
        return dt.datetime.strptime(m.group(1).strip(), "%b %d %H:%M:%S %Y %Z")
    except (OSError, ValueError):
        return None


def _days_left(expiry: dt.datetime | None) -> int | None:
    if not expiry:
        return None
    now = dt.datetime.utcnow()
    return (expiry - now).days


def certbot_certificates() -> list[CertInfo]:
    items: list[CertInfo] = []
    try:
        out = subprocess.run(
            ["certbot", "certificates"],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        text = out.stdout + out.stderr
    except OSError:
        return items

    block_re = re.compile(
        r"Certificate Name:\s*(.+?)\r?\n"
        r"[\s\S]*?"
        r"^\s*Domains:\s*(.+?)\r?\n"
        r"[\s\S]*?"
        r"^\s*Expiry Date:\s*([^\(\n]+)"
        r"[\s\S]*?"
        r"^\s*Certificate Path:\s*(.+?)\r?\n",
        re.MULTILINE,
    )
    for m in block_re.finditer(text):
        name = m.group(1).strip()
        domains = m.group(2).strip().split()
        expiry = _parse_expiry_string(m.group(3))
        cert_path = m.group(4).strip()
        if expiry is None:
            expiry = _parse_openssl_end(Path(cert_path))
        dl = _days_left(expiry)
        items.append(
            CertInfo(
                name=name,
                domains=domains,
                expiry=expiry,
                days_left=dl,
                cert_path=cert_path,
                valid=dl is not None and dl >= 0,
                source="letsencrypt",
            )
        )
    return items


def scan_live_certs() -> list[CertInfo]:
    items: list[CertInfo] = []
    live = Path("/etc/letsencrypt/live")
    if not live.is_dir():
        return items
    for d in sorted(live.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        fullchain = d / "fullchain.pem"
        if not fullchain.is_file():
            continue
        expiry = _parse_openssl_end(fullchain)
        dl = _days_left(expiry)
        items.append(
            CertInfo(
                name=d.name,
                domains=[d.name],
                expiry=expiry,
                days_left=dl,
                cert_path=str(fullchain),
                valid=dl is not None and dl >= 0,
                source="letsencrypt",
            )
        )
    return items


def hysteria_cert_status() -> CertInfo | None:
    p = Path("/etc/hysteria/certs/fullchain.pem")
    if not p.is_file():
        return None
    expiry = _parse_openssl_end(p)
    dl = _days_left(expiry)
    cn = _parse_openssl_subject_cn(p)
    label = f"Hysteria2 ({cn})" if cn else "Hysteria2 copy"
    return CertInfo(
        name=label,
        domains=[cn or "/etc/hysteria/certs"],
        expiry=expiry,
        days_left=dl,
        cert_path=str(p),
        valid=dl is not None and dl >= 0,
        source="hysteria_copy",
    )


def active_vpn_tls_cert() -> CertInfo | None:
    """Сертификат из tls.env (VLESS Wi‑Fi / текущий PUBLIC_HOST)."""
    tls_env = Path("/etc/vless-manager/tls.env")
    if not tls_env.is_file():
        return None
    data: dict[str, str] = {}
    for line in tls_env.read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip().strip('"')
    fc = data.get("LE_FULLCHAIN", "")
    host = data.get("PUBLIC_HOST", "")
    if not fc or not Path(fc).is_file():
        return None
    expiry = _parse_openssl_end(Path(fc))
    dl = _days_left(expiry)
    cn = _parse_openssl_subject_cn(Path(fc)) or host
    domains = [host] if host else ([cn] if cn else [])
    return CertInfo(
        name=host or cn or "vpn-active",
        domains=domains,
        expiry=expiry,
        days_left=dl,
        cert_path=fc,
        valid=dl is not None and dl >= 0,
        source="active_tls",
    )


def certbot_timer_status() -> dict:
    info = {"active": None, "next": None, "raw": ""}
    try:
        out = subprocess.run(
            ["systemctl", "is-active", "certbot.timer"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        info["active"] = out.stdout.strip()
    except OSError:
        pass
    try:
        out = subprocess.run(
            ["systemctl", "list-timers", "certbot.timer", "--no-pager"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        info["raw"] = out.stdout.strip()
        for line in out.stdout.splitlines():
            if "certbot.timer" in line:
                parts = line.split()
                if len(parts) >= 2:
                    info["next"] = " ".join(parts[0:2])
                break
    except OSError:
        pass
    return info


def _merge_cert_lists(*groups: list[CertInfo]) -> list[CertInfo]:
    by_name: dict[str, CertInfo] = {}
    for group in groups:
        for c in group:
            by_name[c.name] = c
    return sorted(by_name.values(), key=lambda x: x.name.lower())


def all_cert_status() -> dict:
    from_bot = certbot_certificates()
    from_live = scan_live_certs()
    certs = _merge_cert_lists(from_bot, from_live)
    hy = hysteria_cert_status()
    active = active_vpn_tls_cert()
    return {
        "certificates": certs,
        "hysteria": hy,
        "active_vpn": active,
        "timer": certbot_timer_status(),
        "checked_at": dt.datetime.utcnow(),
    }
