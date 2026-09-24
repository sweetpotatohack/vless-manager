from __future__ import annotations

import re
import subprocess


def detect_egress_public_ip() -> str:
    urls = (
        "https://ident.me",
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
    )
    for url in urls:
        try:
            r = subprocess.run(
                ["curl", "-4", "-fsSk", "--max-time", "12", url],
                capture_output=True,
                text=True,
                timeout=15,
            )
            ip = (r.stdout or "").strip()
            if re.match(r"^\d+\.\d+\.\d+\.\d+$", ip):
                return ip
        except (OSError, subprocess.TimeoutExpired):
            continue
    return ""
