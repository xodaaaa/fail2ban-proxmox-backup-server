#!/bin/bash
# Script completo de instalacion y configuracion de fail2ban para Proxmox Backup Server
# con notificaciones Telegram incluidas por defecto
# Uso: ./install.sh [--dry-run] [--no-telegram] [--uninstall]

set -euo pipefail

# --- Configuracion -----------------------------------------------------------
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
FILTER_SRC="$REPO_DIR/filter.d/proxmox-backup-server.conf"
JAIL_SRC="$REPO_DIR/jail.d/proxmox-backup-server.conf"
ACTION_SRC="$REPO_DIR/action.d/telegram.conf"
TELEGRAM_DIR_SRC="$REPO_DIR/telegram"

F2B_DIR="/etc/fail2ban"
FILTER_DST="$F2B_DIR/filter.d/proxmox-backup-server.conf"
JAIL_DST="$F2B_DIR/jail.d/proxmox-backup-server.conf"
ACTION_DST="$F2B_DIR/action.d/telegram.conf"
TELEGRAM_DIR_DST="$F2B_DIR/telegram"
TELEGRAM_CONFIG="$TELEGRAM_DIR_DST/config.sh"

PBS_AUTH_LOG="/var/log/proxmox-backup/api/auth.log"
F2B_LOG="/var/log/fail2ban.log"

DRY_RUN=false
NO_TELEGRAM=false
UNINSTALL=false

# --- Argumentos --------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=true; shift ;;
        --no-telegram)  NO_TELEGRAM=true; shift ;;
        --uninstall)    UNINSTALL=true; shift ;;
        --help|-h)
            echo "Uso: $0 [--dry-run] [--no-telegram] [--uninstall]"
            echo "  --dry-run      Simula la instalacion sin hacer cambios"
            echo "  --no-telegram  Instala fail2ban sin el bot de Telegram"
            echo "  --uninstall    Elimina todas las configuraciones instaladas"
            exit 0
            ;;
        *) echo "Opcion desconocida: $1"; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then
        echo "  (simulado) $*"
    else
        "$@"
    fi
}

# --- Desinstalacion ----------------------------------------------------------
if $UNINSTALL; then
    echo "=== Desinstalando configuraciones de fail2ban para PBS ==="
    for f in "$FILTER_DST" "$JAIL_DST" "$ACTION_DST"; do
        if [ -f "$f" ]; then
            run rm -f "$f"
            echo "  Eliminado: $f"
        fi
    done
    if [ -d "$TELEGRAM_DIR_DST" ]; then
        run rm -rf "$TELEGRAM_DIR_DST"
        echo "  Eliminado: $TELEGRAM_DIR_DST"
    fi
    if ! $DRY_RUN; then
        crontab -l 2>/dev/null | grep -v "fail2ban/telegram" | crontab - || true
        echo "  Entradas cron eliminadas"
    fi
    run systemctl restart fail2ban.service 2>/dev/null || true
    echo "=== Desinstalacion completada ==="
    exit 0
fi

# --- Banner ------------------------------------------------------------------
cat << "BANNER"
╔══════════════════════════════════════════════════════════╗
║  fail2ban - Proxmox Backup Server                       ║
║  Instalacion y configuracion automatica                 ║
╚══════════════════════════════════════════════════════════╝
BANNER

# --- Verificaciones previas -------------------------------------------------
if [ "$EUID" -ne 0 ] && ! $DRY_RUN; then
    echo "Este script debe ejecutarse como root."
    exit 1
fi

if [ ! -f "$FILTER_SRC" ]; then
    echo "Error: No se encuentra $FILTER_SRC"
    echo "  Ejecuta este script desde la raiz del repositorio."
    exit 1
fi

# --- 1. Instalar dependencias ------------------------------------------------
echo ""
echo "[1/7] Instalando dependencias del sistema..."
if command -v apt &>/dev/null; then
    run apt update -y
    run apt install -y fail2ban iptables curl
elif command -v dnf &>/dev/null; then
    run dnf install -y fail2ban iptables curl
