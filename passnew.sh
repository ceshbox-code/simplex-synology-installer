#!/bin/bash
# ==============================================================================
# SimpleX Web Panel — генерация нового пароля и смена логина
# Файл: passnew.sh
# Запуск:
#   sudo /bin/bash passnew.sh
#   sudo /bin/bash passnew.sh new_login
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR ]${NC} $1"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  error "Скрипт требует прав суперпользователя. Выполните: sudo /bin/bash $0"
fi

command -v openssl >/dev/null 2>&1 || error "openssl не найден."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# 1. Определение BASE_DIR
# ==============================================================================
if [ -n "${BASE_DIR:-}" ] && [ -f "${BASE_DIR}/.env" ]; then
  info "Используется BASE_DIR из окружения: $BASE_DIR"
elif [ -f "$SCRIPT_DIR/.env" ]; then
  BASE_DIR="$SCRIPT_DIR"
elif [ -f "$PWD/.env" ]; then
  BASE_DIR="$PWD"
else
  FOUND_ENV_PATHS=()
  for v in /volume*; do
    if [ -f "$v/docker/simplex/.env" ]; then
      FOUND_ENV_PATHS+=("$v/docker/simplex")
    fi
  done

  if [ ${#FOUND_ENV_PATHS[@]} -eq 1 ]; then
    BASE_DIR="${FOUND_ENV_PATHS[0]}"
  elif [ ${#FOUND_ENV_PATHS[@]} -gt 1 ]; then
    echo ""
    echo "Найдено несколько конфигураций:"
    idx=1
    for p in "${FOUND_ENV_PATHS[@]}"; do
      echo "  $idx) $p"
      idx=$((idx + 1))
    done
    echo ""

    CHOICE=""
    read -p "Выберите номер конфигурации [1]: " CHOICE </dev/tty || true
    CHOICE="${CHOICE:-1}"

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#FOUND_ENV_PATHS[@]} ]; then
      BASE_DIR="${FOUND_ENV_PATHS[$((CHOICE - 1))]}"
    else
      error "Некорректный выбор конфигурации."
    fi
  fi
fi

if [ -z "${BASE_DIR:-}" ] || [ ! -f "$BASE_DIR/.env" ]; then
  INPUT_BASE=""
  read -p "Укажите папку с файлом .env, например /volume1/docker/simplex: " INPUT_BASE </dev/tty || true
  if [ -n "$INPUT_BASE" ]; then
    BASE_DIR="$INPUT_BASE"
  fi
fi

[ -n "${BASE_DIR:-}" ] || error "Не удалось определить BASE_DIR."
[ -f "$BASE_DIR/.env" ] || error "Файл $BASE_DIR/.env не найден."

# shellcheck disable=SC1091
source "$BASE_DIR/.env"

# ==============================================================================
# 2. Определение WEB_DIR
# ==============================================================================
if [ -n "${WEB_DIR_OVERRIDE:-}" ]; then
  WEB_DIR="$WEB_DIR_OVERRIDE"
fi

WEB_DIR="${WEB_DIR:-}"

if [ -z "$WEB_DIR" ] || [ ! -d "$WEB_DIR" ]; then
  INPUT_WEB=""
  read -p "Укажите веб-папку с .htpasswd, например /volume1/web/simplex: " INPUT_WEB </dev/tty || true
  if [ -n "$INPUT_WEB" ]; then
    WEB_DIR="$INPUT_WEB"
  fi
fi

[ -n "$WEB_DIR" ] || error "Не удалось определить WEB_DIR."
mkdir -p "$WEB_DIR"

# ==============================================================================
# 3. Логин
# ==============================================================================
NEW_LOGIN="${1:-${PASSNEW_LOGIN:-}}"

if [ -z "$NEW_LOGIN" ]; then
  NEW_LOGIN=""
  read -p "Новый логин веб-панели [admin]: " NEW_LOGIN </dev/tty || true
  NEW_LOGIN="${NEW_LOGIN:-admin}"
fi

if [[ ! "$NEW_LOGIN" =~ ^[A-Za-z0-9._@-]+$ ]]; then
  error "Логин может содержать только буквы, цифры и символы . _ @ -"
fi

# ==============================================================================
# 4. Генерация пароля
# ==============================================================================
NEW_PASS=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)

if [ ${#NEW_PASS} -lt 16 ]; then
  NEW_PASS="${NEW_PASS}$(openssl rand -hex 8)"
fi

NEW_PASS="${NEW_PASS:0:16}"

HASH=$(openssl passwd -apr1 "$NEW_PASS" 2>/dev/null || openssl passwd -1 "$NEW_PASS" || true)
[ -n "$HASH" ] || error "Не удалось создать hash для пароля."

# ==============================================================================
# 5. Запись .htpasswd
# ------------------------------------------------------------------------------
# Фикс ошибки 500:
# - удаляем возможные CR-символы;
# - определяем пользователя/группу веб-сервера;
# - делаем .htpasswd читаемым для веб-сервера;
# - если группа не найдена, используем 644, но позже закрываем .htpasswd
#   через .htaccess.
# ==============================================================================
NEW_LOGIN=$(printf '%s' "$NEW_LOGIN" | tr -d '\r\n')
HASH=$(printf '%s' "$HASH" | tr -d '\r\n')

[ -n "$NEW_LOGIN" ] || NEW_LOGIN="admin"

TMP_HTPASSWD=$(mktemp)
printf '%s:%s\n' "$NEW_LOGIN" "$HASH" > "$TMP_HTPASSWD"

WEB_SERVER_USER=""
for PATTERN in '[a]pache' '[h]ttpd' '[n]ginx'; do
  CANDIDATE=$(ps aux 2>/dev/null | grep -E "$PATTERN" | awk '{print $1}' | grep -v '^root$' | head -n 1 || true)
  if [ -n "$CANDIDATE" ]; then
    WEB_SERVER_USER="$CANDIDATE"
    break
  fi
done

WEB_GROUP=""
if [ -n "$WEB_SERVER_USER" ]; then
  WEB_GROUP=$(id -gn "$WEB_SERVER_USER" 2>/dev/null || true)
fi

if [ -z "$WEB_GROUP" ] && getent group http >/dev/null 2>&1; then
  WEB_GROUP="http"
elif [ -z "$WEB_GROUP" ] && grep -q '^http:' /etc/group 2>/dev/null; then
  WEB_GROUP="http"
fi

if [ -n "$WEB_GROUP" ]; then
  if ! chown root:"$WEB_GROUP" "$TMP_HTPASSWD" 2>/dev/null; then
    WEB_GROUP=""
  fi
fi

if [ -n "$WEB_GROUP" ]; then
  chmod 640 "$TMP_HTPASSWD"
  success "Права .htpasswd будут установлены в root:${WEB_GROUP}, 640." \
          ".htpasswd permissions will be set to root:${WEB_GROUP}, 640."
else
  chown root:root "$TMP_HTPASSWD"
  chmod 644 "$TMP_HTPASSWD"
  warn "Группа веб-сервера не определена. .htpasswd будет 644, но доступ к нему будет закрыт через .htaccess." \
       "Web server group not detected. .htpasswd will be 644, but access to it will be denied via .htaccess."
fi

mv "$TMP_HTPASSWD" "$WEB_DIR/.htpasswd"

success ".htpasswd обновлён: $WEB_DIR/.htpasswd" \
        ".htpasswd updated: $WEB_DIR/.htpasswd"

# ==============================================================================
# 5b. Пересоздание .htaccess и нормализация прав веб-папки
# ------------------------------------------------------------------------------
# Фикс ошибки 500:
# - .htaccess пересоздаётся с корректным AuthUserFile;
# - .htpasswd и .htaccess закрываются от доступа по HTTP;
# - права веб-папки приводятся к виду, понятному веб-серверу.
# ==============================================================================
HTACCESS_FILE="$WEB_DIR/.htaccess"

if [ -f "$HTACCESS_FILE" ]; then
  cp -a "$HTACCESS_FILE" "${HTACCESS_FILE}.bak-$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
fi

# Если веб-папка находится внутри BASE_DIR, разрешаем проход по родительским
# директориям, но не открываем листинг.
if [ "${WEB_DIR:-}" != "${BASE_DIR:-}" ]; then
  case "${WEB_DIR}/" in
    "${BASE_DIR}/"*)
      chmod 751 "$BASE_DIR" 2>/dev/null || true

      REL_WEB="${WEB_DIR#${BASE_DIR}/}"
      CUR_DIR="$BASE_DIR"

      IFS='/' read -r -a WEB_PARTS <<< "$REL_WEB"
      WEB_LAST_INDEX=$(( ${#WEB_PARTS[@]} - 1 ))

      for i in "${!WEB_PARTS[@]}"; do
        CUR_DIR="$CUR_DIR/${WEB_PARTS[$i]}"
        if [ "$i" -lt "$WEB_LAST_INDEX" ] && [ -d "$CUR_DIR" ]; then
          chmod 751 "$CUR_DIR" 2>/dev/null || true
        fi
      done
      ;;
  esac
fi

# Нормализуем права веб-папки.
chmod 755 "$WEB_DIR" 2>/dev/null || true
find "$WEB_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
find "$WEB_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true

# Пересоздаём .htaccess.
cat > "$HTACCESS_FILE" <<EOF
<Files ".htpasswd">
Require all denied
</Files>

<Files ".htaccess">
Require all denied
</Files>

<Files "qrsmp.html">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${WEB_DIR}/.htpasswd
Require valid-user
</Files>

<Files "status.json">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${WEB_DIR}/.htpasswd
Require valid-user
</Files>

<Files "connection.js">
AuthType Basic
AuthName "SimpleX Control"
AuthUserFile ${WEB_DIR}/.htpasswd
Require valid-user
</Files>
EOF

tr -d '\r' < "$HTACCESS_FILE" > "${HTACCESS_FILE}.tmp" && mv "${HTACCESS_FILE}.tmp" "$HTACCESS_FILE"
chmod 644 "$HTACCESS_FILE"

# После chmod 644 на все файлы возвращаем безопасные права для .htpasswd.
if [ -f "$WEB_DIR/.htpasswd" ]; then
  if [ -n "${WEB_GROUP:-}" ]; then
    chown root:"$WEB_GROUP" "$WEB_DIR/.htpasswd" 2>/dev/null || true
    chmod 640 "$WEB_DIR/.htpasswd" 2>/dev/null || true
  else
    chown root:root "$WEB_DIR/.htpasswd" 2>/dev/null || true
    chmod 644 "$WEB_DIR/.htpasswd" 2>/dev/null || true
  fi
fi

success ".htaccess пересоздан/обновлён: $HTACCESS_FILE" \
        ".htaccess recreated/updated: $HTACCESS_FILE"

# ==============================================================================
# 6. Запись в CONNECTION_DETAILS.txt
# ==============================================================================
TS=$(date '+%Y-%m-%d %H:%M:%S')
DETAILS="$BASE_DIR/CONNECTION_DETAILS.txt"

BEGIN="# === SIMPLEX WEB PANEL CREDENTIALS BEGIN ==="
END="# === SIMPLEX WEB PANEL CREDENTIALS END ==="

PANEL_URL=""
if [ -n "${MAIN_DOMAIN:-}" ]; then
  PANEL_URL="https://info.smp.${MAIN_DOMAIN}/qrsmp.html"
fi

TMP_BLOCK=$(mktemp)
TMP_DETAILS=$(mktemp)

cat > "$TMP_BLOCK" <<EOF
$BEGIN
🌐 ПАНЕЛЬ УПРАВЛЕНИЯ — ДАННЫЕ ВХОДА
Дата и время последней генерации: $TS
Логин / Login: $NEW_LOGIN
Пароль / Password: $NEW_PASS
Файл паролей: $WEB_DIR/.htpasswd
EOF

if [ -n "$PANEL_URL" ]; then
  echo "URL: $PANEL_URL" >> "$TMP_BLOCK"
fi

cat >> "$TMP_BLOCK" <<EOF
Команда смены пароля: sudo /bin/bash $BASE_DIR/passnew.sh
$END
EOF

if [ -f "$DETAILS" ]; then
  if grep -qF "$BEGIN" "$DETAILS" && grep -qF "$END" "$DETAILS"; then
    awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1; next} $0==e{skip=0; next} !skip' "$DETAILS" > "$TMP_DETAILS"
  else
    cat "$DETAILS" > "$TMP_DETAILS"
  fi

  printf '\n' >> "$TMP_DETAILS"
  cat "$TMP_DETAILS" "$TMP_BLOCK" > "$DETAILS"
else
  {
    echo "================================================================"
    echo "SIMPLEX CHAT SERVER — ДАННЫЕ ПОДКЛЮЧЕНИЯ"
    echo "================================================================"
    echo ""
    cat "$TMP_BLOCK"
  } > "$DETAILS"
fi

rm -f "$TMP_BLOCK" "$TMP_DETAILS"

chmod 600 "$DETAILS"

success "CONNECTION_DETAILS.txt обновлён: $DETAILS"

# ==============================================================================
# 7. Итог
# ==============================================================================
echo ""
success "Пароль веб-панели обновлён."
echo "----------------------------------------"
echo "Логин / Login: $NEW_LOGIN"
echo "Пароль / Password: $NEW_PASS"
echo "Дата и время: $TS"
echo "Файл паролей: $WEB_DIR/.htpasswd"
echo "Записано в: $DETAILS"
echo "----------------------------------------"
warn "Сохраните пароль. При следующем открытии qrsmp.html потребуется новый пароль."