# Lab 03 — Script healthcheck chạy bằng cron

> Tuần 3 · ~3 giờ · Mức độ: 🟥 Lab bắt buộc · Môi trường: `[WSL]`
> Kiến thức cần có: [04 — Processes](../04-processes-systemd.md), [06 — Bash scripting](../06-bash-scripting.md), [07 — Logs & monitoring](../07-logs-monitoring-troubleshooting.md), [08 — Cron](../08-cron-scheduling.md)

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Đặc tả yêu cầu](#2-đặc-tả-yêu-cầu)
- [3. Các bước thực hiện](#3-các-bước-thực-hiện)
- [4. Kết quả mong đợi](#4-kết-quả-mong-đợi)
- [5. Lỗi thường gặp](#5-lỗi-thường-gặp)
- [6. Mở rộng: giới hạn kích thước log bằng logrotate](#6-mở-rộng-giới-hạn-kích-thước-log-bằng-logrotate)
- [7. Đưa vào dự án taskhub](#7-đưa-vào-dự-án-taskhub)
- [8. Dọn dẹp](#8-dọn-dẹp)
- [9. Tiêu chí hoàn thành](#9-tiêu-chí-hoàn-thành)

---

## 1. Mục tiêu

Viết `healthcheck.sh` — một script giám sát tối giản, chạy tự động mỗi 5 phút, ghi lại tình trạng tài nguyên và **báo hiệu khi vượt ngưỡng**. Lab kết hợp toàn bộ kiến thức tuần 2–3:

| Kiến thức | Dùng ở đâu trong lab |
|---|---|
| `/proc`, `free`, `df`, `ps` | Thu thập số liệu |
| `awk`, `cut`, `tr` | Bóc tách số liệu |
| Biến môi trường + giá trị mặc định | Ngưỡng cảnh báo cấu hình được |
| `set -euo pipefail`, exit code | Báo thành công/thất bại đúng cách |
| cron + `flock` + `>> log 2>&1` | Chạy tự động, an toàn, có dấu vết |

Đây là "monitoring thời tiền sử". Ở Module 08 bạn sẽ thay nó bằng Prometheus + Grafana — và sẽ hiểu rõ vì sao công cụ chuyên dụng tốt hơn, chính vì đã tự làm bản thủ công.

---

## 2. Đặc tả yêu cầu

Đọc kỹ đặc tả như đọc một ticket công việc thật:

**Đầu ra:** mỗi lần chạy, nối **đúng một dòng** vào file log:

```text
2026-10-31 11:05:01 OK load1=0.12 mem=38% disk=2% procs=27
2026-10-31 11:10:01 WARN load1=0.30 mem=41% disk=85% procs=29 reason="disk 85%>80%"
```

| Trường | Ý nghĩa | Nguồn gợi ý |
|---|---|---|
| timestamp | `YYYY-MM-DD HH:MM:SS` | `date '+%F %T'` |
| trạng thái | `OK` hoặc `WARN` | |
| `load1` | Load average 1 phút | `/proc/loadavg` (trường 1) |
| `mem` | % RAM đang dùng = (total − available) / total | `free` (cột `total` và `available`) |
| `disk` | % dung lượng đã dùng của `/` | `df --output=pcent /` |
| `procs` | Số process | `ps -e --no-headers \| wc -l` |
| `reason` | Chỉ có khi `WARN`: những ngưỡng nào bị vượt | |

**Cấu hình** qua biến môi trường, có giá trị mặc định:

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `DISK_THRESHOLD` | `80` | Cảnh báo khi disk % **lớn hơn** giá trị này |
| `MEM_THRESHOLD` | `90` | Cảnh báo khi mem % lớn hơn giá trị này |
| `LOG_FILE` | `$HOME/logs/healthcheck.log` | Nơi ghi log |

**Exit code:** `0` khi `OK`, `1` khi `WARN`, `2` khi chính script gặp lỗi (ví dụ không ghi được log).

**Vận hành:** chạy bằng cron mỗi 5 phút, không bao giờ có 2 bản chạy cùng lúc.

> 💡 Vì sao % RAM tính bằng `available` mà không phải `free`? Linux dùng RAM trống làm **cache** cho file (cột `buff/cache`). Phần cache này được giải phóng ngay khi app cần, nên `free` thấp **không** có nghĩa là thiếu RAM. `available` là ước tính của kernel về lượng RAM app thực sự còn dùng được. Chi tiết ở [bài 07](../07-logs-monitoring-troubleshooting.md).

---

## 3. Các bước thực hiện

### Bước 1 — Chuẩn bị

```bash
mkdir -p ~/devops-lab/01-linux/lab03 ~/logs ~/bin
cd ~/devops-lab/01-linux/lab03
```

### Bước 2 — Thử từng lệnh thu thập số liệu trên terminal

Trước khi viết script, chạy từng lệnh riêng lẻ và **hiểu output**:

```bash
cat /proc/loadavg
cut -d ' ' -f1 /proc/loadavg
```

```text
0.12 0.18 0.15 1/312 4821
0.12
```

```bash
free
free | awk '/^Mem:/ { print $2, $7 }'
free | awk '/^Mem:/ { printf "%d\n", ($2 - $7) * 100 / $2 }'
```

```text
               total        used        free      shared  buff/cache   available
Mem:         8029312     2214560     4102380        3204     1712372     5520196
Swap:        2097152           0     2097152
8029312 5520196
31
```

```bash
df --output=pcent /
df --output=pcent / | tail -n 1 | tr -dc '0-9'; echo
ps -e --no-headers | wc -l
```

```text
Use%
  2%
2
27
```

❓ Giải thích từng phần: `awk '/^Mem:/ {...}'` chọn dòng nào? `$7` là cột gì? Vì sao cần `tail -n 1`? `tr -dc '0-9'` làm gì (đọc `man tr`)?

### Bước 3 — Khung script

Tạo `healthcheck.sh`:

```bash
#!/usr/bin/env bash
# healthcheck.sh — ghi một dòng trạng thái tài nguyên mỗi lần chạy.
# Exit code: 0 = OK, 1 = WARN (vượt ngưỡng), 2 = lỗi của chính script.
set -euo pipefail

DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
MEM_THRESHOLD="${MEM_THRESHOLD:-90}"
LOG_FILE="${LOG_FILE:-$HOME/logs/healthcheck.log}"

# TODO 1: đảm bảo thư mục chứa LOG_FILE tồn tại; nếu không tạo được → in lỗi ra stderr, exit 2

timestamp="$(date '+%F %T')"
load1="$(cut -d ' ' -f1 /proc/loadavg)"
# TODO 2: mem_pct, disk_pct, procs — dùng các lệnh đã thử ở Bước 2

status="OK"
reasons=()

# TODO 3: nếu disk_pct > DISK_THRESHOLD → status=WARN, thêm "disk X%>Y%" vào reasons
# TODO 4: tương tự cho mem

line="$timestamp $status load1=$load1 mem=${mem_pct}% disk=${disk_pct}% procs=$procs"
if (( ${#reasons[@]} > 0 )); then
    line+=" reason=\"${reasons[*]}\""
fi

# TODO 5: nối $line vào LOG_FILE; nếu ghi thất bại → exit 2

# TODO 6: exit 1 nếu WARN, exit 0 nếu OK
```

Ghi chú cú pháp mới:

| Cú pháp | Ý nghĩa |
|---|---|
| `reasons=()` | Tạo **mảng** (array) rỗng |
| `reasons+=("chuỗi")` | Thêm một phần tử vào mảng |
| `${#reasons[@]}` | Số phần tử của mảng |
| `${reasons[*]}` | Mọi phần tử nối thành một chuỗi, cách nhau bằng dấu cách |
| `line+="..."` | Nối thêm vào chuỗi |

Tự hoàn thành 6 chỗ `TODO`. Gợi ý cho so sánh số: `(( disk_pct > DISK_THRESHOLD ))` — xem [bài 06, mục 4.6](../06-bash-scripting.md#46--điều-kiện-if---test).

### Bước 4 — Kiểm thử thủ công

```bash
chmod +x healthcheck.sh
bash -n healthcheck.sh && shellcheck healthcheck.sh

./healthcheck.sh; echo "exit=$?"
DISK_THRESHOLD=0 ./healthcheck.sh; echo "exit=$?"            # ép WARN về disk
DISK_THRESHOLD=0 MEM_THRESHOLD=0 ./healthcheck.sh; echo "exit=$?"
LOG_FILE=/root/x.log ./healthcheck.sh; echo "exit=$?"         # ép lỗi ghi log
tail -n 5 ~/logs/healthcheck.log
```

Bảng kiểm thử — điền kết quả thực tế của bạn:

| Trường hợp | Exit code mong đợi | Log mong đợi | Thực tế |
|---|---|---|---|
| Mặc định | 0 | 1 dòng `OK` | |
| `DISK_THRESHOLD=0` | 1 | `WARN ... reason="disk N%>0%"` | |
| Cả 2 ngưỡng = 0 | 1 | `reason` có cả disk và mem | |
| `LOG_FILE=/root/x.log` | 2 | Không ghi gì; thông báo lỗi ở stderr | |

### Bước 5 — Cài vào `~/bin` và kiểm tra trong môi trường giống cron

```bash
cp healthcheck.sh ~/bin/healthcheck.sh

env -i HOME="$HOME" LOGNAME="$USER" PATH=/usr/bin:/bin SHELL=/bin/sh \
    /bin/sh -c "$HOME/bin/healthcheck.sh"
echo "exit=$?"
tail -n 1 ~/logs/healthcheck.log
```

Nếu bước này lỗi mà Bước 4 không lỗi → script phụ thuộc vào thứ gì đó chỉ có trong terminal của bạn. Tìm và sửa trước khi đặt cron. (Xem [bài 08, mục 12](../08-cron-scheduling.md#12-đọc-log-và-xử-lý-lỗi).)

### Bước 6 — Đặt lịch cron với `flock`

```bash
service cron status || sudo service cron start
crontab -l > ~/devops-lab/01-linux/lab03/crontab.bak 2>/dev/null || true
crontab -e
```

Thêm (thay `phuong` bằng user của bạn):

```text
MAILTO=""
*/5 * * * * /usr/bin/flock -n /tmp/healthcheck.lock /home/phuong/bin/healthcheck.sh >> /home/phuong/logs/healthcheck-cron.log 2>&1
```

Hai file log khác nhau:

| File | Ai ghi | Chứa gì |
|---|---|---|
| `healthcheck.log` | Script tự ghi | Dữ liệu giám sát — mỗi lần chạy 1 dòng |
| `healthcheck-cron.log` | Redirect của cron | stdout/stderr bất ngờ: thông báo lỗi của script. **Bình thường phải rỗng** |

### Bước 7 — Kiểm chứng log tăng dần

Để WSL mở (ít nhất một terminal), làm việc khác 15–20 phút, sau đó:

```bash
wc -l ~/logs/healthcheck.log
tail -n 5 ~/logs/healthcheck.log
cat ~/logs/healthcheck-cron.log
journalctl -u cron --since "30 min ago" --no-pager | grep healthcheck    # hoặc: grep CRON /var/log/syslog
```

❓ Các dòng có cách nhau đúng 5 phút không? Phút của timestamp là 00, 05, 10…? `healthcheck-cron.log` có rỗng không?

### Bước 8 — Kiểm tra `flock`

Mô phỏng một lần chạy bị treo bằng cách tự giữ khóa:

```bash
flock /tmp/healthcheck.lock sleep 400 &
```

Đợi qua mốc 5 phút tiếp theo, rồi kiểm tra: lần chạy đó có dòng mới trong `healthcheck.log` không? Cron log có dòng `CMD` không? Sau khi `sleep` kết thúc (hoặc `kill %1`), lần kế tiếp có chạy bình thường không?

---

## 4. Kết quả mong đợi

- `healthcheck.log` có thêm một dòng mỗi 5 phút, phút của timestamp là bội số của 5. Định dạng đúng đặc tả.
- `healthcheck-cron.log` rỗng (không có lỗi bất ngờ).
- Log cron có dòng `CMD (/usr/bin/flock -n /tmp/healthcheck.lock ...)` mỗi 5 phút.
- Bảng kiểm thử Bước 4 khớp hoàn toàn cột "mong đợi".
- Bước 8: trong khi khóa bị giữ, cron **vẫn ghi dòng `CMD`** (cron đã kích hoạt `flock`), nhưng `healthcheck.log` **không có dòng mới** — `flock -n` thoát ngay vì không lấy được khóa. Sau khi khóa được nhả, lần kế tiếp chạy bình thường.

<details>
<summary>Script tham khảo — chỉ mở sau khi đã tự hoàn thành và kiểm thử</summary>

```bash
#!/usr/bin/env bash
# healthcheck.sh — ghi một dòng trạng thái tài nguyên mỗi lần chạy.
# Exit code: 0 = OK, 1 = WARN (vượt ngưỡng), 2 = lỗi của chính script.
set -euo pipefail

DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
MEM_THRESHOLD="${MEM_THRESHOLD:-90}"
LOG_FILE="${LOG_FILE:-$HOME/logs/healthcheck.log}"

if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
    echo "healthcheck: không tạo được thư mục log cho $LOG_FILE" >&2
    exit 2
fi

timestamp="$(date '+%F %T')"
load1="$(cut -d ' ' -f1 /proc/loadavg)"
mem_pct="$(free | awk '/^Mem:/ { printf "%d", ($2 - $7) * 100 / $2 }')"
disk_pct="$(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
procs="$(ps -e --no-headers | wc -l)"

status="OK"
reasons=()

if (( disk_pct > DISK_THRESHOLD )); then
    status="WARN"
    reasons+=("disk ${disk_pct}%>${DISK_THRESHOLD}%")
fi
if (( mem_pct > MEM_THRESHOLD )); then
    status="WARN"
    reasons+=("mem ${mem_pct}%>${MEM_THRESHOLD}%")
fi

line="$timestamp $status load1=$load1 mem=${mem_pct}% disk=${disk_pct}% procs=$procs"
if (( ${#reasons[@]} > 0 )); then
    line+=" reason=\"${reasons[*]}\""
fi

if ! echo "$line" >> "$LOG_FILE" 2>/dev/null; then
    echo "healthcheck: không ghi được vào $LOG_FILE" >&2
    exit 2
fi

if [[ "$status" == "WARN" ]]; then
    exit 1
fi
exit 0
```

Điểm cần chú ý:

- Các lệnh có thể thất bại "có chủ đích" (`mkdir`, ghi log) nằm trong `if !` — `set -e` không dừng script ở đó, ta tự xử lý và trả exit code `2` theo đặc tả.
- Với `LOG_FILE=/root/x.log`: `mkdir -p /root` **thành công** (thư mục đã tồn tại thì `mkdir -p` trả về 0), lỗi chỉ xuất hiện ở bước ghi file → exit 2 từ nhánh ghi log. Bash vẫn in thông báo `Permission denied` ra stderr trước khi `2>/dev/null` có hiệu lực, vì các redirect được xử lý từ trái sang phải — không sao, stderr là nơi lỗi nên xuất hiện.
- Script không dùng lệnh nào ngoài `/usr/bin` và `/bin` → chạy được với `PATH` tối giản của cron.

</details>

---

## 5. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `healthcheck.log` không có dòng mới, cron log không có `CMD` | Cron không chạy (WSL khởi động lại) | `service cron status` → start |
| Có `CMD` nhưng không có dòng mới, `healthcheck-cron.log` có lỗi `not found` | Đường dẫn tương đối hoặc lệnh ngoài `PATH` của cron | Đường dẫn tuyệt đối |
| `syntax error: operand expected` ở dòng `(( ... ))` | Biến số liệu rỗng (lệnh thu thập thất bại hoặc trả về chữ) | Chạy `bash -x`, xem giá trị biến |
| `unbound variable` | Gõ sai tên biến, `set -u` bắt được | Sửa tên biến — đây là `set -u` đang giúp bạn |
| Script luôn exit 1 dù không vượt ngưỡng | Dòng cuối là một kiểm tra trả về khác 0 | Kết thúc bằng `exit 0` rõ ràng |
| Mỗi lần chạy ghi **2 dòng** | Có cả `echo` ra stdout lẫn ghi file, cron redirect stdout vào cùng file log | Script chỉ ghi vào `LOG_FILE`, không echo ra stdout; hoặc dùng 2 file log khác nhau như đặc tả |
| Log nhảy thời gian lung tung khi laptop ngủ | WSL bị tạm dừng | Bình thường trên laptop — chính là lý do monitoring thật chạy trên server |

---

## 6. Mở rộng: giới hạn kích thước log bằng logrotate

🟨 Log mỗi 5 phút → ~290 dòng/ngày, sau vài tháng sẽ lớn. Trên server, việc này do **logrotate** đảm nhận: định kỳ đổi tên log cũ, nén lại, xóa bản quá cũ. Cơ chế chi tiết ở [bài 07](../07-logs-monitoring-troubleshooting.md).

Không cần quyền root — chạy logrotate bằng user của bạn với file cấu hình và file trạng thái riêng:

```bash
cat > ~/logs/logrotate.conf <<EOF
$HOME/logs/healthcheck.log {
    size 100k
    rotate 5
    compress
    missingok
    notifempty
}
EOF

logrotate -d -s ~/logs/logrotate.state ~/logs/logrotate.conf    # -d: chạy thử, chỉ in ra sẽ làm gì
logrotate -f -s ~/logs/logrotate.state ~/logs/logrotate.conf    # -f: ép xoay vòng ngay để kiểm tra
ls -l ~/logs/
```

| Chỉ thị | Ý nghĩa |
|---|---|
| `size 100k` | Chỉ xoay vòng khi file lớn hơn 100 KB |
| `rotate 5` | Giữ tối đa 5 bản cũ |
| `compress` | Nén bản cũ bằng gzip (`.gz`) |
| `missingok` | Không báo lỗi nếu file log chưa tồn tại |
| `notifempty` | Không xoay vòng file rỗng |
| `-s <file>` | File trạng thái — logrotate ghi lần xoay vòng cuối vào đây (mặc định ở `/var/lib/logrotate/`, cần root) |

Thêm một dòng cron chạy logrotate mỗi ngày. ❓ Vì sao script healthcheck của bạn vẫn ghi tiếp bình thường sau khi log bị đổi tên? (Gợi ý: script mở file bằng `>>` **mỗi lần chạy**, khác với một daemon giữ file mở liên tục — đây là lý do logrotate có tùy chọn `copytruncate` và `postrotate`.)

---

## 7. Đưa vào dự án taskhub

Script này sẽ dùng lại khi triển khai lên EC2 (Module 06). Commit vào repo dự án:

```bash
cd ~/projects/taskhub                      # repo tạo ở tuần 1
mkdir -p scripts
cp ~/bin/healthcheck.sh scripts/
git checkout -b feat/healthcheck-script
git add scripts/healthcheck.sh
git commit -m "feat(scripts): add resource healthcheck script"
git push -u origin feat/healthcheck-script
```

Tạo Pull Request trên GitHub, tự review (đọc diff, kiểm tra ShellCheck sạch) rồi merge. Đây là lần đầu bạn áp dụng quy trình PR — sẽ học đầy đủ ở [Module 03](../../03-GIT/).

Thêm vào `README.md` của repo một mục ngắn: script làm gì, biến cấu hình, exit code, dòng crontab mẫu.

---

## 8. Dọn dẹp

⚠️ Không dùng `crontab -r` nếu bạn có job khác.

```bash
crontab -e            # xóa dòng healthcheck (và dòng logrotate nếu đã thêm)
# hoặc phục hồi bản sao lưu:
crontab ~/devops-lab/01-linux/lab03/crontab.bak
crontab -l            # xác nhận
```

Giữ lại `~/bin/healthcheck.sh` và log để dùng cho checkpoint. Xóa file khóa nếu muốn: `rm -f /tmp/healthcheck.lock` (không bắt buộc — `flock` không cần xóa file khóa).

---

## 9. Tiêu chí hoàn thành

- [ ] Script đúng đặc tả: định dạng log, 3 loại exit code, ngưỡng cấu hình bằng biến môi trường.
- [ ] Bảng kiểm thử Bước 4 đã điền, khớp mong đợi.
- [ ] `bash -n` và ShellCheck không cảnh báo.
- [ ] Chạy được với `env -i` (môi trường giống cron).
- [ ] Log có ít nhất 4 dòng liên tiếp cách nhau 5 phút do cron tạo ra; `healthcheck-cron.log` rỗng.
- [ ] Giải thích được kết quả Bước 8 (vì sao có `CMD` nhưng không có dòng log).
- [ ] Script đã được merge vào `taskhub/scripts/` qua Pull Request.
- [ ] Ghi ít nhất 1 lỗi gặp phải vào `troubleshooting-journal.md`.
