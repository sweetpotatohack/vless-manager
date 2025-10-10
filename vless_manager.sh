#!/bin/bash

# VLESS Manager v1.2 - Fixed Working Version
# Created by: AKUMA0xDEAD

# Configuration
readonly CONFIG_DIR="/etc/vless-manager"
readonly LOG_DIR="/var/log"
readonly CLIENT_DIR="$CONFIG_DIR/clients"

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
    mkdir -p "$CONFIG_DIR" "$CLIENT_DIR" "$LOG_DIR"
    mkdir -p "$CONFIG_DIR/urls" "$CONFIG_DIR/backup"
    chmod 755 "$CONFIG_DIR"
    chmod 700 "$CLIENT_DIR"
}

# Check dependencies  
check_dependencies() {
    local missing_deps=()
    local deps=("xray" "sqlite3" "openssl")
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
    ║                    VLESS MANAGER v1.2                        ║
    ║                Ultimate VPN Management (Fixed)                ║
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

# Get server IP
get_server_ip() {
    local ip
    ip=$(curl -s ifconfig.me 2>/dev/null) || \
    ip=$(curl -s icanhazip.com 2>/dev/null) || \
    ip=$(hostname -I | awk '{print $1}')
    echo "$ip"
}

# Find free port
find_free_port() {
    local start_port=${1:-10000}
    local end_port=${2:-65535}
    for ((port=start_port; port<=end_port; port++)); do
        if ! netstat -tuln | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
    done
    echo "0"
    return 1
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
    config_path TEXT,
    url TEXT
);
SQL
        log "INFO" "База данных клиентов инициализирована"
    fi
}

# Setup iptables
setup_iptables() {
    local interface
    interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [[ -z "$interface" ]]; then
        interface="eth0"
    fi
    iptables -I FORWARD -j ACCEPT 2>/dev/null || true
    iptables -t nat -A POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null || true
    log "INFO" "iptables правила настроены для интерфейса: $interface"
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
                local server_ip=$(get_server_ip)
                local vless_url="vless://${uuid}@${server_ip}:${port}?encryption=none&security=none&type=tcp#${client_name}"
                
                # Сохраняем URL в файл
                echo "$vless_url" > "$CONFIG_DIR/urls/${client_name}.txt"
                
                # Добавляем в базу данных
                sqlite3 "$CONFIG_DIR/clients.db" << EOF
INSERT OR REPLACE INTO clients (name, uuid, port, config_path, url) 
VALUES ('$client_name', '$uuid', $port, '$config_file', '$vless_url');
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

# List configs (fixed)
list_configs() {
    clear
    echo -e "${PURPLE}╔══════════════════ СУЩЕСТВУЮЩИЕ КОНФИГИ ══════════════════╗${NC}"
    
    # Сначала пробуем получить из базы данных
    local count=0
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        while IFS='|' read -r name uuid port created; do
            if [[ -n "$name" ]]; then
                ((count++))
                echo -e "${GREEN}║ $count) $name${NC}"
                echo -e "${CYAN}║    UUID: $uuid${NC}"
                echo -e "${BLUE}║    Порт: $port | Создан: $created${NC}"
                echo -e "${PURPLE}║${NC}"
                
                local url_file="$CONFIG_DIR/urls/${name}.txt"
                if [[ -f "$url_file" ]]; then
                    local url=$(cat "$url_file")
                    echo -e "${YELLOW}║    URL: $url${NC}"
                    echo -e "${PURPLE}║${NC}"
                fi
            fi
        done < <(sqlite3 "$CONFIG_DIR/clients.db" "SELECT name, uuid, port, created_at FROM clients ORDER BY created_at DESC;" 2>/dev/null)
    fi
    
    # Если в базе ничего нет, показываем из файловой системы
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}║ База данных пуста. Показываю конфиги из файлов:        ║${NC}"
        echo -e "${PURPLE}║${NC}"
        
        while IFS= read -r client_name; do
            if [[ -n "$client_name" ]]; then
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
    fi
    
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
    read -p "Нажми Enter для продолжения..."
}

