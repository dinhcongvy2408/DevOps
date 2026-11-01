# Lời giải — 08. Cron & lập lịch tác vụ

> ⚠️ Chỉ đọc sau khi đã tự làm.
> Quay lại bài: [08-cron-scheduling.md](../08-cron-scheduling.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức](#phần-a--câu-hỏi-kiểm-tra-kiến-thức)
- [Phần B — Bài tập tự làm](#phần-b--bài-tập-tự-làm)
  - [Bài 1 — Đọc và viết lịch](#bài-1--đọc-và-viết-lịch)
  - [Bài 2 — Dọn file tạm](#bài-2--dọn-file-tạm)
  - [Bài 3 — Chạy chồng](#bài-3--chạy-chồng)
  - [Bài 4 — Chuyển sang systemd timer](#bài-4--chuyển-sang-systemd-timer)
  - [Bài 5 — Điều tra](#bài-5--điều-tra)

---

## Phần A — Câu hỏi kiểm tra kiến thức

**1.** Cron là một daemon thức dậy mỗi phút, đọc các crontab và chạy lệnh đến giờ. Trên WSL, cron chỉ sống khi WSL đang chạy. WSL tự tắt khi không còn terminal nào mở một lúc, và bị tạm dừng khi laptop ngủ → 2:00 sáng cron không chạy, và cron **không chạy bù**.

**2.**
- `0 3 * * *` — 3:00 sáng mỗi ngày.
- `*/15 * * * *` — mỗi 15 phút (phút 0, 15, 30, 45).
- `0 8 * * 1` — 8:00 sáng thứ Hai.
- `30 23 L * *` — **không hợp lệ** với cron của Ubuntu. `L` ("ngày cuối tháng") là cú pháp của một số hệ thống khác (ví dụ Quartz trong Java). `crontab -e` sẽ báo lỗi `bad day-of-month`. Cách làm "ngày cuối tháng" với cron thường: chạy ngày 28–31 và tự kiểm tra trong lệnh: `30 23 28-31 * * [ "$(date -d tomorrow +\%d)" = "01" ] && /đường/dẫn/script`.
- `0 0 1 1 *` — 0:00 ngày 1 tháng 1 (mỗi năm một lần).

**3.** (a) `30 1 * * *` · (b) `0 */2 * * *` · (c) `0 18 * * 1-5` · (d) `0 0 1,15 * *`.

**4.** Người viết nghĩ "lúc 2 giờ", nhưng trường phút là `*` nên job chạy **mỗi phút** trong giờ 2: 2:00, 2:01, …, 2:59 — **60 lần**. Đúng phải là `0 2 * * *`.

**5.** Shell là `/bin/sh` (dash) thay vì bash; `PATH` tối giản; không đọc `~/.bashrc` (không alias, không biến đã export); thư mục làm việc là home; không có TTY; output không redirect sẽ bị gửi mail hoặc mất.

**6.** Dòng `CMD (...)` chứng minh cron đã **kích hoạt** lệnh đúng giờ. Nó **không** chứng minh lệnh chạy thành công — exit code và lỗi của lệnh không có ở đó.

**7.** Redirect được xử lý **từ trái sang phải**:
- `>> job.log 2>&1`: stdout → file; sau đó stderr → "nơi stdout đang trỏ" = file. **Cả hai vào file.** ✅
- `2>&1 >> job.log`: stderr → nơi stdout đang trỏ **lúc đó** (chưa phải file); sau đó mới chuyển stdout vào file. **Lỗi không vào file.** ❌

**8.** `%` chưa thoát được cron đổi thành xuống dòng; mọi thứ sau `%` đầu tiên trở thành stdin của lệnh. Viết `\%`, hoặc tốt hơn: đưa lệnh vào script và crontab chỉ gọi script.

**9.** `crontab -e`: sửa crontab của **chính user**, có kiểm tra cú pháp khi lưu, không có cột user. `/etc/crontab`: file hệ thống, cần root, sửa trực tiếp bằng editor (không có bước kiểm tra cú pháp — lỗi chỉ thấy trong log cron), có thêm **cột user** giữa lịch và lệnh. `/etc/cron.d/*` dùng định dạng giống `/etc/crontab` (có cột user); tiện để công cụ tự động hóa thêm/xóa job bằng cách tạo/xóa một file.

**10.** Không có `flock`, nếu một lần chạy lâu hơn chu kỳ, lần sau bắt đầu khi lần trước chưa xong → hai bản chạy song song, tranh nhau tài nguyên/file, có thể làm hỏng dữ liệu hoặc gây quá tải dây chuyền. Khóa của `flock` gắn với file descriptor đang mở; khi process kết thúc (kể cả bị kill), kernel đóng file descriptor và **tự nhả khóa** → không bị kẹt khóa. File khóa còn nằm lại trên đĩa cũng không sao.

**11.** Ví dụ 3 tiêu chí: log (timer tự vào journal), chạy bù khi máy tắt (`Persistent=true`), chống chạy chồng (timer mặc định không khởi động thêm khi service đang chạy). Chọn timer khi: cần chạy bù, cần log tập trung, cần giới hạn tài nguyên hoặc phụ thuộc vào service khác, hoặc hệ thống đã quản lý mọi thứ bằng systemd.

**12.** 2:00 giờ Việt Nam (UTC+7) = 19:00 UTC **ngày hôm trước** → `0 19 * * *`.

---

## Phần B — Bài tập tự làm

### Bài 1 — Đọc và viết lịch

| Yêu cầu | Biểu thức | Ghi chú |
|---|---|---|
| (a) Mỗi 10 phút | `*/10 * * * *` | |
| (b) 6:00 và 18:00 mỗi ngày | `0 6,18 * * *` | |
| (c) Mỗi 30 phút, 8:00–18:00, thứ Hai–Sáu | `*/30 8-17 * * 1-5` | Chạy 8:00, 8:30, …, 17:30. Nếu cần cả 18:00, thêm dòng `0 18 * * 1-5` |
| (d) 23:59 thứ Bảy, Chủ nhật | `59 23 * * 6,0` | `6,7` cũng đúng (7 = Chủ nhật) |
| (e) 4:00 ngày 1 mỗi quý | `0 4 1 1,4,7,10 *` | Hoặc `0 4 1 */3 *` |
| (f) Mỗi phút trong giờ 3 sáng Chủ nhật | `* 3 * * 0` | Đây là trường hợp `*` ở trường phút là **cố ý** |
| (g) Một lần khi khởi động | `@reboot` | Trên WSL: khi daemon cron khởi động |
| (h) 2:00 sáng giờ Việt Nam trên server UTC | `0 19 * * *` | |

### Bài 2 — Dọn file tạm

```bash
#!/usr/bin/env bash
# cleanup-tmp.sh — xóa file trong TMP_DIR cũ hơn 2 ngày, ghi số lượng đã xóa vào log.
set -euo pipefail

TMP_DIR="${TMP_DIR:-$HOME/devops-lab/tmp}"
LOG_FILE="${LOG_FILE:-$HOME/logs/cleanup-tmp.log}"
MAX_AGE_MIN=$(( 2 * 24 * 60 ))      # 2 ngày tính bằng phút

mkdir -p "$(dirname "$LOG_FILE")"

if [[ ! -d "$TMP_DIR" ]]; then
    echo "$(date '+%F %T') [WARN] Không có thư mục $TMP_DIR, bỏ qua" >> "$LOG_FILE"
    exit 0
fi

deleted="$(find "$TMP_DIR" -type f -mmin +"$MAX_AGE_MIN" -print -delete | wc -l)"
echo "$(date '+%F %T') [INFO] Đã xóa $deleted file trong $TMP_DIR" >> "$LOG_FILE"
```

- Dùng `-mmin +2880` (phút) để chính xác "cũ hơn 48 giờ". Dùng `-mtime` cũng được nhưng phải hiểu cách làm tròn: `-mtime +1` = cũ hơn 1 ngày tròn, tức từ **2 ngày** trở lên; `-mtime +2` = từ **3 ngày** trở lên.
- `-print -delete | wc -l`: in đường dẫn mỗi file bị xóa, đếm số dòng.

Crontab:

```text
MAILTO=""
0 * * * * /home/phuong/bin/cleanup-tmp.sh >> /home/phuong/logs/cleanup-tmp-cron.log 2>&1
```

Kiểm thử:

```bash
mkdir -p ~/devops-lab/tmp
touch -d "3 days ago" ~/devops-lab/tmp/old1 ~/devops-lab/tmp/old2
touch ~/devops-lab/tmp/new1
```

Bằng chứng cần có: log cron có ít nhất 2 dòng `CMD (/home/phuong/bin/cleanup-tmp.sh ...)` cách nhau 1 giờ; `cleanup-tmp.log` có dòng `Đã xóa 2 file` ở lần đầu và `Đã xóa 0 file` ở lần sau; `new1` còn nguyên.

### Bài 3 — Chạy chồng

```bash
#!/usr/bin/env bash
set -euo pipefail
LOG="$HOME/logs/slow-job.log"
echo "$(date '+%T') START pid=$$" >> "$LOG"
sleep 90
echo "$(date '+%T') END   pid=$$" >> "$LOG"
```

Không có `flock` (`* * * * * /home/phuong/bin/slow-job.sh`), log kiểu:

```text
11:00:01 START pid=3101
11:01:01 START pid=3150     ← bản 2 bắt đầu khi bản 1 chưa xong
11:01:31 END   pid=3101
11:02:01 START pid=3199
11:02:31 END   pid=3150
```

Luôn có 2 bản chạy song song.

Có `flock -n` (`* * * * * /usr/bin/flock -n /tmp/slow-job.lock /home/phuong/bin/slow-job.sh`):

```text
11:00:01 START pid=3301
11:01:31 END   pid=3301     ← phút 11:01 bị bỏ qua vì khóa đang bị giữ
11:02:01 START pid=3402
11:03:31 END   pid=3402
```

Chỉ một bản chạy tại một thời điểm; job thực tế chạy mỗi 2 phút. Log cron vẫn có dòng `CMD` **mỗi phút** — chứng minh cron có kích hoạt, nhưng `flock -n` từ chối chạy.

> Bài học: nếu job thường xuyên bị bỏ qua, nghĩa là job chạy chậm hơn chu kỳ — cần tối ưu job hoặc giãn lịch, không chỉ thêm khóa.

### Bài 4 — Chuyển sang systemd timer

`/etc/systemd/system/cleanup-tmp.service`:

```ini
[Unit]
Description=Dọn file tạm cũ hơn 2 ngày

[Service]
Type=oneshot
User=phuong
ExecStart=/home/phuong/bin/cleanup-tmp.sh
```

`/etc/systemd/system/cleanup-tmp.timer`:

```ini
[Unit]
Description=Chạy cleanup-tmp mỗi giờ

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cleanup-tmp.timer
systemctl list-timers cleanup-tmp.timer
sudo systemctl start cleanup-tmp.service          # chạy thử ngay, không cần chờ lịch
journalctl -u cleanup-tmp.service -n 20 --no-pager
```

Ba câu so sánh mẫu:

1. Với timer, `journalctl -u cleanup-tmp.service` cho thấy ngay thời điểm chạy, output và exit code; với cron phải tự sắp xếp redirect và tự đọc file log.
2. `systemctl start cleanup-tmp.service` chạy job **trong đúng môi trường** sẽ dùng khi chạy theo lịch — không cần mẹo `env -i` như với cron.
3. Cron chỉ cần một dòng nên nhanh hơn cho việc đơn giản, nhưng timer có `Persistent=true` và tự chống chạy chồng.

Dọn dẹp:

```bash
sudo systemctl disable --now cleanup-tmp.timer
sudo rm /etc/systemd/system/cleanup-tmp.{service,timer}
sudo systemctl daemon-reload
```

### Bài 5 — Điều tra

| Dòng | Vấn đề |
|---|---|
| `* 3 * * * backup.sh` | (1) Chạy **60 lần** trong giờ 3, không phải 1 lần. (2) Đường dẫn tương đối — `backup.sh` không có trong `PATH` của cron → `not found`. (3) Không ghi log → không biết lỗi |
| `*/5 ... cd /opt/app && ./check.sh > check.log` | (4) `>` **ghi đè** log mỗi 5 phút → mất lịch sử. (5) Thiếu `2>&1` → lỗi bị mất. (6) User chạy crontab cần quyền ghi trong `/opt/app`. (7) Không chống chạy chồng nếu `check.sh` có thể chậm |
| `0 0 * * * tar ... $(date +%F) ...` | (8) `%` chưa thoát → lệnh bị cắt ở `%`. (9) Nếu là crontab của user thường: một số file trong `/etc` (ví dụ `/etc/shadow`) chỉ root đọc được → tar lỗi. (10) `/backup` phải tồn tại và ghi được. Không có log |
| `@daily source ~/.bashrc && python3 report.py` | (11) Lệnh chạy bằng `/bin/sh` (dash) — `source` là lệnh của Bash, dash không có → `source: not found`. (12) Dù có nạp được, `~/.bashrc` của Ubuntu **thoát ngay** khi shell không tương tác (đoạn kiểm tra `case $- in *i*)` ở đầu file) → không nạp được gì. (13) `report.py` là đường dẫn tương đối, cron chạy ở home. Không có log |

Viết lại:

```text
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
MAILTO=""

0 3 * * *    /opt/app/scripts/backup.sh >> /var/log/app/backup.log 2>&1
*/5 * * * *  /usr/bin/flock -n /tmp/check.lock /opt/app/check.sh >> /var/log/app/check.log 2>&1
0 0 * * *    /opt/app/scripts/backup-etc.sh >> /var/log/app/backup-etc.log 2>&1
@daily       /opt/app/scripts/report.sh >> /var/log/app/report.log 2>&1
```

Cùng với:

- `backup-etc.sh` chứa lệnh `tar` (trong script không cần thoát `%`), và job này đặt trong crontab của **root** (hoặc `/etc/cron.d/` với cột user `root`) vì cần đọc toàn bộ `/etc`.
- `report.sh` tự nạp biến cần thiết từ một file cấu hình riêng bằng đường dẫn tuyệt đối (ví dụ `source /opt/app/config/report.env`), rồi `cd` vào thư mục ứng dụng và chạy `python3 report.py`.
- Thư mục `/var/log/app/` tồn tại, user chạy job có quyền ghi.
