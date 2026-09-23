#!/bin/bash

# VLESS Manager v1.3 - QR Codes & Network Enhancement
# Created by: AKUMA0xDEAD

# Configuration
readonly CONFIG_DIR="/etc/vless-manager"
readonly LOG_DIR="/var/log"
readonly CLIENT_DIR="$CONFIG_DIR/clients"
readonly QR_DIR="$CONFIG_DIR/qr-codes"
readonly CERT_DIR="$CONFIG_DIR/certs"
readonly BUNDLE_DIR="$CONFIG_DIR/bundles"
readonly TLS_ENV="$CONFIG_DIR/tls.env"
# WebSocket path (desktop legacy / mobile v2rayTun)
readonly VLESS_WS_PATH="/vless"
# Высокие порты: не пересекаемся с 80/443 (Gophish, nginx, CDN) и типичными сервисами
readonly VLESS_PORT_MIN=25000
readonly VLESS_PORT_MAX=45000
# Мобила (v2rayTun): Xray слушает localhost; снаружи nginx на :443
readonly VLESS_MOBILE_PORT_MIN=31000
readonly VLESS_MOBILE_PORT_MAX=45000
readonly VLESS_MOBILE_PUBLIC_PORT=443
readonly VLESS_NGINX_D="$CONFIG_DIR/nginx.d"
readonly GOPHISH_COMPOSE="/root/sneaky-gophish-ssl-automation/docker-compose.yml"
readonly MOBILE_REALITY_HUB="_mobile-reality"
readonly MOBILE_REALITY_PORT=443
readonly MOBILE_REALITY_DIR="$CONFIG_DIR/mobile-reality"
readonly REALITY_CONFIG_FILE="/etc/xray-reality/config.json"
readonly REALITY_ENV="$CONFIG_DIR/reality.env"
readonly REALITY_DEST_DEFAULT="www.samsung.com:443"
readonly REALITY_SNI_DEFAULT="www.samsung.com"
readonly MOBILE_REALITY_FP="chrome"
readonly HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
readonly HYSTERIA_ENV="$CONFIG_DIR/hysteria.env"
readonly HYSTERIA_CERT_DIR="/etc/hysteria/certs"
readonly HYSTERIA_PORT=25001
readonly VLESS_NEVER_PORTS=(80 443 8080 8443 8000 8888 3000 5000 3333 53 853 4443 9443 9444)

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/vless-manager.log" 2>/dev/null || true
    case "$level" in
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        *) echo "$message" ;;
    esac
}

# Check root
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Этот скрипт нужно запускать под root!${NC}"
        exit 1
    fi
}

# Setup directories
setup_directories() {
    mkdir -p "$CONFIG_DIR" "$CLIENT_DIR" "$LOG_DIR" "$QR_DIR" "$CERT_DIR"
    mkdir -p "$CONFIG_DIR/urls" "$CONFIG_DIR/backup" "$BUNDLE_DIR"
    mkdir -p "$CONFIG_DIR/templates"
    chmod 755 "$CONFIG_DIR"
    chmod 700 "$CERT_DIR"
    chmod 700 "$CLIENT_DIR"
    [[ -f "$TLS_ENV" ]] && chmod 600 "$TLS_ENV"
    local _tm_src=""
    [[ -d "/opt/vless-manager/templates" ]] && _tm_src="/opt/vless-manager/templates"
    [[ -z "$_tm_src" && -d "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates" ]] && _tm_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"
    if [[ -n "$_tm_src" ]]; then
        cp -f "$_tm_src/"* "$CONFIG_DIR/templates/" 2>/dev/null || true
    fi
}

# Check dependencies  
check_dependencies() {
    local missing_deps=()
    local deps=("xray" "sqlite3" "openssl" "qrencode")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Отсутствуют зависимости: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Запустите установщик: ./install_vless_manager.sh${NC}"
        exit 1
    fi
}

# Show banner
show_banner() {
    clear
    echo -e "${PURPLE}"
    cat << 'BANNER'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    VLESS MANAGER v1.3                        ║
    ║             QR Codes & Network Enhancement                    ║
    ║                  by AKUMA0xDEAD                              ║
    ╚═══════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

# Show menu
show_menu() {
    echo -e "${BLUE}╔══════════════════ ГЛАВНОЕ МЕНЮ ══════════════════╗${NC}"
    echo -e "${BLUE}║ 1) Создать новый VLESS конфиг (ПК / Wi‑Fi)       ║${NC}"
    echo -e "${BLUE}║ 10) Мобила — REALITY :443 + Hysteria2 :25001    ║${NC}"
    echo -e "${BLUE}║ 2) Показать существующие конфиги                ║${NC}"
    echo -e "${BLUE}║ 3) Удалить конфиг                               ║${NC}"
    echo -e "${BLUE}║ 4) Показать активные подключения                ║${NC}"
    echo -e "${BLUE}║ 5) Настроить OpenVPN интеграцию                 ║${NC}"
    echo -e "${BLUE}║ 6) Мониторинг системы                           ║${NC}"
    echo -e "${BLUE}║ 7) Показать логи                                ║${NC}"
    echo -e "${BLUE}║ 8) Настройки системы                            ║${NC}"
    echo -e "${BLUE}║ 9) Восстановить базу данных                     ║${NC}"
    echo -e "${BLUE}║ 0) Выход                                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo -n "Выбери опцию, господин хакер: "
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
        openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)/\1-\2-\3-\4-/'
    fi
}

# Публичный IPv4 VPS (для ссылки/QR; клиент должен стучаться именно на этот адрес)
get_server_ip() {
    local ip=""
    local u
    for u in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ip=$(curl -4 -fsS --max-time 7 "$u" 2>/dev/null | tr -d '\r\n ')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    ip=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {print $i; exit}}')
    echo "${ip:-127.0.0.1}"
}

# Режим TLS: самоподпись или общий сертификат Let's Encrypt (из install)
load_tls_env() {
    TLS_MODE="selfsigned"
    PUBLIC_HOST=""
    LE_FULLCHAIN=""
    LE_PRIVKEY=""
    LE_EMAIL=""
    [[ -f "$TLS_ENV" ]] || return 0
    # shellcheck source=/dev/null
    source "$TLS_ENV"
}

tls_uses_letsencrypt() {
    load_tls_env
    [[ "${TLS_MODE:-}" == "letsencrypt" && -n "${LE_FULLCHAIN:-}" && -f "${LE_FULLCHAIN}" && -n "${LE_PRIVKEY:-}" && -f "${LE_PRIVKEY}" ]]
}

# Адрес в ссылке/QR и SNI: домен (LE) или публичный IP
get_public_host() {
    load_tls_env
    if [[ -n "${PUBLIC_HOST:-}" ]]; then
        echo "$PUBLIC_HOST"
    else
        get_server_ip
    fi
}

# Порт зарезервирован под веб/админки/ DNS — не выдаём клиентам VLESS
vless_port_is_forbidden() {
    local p="$1"
    local x
    for x in "${VLESS_NEVER_PORTS[@]}"; do
        [[ "$p" -eq "$x" ]] && return 0
    done
    # привилегированный диапазон
    [[ "$p" -lt 1024 ]] && return 0
    return 1
}

# Слушает ли порт на хосте (ss предпочтительнее netstat)
port_is_listening() {
    local p="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -H -tuln "sport = :$p" 2>/dev/null | grep -q .
        return $?
    fi
    netstat -tuln 2>/dev/null | grep -q ":$p "
}

# Все порты, уже назначенные клиентам (конфиги на диске + БД)
collect_assigned_vless_ports() {
    local client port config_file
    local -A seen=()

    while IFS= read -r client; do
        [[ -z "$client" ]] && continue
        config_file="$CLIENT_DIR/${client}.json"
        port=$(extract_port_from_config "$config_file")
        if [[ -n "$port" && -z "${seen[$port]:-}" ]]; then
            seen["$port"]=1
            echo "$port"
        fi
    done < <(get_all_config_files)

    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        while IFS= read -r port; do
            [[ -z "$port" ]] && continue
            [[ -n "${seen[$port]:-}" ]] && continue
            seen["$port"]=1
            echo "$port"
        done < <(sqlite3 "$CONFIG_DIR/clients.db" "SELECT port FROM clients;" 2>/dev/null)
    fi
}

# Порт занят: запрещённый, слушается ОС или уже назначен другому клиенту
vless_port_is_taken() {
    local p="$1"
    local assigned

    vless_port_is_forbidden "$p" && return 0
    port_is_listening "$p" && return 0

    while IFS= read -r assigned; do
        [[ -z "$assigned" ]] && continue
        [[ "$assigned" -eq "$p" ]] && return 0
    done < <(collect_assigned_vless_ports)

    return 1
}

# Свободный порт в диапазоне [min,max]: не слушается и не занят конфигами
find_free_port() {
    local start_port=${1:-$VLESS_PORT_MIN}
    local end_port=${2:-$VLESS_PORT_MAX}
    local port

    for ((port=start_port; port<=end_port; port++)); do
        vless_port_is_taken "$port" && continue
        echo "$port"
        return 0
    done
    echo "0"
    return 1
}

# Свободный порт для мобильных конфигов (диапазон 31000–45000, только localhost)
find_free_mobile_port() {
    find_free_port "$VLESS_MOBILE_PORT_MIN" "$VLESS_MOBILE_PORT_MAX"
}

# Конфиг mobile-443: Xray на 127.0.0.1, снаружи nginx stream passthrough :443
is_mobile_443_config() {
    local config_file="$1"
    [[ -f "$config_file" ]] || return 1
    grep -q '"listen": "127.0.0.1"' "$config_file" 2>/dev/null
}

# Клиент создан через mobile REALITY (hub)
is_mobile_reality_client() {
    local client_name="$1"
    [[ -f "$MOBILE_REALITY_DIR/${client_name}.uuid" ]]
}

# Ключи REALITY (x25519)
load_reality_env() {
    REALITY_PRIVATE_KEY=""
    REALITY_PUBLIC_KEY=""
    REALITY_SHORT_ID=""
    REALITY_DEST="$REALITY_DEST_DEFAULT"
    REALITY_SNI="$REALITY_SNI_DEFAULT"
    [[ -f "$REALITY_ENV" ]] && source "$REALITY_ENV"
    REALITY_DEST="${REALITY_DEST:-$REALITY_DEST_DEFAULT}"
    REALITY_SNI="${REALITY_SNI:-$REALITY_SNI_DEFAULT}"
}

