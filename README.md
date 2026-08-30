# SimpleX Chat Server Installer for Synology DSM

[English](#english) | [Русский](#русский)

Автоматическая установка и управление серверным стеком [SimpleX Chat](https://simplex.chat) на Synology DSM 7.1+ через **единый управляющий скрипт `simplex.sh`** (меню + CLI-команды).

Automatic installation and management of the [SimpleX Chat](https://simplex.chat) server stack on Synology DSM 7.1+ through a **single control script `simplex.sh`** (interactive menu + CLI commands).

📖 Инструкция / Guide: https://ceshbox-code.github.io/simplex-synology-installer/

<a name="english"></a>
## 🇬🇧 English

### Features
- ✅ One control script — `simplex.sh` — with an interactive menu and CLI commands: install, reinstall, restore, backups (plain & encrypted), web-panel password change, status, logs, status update, uninstall
- 🌐 Installer language selection: Russian / English
- 📂 Interactive selection of the base volume and the Web Station folder
- 🔒 Self-signed TLS certificates; encrypted backups (AES-256-CBC, OpenSSL)
- 📊 Web control panel with live status monitoring
- 💾 Automatic daily backup (03:00, 14-day retention) + on-demand encrypted backups to `/volumeN/docker/simp_bkp`
- 🛟 Restore script with archive integrity and SMP certificate algorithm checks
- 🗑 Safe full uninstall with recommended encrypted backup and triple confirmation
- ⚖️ Legal information included

### Requirements
- Synology NAS with DSM 7.1+
- Docker (Container Manager) installed via Package Center
- Domain name with DNS A records (`smp`, `files`, `turn`, `info.smp`)
- Ports forwarded on your router (5223, 5224, 7788, 3478, 5349, 49152–65535)
- At least 5 GB of free space

### Quick Start
Run this command in SSH (as root) — the interactive menu opens:

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/simplex.sh | bash
```

Or download the script and use CLI commands directly:

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/simplex.sh -o simplex.sh
sudo bash simplex.sh              # interactive menu
sudo bash simplex.sh install      # fresh installation
sudo bash simplex.sh restore      # restore from backup
sudo bash simplex.sh help         # full command reference
```

### Control script: menu and commands
| Menu | Command           | Action                                                       |
| ---- | ----------------- | ------------------------------------------------------------ |
| 1    | `install`         | Fresh installation (asks volume, web folder, IPs, domain)    |
| 2    | `reinstall`       | Reinstall using the saved `.env` configuration               |
| 3    | `restore`         | Restore from a backup archive (plain or encrypted)           |
| 4    | `passnew [login]` | Change web-panel password (and optionally login)             |
| 5    | `backup`          | Create a plain backup now                                    |
| 6    | `status`          | Container status                                             |
| 7    | `logs`            | Last 100 lines of container logs                             |
| 8    | `update`          | Regenerate `status.json` / `connection.js`                   |
| 9    | `uninstall`       | Full removal (encrypted backup recommended, triple confirmation) |
| 10   | `secure-backup`   | Create an encrypted backup in `/volumeN/docker/simp_bkp`     |
| 0    | —                 | Exit                                                         |
| —    | `help`            | Command reference                                            |

How `simplex.sh` resolves worker scripts: for each operation it first uses the **local** copy (`install.sh` / `restore.sh` / `passnew.sh`) from the installation directory (`BASE_DIR`) or the script's own folder; if absent, it **downloads** the script from the repository, strips CRLF and validates syntax (`bash -n`) before running. After a successful install, `restore.sh` and `passnew.sh` are stored in `BASE_DIR`, so restore/password change work offline.

### Typical workflow
1. **Prepare**: DNS records, port forwarding, DSM firewall, Docker, SSH (see the [guide](https://ceshbox-code.github.io/simplex-synology-installer/)).
2. **Install**: menu item 1 / `install`. The installer collects settings, creates directories, certificates, `.env`, `docker-compose.yml`, initializes XFTP, pulls pinned images (SMP/XFTP `v6.5.2`, coturn `4.6.3-r0`), starts containers, obtains fingerprints, deploys the web panel and creates cron jobs (daily backup at 03:00; status update every minute).
3. **Configure Web Station** and save `CONNECTION_DETAILS.txt` (contains all addresses and the one-time web password).
4. **Operate** via the menu: status, logs, backups, password change.
5. **Restore** any time via menu item 3 / `restore` (from `backups/` or encrypted `simp_bkp/` archives).
6. **Uninstall** via menu item 9 / `uninstall` if ever needed.

### Installation paths
| Location                   | Purpose                                                      |
| -------------------------- | ------------------------------------------------------------ |
| `/volumeX/docker/simplex`  | Server data, configs, certificates, scripts (volume selected during install) |
| `/volumeX/web/simplex`     | Control panel web files for Web Station (volume selected during install) |
| `/volumeX/docker/simp_bkp` | Encrypted backups (outside `BASE_DIR`, so they survive uninstall) |

### Repository structure
| File            | Description                                                  |
| --------------- | ------------------------------------------------------------ |
| `simplex.sh`    | **Control script**: interactive menu + CLI (install/restore/backup/uninstall/…) |
| `install.sh`    | Installation worker script (called by `simplex.sh`)          |
| `restore.sh`    | Interactive restore-from-backup script (integrity + certificate checks) |
| `passnew.sh`    | Web-panel password/login rotation script                     |
| `index.html`    | Public instruction page ([GitHub Pages](https://ceshbox-code.github.io/simplex-synology-installer/), RU/EN) |
| `README.md`     | This file                                                    |
| `qrcode.min.js` | QR code generation library                                   |
| `favicon.ico`   | Site icon                                                    |

### Backup & Restore
- **Plain backup** — `simplex-backup.sh` runs daily at 03:00 via cron (and on demand, menu 5). Archive contains `.env`, `docker-compose.yml`, `CONNECTION_DETAILS.txt`, SMP/XFTP identity, data and certificates; kept 14 days in `<BASE_DIR>/backups/`.
- **Encrypted backup** — menu 10 / `secure-backup`: creates a plain backup, encrypts it with AES-256-CBC into `/volumeN/docker/simp_bkp/simplex-secure-backup-*.tar.gz.enc`, verifies it and deletes the plain file. **The password is shown once and stored nowhere.** Encrypted archives are not auto-deleted — manage them manually and keep a copy off the NAS.
- **Restore** — menu 3 / `restore.sh`: lists all archives (including `.enc`, password required, encryption mode auto-detected), verifies integrity, checks that the SMP transport key is Ed25519 (auto-repair offered if a buggy RSA-overwritten backup is detected), then restores with old or new settings and starts the containers.

### Known issue (fixed)
Prior to the fix applied on 2026-08-27, re-running `install.sh` on an existing installation could overwrite the SMP transport certificate (`smp/config/server.key`/`server.crt`, Ed25519, signed by the server's own CA) with the RSA certificate meant only for the web dashboard. This caused the SMP container to crash-loop with `smp-server: user error (unknown key algorithm)`. `install.sh` no longer touches `smp/config/server.*`, and `restore.sh` detects and repairs this condition automatically (re-signing a new Ed25519 certificate with the existing CA, so the server Fingerprint and client addresses are unaffected).

### Disclaimer
The author is not responsible for any consequences of using the scripts. The project is intended solely for personal and family use.

<a name="русский"></a>
## 🇷🇺 Русский

### Возможности
- ✅ Один управляющий скрипт — `simplex.sh` — с интерактивным меню и CLI-командами: установка, переустановка, восстановление, резервные копии (обычные и зашифрованные), смена пароля панели, статус, логи, обновление статуса, полное удаление
- 🌐 Выбор языка: русский / английский
- 📂 Интерактивный выбор тома и папки Web Station
- 🔒 Self-signed TLS-сертификаты; зашифрованные бэкапы (AES-256-CBC, OpenSSL)
- 📊 Веб-панель управления с мониторингом статуса
- 💾 Ежедневный автоматический бэкап (03:00, хранение 14 дней) + зашифрованные бэкапы по запросу в `/volumeN/docker/simp_bkp`
- 🛟 Восстановление с проверкой целостности архива и алгоритма сертификата SMP
- 🗑 Безопасное полное удаление с рекомендованным зашифрованным бэкапом и тройным подтверждением
- ⚖️ Правовая информация (ФЗ-149, ФЗ-152)

### Требования
- Synology NAS с DSM 7.1+
- Docker (Container Manager) из Package Center
- Домен с A-записями (`smp`, `files`, `turn`, `info.smp`)
- Проброшенные порты (5223, 5224, 7788, 3478, 5349, 49152–65535)
- Минимум 5 ГБ свободного места

### Быстрый старт
Выполните в SSH от root — откроется интерактивное меню:

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/simplex.sh | bash
```

Или скачайте скрипт и используйте CLI-команды:

```bash
curl -fsSL https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/simplex.sh -o simplex.sh
sudo bash simplex.sh              # интерактивное меню
sudo bash simplex.sh install      # новая установка
sudo bash simplex.sh restore      # восстановление из бэкапа
sudo bash simplex.sh help         # справка по командам
```

### Управляющий скрипт: меню и команды
| Меню | Команда           | Действие                                                     |
| ---- | ----------------- | ------------------------------------------------------------ |
| 1    | `install`         | Новая установка (том, веб-папка, IP, домен)                  |
| 2    | `reinstall`       | Переустановка с сохранённым `.env`                           |
| 3    | `restore`         | Восстановление из архива (обычного или зашифрованного)       |
| 4    | `passnew [логин]` | Смена пароля веб-панели (и логина при желании)               |
| 5    | `backup`          | Создать обычную резервную копию сейчас                       |
| 6    | `status`          | Статус контейнеров                                           |
| 7    | `logs`            | Последние 100 строк логов контейнеров                        |
| 8    | `update`          | Пересоздать `status.json` / `connection.js`                  |
| 9    | `uninstall`       | Полное удаление (рекомендуется зашифрованный бэкап, тройное подтверждение) |
| 10   | `secure-backup`   | Зашифрованный бэкап в `/volumeN/docker/simp_bkp`             |
| 0    | —                 | Выход                                                        |
| —    | `help`            | Справка                                                      |

Как `simplex.sh` ищет рабочие скрипты: сначала используется **локальная** копия (`install.sh` / `restore.sh` / `passnew.sh`) из папки установки (`BASE_DIR`) или из папки самого скрипта; если её нет — скрипт **скачивается** из репозитория, очищается от CRLF и проверяется (`bash -n`) перед запуском. После установки `restore.sh` и `passnew.sh` лежат в `BASE_DIR`, поэтому восстановление и смена пароля работают без интернета.

### Типовой сценарий
1. **Подготовка**: DNS, проброс портов, брандмауэр DSM, Docker, SSH (см. [инструкцию](https://ceshbox-code.github.io/simplex-synology-installer/)).
2. **Установка**: пункт меню 1 / `install`. Скрипт собирает настройки, создаёт директории, сертификаты, `.env`, `docker-compose.yml`, инициализирует XFTP, загружает зафиксированные образы (SMP/XFTP `v6.5.2`, coturn `4.6.3-r0`), запускает контейнеры, получает fingerprint, разворачивает веб-панель и создаёт cron-задачи (бэкап в 03:00; статус каждую минуту).
3. **Настройка Web Station** и сохранение `CONNECTION_DETAILS.txt` (все адреса и одноразовый пароль панели).
4. **Эксплуатация** через меню: статус, логи, бэкапы, смена пароля.
5. **Восстановление** в любой момент: пункт 3 / `restore` (из `backups/` или зашифрованных `simp_bkp/`).
6. **Удаление** при необходимости: пункт 9 / `uninstall`.

### Пути установки
| Расположение               | Назначение                                                   |
| -------------------------- | ------------------------------------------------------------ |
| `/volumeX/docker/simplex`  | Данные серверов, конфиги, сертификаты, скрипты               |
| `/volumeX/web/simplex`     | Веб-файлы панели для Web Station                             |
| `/volumeX/docker/simp_bkp` | Зашифрованные бэкапы (вне `BASE_DIR` — переживают uninstall) |

### Структура репозитория
| Файл            | Назначение                                                   |
| --------------- | ------------------------------------------------------------ |
| `simplex.sh`    | **Управляющий скрипт**: меню + CLI (install/restore/backup/uninstall/…) |
| `install.sh`    | Рабочий скрипт установки (вызывается из `simplex.sh`)        |
| `restore.sh`    | Интерактивное восстановление из бэкапа (проверки целостности и сертификата) |
| `passnew.sh`    | Смена пароля/логина веб-панели                               |
| `index.html`    | Публичная страница-инструкция (GitHub Pages, RU/EN)          |
| `README.md`     | Этот файл                                                    |
| `qrcode.min.js` | Библиотека QR-кодов                                          |
| `favicon.ico`   | Иконка сайта                                                 |

### Резервное копирование и восстановление
- **Обычный бэкап** — `simplex-backup.sh` ежедневно в 03:00 через cron (и по запросу, пункт 5). В архиве: `.env`, `docker-compose.yml`, `CONNECTION_DETAILS.txt`, identity, данные и сертификаты SMP/XFTP; хранение 14 дней в `<BASE_DIR>/backups/`.
- **Зашифрованный бэкап** — пункт 10 / `secure-backup`: создаёт обычный бэкап, шифрует AES-256-CBC в `/volumeN/docker/simp_bkp/simplex-secure-backup-*.tar.gz.enc`, проверяет и удаляет незашифрованный файл. **Пароль показывается один раз и нигде не хранится.** Зашифрованные архивы не удаляются автоматически — храните копию вне NAS.
- **Восстановление** — пункт 3 / `restore.sh`: показывает все архивы (включая `.enc` — потребуется пароль, метод шифрования определяется автоматически), проверяет целостность и алгоритм транспортного ключа SMP (Ed25519; при обнаружении «битого» RSA-бэкапа предлагает автопочинку), восстанавливает со старыми или новыми настройками и запускает контейнеры.

### Известная проблема (исправлена)
До исправления от 27.08.2026 повторный запуск `install.sh` мог перезаписать транспортный сертификат SMP (Ed25519, подписанный собственным CA) RSA-сертификатом веб-панели, из-за чего SMP падал в цикле рестартов с `smp-server: user error (unknown key algorithm)`. Теперь `install.sh` не трогает `smp/config/server.*`, а `restore.sh` автоматически обнаруживает и исправляет это (перевыпуск Ed25519-сертификата тем же CA — Fingerprint и адреса клиентов не меняются).

### Отказ от ответственности
Автор не несёт ответственности за последствия использования скриптов. Проект предназначен исключительно для личного и семейного использования.