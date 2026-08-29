#!/bin/bash
# ==============================================================================
# SimpleX Chat Server Suite — GitHub bootstrap / menu
# Версия: 0.3
# ==============================================================================
set -u

VERSION="0.3"
LANG_EN=false
ACTION="${1:-menu}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat <<EOF
Использование:
  sudo bash $0 [команда]

Команды:
  menu           интерактивное меню (по умолчанию)
  install        новая установка
  reinstall      переустановка с сохранённой конфигурацией
  restore        восстановление из бэкапа
  passnew        смена пароля веб-панели
  backup         создать обычную резервную копию
  secure-backup  создать зашифрованный бэкап в /volumeN/docker/simp_bkp
  status         статус контейнеров
  logs           последние логи контейнеров
  update         обновить status.json / connection.js
  uninstall      полностью удалить SimpleX с сервера
  help           эта справка

Примеры:
  sudo bash $0
  sudo bash $0 install
  sudo bash $0 restore
  sudo bash $0 passnew admin2
  sudo bash $0 secure-backup
  sudo bash $0 uninstall
EOF
}

if [ "$ACTION" = "help" ] || [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
    usage
    exit 0
fi

# === ВЫБОР ЯЗЫКА / LANGUAGE SELECTION ===
LANG_CHOICE="${LANG_CHOICE:-}"
if [ -z "$LANG_CHOICE" ]; then
    if [ -e /dev/tty ]; then
        echo "" >&2
        echo "Выберите язык / Select language:" >&2
        echo "  1) Русский" >&2
        echo "  2) English" >&2
        echo "" >&2
        read -p "Ваш выбор / Your choice [1]: " LANG_CHOICE </dev/tty || true
    fi
    LANG_CHOICE="${LANG_CHOICE:-1}"
fi

if [ "$LANG_CHOICE" = "2" ]; then
    LANG_EN=true
else
    LANG_EN=false
fi

# URL репозитория. Можно переопределить через переменную окружения:
# sudo SIMPLEX_REPO_RAW="https://raw.githubusercontent.com/user/repo/main" bash simplex.sh
SIMPLEX_REPO_RAW="${SIMPLEX_REPO_RAW:-https://raw.githubusercontent.com/ceshbox-code/simplex-synology-installer/main}"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

BASE_DIR=""
TMP_DIR=""
RESOLVED_PATH=""
LAST_ENCRYPTED_BACKUP_PATH=""

info() {
    if [ "${LANG_EN:-false}" = true ]; then
        echo -e "${BLUE}[INFO]${NC} ${2:-$1}" >&2
    else
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

success() {
    if [ "${LANG_EN:-false}" = true ]; then
        echo -e "${GREEN}[ OK ]${NC} ${2:-$1}" >&2
    else
        echo -e "${GREEN}[ OK ]${NC} $1" >&2
    fi
}

warn() {
    if [ "${LANG_EN:-false}" = true ]; then
        echo -e "${YELLOW}[WARN]${NC} ${2:-$1}" >&2
    else
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    fi
}

error() {
    if [ "${LANG_EN:-false}" = true ]; then
        echo -e "${RED}[ERR ]${NC} ${2:-$1}" >&2
    else
        echo -e "${RED}[ERR ]${NC} $1" >&2
    fi
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Скрипт требует прав суперпользователя. Выполните: sudo bash $0 $*" \
              "Script requires superuser privileges. Run: sudo bash $0 $*"
    fi
}

require_tty() {
    [ -e /dev/tty ] || error "Интерактивное меню требует полноценный терминал." \
                             "Interactive menu requires a full terminal."
}

require_curl() {
    command -v curl >/dev/null 2>&1 || error "curl не найден." "curl not found."
}

detect_base_dir() {
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/.env" ]; then
        printf '%s\n' "$SCRIPT_DIR"
        return 0
    fi

    local found=()
    local v

    for v in /volume*; do
        if [ -f "$v/docker/simplex/.env" ]; then
            found+=("$v/docker/simplex")
        fi
    done

    if [ "${#found[@]}" -eq 1 ]; then
        printf '%s\n' "${found[0]}"
        return 0
    fi

    if [ "${#found[@]}" -gt 1 ]; then
        if [ -e /dev/tty ]; then
            local i=1
            local p
            local choice=""

            info "Найдено несколько конфигураций SimpleX:" \
                 "Multiple SimpleX configurations found:"

            for p in "${found[@]}"; do
                echo "  $i) $p" >&2
                i=$((i + 1))
            done

            read -p "Выберите конфигурацию / Select configuration [1]: " choice </dev/tty || true
            choice="${choice:-1}"

            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#found[@]}" ]; then
                printf '%s\n' "${found[$((choice - 1))]}"
                return 0
            fi
        fi

        return 1
    fi

    return 1
}

init_tmp() {
    if [ -z "$TMP_DIR" ]; then
        TMP_DIR="$(mktemp -d)" || return 1
        trap 'rm -rf "$TMP_DIR"' EXIT
    fi
}

fetch_remote_script() {
    local name="$1"
    local url
    local dest

    require_curl
    init_tmp || return 1

    url="$SIMPLEX_REPO_RAW/$name"
    dest="$TMP_DIR/$name"

    info "Загрузка: $url" "Downloading: $url"

    if ! curl -fsSL --max-time 30 "$url" -o "$dest"; then
        warn "Не удалось загрузить $name" "Failed to download $name"
        return 1
    fi

    # Дополнительная защита от CRLF.
    tr -d '\r' < "$dest" > "$dest.lf"
    mv "$dest.lf" "$dest"

    if ! bash -n "$dest"; then
        warn "Синтаксическая ошибка в загруженном $name" "Syntax error in downloaded $name"
        return 1
    fi

    chmod 700 "$dest"
    RESOLVED_PATH="$dest"
}

resolve_or_fetch() {
    local name="$1"
    RESOLVED_PATH=""

    # Приоритет: локальная установка.
    if [ -n "$BASE_DIR" ] && [ -f "$BASE_DIR/$name" ]; then
        RESOLVED_PATH="$BASE_DIR/$name"
        return 0
    fi

    # Если репозиторий клонирован целиком.
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$name" ]; then
        RESOLVED_PATH="$SCRIPT_DIR/$name"
        return 0
    fi

    # Иначе скачиваем из интернета.
    fetch_remote_script "$name"
}

run_install() {
    local mode="$1"

    if ! resolve_or_fetch "install.sh"; then
        warn "Не удалось получить install.sh" "Failed to get install.sh"
        return 1
    fi

    if [ "$mode" = "new" ]; then
        env REINSTALL_CHOICE_OVERRIDE=2 bash "$RESOLVED_PATH"
    else
        env REINSTALL_CHOICE_OVERRIDE=1 bash "$RESOLVED_PATH"
    fi
}

run_restore() {
    if ! resolve_or_fetch "restore.sh"; then
        warn "Не удалось получить restore.sh" "Failed to get restore.sh"
        return 1
    fi

    bash "$RESOLVED_PATH"
}

run_passnew() {
    if ! resolve_or_fetch "passnew.sh"; then
        warn "Не удалось получить passnew.sh" "Failed to get passnew.sh"
        return 1
    fi

    bash "$RESOLVED_PATH" "$@"
}

run_local_script() {
    local name="$1"

    if [ -n "$BASE_DIR" ] && [ -f "$BASE_DIR/$name" ]; then
        bash "$BASE_DIR/$name"
    else
        warn "$name не найден в локальной установке. Сначала выполните установку/переустановку." \
             "$name not found in local installation. Run install/reinstall first."
        return 1
    fi
}

show_status() {
    if ! command -v docker >/dev/null 2>&1; then
        warn "Docker не найден." "Docker not found."
        return 1
    fi

    info "BASE_DIR: ${BASE_DIR:-не определён / not detected}"

    if ! docker ps \
        --filter name=simplex-smp \
        --filter name=simplex-xftp \
        --filter name=simplex-turn \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'; then
        warn "Не удалось получить статус контейнеров." "Failed to get container status."
        return 1
    fi
}

show_logs() {
    if ! command -v docker >/dev/null 2>&1; then
        warn "Docker не найден." "Docker not found."
        return 1
    fi

    local c

    for c in simplex-smp simplex-xftp simplex-turn; do
        echo ""
        info "Логи $c (последние 100 строк):" "Logs of $c (last 100 lines):"
        docker logs --tail 100 "$c" 2>&1 || true
    done
}

# ==============================================================================
# ENCRYPTED BACKUP — зашифрованный бэкап в /volumeN/docker/simp_bkp
# ==============================================================================

# ==============================================================================
# OPENSSL ENCRYPTION COMPATIBILITY
# ==============================================================================
ALL_ENC_MODES=(pbkdf2_salt pbkdf2 sha256_salt sha256 sha1_salt sha1 md5_salt md5)
ENC_ARGS=()
OPENSSL_ENC_MODE=""
LAST_ENC_MODE=""

set_enc_args() {
    local mode="$1"

    case "$mode" in
        pbkdf2_salt) ENC_ARGS=(-pbkdf2 -iter 200000 -salt) ;;
        pbkdf2)      ENC_ARGS=(-pbkdf2 -iter 200000) ;;
        sha256_salt) ENC_ARGS=(-md sha256 -salt) ;;
        sha256)      ENC_ARGS=(-md sha256) ;;
        sha1_salt)   ENC_ARGS=(-md sha1 -salt) ;;
        sha1)        ENC_ARGS=(-md sha1) ;;
        md5_salt)    ENC_ARGS=(-md md5 -salt) ;;
        md5)         ENC_ARGS=(-md md5) ;;
        *)           ENC_ARGS=(-md sha1) ;;
    esac
}

