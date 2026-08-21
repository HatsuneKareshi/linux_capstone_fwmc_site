#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/capstone"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')

# Ensure the directory exists
mkdir -p "${LOG_DIR}"

# Loop through all .log files in the directory
for TARGET_LOG in "${LOG_DIR}"/*.log; do
    # Skip if no log files are found to avoid bash glob errors
    if [[ -f "${TARGET_LOG}" ]]; then
        mv "${TARGET_LOG}" "${TARGET_LOG}.${TIMESTAMP}"
        gzip "${TARGET_LOG}.${TIMESTAMP}"

        # Recreate a fresh empty log file
        touch "${TARGET_LOG}"

        # Record the rotation action directly into the newly created file
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [LOG-ROTATE]: Successfully rotated and compressed log file." | tee -a "${TARGET_LOG}"
    fi
done

# Keep a maximum of 5 recent log archives, remove anything older

for BASE_LOG in "${LOG_DIR}"/*.log; do
    # List all archives for this specific log, sort newest first, skip the top 5, delete the rest
    ls -t "${BASE_LOG}".*.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
done

echo "Log rotation completed successfully for all modules."