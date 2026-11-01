#!/bin/bash
# Kiểm tra tiến độ Break-fix Network #1. Chạy trong container client: verify
# (Học viên không đọc file này — nó chứa đáp án.)

pass=0
total=0

check() {
  local desc="$1"
  shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then
    printf '  [OK]   %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf '  [FAIL] %s\n' "$desc"
  fi
}

http_code_is() {
  local expected="$1" url="$2" max_time="$3"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -m "$max_time" "$url")
  [ "$code" = "$expected" ]
}

hosts_matches_dns() {
  local from_hosts from_dns
  from_hosts=$(getent hosts api.internal | awk '{print $1; exit}')
  from_dns=$(dig +short api.internal | head -1)
  [ -n "$from_dns" ] && [ "$from_hosts" = "$from_dns" ] \
    && curl -s -m 5 http://api.internal:8000/health | grep -q '"service": "api"'
}

echo "Break-fix Network #1 — kiểm tra:"
check "web trả lời trang gốc (http://web/)"                            http_code_is 200 http://web/ 5
check "#3001a api nhận kết nối từ máy khác trong mạng (api:8000)"      nc -z -w 3 api 8000
check "#3001b web chuyển /api/ tới api thành công"                     http_code_is 200 http://web/api/health 8
check "#3002  web gọi được reports (/reports/)"                        http_code_is 200 http://web/reports/daily 12
check "#3003  web gọi được status (/status/)"                          http_code_is 200 http://web/status/ 8
check "#3004  jump host phân giải api.internal giống DNS và gọi được"  hosts_matches_dns

echo
echo "Kết quả: $pass/$total"
if [ "$pass" -eq "$total" ]; then
  echo "Hoàn thành! Đừng quên viết nhật ký debug."
fi