detect_openssl_enc_mode() {
    local mode
    OPENSSL_ENC_MODE=""

    for mode in "${ALL_ENC_MODES[@]}"; do
        set_enc_args "$mode"

        if printf 'simplex-enc-test\n' | openssl enc -aes-256-cbc -e -pass stdin -in /dev/null -out /dev/null "${ENC_ARGS[@]}" >/dev/null 2>&1; then
            OPENSSL_ENC_MODE="$mode"
            return 0
        fi
    done

    return 1
}

verify_encrypted_archive() {
    local file="$1"
    local pass="$2"
    local mode

    LAST_ENC_MODE=""

    for mode in "${ALL_ENC_MODES[@]}"; do
        set_enc_args "$mode"

        if ( set -o pipefail; printf '%s\n' "$pass" | openssl enc -d -aes-256-cbc "${ENC_ARGS[@]}" -in "$file" -pass stdin | tar -t -z -f - ) >/dev/null 2>&1; then
            LAST_ENC_MODE="$mode"
            return 0
        fi
    done

    return 1
}

create_encrypted_backup() {
    local prefix="${1:-secure}"

    case "$prefix" in
        secure|uninstall) : ;;
        *) prefix="secure" ;;
    esac

    if ! command -v openssl >/dev/null 2>&1; then
        warn "openssl не найден." "openssl not found."
        return 1
    fi

    if [ -z "${BASE_DIR:-}" ] || [ ! -f "$BASE_DIR/.env" ]; then
        warn "BASE_DIR не определён или отсутствует .env." \
             "BASE_DIR is not detected or .env is missing."
        return 1
    fi

    if [ ! -x "$BASE_DIR/simplex-backup.sh" ]; then
        warn "simplex-backup.sh не найден или не исполняем в $BASE_DIR" \
             "simplex-backup.sh not found or not executable in $BASE_DIR"
        return 1
    fi

    local volume_root=""
    local default_safe_dir=""
    local SAFE_BKP_DIR=""
    local input=""

    if [[ "$BASE_DIR" =~ ^(/volume[0-9]+) ]]; then
        volume_root="${BASH_REMATCH[1]}"
    fi

    if [ -n "$volume_root" ]; then
        default_safe_dir="$volume_root/docker/simp_bkp"
    else
        default_safe_dir="/volume1/docker/simp_bkp"
    fi

    SAFE_BKP_DIR="${SIMPLEX_SAFE_BACKUP_DIR:-$default_safe_dir}"

    if [ -e /dev/tty ]; then
        read -p "$( [ "${LANG_EN:-false}" = true ] && echo "Encrypted backup directory" || echo "Папка для зашифрованного бэкапа" ) [$SAFE_BKP_DIR]: " input </dev/tty || true
        input="$(printf '%s' "$input" | tr -d '\r')"

        if [ -n "$input" ]; then
            case "$input" in
                /*)
                    SAFE_BKP_DIR="$input"
                    ;;
                *)
                    warn "Путь должен быть абсолютным и начинаться с /. Используется: $default_safe_dir" \
                         "Path must be absolute and start with /. Using: $default_safe_dir"
                    SAFE_BKP_DIR="$default_safe_dir"
                    ;;
            esac
        fi
    fi

    # Нельзя хранить зашифрованный бэкап внутри BASE_DIR,
    # потому что при удалении BASE_DIR будет удалён и бэкап.
    case "${SAFE_BKP_DIR%/}/" in
        "${BASE_DIR%/}/"*)
            warn "Папка $SAFE_BKP_DIR находится внутри BASE_DIR и будет удалена. Используется $default_safe_dir" \
                 "Folder $SAFE_BKP_DIR is inside BASE_DIR and will be deleted. Using $default_safe_dir"
            SAFE_BKP_DIR="$default_safe_dir"
            ;;
    esac

    mkdir -p "$SAFE_BKP_DIR" || {
        warn "Не удалось создать папку $SAFE_BKP_DIR" \
             "Failed to create $SAFE_BKP_DIR"
        return 1
    }

    chmod 700 "$SAFE_BKP_DIR" 2>/dev/null || true

    if ! detect_openssl_enc_mode; then
        warn "Не удалось подобрать совместимый режим шифрования для текущего openssl." \
             "Could not find a compatible encryption mode for this openssl."
        return 1
    fi

    info "Метод шифрования: $OPENSSL_ENC_MODE" \
         "Encryption mode: $OPENSSL_ENC_MODE"

    local date_str
    local plain_out
    local enc_out
    local bk_log
    local bk_pass

    date_str=$(date +%Y%m%d_%H%M%S)
    enc_out="$SAFE_BKP_DIR/simplex-${prefix}-backup-$date_str.tar.gz.enc"

    info "Создание обычного бэкапа перед шифрованием..." \
         "Creating normal backup before encryption..."

    bk_log=$(bash "$BASE_DIR/simplex-backup.sh" 2>&1) || {
        warn "$bk_log"
        return 1
    }

    plain_out=$(printf '%s\n' "$bk_log" | sed -n 's/^Backup created: //p' | tail -n 1)

    if [ -z "$plain_out" ] || [ ! -f "$plain_out" ]; then
        warn "Не удалось определить созданный файл бэкапа." \
             "Could not determine the created backup file."
        return 1
    fi

    bk_pass=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
    if [ "${#bk_pass}" -lt 24 ]; then
        bk_pass="${bk_pass}$(openssl rand -hex 8)"
        bk_pass="${bk_pass:0:32}"
    fi

    set_enc_args "$OPENSSL_ENC_MODE"

    if ! printf '%s\n' "$bk_pass" | openssl enc -aes-256-cbc -e "${ENC_ARGS[@]}" \
        -in "$plain_out" \
        -out "$enc_out" \
        -pass stdin; then
        rm -f "$enc_out"
        warn "Ошибка шифрования." "Encryption failed."
        return 1
    fi

    if ! verify_encrypted_archive "$enc_out" "$bk_pass"; then
        rm -f "$enc_out"
        warn "Проверка зашифрованного архива завершилась ошибкой." \
             "Encrypted archive verification failed."
        return 1
    fi

    chmod 600 "$enc_out" 2>/dev/null || true
    rm -f "$plain_out"

    LAST_ENCRYPTED_BACKUP_PATH="$enc_out"

    echo ""
    echo "================================================================"
    if [ "${LANG_EN:-false}" = true ]; then
        echo "  ENCRYPTED BACKUP CREATED"
        echo "================================================================"
        echo "File:     $enc_out"
        echo "Mode:     $OPENSSL_ENC_MODE"
        echo "Password: $bk_pass"
        echo "================================================================"
        warn "This password is shown ONLY ONCE and is NOT stored anywhere."
        warn "If you lose it, the archive cannot be restored."
    else
        echo "  СОЗДАН ЗАШИФРОВАННЫЙ БЭКАП"
        echo "================================================================"
        echo "Файл:     $enc_out"
        echo "Метод:    $OPENSSL_ENC_MODE"
        echo "Пароль:   $bk_pass"
        echo "================================================================"
        warn "Пароль показывается ТОЛЬКО ОДИН РАЗ и нигде не сохраняется."
        warn "Если вы его потеряете, восстановить архив будет невозможно."
    fi
    echo ""

    return 0
}

# ==============================================================================
# UNINSTALL — полное удаление SimpleX с сервера
# ==============================================================================
uninstall_safety_check() {
    local path="$1"
    local label="$2"

    if [ -z "$path" ]; then
        if [ "${LANG_EN:-false}" = true ]; then
            warn "Refused: $label is empty."
        else
            warn "Отказано: $label пуст."
        fi
        return 1
    fi

    # Убираем завершающие слэши
    while [ "${path%/}" != "$path" ]; do
        path="${path%/}"
    done

    local re_root='^/$'
    local re_volume_root='^/volume[0-9]+$'
    local re_volume_parent='^/volume[0-9]+/(docker|web)$'
    local re_system='^/(etc|root|home|var|usr|opt|boot|dev|proc|sys|lib|lib64|bin|sbin|run|tmp)$'

    if [[ "$path" =~ $re_root ]] ||
       [[ "$path" =~ $re_volume_root ]] ||
       [[ "$path" =~ $re_volume_parent ]] ||
       [[ "$path" =~ $re_system ]]; then
        if [ "${LANG_EN:-false}" = true ]; then
            warn "Refused: '$path' is a system or parent directory and cannot be removed."
        else
            warn "Отказано: '$path' является системной или родительской директорией и не может быть удалён."
        fi
        return 1
    fi

    # Путь должен быть похож на установку SimpleX
    case "$path" in
        *simplex*) : ;;
        *)
            if [ "${LANG_EN:-false}" = true ]; then
                warn "Refused: '$path' does not look like a SimpleX installation."
            else
                warn "Отказано: '$path' не похож на установку SimpleX."
            fi
            return 1
            ;;
    esac

    # Минимальная вложенность:
    # /volume3/docker/simplex = 3 уровня
    # /volume2/web/simplex    = 3 уровня
    local depth
    depth=$(printf '%s' "$path" | awk -F'/' '{print NF-1}')

    if [ "${depth:-0}" -lt 3 ]; then
        if [ "${LANG_EN:-false}" = true ]; then
            warn "Refused: '$path' has too few path components."
        else
            warn "Отказано: '$path' имеет слишком малую вложенность."
        fi
        return 1
    fi

    if [ ! -e "$path" ]; then
        if [ "${LANG_EN:-false}" = true ]; then
            warn "Path '$path' does not exist."
        else
            warn "Путь '$path' не существует."
        fi
        return 1
    fi

    return 0
}

run_uninstall() {
    require_root
    require_tty

    if [ -z "${BASE_DIR:-}" ]; then
        BASE_DIR="$(detect_base_dir || true)"
    fi

    if [ -z "$BASE_DIR" ] || [ ! -f "$BASE_DIR/.env" ]; then
        error "Не найдена установленная конфигурация SimpleX (.env). Удалять нечего." \
              "No installed SimpleX configuration (.env) found. Nothing to remove."
    fi

    # shellcheck disable=SC1090
    source "$BASE_DIR/.env"

    WEB_DIR="${WEB_DIR:-}"
    WEB_DIR="${WEB_DIR%/}"
    BASE_DIR="${BASE_DIR%/}"
    MAIN_DOMAIN="${MAIN_DOMAIN:-}"

    if [ -z "$MAIN_DOMAIN" ]; then
        error "В .env не найден MAIN_DOMAIN." "MAIN_DOMAIN not found in .env."
    fi

    echo ""
    echo "=========================================="
    echo "  ⚠️  ПОЛНОЕ УДАЛЕНИЕ SIMPLEX  ⚠️"
    echo "=========================================="
    echo ""
    info "BASE_DIR: $BASE_DIR"
    info "WEB_DIR:  $WEB_DIR"
    echo ""

    if [ "${LANG_EN:-false}" = true ]; then
        echo "Uninstall mode:"
        echo "  1) Create an ENCRYPTED backup in /docker/simp_bkp, then uninstall (RECOMMENDED)"
        echo "  2) Uninstall WITHOUT backup (dangerous, all data will be lost)"
        echo "  0) Cancel"
    else
        echo "Режим удаления:"
        echo "  1) Создать ЗАШИФРОВАННЫЙ бэкап в /docker/simp_bkp, потом удалить (РЕКОМЕНДУЕТСЯ)"
        echo "  2) Удалить БЕЗ резервной копии (опасно, все данные будут потеряны)"
        echo "  0) Отмена"
    fi
    echo ""

    local UN_MODE=""
    read -p "$( [ "${LANG_EN:-false}" = true ] && echo 'Your choice [1]: ' || echo 'Ваш выбор [1]: ' )" UN_MODE </dev/tty || true
    UN_MODE="${UN_MODE:-1}"

    case "$UN_MODE" in
        0)
            info "Удаление отменено." "Uninstall cancelled."
            return 0
            ;;
        1) : ;;
        2) : ;;
        *)
            warn "Некорректный выбор." "Invalid choice."
            return 1
            ;;
    esac

    # =========================================================================
    # РЕЖИМ 1: ЗАШИФРОВАННЫЙ БЭКАП ПЕРЕД УДАЛЕНИЕМ
    # =========================================================================
    if [ "$UN_MODE" = "1" ]; then
        if create_encrypted_backup uninstall; then
            echo ""
            read -p "$( [ "${LANG_EN:-false}" = true ] && echo 'I saved the password. Continue uninstall? (y/N): ' || echo 'Я сохранил пароль. Продолжить удаление? (y/N): ' )" CONF_AFTER_BKP </dev/tty || true

            if [[ ! "$CONF_AFTER_BKP" =~ ^[Yy]$ ]]; then
                info "Удаление отменено пользователем." "Uninstall cancelled by user."
                return 0
            fi
        else
            echo ""
            read -p "$( [ "${LANG_EN:-false}" = true ] && echo 'Encrypted backup failed. Continue WITHOUT backup? Type YES to confirm: ' || echo 'Зашифрованный бэкап не создан. Продолжить БЕЗ бэкапа? Введите YES: ' )" CONF_NO_BACKUP </dev/tty || true

            if [ "$CONF_NO_BACKUP" != "YES" ]; then
                info "Удаление отменено." "Uninstall cancelled."
                return 0
            fi
        fi
    fi

    # =========================================================================
    # ТРОЙНОЕ ПОДТВЕРЖДЕНИЕ
    # =========================================================================
    echo ""
    echo "----------------------------------------------------------------"
    if [ "${LANG_EN:-false}" = true ]; then
        echo "WARNING: This operation is IRREVERSIBLE."
        echo "The following will be PERMANENTLY DELETED:"
        echo "  • Containers: simplex-smp, simplex-xftp, simplex-turn"
        echo "  • All SMP/XFTP data, certificates, fingerprints"
        echo "  • .env (all passwords and secrets)"
        echo "  • Web panel files in $WEB_DIR"
        echo "  • Cron jobs for backup and status"
        echo "  • Directory: $BASE_DIR"
    else
        echo "ВНИМАНИЕ: эта операция НЕОБРАТИМА."
        echo "Будут БЕЗВОЗВРАТНО УДАЛЕНЫ:"
        echo "  • Контейнеры: simplex-smp, simplex-xftp, simplex-turn"
        echo "  • Все данные SMP/XFTP, сертификаты, отпечатки"
        echo "  • .env (все пароли и секреты)"
        echo "  • Файлы веб-панели в $WEB_DIR"
        echo "  • Cron-задачи бэкапа и статуса"
        echo "  • Директория: $BASE_DIR"
    fi
    echo "----------------------------------------------------------------"
    echo ""

    local CONF1=""
    read -p "$( [ "${LANG_EN:-false}" = true ] && echo 'Are you sure you want to continue? (y/N): ' || echo 'Вы уверены, что хотите продолжить? (y/N): ' )" CONF1 </dev/tty || true

    if [[ ! "$CONF1" =~ ^[Yy]$ ]]; then
        info "Удаление отменено." "Uninstall cancelled."
        return 0
    fi

    echo ""
    local CONF_DOMAIN=""
    if [ "${LANG_EN:-false}" = true ]; then
        read -p "Type the main domain to confirm ($MAIN_DOMAIN): " CONF_DOMAIN </dev/tty || true
    else
        read -p "Введите основной домен для подтверждения ($MAIN_DOMAIN): " CONF_DOMAIN </dev/tty || true
    fi

    if [ "$CONF_DOMAIN" != "$MAIN_DOMAIN" ]; then
        warn "Домен не совпадает. Удаление отменено." \
             "Domain does not match. Uninstall cancelled."
        return 0
    fi

    echo ""
    local CONF_DELETE=""
    read -p "$( [ "${LANG_EN:-false}" = true ] && echo 'Type DELETE in uppercase to confirm: ' || echo 'Введите DELETE заглавными буквами для подтверждения: ' )" CONF_DELETE </dev/tty || true

    if [ "$CONF_DELETE" != "DELETE" ]; then
        warn "Кодовое слово не совпадает. Удаление отменено." \
             "Confirmation word does not match. Uninstall cancelled."
        return 0
    fi

    # =========================================================================
    # ОТЧЁТ ОБ УДАЛЕНИИ
    # =========================================================================
    local UNINSTALL_LOG="/tmp/simplex-uninstall-$(date +%Y%m%d_%H%M%S).log"

    {
        echo "SIMPLEX UNINSTALL LOG"
        echo "====================="
        echo "Date:        $(date)"
        echo "Mode:        $([ "$UN_MODE" = "1" ] && echo "with encrypted backup" || echo "without backup")"
        echo "BASE_DIR:    $BASE_DIR"
        echo "WEB_DIR:     $WEB_DIR"
        echo "MAIN_DOMAIN: $MAIN_DOMAIN"
        echo ""
        echo "Removed items:"
    } > "$UNINSTALL_LOG"

    # =========================================================================
    # ШАГ 1. ОСТАНОВКА И УДАЛЕНИЕ КОНТЕЙНЕРОВ
    # =========================================================================
    info "Остановка и удаление контейнеров..." "Stopping and removing containers..."

    if command -v docker >/dev/null 2>&1; then
        local svc
        for svc in simplex-smp simplex-xftp simplex-turn; do
            if docker inspect "$svc" >/dev/null 2>&1; then
                docker stop "$svc" >/dev/null 2>&1 || true
                docker rm -f "$svc" >/dev/null 2>&1 || true
                echo "  - container: $svc" >> "$UNINSTALL_LOG"
                success "$svc удалён." "$svc removed."
            fi
        done

        local net
        for net in $(docker network ls --format '{{.Name}}' 2>/dev/null | grep -E '^simplex(_|-)' || true); do
            docker network rm "$net" >/dev/null 2>&1 || true
            echo "  - network: $net" >> "$UNINSTALL_LOG"
        done
    else
        warn "Docker не найден. Пропуск удаления контейнеров." \
             "Docker not found. Skipping container removal."
    fi

    # =========================================================================
    # ШАГ 2. УДАЛЕНИЕ CRON-ЗАДАЧ
    # =========================================================================
    info "Удаление cron-задач..." "Removing cron jobs..."

    if [ -f /etc/crontab ]; then
        local CRON_BACKUP="/tmp/crontab.before-simplex-uninstall.$(date +%s)"
        cp /etc/crontab "$CRON_BACKUP" 2>/dev/null || true

        local REMOVED_CRON=0

        if grep -q "simplex-backup\.sh" /etc/crontab 2>/dev/null; then
            sed -i "/simplex-backup\.sh/d" /etc/crontab
            REMOVED_CRON=$((REMOVED_CRON + 1))
        fi

        if grep -q "status-update\.sh" /etc/crontab 2>/dev/null; then
            sed -i "/status-update\.sh/d" /etc/crontab
            REMOVED_CRON=$((REMOVED_CRON + 1))
        fi

        if [ "$REMOVED_CRON" -gt 0 ]; then
            echo "  - cron entries removed: $REMOVED_CRON" >> "$UNINSTALL_LOG"
            synoservicectl --restart crond >/dev/null 2>&1 || true
            success "Cron-задачи SimpleX удалены (бэкап: $CRON_BACKUP)." \
                    "SimpleX cron entries removed (backup: $CRON_BACKUP)."
        else
            info "Cron-задачи SimpleX не найдены." "No SimpleX cron entries found."
        fi
    fi

    # =========================================================================
    # ШАГ 3. УДАЛЕНИЕ WEB_DIR
    # =========================================================================
    info "Удаление веб-файлов из $WEB_DIR ..." "Removing web files from $WEB_DIR ..."

    if [ -n "$WEB_DIR" ] && uninstall_safety_check "$WEB_DIR" "WEB_DIR"; then
        local WEB_REMOVED=0
        local wf

        for wf in qrsmp.html index.html connection.js status.json \
                  .htaccess .htpasswd qrcode.min.js favicon.ico; do
            if [ -f "$WEB_DIR/$wf" ]; then
                rm -f "$WEB_DIR/$wf"
                echo "  - web file: $WEB_DIR/$wf" >> "$UNINSTALL_LOG"
                WEB_REMOVED=$((WEB_REMOVED + 1))
            fi
        done

        if [ -d "$WEB_DIR" ] && [ -z "$(ls -A "$WEB_DIR" 2>/dev/null)" ]; then
            rmdir "$WEB_DIR" 2>/dev/null && \
                echo "  - empty web dir removed: $WEB_DIR" >> "$UNINSTALL_LOG"
        else
            warn "WEB_DIR $WEB_DIR не пуст после удаления файлов SimpleX — оставшиеся файлы не затронуты." \
                 "WEB_DIR $WEB_DIR is not empty after removing SimpleX files — remaining files untouched."
            echo "  - WEB_DIR not empty, left intact: $WEB_DIR" >> "$UNINSTALL_LOG"
        fi

        if [ "$WEB_REMOVED" -gt 0 ]; then
            success "Удалено веб-файлов: $WEB_REMOVED" "Web files removed: $WEB_REMOVED"
        else
            info "Веб-файлы SimpleX не найдены в $WEB_DIR." \
                 "No SimpleX web files found in $WEB_DIR."
        fi
    else
        warn "WEB_DIR пропущен (небезопасный путь или отсутствует)." \
             "WEB_DIR skipped (unsafe path or missing)."
        echo "  - WEB_DIR skipped: $WEB_DIR" >> "$UNINSTALL_LOG"
    fi

    # =========================================================================
    # ШАГ 4. УДАЛЕНИЕ BASE_DIR
    # =========================================================================
    info "Удаление директории $BASE_DIR ..." "Removing directory $BASE_DIR ..."

    if uninstall_safety_check "$BASE_DIR" "BASE_DIR"; then
        rm -rf "$BASE_DIR"
        echo "  - BASE_DIR removed: $BASE_DIR" >> "$UNINSTALL_LOG"
        success "BASE_DIR удалён." "BASE_DIR removed."
    else
        error "Отказано в удалении BASE_DIR (проверка безопасности не пройдена)." \
              "Refused to remove BASE_DIR (safety check failed)."
    fi

    # =========================================================================
    # ИТОГ
    # =========================================================================
    echo ""
    echo "================================================================"
    if [ "${LANG_EN:-false}" = true ]; then
        echo "SimpleX has been COMPLETELY REMOVED from this server."
    else
        echo "SimpleX ПОЛНОСТЬЮ УДАЛЁН с этого сервера."
    fi
    echo "================================================================"
    echo ""

    if [ "$UN_MODE" = "1" ] && [ -n "$LAST_ENCRYPTED_BACKUP_PATH" ]; then
        if [ "${LANG_EN:-false}" = true ]; then
            echo "Encrypted backup saved:"
            echo "  $LAST_ENCRYPTED_BACKUP_PATH"
            echo ""
            warn "The archive password was shown only once."
        else
            echo "Зашифрованный бэкап сохранён:"
            echo "  $LAST_ENCRYPTED_BACKUP_PATH"
            echo ""
            warn "Пароль от архива был показан только один раз."
        fi
        echo ""
    fi

    if [ "${LANG_EN:-false}" = true ]; then
        echo "Manual follow-up steps:"
    else
        echo "Что осталось сделать вручную:"
    fi

    echo "  • Web Station: remove virtual host info.smp.$MAIN_DOMAIN"
    echo "  • DNS: remove A records smp/files/turn/info.smp.$MAIN_DOMAIN"
    echo "  • Router: close forwarded ports 5223, 5224, 7788, 3478, 5349"
    echo "  • Let's Encrypt: revoke certificates for SimpleX domains"
    echo ""
    echo "Uninstall log: $UNINSTALL_LOG"
    echo ""
}

show_menu() {
    require_tty

    local choice=""

    while true; do
        echo ""
        echo "=========================================="
        echo "  SIMPLEX CHAT SERVER SUITE v$VERSION"
        echo "=========================================="
        echo "  1) Новая установка"
        echo "  2) Переустановка с сохранённой конфигурацией"
        echo "  3) Восстановление из бэкапа"
        echo "  4) Смена пароля веб-панели"
        echo "  5) Создать обычную резервную копию"
        echo "  6) Статус контейнеров"
        echo "  7) Логи контейнеров"
        echo "  8) Обновить status.json / connection.js"
        echo "  9) Полностью удалить SimpleX с сервера"
        echo " 10) Создать зашифрованный бэкап"
        echo "  0) Выход"
        echo ""

        read -p "Ваш выбор [1]: " choice </dev/tty || true
        choice="${choice:-1}"

        case "$choice" in
            1) run_install new || warn "install.sh завершился с ошибкой." ;;
            2) run_install reinstall || warn "install.sh завершился с ошибкой." ;;
            3) run_restore || warn "restore.sh завершился с ошибкой." ;;
            4) run_passnew || warn "passnew.sh завершился с ошибкой." ;;
            5) run_local_script simplex-backup.sh || warn "Не удалось создать резервную копию." ;;
            6) show_status || warn "Не удалось показать статус." ;;
            7) show_logs || warn "Не удалось показать логи." ;;
            8) run_local_script status-update.sh || warn "status-update.sh завершился с ошибкой." ;;
            9) run_uninstall || warn "Удаление завершилось с ошибкой или было отменено." ;;
            10) create_encrypted_backup secure || warn "Не удалось создать зашифрованный бэкап." ;;
            0) break ;;
            *) warn "Некорректный выбор." ;;
        esac
    done
}

case "$ACTION" in
    menu)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        show_menu
        ;;
    install)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        run_install new || exit 1
        ;;
    reinstall)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        run_install reinstall || exit 1
        ;;
    restore)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        run_restore || exit 1
        ;;
    passnew)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        shift || true
        run_passnew "$@" || exit 1
        ;;
    backup)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        run_local_script simplex-backup.sh || exit 1
        ;;
    secure-backup)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        create_encrypted_backup secure || exit 1
        ;;
    status)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        show_status || exit 1
        ;;
    logs)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        show_logs
        ;;
    update)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        run_local_script status-update.sh || exit 1
        ;;
    uninstall)
        require_root
        BASE_DIR="$(detect_base_dir || true)"
        run_uninstall || exit 1
        ;;
    *)
        usage
        exit 1
        ;;
esac