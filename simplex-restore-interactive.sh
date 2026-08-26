#!/bin/bash
set -Eeuo pipefail

VERSION="2.0.0"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

error() {
  printf '%s[ERR ]%s %s\n' "$RED" "$NC" "$*" >&2
  exit 1
}

warn() {
  printf '%s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2
}

info() {
  printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"
}

success() {
  printf '%s[ OK ]%s %s\n' "$GREEN" "$NC" "$*"
}

ok() {
  printf '%s[ OK ]%s %s\n' "$GREEN" "$NC" "$*"
}

safe_read() {
  local prompt="$1"
  local default="${2:-}"
  local var="$3"
  local value=""

  if [ -c /dev/tty ]; then
    read -r -p "$prompt" value < /dev/tty || true
  else
    read -r -p "$prompt" value || true
  fi

  [ -z "$value" ] && value="$default"
  printf -v "$var" '%s' "$value"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

get_env_value() {
  local file="$1"
  local key="$2"

  awk -v k="$key" '
    index($0, k"=") == 1 {
      val = substr($0, length(k) + 2)
      sub(/\r$/, "", val)
      print val
      exit
    }
  ' "$file" 2>/dev/null || true
}

update_env_var() {
  local file="$1"
  local key="$2"
  local val="$3"

  if grep -q "^${key}=" "$file" 2>/dev/null; then
    awk -v k="$key" -v v="$val" '
      index($0, k"=") == 1 {
        print k "=" v
        next
      }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

detect_internal_ip() {
  if ! command -v ip >/dev/null 2>&1; then
    return 0
  fi

  local out=""

  out=$(ip route get 1 2>/dev/null | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i == "src") {
        print $(i + 1)
        exit
      }
    }
  }')

  if [ -z "$out" ]; then
    out=$(ip -4 route get 1 2>/dev/null | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i + 1)
          exit
        }
      }
    }')
  fi

  printf '%s' "$out"
}

detect_external_ip() {
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null | tr -d '[:space:]' || true
}

