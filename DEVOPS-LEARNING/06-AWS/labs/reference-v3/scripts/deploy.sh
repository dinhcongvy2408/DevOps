#!/usr/bin/env bash
# Triển khai taskhub trên EC2 theo tag image GHCR. Lỗi pull/health/smoke → quay về tag trước.
# Chạy bằng root: `sudo /opt/taskhub/scripts/deploy.sh <tag>` (v2) hoặc qua SSM Run Command (v3).
# Dựa trên scripts/deploy.sh của Module 05 bài 05; thêm: kiểm tra tag, lấy mật khẩu từ Parameter Store,
# tự gộp compose.aws.yaml nếu có (v3: log lên CloudWatch).
set -euo pipefail
cd "$(dirname "$0")/.."

new_tag="${1:?Cách dùng: scripts/deploy.sh <tag>, ví dụ v0.4.0 hoặc 9f8e7d6}"
if [[ ! "$new_tag" =~ ^([0-9a-f]{7}|v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?)$ ]]; then
  echo "Tag không hợp lệ: $new_tag" >&2
  exit 2
fi

region="${AWS_REGION:-ap-southeast-1}"
db_param="${TASKHUB_DB_PARAM:-/taskhub/dev/postgres-password}"

# Chỉ dùng file chỉ định rõ: KHÔNG gộp compose.override.yaml (file đó là để build trên laptop).
compose=(docker compose -f compose.yaml)
if [[ -f compose.aws.yaml ]]; then
  compose+=(-f compose.aws.yaml)
fi

# .env chứa mật khẩu → chỉ root đọc được. Không ghi đè cả file, chỉ thay đúng một dòng.
touch .env
chmod 600 .env
set_var() {
  local tmp
  tmp="$(mktemp)"
  grep -v "^${1}=" .env > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  cat "$tmp" > .env          # cat > giữ nguyên quyền 600 của .env
  rm -f "$tmp"
}

prev_tag="$(sed -n 's/^TASKHUB_IMAGE_TAG=//p' .env)"

# Mật khẩu sống trong Parameter Store (SecureString), không nằm trong Git, user data hay GitHub.
db_password="$(aws ssm get-parameter --region "$region" --name "$db_param" \
  --with-decryption --query Parameter.Value --output text)"
set_var POSTGRES_PASSWORD "$db_password"
unset db_password

grep -q '^NGINX_HOST_PORT=' .env || set_var NGINX_HOST_PORT 80
port="$(sed -n 's/^NGINX_HOST_PORT=//p' .env)"

deploy() {
  set_var TASKHUB_IMAGE_TAG "$1"
  "${compose[@]}" pull taskhub
  "${compose[@]}" up -d --wait --wait-timeout 180
}

smoke_test() {
  local cid image
  curl -fsS --retry 10 --retry-connrefused --retry-delay 3 \
    "http://localhost:${port}/actuator/health" | grep -q '"status":"UP"'
  cid="$("${compose[@]}" ps -q taskhub)"
  image="$(docker inspect -f '{{.Config.Image}}' "$cid")"
  [[ "$image" == *":$1" ]] || { echo "Container đang chạy image $image, không phải :$1" >&2; return 1; }
}

echo ">> Triển khai taskhub:${new_tag} (đang chạy: ${prev_tag:-chưa có})"
if deploy "$new_tag" && smoke_test "$new_tag"; then
  echo ">> OK: taskhub:${new_tag}"
  exit 0
fi

echo ">> LỖI khi triển khai ${new_tag}. Log gần nhất:" >&2
"${compose[@]}" logs taskhub --tail 40 >&2 || true

if [[ -z "$prev_tag" || "$prev_tag" == "$new_tag" ]]; then
  echo ">> Không có phiên bản trước để quay về" >&2
  exit 1
fi
echo ">> Rollback về ${prev_tag}" >&2
deploy "$prev_tag"
smoke_test "$prev_tag"
echo ">> Đã rollback về ${prev_tag}. Triển khai ${new_tag} THẤT BẠI." >&2
exit 1
