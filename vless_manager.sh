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
# WebSocket path (только для старых конфигов с network=ws)
readonly VLESS_WS_PATH="/vless"
# Высокие порты: не пересекаемся с 80/443 (Gophish, nginx, CDN) и типичными сервисами
readonly VLESS_PORT_MIN=25000
readonly VLESS_PORT_MAX=45000
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
    echo -e "${BLUE}║ 1) Создать новый VLESS конфиг                    ║${NC}"
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

# Свободный порт в диапазоне [min,max], без пересечения с «запретными»
find_free_port() {
    local start_port=${1:-$VLESS_PORT_MIN}
    local end_port=${2:-$VLESS_PORT_MAX}
    local port
    for ((port=start_port; port<=end_port; port++)); do
        vless_port_is_forbidden "$port" && continue
        if ! netstat -tuln | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
    done
    echo "0"
    return 1
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

# Subscription URL: голый TCP | WS+TLS (старые) | TCP+TLS (текущий)
build_vless_url_from_config() {
    local config_file="$1"
    local client_name="$2"
    local uuid port connect_host sni insecure_q
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
    local path_enc
    path_enc=$(printf '%s' "$VLESS_WS_PATH" | sed 's|/|%2F|g')
    if grep -qE '"network":\s*"ws"' "$config_file" 2>/dev/null; then
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
        # Останавливаем сервер если запущен
        /usr/local/bin/vless-servers stop "$client_name" 2>/dev/null || true
        
        # Удаляем файлы
        rm -f "$CLIENT_DIR/${client_name}.json"
        rm -f "$CONFIG_DIR/urls/${client_name}.txt"
        rm -f "$QR_DIR/${client_name}.png"
        if ! tls_uses_letsencrypt; then
            rm -f "$CERT_DIR/${client_name}.crt" "$CERT_DIR/${client_name}.key"
        fi
        rm -f "$BUNDLE_DIR/${client_name}.sing-box.json"
        
        # Удаляем из базы
        if [[ -f "$CONFIG_DIR/clients.db" ]]; then
            sqlite3 "$CONFIG_DIR/clients.db" "DELETE FROM clients WHERE name='$client_name';" 2>/dev/null || true
        fi
        
        echo -e "${GREEN}Конфиг для '$client_name' успешно удален (включая QR-код)!${NC}"
        log "INFO" "Удален конфиг для клиента: $client_name"
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
    
    # Start server
    /usr/local/bin/vless-servers start "$client_name"
    
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
    main "$@"
fi
