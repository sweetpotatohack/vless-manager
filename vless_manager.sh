#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
#    VLESS Manager v1.0 - Ultimate VPN Management System
#    Created by: AKUMA0xDEAD
#    Description: Professional VLESS VPN management with OpenVPN integration
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail  # Строгий режим - как настоящие профи делают

# ═══════════════════ CONFIGURATION ═══════════════════
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="/etc/vless-manager"
readonly LOG_DIR="/var/log/vless-manager"
readonly CLIENT_DIR="$CONFIG_DIR/clients"
readonly TEMPLATE_DIR="$CONFIG_DIR/templates"
readonly PID_FILE="/var/run/vless-manager.pid"

# Default settings (можно будет кастомизировать)
readonly DEFAULT_PORT=8443
readonly DEFAULT_TRANSPORT="tcp"
readonly DEFAULT_SECURITY="tls"
readonly SERVER_NAME="example.com"

# Colors для красивого вывода (как в Matrix)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# ═══════════════════ UTILITY FUNCTIONS ═══════════════════

# Логирование как у настоящих профи
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
        *) echo -e "${WHITE}[$level]${NC} $message" ;;
    esac
}

# Проверка прав root (без этого никуда)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Эй, друг! Этот скрипт требует root привилегии. Запускай через sudo или под root'ом!"
        exit 1
    fi
}

# Создание директорий
setup_directories() {
    local dirs=("$CONFIG_DIR" "$LOG_DIR" "$CLIENT_DIR" "$TEMPLATE_DIR")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 750 "$dir"
            log "INFO" "Создана директория: $dir"
        fi
    done
}

# Генерация UUID (криптографически стойкого)
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        # Fallback для систем без uuidgen
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    fi
}

# Генерация случайного порта
generate_random_port() {
    local min_port=10000
    local max_port=65000
    echo $((RANDOM % (max_port - min_port + 1) + min_port))
}

# Проверка доступности порта
check_port_available() {
    local port="$1"
    if ss -tuln | grep -q ":$port "; then
        return 1  # Порт занят
    else
        return 0  # Порт свободен
    fi
}

