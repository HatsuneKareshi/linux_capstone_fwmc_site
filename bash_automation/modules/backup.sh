#!/usr/bin/env bash
# capstone backup.sh
# Automated backup of the Capstone system:
#   - PostgreSQL database dump (db_node container, pg_dump custom format)
#   - Application files (/home/triet/App)
#   - Nginx configuration (/etc/nginx)
# Packaged into a timestamped archive, retention applied, pushed to the
# replica VM (vm-backup) via rsync over SSH.
#
# Run as root (systemd timer) or via: sudo ./backup.sh
set -euo pipefail

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/backups/capstone}"
LOG_DIR="${LOG_DIR:-/var/log/capstone}"
LOG_FILE="${LOG_DIR}/backup.log"
CTR="${CTR:-db_node}"
#PGUSER="${PGUSER:-mocochan}"
DB="${DB:-baubau_db}"
APP_DIR="${APP_DIR:-/home/triet/App}"
NGINX_DIR="${NGINX_DIR:-/etc/nginx}"
REPLICA_HOST="${REPLICA_HOST:-triet@100.125.29.98}"
REPLICA_PATH="${REPLICA_PATH:-/backup/server-vm}"
SSH_KEY="${SSH_KEY:-/home/triet/.ssh/id_ed25519}"
ALERTRC="${ALERTRC:-/home/triet/capstone/.alertrc}"
KEEP="${KEEP:-7}"                       # retention in days
MIN_FREE_MB="${MIN_FREE_MB:-500}"       # abort if free space drops below this (MB)
DOCKER="${DOCKER:-/snap/bin/docker}"
SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

TS="$(date +%Y%m%d_%H%M%S)"
DRY_RUN=0
STAGING=""

