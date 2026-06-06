#!/bin/bash
# Telegram notification for fail2ban ban/unban events
# Usage: /etc/fail2ban/telegram/notify.sh <action> <ip> [jail]
#
# Install as fail2ban action:
#   [proxmox-backup-server]
#   action = %(action_)s
#           telegram[actionstart, actionstop, actionban, actionunban]
#
# Or call directly from fail2ban action.d/telegram.conf

set -euo pipefail

CONFIG="/etc/fail2ban/telegram/config.sh"

if [ ! -f "$CONFIG" ]; then
    logger -t fail2ban-telegram "Config not found: $CONFIG"
    exit 1
fi
source "$CONFIG"

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    logger -t fail2ban-telegram "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set"
    exit 1
fi

ACTION="${1:-}"
IP="${2:-}"
JAIL="${3:-proxmox-backup-server}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        -o /dev/null -w "%{http_code}" | grep -q 200 || logger -t fail2ban-telegram "Failed to send message"
}

case "$ACTION" in
    start)
        send_telegram "🟢 *fail2ban iniciado*
Jail: \`$JAIL\"
Servidor: $(hostname)
$TIMESTAMP"
        ;;
    stop)
        send_telegram "🔴 *fail2ban detenido*
Jail: \`$JAIL\"
Servidor: $(hostname)
$TIMESTAMP"
        ;;
    ban)
        # Gather info about the banned IP
        COUNTRY=$(curl -s "http://ip-api.com/json/${IP}?fields=country,isp,org" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d.get(\"country\",\"?\")} - {d.get(\"isp\",\"?\")}')" 2>/dev/null || echo "Desconocido")
        send_telegram "🚫 *IP BANEADA*
IP: \`$IP\`
Jail: \`$JAIL\`
Origen: ${COUNTRY}
Servidor: $(hostname)
$TIMESTAMP"
        ;;
    unban)
        send_telegram "✅ *IP DESBANEADA*
IP: \`$IP\`
Jail: \`$JAIL\"
Servidor: $(hostname)
$TIMESTAMP"
        ;;
    *)
        echo "Usage: $0 {start|stop|ban|unban} <ip> [jail]"
        exit 1
        ;;
esac
