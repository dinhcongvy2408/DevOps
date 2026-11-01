#!/usr/bin/env bash
# Bản tham khảo v5 — backup PostgreSQL của taskhub lên S3.
# Chép vào repo: scripts/backup.sh. Chạy trên HOST (EC2), KHÔNG trong container:
# container không có quyền AWS (IMDS hop limit 1), còn AWS CLI trên host dùng instance role taskhub-ec2-role.
#
# Dùng:   BACKUP_BUCKET=taskhub-backups-<account-id> scripts/backup.sh
# Lịch:   systemd timer taskhub-backup.timer, 18:00 UTC hằng ngày, Persistent=true (Ansible cài) — xem README.
# Thử với MinIO trên laptop: AWS_ENDPOINT_URL=http://localhost:9000 (AWS CLI v2 đọc biến này).
set -euo pipefail

BUCKET="${BACKUP_BUCKET:?Đặt BACKUP_BUCKET=taskhub-backups-<account-id>}"
PREFIX="${BACKUP_PREFIX:-pg-dumps}"
PROJECT="${COMPOSE_PROJECT:-taskhub}"
DB_NAME="${DB_NAME:-taskhub}"
DB_USER="${DB_USER:-taskhub}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"

# Tìm container postgres theo nhãn Compose — không phụ thuộc tên container (taskhub-postgres-1…).
pg="$(docker ps -q \
  --filter "label=com.docker.compose.project=${PROJECT}" \
  --filter "label=com.docker.compose.service=postgres")"
[[ -n "$pg" ]] || { echo "LỖI: không thấy container postgres của project ${PROJECT}" >&2; exit 1; }

ts="$(date -u +%Y%m%dT%H%M%SZ)"
key="${PREFIX}/${DB_NAME}-${ts}.dump"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT          # luôn xóa file tạm, kể cả khi lỗi giữa chừng

start=$SECONDS

# 1. Dump ra file tạm trên host. -Fc (custom format): đã nén sẵn, pg_restore chọn được bảng/đối tượng.
#    Không pipe thẳng lên S3: pg_dump lỗi giữa chừng thì S3 sẽ nhận một file dở dang trông như backup thật.
docker exec "$pg" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$tmp"

# 2. Kiểm tra file đọc được (đọc mục lục). Backup không đọc được = không có backup.
docker exec -i "$pg" pg_restore --list < "$tmp" > /dev/null

size="$(stat -c %s "$tmp")"

# 3. Đẩy lên S3 (versioning + lifecycle của bucket lo phần giữ/xóa bản cũ).
aws s3 cp "$tmp" "s3://${BUCKET}/${key}" --only-show-errors

# 4. Chỉ khi MỌI bước trên thành công mới ghi metric — alert TaskhubBackupStale dựa vào đây.
#    Ghi file tạm rồi mv (atomic) để node-exporter không bao giờ đọc phải file viết dở.
prom="${TEXTFILE_DIR}/taskhub_backup.prom"
cat > "${prom}.$$" <<EOF
# HELP taskhub_backup_last_success_timestamp_seconds Unix time of the last successful taskhub backup.
# TYPE taskhub_backup_last_success_timestamp_seconds gauge
taskhub_backup_last_success_timestamp_seconds $(date +%s)
# HELP taskhub_backup_last_size_bytes Size in bytes of the last successful taskhub backup.
# TYPE taskhub_backup_last_size_bytes gauge
taskhub_backup_last_size_bytes ${size}
# HELP taskhub_backup_last_duration_seconds Duration of the last successful taskhub backup.
# TYPE taskhub_backup_last_duration_seconds gauge
taskhub_backup_last_duration_seconds $((SECONDS - start))
EOF
mv "${prom}.$$" "$prom"

echo "OK: s3://${BUCKET}/${key} (${size} bytes, $((SECONDS - start))s)"
