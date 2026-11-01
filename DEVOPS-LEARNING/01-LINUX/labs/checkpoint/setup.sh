#!/bin/bash
# =============================================================================
# Checkpoint Module 01 — Phần C: môi trường break-fix
#
# CHỈ chạy bên trong container sandbox:
#   docker run --rm -it --name checkpoint01 --cap-add SYS_PTRACE -v "$PWD":/lab ubuntu:22.04 bash
#   bash /lab/setup.sh
#   exec bash
#
# ⚠️ ĐỪNG đọc file này trước khi làm bài — nó chứa toàn bộ đáp án.
# =============================================================================
set -euo pipefail

# --- Kiểm tra an toàn: chỉ chạy trong container ---
if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ]; then
  echo "DỪNG: script này chỉ được chạy BÊN TRONG container sandbox." >&2
  echo "Hãy chạy:  docker run --rm -it -v \"\$PWD\":/lab ubuntu:22.04 bash" >&2
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "DỪNG: cần chạy bằng root trong container." >&2
  exit 1
fi

echo "[1/6] Cài phần mềm (1–2 phút)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq procps psmisc lsof file less nano vim-tiny sudo cron \
  rsyslog openssh-server openssh-client >/dev/null

echo "[2/6] Khởi động rsyslog và sshd..."
# Container không đọc được log kernel -> tắt module imklog cho đỡ báo lỗi
sed -i 's/^module(load="imklog"/#&/' /etc/rsyslog.conf
service rsyslog start >/dev/null 2>&1 || rsyslogd
# pam_loginuid không hoạt động trong container -> chuyển sang optional
sed -i 's/^session\s\+required\s\+pam_loginuid.so/session optional pam_loginuid.so/' \
  /etc/pam.d/sshd /etc/pam.d/cron
ssh-keygen -A >/dev/null
mkdir -p /run/sshd
/usr/sbin/sshd

echo "[3/6] Tạo user và ứng dụng..."
id taskhub >/dev/null 2>&1 || useradd -m -s /bin/bash taskhub
id deploy  >/dev/null 2>&1 || useradd -m -s /bin/bash deploy
# Không cho đăng nhập bằng mật khẩu, nhưng không khóa tài khoản (để SSH key hoạt động)
usermod -p '*' deploy

mkdir -p /opt/taskhub/bin /opt/taskhub/tools /etc/taskhub /var/log/taskhub /var/backups/taskhub
chown taskhub:taskhub /var/log/taskhub
chmod 755 /var/log/taskhub

# Ứng dụng giả lập: ghi heartbeat vào log mỗi 5 giây (người học KHÔNG sửa file này)
cat > /opt/taskhub/bin/taskhub-app <<'EOF'
#!/bin/bash
# taskhub-app: ứng dụng giả lập, ghi heartbeat vào log mỗi 5 giây.
# KHÔNG sửa file này.
LOG_FILE=/var/log/taskhub/app.log
exec >>"$LOG_FILE" 2>&1
if [ -z "${TASKHUB_DB_URL:-}" ]; then
  echo "$(date -Is) FATAL TASKHUB_DB_URL is not set"
  exit 1
fi
echo "$(date -Is) INFO taskhub started, db=$TASKHUB_DB_URL, pid=$$"
while true; do
  echo "$(date -Is) INFO heartbeat ok"
  sleep 5
done
EOF
chmod 755 /opt/taskhub/bin/taskhub-app

# Script khởi động lại, dành cho user deploy chạy qua sudo
cat > /opt/taskhub/bin/restart.sh <<'EOF'
#!/bin/bash
# restart.sh: khởi động lại taskhub. Chạy bằng root (deploy dùng qua sudo).
set -euo pipefail
ENV_FILE=/etc/taskhub/taskhub.env
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi
if [ -z "${TASKHUB_DB_URL:-}" ]; then
  echo "FATAL: TASKHUB_DB_URL is not set" >&2
  exit 1
