#!/bin/bash

# VLESS Manager Pro v2.0 — установка одной командой
# Использование:
#   curl -fsSL .../install.sh | sudo bash
#   или из клонированного репозитория: sudo ./install.sh
#
# Переменные окружения:
#   VLESS_REPO_URL — URL git-репозитория (по умолчанию ниже)

set -e

VLESS_REPO_URL="${VLESS_REPO_URL:-https://github.com/sweetpotatohack/vless-manager}"
TEMP_DIR="/tmp/vless-manager-install-$$"

echo "🔥 VLESS Manager Pro v2.0 — TLS 1.2–1.3, RSA-4096, XUDP, systemd"
echo "🚀 Установка..."

if [[ $EUID -ne 0 ]]; then
    echo "❌ Запустите от root: sudo bash $0"
    exit 1
fi

SCRIPT_PATH="${BASH_SOURCE[0]}"
# При запуске через curl/wget путь может быть пустым или /dev/stdin
if [[ -f "$SCRIPT_PATH" ]] && [[ "$SCRIPT_PATH" != "/dev/stdin" ]] && [[ -f "$(dirname "$SCRIPT_PATH")/install_vless_manager.sh" ]]; then
    REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    echo "📂 Используется локальный репозиторий: $REPO_ROOT"
    cd "$REPO_ROOT"
    chmod +x install_vless_manager.sh
    exec ./install_vless_manager.sh
fi

echo "📦 Клонирование $VLESS_REPO_URL ..."
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$VLESS_REPO_URL.git" .
else
    echo "📦 Установка git..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -q && apt-get install -y git
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git
    else
        echo "❌ Нужен git"
        exit 1
    fi
    git clone --depth 1 "$VLESS_REPO_URL.git" .
fi

chmod +x install_vless_manager.sh
./install_vless_manager.sh

cd /
rm -rf "$TEMP_DIR"

echo "✅ Готово. Команды: vless-manager | systemctl status vless-xray"
