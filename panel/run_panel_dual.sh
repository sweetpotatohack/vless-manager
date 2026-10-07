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

wait_for_port() {
  local port=$1
  local i
  for i in $(seq 1 15); do
    if ! ss -tln "sport = :$port" 2>/dev/null | grep -q ":$port "; then
      return 0
    fi
    sleep 0.2
  done
  echo "vless-panel: ERROR port :$port still in use" >&2
  ss -tlnp 2>/dev/null | grep ":$port " >&2 || true
  return 1
}

wait_for_port "$HTTP_PORT" || exit 1
echo "vless-panel: HTTP fallback :$HTTP_PORT"
VLESS_PANEL_RUN_AGENT_WORKER=0 "$UVICORN" "${BASE_ARGS[@]}" --port "$HTTP_PORT" &
pids+=($!)
sleep 0.3
if ! kill -0 "${pids[-1]}" 2>/dev/null; then
  echo "vless-panel: HTTP worker failed to start on :$HTTP_PORT" >&2
  exit 1
fi

FC="${LE_FULLCHAIN:-}"
PK="${LE_PRIVKEY:-}"
wait_for_port "$HTTPS_PORT" || exit 1
if [[ -n "$FC" && -n "$PK" && -f "$FC" && -f "$PK" ]]; then
  echo "vless-panel: HTTPS :$HTTPS_PORT (certs from tls.env)"
  VLESS_PANEL_RUN_AGENT_WORKER=1 "$UVICORN" "${BASE_ARGS[@]}" --port "$HTTPS_PORT" \
    --ssl-certfile "$FC" --ssl-keyfile "$PK" &
  pids+=($!)
else
  echo "vless-panel: WARN — LE certs missing; HTTPS :$HTTPS_PORT disabled"
  echo "vless-panel: HTTP also on :$HTTPS_PORT (emergency)"
  VLESS_PANEL_RUN_AGENT_WORKER=1 "$UVICORN" "${BASE_ARGS[@]}" --port "$HTTPS_PORT" &
  pids+=($!)
fi
sleep 0.3
if ! kill -0 "${pids[-1]}" 2>/dev/null; then
  echo "vless-panel: HTTPS worker failed to start on :$HTTPS_PORT" >&2
  stop_children
  exit 1
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
