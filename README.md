<div align="center">

# 🔥 VLESS Manager Pro v1.3 - QR CODES & NETWORK ENHANCEMENT

## Ultimate VPN Management & Networking System - **QR CODES INTEGRATED**

<img src="https://img.shields.io/badge/Version-1.3--qr--enhanced-brightgreen?style=for-the-badge" alt="Version">
<img src="https://img.shields.io/badge/Status-QR_CODES_READY-success?style=for-the-badge" alt="Status">
<img src="https://img.shields.io/badge/Platform-Linux-orange?style=for-the-badge" alt="Platform">
<img src="https://img.shields.io/badge/QR_Codes-INTEGRATED-blue?style=for-the-badge" alt="QR Codes">

**Professional-grade VLESS VPN management with QR CODES and ALL NETWORK ACCESS**

![GitHub stars](https://img.shields.io/github/stars/sweetpotatohack/vless-manager-fixed?style=social)
![GitHub forks](https://img.shields.io/github/forks/sweetpotatohack/vless-manager-fixed?style=social)

</div>

---

## 🎯 **What's New in v1.3-QR-ENHANCED** 

### 🔥 **MAJOR NEW FEATURES**
- **📱 QR CODE GENERATION** - Automatic QR codes for easy mobile setup
- **🔍 INTERACTIVE CONFIG VIEWER** - Select configs by number to view QR codes
- **🌐 ALL NETWORK ACCESS** - VLESS clients can access ALL network interfaces
- **🔧 OPENVPN INTEGRATION** - Seamless access through VPN tunnels
- **📊 ENHANCED MONITORING** - Shows all available network interfaces

### ✅ **All Previous Bugs Fixed**
- ✅ Fixed PID Display - Shows actual process IDs
- ✅ Fixed Config Listing - Shows configs from filesystem when DB empty  
- ✅ Fixed Database Integration - Auto-rebuild from existing configs
- ✅ Fixed Deletion UI - Numbered selection for easy deletion

### 🆕 **v1.3 Enhancements**
- **📱 QR Code Generation**: Automatic QR codes created for each config
- **📺 Terminal QR Display**: View QR codes directly in terminal
- **💾 QR Code Storage**: QR codes saved as PNG files in `/etc/vless-manager/qr-codes/`
- **🔗 Easy Mobile Setup**: Scan QR codes to instantly connect
- **🌐 Multi-Interface Support**: Access through ALL network interfaces (eth0, wlan0, tun0, etc.)
- **🔄 VPN Passthrough**: OpenVPN/WireGuard traffic routing
- **📊 Enhanced Monitoring**: Network interface status and IPs

---

## 🚀 **Installation** 

### ⚡ **One-Line Installation (Recommended)**

```bash
curl -fsSL https://raw.githubusercontent.com/sweetpotatohack/vless-manager-fixed/main/install.sh | sudo bash
```

This will:
1. Download the repository
2. Install all dependencies (Xray, sqlite3, qrencode, net-tools, etc.)
3. Configure networking with working iptables rules for ALL interfaces
4. Create sample client configuration with QR code
5. Start VLESS Manager Pro v1.3

### 📋 **Manual Installation**

```bash
# 1. Clone the repository
git clone https://github.com/sweetpotatohack/vless-manager-fixed.git
cd vless-manager-fixed

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

### 📱 **Create Client with QR Code**
```bash
vless-manager
# Select option 1
# Enter client name: "my_phone"
# QR code automatically generated and displayed!
```

### 👀 **View QR Codes for Existing Configs**
```bash
vless-manager
# Select option 2 (Show existing configs)
# Select config number (1, 2, 3...)
# QR code displayed in terminal + saved as PNG
```

### 📊 **Server Management**
```bash
# Check all server status (enhanced with interface info)
vless-servers status

# Start all servers with multi-interface support
vless-servers start

# Restart specific server
vless-servers restart client_name
```

---

## 🛠️ **New Features Showcase**

### 📱 **QR Code Features**

#### **Automatic Generation**
- QR codes created automatically when creating new configs
- Saved as PNG files in `/etc/vless-manager/qr-codes/`
- Displayed in terminal for immediate use

#### **Interactive Viewing** 
- Menu option 2 now shows numbered config list
- Select any config by number to view its QR code
- VLESS URL and QR code displayed together

#### **Mobile Setup**
```bash
1. Create config: vless-manager → option 1 → enter name
2. Scan QR code with v2rayNG, v2rayN, or similar app
3. Instant connection - no manual typing needed!
```

### 🌐 **Network Enhancement Features**

#### **All Interface Access**
- VLESS clients can now access through ANY network interface
- Automatic detection and configuration of all interfaces
- Support for eth0, wlan0, tun0, tap0, ppp0, and more

#### **VPN Integration**
```bash
# If you have OpenVPN running:
vless-manager → option 5 (OpenVPN Integration)
# Automatically detects VPN interfaces
# Configures VLESS traffic to route through VPN
```

#### **Enhanced Monitoring**
- Shows all network interfaces and their IPs
- Displays which interfaces are available to VLESS clients
- Real-time connection status with interface info

---

## 💻 **Usage Examples**

### 📱 **Mobile Client Setup (NEW!)**
```bash
# Create client for phone
vless-manager
# Option 1: Create config
# Name: "my_iphone"
# 📱 QR code automatically displayed
# Scan with v2rayNG app - done!
```

### 👀 **View Existing QR Codes (NEW!)**
```bash
# View QR for existing client
vless-manager
# Option 2: Show configs
# Select client number: 1
# 📺 QR code shown in terminal
# 💾 PNG file location displayed
```

### 🔄 **OpenVPN + VLESS Setup (NEW!)**
```bash
# 1. Start your OpenVPN connection
sudo openvpn --config my_vpn.ovpn

# 2. Configure VLESS to use VPN
vless-manager
# Option 5: OpenVPN Integration
# ✅ Detects tun0 interface
# ✅ Configures routing through VPN
# ✅ VLESS clients now use VPN exit point
```

### 🗑️ **Delete with QR Cleanup**
```bash
vless-manager
# Option 3: Delete config
# Select number: 2
# ✅ Removes config, URL, AND QR code
```

---

## 🛠️ **File Structure (Enhanced)**

### 📂 **New File Locations**
```
/etc/vless-manager/
├── clients/                    # Client server configs
│   ├── client1.json             # Individual client configs
│   └── client2.json
├── urls/                       # Client connection URLs  
│   ├── client1.txt              # VLESS URLs
│   └── client2.txt
├── qr-codes/                   # QR CODE FILES (NEW!)
│   ├── client1.png              # QR codes as PNG images
│   └── client2.png
├── clients.db                  # SQLite database (enhanced with QR paths)
└── backup/                     # Automatic backups

/var/log/
└── vless-manager.log          # Application logs

/opt/vless-manager/
└── vless_manager.sh           # Main application v1.3
```

---

## 🔧 **Technical Improvements**

### 📱 **QR Code System**
- **Generator**: Uses `qrencode` for PNG generation
- **Terminal Display**: ANSI UTF-8 QR codes for terminal viewing
- **Storage**: Organized PNG files with client naming
- **Integration**: Database stores QR file paths

### 🌐 **Network Enhancement**
- **Interface Detection**: Automatic discovery of all network interfaces
- **Multi-Interface NAT**: MASQUERADE rules for all interfaces
- **VPN Detection**: Automatic detection of tun/tap/ppp interfaces
- **Enhanced Routing**: Traffic can exit through any available interface

### 📊 **Monitoring Improvements**
- **Interface Status**: Shows IP addresses for all interfaces
- **Connection Details**: Enhanced PID and port information
- **VPN Integration**: Shows available VPN tunnel information

---

## 📱 **Mobile App Compatibility**

### ✅ **Tested with QR Codes**
- **v2rayNG** (Android) - ✅ QR scan works perfectly
- **v2rayN** (Windows) - ✅ QR import supported
- **Shadowrocket** (iOS) - ✅ QR scan compatible
- **v2rayU** (macOS) - ✅ QR code import
- **Qv2ray** (Linux/Windows) - ✅ Manual paste or QR

### 📋 **Setup Instructions**
1. **Create VLESS config** with `vless-manager`
2. **Scan QR code** with your preferred app
3. **Connect instantly** - no manual configuration!

---

## ⭐ **Testing Results**

### 🧪 **v1.3 Features Verified**
```
✅ QR Code Generation: PNG files created successfully
✅ Terminal QR Display: ANSI UTF-8 codes working  
✅ Config Selection: Numbered interface working
✅ Multi-Interface NAT: All interfaces configured
✅ VPN Integration: OpenVPN routing functional
✅ Enhanced Monitoring: Interface IPs displayed
✅ Database Integration: QR paths stored correctly
```

### 📱 **Mobile Testing Results**
- ✅ **v2rayNG Android**: QR scan → instant connection
- ✅ **iPhone Shadowrocket**: QR import successful
- ✅ **Windows v2rayN**: QR code recognition working
- ✅ **Multiple configs**: Each client gets unique QR

### 🌐 **Network Testing Results**  
- ✅ **Ethernet (eth0)**: VLESS traffic routed correctly
- ✅ **WiFi (wlan0)**: Multi-interface access working
- ✅ **OpenVPN (tun0)**: VPN integration functional
- ✅ **Multiple interfaces**: Automatic failover working

---

## 🔄 **Update Instructions**

### 🚀 **Update from v1.2 to v1.3**
```bash
# Backup current config
sudo cp -r /etc/vless-manager /etc/vless-manager.backup

# Download latest version
git clone https://github.com/sweetpotatohack/vless-manager-fixed.git
cd vless-manager-fixed

# Run installer (preserves existing clients)
sudo ./install_vless_manager.sh

# Rebuild database with QR code support
vless-manager
# Select option 9 to rebuild database
# QR codes will be generated for existing configs
```

---

## 🤝 **Support & Issues**

### 🐛 **Reporting Issues**
Please include:
- **System information**: `uname -a`
- **QR code issues**: Include screenshot if terminal display fails
- **Network setup**: `ip addr show` output
- **VPN configuration**: OpenVPN logs if using VPN integration

### 💬 **Getting Help**
- 📚 **Documentation**: [GitHub Wiki](https://github.com/sweetpotatohack/vless-manager-fixed/wiki)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/sweetpotatohack/vless-manager-fixed/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/sweetpotatohack/vless-manager-fixed/discussions)

---

## 🌟 **Changelog**

### **v1.3-QR-ENHANCED** (Current - All New Features)
- 🆕 **QR Code Generation**: Automatic PNG QR codes for all configs
- 🆕 **Interactive Config Viewer**: Select configs by number to view QR  
- 🆕 **Multi-Interface Support**: VLESS access through ALL network interfaces
- 🆕 **OpenVPN Integration**: Seamless VPN tunnel routing
- 🆕 **Enhanced Monitoring**: Network interface status and IPs
- 🆕 **Terminal QR Display**: View QR codes directly in terminal
- ✅ **Database Enhancement**: QR file paths stored in database
- ✅ **Mobile Compatibility**: Tested with major mobile VPN apps

### **v1.2-FIXED** (Previous - Bug Fixes)
- ✅ Fixed PID display, database integration, deletion UI
- ✅ Added filesystem config discovery
- ✅ Enhanced error handling and stability

---

<div align="center">

**Made with 💀 by sweetpotatohack**

*"Now with QR codes for instant mobile setup!"*

**QR CODES + NETWORK ENHANCEMENT - v1.3 🚀📱**

</div>
