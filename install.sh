#!/bin/bash
# ==============================================================================
# SimpleX Chat Server Suite Installer for Synology DSM 7.1+
# Р’РµСЂСЃРёСЏ: 9.4 (С„РёРєСЃ XFTP init)
# ==============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR ]${NC} $1"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    error "РЎРєСЂРёРїС‚ С‚СЂРµР±СѓРµС‚ РїСЂР°РІ СЃСѓРїРµСЂРїРѕР»СЊР·РѕРІР°С‚РµР»СЏ. Р’С‹РїРѕР»РЅРёС‚Рµ: sudo /bin/bash $0"
fi

command -v openssl &>/dev/null || error "openssl РЅРµ РЅР°Р№РґРµРЅ."
command -v curl    &>/dev/null || error "curl РЅРµ РЅР°Р№РґРµРЅ."
command -v docker  &>/dev/null || error "Docker РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ. РЈСЃС‚Р°РЅРѕРІРёС‚Рµ С‡РµСЂРµР· Package Center."
command -v ip      &>/dev/null || error "ip РЅРµ РЅР°Р№РґРµРЅ."

COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    command -v docker-compose &>/dev/null || error "Docker Compose РЅРµ РЅР°Р№РґРµРЅ."
fi

echo ""
echo "=========================================="
echo "  SIMPLEX CHAT INSTALLER v9.4 вЂ” SYNOLOGY"
echo "=========================================="
echo ""

# ==============================================================================
# 1. РЎР‘РћР  Р”РђРќРќР«РҐ + РђР’РўРћРћРџР Р•Р”Р•Р›Р•РќРР• РўРћРњРђ
# ==============================================================================
# === РРќРўР•Р РђРљРўРР’РќР«Р™ Р’Р«Р‘РћР  Р‘РђР—РћР’РћР™ Р”РР Р•РљРўРћР РР ===
DEFAULT_BASE="/volume1/docker/simplex"
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
    error "РќРµ РЅР°Р№РґРµРЅРѕ РЅРё РѕРґРЅРѕРіРѕ С‚РѕРјР° СЃ РґРёСЂРµРєС‚РѕСЂРёРµР№ docker (/volume*/docker)"
fi
echo ""
echo "Р”РѕСЃС‚СѓРїРЅС‹Рµ РІР°СЂРёР°РЅС‚С‹ СѓСЃС‚Р°РЅРѕРІРєРё:"
for opt in "${OPTIONS[@]}"; do echo "  $opt"; done
echo ""
while true; do
    read -p "Р’С‹Р±РµСЂРёС‚Рµ РЅРѕРјРµСЂ РІР°СЂРёР°РЅС‚Р° [1]: " CHOICE < /dev/tty
    CHOICE=${CHOICE:-1}
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#PATHS[@]} ]; then
        BASE_DIR="${PATHS[$((CHOICE - 1))]}"
        break
    else
        warn "РќРµРєРѕСЂСЂРµРєС‚РЅС‹Р№ РІС‹Р±РѕСЂ. Р’РІРµРґРёС‚Рµ С‡РёСЃР»Рѕ РѕС‚ 1 РґРѕ ${#PATHS[@]}."
    fi
done
WEB_DIR="${BASE_DIR}/install/www"
info "Р‘Р°Р·РѕРІР°СЏ РґРёСЂРµРєС‚РѕСЂРёСЏ: $BASE_DIR"

INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
EXTERNAL_IP=$(curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || echo "")

# Р’РћРЎРЎРўРђРќРћР’Р›Р•РќРќР«Р• Р”РРђР›РћР“Р
read -p "Р’РІРµРґРёС‚Рµ РІРЅРµС€РЅРёР№ IP-Р°РґСЂРµСЃ [$EXTERNAL_IP]: " INPUT_EXT_IP < /dev/tty
EXTERNAL_IP=${INPUT_EXT_IP:-$EXTERNAL_IP}
[ -z "$EXTERNAL_IP" ] && error "РќРµ СѓРґР°Р»РѕСЃСЊ РѕРїСЂРµРґРµР»РёС‚СЊ РІРЅРµС€РЅРёР№ IP."
[ -z "$INTERNAL_IP" ] && error "РќРµ СѓРґР°Р»РѕСЃСЊ РѕРїСЂРµРґРµР»РёС‚СЊ РІРЅСѓС‚СЂРµРЅРЅРёР№ IP NAS."

while true; do
    read -p "Р’РІРµРґРёС‚Рµ РґРѕРјРµРЅРЅРѕРµ РёРјСЏ (РЅР°РїСЂРёРјРµСЂ, РІР°С€-РґРѕРјРµРЅ.ru): " MAIN_DOMAIN < /dev/tty
    if [ -z "$MAIN_DOMAIN" ]; then warn "Р”РѕРјРµРЅ РЅРµ РјРѕР¶РµС‚ Р±С‹С‚СЊ РїСѓСЃС‚С‹Рј."; continue; fi
    DOTS="${MAIN_DOMAIN//[^.]}"
    if [ -z "$DOTS" ]; then warn "Р”РѕРјРµРЅ РґРѕР»Р¶РµРЅ СЃРѕРґРµСЂР¶Р°С‚СЊ С‚РѕС‡РєСѓ."; continue; fi
    break
done

read -p "Email Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР° [admin@$MAIN_DOMAIN]: " ADMIN_EMAIL < /dev/tty
ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@$MAIN_DOMAIN"}

SMP_DOMAIN="smp.$MAIN_DOMAIN"
XFTP_DOMAIN="files.$MAIN_DOMAIN"
TURN_DOMAIN="turn.$MAIN_DOMAIN"

# РЎРѕС…СЂР°РЅСЏРµРј СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёРµ СЃРµРєСЂРµС‚С‹ РїСЂРё РїРѕРІС‚РѕСЂРЅРѕРј Р·Р°РїСѓСЃРєРµ СѓСЃС‚Р°РЅРѕРІС‰РёРєР°
if [ -f "$BASE_DIR/.env" ]; then
    info "РћР±РЅР°СЂСѓР¶РµРЅ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёР№ .env вЂ” СЃРѕС…СЂР°РЅСЏРµРј РґРµР№СЃС‚РІСѓСЋС‰РёРµ РїР°СЂРѕР»Рё."
    # shellcheck disable=SC1090
    source "$BASE_DIR/.env"
    TURN_USER="${TURN_USER:-simplex}"
    SMP_PASS="${SMP_PASS:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}"
    XFTP_PASS="${XFTP_PASS:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}"
    TURN_PASS="${TURN_PASS:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}"
else
    SMP_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    XFTP_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    TURN_USER="simplex"
    TURN_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
fi

# ==============================================================================
# 2. РџР РћР’Р•Р РљРђ DNS
# ==============================================================================
info "РџСЂРѕРІРµСЂРєР° DNS-Р·Р°РїРёСЃРµР№..."
if command -v dig &>/dev/null; then
    for SUB in smp files turn; do
        RESOLVED=$(dig +short "${SUB}.${MAIN_DOMAIN}" 2>/dev/null | tail -1)
        if [ "$RESOLVED" != "$EXTERNAL_IP" ]; then
            warn "DNS: ${SUB}.${MAIN_DOMAIN} в†’ ${RESOLVED:-РЅРµ РЅР°Р№РґРµРЅР°} (РѕР¶РёРґР°РµС‚СЃСЏ $EXTERNAL_IP)"
        fi
    done
else
    warn "РЈС‚РёР»РёС‚Р° dig РЅРµРґРѕСЃС‚СѓРїРЅР°. РџСЂРѕРїСѓСЃРє РїСЂРѕРІРµСЂРєРё DNS."
fi

# ==============================================================================
# 3. Р”РР Р•РљРўРћР РР
# ==============================================================================
info "РџРѕРґРіРѕС‚РѕРІРєР° СЃС‚СЂСѓРєС‚СѓСЂС‹ РґРёСЂРµРєС‚РѕСЂРёР№..."
if [ -d "$BASE_DIR/smp/data" ] && [ "$(ls -A "$BASE_DIR/smp/data" 2>/dev/null)" ]; then
    warn "РћР±РЅР°СЂСѓР¶РµРЅС‹ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёРµ РґР°РЅРЅС‹Рµ SMP. РћРЅРё Р±СѓРґСѓС‚ СЃРѕС…СЂР°РЅРµРЅС‹."
fi

mkdir -p "$BASE_DIR"/{smp/{config,certificates,data,logs},xftp/{config,data,files,logs},turn/logs}
mkdir -p "$WEB_DIR"
mkdir -p "$BASE_DIR/backups"

chown -R 1000:1000 "$BASE_DIR/smp" "$BASE_DIR/xftp"
chmod -R 750 "$BASE_DIR"
success "Р”РёСЂРµРєС‚РѕСЂРёРё СЃРѕР·РґР°РЅС‹."

# РљРѕРїРёСЂРѕРІР°РЅРёРµ РёР»Рё Р·Р°РіСЂСѓР·РєР° С„Р°РІРёРєРѕРЅРєРё
FAVICON_SOURCE="" # РСЃС‚РѕС‡РЅРёРє С‚РµРїРµСЂСЊ С‚РѕР»СЊРєРѕ URL
if [ -f "$FAVICON_SOURCE" ]; then
    cp "$FAVICON_SOURCE" "$WEB_DIR/favicon.ico"
    chmod 644 "$WEB_DIR/favicon.ico"
    success "favicon.ico СЃРєРѕРїРёСЂРѕРІР°РЅ РёР· $FAVICON_SOURCE"