elif command -v yum &>/dev/null; then
    run yum install -y epel-release
    run yum install -y fail2ban iptables curl
else
    echo "No se detecto un gestor de paquetes compatible (apt/dnf/yum)."
    echo "Asegurate de tener instalado: fail2ban, iptables, curl"
fi

# --- 2. Crear directorios ----------------------------------------------------
echo ""
echo "[2/7] Creando directorios..."
run mkdir -p "$F2B_DIR/filter.d" "$F2B_DIR/jail.d" "$F2B_DIR/action.d"

# --- 3. Copiar configuraciones -----------------------------------------------
echo ""
echo "[3/7] Copiando archivos de configuracion..."

run cp "$FILTER_SRC" "$FILTER_DST"
echo "   Filter:  $FILTER_DST"

run cp "$JAIL_SRC" "$JAIL_DST"
echo "   Jail:    $JAIL_DST"

# --- 4. Configurar Telegram --------------------------------------------------
INSTALL_TELEGRAM=false
if ! $NO_TELEGRAM; then
    INSTALL_TELEGRAM=true
    run mkdir -p "$TELEGRAM_DIR_DST"

    echo ""
    echo "[4/7] Configuracion del bot de Telegram"
    echo "--------------------------------------------------"

    while [ -z "${BOT_TOKEN:-}" ]; do
        read -r -p "  Token del bot (de @BotFather): " BOT_TOKEN
    done

    echo "  Como deseas obtener el Chat ID?"
    echo "    [1] Automatico - Envia /start al bot y lo detecto solo"
    echo "    [2] Manual - Ingresas el Chat ID directamente"
    read -r -p "  Opcion (1/2) [1]: " id_option

    CHAT_ID=""
    if [[ "${id_option:-1}" != "2" ]]; then
        echo ""
        echo "  Envia /start al bot en Telegram para detectar tu Chat ID..."
        if [ -f "$REPO_DIR/telegram/get-chat-id.sh" ]; then
            run cp "$REPO_DIR/telegram/get-chat-id.sh" "$TELEGRAM_DIR_DST/"
            run chmod +x "$TELEGRAM_DIR_DST/get-chat-id.sh"
        fi
        if ! $DRY_RUN; then
            cat > "$TELEGRAM_CONFIG" << EOF
#!/bin/bash
TELEGRAM_BOT_TOKEN="${BOT_TOKEN}"
TELEGRAM_CHAT_ID=""
PBS_AUTH_LOG="${PBS_AUTH_LOG}"
FAIL2BAN_LOG="${F2B_LOG}"
EOF
            chmod 600 "$TELEGRAM_CONFIG"
            DETECTED=$("$TELEGRAM_DIR_DST/get-chat-id.sh" --config "$TELEGRAM_CONFIG" 2>&1) || true
            echo "$DETECTED"
            source "$TELEGRAM_CONFIG" 2>/dev/null || true
            CHAT_ID="${TELEGRAM_CHAT_ID:-}"
        fi
    fi

    if [ -z "${CHAT_ID:-}" ]; then
        while [ -z "$CHAT_ID" ]; do
            read -r -p "  Chat ID (tu usuario o grupo): " CHAT_ID
        done
    fi

    if ! $DRY_RUN; then
        cat > "$TELEGRAM_CONFIG" << EOF
