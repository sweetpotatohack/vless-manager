from __future__ import annotations


def render_agent_install_script(*, master_url: str, node_token: str, node_name: str) -> str:
    master_url = master_url.rstrip("/")
    return f"""#!/bin/bash
set -euo pipefail

if [[ "${{EUID:-}}" -ne 0 ]]; then
  echo "Запустите от root: curl -fsSL ... | bash" >&2
  exit 1
fi

MASTER="{master_url}"
NODE_TOKEN="{node_token}"
NODE_NAME="{node_name}"

_vless_report_install_failed() {{
  local ec=$?
  if [[ $ec -eq 0 ]]; then
    return 0
  fi
  curl -fsS --max-time 20 -X POST "$MASTER/api/v1/nodes/install-failed" \\
    -H "Content-Type: application/json" \\
    -d "{{\\"token\\":\\"$NODE_TOKEN\\",\\"code\\":$ec}}" \\
    2>/dev/null || true
  return "$ec"
}}
trap _vless_report_install_failed EXIT

echo "=== VLESS Agent: $NODE_NAME -> $MASTER ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y curl ca-certificates python3 python3-venv rsync tar git >/dev/null 2>&1 || true

WORKDIR="/tmp/vless-agent-install"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "Загрузка bundle с master..."
curl -fsSL "$MASTER/api/v1/agent/bundle.tar.gz?token=$NODE_TOKEN" -o bundle.tar.gz
tar xzf bundle.tar.gz

export VLESS_PANEL_AGENT_TOKEN="$NODE_TOKEN"
export VLESS_PANEL_MASTER_URL="$MASTER"
export VLESS_PANEL_ROLE=agent

if [[ -f install_vless_manager.sh ]]; then
  chmod +x install_vless_manager.sh vless_manager.sh panel/install_panel.sh 2>/dev/null || true
  bash install_vless_manager.sh --remote-agent
else
  mkdir -p /opt/vless-manager
  cp -f vless_manager.sh /opt/vless-manager/vless_manager.sh
  bash panel/install_panel.sh
fi

LOCAL_IP="$(hostname -I 2>/dev/null | awk '{{for(i=1;i<=NF;i++) if($i!~/^127\\./) {{print $i; exit}}}}')"
fetch_public_ip() {{
  local url ip
  for url in "https://ident.me" "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
    ip="$(curl -4 -fsSk --max-time 12 "$url" 2>/dev/null | tr -d '\\r\\n ')"
    if [[ "$ip" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}}
PUBLIC_IP="$(fetch_public_ip 2>/dev/null || true)"
PUBLIC_IP="${{VLESS_AGENT_PUBLIC_IP:-$PUBLIC_IP}}"
if [[ -n "$PUBLIC_IP" ]]; then
  REPORT_IP="$PUBLIC_IP"
else
  REPORT_IP="${{LOCAL_IP:-127.0.0.1}}"
fi
API_BASE="http://${{LOCAL_IP:-127.0.0.1}}:8765"
echo "Публичный IP (egress): ${{REPORT_IP:-?}} · LAN: ${{LOCAL_IP:-—}}"

echo "Регистрация на master..."
REG_BODY="{{\\"token\\":\\"$NODE_TOKEN\\",\\"public_ip\\":\\"$REPORT_IP\\",\\"api_base\\":\\"$API_BASE\\"}}"
REG_RESP="$(curl -fsSL -X POST "$MASTER/api/v1/nodes/register" \\
  -H "Content-Type: application/json" \\
  -d "$REG_BODY")"
echo "$REG_RESP"
VPN_DOMAIN="$(printf '%s' "$REG_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('vpn_domain',''))" 2>/dev/null || true)"
if [[ -n "$VPN_DOMAIN" && -f /opt/vless-manager/vless_manager.sh ]]; then
  echo "VLESS DNS (из панели master): $VPN_DOMAIN"
  bash /opt/vless-manager/vless_manager.sh cli set-public-host "$VPN_DOMAIN" || true
  echo ""
  echo "=== VLESS Panel (DNS из master) ==="
  echo "URL (HTTPS): https://${{VPN_DOMAIN}}:8765/login"
  echo "URL (HTTP fallback): http://${{VPN_DOMAIN}}:8766/login"
fi

echo ""
echo "=== Службы (autostart) ==="
systemctl enable vless-panel.service vless-agent.service 2>/dev/null || systemctl enable vless-panel.service
systemctl is-active vless-panel.service && echo "vless-panel: active"
echo "API (справочно): $API_BASE/api/v1/health"
echo "Provision: agent опрашивает master (HTTPS), прямой доступ master→agent не обязателен"
"""
