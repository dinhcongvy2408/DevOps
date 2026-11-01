#!/usr/bin/env bash
# verify.sh — kiểm tra Phần C của Checkpoint Docker.
# ĐỪNG ĐỌC FILE NÀY TRƯỚC KHI LÀM XONG: nó chứa đáp án.
# Chạy trên WSL, trong thư mục labs/checkpoint:  ./verify.sh
set -u
cd "$(dirname "$0")" || exit 1

PASS=0
TOTAL=4
ok() { echo "  ✅ [$1] $2"; PASS=$((PASS + 1)); }
ko() { echo "  ❌ [$1] $2"; }

if ! docker info >/dev/null 2>&1; then
  echo "Docker chưa chạy (mở Docker Desktop trước)."; exit 1
fi

API=$(docker compose ps -q api 2>/dev/null)
WEB=$(docker compose ps -q web 2>/dev/null)
state() { docker inspect -f "$2" "$1" 2>/dev/null; }

echo "Checkpoint Docker — Phần C — verify"
echo

# 1. api chạy được (không crash lúc khởi động)
if [ -n "$API" ] && [ "$(state "$API" '{{.State.Running}}')" = "true" ]; then
  ok 1 "reports-api đang chạy"
else
  ko 1 "reports-api không chạy (docker compose ps -a, docker compose logs api)"
fi

# 2. api healthy
if [ -n "$API" ] && [ "$(state "$API" '{{if .State.Health}}{{.State.Health.Status}}{{end}}')" = "healthy" ]; then
  ok 2 "reports-api healthy"
else
  ko 2 "reports-api chưa healthy"
fi

# 3. ghi được báo cáo qua web
code="000"
if [ -n "$WEB" ] && [ "$(state "$WEB" '{{.State.Running}}')" = "true" ]; then
  port=$(docker compose port web 80 2>/dev/null | head -1 | sed 's/.*://')
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -d '{"source":"verify","title":"check"}' \
    "http://localhost:${port:-18001}/api/reports")
fi
if [ "$code" = "201" ]; then
  ok 3 "POST /api/reports qua web trả 201 (ghi vào volume được)"
else
  ko 3 "POST /api/reports qua web trả '$code'"
fi

# 4. worker gửi báo cáo tới api thành công
found="no"
if [ -n "$API" ] && [ "$(state "$API" '{{.State.Running}}')" = "true" ]; then
  if docker compose exec -T api python -c '
import json, sys
try:
    rows = [json.loads(l) for l in open("/data/reports.jsonl") if l.strip()]
except OSError:
    sys.exit(1)
sys.exit(0 if any(r.get("source") == "worker" for r in rows) else 1)
' 2>/dev/null; then
    found="yes"
  fi
fi
if [ "$found" = "yes" ]; then
  ok 4 "worker gửi được báo cáo tới reports-api"
else
  ko 4 "chưa có báo cáo nào từ worker (docker compose logs worker)"
fi

echo
echo "Kết quả: $PASS/$TOTAL"
[ "$PASS" -eq "$TOTAL" ] && echo "🎉 Đạt Phần C về kỹ thuật — hoàn thành nhật ký debug để được tính điểm."
