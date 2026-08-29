#!/bin/bash
# ==============================================================================
# SimpleX Chat Server Suite — Restore from Backup (Synology DSM 7.1+)
# Версия: 1.0
# Восстанавливает архив, созданный simplex-backup.sh
# ==============================================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# === ВЫБОР ЯЗЫКА / LANGUAGE SELECTION ===
echo ""
echo "=========================================="
echo "  SIMPLEX CHAT RESTORE v1.0 — SYNOLOGY"
echo "=========================================="
echo ""
echo "Выберите язык / Select language:"
echo "  1) Русский"
echo "  2) English"
echo ""
read -p "Ваш выбор / Your choice [1]: " LANG_CHOICE < /dev/tty
LANG_CHOICE=${LANG_CHOICE:-1}
if [ "$LANG_CHOICE" = "2" ]; then LANG_EN=true; else LANG_EN=false; fi

info()    { if [ "$LANG_EN" = true ]; then echo -e "${BLUE}[INFO]${NC} $2"; else echo -e "${BLUE}[INFO]${NC} $1"; fi; }
success() { if [ "$LANG_EN" = true ]; then echo -e "${GREEN}[ OK ]${NC} $2"; else echo -e "${GREEN}[ OK ]${NC} $1"; fi; }
warn()    { if [ "$LANG_EN" = true ]; then echo -e "${YELLOW}[WARN]${NC} $2"; else echo -e "${YELLOW}[WARN]${NC} $1"; fi; }
error()   { if [ "$LANG_EN" = true ]; then echo -e "${RED}[ERR ]${NC} $2"; exit 1; else echo -e "${RED}[ERR ]${NC} $1"; exit 1; fi; }
ok_line() { echo -e "  ${GREEN}[ OK ]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт требует прав суперпользователя. Выполните: sudo /bin/bash $0" \
          "Script requires superuser privileges. Run: sudo /bin/bash $0"
fi
command -v tar    &>/dev/null || error "tar не найден." "tar not found."
command -v docker &>/dev/null || error "Docker не установлен." "Docker not installed."
command -v openssl &>/dev/null || error "openssl не найден." "openssl not found."
command -v ip     &>/dev/null || error "ip не найден." "ip not found."

COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    command -v docker-compose &>/dev/null || error "Docker Compose не найден." "Docker Compose not found."
fi

# ==============================================================================
# 1. ПОИСК АРХИВОВ БЭКАПА
# ==============================================================================
info "Поиск архивов резервных копий..." "Searching for backup archives..."

BACKUP_FILES=()
for v in /volume*; do
    if [ -d "$v/docker/simplex/backups" ]; then
        while IFS= read -r -d '' f; do
            BACKUP_FILES+=("$f")
        done < <(find "$v/docker/simplex/backups" -maxdepth 1 -name "simplex-backup-*.tar.gz" -print0 2>/dev/null)
    fi
done
# Также проверим текущую директорию на случай локального запуска
while IFS= read -r -d '' f; do
    BACKUP_FILES+=("$f")
done < <(find "$(pwd)" -maxdepth 1 -name "simplex-backup-*.tar.gz" -print0 2>/dev/null)

# Убираем дубликаты, сортируем по дате (новые сверху)
if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
    error "Архивы резервных копий не найдены (искали в /volume*/docker/simplex/backups)." \
          "No backup archives found (searched /volume*/docker/simplex/backups)."
fi

mapfile -t BACKUP_FILES < <(printf '%s\n' "${BACKUP_FILES[@]}" | sort -u | sort -r)

echo ""
info "Найденные архивы:" "Found archives:"
echo ""
idx=1
for f in "${BACKUP_FILES[@]}"; do
    SIZE=$(du -h "$f" 2>/dev/null | cut -f1)
    DATE=$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1)
    printf "  %2d) %s  (%s, %s)\n" "$idx" "$f" "$SIZE" "$DATE"
    idx=$((idx + 1))
done
echo ""

