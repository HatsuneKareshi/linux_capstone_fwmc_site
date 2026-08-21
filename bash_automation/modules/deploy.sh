#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/capstone/deploy.log"
APP_DIR="/home/triet/App"
NGINX_DIR="/etc/nginx/sites-available"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEPLOY]: $*" | tee -a "${LOG_FILE}"
}

log "Deploying"

# 1. PERMISSIONS & SECRETS
log "Securing permissions..."
sudo chown -R triet:triet "${APP_DIR}"
sudo chmod 755 "${APP_DIR}"
for secret in ".env" ".env.db"; do
    if [[ -f "${APP_DIR}/${secret}" ]]; then
        sudo chmod 600 "${APP_DIR}/${secret}"
    fi
done

# 2. GIT PULL
log "Pulling latest updates from GitHub..."
cd "${APP_DIR}"
git pull

# 3. PYTHON SYNTAX CHECK (Pre-flight)
log "Running Python syntax pre-check..."
if ! ./venv/bin/python3 -m py_compile *.py > /dev/null 2>&1; then
    log "ERROR: Python syntax error detected! Rolling back codebase..."
    git reset --hard ORIG_HEAD
    exit 1
fi

# 4. DATABASE HEALTH CHECK
log "Ensuring database is up and healthy..."
sudo docker compose -f dbonly_compose.yaml up -d
for i in {1..5}; do
    HEALTH=$(sudo docker inspect --format="{{.State.Health.Status}}" db_node 2>/dev/null || echo "unknown")
    if [[ "$HEALTH" == "healthy" ]]; then
        break
    fi
    sleep 3
done
if [[ "$HEALTH" != "healthy" ]]; then
    log "ERROR: Database healthcheck failed (Status: $HEALTH). Rolling back..."
    git reset --hard ORIG_HEAD
    exit 1
fi

# 5. VENV UPDATE
log "Updating Python virtual environment..."
./venv/bin/pip install -r requirements.txt > /dev/null

# 6. NGINX CONFIGS & TEST
log "Backing up live Nginx configs..."
sudo cp "${NGINX_DIR}/baubau.conf" "${NGINX_DIR}/baubau.conf.bak" 2>/dev/null || true
sudo cp "${NGINX_DIR}/internal.conf" "${NGINX_DIR}/internal.conf.bak" 2>/dev/null || true

log "Applying new Nginx configs from repository..."
sudo cp "${APP_DIR}/nginx/baubau.conf" "${NGINX_DIR}/baubau.conf"
sudo cp "${APP_DIR}/nginx/internal.conf" "${NGINX_DIR}/internal.conf"

log "Testing Nginx configuration..."
if ! sudo nginx -t; then
    log "ERROR: Nginx test failed. Rolling back Nginx and codebase..."
    sudo cp "${NGINX_DIR}/baubau.conf.bak" "${NGINX_DIR}/baubau.conf" 2>/dev/null || true
    sudo cp "${NGINX_DIR}/internal.conf.bak" "${NGINX_DIR}/internal.conf" 2>/dev/null || true
    git reset --hard ORIG_HEAD
    ./venv/bin/pip install -r requirements.txt > /dev/null # Revert pip packages
    exit 1
fi

# 7. RESTART SERVICES & POST-RESTART CHECK
log "Configuration valid. Reloading Nginx and restarting baubau.service..."
sudo systemctl reload nginx
sudo systemctl restart baubau.service

log "Verifying backend stability..."
sleep 3
if ! systemctl is-active --quiet baubau.service; then
    log "ERROR: baubau.service crashed after restart! Rolling everything back!"

    # Rollback Nginx
    sudo cp "${NGINX_DIR}/baubau.conf.bak" "${NGINX_DIR}/baubau.conf" 2>/dev/null || true
    sudo cp "${NGINX_DIR}/internal.conf.bak" "${NGINX_DIR}/internal.conf" 2>/dev/null || true
    sudo systemctl reload nginx

    # Rollback Code
    git reset --hard ORIG_HEAD
    ./venv/bin/pip install -r requirements.txt > /dev/null

    # Restart Backend with rolled-back code
    sudo systemctl restart baubau.service

    log "Total rollback complete. Deployment aborted."
    exit 1
fi

log "Deployment finished successfully!"