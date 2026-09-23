from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

TLS_ENV = Path("/etc/vless-manager/tls.env")
HYSTERIA_CERT = Path("/etc/hysteria/certs")


@dataclass
class CertActionResult:
    ok: bool
    message: str


def _load_tls() -> dict[str, str]:
    data: dict[str, str] = {}
    if TLS_ENV.is_file():
        for line in TLS_ENV.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                data[k.strip()] = v.strip().strip('"')
    return data


def _write_tls_public_host(domain: str, fullchain: str, privkey: str) -> None:
    tls = _load_tls()
    tls["TLS_MODE"] = "letsencrypt"
    tls["PUBLIC_HOST"] = domain
    tls["LE_FULLCHAIN"] = fullchain
    tls["LE_PRIVKEY"] = privkey
    if "LE_EMAIL" not in tls:
        tls["LE_EMAIL"] = "admin@localhost"
    lines = [f"{k}={v}" for k, v in tls.items()]
    TLS_ENV.write_text("\n".join(lines) + "\n")
    TLS_ENV.chmod(0o600)


def sync_hysteria_from_le() -> CertActionResult:
    tls = _load_tls()
    fc = tls.get("LE_FULLCHAIN", "")
    pk = tls.get("LE_PRIVKEY", "")
    if not fc or not pk or not Path(fc).is_file():
        hook = Path("/root/vpn/server/hooks/hysteria-cert-copy.sh")
        if hook.is_file():
            r = subprocess.run(["bash", str(hook)], capture_output=True, text=True, timeout=60)
            if r.returncode == 0:
                return CertActionResult(True, "Hysteria: сертификат скопирован (hook)")
            return CertActionResult(False, r.stderr or r.stdout or "hook failed")
        return CertActionResult(False, "Нет LE путей в tls.env")
    HYSTERIA_CERT.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-f", fc, str(HYSTERIA_CERT / "fullchain.pem")], check=False)
    subprocess.run(["cp", "-f", pk, str(HYSTERIA_CERT / "privkey.pem")], check=False)
    return CertActionResult(True, "Hysteria: fullchain/privkey обновлены")


def renew_certificates(cert_name: str | None = None) -> CertActionResult:
    cmd = ["certbot", "renew", "--non-interactive", "--no-random-sleep-on-renew"]
    if cert_name:
        cmd.extend(["--cert-name", cert_name])
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    out = (r.stdout + r.stderr)[-3000:]
    sync = sync_hysteria_from_le()
    if r.returncode != 0:
        return CertActionResult(False, f"certbot renew failed:\n{out}")
    msg = "Let's Encrypt: renew выполнен."
    if sync.ok:
        msg += " " + sync.message
    else:
        msg += f" (Hysteria: {sync.message})"
    return CertActionResult(True, msg)


def reissue_new_domain(domain: str, email: str | None = None) -> CertActionResult:
    domain = domain.strip().lower()
    if not re.match(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", domain):
        return CertActionResult(False, "Некорректный домен")
    tls = _load_tls()
    email = (email or tls.get("LE_EMAIL") or "").strip()
    if not email:
        return CertActionResult(False, "Укажите email для Let's Encrypt")

    subprocess.run(["systemctl", "stop", "nginx"], capture_output=True, timeout=30)
    cmd = [
        "certbot",
        "certonly",
        "--standalone",
        "--non-interactive",
        "--agree-tos",
        "--email",
        email,
        "-d",
        domain,
        "--force-renewal",
    ]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    subprocess.run(["systemctl", "start", "nginx"], capture_output=True, timeout=30)

    out = (r.stdout + r.stderr)[-3000:]
    if r.returncode != 0:
        return CertActionResult(False, f"certbot certonly failed:\n{out}")

    fc = f"/etc/letsencrypt/live/{domain}/fullchain.pem"
    pk = f"/etc/letsencrypt/live/{domain}/privkey.pem"
    if not Path(fc).is_file():
        return CertActionResult(False, "Сертификат не найден после certbot")
    _write_tls_public_host(domain, fc, pk)
    sync = sync_hysteria_from_le()
    subprocess.run(["systemctl", "reload", "hysteria-server"], capture_output=True, timeout=30)
    subprocess.run(["systemctl", "reload", "xray-reality"], capture_output=True, timeout=30)
    msg = f"Выпущен сертификат для {domain}, tls.env обновлён."
    if sync.ok:
        msg += " " + sync.message
    return CertActionResult(True, msg)


def maybe_auto_renew(threshold_days: int = 3) -> CertActionResult:
    from app.services.certs import all_cert_status

    data = all_cert_status()
    certs = data.get("certificates") or []
    if not certs:
        return CertActionResult(False, "Нет сертификатов для проверки")
    min_days = min(
        (c.days_left for c in certs if c.days_left is not None),
        default=999,
    )
    if min_days > threshold_days:
        return CertActionResult(True, f"Автопродление: ещё {min_days} дн., действие не требуется")
    return renew_certificates()