while true; do
    read -p "$( [ "$LANG_EN" = true ] && echo 'Select archive number: ' || echo 'Выберите номер архива: ' )" ARCH_CHOICE < /dev/tty
    if [[ "$ARCH_CHOICE" =~ ^[0-9]+$ ]] && [ "$ARCH_CHOICE" -ge 1 ] && [ "$ARCH_CHOICE" -le ${#BACKUP_FILES[@]} ]; then
        SELECTED_ARCHIVE="${BACKUP_FILES[$((ARCH_CHOICE - 1))]}"
        break
    else
        warn "Некорректный выбор. Введите число от 1 до ${#BACKUP_FILES[@]}." \
             "Invalid choice. Enter a number from 1 to ${#BACKUP_FILES[@]}."
    fi
done

info "Выбран архив: $SELECTED_ARCHIVE" "Selected archive: $SELECTED_ARCHIVE"

# ==============================================================================
# 2. ПРОВЕРКА ЦЕЛОСТНОСТИ АРХИВА
# ==============================================================================
echo ""
info "Проверка целостности архива..." "Checking archive integrity..."
echo ""

if ! gzip -t "$SELECTED_ARCHIVE" 2>/dev/null; then
    error "Архив повреждён (ошибка gzip). Восстановление невозможно." \
          "Archive is corrupted (gzip error). Restore is not possible."
fi

ARCHIVE_LIST=$(tar -tzf "$SELECTED_ARCHIVE" 2>/dev/null) || \
    error "Не удалось прочитать содержимое архива (ошибка tar)." \
          "Failed to read archive contents (tar error)."

if [ -z "$ARCHIVE_LIST" ]; then
    error "Архив пуст." "Archive is empty."
fi

if [ "$LANG_EN" = true ]; then
    echo "Archive contents:"
else
    echo "Содержимое архива:"
fi
echo ""
while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    ok_line "$entry"
done <<< "$ARCHIVE_LIST"
echo ""

# Проверка наличия ключевых файлов
REQUIRED_ITEMS=(".env" "docker-compose.yml" "smp/config" "xftp/config")
MISSING=0
for item in "${REQUIRED_ITEMS[@]}"; do
    if ! echo "$ARCHIVE_LIST" | grep -q "^${item}"; then
        warn "В архиве отсутствует: $item" "Missing from archive: $item"
        MISSING=1
    fi
done
if [ "$MISSING" -eq 1 ]; then
    warn "Некоторые ожидаемые элементы отсутствуют. Продолжайте с осторожностью." \
         "Some expected items are missing. Proceed with caution."
fi

success "Архив цел и пригоден для восстановления." "Archive is intact and ready for restore."

# ==============================================================================
# 2b. ПРОВЕРКА АЛГОРИТМА ТРАНСПОРТНОГО КЛЮЧА SMP (Ed25519 vs RSA)
# ------------------------------------------------------------------------------
# smp/config/server.key ДОЛЖЕН быть Ed25519 (подписан ca.key самим smp-server).
# Известный баг install.sh <= v9.5 при повторном запуске мог затереть его RSA-
# сертификатом, предназначенным для веб-панели, что вызывает падение SMP
# контейнера в цикле рестартов с ошибкой "unknown key algorithm". Проверяем
# архив ДО распаковки и запуска контейнеров.
# ==============================================================================
echo ""
info "Проверка алгоритма транспортного TLS-ключа SMP..." "Checking SMP transport TLS key algorithm..."

NEEDS_CERT_REPAIR=0
SERVER_KEY_ALGO=""

if echo "$ARCHIVE_LIST" | grep -q "^smp/config/server\.key$"; then
    SERVER_KEY_CHECK=$(mktemp)
    if tar -xzOf "$SELECTED_ARCHIVE" smp/config/server.key > "$SERVER_KEY_CHECK" 2>/dev/null; then
        SERVER_KEY_ALGO=$(openssl pkey -in "$SERVER_KEY_CHECK" -noout -text 2>/dev/null | head -1)
    fi
    rm -f "$SERVER_KEY_CHECK"
else
    warn "В архиве отсутствует smp/config/server.key — проверку алгоритма пропустить невозможно." \
         "smp/config/server.key not found in archive — algorithm check cannot be performed."
fi

if [ -z "$SERVER_KEY_ALGO" ]; then
    warn "Не удалось определить алгоритм smp/config/server.key (файл отсутствует или повреждён)." \
         "Could not determine smp/config/server.key algorithm (missing or corrupted)."
elif echo "$SERVER_KEY_ALGO" | grep -qi "ED25519\|ED448"; then
    success "Алгоритм ключа SMP корректный: $SERVER_KEY_ALGO" \
            "SMP key algorithm is correct: $SERVER_KEY_ALGO"
else
    echo ""
    warn "ОБНАРУЖЕНО НЕСООТВЕТСТВИЕ АЛГОРИТМА КЛЮЧА!" "KEY ALGORITHM MISMATCH DETECTED!"
    if [ "$LANG_EN" = true ]; then
        echo "  smp/config/server.key uses: $SERVER_KEY_ALGO"
        echo "  Expected: ED25519 (SMP transport protocol requirement)"
        echo ""
        echo "  This backup was likely created after a known install.sh bug overwrote"
        echo "  the SMP transport certificate (Ed25519, signed by ca.key) with the"
        echo "  RSA certificate meant only for the WEB dashboard. Restoring this"
        echo "  archive as-is WILL cause the SMP container to crash-loop with:"
        echo "    smp-server: user error (unknown key algorithm)"
    else
        echo "  smp/config/server.key использует: $SERVER_KEY_ALGO"
        echo "  Ожидается: ED25519 (требование транспортного протокола SMP)"
        echo ""
        echo "  Этот бэкап, вероятно, был создан после того, как известный баг в"
        echo "  install.sh перезаписал транспортный сертификат SMP (Ed25519,"
        echo "  подписанный ca.key) RSA-сертификатом, предназначенным только для"
        echo "  веб-панели. Восстановление этого архива \"как есть\" ПРИВЕДЁТ к"
        echo "  падению контейнера SMP в цикле рестартов с ошибкой:"
        echo "    smp-server: user error (unknown key algorithm)"
    fi
    echo ""
    read -p "$( [ "$LANG_EN" = true ] && echo 'Continue? The script will attempt to auto-repair the certificate after restore (y/N): ' || echo 'Продолжить? Скрипт попытается автоматически починить сертификат после восстановления (y/N): ' )" KEY_MISMATCH_CONFIRM < /dev/tty
    [[ "$KEY_MISMATCH_CONFIRM" =~ ^[Yy]$ ]] || error "Восстановление отменено пользователем." "Restore cancelled by user."
    NEEDS_CERT_REPAIR=1
fi

# ==============================================================================
# 3. РЕЖИМ ВОССТАНОВЛЕНИЯ
# ==============================================================================
echo ""
if [ "$LANG_EN" = true ]; then
    echo "Restore mode:"
    echo "  1) Use existing settings from the archive (.env)"
    echo "  2) Restore with new settings (choose volumes, IP, domain)"
else
    echo "Режим восстановления:"
    echo "  1) Использовать для восстановления существующие настройки (.env из архива)"
    echo "  2) Восстановить с новыми настройками"
fi
echo ""
read -p "$( [ "$LANG_EN" = true ] && echo 'Your choice [1]: ' || echo 'Ваш выбор [1]: ' )" RESTORE_MODE < /dev/tty
RESTORE_MODE=${RESTORE_MODE:-1}

# ==============================================================================
# 4. ВРЕМЕННАЯ РАСПАКОВКА ДЛЯ ЧТЕНИЯ СТАРОГО .env
# ==============================================================================
TMP_EXTRACT=$(mktemp -d)
trap 'rm -rf "$TMP_EXTRACT"' EXIT

tar -xzf "$SELECTED_ARCHIVE" -C "$TMP_EXTRACT" .env 2>/dev/null || \
    error "Не удалось извлечь .env из архива." "Failed to extract .env from archive."

# shellcheck disable=SC1090
source "$TMP_EXTRACT/.env"

OLD_BASE_DIR="$BASE_DIR"
OLD_WEB_DIR="$WEB_DIR"
OLD_MAIN_DOMAIN="$MAIN_DOMAIN"
OLD_EXTERNAL_IP="$EXTERNAL_IP"
OLD_INTERNAL_IP="$INTERNAL_IP"

if [ "$RESTORE_MODE" = "1" ]; then
    # ==========================================================================
    # РЕЖИМ 1: СУЩЕСТВУЮЩИЕ НАСТРОЙКИ
    # ==========================================================================
    NEW_BASE_DIR="$OLD_BASE_DIR"
    NEW_WEB_DIR="$OLD_WEB_DIR"
    NEW_MAIN_DOMAIN="$OLD_MAIN_DOMAIN"
    NEW_EXTERNAL_IP="$OLD_EXTERNAL_IP"
    NEW_INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    [ -z "$NEW_INTERNAL_IP" ] && NEW_INTERNAL_IP="$OLD_INTERNAL_IP"

    info "Восстановление в исходную директорию: $NEW_BASE_DIR" \
         "Restoring to original directory: $NEW_BASE_DIR"
    info "Веб-директория: $NEW_WEB_DIR" "Web directory: $NEW_WEB_DIR"

    if [ -d "$NEW_BASE_DIR" ] && [ "$(ls -A "$NEW_BASE_DIR" 2>/dev/null)" ]; then
        warn "Директория $NEW_BASE_DIR не пуста. Существующие файлы будут перезаписаны данными из архива." \
             "Directory $NEW_BASE_DIR is not empty. Existing files will be overwritten with archive data."
        read -p "$( [ "$LANG_EN" = true ] && echo 'Continue? (y/N): ' || echo 'Продолжить? (y/N): ' )" CONF < /dev/tty
        [[ "$CONF" =~ ^[Yy]$ ]] || error "Восстановление отменено пользователем." "Restore cancelled by user."
    fi

else
    # ==========================================================================
    # РЕЖИМ 2: НОВЫЕ НАСТРОЙКИ
    # ==========================================================================
    echo ""
    OPTIONS=(); PATHS=(); idx=1
    for v in /volume*; do
        if [ -d "$v/docker" ]; then
            OPTIONS+=("$idx) $v/docker/simplex"); PATHS+=("$v/docker/simplex"); idx=$((idx + 1))
        fi
    done
    [ ${#PATHS[@]} -eq 0 ] && error "Не найдено ни одного тома с директорией docker." \
                                     "No volume with docker directory found."

    info "Доступные варианты базовой директории:" "Available base directory options:"
    for opt in "${OPTIONS[@]}"; do echo "  $opt"; done
    echo ""
    while true; do
        read -p "$( [ "$LANG_EN" = true ] && echo 'Select option [1]: ' || echo 'Выберите номер варианта [1]: ' )" CHOICE < /dev/tty
        CHOICE=${CHOICE:-1}
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#PATHS[@]} ]; then
            NEW_BASE_DIR="${PATHS[$((CHOICE - 1))]}"; break
        else
            warn "Некорректный выбор." "Invalid choice."
        fi
    done

    WEB_VOLUMES=(); WEB_PATHS=(); widx=1
    for v in /volume*; do
        if [ -d "$v/web" ]; then
            WEB_VOLUMES+=("$widx) $v/web/simplex"); WEB_PATHS+=("$v/web/simplex"); widx=$((widx + 1))
        fi
    done
    if [ ${#WEB_PATHS[@]} -eq 0 ]; then
        NEW_WEB_DIR="/volume1/web/simplex"
        warn "Папка /web не найдена. Используется $NEW_WEB_DIR" "Folder /web not found. Using $NEW_WEB_DIR"
    elif [ ${#WEB_PATHS[@]} -eq 1 ]; then
        NEW_WEB_DIR="${WEB_PATHS[0]}"
        info "Веб-файлы будут размещены в: $NEW_WEB_DIR" "Web files will be placed in: $NEW_WEB_DIR"
    else
        echo ""
        info "Доступные варианты для веб-файлов:" "Available options for web files:"
        for opt in "${WEB_VOLUMES[@]}"; do echo "  $opt"; done
        echo ""
        while true; do
            read -p "$( [ "$LANG_EN" = true ] && echo 'Select option [1]: ' || echo 'Выберите номер варианта [1]: ' )" WEB_CHOICE < /dev/tty
            WEB_CHOICE=${WEB_CHOICE:-1}
            if [[ "$WEB_CHOICE" =~ ^[0-9]+$ ]] && [ "$WEB_CHOICE" -ge 1 ] && [ "$WEB_CHOICE" -le ${#WEB_PATHS[@]} ]; then
                NEW_WEB_DIR="${WEB_PATHS[$((WEB_CHOICE - 1))]}"; break
            else
                warn "Некорректный выбор." "Invalid choice."
            fi
        done
    fi
    mkdir -p "$NEW_WEB_DIR"

    NEW_INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    [ -z "$NEW_INTERNAL_IP" ] && error "Не удалось определить внутренний IP NAS." "Failed to determine internal NAS IP."

    DETECTED_EXT_IP=$(curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    read -p "$( [ "$LANG_EN" = true ] && echo "Enter external IP [$DETECTED_EXT_IP]: " || echo "Введите внешний IP-адрес [$DETECTED_EXT_IP]: " )" INPUT_EXT_IP < /dev/tty
    NEW_EXTERNAL_IP=${INPUT_EXT_IP:-$DETECTED_EXT_IP}
    [ -z "$NEW_EXTERNAL_IP" ] && error "Внешний IP не может быть пустым." "External IP cannot be empty."

    while true; do
        read -p "$( [ "$LANG_EN" = true ] && echo "Enter domain name [$OLD_MAIN_DOMAIN]: " || echo "Введите доменное имя [$OLD_MAIN_DOMAIN]: " )" INPUT_DOMAIN < /dev/tty
        NEW_MAIN_DOMAIN=${INPUT_DOMAIN:-$OLD_MAIN_DOMAIN}
        [ -z "$NEW_MAIN_DOMAIN" ] && { warn "Домен не может быть пустым." "Domain cannot be empty."; continue; }
        DOTS="${NEW_MAIN_DOMAIN//[^.]}"
        [ -z "$DOTS" ] && { warn "Домен должен содержать точку." "Domain must contain a dot."; continue; }
        break
    done

    if [ -d "$NEW_BASE_DIR" ] && [ "$(ls -A "$NEW_BASE_DIR" 2>/dev/null)" ]; then
        warn "Директория $NEW_BASE_DIR не пуста. Существующие файлы будут перезаписаны." \
             "Directory $NEW_BASE_DIR is not empty. Existing files will be overwritten."
        read -p "$( [ "$LANG_EN" = true ] && echo 'Continue? (y/N): ' || echo 'Продолжить? (y/N): ' )" CONF < /dev/tty
        [[ "$CONF" =~ ^[Yy]$ ]] || error "Восстановление отменено пользователем." "Restore cancelled by user."
    fi
fi

NEW_SMP_DOMAIN="smp.$NEW_MAIN_DOMAIN"
NEW_XFTP_DOMAIN="files.$NEW_MAIN_DOMAIN"
NEW_TURN_DOMAIN="turn.$NEW_MAIN_DOMAIN"

# ==============================================================================
# 5. ОСТАНОВКА ТЕКУЩИХ КОНТЕЙНЕРОВ (если есть)
# ==============================================================================
for svc in simplex-smp simplex-xftp simplex-turn; do
    if docker inspect "$svc" &>/dev/null; then
        info "Остановка контейнера $svc..." "Stopping container $svc..."
        docker stop "$svc" &>/dev/null || true
        docker rm "$svc" &>/dev/null || true
    fi
done

# ==============================================================================
# 6. РАСПАКОВКА АРХИВА
# ==============================================================================
echo ""
info "Распаковка архива в $NEW_BASE_DIR ..." "Extracting archive to $NEW_BASE_DIR ..."
mkdir -p "$NEW_BASE_DIR"
tar -xzf "$SELECTED_ARCHIVE" -C "$NEW_BASE_DIR"
success "Архив распакован." "Archive extracted."

success "Архив распакован." "Archive extracted."

chown -R 1000:1000 "$NEW_BASE_DIR/smp" "$NEW_BASE_DIR/xftp" 2>/dev/null || true

# ==============================================================================
# 6b. БЕЗОПАСНЫЕ ПРАВА ПОСЛЕ РАСПАКОВКИ
# ------------------------------------------------------------------------------

NEW_BASE_DIR="${NEW_BASE_DIR%/}"
NEW_WEB_DIR="${NEW_WEB_DIR%/}"

# Если веб-папка находится внутри базовой директории, базовая директория должна
# быть проходимой для веб-сервера.
# 751 разрешает вход/переход, но не даёт листинг содержимого.
case "${NEW_WEB_DIR}/" in
  "${NEW_BASE_DIR}/"*)
    chmod 751 "$NEW_BASE_DIR" 2>/dev/null || true
    ;;
  *)
    chmod 750 "$NEW_BASE_DIR" 2>/dev/null || true
    ;;
esac

# SMP/XFTP: владельцем контейнерных данных остаётся 1000:1000.
if [ -d "$NEW_BASE_DIR/smp" ]; then
  find "$NEW_BASE_DIR/smp" -type d -exec chmod 750 {} + 2>/dev/null || true
  find "$NEW_BASE_DIR/smp" -type f -exec chmod 640 {} + 2>/dev/null || true
fi

if [ -d "$NEW_BASE_DIR/xftp" ]; then
  find "$NEW_BASE_DIR/xftp" -type d -exec chmod 750 {} + 2>/dev/null || true
  find "$NEW_BASE_DIR/xftp" -type f -exec chmod 640 {} + 2>/dev/null || true
fi

# Секреты должны быть закрыты.
chmod 600 "$NEW_BASE_DIR/.env" 2>/dev/null || true
chmod 600 "$NEW_BASE_DIR/CONNECTION_DETAILS.txt" 2>/dev/null || true

# Скрипты делаем исполняемыми точечно.
for f in "$NEW_BASE_DIR/simplex-backup.sh" "$NEW_BASE_DIR/restore.sh" "$NEW_BASE_DIR/passnew.sh"; do
  [ -f "$f" ] && chmod 700 "$f" 2>/dev/null || true
done

for f in "$NEW_BASE_DIR/status-update.sh"; do
  [ -f "$f" ] && chmod 755 "$f" 2>/dev/null || true
done

# Резервные копии закрываем.
if [ -d "$NEW_BASE_DIR/backups" ]; then
  chmod 700 "$NEW_BASE_DIR/backups" 2>/dev/null || true
  find "$NEW_BASE_DIR/backups" -type f -exec chmod 600 {} + 2>/dev/null || true
fi

success "Права базовой директории скорректированы без рекурсивного закрытия веб-файлов." \
        "Base directory permissions adjusted without recursively locking web files."

# ==============================================================================
# 7. ОБНОВЛЕНИЕ .env И docker-compose.yml ПРИ НОВЫХ НАСТРОЙКАХ
# ==============================================================================
if [ "$RESTORE_MODE" = "2" ]; then
    info "Применение новых настроек к .env и docker-compose.yml..." \
         "Applying new settings to .env and docker-compose.yml..."

    # shellcheck disable=SC1090
    source "$NEW_BASE_DIR/.env"

    cat > "$NEW_BASE_DIR/.env" << EOF
MAIN_DOMAIN=$NEW_MAIN_DOMAIN
SMP_DOMAIN=$NEW_SMP_DOMAIN
XFTP_DOMAIN=$NEW_XFTP_DOMAIN
TURN_DOMAIN=$NEW_TURN_DOMAIN
EXTERNAL_IP=$NEW_EXTERNAL_IP
INTERNAL_IP=$NEW_INTERNAL_IP
ADMIN_EMAIL=$ADMIN_EMAIL
SMP_PASS=$SMP_PASS
XFTP_PASS=$XFTP_PASS
TURN_USER=$TURN_USER
TURN_PASS=$TURN_PASS
BASE_DIR=$NEW_BASE_DIR
WEB_DIR=$NEW_WEB_DIR
TZ=${TZ:-UTC}
EOF
    chmod 600 "$NEW_BASE_DIR/.env"

    # Пересоздаём RSA-сертификат ВЕБ-ПАНЕЛИ под новый домен (smp/certificates,
    # используется только ini-секцией [WEB]). Транспортный Ed25519-сертификат
    # SMP (smp/config/server.*) НЕ трогаем здесь — он пересоздаётся ниже, в
    # единой секции 7b, подписанный существующим ca.key.
    if [ "$NEW_SMP_DOMAIN" != "smp.$OLD_MAIN_DOMAIN" ]; then
        info "Домен изменился — генерация сертификата веб-панели для $NEW_SMP_DOMAIN..." \
             "Domain changed — generating WEB dashboard certificate for $NEW_SMP_DOMAIN..."
        openssl req -x509 -newkey rsa:4096 -nodes \
            -keyout "$NEW_BASE_DIR/smp/certificates/$NEW_SMP_DOMAIN.key" \
            -out    "$NEW_BASE_DIR/smp/certificates/$NEW_SMP_DOMAIN.crt" \
            -days 3650 -subj "/CN=$NEW_SMP_DOMAIN" 2>/dev/null
        chown 1000:1000 "$NEW_BASE_DIR/smp/certificates/"*
        DOMAIN_CHANGED=1
        warn "ВНИМАНИЕ: смена домена меняет ADDR сервера. Fingerprint сохранён из бэкапа, но клиентам потребуются новые адреса подключения (см. отчёт ниже)." \
             "WARNING: changing the domain changes the server ADDR. Fingerprint is preserved from backup, but clients will need updated connection addresses (see report below)."
    fi

    cat > "$NEW_BASE_DIR/docker-compose.yml" << COMPOSEOF
services:
  smp-server:
    image: simplexchat/smp-server:v6.5.2
    container_name: simplex-smp
    restart: unless-stopped
    ports:
      - "5223:5223"
      - "5224:443"
    volumes:
      - ${NEW_BASE_DIR}/smp/config:/etc/opt/simplex:rw
      - ${NEW_BASE_DIR}/smp/data:/var/opt/simplex:rw
      - ${NEW_BASE_DIR}/smp/logs:/var/log/simplex:rw
      - ${NEW_BASE_DIR}/smp/certificates:/certificates:rw
    environment:
      - ADDR=${NEW_SMP_DOMAIN}
      - PASS=${SMP_PASS}
      - STORE_LOG=on
      - SMP_SERVER_TLS_CERT=/certificates/${NEW_SMP_DOMAIN}.crt
      - SMP_SERVER_TLS_KEY=/certificates/${NEW_SMP_DOMAIN}.key
  xftp-server:
    image: simplexchat/xftp-server:v6.5.2
    container_name: simplex-xftp
    restart: unless-stopped
    ports:
      - "7788:443"
    volumes:
      - ${NEW_BASE_DIR}/xftp/config:/etc/opt/simplex-xftp:rw
      - ${NEW_BASE_DIR}/xftp/data:/var/opt/simplex-xftp:rw
      - ${NEW_BASE_DIR}/xftp/files:/srv/xftp:rw
    environment:
      - ADDR=${NEW_XFTP_DOMAIN}
      - QUOTA=100gb
      - PASS=${XFTP_PASS}
    command: ["xftp-server", "run"]
  turn-server:
    image: coturn/coturn:4.6.3-r0
    container_name: simplex-turn
    restart: unless-stopped
    network_mode: host
    command: >
      --verbose
      --listening-port=3478
      --tls-listening-port=5349
      --listening-ip=${NEW_INTERNAL_IP}
      --relay-ip=${NEW_INTERNAL_IP}
      --external-ip=${NEW_EXTERNAL_IP}
      --realm=${NEW_TURN_DOMAIN}
      --user=${TURN_USER}:${TURN_PASS}
      --lt-cred-mech
      --min-port=49152
      --max-port=65535
      --no-cli
      --fingerprint
COMPOSEOF

    success ".env и docker-compose.yml обновлены." ".env and docker-compose.yml updated."
else
    # shellcheck disable=SC1090
    source "$NEW_BASE_DIR/.env"
fi

# ==============================================================================
# 7b. ПЕРЕВЫПУСК Ed25519-СЕРТИФИКАТА ТРАНСПОРТА SMP (при необходимости)
# ------------------------------------------------------------------------------
# Срабатывает если: (а) при проверке архива обнаружен неверный алгоритм ключа
# (NEEDS_CERT_REPAIR=1), либо (б) домен был изменён (DOMAIN_CHANGED=1) — в
# обоих случаях нужен новый server.key/server.crt с CN=текущий SMP-домен,
# подписанный СУЩЕСТВУЮЩИМ ca.key, чтобы Fingerprint не изменился.
# ==============================================================================
if [ "${NEEDS_CERT_REPAIR:-0}" = "1" ] || [ "${DOMAIN_CHANGED:-0}" = "1" ]; then
    echo ""
    info "Перевыпуск транспортного сертификата SMP (Ed25519, CN=$NEW_SMP_DOMAIN)..." \
         "Reissuing SMP transport certificate (Ed25519, CN=$NEW_SMP_DOMAIN)..."

    SMP_CONFIG_DIR="$NEW_BASE_DIR/smp/config"

    if [ ! -s "$SMP_CONFIG_DIR/ca.key" ] || [ ! -s "$SMP_CONFIG_DIR/ca.crt" ]; then
        error "Не найден ca.key/ca.crt в восстановленных данных — автоматический перевыпуск невозможен. Выберите другой архив бэкапа или переинициализируйте SMP вручную." \
              "ca.key/ca.crt not found in restored data — automatic reissue not possible. Choose a different backup archive or re-initialize SMP manually."
    fi

    if [ ! -s "$SMP_CONFIG_DIR/openssl_server.conf" ]; then
        warn "openssl_server.conf отсутствует — создаётся с параметрами по умолчанию." \
             "openssl_server.conf missing — creating with default parameters."
        cat > "$SMP_CONFIG_DIR/openssl_server.conf" << SRVCONF
[req]
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = $NEW_SMP_DOMAIN
[v3]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyAgreement
extendedKeyUsage = serverAuth
SRVCONF
    else
        # Обновляем CN в конфиге на актуальный домен (на случай смены домена)
        sed -i "s/^CN = .*/CN = $NEW_SMP_DOMAIN/" "$SMP_CONFIG_DIR/openssl_server.conf"
    fi

    BROKEN_BACKUP_DIR="$SMP_CONFIG_DIR/broken-rsa-backup"
    mkdir -p "$BROKEN_BACKUP_DIR"
    TS=$(date +%s)
    [ -f "$SMP_CONFIG_DIR/server.crt" ] && mv "$SMP_CONFIG_DIR/server.crt" "$BROKEN_BACKUP_DIR/server.crt.$TS"
    [ -f "$SMP_CONFIG_DIR/server.key" ] && mv "$SMP_CONFIG_DIR/server.key" "$BROKEN_BACKUP_DIR/server.key.$TS"
    [ -f "$SMP_CONFIG_DIR/server.csr" ] && mv "$SMP_CONFIG_DIR/server.csr" "$BROKEN_BACKUP_DIR/server.csr.$TS"

    openssl genpkey -algorithm ED25519 -out "$SMP_CONFIG_DIR/server.key" 2>/dev/null || \
        error "Не удалось сгенерировать Ed25519-ключ." "Failed to generate Ed25519 key."

    openssl req -new -key "$SMP_CONFIG_DIR/server.key" -out "$SMP_CONFIG_DIR/server.csr" \
        -config "$SMP_CONFIG_DIR/openssl_server.conf" 2>/dev/null || \
        error "Не удалось создать CSR." "Failed to create CSR."

    openssl x509 -req -in "$SMP_CONFIG_DIR/server.csr" \
        -CA "$SMP_CONFIG_DIR/ca.crt" -CAkey "$SMP_CONFIG_DIR/ca.key" \
        -CAserial "$SMP_CONFIG_DIR/ca.srl" -CAcreateserial \
        -out "$SMP_CONFIG_DIR/server.crt" -days 3650 \
        -extfile "$SMP_CONFIG_DIR/openssl_server.conf" -extensions v3 2>/dev/null || \
        error "Не удалось подписать сертификат существующим CA." \
              "Failed to sign certificate with existing CA."

    chown 1000:1000 "$SMP_CONFIG_DIR/server.key" "$SMP_CONFIG_DIR/server.crt" "$SMP_CONFIG_DIR/server.csr"
    chmod 750 "$SMP_CONFIG_DIR/server.key" "$SMP_CONFIG_DIR/server.crt" "$SMP_CONFIG_DIR/server.csr"

    if openssl verify -CAfile "$SMP_CONFIG_DIR/ca.crt" "$SMP_CONFIG_DIR/server.crt" >/dev/null 2>&1; then
        success "Сертификат SMP перевыпущен и подписан существующим CA (Fingerprint не изменился). Битые файлы сохранены в $BROKEN_BACKUP_DIR" \
                "SMP certificate reissued and signed by the existing CA (Fingerprint unchanged). Broken files saved to $BROKEN_BACKUP_DIR"
    else
        error "Новый сертификат не прошёл проверку подписи CA — перевыпуск не удался." \
              "New certificate failed CA signature verification — reissue failed."
    fi
fi

# ==============================================================================
# 8. ЗАПУСК КОНТЕЙНЕРОВ
# ==============================================================================
cd "$NEW_BASE_DIR"
info "Загрузка образов..." "Pulling images..."
$COMPOSE_CMD pull || warn "Не удалось обновить образы, используются локальные." \
                          "Failed to pull images, using local ones."

info "Запуск контейнеров..." "Starting containers..."
$COMPOSE_CMD up -d || error "Не удалось запустить контейнеры." "Failed to start containers."

sleep 5
for svc in simplex-smp simplex-xftp simplex-turn; do
    if ! docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null | grep -q true; then
        warn "Логи $svc:" "Logs $svc:"
        docker logs "$svc" 2>&1 | tail -30 || true
        error "$svc не запустился." "$svc failed to start."
    fi
done
success "Все контейнеры запущены." "All containers started."

# ==============================================================================
# 9. ПОЛУЧЕНИЕ FINGERPRINT И ФОРМИРОВАНИЕ АДРЕСОВ
# ==============================================================================
info "Чтение fingerprint..." "Reading fingerprint..."
SMP_FP=$(cat "$NEW_BASE_DIR/smp/config/fingerprint" 2>/dev/null | head -1)
[ -z "$SMP_FP" ] && SMP_FP=$(docker logs simplex-smp 2>&1 | grep -i "Fingerprint:" | tail -1 | awk '{print $NF}')
XFTP_FP=$(cat "$NEW_BASE_DIR/xftp/config/fingerprint" 2>/dev/null | head -1)
[ -z "$XFTP_FP" ] && XFTP_FP=$(docker logs simplex-xftp 2>&1 | grep -i "Fingerprint:" | tail -1 | awk '{print $NF}')

[ -z "$SMP_FP" ]  && warn "Не удалось прочитать SMP fingerprint из восстановленных данных." "Could not read SMP fingerprint from restored data."
[ -z "$XFTP_FP" ] && warn "Не удалось прочитать XFTP fingerprint из восстановленных данных." "Could not read XFTP fingerprint from restored data."

SMP_ADDRESS="smp://${SMP_FP}:${SMP_PASS}@${NEW_SMP_DOMAIN}:5224"
XFTP_ADDRESS="xftp://${XFTP_FP}:${XFTP_PASS}@${NEW_XFTP_DOMAIN}:7788"
TURN_UDP="turn:${TURN_USER}:${TURN_PASS}@${NEW_TURN_DOMAIN}:3478?transport=udp"
TURN_TLS="turns:${TURN_USER}:${TURN_PASS}@${NEW_TURN_DOMAIN}:5349?transport=tcp"
STUN_ADDR="stun:${NEW_TURN_DOMAIN}:3478"

# Обновляем CONNECTION_DETAILS.txt
cat > "$NEW_BASE_DIR/CONNECTION_DETAILS.txt" << EOF
================================================================
SIMPLEX CHAT SERVER — ВОССТАНОВЛЕНО ИЗ БЭКАПА
================================================================
Дата восстановления: $(date)
Исходный архив: $SELECTED_ARCHIVE
Домен: $NEW_MAIN_DOMAIN
Внешний IP: $NEW_EXTERNAL_IP
Внутренний IP: $NEW_INTERNAL_IP

🔗 АДРЕСА ДЛЯ КЛИЕНТА:
SMP:  ${SMP_ADDRESS}
XFTP: ${XFTP_ADDRESS}

📞 TURN / STUN:
${STUN_ADDR}
${TURN_UDP}
${TURN_TLS}

📁 ФАЙЛЫ:
Конфигурация: $NEW_BASE_DIR/.env
Веб-директория: $NEW_WEB_DIR
================================================================
EOF
chmod 600 "$NEW_BASE_DIR/CONNECTION_DETAILS.txt"

# ==============================================================================
# 9b. ВОССТАНОВЛЕНИЕ / ПЕРЕСОЗДАНИЕ WEB-ПАНЕЛИ
# ==============================================================================
info "Восстановление веб-панели..." "Restoring web panel..."

NEW_WEB_DIR="${NEW_WEB_DIR%/}"
[ -z "$NEW_WEB_DIR" ] && NEW_WEB_DIR="/volume1/web/simplex"

if [ -n "${OLD_WEB_DIR:-}" ]; then
  OLD_WEB_DIR="${OLD_WEB_DIR%/}"
fi

js_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

write_connection_js() {
  local details="$1"
  local out="$2"

  local smp xftp stun turn turns

  smp=$(grep '^SMP:' "$details" 2>/dev/null | head -n1 | sed 's/^SMP:[[:space:]]*//; s/\r$//' || true)
  xftp=$(grep '^XFTP:' "$details" 2>/dev/null | head -n1 | sed 's/^XFTP:[[:space:]]*//; s/\r$//' || true)
  stun=$(grep '^stun:' "$details" 2>/dev/null | head -n1 | sed 's/\r$//' || true)
  turn=$(grep '^turn:' "$details" 2>/dev/null | head -n1 | sed 's/\r$//' || true)
  turns=$(grep '^turns:' "$details" 2>/dev/null | head -n1 | sed 's/\r$//' || true)

  cat > "$out" <<EOF
window.SIMPLEX_CONN = {
  "smp": "$(js_escape "$smp")",
  "xftp": "$(js_escape "$xftp")",
  "stun": "$(js_escape "$stun")",
  "turn_udp": "$(js_escape "$turn")",
  "turn_tls": "$(js_escape "$turns")",
  "updated": "$(date '+%Y-%m-%d %H:%M:%S')"
};
EOF

  chmod 644 "$out"
}

create_dynamic_qrsmp() {
  local out="$1"

  cat > "$out" <<'WEBEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SimpleX Control</title>
<script src="connection.js"></script>
<style>
body{font-family:Arial,sans-serif;background:#0c0a14;color:#f5f3fa;margin:20px}
h1{margin-bottom:20px}
.card{background:#1a1528;border:1px solid rgba(139,92,246,.12);border-radius:16px;padding:18px;margin-bottom:14px}
pre{white-space:pre-wrap;word-break:break-all;background:#0c0a14;border:1px solid rgba(139,92,246,.12);padding:10px;border-radius:10px}
button{padding:8px 12px;border-radius:8px;border:0;background:#8B5CF6;color:#fff;font-weight:700;cursor:pointer}
</style>
</head>
<body>
<h1>SimpleX Control</h1>

<div class="card">
  <h2>SMP</h2>
  <pre id="smp"></pre>
  <button onclick="copyText('smp')">Copy</button>
</div>

<div class="card">
  <h2>XFTP</h2>
  <pre id="xftp"></pre>
  <button onclick="copyText('xftp')">Copy</button>
</div>

<div class="card">
  <h2>TURN / STUN</h2>
  <pre id="turn"></pre>
  <button onclick="copyText('turn')">Copy</button>
</div>

<script>
function connValue(k) {
  return (window.SIMPLEX_CONN && window.SIMPLEX_CONN[k]) || "";
}

function turnText() {
  return [connValue('stun'), connValue('turn_udp'), connValue('turn_tls')]
    .filter(Boolean)
    .join("\n");
}

function render() {
  document.getElementById('smp').textContent = connValue('smp') || '—';
  document.getElementById('xftp').textContent = connValue('xftp') || '—';
  document.getElementById('turn').textContent = turnText() || '—';
}

function copyText(id) {
  var text = id === 'turn' ? turnText() : connValue(id);

  if (navigator.clipboard) {
    navigator.clipboard.writeText(text);
  } else {
    var ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }
}

document.addEventListener('DOMContentLoaded', render);
</script>
</body>
</html>
WEBEOF

  chmod 644 "$out"
}

mkdir -p "$NEW_WEB_DIR"

if [ -d "$NEW_WEB_DIR" ] && [ "$(ls -A "$NEW_WEB_DIR" 2>/dev/null)" ]; then
  warn "Директория $NEW_WEB_DIR не пуста — веб-файлы будут перезаписаны/дополнены." \
       "Directory $NEW_WEB_DIR is not empty — web files will be overwritten/merged."
fi

# --- Восстановление веб-папки из архива, если она там есть -------------------
if [ -d "$NEW_BASE_DIR/web" ]; then
  WEB_SRC_DIR=$(find "$NEW_BASE_DIR/web" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)
  [ -n "$WEB_SRC_DIR" ] || WEB_SRC_DIR="$NEW_BASE_DIR/web"

  SKIP_WEB_MOVE=false

  # Если целевая веб-папка и есть распакованная папка из архива,
  # копировать и удалять её нельзя.
  if [ "$NEW_WEB_DIR" = "$WEB_SRC_DIR" ]; then
    SKIP_WEB_MOVE=true
  fi

  # Если целевая веб-папка находится внутри временной распакованной веб-папки,
  # удалять $NEW_BASE_DIR/web нельзя.
  case "${NEW_WEB_DIR}/" in
    "${NEW_BASE_DIR}/web/"*)
      SKIP_WEB_MOVE=true
      ;;
  esac

  if [ "$SKIP_WEB_MOVE" = false ]; then
    mkdir -p "$NEW_WEB_DIR"
    cp -a "$WEB_SRC_DIR/." "$NEW_WEB_DIR/"
    rm -rf "$NEW_BASE_DIR/web"

    success "Web-файлы восстановлены из архива в $NEW_WEB_DIR" \
            "Web files restored from archive to $NEW_WEB_DIR"
  else
    success "Web-файлы уже находятся в целевой директории: $NEW_WEB_DIR" \
            "Web files are already in the target directory: $NEW_WEB_DIR"
  fi
else
  warn "Web-файлы в архиве не найдены — создаётся минимальная веб-панель." \
       "No web files found in archive — creating minimal web panel."
fi

# --- Если веб-файлов нет, создаём минимальные динамические страницы ----------
if [ ! -s "$NEW_WEB_DIR/qrsmp.html" ]; then
  create_dynamic_qrsmp "$NEW_WEB_DIR/qrsmp.html"
  success "Создан динамический qrsmp.html." "Dynamic qrsmp.html created."
fi

if [ ! -s "$NEW_WEB_DIR/index.html" ]; then
  cat > "$NEW_WEB_DIR/index.html" <<'WEBEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="0; url=qrsmp.html">
<title>SimpleX Server</title>
</head>
<body>
<a href="qrsmp.html">SimpleX Control</a>
</body>
</html>
WEBEOF

  chmod 644 "$NEW_WEB_DIR/index.html"
fi

# --- Всегда пересоздаём connection.js из актуального CONNECTION_DETAILS.txt ---
write_connection_js "$NEW_BASE_DIR/CONNECTION_DETAILS.txt" "$NEW_WEB_DIR/connection.js"

success "connection.js сгенерирован из CONNECTION_DETAILS.txt." \
        "connection.js generated from CONNECTION_DETAILS.txt."

# ==============================================================================
# 9c. ГЕНЕРАЦИЯ ЛОГИНА И ПАРОЛЯ ДЛЯ WEB-ПАНЕЛИ
# ------------------------------------------------------------------------------
# Блок создаёт новый пароль для .htpasswd, позволяет изменить логин и
# записывает данные входа в CONNECTION_DETAILS.txt.
#
# Старый .htpasswd при выборе генерации перезаписывается одним новым
# пользователем.
# ==============================================================================
info "Настройка доступа к веб-панели..." "Setting up web panel access..."

WEB_CRED_BEGIN="# === SIMPLEX WEB PANEL CREDENTIALS BEGIN ==="
WEB_CRED_END="# === SIMPLEX WEB PANEL CREDENTIALS END ==="

update_connection_details_web() {
  local details="$1"
  local login="$2"
  local pass="$3"
  local ts="$4"

  local tmp_details
  local tmp_block
  local panel_url

  tmp_details=$(mktemp)
  tmp_block=$(mktemp)

  panel_url=""
  if [ -n "${NEW_MAIN_DOMAIN:-}" ]; then
    panel_url="https://info.smp.${NEW_MAIN_DOMAIN}/qrsmp.html"
  fi

  {
    echo "$WEB_CRED_BEGIN"
    echo "🌐 ПАНЕЛЬ УПРАВЛЕНИЯ — ДАННЫЕ ВХОДА"
    echo "Дата и время последней генерации: $ts"
    echo "Логин / Login: $login"
    echo "Пароль / Password: $pass"
    echo "Файл паролей: $NEW_WEB_DIR/.htpasswd"
    if [ -n "$panel_url" ]; then
      echo "URL: $panel_url"
    fi
    echo "Команда смены пароля: sudo /bin/bash $NEW_BASE_DIR/passnew.sh"
    echo "$WEB_CRED_END"
  } > "$tmp_block"

  if [ -f "$details" ]; then
    if grep -qF "$WEB_CRED_BEGIN" "$details" && grep -qF "$WEB_CRED_END" "$details"; then
      awk -v b="$WEB_CRED_BEGIN" -v e="$WEB_CRED_END" \
        '$0==b{skip=1; next} $0==e{skip=0; next} !skip' "$details" > "$tmp_details"
    else
      cat "$details" > "$tmp_details"
    fi

    printf '\n' >> "$tmp_details"
    cat "$tmp_details" "$tmp_block" > "$details"
  else
    cat "$tmp_block" > "$details"
  fi

  rm -f "$tmp_details" "$tmp_block"
  chmod 600 "$details"
}

WEB_ACCESS_CHOICE="${WEB_ACCESS_CHOICE_OVERRIDE:-}"

if [ -z "$WEB_ACCESS_CHOICE" ]; then
  echo ""
  if [ "$LANG_EN" = true ]; then
    echo "Web panel access:"
    echo "  1) Generate new login/password (recommended, old .htpasswd will be replaced)"
    echo "  2) Keep existing .htpasswd from backup"
  else
    echo "Доступ к веб-панели:"
    echo "  1) Сгенерировать новый логин/пароль (рекомендуется, старый .htpasswd будет заменён)"
    echo "  2) Оставить существующий .htpasswd из бэкапа"
  fi
  echo ""

  read -p "$( [ "$LANG_EN" = true ] && echo 'Your choice [1]: ' || echo 'Ваш выбор [1]: ' )" \
    WEB_ACCESS_CHOICE < /dev/tty || true

  WEB_ACCESS_CHOICE="${WEB_ACCESS_CHOICE:-1}"
fi

GENERATE_WEB_CREDENTIALS=false

if [ "$WEB_ACCESS_CHOICE" != "2" ]; then
  GENERATE_WEB_CREDENTIALS=true
else
  if [ ! -f "$NEW_WEB_DIR/.htpasswd" ]; then
    warn "Выбрано сохранение существующего .htpasswd, но файл не найден. Будет создан новый пароль." \
         "Keeping existing .htpasswd was selected, but the file was not found. A new password will be created."
    GENERATE_WEB_CREDENTIALS=true
  fi
fi

if [ "$GENERATE_WEB_CREDENTIALS" = true ]; then

  WEB_LOGIN="${WEB_LOGIN_OVERRIDE:-}"

  if [ -z "$WEB_LOGIN" ]; then
    read -p "$( [ "$LANG_EN" = true ] && echo 'Web panel login [admin]: ' || echo 'Логин веб-панели [admin]: ' )" \
      WEB_LOGIN < /dev/tty || true

    WEB_LOGIN="${WEB_LOGIN:-admin}"
  fi

  if [[ ! "$WEB_LOGIN" =~ ^[A-Za-z0-9._@-]+$ ]]; then
    warn "Некорректный логин. Разрешены только буквы, цифры и символы . _ @ -. Используется admin." \
         "Invalid login. Allowed characters are letters, digits and . _ @ -. Using admin."
    WEB_LOGIN="admin"
  fi

  WEB_PASS=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)

  if [ ${#WEB_PASS} -lt 16 ]; then
    WEB_PASS="${WEB_PASS}$(openssl rand -hex 8)"
    WEB_PASS="${WEB_PASS:0:16}"
  fi

  WEB_HASH=$(openssl passwd -apr1 "$WEB_PASS" 2>/dev/null || openssl passwd -1 "$WEB_PASS" || true)

  if [ -z "$WEB_HASH" ]; then
    error "Не удалось создать hash для пароля веб-панели." \
          "Failed to create password hash for the web panel."
  fi

  mkdir -p "$NEW_WEB_DIR"

  # Старый .htpasswd перезаписывается одним новым пользователем.
  printf '%s:%s\n' "$WEB_LOGIN" "$WEB_HASH" > "$NEW_WEB_DIR/.htpasswd"

  WEB_GROUP=""
  if getent group http >/dev/null 2>&1; then
    WEB_GROUP="http"
  elif grep -q '^http:' /etc/group 2>/dev/null; then
    WEB_GROUP="http"
  fi

  if [ -n "$WEB_GROUP" ]; then
    chown root:"$WEB_GROUP" "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
    chmod 640 "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
  else
    chown root:root "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
    chmod 600 "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true

    warn "Группа http не найдена. .htpasswd закрыт правами 600. Если веб-сервер не может его прочитать, авторизация может возвращать 500." \
         "http group not found. .htpasswd has 600 permissions. If the web server cannot read it, authentication may return 500."
  fi

  # Если .htaccess отсутствует, создаём базовую защиту.
  if [ ! -f "$NEW_WEB_DIR/.htaccess" ]; then
    cat > "$NEW_WEB_DIR/.htaccess" <<EOF
<Files "qrsmp.html">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>

<Files "status.json">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>

<Files "connection.js">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>
EOF

    chmod 644 "$NEW_WEB_DIR/.htaccess"
  fi

  # Если .htaccess уже есть, но connection.js не защищён, добавляем защиту.
  if ! grep -q '<Files "connection.js">' "$NEW_WEB_DIR/.htaccess" 2>/dev/null; then
    cat >> "$NEW_WEB_DIR/.htaccess" <<EOF

<Files "connection.js">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>
EOF

    chmod 644 "$NEW_WEB_DIR/.htaccess"
  fi

  WEB_GEN_TS=$(date '+%Y-%m-%d %H:%M:%S')

  update_connection_details_web \
    "$NEW_BASE_DIR/CONNECTION_DETAILS.txt" \
    "$WEB_LOGIN" \
    "$WEB_PASS" \
    "$WEB_GEN_TS"

  success "Пароль веб-панели сгенерирован и записан в CONNECTION_DETAILS.txt." \
          "Web panel password generated and saved to CONNECTION_DETAILS.txt."

  echo ""
  echo "----------------------------------------"
  echo "Логин / Login: $WEB_LOGIN"
  echo "Пароль / Password: $WEB_PASS"
  echo "Дата и время: $WEB_GEN_TS"
  echo "Файл: $NEW_WEB_DIR/.htpasswd"
  echo "----------------------------------------"
  echo ""

  warn "Сохраните пароль. Старый пароль веб-панели был стёрт." \
       "Save the password. The old web panel password has been erased."

else

  success "Использован существующий .htpasswd из бэкапа." \
          "Existing .htpasswd from backup used."

  WEB_GROUP=""
  if getent group http >/dev/null 2>&1; then
    WEB_GROUP="http"
  elif grep -q '^http:' /etc/group 2>/dev/null; then
    WEB_GROUP="http"
  fi

  if [ -f "$NEW_WEB_DIR/.htpasswd" ]; then
    if [ -n "$WEB_GROUP" ]; then
      chown root:"$WEB_GROUP" "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
      chmod 640 "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
    else
      chown root:root "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
      chmod 600 "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
    fi
  fi

  warn "Пароль из бэкапа не отображается, так как .htpasswd хранит только hash." \
       "The backup password is not shown because .htpasswd stores only a hash."
fi

# --- Если WEB_DIR изменился, чиним пути в .htaccess ---------------------------
if [ -f "$NEW_WEB_DIR/.htaccess" ] && [ -n "${OLD_WEB_DIR:-}" ] && [ "$OLD_WEB_DIR" != "$NEW_WEB_DIR" ]; then
  SAFE_OLD_WEB_DIR=$(printf '%s' "$OLD_WEB_DIR" | sed 's/[|&]/\\&/g')
  SAFE_NEW_WEB_DIR=$(printf '%s' "$NEW_WEB_DIR" | sed 's/[|&]/\\&/g')

  sed -i "s|$SAFE_OLD_WEB_DIR|$SAFE_NEW_WEB_DIR|g" "$NEW_WEB_DIR/.htaccess" 2>/dev/null || true

  success "Пути в .htaccess обновлены под $NEW_WEB_DIR" \
          "Paths in .htaccess updated to $NEW_WEB_DIR"
fi

# --- Если есть .htpasswd, защищаем .htaccess и connection.js ------------------
if [ -f "$NEW_WEB_DIR/.htpasswd" ]; then
  if [ ! -f "$NEW_WEB_DIR/.htaccess" ]; then
    cat > "$NEW_WEB_DIR/.htaccess" <<EOF
<Files "qrsmp.html">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>

<Files "status.json">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>

<Files "connection.js">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>
EOF

    chmod 644 "$NEW_WEB_DIR/.htaccess"
  fi

  if ! grep -q '<Files "connection.js">' "$NEW_WEB_DIR/.htaccess" 2>/dev/null; then
    cat >> "$NEW_WEB_DIR/.htaccess" <<EOF

<Files "connection.js">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${NEW_WEB_DIR}/.htpasswd
Require valid-user
</Files>
EOF

    chmod 644 "$NEW_WEB_DIR/.htaccess"
  fi
else
  if [ -f "$NEW_WEB_DIR/.htaccess" ]; then
    warn ".htpasswd отсутствует рядом с .htaccess — проверьте защиту веб-панели вручную." \
         ".htpasswd is missing next to .htaccess — check web panel protection manually."
  fi
fi

# ==============================================================================
# 9c. НОРМАЛИЗАЦИЯ ПРАВ WEB_DIR (ИСПРАВЛЕНИЕ 403)
# ==============================================================================
info "Нормализация прав веб-папки..." "Normalizing web directory permissions..."

NEW_WEB_DIR="${NEW_WEB_DIR%/}"
NEW_BASE_DIR="${NEW_BASE_DIR%/}"

if [ -d "$NEW_WEB_DIR" ]; then

  # Если веб-папка находится внутри базовой директории, нужно разрешить
  # веб-серверу проход по родительским каталогам.
  if [ "$NEW_WEB_DIR" != "$NEW_BASE_DIR" ]; then
    case "${NEW_WEB_DIR}/" in
      "${NEW_BASE_DIR}/"*)
        REL_WEB_PATH="${NEW_WEB_DIR#${NEW_BASE_DIR}/}"
        CUR_DIR="$NEW_BASE_DIR"

        chmod 751 "$CUR_DIR" 2>/dev/null || true

        IFS='/' read -r -a WEB_PATH_PARTS <<< "$REL_WEB_PATH"
        WEB_PATH_LAST_INDEX=$(( ${#WEB_PATH_PARTS[@]} - 1 ))

        for i in "${!WEB_PATH_PARTS[@]}"; do
          CUR_DIR="$CUR_DIR/${WEB_PATH_PARTS[$i]}"

          # Последний элемент — это сама веб-папка, ей позже поставим 755.
          if [ "$i" -lt "$WEB_PATH_LAST_INDEX" ] && [ -d "$CUR_DIR" ]; then
            chmod 751 "$CUR_DIR" 2>/dev/null || true
          fi
        done
        ;;
    esac
  fi

  # Сама веб-папка и вложенные каталоги должны быть проходимы и читаемы.
  chmod 755 "$NEW_WEB_DIR" 2>/dev/null || true
  find "$NEW_WEB_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true

  # Обычные веб-файлы должны читаться веб-сервером.
  find "$NEW_WEB_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true

  # .htpasswd должен быть доступен веб-серверу, но не должен быть публичным.
  if [ -f "$NEW_WEB_DIR/.htpasswd" ]; then
    WEB_GROUP=""

    if getent group http >/dev/null 2>&1; then
      WEB_GROUP="http"
    elif grep -q '^http:' /etc/group 2>/dev/null; then
      WEB_GROUP="http"
    fi

    if [ -n "$WEB_GROUP" ]; then
      chown root:"$WEB_GROUP" "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
      chmod 640 "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
      success ".htpasswd: root:${WEB_GROUP}, права 640." \
              ".htpasswd: root:${WEB_GROUP}, permissions 640."
    else
      chown root:root "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
      chmod 600 "$NEW_WEB_DIR/.htpasswd" 2>/dev/null || true
      warn "Группа http не найдена. .htpasswd имеет права 600. Если веб-сервер не может его прочитать, авторизация может возвращать 500." \
           "http group not found. .htpasswd has 600 permissions. If the web server cannot read it, authentication may return 500."
    fi
  fi

  # Дополнительная проверка защиты чувствительного файла.
  if [ -f "$NEW_WEB_DIR/connection.js" ] && [ ! -f "$NEW_WEB_DIR/.htpasswd" ]; then
    warn "connection.js содержит адреса серверов, но .htpasswd не найден. Проверьте защиту веб-панели." \
         "connection.js contains server addresses, but .htpasswd was not found. Check web panel protection."
  fi

  success "Права веб-папки нормализованы: каталоги 755, файлы 644." \
          "Web directory permissions normalized: directories 755, files 644."
else
  warn "WEB_DIR $NEW_WEB_DIR не найден после восстановления." \
       "WEB_DIR $NEW_WEB_DIR not found after restore."
fi

# --- Предупреждение для старых qrsmp.html -------------------------------------
if [ -s "$NEW_WEB_DIR/qrsmp.html" ] && ! grep -q "connection.js" "$NEW_WEB_DIR/qrsmp.html" 2>/dev/null; then
  warn "Восстановленный qrsmp.html не использует connection.js. Для динамических адресов замените его обновлённой версией." \
       "Restored qrsmp.html does not use connection.js. Replace it with the updated version for dynamic addresses."
fi

# ==============================================================================
# 10. ИТОГ
# ==============================================================================
echo ""
cat "$NEW_BASE_DIR/CONNECTION_DETAILS.txt"
echo ""
info "Статус контейнеров:" "Container status:"
$COMPOSE_CMD ps
echo ""
success "Восстановление завершено." "Restore completed."
if [ "$RESTORE_MODE" = "2" ]; then
    warn "Не забудьте: обновить DNS A-записи, проброс портов и брандмауэр для нового домена/IP, а также перенастроить Web Station на $NEW_WEB_DIR." \
         "Don't forget: update DNS A records, port forwarding and firewall for the new domain/IP, and reconfigure Web Station to point to $NEW_WEB_DIR."
fi