elif [ ! -s "$WEB_DIR/favicon.ico" ]; then
    info "Р—Р°РіСЂСѓР·РєР° favicon.ico..."
    if curl -fsSL --max-time 20 \
        "https://install.smp.klenovoe.ru/favicon.ico" \
        -o "$WEB_DIR/favicon.ico" 2>/dev/null; then
        chmod 644 "$WEB_DIR/favicon.ico"
        success "favicon.ico Р·Р°РіСЂСѓР¶РµРЅ."
    else
        warn "РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РіСЂСѓР·РёС‚СЊ favicon.ico. РџР°РЅРµР»СЊ Р±СѓРґРµС‚ СЂР°Р±РѕС‚Р°С‚СЊ Р±РµР· РёРєРѕРЅРєРё."
    fi
else
    success "favicon.ico СѓР¶Рµ СЃСѓС‰РµСЃС‚РІСѓРµС‚ РІ $WEB_DIR"
fi

# ==============================================================================
# 4. TLS РЎР•Р РўРР¤РРљРђРўР«
# ==============================================================================
info "РџСЂРѕРІРµСЂРєР° TLS СЃРµСЂС‚РёС„РёРєР°С‚РѕРІ SMP..."
if [ ! -s "$BASE_DIR/smp/certificates/$SMP_DOMAIN.crt" ] || [ ! -s "$BASE_DIR/smp/certificates/$SMP_DOMAIN.key" ]; then
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$BASE_DIR/smp/certificates/$SMP_DOMAIN.key" \
        -out    "$BASE_DIR/smp/certificates/$SMP_DOMAIN.crt" \
        -days 3650 -subj "/CN=$SMP_DOMAIN" 2>/dev/null
    success "РќРѕРІС‹Р№ self-signed СЃРµСЂС‚РёС„РёРєР°С‚ SMP СЃРѕР·РґР°РЅ."
else
    warn "РЎСѓС‰РµСЃС‚РІСѓСЋС‰РёР№ СЃРµСЂС‚РёС„РёРєР°С‚ SMP СЃРѕС…СЂР°РЅС‘РЅ."
fi

cp "$BASE_DIR/smp/certificates/$SMP_DOMAIN.crt" "$BASE_DIR/smp/config/server.crt"
cp "$BASE_DIR/smp/certificates/$SMP_DOMAIN.key" "$BASE_DIR/smp/config/server.key"
chown 1000:1000 "$BASE_DIR/smp/config/server."* "$BASE_DIR/smp/certificates/"*
success "TLS СЃРµСЂС‚РёС„РёРєР°С‚С‹ SMP РіРѕС‚РѕРІС‹."

# ==============================================================================
# 5. .env
# ==============================================================================
cat > "$BASE_DIR/.env" << EOF
MAIN_DOMAIN=$MAIN_DOMAIN
SMP_DOMAIN=$SMP_DOMAIN
XFTP_DOMAIN=$XFTP_DOMAIN
TURN_DOMAIN=$TURN_DOMAIN
EXTERNAL_IP=$EXTERNAL_IP
INTERNAL_IP=$INTERNAL_IP
ADMIN_EMAIL=$ADMIN_EMAIL
SMP_PASS=$SMP_PASS
XFTP_PASS=$XFTP_PASS
TURN_USER=$TURN_USER
TURN_PASS=$TURN_PASS
BASE_DIR=$BASE_DIR
TZ=$(grep timezone /etc/synoinfo.conf 2>/dev/null | cut -d'"' -f2 || echo "UTC")
EOF
chmod 600 "$BASE_DIR/.env"
success ".env СЃРѕР·РґР°РЅ."

# ==============================================================================
# 6. DOCKER COMPOSE
# ==============================================================================
info "РЎРѕР·РґР°РЅРёРµ docker-compose.yml..."
cat > "$BASE_DIR/docker-compose.yml" << COMPOSEOF
services:
  smp-server:
    image: simplexchat/smp-server:latest
    container_name: simplex-smp
    restart: unless-stopped
    ports:
      - "5223:5223"
      - "5224:443"
    volumes:
      - ${BASE_DIR}/smp/config:/etc/opt/simplex:rw
      - ${BASE_DIR}/smp/data:/var/opt/simplex:rw
      - ${BASE_DIR}/smp/logs:/var/log/simplex:rw
      - ${BASE_DIR}/smp/certificates:/certificates:rw
    environment:
      - ADDR=${SMP_DOMAIN}
      - PASS=${SMP_PASS}
      - STORE_LOG=on
      - SMP_SERVER_TLS_CERT=/certificates/${SMP_DOMAIN}.crt
      - SMP_SERVER_TLS_KEY=/certificates/${SMP_DOMAIN}.key

  xftp-server:
    image: simplexchat/xftp-server:latest
    container_name: simplex-xftp
    restart: unless-stopped
    ports:
      - "7788:443"
    volumes:
      - ${BASE_DIR}/xftp/config:/etc/opt/simplex-xftp:rw
      - ${BASE_DIR}/xftp/data:/var/opt/simplex-xftp:rw
      - ${BASE_DIR}/xftp/files:/srv/xftp:rw
    environment:
      - ADDR=${XFTP_DOMAIN}
      - QUOTA=100gb
      - PASS=${XFTP_PASS}
    command: ["xftp-server", "run"]

  turn-server:
    image: coturn/coturn:latest
    container_name: simplex-turn
    restart: unless-stopped
    network_mode: host
    command: >
      --verbose
      --listening-port=3478
      --tls-listening-port=5349
      --listening-ip=${INTERNAL_IP}
      --relay-ip=${INTERNAL_IP}
      --external-ip=${EXTERNAL_IP}
      --realm=${TURN_DOMAIN}
      --user=${TURN_USER}:${TURN_PASS}
      --lt-cred-mech
      --min-port=49152
      --max-port=65535
      --no-cli
      --fingerprint
COMPOSEOF
success "docker-compose.yml СЃРѕР·РґР°РЅ."

# ==============================================================================
# 7. РРќРР¦РРђР›РР—РђР¦РРЇ XFTP (РЎ Р¤РРљРЎРћРњ Р—РђР’РРЎРђРќРРЇ)
# ==============================================================================
info "РџСЂРѕРІРµСЂРєР° РёРЅРёС†РёР°Р»РёР·Р°С†РёРё XFTP СЃРµСЂРІРµСЂР°..."
XFTP_FP_FILE="$BASE_DIR/xftp/config/fingerprint"

if [ -s "$XFTP_FP_FILE" ] && [ "$(head -1 "$XFTP_FP_FILE")" != "PENDING" ]; then
    XFTP_FP_EXISTING=$(head -1 "$XFTP_FP_FILE")
    success "РЎСѓС‰РµСЃС‚РІСѓСЋС‰Р°СЏ XFTP identity СЃРѕС…СЂР°РЅРµРЅР°: $XFTP_FP_EXISTING"
else
    if find "$BASE_DIR/xftp/config" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        error "XFTP config СЃСѓС‰РµСЃС‚РІСѓРµС‚, РЅРѕ fingerprint РѕС‚СЃСѓС‚СЃС‚РІСѓРµС‚. РџСЂРѕРІРµСЂСЊС‚Рµ $BASE_DIR/xftp/config."
    fi

    info "Р—Р°РїСѓСЃРє РёРЅРёС†РёР°Р»РёР·Р°С†РёРё XFTP..."
    XFTP_INIT_NAME="simplex-xftp-init-$$"

    # xftp-server init РІ v6.5.2 РїРѕСЃР»Рµ РіРµРЅРµСЂР°С†РёРё identity РѕСЃС‚Р°С‘С‚СЃСЏ
    # Р·Р°РїСѓС‰РµРЅРЅС‹Рј foreground-РїСЂРѕС†РµСЃСЃРѕРј. РџРѕСЌС‚РѕРјСѓ init-РєРѕРЅС‚РµР№РЅРµСЂ Р·Р°РїСѓСЃРєР°РµРј
    # detached, Р¶РґС‘Рј РїРѕСЏРІР»РµРЅРёСЏ fingerprint Рё Р·Р°С‚РµРј СѓРґР°Р»СЏРµРј РµРіРѕ.
    if ! docker run -d --name "$XFTP_INIT_NAME" \
        -e ADDR="${XFTP_DOMAIN}" \
        -e QUOTA="100gb" \
        -e PASS="${XFTP_PASS}" \
        -v "$BASE_DIR/xftp/config:/etc/opt/simplex-xftp" \
        -v "$BASE_DIR/xftp/data:/var/opt/simplex-xftp" \
        simplexchat/xftp-server:v6.5.2 \
        xftp-server init -n "$XFTP_DOMAIN" >/dev/null; then
        docker logs "$XFTP_INIT_NAME" 2>&1 | tail -50 || true
        docker rm -f "$XFTP_INIT_NAME" >/dev/null 2>&1 || true
        error "РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РїСѓСЃС‚РёС‚СЊ XFTP init."
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
        warn "XFTP fingerprint РЅРµ РїРѕСЏРІРёР»СЃСЏ Р·Р° 30 СЃРµРєСѓРЅРґ. Р›РѕРіРё init:"
        docker logs "$XFTP_INIT_NAME" 2>&1 | tail -80 || true
        docker rm -f "$XFTP_INIT_NAME" >/dev/null 2>&1 || true
        error "РќРµ СѓРґР°Р»РѕСЃСЊ РїРѕР»СѓС‡РёС‚СЊ XFTP fingerprint."
    fi

    XFTP_FP_INIT=$(head -1 "$XFTP_FP_FILE")
    docker rm -f "$XFTP_INIT_NAME" >/dev/null 2>&1 || true
    success "XFTP identity СЃРѕР·РґР°РЅР°: $XFTP_FP_INIT"
    success "XFTP РёРЅРёС†РёР°Р»РёР·РёСЂРѕРІР°РЅ."