# if [ -f "${APP_DIR}/.env.db" ]; then
#     source "${APP_DIR}/.env.db"
#     DB="${POSTGRES_DB:-$DB}"
#     PGUSER="${POSTGRES_USER:-postgres}"
# fi

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------
log() {
    local msg
    msg="[$(date '+%F %T')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Alert channel: Telegram Bot API. Credentials live in ${ALERTRC} (chmod 600).
alert() {
    local msg
    msg="$(hostname) backup: $*"
    log "ALERT: $*"
    if [ -r "$ALERTRC" ]; then
        # shellcheck source=/dev/null
        . "$ALERTRC"
        if [ -n "${TELEGRAM_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
            curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
                --data-urlencode "text=${msg}" >/dev/null 2>&1 \
                || log "  telegram send failed"
        fi
    fi
}

die() {
    log "FATAL: $*"
    alert "FATAL: $*"
    exit 1
}

err_trap() {
    local rc=$?
    log "ERROR at line ${1}: command failed (exit ${rc})"
    alert "backup failed at line ${1} (exit ${rc}) - see ${LOG_FILE}"
    exit "${rc}"
}
trap 'err_trap $LINENO' ERR

usage() {
    cat <<'EOF'
Usage: backup.sh [options]

  -k, --keep DAYS    retention period in days (default: 7)
  -n, --dry-run      check prerequisites and show actions, make no changes
  -h, --help         show this help

Backs up the database, app files and nginx config into a timestamped
archive, enforces retention, and rsyncs the archive to the replica VM.
Run as root or via: sudo ./backup.sh
EOF
}

# ---------------------------------------------------------------
# Steps
# ---------------------------------------------------------------
preflight() {
    log "preflight: free space, container, source paths"

    local fs_free_mb fs_target
    fs_free_mb="$(df -Pm "$ARCHIVE_DIR" | awk 'NR==2 {print $4}')"
    fs_target="$(df --output=target "$ARCHIVE_DIR" | tail -1)"
    if [ "$fs_free_mb" -lt "$MIN_FREE_MB" ]; then
        die "only ${fs_free_mb} MB free on ${fs_target} (min ${MIN_FREE_MB} MB) - aborting"
    fi
    log "  free space OK: ${fs_free_mb} MB free on ${fs_target}"

    if ! $DOCKER inspect -f '{{.State.Running}}' "$CTR" >/dev/null 2>&1; then
        die "container ${CTR} not running (or docker unreachable) - aborting"
    fi
    log "  container ${CTR} running"

    [ -d "$APP_DIR" ]   || die "app dir ${APP_DIR} missing"
    [ -d "$NGINX_DIR" ] || die "nginx dir ${NGINX_DIR} missing"

    if [ ! -f "${APP_DIR}/.env.db" ]; then
        die "CRITICAL: ${APP_DIR}/.env.db is missing! Aborting backup."
    fi

    source "${APP_DIR}/.env.db"
    DB="${POSTGRES_DB}"
    PGUSER="${POSTGRES_USER}"

    log "  source paths and credentials OK"
}

dump_db() {
    local dump="${STAGING}/db_${TS}.dump"
    log "pg_dump: ${CTR} (${PGUSER}@${DB}) -> ${dump}"
    $DOCKER exec "$CTR" pg_dump -U "$PGUSER" -Fc -d "$DB" >"$dump"
    log "  dump bytes: $(stat -c %s "$dump")"
}

package() {
    local archive="${ARCHIVE_DIR}/backup_${TS}.tar.gz"
    log "packaging -> ${archive}"
    tar -czf "$archive" \
        --exclude='home/triet/App/.env' \
        --exclude='home/triet/App/.env.db' \
        --exclude='home/triet/App/.git' \
        --exclude='home/triet/App/venv' \
        --exclude='home/triet/App/__pycache__' \
        --exclude='home/triet/App/*/__pycache__' \
        -C "$STAGING" "db_${TS}.dump" \
        -C / home/triet/App \
        -C / etc/nginx \
        -C / etc/systemd/system/baubau.service \
        -C / var/www/status_page
    log "  archive bytes: $(stat -c %s "$archive")"
}

verify() {
    local archive="${ARCHIVE_DIR}/backup_${TS}.tar.gz"
    log "verify: ${archive}"
    gzip -t "$archive" || die "corrupt archive - gzip -t failed"
    tar -xzOf "$archive" "db_${TS}.dump" >"${STAGING}/verify.dump"
    if ! $DOCKER exec -i "$CTR" pg_restore --list <"${STAGING}/verify.dump" >/dev/null 2>&1; then
        die "corrupt archive - pg_restore --list failed"
    fi
    log "  verify OK (gzip + pg_restore --list)"
}

retention() {
    log "retention: removing local archives older than ${KEEP} days"
    local removed=0 f
    while IFS= read -r -d '' f; do
        log "  remove ${f}"
        rm -f "$f"
        removed=$((removed + 1))
    done < <(find "$ARCHIVE_DIR" -maxdepth 1 -name 'backup_*.tar.gz' -mtime +"$KEEP" -print0)
    if [ "$removed" -gt 0 ]; then
        log "  removed ${removed} old archive(s)"
    else
        log "  nothing older than ${KEEP} days"
    fi
}

guards() {
    local n
    n="$(find "$ARCHIVE_DIR" -maxdepth 1 -name 'backup_*.tar.gz' | wc -l)"
    if [ "$n" -lt 1 ]; then
        die "no local archives; refusing rsync --delete against an empty set"
    fi
    log "  local archive count: ${n}"

    if ! ssh "${SSH_OPTS[@]}" "$REPLICA_HOST" "findmnt -rn /backup >/dev/null"; then
        die "replica mount /backup not mounted on ${REPLICA_HOST}; refusing rsync"
    fi
    log "  replica /backup is mounted"
}

push() {
    log "rsync -> ${REPLICA_HOST}:${REPLICA_PATH}"
    rsync -avz --delete --partial \
        -e "ssh -i ${SSH_KEY} -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10" \
        "$ARCHIVE_DIR/" "${REPLICA_HOST}:${REPLICA_PATH}/"
    log "  rsync complete"
}

# ---------------------------------------------------------------
# CLI
# ---------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -k|--keep)     KEEP="$2"; shift 2 ;;
        -n|--dry-run)  DRY_RUN=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------
mkdir -p "$ARCHIVE_DIR" "$LOG_DIR"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING:-/nonexistent}"' EXIT

log "==================== backup start (dry-run=${DRY_RUN}) ===================="
preflight

if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: skipping dump, package, verify, retention and rsync"
    log "==================== backup end (dry-run) ===================="
    exit 0
fi

dump_db
package
verify
retention
guards
push
log "==================== backup complete ===================="


## are the bravest