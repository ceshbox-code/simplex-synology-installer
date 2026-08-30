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

umask 022

# На DSM Web Station/Apache всегда работает от пользователя http.
# Проверяем детерминированно, без ps-эвристик.
WEB_USER="";  WEB_GROUP=""
getent passwd http >/dev/null 2>&1 && WEB_USER="http"
getent group  http >/dev/null 2>&1 && WEB_GROUP="http"

TMP_HTPASSWD=$(mktemp)
printf '%s:%s\n' "$NEW_LOGIN" "$HASH" > "$TMP_HTPASSWD"

if [ -n "$WEB_GROUP" ]; then
  chown root:"$WEB_GROUP" "$TMP_HTPASSWD"
  chmod 640 "$TMP_HTPASSWD"          # читает только root и группа http
else
  chmod 644 "$TMP_HTPASSWD"          # НЕ 600! Apache обязан читать файл
fi
mv -f "$TMP_HTPASSWD" "$WEB_DIR/.htpasswd"

# Нормализация веб-папки, БЕЗ затрагивания .htpasswd
chmod 755 "$WEB_DIR" 2>/dev/null || true
find "$WEB_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
find "$WEB_DIR" -type f ! -name '.htpasswd' -exec chmod 644 {} + 2>/dev/null || true

# САМОПРОВЕРКА: веб-пользователь реально может прочитать файл
if [ -n "$WEB_USER" ]; then
  if runuser -u "$WEB_USER" -- cat "$WEB_DIR/.htpasswd" >/dev/null 2>&1; then
    success ".htpasswd доступен пользователю $WEB_USER." \
            ".htpasswd is readable by $WEB_USER."
  else
    error ".htpasswd НЕ читается пользователем $WEB_USER — 500 гарантирована. Проверьте права." \
          ".htpasswd is NOT readable by $WEB_USER — 500 guaranteed. Check permissions."
  fi
fi

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