fi

chown -R 1000:1000 "$BASE_DIR/xftp"

# ==============================================================================
# 8. Р—РђРџРЈРЎРљ
# ==============================================================================
cd "$BASE_DIR"
info "Р—Р°РіСЂСѓР·РєР° Р·Р°С„РёРєСЃРёСЂРѕРІР°РЅРЅС‹С… Docker-РѕР±СЂР°Р·РѕРІ..."
if ! $COMPOSE_CMD pull; then
    error "РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РіСЂСѓР·РёС‚СЊ Docker-РѕР±СЂР°Р·С‹."
fi

info "Р—Р°РїСѓСЃРє СЃРµСЂРІРёСЃРѕРІ..."
if ! $COMPOSE_CMD up -d; then
    error "Docker Compose РЅРµ СЃРјРѕРі Р·Р°РїСѓСЃС‚РёС‚СЊ СЃРµСЂРІРёСЃС‹."
fi

sleep 5
for svc in simplex-smp simplex-xftp simplex-turn; do
    if ! docker inspect -f '{{.State.Running}}' "$svc" 2>/dev/null | grep -q true; then
        warn "Р›РѕРіРё $svc:"
        docker logs "$svc" 2>&1 | tail -30 || true
        error "$svc РЅРµ Р·Р°РїСѓСЃС‚РёР»СЃСЏ."
    fi
done
success "Р’СЃРµ РєРѕРЅС‚РµР№РЅРµСЂС‹ Р·Р°РїСѓС‰РµРЅС‹."

# ==============================================================================
# 9. РћР–РР”РђРќРР• FINGERPRINT
# ==============================================================================
info "РћР¶РёРґР°РЅРёРµ РіРµРЅРµСЂР°С†РёРё fingerprint (РґРѕ 120 СЃРµРє)..."
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
    warn "SMP fingerprint РµС‰С‘ РЅРµ СЃРіРµРЅРµСЂРёСЂРѕРІР°РЅ."
    docker logs simplex-smp 2>&1 | tail -50 || true
    error "РќРµ СѓРґР°Р»РѕСЃСЊ РїРѕР»СѓС‡РёС‚СЊ SMP fingerprint. РЈСЃС‚Р°РЅРѕРІРєР° РѕСЃС‚Р°РЅРѕРІР»РµРЅР°."
fi

if [ -z "$XFTP_FP" ] || [ "$XFTP_FP" = "PENDING" ]; then
    warn "XFTP fingerprint РµС‰С‘ РЅРµ СЃРіРµРЅРµСЂРёСЂРѕРІР°РЅ."
    docker logs simplex-xftp 2>&1 | tail -50 || true
    error "РќРµ СѓРґР°Р»РѕСЃСЊ РїРѕР»СѓС‡РёС‚СЊ XFTP fingerprint. РЈСЃС‚Р°РЅРѕРІРєР° РѕСЃС‚Р°РЅРѕРІР»РµРЅР°."
fi

SMP_ADDRESS="smp://${SMP_FP}:${SMP_PASS}@${SMP_DOMAIN}:5224"
XFTP_ADDRESS="xftp://${XFTP_FP}:${XFTP_PASS}@${XFTP_DOMAIN}:7788"
TURN_UDP="turn:${TURN_USER}:${TURN_PASS}@${TURN_DOMAIN}:3478?transport=udp"
TURN_TLS="turns:${TURN_USER}:${TURN_PASS}@${TURN_DOMAIN}:5349?transport=tcp"
STUN_ADDR="stun:${TURN_DOMAIN}:3478"
success "Fingerprint РїРѕР»СѓС‡РµРЅС‹."

# ==============================================================================
# 10. BACKUP
# ==============================================================================
info "РЎРѕР·РґР°РЅРёРµ СЃРєСЂРёРїС‚Р° СЂРµР·РµСЂРІРЅРѕРіРѕ РєРѕРїРёСЂРѕРІР°РЅРёСЏ..."
BACKUP_SCRIPT="$BASE_DIR/simplex-backup.sh"
cat > "$BACKUP_SCRIPT" << 'BKEOF'
#!/bin/bash
set -e
# РђРІС‚РѕРѕРїСЂРµРґРµР»РµРЅРёРµ С‚РѕРјР° (С‚Р° Р¶Рµ Р»РѕРіРёРєР°, С‡С‚Рѕ РІ СѓСЃС‚Р°РЅРѕРІС‰РёРєРµ)
DOCKER_ROOT=""
for v in /volume*; do
    if [ "$v" != "/volume1" ] && [ -d "$v/docker" ]; then
        DOCKER_ROOT="$v/docker"
        break
    fi
done
if [ -z "$DOCKER_ROOT" ] && [ -d "/volume1/docker" ]; then
    DOCKER_ROOT="/volume1/docker"
fi
[ -z "$DOCKER_ROOT" ] && echo "[ERR] РўРѕРј docker РЅРµ РЅР°Р№РґРµРЅ" && exit 1
BASE_DIR="${DOCKER_ROOT}/simplex"

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
chmod 700 "$BACKUP_SCRIPT"
success "Backup-СЃРєСЂРёРїС‚ СЃРѕР·РґР°РЅ."

# ==============================================================================
# 11. STATUS-UPDATE.SH + CRON
# ==============================================================================
info "РЎРѕР·РґР°РЅРёРµ СЃРєСЂРёРїС‚Р° РѕР±РЅРѕРІР»РµРЅРёСЏ СЃС‚Р°С‚СѓСЃР°..."
STATUS_SCRIPT="$BASE_DIR/status-update.sh"
cat > "$STATUS_SCRIPT" << 'STEOF'
#!/bin/bash
DOCKER_ROOT=""
for v in /volume*; do
    if [[ "$v" =~ ^/volume[0-9]+$ ]] && [ -d "$v/docker" ]; then
        DOCKER_ROOT="$v/docker"
        break
    fi
done
if [ -z "$DOCKER_ROOT" ] && [ -d "/volume1/docker" ]; then
    DOCKER_ROOT="/volume1/docker"
fi
[ -z "$DOCKER_ROOT" ] && echo "[ERR] РўРѕРј docker РЅРµ РЅР°Р№РґРµРЅ" && exit 1
BASE_DIR="${DOCKER_ROOT}/simplex"
OUT="$BASE_DIR/install/www/status.json"
mkdir -p "$(dirname "$OUT")"
SMP=$(docker inspect --format='{{.State.Status}}' simplex-smp 2>/dev/null || echo "not_found")
XFTP=$(docker inspect --format='{{.State.Status}}' simplex-xftp 2>/dev/null || echo "not_found")
TURN=$(docker inspect --format='{{.State.Status}}' simplex-turn 2>/dev/null || echo "not_found")
printf '{"simplex-smp":"%s","simplex-xftp":"%s","simplex-turn":"%s","updated":"%s"}\n' \
    "$SMP" "$XFTP" "$TURN" "$(date '+%Y-%m-%d %H:%M:%S')" > "$OUT"
chmod 644 "$OUT"
STEOF
chmod 755 "$STATUS_SCRIPT"
"$STATUS_SCRIPT"
CRON_LINE="*/1 * * * * root $STATUS_SCRIPT"
if ! grep -q "status-update.sh" /etc/crontab 2>/dev/null; then
    echo "$CRON_LINE" >> /etc/crontab
    synoservicectl --restart crond 2>/dev/null || true
    success "Cron-Р·Р°РґР°С‡Р° СЃС‚Р°С‚СѓСЃР° РґРѕР±Р°РІР»РµРЅР° (РєР°Р¶РґСѓСЋ РјРёРЅСѓС‚Сѓ)."
else
    warn "Cron-Р·Р°РґР°С‡Р° status-update.sh СѓР¶Рµ СЃСѓС‰РµСЃС‚РІСѓРµС‚."
fi
BACKUP_CRON="0 3 * * * root $BASE_DIR/simplex-backup.sh"
if ! grep -q "simplex-backup.sh" /etc/crontab 2>/dev/null; then
    echo "$BACKUP_CRON" >> /etc/crontab
    synoservicectl --restart crond 2>/dev/null || true
    success "Cron-Р·Р°РґР°С‡Р° backup РґРѕР±Р°РІР»РµРЅР° (РµР¶РµРґРЅРµРІРЅРѕ РІ 03:00)."
else
    warn "Cron-Р·Р°РґР°С‡Р° simplex-backup.sh СѓР¶Рµ СЃСѓС‰РµСЃС‚РІСѓРµС‚."
fi
success "status-update.sh СЃРѕР·РґР°РЅ."