fi
pkill -u taskhub -f /opt/taskhub/bin/taskhub-app || true
sleep 1
runuser -u taskhub -- env TASKHUB_DB_URL="$TASKHUB_DB_URL" \
  nohup /opt/taskhub/bin/taskhub-app >/dev/null 2>&1 < /dev/null &
sleep 2
if pgrep -u taskhub -f /opt/taskhub/bin/taskhub-app >/dev/null; then
  echo "taskhub restarted"
else
  echo "FATAL: taskhub failed to start, check /var/log/taskhub/app.log" >&2
  exit 1
fi
EOF
chmod 755 /opt/taskhub/bin/restart.sh

# Công cụ dump database giả lập
cat > /opt/taskhub/tools/taskhub-dump <<'EOF'
#!/bin/bash
# taskhub-dump: giả lập công cụ dump database
echo "-- taskhub dump $(date -Is)"
for i in $(seq 1 50); do
  echo "INSERT INTO tasks VALUES ($i, 'task $i');"
done
EOF
chmod 755 /opt/taskhub/tools/taskhub-dump

# --- Lỗi 4: backup.sh gọi taskhub-dump không có đường dẫn đầy đủ ---
cat > /opt/taskhub/bin/backup.sh <<'EOF'
#!/bin/bash
# backup.sh: sao lưu database taskhub (cron chạy mỗi phút để demo)
BACKUP_DIR=/var/backups/taskhub
LOG=/var/log/taskhub/backup.log
mkdir -p "$BACKUP_DIR"
OUT="$BACKUP_DIR/taskhub-$(date +%Y%m%d-%H%M%S).sql"
if taskhub-dump > "$OUT" 2>>"$LOG"; then
  echo "$(date -Is) backup OK: $OUT" >> "$LOG"
else
  rc=$?
  echo "$(date -Is) backup FAILED (exit $rc)" >> "$LOG"
  rm -f "$OUT"
fi
EOF
chmod 755 /opt/taskhub/bin/backup.sh
# Khi làm tay thì chạy được, vì PATH của root (trong .bashrc) có thư mục tools
echo 'export PATH="$PATH:/opt/taskhub/tools"' >> /root/.bashrc

cat > /etc/cron.d/taskhub-backup <<'EOF'
# Sao lưu taskhub mỗi phút (demo)
* * * * * root /opt/taskhub/bin/backup.sh
EOF
chmod 644 /etc/cron.d/taskhub-backup
service cron start >/dev/null 2>&1 || cron

echo "[4/6] Cấu hình quyền cho user deploy..."
# --- Lỗi 1: thư mục .ssh của deploy có quyền quá rộng ---
mkdir -p /root/.ssh /home/deploy/.ssh
chmod 700 /root/.ssh
rm -f /root/.ssh/deploy_ed25519 /root/.ssh/deploy_ed25519.pub
ssh-keygen -q -t ed25519 -N '' -C 'deploy-key' -f /root/.ssh/deploy_ed25519
cat > /root/.ssh/config <<'EOF'
Host localhost
    StrictHostKeyChecking accept-new
EOF
chmod 600 /root/.ssh/config
cp /root/.ssh/deploy_ed25519.pub /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
chmod 777 /home/deploy/.ssh

# --- Lỗi 2: sudoers trỏ sai đường dẫn script ---
cat > /etc/sudoers.d/deploy <<'EOF'
# deploy được phép khởi động lại taskhub mà không cần mật khẩu
deploy ALL=(root) NOPASSWD: /opt/taskhub/restart.sh
EOF
chmod 440 /etc/sudoers.d/deploy
visudo -c -q

# --- Lỗi 3: biến môi trường chỉ có trong shell tương tác của deploy ---
echo 'export TASKHUB_DB_URL="postgresql://db.internal:5432/taskhub"' >> /home/deploy/.bashrc

