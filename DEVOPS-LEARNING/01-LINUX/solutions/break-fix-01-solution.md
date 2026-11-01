# Lời giải — Break-fix Linux #1: Ca trực đêm

> ⚠️ Chỉ đọc khi đã hoàn thành, hoặc đã xem hết 3 cấp gợi ý mà vẫn kẹt quá 30 phút.
> Đề bài: [labs/break-fix-01/README.md](../labs/break-fix-01/README.md)

Lời giải tập trung vào **cách TÌM RA** lỗi — đó mới là kỹ năng được rèn. Cách sửa thường chỉ là một dòng.

## Mục lục

- [Tổng quan 6 lỗi](#tổng-quan-6-lỗi)
- [Ticket #1042](#ticket-1042)
  - [Lỗi 1a — start.sh không có quyền thực thi](#lỗi-1a--startsh-không-có-quyền-thực-thi)
  - [Lỗi 1b — Xuống dòng CRLF](#lỗi-1b--xuống-dòng-crlf)
  - [Lỗi 2 — File cấu hình sai chỗ](#lỗi-2--file-cấu-hình-sai-chỗ)
  - [Lỗi 3 — Tên biến gõ sai](#lỗi-3--tên-biến-gõ-sai)
  - [Lỗi 4 — Không ghi được log](#lỗi-4--không-ghi-được-log)
  - [Lỗi 5 — File khổng lồ bị giấu](#lỗi-5--file-khổng-lồ-bị-giấu)
- [Ticket #1043 — Process ngốn CPU có watchdog](#ticket-1043--process-ngốn-cpu-có-watchdog)
- [Bài học rút ra](#bài-học-rút-ra)

---

## Tổng quan 6 lỗi

| # | Lỗi | Bài liên quan |
|---|---|---|
| 1 | `start.sh` thiếu quyền `x` **và** xuống dòng CRLF | [01](../01-linux-architecture-filesystem.md), [03](../03-permissions-users-groups.md) |
| 2 | File cấu hình ở `/etc/taskhub.conf` thay vì `/etc/taskhub/taskhub.conf` | [01](../01-linux-architecture-filesystem.md), [02](../02-essential-commands-text.md) |
| 3 | Biến `APP_PROT` thay vì `APP_PORT` | [02](../02-essential-commands-text.md), [06](../06-bash-scripting.md) |
| 4 | Thư mục và file log thuộc `root`, user `taskhub` không ghi được | [03](../03-permissions-users-groups.md) |
| 5 | File heap dump 300MB trong thư mục ẩn làm vượt hạn mức 200MB | [07](../07-logs-monitoring-troubleshooting.md) |
| 6 | Process `sync-agent` ngốn CPU, được `watchdog.sh` bật lại liên tục | [04](../04-processes-systemd.md), [07](../07-logs-monitoring-troubleshooting.md) |

---

## Ticket #1042

### Lỗi 1a — `start.sh` không có quyền thực thi

**Triệu chứng:**

```text
root@c0ffee:/# /opt/taskhub/bin/start.sh
bash: /opt/taskhub/bin/start.sh: Permission denied
```

**Suy luận:** đang là **root** mà vẫn `Permission denied` → không phải vấn đề "ai được phép", mà là file **không có quyền thực thi** (root bỏ qua được quyền đọc/ghi, nhưng kernel vẫn yêu cầu file có ít nhất một bit `x` mới chạy trực tiếp được).

**Quan sát:**

```bash
ls -l /opt/taskhub/bin/
```

```text
-rw-r--r-- 1 root root  ... start.sh
-rwxr-xr-x 1 root root  ... taskhub-app
```

`start.sh` là `rw-r--r--` — không có `x`.

**Sửa:**

```bash
chmod 755 /opt/taskhub/bin/start.sh
```

### Lỗi 1b — Xuống dòng CRLF

**Triệu chứng** (ngay sau khi sửa 1a):

```text
bash: /opt/taskhub/bin/start.sh: /bin/bash^M: bad interpreter: No such file or directory
```

**Suy luận:** `^M` là cách terminal hiển thị ký tự `\r` (carriage return). Kernel đọc dòng shebang và tìm chương trình tên `/bin/bash\r` — không tồn tại. Ticket cũng nhắc "sửa trên laptop cá nhân" → nghi ngờ file được sửa trên Windows.

**Quan sát:**

```bash
file /opt/taskhub/bin/start.sh
cat -A /opt/taskhub/bin/start.sh | head -3
```

```text
/opt/taskhub/bin/start.sh: Bourne-Again shell script, Unicode text, UTF-8 text executable, with CRLF line terminators
#!/bin/bash^M$
# start.sh: khM-a...^M$
set -e^M$
```

`cat -A` hiện `^M$` ở cuối mỗi dòng: `^M` = `\r`, `$` = `\n`.

> Nếu bạn thử `bash /opt/taskhub/bin/start.sh` (gọi bash trực tiếp, bỏ qua shebang), bạn sẽ thấy lỗi khác: `set: -: invalid option` và `runuser: failed to execute /opt/taskhub/bin/taskhub-app: No such file or directory` — vì tên chương trình bị dính `\r` ở cuối. **Nguy hiểm hơn:** dòng cuối vẫn in `taskhub is up.` và exit code là 0 (vì `set -e` dính `\r` nên không bật được `-e`) — script báo thành công dù app không chạy. Cùng một nguyên nhân, triệu chứng khác nhau tùy cách chạy (đã kiểm chứng trong container `ubuntu:22.04`).

**Sửa:**

```bash
sed -i 's/\r$//' /opt/taskhub/bin/start.sh
file /opt/taskhub/bin/start.sh     # không còn "with CRLF line terminators"
```

(Hoặc `dos2unix` nếu cài gói `dos2unix`.)

### Lỗi 2 — File cấu hình sai chỗ

**Triệu chứng:**

```text
Starting taskhub...
2026-10-31T07:41:10+00:00 FATAL cannot read config file /etc/taskhub/taskhub.conf: No such file or directory
```

**Quan sát:** ứng dụng nói rõ nó tìm ở đâu. Kiểm tra:

```bash
ls -la /etc/taskhub/
ls /etc | grep -i taskhub
# hoặc tìm rộng hơn:
find / -name "*taskhub*.conf*" -not -path "/proc/*" 2>/dev/null
```

```text
total 12
drwxr-xr-x 2 root root 4096 ... .
drwxr-xr-x 1 root root 4096 ... ..
taskhub
taskhub.conf
/etc/taskhub.conf
```

Thư mục `/etc/taskhub/` rỗng, file lại nằm ở `/etc/taskhub.conf`.

**Sửa:**

```bash
mv /etc/taskhub.conf /etc/taskhub/taskhub.conf
```

> Vì sao `mv` chứ không `cp`? Để lại hai bản cấu hình là mầm mống của lỗi tiếp theo: lần sau ai đó sửa nhầm bản không được dùng. Một nguồn sự thật duy nhất.

### Lỗi 3 — Tên biến gõ sai

**Triệu chứng:**

```text
2026-10-31T07:42:03+00:00 FATAL APP_PORT is not set in /etc/taskhub/taskhub.conf
```

**Quan sát:**

```bash
cat /etc/taskhub/taskhub.conf
grep -n PORT /etc/taskhub/taskhub.conf   # không ra gì → biến không có tên PORT
grep -n -i "prot\|port" /etc/taskhub/taskhub.conf
```

```text
2:APP_PROT=8080
```

Đối chiếu với code ứng dụng (được phép đọc): `grep -n 'APP_' /opt/taskhub/bin/taskhub-app` → app cần `APP_PORT`.

**Sửa:**

```bash
sed -i 's/^APP_PROT=/APP_PORT=/' /etc/taskhub/taskhub.conf
```

### Lỗi 4 — Không ghi được log

**Triệu chứng:**

```text
2026-10-31T07:43:15+00:00 FATAL cannot write log file /var/log/taskhub/app.log: Permission denied (running as user taskhub)
```

**Suy luận:** thông báo đã cho biết **ai** (user `taskhub`) và **cái gì** (`/var/log/taskhub/app.log`). Cần xem quyền của **cả đường đi**: thư mục và file.

**Quan sát:**

```bash
ls -ld /var/log/taskhub
ls -l /var/log/taskhub/
runuser -u taskhub -- touch /var/log/taskhub/app.log
```

```text
drwxr-xr-x 2 root root 4096 ... /var/log/taskhub
-rw-r--r-- 1 root root   98 ... app.log
touch: cannot touch '/var/log/taskhub/app.log': Permission denied
```

Cả thư mục và file đều thuộc `root`, `taskhub` chỉ thuộc nhóm "others" → chỉ có quyền đọc.

**Bẫy:** nếu chỉ `chown taskhub /var/log/taskhub` (không `-R`), file `app.log` cũ vẫn thuộc root → vẫn lỗi. Cả **thư mục** (để tạo file mới, xoay log) lẫn **file** (để ghi tiếp) đều cần đúng chủ.

**Sửa (quyền tối thiểu):**

```bash
chown -R taskhub:taskhub /var/log/taskhub
chmod 750 /var/log/taskhub
chmod 640 /var/log/taskhub/app.log
runuser -u taskhub -- touch /var/log/taskhub/app.log && echo OK
```

> ❌ Cách sai nhưng "chạy được": `chmod 777 /var/log/taskhub`. Bất kỳ user nào cũng ghi/xóa được log → có thể xóa dấu vết. Trong phỏng vấn, chọn 777 là điểm trừ lớn.

### Lỗi 5 — File khổng lồ bị giấu

**Triệu chứng:**

```text
2026-10-31T07:45:02+00:00 FATAL data directory /var/lib/taskhub uses 306MB, quota is 200MB: No space left on device
```

**Quan sát — đi từ trên xuống:**

```bash
du -sh /var/lib/taskhub
du -h --max-depth=1 /var/lib/taskhub | sort -h
ls -l /var/lib/taskhub/cache          # không thấy gì lớn!
ls -la /var/lib/taskhub/cache         # -a: lộ ra thư mục .tmp
du -ah /var/lib/taskhub | sort -h | tail -5
```

```text
306M	/var/lib/taskhub
4.0K	/var/lib/taskhub/... 
5.1M	/var/lib/taskhub/data
301M	/var/lib/taskhub/cache
306M	/var/lib/taskhub
...
300M	/var/lib/taskhub/cache/.tmp/.old/heapdump-20261029.hprof
```

Cách tìm nhanh hơn khi biết đang tìm file lớn:

```bash
find /var/lib/taskhub -type f -size +100M -exec ls -lh {} \;
```

**Suy luận:** `ls` không hiện thư mục bắt đầu bằng `.` — đó là lý do `ls -l cache` trông "trống". `du` không bị lừa vì nó đếm mọi thứ. File `.hprof` là **heap dump** của JVM (ảnh chụp bộ nhớ Java, thường được tạo khi app bị `OutOfMemoryError`) — rất lớn, chỉ cần cho việc phân tích sự cố.

**Sửa:** trong thực tế, hỏi team trước khi xóa — heap dump có thể đang được dùng để điều tra sự cố. Nếu cần giữ, chuyển sang nơi lưu trữ khác (ví dụ S3 — Module 06). Trong bài lab:

```bash
rm /var/lib/taskhub/cache/.tmp/.old/heapdump-20261029.hprof
du -sh /var/lib/taskhub
```

**Chạy lại:**

```text
Starting taskhub...
2026-10-31T07:47:30+00:00 INFO taskhub started on port 8080 (pid 1234)
taskhub is up.
```

---

## Ticket #1043 — Process ngốn CPU có watchdog

### Bước 1 — Xác định process

```bash
uptime
top        # nhấn P (sắp theo CPU), nhấn c (hiện dòng lệnh đầy đủ)
```

```text
  PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
  431 root      20   0    4628   3364   2964 R 100.0   0.0  12:04.11 /usr/local/bin/sync-agent -c while :; do :; done
```

Một process tên `sync-agent` (đường dẫn đầy đủ `/usr/local/bin/sync-agent`) dùng 100% một nhân. Tên nghe như dịch vụ hệ thống, nhưng dòng lệnh `-c while :; do :; done` là **vòng lặp vô hạn không làm gì** — đáng ngờ.

### Bước 2 — Nó thực sự là gì?

```bash
ps -o pid,ppid,user,etime,cmd -p 431
ls -l /proc/431/exe
md5sum /usr/local/bin/sync-agent /bin/bash
```

```text
  PID  PPID USER     ELAPSED CMD
  431   212 root       12:04 /usr/local/bin/sync-agent -c while :; do :; done
lrwxrwxrwx 1 root root 0 ... /proc/431/exe -> /usr/local/bin/sync-agent
3d8a...  /usr/local/bin/sync-agent
3d8a...  /bin/bash
```

`/proc/<PID>/exe` cho biết **file chương trình thật**. Checksum giống hệt `/bin/bash` → `sync-agent` chỉ là **bản sao của bash được đổi tên** để trông vô hại. (Đây cũng là kỹ thuật kẻ tấn công hay dùng để ngụy trang — ví dụ đặt tên process giống luồng kernel.)

### Bước 3 — Thử kill và quan sát

```bash
kill 431
sleep 6
pgrep -a sync-agent
```

```text
447 /usr/local/bin/sync-agent -c while :; do :; done
```

Nó **sống lại** với PID mới sau vài giây → có thứ gì đó đang bật lại nó. Nhìn cột `PPID` ở Bước 2 (`212`):

```bash
ps -o pid,ppid,user,cmd -p 212
ps -ef --forest | grep -B2 -A2 sync-agent
```

```text
  PID  PPID USER     CMD
  212     1 root     /bin/bash /usr/local/lib/sync-agent/watchdog.sh
```

```bash
cat /usr/local/lib/sync-agent/watchdog.sh
```

Watchdog kiểm tra mỗi 5 giây, nếu không thấy `sync-agent` thì chạy lại.

### Bước 4 — Xử lý triệt để: **cha trước, con sau**

```bash
kill 212                          # dừng watchdog trước
pkill -x sync-agent               # rồi mới dừng process ngốn CPU
sleep 6
pgrep -a -f 'sync-agent' || echo "Đã sạch"
```

Sau đó loại bỏ nguồn gốc để không chạy lại khi khởi động lại:

```bash
rm -r /usr/local/lib/sync-agent
rm /usr/local/bin/sync-agent
```

> Trên server thật, bước tiếp theo là tìm **cái gì khởi chạy watchdog** khi boot: systemd unit (`systemctl list-units`, `/etc/systemd/system/`), cron (`crontab -l`, `/etc/cron.d/`), `/etc/rc.local`, `~/.bashrc`… Và nếu không ai trong team cài nó → coi như **sự cố bảo mật**, báo cáo theo quy trình, không chỉ xóa đi.

---

## Bài học rút ra

1. **Lỗi nối tiếp nhau là bình thường.** Sửa một lỗi, chạy lại, đọc lỗi mới. Đừng sửa nhiều thứ cùng lúc khi chưa hiểu.
2. **Thông báo lỗi thường đã nói gần hết.** 5/6 lỗi ở đây có thông báo chỉ thẳng vào đối tượng bị lỗi.
3. **Root không bỏ qua được quyền thực thi** và **kernel không đọc được shebang có `\r`**.
4. **`ls` giấu file ẩn, `du` thì không.** Khi tìm "ai ăn ổ đĩa", dùng `du`/`find`, không dùng `ls`.
5. **Quyền phải đúng trên cả đường đi** — thư mục lẫn file.
6. **Kill process cha trước.** Và luôn hỏi: "cái gì đã khởi chạy nó?"
7. **Quyền tối thiểu**, không 777.
