# 07. Logs, Monitoring & Troubleshooting

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [02. Lệnh thiết yếu & xử lý văn bản](02-essential-commands-text.md), [04. Processes & systemd](04-processes-systemd.md)
> Môi trường: `[WSL]` Ubuntu 24.04, `[Sandbox]` container `ubuntu:22.04`

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc / luồng hoạt động](#6-sơ-đồ-kiến-trúc--luồng-hoạt-động)
7. [Các câu lệnh cần biết](#7-các-câu-lệnh-cần-biết)
8. [Giải thích câu lệnh và tham số](#8-giải-thích-câu-lệnh-và-tham-số)
9. [Bài thực hành từng bước](#9-bài-thực-hành-từng-bước)
10. [Kết quả mong đợi](#10-kết-quả-mong-đợi)
11. [Các lỗi thường gặp](#11-các-lỗi-thường-gặp)
12. [Đọc log và xử lý lỗi](#12-đọc-log-và-xử-lý-lỗi)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Biết log của hệ thống và ứng dụng nằm ở đâu trên Ubuntu, và hiểu vì sao có **hai** hệ thống log chạy song song: `systemd-journald` và `rsyslog`.
- Dùng `journalctl` để lọc log theo service, mức độ nghiêm trọng, khoảng thời gian.
- Cấu hình `logrotate` để log của ứng dụng không làm đầy ổ đĩa.
- **Đọc stack trace Java** của một ứng dụng Spring Boot và tìm ra nguyên nhân gốc trong vài phút.
- Đánh giá tình trạng CPU, RAM, ổ đĩa của server bằng `uptime`, `top`, `free`, `vmstat`, `df`, `du`, `iostat`, và giải thích được từng con số.
- Áp dụng một **quy trình có hệ thống** cho 2 tình huống kinh điển: "server chậm" và "ứng dụng chết / không truy cập được".

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Phần lớn thời gian "chữa cháy" của một DevOps Engineer gồm hai việc: **đọc log** và **đọc số liệu tài nguyên**. Các tình huống thật:

| Tình huống | Bạn cần biết |
|---|---|
| "Deploy xong app không lên" | Xem log service bằng `journalctl -u`, đọc stack trace Java tìm `Caused by` |
| "Đêm qua app tự chết lúc 3 giờ" | Tìm dấu vết **OOM killer** trong log kernel |
| "Server chậm, khách hàng phàn nàn" | Đọc load average, CPU, RAM, I/O để biết **tài nguyên nào** đang nghẽn |
| "Ổ đĩa 100% dù đã xóa log" | Hiểu vì sao `df` và `du` cho kết quả khác nhau |
| "Log app chiếm 40GB" | Cấu hình `logrotate` |
| Phỏng vấn: "Server chậm, bạn làm gì?" | Câu hỏi gần như chắc chắn gặp — cần trả lời theo quy trình, không liệt kê lệnh lung tung |

Module 08 (Monitoring) sau này sẽ dùng Prometheus, Grafana, Loki để **tự động hóa** đúng những việc bạn làm bằng tay trong bài này. Hiểu bằng tay trước thì mới đọc được dashboard sau.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Log là gì?

**Log** (nhật ký) là các dòng văn bản mà chương trình ghi lại về những gì nó đã làm: khởi động, nhận request, gặp lỗi, tắt. Một dòng log tốt thường có:

```text
2026-10-31T09:15:02+0700  ERROR  taskhub  [main]  Failed to connect to database at localhost:5432
│                         │      │        │       └ nội dung
│                         │      │        └ luồng xử lý (thread)
│                         │      └ nguồn (chương trình nào)
│                         └ mức độ nghiêm trọng
└ thời điểm (luôn có múi giờ)
```

Log trả lời câu hỏi **"chuyện gì đã xảy ra?"**. Số liệu tài nguyên (CPU, RAM, disk) trả lời câu hỏi **"hệ thống đang khỏe hay yếu?"**. Khi debug bạn cần cả hai.

### 3.2. Mức độ nghiêm trọng (log level)

Linux dùng 8 mức theo chuẩn **syslog**. Số càng nhỏ càng nghiêm trọng:

| Số | Tên | Nghĩa | Ví dụ |
|---|---|---|---|
| 0 | `emerg` | Hệ thống không dùng được | Kernel panic |
| 1 | `alert` | Phải xử lý ngay | |
| 2 | `crit` | Nghiêm trọng | Ổ đĩa hỏng |
| 3 | `err` | Lỗi | Service không khởi động được |
| 4 | `warning` | Cảnh báo | Sắp hết dung lượng |
| 5 | `notice` | Bình thường nhưng đáng chú ý | |
| 6 | `info` | Thông tin | Service đã khởi động |
| 7 | `debug` | Chi tiết để debug | |

Ứng dụng Java (Logback/Log4j) dùng bộ mức gần giống: `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE`.

### 3.3. Hai hệ thống log trên Ubuntu

Ubuntu chạy song song hai thành phần — người mới thường bối rối vì cùng một lỗi xuất hiện ở hai nơi:

| | `systemd-journald` | `rsyslog` |
|---|---|---|
| Là gì | Dịch vụ log của systemd | Dịch vụ syslog truyền thống |
| Lưu ở đâu | `/var/log/journal/` (file **nhị phân**) | `/var/log/syslog`, `/var/log/auth.log`… (file **văn bản**) |
| Đọc bằng | `journalctl` | `less`, `grep`, `tail` |
| Ưu điểm | Lọc mạnh theo service, thời gian, mức độ; tự gắn metadata (PID, unit) | Đọc bằng mọi công cụ văn bản; quen thuộc, dễ chuyển đi nơi khác |

Luồng thông thường: journald nhận log trước (từ kernel, từ stdout/stderr của các service, từ lời gọi syslog), sau đó **chuyển tiếp một bản** cho rsyslog để ghi ra file văn bản.

> Trên WSL: nếu systemd chưa bật (bài 04), journald không chạy và `/var/log/syslog` có thể không tồn tại. Những bước dùng `journalctl` khi đó hãy đánh dấu lại và làm trên EC2 ở tuần 11–12.

### 3.4. Tài nguyên của một server

Mọi vấn đề hiệu năng đều quy về 4 loại tài nguyên: **CPU, RAM, ổ đĩa (dung lượng + tốc độ I/O), mạng**. Với mỗi tài nguyên, có 3 câu hỏi (phương pháp **USE** của Brendan Gregg):

| Chữ | Tiếng Anh | Câu hỏi |
|---|---|---|
| **U** | Utilization (mức sử dụng) | Tài nguyên bận bao nhiêu % thời gian? |
| **S** | Saturation (mức bão hòa) | Có việc phải **xếp hàng chờ** không? |
| **E** | Errors (lỗi) | Có lỗi nào được ghi nhận không? |

Ý quan trọng: CPU 100% chưa chắc đã có vấn đề (máy đang làm việc hết sức). Vấn đề thật là khi **có hàng đợi** — tiến trình phải chờ CPU, chờ đĩa, chờ RAM.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Bản đồ `/var/log`

| File / thư mục | Chứa gì | Khi nào xem |
|---|---|---|
| `/var/log/syslog` | Log chung của hệ thống (rsyslog) | Không biết xem đâu thì xem đây trước |
| `/var/log/auth.log` | Đăng nhập, `sudo`, SSH | Ai đã đăng nhập? SSH bị từ chối vì sao? Ai đó đang dò mật khẩu? |
| `/var/log/kern.log` | Log của kernel | Lỗi phần cứng, OOM killer |
| `/var/log/dpkg.log` | Cài/gỡ gói ở mức `dpkg` | "Ai cài/nâng cấp gói gì, lúc nào?" |
| `/var/log/apt/history.log` | Lịch sử lệnh `apt` | Sau khi `apt upgrade` thì app hỏng — gói nào đã đổi? |
| `/var/log/nginx/` | `access.log`, `error.log` của Nginx | Request nào lỗi 502? (Module 02) |
| `/var/log/journal/` | Dữ liệu nhị phân của journald | Không đọc trực tiếp — dùng `journalctl` |
| `/var/log/cloud-init.log` | Quá trình khởi tạo máy ảo cloud | Trên EC2: script `user data` có chạy không? (Module 06) |
| `/var/log/<app>/` | Log riêng của ứng dụng | Ví dụ `/var/log/taskhub/app.log` |

File cũ thường có dạng `syslog.1`, `syslog.2.gz` — đó là kết quả của **log rotation** (xem 4.4). Đọc file nén bằng `zless`, `zgrep` mà không cần giải nén.

**Quyền đọc log:** nhiều file trong `/var/log` chỉ đọc được bởi root hoặc thành viên group `adm`. Kiểm tra bằng `id` — nếu thấy `adm` trong danh sách group thì bạn đọc được mà không cần `sudo`.

### 4.2. 🟥 `journalctl` — đọc log của journald

Bài 04 đã dùng `journalctl -u <service>`. Ở đây bạn học cách **lọc chính xác** — kỹ năng quyết định bạn tìm ra lỗi trong 1 phút hay 30 phút.

Bốn trục lọc quan trọng, có thể **kết hợp** với nhau:

| Trục | Tham số | Ví dụ |
|---|---|---|
| Nguồn | `-u <unit>`, `-t <tag>`, `-k` (kernel), `_PID=` | `-u nginx`, `-t taskhub` |
| Mức độ | `-p <mức>` hoặc `-p <từ>..<đến>` | `-p err` = err + crit + alert + emerg |
| Thời gian | `--since`, `--until`, `-b` | `--since "10 min ago"`, `-b` (từ lần khởi động hiện tại) |
| Số lượng / theo dõi | `-n <số dòng>`, `-f`, `-r` | `-n 50`, `-f` (như `tail -f`) |

Ví dụ kết hợp: "lỗi của nginx trong 1 giờ qua":

```bash
journalctl -u nginx -p err --since "1 hour ago" --no-pager
```

### 4.3. 🟥 Đọc stack trace Java

Ứng dụng Spring Boot khi gặp lỗi sẽ in **stack trace** (dấu vết ngăn xếp) — danh sách các hàm đang được gọi lồng nhau tại thời điểm lỗi. Một stack trace có thể dài 200 dòng, nhưng bạn chỉ cần đọc **3–5 dòng đúng chỗ**.

Cấu trúc:

```text
<Loại exception>: <thông báo>                     ← lỗi ở tầng ngoài cùng
    at <package.Class.method>(File.java:dòng)     ← hàm đang chạy khi lỗi (trên cùng = sâu nhất)
    at ...                                        ← các hàm đã gọi tới nó
Caused by: <Loại exception>: <thông báo>          ← lỗi bên trong gây ra lỗi trên
    at ...
    ... 25 more                                   ← các dòng trùng với phần trên, bị lược bớt
Caused by: <Loại exception>: <thông báo>          ← "Caused by" CUỐI CÙNG = nguyên nhân gốc
    at ...
```

**Ba quy tắc đọc:**

1. **Nhảy xuống `Caused by:` cuối cùng** — đó thường là **nguyên nhân gốc** (root cause). Các exception phía trên chỉ là lớp "bọc" của framework.
2. Đọc **thông báo** của nó thật kỹ — thường đã nói rõ vấn đề (`Connection refused`, `password authentication failed`, `No such file`).
3. Tìm dòng `at ...` **đầu tiên thuộc package của bạn** (ví dụ `com.example.taskhub`) — đó là chỗ trong code của bạn liên quan đến lỗi. Bỏ qua các dòng `org.springframework`, `java.base`, `com.zaxxer.hikari`… trừ khi cần.

Với lỗi khởi động, Spring Boot thường in thêm một khối tóm tắt rất dễ đọc ở cuối (`APPLICATION FAILED TO START`). **Tìm khối đó trước.** Ví dụ cụ thể ở [mục 5](#5-ví-dụ-thực-tế).

### 4.4. 🟥 `logrotate` — không để log làm đầy ổ đĩa

Log ghi liên tục sẽ phình to mãi. **Log rotation** (xoay vòng log) là: định kỳ đổi tên file log hiện tại (`app.log` → `app.log.1`), nén file cũ, xóa file quá cũ, và bắt đầu file mới.

Trên Ubuntu, `logrotate` được chạy **mỗi ngày** (bằng systemd timer `logrotate.timer`). Cấu hình:

- `/etc/logrotate.conf` — cấu hình chung.
- `/etc/logrotate.d/<tên>` — cấu hình cho từng ứng dụng. Bạn thêm file của mình vào đây.

Ví dụ cho dự án `taskhub` — file `/etc/logrotate.d/taskhub`:

```text
/var/log/taskhub/*.log {
    daily               # xoay mỗi ngày
    rotate 14           # giữ 14 bản cũ, cũ hơn thì xóa
    compress            # nén bản cũ bằng gzip
    delaycompress       # bản mới nhất (.1) chưa nén, để còn đọc/grep nhanh
    missingok           # không báo lỗi nếu file không tồn tại
    notifempty          # file rỗng thì không xoay
    copytruncate        # xem giải thích bên dưới
    su taskhub taskhub  # xoay với quyền user taskhub (thư mục thuộc taskhub)
}
```

> Ghi chú `#` ở cuối dòng chỉ để giải thích trong bài. Khi viết file thật, nên đặt chú thích trên một dòng riêng.

**`copytruncate` hay `create`?** Đây là câu hỏi hay gặp khi phỏng vấn:

| | `create` (mặc định) | `copytruncate` |
|---|---|---|
| Cách làm | Đổi tên `app.log` → `app.log.1`, tạo `app.log` mới rỗng | **Sao chép** `app.log` → `app.log.1`, rồi **cắt rỗng** `app.log` tại chỗ |
| Vấn đề | Ứng dụng vẫn đang mở file cũ (đã đổi tên) → tiếp tục ghi vào `app.log.1`! Phải báo ứng dụng **mở lại file** bằng `postrotate` (ví dụ gửi tín hiệu, `systemctl reload`) | Có thể **mất vài dòng log** ghi vào đúng khoảnh khắc giữa lúc sao chép và cắt |
| Dùng khi | Ứng dụng hỗ trợ mở lại file log (Nginx, rsyslog) | Ứng dụng không hỗ trợ mở lại file |

Vì sao ứng dụng vẫn ghi vào file đã đổi tên? Vì process giữ một **file descriptor** (bộ mô tả file — "tay cầm" trỏ tới inode, xem [bài 01](01-linux-architecture-filesystem.md#44--liên-kết-mềm-và-liên-kết-cứng)), không phải giữ **tên** file. Đổi tên không làm đổi inode.

> 💡 Với ứng dụng Java hiện đại, cách phổ biến hơn là: để Logback tự xoay log, **hoặc** ghi log ra stdout và để systemd-journald/Docker thu thập. Module 04 và 08 sẽ dùng cách thứ hai. `logrotate` vẫn cần cho mọi log ghi ra file trên server.

### 4.5. 🟥 CPU: `uptime`, load average, `top`

**Load average** (tải trung bình) là số tiến trình trung bình **đang chạy hoặc đang chờ** được chạy, tính trong 1, 5, 15 phút gần nhất. Trên Linux, con số này còn tính cả tiến trình đang chờ I/O ổ đĩa (trạng thái `D`).

Cách đọc: **so với số nhân CPU** (`nproc`).

| Máy 4 nhân, load = | Ý nghĩa |
|---|---|
| 1.0 | Dùng ~25% khả năng, thoải mái |
| 4.0 | Vừa đủ tải, không ai phải chờ |
| 8.0 | Trung bình luôn có 4 tiến trình **xếp hàng chờ** → bão hòa |

Ba con số còn cho biết **xu hướng**: `load average: 7.80, 3.10, 1.20` → tải đang **tăng nhanh** (1 phút cao hơn nhiều so với 15 phút). Ngược lại `1.20, 3.10, 7.80` → sự cố đang qua đi.

Load cao không có nghĩa chắc chắn là CPU — có thể là chờ I/O. Phải nhìn tiếp dòng `%Cpu(s)` của `top`:

```text
%Cpu(s): 12.0 us,  3.0 sy,  0.0 ni, 60.0 id, 25.0 wa,  0.0 hi,  0.0 si,  0.0 st
```

| Trường | Nghĩa | Cao thì nghĩ đến |
|---|---|---|
| `us` | user — chạy code ứng dụng | App tính toán nhiều, vòng lặp vô hạn, GC Java |
| `sy` | system — chạy code kernel | Nhiều system call, nhiều kết nối mạng |
| `id` | idle — rảnh | |
| `wa` | I/O wait — CPU rảnh nhưng có tiến trình chờ đĩa | **Ổ đĩa là nút cổ chai** |
| `st` | steal — CPU bị hypervisor lấy cho máy ảo khác | Trên cloud: máy ảo đang bị thiếu CPU thật |

### 4.6. 🟥 RAM: `free -h` và vì sao "RAM free thấp" không đáng sợ

```text
               total        used        free      shared  buff/cache   available
Mem:           7.7Gi       2.1Gi       0.4Gi        12Mi       5.2Gi       5.3Gi
Swap:          2.0Gi          0B       2.0Gi
```

Người mới nhìn `free 0.4Gi` và hoảng. Thực tế:

- Linux dùng RAM rảnh làm **cache** cho ổ đĩa (`buff/cache`) để đọc file nhanh hơn. RAM để trống là RAM lãng phí.
- Khi ứng dụng cần RAM, kernel **tự giải phóng cache** ngay.
- Cột cần nhìn là **`available`** — lượng RAM thực sự có thể cấp cho ứng dụng mới. Ở ví dụ trên còn 5.3Gi → hoàn toàn khỏe.

Dấu hiệu **thiếu RAM thật**:

1. `available` rất thấp (vài % của `total`).
2. **Swap** (vùng trao đổi — dùng ổ đĩa làm RAM tạm) đang được dùng **và liên tục ra vào** (cột `si`/`so` của `vmstat` khác 0 liên tục).
3. Kernel kích hoạt **OOM killer** (Out-Of-Memory killer — "kẻ giết tiến trình khi hết bộ nhớ"): chọn và giết tiến trình chiếm nhiều RAM nhất — thường chính là ứng dụng Java của bạn.

### 4.7. 🟥 OOM killer và `dmesg`

Khi OOM killer ra tay, ứng dụng của bạn **chết không kịp để lại log** (bị giết bằng `SIGKILL`, không bắt được). Dấu vết duy nhất nằm trong **log kernel**:

```text
Out of memory: Killed process 2345 (java) total-vm:4123456kB, anon-rss:3012345kB, file-rss:0kB, shmem-rss:0kB, UID:999 pgtables:6200kB oom_score_adj:0
```

Đọc: tiến trình PID `2345`, tên `java`, của user UID `999`, đang chiếm ~3GB RAM thật (`anon-rss`) thì bị giết.

Tìm bằng:

```bash
sudo dmesg -T | grep -i -E "out of memory|killed process"
journalctl -k | grep -i "killed process"
```

Phía systemd sẽ ghi `Main process exited, code=killed, status=9/KILL`. Phía Docker, container bị OOM có exit code `137` (= 128 + 9, tín hiệu số 9 là `SIGKILL`) — bạn sẽ gặp lại ở Module 04.

### 4.8. 🟥 Ổ đĩa: dung lượng (`df`, `du`) và tốc độ (`iostat`)

**Hai câu hỏi khác nhau:**

| Câu hỏi | Công cụ |
|---|---|
| Ổ nào sắp đầy? | `df -h` (toàn ổ), `df -i` (inode) |
| Thư mục nào chiếm chỗ? | `du -sh`, `du -h --max-depth=1` |
| Ổ có bị quá tải đọc/ghi không? | `iostat -xz 1` (🟨), cột `wa` trong `top`/`vmstat` |

**Quy trình tìm "thủ phạm" làm đầy ổ** — đi từ trên xuống, mỗi lần một cấp:

```bash
df -h                                          # ổ nào đầy? giả sử là /
sudo du -h --max-depth=1 -x / 2>/dev/null | sort -h | tail -5
sudo du -h --max-depth=1 -x /var 2>/dev/null | sort -h | tail -5
# ... tiếp tục đi sâu vào thư mục lớn nhất
```

`-x` nghĩa là **không đi sang ổ khác** (không tính `/mnt/c`, `/proc`…).

### 4.9. 🟨 Vì sao `df` báo đầy mà `du` không thấy?

Tình huống kinh điển: ổ 100%, ai đó `rm` file log 20GB, nhưng `df` vẫn báo 100%.

Lý do: **file bị xóa nhưng một process vẫn đang mở nó.** `rm` chỉ xóa **tên** (nhãn trỏ tới inode). Dữ liệu chỉ thực sự được giải phóng khi **không còn tên nào VÀ không còn process nào mở**. `du` đếm theo tên → không thấy. `df` hỏi filesystem → vẫn thấy dung lượng bị chiếm.

Tìm bằng:

```bash
sudo lsof +L1
```

```text
COMMAND  PID    USER   FD   TYPE DEVICE   SIZE/OFF NLINK  NODE NAME
java    2345 taskhub    1w   REG  259,1 21474836480     0 13421 /var/log/taskhub/app.log (deleted)
```

`NLINK 0` = không còn tên nào, `(deleted)` = đã bị xóa, nhưng `java` PID 2345 vẫn giữ. Cách giải phóng: **khởi động lại process** đó (hoặc 🟦 cắt rỗng qua `/proc/2345/fd/1`).

> **Bài học vận hành:** muốn dọn file log đang được ghi, đừng `rm` — hãy dùng `truncate -s 0 app.log` (cắt rỗng, giữ nguyên inode) hoặc cấu hình logrotate đúng.

**Hết inode** (`df -i` báo `IUse%` 100%): ổ vẫn còn dung lượng nhưng không tạo được file mới (`No space left on device`). Thường do hàng triệu file nhỏ (session, cache, mail queue). Tìm thư mục có nhiều file nhất:

```bash
sudo find / -xdev -type f 2>/dev/null | cut -d/ -f2,3 | sort | uniq -c | sort -rn | head
```

### 4.10. 🟥 `ss -tulpn` — port nào đang mở, của process nào

Khi "app không truy cập được", một câu hỏi bắt buộc: **app có đang lắng nghe (listen) trên port không?**

```bash
sudo ss -tulpn
```

```text
Netid State  Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
tcp   LISTEN 0      4096       127.0.0.1:5432       0.0.0.0:*     users:(("postgres",pid=812,fd=6))
tcp   LISTEN 0      100                *:8080             *:*     users:(("java",pid=2345,fd=12))
```

| Tham số | Nghĩa |
|---|---|
| `-t` / `-u` | TCP / UDP |
| `-l` | Chỉ socket đang lắng nghe (listening) |
| `-p` | Hiện process (cần `sudo` để thấy process của user khác) |
| `-n` | Hiện số port thay vì tên dịch vụ (`5432` thay vì `postgresql`) |

Đọc nhanh cột `Local Address`: `127.0.0.1:5432` = chỉ nhận kết nối **từ chính máy này**; `*:8080` hoặc `0.0.0.0:8080` = nhận từ **mọi** địa chỉ. Chi tiết về địa chỉ, port, firewall ở Module 02.

### 4.11. 🟨 `vmstat` và `iostat` — nhìn theo thời gian

`top` cho một ảnh chụp. `vmstat 1` in một dòng mỗi giây — thấy được **xu hướng**:

```text
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0      0 412000  81000 5300000    0    0     5    20  310  620  8  2 90  0  0
 6  3      0 398000  81000 5300000    0    0  9800 45000 2100 3900 20  8 30 42  0
```

| Cột | Nghĩa | Đáng lo khi |
|---|---|---|
| `r` | Số tiến trình chờ CPU | Lớn hơn số nhân liên tục |
| `b` | Số tiến trình bị chặn chờ I/O | Khác 0 liên tục |
| `si` / `so` | Swap in / swap out (KB/s) | Khác 0 liên tục → thiếu RAM |
| `bi` / `bo` | Đọc / ghi đĩa (block/s) | Tăng vọt cùng lúc với `wa` cao |
| `wa` | % CPU chờ I/O | Cao → đĩa là nút cổ chai |

Dòng đầu tiên của `vmstat` là trung bình từ lúc khởi động — **bỏ qua**, đọc từ dòng thứ hai.

`iostat -xz 1` (gói `sysstat`) cho chi tiết từng ổ: `%util` gần 100% = ổ bận liên tục; `r_await`/`w_await` = thời gian trung bình mỗi lần đọc/ghi (ms) — với SSD, hàng chục ms trở lên là chậm.

### 4.12. 🟥 Phương pháp troubleshooting

**Nguyên tắc vàng:** đi từ **tổng quan → chi tiết**, **quan sát trước khi sửa**, **ghi lại mọi thứ**.

**Checklist 60 giây đầu tiên** khi SSH vào một server có vấn đề (chỉ quan sát, chưa sửa gì):

```bash
uptime                      # load bao nhiêu, xu hướng tăng hay giảm?
nproc                       # bao nhiêu nhân để so với load
free -h                     # còn RAM available không? swap?
df -h; df -i                # ổ đầy? inode?
top                         # (nhấn P, rồi M) ai ăn CPU, ai ăn RAM? %wa? %st?
sudo dmesg -T | tail -20    # kernel có kêu gì không? OOM? lỗi đĩa?
journalctl -p err -b -n 30  # lỗi gần đây của hệ thống
sudo ss -tulpn              # các service có đang listen không?
```

Sơ đồ quyết định cho 2 tình huống kinh điển ở [mục 6](#6-sơ-đồ-kiến-trúc--luồng-hoạt-động).

---

## 5. Ví dụ thực tế

### Ví dụ 1: Spring Boot không khởi động vì không kết nối được PostgreSQL

`journalctl -u taskhub -n 80` cho ra (đã lược bớt):

```text
2026-10-31T09:20:11.204+07:00  INFO 2345 --- [taskhub] [main] c.example.taskhub.TaskhubApplication : Starting TaskhubApplication v0.1.0 using Java 21.0.5
2026-10-31T09:20:13.871+07:00  INFO 2345 --- [taskhub] [main] com.zaxxer.hikari.HikariDataSource   : HikariPool-1 - Starting...
2026-10-31T09:20:13.990+07:00 ERROR 2345 --- [taskhub] [main] com.zaxxer.hikari.pool.HikariPool    : HikariPool-1 - Exception during pool initialization.

org.postgresql.util.PSQLException: Connection to localhost:5432 refused. Check that the hostname and port are correct and that the postmaster is accepting TCP/IP connections.
	at org.postgresql.core.v3.ConnectionFactoryImpl.openConnectionImpl(ConnectionFactoryImpl.java:352)
	at org.postgresql.core.ConnectionFactory.openConnection(ConnectionFactory.java:54)
	at org.postgresql.jdbc.PgConnection.<init>(PgConnection.java:273)
	...
	at com.zaxxer.hikari.pool.HikariPool.<init>(HikariPool.java:115)
	...
Caused by: java.net.ConnectException: Connection refused
	at java.base/sun.nio.ch.Net.connect0(Native Method)
	at java.base/sun.nio.ch.Net.connect(Net.java:589)
	...
	... 52 common frames omitted
```

> Số dòng (`:352`, `:54`…) và phiên bản thư viện trên máy bạn sẽ khác — hãy tập trung vào **cấu trúc**.

**Cách đọc:**

1. `Caused by` cuối cùng: `java.net.ConnectException: Connection refused` → ở tầng mạng, **có máy trả lời nhưng không có ai nghe ở port đó**. (Nếu là `Connection timed out` thì lại khác — gói tin không tới được nơi, thường do firewall. Module 02 sẽ phân biệt kỹ.)
2. Thông báo phía trên: `Connection to localhost:5432 refused` → app đang kết nối tới **localhost:5432**.
3. Kiểm tra giả thuyết, không sửa vội:

```bash
sudo ss -tlnp | grep 5432        # có ai listen 5432 không?
systemctl status postgresql      # PostgreSQL có chạy không?
```

Các nguyên nhân hay gặp: PostgreSQL chưa chạy; PostgreSQL chạy ở máy/container khác nhưng cấu hình vẫn trỏ `localhost`; sai port. **Gợi ý cho Module 04:** khi chạy bằng Docker Compose, `localhost` bên trong container app là **chính container app**, không phải container PostgreSQL — lỗi này sẽ xuất hiện y hệt.

### Ví dụ 2: Port 8080 đã bị chiếm

```text
***************************
APPLICATION FAILED TO START
***************************

Description:

Web server failed to start. Port 8080 was already in use.

Action:

Identify and stop the process that's listening on port 8080 or configure this application to listen on another port.
```

Spring Boot đã chẩn đoán sẵn. Việc của bạn là tìm ai đang giữ port:

```bash
sudo ss -tlnp | grep ':8080'
```

```text
LISTEN 0  100  *:8080  *:*  users:(("java",pid=1990,fd=12))
```

Thường đó là **bản cũ của chính app** chưa tắt (ví dụ bạn chạy tay bằng `java -jar` rồi lại chạy service). Xem nó là gì trước khi tắt: `ps -fp 1990`.

### Ví dụ 3: "Server chậm" — nhìn số liệu và kết luận

```text
$ uptime
 14:02:11 up 12 days,  3:41,  1 user,  load average: 9.12, 8.70, 5.33
$ nproc
2
$ top   (dòng %Cpu)
%Cpu(s):  4.1 us,  2.0 sy,  0.0 ni,  3.2 id, 90.5 wa,  0.0 hi,  0.2 si,  0.0 st
```

Kết luận: load 9 trên máy 2 nhân → bão hòa nặng. Nhưng `us` chỉ 4% và `wa` 90% → **không phải thiếu CPU mà là chờ ổ đĩa**. Bước tiếp theo: `iostat -xz 1` xem ổ nào bận, `top` tìm process ở trạng thái `D`, kiểm tra `free -h` xem có phải đang swap không (thiếu RAM → swap → đĩa quá tải là chuỗi hay gặp).

---

## 6. Sơ đồ kiến trúc / luồng hoạt động

### 6.1. Đường đi của log trên Ubuntu

```text
 kernel ───────────────┐
 service (stdout/err) ─┼──► systemd-journald ──► /var/log/journal/  (nhị phân) ──► journalctl
 logger / syslog() ────┘          │
                                  └─ chuyển tiếp ─► rsyslog ──► /var/log/syslog, auth.log, kern.log (văn bản)

 ứng dụng tự ghi file ─────────────────────────────► /var/log/taskhub/app.log
                                                            │
                                         logrotate (mỗi ngày) ─► app.log.1, app.log.2.gz, ...
```

### 6.2. Cây quyết định: "Ứng dụng chết / không truy cập được"

```text
Người dùng báo: không vào được taskhub
│
├─(1) Process có chạy không?   systemctl status taskhub  /  ps -ef | grep java
│     ├─ KHÔNG → Vì sao nó chết?
│     │          ├─ journalctl -u taskhub -n 100  → đọc stack trace (Caused by cuối)
│     │          ├─ status=9/KILL? → dmesg -T | grep -i "killed process"  (OOM)
│     │          └─ Sửa nguyên nhân → khởi động lại → theo dõi log (-f)
│     └─ CÓ ↓
├─(2) Có lắng nghe đúng port/địa chỉ không?   sudo ss -tlnp | grep 8080
│     ├─ KHÔNG / chỉ 127.0.0.1 → sai cấu hình port/bind, hoặc app treo khi khởi động
│     └─ CÓ ↓
├─(3) Gọi từ CHÍNH server có được không?   curl -v http://localhost:8080/actuator/health
│     ├─ KHÔNG / rất chậm → app treo: log, CPU/RAM (top), kết nối DB
│     └─ ĐƯỢC ↓
└─(4) Từ bên ngoài không được → vấn đề nằm GIỮA người dùng và server:
       reverse proxy (Nginx), firewall, Security Group, DNS  → Module 02, 06
```

### 6.3. Cây quyết định: "Server chậm"

```text
uptime + nproc: load so với số nhân?
│
├─ Load THẤP → server không quá tải → vấn đề ở app (log, DB chậm, gọi API ngoài chậm) hoặc mạng
│
└─ Load CAO → top, xem dòng %Cpu:
      ├─ us/sy cao   → CPU: process nào? (top, nhấn P) — vòng lặp? GC Java? quá nhiều request?
      ├─ wa cao      → ĐĨA: iostat -xz 1, process trạng thái D, df -h (đầy?)
      │                 └─ kiểm tra free -h + vmstat si/so: thiếu RAM gây swap?
      ├─ st cao      → máy ảo bị thiếu CPU thật (cloud) → cân nhắc đổi loại instance
      └─ free -h: available thấp, swap dùng nhiều → RAM: process nào? (top, nhấn M)
                                                    dmesg: OOM đã xảy ra chưa?
```

### 6.4. USE method — bảng tra lệnh

| Tài nguyên | Utilization (bận bao nhiêu) | Saturation (có xếp hàng không) | Errors |
|---|---|---|---|
| CPU | `top`: `100 - id` | load avg > `nproc`; `vmstat` cột `r` | (hiếm) |
| RAM | `free -h`: `used` / `available` | swap dùng nhiều; `vmstat` `si`/`so` | OOM trong `dmesg` |
| Đĩa (I/O) | `iostat -x`: `%util` | `iostat` `aqu-sz`, `await`; `vmstat` `b` | `dmesg`: I/O error |
| Đĩa (dung lượng) | `df -h`, `df -i` | — (đầy là hết) | `No space left on device` trong log |
| Mạng | Module 02 | Module 02 | Module 02 |

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `journalctl -u/-p/--since/-f/-n/-b/-k` | Lọc log của journald | 🟥 |
| `journalctl --disk-usage` | Journal chiếm bao nhiêu chỗ | 🟨 |
| `logger` | Tự ghi một dòng vào log hệ thống (để thử nghiệm) | 🟨 |
| `zless`, `zgrep` | Đọc / tìm trong log đã nén `.gz` | 🟥 |
| `logrotate -d` / `-f` | Thử cấu hình / ép xoay log | 🟥 |
| `uptime`, `nproc` | Load average, số nhân | 🟥 |
| `top` (🟨 `htop`) | Tổng quan CPU, RAM, process | 🟥 |
| `free -h` | RAM và swap | 🟥 |
| `vmstat 1` | CPU, RAM, swap, I/O theo thời gian | 🟨 |
| `iostat -xz 1` | Hiệu năng từng ổ đĩa (gói `sysstat`) | 🟨 |
| `df -h`, `df -i` | Dung lượng và inode từng ổ | 🟥 |
| `du -sh`, `du -h --max-depth=1` | Dung lượng thư mục | 🟥 |
| `lsof` | File / port mà process đang mở | 🟨 |
| `dmesg -T` | Log kernel (OOM, lỗi phần cứng) | 🟥 |
| `ss -tulpn` | Port đang lắng nghe và process | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu lấy từ Ubuntu 24.04. Số liệu trên máy bạn sẽ khác — hãy tập trung vào **cấu trúc**.

### `journalctl` — các cách lọc

```bash
journalctl -u ssh -n 20 --no-pager
```

```text
Oct 31 08:01:12 LEGION systemd[1]: Starting OpenBSD Secure Shell server...
Oct 31 08:01:12 LEGION sshd[640]: Server listening on 0.0.0.0 port 22.
Oct 31 08:01:12 LEGION systemd[1]: Started OpenBSD Secure Shell server.
```

| Tham số | Ý nghĩa |
|---|---|
| `-u <unit>` | Chỉ log của một systemd unit. Lặp lại được: `-u nginx -u taskhub` |
| `-t <tag>` | Theo tên định danh (syslog identifier), ví dụ log ghi bằng `logger -t taskhub` |
| `-p <mức>` | Mức đó **và nghiêm trọng hơn**. `-p warning..err` = chỉ trong khoảng |
| `-k` | Chỉ log kernel (tương đương `dmesg`) |
| `-b` | Từ lần khởi động hiện tại. `-b -1` = lần khởi động trước (cần journal lưu bền) |
| `--since` / `--until` | `"2026-10-31 08:00"`, `"1 hour ago"`, `today`, `yesterday` |
| `-n <N>` | N dòng cuối |
| `-f` | Theo dõi trực tiếp, như `tail -f`. `Ctrl+C` để thoát |
| `-r` | Mới nhất lên đầu |
| `-o short-iso` | Thời gian dạng ISO có múi giờ — tốt khi so sánh với log ứng dụng |
| `-o json-pretty` | Xem đầy đủ mọi trường metadata (PID, UID, unit…) |
| `--no-pager` | In thẳng ra, không mở trình xem — cần khi dùng trong script hoặc pipe |
| `-x` | Thêm giải thích cho một số thông báo |

```bash
journalctl --disk-usage
```

```text
Archived and active journals take up 48.0M in the file system.
```

⚠️ Dọn journal cũ (xóa vĩnh viễn log đã lưu trữ, không đụng file đang ghi):

```bash
sudo journalctl --vacuum-time=7d      # xóa log lưu trữ cũ hơn 7 ngày
sudo journalctl --vacuum-size=200M    # xóa log lưu trữ cũ nhất cho đến khi còn dưới 200MB
```

### `logger` — tự ghi log để thử nghiệm

```bash
logger -t taskhub -p user.err "Database connection lost"
journalctl -t taskhub -n 1 -o short-iso
```

```text
2026-10-31T09:30:44+0700 LEGION taskhub[3120]: Database connection lost
```

`-t` đặt tên nguồn, `-p <facility>.<mức>` đặt mức độ. Rất tiện để kiểm tra bộ lọc, alert, hoặc để script Bash ghi log vào hệ thống.

### `zless` / `zgrep` — đọc log đã nén

```bash
zgrep -h "Failed password" /var/log/auth.log*
```

`zgrep` tự xử lý cả file thường lẫn `.gz`. `-h` bỏ tên file ở đầu mỗi dòng kết quả.

### `logrotate` — thử và ép xoay

```bash
sudo logrotate -d /etc/logrotate.d/taskhub     # chạy thử: in ra sẽ làm gì, KHÔNG thay đổi gì
sudo logrotate -f /etc/logrotate.d/taskhub     # ⚠️ ép xoay ngay, bất kể đã đến hạn chưa
```

| Tham số | Ý nghĩa |
|---|---|
| `-d` | Debug — chỉ in, không đổi file, không cập nhật state |
| `-f` | Force — ép xoay |
| `-v` | Verbose — in chi tiết khi chạy thật |
| `-s <file>` | Dùng file **state** khác (nơi logrotate nhớ lần xoay cuối). Dùng khi chạy bằng user thường |

### `uptime` và `nproc`

```bash
uptime; nproc
```

```text
 09:15:02 up  2:13,  1 user,  load average: 0.52, 0.48, 0.40
16
```

`up 2:13` = đã chạy 2 giờ 13 phút. Ba số load: 1, 5, 15 phút. So với `nproc` = 16 nhân logic → máy rất rảnh.

### `top` — đọc phần đầu

Bài 04 dùng `top` để xem process. Ở đây đọc **5 dòng đầu**:

```text
top - 09:15:02 up  2:13,  1 user,  load average: 0.52, 0.48, 0.40
Tasks: 41 total,   1 running,  40 sleeping,   0 stopped,   0 zombie
%Cpu(s):  2.1 us,  0.8 sy,  0.0 ni, 96.9 id,  0.1 wa,  0.0 hi,  0.1 si,  0.0 st
MiB Mem :   7861.2 total,   4980.4 free,   1201.6 used,   1679.2 buff/cache
MiB Swap:   2048.0 total,   2048.0 free,      0.0 used.   6360.1 avail Mem
```

Phím tắt hữu ích: `P` sắp theo CPU, `M` sắp theo RAM, `1` xem từng nhân CPU, `c` hiện đầy đủ dòng lệnh, `q` thoát.

🟨 `htop` (cài bằng `sudo apt install htop`) cho giao diện màu, dễ nhìn hơn — nhưng trên server lạ có thể không có, nên **phải thạo `top` trước**.

### `free -h`

```bash
free -h
```

Đã giải thích ở [4.6](#46--ram-free--h-và-vì-sao-ram-free-thấp-không-đáng-sợ). Nhớ: nhìn cột **`available`**, không nhìn `free`. `-h` = dễ đọc; `-s 2` = in lại mỗi 2 giây.

### `vmstat 1 5`

```bash
vmstat 1 5      # in mỗi 1 giây, 5 lần
```

Đã giải thích các cột ở [4.11](#411--vmstat-và-iostat--nhìn-theo-thời-gian). Bỏ qua dòng đầu tiên.

### `iostat -xz 1` 🟨

```bash
sudo apt install sysstat      # nếu chưa có
iostat -xz 1 3
```

```text
Device   r/s    w/s   rkB/s   wkB/s  r_await w_await aqu-sz  %util
sdc     0.20  12.40    3.10  410.50     0.45    1.20   0.02   1.10
```

| Tham số | Ý nghĩa |
|---|---|
| `-x` | Thống kê mở rộng (`await`, `%util`…) |
| `-z` | Ẩn thiết bị không có hoạt động |
| `1 3` | Mỗi 1 giây, 3 lần (lần đầu là trung bình từ lúc khởi động) |

### `df` và `du`

```bash
df -h /
df -i /
du -sh ~/devops-lab
du -h --max-depth=1 ~ 2>/dev/null | sort -h | tail -5
```

```text
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdc       1007G   12G  944G   2% /
Filesystem       Inodes  IUsed    IFree IUse% Mounted on
/dev/sdc       67108864 251032 66857832    1% /
12M	/home/phuong/devops-lab
```

| Tham số `du` | Ý nghĩa |
|---|---|
| `-s` | Chỉ tổng (summary), không liệt kê từng thư mục con |
| `-h` | Dễ đọc |
| `--max-depth=1` (hoặc `-d 1`) | Chỉ liệt kê thư mục con cấp 1 |
| `-x` | Không đi sang filesystem khác |

`sort -h` sắp xếp đúng các giá trị dạng `12M`, `3.1G` (đã học ở bài 02). `2>/dev/null` giấu các lỗi `Permission denied` để kết quả gọn.

### `lsof` 🟨

```bash
sudo lsof -i :8080        # ai đang dùng port 8080
sudo lsof -p 2345         # process 2345 đang mở những file nào
sudo lsof +L1             # file đã bị xóa nhưng vẫn đang được mở
sudo lsof /var/log/taskhub/app.log   # ai đang mở file này
```

`lsof` = "list open files". Vì "mọi thứ đều là file", nó liệt kê cả file, socket mạng, pipe. Nếu chưa có: `sudo apt install lsof`.

### `dmesg -T`

```bash
sudo dmesg -T | tail -20
sudo dmesg -T --level=err,warn
```

`-T` đổi mốc thời gian sang giờ dễ đọc. Trên Ubuntu, `dmesg` thường **cần `sudo`** vì log kernel bị giới hạn với user thường.

### `ss -tulpn`

Đã giải thích ở [4.10](#410--ss--tulpn--port-nào-đang-mở-của-process-nào). Mẹo lọc nhanh: `sudo ss -tlnp | grep ':8080'`, hoặc dùng bộ lọc riêng của `ss`: `ss -tln 'sport = :8080'`.

---

## 9. Bài thực hành từng bước

**Lab: Thám tử log và tài nguyên** · `[WSL]` + `[Sandbox]` · ~90 phút

Ghi câu trả lời vào `~/devops-lab/01-linux/lab07-answers.md`, cuối buổi commit vào `~/devops-journey/week03/`.

### Bước 1 — Hệ thống log của bạn

```bash
ps -p 1 -o comm=                 # systemd hay init?
ls -l /var/log | head -20
id                                # bạn có thuộc group adm không?
journalctl --disk-usage
```

❓ Hệ thống của bạn có systemd không? Có `/var/log/syslog` không? Journal chiếm bao nhiêu? Nếu không có systemd, ghi chú lại và **bỏ qua Bước 2** (làm lại trên EC2 ở tuần 12).

### Bước 2 — Lọc log với `journalctl`

```bash
logger -t taskhub -p user.info "Application started"
logger -t taskhub -p user.warning "Disk usage above 80%"
logger -t taskhub -p user.err "Database connection lost"

journalctl -t taskhub --no-pager
journalctl -t taskhub -p warning --no-pager
journalctl -t taskhub -p err --since "5 min ago" -o short-iso --no-pager
journalctl -t taskhub -n 1 -o json-pretty --no-pager
```

❓ Lệnh thứ hai hiện mấy dòng? Vì sao? Trong kết quả `json-pretty`, tìm trường cho biết PID và mức độ (`PRIORITY`). `PRIORITY` của dòng `err` là số mấy?

Mở thêm một terminal, chạy `journalctl -t taskhub -f`, rồi ở terminal kia gõ lại một lệnh `logger`. Quan sát.

### Bước 3 — Logrotate không cần quyền root

Bạn sẽ chạy `logrotate` bằng chính user của mình trên một thư mục log giả, nên không đụng tới cấu hình hệ thống.

```bash
mkdir -p ~/devops-lab/01-linux/logrotate-test/logs
cd ~/devops-lab/01-linux/logrotate-test
for i in $(seq 1 2000); do echo "$(date -Is) INFO request $i handled" >> logs/app.log; done
ls -lh logs/
```

Tạo file `taskhub-logrotate.conf` (dùng `nano` hoặc VS Code), **thay `/home/phuong` bằng home của bạn** (`echo $HOME`):

```text
/home/phuong/devops-lab/01-linux/logrotate-test/logs/*.log {
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

Chạy thử, rồi ép xoay:

```bash
logrotate -d -s state.txt taskhub-logrotate.conf      # chỉ xem sẽ làm gì
logrotate -v -f -s state.txt taskhub-logrotate.conf   # xoay thật
ls -lh logs/
```

Lặp lại 3 lần: thêm vài dòng vào `logs/app.log` rồi chạy lại lệnh `-f`. Mỗi lần `ls -lh logs/`.

❓ Sau mỗi lần xoay, các file `app.log.1`, `app.log.2.gz`… xuất hiện thế nào? Vì sao `app.log.1` không bị nén? Sau 4–5 lần, có file nào biến mất không? Vì sao?

### Bước 4 — CPU: tạo tải và quan sát

```bash
nproc
uptime
yes > /dev/null &          # một process ăn 100% một nhân
yes > /dev/null &
jobs -l                    # ghi lại 2 PID
```

Chờ ~1 phút, sau đó:

```bash
uptime
top                         # nhấn P, quan sát dòng %Cpu và process "yes"; nhấn 1 để xem từng nhân; q để thoát
vmstat 1 5
```

Dọn dẹp:

```bash
kill %1 %2
jobs -l                     # không còn job nào
```

❓ Load 1 phút tăng tới khoảng bao nhiêu? Vì sao dòng `%Cpu(s)` tổng có thể chỉ hiện ~12% `us` dù có 2 process 100%? (Gợi ý: `nproc`.) Cột `r` của `vmstat` cho thấy gì?

### Bước 5 — RAM

```bash
free -h
cat /proc/meminfo | grep -E "MemTotal|MemAvailable|^Cached|SwapTotal"
```

❓ Cột `free` và `available` chênh nhau bao nhiêu? Giải thích bằng lời của bạn vì sao.

### Bước 6 — Đĩa: `df` vs `du` và file "ma"

⚠️ Bước này tạo một file 1GB trong thư mục lab. Kiểm tra `df -h ~` còn trống trên 5GB trước khi làm.

```bash
cd ~/devops-lab/01-linux
df -h ~
fallocate -l 1G bigfile.bin
df -h ~
du -sh ~/devops-lab
```

Giờ mô phỏng một process giữ file:

```bash
tail -f bigfile.bin > /dev/null &
TAILPID=$!
rm bigfile.bin
ls -l bigfile.bin           # đã biến mất?
du -sh ~/devops-lab         # du nói gì?
df -h ~                     # df nói gì?
lsof +L1 2>/dev/null | grep bigfile   # nếu chưa có lsof: sudo apt install lsof
ls -l /proc/$TAILPID/fd
```

Giải phóng:

```bash
kill $TAILPID
df -h ~
```

❓ Ghi lại `Used` của `df` ở 4 thời điểm: trước khi tạo file, sau khi tạo, sau khi `rm`, sau khi `kill`. Giải thích từng thay đổi.

### Bước 7 — Port nào đang mở

```bash
python3 -m http.server 8080 > /dev/null 2>&1 &
sudo ss -tulpn
sudo ss -tlnp | grep ':8080'
sudo lsof -i :8080
curl -sI http://localhost:8080 | head -1
kill %1
```

❓ Process nào đang lắng nghe 8080, PID bao nhiêu? Nó lắng nghe trên địa chỉ nào (chỉ máy này hay mọi địa chỉ)?

### Bước 8 — Đọc stack trace `[Sandbox]` (không cần chạy gì)

Đọc stack trace dưới đây và trả lời: (a) nguyên nhân gốc là gì, (b) dòng nào là code của chính ứng dụng, (c) bạn sẽ kiểm tra gì đầu tiên.

```text
2026-10-31T10:02:41.118+07:00 ERROR 4120 --- [taskhub] [nio-8080-exec-3] o.a.c.c.C.[.[.[/].[dispatcherServlet] : Servlet.service() for servlet [dispatcherServlet] threw exception

java.lang.IllegalStateException: Failed to export task report
	at com.example.taskhub.report.ReportService.export(ReportService.java:58)
	at com.example.taskhub.report.ReportController.download(ReportController.java:31)
	at java.base/jdk.internal.reflect.DirectMethodHandleAccessor.invoke(DirectMethodHandleAccessor.java:103)
	...
Caused by: java.nio.file.AccessDeniedException: /var/lib/taskhub/reports/2026-10-31.csv
	at java.base/sun.nio.fs.UnixException.translateToIOException(UnixException.java:90)
	at java.base/sun.nio.fs.UnixFileSystemProvider.newByteChannel(UnixFileSystemProvider.java:261)
	at java.base/java.nio.file.Files.newBufferedWriter(Files.java:3002)
	at com.example.taskhub.report.CsvWriter.write(CsvWriter.java:22)
	at com.example.taskhub.report.ReportService.export(ReportService.java:54)
	... 48 common frames omitted
```

### Bước 9 — Commit

```bash
cd ~/devops-journey
mkdir -p week03
cp ~/devops-lab/01-linux/lab07-answers.md week03/
git add week03/lab07-answers.md
git commit -m "docs(linux): lab 07 - logs and resource monitoring"
git push
```

Dọn dẹp thư mục thử nghiệm logrotate nếu muốn: `rm -r ~/devops-lab/01-linux/logrotate-test` (⚠️ kiểm tra đường dẫn bằng `ls` trước).

---

## 10. Kết quả mong đợi

- **Bước 2:** lệnh `-p warning` hiện 2 dòng (`warning` và `err`) vì `-p` lấy mức đó **và nghiêm trọng hơn**. `PRIORITY` của dòng err là `3`.
- **Bước 3:** lần xoay đầu tạo `app.log.1` (chưa nén do `delaycompress`) và `app.log` rỗng (do `copytruncate`). Lần sau `app.log.1` → `app.log.2.gz` (được nén). Vì `rotate 3`, khi có bản thứ 4 thì bản cũ nhất bị xóa. Lưu ý `notifempty`: nếu `app.log` rỗng thì không xoay.
- **Bước 4:** load 1 phút tiến dần về ~2. `%Cpu(s)` là trung bình **của mọi nhân**: 2 nhân bận trên 16 nhân ≈ 12,5%. Nhấn `1` trong `top` sẽ thấy 2 nhân gần 100%. Cột `r` của `vmstat` ≈ 2.
- **Bước 5:** `available` lớn hơn nhiều so với `free` vì phần lớn RAM "đã dùng" thực chất là cache, có thể giải phóng ngay.
- **Bước 6:** `Used` tăng ~1GB sau `fallocate`; **không giảm** sau `rm` (vì `tail` còn giữ); `du` đã không thấy file; `lsof +L1` và `ls -l /proc/<PID>/fd` hiện `bigfile.bin (deleted)`; `Used` chỉ giảm sau `kill`.
- **Bước 7:** `python3` lắng nghe `0.0.0.0:8080` (mọi địa chỉ IPv4). `curl` trả `HTTP/1.0 200 OK`.
- **Bước 8:** (a) Nguyên nhân gốc: `AccessDeniedException` — process ứng dụng **không có quyền ghi** vào `/var/lib/taskhub/reports/`. (b) Dòng code của mình đầu tiên trong `Caused by`: `CsvWriter.java:22`, được gọi từ `ReportService.java:54`. (c) Kiểm tra: app chạy bằng user nào (`ps -o user= -p 4120`), quyền và chủ sở hữu thư mục (`ls -ld /var/lib/taskhub/reports`) — kiến thức của [bài 03](03-permissions-users-groups.md).

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `journalctl` báo `No journal files were found` hoặc chỉ thấy log của bạn | Không thuộc group `adm`/`systemd-journal`, hoặc systemd không chạy (WSL) | Dùng `sudo journalctl`; kiểm tra `ps -p 1 -o comm=` |
| `Hint: You are currently not seeing messages from other users and the system.` | Như trên | Thêm `sudo` |
| `dmesg: read kernel buffer failed: Operation not permitted` | Ubuntu giới hạn `dmesg` với user thường | `sudo dmesg` |
| Không tìm thấy `/var/log/syslog` | rsyslog không được cài (WSL, container, một số image tối giản) | Dùng `journalctl`; hoặc tự cài `rsyslog` nếu thật sự cần |
| `logrotate`: `error: skipping "...log" because parent directory has insecure permissions` | Thư mục log ghi được bởi group/others không phải root | Thêm dòng `su <user> <group>` vào cấu hình, hoặc sửa quyền thư mục |
| `logrotate`: file cấu hình bị bỏ qua vì quyền | File cấu hình ghi được bởi group/others | `chmod 644` file cấu hình |
| Xoay log xong app vẫn ghi vào `app.log.1` | Dùng `create` nhưng app không mở lại file | Dùng `copytruncate`, hoặc thêm `postrotate` báo app mở lại file |
| Xóa log nhưng ổ vẫn đầy | Process còn giữ file đã xóa | `lsof +L1` → khởi động lại process. Lần sau dùng `truncate -s 0` |
| `No space left on device` dù `df -h` còn trống | Hết inode | `df -i`, tìm thư mục chứa nhiều file nhỏ |
| `top` hiển thị CPU > 100% cho một process | `top` tính theo từng nhân: 200% = dùng trọn 2 nhân | Bình thường với ứng dụng đa luồng như Java |
| Hoảng vì `free` gần 0 | Hiểu nhầm cache là RAM bị chiếm | Nhìn cột `available` |

---

## 12. Đọc log và xử lý lỗi

Bài này **chính là** bài về đọc log, nên mục này tổng hợp thành một quy trình bạn sẽ dùng suốt khóa học.

### 12.1. Năm câu hỏi khi mở một file log

1. **Khi nào?** Lỗi bắt đầu lúc mấy giờ? Trùng với sự kiện gì (deploy, cron, `apt upgrade` — xem `/var/log/apt/history.log`)?
2. **Ở đâu?** Thành phần nào báo lỗi (app, DB, Nginx, kernel)?
3. **Lỗi gì?** Đọc trọn thông báo, đặc biệt `Caused by` cuối cùng.
4. **Lặp lại không?** Một lần hay liên tục? Đếm bằng `grep -c`.
5. **Trước lỗi có gì?** Lỗi đầu tiên thường quan trọng hơn hàng trăm lỗi kéo theo sau. Xem các dòng **trước** lỗi đầu tiên.

### 12.2. Các mẫu lệnh hay dùng

```bash
# Lỗi đầu tiên (không phải cuối cùng!) trong log
grep -n -m 1 -E "ERROR|Exception" /var/log/taskhub/app.log

# Xem 20 dòng trước và 5 dòng sau lỗi đầu tiên
grep -n -m 1 -B 20 -A 5 "ERROR" /var/log/taskhub/app.log

# Loại lỗi nào nhiều nhất
grep -oE "[A-Za-z.]+(Exception|Error)" /var/log/taskhub/app.log | sort | uniq -c | sort -rn | head

# Theo dõi trực tiếp, chỉ hiện lỗi/cảnh báo
tail -f /var/log/taskhub/app.log | grep --line-buffered -E "WARN|ERROR"

# Log của service trong khoảng thời gian xảy ra sự cố
journalctl -u taskhub --since "2026-10-31 02:55" --until "2026-10-31 03:10" -o short-iso --no-pager

# Ai đang dò mật khẩu SSH (top 10 IP)
sudo grep "Failed password" /var/log/auth.log | grep -oE "from [0-9.]+" | sort | uniq -c | sort -rn | head
```

### 12.3. Bảng tra thông báo lỗi thường gặp

| Thông báo | Ý nghĩa | Hướng điều tra |
|---|---|---|
| `Permission denied` / `AccessDeniedException` | Không có quyền | User nào chạy process? Quyền file/thư mục? (bài 03) |
| `No such file or directory` / `NoSuchFileException` | Sai đường dẫn | Đường dẫn tuyệt đối? Thư mục làm việc của service? |
| `Connection refused` | Tới được máy nhưng không ai nghe ở port đó | Service đích có chạy? Đúng port? `ss -tlnp` |
| `Connection timed out` | Gói tin không tới hoặc không được trả lời | Firewall, Security Group, sai IP (Module 02) |
| `Address already in use` / `Port ... already in use` | Port đã có process khác giữ | `ss -tlnp`, `lsof -i :<port>` |
| `No space left on device` | Hết dung lượng **hoặc** hết inode | `df -h`, `df -i` |
| `code=killed, status=9/KILL` | Bị giết bằng SIGKILL | OOM? `dmesg -T` |
| `java.lang.OutOfMemoryError: Java heap space` | JVM hết heap (khác OOM killer của kernel!) | Tăng `-Xmx` hoặc tìm rò rỉ bộ nhớ |
| `password authentication failed for user` | Sai mật khẩu DB | Biến môi trường, file cấu hình |

> Phân biệt quan trọng: `OutOfMemoryError` là **JVM** báo heap của nó đầy (app vẫn kịp ghi log). OOM killer là **kernel** giết cả process vì máy hết RAM (app không kịp ghi gì). Hai nguyên nhân, hai cách xử lý khác nhau.

### 12.4. Ghi nhật ký debug

Tiếp tục dùng mẫu `troubleshooting-journal.md` từ [bài 01](01-linux-architecture-filesystem.md#12-đọc-thông-báo-lỗi-và-xử-lý). Từ bài này, thêm 2 dòng: **"Số liệu quan sát được"** (load, RAM, disk lúc đó) và **"Lệnh đã dùng để tìm ra"**.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Vì sao Ubuntu có cả `systemd-journald` và `rsyslog`? Mỗi cái lưu log ở đâu, đọc bằng gì?
2. `journalctl -p warning` hiện những mức nào? Viết lệnh xem lỗi của service `nginx` từ 8 giờ sáng hôm nay.
3. Bạn cần biết ai đã chạy `sudo` trên server hôm qua. Xem file nào?
4. Trong stack trace Java, vì sao nên đọc `Caused by` **cuối cùng** trước? Dòng nào là "code của mình"?
5. `Connection refused` và `Connection timed out` khác nhau thế nào về nguyên nhân?
6. Giải thích sự khác nhau giữa `copytruncate` và `create` trong logrotate. Khi nào dùng cái nào?
7. Máy 4 nhân có load average `6.5, 6.2, 5.9`. Bạn kết luận gì? Cần xem thêm gì để biết nguyên nhân?
8. `top` hiện `wa` = 70%. Điều đó nói gì? Bước tiếp theo?
9. `free -h` báo `free` 200Mi, `available` 5Gi. Server có thiếu RAM không? Vì sao?
10. App Java đột ngột chết, log ứng dụng không có dòng lỗi nào. Bạn nghi ngờ gì và kiểm tra bằng lệnh nào?
11. `df` báo ổ 100% nhưng `du -sh /` chỉ ra 40%. Giải thích nguyên nhân có thể và cách xác nhận.
12. `No space left on device` nhưng `df -h` còn 30%. Nguyên nhân?
13. `ss -tlnp` cho thấy app listen ở `127.0.0.1:8080`. Người dùng bên ngoài có truy cập được trực tiếp không? Vì sao?
14. Nêu USE method và áp dụng cho RAM.
15. Trình bày quy trình của bạn khi nhận ticket "server chậm" — không quá 6 bước.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/07-solutions.md](solutions/07-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Đọc stack trace.** Phân tích log sau: nguyên nhân gốc, file/dòng liên quan trong code của ứng dụng (nếu có), 2 giả thuyết và lệnh để kiểm chứng từng giả thuyết.

```text
2026-11-02T08:00:03.412+07:00  WARN 2210 --- [taskhub] [main] o.s.b.w.s.c.AnnotationConfigServletWebServerApplicationContext : Exception encountered during context initialization - cancelling refresh attempt: org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'entityManagerFactory' ...
...
Caused by: org.hibernate.exception.JDBCConnectionException: Unable to open JDBC Connection for DDL execution
	at org.hibernate.exception.internal.SQLStateConversionDelegate.convert(SQLStateConversionDelegate.java:100)
	...
Caused by: org.postgresql.util.PSQLException: FATAL: password authentication failed for user "taskhub"
	at org.postgresql.core.v3.ConnectionFactoryImpl.doAuthentication(ConnectionFactoryImpl.java:693)
	at org.postgresql.core.v3.ConnectionFactoryImpl.tryConnect(ConnectionFactoryImpl.java:203)
	...
	... 38 common frames omitted
```

**Bài 2 — Thống kê lỗi theo nguồn.** Viết một pipeline dùng `journalctl` (trên WSL có systemd, hoặc trên EC2 sau này) liệt kê **các nguồn (identifier) có nhiều cảnh báo/lỗi nhất từ đầu ngày hôm nay**, dạng `số lượng  tên`, bỏ phần `[PID]`. Gợi ý: `-o short-iso`, `awk`, `sed`, `sort`, `uniq -c`.

**Bài 3 — Logrotate cho taskhub dùng `create`.** Viết file `/etc/logrotate.d/taskhub` (chỉ viết ra file trong repo `devops-journey`, **không** cài lên hệ thống) cho thư mục `/var/log/taskhub/*.log`, yêu cầu: xoay hằng tuần **hoặc** khi file vượt 100MB, giữ 8 bản, nén, file mới tạo với quyền `0640` thuộc `taskhub:adm`, sau khi xoay thì báo cho service `taskhub` mở lại log bằng `systemctl kill -s HUP taskhub.service` (giả định app hỗ trợ). Giải thích từng dòng. Đọc `man logrotate` để tìm directive cho điều kiện "vượt 100MB".

**Bài 4 — Ổ đầy "bí ẩn".** Viết một runbook ngắn (markdown, tối đa 1 trang) mang tên "Ổ đĩa đầy" cho dự án `taskhub`: các bước kiểm tra theo thứ tự, lệnh cụ thể, cách xử lý cho từng nguyên nhân (log lớn, file bị xóa vẫn mở, hết inode, Docker chiếm chỗ — chỉ cần ghi "sẽ bổ sung ở Module 04"). Lưu vào `taskhub/docs/runbooks/disk-full.md`.

**Bài 5 — Quan sát I/O wait.** ⚠️ Tạo khoảng 2GB dữ liệu — kiểm tra dung lượng trước. Mở 2 terminal. Terminal 1 chạy `vmstat 1`. Terminal 2 chạy:

```bash
dd if=/dev/zero of=$HOME/devops-lab/01-linux/io.test bs=1M count=2000 oflag=direct status=progress
rm $HOME/devops-lab/01-linux/io.test
```

Ghi lại các cột `b`, `bo`, `wa` trong lúc chạy và sau khi xong. Giải thích `oflag=direct` làm gì và vì sao nó làm hiện tượng dễ quan sát hơn (đọc `man dd`).

**Bài 6 — Trả lời phỏng vấn.** Viết câu trả lời (bằng lời nói, ~2 phút, ghi ra giấy) cho câu: *"Ứng dụng production báo lỗi 502 và người dùng không vào được. Bạn SSH vào server. Bạn làm gì?"*. Câu trả lời phải theo cây quyết định ở mục 6.2, nêu lệnh cụ thể và **lý do** cho từng bước.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Biết ngay nên mở file/lệnh nào cho các câu hỏi: lỗi service, đăng nhập SSH, OOM, ai cài gói gì.
- [ ] Viết được lệnh `journalctl` kết hợp đủ 3 trục (nguồn, mức độ, thời gian) mà không tra cứu.
- [ ] Đọc một stack trace Java bất kỳ và chỉ ra nguyên nhân gốc trong dưới 2 phút.
- [ ] Giải thích được `copytruncate` vs `create`, và vì sao app vẫn ghi vào file đã đổi tên.
- [ ] Nhìn `uptime` + `top` + `free -h` và nói được tài nguyên nào đang nghẽn, kèm lý do.
- [ ] Giải thích được hiện tượng `df` ≠ `du` và tự tái hiện được nó (Bước 6).
- [ ] Trình bày được 2 cây quyết định ở mục 6 mà không nhìn tài liệu.
- [ ] Làm xong [Break-fix Linux #1](labs/break-fix-01/README.md) mà không mở lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [journalctl(1) — Ubuntu 24.04 manpage](https://manpages.ubuntu.com/manpages/noble/man1/journalctl.1.html) | Mọi tham số lọc, quyền đọc journal (group `adm`, `systemd-journal`) | 2026-10-31 |
| [logrotate(8) — Ubuntu 24.04 manpage](https://manpages.ubuntu.com/manpages/noble/man8/logrotate.8.html) | `copytruncate`, `create`, `su`, `-d`, `-f`, `-s` | 2026-10-31 |
| [The USE Method — Brendan Gregg](https://www.brendangregg.com/usemethod.html) | Phương pháp Utilization / Saturation / Errors | 2026-10-31 |
| [Linux Journey — Journeyman: Process Utilization, Logging](https://labex.io/linuxjourney) | Ôn tập ngắn | 2026-10-31 |
| [MIT Missing Semester 2026 — Debugging and Profiling](https://missing.csail.mit.edu/) | Tư duy debug, công cụ đo hiệu năng | 2026-10-31 |
| [Ubuntu Server docs](https://ubuntu.com/server/docs) | Tra cứu chính thức (phần Observability, Debugging) | 2026-10-31 |
| `man top`, `man free`, `man vmstat`, `man ss`, `man lsof` (chạy trên máy) | Ý nghĩa chính xác từng cột | — |
