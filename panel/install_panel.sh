#!/bin/bash
set -euo pipefail

if [[ "${EUID:-}" -ne 0 ]]; then
  echo "Запустите от root: sudo $0" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/opt/vless-manager/panel"
VENV="$INSTALL_DIR/venv"
DATA="/etc/vless-manager/panel"

mkdir -p "$DATA" "$INSTALL_DIR"
rsync -a --delete \
  --exclude venv \
  --exclude __pycache__ \
  "$REPO_ROOT/panel/" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/run_panel_dual.sh"

mkdir -p /opt/vless-manager
cp -f "$REPO_ROOT/vless_manager.sh" /opt/vless-manager/vless_manager.sh
chmod +x /opt/vless-manager/vless_manager.sh

apt-get update -qq >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv python3-pip rsync >/dev/null 2>&1 || true

python3 -m venv "$VENV"
"$VENV/bin/pip" install -q -U pip
"$VENV/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
if "$VENV/bin/python" -c "import sys; sys.exit(0 if sys.version_info >= (3, 14) else 1)"; then
  echo "Python 3.14+: upgrading SQLAlchemy (PEP 649 / Union compatibility)"
  "$VENV/bin/pip" install -q -U "sqlalchemy>=2.0.54"
fi

PY_VER="$("$VENV/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
echo "Python $PY_VER (panel venv)"
PYTHONPATH="$INSTALL_DIR" "$VENV/bin/python" -c "from app.models import Node  # noqa: F401" \
  || {
  echo "Ошибка: ORM не загружается (часто Python 3.14 + старый SQLAlchemy). Обновите bundle на master и повторите." >&2
  exit 1
}

if [[ -n "${VLESS_PANEL_AGENT_TOKEN:-}" ]]; then
  cat > "$DATA/agent.env" << EOF
VLESS_PANEL_AGENT_TOKEN=${VLESS_PANEL_AGENT_TOKEN}
EOF
  chmod 600 "$DATA/agent.env"
elif [[ ! -f "$DATA/agent.env" ]]; then
  TOKEN="$(openssl rand -hex 24)"
  cat > "$DATA/agent.env" << EOF
VLESS_PANEL_AGENT_TOKEN=$TOKEN
EOF
  chmod 600 "$DATA/agent.env"
  echo "Agent token (local): $TOKEN"
fi

if [[ -n "${VLESS_PANEL_MASTER_URL:-}" ]]; then
  echo "$VLESS_PANEL_MASTER_URL" > "$DATA/master.url"
elif [[ -f /etc/vless-manager/tls.env ]]; then
  # shellcheck source=/dev/null
  source /etc/vless-manager/tls.env
  if [[ -n "${PUBLIC_HOST:-}" ]]; then
    echo "https://${PUBLIC_HOST}:8765" > "$DATA/master.url"
  fi
fi

PANEL_ROLE="${VLESS_PANEL_ROLE:-master}"
if [[ "$PANEL_ROLE" == "agent" ]]; then
  PANEL_DESC="VLESS Remote Agent (API + panel)"
else
  PANEL_DESC="VLESS Manager Pro Control Panel"
fi

cat > /etc/systemd/system/vless-panel.service << EOF
[Unit]
Description=$PANEL_DESC
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
Environment=PYTHONPATH=$INSTALL_DIR
EnvironmentFile=-$DATA/agent.env
Environment=VLESS_PANEL_HOST=0.0.0.0
Environment=VLESS_PANEL_HTTPS_PORT=8765
Environment=VLESS_PANEL_HTTP_PORT=8766
Environment=VLESS_PANEL_ROLE=$PANEL_ROLE
Environment=VLESS_PANEL_INSTALL_DIR=$INSTALL_DIR
Environment=VLESS_PANEL_VENV=$VENV
Environment=VLESS_TLS_ENV=/etc/vless-manager/tls.env
Environment=VLESS_MANAGER_SH=/opt/vless-manager/vless_manager.sh
ExecStart=/bin/bash $INSTALL_DIR/run_panel_dual.sh
Restart=on-failure
RestartSec=3
KillMode=control-group
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Псевдоним для удалённых нод (то же самое)
cp -f /etc/systemd/system/vless-panel.service /etc/systemd/system/vless-agent.service

systemctl daemon-reload
systemctl enable vless-panel.service
systemctl enable vless-agent.service 2>/dev/null || true
systemctl restart vless-panel.service

sleep 1
PYTHONPATH="$INSTALL_DIR" "$VENV/bin/python" << 'PY'
from app.auth import hash_password
from app.database import SessionLocal
from app.models import AdminUser

db = SessionLocal()
admin = db.query(AdminUser).filter(AdminUser.username == "admin").first()
if not admin:
    db.add(AdminUser(username="admin", password_hash=hash_password("admin")))
else:
    admin.password_hash = hash_password("admin")
db.commit()
db.close()
print("Admin: admin / admin")
PY

echo "=== VLESS Panel ==="
echo "URL (HTTPS): https://$(hostname -f 2>/dev/null || echo 127.0.0.1):8765/login"
echo "URL (HTTP fallback): http://$(hostname -f 2>/dev/null || echo 127.0.0.1):8766/login"
echo "Логин: admin  Пароль: admin"
systemctl --no-pager status vless-panel.service | head -5
