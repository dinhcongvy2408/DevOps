#!/bin/bash
# Kiểm tra Checkpoint Module 02 — Phần C. Chạy trong container client: verify-checkpoint
# (Học viên không đọc file này — nó chứa đáp án.)
# Mỗi kiểm tra độc lập với nhau: dùng --resolve để không phụ thuộc lỗi DNS.

EDGE_IP="172.29.1.10"
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

dns_points_to_edge() {
  [ "$(dig +short app.taskhub.test | head -1)" = "$EDGE_IP" ]
}

tls_valid() {
  curl -sS -m 5 --cacert /certs/edge.crt \
    --resolve "app.taskhub.test:443:${EDGE_IP}" https://app.taskhub.test/ \
    | grep -q "taskhub app OK"
}

report_ok() {
  local code
  code=$(curl -s -k -o /dev/null -w '%{http_code}' -m 20 \
    --resolve "app.taskhub.test:443:${EDGE_IP}" https://app.taskhub.test/api/report)
  [ "$code" = "200" ]
}

health_ok() {
  curl -s -m 5 --resolve "app.taskhub.test:80:${EDGE_IP}" http://app.taskhub.test/health \
    | grep -qx "ok"
}

echo "Checkpoint Module 02 — Phần C:"
check "#4001 DNS: app.taskhub.test trỏ tới edge mới"               dns_points_to_edge
check "#4002 TLS: chứng chỉ hợp lệ cho app.taskhub.test"           tls_valid
check "#4003 /api/report trả 200 (không còn 504)"                  report_ok
check "#4004 healthcheck http://app.taskhub.test/health trả ok"    health_ok

echo
echo "Kết quả: $pass/$total"
