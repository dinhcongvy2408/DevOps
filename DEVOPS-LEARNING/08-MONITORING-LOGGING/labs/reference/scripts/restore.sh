#!/usr/bin/env bash
# Bản tham khảo v5 — restore một bản backup vào database MỚI để kiểm tra (diễn tập restore).
# Chép vào repo: scripts/restore.sh. Chạy trên HOST như backup.sh.
#
# Dùng:   BACKUP_BUCKET=taskhub-backups-<account-id> scripts/restore.sh            # bản mới nhất
#         BACKUP_BUCKET=... scripts/restore.sh pg-dumps/taskhub-20270301T020000Z.dump
#
# Mặc định restore vào taskhub_restore — database đang phục vụ (taskhub) KHÔNG bị đụng tới.
# Đổi chỗ (swap) sang bản restore là bước THỦ CÔNG có chủ đích, in ra ở cuối script.
set -euo pipefail

BUCKET="${BACKUP_BUCKET:?Đặt BACKUP_BUCKET=taskhub-backups-<account-id>}"
PREFIX="${BACKUP_PREFIX:-pg-dumps}"
PROJECT="${COMPOSE_PROJECT:-taskhub}"
DB_NAME="${DB_NAME:-taskhub}"
DB_USER="${DB_USER:-taskhub}"
TARGET_DB="${TARGET_DB:-taskhub_restore}"

if [[ "$TARGET_DB" == "$DB_NAME" ]]; then
  echo "LỖI: TARGET_DB trùng database đang chạy (${DB_NAME}). Restore vào database mới rồi swap." >&2
  exit 1
fi

pg="$(docker ps -q \
  --filter "label=com.docker.compose.project=${PROJECT}" \
  --filter "label=com.docker.compose.service=postgres")"
[[ -n "$pg" ]] || { echo "LỖI: không thấy container postgres của project ${PROJECT}" >&2; exit 1; }

key="${1:-}"
if [[ -z "$key" ]]; then
  # Tên file chứa thời điểm UTC dạng YYYYMMDDTHHMMSSZ → sắp xếp theo tên = theo thời gian.
  key="${PREFIX}/$(aws s3 ls "s3://${BUCKET}/${PREFIX}/" | awk '{print $4}' | sort | tail -n 1)"
  [[ "$key" != "${PREFIX}/" ]] || { echo "LỖI: không có bản backup nào trong s3://${BUCKET}/${PREFIX}/" >&2; exit 1; }
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
start=$SECONDS

echo "Tải s3://${BUCKET}/${key} ..."
aws s3 cp "s3://${BUCKET}/${key}" "$tmp" --only-show-errors

# ⚠️ Chỉ xóa database ĐÍCH (taskhub_restore) — đã chặn trường hợp trùng tên ở trên.
docker exec "$pg" dropdb -U "$DB_USER" --if-exists "$TARGET_DB"
docker exec "$pg" createdb -U "$DB_USER" "$TARGET_DB"
# --exit-on-error: lỗi đầu tiên là dừng, không "restore được một nửa" mà tưởng thành công.
docker exec -i "$pg" pg_restore -U "$DB_USER" -d "$TARGET_DB" --no-owner --exit-on-error < "$tmp"

# Kiểm chứng: so số dòng và phiên bản migration giữa database đang chạy và bản restore.
q() { docker exec "$pg" psql -U "$DB_USER" -d "$1" -tAc "$2"; }
for db in "$DB_NAME" "$TARGET_DB"; do
  printf '%-16s tasks=%s  flyway_version=%s\n' "$db" \
    "$(q "$db" 'SELECT count(*) FROM tasks')" \
    "$(q "$db" 'SELECT max(version::int) FROM flyway_schema_history WHERE success')"
done

echo "Restore xong trong $((SECONDS - start))s (đây là một phần RTO của bạn)."
cat <<EOF

Bản restore nằm ở database ${TARGET_DB}. Số dòng có thể ÍT hơn ${DB_NAME} (dữ liệu sinh ra sau thời điểm backup
— chính là RPO). Muốn ĐỔI SANG bản restore (sự cố thật), làm có chủ đích theo runbook:
  1. docker compose -p ${PROJECT} stop taskhub
  2. docker exec ${pg} psql -U ${DB_USER} -d postgres -c 'ALTER DATABASE ${DB_NAME} RENAME TO ${DB_NAME}_broken'
  3. docker exec ${pg} psql -U ${DB_USER} -d postgres -c 'ALTER DATABASE ${TARGET_DB} RENAME TO ${DB_NAME}'
  4. docker compose -p ${PROJECT} start taskhub   rồi kiểm tra /actuator/health và dữ liệu
EOF
