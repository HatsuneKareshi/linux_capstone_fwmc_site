#!/usr/bin/env bash
# ==============================================================================
# Script Name: manager.sh
# Description: CLI Manager for Linux Capstone Project
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# SUDO CHECK
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root. Please use sudo."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/capstone/manager.log"

log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}]: $*" | tee -a "${LOG_FILE}"
}

error_handler() {
    local exit_code=$?
    log "ERROR" "Error occurred on line $1 with exit code ${exit_code}."
}

trap 'error_handler ${LINENO}' ERR

usage() {
    cat << EOF
Usage: $0 [OPTIONS]
Options:
  -d, --deploy        Deploy the application (Test & Rollback)
  -b, --backup        Backup DB & Web content, rsync to VM2
  -r, --restore       Restore system from a backup file
  -c, --health-check  Check resource and service health
  -l, --log-rotate    Rotate application logs
  -h, --help          Show this help message
EOF
    exit 0
}

interactive_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "        LINUX PROJECT AUTOMATION CLI      "
        echo "=========================================="
        echo "1. Deploy Application (Test & Rollback)"
        echo "2. Backup Data & Rsync to VM2"
        echo "3. Restore Data"
        echo "4. Health-Check & Send Alerts"
        echo "5. Rotate Logs"
        echo "6. Exit"
        echo "=========================================="
        read -rp "Select an option [1-6]: " choice
        case "$choice" in
            1) bash "${SCRIPT_DIR}/modules/deploy.sh"; read -rp "Press Enter to continue..." ;;
            2) bash "${SCRIPT_DIR}/modules/backup.sh"; read -rp "Press Enter to continue..." ;;
            3) bash "${SCRIPT_DIR}/modules/restore.sh"; read -rp "Press Enter to continue..." ;;
            4) bash "${SCRIPT_DIR}/modules/health_check.sh"; read -rp "Press Enter to continue..." ;;
            5) bash "${SCRIPT_DIR}/modules/log_rotate.sh"; read -rp "Press Enter to continue..." ;;
            6) exit 0 ;;
            *) echo "Invalid option!"; sleep 1 ;;
        esac
    done
}

if [[ $# -gt 0 ]]; then
    opt="${1#--}"
    case "$opt" in
        deploy|d) bash "${SCRIPT_DIR}/modules/deploy.sh" ;;
        backup|b) bash "${SCRIPT_DIR}/modules/backup.sh" ;;
        restore|r) bash "${SCRIPT_DIR}/modules/restore.sh" ;;
        health-check|c) bash "${SCRIPT_DIR}/modules/health_check.sh" ;;
        log-rotate|l) bash "${SCRIPT_DIR}/modules/log_rotate.sh" ;;
        help|h) usage ;;
        *) echo "Invalid parameter. Use --help for usage."; exit 1 ;;
    esac
else
    interactive_menu
fi#!/usr/bin/env bash
# ==============================================================================
# Script Name: manager.sh
# Description: CLI Manager for Linux Capstone Project
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# SUDO CHECK
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root. Please use sudo."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/capstone/manager.log"

log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}]: $*" | tee -a "${LOG_FILE}"
}

error_handler() {
    local exit_code=$?
    log "ERROR" "Error occurred on line $1 with exit code ${exit_code}."
}

trap 'error_handler ${LINENO}' ERR

usage() {
    cat << EOF
Usage: $0 [OPTIONS]
Options:
  -d, --deploy        Deploy the application (Test & Rollback)
  -b, --backup        Backup DB & Web content, rsync to VM2
  -r, --restore       Restore system from a backup file
  -c, --health-check  Check resource and service health
  -l, --log-rotate    Rotate application logs
  -h, --help          Show this help message
EOF
    exit 0
}

interactive_menu() {
    while true; do
        clear
        echo "=========================================="
        echo "        LINUX PROJECT AUTOMATION CLI      "
        echo "=========================================="
        echo "1. Deploy Application (Test & Rollback)"
        echo "2. Backup Data & Rsync to VM2"
        echo "3. Restore Data"
        echo "4. Health-Check & Send Alerts"
        echo "5. Rotate Logs"
        echo "6. Exit"
        echo "=========================================="
        read -rp "Select an option [1-6]: " choice
        case "$choice" in
            1) bash "${SCRIPT_DIR}/modules/deploy.sh"; read -rp "Press Enter to continue..." ;;
            2) bash "${SCRIPT_DIR}/modules/backup.sh"; read -rp "Press Enter to continue..." ;;
            3) bash "${SCRIPT_DIR}/modules/restore.sh"; read -rp "Press Enter to continue..." ;;
            4) bash "${SCRIPT_DIR}/modules/health_check.sh"; read -rp "Press Enter to continue..." ;;
            5) bash "${SCRIPT_DIR}/modules/log_rotate.sh"; read -rp "Press Enter to continue..." ;;
            6) exit 0 ;;
            *) echo "Invalid option!"; sleep 1 ;;
        esac
    done
}

if [[ $# -gt 0 ]]; then
    opt="${1#--}"
    case "$opt" in
        deploy|d) bash "${SCRIPT_DIR}/modules/deploy.sh" ;;
        backup|b) bash "${SCRIPT_DIR}/modules/backup.sh" ;;
        restore|r) bash "${SCRIPT_DIR}/modules/restore.sh" ;;
        health-check|c) bash "${SCRIPT_DIR}/modules/health_check.sh" ;;
        log-rotate|l) bash "${SCRIPT_DIR}/modules/log_rotate.sh" ;;
        help|h) usage ;;
        *) echo "Invalid parameter. Use --help for usage."; exit 1 ;;
    esac
else
    interactive_menu
fi