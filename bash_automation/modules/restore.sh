#!/usr/bin/env bash
# capstone restore.sh
# Restore a backup produced by backup.sh: database + app files + nginx config.
#
# Sources:
#   - local archives  : ${ARCHIVE_DIR}/backup_<TS>.tar.gz
#   - replica archives: ${REPLICA_HOST}:${REPLICA_PATH}/backup_<TS>.tar.gz
#
# A selected archive is looked up locally first; if missing locally it is
# pulled from the replica automatically. The archive is verified before any
# restore is attempted.
#
# Modes:
#   restore.sh                     interactive menu
#   restore.sh --list-local        list local archives
#   restore.sh --list-remote       list replica archives
#   restore.sh --latest            restore the most recent archive
#   restore.sh --file NAME         restore a specific archive by name
#   restore.sh --help
#
# Run as root or via: sudo ./restore.sh
set -euo pipefail

ARCHIVE_DIR="${ARCHIVE_DIR:-/var/backups/capstone}"
LOG_DIR="${LOG_DIR:-/var/log/capstone}"
LOG_FILE="${LOG_DIR}/restore.log"
CTR="${CTR:-db_node}"
PGUSER="${PGUSER:-mocochan}"
DB="${DB:-baubau_db}"
APP_DIR="${APP_DIR:-/home/triet/App}"
NGINX_DIR="${NGINX_DIR:-/etc/nginx}"
REPLICA_HOST="${REPLICA_HOST:-triet@100.125.29.98}"
REPLICA_PATH="${REPLICA_PATH:-/backup/server-vm}"
SSH_KEY="${SSH_KEY:-/home/triet/.ssh/id_ed25519}"
ALERTRC="${ALERTRC:-/home/triet/capstone/.alertrc}"
DOCKER="${DOCKER:-/snap/bin/docker}"
SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
COMPOSE_FILE="${COMPOSE_FILE:-dbonly_compose.yaml}"

STAGING="$(mktemp -d)"
ARCHIVE=""
SOURCE=""
LATEST_NAME=""

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
    msg="$(hostname) restore: $*"
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
    alert "restore failed at line ${1} (exit ${rc}) - see ${LOG_FILE}"
    exit "${rc}"
}
trap 'err_trap $LINENO' ERR
trap 'rm -rf "$STAGING"' EXIT

usage() {
    cat <<'EOF'
Usage: restore.sh [mode]

  --list-local        list local archives
  --list-remote       list archives on the replica VM
  --latest            restore the most recent archive (local, else replica)
  --file NAME         restore archive backup_<TS>.tar.gz by name
  --help              show this help

With no mode an interactive menu is shown. Run as root or via: sudo ./restore.sh
EOF
}

# ---------------------------------------------------------------
# Listing
# ---------------------------------------------------------------
list_local() {
    echo "== Local archives: ${ARCHIVE_DIR} =="
    if ! ls -lht --time-style=+'%Y-%m-%d %H:%M' "${ARCHIVE_DIR}"/backup_*.tar.gz 2>/dev/null; then
        echo "  (none)"
    fi
}

list_remote() {
    echo "== Replica archives: ${REPLICA_HOST}:${REPLICA_PATH} =="
    # shellcheck disable=SC2029 # REPLICA_PATH is a constant identical on both VMs; local expansion intended
    if ! ssh "${SSH_OPTS[@]}" "$REPLICA_HOST" "ls -lht --time-style=+'%Y-%m-%d %H:%M' ${REPLICA_PATH}/backup_*.tar.gz"; then
        echo "  (none / unreachable)"
    fi
}

