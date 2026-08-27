# SimpleX Chat Server Installer for Synology DSM

[English](#english) | [Русский](#русский)

Автоматический установщик серверного стека [SimpleX Chat](https://simplex.chat) для Synology DSM 7.1+.
Automatic installer for the [SimpleX Chat](https://simplex.chat) server stack on Synology DSM 7.1+.

📖 **Инструкция / Guide:** https://ceshbox-code.github.io/simplex-synology-installer/

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
- 🛟 Interactive restore script (`restore.sh`) with archive integrity and certificate algorithm checks
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
| `restore.sh` | Interactive restore-from-backup script (integrity + certificate checks) |
| `index.html` | Public instruction page ([GitHub Pages](https://ceshbox-code.github.io/simplex-synology-installer/), RU/EN) |
| `README.md` | This file |
| `qrcode.min.js` | QR code generation library |
| `favicon.ico` | Site icon |

### Backup & Restore

Every day at 03:00 the server (via `simplex-backup.sh`, installed by `install.sh`) creates a `simplex-backup-YYYYMMDD_HHMMSS.tar.gz` archive containing `.env`, `docker-compose.yml`, `CONNECTION_DETAILS.txt`, and the SMP/XFTP identity, data and certificates. Archives are kept for 14 days in `<BASE_DIR>/backups/`.

To restore, run `restore.sh` on the NAS (as root):

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/restore.sh -o restore.sh
chmod +x restore.sh
sudo /bin/bash restore.sh
```

The script:
1. Lists all found backup archives (scans `/volume*/docker/simplex/backups/`) and lets you pick one.
2. Verifies archive integrity, lists its contents, and checks that the SMP transport key (`smp/config/server.key`) uses the correct **Ed25519** algorithm — catching backups affected by the certificate bug described below before they're restored.
3. Lets you choose between restoring with the **existing settings** (same volume, domain, IP) or **new settings** (choose a different volume, external IP, or domain — as in the original installer).
4. Extracts the archive, reissues the SMP certificate if needed, and starts the containers.

### Known issue (fixed)

Prior to the fix applied on 2026-08-27, re-running `install.sh` on an existing installation could overwrite the SMP transport certificate (`smp/config/server.key`/`server.crt`, Ed25519, signed by the server's own CA) with the RSA certificate meant only for the web dashboard. This caused the SMP container to crash-loop with `smp-server: user error (unknown key algorithm)`. `install.sh` no longer touches `smp/config/server.*`, and `restore.sh` detects and repairs this condition automatically (re-signing a new Ed25519 certificate with the existing CA, so the server Fingerprint and client addresses are unaffected).

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
- 🛟 Интерактивный скрипт восстановления (`restore.sh`) с проверкой целостности архива и алгоритма сертификата
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
| `restore.sh` | Интерактивный скрипт восстановления из бэкапа (с проверками целостности и сертификата) |
| `index.html` | Публичная страница-инструкция ([GitHub Pages](https://ceshbox-code.github.io/simplex-synology-installer/), RU/EN) |
| `README.md` | Этот файл |
| `qrcode.min.js` | Библиотека генерации QR-кодов |
| `favicon.ico` | Иконка сайта |

### Резервное копирование и восстановление

Каждый день в 03:00 сервер (через `simplex-backup.sh`, устанавливается `install.sh`) создаёт архив `simplex-backup-YYYYMMDD_HHMMSS.tar.gz`, содержащий `.env`, `docker-compose.yml`, `CONNECTION_DETAILS.txt`, а также identity, данные и сертификаты SMP/XFTP. Архивы хранятся 14 дней в `<BASE_DIR>/backups/`.

Для восстановления запустите на NAS `restore.sh` (от имени root):

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/restore.sh -o restore.sh
chmod +x restore.sh
sudo /bin/bash restore.sh
```

Скрипт:
1. Находит все архивы бэкапа (сканирует `/volume*/docker/simplex/backups/`) и предлагает выбрать нужный.
2. Проверяет целостность архива, выводит его содержимое и проверяет, что транспортный ключ SMP (`smp/config/server.key`) использует правильный алгоритм **Ed25519** — это позволяет отловить бэкапы, затронутые описанным ниже багом, ещё до восстановления.
3. Предлагает выбрать: восстановить с **существующими настройками** (тот же том, домен, IP) или с **новыми настройками** (другой том, внешний IP или домен — как в оригинальном установщике).
4. Распаковывает архив, при необходимости перевыпускает сертификат SMP и запускает контейнеры.

### Известная проблема (исправлена)

До исправления, внесённого 27.08.2026, повторный запуск `install.sh` на уже установленном сервере мог перезаписать транспортный сертификат SMP (`smp/config/server.key`/`server.crt`, Ed25519, подписанный собственным CA сервера) RSA-сертификатом, предназначенным только для веб-панели. Это приводило к падению контейнера SMP в цикле рестартов с ошибкой `smp-server: user error (unknown key algorithm)`. Теперь `install.sh` не трогает `smp/config/server.*`, а `restore.sh` автоматически обнаруживает и исправляет эту ситуацию (перевыпускает Ed25519-сертификат тем же CA — Fingerprint сервера и адреса клиентов при этом не меняются).

### Отказ от ответственности
Автор не несёт ответственности за последствия использования скрипта.
Скрипт предназначен исключительно для личного и семейного использования.