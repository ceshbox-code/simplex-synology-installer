#!/bin/bash
# Скрипт для добавления поддержки английского языка в install.sh

FILE="install.sh"

# 1. Добавляем выбор языка в начало скрипта (после shebang и set -e)
# Находим строку с 'set -e' и вставляем после неё блок выбора языка
sed -i '/^set -e$/a\
\
# === ВЫБОР ЯЗЫКА / LANGUAGE SELECTION ===\
echo ""\
echo "Выберите язык / Select language:"\
echo "  1) Русский"\
echo "  2) English"\
echo ""\
read -p "Ваш выбор / Your choice [1]: " LANG_CHOICE < /dev/tty\
LANG_CHOICE=${LANG_CHOICE:-1}\
\
if [ "$LANG_CHOICE" = "2" ]; then\
    LANG_EN=true\
else\
    LANG_EN=false\
fi\
\
# Функция для двуязычного вывода\
# Использование: msg "Русский текст" "English text"\
msg() {\
    if [ "$LANG_EN" = true ]; then\
        echo "$2"\
    else\
        echo "$1"\
    fi\
}\
\
# Переопределяем функции вывода для двуязычности\
# Мы не можем легко переопределить info/warn/error без изменения всех вызовов,\
# поэтому просто сделаем все строки двуязычными через sed ниже.\
' "$FILE"

