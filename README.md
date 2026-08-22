# SimpleX Chat Server Installer for Synology DSM

[English](#english) | [Русский](#russian)

Automatic installer for the [SimpleX Chat](https://simplex.chat) server stack on Synology DSM 7.1+.
Автоматический установщик серверного стека [SimpleX Chat](https://simplex.chat) для Synology DSM 7.1+.

---

<a name="english"></a>
## 🇬🇧 English

### Features
- ✅ One-command installation of SMP, XFTP, and TURN servers
- 🔒 Automatic generation of TLS certificates
- 📊 Web control panel with status monitoring
- 💾 Automatic backup script
- 📱 Client installation guide with QR codes
- ⚖️ Legal information included

### Requirements
- Synology NAS with DSM 7.1+
- Docker (Container Manager) installed via Package Center
- Domain name with configured DNS A records
- Ports forwarded on your router
- At least 5 GB of free space

### Quick Start
Run this command in SSH (as root):
```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/install.sh | sudo /bin/bash