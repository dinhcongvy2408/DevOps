#!/bin/bash
# =============================================================================
# Break-fix Linux #1 — script tạo môi trường có lỗi cài sẵn
#
# CHỈ chạy bên trong container sandbox:
#   docker run --rm -it -v "$PWD":/lab ubuntu:22.04 bash
#   bash /lab/setup.sh
#
# ⚠️ ĐỪNG đọc file này trước khi làm bài — nó chứa toàn bộ đáp án.
# =============================================================================
set -euo pipefail

# --- Kiểm tra an toàn: chỉ chạy trong container, không bao giờ chạy trên WSL ---
if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ]; then
  echo "DỪNG: script này chỉ được chạy BÊN TRONG container sandbox." >&2
  echo "Hãy chạy:  docker run --rm -it -v \"\$PWD\":/lab ubuntu:22.04 bash" >&2
  echo "rồi trong container:  bash /lab/setup.sh" >&2
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "DỪNG: cần chạy bằng root trong container." >&2
  exit 1
fi

echo "[1/5] Cài công cụ cần thiết (khoảng 1 phút)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq procps psmisc lsof file less nano vim-tiny >/dev/null

echo "[2/5] Tạo user và thư mục của taskhub..."
id taskhub >/dev/null 2>&1 || useradd -m -s /bin/bash taskhub
mkdir -p /opt/taskhub/bin /etc/taskhub /var/log/taskhub \
         /var/lib/taskhub/data /var/lib/taskhub/cache/.tmp/.old

# --- Ứng dụng giả lập (người học KHÔNG được sửa file này) ---
cat > /opt/taskhub/bin/taskhub-app <<'EOF'
#!/bin/bash
# taskhub-app: ứng dụng giả lập. Kiểm tra cấu hình và môi trường rồi "khởi động".
# KHÔNG sửa file này — hãy sửa môi trường xung quanh nó.
CONFIG_FILE=/etc/taskhub/taskhub.conf
QUOTA_MB=200

fail() {
  echo "$(date -Is) FATAL $*" >&2
  if [ -n "${LOG_FILE:-}" ] && [ -w "$LOG_FILE" ]; then
    echo "$(date -Is) FATAL $*" >> "$LOG_FILE"
  fi
  exit 1
}

[ -r "$CONFIG_FILE" ] || fail "cannot read config file $CONFIG_FILE: No such file or directory"
# shellcheck disable=SC1090
. "$CONFIG_FILE"

[ -n "${APP_PORT:-}" ] || fail "APP_PORT is not set in $CONFIG_FILE"
[ -n "${LOG_DIR:-}" ]  || fail "LOG_DIR is not set in $CONFIG_FILE"
[ -n "${DATA_DIR:-}" ] || fail "DATA_DIR is not set in $CONFIG_FILE"

LOG_FILE="$LOG_DIR/app.log"
touch "$LOG_FILE" 2>/dev/null \
  || fail "cannot write log file $LOG_FILE: Permission denied (running as user $(id -un))"

used_mb=$(du -sm "$DATA_DIR" 2>/dev/null | cut -f1)
if [ "${used_mb:-0}" -gt "$QUOTA_MB" ]; then
  fail "data directory $DATA_DIR uses ${used_mb}MB, quota is ${QUOTA_MB}MB: No space left on device"
fi

echo "$(date -Is) INFO taskhub started on port $APP_PORT (pid $$)" | tee -a "$LOG_FILE"
EOF
chmod 755 /opt/taskhub/bin/taskhub-app

# --- Lỗi 1: start.sh có xuống dòng CRLF và thiếu quyền thực thi ---
cat > /opt/taskhub/bin/start.sh <<'EOF'
#!/bin/bash
# start.sh: khởi động taskhub bằng user taskhub (chạy bằng root)
set -e
echo "Starting taskhub..."
runuser -u taskhub -- /opt/taskhub/bin/taskhub-app
echo "taskhub is up."
EOF
sed -i 's/$/\r/' /opt/taskhub/bin/start.sh
chmod 644 /opt/taskhub/bin/start.sh

# --- Lỗi 2 + 3: file cấu hình đặt sai chỗ và gõ sai tên biến ---
cat > /etc/taskhub.conf <<'EOF'
# Cấu hình taskhub
APP_PROT=8080
LOG_DIR=/var/log/taskhub
DATA_DIR=/var/lib/taskhub
EOF
chmod 644 /etc/taskhub.conf