#!/bin/bash
TELEGRAM_BOT_TOKEN="${BOT_TOKEN}"
TELEGRAM_CHAT_ID="${CHAT_ID}"
PBS_AUTH_LOG="${PBS_AUTH_LOG}"
FAIL2BAN_LOG="${F2B_LOG}"
EOF
        chmod 600 "$TELEGRAM_CONFIG"
        echo "   Config:  $TELEGRAM_CONFIG"
    fi

    if [ -d "$TELEGRAM_DIR_SRC" ]; then
        for script in notify.sh status.sh alerts.sh weekly-report.sh; do
            if [ -f "$TELEGRAM_DIR_SRC/$script" ]; then
                run cp "$TELEGRAM_DIR_SRC/$script" "$TELEGRAM_DIR_DST/"
            fi
        done
        run chmod +x "$TELEGRAM_DIR_DST"/*.sh
        echo "   Scripts: $TELEGRAM_DIR_DST"
    fi

    if [ -f "$ACTION_SRC" ]; then
        run cp "$ACTION_SRC" "$ACTION_DST"
        echo "   Action:  $ACTION_DST"
    fi

    echo ""
    echo "   Probando conexion con Telegram..."
    if ! $DRY_RUN; then
        TEST_MSG=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=*fail2ban PBS* - Conexion establecida correctamente" \
            -d "parse_mode=Markdown" 2>&1)
        if echo "$TEST_MSG" | grep -q '"ok":true'; then
            echo "   Mensaje de prueba enviado correctamente a Telegram."
        else
            echo "   No se pudo enviar el mensaje de prueba."
            echo "   Error: $(echo "$TEST_MSG" | grep -o '"description":"[^"]*"' | head -1)"
        fi
    fi

    # --- 5. Configurar cron --------------------------------------------------
    echo ""
    echo "[5/7] Configuracion de tareas programadas (cron)"
    echo "------------------------------------------------"
    read -r -p "  Configurar reportes periodicos por cron? (S/n): " cron_resp
    if [[ ! "$cron_resp" =~ ^[nN]$ ]]; then
        if ! $DRY_RUN; then
            (crontab -l 2>/dev/null | grep -v "fail2ban/telegram"; \
             echo "*/30 * * * * $TELEGRAM_DIR_DST/status.sh"; \
             echo "*/15 * * * * $TELEGRAM_DIR_DST/alerts.sh"; \
             echo "0 9 * * 1 $TELEGRAM_DIR_DST/weekly-report.sh") | crontab - || true
            echo "   Tareas cron instaladas:"
        fi
        echo "      status.sh       cada 30 min (estado de jails)"
        echo "      alerts.sh       cada 15 min (analisis de seguridad)"
        echo "      weekly-report   cada lunes 9 AM (informe semanal)"
    fi
else
    # Sin Telegram: copiar jail sin action de Telegram
    echo ""
    echo "[4/7] Telegram omitido. El jail se instalara sin action de Telegram."
    echo "[5/7] Cron omitido."
fi

# --- 6. Verificar log de autenticacion ---------------------------------------
echo ""
echo "[6/7] Verificando log de autenticacion..."
if $DRY_RUN; then
    echo "   (simulado) Verificacion de $PBS_AUTH_LOG"
else
    if [ -f "$PBS_AUTH_LOG" ]; then
        echo "   Log encontrado: $PBS_AUTH_LOG"
        echo "   Ultimas lineas:"
        tail -3 "$PBS_AUTH_LOG" | sed 's/^/   /'
    else
        echo "   No se encuentra $PBS_AUTH_LOG"
        echo "   Esto es normal si PBS aun no ha generado eventos de autenticacion."
    fi
fi

# --- 7. Reiniciar fail2ban ---------------------------------------------------
echo ""
echo "[7/7] Reiniciando servicio fail2ban..."
if $DRY_RUN; then
    echo "   (simulado) systemctl restart fail2ban.service"
else
    run systemctl restart fail2ban.service 2>/dev/null || {
        echo "   No se pudo reiniciar fail2ban. Esta instalado?"
    }
    sleep 2
fi

# --- Verificacion final ------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "   Instalacion completada"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "   Comandos utiles:"
echo "   fail2ban-client status"
echo "   fail2ban-client status proxmox-backup-server"
echo "   tail -f /var/log/fail2ban.log"
echo ""

if $INSTALL_TELEGRAM; then
    echo "   Notificaciones Telegram activas."
    echo "   Recibiras alertas de baneos en tiempo real."
fi

echo ""
if ! $DRY_RUN; then
    echo "Para verificar el estado ahora:"
    fail2ban-client status proxmox-backup-server 2>/dev/null | head -10 || echo "(fail2ban no esta corriendo)"
fi
echo ""
