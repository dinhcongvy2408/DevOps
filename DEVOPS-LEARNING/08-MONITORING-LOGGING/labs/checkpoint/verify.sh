#!/usr/bin/env bash
# Kiểm tra Checkpoint GĐ 8 — Phần C (ck08). Chỉ ĐỌC, không sửa gì.
# Lưu ý: alert có "for: 2m" → sau khi sửa rule, chờ ~3 phút rồi mới chạy lại.

set -uo pipefail

LAB_DIR="${CK08_DIR:-$HOME/devops-lab/08-monitoring/ck08}"
if [[ -f "$LAB_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$LAB_DIR/.env"; set +a
fi
PROM="http://127.0.0.1:${CK08_PROM_PORT:-19190}"
WEBHOOK="http://127.0.0.1:${CK08_WEBHOOK_PORT:-15101}"
LOKI="http://127.0.0.1:${CK08_LOKI_PORT:-13110}"

command -v python3 >/dev/null 2>&1 || { echo "Cần python3"; exit 2; }

pass=0; total=7
ok()   { echo "  ✅ $*"; pass=$((pass + 1)); }
fail() { echo "  ❌ $*"; }
get()  { curl -fsS --max-time 8 "$@" 2>/dev/null; }

echo "Checkpoint ck08 — kiểm tra"

# 1. Mọi target UP
result="$(get "$PROM/api/v1/targets?state=active" | python3 -c '
import json, sys
try:
    t = json.load(sys.stdin)["data"]["activeTargets"]
except Exception:
    print("không gọi được Prometheus"); sys.exit()
down = ["%s (%s)" % (x["labels"].get("job"), x.get("lastError") or x["health"]) for x in t if x["health"] != "up"]
print("OK" if t and not down else "; ".join(down) or "không có target")
')"
if [[ "$result" == "OK" ]]; then ok "1. Mọi target Prometheus đều UP"; else fail "1. $result"; fi

# 2–3. Alert đang firing trên Prometheus
alerts="$(get "$PROM/api/v1/alerts")"
n=2
for name in HighErrorRate HighLatencyP95; do
  state="$(printf '%s' "$alerts" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    a = json.load(sys.stdin)["data"]["alerts"]
except Exception:
    print("?"); sys.exit()
states = [x["state"] for x in a if x["labels"].get("alertname") == name]
print("firing" if "firing" in states else (states[0] if states else "không có"))
' "$name")"
  if [[ "$state" == firing ]]; then ok "$n. $name đang firing trên Prometheus"
  else fail "$n. $name trên Prometheus: $state (đã chờ đủ 'for' chưa?)"; fi
  n=$((n + 1))
done

# 4–5. Webhook nhận được cả hai
received="$(get "$WEBHOOK/")"
for name in HighErrorRate HighLatencyP95; do
  if printf '%s' "$received" | python3 -c '
import json, sys
name = sys.argv[1]
sys.exit(0 if any(a.get("alertname") == name and a.get("status") == "firing" for a in json.load(sys.stdin)) else 1)
' "$name" 2>/dev/null; then ok "$n. webhook-debug đã nhận $name (firing)"
  else fail "$n. webhook-debug chưa nhận $name"; fi
  n=$((n + 1))
done

# 6. request_id không còn là label của Loki.
#    KHÔNG dùng /loki/api/v1/labels: API đó trả nhãn của mọi stream còn trong bộ nhớ ingester
#    (tới khi flush, mặc định chunk_idle_period = 30 phút) dù đã lọc thời gian.
#    Thay vào đó: lấy log 60 giây gần nhất và xem nhãn của các stream THỰC SỰ có dòng mới.
start_ns="$(( $(date +%s) - 60 ))000000000"
recent="$(get -G "$LOKI/loki/api/v1/query_range" --data-urlencode 'query={compose_service="app"}'             --data-urlencode "start=$start_ns" --data-urlencode 'limit=200')"
if [[ -z "$recent" ]]; then
  fail "6. Không gọi được Loki ở $LOKI"
else
  res="$(printf '%s' "$recent" | python3 -c '
import json, sys
r = json.load(sys.stdin)["data"]["result"]
bad = sum(1 for s in r if "request_id" in s["stream"])
print("EMPTY" if not r else ("BAD %d/%d" % (bad, len(r)) if bad else "OK %d" % len(r)))
')"
  case "$res" in
    OK*)   ok "6. Log 60 giây gần nhất không còn label request_id (${res#OK } stream)" ;;
    EMPTY) fail "6. Không có log nào của app trong 60 giây gần nhất (Alloy/Loki có chạy?)" ;;
    *)     fail "6. request_id vẫn là label của Loki (${res#BAD } stream mới có label này)" ;;
  esac
fi

# 7. Vẫn tìm được log theo request_id (từ nội dung, không phải label)
count="$(get -G "$LOKI/loki/api/v1/query" \
  --data-urlencode 'query=sum(count_over_time({compose_service="app"} | json | request_id != "" [5m]))' \
  | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)["data"]["result"]
    print(int(float(r[0]["value"][1])) if r else 0)
except Exception:
    print(0)
')"
if [[ "$count" -ge 1 ]]; then ok "7. Lọc được $count dòng log theo request_id bằng | json trong 5 phút"
else fail "7. Không lọc được log theo request_id bằng | json (Alloy còn gửi log không?)"; fi

echo "Kết quả: $pass/$total đạt"
[[ "$pass" -eq "$total" ]]
