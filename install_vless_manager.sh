#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
#    VLESS Manager Installation Script
#    Created by: AKUMA0xDEAD
#    Description: Automatic installation and setup for VLESS Manager
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

banner() {
    clear
    echo -e "${PURPLE}"
    cat << 'INSTALL_BANNER_EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║              VLESS MANAGER INSTALLER v1.0                    ║
    ║                Ultimate VPN Setup Wizard                     ║
    ║                    by AKUMA0xDEAD                            ║
    ╚═══════════════════════════════════════════════════════════════╝
INSTALL_BANNER_EOF
    echo -e "${NC}"
}

log_install() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "/tmp/vless-install.log"
}

check_requirements() {
    log_install "INFO" "Проверяю системные требования..."
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_install "ERROR" "Установка требует root привилегии!"
        exit 1
    fi
    
    # Check OS
    if ! command -v systemctl >/dev/null 2>&1; then
        log_install "WARN" "systemd не найден, автозапуск будет недоступен"
    fi
    
    # Check basic commands
    local required_commands=("curl" "wget" "iptables" "ss" "ip")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_install "WARN" "Команда $cmd не найдена, попробую установить..."
            install_dependencies
            break
        fi
    done
    
    log_install "INFO" "✓ Системные требования проверены"
}

install_dependencies() {
    log_install "INFO" "Устанавливаю зависимости..."
    
    # Detect package manager
    if command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y curl wget iproute2 iptables uuid-runtime python3 qrencode vnstat htop net-tools
    elif command -v yum >/dev/null 2>&1; then
        yum update -y
        yum install -y curl wget iproute2 iptables util-linux python3 qrencode vnstat htop net-tools
    elif command -v dnf >/dev/null 2>&1; then
        dnf update -y
        dnf install -y curl wget iproute2 iptables util-linux python3 qrencode vnstat htop net-tools
    else
        log_install "WARN" "Неизвестный пакетный менеджер, некоторые функции могут не работать"
    fi
    
    log_install "INFO" "✓ Зависимости установлены"
}

install_xray() {
    log_install "INFO" "Устанавливаю Xray-core..."
    
    # Download and install Xray
    local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    local temp_dir="/tmp/xray-install"
    
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    if wget -q "$xray_url" -O xray.zip; then
        unzip -q xray.zip
        chmod +x xray
        mv xray /usr/local/bin/
        
        # Create xray user
        useradd -r -M -s /sbin/nologin xray 2>/dev/null || true
        
        # Create directories
        mkdir -p /usr/local/etc/xray /var/log/xray
        chown xray:xray /var/log/xray
        
        log_install "INFO" "✓ Xray-core установлен"
    else
        log_install "WARN" "Не удалось скачать Xray, продолжаю без него"
    fi
    
    cd / && rm -rf "$temp_dir"
}

setup_directories() {
    log_install "INFO" "Создаю системные директории..."
    
    # Create directories
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" 
    mkdir -p "$CONFIG_DIR/clients" "$CONFIG_DIR/templates" "$CONFIG_DIR/backup"
    
    # Set permissions
    chmod 750 "$CONFIG_DIR" "$LOG_DIR"
    chmod 700 "$CONFIG_DIR/clients"
    
    log_install "INFO" "✓ Директории созданы"
}

install_manager() {
    log_install "INFO" "Устанавливаю VLESS Manager..."
    
    # Copy main script
    cp "/root/vless_manager.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/vless_manager.sh"
    
    # Create symlink
    ln -sf "$INSTALL_DIR/vless_manager.sh" "$BIN_DIR/vless-manager"
    
    # Create default config
    cat > "$CONFIG_DIR/manager.conf" << MANAGER_CONFIG_EOF
# VLESS Manager Configuration
SERVER_NAME=example.com
DEFAULT_PORT=8443
LOG_LEVEL=info
AUTO_BACKUP=true
BACKUP_RETENTION_DAYS=30
TUNNEL_AUTO_DETECT=true
MANAGER_CONFIG_EOF
    
    log_install "INFO" "✓ VLESS Manager установлен"
}

