#!/bin/bash
# HTTPS :8765 (LE из tls.env) + HTTP :8766 (аварийный вход без TLS)
set -euo pipefail

INSTALL_DIR="${VLESS_PANEL_INSTALL_DIR:-/opt/vless-manager/panel}"
VENV="${VLESS_PANEL_VENV:-$INSTALL_DIR/venv}"
TLS_ENV="${VLESS_TLS_ENV:-/etc/vless-manager/tls.env}"

HTTPS_PORT="${VLESS_PANEL_HTTPS_PORT:-8765}"
HTTP_PORT="${VLESS_PANEL_HTTP_PORT:-8766}"
HOST="${VLESS_PANEL_HOST:-0.0.0.0}"

cd "$INSTALL_DIR"
export PYTHONPATH="$INSTALL_DIR"

if [[ -f "$TLS_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$TLS_ENV"
fi

UVICORN="$VENV/bin/uvicorn"
BASE_ARGS=(app.main:app --host "$HOST")

pids=()
stop_children() {
  local p
  for p in "${pids[@]:-}"; do
    kill "$p" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}

trap 'stop_children; exit 0' SIGTERM SIGINT

echo "vless-panel: HTTP fallback :$HTTP_PORT"
"$UVICORN" "${BASE_ARGS[@]}" --port "$HTTP_PORT" &
pids+=($!)

FC="${LE_FULLCHAIN:-}"
PK="${LE_PRIVKEY:-}"
if [[ -n "$FC" && -n "$PK" && -f "$FC" && -f "$PK" ]]; then
  echo "vless-panel: HTTPS :$HTTPS_PORT (certs from tls.env)"
  "$UVICORN" "${BASE_ARGS[@]}" --port "$HTTPS_PORT" \
    --ssl-certfile "$FC" --ssl-keyfile "$PK" &
  pids+=($!)
else
  echo "vless-panel: WARN — LE certs missing; HTTPS :$HTTPS_PORT disabled"
  echo "vless-panel: HTTP also on :$HTTPS_PORT (emergency)"
  "$UVICORN" "${BASE_ARGS[@]}" --port "$HTTPS_PORT" &
  pids+=($!)
fi

while true; do
  for p in "${pids[@]}"; do
    if ! kill -0 "$p" 2>/dev/null; then
      wait "$p" 2>/dev/null || true
      echo "vless-panel: worker $p exited"
      stop_children
      exit 1
    fi
  done
  sleep 2
done
