#!/bin/bash

# VLESS Server Management Script
# Usage: vless-servers {start|stop|status|restart} [client_name]

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

CONFIG_DIR="/etc/vless-manager/clients"
PID_DIR="/var/run"
LOG_DIR="/var/log"

port_is_listening() {
    local p="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -H -tuln "sport = :$p" 2>/dev/null | grep -q .
        return $?
    fi
    netstat -tln 2>/dev/null | grep -q ":$p "
}

get_config_port() {
    local config_file="$1"
    grep -o '"port": [0-9]*' "$config_file" 2>/dev/null | head -1 | awk '{print $2}'
}

find_port_conflict() {
    local client_name="$1"
    local port="$2"
    local other other_port other_pid other_pid_file

    for other in $(get_all_clients); do
        [[ "$other" == "$client_name" ]] && continue
        other_port=$(get_config_port "${CONFIG_DIR}/${other}.json")
        [[ -n "$other_port" && "$other_port" == "$port" ]] || continue
        other_pid_file="${PID_DIR}/vless-${other}.pid"
        if [[ -f "$other_pid_file" ]]; then
            other_pid=$(cat "$other_pid_file")
            if kill -0 "$other_pid" 2>/dev/null; then
                echo "$other"
                return 0
            fi
        fi
        echo "$other"
        return 0
    done
    return 1
}

start_single_server() {
    local client_name="$1"
    local config_file="${CONFIG_DIR}/${client_name}.json"
    local pid_file="${PID_DIR}/vless-${client_name}.pid"
    local log_file="${LOG_DIR}/vless-${client_name}.log"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Конфигурация для $client_name не найдена${NC}"
        return 1
    fi
    
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo -e "${YELLOW}⚠️ Сервер для $client_name уже запущен (PID: $old_pid)${NC}"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    
    local port
    port=$(get_config_port "$config_file")
    if [ -n "$port" ]; then
        local conflict
        if conflict=$(find_port_conflict "$client_name" "$port"); then
            echo -e "${RED}❌ Порт $port уже назначен клиенту $conflict${NC}"
            echo -e "${YELLOW}⚠️  Запустите: vless-manager → Настройки → Исправить дублирующиеся порты${NC}"
            return 1
        fi
        if port_is_listening "$port"; then
            echo -e "${RED}❌ Порт $port уже занят другим процессом${NC}"
            return 1
        fi
    fi

    echo -e "${BLUE}🚀 Запускаем сервер для $client_name...${NC}"
    nohup xray run -config "$config_file" > "$log_file" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$pid_file"
    
    sleep 3
    if kill -0 "$new_pid" 2>/dev/null; then
        echo -e "${GREEN}✅ Сервер для $client_name запущен успешно (PID: $new_pid)${NC}"
        if [ -n "$port" ] && port_is_listening "$port"; then
            echo -e "${GREEN}✅ Порт $port прослушивается${NC}"
        fi
        return 0
    else
        echo -e "${RED}❌ Не удалось запустить сервер для $client_name${NC}"
        if [ -f "$log_file" ]; then
            echo -e "${YELLOW}Последние строки лога:${NC}"
            tail -5 "$log_file" 2>/dev/null || true
        fi
        rm -f "$pid_file"
        return 1
    fi
}

stop_single_server() {
    local client_name="$1"
    local pid_file="${PID_DIR}/vless-${client_name}.pid"
    
    if [ ! -f "$pid_file" ]; then
        echo -e "${YELLOW}⚠️ Сервер для $client_name не запущен${NC}"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${BLUE}🛑 Останавливаем сервер для $client_name (PID: $pid)...${NC}"
        kill "$pid"
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid"
        fi
        rm -f "$pid_file"
        echo -e "${GREEN}✅ Сервер для $client_name остановлен${NC}"
    else
        rm -f "$pid_file"
    fi
}

status_single_server() {
    local client_name="$1"
    local config_file="${CONFIG_DIR}/${client_name}.json"
    local pid_file="${PID_DIR}/vless-${client_name}.pid"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ $client_name: конфигурация не найдена${NC}"
        return 1
    fi
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            local port=$(grep -o '"port": [0-9]*' "$config_file" | cut -d' ' -f2)
            echo -e "${GREEN}✅ $client_name: запущен (PID: $pid, порт $port)${NC}"
        else
            echo -e "${RED}❌ $client_name: PID файл есть, но процесс не запущен${NC}"
            rm -f "$pid_file"
        fi
    else
        echo -e "${YELLOW}⚠️ $client_name: остановлен${NC}"
    fi
}

get_all_clients() {
    if [ -d "$CONFIG_DIR" ]; then
        ls "$CONFIG_DIR"/*.json 2>/dev/null | xargs -r basename -s .json | grep -v '^_mobile-reality$' || true
    fi
}

case "$1" in
    start)
        if [ -n "$2" ]; then
            start_single_server "$2"
        else
            echo -e "${BLUE}🚀 Запускаем все серверы...${NC}"
            for client in $(get_all_clients); do
                start_single_server "$client"
                echo
            done
        fi
        ;;
    stop)
        if [ -n "$2" ]; then
            stop_single_server "$2"
        else
            echo -e "${BLUE}🛑 Останавливаем все серверы...${NC}"
            for client in $(get_all_clients); do
                stop_single_server "$client"
            done
        fi
        ;;
    status)
        if [ -n "$2" ]; then
            status_single_server "$2"
        else
            echo -e "${BLUE}📊 Статус всех серверов:${NC}"
            for client in $(get_all_clients); do
                status_single_server "$client"
            done
        fi
        ;;
    restart)
        if [ -n "$2" ]; then
            stop_single_server "$2"
            sleep 1
            start_single_server "$2"
        else
            echo -e "${BLUE}🔄 Перезапускаем все серверы...${NC}"
            for client in $(get_all_clients); do
                stop_single_server "$client"
                sleep 1
                start_single_server "$client"
                echo
            done
        fi
        ;;
    *)
        echo "Использование: $0 {start|stop|status|restart} [client_name]"
        exit 1
        ;;
esac
