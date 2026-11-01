#!/bin/bash
# =============================================================================
# Break-fix CI #1 — tạo repo luyện tập có pipeline CI bị lỗi cài sẵn
#
# Chạy trên WSL:
#   bash setup.sh [đường-dẫn-repo-taskhub]     # mặc định: ~/projects/taskhub
#
# Script CHỈ ĐỌC repo taskhub của bạn (git archive HEAD) và tạo một thư mục MỚI:
#   ~/devops-lab/05-cicd/bf05-ci
# Không sửa, không xóa bất cứ thứ gì đã có.
#
# ⚠️ ĐỪNG đọc phần còn lại của file này trước khi làm bài — nó chứa đáp án.
# =============================================================================
set -euo pipefail

src="${1:-$HOME/projects/taskhub}"
dest="$HOME/devops-lab/05-cicd/bf05-ci"

die() {
  echo "DỪNG: $*" >&2
  exit 1
}

# --- Kiểm tra điều kiện ------------------------------------------------------
command -v git >/dev/null 2>&1 || die "không tìm thấy lệnh git."
command -v tar >/dev/null 2>&1 || die "không tìm thấy lệnh tar."

[ -d "$src" ] || die "không có thư mục '$src'. Truyền đường dẫn repo taskhub: bash setup.sh <đường-dẫn>"
git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "'$src' không phải một Git repository."
git -C "$src" rev-parse --verify --quiet HEAD >/dev/null \
  || die "repo '$src' chưa có commit nào."

for f in app/mvnw app/pom.xml docker/Dockerfile; do
  git -C "$src" cat-file -e "HEAD:$f" 2>/dev/null \
    || die "commit HEAD của '$src' không có '$f'. Hoàn thành dự án v0 (tuần 8) trước khi làm bài này."
done

# Repo luyện tập sẽ là PUBLIC → không được mang theo file secret.
if git -C "$src" ls-tree -r --name-only HEAD | grep -Eq '(^|/)\.env$'; then
  die "commit HEAD của '$src' chứa file .env. Xử lý việc lộ secret này trước (Module 03, bài 00 — rotate secret)."
fi

[ ! -e "$dest" ] || die "'$dest' đã tồn tại. Muốn làm lại từ đầu: tự kiểm tra rồi tự xóa thư mục đó, sau đó chạy lại script."

if [ -n "$(git -C "$src" status --porcelain)" ]; then
  echo "LƯU Ý: '$src' có thay đổi chưa commit. Bài lab chỉ dùng nội dung của commit HEAD." >&2
fi

# --- Tạo bản sao từ commit HEAD ----------------------------------------------
echo "[1/4] Sao chép nội dung commit HEAD của $src ..."
mkdir -p "$(dirname "$dest")"
mkdir "$dest"
git -C "$src" archive --format=tar HEAD | tar -x -C "$dest"

# Bản sao mới tạo, nằm trong thư mục của lab: bỏ workflow cũ (nếu bạn đã làm lab 01/02)
rm -rf -- "$dest/.github"

# --- Workflow CI "được bàn giao" ---------------------------------------------
echo "[2/4] Thêm workflow CI ..."
mkdir -p "$dest/.github/workflows"
cat > "$dest/.github/workflows/ci.yml" <<'EOF'
name: CI

on:
  pull-request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  build-test:
    name: build-test
    runs-on: ubuntu-24.4
    timeout-minutes: 15

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_DB: taskhub
          POSTGRES_USER: taskhub
          POSTGRES_PASSWORD: ci-only-password
        options: >-
          --health-cmd "pg_isready -U taskhub -d taskhub"
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10

    env:
      SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/taskhub
      SPRING_DATASOURCE_USERNAME: taskhub
      SPRING_DATASOURCE_PASSWORD: ${{ secrets.DB_PASSWORD }}

    defaults:
      run:
        working-directory: app

    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Set up JDK
        uses: actions/setup-java@b843ebf9b913146b38da2eaa7aeddf76074ae1ad # v6.1.0
        with:
          distribution: temurin
          java-version: '17'
          cache: maven

      - name: Build and test
        run: ./mvnw -B -ntp verify

      - name: Upload test reports
        if: failure()
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: test-reports
          path: target/surefire-reports/
          retention-days: 7
EOF

# --- Lỗi ngoài workflow --------------------------------------------------------
echo "[3/4] Chuẩn bị repo ..."
chmod -x "$dest/app/mvnw"

# --- Tạo repo Git mới ----------------------------------------------------------
echo "[4/4] Tạo Git repository mới và commit ..."
git -C "$dest" init -q -b main

author_args=()
if [ -z "$(git -C "$dest" config user.name || true)" ]; then
  author_args+=(-c "user.name=DevOps Learner")
fi
if [ -z "$(git -C "$dest" config user.email || true)" ]; then
  author_args+=(-c "user.email=you@example.com")
fi

git -C "$dest" add -A
git -C "$dest" ${author_args[@]+"${author_args[@]}"} commit -q -m "chore: import taskhub snapshot with CI pipeline"

cat <<MSG

Xong. Repo luyện tập: $dest

Bước tiếp theo:
  1. [GitHub] Tạo repo MỚI, RỖNG, Public tên: taskhub-ci-breakfix
     (KHÔNG tick README / .gitignore / license).
  2. [WSL]
       cd "$dest"
       git remote add origin git@github.com:<github-user>/taskhub-ci-breakfix.git
       git push -u origin main
  3. [GitHub] Mở tab Actions của repo taskhub-ci-breakfix và bắt đầu làm ticket trong README.

Repo taskhub thật của bạn ($src) không bị thay đổi.
MSG