# ==============================================================================
# 12. WEB-Р¤РђР™Р›Р«
# ==============================================================================
info "РЎРѕР·РґР°РЅРёРµ РІРµР±-СЃС‚СЂР°РЅРёС†..."
QRCODE_JS="$WEB_DIR/qrcode.min.js"
if [ ! -s "$QRCODE_JS" ]; then
    info "Р—Р°РіСЂСѓР·РєР° QRCode.js..."
    if curl -fsSL --max-time 20 \
        "https://install.smp.klenovoe.ru/qrcode.min.js" \
        -o "$QRCODE_JS" 2>/dev/null; then
        chmod 644 "$QRCODE_JS"
        success "QRCode.js Р·Р°РіСЂСѓР¶РµРЅ."
    else
        error "РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РіСЂСѓР·РёС‚СЊ QRCode.js. РџСЂРѕРІРµСЂСЊС‚Рµ РґРѕСЃС‚СѓРїРЅРѕСЃС‚СЊ install.smp.klenovoe.ru"
    fi
fi
chmod 644 "$QRCODE_JS"

# --- 12a. qrsmp.html (Р­С‚Р°Р»РѕРЅРЅР°СЏ РІРµСЂСЃРёСЏ) ---
cat > "$WEB_DIR/qrsmp.html" << HTMLEOF
<!DOCTYPE html>
<html lang="ru" data-theme="dark">
<head>
<meta charset="UTF-8">
<link rel="icon" href="favicon.ico" type="image/x-icon">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0c0a14">
<title>SimpleX Control вЂ” ${MAIN_DOMAIN}</title>
<style>
[data-theme="dark"]{--bg:#0c0a14;--card:#1a1528;--line:rgba(139,92,246,.12);--text:#f5f3fa;--muted:#9d8fb8;--purple:#8B5CF6;--purple-light:#a78bfa;--green:#34d399;--red:#f87171;--topbar-bg:rgba(12,10,20,.86);--input-bg:#0c0a14;--code-text:#b8a8d8;--icon-bg:rgba(139,92,246,.14);--icon-green:rgba(52,211,153,.12);--btn-bg:rgba(139,92,246,.06);--btn-p-bg:rgba(139,92,246,.16);--btn-p-bd:rgba(139,92,246,.25);--toast-bg:#8B5CF6;--warn-bg:rgba(248,113,113,.07);--warn-bd:rgba(248,113,113,.16);--warn-t:#fca5a5;--logo-bg:linear-gradient(145deg,#2d1f52,#1a1230);--r1:rgba(139,92,246,.14);--r2:rgba(109,40,217,.09);--shadow:rgba(0,0,0,.25);--copy-bg:rgba(139,92,246,.1);--copy-c:#d4c8ee;--footer:#5a4d78;--handle:#4a3d6b;--service-bg:rgba(0,0,0,.2)}
[data-theme="light"]{--bg:#f4f1fa;--card:#fff;--line:rgba(139,92,246,.14);--text:#1a1528;--muted:#6b5f85;--purple:#7C3AED;--purple-light:#6d28d9;--green:#059669;--red:#dc2626;--topbar-bg:rgba(244,241,250,.88);--input-bg:#f0ecf8;--code-text:#4a3d6b;--icon-bg:rgba(139,92,246,.1);--icon-green:rgba(5,150,105,.1);--btn-bg:rgba(139,92,246,.06);--btn-p-bg:rgba(139,92,246,.12);--btn-p-bd:rgba(139,92,246,.22);--toast-bg:#7C3AED;--warn-bg:rgba(220,38,38,.05);--warn-bd:rgba(220,38,38,.14);--warn-t:#b91c1c;--logo-bg:linear-gradient(145deg,#ede9fe,#ddd6fe);--r1:rgba(139,92,246,.08);--r2:rgba(109,40,217,.05);--shadow:rgba(109,40,217,.08);--copy-bg:rgba(139,92,246,.08);--copy-c:#5b21b6;--footer:#8a7aa8;--handle:#c4b5e0;--service-bg:rgba(139,92,246,.05)}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}html{scroll-behavior:smooth}body{margin:0;min-height:100vh;background:radial-gradient(circle at 80% -10%,var(--r1),transparent 32%),radial-gradient(circle at -10% 20%,var(--r2),transparent 28%),var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;transition:background .3s,color .3s}.app{max-width:820px;margin:auto;padding:0 15px 40px}.topbar{position:sticky;top:0;z-index:50;margin:0 -15px;padding:calc(12px + env(safe-area-inset-top)) 15px 12px;background:var(--topbar-bg);backdrop-filter:blur(22px);border-bottom:1px solid var(--line)}.topbar-inner{display:flex;align-items:center;justify-content:space-between}.brand{display:flex;align-items:center;gap:11px}.logo{width:40px;height:40px;display:grid;place-items:center;border-radius:13px;background:var(--logo-bg);border:1px solid var(--line)}.logo svg{width:22px;height:22px;color:var(--purple-light)}.bt{font-size:16px;font-weight:750}.bd{color:var(--muted);font-size:12px}.hbtn{display:grid;place-items:center;width:40px;height:40px;border-radius:12px;border:1px solid var(--line);background:var(--btn-bg);color:var(--text);cursor:pointer}.hbtn svg{width:18px}.hero{padding:25px 2px 18px}.hero h1{margin:0;font-size:28px;letter-spacing:-1px}.hero p{margin:8px 0 0;color:var(--muted);font-size:14px}.card{background:var(--card);border:1px solid var(--line);border-radius:20px;box-shadow:0 12px 35px var(--shadow);padding:20px;margin-bottom:14px;transition:background .3s}.ct{font-size:17px;font-weight:750;margin-bottom:12px;display:flex;align-items:center;gap:9px}.ct svg{width:20px;color:var(--purple-light);flex:none}.st-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}.st-title{font-size:17px;font-weight:750}.st-sub{color:var(--muted);font-size:12px;margin-top:2px}.online{display:flex;align-items:center;gap:7px;font-size:12px;font-weight:700}.online.ok{color:var(--green)}.online.err{color:var(--red)}.online.na{color:var(--muted)}.odot{width:8px;height:8px;border-radius:50%;flex:none}.odot.ok{background:var(--green);box-shadow:0 0 0 4px rgba(52,211,153,.15)}.odot.err{background:var(--red);box-shadow:0 0 0 4px rgba(248,113,113,.15)}.odot.na{background:var(--muted)}.st-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.st-item{padding:12px;background:var(--service-bg);border:1px solid var(--line);border-radius:13px;text-align:center}.st-name{font-size:11px;color:var(--muted)}.st-val{margin-top:3px;font-size:12px;font-weight:700}.st-val.run{color:var(--green)}.st-val.stop{color:var(--red)}.st-val.na{color:var(--muted)}.srv-head{display:flex;align-items:center;gap:12px;margin-bottom:14px}.srv-icon{width:43px;height:43px;flex:none;display:grid;place-items:center;border-radius:14px;background:var(--icon-bg);color:var(--purple-light)}.srv-icon.grn{background:var(--icon-green);color:var(--green)}.srv-icon svg{width:21px}.srv-name{font-size:16px;font-weight:750}.srv-desc{color:var(--muted);font-size:12px;margin-top:2px}.abox{position:relative;padding:12px 43px 12px 12px;border-radius:12px;background:var(--input-bg);border:1px solid var(--line);color:var(--code-text);font:11px/1.55 ui-monospace,Menlo,Consolas,monospace;word-break:break-all}.aval{filter:blur(4px);user-select:none;transition:filter .2s}.abox.rev .aval{filter:none;user-select:text}.cmini{position:absolute;right:7px;top:7px;width:30px;height:30px;border-radius:9px;background:var(--copy-bg);border:1px solid var(--line);color:var(--copy-c);display:grid;place-items:center;cursor:pointer}.cmini svg{width:15px}.tbox{padding:12px;border-radius:12px;background:var(--input-bg);border:1px solid var(--line);color:var(--code-text);font:11px/1.55 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-all}.tval{filter:blur(5px);user-select:none;transition:filter .25s}.tbox.rev .tval{filter:none;user-select:text}.acts{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.tacts{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.btn{min-height:44px;display:flex;align-items:center;justify-content:center;gap:7px;border-radius:12px;border:1px solid var(--line);background:var(--btn-bg);color:var(--text);font-weight:700;font-size:12px;cursor:pointer}.btn:active{transform:scale(.97)}.btn.p{background:var(--btn-p-bg);border-color:var(--btn-p-bd);color:var(--purple-light)}.irow{display:flex;justify-content:space-between;gap:15px;padding:13px 0;border-bottom:1px solid var(--line)}.irow:last-child{border:0}.il{color:var(--muted);font-size:12px}.iv{font-size:12px;font-weight:600}.port-list{display:flex;flex-wrap:wrap;gap:7px}.port-item{padding:7px 14px;border-radius:9px;background:var(--btn-p-bg);color:var(--purple-light);font:12px/1 ui-monospace,Menlo,Consolas,monospace;font-weight:650}.code-block{background:var(--input-bg);border:1px solid var(--line);border-radius:12px;padding:13px;color:var(--code-text);font:10.5px/1.6 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-word}.sec{background:var(--warn-bg);border:1px solid var(--warn-bd);border-radius:20px;padding:17px}.sec-t{color:var(--warn-t);font-size:15px;font-weight:750;margin-bottom:10px}.sec ul{padding-left:19px;margin:0;color:var(--muted);font-size:12px}.sec li{margin-bottom:7px}.footer{text-align:center;padding:22px 0 10px;color:var(--footer);font-size:10px}.toast{position:fixed;left:50%;bottom:30px;transform:translate(-50%,20px);z-index:200;opacity:0;pointer-events:none;padding:11px 18px;background:var(--toast-bg);color:#fff;border-radius:12px;font-size:12px;font-weight:750;box-shadow:0 12px 35px rgba(109,40,217,.3);transition:.2s}.toast.show{opacity:1;transform:translate(-50%,0)}.modal{position:fixed;inset:0;z-index:100;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.65);backdrop-filter:blur(8px)}.modal.on{display:flex}.mcont{width:100%;max-width:420px;padding:20px;background:var(--card);border:1px solid var(--line);border-radius:25px;text-align:center}.mh{width:38px;height:4px;background:var(--handle);border-radius:20px;margin:0 auto 16px}.qrf{padding:12px;background:#fff;border-radius:16px;display:inline-block;margin:14px 0}.qrf img{display:block}.disclaimer-card{border-color:var(--warn-bd)}.box{padding:12px 14px;border-radius:10px;font-size:12px;line-height:1.6;margin:8px 0}.box strong{display:block;margin-bottom:4px;font-size:13px}.box.warn{background:var(--warn-bg);border:1px solid var(--warn-bd);color:var(--warn-t)}.box.info{background:var(--btn-bg);border:1px solid var(--line);color:var(--muted)}.box.note{background:var(--btn-bg);border:1px solid var(--btn-p-bd);color:var(--muted)}.box ul{padding-left:16px;margin:6px 0 0}.box li{margin-bottom:4px}@media(max-width:400px){.app{padding:0 12px 30px}.topbar{margin:0 -12px;padding-left:12px;padding-right:12px}.acts,.tacts{grid-template-columns:1fr}.st-grid{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="app">
<header class="topbar"><div class="topbar-inner">
<div class="brand">
<div class="logo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3l7 4v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V7l7-4z"/><path d="M9 12l2 2 4-4"/></svg></div>
<div><div class="bt">SimpleX Control</div><div class="bd">${MAIN_DOMAIN}</div></div>
</div>
<button class="hbtn" onclick="toggleTheme()" aria-label="РўРµРјР°">
<svg id="ico-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" style="display:none"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg>
<svg id="ico-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
</button>
</div></header>

<section class="hero"><h1>SimpleX Server</h1><p>РЈРїСЂР°РІР»РµРЅРёРµ СЃРµСЂРІРµСЂР°РјРё Рё РїРѕРґРєР»СЋС‡РµРЅРёРµ РєР»РёРµРЅС‚РѕРІ В· ${MAIN_DOMAIN}</p></section>

<section class="card disclaimer-card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>РџСЂР°РІРѕРІР°СЏ РёРЅС„РѕСЂРјР°С†РёСЏ</div>
<div class="box warn"><strong>вљ пёЏ РќР°Р·РЅР°С‡РµРЅРёРµ РїР°РЅРµР»Рё</strong>Р”Р°РЅРЅР°СЏ РїР°РЅРµР»СЊ СѓРїСЂР°РІР»РµРЅРёСЏ РїСЂРµРґРЅР°Р·РЅР°С‡РµРЅР° РёСЃРєР»СЋС‡РёС‚РµР»СЊРЅРѕ РґР»СЏ Р°РґРјРёРЅРёСЃС‚СЂРёСЂРѕРІР°РЅРёСЏ СЃРµСЂРІРµСЂР° SimpleX Chat, СЂР°Р·РІС‘СЂРЅСѓС‚РѕРіРѕ РЅР° СЃРѕР±СЃС‚РІРµРЅРЅРѕРј РѕР±РѕСЂСѓРґРѕРІР°РЅРёРё РІР»Р°РґРµР»СЊС†Р° РІ С†РµР»СЏС… Р»РёС‡РЅРѕРіРѕ Рё СЃРµРјРµР№РЅРѕРіРѕ РёСЃРїРѕР»СЊР·РѕРІР°РЅРёСЏ. РџР°РЅРµР»СЊ РЅРµ РїСЂРµРґРЅР°Р·РЅР°С‡РµРЅР° РґР»СЏ РїСЂРµРґРѕСЃС‚Р°РІР»РµРЅРёСЏ РїСѓР±Р»РёС‡РЅС‹С… СЃРµСЂРІРёСЃРѕРІ РЅРµРѕРіСЂР°РЅРёС‡РµРЅРЅРѕРјСѓ РєСЂСѓРіСѓ Р»РёС†.</div>
<div class="box info"><strong>рџ“‹ РћС‚РІРµС‚СЃС‚РІРµРЅРЅРѕСЃС‚СЊ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР°</strong><ul><li>РСЃРїРѕР»СЊР·РѕРІР°РЅРёРµ СЃРµСЂРІРµСЂР° РґР»СЏ РїСЂРµРґРѕСЃС‚Р°РІР»РµРЅРёСЏ СЃРµСЂРІРёСЃР° РЅРµРѕРіСЂР°РЅРёС‡РµРЅРЅРѕРјСѓ РєСЂСѓРіСѓ Р»РёС† РјРѕР¶РµС‚ РїРѕРІР»РµС‡СЊ РѕР±СЏР·Р°РЅРЅРѕСЃС‚СЊ СЂРµРіРёСЃС‚СЂР°С†РёРё РІ РєР°С‡РµСЃС‚РІРµ РѕСЂРіР°РЅРёР·Р°С‚РѕСЂР° СЂР°СЃРїСЂРѕСЃС‚СЂР°РЅРµРЅРёСЏ РёРЅС„РѕСЂРјР°С†РёРё (РћР Р) РІ СЃРѕРѕС‚РІРµС‚СЃС‚РІРёРё СЃРѕ СЃС‚. 10.1 Р¤РµРґРµСЂР°Р»СЊРЅРѕРіРѕ Р·Р°РєРѕРЅР° в„– 149-Р¤Р— В«РћР± РёРЅС„РѕСЂРјР°С†РёРё, РёРЅС„РѕСЂРјР°С†РёРѕРЅРЅС‹С… С‚РµС…РЅРѕР»РѕРіРёСЏС… Рё Рѕ Р·Р°С‰РёС‚Рµ РёРЅС„РѕСЂРјР°С†РёРёВ».</li><li>РћР±СЂР°Р±РѕС‚РєР° РїРµСЂСЃРѕРЅР°Р»СЊРЅС‹С… РґР°РЅРЅС‹С… РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№ СЂРµРіСѓР»РёСЂСѓРµС‚СЃСЏ Р¤РµРґРµСЂР°Р»СЊРЅС‹Рј Р·Р°РєРѕРЅРѕРј в„– 152-Р¤Р— В«Рћ РїРµСЂСЃРѕРЅР°Р»СЊРЅС‹С… РґР°РЅРЅС‹С…В».</li><li>РђРґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ СЃРµСЂРІРµСЂР° СЃР°РјРѕСЃС‚РѕСЏС‚РµР»СЊРЅРѕ РЅРµСЃС‘С‚ РѕС‚РІРµС‚СЃС‚РІРµРЅРЅРѕСЃС‚СЊ Р·Р° СЃРѕР±Р»СЋРґРµРЅРёРµ РїСЂРёРјРµРЅРёРјРѕРіРѕ Р·Р°РєРѕРЅРѕРґР°С‚РµР»СЊСЃС‚РІР°, РЅР°СЃС‚СЂРѕР№РєСѓ Р±РµР·РѕРїР°СЃРЅРѕСЃС‚Рё, СЂРµР·РµСЂРІРЅРѕРµ РєРѕРїРёСЂРѕРІР°РЅРёРµ Рё Р·Р°С‰РёС‚Сѓ РґР°РЅРЅС‹С….</li><li>РђРІС‚РѕСЂ СЃРєСЂРёРїС‚Р° РЅРµ РЅРµСЃС‘С‚ РѕС‚РІРµС‚СЃС‚РІРµРЅРЅРѕСЃС‚Рё Р·Р° РїРѕСЃР»РµРґСЃС‚РІРёСЏ РёСЃРїРѕР»СЊР·РѕРІР°РЅРёСЏ, РІРєР»СЋС‡Р°СЏ СЃР±РѕРё, РїРѕС‚РµСЂСЋ РґР°РЅРЅС‹С… РёР»Рё РїСЂРµС‚РµРЅР·РёРё С‚СЂРµС‚СЊРёС… Р»РёС†.</li></ul></div>
<div class="box note"><strong>рџ’Ў Р РµРєРѕРјРµРЅРґР°С†РёСЏ</strong>РќРµ РїСѓР±Р»РёРєСѓР№С‚Рµ Р°РґСЂРµСЃР° СЃРµСЂРІРµСЂРѕРІ (SMP, XFTP, TURN) Рё QR-РєРѕРґС‹ РІ РѕС‚РєСЂС‹С‚РѕРј РґРѕСЃС‚СѓРїРµ. РџРµСЂРµРґ СЂР°СЃС€РёСЂРµРЅРёРµРј РєСЂСѓРіР° РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№ Р·Р° РїСЂРµРґРµР»С‹ СЃРµРјСЊРё РёР»Рё Р±Р»РёР·РєРёС… Р·РЅР°РєРѕРјС‹С… СЂРµРєРѕРјРµРЅРґСѓРµС‚СЃСЏ РїСЂРѕРєРѕРЅСЃСѓР»СЊС‚РёСЂРѕРІР°С‚СЊСЃСЏ СЃ РєРІР°Р»РёС„РёС†РёСЂРѕРІР°РЅРЅС‹Рј СЋСЂРёСЃС‚РѕРј, СЃРїРµС†РёР°Р»РёР·РёСЂСѓСЋС‰РёРјСЃСЏ РЅР° РёРЅС„РѕСЂРјР°С†РёРѕРЅРЅРѕРј РїСЂР°РІРµ.</div>
</section>

<div class="card">
<div class="st-head"><div><div class="st-title">РЎРµСЂРІРµСЂРЅР°СЏ РёРЅС„СЂР°СЃС‚СЂСѓРєС‚СѓСЂР°</div><div class="st-sub">SimpleX Installer 9.4</div></div><div class="online na" id="ov-status"><span class="odot na" id="ov-dot"></span><span id="ov-text">вЂ¦</span></div></div>
<div class="st-grid"><div class="st-item"><div class="st-name">SMP</div><div class="st-val na" id="st-smp">вЂ¦</div></div><div class="st-item"><div class="st-name">XFTP</div><div class="st-val na" id="st-xftp">вЂ¦</div></div><div class="st-item"><div class="st-name">TURN</div><div class="st-val na" id="st-turn">вЂ¦</div></div></div>
</div>

<div class="card">
<div class="srv-head"><div class="srv-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 5h16v11H4z"/><path d="M8 20h8M12 16v4"/></svg></div><div><div class="srv-name">SMP Server</div><div class="srv-desc">РџРµСЂРµРґР°С‡Р° СЃРѕРѕР±С‰РµРЅРёР№ В· РїРѕСЂС‚ 5224</div></div></div>
<div class="abox" id="smp-box"><span class="aval">${SMP_ADDRESS}</span><button class="cmini" onclick="copyText(S.smp)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="8" y="8" width="11" height="11" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg></button></div>
<div class="acts"><button class="btn p" onclick="openQR('smp')">в–¦ QR-РєРѕРґ</button><button class="btn" onclick="rev('smp-box')">РџРѕРєР°Р·Р°С‚СЊ</button></div>
</div>

<div class="card">
<div class="srv-head"><div class="srv-icon grn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 6a2 2 0 0 1 2-2h5l2 2h5a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/></svg></div><div><div class="srv-name">XFTP Server</div><div class="srv-desc">РџРµСЂРµРґР°С‡Р° С„Р°Р№Р»РѕРІ В· РїРѕСЂС‚ 7788</div></div></div>
<div class="abox" id="xftp-box"><span class="aval">${XFTP_ADDRESS}</span><button class="cmini" onclick="copyText(S.xftp)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="8" y="8" width="11" height="11" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg></button></div>
<div class="acts"><button class="btn p" onclick="openQR('xftp')">в–¦ QR-РєРѕРґ</button><button class="btn" onclick="rev('xftp-box')">РџРѕРєР°Р·Р°С‚СЊ</button></div>
</div>

<div class="card">
<div class="srv-head"><div class="srv-icon grn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2c2.5 2.7 4 6.3 4 10s-1.5 7.3-4 10c-2.5-2.7-4-6.3-4-10s1.5-7.3 4-10z"/></svg></div><div><div class="srv-name">TURN / STUN</div><div class="srv-desc">РђСѓРґРёРѕ- Рё РІРёРґРµРѕР·РІРѕРЅРєРё В· РїРѕСЂС‚С‹ 3478, 5349</div></div></div>
<div class="tbox" id="turn-box"><span class="tval">${STUN_ADDR}
${TURN_UDP}
${TURN_TLS}</span></div>
<div class="tacts"><button class="btn p" onclick="copyText(S.turn)">рџ“‹ РљРѕРїРёСЂРѕРІР°С‚СЊ РІСЃРµ Р°РґСЂРµСЃР°</button><button class="btn" onclick="revT()">РџРѕРєР°Р·Р°С‚СЊ</button></div>
</div>

<div class="card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 12h14"/><path d="M12 5l7 7-7 7"/></svg>РџРѕРґРєР»СЋС‡РµРЅРёРµ</div>
<div class="irow"><div class="il">SMP</div><div class="iv">${SMP_DOMAIN}:5224</div></div>
<div class="irow"><div class="il">XFTP</div><div class="iv">${XFTP_DOMAIN}:7788</div></div>
<div class="irow"><div class="il">TURN / STUN</div><div class="iv">${TURN_DOMAIN}</div></div>
<div class="irow"><div class="il">РџСЂРѕС‚РѕРєРѕР»</div><div class="iv">TLS / UDP</div></div>
<div class="irow"><div class="il">Р’РµСЂСЃРёСЏ РёРЅСЃС‚Р°Р»Р»РµСЂР°</div><div class="iv">9.4</div></div>
</div>

<div class="card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><path d="M6 6h.01M6 18h.01"/></svg>РџРѕСЂС‚С‹</div>
<div class="port-list"><span class="port-item">5224 TCP</span><span class="port-item">7788 TCP</span><span class="port-item">3478 TCP+UDP</span><span class="port-item">5349 TCP</span><span class="port-item">49152-65535 UDP</span></div>
</div>

<div class="card">
<div class="ct"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>Р”РёР°РіРЅРѕСЃС‚РёРєР°</div>
<div class="code-block">cd ${BASE_DIR}
docker compose ps
docker logs simplex-smp
docker logs simplex-xftp
docker logs simplex-turn
docker compose pull && docker compose up -d</div>
</div>

<div class="sec">
<div class="sec-t">вљ пёЏ Р‘РµР·РѕРїР°СЃРЅРѕСЃС‚СЊ</div>
<ul><li>РќРµ РїСѓР±Р»РёРєСѓР№С‚Рµ QR-РєРѕРґС‹ РІ РѕС‚РєСЂС‹С‚РѕРј РґРѕСЃС‚СѓРїРµ.</li><li>РќРµ РїРµСЂРµРґР°РІР°Р№С‚Рµ Р°РґСЂРµСЃР° SMP Рё XFTP РїРѕСЃС‚РѕСЂРѕРЅРЅРёРј.</li><li>РҐСЂР°РЅРёС‚Рµ СЂРµР·РµСЂРІРЅС‹Рµ РєРѕРїРёРё РѕС‚РґРµР»СЊРЅРѕ РѕС‚ NAS.</li><li>РџСЂРё РєРѕРјРїСЂРѕРјРµС‚Р°С†РёРё СЃРѕР·РґР°Р№С‚Рµ РЅРѕРІС‹Рµ Р°РґСЂРµСЃР°.</li><li>Р РµРіСѓР»СЏСЂРЅРѕ РѕР±РЅРѕРІР»СЏР№С‚Рµ РєРѕРЅС‚РµР№РЅРµСЂС‹ SimpleX.</li><li>Р¤Р°Р№Р» .env СЃРѕРґРµСЂР¶РёС‚ РІСЃРµ РїР°СЂРѕР»Рё вЂ” РЅРµ РїРµСЂРµРґР°РІР°Р№С‚Рµ РµРіРѕ.</li></ul>
</div>

<section class="card backup-card">
<h2>рџ’ѕ Р РµР·РµСЂРІРЅРѕРµ РєРѕРїРёСЂРѕРІР°РЅРёРµ</h2>
<p>РЈСЃС‚Р°РЅРѕРІС‰РёРє СЃРѕР·РґР°С‘С‚ СЃРєСЂРёРїС‚ Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРѕРіРѕ СЂРµР·РµСЂРІРЅРѕРіРѕ РєРѕРїРёСЂРѕРІР°РЅРёСЏ <code>simplex-backup.sh</code>. РџРѕ СѓРјРѕР»С‡Р°РЅРёСЋ backup РІС‹РїРѕР»РЅСЏРµС‚СЃСЏ РµР¶РµРґРЅРµРІРЅРѕ РІ <strong>03:00</strong>.</p>
<div class="notice"><strong>Р’Р°Р¶РЅРѕ:</strong> СЂРµР·РµСЂРІРЅС‹Рµ РєРѕРїРёРё СЃРѕС…СЂР°РЅСЏСЋС‚СЃСЏ РЅР° СЌС‚РѕРј Р¶Рµ NAS. Р”Р»СЏ Р·Р°С‰РёС‚С‹ РѕС‚ РѕС‚РєР°Р·Р° РЅР°РєРѕРїРёС‚РµР»СЏ РёР»Рё СЃР°РјРѕРіРѕ NAS СЂРµРєРѕРјРµРЅРґСѓРµС‚СЃСЏ РґРѕРїРѕР»РЅРёС‚РµР»СЊРЅРѕ РєРѕРїРёСЂРѕРІР°С‚СЊ РєР°С‚Р°Р»РѕРі backup РЅР° РґСЂСѓРіРѕР№ NAS, USB-РґРёСЃРє РёР»Рё СѓРґР°Р»С‘РЅРЅРѕРµ С…СЂР°РЅРёР»РёС‰Рµ.</div>
<h3>РќР°СЃС‚СЂРѕР№РєР° РџР»Р°РЅРёСЂРѕРІС‰РёРєР° Р·Р°РґР°С‡ DSM</h3>
<ol>
<li>РћС‚РєСЂРѕР№С‚Рµ <strong>DSM в†’ РџР°РЅРµР»СЊ СѓРїСЂР°РІР»РµРЅРёСЏ в†’ РџР»Р°РЅРёСЂРѕРІС‰РёРє Р·Р°РґР°С‡</strong>.</li>
<li>РќР°Р¶РјРёС‚Рµ <strong>РЎРѕР·РґР°С‚СЊ в†’ Р—Р°РїР»Р°РЅРёСЂРѕРІР°РЅРЅР°СЏ Р·Р°РґР°С‡Р° в†’ РћРїСЂРµРґРµР»С‘РЅРЅР°СЏ РїРѕР»СЊР·РѕРІР°С‚РµР»РµРј РєРѕРјР°РЅРґР°</strong>.</li>
<li>Р’РєР»Р°РґРєР° <strong>РћР±С‰РёРµ</strong>:<br>Р—Р°РґР°С‡Р°: <code>SimpleX Backup</code><br>РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ: <strong>root</strong><br>Р’РєР»СЋС‡РµРЅРѕ: вњ”</li>
<li>Р’РєР»Р°РґРєР° <strong>Р Р°СЃРїРёСЃР°РЅРёРµ</strong>:<br>Р’С‹РїРѕР»РЅСЏС‚СЊ: <strong>Р•Р¶РµРґРЅРµРІРЅРѕ</strong><br>Р’СЂРµРјСЏ: <strong>03:00</strong></li>
<li>Р’РєР»Р°РґРєР° <strong>РџР°СЂР°РјРµС‚СЂС‹ Р·Р°РґР°С‡Рё</strong>:<br>РљРѕРјР°РЅРґР°: <pre>${BASE_DIR}/simplex-backup.sh</pre></li>
<li>РќР°Р¶РјРёС‚Рµ <strong>OK</strong> РґР»СЏ СЃРѕС…СЂР°РЅРµРЅРёСЏ.</li>
</ol>
<p><strong>РџСЂРѕРІРµСЂРєР°:</strong> РІС‹РґРµР»РёС‚Рµ Р·Р°РґР°С‡Сѓ в†’ <strong>Р—Р°РїСѓСЃС‚РёС‚СЊ</strong>. Р¤Р°Р№Р» РїРѕСЏРІРёС‚СЃСЏ РІ <code>${BASE_DIR}/backups/</code>.</p>
<p class="muted">рџ’Ў РЎРєСЂРёРїС‚ Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё СѓРґР°Р»СЏРµС‚ РєРѕРїРёРё СЃС‚Р°СЂС€Рµ 14 РґРЅРµР№. Р”Р»СЏ РёР·РјРµРЅРµРЅРёСЏ СЃСЂРѕРєР° РѕС‚СЂРµРґР°РєС‚РёСЂСѓР№С‚Рµ <code>-mtime +14</code> РІ С„Р°Р№Р»Рµ <code>simplex-backup.sh</code>.</p>
<p class="muted">вљ пёЏ РҐСЂР°РЅРёС‚Рµ С…РѕС‚СЏ Р±С‹ РѕРґРЅСѓ СЂРµР·РµСЂРІРЅСѓСЋ РєРѕРїРёСЋ РЅР° РІРЅРµС€РЅРµРј РЅРѕСЃРёС‚РµР»Рµ РёР»Рё РІ РѕР±Р»Р°С‡РЅРѕРј С…СЂР°РЅРёР»РёС‰Рµ РѕС‚РґРµР»СЊРЅРѕ РѕС‚ NAS.</p>
</section>

<div class="footer">SimpleX Server В· ${MAIN_DOMAIN} В· Installer 9.4 В· $(date '+%d.%m.%Y')</div>
</div>

<div class="modal" id="qr-modal" onclick="closeQR(event)"><div class="mcont"><div class="mh"></div><div style="font-size:17px;font-weight:750" id="qr-title">QR</div><div class="qrf" id="qr-c"></div><div style="color:var(--muted);font-size:12px">РћС‚СЃРєР°РЅРёСЂСѓР№С‚Рµ СЌС‚РѕС‚ QR-РєРѕРґ РІ РїСЂРёР»РѕР¶РµРЅРёРё SimpleX Chat</div></div></div>
<div class="toast" id="toast">РЎРєРѕРїРёСЂРѕРІР°РЅРѕ</div>

<script src="qrcode.min.js"></script>
<script>
const S={smp:"${SMP_ADDRESS}",xftp:"${XFTP_ADDRESS}",turn:"${STUN_ADDR}\n${TURN_UDP}\n${TURN_TLS}"};
function toggleTheme(){const t=document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark';setTheme(t)}
function setTheme(t){document.documentElement.setAttribute('data-theme',t);localStorage.setItem('simplex-theme',t);updIco(t);document.querySelector('meta[name="theme-color"]').content=t==='dark'?'#0c0a14':'#f4f1fa'}
function updIco(t){document.getElementById('ico-sun').style.display=t==='dark'?'none':'block';document.getElementById('ico-moon').style.display=t==='dark'?'block':'none'}
setTheme(localStorage.getItem('simplex-theme')||'dark');
function copyText(x){if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(x).then(()=>toast('РЎРєРѕРїРёСЂРѕРІР°РЅРѕ'));return}const a=document.createElement('textarea');a.value=x;a.style.cssText='position:fixed;opacity:0';document.body.appendChild(a);a.select();try{document.execCommand('copy');toast('РЎРєРѕРїРёСЂРѕРІР°РЅРѕ')}catch(e){}a.remove()}
function toast(m){const t=document.getElementById('toast');t.textContent=m;t.classList.add('show');clearTimeout(t._t);t._t=setTimeout(()=>t.classList.remove('show'),1800)}
function rev(id){const b=document.getElementById(id);const s=b.querySelector('.aval');if(!b.classList.contains('rev')){const k=id==='smp-box'?'smp':'xftp';s.textContent=S[k]}b.classList.toggle('rev')}
function revT(){const b=document.getElementById('turn-box');const s=b.querySelector('.tval');if(!b.classList.contains('rev'))s.textContent=S.turn;b.classList.toggle('rev')}
function openQR(k){const m=document.getElementById('qr-modal'),c=document.getElementById('qr-c');document.getElementById('qr-title').textContent=(k==='smp'?'SMP':'XFTP')+' вЂ” QR';c.innerHTML='';new QRCode(c,{text:S[k],width:250,height:250,colorDark:'#000',colorLight:'#fff',correctLevel:QRCode.CorrectLevel.M});m.classList.add('on');document.body.style.overflow='hidden'}
function closeQR(e){const m=document.getElementById('qr-modal');if(e&&e.target!==m&&!e.target.closest('.mcont'))return;m.classList.remove('on');document.body.style.overflow=''}
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeQR()});
function translateStatus(s){var m={"running":"Р РђР‘РћРўРђР•Рў","exited":"РћРЎРўРђРќРћР’Р›Р•Рќ","dead":"РђР’РђР РРЇ","paused":"РџРђРЈР—Рђ","restarting":"РџР•Р Р•Р—РђРџРЈРЎРљ","created":"РЎРћР—Р”РђРќ","not_found":"РќР• РќРђР™Р”Р•Рќ","removing":"РЈР”РђР›РЇР•РўРЎРЇ"};return m[s]||s.toUpperCase()}
function checkStatus(){fetch('status.json?t='+Date.now()).then(function(r){if(!r.ok)throw new Error(r.status);return r.json()}).then(function(d){var map={'simplex-smp':'st-smp','simplex-xftp':'st-xftp','simplex-turn':'st-turn'};var allOk=true;for(var c in map){var el=document.getElementById(map[c]);var s=d[c]||'not_found';if(s==='running'){el.textContent='в—Џ Р РђР‘РћРўРђР•Рў';el.className='st-val run'}else{el.textContent='в—Џ '+translateStatus(s);el.className='st-val stop';allOk=false}}var ov=document.getElementById('ov-status');var od=document.getElementById('ov-dot');var ot=document.getElementById('ov-text');if(allOk){ov.className='online ok';od.className='odot ok';ot.textContent='Р’ РЎР•РўР'}else{ov.className='online err';od.className='odot err';ot.textContent='Р”Р•Р“Р РђР”РђР¦РРЇ'}}).catch(function(){var ov=document.getElementById('ov-status');var od=document.getElementById('ov-dot');var ot=document.getElementById('ov-text');ov.className='online na';od.className='odot na';ot.textContent='РќР•Рў Р”РђРќРќР«РҐ'})}
checkStatus();setInterval(checkStatus,60000);
</script>
</body>
</html>
HTMLEOF
chmod 644 "$WEB_DIR/qrsmp.html"