create_systemd_service() {
    if command -v systemctl >/dev/null 2>&1; then
        log_install "INFO" "Создаю systemd сервис..."
        
        cat > "/etc/systemd/system/vless-manager.service" << SYSTEMD_EOF
[Unit]
Description=VLESS Manager Service
After=network.target
Documentation=https://github.com/AKUMA0xDEAD/vless-manager

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/vless_manager.sh --daemon
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
        
        systemctl daemon-reload
        systemctl enable vless-manager.service
        
        log_install "INFO" "✓ Systemd сервис создан"
    fi
}

setup_firewall() {
    log_install "INFO" "Настраиваю firewall правила..."
    
    # Basic firewall setup
    if command -v ufw >/dev/null 2>&1; then
        ufw --force enable
        ufw allow ssh
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 8443/tcp
        log_install "INFO" "✓ UFW правила настроены"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=8443/tcp
        firewall-cmd --reload
        log_install "INFO" "✓ Firewalld правила настроены"
    else
        log_install "WARN" "Firewall не найден, настройте правила вручную"
    fi
}

create_backup_script() {
    log_install "INFO" "Создаю скрипт резервного копирования..."
    
    cat > "$INSTALL_DIR/backup.sh" << BACKUP_SCRIPT_EOF
#!/bin/bash
# VLESS Manager Backup Script

BACKUP_DIR="$CONFIG_DIR/backup"
DATE=\$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="\$BACKUP_DIR/vless_backup_\$DATE.tar.gz"

mkdir -p "\$BACKUP_DIR"

# Create backup
tar czf "\$BACKUP_FILE" -C "$CONFIG_DIR" clients clients.db tunnel_config.conf manager.conf 2>/dev/null

# Clean old backups (keep last 30 days)
find "\$BACKUP_DIR" -name "vless_backup_*.tar.gz" -mtime +30 -delete

echo "Backup created: \$BACKUP_FILE"
BACKUP_SCRIPT_EOF
    
    chmod +x "$INSTALL_DIR/backup.sh"
    
    # Add to crontab for daily backup
    (crontab -l 2>/dev/null || true; echo "0 2 * * * $INSTALL_DIR/backup.sh") | crontab -
    
    log_install "INFO" "✓ Скрипт резервного копирования создан"
}

finalize_installation() {
    log_install "INFO" "Завершаю установку..."
    
    # Enable IP forwarding
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    
    # Create first run flag
    touch "$CONFIG_DIR/.first_run"
    
    log_install "INFO" "✓ Установка завершена!"
}

show_completion_info() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 УСТАНОВКА ЗАВЕРШЕНА!                         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}VLESS Manager успешно установлен!${NC}"
    echo ""
    echo -e "${YELLOW}Как запустить:${NC}"
    echo -e "  • Команда: ${WHITE}vless-manager${NC}"
    echo -e "  • Или:     ${WHITE}$INSTALL_DIR/vless_manager.sh${NC}"
    echo ""
    echo -e "${YELLOW}Полезные команды:${NC}"
    echo -e "  • ${WHITE}systemctl start vless-manager${NC}   - запустить сервис"
    echo -e "  • ${WHITE}systemctl status vless-manager${NC}  - проверить статус"
    echo -e "  • ${WHITE}journalctl -u vless-manager${NC}     - показать логи"
    echo ""
    echo -e "${YELLOW}Конфигурационные файлы:${NC}"
    echo -e "  • Конфиги: ${WHITE}$CONFIG_DIR${NC}"
    echo -e "  • Логи:    ${WHITE}$LOG_DIR${NC}"
    echo -e "  • Бэкапы:  ${WHITE}$CONFIG_DIR/backup${NC}"
    echo ""
    echo -e "${RED}ВАЖНО:${NC} Не забудьте настроить ваш домен в настройках!"
    echo ""
    echo -e "${GREEN}Хакерского настроения! 🚀💀${NC}"
    echo ""
}

# Main installation flow
main() {
    banner
    
    echo -e "${YELLOW}Добро пожаловать в установщик VLESS Manager!${NC}"
    echo -e "${YELLOW}Это займет несколько минут...${NC}"
    echo ""
    
    sleep 3
    
    check_requirements
    install_dependencies
    install_xray
    setup_directories  
    install_manager
    create_systemd_service
    setup_firewall
    create_backup_script
    finalize_installation
    
    show_completion_info
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
