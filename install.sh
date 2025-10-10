#!/bin/bash

# Quick installer for VLESS Manager Pro
# Usage: curl -fsSL https://raw.githubusercontent.com/sweetpotatohack/vless-manager-pro/main/install.sh | sudo bash

set -e

REPO_URL="https://github.com/sweetpotatohack/vless-manager-pro"
TEMP_DIR="/tmp/vless-manager-install"

echo "🔥 VLESS Manager Pro - Quick Installer"
echo "🚀 Downloading and installing..."

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download repository
if command -v git >/dev/null 2>&1; then
    git clone "$REPO_URL.git" .
else
    wget -O main.zip "$REPO_URL/archive/main.zip"
    unzip main.zip
    cd vless-manager-pro-main
fi

# Run the main installer
chmod +x install_vless_manager.sh
./install_vless_manager.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo "✅ Installation complete! Run 'vless-manager' to start."