ensure_reality_keys() {
    load_reality_env
    if [[ -n "${REALITY_PRIVATE_KEY:-}" && -n "${REALITY_PUBLIC_KEY:-}" && -n "${REALITY_SHORT_ID:-}" ]]; then
        return 0
    fi
    local out priv pub
    out=$(xray x25519 2>/dev/null) || return 1
    priv=$(echo "$out" | awk -F': ' '/^PrivateKey/ {print $2}' | tr -d ' \r')
    pub=$(echo "$out" | awk -F': ' '/Password \(PublicKey\)/ {print $2}' | tr -d ' \r')
    REALITY_SHORT_ID=$(openssl rand -hex 4 2>/dev/null || echo "a1b2c3d4")
    REALITY_PRIVATE_KEY="$priv"
    REALITY_PUBLIC_KEY="$pub"
    cat > "$REALITY_ENV" << EOF
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
REALITY_DEST=$REALITY_DEST
REALITY_SNI=$REALITY_SNI
EOF
    chmod 600 "$REALITY_ENV"
}

# VLESS URL — REALITY TCP + Vision :443 (схема kibervpn / LTE РФ)
build_mobile_reality_url() {
    local client_name="$1" uuid="$2" connect_host
    load_reality_env
    connect_host=$(get_public_host)
    echo "vless://${uuid}@${connect_host}:${VLESS_MOBILE_PUBLIC_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=${MOBILE_REALITY_FP}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#${client_name}"
}

load_hysteria_env() {
    HY2_PASS=""
    [[ -f "$HYSTERIA_ENV" ]] && source "$HYSTERIA_ENV"
}

ensure_hysteria_password() {
    load_hysteria_env
    if [[ -n "${HY2_PASS:-}" ]]; then
        return 0
    fi
    HY2_PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
    echo "HY2_PASS=${HY2_PASS}" > "$HYSTERIA_ENV"
    chmod 600 "$HYSTERIA_ENV"
}

build_hysteria_url() {
    local client_name="$1" host
    load_hysteria_env
    host=$(get_public_host)
    echo "hy2://${HY2_PASS}@${host}:${HYSTERIA_PORT}?sni=${host}#${client_name}-hy2"
}

# Отдельный inbound REALITY :443 → /etc/xray-reality/config.json (как kibervpn)
rebuild_mobile_reality_hub() {
    load_reality_env
    mkdir -p "$MOBILE_REALITY_DIR" /etc/xray-reality

    HUB_CFG_PATH="$REALITY_CONFIG_FILE" HUB_MDIR="$MOBILE_REALITY_DIR" HUB_PORT="$MOBILE_REALITY_PORT" \
    REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY" REALITY_SHORT_ID="$REALITY_SHORT_ID" \
    REALITY_DEST="$REALITY_DEST" REALITY_SNI="$REALITY_SNI" \
    python3 << 'PY'
import json, os, glob
port = int(os.environ.get("HUB_PORT", "443"))
cfg_path = os.environ["HUB_CFG_PATH"]
mdir = os.environ["HUB_MDIR"]
priv = os.environ["REALITY_PRIVATE_KEY"]
sid = os.environ["REALITY_SHORT_ID"]
dest = os.environ.get("REALITY_DEST", "www.samsung.com:443")
sni = os.environ.get("REALITY_SNI", "www.samsung.com")

clients = []
for path in sorted(glob.glob(mdir + "/*.uuid")):
    name = os.path.basename(path).replace(".uuid", "")
    with open(path) as f:
        uuid = f.read().strip()
    if uuid:
        clients.append({
            "id": uuid,
            "flow": "xtls-rprx-vision",
            "email": f"{name}@vless.local"
        })

cfg = {
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "listen": "0.0.0.0",
        "port": port,
        "protocol": "vless",
        "settings": {"clients": clients, "decryption": "none"},
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "dest": dest,
                "serverNames": [sni],
                "privateKey": priv,
                "shortIds": [sid]
            }
        },
        "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}
    }],
    "outbounds": [{"protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}}]
}
with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
    rm -f "$CLIENT_DIR/${MOBILE_REALITY_HUB}.json" 2>/dev/null || true
}

# Освободить :443 для xray-reality; nginx/hysteria на 443 не используем
setup_nginx_reality_stream() {
    local stream_conf="/etc/nginx/stream.d/vless-mobile.conf"

    setup_gophish_port_for_nginx
    systemctl stop hysteria-mobile.service 2>/dev/null || true
    systemctl disable hysteria-mobile.service 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/vless-mobile-443.conf /etc/nginx/sites-enabled/default 2>/dev/null || true

    cat > "$stream_conf" << 'NGINX_STREAM'
# REALITY :443 — отдельный xray-reality.service
NGINX_STREAM

    if command -v nginx >/dev/null 2>&1; then
        nginx -t >/dev/null 2>&1 || { nginx -t; return 1; }
        systemctl reload nginx >/dev/null 2>&1 || true
    fi
}