echo "[5/6] Khởi động taskhub..."
runuser -u taskhub -- env TASKHUB_DB_URL="postgresql://db.internal:5432/taskhub" \
  nohup /opt/taskhub/bin/taskhub-app >/dev/null 2>&1 < /dev/null &
sleep 3
# --- Lỗi 5: ai đó xóa file log đang được ghi, rồi tạo lại file rỗng ---
rm /var/log/taskhub/app.log
runuser -u taskhub -- touch /var/log/taskhub/app.log

echo "[6/6] Cài công cụ kiểm tra 'verify-checkpoint'..."
cat > /usr/local/bin/verify-checkpoint <<'EOF'
#!/bin/bash
# verify-checkpoint: kiểm tra Phần C của Checkpoint Module 01
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

t_ssh() {
  ssh -o BatchMode=yes -o ConnectTimeout=5 -i /root/.ssh/deploy_ed25519 deploy@localhost true
}
t_sudo() {
  sudo -l -U deploy | grep -Eq 'NOPASSWD:.*/opt/taskhub/bin/restart\.sh'
}
t_env() {
  grep -Eq '^(export )?TASKHUB_DB_URL=.+' /etc/taskhub/taskhub.env 2>/dev/null \
    || grep -rqs 'env_keep.*TASKHUB_DB_URL' /etc/sudoers /etc/sudoers.d/
}
t_cron() {
  pgrep -x cron || return 1
  local p
  p=$(grep -E '^PATH=' /etc/cron.d/taskhub-backup | tail -1 | cut -d= -f2-)
  env -i PATH="${p:-/usr/bin:/bin}" HOME=/root SHELL=/bin/sh /opt/taskhub/bin/backup.sh
  tail -1 /var/log/taskhub/backup.log | grep -q 'backup OK'
}
t_app() {
  local pid
  pid=$(pgrep -u taskhub -f /opt/taskhub/bin/taskhub-app | head -1)
  [ -n "$pid" ] || return 1
  # Đọc /proc của process user khác cần CAP_SYS_PTRACE; chạy bằng chính user taskhub thì không cần
  runuser -u taskhub -- ls -l "/proc/$pid/fd" >/dev/null 2>&1 || return 1
  ! runuser -u taskhub -- ls -l "/proc/$pid/fd" | grep -q '(deleted)' || return 1
  runuser -u taskhub -- cat "/proc/$pid/environ" | tr '\0' '\n' | grep -q '^TASKHUB_DB_URL=.' || return 1
  [ -n "$(find /var/log/taskhub/app.log -newermt '15 seconds ago' 2>/dev/null)" ]
}
t_app_intact() { grep -q 'heartbeat ok' /opt/taskhub/bin/taskhub-app; }

echo "Ticket #2001 — deploy không SSH được:"
check "deploy đăng nhập SSH bằng key"                    t_ssh
echo "Ticket #2002 — deploy không khởi động lại được taskhub:"
check "deploy có quyền sudo đúng cho restart.sh"          t_sudo
check "restart.sh có biến môi trường cần thiết khi chạy qua sudo" t_env
echo "Ticket #2003 — backup không chạy:"
check "backup chạy thành công trong môi trường của cron"  t_cron
echo "Ticket #2004 — app.log không còn ghi gì:"
check "taskhub đang chạy và ghi log vào đúng file"        t_app
echo "Luật chơi:"
check "không sửa ứng dụng taskhub-app"                    t_app_intact

echo
echo "Kết quả: $pass/$total"
exit 0
EOF
chmod 755 /usr/local/bin/verify-checkpoint

cat <<'EOF'

==========================================================================
 Môi trường Checkpoint — Phần C đã sẵn sàng.
 BƯỚC TIẾP THEO: gõ  exec bash  để nạp lại cấu hình shell của root.
 Đọc các ticket trong checkpoint.md (Phần C) và bắt đầu.
 Kiểm tra tiến độ:  verify-checkpoint
==========================================================================
EOF
