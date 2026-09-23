from __future__ import annotations

import os
import secrets
from pathlib import Path

PANEL_ROOT = Path(os.environ.get("VLESS_PANEL_ROOT", "/etc/vless-manager/panel"))
PANEL_ROOT.mkdir(parents=True, exist_ok=True)

DATA_DIR = PANEL_ROOT
DB_PATH = Path(os.environ.get("VLESS_PANEL_DB", str(PANEL_ROOT / "panel.db")))

VLESS_CONFIG_DIR = Path("/etc/vless-manager")
VLESS_MANAGER_SH = Path(os.environ.get("VLESS_MANAGER_SH", "/opt/vless-manager/vless_manager.sh"))
QR_DIR = VLESS_CONFIG_DIR / "qr-codes"
URL_DIR = VLESS_CONFIG_DIR / "urls"

SECRET_KEY_FILE = PANEL_ROOT / "secret.key"
if SECRET_KEY_FILE.exists():
    SECRET_KEY = SECRET_KEY_FILE.read_text().strip()
else:
    SECRET_KEY = secrets.token_hex(32)
    SECRET_KEY_FILE.write_text(SECRET_KEY)
    os.chmod(SECRET_KEY_FILE, 0o600)

SESSION_COOKIE = "vless_panel_session"
SESSION_MAX_AGE = 60 * 60 * 12

BIND_HOST = os.environ.get("VLESS_PANEL_HOST", "127.0.0.1")
BIND_HTTPS_PORT = int(os.environ.get("VLESS_PANEL_HTTPS_PORT", "8765"))
BIND_HTTP_PORT = int(os.environ.get("VLESS_PANEL_HTTP_PORT", "8766"))
BIND_PORT = BIND_HTTPS_PORT

APP_TITLE = "VLESS Manager Pro — Control Panel"