# Создание VLESS конфига для клиента
create_vless_config() {
    local client_name="$1"
    local port="${2:-$(generate_random_port)}"
    local uuid=$(generate_uuid)
    local config_file="$CLIENT_DIR/${client_name}.json"
    
    # Проверяем доступность порта
    while ! check_port_available "$port"; do
        port=$(generate_random_port)
        log "WARN" "Порт $port занят, генерируем новый..."
    done
    
    log "INFO" "Создаю VLESS конфиг для клиента: $client_name"
    log "INFO" "UUID: $uuid"
    log "INFO" "Порт: $port"
    
    # Получаем внешний IP
    local server_ip=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
    
    # Серверный конфиг (xray/v2ray format)
    cat > "$config_file" << CONFIG_EOF
{
    "log": {
        "level": "warning",
        "timestamp": true
    },
    "inbounds": [
        {
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "level": 0,
                        "email": "${client_name}@vless-manager"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "none"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ],
    "routing": {
        "rules": []
    }
}
CONFIG_EOF

    # Клиентский конфиг для v2rayTun и подобных
    local client_config_file="$CLIENT_DIR/${client_name}_client.json"
    cat > "$client_config_file" << CLIENT_EOF
{
    "outbounds": [
        {
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "$server_ip",
                        "port": $port,
                        "users": [
                            {
                                "id": "$uuid",
                                "encryption": "none",
                                "level": 0
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "none"
            },
            "tag": "vless-out"
        }
    ],
    "inbounds": [
        {
            "port": 1080,
            "protocol": "socks",
            "settings": {
                "auth": "noauth"
            },
            "tag": "socks-in"
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "inboundTag": ["socks-in"],
                "outboundTag": "vless-out"
            }
        ]
    }
}
CLIENT_EOF

    # VLESS URL для быстрого импорта
    local vless_url="vless://$uuid@$server_ip:$port?type=tcp&security=none#$client_name"
    echo "$vless_url" > "$CLIENT_DIR/${client_name}_url.txt"

    # Создаем базу данных клиентов
    echo "${client_name}:${uuid}:${port}:$(date '+%Y-%m-%d %H:%M:%S'):active" >> "$CONFIG_DIR/clients.db"
    
    log "INFO" "VLESS конфиг для $client_name создан успешно!"
    log "INFO" "Серверный конфиг: $config_file"
    log "INFO" "Клиентский конфиг: $client_config_file"
    log "INFO" "VLESS URL: $vless_url"
    
    return 0
}

show_banner() {
    clear
    echo -e "${PURPLE}"
    cat << 'BANNER_EOF'
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    VLESS MANAGER v1.0                        ║
    ║                 Ultimate VPN Management                       ║
    ║                  by AKUMA0xDEAD                              ║
    ╚═══════════════════════════════════════════════════════════════╝
BANNER_EOF
    echo -e "${NC}"
}

show_menu() {
    echo -e "${CYAN}╔══════════════════ ГЛАВНОЕ МЕНЮ ══════════════════╗${NC}"
    echo -e "${WHITE}║ 1)${NC} Создать новый VLESS конфиг                    ${WHITE}║${NC}"
    echo -e "${WHITE}║ 2)${NC} Показать существующие конфиги                ${WHITE}║${NC}"
    echo -e "${WHITE}║ 3)${NC} Удалить конфиг                               ${WHITE}║${NC}"
    echo -e "${WHITE}║ 4)${NC} Показать активные подключения                ${WHITE}║${NC}"
    echo -e "${WHITE}║ 5)${NC} Настроить OpenVPN интеграцию                 ${WHITE}║${NC}"
    echo -e "${WHITE}║ 6)${NC} Мониторинг системы                           ${WHITE}║${NC}"
    echo -e "${WHITE}║ 7)${NC} Показать логи                                ${WHITE}║${NC}"
    echo -e "${WHITE}║ 8)${NC} Настройки системы                            ${WHITE}║${NC}"
    echo -e "${WHITE}║ 0)${NC} Выход                                        ${WHITE}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -n "Выбери опцию, господин хакер: "
}

# Основная функция меню
main_menu() {
    while true; do
        show_banner
        show_menu
        read -r choice
        
        case "$choice" in
            1) 
                echo -n "Введи имя клиента: "
                read -r client_name
                create_vless_config "$client_name"
                read -p "Нажми Enter для продолжения..." 
                ;;
            2) list_configs ;;
            3) delete_config_menu ;;
            4) show_active_connections ;;
            5) setup_openvpn_integration ;;
            6) show_system_monitoring ;;
            7) show_logs_menu ;;
            8) system_settings_menu ;;
            0) 
                log "INFO" "VLESS Manager завершает работу. До встречи!"
                exit 0 
                ;;
            *) 
                log "WARN" "Неверный выбор! Попробуй еще раз."
                ;;
        esac
    done
}


# ═══════════════════ MAIN EXECUTION ═══════════════════

main() {
    check_root
    setup_directories
    
    log "INFO" "VLESS Manager запущен!"
    log "INFO" "Версия: 1.0 | Автор: AKUMA0xDEAD"
    
    main_menu
}

# Запуск только если скрипт вызван напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# ═══════════════════ EXTENDED MANAGEMENT FUNCTIONS ═══════════════════

