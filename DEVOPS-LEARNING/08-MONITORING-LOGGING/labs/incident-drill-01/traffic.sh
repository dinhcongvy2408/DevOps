#!/usr/bin/env bash
# Giả lập người dùng: gọi taskhub qua nginx liên tục, mỗi 10 giây in thống kê mã HTTP.
# Không có traffic thì không có tỷ lệ lỗi/latency — alert dựa trên request sẽ im lặng.
# Dừng bằng Ctrl+C.
set -euo pipefail

TASKHUB_DIR="${TASKHUB_DIR:-$HOME/projects/taskhub}"
port="${NGINX_HOST_PORT:-}"
if [[ -z "$port" && -f "$TASKHUB_DIR/.env" ]]; then
  port="$(sed -n 's/^NGINX_HOST_PORT=//p' "$TASKHUB_DIR/.env")"
fi
base="http://localhost:${port:-8000}"
echo "Gửi traffic tới $base (Ctrl+C để dừng)"

declare -A count=()
last=$SECONDS
while true; do
  # 1 GET danh sách, thỉnh thoảng 1 POST — đủ để có rate, 5xx ratio và latency trên dashboard.
  code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$base/api/tasks" || true)"
  count[$code]=$(( ${count[$code]:-0} + 1 ))
  if (( RANDOM % 5 == 0 )); then
    code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' -X POST "$base/api/tasks" \
      -H 'Content-Type: application/json' -d '{"title":"drill traffic"}' || true)"
    count[$code]=$(( ${count[$code]:-0} + 1 ))
  fi
  if (( SECONDS - last >= 10 )); then
    line="$(date -u +%TZ)"
    for c in "${!count[@]}"; do line+="  $c=${count[$c]}"; done
    echo "$line"
    count=()
    last=$SECONDS
  fi
  sleep 0.5
done
