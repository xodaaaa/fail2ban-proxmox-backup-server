#!/bin/bash
# Install fail2ban configuration for Proxmox Backup Server
# Usage: ./install.sh [--dry-run]

set -euo pipefail

FILTER_SRC="filter.d/proxmox-backup-server.conf"
JAIL_SRC="jail.d/proxmox-backup-server.conf"
FILTER_DST="/etc/fail2ban/filter.d/proxmox-backup-server.conf"
JAIL_DST="/etc/fail2ban/jail.d/proxmox-backup-server.conf"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

if [ ! -f "$FILTER_SRC" ]; then
    echo "Error: $FILTER_SRC not found. Run this script from the repository root."
    exit 1
fi

echo "Installing fail2ban filter: $FILTER_DST"
$DRY_RUN || cp "$FILTER_SRC" "$FILTER_DST"

echo "Installing fail2ban jail: $JAIL_DST"
$DRY_RUN || cp "$JAIL_SRC" "$JAIL_DST"

if ! $DRY_RUN; then
    echo "Restarting fail2ban service..."
    systemctl restart fail2ban.service
    echo "Done. Verify with: fail2ban-client status proxmox-backup-server"
else
    echo "Dry-run complete. No changes made."
fi
