#!/usr/bin/env bash
# verify.sh — kiểm tra tiến độ Break-fix Docker #1.
# ĐỪNG ĐỌC FILE NÀY TRƯỚC KHI LÀM XONG: nó chứa đáp án.
# Chạy trên WSL, trong thư mục lab:  ./verify.sh
set -u
cd "$(dirname "$0")" || exit 1

PASS=0
TOTAL=8
ok() { echo "  ✅ [$1] $2"; PASS=$((PASS + 1)); }
ko() { echo "  ❌ [$1] $2"; }

if ! docker info >/dev/null 2>&1; then
  echo "Docker chưa chạy (mở Docker Desktop trước)."; exit 1
fi

cid() { docker compose ps -q "$1" 2>/dev/null; }
running() { [ -n "$1" ] && [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

API=$(cid api)
PG=$(cid postgres)
NG=$(cid nginx)

echo "Break-fix Docker #1 — verify"
echo

# 1. api đang chạy và trỏ DB tới tên service, không phải localhost
if running "$API"; then
  dbhost=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$API" | sed -n 's/^DB_HOST=//p')
  if [ "$dbhost" = "postgres" ]; then
    ok 1 "api đang chạy và kết nối DB qua tên service"
  else
    ko 1 "api đang chạy nhưng DB_HOST='$dbhost'"
  fi
else
  ko 1 "api không chạy (docker compose ps -a)"
fi

# 2. thứ tự khởi động: postgres có healthcheck, api chờ service_healthy
cfg=$(docker compose config --format json 2>/dev/null)
order=$(printf '%s' "$cfg" | python3 -c '
import json, sys
try:
    c = json.load(sys.stdin)
except Exception:
    print("bad"); sys.exit()
s = c.get("services", {})
hc = "healthcheck" in s.get("postgres", {}) and not s["postgres"]["healthcheck"].get("disable", False)
dep = s.get("api", {}).get("depends_on", {}).get("postgres", {}).get("condition")
print("ok" if hc and dep == "service_healthy" else "no")
' 2>/dev/null)
if [ "$order" = "ok" ]; then
  ok 2 "api chỉ khởi động khi postgres đã healthy"
else
  ko 2 "thứ tự khởi động api/postgres chưa đảm bảo"
fi

# 3. nginx định tuyến /api/ tới api
if running "$NG"; then
  hostport=$(docker compose port nginx 80 2>/dev/null | head -1 | sed 's/.*://')
  body=$(curl -s -m 5 "http://localhost:${hostport:-18000}/api/health" 2>/dev/null)
  if printf '%s' "$body" | grep -q '"status": "UP"'; then
    ok 3 "http://localhost:${hostport:-18000}/api/health trả về UP qua nginx"
  else
    ko 3 "/api/health qua nginx chưa trả về UP"
  fi
else
  ko 3 "nginx không chạy"
fi

# 4. dữ liệu postgres nằm trong named volume đúng đường dẫn PGDATA
if [ -n "$PG" ]; then
  mnt=$(docker inspect -f '{{range .Mounts}}{{.Type}}|{{.Name}}|{{.Destination}}{{println}}{{end}}' "$PG" \
        | awk -F'|' '$3=="/var/lib/postgresql/data"')
  vname=$(printf '%s' "$mnt" | cut -d'|' -f2)
  if [ -n "$mnt" ] && [ "$(printf '%s' "$mnt" | cut -d'|' -f1)" = "volume" ] \
     && ! printf '%s' "$vname" | grep -Eq '^[0-9a-f]{64}$'; then
    ok 4 "dữ liệu postgres nằm trong named volume '$vname'"
  else
    ko 4 "dữ liệu postgres chưa nằm trong named volume (sẽ mất sau down/up)"
  fi
else
  ko 4 "không tìm thấy container postgres"
fi

# 5. PID 1 của api là python (nhận được SIGTERM)
if running "$API"; then
  pid1=$(docker compose exec -T api cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ' | awk '{print $1}')
  case "$(basename "${pid1:-none}")" in
    python*) ok 5 "PID 1 của api là python — docker stop dừng ngay, không chờ 10 giây" ;;
    *) ko 5 "PID 1 của api là '${pid1:-?}'" ;;
  esac
else
  ko 5 "api không chạy nên chưa kiểm tra được PID 1"
fi

# 6. postgres không mở port ra mọi địa chỉ của host
if [ -n "$PG" ]; then
  exposed=$(docker inspect -f '{{json .HostConfig.PortBindings}}' "$PG" | python3 -c '
import json, sys
b = json.load(sys.stdin) or {}
bad = [x for v in b.values() for x in (v or []) if x.get("HostIp", "") not in ("127.0.0.1", "::1")]
print("bad" if bad else "ok")
' 2>/dev/null)
  if [ "$exposed" = "ok" ]; then
    ok 6 "postgres không bị publish ra mọi địa chỉ của host"
  else
    ko 6 "postgres đang publish port ra mọi địa chỉ của host"
  fi
else
  ko 6 "không tìm thấy container postgres"
fi

# 7. không còn secret hard-code trong compose.yaml, .env được Git bỏ qua
if ! grep -q 'taskhub123' compose.yaml && [ -f .env ] && grep -Eqx '/?\.env' .gitignore 2>/dev/null; then
  ok 7 "mật khẩu không còn nằm trong compose.yaml, .env có trong .gitignore"
else
  ko 7 "secret vẫn hard-code trong compose.yaml hoặc .env chưa được Git bỏ qua"
fi

# 8. api chạy non-root
if running "$API"; then
  uid=$(docker compose exec -T api id -u 2>/dev/null | tr -d '\r')
  if [ -n "$uid" ] && [ "$uid" != "0" ]; then
    ok 8 "api chạy bằng UID $uid (non-root)"
  else
    ko 8 "api đang chạy bằng root"
  fi
else
  ko 8 "api không chạy nên chưa kiểm tra được user"
fi

echo
echo "Kết quả: $PASS/$TOTAL"
[ "$PASS" -eq "$TOTAL" ] && echo "🎉 Hoàn thành! Nhớ làm phép thử dữ liệu bền (mục 5, ticket #5003) và viết nhật ký."