# --- Lỗi 4: thư mục log và file log cũ thuộc root, user taskhub không ghi được ---
YESTERDAY=$(date -d yesterday +%F)
cat > /var/log/taskhub/app.log <<EOF
${YESTERDAY}T01:58:02+00:00 INFO taskhub started on port 8080 (pid 812)
${YESTERDAY}T23:59:59+00:00 INFO daily report generated
EOF
chown -R root:root /var/log/taskhub
chmod 755 /var/log/taskhub
chmod 644 /var/log/taskhub/app.log

echo "[3/5] Tạo dữ liệu ứng dụng..."
dd if=/dev/urandom of=/var/lib/taskhub/data/tasks.db bs=1M count=5 status=none
echo "cache v1" > /var/lib/taskhub/cache/index.txt

# --- Lỗi 5: một file 300MB bị giấu sâu làm vượt hạn mức dữ liệu ---
BIG=/var/lib/taskhub/cache/.tmp/.old/heapdump-20261029.hprof
fallocate -l 300M "$BIG" 2>/dev/null \
  || dd if=/dev/zero of="$BIG" bs=1M count=300 status=none
chown -R taskhub:taskhub /var/lib/taskhub

echo "[4/5] Khởi động các dịch vụ nền..."
# --- Lỗi 6: process ngốn CPU, có watchdog tự bật lại khi bị kill ---
cp /bin/bash /usr/local/bin/sync-agent
mkdir -p /usr/local/lib/sync-agent
cat > /usr/local/lib/sync-agent/watchdog.sh <<'EOF'
#!/bin/bash
# Giữ cho sync-agent luôn chạy
while true; do
  if ! pgrep -x sync-agent >/dev/null; then
    /usr/local/bin/sync-agent -c 'while :; do :; done' &
  fi
  sleep 5
done
EOF
chmod 755 /usr/local/lib/sync-agent/watchdog.sh
setsid nohup /usr/local/lib/sync-agent/watchdog.sh >/dev/null 2>&1 < /dev/null &

echo "[5/5] Cài công cụ kiểm tra 'verify'..."
cat > /usr/local/bin/verify <<'EOF'
#!/bin/bash
# verify: kiểm tra tiến độ Break-fix Linux #1
# (Tự giác: đừng đọc file này để tìm đáp án.)
pass=0
total=0

check() {
  local desc="$1"; shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then
    echo "  ✅ $desc"; pass=$((pass + 1))
  else
    echo "  ❌ $desc"
  fi
}

t_script()  { [ -x /opt/taskhub/bin/start.sh ] && ! grep -q $'\r' /opt/taskhub/bin/start.sh; }
t_cfgpath() { [ -f /etc/taskhub/taskhub.conf ]; }
t_cfgkey()  { grep -Eq '^APP_PORT=[0-9]+$' /etc/taskhub/taskhub.conf; }
t_logdir()  {
  runuser -u taskhub -- test -w /var/log/taskhub || return 1
  [ ! -e /var/log/taskhub/app.log ] || runuser -u taskhub -- test -w /var/log/taskhub/app.log
}
t_quota()   { [ "$(du -sm /var/lib/taskhub | cut -f1)" -le 200 ]; }
t_cpu()     { ! pgrep -x sync-agent && ! pgrep -f 'sync-agent/watchdog'; }
t_started() { grep -q "^$(date +%F).*INFO taskhub started" /var/log/taskhub/app.log; }
t_app_intact() { grep -q 'QUOTA_MB=200' /opt/taskhub/bin/taskhub-app; }

echo "Ticket #1042 — taskhub không khởi động:"
check "start.sh chạy được trực tiếp"              t_script
check "taskhub tìm thấy file cấu hình"            t_cfgpath
check "file cấu hình hợp lệ"                       t_cfgkey
check "taskhub ghi được log"                       t_logdir
check "dữ liệu nằm trong hạn mức"                  t_quota
check "taskhub đã khởi động thành công hôm nay"    t_started
echo "Ticket #1043 — CPU cao bất thường:"
check "không còn process lạ ngốn CPU (và không tự bật lại)" t_cpu
echo "Luật chơi:"
check "không sửa ứng dụng taskhub-app"             t_app_intact

echo
echo "Kết quả: $pass/$total"
[ "$pass" -eq "$total" ] && echo "🎉 Hoàn thành! Đừng quên viết nhật ký debug."
exit 0
EOF
chmod 755 /usr/local/bin/verify

cat <<'EOF'

==========================================================================
 Môi trường break-fix đã sẵn sàng.
 Đọc 2 ticket trong labs/break-fix-01/README.md và bắt đầu điều tra.
 Kiểm tra tiến độ bất cứ lúc nào bằng lệnh:  verify
 Gõ "exit" để thoát — container và mọi thay đổi sẽ bị xóa.
==========================================================================
EOF
