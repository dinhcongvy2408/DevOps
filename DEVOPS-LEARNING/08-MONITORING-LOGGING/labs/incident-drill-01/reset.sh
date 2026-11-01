#!/usr/bin/env bash
# Gỡ mọi thứ inject.sh đã làm và đưa stack taskhub về trạng thái khỏe.
# An toàn khi chạy nhiều lần, kể cả khi bạn đã tự giảm thiểu xong.
set -euo pipefail

PROJECT="taskhub"
TASKHUB_DIR="${TASKHUB_DIR:-$HOME/projects/taskhub}"
STATE_DIR="${STATE_DIR:-$HOME/devops-lab/08-monitoring/drill}"

die() { echo "LỖI: $*" >&2; exit 1; }

command -v docker > /dev/null || die "không thấy lệnh docker"
[[ -f "$TASKHUB_DIR/compose.yaml" ]] || die "không thấy $TASKHUB_DIR/compose.yaml — đặt TASKHUB_DIR cho đúng"

if [[ ! -f "$STATE_DIR/active" ]]; then
  echo "Không có drill nào đang hoạt động — vẫn kiểm tra sức khỏe stack."
  scenario=""; started=""
else
  scenario="$(sed -n 's/^scenario=//p' "$STATE_DIR/active")"
  started="$(sed -n 's/^started=//p' "$STATE_DIR/active")"
fi

# 1. Hủy các lệnh hẹn giờ còn chờ (mỗi lệnh là một process group riêng do setsid tạo).
if [[ -f "$STATE_DIR/pids" ]]; then
  while read -r pid; do
    [[ -n "$pid" ]] && kill -- "-$pid" 2> /dev/null || true
  done < "$STATE_DIR/pids"
  rm -f "$STATE_DIR/pids"
fi

container_of() {
  docker ps -a \
    --filter "label=com.docker.compose.project=${PROJECT}" \
    --filter "label=com.docker.compose.service=$1" \
    --format '{{.Names}}' | head -n 1
}
pg="$(container_of postgres)"
[[ "$pg" == taskhub-* ]] || die "không thấy container postgres của project taskhub"

# 2. PostgreSQL: bỏ đóng băng / khởi động lại nếu cần.
if [[ "$(docker inspect -f '{{.State.Paused}}' "$pg")" == "true" ]]; then
  docker unpause "$pg" > /dev/null
  echo "- Đã unpause $pg"
fi
if [[ "$(docker inspect -f '{{.State.Running}}' "$pg")" != "true" ]]; then
  docker start "$pg" > /dev/null
  echo "- Đã start $pg"
fi

# 3. App: tạo lại theo cấu hình CHUẨN của repo (không có file override của drill).
#    Không có -f → Compose tự gộp compose.override.yaml (laptop) như khi bạn chạy bình thường.
(cd "$TASKHUB_DIR" && docker compose -p "$PROJECT" up -d --no-build --wait --wait-timeout 180) > /dev/null
rm -f "$STATE_DIR/compose.drill.yaml"
echo "- Stack taskhub đã healthy"

# 4. Kết thúc drill.
if [[ -n "$scenario" ]]; then
  mv "$STATE_DIR/active" "$STATE_DIR/last-drill-$(date -u +%Y%m%dT%H%M%SZ).txt"
  echo
  echo "Drill kết thúc lúc $(date -u +%FT%TZ). Bắt đầu: $started. Kịch bản: $scenario"
  echo "Viết postmortem: docs/postmortems/$(date -u +%F)-<slug>.md (mẫu: bài 06 §4.10)"
fi