# --- 12a2. index.html (РРЅСЃС‚СЂСѓРєС†РёСЏ СѓСЃС‚Р°РЅРѕРІРєРё РєР»РёРµРЅС‚Р°) ---
cat > "$WEB_DIR/index.html" << INDEXEOF
<!DOCTYPE html>
<html lang="ru" data-theme="dark">
<head>
<meta charset="UTF-8">
<link rel="icon" href="favicon.ico" type="image/x-icon">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0c0a14">
<title>SimpleX Server вЂ” ${MAIN_DOMAIN}</title>
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
.toggle{position:absolute;top:1rem;right:1rem;width:36px;height:36px;border-radius:10px;border:1px solid var(--line);background:transparent;color:var(--text);cursor:pointer;display:grid;place-items:center}
.toggle svg{width:16px}
@media(max-width:400px){.platform-grid{flex-wrap:wrap}.platform-card{flex:1 1 calc(50% - .35rem);min-width:calc(50% - .35rem)}}
</style>
</head>
<body>
<button class="toggle" onclick="toggleTheme()" aria-label="РўРµРјР°">
<svg id="ico-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" style="display:none"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg>
<svg id="ico-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
</button>
<div class="container">
<div class="card">
<div class="logo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3l7 4v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V7l7-4z"/><path d="M9 12l2 2 4-4"/></svg></div>
<h1>SimpleX Server</h1>
<p class="sub">РџСЂРёРІР°С‚РЅС‹Р№ РјРµСЃСЃРµРЅРґР¶РµСЂ В· ${MAIN_DOMAIN}</p>
<div class="info">
<strong>рџ”’ Рћ СЃРµСЂРІРёСЃРµ</strong>
Р­С‚РѕС‚ СЃРµСЂРІРµСЂ РѕР±РµСЃРїРµС‡РёРІР°РµС‚ СЂР°Р±РѕС‚Сѓ РїСЂРёРІР°С‚РЅРѕРіРѕ РјРµСЃСЃРµРЅРґР¶РµСЂР° SimpleX Chat.
Р’СЃРµ СЃРѕРѕР±С‰РµРЅРёСЏ Рё С„Р°Р№Р»С‹ РїРµСЂРµРґР°СЋС‚СЃСЏ РїРѕ Р·Р°С€РёС„СЂРѕРІР°РЅРЅС‹Рј РєР°РЅР°Р»Р°Рј.
РЎРµСЂРІРµСЂ РЅРµ РёРјРµРµС‚ РґРѕСЃС‚СѓРїР° Рє СЃРѕРґРµСЂР¶РёРјРѕРјСѓ РїРµСЂРµРїРёСЃРєРё.
</div>
<div class="section-title">рџ“± РЈСЃС‚Р°РЅРѕРІРєР° РЅР° СЃРјР°СЂС‚С„РѕРЅ</div>
<div class="platform-grid">
<a href="https://apps.apple.com/app/simplex-chat/id1605771084" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">рџЌЋ</span>iOS</a>
<a href="https://play.google.com/store/apps/details?id=chat.simplex.app" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">рџ¤–</span>Android</a>
<a href="https://f-droid.org/packages/chat.simplex.app/" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">рџ“¦</span>F-Droid</a>
<a href="https://github.com/simplex-chat/simplex-chat/releases/latest" target="_blank" rel="noopener" class="platform-card"><span class="platform-icon">рџ’»</span>Desktop</a>
</div>
<div class="qr-section">
<p>рџ“· РР»Рё РѕС‚СЃРєР°РЅРёСЂСѓР№С‚Рµ QR-РєРѕРґ:</p>
<div id="download-qr"></div>
<p class="qr-hint">Р’РµРґС‘С‚ РЅР° simplex.chat</p>
</div>
<a href="qrsmp.html" class="btn">
<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
РџР°РЅРµР»СЊ СѓРїСЂР°РІР»РµРЅРёСЏ
</a>
<div class="footer">SimpleX Installer 9.4 В· ${MAIN_DOMAIN}</div>
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
success "index.html СЃРѕР·РґР°РЅ."

