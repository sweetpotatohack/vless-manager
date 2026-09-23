#!/bin/bash
# DNS панели agent для вывода в install (из master node-config, иначе hostname).
set -euo pipefail

DATA="${VLESS_PANEL_DATA:-/etc/vless-manager/panel}"
fallback="$(hostname -f 2>/dev/null || echo "127.0.0.1")"

if [[ "${VLESS_PANEL_ROLE:-master}" != "agent" ]]; then
  echo "$fallback"
  exit 0
fi

master="${VLESS_PANEL_MASTER_URL:-}"
if [[ -z "$master" && -f "$DATA/master.url" ]]; then
  master="$(tr -d '\n\r' < "$DATA/master.url")"
fi
token="${VLESS_PANEL_AGENT_TOKEN:-}"
if [[ -z "$token" && -f "$DATA/agent.env" ]]; then
  # shellcheck disable=SC1090
  source "$DATA/agent.env"
  token="${VLESS_PANEL_AGENT_TOKEN:-}"
fi

if [[ -n "$master" && -n "$token" ]]; then
  domain="$(curl -fsS --max-time 25 -H "Authorization: Bearer ${token}" \
    "${master%/}/api/v1/agent/node-config" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print((d.get('vpn_domain') or '').strip())" 2>/dev/null \
    || true)"
  if [[ -n "$domain" && ! "$domain" =~ \.local$ ]]; then
    echo "$domain"
    exit 0
  fi
fi

echo "$fallback"