install_xray_reality_unit() {
    cat > /etc/systemd/system/xray-reality.service << 'UNIT'
[Unit]
Description=Xray VLESS Reality :443 (vless-manager mobile)
After=network-online.target

[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray-reality/config.json
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable xray-reality.service >/dev/null 2>&1 || true
}

sync_hysteria_certs() {
    load_tls_env
    [[ -f "${LE_FULLCHAIN:-}" && -f "${LE_PRIVKEY:-}" ]] || return 1
    mkdir -p "$HYSTERIA_CERT_DIR"
    cp -f "$LE_FULLCHAIN" "$HYSTERIA_CERT_DIR/fullchain.pem"
    cp -f "$LE_PRIVKEY" "$HYSTERIA_CERT_DIR/privkey.pem"
    chmod 644 "$HYSTERIA_CERT_DIR/fullchain.pem" 2>/dev/null || true
    chmod 600 "$HYSTERIA_CERT_DIR/privkey.pem" 2>/dev/null || true
}

setup_hysteria_mobile() {
    load_tls_env
    ensure_hysteria_password
    sync_hysteria_certs || {
        echo -e "${RED}Нужен Let's Encrypt для Hysteria2${NC}"
        return 1
    }
    local public_host
    public_host=$(get_public_host)
    mkdir -p /etc/hysteria
    cat > "$HYSTERIA_CONFIG" << EOF
listen: :${HYSTERIA_PORT}

tls:
  cert: ${HYSTERIA_CERT_DIR}/fullchain.pem
  key: ${HYSTERIA_CERT_DIR}/privkey.pem

auth:
  type: password
  password: ${HY2_PASS}

masquerade:
  type: proxy
  proxy:
    url: https://${public_host}
    rewriteHost: true

bandwidth:
  up: 1 gbps
  down: 1 gbps
EOF
    cat > /etc/systemd/system/hysteria-server.service << 'UNIT'
[Unit]
Description=Hysteria2 mobile backup (UDP)
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT
    if ! command -v hysteria >/dev/null 2>&1; then
        echo -e "${YELLOW}Устанавливаю Hysteria2...${NC}"
        curl -fsSL -o /usr/local/bin/hysteria \
            "https://github.com/apernet/hysteria/releases/download/app/v2.12.3/hysteria-linux-amd64" && \
            chmod +x /usr/local/bin/hysteria || return 1
    fi
    local hook="/etc/letsencrypt/renewal-hooks/post/vless-hysteria-cert-copy.sh"
    cat > "$hook" << 'HOOK'
#!/bin/bash
set -e
for d in /etc/letsencrypt/live/*/; do
  [[ -f "$d/fullchain.pem" && -f "$d/privkey.pem" ]] || continue
  cp -f "$d/fullchain.pem" /etc/hysteria/certs/fullchain.pem
  cp -f "$d/privkey.pem" /etc/hysteria/certs/privkey.pem
  break
done
HOOK
    chmod +x "$hook"
    systemctl daemon-reload
    systemctl enable hysteria-server.service >/dev/null 2>&1 || true
    systemctl restart hysteria-server.service 2>/dev/null || systemctl start hysteria-server.service
    iptables -C INPUT -p udp --dport "$HYSTERIA_PORT" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport "$HYSTERIA_PORT" -j ACCEPT 2>/dev/null || true
    log "INFO" "Hysteria2 UDP :${HYSTERIA_PORT} (запасной профиль LTE)"
}

restart_xray_reality() {
    install_xray_reality_unit
    if ! xray run -test -c "$REALITY_CONFIG_FILE" 2>/dev/null; then
        xray run -test -c "$REALITY_CONFIG_FILE" || return 1
    fi
    systemctl restart xray-reality.service 2>/dev/null || systemctl start xray-reality.service
}

# Добавить mobile-клиента в REALITY hub
register_mobile_reality_client() {
    local client_name="$1" uuid="$2"
    mkdir -p "$MOBILE_REALITY_DIR"
    echo "$uuid" > "$MOBILE_REALITY_DIR/${client_name}.uuid"
    rebuild_mobile_reality_hub
    restart_xray_reality
}

# Wi‑Fi + LTE: выдать обе ссылки
write_mobile_profile_bundle() {
    local client_name="$1" vless_url="$2" hy2_url="$3"
    local note_file="$CONFIG_DIR/urls/${client_name}-v2raytun.txt"
    load_reality_env
    cat > "$note_file" << EOF
Мобильный профиль: $client_name (схема kibervpn)
==============================================

★ LTE — REALITY :443 (основной, как у kibervpn):
$vless_url

★ Запасной — Hysteria2 UDP :${HYSTERIA_PORT}:
$hy2_url

Wi‑Fi / ПК — пункт 1 меню (VLESS+TLS порт 25000+), НЕ удаляйте!

v2rayTun:
1) Удалите старые профили с этим именем
2) Импортируй LTE-ссылку REALITY; если нет инета — hy2://
3) Private DNS ВЫКЛ, MUX ВЫКЛ
EOF
    echo "$vless_url" > "$CONFIG_DIR/urls/${client_name}.txt"
    echo "$hy2_url" > "$CONFIG_DIR/urls/${client_name}-hy2.txt"
    chmod 644 "$note_file" 2>/dev/null || true
}

# Освободить :443 на хосте для nginx (GoPhish → 127.0.0.1:8443)
setup_gophish_port_for_nginx() {
    [[ -f "$GOPHISH_COMPOSE" ]] || return 0
    if grep -qE '127\.0\.0\.1:8443:443|"443:443"' "$GOPHISH_COMPOSE" 2>/dev/null; then
        if grep -q '127.0.0.1:8443:443' "$GOPHISH_COMPOSE" 2>/dev/null; then
            return 0
        fi
    fi
    if ! grep -q '"443:443"' "$GOPHISH_COMPOSE" 2>/dev/null; then
        log "WARN" "GoPhish compose: не найден проброс 443:443 — nginx :443 настраивается вручную"
        return 0
    fi
    echo -e "${YELLOW}Переношу GoPhish с :443 на 127.0.0.1:8443 (для nginx + VLESS)...${NC}"
    cp -a "$GOPHISH_COMPOSE" "${GOPHISH_COMPOSE}.bak-vless-$(date +%Y%m%d%H%M%S)"
    sed -i 's/"443:443"/"127.0.0.1:8443:443"/' "$GOPHISH_COMPOSE"
    if command -v docker >/dev/null 2>&1; then
        (cd /root/sneaky-gophish-ssl-automation && docker compose up -d sneaky_gophish 2>/dev/null) || \
        (cd /root/sneaky-gophish-ssl-automation && docker-compose up -d sneaky_gophish 2>/dev/null) || true
        sleep 2
    fi
    log "INFO" "GoPhish: 443 перенесён на 127.0.0.1:8443"
}

# nginx stream :443 — SNI VPN-домена → Xray (TLS passthrough), иначе fallback upstream
setup_nginx_mobile_443() {
    local public_host stream_conf nginx_conf

    load_tls_env
    public_host=$(get_public_host)
    stream_conf="/etc/nginx/stream.d/vless-mobile.conf"
    nginx_conf="/etc/nginx/nginx.conf"

    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${YELLOW}Устанавливаю nginx...${NC}"
        apt-get update -qq >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y nginx libnginx-mod-stream >/dev/null 2>&1 || {
            echo -e "${RED}Не удалось установить nginx (apt-get install nginx libnginx-mod-stream)${NC}"
            return 1
        }
    fi
    if ! nginx -V 2>&1 | grep -q with-stream; then
        echo -e "${YELLOW}Устанавливаю модуль nginx stream...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y libnginx-mod-stream >/dev/null 2>&1 || true
    fi
    if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so ]] && \
       [[ ! -f /etc/nginx/modules-enabled/50-mod-stream.conf ]]; then
        echo 'load_module modules/ngx_stream_module.so;' > /etc/nginx/modules-enabled/50-mod-stream.conf
    fi

    setup_gophish_port_for_nginx
    mkdir -p "$VLESS_NGINX_D" /etc/nginx/stream.d "$CONFIG_DIR/mobile-stream"

    if [[ ! -f "${LE_FULLCHAIN:-}" || ! -f "${LE_PRIVKEY:-}" ]]; then
        echo -e "${RED}Нужен Let's Encrypt для ${public_host}${NC}"
        return 1
    fi

    # Убираем HTTP :443 (WS+http2 ломает v2rayTun на LTE)
    rm -f /etc/nginx/sites-enabled/vless-mobile-443.conf 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    if ! grep -q '^stream {' "$nginx_conf" 2>/dev/null; then
        cat >> "$nginx_conf" << 'NGINX_STREAM'

stream {
    include /etc/nginx/stream.d/*.conf;
}
NGINX_STREAM
    elif ! grep -q 'stream.d/\*\.conf' "$nginx_conf" 2>/dev/null; then
        sed -i '/^stream {/a \    include /etc/nginx/stream.d/*.conf;' "$nginx_conf"
    fi

    rebuild_mobile_stream_map "$public_host"

    if ! nginx -t 2>/dev/null; then
        echo -e "${RED}nginx -t failed — проверьте конфиг${NC}"
        nginx -t
        return 1
    fi
    systemctl enable nginx 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || {
        echo -e "${RED}Не удалось перезапустить nginx${NC}"
        return 1
    }
    log "INFO" "nginx stream :443 — TLS passthrough ${public_host} → Xray, иначе GoPhish"
}

# Пересобрать SNI map для mobile (один домен → последний зарегистрированный порт)
rebuild_mobile_stream_map() {
    local public_host="$1"
    local stream_conf="/etc/nginx/stream.d/vless-mobile.conf"
    local map_body="" client config_file port name

    while IFS= read -r client; do
        [[ -z "$client" ]] && continue
        config_file="$CLIENT_DIR/${client}.json"
        is_mobile_443_config "$config_file" || continue
        port=$(extract_port_from_config "$config_file")
        [[ -n "$port" ]] || continue
        echo "${public_host} 127.0.0.1:${port};" > "$CONFIG_DIR/mobile-stream/${client}.map"
    done < <(get_all_config_files)

    map_body="    ${public_host} 127.0.0.1:31999;"
    if [[ -d "$CONFIG_DIR/mobile-stream" ]]; then
        local latest=""
        for f in "$CONFIG_DIR/mobile-stream"/*.map; do
            [[ -f "$f" ]] || continue
            latest="$f"
        done
        if [[ -n "$latest" ]]; then
            map_body="    $(tr -d '\n' < "$latest" | sed 's/;$//');"
        fi
    fi

    cat > "$stream_conf" << NGINX_STREAM
# VLESS Manager — TLS passthrough (без WebSocket, v2rayTun LTE)
map \$ssl_preread_server_name \$vless_mobile_upstream {
    ${map_body}
    default 127.0.0.1:8443;
}

server {
    listen 443;
    ssl_preread on;
    proxy_pass \$vless_mobile_upstream;
    proxy_timeout 86400s;
    proxy_connect_timeout 10s;
}
NGINX_STREAM
}

# Зарегистрировать mobile-клиента в stream map
register_mobile_stream_client() {
    local client_name="$1"
    local internal_port="$2"
    local public_host

    public_host=$(get_public_host)
    echo "${public_host} 127.0.0.1:${internal_port};" > "$CONFIG_DIR/mobile-stream/${client_name}.map"
    rebuild_mobile_stream_map "$public_host"
    rm -f "$VLESS_NGINX_D/${client_name}.conf" 2>/dev/null || true

    if command -v nginx >/dev/null 2>&1 && nginx -t 2>/dev/null; then
        systemctl reload nginx 2>/dev/null || true
    fi
}

# Инструкция v2rayTun рядом с URL
write_v2raytun_mobile_notes() {
    local client_name="$1" vless_url="$2" hy2_url="${3:-}"
    [[ -n "$hy2_url" ]] && write_mobile_profile_bundle "$client_name" "$vless_url" "$hy2_url" && return 0
    echo "$vless_url" > "$CONFIG_DIR/urls/${client_name}.txt"
}

# Обновить inbound port в JSON-конфиге клиента
set_config_port() {
    local config_file="$1"
    local new_port="$2"

    CONFIG_FILE="$config_file" NEW_PORT="$new_port" python3 << 'PY'
import json, os, sys
path = os.environ["CONFIG_FILE"]
port = int(os.environ["NEW_PORT"])
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)
updated = False
for ib in cfg.get("inbounds", []):
    if "port" in ib:
        ib["port"] = port
        updated = True
        break
if not updated:
    sys.exit(1)
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

# Пересобрать URL/QR/bundle и запись в БД после смены порта
refresh_client_artifacts() {
    local client_name="$1"
    local config_file="$CLIENT_DIR/${client_name}.json"
    local uuid port vless_url qr_path=""

    uuid=$(extract_uuid_from_config "$config_file")
    port=$(extract_port_from_config "$config_file")
    [[ -n "$uuid" && -n "$port" ]] || return 1

    vless_url=$(build_vless_url_from_config "$config_file" "$client_name")
    echo "$vless_url" > "$CONFIG_DIR/urls/${client_name}.txt"
    local bundle_port="$port"
    is_mobile_443_config "$config_file" && bundle_port=$VLESS_MOBILE_PUBLIC_PORT
    write_singbox_client_bundle "$client_name" "$uuid" "$bundle_port" "$(get_public_host)"
    if generate_qr_code "$vless_url" "$client_name"; then
        qr_path="$QR_DIR/${client_name}.png"
    fi

    init_database
    sqlite3 "$CONFIG_DIR/clients.db" << EOF
INSERT OR REPLACE INTO clients (name, uuid, port, config_path, url, qr_path)
VALUES ('$client_name', '$uuid', $port, '$config_file', '$vless_url', '$qr_path');
EOF
}

# Исправить дублирующиеся порты у существующих клиентов
repair_duplicate_ports() {
    local interactive="${1:-1}"
    local -A port_owner=()
    local -A port_count=()
    local client port config_file keeper new_port fixed=0
    local -a to_fix=()

    if [[ "$interactive" == "1" ]]; then
        clear
        echo -e "${YELLOW}╔════════════════ ИСПРАВЛЕНИЕ ПОРТОВ ════════════════╗${NC}"
        echo -e "${BLUE}║ Поиск дубликатов портов среди клиентов...            ║${NC}"
    fi

    while IFS= read -r client; do
        [[ -z "$client" ]] && continue
        config_file="$CLIENT_DIR/${client}.json"
        port=$(extract_port_from_config "$config_file")
        [[ -n "$port" ]] || continue

        if [[ -z "${port_owner[$port]:-}" ]]; then
            port_owner["$port"]="$client"
            port_count["$port"]=1
        else
            port_count["$port"]=$((port_count["$port"] + 1))
            to_fix+=("$client|$port")
        fi
    done < <(get_all_config_files)

    if [[ ${#to_fix[@]} -eq 0 ]]; then
        if [[ "$interactive" == "1" ]]; then
            echo -e "${GREEN}║ Дубликатов портов не найдено.                        ║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
            read -p "Нажми Enter для продолжения..."
        else
            log "INFO" "Дубликатов портов не найдено"
        fi
        return 0
    fi

    if [[ "$interactive" == "1" ]]; then
        echo -e "${RED}║ Найдено конфликтов: ${#to_fix[@]}                                   ║${NC}"
    else
        log "WARN" "Найдено конфликтов портов: ${#to_fix[@]}"
    fi

    for entry in "${to_fix[@]}"; do
        client="${entry%%|*}"
        port="${entry##*|}"
        keeper="${port_owner[$port]}"
        new_port=$(find_free_port "$VLESS_PORT_MIN" "$VLESS_PORT_MAX")
        if [[ "$new_port" == "0" ]]; then
            log "ERROR" "Не удалось найти свободный порт для $client"
            continue
        fi

        if ! set_config_port "$CLIENT_DIR/${client}.json" "$new_port"; then
            log "ERROR" "Не удалось обновить порт в конфиге $client"
            continue
        fi

        refresh_client_artifacts "$client"
        /usr/local/bin/vless-servers restart "$client" 2>/dev/null || \
            /usr/local/bin/vless-servers start "$client" 2>/dev/null || true

        if [[ "$interactive" == "1" ]]; then
            echo -e "${GREEN}║ ✅ $client: $port → $new_port (оставлен $keeper на $port)${NC}"
        else
            log "INFO" "$client: порт $port → $new_port (оставлен $keeper на $port)"
        fi
        ((fixed++)) || true
    done

    if [[ "$interactive" == "1" ]]; then
        echo -e "${BLUE}║ Исправлено конфигов: $fixed                            ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
        read -p "Нажми Enter для продолжения..."
    else
        log "INFO" "Исправлено конфликтов портов: $fixed"
    fi
}

# Generate QR code
generate_qr_code() {
    local vless_url="$1"
    local client_name="$2"
    local qr_file="$QR_DIR/${client_name}.png"
    
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -s 8 -o "$qr_file" "$vless_url" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            return 0
        fi
    fi
    return 1
}

# Display QR code in terminal
display_qr_terminal() {
    local vless_url="$1"
    if command -v qrencode >/dev/null 2>&1; then
        echo -e "${GREEN}QR-код (сканируй для подключения):${NC}"
        qrencode -t ansiutf8 "$vless_url" 2>/dev/null || echo -e "${YELLOW}Не удалось отобразить QR-код в терминале${NC}"
    else
        echo -e "${YELLOW}qrencode не установлен${NC}"
    fi
}

# Добавить колонки в старую БД (установщик v1.2 создавал clients без config_path/url/qr_path)
migrate_clients_db() {
    local db="$CONFIG_DIR/clients.db"
    [[ -f "$db" ]] || return 0
    if ! sqlite3 "$db" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='clients';" 2>/dev/null | grep -q 1; then
        return 0
    fi
    local cols
    cols=$(sqlite3 "$db" "PRAGMA table_info(clients);" 2>/dev/null | cut -d'|' -f2)
    [[ -z "$cols" ]] && return 0
    echo "$cols" | grep -qx 'config_path' || sqlite3 "$db" "ALTER TABLE clients ADD COLUMN config_path TEXT;" 2>/dev/null
    echo "$cols" | grep -qx 'url' || sqlite3 "$db" "ALTER TABLE clients ADD COLUMN url TEXT;" 2>/dev/null
    echo "$cols" | grep -qx 'qr_path' || sqlite3 "$db" "ALTER TABLE clients ADD COLUMN qr_path TEXT;" 2>/dev/null
    echo "$cols" | grep -qx 'status' || sqlite3 "$db" "ALTER TABLE clients ADD COLUMN status TEXT DEFAULT 'active';" 2>/dev/null
}

# Initialize database
init_database() {
    if [[ ! -f "$CONFIG_DIR/clients.db" ]]; then
        sqlite3 "$CONFIG_DIR/clients.db" << 'SQL'
CREATE TABLE IF NOT EXISTS clients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    uuid TEXT NOT NULL,
    port INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT DEFAULT 'active',
    config_path TEXT,
    url TEXT,
    qr_path TEXT
);
SQL
        log "INFO" "База данных клиентов инициализирована"
    fi
    migrate_clients_db
}

# Входящий TCP на порты VLESS (иначе с клиента: i/o timeout к IP:порт)
# При активном UFW правила нужно добавлять через «ufw allow», иначе ufw reload затирает ручной iptables -I INPUT
setup_vless_input_firewall() {
    local vmin=$VLESS_PORT_MIN vmax=$VLESS_PORT_MAX

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qiE 'Status:\s+active'; then
        if ufw status 2>/dev/null | grep -qE "${vmin}:${vmax}/tcp|${vmin}:${vmax}"; then
            log "INFO" "ufw: порты ${vmin}-${vmax}/tcp уже разрешены"
        else
            ufw allow "${vmin}:${vmax}/tcp" comment 'vless-manager' 2>/dev/null || \
            ufw allow "${vmin}:${vmax}/tcp" 2>/dev/null || true
            log "INFO" "ufw: разрешён TCP ${vmin}-${vmax} (VLESS). Проверка: ufw status numbered"
        fi
        return 0
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        return 0
    fi
    if ! iptables -C INPUT -p tcp --dport "${vmin}:${vmax}" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT 1 -p tcp --dport "${vmin}:${vmax}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "${vmin}:${vmax}" -j ACCEPT 2>/dev/null || true
        log "INFO" "iptables INPUT: TCP ${vmin}-${vmax} (VLESS), UFW выключен"
    fi
    if [[ -d /etc/iptables ]] && [[ -w /etc/iptables/rules.v4 ]]; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}

# Setup enhanced iptables for all interfaces
setup_enhanced_iptables() {
    echo -e "${YELLOW}Настройка расширенных правил iptables...${NC}"
    
    setup_vless_input_firewall
    
    # Основные правила
    iptables -I FORWARD -j ACCEPT 2>/dev/null || true
    
    # Получаем все активные интерфейсы
    local interfaces=()
    while IFS= read -r interface; do
        if [[ -n "$interface" && "$interface" != "lo" ]]; then
            interfaces+=("$interface")
        fi
    done < <(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$')
    
    # Настраиваем MASQUERADE для всех интерфейсов
    for interface in "${interfaces[@]}"; do
        iptables -t nat -C POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null
        echo -e "${GREEN}✅ Настроен MASQUERADE для интерфейса: $interface${NC}"
    done
    
    # Включаем IP forwarding для всех интерфейсов
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Дополнительные правила для VPN интерфейсов
    for vpn_interface in tun0 tap0 ppp0; do
        if ip link show "$vpn_interface" >/dev/null 2>&1; then
            iptables -t nat -C POSTROUTING -o "$vpn_interface" -j MASQUERADE 2>/dev/null || \
            iptables -t nat -A POSTROUTING -o "$vpn_interface" -j MASQUERADE 2>/dev/null
            echo -e "${CYAN}✅ Настроен доступ к VPN интерфейсу: $vpn_interface${NC}"
        fi
    done
    
    log "INFO" "Расширенные правила iptables настроены для всех интерфейсов"
}

# Get all existing configs from filesystem
get_all_config_files() {
    if [[ -d "$CLIENT_DIR" ]]; then
        find "$CLIENT_DIR" -name "*.json" -exec basename {} .json \; 2>/dev/null | sort
    fi
}

# Extract UUID from config file
extract_uuid_from_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        grep -o '"id": "[^"]*"' "$config_file" 2>/dev/null | cut -d'"' -f4 | head -1
    fi
}

# Extract port from config file
extract_port_from_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        grep -o '"port": [0-9]*' "$config_file" 2>/dev/null | cut -d' ' -f2 | head -1
    fi
}

# TLS: самоподпись на клиента (IP в CN) или общий Let's Encrypt из $TLS_ENV
generate_client_tls_cert() {
    local server_ip="$1"
    local client_name="$2"
    load_tls_env
    if tls_uses_letsencrypt; then
        echo -e "${GREEN}TLS: используется Let's Encrypt (${PUBLIC_HOST})${NC}"
        return 0
    fi
    local key="$CERT_DIR/${client_name}.key"
    local crt="$CERT_DIR/${client_name}.crt"
    mkdir -p "$CERT_DIR"
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${RED}Нужен openssl (apt-get install -y openssl)${NC}"
        return 1
    fi
    if ! openssl req -x509 -nodes -newkey rsa:4096 -keyout "$key" -out "$crt" -days 8250 \
        -subj "/CN=${server_ip}" \
        -addext "subjectAltName=IP:${server_ip}" 2>/dev/null; then
        openssl req -x509 -nodes -newkey rsa:4096 -keyout "$key" -out "$crt" -days 8250 \
            -subj "/CN=${server_ip}"
    fi
    chmod 600 "$key" 2>/dev/null || true
    chmod 644 "$crt" 2>/dev/null || true
    if [[ ! -f "$crt" || ! -f "$key" ]]; then
        echo -e "${RED}Не удалось создать TLS-сертификат${NC}"
        return 1
    fi
    return 0
}

# Извлечь WS path из JSON конфига
extract_ws_path_from_config() {
    local config_file="$1"
    local path
    path=$(grep -o '"path": "[^"]*"' "$config_file" 2>/dev/null | head -1 | cut -d'"' -f4)
    echo "${path:-$VLESS_WS_PATH}"
}

# Subscription URL: TCP+TLS | WS+TLS | mobile-443 (nginx)
build_vless_url_from_config() {
    local config_file="$1"
    local client_name="$2"
    local uuid port connect_host sni insecure_q path_enc ws_path
    uuid=$(extract_uuid_from_config "$config_file")
    port=$(extract_port_from_config "$config_file")
    if [[ -z "$uuid" || -z "$port" ]]; then
        return 1
    fi
    load_tls_env
    connect_host=$(get_public_host)
    sni="$connect_host"
    if tls_uses_letsencrypt; then
        insecure_q="allowInsecure=0"
    else
        insecure_q="allowInsecure=1"
    fi
    if is_mobile_reality_client "$client_name"; then
        build_mobile_reality_url "$client_name" "$uuid"
        return 0
    fi
    if is_mobile_443_config "$config_file"; then
        port=$VLESS_MOBILE_PUBLIC_PORT
        echo "vless://${uuid}@${connect_host}:${port}?encryption=none&security=tls&sni=${sni}&fp=chrome&type=tcp&${insecure_q}#${client_name}"
    elif grep -qE '"network":\s*"ws"' "$config_file" 2>/dev/null; then
        ws_path=$(extract_ws_path_from_config "$config_file")
        path_enc=$(printf '%s' "$ws_path" | sed 's|/|%2F|g')
        echo "vless://${uuid}@${connect_host}:${port}?encryption=none&security=tls&sni=${sni}&fp=chrome&type=ws&host=${connect_host}&path=${path_enc}&${insecure_q}#${client_name}"
    elif grep -qE '"network":\s*"tcp"' "$config_file" 2>/dev/null && grep -q '"security": "tls"' "$config_file" 2>/dev/null; then
        echo "vless://${uuid}@${connect_host}:${port}?encryption=none&security=tls&sni=${sni}&fp=chrome&type=tcp&${insecure_q}#${client_name}"
    else
        echo "vless://${uuid}@${connect_host}:${port}?encryption=none&security=none&type=tcp#${client_name}"
    fi
}

# Готовый профиль sing-box / NekoBox: legacy DNS (tcp:// через прокси), TLS + xudp; Instagram/приложения — без DoH-шума
write_singbox_client_bundle() {
    local client_name="$1" uuid="$2" port="$3" server_ip="$4"
    local out="$BUNDLE_DIR/${client_name}.sing-box.json"
    local cfg="$CLIENT_DIR/${client_name}.json"
    mkdir -p "$BUNDLE_DIR"
    if ! command -v python3 >/dev/null 2>&1; then
        log "WARN" "python3 не найден — профиль sing-box не создан"
        return 1
    fi
    CLIENT_NAME="$client_name" UUID="$uuid" PORT="$port" SERVER_IP="$server_ip" CFG_PATH="$cfg" OUT_PATH="$out" python3 << 'PY'
import json, os, re

name = os.environ["CLIENT_NAME"]
uuid = os.environ["UUID"]
port = int(os.environ["PORT"])
sip = os.environ["SERVER_IP"]
cfg_path = os.environ["CFG_PATH"]
out_path = os.environ["OUT_PATH"]

raw = ""
if os.path.isfile(cfg_path):
    with open(cfg_path, encoding="utf-8") as f:
        raw = f.read()

use_tls = bool(re.search(r'"network"\s*:\s*"ws"', raw)) or (
    bool(re.search(r'"network"\s*:\s*"tcp"', raw)) and bool(re.search(r'"security"\s*:\s*"tls"', raw))
)
ws = bool(re.search(r'"network"\s*:\s*"ws"', raw))
ws_path = "/vless"
if ws:
    m = re.search(r'"path"\s*:\s*"([^"]*)"', raw)
    if m:
        ws_path = m.group(1)

proxy = {
    "type": "vless",
    "tag": "proxy",
    "server": sip,
    "server_port": port,
    "uuid": uuid,
    "packet_encoding": "xudp",
}
if use_tls:
    proxy["tls"] = {
        "enabled": True,
        "server_name": sip,
        "insecure": True,
        "alpn": ["http/1.1"],
    }

if ws:
    proxy["transport"] = {
        "type": "ws",
        "path": ws_path,
        "headers": {"Host": sip},
    }

doc = {
    "log": {"level": "warning"},
    "dns": {
        "servers": [
            {
                "tag": "dns-remote",
                "address": "tcp://8.8.8.8",
                "detour": "proxy",
            },
            {"tag": "local", "address": "local"},
        ],
        "final": "dns-remote",
        "strategy": "prefer_ipv4",
        "independent_cache": True,
    },
    "inbounds": [
        {
            "type": "mixed",
            "tag": "mixed-in",
            "listen": "127.0.0.1",
            "listen_port": 2080,
            "sniff": True,
            "sniff_override_destination": True,
        }
    ],
    "outbounds": [{"type": "direct", "tag": "direct"}, proxy],
    "route": {"final": "proxy", "auto_detect_interface": True},
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
PY
    if [[ $? -ne 0 ]]; then
        log "WARN" "Не удалось записать sing-box профиль: $out"
        return 1
    fi
    python3 -c "import json; json.load(open('$out'))" 2>/dev/null || log "WARN" "Проверьте JSON: $out"
}

# Rebuild database from existing configs
rebuild_database() {
    clear
    echo -e "${YELLOW}╔══════════════════ ВОССТАНОВЛЕНИЕ БД ══════════════════╗${NC}"
    echo -e "${BLUE}║ Сканируем существующие конфиги...                   ║${NC}"
    
    init_database
    
    # Очищаем базу
    sqlite3 "$CONFIG_DIR/clients.db" "DELETE FROM clients;" 2>/dev/null
    
    local count=0
    while IFS= read -r client_name; do
        if [[ -n "$client_name" ]]; then
            local config_file="$CLIENT_DIR/${client_name}.json"
            local uuid=$(extract_uuid_from_config "$config_file")
            local port=$(extract_port_from_config "$config_file")
            
            if [[ -n "$uuid" && -n "$port" ]]; then
                # Создаем URL
                local vless_url
                vless_url=$(build_vless_url_from_config "$config_file" "$client_name")
                
                # Сохраняем URL в файл
                echo "$vless_url" > "$CONFIG_DIR/urls/${client_name}.txt"
                write_singbox_client_bundle "$client_name" "$uuid" "$port" "$(get_public_host)"
                
                # Генерируем QR-код
                local qr_path=""
                if generate_qr_code "$vless_url" "$client_name"; then
                    qr_path="$QR_DIR/${client_name}.png"
                fi
                
                # Добавляем в базу данных
                sqlite3 "$CONFIG_DIR/clients.db" << EOF
INSERT OR REPLACE INTO clients (name, uuid, port, config_path, url, qr_path) 
VALUES ('$client_name', '$uuid', $port, '$config_file', '$vless_url', '$qr_path');
EOF
                ((count++))
                echo -e "${GREEN}║ ✅ $client_name (UUID: ${uuid:0:8}..., Port: $port)${NC}"
            fi
        fi
    done < <(get_all_config_files)
    
    echo -e "${BLUE}║                                                      ║${NC}"
    echo -e "${GREEN}║ Обработано конфигов: $count                           ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    
    log "INFO" "База данных восстановлена с $count конфигами"
    read -p "Нажми Enter для продолжения..."
}

# List configs with enhanced display
list_configs() {
    clear
    echo -e "${PURPLE}╔══════════════════ СУЩЕСТВУЮЩИЕ КОНФИГИ ══════════════════╗${NC}"
    
    local configs=()
    local count=0
    
    # Сначала пробуем получить из базы данных
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        while IFS='|' read -r name uuid port created; do
            if [[ -n "$name" ]]; then
                configs+=("$name")
                ((count++))
                echo -e "${GREEN}║ $count) $name${NC}"
                echo -e "${CYAN}║    UUID: $uuid${NC}"
                echo -e "${BLUE}║    Порт: $port | Создан: $created${NC}"
                echo -e "${PURPLE}║${NC}"
            fi
        done < <(sqlite3 "$CONFIG_DIR/clients.db" "SELECT name, uuid, port, created_at FROM clients ORDER BY created_at DESC;" 2>/dev/null)
    fi
    
    # Если в базе ничего нет, показываем из файловой системы
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}║ База данных пуста. Показываю конфиги из файлов:        ║${NC}"
        echo -e "${PURPLE}║${NC}"
        
        while IFS= read -r client_name; do
            if [[ -n "$client_name" ]]; then
                configs+=("$client_name")
                ((count++))
                local config_file="$CLIENT_DIR/${client_name}.json"
                local uuid=$(extract_uuid_from_config "$config_file")
                local port=$(extract_port_from_config "$config_file")
                
                echo -e "${GREEN}║ $count) $client_name${NC}"
                echo -e "${CYAN}║    UUID: ${uuid:-'неизвестно'}${NC}"
                echo -e "${BLUE}║    Порт: ${port:-'неизвестно'}${NC}"
                echo -e "${PURPLE}║${NC}"
            fi
        done < <(get_all_config_files)
        
        if [[ $count -gt 0 ]]; then
            echo -e "${YELLOW}║ Используйте пункт 9 для восстановления базы данных    ║${NC}"
        fi
    fi
    
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}║ Конфиги не найдены. Создайте первый конфиг!          ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
        read -p "Нажми Enter для продолжения..."
        return
    fi
    
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Выберите номер конфига для просмотра QR-кода (1-$count) или 0 для возврата: ${NC}"
    read -r choice
    
    if [[ "$choice" == "0" ]]; then
        return
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le $count ]]; then
        local selected_client="${configs[$((choice - 1))]}"
        show_client_details "$selected_client"
    else
        echo -e "${RED}Неверный номер!${NC}"
        sleep 2
    fi
}

# Show client details with QR code
show_client_details() {
    local client_name="$1"
    clear
    echo -e "${PURPLE}╔══════════════════ ДЕТАЛИ КЛИЕНТА ══════════════════╗${NC}"
    echo -e "${GREEN}║ Клиент: $client_name${NC}"
    echo -e "${PURPLE}║${NC}"
    
    # Получаем данные из базы данных или файлов
    local uuid port vless_url
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        local db_data=$(sqlite3 "$CONFIG_DIR/clients.db" "SELECT uuid, port, url FROM clients WHERE name='$client_name';" 2>/dev/null)
        if [[ -n "$db_data" ]]; then
            uuid=$(echo "$db_data" | cut -d'|' -f1)
            port=$(echo "$db_data" | cut -d'|' -f2)
            vless_url=$(echo "$db_data" | cut -d'|' -f3)
        fi
    fi
    
    # URL из файла подписки (актуальнее БД)
    if [[ -f "$CONFIG_DIR/urls/${client_name}.txt" ]]; then
        vless_url=$(cat "$CONFIG_DIR/urls/${client_name}.txt")
    fi
    local config_file="$CLIENT_DIR/${client_name}.json"
    if [[ -z "$uuid" && -f "$config_file" ]]; then
        uuid=$(extract_uuid_from_config "$config_file")
        port=$(extract_port_from_config "$config_file")
    fi
    if [[ -z "$vless_url" && -f "$config_file" ]]; then
        vless_url=$(build_vless_url_from_config "$config_file" "$client_name")
    fi
    
    if [[ -n "$uuid" && -n "$port" ]]; then
        echo -e "${CYAN}║ UUID: $uuid${NC}"
        echo -e "${BLUE}║ Порт: $port${NC}"
        echo -e "${PURPLE}║${NC}"
        echo -e "${YELLOW}║ VLESS URL:${NC}"
        echo -e "${WHITE}║ $vless_url${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
        echo
        
        # Показываем QR-код в терминале
        display_qr_terminal "$vless_url"
        echo
        
        # Информация о сохраненном QR-коде
        local qr_file="$QR_DIR/${client_name}.png"
        if [[ -f "$qr_file" ]]; then
            echo -e "${GREEN}💾 QR-код сохранен: $qr_file${NC}"
        else
            echo -e "${YELLOW}🔄 Генерирую QR-код...${NC}"
            if generate_qr_code "$vless_url" "$client_name"; then
                echo -e "${GREEN}💾 QR-код создан: $qr_file${NC}"
            fi
        fi
    else
        echo -e "${RED}║ Ошибка: не удалось извлечь данные конфига${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
    fi
    
    echo
    read -p "Нажми Enter для продолжения..."
}

# Удалить клиента (Wi‑Fi json, mobile REALITY uuid, URL, QR) — для panel/cli
delete_vless_client() {
    local client_name="$1"
    local do_wifi="${2:-1}"
    local do_mobile="${3:-1}"
    local mob_name="$client_name"

    [[ -n "$client_name" ]] || return 1
    if [[ "$do_wifi" == "1" && "$do_mobile" == "1" ]]; then
        mob_name="${client_name}-mob"
    elif [[ "$do_mobile" == "1" && "$do_wifi" != "1" ]]; then
        mob_name="$client_name"
    fi

    if [[ "$do_wifi" == "1" ]]; then
        /usr/local/bin/vless-servers stop "$client_name" 2>/dev/null || true
        rm -f "$CLIENT_DIR/${client_name}.json"
        rm -f "$CONFIG_DIR/urls/${client_name}.txt"
        rm -f "$QR_DIR/${client_name}.png"
        if ! tls_uses_letsencrypt; then
            rm -f "$CERT_DIR/${client_name}.crt" "$CERT_DIR/${client_name}.key"
        fi
        rm -f "$BUNDLE_DIR/${client_name}.sing-box.json"
        if [[ -f "$CONFIG_DIR/clients.db" ]]; then
            sqlite3 "$CONFIG_DIR/clients.db" "DELETE FROM clients WHERE name='$client_name';" 2>/dev/null || true
        fi
    fi

    if [[ "$do_mobile" == "1" ]]; then
        rm -f "$MOBILE_REALITY_DIR/${mob_name}.uuid"
        rm -f "$CONFIG_DIR/urls/${mob_name}.txt"
        rm -f "$CONFIG_DIR/urls/${mob_name}-hy2.txt"
        rm -f "$CONFIG_DIR/urls/${mob_name}-v2raytun.txt"
        rm -f "$CONFIG_DIR/urls/${client_name}-hy2.txt"
        rm -f "$CONFIG_DIR/urls/${client_name}.txt"
        rm -f "$QR_DIR/${mob_name}.png"
        rm -f "$QR_DIR/${client_name}.png"
        if [[ -f "$CONFIG_DIR/clients.db" ]]; then
            sqlite3 "$CONFIG_DIR/clients.db" "DELETE FROM clients WHERE name='$mob_name';" 2>/dev/null || true
            sqlite3 "$CONFIG_DIR/clients.db" "DELETE FROM clients WHERE name='$client_name';" 2>/dev/null || true
        fi
        if [[ -f "$REALITY_CONFIG_FILE" ]] && command -v python3 >/dev/null 2>&1; then
            load_reality_env
            rebuild_mobile_reality_hub 2>/dev/null || true
            restart_xray_reality 2>/dev/null || true
        fi
    fi

    log "INFO" "Удалён клиент: $client_name (wifi=$do_wifi mobile=$do_mobile)"
    return 0
}

# Delete config menu (enhanced)
delete_config_menu() {
    clear
    echo -e "${RED}╔══════════════════ УДАЛЕНИЕ КОНФИГА ══════════════════╗${NC}"
    
    # Собираем список всех доступных конфигов
    local configs=()
    
    # Сначала из базы данных
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        while IFS='|' read -r name; do
            if [[ -n "$name" ]]; then
                configs+=("$name")
            fi
        done < <(sqlite3 "$CONFIG_DIR/clients.db" "SELECT name FROM clients ORDER BY name;" 2>/dev/null)
    fi
    
    # Если база пуста, берем из файловой системы
    if [[ ${#configs[@]} -eq 0 ]]; then
        while IFS= read -r client_name; do
            if [[ -n "$client_name" ]]; then
                configs+=("$client_name")
            fi
        done < <(get_all_config_files)
    fi
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo -e "${YELLOW}║ Нет конфигов для удаления                           ║${NC}"
        echo -e "${RED}╚═════════════════════════════════════════════════════╝${NC}"
        read -p "Нажми Enter для продолжения..."
        return
    fi
    
    echo -e "${YELLOW}║ Доступные конфиги:                                  ║${NC}"
    for i in "${!configs[@]}"; do
        local num=$((i + 1))
        echo -e "${GREEN}║ $num) ${configs[$i]}${NC}"
    done
    
    echo -e "${RED}╚═════════════════════════════════════════════════════╝${NC}"
    echo -n "Введи номер конфига для удаления (1-${#configs[@]}): "
    read -r choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#configs[@]} ]]; then
        echo -e "${RED}Неверный номер!${NC}"
        read -p "Нажми Enter для продолжения..."
        return
    fi
    
    local client_name="${configs[$((choice - 1))]}"
    
    echo -e "${YELLOW}Точно удалить конфиг для '$client_name'? [y/N]${NC}"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local _w=1 _m=0
        if is_mobile_reality_client "$client_name"; then
            _m=1
            _w=0
        fi
        delete_vless_client "$client_name" "$_w" "$_m"
        echo -e "${GREEN}Конфиг для '$client_name' успешно удален (включая QR-код)!${NC}"
    else
        echo -e "${YELLOW}Отменено.${NC}"
    fi
    
    read -p "Нажми Enter для продолжения..."
}

# Show active connections (enhanced)
show_active_connections() {
    clear
    echo -e "${BLUE}╔══════════════════ АКТИВНЫЕ ПОДКЛЮЧЕНИЯ ══════════════════╗${NC}"
    
    local has_connections=false
    
    if pgrep -f "xray.*run.*config" >/dev/null; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                has_connections=true
                # Правильно извлекаем PID (второе поле в ps aux)
                local pid=$(echo "$line" | awk '{print $2}')
                local config_file=$(echo "$line" | grep -o '/etc/vless-manager/clients/[^[:space:]]*\.json')
                if [[ -n "$config_file" ]]; then
                    local client_name=$(basename "$config_file" .json)
                    local port=$(extract_port_from_config "$config_file")
                    echo -e "${GREEN}║ Клиент: $client_name${NC}"
                    echo -e "${CYAN}║ PID: $pid | Порт: $port${NC}"
                    
                    # Показываем доступные сетевые интерфейсы
                    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | tr '\n' ', ')
                    interfaces=${interfaces%, }  # Убираем последнюю запятую
                    echo -e "${YELLOW}║ Доступные интерфейсы: $interfaces${NC}"
                    echo -e "${BLUE}║${NC}"
                fi
            fi
        done < <(ps aux | grep "xray.*run.*config" | grep -v grep)
    fi
    
    if [[ "$has_connections" == false ]]; then
        echo -e "${YELLOW}║ Нет активных подключений                            ║${NC}"
    fi
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    read -p "Нажми Enter для продолжения..."
}

# Setup OpenVPN integration (enhanced)
setup_openvpn_integration() {
    clear
    echo -e "${PURPLE}╔══════════════════ OPENVPN ИНТЕГРАЦИЯ ══════════════════╗${NC}"
    
    # Проверяем наличие OpenVPN
    if command -v openvpn >/dev/null 2>&1; then
        echo -e "${GREEN}║ OpenVPN найден в системе                             ║${NC}"
        
        # Проверяем активные VPN интерфейсы
        local vpn_interfaces=()
        for interface in tun0 tun1 tap0 tap1 ppp0; do
            if ip link show "$interface" >/dev/null 2>&1; then
                vpn_interfaces+=("$interface")
            fi
        done
        
        if [[ ${#vpn_interfaces[@]} -gt 0 ]]; then
            echo -e "${CYAN}║ Найдены VPN интерфейсы: ${vpn_interfaces[*]}${NC}"
            echo -e "${GREEN}║ Настраиваю маршрутизацию через VPN...                ║${NC}"
            
            # Настраиваем правила для VPN интерфейсов
            for vpn_int in "${vpn_interfaces[@]}"; do
                iptables -t nat -C POSTROUTING -o "$vpn_int" -j MASQUERADE 2>/dev/null || \
                iptables -t nat -A POSTROUTING -o "$vpn_int" -j MASQUERADE 2>/dev/null
                echo -e "${GREEN}║ ✅ Настроен доступ через $vpn_int                      ║${NC}"
            done
            
            echo -e "${BLUE}║ VLESS клиенты теперь имеют доступ к VPN!             ║${NC}"
        else
            echo -e "${YELLOW}║ VPN интерфейсы не найдены                           ║${NC}"
            echo -e "${CYAN}║ Запустите OpenVPN и повторите попытку                ║${NC}"
        fi
    else
        echo -e "${YELLOW}║ OpenVPN не установлен                               ║${NC}"
        echo -e "${CYAN}║ Установите OpenVPN для интеграции                   ║${NC}"
    fi
    
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "Нажми Enter для продолжения..."
}

# System monitoring (enhanced)
show_system_monitoring() {
    clear
    echo -e "${GREEN}╔══════════════════ МОНИТОРИНГ СИСТЕМЫ ══════════════════╗${NC}"
    echo -e "${CYAN}║ Загрузка CPU:${NC}"
    uptime | awk -F'load average:' '{print "║ "$2}' | head -1
    echo -e "${CYAN}║ Использование памяти:${NC}"
    free -h | grep Mem | awk '{print "║ Использовано: "$3" из "$2" ("int($3/$2*100)"%)"}' 
    echo -e "${CYAN}║ Использование диска:${NC}"
    df -h / | tail -1 | awk '{print "║ Использовано: "$3" из "$2" ("$5")"}'
    echo -e "${CYAN}║ Активные VLESS соединения:${NC}"
    local vless_count=$(pgrep -cf "xray.*run.*config")
    echo -e "║ Активных серверов: $vless_count"
    
    echo -e "${CYAN}║ Сетевые интерфейсы:${NC}"
    while IFS= read -r interface; do
        if [[ -n "$interface" && "$interface" != "lo" ]]; then
            local ip=$(ip addr show "$interface" | grep -oP 'inet \K[^/]+' | head -1)
            if [[ -n "$ip" ]]; then
                echo -e "║ $interface: $ip"
            else
                echo -e "║ $interface: не подключен"
            fi
        fi
    done < <(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$')
    
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "Нажми Enter для продолжения..."
}

# Show logs menu
show_logs_menu() {
    clear
    echo -e "${YELLOW}╔══════════════════ ПРОСМОТР ЛОГОВ ══════════════════╗${NC}"
    echo -e "${BLUE}║ 1) Логи VLESS Manager                             ║${NC}"
    echo -e "${BLUE}║ 2) Логи системы                                   ║${NC}"
    echo -e "${BLUE}║ 3) Логи конкретного клиента                       ║${NC}"
    echo -e "${BLUE}║ 0) Назад                                          ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════╝${NC}"
    echo -n "Выбери опцию: "
    read -r choice
    
    case "$choice" in
        1)
            if [[ -f "$LOG_DIR/vless-manager.log" ]]; then
                echo -e "${GREEN}Последние 50 строк лога VLESS Manager:${NC}"
                tail -50 "$LOG_DIR/vless-manager.log"
            else
                echo -e "${YELLOW}Лог файл не найден${NC}"
            fi
            ;;
        2)
            echo -e "${GREEN}Системные логи (последние 20 строк):${NC}"
            journalctl --no-pager -n 20
            ;;
        3)
            echo -n "Введи имя клиента: "
            read -r client_name
            if [[ -f "$LOG_DIR/vless-${client_name}.log" ]]; then
                echo -e "${GREEN}Логи для $client_name:${NC}"
                tail -30 "$LOG_DIR/vless-${client_name}.log"
            else
                echo -e "${YELLOW}Лог для $client_name не найден${NC}"
            fi
            ;;
        0) return ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac
    read -p "Нажми Enter для продолжения..."
}

# System settings menu (enhanced)
system_settings_menu() {
    clear
    echo -e "${PURPLE}╔══════════════════ НАСТРОЙКИ СИСТЕМЫ ══════════════════╗${NC}"
    echo -e "${BLUE}║ 1) Проверить iptables правила                        ║${NC}"
    echo -e "${BLUE}║ 2) Восстановить iptables правила (все интерфейсы)    ║${NC}"
    echo -e "${BLUE}║ 3) Проверить статус IP forwarding                    ║${NC}"
    echo -e "${BLUE}║ 4) Включить IP forwarding                            ║${NC}"
    echo -e "${BLUE}║ 5) Показать сетевые интерфейсы                       ║${NC}"
    echo -e "${BLUE}║ 6) Настроить доступ к VPN интерфейсам                ║${NC}"
    echo -e "${BLUE}║ 7) Исправить дублирующиеся порты                     ║${NC}"
    echo -e "${BLUE}║ 0) Назад                                             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════╝${NC}"
    echo -n "Выбери опцию: "
    read -r choice
    
    case "$choice" in
        1)
            echo -e "${GREEN}Текущие iptables правила:${NC}"
            iptables -L -n --line-numbers
            iptables -t nat -L -n --line-numbers
            ;;
        2)
            echo -e "${YELLOW}Восстанавливаю правила для всех интерфейсов...${NC}"
            setup_enhanced_iptables
            echo -e "${GREEN}Правила восстановлены для всех интерфейсов${NC}"
            ;;
        3)
            local forward_status=$(cat /proc/sys/net/ipv4/ip_forward)
            if [[ "$forward_status" == "1" ]]; then
                echo -e "${GREEN}IP forwarding включен${NC}"
            else
                echo -e "${RED}IP forwarding выключен${NC}"
            fi
            ;;
        4)
            echo 1 > /proc/sys/net/ipv4/ip_forward
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
            echo -e "${GREEN}IP forwarding включен${NC}"
            ;;
        5)
            echo -e "${GREEN}Сетевые интерфейсы:${NC}"
            ip addr show
            ;;
        6)
            echo -e "${YELLOW}Настройка доступа к VPN интерфейсам...${NC}"
            setup_openvpn_integration
            ;;
        7)
            repair_duplicate_ports 1
            return
            ;;
        0) return ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac
    read -p "Нажми Enter для продолжения..."
}

# Create VLESS config (enhanced with QR)
create_vless_config() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        echo -e "${RED}Имя клиента не может быть пустым!${NC}"
        return 1
    fi
    
    if [[ -f "$CLIENT_DIR/${client_name}.json" ]]; then
        echo -e "${YELLOW}Конфиг для $client_name уже существует!${NC}"
        return 1
    fi
    
    local uuid port server_ip
    uuid=$(generate_uuid)
    port=$(find_free_port "$VLESS_PORT_MIN" "$VLESS_PORT_MAX")
    server_ip=$(get_server_ip)
    
    if [[ "$port" == "0" ]]; then
        echo -e "${RED}Не удалось найти свободный порт!${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Генерация TLS для VLESS поверх TCP (стабильнее WebSocket в клиентах)...${NC}"
    if ! generate_client_tls_cert "$server_ip" "$client_name"; then
        return 1
    fi
    
    local cert_file key_file
    load_tls_env
    if tls_uses_letsencrypt; then
        cert_file="$LE_FULLCHAIN"
        key_file="$LE_PRIVKEY"
    else
        cert_file="$CERT_DIR/${client_name}.crt"
        key_file="$CERT_DIR/${client_name}.key"
    fi
    
    local public_host
    public_host=$(get_public_host)
    
    # VLESS + TCP + TLS + DNS/IPv4/sniffing (без WebSocket — меньше сбоев в v2rayNG/Nekoray)
    cat > "$CLIENT_DIR/${client_name}.json" << EOF
{
  "log": {
    "loglevel": "info"
  },
  "dns": {
    "servers": [
      "8.8.8.8",
      "1.1.1.1"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "email": "${client_name}@vless.local"
          }
        ],
        "decryption": "none",
        "packetEncoding": "xudp"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$cert_file",
              "keyFile": "$key_file"
            }
          ],
          "minVersion": "1.2",
          "maxVersion": "1.3",
          "alpn": ["http/1.1"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "tag": "direct"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
    
    local vless_url
    vless_url=$(build_vless_url_from_config "$CLIENT_DIR/${client_name}.json" "$client_name")
    echo "$vless_url" > "$CONFIG_DIR/urls/${client_name}.txt"
    write_singbox_client_bundle "$client_name" "$uuid" "$port" "$public_host"
    
    # Generate QR code
    local qr_path=""
    echo -e "${YELLOW}🔄 Генерирую QR-код...${NC}"
    if generate_qr_code "$vless_url" "$client_name"; then
        qr_path="$QR_DIR/${client_name}.png"
        echo -e "${GREEN}✅ QR-код создан: $qr_path${NC}"
    fi
    
    # Save to database
    init_database
    sqlite3 "$CONFIG_DIR/clients.db" << EOF
INSERT INTO clients (name, uuid, port, config_path, url, qr_path) 
VALUES ('$client_name', '$uuid', $port, '$CLIENT_DIR/${client_name}.json', '$vless_url', '$qr_path');
EOF
    
    # Setup enhanced networking
    setup_enhanced_iptables
    
    # Start server (outside panel cgroup when started via systemd-run)
    if ! /usr/local/bin/vless-servers start "$client_name"; then
        echo -e "${RED}Не удалось запустить Xray для $client_name${NC}" >&2
        return 1
    fi
    local started_port
    started_port=$(extract_port_from_config "$CLIENT_DIR/${client_name}.json")
    if [[ -n "$started_port" ]] && command -v ss >/dev/null 2>&1; then
        if ! ss -H -tln "sport = :$started_port" 2>/dev/null | grep -q .; then
            echo -e "${RED}Порт $started_port не слушается после запуска${NC}" >&2
            return 1
        fi
    fi
    
    # Show result
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    КОНФИГ СОЗДАН УСПЕШНО!                      ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║ Клиент: $client_name${NC}"
    echo -e "${CYAN}║ UUID: $uuid${NC}"
    echo -e "${CYAN}║ Порт: $port${NC}"
    echo -e "${CYAN}║ Публичный IP: $server_ip | Адрес в ссылке: $public_host${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║ VLESS URL:${NC}"
    echo -e "${WHITE}║ $vless_url${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║ Конфиг: $CLIENT_DIR/${client_name}.json${NC}"
    echo -e "${BLUE}║ URL: $CONFIG_DIR/urls/${client_name}.txt${NC}"
    if [[ -n "$qr_path" ]]; then
        echo -e "${BLUE}║ QR-код: $qr_path${NC}"
    fi
    echo -e "${BLUE}║ NekoBox/sing-box (с DNS «из коробки»): $BUNDLE_DIR/${client_name}.sing-box.json${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Подсказка: если при включении VPN «пропадает весь интернет» — в клиенте включите DNS${NC}"
    echo -e "${YELLOW}через прокси (remote/8.8.8.8), на Android отключите Private DNS; адрес в ссылке = $server_ip${NC}"
    echo -e "${YELLOW}Импорт в NekoBox: «Из файла» → $BUNDLE_DIR/${client_name}.sing-box.json (или QR URL). Шифрование: см. templates/ШИФРОВАНИЕ.txt${NC}"
    echo -e "${YELLOW}Если таймаут до $server_ip:$port — откройте TCP $port в панели облака; см. templates/FIREWALL-HINT.txt${NC}"
    
    # Display QR in terminal
    echo
    display_qr_terminal "$vless_url"
    
    log "INFO" "Создан конфиг с QR-кодом для клиента $client_name (UUID: $uuid, Port: $port)"
}

# Записать mobile inbound: 127.0.0.1 + TCP + TLS (nginx stream passthrough :443)
write_mobile_xray_config() {
    local client_name="$1" uuid="$2" internal_port="$3"
    local cert_file key_file public_host

    load_tls_env
    public_host=$(get_public_host)
    if tls_uses_letsencrypt; then
        cert_file="$LE_FULLCHAIN"
        key_file="$LE_PRIVKEY"
    else
        cert_file="$CERT_DIR/${client_name}.crt"
        key_file="$CERT_DIR/${client_name}.key"
    fi

    cat > "$CLIENT_DIR/${client_name}.json" << EOF
{
  "log": {
    "loglevel": "info"
  },
  "dns": {
    "servers": [
      "8.8.8.8",
      "1.1.1.1"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $internal_port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "email": "${client_name}@vless.local"
          }
        ],
        "decryption": "none",
        "packetEncoding": "xudp"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$cert_file",
              "keyFile": "$key_file"
            }
          ],
          "minVersion": "1.2",
          "maxVersion": "1.3",
          "alpn": ["http/1.1"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "tag": "direct"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
}

# Миграция mobile: WS/внешний порт → TCP+TLS + nginx stream :443
migrate_mobile_config_to_443() {
    local client_name="$1"
    local config_file="$CLIENT_DIR/${client_name}.json"
    local internal_port uuid

    [[ -f "$config_file" ]] || return 1
    internal_port=$(extract_port_from_config "$config_file")
    uuid=$(extract_uuid_from_config "$config_file")
    [[ -n "$internal_port" && -n "$uuid" ]] || return 1

    if is_mobile_443_config "$config_file" && \
       grep -qE '"network": "tcp"' "$config_file" && \
       grep -q '"security": "tls"' "$config_file"; then
        setup_nginx_mobile_443 || return 1
        register_mobile_stream_client "$client_name" "$internal_port"
        refresh_client_artifacts "$client_name"
        write_v2raytun_mobile_notes "$client_name" \
            "$(build_vless_url_from_config "$config_file" "$client_name")"
        return 0
    fi

    echo -e "${YELLOW}Миграция $client_name → TCP+TLS passthrough :443...${NC}"
    if ! setup_nginx_mobile_443; then
        return 1
    fi
    if ! generate_client_tls_cert "$(get_server_ip)" "$client_name"; then
        return 1
    fi

    write_mobile_xray_config "$client_name" "$uuid" "$internal_port"
    register_mobile_stream_client "$client_name" "$internal_port"
    refresh_client_artifacts "$client_name"
    write_v2raytun_mobile_notes "$client_name" \
        "$(build_vless_url_from_config "$config_file" "$client_name")"
    /usr/local/bin/vless-servers restart "$client_name" 2>/dev/null || \
        /usr/local/bin/vless-servers start "$client_name" 2>/dev/null || true
    log "INFO" "Мобильный конфиг $client_name: TCP+TLS stream :443 (127.0.0.1:${internal_port})"
}

# VLESS + TLS :443 — для v2rayTun / LTE
create_mobile_vless_config() {
    local client_name="$1"

    if [[ -z "$client_name" ]]; then
        echo -e "${RED}Имя клиента не может быть пустым!${NC}"
        return 1
    fi

    if [[ "$client_name" == "$MOBILE_REALITY_HUB" ]]; then
        echo -e "${RED}Имя ${MOBILE_REALITY_HUB} зарезервировано системой!${NC}"
        return 1
    fi

    if is_mobile_reality_client "$client_name"; then
        echo -e "${RED}Mobile конфиг для $client_name уже существует! Сначала удалите его.${NC}"
        return 1
    fi

    local uuid vless_url hy2_url qr_path="" public_host
    uuid=$(generate_uuid)
    public_host=$(get_public_host)
    load_reality_env

    echo -e "${CYAN}📱 LTE: REALITY :443 (${REALITY_SNI}) + Hysteria2 :${HYSTERIA_PORT}${NC}"
    echo -e "${YELLOW}   Wi‑Fi: создайте отдельно пункт 1 — конфиги не удаляем${NC}"

    if ! ensure_reality_keys; then
        echo -e "${RED}Не удалось получить ключи REALITY (xray x25519)${NC}"
        return 1
    fi
    if ! setup_nginx_reality_stream; then
        echo -e "${RED}Не удалось освободить :443${NC}"
        return 1
    fi
    setup_hysteria_mobile || echo -e "${YELLOW}Hysteria2 не поднялась — только REALITY${NC}"

    register_mobile_reality_client "$client_name" "$uuid"
    vless_url=$(build_mobile_reality_url "$client_name" "$uuid")
    hy2_url=$(build_hysteria_url "$client_name")
    write_v2raytun_mobile_notes "$client_name" "$vless_url" "$hy2_url"

    echo -e "${YELLOW}🔄 Генерирую QR-код для v2rayTun...${NC}"
    if generate_qr_code "$vless_url" "$client_name"; then
        qr_path="$QR_DIR/${client_name}.png"
        echo -e "${GREEN}✅ QR-код создан: $qr_path${NC}"
    fi

    init_database
    sqlite3 "$CONFIG_DIR/clients.db" << EOF
INSERT OR REPLACE INTO clients (name, uuid, port, config_path, url, qr_path)
VALUES ('$client_name', '$uuid', $VLESS_MOBILE_PUBLIC_PORT, '$REALITY_CONFIG_FILE', '$vless_url', '$qr_path');
EOF

    setup_enhanced_iptables

    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        📱 MOBILE kibervpn-style (REALITY + Hy2)                 ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║ Клиент: $client_name${NC}"
    echo -e "${CYAN}║ UUID: $uuid${NC}"
    echo -e "${CYAN}║ LTE: 443 REALITY Vision | SNI: ${REALITY_SNI}${NC}"
    echo -e "${CYAN}║ Запасной: Hysteria2 UDP :${HYSTERIA_PORT}${NC}"
    echo -e "${CYAN}║ Hy2: $hy2_url${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║ VLESS URL:${NC}"
    echo -e "${WHITE}║ $vless_url${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║ URL: $CONFIG_DIR/urls/${client_name}.txt${NC}"
    if [[ -n "$qr_path" ]]; then
        echo -e "${BLUE}║ QR: $qr_path${NC}"
    fi
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}v2rayTun: MUX ВЫКЛ, Private DNS ВЫКЛ, только LTE${NC}"
    echo -e "${YELLOW}Wi‑Fi/ПК: используйте пункт 1 меню (отдельный конфиг)${NC}"

    echo
    display_qr_terminal "$vless_url"

    log "INFO" "Mobile kibervpn-style $client_name (UUID: $uuid, REALITY :443, Hy2 :${HYSTERIA_PORT})"
}

# Main menu function
main_menu() {
    while true; do
        show_banner
        show_menu
        read -r choice
        
        case "$choice" in
            1) 
                echo -n "Введи имя клиента: "
                read -r client_name
                if [[ -n "$client_name" ]]; then
                    create_vless_config "$client_name"
                else
                    echo -e "${RED}Имя не может быть пустым!${NC}"
                fi
                read -p "Нажми Enter для продолжения..." 
                ;;
            10)
                echo -e "${CYAN}📱 REALITY :443 + Hysteria2 (LTE, kibervpn)${NC}"
                echo -n "Введи имя клиента (например akuma0xdead-mob): "
                read -r client_name
                if [[ -n "$client_name" ]]; then
                    create_mobile_vless_config "$client_name"
                else
                    echo -e "${RED}Имя не может быть пустым!${NC}"
                fi
                read -p "Нажми Enter для продолжения..."
                ;;
            2) list_configs ;;
            3) delete_config_menu ;;
            4) show_active_connections ;;
            5) setup_openvpn_integration ;;
            6) show_system_monitoring ;;
            7) show_logs_menu ;;
            8) system_settings_menu ;;
            9) rebuild_database ;;
            0) 
                log "INFO" "VLESS Manager завершает работу. До встречи!"
                exit 0 
                ;;
            *) 
                echo -e "${RED}Неверный выбор! Попробуй еще раз.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Main function
main() {
    ensure_root
    setup_directories
    check_dependencies
    init_database
    
    log "INFO" "VLESS Manager v1.3 запущен (QR Codes & Network Enhancement)"
    log "INFO" "Версия: 1.3 | Автор: AKUMA0xDEAD"
    
    main_menu
}

# Run only if script called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "repair-ports" ]]; then
        ensure_root
        setup_directories
        check_dependencies
        init_database
        repair_duplicate_ports 0
        exit $?
    fi
    if [[ "${1:-}" == "cli" ]]; then
        ensure_root
        setup_directories
        check_dependencies
        init_database
        cmd="${2:-}"
        name="${3:-}"
        case "$cmd" in
            create-wifi)
                [[ -n "$name" ]] || { echo "usage: cli create-wifi NAME" >&2; exit 2; }
                create_vless_config "$name"
                exit $?
                ;;
            create-mobile)
                [[ -n "$name" ]] || { echo "usage: cli create-mobile NAME" >&2; exit 2; }
                create_mobile_vless_config "$name"
                exit $?
                ;;
            delete-client)
                local wifi_flag="${4:-1}" mobile_flag="${5:-1}"
                [[ -n "$name" ]] || { echo "usage: cli delete-client NAME [wifi 0|1] [mobile 0|1]" >&2; exit 2; }
                delete_vless_client "$name" "$wifi_flag" "$mobile_flag"
                exit $?
                ;;
            set-public-host)
                [[ -n "$name" ]] || { echo "usage: cli set-public-host DOMAIN" >&2; exit 2; }
                umask 077
                mkdir -p "$CONFIG_DIR"
                if [[ -f "$TLS_ENV" ]]; then
                    if grep -q '^PUBLIC_HOST=' "$TLS_ENV"; then
                        sed -i "s/^PUBLIC_HOST=.*/PUBLIC_HOST=${name}/" "$TLS_ENV"
                    else
                        echo "PUBLIC_HOST=${name}" >> "$TLS_ENV"
                    fi
                else
                    cat > "$TLS_ENV" << EOF
TLS_MODE=selfsigned
PUBLIC_HOST=${name}
LE_FULLCHAIN=
LE_PRIVKEY=
LE_EMAIL=
EOF
                    chmod 600 "$TLS_ENV"
                fi
                echo "PUBLIC_HOST=${name} (VLESS/Hysteria ссылки)"
                exit 0
                ;;
            *)
                echo "usage: $0 cli create-wifi|create-mobile|delete-client|set-public-host ..." >&2
                exit 2
                ;;
        esac
    fi
    main "$@"
fi
