#!/bin/bash
# Обновление master/agent, когда /opt/vless-manager не git-клон (типичная установка).
set -euo pipefail

if [[ "${EUID:-}" -ne 0 ]]; then
  echo "Запустите от root: sudo $0" >&2
  exit 1
fi

REPO_URL="${VLESS_UPDATE_REPO:-https://github.com/sweetpotatohack/vless-manager.git}"
REF="${VLESS_UPDATE_REF:-main}"
WORKDIR="$(mktemp -d /tmp/vless-manager-update.XXXXXX)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "=== VLESS Manager: update from GitHub ($REF) ==="
if ! command -v git >/dev/null 2>&1; then
  apt-get update -qq >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y git >/dev/null 2>&1
fi

git clone --depth 1 --branch "$REF" "$REPO_URL" "$WORKDIR/src"
SRC="$WORKDIR/src"

install -d /opt/vless-manager
rsync -a --delete \
  --exclude venv \
  --exclude __pycache__ \
  "$SRC/panel/" /opt/vless-manager/panel/
chmod +x /opt/vless-manager/panel/run_panel_dual.sh

for f in vless_manager.sh vless-servers-script.sh install_vless_manager.sh; do
  if [[ -f "$SRC/$f" ]]; then
    install -m 755 "$SRC/$f" "/opt/vless-manager/$f"
  fi
done
if [[ -f "$SRC/vless-servers-script.sh" ]]; then
  install -m 755 "$SRC/vless-servers-script.sh" /usr/local/bin/vless-servers
fi

bash "$SRC/panel/install_panel.sh"

echo ""
echo "Проверка:"
grep -E '^sqlalchemy' /opt/vless-manager/panel/requirements.txt || true
systemctl is-active vless-panel.service && echo "vless-panel: active" || systemctl status vless-panel.service --no-pager | head -8
echo "Готово. Bundle для agent-нод обновлён с этого сервера."
