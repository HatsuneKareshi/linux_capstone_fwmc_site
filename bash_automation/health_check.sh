#!/usr/bin/env bash
set -euo pipefail

DISK_THRESHOLD=85

send_alert() {
    local message="$1"
    echo "[ALERT] ${message}"
}

DISK_USAGE=$(df / | grep / | awk '{print $5}' | sed 's/%//g')
if (( DISK_USAGE > DISK_THRESHOLD )); then
    send_alert "Disk usage is at${DISK_USAGE}%!"
fi

SERVICES=("nginx" "snap.docker.dockerd.service" "baubau.service")
for svc in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet "${svc}"; then
        send_alert "Service ${svc} is stopped, attempting restart..."
        # sudo systemctl restart "${svc}" the health check should only check health
    fi
done

if ! docker inspect -f '{{.State.Running}}' db_node | grep -q "true"; then
    send_alert "Database docker container (db_node) isnt running!"
else
    DB_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' db_node)
    if [ "$DB_HEALTH" != "healthy" ]; then
        send_alert "Database docker container (db_node) isnt ready (${DB_HEALTH})!"
    fi
fi

echo "Health check done."
