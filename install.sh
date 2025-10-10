#!/bin/bash

# Quick installer for VLESS Manager Pro v1.2
# Usage: curl -fsSL https://raw.githubusercontent.com/sweetpotatohack/vless-manager-pro/main/install.sh | sudo bash

set -e

REPO_URL="https://github.com/sweetpotatohack/vless-manager-pro"
TEMP_DIR="/tmp/vless-manager-install"

echo "🔥 VLESS Manager Pro v1.2 - Quick Installer"
echo "🚀 Downloading and installing with networking fixes..."

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download repository
if command -v git >/dev/null 2>&1; then
    git clone "$REPO_URL.git" .
else
    echo "📦 Installing git..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -q && apt-get install -y git
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git
    fi
    git clone "$REPO_URL.git" .
fi

# Run installer
chmod +x install_vless_manager.sh
./install_vless_manager.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo "✅ Installation completed! Run 'vless-manager' to get started."