# РћР±РЅРѕРІР»РµРЅРёРµ РІРµСЂСЃРёРё РІ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РµРј index.html
if [ -f "$WEB_DIR/index.html" ]; then
    sed -i -E 's/Installer[[:space:]]+9\.[0-9]+/Installer 9.4/g; s/\bv9\.[0-9]+\b/v9.4/g' "$WEB_DIR/index.html"
    chmod 644 "$WEB_DIR/index.html"
    success "Р’РµСЂСЃРёСЏ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РµРіРѕ index.html РѕР±РЅРѕРІР»РµРЅР° РґРѕ v9.4."
fi

# --- 12b. .htaccess ---
cat > "$WEB_DIR/.htaccess" << EOF
<Files "qrsmp.html">
AuthType Basic
AuthName "SimpleX Control вЂ” ${MAIN_DOMAIN}"
AuthUserFile ${WEB_DIR}/.htpasswd
Require valid-user
</Files>
<Files "status.json">
AuthType Basic
AuthName "SimpleX Control вЂ” ${MAIN_DOMAIN}"
AuthUserFile ${WEB_DIR}/.htpasswd
Require valid-user
</Files>
EOF
chmod 644 "$WEB_DIR/.htaccess"

# --- 12c. .htpasswd ---
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
    warn ".htpasswd СѓР¶Рµ СЃСѓС‰РµСЃС‚РІСѓРµС‚. РџР°СЂРѕР»СЊ РЅРµ РёР·РјРµРЅС‘РЅ."
    WEB_PASS="(РёСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёР№ РїР°СЂРѕР»СЊ)"
