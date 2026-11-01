#!/bin/bash
# =============================================================================
# Break-fix CI #1 — kiểm tra tĩnh tiến độ sửa lỗi
#
# Chạy trong thư mục repo luyện tập trên WSL:
#   cd ~/devops-lab/05-cicd/bf05-ci
#   bash /đường-dẫn/verify.sh            # chỉ kiểm tra tĩnh
#   bash /đường-dẫn/verify.sh --lint     # thêm actionlint chạy bằng Docker (cần Docker Desktop đang chạy)
#
# Script này chỉ ĐỌC file và lịch sử Git, không sửa gì.
# Kiểm tra tĩnh xanh KHÔNG có nghĩa là xong: tiêu chí cuối cùng là lần chạy trên GitHub (xem README).
#
# ⚠️ ĐỪNG đọc phần còn lại của file này trước khi làm xong — nó chứa đáp án.
# =============================================================================
set -euo pipefail

lint=false
if [ "${1:-}" = "--lint" ]; then
  lint=true
fi

wf=".github/workflows/ci.yml"
pass=0
fail=0

ok()  { echo "  [PASS] $*"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] $*"; fail=$((fail + 1)); }

# Lấy giá trị của khóa YAML đầu tiên khớp tên (bỏ dấu nháy, ghi chú cuối dòng, khoảng trắng)
yaml_value() {
  grep -E "^[[:space:]]*$1:" "$wf" | head -n 1 \
    | sed -E "s/^[[:space:]]*$1:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^['\"]//; s/['\"][[:space:]]*$//; s/[[:space:]]+$//"
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "DỪNG: hãy cd vào ~/devops-lab/05-cicd/bf05-ci trước khi chạy." >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"
[ -f "$wf" ] || { echo "DỪNG: không thấy $wf trong repo này." >&2; exit 1; }

echo "== Break-fix CI #1 — kiểm tra tĩnh"
echo

# 1. Sự kiện kích hoạt
if grep -Eq '^[[:space:]]*pull_request:' "$wf" && ! grep -Eq '^[[:space:]]*pull-request:' "$wf"; then
  ok "1. Sự kiện kích hoạt"
else
  bad "1. Sự kiện kích hoạt"
fi

# 2. Nhãn runner: mọi job phải ghim ubuntu-24.04
runners="$(grep -E '^[[:space:]]*runs-on:' "$wf" | sed -E 's/^[[:space:]]*runs-on:[[:space:]]*//; s/[[:space:]]+#.*$//; s/["'\'']//g')"
if [ -n "$runners" ] && ! printf '%s\n' "$runners" | grep -vqx 'ubuntu-24.04'; then
  ok "2. Runner"
else
  bad "2. Runner (giá trị hiện tại: $(printf '%s ' $runners))"
fi

# 3. File trong commit HEAD (GitHub chỉ thấy những gì đã commit)
mode_head="$(git ls-tree HEAD app/mvnw | awk '{print $1}')"
mode_index="$(git ls-files -s app/mvnw | awk '{print $1}')"
if [ "$mode_head" = "100755" ]; then
  ok "3. File trong commit HEAD"
elif [ "$mode_index" = "100755" ]; then
  bad "3. File trong commit HEAD (đã sửa trong index nhưng CHƯA commit)"
else
  bad "3. File trong commit HEAD"
fi

# 4. Môi trường build
java_version="$(yaml_value java-version)"
if [ "$java_version" = "21" ]; then
  ok "4. Môi trường build"
else
  bad "4. Môi trường build"
fi

# 5. Service container có thể truy cập từ runner
if grep -Eq '^[[:space:]]*-[[:space:]]*["'\'']?5432:5432["'\'']?[[:space:]]*(#.*)?$' "$wf"; then
  ok "5. Service container"
else
  bad "5. Service container"
fi

# 6. Cấu hình kết nối database
pg_pass="$(yaml_value POSTGRES_PASSWORD)"
app_pass="$(yaml_value SPRING_DATASOURCE_PASSWORD)"
if [ -n "$pg_pass" ] && [ "$pg_pass" = "$app_pass" ]; then
  ok "6. Cấu hình kết nối database"
  case "$pg_pass" in
    *secrets.*) echo "         ↳ Hai bên cùng dùng secret. Script không kiểm tra được secret đó đã được tạo trên GitHub hay chưa." ;;
  esac
else
  bad "6. Cấu hình kết nối database"
fi

# 7. Báo cáo test khi job đỏ
if grep -Eq '^[[:space:]]*path:[[:space:]]*["'\'']?(\./)?app/target/surefire-reports/?["'\'']?[[:space:]]*(#.*)?$' "$wf"; then
  ok "7. Artifact báo cáo test"
else
  bad "7. Artifact báo cáo test"
fi

echo
echo "== Trạng thái Git"
if [ -n "$(git status --porcelain)" ]; then
  echo "  [WARN] Còn thay đổi chưa commit — GitHub sẽ không thấy chúng."
fi
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  ahead="$(git rev-list --count '@{u}..HEAD')"
  if [ "$ahead" -gt 0 ]; then
    echo "  [WARN] Có $ahead commit chưa push lên GitHub."
  else
    echo "  [OK]   Nhánh hiện tại đã đồng bộ với remote."
  fi
else
  echo "  [WARN] Nhánh hiện tại chưa có upstream (chưa 'git push -u origin main'?)."
fi

if [ "$lint" = true ]; then
  echo
  echo "== actionlint (Docker image rhysd/actionlint:1.7.12)"
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:1.7.12 -color; then
      echo "  [OK]   actionlint không báo lỗi."
    else
      echo "  [WARN] actionlint báo lỗi (xem phía trên)."
    fi
  else
    echo "  [SKIP] Docker chưa chạy hoặc chưa cài — bỏ qua actionlint."
  fi
fi

echo
echo "Kết quả kiểm tra tĩnh: $pass PASS, $fail FAIL"
if [ "$fail" -eq 0 ]; then
  echo "Tĩnh đã ổn. Tiêu chí cuối cùng nằm trên GitHub: lần chạy xanh trên main + artifact test-reports khi cố ý làm đỏ một test (README mục 7)."
fi
