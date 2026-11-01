#!/usr/bin/env bash
# Kiểm tra Checkpoint GĐ 7 — Phần C. Chạy trong ~/devops-lab/07-terraform/ck07.
# Lưu ý: mục 5 CHẠY playbook một lần (đo tính idempotent) — nếu hệ thống đã đúng, lần chạy này không đổi gì.

set -uo pipefail

BASE="${HOME}/devops-lab/07-terraform"
DIR="${BASE}/ck07"
STATE_DIR="${BASE}/.ck07"
[[ -d "$DIR" && -d "$STATE_DIR" ]] || { echo "Chưa có môi trường ck07 — chạy setup.sh trước."; exit 2; }
cd "$DIR"
PORT="$(cat "$STATE_DIR/port")"

pass=0; fail=0
ok()  { echo "  ✅ $*"; pass=$((pass + 1)); }
bad() { echo "  ❌ $*"; fail=$((fail + 1)); }

echo "== 1. terraform plan sạch"
terraform plan -detailed-exitcode -input=false -no-color -lock-timeout=5s > "$STATE_DIR/plan.out" 2>&1
rc=$?
case "$rc" in
  0) ok "No changes" ;;
  2) bad "Còn thay đổi: $(grep -m1 -E '^Plan:' "$STATE_DIR/plan.out")" ;;
  *) bad "plan lỗi (exit $rc): $(grep -m1 'Error' "$STATE_DIR/plan.out")" ;;
esac

echo "== 2. worker và web KHÔNG bị tạo lại, api đã gỡ"
same=1
for n in worker web; do
  want="$(cat "$STATE_DIR/$n.id")"
  got="$(docker inspect -f '{{.Id}}' "ck07-$n" 2> /dev/null || true)"
  [[ "$want" == "$got" ]] || { same=0; echo "     ck07-$n: ID ban đầu ${want:0:12}, hiện tại ${got:0:12}"; }
done
if [[ "$same" -eq 1 ]] && ! docker inspect ck07-api > /dev/null 2>&1; then
  ok "ck07-worker, ck07-web giữ nguyên; ck07-api đã xóa"
else
  bad "Có node bị tạo lại, hoặc ck07-api vẫn còn"
fi

echo "== 3. Địa chỉ trong state theo tên dịch vụ, không theo số thứ tự"
state="$(terraform state list 2> /dev/null || true)"
if grep -qx 'docker_container.node\["worker"\]' <<< "$state" \
  && grep -qx 'docker_container.node\["web"\]' <<< "$state" \
  && ! grep -qE 'docker_container\.node\[[0-9]+\]' <<< "$state"; then
  ok 'docker_container.node["worker"], docker_container.node["web"]'
else
  bad "State hiện có: $(grep docker_container <<< "$state" | tr '\n' ' ')"
fi

echo "== 4. Output mật khẩu được đánh dấu sensitive"
if terraform output -no-color 2> /dev/null | grep -qE '^db_password = <sensitive>'; then
  ok "db_password = <sensitive>"
else
  bad "terraform output không hiện 'db_password = <sensitive>'"
fi

echo "== 5. Playbook idempotent và thực sự chạy trên ck07-web"
ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0 ansible-playbook site.yml > "$STATE_DIR/play.out" 2>&1
play_rc=$?
recap="$(grep -E '^ck07-web +:' "$STATE_DIR/play.out" || true)"
ok_count="$(sed -nE 's/.*ok=([0-9]+).*/\1/p' <<< "$recap")"
if [[ "$play_rc" -eq 0 ]] && grep -q 'changed=0' <<< "$recap" && grep -q 'failed=0' <<< "$recap" && [[ "${ok_count:-0}" -ge 4 ]]; then
  ok "Lần chạy lại: $recap"
else
  bad "rc=$play_rc · recap ck07-web: ${recap:-<không có — play web không chạy trên host nào?>}"
fi

echo "== 6. nginx cấu hình hợp lệ, hardening đúng một dòng"
n_tokens="$(docker exec ck07-web sh -c 'grep -c "server_tokens" /etc/nginx/conf.d/hardening.conf' 2> /dev/null || echo 0)"
if docker exec ck07-web nginx -t > /dev/null 2>&1 && [[ "$n_tokens" -eq 1 ]]; then
  ok "nginx -t thành công, server_tokens xuất hiện 1 lần"
else
  bad "nginx -t lỗi hoặc server_tokens xuất hiện $n_tokens lần"
fi

echo "== 7. Web trả lời qua cổng $PORT"
if curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/" 2> /dev/null | grep -q "ck07 OK from ck07-web"; then
  ok "http://127.0.0.1:${PORT}/ trả 'ck07 OK from ck07-web'"
else
  bad "http://127.0.0.1:${PORT}/ không trả nội dung mong đợi"
fi

echo
echo "Kết quả: $pass/7 đạt"
[[ "$fail" -eq 0 ]]
