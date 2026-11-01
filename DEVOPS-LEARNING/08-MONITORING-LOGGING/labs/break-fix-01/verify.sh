#!/usr/bin/env bash
# Kiểm tra tiến độ Break-fix Observability #1 (bf08). Chỉ ĐỌC, không sửa gì.
#   bash verify.sh          → 7 mục kiểm tra nhanh
#   bash verify.sh --e2e    → thêm mục 8: dừng app thật, chờ AppDown tới webhook, bật lại app (~3–4 phút)

set -uo pipefail

LAB_DIR="${BF08_DIR:-$HOME/devops-lab/08-monitoring/bf08}"
if [[ -f "$LAB_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "$LAB_DIR/.env"; set +a
fi
PROM="http://127.0.0.1:${BF08_PROM_PORT:-19090}"
WEBHOOK="http://127.0.0.1:${BF08_WEBHOOK_PORT:-15001}"
LOKI="http://127.0.0.1:${BF08_LOKI_PORT:-13100}"
GRAFANA="http://127.0.0.1:${BF08_GRAFANA_PORT:-13000}"
GPASS="${BF08_GRAFANA_PASSWORD:-bf08-admin}"

command -v python3 >/dev/null 2>&1 || { echo "Cần python3 (có sẵn trên Ubuntu 24.04)"; exit 2; }

pass=0; total=7
ok()   { echo "  ✅ $*"; pass=$((pass + 1)); }
fail() { echo "  ❌ $*"; }

get() { curl -fsS --max-time 8 "$@" 2>/dev/null; }
# Không có -f: Grafana trả HTTP 400 kèm JSON mô tả lỗi khi data source hỏng — cần giữ lại phần thân đó
getbody() { curl -sS --max-time 8 "$@" 2>/dev/null; }

echo "Break-fix bf08 — kiểm tra"

# 1. Mọi target của Prometheus đều UP
targets_json="$(get "$PROM/api/v1/targets?state=active")"
if [[ -z "$targets_json" ]]; then
  fail "1. Không gọi được Prometheus ở $PROM"
else
  result="$(printf '%s' "$targets_json" | python3 -c '
import json, sys
t = json.load(sys.stdin)["data"]["activeTargets"]
down = ["%s (%s)" % (x["labels"].get("job"), x.get("lastError") or x["health"]) for x in t if x["health"] != "up"]
print("OK" if t and not down else "; ".join(down) or "không có target")
')"
  if [[ "$result" == "OK" ]]; then ok "1. Mọi target Prometheus đều UP"; else fail "1. Target chưa UP: $result"; fi
fi

# 2–3. Data source trong Grafana khỏe
for ds in prometheus loki; do
  n=$([[ "$ds" == prometheus ]] && echo 2 || echo 3)
  health="$(getbody -u "admin:$GPASS" "$GRAFANA/api/datasources/uid/$ds/health" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin); print(d.get("status", "?"), "-", d.get("message", "")[:120])
except Exception:
    print("? - không đọc được phản hồi")
')"
  if [[ "$health" == OK* ]]; then ok "$n. Data source Grafana '$ds' khỏe"; else fail "$n. Data source Grafana '$ds': $health"; fi
done

# 4. Biểu thức của AppDown khớp series thật
rules_json="$(get "$PROM/api/v1/rules?type=alert")"
appdown="$(printf '%s' "$rules_json" | python3 -c '
import json, sys
try:
    groups = json.load(sys.stdin)["data"]["groups"]
except Exception:
    sys.exit()
for g in groups:
    for r in g["rules"]:
        if r.get("name") == "AppDown":
            print(json.dumps({"query": r["query"], "labels": r.get("labels", {})}))
')"
if [[ -z "$appdown" ]]; then
  fail "4. Không tìm thấy rule AppDown trong Prometheus"
  fail "5. (bỏ qua) chưa có rule AppDown"
else
  selector="$(printf '%s' "$appdown" | python3 -c '
import json, re, sys
q = json.load(sys.stdin)["query"]
m = re.search(r"up\{[^}]*\}", q)
print(m.group(0) if m else "")
')"
  if [[ -z "$selector" ]]; then
    fail "4. Không tự kiểm tra được biểu thức AppDown (không thấy selector up{...}) — hãy chứng minh bằng verify.sh --e2e"
  else
    count="$(get -G "$PROM/api/v1/query" --data-urlencode "query=$selector" | python3 -c '
import json, sys
try: print(len(json.load(sys.stdin)["data"]["result"]))
except Exception: print(0)
')"
    if [[ "$count" -ge 1 ]]; then ok "4. Selector $selector của AppDown khớp $count series"
    else fail "4. Selector $selector của AppDown không khớp series nào — rule sẽ không bao giờ firing"; fi
  fi

  # 5. Nhãn của AppDown được route tới webhook-debug
  args="$(printf '%s' "$appdown" | python3 -c '
import json, sys
labels = json.load(sys.stdin)["labels"]
labels["alertname"] = "AppDown"
print(" ".join(f"{k}={v}" for k, v in labels.items()))
')"
  # shellcheck disable=SC2086
  route="$(docker compose -p bf08 exec -T alertmanager amtool config routes test \
            --config.file=/etc/alertmanager/alertmanager.yml $args 2>&1 | tail -n 1)"
  if [[ "$route" == *webhook-debug* ]]; then ok "5. AppDown ($args) được route tới webhook-debug"
  else fail "5. AppDown ($args) được route tới: ${route:-?}"; fi
fi

# 6. Webhook đã nhận Watchdog
if get "$WEBHOOK/" | python3 -c '
import json, sys
sys.exit(0 if any(a.get("alertname") == "Watchdog" for a in json.load(sys.stdin)) else 1)
' 2>/dev/null; then ok "6. webhook-debug đã nhận Watchdog (đường ống cảnh báo thông)"
else fail "6. webhook-debug chưa nhận Watchdog"; fi

# 7. Loki có log của app
lines="$(get -G "$LOKI/loki/api/v1/query_range" --data-urlencode 'query={compose_service="app"}' \
          --data-urlencode 'limit=5' | python3 -c '
import json, sys
try: print(sum(len(s["values"]) for s in json.load(sys.stdin)["data"]["result"]))
except Exception: print(0)
')"
if [[ "$lines" -ge 1 ]]; then ok "7. Loki có log của app (mẫu $lines dòng)"
else fail "7. Loki chưa có log nào với {compose_service=\"app\"}"; fi

# 8. (tùy chọn) Thử thật: dừng app → AppDown phải tới webhook
if [[ "${1:-}" == "--e2e" ]]; then
  total=8
  echo "  … Dừng app, chờ AppDown tới webhook (tối đa 240 giây)"
  since="$(date -u +%Y-%m-%dT%H:%M:%S)"
  docker compose -p bf08 stop app >/dev/null 2>&1
  got=""
  for _ in $(seq 1 48); do
    sleep 5
    if get "$WEBHOOK/" | python3 -c '
import json, sys
since = sys.argv[1]
sys.exit(0 if any(a.get("alertname") == "AppDown" and a.get("status") == "firing"
                  and (a.get("startsAt") or "") >= since for a in json.load(sys.stdin)) else 1)
' "$since" 2>/dev/null; then got=yes; break; fi
  done
  docker compose -p bf08 start app >/dev/null 2>&1
  if [[ -n "$got" ]]; then ok "8. Dừng app → AppDown firing đã tới webhook-debug"
  else fail "8. Dừng app 4 phút mà webhook-debug không nhận AppDown"; fi
fi

echo "Kết quả: $pass/$total đạt"
[[ "$pass" -eq "$total" ]]
