#!/bin/bash
# ==============================================================================
# SimpleX Chat Server Suite Installer for Synology DSM 7.1+
# Версия: 9.6
# ==============================================================================
set -euo pipefail

# === КОНФИГУРАЦИЯ ВЕРСИЙ ===
SMP_IMAGE="simplexchat/smp-server:v6.5.2"
XFTP_IMAGE="simplexchat/xftp-server:v6.5.2"
TURN_IMAGE="coturn/coturn:4.6.3-r0"
INSTALLER_VERSION="9.6"

# === ЦВЕТА ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo ""
echo "=========================================="
echo "  SIMPLEX CHAT INSTALLER v${INSTALLER_VERSION} — SYNOLOGY"
echo "=========================================="
echo ""

# === ФУНКЦИЯ БЕЗОПАСНОГО ЧТЕНИЯ ===
safe_read() {
    local prompt="$1"
    local default="${2:-}"
    local var_name="$3"
    local value=""
    if [ -c /dev/tty ]; then
        printf '%s' "$prompt" > /dev/tty
        read -r value < /dev/tty 2>/dev/null || true
    fi
    if [ -z "$value" ] && [ -n "$default" ]; then
        value="$default"
    fi
    eval "$var_name=\"\$value\""
}

# === ВЫБОР ЯЗЫКА ===
if [ -n "${LANG_CHOICE:-}" ] && [[ "${LANG_CHOICE}" =~ ^[12]$ ]]; then
    echo "[INFO] Язык задан через окружение / Language set via environment: $LANG_CHOICE"
else
    echo "Выберите язык / Select language:"
    echo "  1) Русский"
    echo "  2) English"
    echo ""
    safe_read "Ваш выбор / Your choice [1]: " "1" LANG_CHOICE
fi

if [ "$LANG_CHOICE" = "2" ]; then
    LANG_EN=true
else
    LANG_EN=false
fi

# === ФУНКЦИИ ВЫВОДА ===
info()    { if [ "$LANG_EN" = true ]; then echo -e "${BLUE}[INFO]${NC} $2"; else echo -e "${BLUE}[INFO]${NC} $1"; fi; }
success() { if [ "$LANG_EN" = true ]; then echo -e "${GREEN}[ OK ]${NC} $2"; else echo -e "${GREEN}[ OK ]${NC} $1"; fi; }
warn()    { if [ "$LANG_EN" = true ]; then echo -e "${YELLOW}[WARN]${NC} $2"; else echo -e "${YELLOW}[WARN]${NC} $1"; fi; }
error()   { if [ "$LANG_EN" = true ]; then echo -e "${RED}[ERR ]${NC} $2"; exit 1; else echo -e "${RED}[ERR ]${NC} $1"; exit 1; fi; }

# ==============================================================================
# 0.0 ПОИСК СОХРАНЁННОЙ КОНФИГУРАЦИИ (ПЕРЕУСТАНОВКА)
# ==============================================================================
REINSTALL_MODE=false
FOUND_ENV_PATHS=()
for v in /volume*; do
    if [ -f "$v/docker/simplex/.env" ]; then
        FOUND_ENV_PATHS+=("$v/docker/simplex")
    fi
done

