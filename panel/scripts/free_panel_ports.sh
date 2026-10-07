#!/bin/bash
# Перед стартом vless-panel: снять «осиротевшие» uvicorn после неудачного restart.
set -euo pipefail

INSTALL_DIR="${VLESS_PANEL_INSTALL_DIR:-/opt/vless-manager/panel}"
HTTPS_PORT="${VLESS_PANEL_HTTPS_PORT:-8765}"
HTTP_PORT="${VLESS_PANEL_HTTP_PORT:-8766}"
UVICORN="${VLESS_PANEL_VENV:-$INSTALL_DIR/venv}/bin/uvicorn"

if [[ -x "$UVICORN" ]]; then
  pkill -f "${UVICORN} app.main:app" 2>/dev/null || true
fi
pkill -f "${INSTALL_DIR}/venv/bin/uvicorn app.main:app" 2>/dev/null || true

for port in "$HTTPS_PORT" "$HTTP_PORT"; do
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${port}/tcp" 2>/dev/null || true
  fi
done

sleep 0.4