# Показать существующие конфиги
list_configs() {
    clear
    echo -e "${PURPLE}╔══════════════════ СУЩЕСТВУЮЩИЕ КОНФИГИ ══════════════════╗${NC}"
    
    if [[ ! -f "$CONFIG_DIR/clients.db" ]]; then
        echo -e "${YELLOW}║ База данных клиентов пуста. Создайте первый конфиг!     ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
        read -p "Нажми Enter для продолжения..."
        return
    fi
    
    local counter=1
    while IFS=':' read -r name uuid port created_date status; do
        case "$status" in
            "active") 
                status_color="${GREEN}✓ Активен${NC}"
                ;;
            "inactive")
                status_color="${RED}✗ Неактивен${NC}"
                ;;
            *)
                status_color="${YELLOW}? Неизвестно${NC}"
                ;;
        esac
        
        echo -e "${WHITE}║ $counter) ${CYAN}$name${NC}"
        echo -e "${WHITE}║    UUID: ${BLUE}$uuid${NC}"
        echo -e "${WHITE}║    Порт: ${YELLOW}$port${NC} | Статус: $status_color"
        echo -e "${WHITE}║    Создан: ${PURPLE}$created_date${NC}"
        echo -e "${WHITE}║${NC}"
        
        counter=$((counter + 1))
    done < "$CONFIG_DIR/clients.db"
    
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Доступные команды:${NC}"
    echo -e "• ${WHITE}show [имя]${NC} - показать конфиг клиента"
    echo -e "• ${WHITE}url [имя]${NC} - показать VLESS URL"
    echo -e "• ${WHITE}qr [имя]${NC} - показать QR код"
    echo ""
    echo -n "Введите команду (или Enter для возврата): "
    read -r cmd name_arg
    
    case "$cmd" in
        "show")
            if [[ -n "$name_arg" ]]; then
                show_client_config "$name_arg"
            else
                echo -e "${RED}Укажите имя клиента!${NC}"
            fi
            ;;
        "url")
            if [[ -n "$name_arg" ]]; then
                show_client_url "$name_arg"
            else
                echo -e "${RED}Укажите имя клиента!${NC}"
            fi
            ;;
        "qr")
            if [[ -n "$name_arg" ]]; then
                show_client_qr "$name_arg"
            else
                echo -e "${RED}Укажите имя клиента!${NC}"
            fi
            ;;
    esac
    
    read -p "Нажми Enter для продолжения..."
}

# Показать конфиг конкретного клиента
show_client_config() {
    local client_name="$1"
    local config_file="$CLIENT_DIR/${client_name}_client.json"
    
    if [[ -f "$config_file" ]]; then
        echo -e "${GREEN}Клиентский конфиг для $client_name:${NC}"
        echo -e "${YELLOW}════════════════════════════════════${NC}"
        cat "$config_file"
        echo -e "${YELLOW}════════════════════════════════════${NC}"
    else
        echo -e "${RED}Конфиг для клиента '$client_name' не найден!${NC}"
    fi
}

# Показать VLESS URL
show_client_url() {
    local client_name="$1"
    local url_file="$CLIENT_DIR/${client_name}_url.txt"
    
    if [[ -f "$url_file" ]]; then
        echo -e "${GREEN}VLESS URL для $client_name:${NC}"
        echo -e "${YELLOW}════════════════════════════════════${NC}"
        cat "$url_file"
        echo -e "${YELLOW}════════════════════════════════════${NC}"
    else
        echo -e "${RED}URL для клиента '$client_name' не найден!${NC}"
    fi
}

# Показать QR код (если установлен qrencode)
show_client_qr() {
    local client_name="$1"
    local url_file="$CLIENT_DIR/${client_name}_url.txt"
    
    if [[ -f "$url_file" ]]; then
        if command -v qrencode >/dev/null 2>&1; then
            echo -e "${GREEN}QR код для $client_name:${NC}"
            qrencode -t ansiutf8 < "$url_file"
        else
            echo -e "${YELLOW}qrencode не установлен. Установите: apt install qrencode${NC}"
            echo -e "${GREEN}VLESS URL для $client_name:${NC}"
            cat "$url_file"
        fi
    else
        echo -e "${RED}URL для клиента '$client_name' не найден!${NC}"
    fi
}