if [ ${#FOUND_ENV_PATHS[@]} -gt 0 ]; then
    echo ""
    warn "На сервере есть сохранённая конфигурация:" \
         "A saved configuration was found on this server:"
    for p in "${FOUND_ENV_PATHS[@]}"; do
        echo "  - $p/.env"
    done
    echo ""
    if [ "$LANG_EN" = true ]; then
        echo "  1) Use saved configuration (reinstall)"
        echo "  2) Enter new configuration"
    else
        echo "  1) Использовать сохранённую конфигурацию (переустановка)"
        echo "  2) Ввести новую конфигурацию"
    fi
    echo ""
    safe_read "Ваш выбор / Your choice [1]: " "1" REINSTALL_CHOICE

    if [ "$REINSTALL_CHOICE" != "2" ]; then
        REINSTALL_MODE=true
        if [ ${#FOUND_ENV_PATHS[@]} -eq 1 ]; then
            BASE_DIR="${FOUND_ENV_PATHS[0]}"
        else
            echo ""
            info "Найдено несколько сохранённых конфигураций:" \
                 "Multiple saved configurations found:"
            ridx=1
            for p in "${FOUND_ENV_PATHS[@]}"; do
                echo "  $ridx) $p"
                ridx=$((ridx + 1))
            done
            echo ""
            while true; do
                safe_read "Выберите номер конфигурации / Select configuration number [1]: " "1" RCHOICE
                if [[ "$RCHOICE" =~ ^[0-9]+$ ]] && [ "$RCHOICE" -ge 1 ] && [ "$RCHOICE" -le ${#FOUND_ENV_PATHS[@]} ]; then
                    BASE_DIR="${FOUND_ENV_PATHS[$((RCHOICE - 1))]}"
                    break
                else
                    warn "Некорректный выбор." "Invalid choice."
                fi
            done
        fi

        info "Используется сохранённая конфигурация: $BASE_DIR/.env" \
             "Using saved configuration: $BASE_DIR/.env"
        # shellcheck disable=SC1090
        source "$BASE_DIR/.env"
        [ -z "${WEB_DIR:-}" ] && WEB_DIR="/volume1/web/simplex"
        [ -z "${TURN_USER:-}" ] && TURN_USER="simplex"
        success "Конфигурация загружена из $BASE_DIR/.env" \
                "Configuration loaded from $BASE_DIR/.env"
    else
        info "Будет введена новая конфигурация." \
             "A new configuration will be entered."
    fi
fi

# === ПРОВЕРКИ ЗАВИСИМОСТЕЙ ===
if [ "$(id -u)" -ne 0 ]; then
    error "Скрипт требует прав суперпользователя. Выполните: sudo /bin/bash $0" \
          "Script requires superuser privileges. Run: sudo /bin/bash $0"
fi

command -v openssl &>/dev/null || error "openssl не найден." "openssl not found."
command -v curl    &>/dev/null || error "curl не найден." "curl not found."
command -v docker  &>/dev/null || error "Docker не установлен. Установите через Package Center." "Docker not installed. Install via Package Center."
command -v ip      &>/dev/null || error "ip не найден." "ip not found."

COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    command -v docker-compose &>/dev/null || error "Docker Compose не найден." "Docker Compose not found."
fi

echo ""

if [ "$REINSTALL_MODE" = false ]; then

# ==============================================================================
# 0. ВЫБОР ТОМА
# ==============================================================================
OPTIONS=()
PATHS=()
idx=1
for v in /volume*; do
    if [ -d "$v/docker" ]; then
        OPTIONS+=("$idx) $v/docker/simplex")
        PATHS+=("$v/docker/simplex")
        idx=$((idx + 1))
    fi
done

if [ ${#OPTIONS[@]} -eq 0 ]; then
    error "Не найдено ни одного тома с директорией docker (/volume*/docker)" \
          "No volume with docker directory found (/volume*/docker)"
fi

echo ""
info "Доступные варианты установки:" "Available installation options:"
for opt in "${OPTIONS[@]}"; do echo "  $opt"; done
echo ""

while true; do
    safe_read "Выберите номер варианта / Select option [1]: " "1" CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#PATHS[@]} ]; then
        BASE_DIR="${PATHS[$((CHOICE - 1))]}"
        break
    else
        warn "Некорректный выбор. Введите число от 1 до ${#PATHS[@]}." \
             "Invalid choice. Enter a number from 1 to ${#PATHS[@]}."
    fi
done

# === ЗАГРУЗКА СУЩЕСТВУЮЩЕЙ КОНФИГУРАЦИИ ===
EXISTING_ENV=false
if [ -f "$BASE_DIR/.env" ]; then
    info "Обнаружен существующий .env — загружаю конфигурацию..." \
         "Existing .env found — loading configuration..."
    # shellcheck disable=SC1090
    source "$BASE_DIR/.env"
    EXISTING_ENV=true
fi

# ==============================================================================
# 1. СБОР ДАННЫХ
# ==============================================================================

# ВАЖНО:
# На этом этапе .env НЕ загружается как рабочая конфигурация.
# Все обязательные параметры пользователь вводит/подтверждает вручную.
# .env будет прочитан ниже только для сохранения секретов.

OLD_ENV_FILE="$BASE_DIR/.env"
EXISTING_ENV=false

if [ -f "$OLD_ENV_FILE" ]; then
    EXISTING_ENV=true
    info "Обнаружен существующий .env. Его параметры будут использованы только для сохранения секретов." \
         "Existing .env found. Its parameters will only be used to preserve secrets."
fi

# ==============================================================================
# 1.1 WEB DIRECTORY
# ==============================================================================

WEB_VOLUMES=()
WEB_PATHS=()
widx=1

for v in /volume*; do
    if [ -d "$v/web" ]; then
        WEB_VOLUMES+=("$widx) $v/web/simplex")
        WEB_PATHS+=("$v/web/simplex")
        widx=$((widx + 1))
    fi
done

if [ ${#WEB_PATHS[@]} -eq 0 ]; then
    warn "Папка /web не найдена ни на одном томе. Используется /volume1/web/simplex" \
         "No /web directory found on any volume. Using /volume1/web/simplex"
    WEB_DIR="/volume1/web/simplex"

elif [ ${#WEB_PATHS[@]} -eq 1 ]; then
    WEB_DIR="${WEB_PATHS[0]}"
    info "Веб-файлы будут размещены в: $WEB_DIR" \
         "Web files will be placed in: $WEB_DIR"

else
    echo ""
    info "Доступные варианты для веб-файлов (Web Station):" \
         "Available options for web files (Web Station):"

    for opt in "${WEB_VOLUMES[@]}"; do
        echo "  $opt"
    done

    echo ""

    while true; do
        safe_read \
            "Выберите номер варианта для веб-файлов / Select option for web files [1]: " \
            "1" \
            WEB_CHOICE

        if [[ "$WEB_CHOICE" =~ ^[0-9]+$ ]] &&
           [ "$WEB_CHOICE" -ge 1 ] &&
           [ "$WEB_CHOICE" -le ${#WEB_PATHS[@]} ]; then

            WEB_DIR="${WEB_PATHS[$((WEB_CHOICE - 1))]}"
            break
        else
            warn "Некорректный выбор. Введите число от 1 до ${#WEB_PATHS[@]}." \
                 "Invalid choice. Enter a number from 1 to ${#WEB_PATHS[@]}."
        fi
    done
fi

mkdir -p "$WEB_DIR"

info "Базовая директория: $BASE_DIR" \
     "Base directory: $BASE_DIR"

info "Веб-директория: $WEB_DIR" \
     "Web directory: $WEB_DIR"

# ==============================================================================
# 1.2 INTERNAL IP
# ==============================================================================

AUTO_INTERNAL_IP=$(
    ip route get 1 2>/dev/null |
    awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'
)

if [ -z "$AUTO_INTERNAL_IP" ]; then
    AUTO_INTERNAL_IP=$(
        ip -4 route get 1 2>/dev/null |
        awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'
    )
fi

if [ -z "$AUTO_INTERNAL_IP" ]; then
    error "Не удалось автоматически определить внутренний IP NAS." \
          "Failed to automatically determine the NAS internal IP."
fi

echo ""
info "Автоматически определён внутренний IP NAS: $AUTO_INTERNAL_IP" \
     "Automatically detected NAS internal IP: $AUTO_INTERNAL_IP"
if [ "$LANG_EN" = true ]; then
    echo "  1) Use detected IP ($AUTO_INTERNAL_IP)"
    echo "  2) Enter my own IP"
else
    echo "  1) Использовать определённый IP ($AUTO_INTERNAL_IP)"
    echo "  2) Ввести свой IP"
fi
safe_read "Ваш выбор / Your choice [1]: " "1" INTERNAL_IP_CHOICE

if [ "$INTERNAL_IP_CHOICE" = "2" ]; then
    safe_read \
        "Введите внутренний IP NAS / Enter NAS internal IP: " \
        "" \
        INTERNAL_IP
else
    INTERNAL_IP="$AUTO_INTERNAL_IP"
fi

if [ -z "$INTERNAL_IP" ]; then
    error "Внутренний IP NAS не может быть пустым." \
          "NAS internal IP cannot be empty."
fi

info "Используется внутренний IP NAS: $INTERNAL_IP" \
     "NAS internal IP in use: $INTERNAL_IP"

# ==============================================================================
# 1.3 EXTERNAL IP
# ==============================================================================

AUTO_EXTERNAL_IP=$(
    curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || echo ""
)

if [ -n "$AUTO_EXTERNAL_IP" ]; then
    info "Автоматически определён внешний IP: $AUTO_EXTERNAL_IP" \
         "Automatically detected external IP: $AUTO_EXTERNAL_IP"
    if [ "$LANG_EN" = true ]; then
        echo "  1) Use detected IP ($AUTO_EXTERNAL_IP)"
        echo "  2) Enter my own IP"
    else
        echo "  1) Использовать определённый IP ($AUTO_EXTERNAL_IP)"
        echo "  2) Ввести свой IP"
    fi
    safe_read "Ваш выбор / Your choice [1]: " "1" EXTERNAL_IP_CHOICE

    if [ "$EXTERNAL_IP_CHOICE" = "2" ]; then
        safe_read \
            "Введите внешний IP-адрес / Enter external IP: " \
            "" \
            EXTERNAL_IP
    else
        EXTERNAL_IP="$AUTO_EXTERNAL_IP"
    fi
else
    warn "Не удалось автоматически определить внешний IP." \
         "Could not automatically determine external IP."
    safe_read \
        "Введите внешний IP-адрес / Enter external IP: " \
        "" \
        EXTERNAL_IP
fi

if [ -z "$EXTERNAL_IP" ]; then
    error "Внешний IP не может быть пустым." \
          "External IP cannot be empty."
fi

info "Используется внешний IP: $EXTERNAL_IP" \
     "External IP in use: $EXTERNAL_IP"

# ==============================================================================
# 1.4 DOMAIN
# ==============================================================================

echo ""

while true; do
    # Никакого автоматического пропуска вопроса.
    # Даже если старый .env существует — спрашиваем всегда.
    safe_read \
        "Введите доменное имя / Enter domain name (e.g., your-domain.com): " \
        "" \
        MAIN_DOMAIN

    MAIN_DOMAIN="${MAIN_DOMAIN#http://}"
    MAIN_DOMAIN="${MAIN_DOMAIN#https://}"
    MAIN_DOMAIN="${MAIN_DOMAIN%%/*}"

    if [ -z "$MAIN_DOMAIN" ]; then
        warn "Домен не может быть пустым." \
             "Domain cannot be empty."
        continue
    fi

    DOTS="${MAIN_DOMAIN//[^.]}"
    if [ -z "$DOTS" ]; then
        warn "Домен должен содержать точку." \
             "Domain must contain a dot."
        continue
    fi

    break
done

info "Используется домен: $MAIN_DOMAIN" \
     "Domain in use: $MAIN_DOMAIN"

# ==============================================================================
# 1.5 EMAIL (авто, без вопроса — поле не используется для отправки писем)
# ==============================================================================

if [ -n "${ADMIN_EMAIL_OVERRIDE:-}" ]; then
    ADMIN_EMAIL="$ADMIN_EMAIL_OVERRIDE"
else
    ADMIN_EMAIL="admin@$MAIN_DOMAIN"
fi

fi

# ==============================================================================
# 1.6 ПРОИЗВОДНЫЕ ДОМЕНЫ
# ==============================================================================

SMP_DOMAIN="smp.$MAIN_DOMAIN"
XFTP_DOMAIN="files.$MAIN_DOMAIN"
TURN_DOMAIN="turn.$MAIN_DOMAIN"

if [ "$REINSTALL_MODE" = false ]; then

# ==============================================================================
# 1.7 СОХРАНЕНИЕ СЕКРЕТОВ ИЗ СТАРОГО .env
# ==============================================================================

SMP_PASS=""
XFTP_PASS=""
TURN_USER="simplex"
TURN_PASS=""

if [ "$EXISTING_ENV" = true ]; then

    info "Читаю из старого .env только секреты..." \
         "Reading only secrets from existing .env..."

    # shellcheck disable=SC1090
    OLD_MAIN_DOMAIN=""
    OLD_EXTERNAL_IP=""
    OLD_INTERNAL_IP=""
    OLD_ADMIN_EMAIL=""
    OLD_WEB_DIR=""

    SMP_PASS=""
    XFTP_PASS=""
    TURN_USER="simplex"
    TURN_PASS=""

    # Безопасно извлекаем только необходимые значения.
    # Остальные параметры старого .env намеренно игнорируются.

    SMP_PASS=$(grep -E '^SMP_PASS=' "$OLD_ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
    XFTP_PASS=$(grep -E '^XFTP_PASS=' "$OLD_ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
    TURN_USER=$(grep -E '^TURN_USER=' "$OLD_ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
    TURN_PASS=$(grep -E '^TURN_PASS=' "$OLD_ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)

    [ -z "$TURN_USER" ] && TURN_USER="simplex"

    info "Существующие секреты сохранены." \
         "Existing secrets preserved."

else

    info "Существующий .env не найден. Будут созданы новые секреты." \
         "Existing .env not found. New secrets will be generated."

fi

# ==============================================================================
# 1.8 ГЕНЕРАЦИЯ ОТСУТСТВУЮЩИХ СЕКРЕТОВ
# ==============================================================================

[ -n "$SMP_PASS" ] || \
    SMP_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

[ -n "$XFTP_PASS" ] || \
    XFTP_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

[ -n "$TURN_PASS" ] || \
    TURN_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

TURN_USER="${TURN_USER:-simplex}"

else
    info "Секреты и адреса используются из сохранённой конфигурации." \
         "Secrets and addresses are used from the saved configuration."
fi

info "Параметры установки собраны." \
     "Installation parameters collected."

echo ""
echo "------------------------------------------"
info "Проверка параметров установки:" \
     "Installation parameters:"
echo "  BASE_DIR:    $BASE_DIR"
echo "  WEB_DIR:     $WEB_DIR"
echo "  INTERNAL_IP: $INTERNAL_IP"
echo "  EXTERNAL_IP: $EXTERNAL_IP"
echo "  DOMAIN:      $MAIN_DOMAIN"
echo "------------------------------------------"

# ==============================================================================
# 2. ПРОВЕРКА DNS
# ==============================================================================
info "Проверка DNS-записей..." "Checking DNS records..."
if command -v dig &>/dev/null; then
    for SUB in smp files turn info.smp; do
        RESOLVED=$(dig +short "${SUB}.${MAIN_DOMAIN}" 2>/dev/null | tail -1)
        if [ "$RESOLVED" != "$EXTERNAL_IP" ]; then
            warn "DNS: ${SUB}.${MAIN_DOMAIN} → ${RESOLVED:-не найдена} (ожидается $EXTERNAL_IP)" \
                 "DNS: ${SUB}.${MAIN_DOMAIN} → ${RESOLVED:-not found} (expected $EXTERNAL_IP)"
        fi
    done
else
    warn "Утилита dig недоступна. Пропуск проверки DNS." \
         "dig utility not available. Skipping DNS check."
fi

# ==============================================================================
# 3. ДИРЕКТОРИИ
# ==============================================================================
info "Подготовка структуры директорий..." "Preparing directory structure..."
if [ -d "$BASE_DIR/smp/data" ] && [ "$(ls -A "$BASE_DIR/smp/data" 2>/dev/null)" ]; then
    warn "Обнаружены существующие данные SMP. Они будут сохранены." \
         "Existing SMP data found. It will be preserved."
fi

mkdir -p "$BASE_DIR"/{smp/{config,certificates,data,logs},xftp/{config,data,files,logs},turn/logs}
mkdir -p "$BASE_DIR/backups"
chown -R 1000:1000 "$BASE_DIR/smp" "$BASE_DIR/xftp"
chmod -R 750 "$BASE_DIR"
success "Директории созданы." "Directories created."

if [ ! -s "$WEB_DIR/favicon.ico" ]; then
    info "Загрузка favicon.ico..." "Downloading favicon.ico..."
    if curl -fsSL --max-time 20 \
        "https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/favicon.ico" \
        -o "$WEB_DIR/favicon.ico" 2>/dev/null; then
        chmod 644 "$WEB_DIR/favicon.ico"
        success "favicon.ico загружен." "favicon.ico downloaded."
    else
        warn "Не удалось загрузить favicon.ico. Панель будет работать без иконки." \
             "Failed to download favicon.ico. Panel will work without icon."
    fi
else
    success "favicon.ico уже существует в $WEB_DIR" "favicon.ico already exists in $WEB_DIR"
fi

# ==============================================================================
# 4. TLS СЕРТИФИКАТЫ
# ==============================================================================
info "Проверка TLS сертификатов SMP..." "Checking SMP TLS certificates..."
if [ ! -s "$BASE_DIR/smp/certificates/$SMP_DOMAIN.crt" ] || [ ! -s "$BASE_DIR/smp/certificates/$SMP_DOMAIN.key" ]; then
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$BASE_DIR/smp/certificates/$SMP_DOMAIN.key" \
        -out    "$BASE_DIR/smp/certificates/$SMP_DOMAIN.crt" \
        -days 3650 -subj "/CN=$SMP_DOMAIN" 2>/dev/null
    success "Новый self-signed сертификат SMP создан." "New self-signed SMP certificate created."
else
    warn "Существующий сертификат SMP сохранён." "Existing SMP certificate preserved."
fi

cp "$BASE_DIR/smp/certificates/$SMP_DOMAIN.crt" "$BASE_DIR/smp/config/server.crt"
cp "$BASE_DIR/smp/certificates/$SMP_DOMAIN.key" "$BASE_DIR/smp/config/server.key"
chown 1000:1000 "$BASE_DIR/smp/config/server."* "$BASE_DIR/smp/certificates/"*
success "TLS сертификаты SMP готовы." "SMP TLS certificates ready."

# ==============================================================================
# 5. .env (БЕЗОПАСНАЯ ГЕНЕРАЦИЯ)
# ==============================================================================
TZ_VALUE=$(grep timezone /etc/synoinfo.conf 2>/dev/null | cut -d'"' -f2 || echo "UTC")

{
    printf '%s\n' "MAIN_DOMAIN=$MAIN_DOMAIN"
    printf '%s\n' "SMP_DOMAIN=$SMP_DOMAIN"
    printf '%s\n' "XFTP_DOMAIN=$XFTP_DOMAIN"
    printf '%s\n' "TURN_DOMAIN=$TURN_DOMAIN"
    printf '%s\n' "EXTERNAL_IP=$EXTERNAL_IP"
    printf '%s\n' "INTERNAL_IP=$INTERNAL_IP"
    printf '%s\n' "ADMIN_EMAIL=$ADMIN_EMAIL"
    printf '%s\n' "SMP_PASS=$SMP_PASS"
    printf '%s\n' "XFTP_PASS=$XFTP_PASS"
    printf '%s\n' "TURN_USER=$TURN_USER"
    printf '%s\n' "TURN_PASS=$TURN_PASS"
    printf '%s\n' "BASE_DIR=$BASE_DIR"
    printf '%s\n' "WEB_DIR=$WEB_DIR"
    printf '%s\n' "TZ=$TZ_VALUE"
} > "$BASE_DIR/.env"

chmod 600 "$BASE_DIR/.env"
success ".env создан безопасно." ".env created securely."

# ==============================================================================
# 6. DOCKER COMPOSE
# ==============================================================================
info "Создание docker-compose.yml..." "Creating docker-compose.yml..."
cat > "$BASE_DIR/docker-compose.yml" << COMPOSEOF
services:
  smp-server:
    image: ${SMP_IMAGE}
    container_name: simplex-smp
    restart: unless-stopped
    ports:
      - "5223:5223"
      - "5224:443"
    volumes:
      - \${BASE_DIR}/smp/config:/etc/opt/simplex:rw
      - \${BASE_DIR}/smp/data:/var/opt/simplex:rw
      - \${BASE_DIR}/smp/logs:/var/log/simplex:rw
      - \${BASE_DIR}/smp/certificates:/certificates:rw
    environment:
      - ADDR=\${SMP_DOMAIN}
      - PASS=\${SMP_PASS}
      - STORE_LOG=on
      - SMP_SERVER_TLS_CERT=/certificates/\${SMP_DOMAIN}.crt
      - SMP_SERVER_TLS_KEY=/certificates/\${SMP_DOMAIN}.key

  xftp-server:
    image: ${XFTP_IMAGE}
    container_name: simplex-xftp
    restart: unless-stopped
    ports:
      - "7788:443"
    volumes:
      - \${BASE_DIR}/xftp/config:/etc/opt/simplex-xftp:rw
      - \${BASE_DIR}/xftp/data:/var/opt/simplex-xftp:rw
      - \${BASE_DIR}/xftp/files:/srv/xftp:rw
    environment:
      - ADDR=\${XFTP_DOMAIN}
      - QUOTA=100gb
      - PASS=\${XFTP_PASS}
    command: ["xftp-server", "run"]

  turn-server:
    image: ${TURN_IMAGE}
    container_name: simplex-turn
    restart: unless-stopped
    network_mode: host
    command: >
      --verbose
      --listening-port=3478
      --tls-listening-port=5349
      --listening-ip=\${INTERNAL_IP}
      --relay-ip=\${INTERNAL_IP}
      --external-ip=\${EXTERNAL_IP}
      --realm=\${TURN_DOMAIN}
      --user=\${TURN_USER}:\${TURN_PASS}
      --lt-cred-mech
      --min-port=49152
      --max-port=65535
      --no-cli
      --fingerprint
COMPOSEOF
success "docker-compose.yml создан." "docker-compose.yml created."

# ==============================================================================
# 7. ИНИЦИАЛИЗАЦИЯ XFTP
# ==============================================================================
info "Проверка инициализации XFTP сервера..." "Checking XFTP server initialization..."
XFTP_FP_FILE="$BASE_DIR/xftp/config/fingerprint"

cleanup_xftp_init() {
    local name="$1"
    docker rm -f "$name" >/dev/null 2>&1 || true
}

if [ -s "$XFTP_FP_FILE" ] && [ "$(head -1 "$XFTP_FP_FILE")" != "PENDING" ]; then
    XFTP_FP_EXISTING=$(head -1 "$XFTP_FP_FILE")
    success "Существующая XFTP identity сохранена: $XFTP_FP_EXISTING" \
            "Existing XFTP identity preserved: $XFTP_FP_EXISTING"
else
    if find "$BASE_DIR/xftp/config" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        error "XFTP config существует, но fingerprint отсутствует. Проверьте $BASE_DIR/xftp/config." \
              "XFTP config exists but fingerprint is missing. Check $BASE_DIR/xftp/config."
    fi

    info "Запуск инициализации XFTP..." "Starting XFTP initialization..."
    XFTP_INIT_NAME="simplex-xftp-init-$$"
    trap "cleanup_xftp_init '$XFTP_INIT_NAME'" EXIT ERR

    if ! docker run -d --name "$XFTP_INIT_NAME" \
        -e ADDR="${XFTP_DOMAIN}" \
        -e QUOTA="100gb" \
        -e PASS="${XFTP_PASS}" \
        -v "$BASE_DIR/xftp/config:/etc/opt/simplex-xftp" \
        -v "$BASE_DIR/xftp/data:/var/opt/simplex-xftp" \
        "$XFTP_IMAGE" \
        xftp-server init -n "$XFTP_DOMAIN" >/dev/null; then
        docker logs "$XFTP_INIT_NAME" 2>&1 | tail -50 || true
        error "Не удалось запустить XFTP init." "Failed to start XFTP init."
    fi

    XFTP_WAIT=0
    while [ "$XFTP_WAIT" -lt 30 ]; do
        if [ -s "$XFTP_FP_FILE" ] && [ "$(head -1 "$XFTP_FP_FILE")" != "PENDING" ]; then
            break
        fi
        sleep 1
        XFTP_WAIT=$((XFTP_WAIT + 1))
    done

    if [ ! -s "$XFTP_FP_FILE" ] || [ "$(head -1 "$XFTP_FP_FILE")" = "PENDING" ]; then
        warn "XFTP fingerprint не появился за 30 секунд. Логи init:" \
             "XFTP fingerprint did not appear within 30 seconds. Init logs:"
        docker logs "$XFTP_INIT_NAME" 2>&1 | tail -80 || true
        error "Не удалось получить XFTP fingerprint." "Failed to obtain XFTP fingerprint."
    fi

    XFTP_FP_INIT=$(head -1 "$XFTP_FP_FILE")
    cleanup_xftp_init "$XFTP_INIT_NAME"
    trap - EXIT ERR
    success "XFTP identity создана: $XFTP_FP_INIT" "XFTP identity created: $XFTP_FP_INIT"
    success "XFTP инициализирован." "XFTP initialized."
fi

chown -R 1000:1000 "$BASE_DIR/xftp"

# ==============================================================================
# 8. ЗАПУСК
# ==============================================================================
cd "$BASE_DIR"
info "Загрузка Docker-образов SimpleX Chat..." "Pulling Docker images SimpleX Chat..."
if ! $COMPOSE_CMD pull; then
    error "Не удалось загрузить Docker-образы." "Failed to pull Docker images."
fi

info "Запуск сервисов..." "Starting services..."
if ! $COMPOSE_CMD up -d; then
    error "Docker Compose не смог запустить сервисы." "Docker Compose failed to start services."
fi

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
# 9. ОЖИДАНИЕ FINGERPRINT
# ==============================================================================
info "Ожидание генерации fingerprint (до 120 сек)..." "Waiting for fingerprint generation (up to 120 sec)..."
sleep 10
WAIT=0; SMP_FP=""
while [ $WAIT -lt 55 ] && [ -z "$SMP_FP" ]; do
    SMP_FP=$(docker logs simplex-smp 2>&1 | grep -i "Fingerprint:" | tail -1 | awk '{print $NF}')
    [ -z "$SMP_FP" ] && SMP_FP=$(cat "$BASE_DIR/smp/config/fingerprint" 2>/dev/null | head -1)
    sleep 2; WAIT=$((WAIT + 1))
done

XFTP_FP=$(docker logs simplex-xftp 2>&1 | grep -i "Fingerprint:" | tail -1 | awk '{print $NF}')
[ -z "$XFTP_FP" ] && XFTP_FP=$(cat "$BASE_DIR/xftp/config/fingerprint" 2>/dev/null | head -1)

if [ -z "$SMP_FP" ] || [ "$SMP_FP" = "PENDING" ]; then
    warn "SMP fingerprint ещё не сгенерирован." "SMP fingerprint not yet generated."
    docker logs simplex-smp 2>&1 | tail -50 || true
    error "Не удалось получить SMP fingerprint. Установка остановлена." \
          "Failed to obtain SMP fingerprint. Installation stopped."
fi

if [ -z "$XFTP_FP" ] || [ "$XFTP_FP" = "PENDING" ]; then
    warn "XFTP fingerprint ещё не сгенерирован." "XFTP fingerprint not yet generated."
    docker logs simplex-xftp 2>&1 | tail -50 || true
    error "Не удалось получить XFTP fingerprint. Установка остановлена." \
          "Failed to obtain XFTP fingerprint. Installation stopped."
fi

SMP_ADDRESS="smp://${SMP_FP}:${SMP_PASS}@${SMP_DOMAIN}:5224"
XFTP_ADDRESS="xftp://${XFTP_FP}:${XFTP_PASS}@${XFTP_DOMAIN}:7788"
TURN_UDP="turn:${TURN_USER}:${TURN_PASS}@${TURN_DOMAIN}:3478?transport=udp"
TURN_TLS="turns:${TURN_USER}:${TURN_PASS}@${TURN_DOMAIN}:5349?transport=tcp"
STUN_ADDR="stun:${TURN_DOMAIN}:3478"
success "Fingerprint получены." "Fingerprints obtained."

# ==============================================================================
# 10. BACKUP SCRIPT
# ==============================================================================
info "Создание скрипта резервного копирования..." "Creating backup script..."
BACKUP_SCRIPT="$BASE_DIR/simplex-backup.sh"
cat > "$BACKUP_SCRIPT" << 'BKEOF'
#!/bin/bash
set -e
BASE_DIR="__BASE_DIR__"
BACKUP_DIR="$BASE_DIR/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"
OUT="$BACKUP_DIR/simplex-backup-$DATE.tar.gz"
if ! tar -czf "$OUT" -C "$BASE_DIR" \
    .env docker-compose.yml CONNECTION_DETAILS.txt \
    smp/config smp/data smp/certificates \
    xftp/config xftp/data xftp/files; then
    rm -f "$OUT"
    echo "Backup failed" >&2
    exit 1
fi
find "$BACKUP_DIR" -name "simplex-backup-*.tar.gz" -mtime +14 -delete
echo "Backup created: $OUT"
BKEOF
sed -i "s|__BASE_DIR__|$BASE_DIR|g" "$BACKUP_SCRIPT"
chmod 700 "$BACKUP_SCRIPT"
success "Backup-скрипт создан." "Backup script created."

# ==============================================================================
# 11. STATUS-UPDATE.SH + CRON
# ==============================================================================
info "Создание скрипта обновления статуса..." "Creating status update script..."
STATUS_SCRIPT="$BASE_DIR/status-update.sh"
cat > "$STATUS_SCRIPT" << STEOF
#!/bin/bash
BASE_DIR="$BASE_DIR"
WEB_DIR="$WEB_DIR"
OUT="\${WEB_DIR}/status.json"
mkdir -p "\$(dirname "\$OUT")"
SMP=\$(docker inspect --format='{{.State.Status}}' simplex-smp 2>/dev/null || echo "not_found")
XFTP=\$(docker inspect --format='{{.State.Status}}' simplex-xftp 2>/dev/null || echo "not_found")
TURN=\$(docker inspect --format='{{.State.Status}}' simplex-turn 2>/dev/null || echo "not_found")
printf '{"simplex-smp":"%s","simplex-xftp":"%s","simplex-turn":"%s","updated":"%s"}\n' \\
    "\$SMP" "\$XFTP" "\$TURN" "\$(date '+%Y-%m-%d %H:%M:%S')" > "\$OUT"
chmod 644 "\$OUT"
STEOF
chmod 755 "$STATUS_SCRIPT"
"$STATUS_SCRIPT"

CRON_LINE="*/1 * * * * root $STATUS_SCRIPT"
if ! grep -q "status-update.sh" /etc/crontab 2>/dev/null; then
    echo "$CRON_LINE" >> /etc/crontab
    synoservicectl --restart crond 2>/dev/null || true
    success "Cron-задача статуса добавлена (каждую минуту)." "Status cron added (every minute)."
else
    warn "Cron-задача status-update.sh уже существует." "status-update.sh cron already exists."
fi

BACKUP_CRON="0 3 * * * root $BASE_DIR/simplex-backup.sh"
if ! grep -q "simplex-backup.sh" /etc/crontab 2>/dev/null; then
    echo "$BACKUP_CRON" >> /etc/crontab
    synoservicectl --restart crond 2>/dev/null || true
    success "Cron-задача backup добавлена (ежедневно в 03:00)." "Backup cron added (daily at 03:00)."
else
    warn "Cron-задача simplex-backup.sh уже существует." "simplex-backup.sh cron already exists."
fi
success "status-update.sh создан." "status-update.sh created."

# ==============================================================================
# 12. WEB-ФАЙЛЫ
# ==============================================================================
info "Создание веб-страниц..." "Creating web pages..."
QRCODE_JS="$WEB_DIR/qrcode.min.js"
if [ ! -s "$QRCODE_JS" ]; then
    info "Загрузка QRCode.js..." "Downloading QRCode.js..."
    if curl -fsSL --max-time 20 \
        "https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main/qrcode.min.js" \
        -o "$QRCODE_JS" 2>/dev/null; then
        chmod 644 "$QRCODE_JS"
        success "QRCode.js загружен." "QRCode.js downloaded."
    else
        error "Не удалось загрузить QRCode.js. Проверьте доступность GitHub." \
              "Failed to download QRCode.js. Check GitHub availability."
    fi
fi
chmod 644 "$QRCODE_JS"

cat > "$WEB_DIR/qrsmp.html" << HTMLEOF
<!DOCTYPE html>
<html lang="ru" data-theme="dark">
<head>
<meta charset="UTF-8">
<link rel="icon" href="favicon.ico" type="image/x-icon">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0c0a14">
<title>SimpleX Control — ${MAIN_DOMAIN}</title>
<style>
[data-theme="dark"]{--bg:#0c0a14;--card:#1a1528;--line:rgba(139,92,246,.12);--text:#f5f3fa;--muted:#9d8fb8;--purple:#8B5CF6;--purple-light:#a78bfa;--green:#34d399;--red:#f87171;--topbar-bg:rgba(12,10,20,.86);--input-bg:#0c0a14;--code-text:#b8a8d8;--icon-bg:rgba(139,92,246,.14);--icon-green:rgba(52,211,153,.12);--btn-bg:rgba(139,92,246,.06);--btn-p-bg:rgba(139,92,246,.16);--btn-p-bd:rgba(139,92,246,.25);--toast-bg:#8B5CF6;--warn-bg:rgba(248,113,113,.07);--warn-bd:rgba(248,113,113,.16);--warn-t:#fca5a5;--logo-bg:linear-gradient(145deg,#2d1f52,#1a1230);--r1:rgba(139,92,246,.14);--r2:rgba(109,40,217,.09);--shadow:rgba(0,0,0,.25);--copy-bg:rgba(139,92,246,.1);--copy-c:#d4c8ee;--footer:#5a4d78;--handle:#4a3d6b;--service-bg:rgba(0,0,0,.2)}
[data-theme="light"]{--bg:#f4f1fa;--card:#fff;--line:rgba(139,92,246,.14);--text:#1a1528;--muted:#6b5f85;--purple:#7C3AED;--purple-light:#6d28d9;--green:#059669;--red:#dc2626;--topbar-bg:rgba(244,241,250,.88);--input-bg:#f0ecf8;--code-text:#4a3d6b;--icon-bg:rgba(139,92,246,.1);--icon-green:rgba(5,150,105,.1);--btn-bg:rgba(139,92,246,.06);--btn-p-bg:rgba(139,92,246,.12);--btn-p-bd:rgba(139,92,246,.22);--toast-bg:#7C3AED;--warn-bg:rgba(220,38,38,.05);--warn-bd:rgba(220,38,38,.14);--warn-t:#b91c1c;--logo-bg:linear-gradient(145deg,#ede9fe,#ddd6fe);--r1:rgba(139,92,246,.08);--r2:rgba(109,40,217,.05);--shadow:rgba(109,40,217,.08);--copy-bg:rgba(139,92,246,.08);--copy-c:#5b21b6;--footer:#8a7aa8;--handle:#c4b5e0;--service-bg:rgba(139,92,246,.05)}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}html{scroll-behavior:smooth}body{margin:0;min-height:100vh;background:radial-gradient(circle at 80% -10%,var(--r1),transparent 32%),radial-gradient(circle at -10% 20%,var(--r2),transparent 28%),var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;transition:background .3s,color .3s}.app{max-width:820px;margin:auto;padding:0 15px 40px}.topbar{position:sticky;top:0;z-index:50;margin:0 -15px;padding:calc(12px + env(safe-area-inset-top)) 15px 12px;background:var(--topbar-bg);backdrop-filter:blur(22px);border-bottom:1px solid var(--line)}.topbar-inner{display:flex;align-items:center;justify-content:space-between}.brand{display:flex;align-items:center;gap:11px}.logo{width:40px;height:40px;display:grid;place-items:center;border-radius:13px;background:var(--logo-bg);border:1px solid var(--line)}.logo svg{width:22px;height:22px;color:var(--purple-light)}.bt{font-size:16px;font-weight:750}.bd{color:var(--muted);font-size:12px}.hbtn{display:grid;place-items:center;width:40px;height:40px;border-radius:12px;border:1px solid var(--line);background:var(--btn-bg);color:var(--text);cursor:pointer}.hbtn svg{width:18px;color:var(--text)}[data-theme="dark"] .hbtn svg{color:#fff}[data-theme="light"] .hbtn svg{color:#1a1528}.hero{padding:25px 2px 18px}.hero h1{margin:0;font-size:28px;letter-spacing:-1px}.hero p{margin:8px 0 0;color:var(--muted);font-size:14px}.card{background:var(--card);border:1px solid var(--line);border-radius:20px;box-shadow:0 12px 35px var(--shadow);padding:20px;margin-bottom:14px;transition:background .3s}.ct{font-size:17px;font-weight:750;margin-bottom:12px;display:flex;align-items:center;gap:9px}.ct svg{width:20px;color:var(--purple-light);flex:none}.st-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}.st-title{font-size:17px;font-weight:750}.st-sub{color:var(--muted);font-size:12px;margin-top:2px}.online{display:flex;align-items:center;gap:7px;font-size:12px;font-weight:700}.online.ok{color:var(--green)}.online.err{color:var(--red)}.online.na{color:var(--muted)}.odot{width:8px;height:8px;border-radius:50%;flex:none}.odot.ok{background:var(--green);box-shadow:0 0 0 4px rgba(52,211,153,.15)}.odot.err{background:var(--red);box-shadow:0 0 0 4px rgba(248,113,113,.15)}.odot.na{background:var(--muted)}.st-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.st-item{padding:12px;background:var(--service-bg);border:1px solid var(--line);border-radius:13px;text-align:center}.st-name{font-size:11px;color:var(--muted)}.st-val{margin-top:3px;font-size:12px;font-weight:700}.st-val.run{color:var(--green)}.st-val.stop{color:var(--red)}.st-val.na{color:var(--muted)}.srv-head{display:flex;align-items:center;gap:12px;margin-bottom:14px}.srv-icon{width:43px;height:43px;flex:none;display:grid;place-items:center;border-radius:14px;background:var(--icon-bg);color:var(--purple-light)}.srv-icon.grn{background:var(--icon-green);color:var(--green)}.srv-icon svg{width:21px}.srv-name{font-size:16px;font-weight:750}.srv-desc{color:var(--muted);font-size:12px;margin-top:2px}.abox{position:relative;padding:12px 43px 12px 12px;border-radius:12px;background:var(--input-bg);border:1px solid var(--line);color:var(--code-text);font:11px/1.55 ui-monospace,Menlo,Consolas,monospace;word-break:break-all}.aval{filter:blur(4px);user-select:none;transition:filter .2s}.abox.rev .aval{filter:none;user-select:text}.cmini{position:absolute;right:7px;top:7px;width:30px;height:30px;border-radius:9px;background:var(--copy-bg);border:1px solid var(--line);color:var(--copy-c);display:grid;place-items:center;cursor:pointer}.cmini svg{width:15px}.tbox{padding:12px;border-radius:12px;background:var(--input-bg);border:1px solid var(--line);color:var(--code-text);font:11px/1.55 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-all}.tval{filter:blur(5px);user-select:none;transition:filter .25s}.tbox.rev .tval{filter:none;user-select:text}.acts{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.tacts{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.btn{min-height:44px;display:flex;align-items:center;justify-content:center;gap:7px;border-radius:12px;border:1px solid var(--line);background:var(--btn-bg);color:var(--text);font-weight:700;font-size:12px;cursor:pointer}.btn:active{transform:scale(.97)}.btn.p{background:var(--btn-p-bg);border-color:var(--btn-p-bd);color:var(--purple-light)}.irow{display:flex;justify-content:space-between;gap:15px;padding:13px 0;border-bottom:1px solid var(--line)}.irow:last-child{border:0}.il{color:var(--muted);font-size:12px}.iv{font-size:12px;font-weight:600}.port-list{display:flex;flex-wrap:wrap;gap:7px}.port-item{padding:7px 14px;border-radius:9px;background:var(--btn-p-bg);color:var(--purple-light);font:12px/1 ui-monospace,Menlo,Consolas,monospace;font-weight:650}.code-block{background:var(--input-bg);border:1px solid var(--line);border-radius:12px;padding:13px;color:var(--code-text);font:10.5px/1.6 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-word}.sec{background:var(--warn-bg);border:1px solid var(--warn-bd);border-radius:20px;padding:17px}.sec-t{color:var(--warn-t);font-size:15px;font-weight:750;margin-bottom:10px}.sec ul{padding-left:19px;margin:0;color:var(--muted);font-size:12px}.sec li{margin-bottom:7px}.footer{text-align:center;padding:22px 0 10px;color:var(--footer);font-size:10px}.toast{position:fixed;left:50%;bottom:30px;transform:translate(-50%,20px);z-index:200;opacity:0;pointer-events:none;padding:11px 18px;background:var(--toast-bg);color:#fff;border-radius:12px;font-size:12px;font-weight:750;box-shadow:0 12px 35px rgba(109,40,217,.3);transition:.2s}.toast.show{opacity:1;transform:translate(-50%,0)}.modal{position:fixed;inset:0;z-index:100;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.65);backdrop-filter:blur(8px)}.modal.on{display:flex}.mcont{width:100%;max-width:420px;padding:20px;background:var(--card);border:1px solid var(--line);border-radius:25px;text-align:center}.mh{width:38px;height:4px;background:var(--handle);border-radius:20px;margin:0 auto 16px}.qrf{padding:12px;background:#fff;border-radius:16px;display:inline-block;margin:14px 0}.qrf img{display:block}.disclaimer-card{border-color:var(--warn-bd)}.box{padding:12px 14px;border-radius:10px;font-size:12px;line-height:1.6;margin:8px 0}.box strong{display:block;margin-bottom:4px;font-size:13px}.box.warn{background:var(--warn-bg);border:1px solid var(--warn-bd);color:var(--warn-t)}.box.info{background:var(--btn-bg);border:1px solid var(--line);color:var(--muted)}.box.note{background:var(--btn-bg);border:1px solid var(--btn-p-bd);color:var(--muted)}.box ul{padding-left:16px;margin:6px 0 0}.box li{margin-bottom:4px}@media(max-width:400px){.app{padding:0 12px 30px}.topbar{margin:0 -12px;padding-left:12px;padding-right:12px}.acts,.tacts{grid-template-columns:1fr}.st-grid{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="app">
<header class="topbar"><div class="topbar-inner">
<div class="brand">
<div class="logo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3l7 4v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V7l7-4z"/><path d="M9 12l2 2 4-4"/></svg></div>
<div><div class="bt">SimpleX Control</div><div class="bd">${MAIN_DOMAIN}</div></div>
</div>
<button class="hbtn" onclick="toggleTheme()" aria-label="Тема">
<svg id="ico-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" style="display:none"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg>
<svg id="ico-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
</button>
</div></header>
<section class="hero"><h1>SimpleX Server</h1><p>Управление серверами и подключение клиентов · ${MAIN_DOMAIN}</p></section>
<section class="card disclaimer-card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>Правовая информация</div>
<div class="box warn"><strong>⚠️ Назначение панели</strong>Данная панель управления предназначена исключительно для администрирования сервера SimpleX Chat, развёрнутого на собственном оборудовании владельца в целях личного и семейного использования. Панель не предназначена для предоставления публичных сервисов неограниченному кругу лиц.</div>
<div class="box info"><strong>📋 Ответственность администратора</strong><ul><li>Использование сервера для предоставления сервиса неограниченному кругу лиц может повлечь обязанность регистрации в качестве организатора распространения информации (ОРИ) в соответствии со ст. 10.1 Федерального закона № 149-ФЗ «Об информации, информационных технологиях и о защите информации».</li><li>Обработка персональных данных пользователей регулируется Федеральным законом № 152-ФЗ «О персональных данных».</li><li>Администратор сервера самостоятельно несёт ответственность за соблюдение применимого законодательства, настройку безопасности, резервное копирование и защиту данных.</li><li>Автор скрипта не несёт ответственности за последствия использования, включая сбои, потерю данных или претензии третьих лиц.</li></ul></div>
<div class="box note"><strong>💡 Рекомендация</strong>Не публикуйте адреса серверов (SMP, XFTP, TURN) и QR-коды в открытом доступе. Перед расширением круга пользователей за пределы семьи или близких знакомых рекомендуется проконсультироваться с квалифицированным юристом, специализирующимся на информационном праве.</div>
</section>
<div class="card">
<div class="st-head"><div><div class="st-title">Серверная инфраструктура</div><div class="st-sub">SimpleX Installer ${INSTALLER_VERSION}</div></div><div class="online na" id="ov-status"><span class="odot na" id="ov-dot"></span><span id="ov-text">…</span></div></div>
<div class="st-grid"><div class="st-item"><div class="st-name">SMP</div><div class="st-val na" id="st-smp">…</div></div><div class="st-item"><div class="st-name">XFTP</div><div class="st-val na" id="st-xftp">…</div></div><div class="st-item"><div class="st-name">TURN</div><div class="st-val na" id="st-turn">…</div></div></div>
</div>
<div class="card">
<div class="srv-head"><div class="srv-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 5h16v11H4z"/><path d="M8 20h8M12 16v4"/></svg></div><div><div class="srv-name">SMP Server</div><div class="srv-desc">Передача сообщений · порт 5224</div></div></div>
<div class="abox" id="smp-box"><span class="aval">${SMP_ADDRESS}</span><button class="cmini" onclick="copyText(S.smp)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="8" y="8" width="11" height="11" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg></button></div>
<div class="acts"><button class="btn p" onclick="openQR('smp')">▦ QR-код</button><button class="btn" onclick="rev('smp-box')">Показать</button></div>
</div>
<div class="card">
<div class="srv-head"><div class="srv-icon grn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 6a2 2 0 0 1 2-2h5l2 2h5a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/></svg></div><div><div class="srv-name">XFTP Server</div><div class="srv-desc">Передача файлов · порт 7788</div></div></div>
<div class="abox" id="xftp-box"><span class="aval">${XFTP_ADDRESS}</span><button class="cmini" onclick="copyText(S.xftp)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="8" y="8" width="11" height="11" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg></button></div>
<div class="acts"><button class="btn p" onclick="openQR('xftp')">▦ QR-код</button><button class="btn" onclick="rev('xftp-box')">Показать</button></div>
</div>
<div class="card">
<div class="srv-head"><div class="srv-icon grn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2c2.5 2.7 4 6.3 4 10s-1.5 7.3-4 10c-2.5-2.7-4-6.3-4-10s1.5-7.3 4-10z"/></svg></div><div><div class="srv-name">TURN / STUN</div><div class="srv-desc">Аудио- и видеозвонки · порты 3478, 5349</div></div></div>
<div class="tbox" id="turn-box"><span class="tval">${STUN_ADDR}
${TURN_UDP}
${TURN_TLS}</span></div>
<div class="tacts"><button class="btn p" onclick="copyText(S.turn)">📋 Копировать все адреса</button><button class="btn" onclick="revT()">Показать</button></div>
</div>
<div class="card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 12h14"/><path d="M12 5l7 7-7 7"/></svg>Подключение</div>
<div class="irow"><div class="il">SMP</div><div class="iv">${SMP_DOMAIN}:5224</div></div>
<div class="irow"><div class="il">XFTP</div><div class="iv">${XFTP_DOMAIN}:7788</div></div>
<div class="irow"><div class="il">TURN / STUN</div><div class="iv">${TURN_DOMAIN}</div></div>
<div class="irow"><div class="il">Протокол</div><div class="iv">TLS / UDP</div></div>
<div class="irow"><div class="il">Версия инсталлера</div><div class="iv">${INSTALLER_VERSION}</div></div>
</div>
<div class="card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><path d="M6 6h.01M6 18h.01"/></svg>Порты</div>
<div class="port-list"><span class="port-item">5224 TCP</span><span class="port-item">7788 TCP</span><span class="port-item">3478 TCP+UDP</span><span class="port-item">5349 TCP</span><span class="port-item">49152-65535 UDP</span></div>
</div>
<div class="card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>Диагностика</div>
<div class="code-block">cd ${BASE_DIR}
docker compose ps
docker logs simplex-smp
docker logs simplex-xftp
docker logs simplex-turn
docker compose pull && docker compose up -d</div>
</div>
<div class="sec">
<div class="sec-t">⚠️ Безопасность</div>
<ul><li>Не публикуйте QR-коды в открытом доступе.</li><li>Не передавайте адреса SMP и XFTP посторонним.</li><li>Храните резервные копии отдельно от NAS.</li><li>При компрометации создайте новые адреса.</li><li>Регулярно обновляйте контейнеры SimpleX.</li><li>Файл .env содержит все пароли — не передавайте его.</li></ul>
</div>
<div class="footer">SimpleX Server · ${MAIN_DOMAIN} · Installer ${INSTALLER_VERSION} · $(date '+%d.%m.%Y')</div>
</div>
<div class="modal" id="qr-modal" onclick="closeQR(event)"><div class="mcont"><div class="mh"></div><div style="font-size:17px;font-weight:750" id="qr-title">QR</div><div class="qrf" id="qr-c"></div><div style="color:var(--muted);font-size:12px">Отсканируйте этот QR-код в приложении SimpleX Chat</div></div></div>
<div class="toast" id="toast">Скопировано</div>
<script src="qrcode.min.js"></script>
<script>
const S={smp:"${SMP_ADDRESS}",xftp:"${XFTP_ADDRESS}",turn:"${STUN_ADDR}\n${TURN_UDP}\n${TURN_TLS}"};
function toggleTheme(){const t=document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark';setTheme(t)}
function setTheme(t){document.documentElement.setAttribute('data-theme',t);localStorage.setItem('simplex-theme',t);updIco(t);document.querySelector('meta[name="theme-color"]').content=t==='dark'?'#0c0a14':'#f4f1fa'}
function updIco(t){document.getElementById('ico-sun').style.display=t==='dark'?'none':'block';document.getElementById('ico-moon').style.display=t==='dark'?'block':'none'}
setTheme(localStorage.getItem('simplex-theme')||'dark');
function copyText(x){if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(x).then(()=>toast('Скопировано'));return}const a=document.createElement('textarea');a.value=x;a.style.cssText='position:fixed;opacity:0';document.body.appendChild(a);a.select();try{document.execCommand('copy');toast('Скопировано')}catch(e){}a.remove()}
function toast(m){const t=document.getElementById('toast');t.textContent=m;t.classList.add('show');clearTimeout(t._t);t._t=setTimeout(()=>t.classList.remove('show'),1800)}
function rev(id){const b=document.getElementById(id);const s=b.querySelector('.aval');if(!b.classList.contains('rev')){const k=id==='smp-box'?'smp':'xftp';s.textContent=S[k]}b.classList.toggle('rev')}
function revT(){const b=document.getElementById('turn-box');const s=b.querySelector('.tval');if(!b.classList.contains('rev'))s.textContent=S.turn;b.classList.toggle('rev')}
function openQR(k){const m=document.getElementById('qr-modal'),c=document.getElementById('qr-c');document.getElementById('qr-title').textContent=(k==='smp'?'SMP':'XFTP')+' — QR';c.innerHTML='';new QRCode(c,{text:S[k],width:250,height:250,colorDark:'#000',colorLight:'#fff',correctLevel:QRCode.CorrectLevel.M});m.classList.add('on');document.body.style.overflow='hidden'}
function closeQR(e){const m=document.getElementById('qr-modal');if(e&&e.target!==m&&!e.target.closest('.mcont'))return;m.classList.remove('on');document.body.style.overflow=''}
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeQR()});
function translateStatus(s){var m={"running":"РАБОТАЕТ","exited":"ОСТАНОВЛЕН","dead":"АВАРИЯ","paused":"ПАУЗА","restarting":"ПЕРЕЗАПУСК","created":"СОЗДАН","not_found":"НЕ НАЙДЕН","removing":"УДАЛЯЕТСЯ"};return m[s]||s.toUpperCase()}
function checkStatus(){fetch('status.json?t='+Date.now()).then(function(r){if(!r.ok)throw new Error(r.status);return r.json()}).then(function(d){var map={'simplex-smp':'st-smp','simplex-xftp':'st-xftp','simplex-turn':'st-turn'};var allOk=true;for(var c in map){var el=document.getElementById(map[c]);var s=d[c]||'not_found';if(s==='running'){el.textContent='● РАБОТАЕТ';el.className='st-val run'}else{el.textContent='● '+translateStatus(s);el.className='st-val stop';allOk=false}}var ov=document.getElementById('ov-status');var od=document.getElementById('ov-dot');var ot=document.getElementById('ov-text');if(allOk){ov.className='online ok';od.className='odot ok';ot.textContent='В СЕТИ'}else{ov.className='online err';od.className='odot err';ot.textContent='ДЕГРАДАЦИЯ'}}).catch(function(){var ov=document.getElementById('ov-status');var od=document.getElementById('ov-dot');var ot=document.getElementById('ov-text');ov.className='online na';od.className='odot na';ot.textContent='НЕТ ДАННЫХ'})}
checkStatus();setInterval(checkStatus,60000);
</script>
</body>
</html>
HTMLEOF
chmod 644 "$WEB_DIR/qrsmp.html"

cat > "$WEB_DIR/index.html" << INDEXEOF
<!DOCTYPE html>
<html lang="ru" data-theme="dark">
<head>
<meta charset="UTF-8">
<link rel="icon" href="favicon.ico" type="image/x-icon">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0c0a14">
<title>SimpleX Server — ${MAIN_DOMAIN}</title>
<style>
[data-theme="dark"]{--bg:#0c0a14;--card:#1a1528;--text:#f5f3fa;--muted:#9d8fb8;--purple:#8B5CF6;--line:rgba(139,92,246,.12);--btn-bg:#8B5CF6;--btn-text:#fff;--info-bg:rgba(139,92,246,.06)}
[data-theme="light"]{--bg:#f4f1fa;--card:#fff;--text:#1a1528;--muted:#6b5f85;--purple:#7C3AED;--line:rgba(139,92,246,.14);--btn-bg:#7C3AED;--btn-text:#fff;--info-bg:rgba(139,92,246,.06)}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;background:var(--bg);color:var(--text);line-height:1.6;transition:background .3s,color .3s}
.container{max-width:520px;margin:0 auto;padding:2rem 1.5rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:2rem;text-align:center;box-shadow:0 12px 35px rgba(0,0,0,.15)}
.logo{width:64px;height:64px;margin:0 auto 1.25rem;background:linear-gradient(145deg,#2d1f52,#1a1230);border-radius:18px;display:grid;place-items:center;border:1px solid var(--line)}
.logo svg{width:32px;height:32px;color:var(--purple)}
h1{margin:0 0 .5rem;font-size:1.6rem;letter-spacing:-.5px}
.sub{color:var(--muted);margin:0 0 1.5rem;font-size:.9rem}
.info{text-align:left;background:var(--info-bg);border:1px solid var(--line);border-radius:12px;padding:1rem 1.25rem;margin-bottom:1.5rem;font-size:.85rem;line-height:1.6;color:var(--muted)}
.info strong{color:var(--text);display:block;margin-bottom:.3rem}
.section-title{font-size:1rem;font-weight:700;color:var(--purple);margin-bottom:.75rem;text-align:left}
.platform-grid{display:flex;flex-wrap:nowrap;gap:.5rem;margin-bottom:1.25rem}
.platform-card{flex:1 1 0;min-width:0;text-align:center;padding:.6rem .4rem;background:var(--info-bg);border:1px solid var(--line);border-radius:10px;text-decoration:none;color:var(--text);font-size:.75rem;font-weight:600;transition:border-color .2s,transform .2s;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.25rem}
.platform-card:hover{border-color:var(--purple);transform:translateY(-2px)}
.platform-icon{font-size:1.5rem;line-height:1}
.qr-section{text-align:center;padding:1rem;background:rgba(139,92,246,.04);border:1px dashed var(--line);border-radius:12px;margin-bottom:1.5rem}
.qr-section p{font-size:.8rem;color:var(--muted);margin-bottom:.5rem}
#download-qr{display:inline-block;padding:10px;background:#fff;border-radius:10px}
#download-qr img,#download-qr canvas{display:block;border-radius:6px}
.qr-hint{font-size:.7rem!important;margin-top:.5rem!important}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:12px 28px;background:var(--btn-bg);color:var(--btn-text);border:none;border-radius:12px;font-size:.95rem;font-weight:700;text-decoration:none;cursor:pointer;transition:transform .15s,opacity .15s;margin-bottom:1rem}
.btn:hover{opacity:.9}.btn:active{transform:scale(.97)}
.footer{margin-top:1.5rem;font-size:.7rem;color:var(--muted)}
.toggle{position:fixed;top:1rem;right:1rem;width:44px;height:44px;border-radius:50%;border:2px solid #d1d5db;background:#a78bfa;color:#ffffff;cursor:pointer;display:grid;place-items:center;z-index:100;box-shadow:0 4px 12px rgba(0,0,0,.4)}
.toggle svg{width:22px;height:22px;color:#ffffff}
@media(max-width:400px){.platform-grid{flex-wrap:wrap}.platform-card{flex:1 1 calc(50% - .35rem);min-width:calc(50% - .35rem)}}
</style>
</head>
<body>
<button class="toggle" onclick="toggleTheme()" aria-label="Тема">
<svg id="ico-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" style="display:none"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg>
<svg id="ico-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
</button>
<div class="container">
<div class="card">
<div class="logo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3l7 4v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V7l7-4z"/><path d="M9 12l2 2 4-4"/></svg></div>
<h1>SimpleX Server</h1>
<p class="sub">Приватный мессенджер · ${MAIN_DOMAIN}</p>
<div class="info">
<strong>🔒 О сервисе</strong>
Этот сервер обеспечивает работу приватного мессенджера SimpleX Chat.
Все сообщения и файлы передаются по зашифрованным каналам.
Сервер не имеет доступа к содержимому переписки.
</div>
<div class="section-title">📱 Установка на смартфон</div>
<div class="platform-grid">
<a href="https://apps.apple.com/app/simplex-chat/id1605771084" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">🍎</span>iOS</a>
<a href="https://play.google.com/store/apps/details?id=chat.simplex.app" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">🤖</span>Android</a>
<a href="https://f-droid.org/packages/chat.simplex.app/" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">📦</span>F-Droid</a>
<a href="https://github.com/simplex-chat/simplex-chat/releases/latest" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">💻</span>Desktop</a>
</div>
<div class="qr-section">
<p>📷 Или отсканируйте QR-код:</p>
<div id="download-qr"></div>
<p class="qr-hint">Ведёт на simplex.chat</p>
</div>
<a href="qrsmp.html" class="btn">
<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
Панель управления
</a>
<div class="footer">SimpleX Installer ${INSTALLER_VERSION} · ${MAIN_DOMAIN}</div>
</div>
</div>
<script>
function toggleTheme(){var t=document.documentElement.getAttribute("data-theme")==="dark"?"light":"dark";document.documentElement.setAttribute("data-theme",t);localStorage.setItem("simplex-theme",t);updIco(t)}
function updIco(t){document.getElementById("ico-sun").style.display=t==="dark"?"none":"block";document.getElementById("ico-moon").style.display=t==="dark"?"block":"none"}
var saved=localStorage.getItem("simplex-theme")||"dark";document.documentElement.setAttribute("data-theme",saved);updIco(saved);
</script>
</body>
</html>
INDEXEOF
chmod 644 "$WEB_DIR/index.html"
success "index.html создан." "index.html created."

cat > "$WEB_DIR/.htaccess" << EOF
<Files "qrsmp.html">
AuthType Basic
AuthName "SimpleX Control — ${MAIN_DOMAIN}"
AuthUserFile ${WEB_DIR}/.htpasswd
Require valid-user
</Files>
<Files "status.json">
AuthType Basic
AuthName "SimpleX Control — ${MAIN_DOMAIN}"
AuthUserFile ${WEB_DIR}/.htpasswd
Require valid-user
</Files>
EOF
chmod 644 "$WEB_DIR/.htaccess"
warn "ВАЖНО: защита паролем сработает только если в Web Station включена опция AllowOverride для виртуального хоста ${MAIN_DOMAIN}." \
     "IMPORTANT: password protection only works if Web Station has AllowOverride enabled for the ${MAIN_DOMAIN} virtual host."

WEB_GROUP=""
if getent group http >/dev/null 2>&1; then
    WEB_GROUP="http"
elif grep -q '^http:' /etc/group 2>/dev/null; then
    WEB_GROUP="http"
fi

if [ ! -f "$WEB_DIR/.htpasswd" ]; then
    WEB_PASS=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
    HASH=$(openssl passwd -apr1 "$WEB_PASS")
    printf 'admin:%s\n' "$HASH" > "$WEB_DIR/.htpasswd"
else
    warn ".htpasswd уже существует. Пароль не изменён." \
         ".htpasswd already exists. Password not changed."
    WEB_PASS=""
fi

if [ -n "$WEB_GROUP" ]; then
    chown root:"$WEB_GROUP" "$WEB_DIR/.htpasswd"
    chmod 640 "$WEB_DIR/.htpasswd"
    success ".htpasswd защищён: root:${WEB_GROUP}, права 640." \
            ".htpasswd protected: root:${WEB_GROUP}, permissions 640."
else
    warn "Группа http не найдена. Файл .htpasswd закрыт максимально (600). Убедитесь, что процесс Apache/Web Station имеет к нему доступ на чтение." \
         "http group not found. .htpasswd locked down to 600. Make sure Apache/Web Station process can still read it."
    chown root:root "$WEB_DIR/.htpasswd"
    chmod 600 "$WEB_DIR/.htpasswd"
fi

if [ -n "${WEB_PASS:-}" ]; then
    success "Веб-пароль создан и сохранён в CONNECTION_DETAILS.txt" \
            "Web password created and saved in CONNECTION_DETAILS.txt"
    warn "Сохраните пароль из файла отчёта! Он показывается только один раз." \
         "Save the password from the report file! It is shown only once."
fi

success "Веб-файлы созданы в $WEB_DIR" "Web files created in $WEB_DIR"
warn "Панель управления будет доступна только по HTTP, пока вы не настроите HTTPS в Web Station." \
     "The control panel will be HTTP-only until you configure HTTPS in Web Station."

# ==============================================================================
# 13. ОТЧЁТ
# ==============================================================================
RESULT_FILE="$BASE_DIR/CONNECTION_DETAILS.txt"
{
    echo "================================================================"
    echo "SIMPLEX CHAT SERVER УСПЕШНО РАЗВЕРНУТ (v${INSTALLER_VERSION})"
    echo "================================================================"
    echo "Дата: $(date)"
    echo "Домен: $MAIN_DOMAIN"
    echo "Внешний IP: $EXTERNAL_IP"
    echo "Внутренний IP: $INTERNAL_IP"
    echo ""
    echo "🔗 АДРЕСА ДЛЯ КЛИЕНТА:"
    echo "SMP:  ${SMP_ADDRESS}"
    echo "XFTP: ${XFTP_ADDRESS}"
    echo ""
    echo "📞 TURN / STUN:"
    echo "${STUN_ADDR}"
    echo "${TURN_UDP}"
    echo "${TURN_TLS}"
    echo ""
    echo "🌐 ПАНЕЛЬ УПРАВЛЕНИЯ:"
    echo "URL: https://info.smp.${MAIN_DOMAIN}  (сначала настройте HTTPS-сертификат в Web Station!)"
    echo "⚠️  До настройки HTTPS сертификата пароль передаётся в открытом виде."
    echo "Логин / Login: admin"
    echo "Пароль / Password: ${WEB_PASS:-см. существующий .htpasswd / see existing .htpasswd}"
    echo ""
    echo "📁 ФАЙЛЫ:"
    echo "Конфигурация / Config: $BASE_DIR/.env"
    echo "Веб-страницы / Web pages: $WEB_DIR/"
    echo "Backup: $BACKUP_SCRIPT"
    echo "Статус: $BASE_DIR/status-update.sh"
    echo ""
    echo "⚠️ ДАЛЬНЕЙШИЕ ДЕЙСТВИЯ / NEXT STEPS:"
    echo "1. Настройте Web Station: корень → $WEB_DIR"
    echo "2. Проброс портов: SMP 5223, 5224, XFTP 7788, TURN 3478, 5349, 49152-65535"
    echo "3. DNS A-записи: smp, files, turn, info.smp → $EXTERNAL_IP"
    echo "4. Откройте порты в Брандмауэре DSM"
    echo "================================================================"
} > "$RESULT_FILE"

chmod 600 "$RESULT_FILE"
echo ""
cat "$RESULT_FILE"
echo ""

info "Статус контейнеров:" "Container status:"
$COMPOSE_CMD ps
echo ""

# ==============================================================================
# 14. POST-INSTALL ПРОВЕРКА
# ==============================================================================
info "Проверка защиты панели управления..." "Checking control panel protection..."

PANEL_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -H "Host: info.smp.${MAIN_DOMAIN}" "http://127.0.0.1/qrsmp.html" 2>/dev/null || echo "000")

if [ "$PANEL_HTTP_CODE" = "000" ]; then
    PANEL_HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
        -H "Host: info.smp.${MAIN_DOMAIN}" "https://127.0.0.1/qrsmp.html" 2>/dev/null || echo "000")
fi

if [ "$PANEL_HTTP_CODE" = "200" ]; then
    warn "КРИТИЧНО: qrsmp.html отдаётся БЕЗ пароля (HTTP 200)! Включите AllowOverride для виртуального хоста в Web Station." \
         "CRITICAL: qrsmp.html is served WITHOUT a password (HTTP 200)! Enable AllowOverride for the virtual host in Web Station."
elif [ "$PANEL_HTTP_CODE" = "401" ]; then
    success "Панель защищена паролем (HTTP 401 без авторизации)." "Panel is password-protected (HTTP 401 without auth)."
else
    info "Не удалось проверить защиту панели локально (код: $PANEL_HTTP_CODE). После настройки Web Station проверьте вручную: откройте https://info.smp.${MAIN_DOMAIN}/qrsmp.html в приватном окне браузера." \
         "Could not verify panel protection locally (code: $PANEL_HTTP_CODE). After configuring Web Station, verify manually: open https://info.smp.${MAIN_DOMAIN}/qrsmp.html in a private browser window."
fi

success "Установка завершена." "Installation completed."
info "Настройте Web Station для доступа к панели управления." \
     "Configure Web Station to access the control panel."