# Delete config menu (fixed)
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
        
        # Удаляем из базы
        if [[ -f "$CONFIG_DIR/clients.db" ]]; then
            sqlite3 "$CONFIG_DIR/clients.db" "DELETE FROM clients WHERE name='$client_name';" 2>/dev/null || true
        fi
        
        echo -e "${GREEN}Конфиг для '$client_name' успешно удален!${NC}"
        log "INFO" "Удален конфиг для клиента: $client_name"
    else
        echo -e "${YELLOW}Отменено.${NC}"
    fi
    
    read -p "Нажми Enter для продолжения..."
}

# Show active connections (fixed)
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

# Setup OpenVPN integration (placeholder)
setup_openvpn_integration() {
    clear
    echo -e "${PURPLE}╔══════════════════ OPENVPN ИНТЕГРАЦИЯ ══════════════════╗${NC}"
    echo -e "${YELLOW}║ Функция в разработке                               ║${NC}"
    echo -e "${CYAN}║ Будет доступна в следующих версиях                  ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "Нажми Enter для продолжения..."
}

# System monitoring  
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

# System settings menu
system_settings_menu() {
    clear
    echo -e "${PURPLE}╔══════════════════ НАСТРОЙКИ СИСТЕМЫ ══════════════════╗${NC}"
    echo -e "${BLUE}║ 1) Проверить iptables правила                        ║${NC}"
    echo -e "${BLUE}║ 2) Восстановить iptables правила                     ║${NC}"
    echo -e "${BLUE}║ 3) Проверить статус IP forwarding                    ║${NC}"
    echo -e "${BLUE}║ 4) Включить IP forwarding                            ║${NC}"
    echo -e "${BLUE}║ 5) Показать сетевые интерфейсы                       ║${NC}"
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
            echo -e "${YELLOW}Восстанавливаю iptables правила...${NC}"
            setup_iptables
            echo -e "${GREEN}Правила восстановлены${NC}"
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
        0) return ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac
    read -p "Нажми Enter для продолжения..."
}

# Create VLESS config
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
    port=$(find_free_port 10000 20000)
    server_ip=$(get_server_ip)
    
    if [[ "$port" == "0" ]]; then
        echo -e "${RED}Не удалось найти свободный порт!${NC}"
        return 1
    fi
    
    # Create Xray config
    cat > "$CLIENT_DIR/${client_name}.json" << EOF
{
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "email": "${client_name}@vless.local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field", 
        "outboundTag": "direct",
        "network": "tcp,udp"
      }
    ]
  }
}
EOF
    
    # Create VLESS URL
    local vless_url="vless://${uuid}@${server_ip}:${port}?encryption=none&security=none&type=tcp#${client_name}"
    echo "$vless_url" > "$CONFIG_DIR/urls/${client_name}.txt"
    
    # Save to database
    init_database
    sqlite3 "$CONFIG_DIR/clients.db" << EOF
INSERT INTO clients (name, uuid, port, config_path, url) 
VALUES ('$client_name', '$uuid', $port, '$CLIENT_DIR/${client_name}.json', '$vless_url');
EOF
    
    setup_iptables
    /usr/local/bin/vless-servers start "$client_name"
    
    # Show result
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    КОНФИГ СОЗДАН УСПЕШНО!                      ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║ Клиент: $client_name${NC}"
    echo -e "${CYAN}║ UUID: $uuid${NC}"
    echo -e "${CYAN}║ Порт: $port${NC}"
    echo -e "${CYAN}║ IP сервера: $server_ip${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║ VLESS URL:${NC}"
    echo -e "${WHITE}║ $vless_url${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║ Конфиг сохранен: $CLIENT_DIR/${client_name}.json${NC}"
    echo -e "${BLUE}║ URL сохранен: $CONFIG_DIR/urls/${client_name}.txt${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    log "INFO" "Создан конфиг для клиента $client_name (UUID: $uuid, Port: $port)"
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
    
    log "INFO" "VLESS Manager v1.2 запущен"
    log "INFO" "Версия: 1.2 | Автор: AKUMA0xDEAD"
    
    main_menu
}

# Run only if script called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