# Удаление конфигов
delete_config_menu() {
    clear
    echo -e "${RED}╔═════════════════ УДАЛЕНИЕ КОНФИГОВ ═════════════════╗${NC}"
    
    if [[ ! -f "$CONFIG_DIR/clients.db" ]]; then
        echo -e "${YELLOW}База данных клиентов пуста!${NC}"
        read -p "Нажми Enter для продолжения..."
        return
    fi
    
    echo -e "${WHITE}Существующие клиенты:${NC}"
    local counter=1
    while IFS=':' read -r name uuid port created_date status; do
        echo -e "${WHITE}$counter) ${CYAN}$name${NC} (порт: $port, статус: $status)"
        counter=$((counter + 1))
    done < "$CONFIG_DIR/clients.db"
    
    echo ""
    echo -n "Введите имя клиента для удаления: "
    read -r client_name
    
    if [[ -z "$client_name" ]]; then
        echo -e "${RED}Имя клиента не может быть пустым!${NC}"
        return
    fi
    
    # Проверяем, существует ли клиент
    if ! grep -q "^${client_name}:" "$CONFIG_DIR/clients.db" 2>/dev/null; then
        echo -e "${RED}Клиент '$client_name' не найден!${NC}"
        return
    fi
    
    echo -e "${YELLOW}ВНИМАНИЕ! Вы действительно хотите удалить клиента '$client_name'?${NC}"
    echo -n "Введите 'YES' для подтверждения: "
    read -r confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        echo -e "${GREEN}Удаление отменено.${NC}"
        return
    fi
    
    delete_client_config "$client_name"
}

# Функция удаления конфигов клиента
delete_client_config() {
    local client_name="$1"
    
    log "INFO" "Удаляю конфигурацию для клиента: $client_name"
    
    # Удаляем файлы конфигов
    local files_to_delete=(
        "$CLIENT_DIR/${client_name}.json"
        "$CLIENT_DIR/${client_name}_client.json" 
        "$CLIENT_DIR/${client_name}_url.txt"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "INFO" "Удален файл: $file"
        fi
    done
    
    # Удаляем запись из базы данных
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        grep -v "^${client_name}:" "$CONFIG_DIR/clients.db" > "$CONFIG_DIR/clients.db.tmp" || true
        mv "$CONFIG_DIR/clients.db.tmp" "$CONFIG_DIR/clients.db"
        log "INFO" "Запись клиента удалена из базы данных"
    fi
    
    echo -e "${GREEN}Клиент '$client_name' успешно удален!${NC}"
}

# Показать активные подключения
show_active_connections() {
    clear
    echo -e "${GREEN}╔════════════════ АКТИВНЫЕ ПОДКЛЮЧЕНИЯ ════════════════╗${NC}"
    
    # Проверяем активные сетевые соединения
    echo -e "${WHITE}Активные VLESS порты:${NC}"
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        while IFS=':' read -r name uuid port created_date status; do
            if [[ "$status" == "active" ]]; then
                # Проверяем, слушается ли порт
                if ss -tuln | grep -q ":$port "; then
                    connection_status="${GREEN}✓ Слушается${NC}"
                else
                    connection_status="${RED}✗ Не активен${NC}"
                fi
                
                echo -e "${CYAN}$name${NC}: порт $port - $connection_status"
                
                # Показываем подключения к порту
                local connections=$(ss -tuln | grep ":$port " | wc -l)
                if [[ $connections -gt 0 ]]; then
                    echo -e "  └─ Соединений: $connections"
                fi
            fi
        done < "$CONFIG_DIR/clients.db"
    else
        echo -e "${YELLOW}База данных клиентов пуста${NC}"
    fi
    
    echo -e "${WHITE}${NC}"
    echo -e "${WHITE}Системная информация:${NC}"
    echo -e "├─ Доступная память: $(free -h | awk '/^Mem:/ {print $7}')"
    echo -e "├─ Загрузка CPU: $(uptime | awk -F'load average:' '{print $2}')"
    echo -e "├─ Сетевые интерфейсы:"
    
    # Показываем интерфейсы включая tun0/tun1
    ip addr show | grep -E "^[0-9]+:" | while read -r line; do
        interface=$(echo "$line" | awk '{print $2}' | sed 's/://')
        status=$(echo "$line" | grep -o "state [A-Z]*" | awk '{print $2}')
        echo -e "│  └─ $interface: $status"
    done
    
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    read -p "Нажми Enter для продолжения..."
}

# Переопределяем функции в конце файла, убираем заглушки

# ═══════════════════ OPENVPN INTEGRATION ═══════════════════

# Настройка интеграции с OpenVPN
setup_openvpn_integration() {
    clear
    echo -e "${PURPLE}╔══════════════ OPENVPN ИНТЕГРАЦИЯ ══════════════╗${NC}"
    echo -e "${WHITE}║ Настройка роутинга через OpenVPN туннели      ║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════╝${NC}"
    
    echo -e "${CYAN}Доступные опции:${NC}"
    echo -e "${WHITE}1)${NC} Настроить автоматический роутинг через tun0"
    echo -e "${WHITE}2)${NC} Настроить автоматический роутинг через tun1"
    echo -e "${WHITE}3)${NC} Показать текущие маршруты"
    echo -e "${WHITE}4)${NC} Настроить NAT и форвардинг"
    echo -e "${WHITE}5)${NC} Проверить статус туннелей"
    echo -e "${WHITE}0)${NC} Назад"
    echo ""
    echo -n "Выберите опцию: "
    read -r choice
    
    case "$choice" in
        1) setup_tunnel_routing "tun0" ;;
        2) setup_tunnel_routing "tun1" ;;
        3) show_current_routes ;;
        4) setup_nat_forwarding ;;
        5) check_tunnel_status ;;
        0) return ;;
        *) 
            echo -e "${RED}Неверный выбор!${NC}"
            sleep 2
            ;;
    esac
    
    read -p "Нажми Enter для продолжения..."
}

