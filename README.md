<div align="center">

# 🔥 VLESS Manager Pro v1.2

## Ultimate VPN Management & Networking System - **FULLY WORKING**

<img src="https://img.shields.io/badge/Version-1.2-brightgreen?style=for-the-badge" alt="Version">
<img src="https://img.shields.io/badge/Status-FULLY_WORKING-success?style=for-the-badge" alt="Status">
<img src="https://img.shields.io/badge/Platform-Linux-orange?style=for-the-badge" alt="Platform">
<img src="https://img.shields.io/badge/Networking-FIXED-success?style=for-the-badge" alt="Networking">

**Professional-grade VLESS VPN management system with working networking fixes**

![GitHub stars](https://img.shields.io/github/stars/sweetpotatohack/vless-manager-pro?style=social)
![GitHub forks](https://img.shields.io/github/forks/sweetpotatohack/vless-manager-pro?style=social)

</div>

---

## 🎯 **What's New in v1.2** 

### ✅ **FULLY WORKING NETWORK CONFIGURATION**
- **Fixed iptables rules** - Proper FORWARD chain configuration
- **Working NAT/MASQUERADE** - Internet traffic routing works perfectly
- **Automatic interface detection** - Auto-detects and configures main network interface
- **Persistent rules** - iptables rules survive reboots via systemd service

### 🔧 **Technical Fixes Applied**
- Added `iptables -I FORWARD -j ACCEPT` rule
- Configured `MASQUERADE` for main network interface
- Fixed VLESS server configuration with proper `outboundTag` routing
- Automatic IP forwarding enabled and made persistent

### 🧪 **Battle Tested**
- ✅ **Real server tested**: `vless://052d58ae-7389-4857-8caf-fa9275dd5ca7@195.133.74.137:56772`
- ✅ **Internet connectivity verified** through VLESS proxy
- ✅ **Mobile client compatibility** confirmed
- ✅ **Auto-installation works** on fresh Ubuntu servers

---

## 🚀 **Installation** 

### ⚡ **One-Line Installation (Recommended)**

```bash
curl -fsSL https://raw.githubusercontent.com/sweetpotatohack/vless-manager-pro/main/install.sh | sudo bash
```

This will:
1. Download the repository
2. Install all dependencies (Xray, sqlite3, net-tools, etc.)
3. Configure networking with working iptables rules
4. Create sample client configuration
5. Start VLESS Manager Pro

### 📋 **Manual Installation**

```bash
# 1. Clone the repository
git clone https://github.com/sweetpotatohack/vless-manager-pro.git
cd vless-manager-pro

# 2. Run the installer
sudo ./install_vless_manager.sh
```

---

## 🎮 **Quick Start**

### 🚀 **Launch Manager**
```bash
# Start the interactive manager
vless-manager

# Or run directly
/opt/vless-manager/vless_manager.sh
```

### 📊 **Server Management**
```bash
# Check all server status
vless-servers status

# Start all servers
vless-servers start

# Start specific server
vless-servers start client_name

# Stop all servers
vless-servers stop
```

---

## 💻 **System Requirements**

### 🖥️ **Supported Systems**
- **Ubuntu 20.04+** ✅ (Tested)
- **Debian 11+** ✅ 
- **CentOS 8+** ✅
- **RHEL 8+** ✅

### 📦 **Minimum Requirements**
- **RAM**: 512MB available
- **CPU**: Any x64 processor
- **Disk**: 100MB free space
- **Network**: Public IP (VPS/Dedicated server)

### 🌐 **Network Requirements**
- Root access for iptables configuration
- Outbound internet access for Xray installation
- Open ports for VLESS clients (auto-configured)

---

## 🛠️ **Configuration Structure**

### 📂 **File Locations**
```
/etc/vless-manager/
├── clients/                    # Client server configs
│   ├── sample_client.json        # Generated sample
│   └── your_client.json          # Your clients
├── urls/                       # Client connection URLs  
│   ├── sample_client.txt          # VLESS URLs
│   └── your_client.txt
├── clients.db                  # SQLite database
└── backup/                     # Automatic backups

/var/log/
└── vless-manager.log          # Application logs

/opt/vless-manager/
└── vless_manager.sh           # Main application
```

### ⚙️ **Networking Configuration**
```bash
# IP Forwarding (enabled automatically)
net.ipv4.ip_forward=1

# iptables Rules (configured automatically)
iptables -I FORWARD -j ACCEPT
iptables -t nat -A POSTROUTING -o <interface> -j MASQUERADE

# Persistent Rules
/etc/iptables/rules.v4          # Saved rules
/etc/systemd/system/iptables-restore.service  # Auto-restore service
```

---

## 🎯 **Client Configuration**

### 📱 **VLESS URL Format**
```
vless://UUID@SERVER_IP:PORT?encryption=none&security=none&type=tcp#CLIENT_NAME
```

### 🔧 **Manual Client Settings**
- **Protocol**: VLESS
- **Address**: Your server IP
- **Port**: Generated port (10000-20000 range)
- **UUID**: Auto-generated UUID v4
- **Encryption**: none
- **Security**: none
- **Transport**: TCP
- **Flow**: **LEAVE EMPTY** (important!)

### 📱 **Supported Clients**
- **v2rayN** (Windows) ✅
- **v2rayNG** (Android) ✅
- **Qv2ray** (Linux/Windows) ✅
- **v2rayU** (macOS) ✅
- **Shadowrocket** (iOS) ✅

---

## 🔧 **Troubleshooting**

### ❌ **"No Internet After Connection"**
This was the main issue fixed in v1.2! If you still experience this:

```bash
# Check iptables rules
sudo iptables -L FORWARD -n
sudo iptables -t nat -L POSTROUTING -n

# Should show:
# FORWARD chain: ACCEPT rule at top
# POSTROUTING: MASQUERADE rule for your interface

# If missing, reinstall:
sudo ./install_vless_manager.sh
```

### ❌ **"Server Not Starting"**
```bash
# Check Xray installation
xray version

# Check configuration
sudo vless-servers status

# Check logs
sudo tail -f /var/log/vless-CLIENT_NAME.log
```

### ❌ **"Port Not Accessible"**
```bash
# Check if port is listening
sudo netstat -tlnp | grep PORT_NUMBER

# Check firewall (if enabled)
sudo ufw allow PORT_NUMBER/tcp

# For cloud servers, check security groups/firewall rules
```

---

## 🔄 **Update Instructions**

### 🚀 **Update to Latest Version**
```bash
# Backup current config
sudo cp -r /etc/vless-manager /etc/vless-manager.backup

# Download latest version
git clone https://github.com/sweetpotatohack/vless-manager-pro.git
cd vless-manager-pro

# Run installer (preserves existing clients)
sudo ./install_vless_manager.sh

# Restore any custom configurations if needed
```

---

## ⭐ **Testing & Verification**

### 🧪 **Verified Working Configuration**
```
Server IP: 195.133.74.137
Client: akuma0xdead
UUID: 052d58ae-7389-4857-8caf-fa9275dd5ca7
Port: 56772
URL: vless://052d58ae-7389-4857-8caf-fa9275dd5ca7@195.133.74.137:56772?encryption=none&security=none&type=tcp#akuma0xdead
```

### ✅ **Test Results**
- ✅ Server starts and listens on port
- ✅ Client connects successfully  
- ✅ Internet traffic flows through proxy
- ✅ DNS resolution works
- ✅ HTTPS websites accessible
- ✅ Mobile apps work perfectly

---

## 🤝 **Support & Issues**

### 🐛 **Reporting Issues**
Please include:
- **System information**: `uname -a`
- **Installation method used**
- **Error messages with full context**
- **Network configuration**: `ip route show`
- **iptables rules**: `sudo iptables -L -n`

### 💬 **Getting Help**
- 📚 **Documentation**: [GitHub Wiki](https://github.com/sweetpotatohack/vless-manager-pro/wiki)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/sweetpotatohack/vless-manager-pro/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/sweetpotatohack/vless-manager-pro/discussions)

---

## 📜 **License & Disclaimer**

### ⚖️ **License**
This project is licensed under the MIT License.

### ⚠️ **Usage Disclaimer**
This software is intended for:
- ✅ **Legal VPN setup** on your own servers
- ✅ **Privacy protection** where legally permitted
- ✅ **Educational purposes** and learning
- ✅ **Network administration** with proper authorization

**Users are responsible for compliance with local laws and regulations.**

---

## 🌟 **Changelog**

### **v1.2** (Current - Working Release)
- ✅ **Fixed networking**: Added proper iptables FORWARD rules
- ✅ **Fixed NAT**: Correct MASQUERADE configuration  
- ✅ **Fixed routing**: Proper VLESS server outbound tags
- ✅ **Auto-detection**: Network interface auto-detection
- ✅ **Persistence**: Rules survive reboots
- ✅ **Battle-tested**: Real-world server verification

### **v1.0-1.1** (Previous - Had Issues)
- ❌ Missing iptables FORWARD rules
- ❌ Incorrect NAT configuration
- ❌ VLESS routing issues
- ❌ No internet connectivity through proxy

---

<div align="center">

**Made with 💀 by sweetpotatohack**

*"A VPN that actually works is a beautiful thing"*

**NOW FULLY WORKING - v1.2 🚀**

</div>
