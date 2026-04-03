<div align="center">

# 🔥 VLESS Manager Pro v2.0 — VLESS + TLS + Xray + systemd

## Ultimate VPN Management — QR codes, Let’s Encrypt, sing-box bundles

<img src="https://img.shields.io/badge/Version-2.0-brightgreen?style=for-the-badge" alt="Version">
<img src="https://img.shields.io/badge/Status-stable-success?style=for-the-badge" alt="Status">
<img src="https://img.shields.io/badge/Platform-Linux-orange?style=for-the-badge" alt="Platform">
<img src="https://img.shields.io/badge/TLS-LE%20or%20self--signed-blue?style=for-the-badge" alt="TLS">

**Professional VLESS server management on Linux (Xray-core, `vless-servers`, `vless-xray.service`).**

![GitHub stars](https://img.shields.io/github/stars/sweetpotatohack/vless-manager?style=social)
![GitHub forks](https://img.shields.io/github/forks/sweetpotatohack/vless-manager?style=social)

**Canonical repository:** [sweetpotatohack/vless-manager](https://github.com/sweetpotatohack/vless-manager)

</div>

---

## 🎯 **Highlights**

### 🔥 **MAJOR FEATURES**
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

### 🆕 **Recent enhancements**
- **📱 QR Code Generation**: Automatic QR codes created for each config
- **📺 Terminal QR Display**: View QR codes directly in terminal
- **💾 QR Code Storage**: QR codes saved as PNG files in `/etc/vless-manager/qr-codes/`
- **🔗 Easy Mobile Setup**: Scan QR codes to instantly connect
- **🌐 Multi-Interface Support**: Access through ALL network interfaces (eth0, wlan0, tun0, etc.)
- **🔄 VPN Passthrough**: OpenVPN/WireGuard traffic routing
- **📊 Enhanced Monitoring**: Network interface status and IPs

---

## 🚀 **Full installation (server)**

Install **on a Linux VPS** as **root** (Debian/Ubuntu or RHEL/CentOS family). The installer ships **Xray**, **sqlite3**, **qrencode**, **certbot** (when needed), **iptables/UFW** rules for VLESS ports **25000–45000**, and registers **`vless-xray.service`** (uses **`vless-servers start|stop`**).

### Prerequisites

| Topic | Notes |
|--------|--------|
| **OS** | Debian/Ubuntu or RHEL/CentOS (see installer checks). |
| **DNS (Let’s Encrypt)** | **A** record of your domain must point to this server’s **IPv4**. If **AAAA (IPv6)** exists but does not reach this host, validation often fails — remove AAAA or fix IPv6. **Cloudflare:** use **DNS only** (grey cloud), not **Proxied**. |
| **Port 80** | Required **during issuance/renewal** of Let’s Encrypt (**HTTP-01**, certbot **standalone**). Open **80/tcp** from the Internet and stop nginx/apache on :80 for that step if they conflict. |
| **Non-interactive install** | Running `install_vless_manager.sh` **without a TTY** (e.g. piped or automated) skips Let’s Encrypt prompts → **self-signed TLS** (enable **Allow insecure** / skip verify in clients unless you add real certs later). |
| **Git** | Required on the server to clone this repository (`apt install git` / `yum install git` if missing). |

### ⚡ Quick install (recommended)

```bash
git clone --depth 1 https://github.com/sweetpotatohack/vless-manager.git
cd vless-manager
chmod +x install_vless_manager.sh
sudo ./install_vless_manager.sh
```

### 📋 Same thing in one line

```bash
git clone --depth 1 https://github.com/sweetpotatohack/vless-manager.git /tmp/vless-manager && cd /tmp/vless-manager && chmod +x install_vless_manager.sh && sudo ./install_vless_manager.sh
```

(Install **`git`** first if the system does not have it.)

If the installer is started **outside** the repo directory (e.g. copied scripts only), set:

```bash
export VLESS_MANAGER_REPO=/path/to/vless-manager
sudo -E ./install_vless_manager.sh
```

### TLS during `install_vless_manager.sh`

- **Let’s Encrypt:** enter **FQDN** (e.g. `vpn.example.com`) and a valid **email**. Installer runs **certbot certonly --standalone**, writes **`/etc/vless-manager/tls.env`**, and installs a **renewal hook** that restarts **`vless-xray`** after renew.
- **Self-signed:** press **Enter** at the domain prompt (or invalid email) → clients must allow **insecure** / self-signed unless you replace certs manually.
- **UFW active:** installer adds **VLESS TCP range** and **80/tcp** when Let’s Encrypt is used.

### After install

```bash
vless-manager              # interactive menu
vless-servers status       # per-client Xray processes
systemctl status vless-xray
```

Server-side client material:

- VLESS URLs: `/etc/vless-manager/urls/<client>.txt`
- QR PNG: `/etc/vless-manager/qr-codes/<client>.png`
- **sing-box** bundles: `/etc/vless-manager/bundles/<client>.sing-box.json`

Logs: `/var/log/vless-manager.log`, per-client: `/var/log/vless-<name>.log`; systemd: `journalctl -u vless-xray`.

---

## 💻 **Connecting from a PC (Windows & Linux)**

For **desktop** machines, use **[v2rayN](https://github.com/2dust/v2rayN)** — a GUI client for **Windows and Linux** (and macOS) with **Xray** and **sing-box** support. Import your **VLESS** link from `/etc/vless-manager/urls/<name>.txt` (or scan the same QR you use on the phone), or open the generated **sing-box** JSON if the app supports it.

- **Project:** [github.com/2dust/v2rayN](https://github.com/2dust/v2rayN)  
- **Releases:** install the build for your OS from the project’s **Releases** page; on Linux follow the project’s notes for TUN/capabilities if you use TUN mode.

Mobile clients (v2rayNG, Shadowrocket, etc.) can keep using QR / URL as before.

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

#### **Mobile setup**
```bash
1. Create config: vless-manager → option 1 → enter name
2. Scan QR code with v2rayNG / Shadowrocket / similar
3. On PC (Windows/Linux): import the same URL in v2rayN — see section above
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
├── bundles/                    # sing-box JSON per client
├── tls.env                     # TLS mode (Let's Encrypt or self-signed)
├── clients.db                  # SQLite database (QR paths, etc.)
└── backup/                     # Automatic backups

/var/log/
├── vless-manager.log           # Manager log
└── vless-<client>.log          # Per-client Xray logs (when used)

/opt/vless-manager/
└── vless_manager.sh           # Main application
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

## 📱 **Client compatibility**

### **PC — Windows & Linux (recommended)**

Use **[v2rayN](https://github.com/2dust/v2rayN)** to import the VLESS URL or QR ([releases](https://github.com/2dust/v2rayN/releases)).

### **Mobile & other**

- **v2rayNG** (Android) — QR / URL  
- **Shadowrocket** (iOS) — QR / URL  
- **v2rayN** (Windows / Linux / macOS) — same project as desktop above  
- Other Xray/sing-box clients — paste URL from `/etc/vless-manager/urls/<name>.txt`

### 📋 **Quick steps**

1. Create a client in `vless-manager` (QR + URL file on server).  
2. **Phone:** scan QR. **PC:** open the same link in **v2rayN**.  
3. Connect using the client’s docs (system proxy / TUN as needed).

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

## 🔄 **Update**

```bash
sudo cp -r /etc/vless-manager /etc/vless-manager.backup

git clone https://github.com/sweetpotatohack/vless-manager.git
cd vless-manager
sudo ./install_vless_manager.sh
```

Re-run **`vless-manager`** and use **rebuild DB / resync** options if the menu offers them after an upgrade. A full reinstall **purges** `/etc/vless-manager` — always **backup** first.

---

## 🤝 **Support & Issues**

### 🐛 **Reporting Issues**
Please include:
- **System information**: `uname -a`
- **QR code issues**: Include screenshot if terminal display fails
- **Network setup**: `ip addr show` output
- **VPN configuration**: OpenVPN logs if using VPN integration

### 💬 **Getting Help**
- 📚 **Repository**: [sweetpotatohack/vless-manager](https://github.com/sweetpotatohack/vless-manager)
- 🐛 **Issues**: [GitHub Issues](https://github.com/sweetpotatohack/vless-manager/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/sweetpotatohack/vless-manager/discussions)

---

## 🌟 **Changelog**

### **v2.0** (installer / TLS)

- Let’s Encrypt via **certbot** (optional), **`tls.env`**, renewal hook for **`vless-xray`**
- **UFW/iptables**: VLESS port range + **:80** when LE is used
- **`resolve_install_repo_root`**: install works when not run from repo cwd
- **`vless-servers`** / **`vless-xray.service`**: start/stop lifecycle fixes
- Install only via **`install_vless_manager.sh`** (after `git clone` of **`sweetpotatohack/vless-manager`**)

### **v1.3-QR-ENHANCED**
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

**VLESS Manager Pro — v2.0 🚀**

</div>
