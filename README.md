# fail2ban-proxmox-backup-server

Fail2Ban for Proxmox Backup Server (PBS)

filter and jail for fail2ban protecting a Proxmox Backup Server (PBS) from brute force attacks to the API/WebGUI

# Requirements

- [fail2ban](https://www.fail2ban.org/wiki/index.php/Main_Page) - see [fail2ban requirements](https://www.fail2ban.org/wiki/index.php/Requirements)
- fail2ban needs [iptables](https://www.netfilter.org/projects/iptables/index.html).

# Installation

## Install fail2ban on a Proxmox Backup Server

```
apt -y update; apt -y install fail2ban iptables
```

## Add the configs from this repository

```
# Download or clone this repository
git clone https://github.com/inettgmbh/fail2ban-proxmox-backup-server.git

# Put filter.d/proxmox-backup-server.conf contents to /etc/fail2ban/filter.d/proxmox-backup-server.conf
cp filter.d/proxmox-backup-server.conf /etc/fail2ban/filter.d/proxmox-backup-server.conf

# Put jail.d/proxmox-backup-server.conf to /etc/fail2ban/jail.d/proxmox-backup-server.conf
cp jail.d/proxmox-backup-server.conf /etc/fail2ban/jail.d/proxmox-backup-server.conf

# Restart Fail2Ban Service
systemctl restart fail2ban.service
```

## Check if new jail is active

```
fail2ban-client status

Status
|- Number of jail:	2
`- Jail list:	proxmox-backup-server, sshd
```

```
fail2ban-client status proxmox-backup-server

Status for the jail: proxmox-backup-server
|- Filter
|  |- Currently failed:	0
|  |- Total failed:	0
|  `- File list:	/var/log/proxmox-backup/api/auth.log
`- Actions
   |- Currently banned:	0
   |- Total banned:	0
   `- Banned IP list:
```

# Telegram Bot Monitoring (Optional)

Get real-time notifications on Telegram when IPs are banned, plus periodic status reports and security analysis.

## Setup

### 1. Create a Telegram Bot

1. Open Telegram and search for [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts to create your bot
3. Save the bot token (looks like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)

### 2. Get Your Chat ID

1. Start a chat with your new bot and send `/start`
2. Open in browser: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
3. Look for `"chat":{"id":<YOUR_CHAT_ID>}` in the response

### 3. Install & Configure

```
# Copy config and edit with your token and chat ID
mkdir -p /etc/fail2ban/telegram
cp telegram/config.sh.example /etc/fail2ban/telegram/config.sh
chmod 600 /etc/fail2ban/telegram/config.sh
nano /etc/fail2ban/telegram/config.sh

# Install scripts
cp telegram/notify.sh /etc/fail2ban/telegram/
cp telegram/status.sh /etc/fail2ban/telegram/
cp telegram/alerts.sh /etc/fail2ban/telegram/
cp telegram/weekly-report.sh /etc/fail2ban/telegram/
chmod +x /etc/fail2ban/telegram/*.sh

# Install action.d config for fail2ban integration
cp action.d/telegram.conf /etc/fail2ban/action.d/

# Enable Telegram in jail config (uncomment the action lines)
# then restart fail2ban:
systemctl restart fail2ban.service
```

### 4. Schedule Periodic Reports (Optional)

Add to crontab (`crontab -e`):

```
# Status report every 30 minutes
*/30 * * * * /etc/fail2ban/telegram/status.sh

# Security alerts every 15 minutes
*/15 * * * * /etc/fail2ban/telegram/alerts.sh

# Weekly report every Monday at 9 AM
0 9 * * 1 /etc/fail2ban/telegram/weekly-report.sh
```

## Telegram Scripts Overview

| Script | Purpose | Trigger |
|--------|---------|---------|
| `notify.sh` | Ban/unban notifications | fail2ban action |
| `status.sh` | Current jail status | cron (every 30m) |
| `alerts.sh` | Pattern analysis & brute force detection | cron (every 15m) |
| `weekly-report.sh` | Weekly security summary | cron (weekly) |

## Features

- 🚫 Real-time ban/unban alerts with IP geolocation
- 📊 Periodic jail status reports (banned IPs, failure counts)
- 🔍 Brute force attack detection (same IP, multiple users)
- 🎯 Credential stuffing detection (same user, multiple IPs)
- 📈 Weekly security report with top attackers and statistics```