fi

if [ -n "$WEB_GROUP" ]; then
    chown root:"$WEB_GROUP" "$WEB_DIR/.htpasswd"
    chmod 640 "$WEB_DIR/.htpasswd"
    success ".htpasswd Р·Р°С‰РёС‰С‘РЅ: root:${WEB_GROUP}, РїСЂР°РІР° 640."
else
    warn "Р“СЂСѓРїРїР° http РЅРµ РЅР°Р№РґРµРЅР°. РСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ chmod 644 РґР»СЏ .htpasswd."
    chown root:root "$WEB_DIR/.htpasswd"
    chmod 644 "$WEB_DIR/.htpasswd"
fi

if [ -n "${WEB_PASS:-}" ] && [ "$WEB_PASS" != "(РёСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёР№ РїР°СЂРѕР»СЊ)" ]; then
    success "Р’РµР±-РїР°СЂРѕР»СЊ СЃРѕР·РґР°РЅ: admin / ${WEB_PASS}"
    warn "РЎРѕС…СЂР°РЅРёС‚Рµ СЌС‚РѕС‚ РїР°СЂРѕР»СЊ! РћРЅ РїРѕРєР°Р·С‹РІР°РµС‚СЃСЏ С‚РѕР»СЊРєРѕ РѕРґРёРЅ СЂР°Р·."
