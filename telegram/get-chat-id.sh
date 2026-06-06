#!/bin/bash
# Utilidad para obtener el Chat ID de Telegram automaticamente
# Envia /start al bot y este script detecta tu Chat ID
#
# Uso: ./telegram/get-chat-id.sh <BOT_TOKEN>
#   o: ./telegram/get-chat-id.sh --config /etc/fail2ban/telegram/config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=""

# Verificar dependencias
for cmd in curl python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd no esta instalado."
        exit 1
    fi
done

# Parsear argumentos
if [[ "${1:-}" == "--config" && -n "${2:-}" ]]; then
    CONFIG_FILE="$2"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo "Error: No se encuentra $CONFIG_FILE"
        exit 1
    fi
elif [ -n "${1:-}" ] && [[ "$1" != --* ]]; then
    TELEGRAM_BOT_TOKEN="$1"
elif [ -f "/etc/fail2ban/telegram/config.sh" ]; then
    source "/etc/fail2ban/telegram/config.sh"
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    read -r -p "Token del bot (de @BotFather): " TELEGRAM_BOT_TOKEN
fi

API_BASE="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Obteniendo Chat ID de Telegram                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "1. Abre Telegram y busca tu bot."
echo "2. Envia el comando /start a tu bot."
echo ""
echo "Esperando mensaje..."

LAST_ID=0

# Intentar obtener el último update_id para no procesar mensajes viejos
INITIAL=$(curl -s "${API_BASE}/getUpdates?offset=-1&timeout=5" 2>/dev/null || echo '{"ok":true,"result":[]}')
if echo "$INITIAL" | grep -q '"ok":true'; then
    LAST_ID=$(echo "$INITIAL" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['result'][-1]['update_id']) if r['result'] else print(0)" 2>/dev/null || echo "0")
fi

OFFSET=$((LAST_ID + 1))

for i in $(seq 1 30); do
    RESPONSE=$(curl -s "${API_BASE}/getUpdates?offset=${OFFSET}&timeout=10" 2>/dev/null)

    if echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if not data.get('ok'): sys.exit(1)
for update in data.get('result', []):
    msg = update.get('message', {})
    text = msg.get('text', '')
    chat = msg.get('chat', {})
    chat_id = chat.get('id')
    chat_type = chat.get('type', '')
    first_name = chat.get('first_name', '')
    username = chat.get('username', '')
    if chat_id:
        print(f'{chat_id}|{chat_type}|{first_name}|{username}|{text}')
        sys.exit(0)
sys.exit(2)
" 2>/dev/null; then
        RESULT=$(echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for update in data.get('result', []):
    msg = update.get('message', {})
    text = msg.get('text', '')
    chat = msg.get('chat', {})
    chat_id = chat.get('id')
    chat_type = chat.get('type', '')
    first_name = chat.get('first_name', '')
    username = chat.get('username', '')
    if chat_id:
        print(f'{chat_id}|{chat_type}|{first_name}|{username}|{text}')
        break
" 2>/dev/null)

        CHAT_ID=$(echo "$RESULT" | cut -d'|' -f1)
        CHAT_TYPE=$(echo "$RESULT" | cut -d'|' -f2)
        FIRST_NAME=$(echo "$RESULT" | cut -d'|' -f3)
        USERNAME=$(echo "$RESULT" | cut -d'|' -f4)
        MSG_TEXT=$(echo "$RESULT" | cut -d'|' -f5)

        echo ""
        echo "Chat detectado!"
        echo "  Chat ID:     $CHAT_ID"
        echo "  Tipo:        $CHAT_TYPE"
        echo "  Nombre:      $FIRST_NAME"
        [ -n "$USERNAME" ] && echo "  Usuario:     @$USERNAME"
        echo "  Mensaje:     $MSG_TEXT"
        echo ""

        # Guardar en config
        if [ -n "$CONFIG_FILE" ] || [ -f "/etc/fail2ban/telegram/config.sh" ]; then
            TARGET="${CONFIG_FILE:-/etc/fail2ban/telegram/config.sh}"
            if [ -w "$TARGET" ] || [ ! -f "$TARGET" ]; then
                sed -i "s/^TELEGRAM_CHAT_ID=.*/TELEGRAM_CHAT_ID=\"${CHAT_ID}\"/" "$TARGET" 2>/dev/null || true
                echo "Chat ID guardado en: $TARGET"
            fi
        fi

        # Enviar confirmacion al chat
        USER_DISPLAY="${FIRST_NAME} (${USERNAME:-sin usuario})"
        curl -s -X POST "${API_BASE}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=*fail2ban PBS* - Chat ID configurado: \`${CHAT_ID}\`

🤖 Recibiras notificaciones de seguridad de tu Proxmox Backup Server.

*Resumen de notificaciones:*" \
            -d "parse_mode=Markdown" \
            -d "disable_web_page_preview=true" \
            -o /dev/null

        # Enviar mensaje detallado
        sleep 1
        curl -s -X POST "${API_BASE}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=🚫 *Baneos* - cuando una IP sea bloqueada
📊 *Estado* - cada 30 min (reporte de jails)
🔍 *Alertas* - deteccion de patrones de ataque
📈 *Informe semanal* - estadisticas cada lunes

_Configurado el $(date '+%d/%m/%Y %H:%M')_" \
            -d "parse_mode=Markdown" \
            -d "disable_web_page_preview=true" \
            -o /dev/null

        echo "Mensaje de confirmacion enviado a Telegram."
        exit 0
    fi

    echo -n "."
    sleep 2
done

echo ""
echo "No se recibio ningun mensaje en 60 segundos."
echo "Asegurate de enviar /start al bot e intenta de nuevo."
exit 1
