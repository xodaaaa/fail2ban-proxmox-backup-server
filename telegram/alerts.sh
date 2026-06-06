#!/bin/bash
# Telegram security alerts - analyzes PBS auth logs for patterns and anomalies
# Run via cron every 15-30 minutes:
# */15 * * * * /etc/fail2ban/telegram/alerts.sh

set -euo pipefail

CONFIG="/etc/fail2ban/telegram/config.sh"
[ -f "$CONFIG" ] && source "$CONFIG" || { logger -t fail2ban-telegram "Config not found"; exit 1; }

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    logger -t fail2ban-telegram "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set"
    exit 1
fi

SINCE="${1:-30m}"  # Analyze last 30 minutes by default
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ALERT_FILE="/tmp/fail2ban-telegram-last-alert"

send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${1}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        -o /dev/null || logger -t fail2ban-telegram "Failed to send alert"
}

# Check if auth log exists and is readable
if [ ! -r "$PBS_AUTH_LOG" ]; then
    logger -t fail2ban-telegram "Cannot read $PBS_AUTH_LOG"
    exit 1
fi

# Get recent auth failures (last N minutes)
RECENT_FAILURES=$(awk -v d="$(date -d "$SINCE" '+%Y-%m-%dT%H:%M:%S')" '$0 >= d' "$PBS_AUTH_LOG" 2>/dev/null | grep "authentication failure" || true)

# Count total failures
FAILURE_COUNT=$(echo "$RECENT_FAILURES" | grep -c . || echo 0)

# If no recent failures, skip (unless forced)
if [ "$FAILURE_COUNT" -eq 0 ]; then
    exit 0
fi

# Check if we already alerted for these (dedup)
LAST_ALERT=$(cat "$ALERT_FILE" 2>/dev/null || echo "0")
NOW_EPOCH=$(date +%s)
if [ $((NOW_EPOCH - LAST_ALERT)) -lt 300 ]; then
    exit 0  # Don't alert more than once every 5 minutes
fi

# Top attacking IPs
TOP_IPS=$(echo "$RECENT_FAILURES" | grep -oP 'rhost=\[\K[^\]]+' | sort | uniq -c | sort -rn | head -10)

# Top targeted users
TOP_USERS=$(echo "$RECENT_FAILURES" | grep -oP 'user=\K\S+' | sort | uniq -c | sort -rn | head -10)

# Error type distribution
ERROR_TYPES=$(echo "$RECENT_FAILURES" | grep -oP 'msg=\K.+' | sort | uniq -c | sort -rn | head -5)

# Detect brute force patterns (same IP, multiple users)
AGGRESSIVE_IPS=$(echo "$RECENT_FAILURES" | grep -oP 'rhost=\[\K[^\]]+' | sort | uniq -c | sort -rn | awk '$1 >= 10 {print $2 " (" $1 " intentos)"}' | head -5)

# Detect credential stuffing (same user, many IPs)
TARGETED_USERS=$(echo "$RECENT_FAILURES" | grep -oP 'user=\K\S+' | sort | uniq -c | sort -rn | awk '$1 >= 5 {print $2 " (" $1 " intentos)"}' | head -5)

# Build message
MESSAGE="🔍 *Alerta de Seguridad - PBS*
*Período:* Últimos ${SINCE}
*Total de fallos:* ${FAILURE_COUNT}

*🔥 IPs más activas:*
${TOP_IPS:-(sin datos)}

*👤 Usuarios más atacados:*
${TOP_USERS:-(sin datos)}

*📋 Tipos de error:*
${ERROR_TYPES:-(sin datos)}"

if [ -n "$AGGRESSIVE_IPS" ]; then
    MESSAGE+="

*⚠️ Ataque de fuerza bruta detectado:*
${AGGRESSIVE_IPS}"
fi

if [ -n "$TARGETED_USERS" ]; then
    MESSAGE+="

*🎯 Credential stuffing detectado:*
${TARGETED_USERS}"
fi

MESSAGE+="

🕐 ${TIMESTAMP}"

send_telegram "$MESSAGE"
echo "$NOW_EPOCH" > "$ALERT_FILE"