fi
success "Р’РµР±-С„Р°Р№Р»С‹ СЃРѕР·РґР°РЅС‹ РІ $WEB_DIR"

# ==============================================================================
# 13. РћРўР§РЃРў
# ==============================================================================
RESULT_FILE="$BASE_DIR/CONNECTION_DETAILS.txt"
cat > "$RESULT_FILE" << EOF
================================================================
SIMPLEX CHAT SERVER РЈРЎРџР•РЁРќРћ Р РђР—Р’Р•Р РќРЈРў (v9.4)
================================================================
Р”Р°С‚Р°: $(date)
Р”РѕРјРµРЅ: $MAIN_DOMAIN
Р’РЅРµС€РЅРёР№ IP: $EXTERNAL_IP
Р’РЅСѓС‚СЂРµРЅРЅРёР№ IP: $INTERNAL_IP

рџ”— РђР”Р Р•РЎРђ Р”Р›РЇ РљР›РР•РќРўРђ:
SMP:  ${SMP_ADDRESS}
XFTP: ${XFTP_ADDRESS}

рџ“ћ TURN / STUN:
${STUN_ADDR}
${TURN_UDP}
${TURN_TLS}

рџЊђ РџРђРќР•Р›Р¬ РЈРџР РђР’Р›Р•РќРРЇ:
URL: http://info.smp.${MAIN_DOMAIN}
Р›РѕРіРёРЅ: admin
РџР°СЂРѕР»СЊ: ${WEB_PASS:-СЃРј. СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёР№ .htpasswd}

рџ“Ѓ Р¤РђР™Р›Р«:
РљРѕРЅС„РёРіСѓСЂР°С†РёСЏ: $BASE_DIR/.env
Р’РµР±-СЃС‚СЂР°РЅРёС†С‹: $WEB_DIR/
Backup: $BACKUP_SCRIPT
РЎС‚Р°С‚СѓСЃ: $BASE_DIR/status-update.sh

вљ пёЏ Р”РђР›Р¬РќР•Р™РЁРР• Р”Р•Р™РЎРўР’РРЇ:
1. РќР°СЃС‚СЂРѕР№С‚Рµ Web Station: РєРѕСЂРµРЅСЊ в†’ $WEB_DIR
2. РџСЂРѕР±СЂРѕСЃ РїРѕСЂС‚РѕРІ: SMP 5223, 5224, XFTP 7788, TURN 3478, 5349, 49152-65535
3. DNS A-Р·Р°РїРёСЃРё: smp, files, turn в†’ $EXTERNAL_IP
4. РћС‚РєСЂРѕР№С‚Рµ РїРѕСЂС‚С‹ РІ Р‘СЂР°РЅРґРјР°СѓСЌСЂРµ DSM
================================================================
EOF

echo ""
cat "$RESULT_FILE"
echo ""
info "РЎС‚Р°С‚СѓСЃ РєРѕРЅС‚РµР№РЅРµСЂРѕРІ:"
$COMPOSE_CMD ps
echo ""
success "РЈСЃС‚Р°РЅРѕРІРєР° Р·Р°РІРµСЂС€РµРЅР°."
info "РќР°СЃС‚СЂРѕР№С‚Рµ Web Station РґР»СЏ РґРѕСЃС‚СѓРїР° Рє РїР°РЅРµР»Рё СѓРїСЂР°РІР»РµРЅРёСЏ."
