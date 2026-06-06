#!/bin/bash
# Telegram weekly security report for Proxmox Backup Server
# Run via cron once a week:
# 0 9 * * 1 /etc/fail2ban/telegram/weekly-report.sh

set -euo pipefail

CONFIG="/etc/fail2ban/telegram/config.sh"
[ -f "$CONFIG" ] && source "$CONFIG" || { logger -t fail2ban-telegram "Config not found"; exit 1; }

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    logger -t fail2ban-telegram "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set"
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SINCE="7 days ago"
JAIL="${1:-proxmox-backup-server}"

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${1}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        -o /dev/null || logger -t fail2ban-telegram "Failed to send weekly report"
}

# Format date for log filtering
SINCE_DATE=$(date -d "$SINCE" '+%Y-%m-%d')

# Fail2ban stats
FAIL2BAN_STATUS=$(fail2ban-client status "$JAIL" 2>/dev/null || echo "")
TOTAL_BANNED=$(echo "$FAIL2BAN_STATUS" | grep "Total banned" | awk '{print $NF}')
TOTAL_FAILED=$(echo "$FAIL2BAN_STATUS" | grep "Total failed" | awk '{print $NF}')

# Weekly auth failures from PBS log
WEEKLY_FAILURES=$(grep -c "authentication failure" "$PBS_AUTH_LOG" 2>/dev/null || echo 0)

# Weekly bans from fail2ban log
WEEKLY_BANS=$(grep "$JAIL.*Ban" "$FAIL2BAN_LOG" 2>/dev/null | wc -l || echo 0)

# Unique IPs banned this week
UNIQUE_IPS=$(grep "$JAIL.*Ban" "$FAIL2BAN_LOG" 2>/dev/null | grep -oP 'IP \K[0-9a-f:.]*' | sort -u | wc -l || echo 0)

# Most banned IP this week
TOP_BANNED=$(grep "$JAIL.*Ban" "$FAIL2BAN_LOG" 2>/dev/null | grep -oP 'IP \K[0-9a-f:.]*' | sort | uniq -c | sort -rn | head -5)

# Top 5 attacking IPs from auth log
TOP_ATTACKERS=$(awk -v d="$SINCE_DATE" '$0 ~ d,0' "$PBS_AUTH_LOG" 2>/dev/null | grep "authentication failure" | grep -oP 'rhost=\[\K[^\]]+' | sort | uniq -c | sort -rn | head -5)

# Top 5 targeted users
TOP_USERS=$(awk -v d="$SINCE_DATE" '$0 ~ d,0' "$PBS_AUTH_LOG" 2>/dev/null | grep "authentication failure" | grep -oP 'user=\K\S+' | sort | uniq -c | sort -rn | head -5)

# Currently banned IPs
CURRENT_BANNED=$(fail2ban-client status "$JAIL" 2>/dev/null | grep "Banned IP list" -A 99 | tail -n +2 | tr -d ' ' | paste -sd, - || echo "Ninguna")

MESSAGE="📈 *Informe Semanal - PBS fail2ban*
📅 ${SINCE_DATE} → $(date '+%Y-%m-%d')

━━━━━━━━━━━━━━━━━━━
*📊 Resumen General*
┌ Fallos de autenticación: ${WEEKLY_FAILURES}
├ Baneos esta semana: ${WEEKLY_BANS}
├ IPs únicas baneadas: ${UNIQUE_IPS}
├ Baneados totales (histórico): ${TOTAL_BANNED}
└ Fallos totales (histórico): ${TOTAL_FAILED}

━━━━━━━━━━━━━━━━━━━
*🔥 Top IPs atacantes*
${TOP_ATTACKERS:-(sin datos)}

*👤 Top usuarios atacados*
${TOP_USERS:-(sin datos)}

*🚫 IPs más baneadas*
${TOP_BANNED:-(sin datos)}

━━━━━━━━━━━━━━━━━━━
*🔒 IPs actualmente baneadas*
${CURRENT_BANNED}

🖥 $(hostname)
🕐 ${TIMESTAMP}
_Próximo reporte: $(date -d '+7 days' '+%Y-%m-%d')_"

send_telegram "$MESSAGE"