# Настройка роутинга через туннель
setup_tunnel_routing() {
    local tunnel_interface="$1"
    
    log "INFO" "Настраиваю роутинг через интерфейс $tunnel_interface"
    
    # Проверяем, существует ли интерфейс
    if ! ip link show "$tunnel_interface" >/dev/null 2>&1; then
        echo -e "${RED}Интерфейс $tunnel_interface не найден!${NC}"
        echo -e "${YELLOW}Убедитесь, что OpenVPN подключение активно.${NC}"
        return 1
    fi
    
    # Получаем IP адрес туннеля
    local tunnel_ip=$(ip addr show "$tunnel_interface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [[ -z "$tunnel_ip" ]]; then
        echo -e "${RED}Не удалось получить IP адрес для $tunnel_interface${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Найден туннель: $tunnel_interface с IP $tunnel_ip${NC}"
    
    # Создаем правила iptables для VLESS клиентов
    echo -e "${YELLOW}Настраиваю iptables правила...${NC}"
    
    # Разрешаем форвардинг
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Настраиваем NAT для VLESS трафика через туннель
    iptables -t nat -C POSTROUTING -o "$tunnel_interface" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "$tunnel_interface" -j MASQUERADE
    
    # Разрешаем трафик между интерфейсами
    iptables -C FORWARD -i "$tunnel_interface" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$tunnel_interface" -j ACCEPT
    iptables -C FORWARD -o "$tunnel_interface" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -o "$tunnel_interface" -j ACCEPT
    
    # Настраиваем маршрутизацию для каждого VLESS клиента
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        while IFS=':' read -r name uuid port created_date status; do
            if [[ "$status" == "active" ]]; then
                # Добавляем правила для перенаправления трафика VLESS клиентов через туннель
                setup_client_routing "$port" "$tunnel_interface" "$name"
            fi
        done < "$CONFIG_DIR/clients.db"
    fi
    
    # Сохраняем конфигурацию в файл
    cat > "$CONFIG_DIR/tunnel_config.conf" << TUNNEL_CONFIG_EOF
# VLESS Manager - OpenVPN Integration Config
TUNNEL_INTERFACE=$tunnel_interface
TUNNEL_IP=$tunnel_ip
CONFIGURED_DATE=$(date '+%Y-%m-%d %H:%M:%S')
STATUS=active
TUNNEL_CONFIG_EOF
    
    log "INFO" "Роутинг через $tunnel_interface настроен успешно!"
    echo -e "${GREEN}✓ Все VLESS клиенты теперь используют $tunnel_interface для выхода в интернет${NC}"
}

# Настройка роутинга для конкретного клиента
setup_client_routing() {
    local port="$1"
    local tunnel_interface="$2"
    local client_name="$3"
    
    # Создаем правило для маркировки пакетов от VLESS клиента
    iptables -t mangle -C OUTPUT -p tcp --sport "$port" -j MARK --set-mark 100 2>/dev/null || \
        iptables -t mangle -A OUTPUT -p tcp --sport "$port" -j MARK --set-mark 100
    
    # Создаем таблицу маршрутизации для маркированных пакетов
    if ! ip rule show | grep -q "fwmark 0x64"; then
        ip rule add fwmark 100 table 100
        ip route add default dev "$tunnel_interface" table 100
    fi
    
    log "INFO" "Настроен роутинг для клиента $client_name (порт $port) через $tunnel_interface"
}

# Показать текущие маршруты
show_current_routes() {
    clear
    echo -e "${BLUE}╔═════════════════ ТЕКУЩИЕ МАРШРУТЫ ═════════════════╗${NC}"
    
    echo -e "${WHITE}Основная таблица маршрутизации:${NC}"
    ip route show | head -10
    
    echo -e "${WHITE}\nТуннельные интерфейсы:${NC}"
    ip addr show | grep -A 4 "^[0-9]*: tun"
    
    echo -e "${WHITE}\nIPTables NAT правила:${NC}"
    iptables -t nat -L POSTROUTING -n | head -10
    
    echo -e "${WHITE}\nПравила форвардинга:${NC}"
    iptables -L FORWARD -n | head -10
    
    if [[ -f "$CONFIG_DIR/tunnel_config.conf" ]]; then
        echo -e "${WHITE}\nТекущая конфигурация туннеля:${NC}"
        cat "$CONFIG_DIR/tunnel_config.conf"
    fi
    
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
}

# Настройка NAT и форвардинга
setup_nat_forwarding() {
    echo -e "${YELLOW}Настраиваю системный NAT и форвардинг...${NC}"
    
    # Включаем форвардинг постоянно
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    sysctl -p
    
    # Настраиваем базовые правила iptables
    iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    echo -e "${GREEN}✓ NAT и форвардинг настроены${NC}"
}

# Проверка статуса туннелей
check_tunnel_status() {
    clear
    echo -e "${GREEN}╔═════════════════ СТАТУС ТУННЕЛЕЙ ═════════════════╗${NC}"
    
    echo -e "${WHITE}Активные туннельные интерфейсы:${NC}"
    for interface in tun0 tun1 tun2; do
        if ip link show "$interface" >/dev/null 2>&1; then
            local ip_addr=$(ip addr show "$interface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
            local status=$(ip link show "$interface" | grep -o "state [A-Z]*" | awk '{print $2}')
            echo -e "${GREEN}✓ $interface${NC}: IP=$ip_addr, Статус=$status"
            
            # Показываем статистику трафика
            local rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
            local tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
            local rx_mb=$((rx_bytes / 1024 / 1024))
            local tx_mb=$((tx_bytes / 1024 / 1024))
            echo -e "   └─ RX: ${rx_mb}MB, TX: ${tx_mb}MB"
        else
            echo -e "${RED}✗ $interface${NC}: Не найден"
        fi
    done
    
    echo -e "${WHITE}\nПроверка связности:${NC}"
    for interface in tun0 tun1; do
        if ip link show "$interface" >/dev/null 2>&1; then
            echo -n "Пингую 8.8.8.8 через $interface: "
            if ping -I "$interface" -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAIL${NC}"
            fi
        fi
    done
    
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
}

# Система мониторинга и логирования
show_system_monitoring() {
    clear
    echo -e "${BLUE}╔═══════════════ МОНИТОРИНГ СИСТЕМЫ ═══════════════╗${NC}"
    
    echo -e "${WHITE}Общая информация:${NC}"
    echo -e "├─ Время работы: $(uptime | awk '{print $3,$4}' | sed 's/,//')"
    echo -e "├─ Загрузка: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
    echo -e "├─ Память: $(free -h | awk '/^Mem:/ {printf "%s/%s (%.1f%%)", $3, $2, $3/$2*100}')"
    echo -e "└─ Диск: $(df -h / | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')"
    
    echo -e "${WHITE}\nСетевая активность (за последние 5 мин):${NC}"
    if command -v vnstat >/dev/null 2>&1; then
        vnstat -i eth0 -5
    else
        echo -e "${YELLOW}vnstat не установлен${NC}"
        echo -e "Активные соединения: $(ss -tuln | wc -l)"
    fi
    
    echo -e "${WHITE}\nVLESS трафик:${NC}"
    if [[ -f "$CONFIG_DIR/clients.db" ]]; then
        local total_clients=$(wc -l < "$CONFIG_DIR/clients.db")
        local active_clients=$(grep -c ":active$" "$CONFIG_DIR/clients.db" 2>/dev/null || echo "0")
        echo -e "├─ Всего клиентов: $total_clients"
        echo -e "├─ Активных: $active_clients"
        echo -e "└─ Открытых портов: $(ss -tuln | grep -c ':')"
    fi
    
    echo -e "${WHITE}\nПоследние события (последние 10 строк лога):${NC}"
    if [[ -f "$LOG_DIR/vless-manager.log" ]]; then
        tail -10 "$LOG_DIR/vless-manager.log" | while read -r line; do
            echo -e "${CYAN}  $line${NC}"
        done
    else
        echo -e "${YELLOW}  Лог файл пуст${NC}"
    fi
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    read -p "Нажми Enter для продолжения..."
}

# Показать логи
show_logs_menu() {
    clear
    echo -e "${PURPLE}╔══════════════════ ЛОГИ СИСТЕМЫ ══════════════════╗${NC}"
    echo -e "${WHITE}║ 1)${NC} Показать последние 50 записей              ${WHITE}║${NC}"
    echo -e "${WHITE}║ 2)${NC} Показать только ошибки                     ${WHITE}║${NC}"
    echo -e "${WHITE}║ 3)${NC} Показать активность за сегодня             ${WHITE}║${NC}"
    echo -e "${WHITE}║ 4)${NC} Очистить логи                              ${WHITE}║${NC}"
    echo -e "${WHITE}║ 5)${NC} Следить за логами в реальном времени       ${WHITE}║${NC}"
    echo -e "${WHITE}║ 0)${NC} Назад                                       ${WHITE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════╝${NC}"
    echo -n "Выберите опцию: "
    read -r choice
    
    case "$choice" in
        1) show_recent_logs ;;
        2) show_error_logs ;;
        3) show_today_logs ;;
        4) clear_logs ;;
        5) tail_logs ;;
        0) return ;;
    esac
}

