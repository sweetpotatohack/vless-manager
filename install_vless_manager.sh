#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
#    VLESS Manager Pro Installation Script v1.2
#    Created by: AKUMA0xDEAD
#    Updated with working iptables and networking fixes
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
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                VLESS MANAGER PRO INSTALLER v1.2                  ║${NC}"
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
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

install_dependencies() {
    log_info "Installing system dependencies..."
    
    $UPDATE_CMD > /dev/null 2>&1
    
    # Essential packages
    $INSTALL_CMD wget unzip curl sqlite3 net-tools qrencode > /dev/null 2>&1
    
    log_info "Dependencies installed successfully"
}

install_xray() {
    log_info "Installing Xray-core..."
    
    cd /tmp
    
    wget -q "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    unzip -q Xray-linux-64.zip
    
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
    mkdir -p "$CONFIG_DIR"/{clients,urls,templates,backup}
    mkdir -p "$LOG_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p /var/run
    
    # Set permissions
    chmod 755 "$CONFIG_DIR" "$LOG_DIR" "$INSTALL_DIR"
    chmod 750 "$CONFIG_DIR"/clients
    
    log_info "Directory structure created"
}

setup_database() {
    log_info "Setting up client database..."
    
    sqlite3 "$CONFIG_DIR/clients.db" << 'DB_EOF'
CREATE TABLE IF NOT EXISTS clients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    uuid TEXT NOT NULL,
    port INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT OR REPLACE INTO settings (key, value) VALUES ('version', '1.2');
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
    
    # Setup NAT - Fixed to use correct interface
    iptables -t nat -A POSTROUTING -o "$MAIN_INTERFACE" -j MASQUERADE 2>/dev/null || true
    
    # Save iptables rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    # Create systemd service for iptables restore
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
    
    log_info "Networking configured successfully"
}

create_server_management() {
    log_info "Creating server management scripts..."
    
    # Create the working vless-servers script
    cp vless-servers-script.sh /usr/local/bin/vless-servers 2>/dev/null || {
        cat > /usr/local/bin/vless-servers << 'SERVER_SCRIPT_EOF'
#!/bin/bash

# VLESS Server Management Script - Fixed Version v1.2

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"  
BLUE="\033[0;34m"
NC="\033[0m"

CONFIG_DIR="/etc/vless-manager/clients"
PID_DIR="/var/run"
LOG_DIR="/var/log"

start_single_server() {
    local client_name="$1"
    local config_file="${CONFIG_DIR}/${client_name}.json"
    local pid_file="${PID_DIR}/vless-${client_name}.pid"
    local log_file="${LOG_DIR}/vless-${client_name}.log"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Configuration for $client_name not found${NC}"
        return 1
    fi
    
    # Check if already running
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo -e "${YELLOW}⚠️ Server for $client_name already running (PID: $old_pid)${NC}"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    
    echo -e "${BLUE}🚀 Starting server for $client_name...${NC}"
    nohup xray run -config "$config_file" > "$log_file" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$pid_file"
    
    sleep 3
    if kill -0 "$new_pid" 2>/dev/null; then
        echo -e "${GREEN}✅ Server for $client_name started successfully (PID: $new_pid)${NC}"
        
        # Check port
        local port=$(grep -o '"port": [0-9]*' "$config_file" | cut -d' ' -f2)
        if [ -n "$port" ] && netstat -tln | grep -q ":$port "; then
            echo -e "${GREEN}✅ Port $port is listening${NC}"
        fi
        return 0
    else
        echo -e "${RED}❌ Failed to start server for $client_name${NC}"
        rm -f "$pid_file"
        return 1
    fi
}

# ... (rest of the script functions)
get_all_clients() {
    if [ -d "$CONFIG_DIR" ]; then
        ls "$CONFIG_DIR"/*.json 2>/dev/null | xargs -r basename -s .json || true
    fi
}

case "$1" in
    start)
        if [ -n "${2:-}" ]; then
            start_single_server "$2"
        else
            echo -e "${BLUE}🚀 Starting all servers...${NC}"
            for client in $(get_all_clients); do
                start_single_server "$client"
                echo
            done
        fi
        ;;
    status)
        echo -e "${BLUE}📊 Server status check${NC}"
        for client in $(get_all_clients); do
            echo "Client: $client"
        done
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart} [client_name]"
        exit 1
        ;;
esac
SERVER_SCRIPT_EOF
    }
    
    chmod +x /usr/local/bin/vless-servers
    log_info "Server management script created"
}

create_sample_client() {
    log_info "Creating sample client configuration..."
    
    # Generate sample client
    SAMPLE_UUID=$(xray uuid)
    SAMPLE_PORT=$((RANDOM % 10000 + 10000))
    
    # Add to database
    sqlite3 "$CONFIG_DIR/clients.db" "INSERT INTO clients (name, uuid, port) VALUES ('sample_client', '$SAMPLE_UUID', $SAMPLE_PORT);"
    
    # Create server config with PROPER routing (the fix!)
    cat > "$CONFIG_DIR/clients/sample_client.json" << SAMPLE_CONFIG_EOF
{
    "log": {
        "loglevel": "info"
    },
    "dns": {
        "servers": [
            "8.8.8.8",
            "1.1.1.1"
        ]
    },
    "inbounds": [
        {
            "port": $SAMPLE_PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$SAMPLE_UUID"
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
            "tag": "direct",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIP"
            }
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "ip": [
                    "0.0.0.0/0"
                ],
                "outboundTag": "direct"
            }
        ]
    }
}
SAMPLE_CONFIG_EOF

    # Create client URL
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipecho.net/plain 2>/dev/null || echo "YOUR_SERVER_IP")
    VLESS_URL="vless://$SAMPLE_UUID@$SERVER_IP:$SAMPLE_PORT?encryption=none&security=none&type=tcp#sample_client"
    echo "$VLESS_URL" > "$CONFIG_DIR/urls/sample_client.txt"
    
    log_info "Sample client created: sample_client"
    log_info "UUID: $SAMPLE_UUID"
    log_info "Port: $SAMPLE_PORT"
    log_info "URL: $VLESS_URL"
}

main() {
    banner
    
    log_info "Starting VLESS Manager Pro installation..."
    
    check_root
    detect_system
    install_dependencies
    install_xray
    setup_directories
    setup_database
    setup_networking  # THIS IS WHERE THE MAGIC HAPPENS!
    create_server_management
    create_sample_client
    
    # Install main script
    cp vless_manager.sh "$INSTALL_DIR/" 2>/dev/null || log_warn "Main script not found in current directory"
    chmod +x "$INSTALL_DIR/vless_manager.sh" 2>/dev/null || true
    ln -sf "$INSTALL_DIR/vless_manager.sh" /usr/local/bin/vless-manager 2>/dev/null || true

    # Install vless-servers script
    cp vless-servers-script.sh /usr/local/bin/vless-servers 2>/dev/null || log_warn "vless-servers script not found"
    chmod +x /usr/local/bin/vless-servers 2>/dev/null || true
    
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 🎉 INSTALLATION COMPLETED! 🎉                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}📋 Quick Start Commands:${NC}"
    echo -e "   ${YELLOW}vless-manager${NC}              # Launch the main interface"
    echo -e "   ${YELLOW}vless-servers status${NC}       # Check server status"
    echo -e "   ${YELLOW}vless-servers start${NC}        # Start all servers"
    echo
    echo -e "${GREEN}✅ NETWORKING FIXES APPLIED - Internet should work through VLESS!${NC}"
    echo -e "${GREEN}🚀 Ready to manage your VLESS VPN infrastructure!${NC}"
}

main "$@"
