#!/bin/bash
# Telegram status reporter for fail2ban jails
# Run via cron every 30-60 minutes:
# */30 * * * * /etc/fail2ban/telegram/status.sh

set -euo pipefail

CONFIG="/etc/fail2ban/telegram/config.sh"
[ -f "$CONFIG" ] && source "$CONFIG" || { logger -t fail2ban-telegram "Config not found"; exit 1; }

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    logger -t fail2ban-telegram "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set"
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
JAIL="${1:-proxmox-backup-server}"

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${1}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        -o /dev/null || logger -t fail2ban-telegram "Failed to send status"
}

get_jail_status() {
    local jail_name="$1"
    local status
    status=$(fail2ban-client status "$jail_name" 2>/dev/null) || return 1

    local banned total_banned failed total_failed banned_ips
    banned=$(echo "$status" | grep "Currently banned" | awk '{print $NF}')
    total_banned=$(echo "$status" | grep "Total banned" | awk '{print $NF}')
    failed=$(echo "$status" | grep "Currently failed" | awk '{print $NF}')
    total_failed=$(echo "$status" | grep "Total failed" | awk '{print $NF}')

    # Extract banned IPs
    banned_ips=$(echo "$status" | sed -n '/Banned IP list/,//p' | tail -n +2 | tr -d ' ' | paste -sd, -)
    [ -z "$banned_ips" ] && banned_ips="Ninguna"

    # System info
    local uptime load
    uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
    load=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "N/A")

    cat <<EOF
📊 *Estado fail2ban - ${jail_name}*
┌ Baneados actuales: ${banned}
├ Baneados totales: ${total_banned}
├ Fallos actuales: ${failed}
└ Fallos totales: ${total_failed}

*IPs baneadas:* ${banned_ips}

🖥 *Servidor:* $(hostname)
⏱ *Uptime:* ${uptime}
📈 *Load:* ${load}
🕐 ${TIMESTAMP}
EOF
}

message=$(get_jail_status "$JAIL") || message="⚠️ *Error:* No se pudo obtener estado de la jail \`$JAIL\`"
send_telegram "$message"