ask_ip() {
  local prompt="$1"
  local default="$2"
  local var="$3"
  local value=""

  while true; do
    safe_read "$prompt" "$default" value
    value=$(trim "$value")

    if [[ "$value" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      printf -v "$var" '%s' "$value"
      return 0
    fi

    warn "Некорректный IPv4-адрес: ${value:-<пусто>}"
    default="$value"
  done
}

scan_backup_files() {
  local dirs=()
  local d
  local script_path
  local bd

  for d in /volume*/docker/simplex/backups; do
    [ -d "$d" ] && dirs+=("$d")
  done

  if [ -f /etc/crontab ]; then
    script_path=$(awk '!/^#/ && /simplex-backup\.sh/ {print $NF; exit}' /etc/crontab 2>/dev/null || true)
    if [ -n "${script_path:-}" ]; then
      bd="$(dirname "$script_path")/backups"
      [ -d "$bd" ] && dirs+=("$bd")
    fi
  fi

  if [ -d "$(pwd)/backups" ]; then
    dirs+=("$(pwd)/backups")
  fi

  if [ ${#dirs[@]} -eq 0 ]; then
    return 0
  fi

  find "${dirs[@]}" -maxdepth 1 -type f -name 'simplex-backup-*.tar.gz' 2>/dev/null | sort | awk '!seen[$0]++'
}

echo ""
echo "=========================================="
echo "  SIMPLEX RESTORE v${VERSION} — SYNOLOGY"
echo "=========================================="
echo ""

[ "$(id -u)" -eq 0 ] || error "Скрипт нужно запускать от root: sudo bash $0"
command -v docker >/dev/null 2>&1 || error "Docker не найден."
command -v tar >/dev/null 2>&1 || error "tar не найден."
command -v awk >/dev/null 2>&1 || error "awk не найден."

docker info >/dev/null 2>&1 || warn "Docker daemon недоступен или ещё не запущен."

COMPOSE=()
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  error "Docker Compose не найден."
fi

# ==========================================================
# 1. Поиск всех архивов бэкапов
# ==========================================================

BACKUP_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && BACKUP_FILES+=("$f")
done < <(scan_backup_files)

if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
  error "Не найдено ни одного архива simplex-backup-*.tar.gz"
fi

echo ""
info "Доступные архивы бэкапов:"
idx=1
for f in "${BACKUP_FILES[@]}"; do
  echo "  $idx) $f"
  idx=$((idx + 1))
done
echo ""

while true; do
  safe_read "Выберите номер архива [${#BACKUP_FILES[@]}]: " "${#BACKUP_FILES[@]}" ARCHIVE_CHOICE

  if [[ "$ARCHIVE_CHOICE" =~ ^[0-9]+$ ]] && \
     [ "$ARCHIVE_CHOICE" -ge 1 ] && \
     [ "$ARCHIVE_CHOICE" -le ${#BACKUP_FILES[@]} ]; then
    BACKUP_FILE="${BACKUP_FILES[$((ARCHIVE_CHOICE - 1))]}"
    break
  fi

  warn "Некорректный выбор. Введите число от 1 до ${#BACKUP_FILES[@]}."
done

info "Выбран архив: $BACKUP_FILE"

# ==========================================================
# 2. Определение целевой директории
# ==========================================================

ARCHIVE_DIR=$(dirname "$BACKUP_FILE")

if [ "$(basename "$ARCHIVE_DIR")" = "backups" ]; then
  BASE_DIR=$(dirname "$ARCHIVE_DIR")
else
  BASE_DIR="$ARCHIVE_DIR"
fi

if [[ "$BASE_DIR" != */simplex ]]; then
  warn "Архив находится вне стандартной директории .../docker/simplex."
  safe_read "Целевая директория для восстановления [$BASE_DIR]: " "$BASE_DIR" BASE_DIR_INPUT
  BASE_DIR=$(trim "$BASE_DIR_INPUT")
fi

BASE_DIR="${BASE_DIR%/}"
[[ "$BASE_DIR" = /* ]] || BASE_DIR="$(pwd)/$BASE_DIR"

case "$BASE_DIR" in
  ""|"/")
    error "Невозможно определить целевую директорию."
    ;;
esac

info "Целевая директория: $BASE_DIR"

# ==========================================================
# 3. Проверка целостности архива
# ==========================================================

WORK_DIR=$(mktemp -d /tmp/simplex-restore.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/stage"

echo ""
info "Проверка целостности архива..."

if ! tar -tzf "$BACKUP_FILE" > "$WORK_DIR/list.txt"; then
  error "Не удалось прочитать архив: $BACKUP_FILE"
fi

if ! tar -xzf "$BACKUP_FILE" -C "$WORK_DIR/stage"; then
  error "Не удалось распаковать архив: $BACKUP_FILE"
fi

FILE_COUNT=0
FAILED=0

while IFS= read -r rel; do
  if [ -f "$WORK_DIR/stage/$rel" ]; then
    ok "$rel"
    FILE_COUNT=$((FILE_COUNT + 1))
  else
    printf '%s[ERR ]%s %s\n' "$RED" "$NC" "$rel"
    FAILED=1
  fi
done < <(cd "$WORK_DIR/stage" && find . -type f | sed 's|^\./||' | sort)

if [ "$FAILED" -ne 0 ]; then
  error "Проверка целостности завершена с ошибками."
fi

if [ "$FILE_COUNT" -eq 0 ]; then
  error "Архив не содержит файлов."
fi

success "Архив прочитан. Файлов: $FILE_COUNT"

echo ""
info "Проверка обязательных компонентов:"

REQUIRED=(
  ".env"
  "docker-compose.yml"
  "smp/config"
  "smp/data"
  "smp/certificates"
  "xftp/config"
  "xftp/data"
  "xftp/files"
)

for req in "${REQUIRED[@]}"; do
  if [ -e "$WORK_DIR/stage/$req" ]; then
    ok "$req"
  else
    error "В архиве отсутствует обязательный компонент: $req"
  fi
done

STAGE_ENV="$WORK_DIR/stage/.env"
[ -f "$STAGE_ENV" ] || error "В архиве отсутствует .env"

OLD_MAIN_DOMAIN=$(get_env_value "$STAGE_ENV" "MAIN_DOMAIN")
OLD_SMP_DOMAIN=$(get_env_value "$STAGE_ENV" "SMP_DOMAIN")
OLD_XFTP_DOMAIN=$(get_env_value "$STAGE_ENV" "XFTP_DOMAIN")
OLD_TURN_DOMAIN=$(get_env_value "$STAGE_ENV" "TURN_DOMAIN")
OLD_INTERNAL_IP=$(get_env_value "$STAGE_ENV" "INTERNAL_IP")
OLD_EXTERNAL_IP=$(get_env_value "$STAGE_ENV" "EXTERNAL_IP")
OLD_ADMIN_EMAIL=$(get_env_value "$STAGE_ENV" "ADMIN_EMAIL")

# ==========================================================
# 4. Выбор режима настроек
# ==========================================================

echo ""
echo "1) Использовать существующие настройки"
echo "2) Изменить настройки"
echo ""

while true; do
  safe_read "Ваш выбор [1]: " "1" SETTINGS_CHOICE

  if [[ "$SETTINGS_CHOICE" =~ ^[12]$ ]]; then
    break
  fi

  warn "Выберите 1 или 2."
done

SETTINGS_CHANGED=false

if [ "$SETTINGS_CHOICE" = "2" ]; then
  SETTINGS_CHANGED=true

  # ------------------------------------------------------------
  # Внутренний IP
  # ------------------------------------------------------------
  AUTO_INTERNAL_IP=$(detect_internal_ip)

  echo ""
  if [ -n "$AUTO_INTERNAL_IP" ]; then
    info "Автоматически определён внутренний IP NAS: $AUTO_INTERNAL_IP"
    echo "  1) Использовать определённый IP ($AUTO_INTERNAL_IP)"
    echo "  2) Ввести свой IP"
    echo ""

    while true; do
      safe_read "Ваш выбор [1]: " "1" INTERNAL_CHOICE
      if [[ "$INTERNAL_CHOICE" =~ ^[12]$ ]]; then
        break
      fi
      warn "Выберите 1 или 2."
    done

    if [ "$INTERNAL_CHOICE" = "2" ]; then
      ask_ip "Введите внутренний IP NAS [$OLD_INTERNAL_IP]: " "$OLD_INTERNAL_IP" INTERNAL_IP
    else
      INTERNAL_IP="$AUTO_INTERNAL_IP"
    fi
  else
    warn "Не удалось автоматически определить внутренний IP."
    ask_ip "Введите внутренний IP NAS [$OLD_INTERNAL_IP]: " "$OLD_INTERNAL_IP" INTERNAL_IP
  fi

  info "Используется внутренний IP: $INTERNAL_IP"

  # ------------------------------------------------------------
  # Внешний IP
  # ------------------------------------------------------------
  AUTO_EXTERNAL_IP=$(detect_external_ip)

  echo ""
  if [ -n "$AUTO_EXTERNAL_IP" ]; then
    info "Автоматически определён внешний IP: $AUTO_EXTERNAL_IP"
    echo "  1) Использовать определённый IP ($AUTO_EXTERNAL_IP)"
    echo "  2) Ввести свой IP"
    echo ""

    while true; do
      safe_read "Ваш выбор [1]: " "1" EXTERNAL_CHOICE
      if [[ "$EXTERNAL_CHOICE" =~ ^[12]$ ]]; then
        break
      fi
      warn "Выберите 1 или 2."
    done

    if [ "$EXTERNAL_CHOICE" = "2" ]; then
      ask_ip "Введите внешний IP-адрес [$OLD_EXTERNAL_IP]: " "$OLD_EXTERNAL_IP" EXTERNAL_IP
    else
      EXTERNAL_IP="$AUTO_EXTERNAL_IP"
    fi
  else
    warn "Не удалось автоматически определить внешний IP."
    ask_ip "Введите внешний IP-адрес [$OLD_EXTERNAL_IP]: " "$OLD_EXTERNAL_IP" EXTERNAL_IP
  fi

  info "Используется внешний IP: $EXTERNAL_IP"

  # ------------------------------------------------------------
  # Домен
  # ------------------------------------------------------------
  echo ""
  while true; do
    safe_read "Укажите Ваш домен [$OLD_MAIN_DOMAIN]: " "$OLD_MAIN_DOMAIN" MAIN_DOMAIN
    MAIN_DOMAIN=$(trim "$MAIN_DOMAIN")

    MAIN_DOMAIN="${MAIN_DOMAIN#http://}"
    MAIN_DOMAIN="${MAIN_DOMAIN#https://}"
    MAIN_DOMAIN="${MAIN_DOMAIN%%/*}"

    if [ -z "$MAIN_DOMAIN" ]; then
      warn "Домен не может быть пустым."
      continue
    fi

    DOTS="${MAIN_DOMAIN//[^.]}"
    if [ -z "$DOTS" ]; then
      warn "Домен должен содержать точку."
      continue
    fi

    break
  done

  info "Используется домен: $MAIN_DOMAIN"

  # ------------------------------------------------------------
  # Email администратора
  # ------------------------------------------------------------
  EMAIL_DEFAULT="admin@$MAIN_DOMAIN"
  [ -z "$OLD_ADMIN_EMAIL" ] && OLD_ADMIN_EMAIL="$EMAIL_DEFAULT"

  safe_read "Укажите эл. почту админа [$EMAIL_DEFAULT]: " "$EMAIL_DEFAULT" ADMIN_EMAIL
  ADMIN_EMAIL=$(trim "$ADMIN_EMAIL")
  [ -z "$ADMIN_EMAIL" ] && ADMIN_EMAIL="$EMAIL_DEFAULT"

  info "Email администратора: $ADMIN_EMAIL"

  NEW_SMP_DOMAIN="smp.$MAIN_DOMAIN"
  NEW_XFTP_DOMAIN="files.$MAIN_DOMAIN"
  NEW_TURN_DOMAIN="turn.$MAIN_DOMAIN"
else
  MAIN_DOMAIN="$OLD_MAIN_DOMAIN"
  INTERNAL_IP="$OLD_INTERNAL_IP"
  EXTERNAL_IP="$OLD_EXTERNAL_IP"
  ADMIN_EMAIL="$OLD_ADMIN_EMAIL"
  NEW_SMP_DOMAIN="$OLD_SMP_DOMAIN"
  NEW_XFTP_DOMAIN="$OLD_XFTP_DOMAIN"
  NEW_TURN_DOMAIN="$OLD_TURN_DOMAIN"
fi

# ==========================================================
# 5. Подтверждение восстановления
# ==========================================================

echo ""
info "План восстановления:"
echo "  Архив:              $BACKUP_FILE"
echo "  Целевая директория: $BASE_DIR"

if $SETTINGS_CHANGED; then
  echo "  Настройки:          будут изменены"
  echo "  MAIN_DOMAIN:        $MAIN_DOMAIN"
  echo "  INTERNAL_IP:        $INTERNAL_IP"
  echo "  EXTERNAL_IP:        $EXTERNAL_IP"
  echo "  ADMIN_EMAIL:        $ADMIN_EMAIL"
else
  echo "  Настройки:          из архива"
fi

echo ""
safe_read "Начать восстановление? [y/N]: " "n" CONFIRM

if ! [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  info "Отменено."
  exit 0
fi

# ==========================================================
# 6. Снимок текущего состояния
# ==========================================================

mkdir -p "$BASE_DIR/backups"

SNAP_MEMBERS=()
for m in .env docker-compose.yml CONNECTION_DETAILS.txt smp xftp simplex-backup.sh status-update.sh; do
  [ -e "$BASE_DIR/$m" ] && SNAP_MEMBERS+=("$m")
done

if [ ${#SNAP_MEMBERS[@]} -gt 0 ]; then
  SNAPSHOT_FILE="$BASE_DIR/backups/pre-restore-$(date +%Y%m%d_%H%M%S).tar.gz"

  if tar -czf "$SNAPSHOT_FILE" -C "$BASE_DIR" "${SNAP_MEMBERS[@]}"; then
    success "Снимок текущего состояния создан: $SNAPSHOT_FILE"
  else
    warn "Не удалось создать снимок текущего состояния."
  fi
else
  info "Целевая директория пуста или не содержит данных для снимка."
fi

# ==========================================================
# 7. Остановка контейнеров
# ==========================================================

echo ""
info "Остановка контейнеров SimpleX..."

if [ -f "$BASE_DIR/docker-compose.yml" ]; then
  (cd "$BASE_DIR" && "${COMPOSE[@]}" down || true)
fi

for c in simplex-smp simplex-xftp simplex-turn; do
  if docker inspect "$c" >/dev/null 2>&1; then
    docker rm -f "$c" >/dev/null 2>&1 || true
  fi
done

success "Контейнеры остановлены."

# ==========================================================
# 8. Очистка восстанавливаемых путей
# ==========================================================

info "Подготовка целевой директории..."

RESTORE_PATHS=(
  ".env"
  "docker-compose.yml"
  "CONNECTION_DETAILS.txt"
  "smp/config"
  "smp/data"
  "smp/certificates"
  "xftp/config"
  "xftp/data"
  "xftp/files"
)

for p in "${RESTORE_PATHS[@]}"; do
  if [ -e "$WORK_DIR/stage/$p" ] && [ -e "$BASE_DIR/$p" ]; then
    rm -rf -- "${BASE_DIR:?}/$p"
  fi
done

# ==========================================================
# 9. Копирование файлов из архива
# ==========================================================

info "Восстановление файлов из архива..."

tar -C "$WORK_DIR/stage" -cf - . | tar -C "$BASE_DIR" -xf - || error "Не удалось скопировать файлы из архива."

success "Файлы восстановлены."

# ==========================================================
# 10. Обновление .env
# ==========================================================

if [ ! -f "$BASE_DIR/.env" ]; then
  error "После восстановления отсутствует .env"
fi

update_env_var "$BASE_DIR/.env" "BASE_DIR" "$BASE_DIR"

if $SETTINGS_CHANGED; then
  info "Обновление настроек в .env..."

  update_env_var "$BASE_DIR/.env" "MAIN_DOMAIN" "$MAIN_DOMAIN"
  update_env_var "$BASE_DIR/.env" "SMP_DOMAIN" "$NEW_SMP_DOMAIN"
  update_env_var "$BASE_DIR/.env" "XFTP_DOMAIN" "$NEW_XFTP_DOMAIN"
  update_env_var "$BASE_DIR/.env" "TURN_DOMAIN" "$NEW_TURN_DOMAIN"
  update_env_var "$BASE_DIR/.env" "INTERNAL_IP" "$INTERNAL_IP"
  update_env_var "$BASE_DIR/.env" "EXTERNAL_IP" "$EXTERNAL_IP"
  update_env_var "$BASE_DIR/.env" "ADMIN_EMAIL" "$ADMIN_EMAIL"

  success ".env обновлён."
fi

chmod 600 "$BASE_DIR/.env"

# ==========================================================
# 11. Сертификаты при смене домена
# ==========================================================

CURRENT_SMP_DOMAIN=$(get_env_value "$BASE_DIR/.env" "SMP_DOMAIN")

if [ -n "$CURRENT_SMP_DOMAIN" ]; then
  if $SETTINGS_CHANGED && [ -n "${OLD_SMP_DOMAIN:-}" ] && [ "$OLD_SMP_DOMAIN" != "$CURRENT_SMP_DOMAIN" ]; then
    info "Домен SMP изменён: $OLD_SMP_DOMAIN -> $CURRENT_SMP_DOMAIN"

    if [ -f "$BASE_DIR/smp/certificates/$OLD_SMP_DOMAIN.crt" ] && \
       [ -f "$BASE_DIR/smp/certificates/$OLD_SMP_DOMAIN.key" ]; then
      [ -f "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.crt" ] || \
        cp "$BASE_DIR/smp/certificates/$OLD_SMP_DOMAIN.crt" "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.crt"

      [ -f "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.key" ] || \
        cp "$BASE_DIR/smp/certificates/$OLD_SMP_DOMAIN.key" "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.key"

      success "Старые сертификаты скопированы для нового домена."
    fi
  fi

  if [ ! -s "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.crt" ] || \
     [ ! -s "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.key" ]; then
    warn "Сертификат для $CURRENT_SMP_DOMAIN отсутствует. Создаю новый self-signed сертификат."
    command -v openssl >/dev/null 2>&1 || error "openssl не найден."

    openssl req -x509 -newkey rsa:4096 -nodes \
      -keyout "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.key" \
      -out "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.crt" \
      -days 3650 -subj "/CN=$CURRENT_SMP_DOMAIN" 2>/dev/null \
      || error "Не удалось создать сертификат для $CURRENT_SMP_DOMAIN"

    success "Новый сертификат создан."
  fi

  if [ -f "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.crt" ] && \
     [ -f "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.key" ]; then
    cp -f "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.crt" "$BASE_DIR/smp/config/server.crt"
    cp -f "$BASE_DIR/smp/certificates/$CURRENT_SMP_DOMAIN.key" "$BASE_DIR/smp/config/server.key"
  fi

  chown 1000:1000 "$BASE_DIR/smp/config/server."* 2>/dev/null || true
  chown 1000:1000 "$BASE_DIR/smp/certificates/"* 2>/dev/null || true
fi

# ==========================================================
# 12. Права
# ==========================================================

info "Восстановление прав..."

if [ -d "$BASE_DIR/smp" ]; then
  chown -R 1000:1000 "$BASE_DIR/smp" || true
  find "$BASE_DIR/smp" -type d -exec chmod 750 {} + 2>/dev/null || true
fi

if [ -d "$BASE_DIR/xftp" ]; then
  chown -R 1000:1000 "$BASE_DIR/xftp" || true
  find "$BASE_DIR/xftp" -type d -exec chmod 750 {} + 2>/dev/null || true
fi

[ -f "$BASE_DIR/.env" ] && chmod 600 "$BASE_DIR/.env"
[ -f "$BASE_DIR/CONNECTION_DETAILS.txt" ] && chmod 600 "$BASE_DIR/CONNECTION_DETAILS.txt"

find "$BASE_DIR/smp/certificates" "$BASE_DIR/smp/config" -type f \( -name '*.key' -o -name '*.crt' \) -exec chmod 600 {} + 2>/dev/null || true
find "$BASE_DIR/xftp/config" -type f -name '*.key' -exec chmod 600 {} + 2>/dev/null || true

success "Права восстановлены."

# ==========================================================
# 13. Запуск контейнеров
# ==========================================================

cd "$BASE_DIR"

echo ""
info "Загрузка Docker-образов..."
"${COMPOSE[@]}" pull || warn "Docker pull завершился с ошибкой. Пробую запустить с существующими образами."

info "Запуск сервисов..."
"${COMPOSE[@]}" up -d || error "Docker Compose не смог запустить сервисы."

sleep 5

FAILED=false
for c in simplex-smp simplex-xftp simplex-turn; do
  RUNNING=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null || echo "false")

  if [ "$RUNNING" != "true" ]; then
    FAILED=true
    warn "$c не запущен. Логи:"
    docker logs --tail 50 "$c" 2>&1 || true
  fi
done

if $FAILED; then
  error "Один или несколько контейнеров не запустились. Проверьте логи выше."
fi

success "Контейнеры запущены."

# ==========================================================
# 14. Ожидание fingerprint
# ==========================================================

info "Ожидание появления fingerprint..."

SMP_FP=""
XFTP_FP=""

for i in {1..30}; do
  SMP_FP=$(head -1 "$BASE_DIR/smp/config/fingerprint" 2>/dev/null || true)
  XFTP_FP=$(head -1 "$BASE_DIR/xftp/config/fingerprint" 2>/dev/null || true)

  if [ -n "$SMP_FP" ] && [ "$SMP_FP" != "PENDING" ] && \
     [ -n "$XFTP_FP" ] && [ "$XFTP_FP" != "PENDING" ]; then
    break
  fi

  sleep 2
done

if [ -z "$SMP_FP" ] || [ "$SMP_FP" = "PENDING" ]; then
  SMP_FP=$(docker logs simplex-smp 2>&1 | grep -i 'Fingerprint:' | tail -1 | awk '{print $NF}' || true)
fi

if [ -z "$XFTP_FP" ] || [ "$XFTP_FP" = "PENDING" ]; then
  XFTP_FP=$(docker logs simplex-xftp 2>&1 | grep -i 'Fingerprint:' | tail -1 | awk '{print $NF}' || true)
fi

echo ""
info "Fingerprints:"
echo "  SMP:  ${SMP_FP:-не найден}"
echo "  XFTP: ${XFTP_FP:-не найден}"

if [ -z "${SMP_FP:-}" ] || [ "${SMP_FP:-}" = "PENDING" ] || \
   [ -z "${XFTP_FP:-}" ] || [ "${XFTP_FP:-}" = "PENDING" ]; then
  warn "Fingerprint ещё не готов. Проверьте: docker logs simplex-smp / docker logs simplex-xftp"
fi

# ==========================================================
# 15. Обновление CONNECTION_DETAILS.txt при смене настроек
# ==========================================================

if $SETTINGS_CHANGED; then
  if [ -n "${SMP_FP:-}" ] && [ "${SMP_FP}" != "PENDING" ] && \
     [ -n "${XFTP_FP:-}" ] && [ "${XFTP_FP}" != "PENDING" ]; then

    SMP_PASS=$(get_env_value "$BASE_DIR/.env" "SMP_PASS")
    XFTP_PASS=$(get_env_value "$BASE_DIR/.env" "XFTP_PASS")
    TURN_USER=$(get_env_value "$BASE_DIR/.env" "TURN_USER")
    TURN_PASS=$(get_env_value "$BASE_DIR/.env" "TURN_PASS")

    CURRENT_SMP_DOMAIN=$(get_env_value "$BASE_DIR/.env" "SMP_DOMAIN")
    CURRENT_XFTP_DOMAIN=$(get_env_value "$BASE_DIR/.env" "XFTP_DOMAIN")
    CURRENT_TURN_DOMAIN=$(get_env_value "$BASE_DIR/.env" "TURN_DOMAIN")
    CURRENT_EXTERNAL_IP=$(get_env_value "$BASE_DIR/.env" "EXTERNAL_IP")
    CURRENT_INTERNAL_IP=$(get_env_value "$BASE_DIR/.env" "INTERNAL_IP")

    if [ -n "$SMP_PASS" ] && [ -n "$XFTP_PASS" ] && [ -n "$TURN_USER" ] && [ -n "$TURN_PASS" ]; then
      SMP_ADDRESS="smp://${SMP_FP}:${SMP_PASS}@${CURRENT_SMP_DOMAIN}:5224"
      XFTP_ADDRESS="xftp://${XFTP_FP}:${XFTP_PASS}@${CURRENT_XFTP_DOMAIN}:7788"
      STUN_ADDR="stun:${CURRENT_TURN_DOMAIN}:3478"
      TURN_UDP="turn:${TURN_USER}:${TURN_PASS}@${CURRENT_TURN_DOMAIN}:3478?transport=udp"
      TURN_TLS="turns:${TURN_USER}:${TURN_PASS}@${CURRENT_TURN_DOMAIN}:5349?transport=tcp"

      cat > "$BASE_DIR/CONNECTION_DETAILS.txt" <<EOF
================================================================
SIMPLEX CHAT SERVER RESTORED / SETTINGS UPDATED
================================================================
Дата: $(date)
Домен: $MAIN_DOMAIN
Внешний IP: ${CURRENT_EXTERNAL_IP:-}
Внутренний IP: ${CURRENT_INTERNAL_IP:-}
Email администратора: ${ADMIN_EMAIL:-}

🔗 АДРЕСА ДЛЯ КЛИЕНТА:
SMP:  $SMP_ADDRESS
XFTP: $XFTP_ADDRESS

📞 TURN / STUN:
$STUN_ADDR
$TURN_UDP
$TURN_TLS

⚠️ Если домен менялся, обновите DNS-записи:
  smp.${MAIN_DOMAIN}
  files.${MAIN_DOMAIN}
  turn.${MAIN_DOMAIN}
  info.smp.${MAIN_DOMAIN}

⚠️ Веб-пароль панели управления не сохраняется в этом отчёте автоматически.
   Если .htpasswd не восстанавливался отдельно, пароль может быть неизвестен.
================================================================
EOF

      chmod 600 "$BASE_DIR/CONNECTION_DETAILS.txt"
      success "CONNECTION_DETAILS.txt обновлён."
    fi
  else
    warn "CONNECTION_DETAILS.txt не обновлён, так как fingerprint ещё не готов."
  fi
fi

echo ""
success "Восстановление завершено."

if $SETTINGS_CHANGED; then
  warn "Если вы меняли домен или IP, не забудьте обновить DNS и параметры клиентов."
fi

info "Проверить статус: cd $BASE_DIR && ${COMPOSE[*]} ps"