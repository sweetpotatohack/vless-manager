#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
#    VLESS Manager Pro Installation Script v2.0
#    VLESS+TLS 1.2–1.3, RSA-4096, XUDP, systemd, чистая переустановка
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly WHITE='\033[0;37m'
readonly NC='\033[0m'

# Installation paths
readonly INSTALL_DIR="/opt/vless-manager"
readonly BIN_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/vless-manager"
readonly LOG_DIR="/var/log/vless-manager"
readonly INSTALL_VERSION="2.0"
# Должен совпадать с VLESS_PORT_MIN/MAX в vless_manager.sh
readonly VLESS_IPT_MIN=25000
readonly VLESS_IPT_MAX=45000

banner() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                VLESS MANAGER PRO INSTALLER v2.0                  ║${NC}"
    echo -e "${PURPLE}║            Ultimate VPN Management & Networking System           ║${NC}"
    echo -e "${PURPLE}║                        by AKUMA0xDEAD                            ║${NC}"
    echo -e "${PURPLE}║                                                                   ║${NC}"
    echo -e "${PURPLE}║        🔥 NOW WITH WORKING IPTABLES & ROUTING FIXES! 🔥         ║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Остановка xray и удаление старых конфигов/БД (чистая переустановка)
purge_previous_installation() {
    log_warn "Останавливаю старые процессы и удаляю данные $CONFIG_DIR (клиенты, URL, сертификаты, БД)..."
    systemctl stop vless-xray.service 2>/dev/null || true
    if [[ -x /usr/local/bin/vless-servers ]]; then
        /usr/local/bin/vless-servers stop 2>/dev/null || true
    fi
    pkill -f "xray run -config ${CONFIG_DIR}/clients/" 2>/dev/null || true
    rm -f /var/run/vless-*.pid 2>/dev/null || true
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"/clients/* 2>/dev/null || true
        rm -rf "$CONFIG_DIR"/urls/* 2>/dev/null || true
        rm -rf "$CONFIG_DIR"/certs/* 2>/dev/null || true
        rm -rf "$CONFIG_DIR"/qr-codes/* 2>/dev/null || true
        rm -rf "$CONFIG_DIR"/backup/* 2>/dev/null || true
        rm -rf "$CONFIG_DIR"/templates/* 2>/dev/null || true
        rm -rf "$CONFIG_DIR"/bundles/* 2>/dev/null || true
        rm -f "$CONFIG_DIR"/clients.db 2>/dev/null || true
        rm -f "$CONFIG_DIR"/tls.env 2>/dev/null || true
    fi
    log_info "Старые данные VLESS Manager удалены"
}

install_systemd_vless_service() {
    log_info "Устанавливаю systemd: vless-xray.service (автозапуск всех inbound)..."
    cat > /etc/systemd/system/vless-xray.service << 'UNIT_EOF'
[Unit]
Description=VLESS (Xray) VPN instances — vless-manager
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/vless-servers start
ExecStop=/usr/local/bin/vless-servers stop
TimeoutStartSec=180
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT_EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable vless-xray.service 2>/dev/null || log_warn "systemd недоступен — включите автозапуск вручную или используйте vless-servers start"
    log_info "Сервис vless-xray.service зарегистрирован"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Каталог с vless-servers-script.sh (не обязательно pwd при запуске из /tmp и т.п.)
resolve_install_repo_root() {
    local here cwd gitroot
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$here/vless-servers-script.sh" ]]; then
        echo "$here"
        return 0
    fi
    cwd="$(pwd)"
    if [[ -f "$cwd/vless-servers-script.sh" ]]; then
        echo "$cwd"
        return 0
    fi
    if [[ -n "${VLESS_MANAGER_REPO:-}" && -f "${VLESS_MANAGER_REPO}/vless-servers-script.sh" ]]; then
        echo "$VLESS_MANAGER_REPO"
        return 0
    fi
    gitroot="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -n "$gitroot" && -f "$gitroot/vless-servers-script.sh" ]]; then
        echo "$gitroot"
        return 0
    fi
    gitroot="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -n "$gitroot" && -f "$gitroot/vless-servers-script.sh" ]]; then
        echo "$gitroot"
        return 0
    fi
    log_error "Не найден vless-servers-script.sh рядом с установщиком, в текущем каталоге или в \$VLESS_MANAGER_REPO."
    log_error "Запустите: cd /path/to/vless-manager-pro && sudo ./install_vless_manager.sh"
    log_error "или: export VLESS_MANAGER_REPO=/path/to/vless-manager-pro && sudo ./install_vless_manager.sh"
    return 1
}

detect_system() {
    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="apt-get install -y"
        UPDATE_CMD="apt-get update -q"
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"  
        INSTALL_CMD="yum install -y"
        UPDATE_CMD="yum update -y"
    else
        log_error "Unsupported system. Only Debian/Ubuntu and RHEL/CentOS are supported."
        exit 1
    fi
    
    log_info "Detected package manager: $PACKAGE_MANAGER"
}

# shellcheck disable=SC2034
VLESS_INSTALL_LE_DOMAIN=""
VLESS_INSTALL_LE_EMAIL=""

write_tls_env_selfsigned() {
    umask 077
    cat > "$CONFIG_DIR/tls.env" << 'TLS_SELF_EOF'
TLS_MODE=selfsigned
PUBLIC_HOST=
LE_FULLCHAIN=
LE_PRIVKEY=
LE_EMAIL=
TLS_SELF_EOF
    chmod 600 "$CONFIG_DIR/tls.env"
}

write_tls_env_le() {
    local domain="$1"
    umask 077
    cat > "$CONFIG_DIR/tls.env" << EOF
TLS_MODE=letsencrypt
PUBLIC_HOST=${domain}
LE_FULLCHAIN=/etc/letsencrypt/live/${domain}/fullchain.pem
LE_PRIVKEY=/etc/letsencrypt/live/${domain}/privkey.pem
LE_EMAIL=${VLESS_INSTALL_LE_EMAIL}
EOF
    chmod 600 "$CONFIG_DIR/tls.env"
}

prompt_letsencrypt_or_selfsigned() {
    VLESS_INSTALL_LE_DOMAIN=""
    VLESS_INSTALL_LE_EMAIL=""
    if [[ ! -t 0 ]]; then
        log_info "Нет интерактивного ввода — TLS: самоподпись (Allow Insecure в клиенте)."
        write_tls_env_selfsigned
        return 0
    fi
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}Сертификат TLS${NC}"
    echo -e "  ${BLUE}Let's Encrypt${NC} — укажите домен (DNS A уже на этот сервер) и email."
    echo -e "  Порт ${YELLOW}80/tcp${NC} должен быть доступен с интернета на время установки (HTTP-01)."
    echo -e "  ${BLUE}Enter${NC} без домена — самоподписанный сертификат (как раньше, Allow Insecure)."
    echo -e "  ${YELLOW}Важно:${NC} если у домена есть ${YELLOW}AAAA (IPv6)${NC} не на этот сервер — LE даст 404."
    echo -e "  Cloudflare: только ${YELLOW}DNS (серое облако)${NC}, не Proxied."
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -r -p "Домен для TLS (например vpn.example.com), Enter = самоподпись: " _dom
    _dom="${_dom//[[:space:]]/}"
    if [[ -z "$_dom" ]]; then
        write_tls_env_selfsigned
        log_info "Выбрана самоподпись (tls.env → selfsigned)."
        return 0
    fi
    if ! [[ "$_dom" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        log_warn "Домен не похож на FQDN — используем самоподпись."
        write_tls_env_selfsigned
        return 0
    fi
    read -r -p "Email для Let's Encrypt (ACME): " _em
    _em="${_em//[[:space:]]/}"
    if [[ -z "$_em" || "$_em" != *"@"* ]]; then
        log_warn "Нужен корректный email для LE — используем самоподпись."
        write_tls_env_selfsigned
        return 0
    fi
    VLESS_INSTALL_LE_DOMAIN="$_dom"
    VLESS_INSTALL_LE_EMAIL="$_em"
    log_info "Будет запрошен Let's Encrypt для: $VLESS_INSTALL_LE_DOMAIN"
}

install_certbot_package() {
    log_info "Устанавливаю certbot (Let's Encrypt)..."
    if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
        $INSTALL_CMD certbot 2>/dev/null || apt-get install -y certbot
    else
        $INSTALL_CMD certbot 2>/dev/null || true
        if ! command -v certbot >/dev/null 2>&1; then
            yum install -y epel-release 2>/dev/null || true
            $INSTALL_CMD certbot 2>/dev/null || dnf install -y certbot 2>/dev/null || true
        fi
    fi
}

obtain_letsencrypt_certificate() {
    [[ -n "${VLESS_INSTALL_LE_DOMAIN:-}" ]] || return 0
    install_certbot_package
    if ! command -v certbot >/dev/null 2>&1; then
        log_warn "certbot не найден — остаётся самоподпись."
        write_tls_env_selfsigned
        return 0
    fi
    # dig для подсказки по A/AAAA (опционально)
    if command -v dig >/dev/null 2>&1; then
        local pub ip_a
        pub=$(curl -4 -fsS --max-time 6 "https://api.ipify.org" 2>/dev/null || true)
        ip_a=$(dig +short A "$VLESS_INSTALL_LE_DOMAIN" @8.8.8.8 2>/dev/null | tail -1)
        if [[ -n "$pub" && -n "$ip_a" && "$ip_a" != "$pub" ]]; then
            log_warn "DNS A: $VLESS_INSTALL_LE_DOMAIN → $ip_a, IP сервера (IPv4): $pub — если это не тот же хост, LE не пройдёт."
        fi
        local aaaa
        aaaa=$(dig +short AAAA "$VLESS_INSTALL_LE_DOMAIN" @8.8.8.8 2>/dev/null | head -1)
        if [[ -n "$aaaa" ]]; then
            log_warn "У домена есть AAAA (IPv6): $aaaa — Let's Encrypt часто проверяет по IPv6; ответ 404 обычно значит: IPv6 указывает не на этот сервер (удалите AAAA или настройте IPv6 здесь)."
        fi
    else
        log_info "Установите пакет dnsutils (dig) для проверки DNS при следующей установке."
    fi
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    log_info "Запуск certbot standalone (слушаем IPv4 на :80)..."
    local _cb=(certbot certonly --standalone
        -d "$VLESS_INSTALL_LE_DOMAIN"
        --email "$VLESS_INSTALL_LE_EMAIL"
        --agree-tos
        --non-interactive
        --preferred-challenges http)
    if certbot --help 2>/dev/null | grep -q -- '--http-01-address'; then
        _cb+=(--http-01-address 0.0.0.0)
    fi
    if "${_cb[@]}"; then
        write_tls_env_le "$VLESS_INSTALL_LE_DOMAIN"
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > /etc/letsencrypt/renewal-hooks/deploy/vless-manager-restart.sh << 'DEPLOY_EOF'
#!/bin/bash
systemctl restart vless-xray.service 2>/dev/null || true
/usr/local/bin/vless-servers start 2>/dev/null || true
DEPLOY_EOF
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/vless-manager-restart.sh
        systemctl enable certbot.timer 2>/dev/null || true
        log_info "Сертификат Let's Encrypt установлен. Продление: timers certbot; hook перезапускает vless-xray."
        return 0
    fi
    log_warn "Certbot не выдал сертификат. Частые причины: A/AAAA не на этот сервер, Cloudflare Proxied, порт 80 занят, лимиты LE."
    log_warn "При ошибке с IPv6/2a00:…/404 — удалите запись AAAA в DNS или приведите IPv6 к этому серверу; в Cloudflare включите DNS-only."
    write_tls_env_selfsigned
    return 0
}

install_dependencies() {
    log_info "Installing system dependencies..."
    
    $UPDATE_CMD > /dev/null 2>&1
    
    # Essential packages (+ dig для проверки DNS при LE)
    $INSTALL_CMD wget unzip curl sqlite3 net-tools qrencode openssl dnsutils > /dev/null 2>&1 || \
    $INSTALL_CMD wget unzip curl sqlite3 net-tools qrencode openssl > /dev/null 2>&1
    
    log_info "Dependencies installed successfully"
}

install_xray() {
    log_info "Installing Xray-core..."
    
    cd /tmp
    
    wget -q "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    unzip -o -q Xray-linux-64.zip
    
    mv xray /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # Test installation
    if /usr/local/bin/xray version >/dev/null 2>&1; then
        log_info "Xray-core installed successfully"
    else
        log_error "Failed to install Xray-core"
        exit 1
    fi
    
    # Cleanup
    rm -f /tmp/Xray-linux-64.zip /tmp/geoip.dat /tmp/geosite.dat 2>/dev/null || true
}

setup_directories() {
    log_info "Setting up directory structure..."
    
    # Create directories
    mkdir -p "$CONFIG_DIR"/{clients,urls,templates,backup,certs,qr-codes,bundles}
    mkdir -p "$LOG_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p /var/run
    
    # Set permissions
    chmod 755 "$CONFIG_DIR" "$LOG_DIR" "$INSTALL_DIR"
    chmod 750 "$CONFIG_DIR"/clients
    chmod 700 "$CONFIG_DIR"/certs
    
    local _tm
    _tm="${REPO_ROOT:-}"
    [[ -z "$_tm" ]] && _tm="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "$_tm/templates" ]]; then
        cp -f "$_tm/templates/"* "$CONFIG_DIR/templates/" 2>/dev/null || true
        log_info "Шаблоны клиента (NekoBox DNS): $_tm/templates/ → $CONFIG_DIR/templates/"
    fi
    
    log_info "Directory structure created"
}

setup_database() {
    log_info "Setting up client database..."
    
    sqlite3 "$CONFIG_DIR/clients.db" << DB_EOF
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

CREATE TABLE IF NOT EXISTS settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT OR REPLACE INTO settings (key, value) VALUES ('version', '${INSTALL_VERSION}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('install_date', datetime('now'));
DB_EOF

    log_info "Database initialized"
}

setup_networking() {
    log_info "Configuring networking and firewall..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Make it permanent
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null 2>&1
    
    # Get main interface
    MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    log_info "Main network interface: $MAIN_INTERFACE"
    
    # Configure iptables rules (THE KEY FIXES!)
    # Allow forwarding - THIS WAS THE MAIN MISSING PIECE
    iptables -I FORWARD -j ACCEPT 2>/dev/null || true
    
    # Порты VLESS: при UFW — только через ufw (иначе reload затирает ручной iptables -I INPUT)
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qiE 'Status:\s+active'; then
        ufw allow "${VLESS_IPT_MIN}:${VLESS_IPT_MAX}/tcp" comment 'vless-manager' 2>/dev/null || \
        ufw allow "${VLESS_IPT_MIN}:${VLESS_IPT_MAX}/tcp" 2>/dev/null || true
        if [[ -n "${VLESS_INSTALL_LE_DOMAIN:-}" ]]; then
            ufw allow 80/tcp comment 'letsencrypt-http-01' 2>/dev/null || ufw allow 80/tcp 2>/dev/null || true
            log_info "ufw: открыт 80/tcp для Let's Encrypt (выпуск и продление HTTP-01)"
        fi
        log_info "ufw: TCP ${VLESS_IPT_MIN}-${VLESS_IPT_MAX} (VLESS) — смотрите ufw status numbered"
    else
        if command -v iptables >/dev/null 2>&1; then
            if ! iptables -C INPUT -p tcp --dport "${VLESS_IPT_MIN}:${VLESS_IPT_MAX}" -j ACCEPT 2>/dev/null; then
                iptables -I INPUT 1 -p tcp --dport "${VLESS_IPT_MIN}:${VLESS_IPT_MAX}" -j ACCEPT 2>/dev/null || \
                iptables -I INPUT -p tcp --dport "${VLESS_IPT_MIN}:${VLESS_IPT_MAX}" -j ACCEPT 2>/dev/null || true
            fi
            log_info "iptables INPUT: TCP ${VLESS_IPT_MIN}-${VLESS_IPT_MAX} (UFW выключен)"
            if [[ -n "${VLESS_INSTALL_LE_DOMAIN:-}" ]]; then
                iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || \
                iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
                log_info "iptables INPUT: TCP 80 (Let's Encrypt HTTP-01)"
            fi
        fi
    fi
    
    # Setup NAT - Fixed to use correct interface
    iptables -t nat -A POSTROUTING -o "$MAIN_INTERFACE" -j MASQUERADE 2>/dev/null || true
    
    mkdir -p /etc/iptables

    # При UFW не включаем iptables-restore: при загрузке он может перезаписать цепочки UFW
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qiE 'Status:\s+active'; then
        systemctl disable iptables-restore.service 2>/dev/null || true
        log_info "UFW активен — служба iptables-restore отключена (используйте ufw для постоянных правил)"
    else
        iptables-save > /etc/iptables/rules.v4
        cat > /etc/systemd/system/iptables-restore.service << 'IPTABLES_EOF'
[Unit]
Description=Restore iptables rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
IPTABLES_EOF
        systemctl enable iptables-restore.service > /dev/null 2>&1 || true
    fi
    
    log_info "Networking configured successfully"
}

create_server_management() {
    log_info "Creating server management scripts..."
    
    local _install_root="${REPO_ROOT:?}"
    if [[ ! -f "$_install_root/vless-servers-script.sh" ]]; then
        log_error "Не найден $_install_root/vless-servers-script.sh"
        exit 1
    fi
    cp -f "$_install_root/vless-servers-script.sh" /usr/local/bin/vless-servers
    chmod +x /usr/local/bin/vless-servers
    log_info "Server management script created (полный vless-servers: start/stop/restart)"
}

create_sample_client() {
    log_info "Creating sample client configuration..."
    
    # Generate sample client
    SAMPLE_UUID=$(xray uuid)
    # 25000–44999: не 80/443 и не типичные веб-порты (рядом с Gophish/nginx)
    SAMPLE_PORT=$((RANDOM % 20000 + 25000))
    local n=0
    while netstat -tuln 2>/dev/null | grep -q ":$SAMPLE_PORT " && [[ $n -lt 150 ]]; do
        SAMPLE_PORT=$((RANDOM % 20000 + 25000))
        n=$((n + 1))
    done
    SERVER_IP=$(curl -4 -fsS --max-time 7 "https://api.ipify.org" 2>/dev/null || curl -4 -fsS --max-time 7 "https://ifconfig.me/ip" 2>/dev/null || echo "127.0.0.1")
    
    mkdir -p "$CONFIG_DIR/certs"
    SAMPLE_HOST_LINK="$SERVER_IP"
    TLS_MODE_LOCAL="selfsigned"
    # shellcheck source=/dev/null
    [[ -f "$CONFIG_DIR/tls.env" ]] && source "$CONFIG_DIR/tls.env"
    TLS_MODE_LOCAL="${TLS_MODE:-selfsigned}"
    if [[ "$TLS_MODE_LOCAL" == "letsencrypt" && -n "${LE_FULLCHAIN:-}" && -f "$LE_FULLCHAIN" && -n "${LE_PRIVKEY:-}" && -f "$LE_PRIVKEY" ]]; then
        SAMPLE_CRT="$LE_FULLCHAIN"
        SAMPLE_KEY="$LE_PRIVKEY"
        SAMPLE_HOST_LINK="${PUBLIC_HOST:-$SERVER_IP}"
        log_info "sample_client: TLS Let's Encrypt ($SAMPLE_HOST_LINK)"
    else
        SAMPLE_KEY="$CONFIG_DIR/certs/sample_client.key"
        SAMPLE_CRT="$CONFIG_DIR/certs/sample_client.crt"
        openssl req -x509 -nodes -newkey rsa:4096 -keyout "$SAMPLE_KEY" -out "$SAMPLE_CRT" -days 8250 \
            -subj "/CN=${SERVER_IP}" \
            -addext "subjectAltName=IP:${SERVER_IP}" 2>/dev/null || \
        openssl req -x509 -nodes -newkey rsa:4096 -keyout "$SAMPLE_KEY" -out "$SAMPLE_CRT" -days 8250 \
            -subj "/CN=${SERVER_IP}"
        chmod 600 "$SAMPLE_KEY" 2>/dev/null || true
        chmod 644 "$SAMPLE_CRT" 2>/dev/null || true
        log_info "sample_client: самоподписанный TLS (Allow Insecure)"
    fi
    
    # VLESS+TCP+TLS+XUDP, TLS 1.2–1.3, шифрование транспорта
    cat > "$CONFIG_DIR/clients/sample_client.json" << SAMPLE_CONFIG_EOF
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
            "port": $SAMPLE_PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$SAMPLE_UUID"
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
                            "certificateFile": "$SAMPLE_CRT",
                            "keyFile": "$SAMPLE_KEY"
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
            "tag": "direct",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4"
            }
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
SAMPLE_CONFIG_EOF

    if [[ "$TLS_MODE_LOCAL" == "letsencrypt" ]]; then
        VLESS_URL="vless://$SAMPLE_UUID@${SAMPLE_HOST_LINK}:$SAMPLE_PORT?encryption=none&security=tls&sni=${SAMPLE_HOST_LINK}&fp=chrome&type=tcp&allowInsecure=0#sample_client"
    else
        VLESS_URL="vless://$SAMPLE_UUID@${SAMPLE_HOST_LINK}:$SAMPLE_PORT?encryption=none&security=tls&sni=${SAMPLE_HOST_LINK}&fp=chrome&type=tcp&allowInsecure=1#sample_client"
    fi
    echo "$VLESS_URL" > "$CONFIG_DIR/urls/sample_client.txt"

    local SAMPLE_QR=""
    mkdir -p "$CONFIG_DIR/qr-codes"
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -s 8 -o "$CONFIG_DIR/qr-codes/sample_client.png" "$VLESS_URL" 2>/dev/null && SAMPLE_QR="$CONFIG_DIR/qr-codes/sample_client.png"
    fi
    local VURL_ESC
    VURL_ESC=$(printf '%s' "$VLESS_URL" | sed "s/'/''/g")
    sqlite3 "$CONFIG_DIR/clients.db" "INSERT INTO clients (name, uuid, port, config_path, url, qr_path) VALUES ('sample_client', '$SAMPLE_UUID', $SAMPLE_PORT, '$CONFIG_DIR/clients/sample_client.json', '$VURL_ESC', '$SAMPLE_QR');"
    
    if [[ -f "$INSTALL_DIR/vless_manager.sh" ]] && command -v python3 >/dev/null 2>&1; then
        bash << EOS
source "$INSTALL_DIR/vless_manager.sh"
write_singbox_client_bundle "sample_client" "$SAMPLE_UUID" "$SAMPLE_PORT" "$SAMPLE_HOST_LINK"
EOS
        log_info "NekoBox/sing-box: $CONFIG_DIR/bundles/sample_client.sing-box.json"
    fi
    
    log_info "Sample client created: sample_client"
    log_info "UUID: $SAMPLE_UUID"
    log_info "Port: $SAMPLE_PORT"
    log_info "URL: $VLESS_URL"
}

main() {
    banner
    
    log_info "Starting VLESS Manager Pro v${INSTALL_VERSION} installation..."
    
    check_root
    REPO_ROOT="$(resolve_install_repo_root)" || exit 1
    export REPO_ROOT
    purge_previous_installation
    detect_system
    install_dependencies
    install_xray
    setup_directories
    prompt_letsencrypt_or_selfsigned
    setup_database
    setup_networking  # UFW: VLESS + при LE — порт 80
    obtain_letsencrypt_certificate
    create_server_management
    
    cp "$REPO_ROOT/vless_manager.sh" "$INSTALL_DIR/" 2>/dev/null || log_warn "vless_manager.sh не скопирован из $REPO_ROOT"
    chmod +x "$INSTALL_DIR/vless_manager.sh" 2>/dev/null || true
    ln -sf "$INSTALL_DIR/vless_manager.sh" /usr/local/bin/vless-manager 2>/dev/null || true
    cp -f "$REPO_ROOT/vless-servers-script.sh" /usr/local/bin/vless-servers 2>/dev/null || log_warn "vless-servers не скопирован"
    chmod +x /usr/local/bin/vless-servers 2>/dev/null || true
    [[ -d "$REPO_ROOT/templates" ]] && cp -r "$REPO_ROOT/templates" "$INSTALL_DIR/" 2>/dev/null || true
    
    create_sample_client
    install_systemd_vless_service
    
    systemctl start vless-xray.service 2>/dev/null || {
        log_warn "systemctl start vless-xray не удался, запускаю vless-servers start"
        /usr/local/bin/vless-servers start 2>/dev/null || true
    }
    
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 🎉 INSTALLATION COMPLETED! 🎉                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}📋 Команды:${NC}"
    echo -e "   ${YELLOW}systemctl status vless-xray${NC}   # Статус Xray (автозапуск)"
    echo -e "   ${YELLOW}vless-manager${NC}                 # Меню управления клиентами"
    echo -e "   ${YELLOW}vless-servers status${NC}          # Статус процессов"
    echo -e "   ${YELLOW}cat ${CONFIG_DIR}/urls/sample_client.txt${NC}  # Пример VLESS URL"
    echo
    echo -e "${GREEN}✅ Транспорт: VLESS + TCP + TLS (1.2–1.3) + XUDP${NC}"
    if [[ -f "$CONFIG_DIR/tls.env" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_DIR/tls.env"
        if [[ "${TLS_MODE:-}" == "letsencrypt" && -n "${PUBLIC_HOST:-}" ]]; then
            echo -e "${GREEN}✅ TLS: Let's Encrypt, домен в ссылке: ${PUBLIC_HOST} (Allow Insecure в клиенте не нужен)${NC}"
        else
            echo -e "${YELLOW}✅ TLS: самоподпись на IP — в клиенте включите «Allow Insecure»${NC}"
        fi
    fi
    echo -e "${GREEN}✅ Готовый профиль NekoBox/sing-box: ${CONFIG_DIR}/bundles/*.sing-box.json${NC}"
    echo -e "${GREEN}✅ Шаблоны и пояснения: ${CONFIG_DIR}/templates/${NC}"
}

main "$@"