# 2. Заменяем ключевые сообщения на двуязычные
# Используем | как разделитель, чтобы избежать проблем с /
sed -i \
-e 's|error "Скрипт требует прав суперпользователя. Выполните: sudo /bin/bash $0"|error "Скрипт требует прав суперпользователя. Выполните: sudo /bin/bash $0 / Script requires superuser privileges. Run: sudo /bin/bash $0"|' \
-e 's|error "openssl не найден."|error "openssl не найден. / openssl not found."|' \
-e 's|error "curl не найден."|error "curl не найден. / curl not found."|' \
-e 's|error "Docker не установлен. Установите через Package Center."|error "Docker не установлен. Установите через Package Center. / Docker not installed. Install via Package Center."|' \
-e 's|error "ip не найден."|error "ip не найден. / ip not found."|' \
-e 's|error "Docker Compose не найден."|error "Docker Compose не найден. / Docker Compose not found."|' \
-e 's|echo "  SIMPLEX CHAT INSTALLER v9.4 — SYNOLOGY"|echo "  SIMPLEX CHAT INSTALLER v9.4 — SYNOLOGY"|' \
-e 's|error "Не найдено ни одного тома с директорией docker (/volume\*/docker)"|error "Не найдено ни одного тома с директорией docker (/volume*/docker) / No volume with docker directory found (/volume*/docker)"|' \
-e 's|echo "Доступные варианты установки:"|echo "Доступные варианты установки: / Available installation options:"|' \
-e 's|read -p "Выберите номер варианта \[1\]: " CHOICE < /dev/tty|read -p "Выберите номер варианта / Select option [1]: " CHOICE < /dev/tty|' \
-e 's|warn "Некорректный выбор. Введите число от 1 до ${#PATHS\[@\]}."|warn "Некорректный выбор. Введите число от 1 до ${#PATHS[@]}. / Invalid choice. Enter a number from 1 to ${#PATHS[@]}."|' \
-e 's|info "Базовая директория: $BASE_DIR"|info "Базовая директория: $BASE_DIR / Base directory: $BASE_DIR"|' \
-e 's|read -p "Введите внешний IP-адрес \[$EXTERNAL_IP\]: " INPUT_EXT_IP < /dev/tty|read -p "Введите внешний IP-адрес / Enter external IP [$EXTERNAL_IP]: " INPUT_EXT_IP < /dev/tty|' \
-e 's|error "Не удалось определить внешний IP."|error "Не удалось определить внешний IP. / Failed to determine external IP."|' \
-e 's|error "Не удалось определить внутренний IP NAS."|error "Не удалось определить внутренний IP NAS. / Failed to determine internal NAS IP."|' \
-e 's|read -p "Введите доменное имя (например, ваш-домен.ru): " MAIN_DOMAIN < /dev/tty|read -p "Введите доменное имя / Enter domain name (e.g., your-domain.com): " MAIN_DOMAIN < /dev/tty|' \
-e 's|warn "Домен не может быть пустым."|warn "Домен не может быть пустым. / Domain cannot be empty."|' \
-e 's|warn "Домен должен содержать точку."|warn "Домен должен содержать точку. / Domain must contain a dot."|' \
-e 's|read -p "Email администратора \[admin@$MAIN_DOMAIN\]: " ADMIN_EMAIL < /dev/tty|read -p "Email администратора / Admin email [admin@$MAIN_DOMAIN]: " ADMIN_EMAIL < /dev/tty|' \
-e 's|info "Обнаружен существующий .env — сохраняем действующие пароли."|info "Обнаружен существующий .env — сохраняем действующие пароли. / Existing .env found — keeping current passwords."|' \
-e 's|info "Проверка DNS-записей..."|info "Проверка DNS-записей... / Checking DNS records..."|' \
-e 's|warn "DNS: ${SUB}.${MAIN_DOMAIN} → ${RESOLVED:-не найдена} (ожидается $EXTERNAL_IP)"|warn "DNS: ${SUB}.${MAIN_DOMAIN} → ${RESOLVED:-не найдена} (ожидается $EXTERNAL_IP) / DNS: ${SUB}.${MAIN_DOMAIN} → ${RESOLVED:-not found} (expected $EXTERNAL_IP)"|' \
-e 's|warn "Утилита dig недоступна. Пропуск проверки DNS."|warn "Утилита dig недоступна. Пропуск проверки DNS. / dig utility not available. Skipping DNS check."|' \
-e 's|info "Подготовка структуры директорий..."|info "Подготовка структуры директорий... / Preparing directory structure..."|' \
-e 's|warn "Обнаружены существующие данные SMP. Они будут сохранены."|warn "Обнаружены существующие данные SMP. Они будут сохранены. / Existing SMP data found. It will be preserved."|' \
-e 's|success "Директории созданы."|success "Директории созданы. / Directories created."|' \
-e 's|success "favicon.ico скопирован из $FAVICON_SOURCE"|success "favicon.ico скопирован из $FAVICON_SOURCE / favicon.ico copied from $FAVICON_SOURCE"|' \
-e 's|info "Загрузка favicon.ico..."|info "Загрузка favicon.ico... / Downloading favicon.ico..."|' \
-e 's|success "favicon.ico загружен."|success "favicon.ico загружен. / favicon.ico downloaded."|' \
-e 's|warn "Не удалось загрузить favicon.ico. Панель будет работать без иконки."|warn "Не удалось загрузить favicon.ico. Панель будет работать без иконки. / Failed to download favicon.ico. Panel will work without icon."|' \
-e 's|success "favicon.ico уже существует в $WEB_DIR"|success "favicon.ico уже существует в $WEB_DIR / favicon.ico already exists in $WEB_DIR"|' \
-e 's|info "Проверка TLS сертификатов SMP..."|info "Проверка TLS сертификатов SMP... / Checking SMP TLS certificates..."|' \
-e 's|success "Новый self-signed сертификат SMP создан."|success "Новый self-signed сертификат SMP создан. / New self-signed SMP certificate created."|' \
-e 's|warn "Существующий сертификат SMP сохранён."|warn "Существующий сертификат SMP сохранён. / Existing SMP certificate preserved."|' \
-e 's|success "TLS сертификаты SMP готовы."|success "TLS сертификаты SMP готовы. / SMP TLS certificates ready."|' \
-e 's|success ".env создан."|success ".env создан. / .env created."|' \
-e 's|info "Создание docker-compose.yml..."|info "Создание docker-compose.yml... / Creating docker-compose.yml..."|' \
-e 's|success "docker-compose.yml создан."|success "docker-compose.yml создан. / docker-compose.yml created."|' \
-e 's|info "Проверка инициализации XFTP сервера..."|info "Проверка инициализации XFTP сервера... / Checking XFTP server initialization..."|' \
-e 's|success "Существующая XFTP identity сохранена: $XFTP_FP_EXISTING"|success "Существующая XFTP identity сохранена: $XFTP_FP_EXISTING / Existing XFTP identity preserved: $XFTP_FP_EXISTING"|' \
-e 's|error "XFTP config существует, но fingerprint отсутствует. Проверьте $BASE_DIR/xftp/config."|error "XFTP config существует, но fingerprint отсутствует. Проверьте $BASE_DIR/xftp/config. / XFTP config exists but fingerprint is missing. Check $BASE_DIR/xftp/config."|' \
-e 's|info "Запуск инициализации XFTP..."|info "Запуск инициализации XFTP... / Starting XFTP initialization..."|' \
-e 's|error "Не удалось запустить XFTP init."|error "Не удалось запустить XFTP init. / Failed to start XFTP init."|' \
-e 's|warn "XFTP fingerprint не появился за 30 секунд. Логи init:"|warn "XFTP fingerprint не появился за 30 секунд. Логи init: / XFTP fingerprint did not appear within 30 seconds. Init logs:"|' \
-e 's|error "Не удалось получить XFTP fingerprint."|error "Не удалось получить XFTP fingerprint. / Failed to obtain XFTP fingerprint."|' \
-e 's|success "XFTP identity создана: $XFTP_FP_INIT"|success "XFTP identity создана: $XFTP_FP_INIT / XFTP identity created: $XFTP_FP_INIT"|' \
-e 's|success "XFTP инициализирован."|success "XFTP инициализирован. / XFTP initialized."|' \
-e 's|info "Загрузка зафиксированных Docker-образов..."|info "Загрузка зафиксированных Docker-образов... / Pulling pinned Docker images..."|' \
-e 's|error "Не удалось загрузить Docker-образы."|error "Не удалось загрузить Docker-образы. / Failed to pull Docker images."|' \
-e 's|info "Запуск сервисов..."|info "Запуск сервисов... / Starting services..."|' \
-e 's|error "Docker Compose не смог запустить сервисы."|error "Docker Compose не смог запустить сервисы. / Docker Compose failed to start services."|' \
-e 's|warn "Логи $svc:"|warn "Логи $svc: / Logs $svc:"|' \
-e 's|error "$svc не запустился."|error "$svc не запустился. / $svc failed to start."|' \
-e 's|success "Все контейнеры запущены."|success "Все контейнеры запущены. / All containers started."|' \
-e 's|info "Ожидание генерации fingerprint (до 120 сек)..."|info "Ожидание генерации fingerprint (до 120 сек)... / Waiting for fingerprint generation (up to 120 sec)..."|' \
-e 's|warn "SMP fingerprint ещё не сгенерирован."|warn "SMP fingerprint ещё не сгенерирован. / SMP fingerprint not yet generated."|' \
-e 's|error "Не удалось получить SMP fingerprint. Установка остановлена."|error "Не удалось получить SMP fingerprint. Установка остановлена. / Failed to obtain SMP fingerprint. Installation stopped."|' \
-e 's|warn "XFTP fingerprint ещё не сгенерирован."|warn "XFTP fingerprint ещё не сгенерирован. / XFTP fingerprint not yet generated."|' \
-e 's|error "Не удалось получить XFTP fingerprint. Установка остановлена."|error "Не удалось получить XFTP fingerprint. Установка остановлена. / Failed to obtain XFTP fingerprint. Installation stopped."|' \
-e 's|success "Fingerprint получены."|success "Fingerprint получены. / Fingerprints obtained."|' \
-e 's|info "Создание скрипта резервного копирования..."|info "Создание скрипта резервного копирования... / Creating backup script..."|' \
-e 's|success "Backup-скрипт создан."|success "Backup-скрипт создан. / Backup script created."|' \
-e 's|info "Создание скрипта обновления статуса..."|info "Создание скрипта обновления статуса... / Creating status update script..."|' \
-e 's|success "Cron-задача статуса добавлена (каждую минуту)."|success "Cron-задача статуса добавлена (каждую минуту). / Status cron added (every minute)."|' \
-e 's|warn "Cron-задача status-update.sh уже существует."|warn "Cron-задача status-update.sh уже существует. / status-update.sh cron already exists."|' \
-e 's|success "Cron-задача backup добавлена (ежедневно в 03:00)."|success "Cron-задача backup добавлена (ежедневно в 03:00). / Backup cron added (daily at 03:00)."|' \
-e 's|warn "Cron-задача simplex-backup.sh уже существует."|warn "Cron-задача simplex-backup.sh уже существует. / simplex-backup.sh cron already exists."|' \
-e 's|success "status-update.sh создан."|success "status-update.sh создан. / status-update.sh created."|' \
-e 's|info "Создание веб-страниц..."|info "Создание веб-страниц... / Creating web pages..."|' \
-e 's|info "Загрузка QRCode.js..."|info "Загрузка QRCode.js... / Downloading QRCode.js..."|' \
-e 's|success "QRCode.js загружен."|success "QRCode.js загружен. / QRCode.js downloaded."|' \
-e 's|error "Не удалось загрузить QRCode.js. Проверьте доступность install.smp.klenovoe.ru"|error "Не удалось загрузить QRCode.js. Проверьте доступность install.smp.klenovoe.ru / Failed to download QRCode.js. Check availability of install.smp.klenovoe.ru"|' \
-e 's|success "index.html создан."|success "index.html создан. / index.html created."|' \
-e 's|success "Версия существующего index.html обновлена до v9.4."|success "Версия существующего index.html обновлена до v9.4. / Existing index.html version updated to v9.4."|' \
-e 's|warn ".htpasswd уже существует. Пароль не изменён."|warn ".htpasswd уже существует. Пароль не изменён. / .htpasswd already exists. Password not changed."|' \
-e 's|success ".htpasswd защищён: root:${WEB_GROUP}, права 640."|success ".htpasswd защищён: root:${WEB_GROUP}, права 640. / .htpasswd protected: root:${WEB_GROUP}, permissions 640."|' \
-e 's|warn "Группа http не найдена. Используется chmod 644 для .htpasswd."|warn "Группа http не найдена. Используется chmod 644 для .htpasswd. / http group not found. Using chmod 644 for .htpasswd."|' \
-e 's|success "Веб-пароль создан: admin / ${WEB_PASS}"|success "Веб-пароль создан: admin / ${WEB_PASS} / Web password created: admin / ${WEB_PASS}"|' \
-e 's|warn "Сохраните этот пароль! Он показывается только один раз."|warn "Сохраните этот пароль! Он показывается только один раз. / Save this password! It is shown only once."|' \
-e 's|success "Веб-файлы созданы в $WEB_DIR"|success "Веб-файлы созданы в $WEB_DIR / Web files created in $WEB_DIR"|' \
-e 's|success "Установка завершена."|success "Установка завершена. / Installation completed."|' \
-e 's|info "Настройте Web Station для доступа к панели управления."|info "Настройте Web Station для доступа к панели управления. / Configure Web Station to access the control panel."|' \
-e 's|🔗 АДРЕСА ДЛЯ КЛИЕНТА:|🔗 АДРЕСА ДЛЯ КЛИЕНТА / ADDRESSES FOR CLIENT:|' \
-e 's|📞 TURN / STUN:|📞 TURN / STUN:|' \
-e 's|🌐 ПАНЕЛЬ УПРАВЛЕНИЯ:|🌐 ПАНЕЛЬ УПРАВЛЕНИЯ / CONTROL PANEL:|' \
-e 's|Логин: admin|Логин / Login: admin|' \
-e 's|Пароль: ${WEB_PASS:-см. существующий .htpasswd}|Пароль / Password: ${WEB_PASS:-см. существующий .htpasswd / see existing .htpasswd}|' \
-e 's|📁 ФАЙЛЫ:|📁 ФАЙЛЫ / FILES:|' \
-e 's|Конфигурация: $BASE_DIR/.env|Конфигурация / Config: $BASE_DIR/.env|' \
-e 's|Веб-страницы: $WEB_DIR/|Веб-страницы / Web pages: $WEB_DIR/|' \
-e 's|⚠️ ДАЛЬНЕЙШИЕ ДЕЙСТВИЯ:|⚠️ ДАЛЬНЕЙШИЕ ДЕЙСТВИЯ / NEXT STEPS:|' \
-e 's|1. Настройте Web Station: корень → $WEB_DIR|1. Настройте Web Station / Configure Web Station: корень / root → $WEB_DIR|' \
-e 's|2. Проброс портов: SMP 5223, 5224, XFTP 7788, TURN 3478, 5349, 49152-65535|2. Проброс портов / Port forwarding: SMP 5223, 5224, XFTP 7788, TURN 3478, 5349, 49152-65535|' \
-e 's|3. DNS A-записи: smp, files, turn → $EXTERNAL_IP|3. DNS A-записи / DNS A records: smp, files, turn → $EXTERNAL_IP|' \
-e 's|4. Откройте порты в Брандмауэре DSM|4. Откройте порты в Брандмауэре DSM / Open ports in DSM Firewall|' \
"$FILE"

if [ $? -eq 0 ]; then
    echo "[OK] Поддержка английского языка добавлена в install.sh"
else
    echo "[ERR] Произошла ошибка при выполнении sed"
fi