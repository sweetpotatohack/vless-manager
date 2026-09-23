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

    blocks = re.split(r"\n(?=Certificate Name:)", text)
    for block in blocks:
        if "Certificate Name:" not in block:
            continue
        name_m = re.search(r"Certificate Name:\s*(.+)", block)
        domains_m = re.search(r"Domains:\s*(.+)", block)
        path_m = re.search(r"Certificate Path:\s*(.+)", block)
        expiry_m = re.search(r"Expiry Date:\s*([^\(]+)", block)
        if not name_m or not path_m:
            continue
        name = name_m.group(1).strip()
        domains = (domains_m.group(1).strip().split() if domains_m else [])
        cert_path = path_m.group(1).strip()
        expiry = None
        if expiry_m:
            try:
                expiry = dt.datetime.strptime(
                    expiry_m.group(1).strip(), "%Y-%m-%d %H:%M:%S%z"
                ).replace(tzinfo=None)
            except ValueError:
                expiry = _parse_openssl_end(Path(cert_path))
        else:
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
    return CertInfo(
        name="hysteria-copy",
        domains=["/etc/hysteria/certs"],
        expiry=expiry,
        days_left=dl,
        cert_path=str(p),
        valid=dl is not None and dl >= 0,
        source="hysteria_copy",
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


def all_cert_status() -> dict:
    certs = certbot_certificates()
    if not certs:
        certs = scan_live_certs()
    hy = hysteria_cert_status()
    return {
        "certificates": certs,
        "hysteria": hy,
        "timer": certbot_timer_status(),
        "checked_at": dt.datetime.utcnow(),
    }
