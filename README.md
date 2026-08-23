# SimpleX Chat Server Installer for Synology DSM

[English](#english) | [Русский](#русский)

Автоматический установщик серверного стека [SimpleX Chat](https://simplex.chat) для Synology DSM 7.1+.
Automatic installer for the [SimpleX Chat](https://simplex.chat) server stack on Synology DSM 7.1+.

---

<a name="english"></a>
## 🇬🇧 English

### Features
- ✅ One-command installation of SMP, XFTP, and TURN servers
- 🌐 Installer language selection: Russian / English
- 📂 Interactive selection of the base volume and the Web Station folder
- 🔒 Automatic generation of self-signed TLS certificates
- 📊 Web control panel with live status monitoring
- 💾 Automatic backup script (daily at 03:00, 14-day retention)
- 📱 Client installation guide with QR codes
- ⚖️ Legal information included

### Requirements
- Synology NAS with DSM 7.1+
- Docker (Container Manager) installed via Package Center
- Domain name with configured DNS A records (`smp`, `files`, `turn`, `info.smp`)
- Ports forwarded on your router (5223, 5224, 7788, 3478, 5349, 49152–65535)
- At least 5 GB of free space

### Quick Start
Run this command in SSH (as root):

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/install.sh | /bin/bash
```

### Installation paths
| Location | Purpose |
| :--- | :--- |
| `/volumeX/docker/simplex` | Server data, configs, certificates (volume selected during install) |
| `/volumeX/web/simplex` | Control panel web files for Web Station (volume selected during install) |

### Repository Structure
| File | Description |
| :--- | :--- |
| `install.sh` | Installation script |
| `index.html` | Public instruction page (GitHub Pages, RU/EN) |
| `README.md` | This file |
| `qrcode.min.js` | QR code generation library |
| `favicon.ico` | Site icon |

### Disclaimer
The author is not responsible for any consequences of using the script.
The script is intended solely for personal and family use.
---

<a name="русский"></a>
## 🇷🇺 Русский

### Возможности
- ✅ Установка SMP, XFTP, TURN серверов одной командой
- 🌐 Выбор языка установщика: русский / английский
- 📂 Интерактивный выбор базового тома и папки для Web Station
- 🔒 Автоматическая генерация self-signed TLS-сертификатов
- 📊 Веб-панель управления с мониторингом статуса в реальном времени
- 💾 Скрипт автоматического резервного копирования (ежедневно в 03:00, хранение 14 дней)
- 📱 Инструкция по установке клиента на смартфон с QR-кодами
- ⚖️ Правовая информация (ФЗ-149, ФЗ-152)

### Требования
- Synology NAS с DSM 7.1+
- Docker (Container Manager), установленный через Package Center
- Доменное имя с настроенными DNS A-записями (`smp`, `files`, `turn`, `info.smp`)
- Проброшенные порты на роутере (5223, 5224, 7788, 3478, 5349, 49152–65535)
- Минимум 5 ГБ свободного места

### Быстрый старт
Выполните эту команду в SSH (от имени root):

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/install.sh | /bin/bash
```

### Пути установки
| Расположение | Назначение |
| :--- | :--- |
| `/volumeX/docker/simplex` | Данные серверов, конфигурации, сертификаты (том выбирается при установке) |
| `/volumeX/web/simplex` | Веб-файлы панели управления для Web Station (том выбирается при установке) |

### Структура репозитория
| Файл | Назначение |
| :--- | :--- |
| `install.sh` | Скрипт установки |
| `index.html` | Публичная страница-инструкция (GitHub Pages, RU/EN) |
| `README.md` | Этот файл |
| `qrcode.min.js` | Библиотека генерации QR-кодов |
| `favicon.ico` | Иконка сайта |

### Отказ от ответственности
Автор не несёт ответственности за последствия использования скрипта.
Скрипт предназначен исключительно для личного и семейного использования.