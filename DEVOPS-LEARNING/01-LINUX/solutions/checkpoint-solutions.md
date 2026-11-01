# Lời giải — Checkpoint Module 01

> ⚠️ Chỉ đọc sau khi đã commit bài làm của mình. Tự chấm **trung thực**: câu trả lời đúng bản chất nhưng diễn đạt khác vẫn được tính; câu trả lời đúng từ khóa nhưng không giải thích được thì không tính.
> Đề bài: [checkpoint.md](../checkpoint.md)

## Mục lục

- [Phần A — Đáp án lý thuyết](#phần-a--đáp-án-lý-thuyết)
- [Phần B — Lời giải disk-guard.sh](#phần-b--lời-giải-disk-guardsh)
- [Phần C — Lời giải break-fix](#phần-c--lời-giải-break-fix)

---

## Phần A — Đáp án lý thuyết

**1.** Terminal nhận phím gõ và hiển thị chữ. Shell (Bash) phân tích dòng lệnh, tìm chương trình `cat` trong `$PATH` và yêu cầu kernel tạo process mới chạy nó. `cat` dùng **system call** (`open`, `read`, `write`) để nhờ kernel mở file `/etc/hostname`, đọc nội dung từ ổ đĩa và ghi ra stdout. Kernel là phần duy nhất chạm trực tiếp vào phần cứng. Kết quả đi ngược về terminal để hiển thị.

**2.** `cat /etc/os-release` (distribution và phiên bản → biết dùng `apt` hay `dnf`, tài liệu nào phù hợp); `uname -r` / `uname -m` (phiên bản kernel, kiến trúc CPU `x86_64` hay `aarch64` → tải đúng bản phần mềm); `uptime` hoặc `df -h` / `free -h` (máy đang khỏe hay không). Chấp nhận các lựa chọn hợp lý khác như `hostname`, `whoami`, `id`.

**3.** Cấu hình: `/etc`; log: `/var/log`; dữ liệu ứng dụng: `/var/lib/<app>`; phần mềm tự cài: `/opt`. Nhờ quy ước này, gặp lỗi của một service bạn biết ngay nơi cần nhìn, thay vì tìm khắp hệ thống.

**4.** `d` = thư mục; chủ `taskhub` có `rwx` (đọc, tạo/xóa file, đi vào); group `adm` có `r-x` (liệt kê, đi vào, **không** tạo/xóa file); others `---`. `phuong` không thuộc `adm` → thuộc "others" → **không `cd` được**. User trong `adm` vào được, xem được danh sách file, **không tạo** được file mới (thiếu `w` trên thư mục).

**5.** Root bỏ qua được kiểm tra đọc/ghi, nhưng để **thực thi** một file, kernel yêu cầu file có ít nhất một bit `x`. `644` không có bit `x` nào. (Vẫn chạy được bằng `bash script.sh` vì khi đó chương trình được thực thi là `bash`, còn script chỉ được **đọc**.)

**6.** Danh sách group của một phiên đăng nhập được xác định **lúc đăng nhập**. Shell hiện tại vẫn mang danh sách group cũ (kiểm tra bằng `id`). Khắc phục: đăng xuất và đăng nhập lại (trên WSL: đóng hết terminal hoặc `wsl --shutdown` rồi mở lại), hoặc tạm thời `newgrp docker`.

**7.** `SIGTERM` (15) là **yêu cầu** dừng — process có thể bắt tín hiệu để dọn dẹp (đóng kết nối DB, ghi nốt dữ liệu, xóa file tạm) rồi tự thoát. `SIGKILL` (9) do kernel thực hiện ngay, process không bắt được, không kịp dọn dẹp → có thể hỏng dữ liệu. Không kill được bằng `-9` khi process đang ở trạng thái `D` (chờ I/O không ngắt được), hoặc là **zombie** (đã chết rồi, chỉ còn chờ process cha "nhận xác" bằng `wait`).

**8.** `start` chạy service **ngay bây giờ**; `enable` cấu hình để service **tự chạy khi khởi động máy** (tạo symlink trong thư mục `*.wants`). Một ứng dụng production cần cả hai; viết gọn: `systemctl enable --now taskhub`.

**9.** `apt update` chỉ tải lại **danh sách gói** từ repository (không cài gì). `apt upgrade` **cài phiên bản mới** của các gói đã có. Trên production, upgrade có thể đổi phiên bản thư viện/runtime, khởi động lại service, gây lỗi ngoài dự kiến → nên thử trên staging trước, làm trong khung giờ bảo trì, có kế hoạch rollback.

**10.** **Private key** ở máy client (ví dụ `~/.ssh/id_ed25519`), không bao giờ chia sẻ. **Public key** được thêm vào `~/.ssh/authorized_keys` của user đích trên server. `sshd` mặc định bật `StrictModes`: nếu `~/.ssh` hoặc `authorized_keys` ghi được bởi người khác, bất kỳ ai cũng có thể chèn key của họ vào → `sshd` coi là không an toàn và từ chối.

**11.** `-e`: thoát ngay khi một lệnh lỗi (exit code khác 0); `-u`: báo lỗi khi dùng biến chưa định nghĩa (bắt lỗi gõ sai tên biến); `-o pipefail`: pipeline bị coi là lỗi nếu **bất kỳ** lệnh nào trong đó lỗi, không chỉ lệnh cuối. Đặt `"$file"` trong nháy kép để tránh **word splitting** (tên có dấu cách bị tách làm nhiều tham số) và **globbing** (`*` bị mở rộng thành danh sách file); biến rỗng vẫn được giữ là một tham số rỗng.

**12.** (a) `sudo`: mặc định **không** — `env_reset` xóa gần hết biến môi trường, chỉ giữ một danh sách an toàn. (b) cron: **không** — cron chạy với môi trường tối giản (`PATH=/usr/bin:/bin`, `SHELL=/bin/sh`, `HOME`) và không đọc `~/.bashrc`. (c) systemd: **không** — service chỉ có biến được khai báo bằng `Environment=` hoặc `EnvironmentFile=` trong unit. Bài học: cấu hình cho service phải nằm trong file cấu hình/env của service, không nằm trong shell cá nhân.

**13.**

```text
30 2 * * * /opt/taskhub/bin/backup.sh >> /var/log/taskhub/backup.log 2>&1
```

(Trong `/etc/cron.d/` phải thêm cột user: `30 2 * * * root /opt/...`.) Lý do phổ biến khiến cron lỗi: `PATH` tối giản nên không tìm thấy lệnh; dùng đường dẫn tương đối (cron chạy ở thư mục `HOME`); thiếu biến môi trường; ký tự `%` có nghĩa đặc biệt trong crontab (phải viết `\%`); script có CRLF hoặc thiếu quyền `x`.

**14.** Load ~5 trên máy 2 nhân → trung bình có ~3 tiến trình phải chờ → bão hòa. Nhưng `wa` 85% → CPU phần lớn **ngồi chờ ổ đĩa**, nút cổ chai là **I/O**, không phải tính toán. Tiếp theo: `iostat -xz 1` (ổ nào, `%util`, `await`), tìm process trạng thái `D` (`ps -eo state,pid,user,cmd | awk '$1=="D"'`), kiểm tra `free -h` và `vmstat 1` (`si`/`so`) xem có phải thiếu RAM dẫn tới swap không, `df -h` xem ổ có đầy không.

**15.** Giả thuyết hàng đầu: **OOM killer** của kernel giết process (SIGKILL → app không kịp ghi log). Xác nhận: `sudo dmesg -T | grep -i -E "out of memory|killed process"` hoặc `journalctl -k --since "03:00" --until "03:10"`; phía systemd: `journalctl -u taskhub` thấy `code=killed, status=9/KILL`.

---

## Phần B — Lời giải `disk-guard.sh`

```bash
#!/bin/bash
# disk-guard.sh: cảnh báo khi filesystem sắp đầy (dung lượng hoặc inode)
# Cách dùng: disk-guard.sh [ngưỡng 1-99]   (mặc định 80)
# Biến môi trường: DISK_GUARD_LOG — file log (mặc định /var/log/disk-guard.log)
set -euo pipefail

# PATH tường minh để chạy giống nhau dưới cron và khi chạy tay
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

THRESHOLD="${1:-80}"
LOG_FILE="${DISK_GUARD_LOG:-/var/log/disk-guard.log}"
# Các loại filesystem ảo / không cần theo dõi
EXCLUDES=(-x tmpfs -x devtmpfs -x overlay -x squashfs)

usage() {
  echo "Cách dùng: $(basename "$0") [ngưỡng 1-99, mặc định 80]" >&2
  echo "Biến môi trường: DISK_GUARD_LOG (mặc định /var/log/disk-guard.log)" >&2
}

# --- Kiểm tra tham số: số nguyên từ 1 đến 99 ---
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 99 ]; then
  usage
  exit 2
fi

mkdir -p "$(dirname "$LOG_FILE")"
warnings=0

log_warn() {
  echo "$(date -Is) WARN disk-guard: $*" >> "$LOG_FILE"
  # Không dùng ((warnings++)): khi warnings=0 biểu thức trả về 1 và set -e sẽ thoát script
  warnings=$((warnings + 1))
}

# --- Kiểm tra dung lượng: mỗi dòng "Use% Mountpoint" ---
while read -r pcent target; do
  [[ "$pcent" =~ ^[0-9]+%$ ]] || continue      # bỏ qua giá trị "-"
  used="${pcent%\%}"
  if [ "$used" -ge "$THRESHOLD" ]; then
    log_warn "$target at ${used}% (threshold ${THRESHOLD}%)"
  fi
done < <(df --output=pcent,target "${EXCLUDES[@]}" | tail -n +2)

# --- Kiểm tra inode ---
while read -r ipcent target; do
  [[ "$ipcent" =~ ^[0-9]+%$ ]] || continue     # một số filesystem không có inode
  used="${ipcent%\%}"
  if [ "$used" -ge "$THRESHOLD" ]; then
    log_warn "$target inodes at ${used}% (threshold ${THRESHOLD}%)"
  fi
done < <(df --output=ipcent,target "${EXCLUDES[@]}" | tail -n +2)

# --- Exit code: 0 = ổn, 1 = có cảnh báo ---
if [ "$warnings" -gt 0 ]; then
  exit 1
fi
exit 0
```

**Các điểm đáng chú ý:**

| Điểm | Giải thích |
|---|---|
| `PATH=...` ở đầu | Cron chỉ có `PATH=/usr/bin:/bin`. Đặt `PATH` tường minh giúp script chạy giống nhau ở mọi nơi |
| `df --output=pcent,target` | Lấy đúng cột cần thiết, không phải đếm cột bằng `awk`. **Không** dùng chung được với `-P` (GNU `df` báo lỗi hai tùy chọn loại trừ nhau) |
| `read -r pcent target` | Phần còn lại của dòng dồn vào `target` → mount point có dấu cách vẫn đúng |
| `< <(...)` (process substitution) | Vòng `while` chạy trong shell hiện tại nên biến `warnings` giữ được giá trị. Nếu viết `df ... \| while ...`, vòng lặp chạy trong **subshell** và `warnings` luôn bằng 0 khi ra ngoài — lỗi rất hay gặp |
| `warnings=$((warnings + 1))` | Xem comment trong code — bẫy kinh điển của `set -e` |
| `[[ ... =~ ^[0-9]+%$ ]] \|\| continue` | `df` in `-` cho filesystem không có thông tin inode |
| Trong container | Ổ gốc của container là `overlay` nên bị loại theo đề bài. Bạn vẫn thấy các mount thật như `/etc/hosts`, `/work` — đó là các bind mount từ máy chủ. Trên server thật bạn sẽ thấy `/`, `/data`… |

**Cron và cách chứng minh cron đã chạy:**

Vì với ngưỡng 85 có thể không có cảnh báo nào (log trống), hãy chứng minh bằng một lịch **tạm thời** với ngưỡng 1:

```bash
cat > /etc/cron.d/disk-guard-test <<'EOF'
* * * * * root DISK_GUARD_LOG=/tmp/cron-test.log /work/disk-guard.sh 1 >/dev/null 2>&1
EOF
# chờ qua đầu phút tiếp theo
sleep 70; cat /tmp/cron-test.log      # có dòng WARN với thời gian đúng đầu phút → cron đã chạy
rm /etc/cron.d/disk-guard-test
```

Lịch chính thức:

```text
# /etc/cron.d/disk-guard
*/10 * * * * root /work/disk-guard.sh 85 >> /var/log/disk-guard-cron.log 2>&1
```

Ghi chú: chuyển hướng output (`>>... 2>&1`) để lỗi bất ngờ (nếu có) được lưu lại thay vì cron cố gửi mail rồi bỏ đi. Trên server thật nên đặt script ở `/usr/local/bin/` thay vì thư mục làm việc. Nếu dùng WSL có systemd, một **systemd timer** (bài 08) cũng được chấp nhận — kèm `systemctl list-timers` làm bằng chứng.

---

## Phần C — Lời giải break-fix

Thứ tự hợp lý: #2001 → #2002 → #2004 (cần restart.sh chạy được) và #2003 làm độc lập.

### Ticket #2001 — `Permission denied (publickey)`

**Quan sát phía client:**

```bash
ssh -v -i /root/.ssh/deploy_ed25519 deploy@localhost
```

```text
debug1: Offering public key: /root/.ssh/deploy_ed25519 ED25519 SHA256:... explicit
debug1: Authentications that can continue: publickey
...
deploy@localhost: Permission denied (publickey,password).
```

(Server còn cho phép đăng nhập bằng mật khẩu nên danh sách là `publickey,password`; pipeline dùng `BatchMode` không nhập mật khẩu được, nên với nó chỉ còn cách `publickey` — đó là lý do ticket ghi `Permission denied (publickey)`.)

Client **có gửi** key nhưng server không chấp nhận → nguyên nhân nằm **phía server**. Lời khuyên vàng: lỗi SSH xác thực, **đọc log của server**, không đoán phía client.

**Quan sát phía server:**

```bash
grep sshd /var/log/auth.log | tail -5
```

```text
... sshd[812]: Authentication refused: bad ownership or modes for directory /home/deploy/.ssh
```

```bash
ls -ld /home/deploy /home/deploy/.ssh
ls -l /home/deploy/.ssh/authorized_keys
```

```text
drwxr-x--- 3 deploy deploy 4096 ... /home/deploy
drwxrwxrwx 2 deploy deploy 4096 ... /home/deploy/.ssh
-rw------- 1 deploy deploy   93 ... authorized_keys
```

**Sửa:**

```bash
chmod 700 /home/deploy/.ssh
ssh -i /root/.ssh/deploy_ed25519 deploy@localhost 'whoami'     # → deploy
```

> Nếu không có `/var/log/auth.log` (server không có rsyslog), có 2 cách khác: `journalctl -u ssh`, hoặc chạy một `sshd` debug ở port khác: `/usr/sbin/sshd -d -p 2222` rồi `ssh -p 2222 ...` — server in thẳng lý do từ chối ra màn hình.

### Ticket #2002 — sudo đòi mật khẩu, rồi thiếu biến môi trường

**Phần 1 — sudoers.** Đăng nhập bằng deploy:

```bash
sudo -n /opt/taskhub/bin/restart.sh
sudo -l
```

```text
sudo: a password is required
User deploy may run the following commands on c0ffee:
    (root) NOPASSWD: /opt/taskhub/restart.sh
```

`sudo -l` cho thấy quyền được cấp cho `/opt/taskhub/restart.sh` — thiếu `/bin`. Lệnh không khớp chính xác → sudo coi là lệnh không được phép không cần mật khẩu → đòi mật khẩu (mà deploy không có).

Sửa bằng root, **luôn qua `visudo`** (kiểm tra cú pháp trước khi lưu — một file sudoers lỗi có thể khóa toàn bộ quyền sudo):

```bash
visudo -f /etc/sudoers.d/deploy
# sửa thành: deploy ALL=(root) NOPASSWD: /opt/taskhub/bin/restart.sh
visudo -c
```

**Phần 2 — biến môi trường.** Giờ deploy chạy được nhưng:

```text
FATAL: TASKHUB_DB_URL is not set
```

Quan sát khác biệt môi trường:

```bash
# Bằng deploy:
echo "$TASKHUB_DB_URL"                  # có giá trị
grep -n TASKHUB ~/.bashrc               # được export trong ~/.bashrc của deploy
cat /opt/taskhub/bin/restart.sh         # script cần biến này, và tìm nó trong /etc/taskhub/taskhub.env
ls -l /etc/taskhub/                     # file env không tồn tại
# Bằng root — xem sudo giữ lại những biến nào:
sudo -V | grep -A 30 "Environment variables to preserve"
```

Biến chỉ tồn tại trong shell tương tác của deploy. `sudo` mặc định `env_reset` → biến không đi theo. Đọc `restart.sh` thấy script nạp `/etc/taskhub/taskhub.env` nếu có — và file này **không tồn tại**.

**Sửa đúng cách** (bằng root) — cấu hình của service nằm ở nơi của service:

```bash
install -m 640 -o root -g root /dev/null /etc/taskhub/taskhub.env
echo 'TASKHUB_DB_URL="postgresql://db.internal:5432/taskhub"' > /etc/taskhub/taskhub.env
ls -l /etc/taskhub/taskhub.env      # -rw-r----- root root: chứa thông tin kết nối DB, không cho mọi người đọc
```

Thử lại bằng deploy: `sudo /opt/taskhub/bin/restart.sh` → `taskhub restarted`. Có thể xóa dòng export trong `~/.bashrc` của deploy để tránh hai nguồn sự thật.

**Vì sao không chọn cách khác?**

| Cách | Vấn đề |
|---|---|
| `sudo -E` | sudoers không cấp `SETENV` nên bị từ chối; và cho phép người gọi truyền **bất kỳ** biến nào vào lệnh chạy bằng root là rủi ro bảo mật |
| `Defaults:deploy env_keep += "TASKHUB_DB_URL"` | Chạy được khi gõ tay, nhưng phụ thuộc vào shell của deploy có biến đó hay không. Pipeline chạy `ssh deploy@host 'sudo ...'` là shell **không tương tác** — `.bashrc` của Ubuntu thoát sớm ở dòng kiểm tra tương tác, nên biến khai báo cuối file không bao giờ được nạp |
| Sửa `restart.sh` để hard-code URL | Trộn cấu hình vào code; đổi môi trường là phải sửa script |

### Ticket #2003 — Backup không chạy bằng cron

**Quan sát:**

```bash
ls -lt /var/backups/taskhub | head -3      # không có file mới
tail -5 /var/log/taskhub/backup.log
grep CRON /var/log/syslog | tail -3
```

```text
/opt/taskhub/bin/backup.sh: line 7: taskhub-dump: command not found
2026-10-31T08:12:01+00:00 backup FAILED (exit 127)
... CRON[1502]: (root) CMD (/opt/taskhub/bin/backup.sh)
```

- `syslog` chứng minh **cron có chạy** script đúng giờ → vấn đề nằm trong script/môi trường, không phải lịch.
- Exit code `127` = **command not found**.

So sánh môi trường:

```bash
which taskhub-dump          # /opt/taskhub/tools/taskhub-dump — chạy tay thì tìm thấy
echo "$PATH"                # có /opt/taskhub/tools
grep -n PATH /root/.bashrc  # được thêm trong .bashrc — cron không đọc file này
env -i PATH=/usr/bin:/bin /opt/taskhub/bin/backup.sh; tail -1 /var/log/taskhub/backup.log   # tái hiện lỗi
```

`env -i PATH=/usr/bin:/bin` là cách **tái hiện môi trường cron** để test mà không phải chờ từng phút.

**Sửa** (ưu tiên đường dẫn tuyệt đối trong script — script tự đứng được, không phụ thuộc người gọi):

```bash
sed -i 's|^if taskhub-dump |if /opt/taskhub/tools/taskhub-dump |' /opt/taskhub/bin/backup.sh
env -i PATH=/usr/bin:/bin /opt/taskhub/bin/backup.sh; tail -1 /var/log/taskhub/backup.log
```

Cách chấp nhận được khác: thêm `PATH=/usr/local/bin:/usr/bin:/bin:/opt/taskhub/tools` ở đầu `/etc/cron.d/taskhub-backup`, hoặc đặt `PATH=` ở đầu script.

### Ticket #2004 — app.log rỗng dù process vẫn chạy

**Quan sát:**

```bash
pgrep -a -u taskhub -f taskhub-app
ls -l /var/log/taskhub/app.log
ls -l /proc/$(pgrep -u taskhub -f taskhub-app | head -1)/fd
lsof +L1
```

```text
231 /bin/bash /opt/taskhub/bin/taskhub-app
-rw-r--r-- 1 taskhub taskhub 0 ... /var/log/taskhub/app.log
...
l-wx------ 1 taskhub taskhub 64 ... 1 -> '/var/log/taskhub/app.log (deleted)'
l-wx------ 1 taskhub taskhub 64 ... 2 -> '/var/log/taskhub/app.log (deleted)'
COMMAND PID    USER  FD TYPE ... NLINK ... NAME
taskhub-a 231 taskhub 1w REG ...     0 ... /var/log/taskhub/app.log (deleted)
sleep   312 taskhub   1w REG ...     0 ... /var/log/taskhub/app.log (deleted)
```

> Nếu `ls -l /proc/<PID>/fd` báo `cannot read symbolic link ... Permission denied` và `lsof +L1` không in gì: bạn đã quên cờ `--cap-add SYS_PTRACE` khi chạy container (xem phần Khởi tạo trong đề). Root trong container mặc định không có quyền đọc `/proc` của process thuộc user khác. Cách vòng: chạy bằng chính user sở hữu process — `runuser -u taskhub -- ls -l /proc/<PID>/fd`.

**Suy luận:** process mở file log một lần khi khởi động (`exec >>`) và giữ **file descriptor** trỏ tới **inode cũ**. Ai đó `rm` file → tên biến mất, inode vẫn sống vì process còn giữ. File `app.log` mới tạo là một **inode khác hoàn toàn** — process không hề biết tới nó. Heartbeat vẫn đang được ghi… vào file "ma".

🟦 Cứu log đã ghi vào file ma trước khi restart:

```bash
cp /proc/231/fd/1 /var/log/taskhub/app.log.recovered
```

**Sửa:** khởi động lại để process mở lại đường dẫn — dùng đúng quy trình của team (sau khi đã sửa #2002):

```bash
ssh -i /root/.ssh/deploy_ed25519 deploy@localhost 'sudo /opt/taskhub/bin/restart.sh'
sleep 6; tail -3 /var/log/taskhub/app.log
```

**Phòng tránh:** không bao giờ `rm` file log đang được ghi; muốn làm rỗng thì `truncate -s 0 app.log`; xoay log bằng logrotate đúng cấu hình ([bài 07, mục 4.4](../07-logs-monitoring-troubleshooting.md#44--logrotate--không-để-log-làm-đầy-ổ-đĩa)).

### Tóm tắt Phần C

| Ticket | Nguyên nhân | Lệnh tìm ra then chốt |
|---|---|---|
| #2001 | `~/.ssh` quyền 777 → `StrictModes` từ chối | `grep sshd /var/log/auth.log` |
| #2002a | sudoers trỏ sai đường dẫn | `sudo -l` |
| #2002b | `env_reset` + biến chỉ có trong `.bashrc` | So sánh `env` thường và qua sudo; đọc `restart.sh` |
| #2003 | `PATH` của cron không có `/opt/taskhub/tools` | `backup.log` (exit 127) + `env -i PATH=/usr/bin:/bin` |
| #2004 | File log bị xóa khi process vẫn giữ | `ls -l /proc/<PID>/fd`, `lsof +L1` |