show_recent_logs() {
    echo -e "${GREEN}Последние 50 записей лога:${NC}"
    if [[ -f "$LOG_DIR/vless-manager.log" ]]; then
        tail -50 "$LOG_DIR/vless-manager.log"
    else
        echo -e "${YELLOW}Лог файл не найден${NC}"
    fi
    read -p "Нажми Enter для продолжения..."
}

show_error_logs() {
    echo -e "${RED}Только ошибки:${NC}"
    if [[ -f "$LOG_DIR/vless-manager.log" ]]; then
        grep "\[ERROR\]" "$LOG_DIR/vless-manager.log" | tail -20
    else
        echo -e "${YELLOW}Лог файл не найден${NC}"
    fi
    read -p "Нажми Enter для продолжения..."
}

show_today_logs() {
    local today=$(date '+%Y-%m-%d')
    echo -e "${BLUE}Активность за сегодня ($today):${NC}"
    if [[ -f "$LOG_DIR/vless-manager.log" ]]; then
        grep "$today" "$LOG_DIR/vless-manager.log"
    else
        echo -e "${YELLOW}Лог файл не найден${NC}"
    fi
    read -p "Нажми Enter для продолжения..."
}

clear_logs() {
    echo -n "Вы уверены что хотите очистить логи? (yes/no): "
    read -r confirm
    if [[ "$confirm" == "yes" ]]; then
        > "$LOG_DIR/vless-manager.log"
        echo -e "${GREEN}Логи очищены${NC}"
        log "INFO" "Логи были очищены администратором"
    fi
    read -p "Нажми Enter для продолжения..."
}

