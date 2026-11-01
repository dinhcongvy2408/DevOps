#!/usr/bin/env bash
# Kiểm tra tiến độ Break-fix Terraform #1. Chạy trong thư mục ~/devops-lab/07-terraform/bf07.
# Chỉ đọc: không apply, không sửa gì. Lệnh plan có thể chờ tối đa 5 giây nếu state đang bị khóa.

set -uo pipefail

BASE="${HOME}/devops-lab/07-terraform"
DIR="${BASE}/bf07"
STATE_DIR="${BASE}/.bf07"

[[ -d "$DIR" && -d "$STATE_DIR" ]] || { echo "Chưa có môi trường bf07 — chạy setup.sh trước."; exit 2; }
cd "$DIR"

mapfile -t PORTS < "$STATE_DIR/ports"
PORT_A="${PORTS[0]}"; PORT_B="${PORTS[1]}"; PORT_HOTFIX="${PORTS[2]}"

pass=0; fail=0
ok()  { echo "  ✅ $*"; pass=$((pass + 1)); }
bad() { echo "  ❌ $*"; fail=$((fail + 1)); }

echo "== 1. Không còn ai giữ khóa state"
# Tìm process terraform (không tính zombie) đang chạy TRONG thư mục này — đó mới là thứ giữ khóa.
# (Không dựa vào PID của shell bọc ngoài: kill terraform xong, shell đó vẫn sống vì `sleep` của nó.)
holders=""
here="$(pwd -P)"
for p in $(pgrep -x terraform 2> /dev/null); do
  [[ "$(readlink -f "/proc/$p/cwd" 2> /dev/null)" == "$here" ]] && holders+="$p "
done
if [[ -n "$holders" ]]; then
  bad "Vẫn còn process terraform đang chạy trong thư mục này (PID: ${holders% }) — nó giữ khóa state"
elif [[ -e .terraform.tfstate.lock.info ]]; then
  bad "Vẫn còn file .terraform.tfstate.lock.info (có process terraform nào khác đang chạy trong thư mục này?)"
else
  ok "State không bị khóa"
fi

echo "== 2. Ràng buộc phiên bản provider khớp với lock file"
# `terraform validate` KHÔNG kiểm tra lock file (đã thử: vẫn "Success!" khi lệch) → dùng plan không khóa,
# không refresh: chỉ đọc, không ghi state, nhưng có nạp provider theo lock file.
terraform plan -lock=false -refresh=false -input=false -no-color > "$STATE_DIR/lockcheck.out" 2>&1
if grep -q 'Inconsistent dependency lock file' "$STATE_DIR/lockcheck.out"; then
  bad "Ràng buộc version trong versions.tf không khớp .terraform.lock.hcl"
else
  ok "Ràng buộc provider khớp lock file"
fi

echo "== 3. Code và hạ tầng khớp nhau (plan không còn thay đổi)"
terraform plan -detailed-exitcode -input=false -no-color -lock-timeout=5s > "$STATE_DIR/plan.out" 2>&1
rc=$?
case "$rc" in
  0) ok "plan: No changes" ;;
  2) bad "plan vẫn còn thay đổi: $(grep -m1 -E '^Plan:' "$STATE_DIR/plan.out" || echo 'xem terraform plan')" ;;
  *) bad "plan lỗi (exit $rc) — dòng đầu: $(grep -m1 -i 'error' "$STATE_DIR/plan.out" || echo 'chạy terraform plan để xem')" ;;
esac

echo "== 4. State có đủ tài nguyên, không trùng"
state="$(terraform state list 2> /dev/null || true)"
missing=()
for addr in docker_image.nginx docker_network.bf07 docker_volume.shared docker_volume.backup local_file.index docker_container.web_b; do
  grep -qx "$addr" <<< "$state" || missing+=("$addr")
done
web_a_count="$(grep -cxE 'docker_container\.(web_a|web_primary)' <<< "$state")"
if [[ ${#missing[@]} -eq 0 && "$web_a_count" -eq 1 ]]; then
  ok "Đủ 7 địa chỉ trong state"
else
  bad "State thiếu/thừa: thiếu [${missing[*]:-}] · số địa chỉ cho bf07-web-a = $web_a_count (phải là 1)"
fi

echo "== 5. bf07-web-a KHÔNG bị tạo lại (không gián đoạn dịch vụ)"
orig_id="$(cat "$STATE_DIR/web-a.id")"
cur_id="$(docker inspect -f '{{.Id}}' bf07-web-a 2> /dev/null || true)"
if [[ -n "$cur_id" && "$cur_id" == "$orig_id" ]]; then
  ok "Vẫn là container ban đầu (${cur_id:0:12})"
else
  bad "bf07-web-a đã bị xóa/tạo lại (ID ban đầu ${orig_id:0:12}, hiện tại ${cur_id:0:12})"
fi

echo "== 6. Hai web trả đúng nội dung trên cổng chuẩn"
for p in "$PORT_A" "$PORT_B"; do
  if curl -fsS --max-time 3 "http://127.0.0.1:${p}/" 2> /dev/null | grep -q "bf07 OK"; then
    ok "Cổng $p trả 'bf07 OK'"
  else
    bad "Cổng $p không trả 'bf07 OK'"
  fi
done

echo "== 7. Không còn container 'hotfix' ngoài Terraform"
names="$(docker ps -a --filter 'name=^bf07-' --format '{{.Names}}' | sort | tr '\n' ' ')"
if [[ "$names" == "bf07-web-a bf07-web-b " ]] && ! docker ps --format '{{.Ports}}' | grep -q "127.0.0.1:${PORT_HOTFIX}->"; then
  ok "Chỉ còn bf07-web-a, bf07-web-b; cổng $PORT_HOTFIX đã đóng"
else
  bad "Container bf07-*: [$names] · cổng $PORT_HOTFIX còn mở? $(docker ps --format '{{.Names}} {{.Ports}}' | grep "${PORT_HOTFIX}->" || echo không)"
fi

echo
echo "Kết quả: $pass đạt, $fail chưa đạt"
[[ "$fail" -eq 0 ]] && echo "🎉 Hoàn thành! Viết báo cáo theo mục 'Sản phẩm phải nộp' trong README."
[[ "$fail" -eq 0 ]]
