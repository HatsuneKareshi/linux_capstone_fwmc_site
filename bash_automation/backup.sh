#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/triet/App"
BACKUP_DIR="/mnt/backup-storage"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
VM2_IP="100.125.29.98"
VM2_USER="triet"

# Source the .env file so we can safely use the database credentials
source "${APP_DIR}/.env"

mkdir -p "${BACKUP_DIR}/db" "${BACKUP_DIR}/web"

echo "[BACKUP] Backup starting @ ${TIMESTAMP}..."

# 1. Database Backup (Docker integration)
echo "[BACKUP] Backing up data off of db_node..."
# We use docker exec to run pg_dump inside the container, passing the variables we sourced from .env
docker exec db_node pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "${BACKUP_DIR}/db/db_${TIMESTAMP}.sql.gz"

# 2. Application Backup (Targeted archiving)
echo "[BACKUP] Backing up application source code and related resources..."
# The --exclude flags prevent the massive venv folder and git history from bloating your backup

echo "[BACKUP] Backing up static web front, application files, service files and nginx virtualHost configs..."
sudo tar -czf "${BACKUP_DIR}/web/app_${TIMESTAMP}.tar.gz" \
    --exclude="venv" \
    --exclude=".git" \
    --exclude="__pycache__" \
    --exclude="*.zip" \
    -C "${APP_DIR}" . \
    /var/www/html \
    /etc/nginx \
    /etc/systemd/system/baubau.service

echo "[BACKUP] Backup should be saved at ${BACKUP_DIR}"

# 3. Retention Policy
echo "[BACKUP] Purging older backups..."
find "${BACKUP_DIR}/db/" -type f -mtime +7 -exec rm -f {} \;
find "${BACKUP_DIR}/web/" -type f -mtime +7 -exec rm -f {} \;

# 4. Offsite Synchronization
echo "[BACKUP] Attempting to back up to (${VM2_IP})..."
rsync -avz --delete "${BACKUP_DIR}/" "${VM2_USER}@${VM2_IP}:/backups/"

echo "[BACKUP] Backup script ran."