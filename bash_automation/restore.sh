#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/triet/App"
BACKUP_DIR="/mnt/backup-storage"
VM2_IP="100.125.29.98"
VM2_USER="triet"

echo "[RESTORE] Bắt đầu quá trình phục hồi dữ liệu..."

# 1. Tìm bản sao lưu mới nhất trên máy cục bộ (server-vm)
LATEST_DB=$(ls -t "${BACKUP_DIR}/db"/db_*.sql.gz 2>/dev/null | head -n 1 || true)
LATEST_WEB=$(ls -t "${BACKUP_DIR}/web"/app_*.tar.gz 2>/dev/null | head -n 1 || true)

# 2. Xử lý kịch bản Disaster Recovery: Kéo dữ liệu từ VM2 nếu không có sẵn
if [ -z "$LATEST_DB" ] || [ -z "$LATEST_WEB" ]; then
    echo "[CẢNH BÁO] Không tìm thấy đủ bản sao lưu cục bộ! Đang lấy dữ liệu từ VM2 (${VM2_IP})..."
    
    # Đảm bảo cấu trúc thư mục tồn tại trước khi rsync
    mkdir -p "${BACKUP_DIR}/db" "${BACKUP_DIR}/web"
    
    # Kéo toàn bộ thư mục /backups từ VM2 về lại BACKUP_DIR
    rsync -avz "${VM2_USER}@${VM2_IP}:/backups/" "${BACKUP_DIR}/"
    
    # Kiểm tra lại biến sau khi đã đồng bộ
    LATEST_DB=$(ls -t "${BACKUP_DIR}/db"/db_*.sql.gz 2>/dev/null | head -n 1 || true)
    LATEST_WEB=$(ls -t "${BACKUP_DIR}/web"/app_*.tar.gz 2>/dev/null | head -n 1 || true)
    
    if [ -z "$LATEST_DB" ] || [ -z "$LATEST_WEB" ]; then
        echo "[LỖI] Khôi phục thất bại: Vẫn không tìm thấy file sao lưu kể cả sau khi đồng bộ từ VM2!"
        exit 1
    fi
fi

echo "[RESTORE] Sử dụng bản sao lưu DB: $(basename "${LATEST_DB}")"
echo "[RESTORE] Sử dụng bản sao lưu Web/App: $(basename "${LATEST_WEB}")"

# 3. Dừng ứng dụng để tránh ghi đè dữ liệu rác
echo "[RESTORE] Tạm dừng ứng dụng (baubau.service)..."
sudo systemctl stop baubau.service

# 4. Phục hồi Cơ sở dữ liệu
echo "[RESTORE] Đang phục hồi cơ sở dữ liệu vào db_node..."
sudo docker start db_node >/dev/null

# Tải biến môi trường ngay trước khi sử dụng
source "${APP_DIR}/.env"

gunzip -c "${LATEST_DB}" | sudo docker exec -i db_node psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"

# 5. Phục hồi file ứng dụng và cấu hình Nginx
echo "[RESTORE] Đang giải nén mã nguồn và cấu hình..."
sudo tar -xzf "${LATEST_WEB}" -C /

# 5.5 Rebuild the Python Virtual Environment
echo "[RESTORE] Đang thiết lập lại môi trường ảo (venv) và cài đặt dependencies..."
cd "${APP_DIR}"
# If the venv folder doesn't exist, create it
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
# Use the virtual environment's pip to install the requirements
./venv/bin/pip install -r requirements.txt > /dev/null

# 6. Khởi động lại toàn bộ hệ thống
echo "[RESTORE] Khởi động lại dịch vụ web và ứng dụng..."
sudo systemctl daemon-reload
sudo systemctl restart nginx
sudo systemctl start baubau.service

echo "[RESTORE] Phục hồi thành công! Hệ thống đã hoạt động trở lại."