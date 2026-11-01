#!/usr/bin/env bash
# Incident drill #1 — tạo một sự cố CÓ KIỂM SOÁT trên stack taskhub ở laptop.
# Chỉ đụng tới container của Compose project "taskhub" (tên bắt đầu bằng "taskhub-"). Không đụng ổ đĩa host.
#
# Dùng:   ./inject.sh random        # khuyến nghị: không biết trước kịch bản nào
#         ./inject.sh A|B|C         # chọn kịch bản (dùng khi luyện lại)
# Gỡ:     ./reset.sh
#
# Biến môi trường (tùy chọn):
#   TASKHUB_DIR  thư mục repo taskhub (mặc định ~/projects/taskhub)
#   STATE_DIR    nơi lưu trạng thái drill (mặc định ~/devops-lab/08-monitoring/drill)
set -euo pipefail

PROJECT="taskhub"
TASKHUB_DIR="${TASKHUB_DIR:-$HOME/projects/taskhub}"
STATE_DIR="${STATE_DIR:-$HOME/devops-lab/08-monitoring/drill}"

die() { echo "LỖI: $*" >&2; exit 1; }

usage() {
  echo "Dùng: $0 random|A|B|C" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
choice="${1^^}"
[[ "$choice" =~ ^(RANDOM|A|B|C)$ ]] || usage

command -v docker > /dev/null || die "không thấy lệnh docker (đã bật WSL integration của Docker Desktop chưa?)"
docker info > /dev/null 2>&1 || die "không kết nối được Docker daemon"
[[ -f "$TASKHUB_DIR/compose.yaml" ]] || die "không thấy $TASKHUB_DIR/compose.yaml — đặt TASKHUB_DIR cho đúng"

# --- Hàng rào an toàn: chỉ làm việc với container của project taskhub -------------------
mapfile -t names < <(docker ps --filter "label=com.docker.compose.project=${PROJECT}" --format '{{.Names}}')
(( ${#names[@]} > 0 )) || die "không có container nào đang chạy của project '${PROJECT}'. Chạy stack trước: cd $TASKHUB_DIR && docker compose up -d --wait"
for n in "${names[@]}"; do
  [[ "$n" == taskhub-* ]] || die "container '$n' thuộc project taskhub nhưng tên lạ — dừng để an toàn"
done

container_of() {
  docker ps -a \
    --filter "label=com.docker.compose.project=${PROJECT}" \
    --filter "label=com.docker.compose.service=$1" \
    --format '{{.Names}}' | head -n 1
}
pg="$(container_of postgres)"
app="$(container_of taskhub)"
[[ "$pg" == taskhub-* ]] || die "không thấy container postgres của project taskhub"
[[ "$app" == taskhub-* ]] || die "không thấy container taskhub (app) của project taskhub"

mkdir -p "$STATE_DIR"
[[ ! -f "$STATE_DIR/active" ]] || die "đang có một drill chưa gỡ ($(cat "$STATE_DIR/active")). Chạy ./reset.sh trước"

if [[ "$choice" == "RANDOM" ]]; then
  choice="$(printf 'A\nB\nC\n' | shuf -n 1)"
fi

now="$(date -u +%FT%TZ)"
printf 'scenario=%s\nstarted=%s\npg=%s\napp=%s\n' "$choice" "$now" "$pg" "$app" > "$STATE_DIR/active"

# Chạy một lệnh trễ ở nền, trong process group riêng (setsid) để reset.sh hủy được cả nhóm.
schedule() {
  local delay="$1" cmd="$2"
  setsid bash -c "sleep $delay; $cmd" < /dev/null > /dev/null 2>&1 &
  echo "$!" >> "$STATE_DIR/pids"
}

case "$choice" in
  A)
    # Database "biến mất" vào một thời điểm ngẫu nhiên trong 1–10 phút tới.
    schedule "$(( RANDOM % 541 + 60 ))" "docker stop '$pg'"
    ;;
  B)
    # Một lần "deploy" cấu hình lỗi: đổi biến môi trường của app qua file override riêng của drill.
    cat > "$STATE_DIR/compose.drill.yaml" <<'EOF'
services:
  taskhub:
    environment:
      SPRING_DATASOURCE_PASSWORD: "tuned-by-ci-bot"
EOF
    files=(-f "$TASKHUB_DIR/compose.yaml")
    [[ -f "$TASKHUB_DIR/compose.override.yaml" ]] && files+=(-f "$TASKHUB_DIR/compose.override.yaml")
    files+=(-f "$STATE_DIR/compose.drill.yaml")
    if ! out="$(docker compose -p "$PROJECT" --project-directory "$TASKHUB_DIR" "${files[@]}" \
        up -d --no-deps --no-build taskhub 2>&1)"; then
      rm -f "$STATE_DIR/active" "$STATE_DIR/compose.drill.yaml"
      die "không áp được cấu hình drill:"$'\n'"$out"
    fi
    # Dấu vết mà một on-call giỏi sẽ đi tìm: "gần đây có gì thay đổi?"
    echo "$now deploy taskhub config by ci-bot: \"tune datasource settings\" (drill PR #42)" \
      >> "$STATE_DIR/deploy-history.log"
    ;;
  C)
    # Database "treo": container vẫn tồn tại nhưng mọi process bị đóng băng (docker pause).
    # Lưới an toàn: tự gỡ sau khoảng 20 phút kể từ lúc treo nếu bạn chưa tìm ra.
    schedule "$(( RANDOM % 241 + 60 ))" "docker pause '$pg'"
    schedule 1500 "docker unpause '$pg'"
    ;;
esac

cat <<EOF
Drill đã bắt đầu lúc $now (UTC). Kịch bản được giữ kín trong $STATE_DIR/active — ĐỪNG mở file đó.

Bây giờ bạn là on-call:
  1. Mở một terminal khác chạy ./traffic.sh (giả lập người dùng).
  2. Mở incident-notes.md, ghi giờ UTC cho MỌI quan sát và hành động.
  3. Chờ alert (webhook-debug / Telegram), rồi: dashboard → log → "gần đây có gì đổi?" → giảm thiểu.
  4. Khi đã ổn định: ./reset.sh (dọn phần còn sót), rồi viết postmortem.
EOF