# ---------------------------------------------------------------
# Source resolution
# ---------------------------------------------------------------
resolve_source() {
    local name="$1"
    local local_file="${ARCHIVE_DIR}/${name}"

    if [ -f "$local_file" ]; then
        ARCHIVE="$local_file"
        SOURCE="local"
        log "source: ${ARCHIVE} (local)"
        return 0
    fi

    # shellcheck disable=SC2029 # REPLICA_PATH is a constant; ${name} is validated local input (both intentionally local)
    if ssh "${SSH_OPTS[@]}" "$REPLICA_HOST" "test -f '${REPLICA_PATH}/${name}'"; then
        log "local '${name}' missing - pulling from replica"
        rsync -e "ssh -i ${SSH_KEY} -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
            "${REPLICA_HOST}:${REPLICA_PATH}/${name}" "$ARCHIVE_DIR/"
        ARCHIVE="$local_file"
        SOURCE="replica"
        log "source: ${ARCHIVE} (pulled from replica)"
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------
# Verify + restore
# ---------------------------------------------------------------
verify_archive() {
    log "verify: ${ARCHIVE}"
    gzip -t "$ARCHIVE" || die "corrupt archive - gzip -t failed"
    if ! tar -xzOf "$ARCHIVE" --wildcards 'db_*.dump' >"${STAGING}/restore.dump" 2>/dev/null; then
        die "corrupt archive - cannot extract dump"
    fi
    if ! $DOCKER exec -i "$CTR" pg_restore --list <"${STAGING}/restore.dump" >/dev/null 2>&1; then
        die "corrupt archive - pg_restore --list failed"
    fi
    log "  verify OK"
}

restore_db() {
    log "restoring database ${DB} (--clean --if-exists)"
    $DOCKER exec -i "$CTR" pg_restore -U "$PGUSER" -Fc --clean --if-exists -d "$DB" <"${STAGING}/restore.dump"
    log "  database restore complete"
}

restore_files() {
    log "restoring app files and nginx config"
    tar -xzf "$ARCHIVE" -C / home/triet/App
    tar -xzf "$ARCHIVE" -C / etc/nginx
    tar -xzf "$ARCHIVE" -C / etc/systemd/system/baubau.service
    tar -xzf "$ARCHIVE" -C / var/www/status_page 2>/dev/null || true
    chown -R triet:triet "$APP_DIR"
    log "  files restored and ownership fixed"
}

proof() {
    local count
    count="$($DOCKER exec "$CTR" psql -U "$PGUSER" -d "$DB" -Atc 'SELECT count(*) FROM "baubau_table"' | head -1)"
    log "proof: rows in baubau_table = ${count}"
    local http
    http="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1/ || true)"
    log "proof: HTTP through nginx = ${http}"
    [ "$count" -ge 0 ] 2>/dev/null || die "database proof failed"
    [ "$http" = "200" ] || log "WARN: expected HTTP 200, got ${http}"
    log "restore verified (rows=${count}, http=${http})"
}

do_restore() {
    log "Stopping baubau.service"
    sudo systemctl stop baubau.service || true

    # 1. MUST extract files first so the compose file and .env.db actually exist on the disk
    restore_files

    # 2. load credentials
    if [ -f "${APP_DIR}/.env.db" ]; then
        log "Found .env.db, loading credentials..."
        source "${APP_DIR}/.env.db"
        # update these things
        PGUSER="${POSTGRES_USER}"
        DB="${POSTGRES_DB}"
    else
        die "Warninng: ${APP_DIR}/.env.db! not found"
    fi

    log "Starting db_node via docker compose..."
    cd "${APP_DIR}"
    sudo docker compose -f "$COMPOSE_FILE" up -d

    
    log "Waiting for db to stop dying..."
    sleep 5

    # 2. Verify and restore the database now that the container is online
    verify_archive
    restore_db

    log "creating venv..."
    cd "${APP_DIR}"
    if [ ! -d "venv" ]; then
        log "  No venv, making one..."
        python3 -m venv venv
    fi
    if [ -f "requirements.txt" ]; then
        log "  installing requirements.txt..."
        ./venv/bin/pip install -r requirements.txt > /dev/null
    fi

    log "Restarting service..."
    sudo systemctl daemon-reload
    sudo systemctl restart nginx
    sudo systemctl enable --now baubau.service

    proof

    log "==================== restore complete (from ${SOURCE}) ===================="
}

# ---------------------------------------------------------------
# CLI / menu
# ---------------------------------------------------------------
MODE="menu"
FILE_NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list-local)  MODE="list-local"; shift ;;
        --list-remote) MODE="list-remote"; shift ;;
        --latest)      MODE="latest"; shift ;;
        --file)        MODE="file"; FILE_NAME="$2"; shift 2 ;;
        --help)        usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$MODE" in
    list-local)  list_local; exit 0 ;;
    list-remote) list_remote; exit 0 ;;
    latest)
        log "==================== restore start (latest) ===================="
        LATEST_NAME="$(find "$ARCHIVE_DIR" -maxdepth 1 -name 'backup_*.tar.gz' -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
        if [ -z "$LATEST_NAME" ]; then
            # shellcheck disable=SC2029 # REPLICA_PATH constant, identical on both VMs
            LATEST_NAME="$(ssh "${SSH_OPTS[@]}" "$REPLICA_HOST" "find ${REPLICA_PATH} -maxdepth 1 -name 'backup_*.tar.gz' -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-")"
        fi
        if [ -z "$LATEST_NAME" ]; then
            die "no archives found locally or on the replica"
        fi
        log "latest archive: ${LATEST_NAME}"
        if ! resolve_source "$LATEST_NAME"; then
            die "archive ${LATEST_NAME} not found"
        fi
        do_restore
        exit 0
        ;;
    file)
        case "$FILE_NAME" in
            ""|*/*|backup_*.tar.gz) : ;;
            *) die "invalid archive name: ${FILE_NAME}" ;;
        esac
        log "==================== restore start (${FILE_NAME}) ===================="
        if ! resolve_source "$FILE_NAME"; then
            log "error: '${FILE_NAME}' found neither locally nor on the replica"
            echo "Available locally:"; list_local
            echo "Available on replica:"; list_remote
            die "archive not found"
        fi
        do_restore
        exit 0
        ;;
esac

# interactive menu
while true; do
    echo
    echo "=================== Capstone restore menu ==================="
    echo "  1) List local archives"
    echo "  2) List replica archives"
    echo "  3) Restore a specific archive (by filename)"
    echo "  4) Quit"
    echo "=============================================================="
    read -r -p "Choice [1-4]: " choice
    case "$choice" in
        1) list_local ;;
        2) list_remote ;;
        3)
            read -r -p "Archive filename (e.g. backup_20260816_020000.tar.gz): " name
            [ -n "$name" ] || { echo "empty input - nothing to do"; continue; }
            log "==================== restore start (${name}) ===================="
            if ! resolve_source "$name"; then
                log "error: '${name}' found neither locally nor on the replica"
                echo "Available locally:"; list_local
                echo "Available on replica:"; list_remote
                die "archive not found"
            fi
            do_restore
            ;;
        4) echo "bye"; exit 0 ;;
        *) echo "invalid choice - try again" ;;
    esac
done

## the smollest