#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/capstone/health.log"
ALERTRC="${ALERTRC:-/home/triet/capstone/.alertrc}"

# Configurable thresholds
DISK_THRESHOLD=85
CPU_THRESHOLD=90
RAM_THRESHOLD=90

# Ensure log directory exists
mkdir -p /var/log/capstone

send_alert() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [HEALTH CRITICAL]: ${message}" | tee -a "${LOG_FILE}"

    # Trigger Telegram API if .alertrc exists
    if [[ -r "$ALERTRC" ]]; then
        # shellcheck source=/dev/null
        source "$ALERTRC"
        if [[ -n "${TELEGRAM_TOKEN:-}" ]] && [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
            curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
                --data-urlencode "text=$(hostname) HEALTH ALERT: ${message}" >/dev/null 2>&1 || true
        fi
    fi
}

# 1. RESOURCE CHECK (CPU, RAM, DISK)
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    send_alert "Disk usage is high: ${DISK_USAGE}%"
fi

RAM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
if [ "$RAM_USAGE" -gt "$RAM_THRESHOLD" ]; then
    send_alert "RAM usage is high: ${RAM_USAGE}%"
fi

CPU_USAGE=$(vmstat 1 2 | awk 'NR==4 {print 100 - $15}')
if [ "$CPU_USAGE" -gt "$CPU_THRESHOLD" ]; then
    send_alert "CPU usage is high: ${CPU_USAGE}%"
fi

# 2. LISTENING PORTS CHECK
PORTS=(80 8000)
for port in "${PORTS[@]}"; do
    if ! ss -tuln | grep -q ":${port} "; then
        send_alert "Port ${port} is NOT listening!"
    fi
done

# 3. SERVICES STATUS CHECK
SERVICES=("nginx" "snap.docker.dockerd.service" "baubau.service")
for svc in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet "${svc}"; then
        send_alert "Service ${svc} is stopped!"
    fi
done

# 4. DATABASE CONTAINER CHECK
if ! docker inspect -f '{{.State.Running}}' db_node 2>/dev/null | grep -q "true"; then
    send_alert "Database container (db_node) isn't running!"
else
    DB_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' db_node 2>/dev/null || echo "unknown")
    if [ "$DB_HEALTH" != "healthy" ]; then
        send_alert "Database container isn't ready (Status: ${DB_HEALTH})!"
    fi
fi

echo "Health check complete."