tail_logs() {
    echo -e "${CYAN}Следим за логами в реальном времени (Ctrl+C для выхода):${NC}"
    tail -f "$LOG_DIR/vless-manager.log" 2>/dev/null || echo "Лог файл не найден"
}

# Настройки системы  
system_settings_menu() {
    clear
    echo -e "${BLUE}╔════════════════ НАСТРОЙКИ СИСТЕМЫ ════════════════╗${NC}"
    echo -e "${WHITE}║ 1)${NC} Изменить сервер по умолчанию               ${WHITE}║${NC}"
    echo -e "${WHITE}║ 2)${NC} Настроить автозапуск                       ${WHITE}║${NC}"
    echo -e "${WHITE}║ 3)${NC} Обновить сертификаты                       ${WHITE}║${NC}"
    echo -e "${WHITE}║ 4)${NC} Экспорт/Импорт конфигурации                ${WHITE}║${NC}"
    echo -e "${WHITE}║ 5)${NC} Установить дополнительные утилиты          ${WHITE}║${NC}"
    echo -e "${WHITE}║ 0)${NC} Назад                                       ${WHITE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo -n "Выберите опцию: "
    read -r choice
    
    case "$choice" in
        1) change_default_server ;;
        2) setup_autostart ;;
        3) update_certificates ;;
        4) export_import_menu ;;
        5) install_utils ;;
        0) return ;;
    esac
    
    read -p "Нажми Enter для продолжения..."
}

change_default_server() {
    echo -e "${YELLOW}Текущий сервер: $SERVER_NAME${NC}"
    echo -n "Введите новый сервер: "
    read -r new_server
    if [[ -n "$new_server" ]]; then
        sed -i "s/readonly SERVER_NAME=.*/readonly SERVER_NAME=\"$new_server\"/" "$0"
        echo -e "${GREEN}Сервер обновлен на: $new_server${NC}"
    fi
}

setup_autostart() {
    echo -e "${YELLOW}Создаю systemd сервис...${NC}"
    cat > "/etc/systemd/system/vless-manager.service" << SERVICE_EOF
[Unit]
Description=VLESS Manager Service
After=network.target

[Service]
Type=forking
User=root
ExecStart=/root/vless_manager.sh --daemon
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    
    systemctl daemon-reload
    systemctl enable vless-manager.service
    echo -e "${GREEN}Автозапуск настроен${NC}"
}

install_utils() {
    echo -e "${YELLOW}Устанавливаю полезные утилиты...${NC}"
    apt update
    apt install -y qrencode vnstat htop iftop curl wget jq
    echo -e "${GREEN}Утилиты установлены${NC}"
}

