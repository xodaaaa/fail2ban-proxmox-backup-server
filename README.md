# fail2ban-proxmox-backup-server

Fail2Ban para **Proxmox Backup Server (PBS)** — protege tu servidor de ataques de fuerza bruta contra la API y WebGUI.

## Características

- 🛡️ Filtro para detectar intentos de autenticación fallidos en PBS
- ⚙️ Jail optimizado con `maxretry=5`, `bantime.increment` y `ignoreip`
- 🔒 Baneo progresivo para reincidentes (factor x2, hasta 1 semana)
- 🤖 **Bot de Telegram** opcional con notificaciones en tiempo real
- 📊 Reportes periódicos de estado y análisis de seguridad
- 📈 Informe semanal con estadísticas de ataques

## Requisitos

- Proxmox Backup Server (cualquier versión reciente)
- fail2ban (se instala automáticamente con el script)
- iptables
- curl (para notificaciones Telegram)

## Instalación Rápida

```bash
# Descargar el repositorio
git clone https://github.com/xodaaaa/fail2ban-proxmox-backup-server.git
cd fail2ban-proxmox-backup-server

# Ejecutar el instalador (como root)
chmod +x install.sh
./install.sh
```

Esto instalará fail2ban, copiará las configuraciones y te preguntará si deseas configurar el bot de Telegram.

### Opciones del instalador

```bash
./install.sh                       # Instalación completa con Telegram
./install.sh --no-telegram         # Sin bot de Telegram
./install.sh --dry-run             # Simular sin hacer cambios
./install.sh --uninstall           # Eliminar todas las configuraciones
```

> ⚠️ **El bot de Telegram se configura por defecto.** Si no querés Telegram, usá `--no-telegram`.

## Instalación Manual

```bash
# Instalar dependencias
apt update && apt install -y fail2ban iptables

# Copiar configuraciones
cp filter.d/proxmox-backup-server.conf /etc/fail2ban/filter.d/
cp jail.d/proxmox-backup-server.conf /etc/fail2ban/jail.d/

# Reiniciar fail2ban
systemctl restart fail2ban.service

# Verificar estado
fail2ban-client status proxmox-backup-server
```

## Configuración del Jail

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| `maxretry` | 5 | Intentos fallidos antes de banear |
| `findtime` | 60m | Ventana de tiempo para contar intentos |
| `bantime` | 1h | Duración del primer baneo |
| `bantime.increment` | true | Aumenta el baneo en cada reincidencia |
| `bantime.factor` | 2 | Multiplicador del baneo progresivo |
| `bantime.maxtime` | 1w | Duración máxima de baneo |
| `banaction` | iptables-allports | Bloquea todos los puertos |

### Red privada excluida (`ignoreip`)

Por defecto se excluyen:

- `127.0.0.1/8` — localhost IPv4
- `::1` — localhost IPv6
- `10.0.0.0/8` — red privada clase A
- `172.16.0.0/12` — red privada clase B
- `192.168.0.0/16` — red privada clase C

### Jail Recidiva (para reincidentes persistentes)

Para activarla, descomenta las líneas en `jail.d/proxmox-backup-server.conf` y asegúrate de que fail2ban esté logueando en `/var/log/fail2ban.log`.

## Bot de Telegram

El bot de Telegram **se instala y configura por defecto** junto con fail2ban. Recibe notificaciones en tiempo real cuando se banea una IP, más reportes periódicos y análisis de seguridad.

### Requisitos previos

1. Abre Telegram y busca [@BotFather](https://t.me/BotFather)
2. Envía `/newbot` y sigue las instrucciones para crear tu bot
3. Guarda el **token** que recibes (ej: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)

### Obtención del Chat ID

**Opción A — Automática (recomendada):** Ejecuta el script y envía `/start` al bot:

```bash
./telegram/get-chat-id.sh <TU_TOKEN>
```

El script detectará tu Chat ID automáticamente y lo guardará en la configuración.

**Opción B — Manual:** Envía `/start` al bot y luego abre en el navegador:
`https://api.telegram.org/bot<TU_TOKEN>/getUpdates`
Busca `"chat":{"id":<NUMERO>}` en la respuesta.

### Scripts disponibles

| Script | Función | Activación |
|--------|---------|------------|
| `telegram/get-chat-id.sh` | Obtiene el Chat ID automáticamente | Manual |
| `telegram/notify.sh` | Notificaciones de baneo/desbaneo | Acción de fail2ban |
| `telegram/status.sh` | Estado actual de las jails | Cron (cada 30 min) |
| `telegram/alerts.sh` | Detección de patrones de ataque | Cron (cada 15 min) |
| `telegram/weekly-report.sh` | Informe semanal de seguridad | Cron (semanal) |

### Instalación manual del bot

```bash
# Copiar configuración y scripts
mkdir -p /etc/fail2ban/telegram
cp telegram/config.sh.example /etc/fail2ban/telegram/config.sh
chmod 600 /etc/fail2ban/telegram/config.sh
nano /etc/fail2ban/telegram/config.sh  # ← Editar token y chat ID

# Copiar scripts
cp telegram/*.sh /etc/fail2ban/telegram/
chmod +x /etc/fail2ban/telegram/*.sh

# Copiar acción de fail2ban
cp action.d/telegram.conf /etc/fail2ban/action.d/

# Habilitar en jail.d (descomentar las líneas action)
# y reiniciar:
systemctl restart fail2ban.service
```

### Tareas programadas (cron)

```bash
# Reportes cada 30 minutos
*/30 * * * * /etc/fail2ban/telegram/status.sh

# Alertas de seguridad cada 15 minutos
*/15 * * * * /etc/fail2ban/telegram/alerts.sh

# Informe semanal cada lunes a las 9 AM
0 9 * * 1 /etc/fail2ban/telegram/weekly-report.sh
```

### Ejemplo de notificaciones

```
🚫 IP BANEADA
IP: 185.220.101.x
Jail: proxmox-backup-server
Origen: Alemania - Contabo GmbH

📊 Estado fail2ban - PBS
Baneados actuales: 3
Baneados totales: 12
Fallos actuales: 0

🔍 Alerta de Seguridad
Ataque de fuerza bruta detectado:
185.220.101.x (45 intentos en 30 min)

📈 Informe Semanal
Fallos de autenticación: 1,234
IPs únicas baneadas: 28
```

## Archivos del proyecto

```
├── filter.d/
│   └── proxmox-backup-server.conf   ← Regex para detectar auth fallidos
├── jail.d/
│   └── proxmox-backup-server.conf   ← Configuración de la jail
├── action.d/
│   └── telegram.conf                ← Acción de fail2ban para Telegram
├── telegram/
│   ├── config.sh.example            ← Plantilla de configuración
│   ├── notify.sh                    ← Notificaciones ban/unban
│   ├── status.sh                    ← Reporte de estado
│   ├── alerts.sh                    ← Análisis de seguridad
│   └── weekly-report.sh             ← Informe semanal
├── install.sh                       ← Instalador completo
└── LICENSE
```

## Personalización

Puedes ajustar los siguientes parámetros editando `/etc/fail2ban/jail.d/proxmox-backup-server.conf`:

- `maxretry`: número de intentos antes de banear
- `bantime`: duración del baneo
- `findtime`: ventana de tiempo para contar intentos
- `ignoreip`: IPs/rangos excluidos (separados por espacio)
- `bantime.factor`: multiplicador para baneo progresivo
- `bantime.maxtime`: duración máxima del baneo

## Licencia

Este proyecto está bajo la licencia MIT. Ver archivo `LICENSE`.
