# 08. Cron & lập lịch tác vụ

> ⏱️ ~2 giờ · Mức độ: 🟨 Nên biết (cron cơ bản là 🟥 trong thực tế vận hành) · Kiến thức cần có trước: [04](04-processes-systemd.md), [06](06-bash-scripting.md), [07](07-logs-monitoring-troubleshooting.md)
> Môi trường: `[WSL]` Ubuntu 24.04

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ luồng hoạt động](#6-sơ-đồ-luồng-hoạt-động)
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

- Đọc và viết được biểu thức lịch 5 trường của cron mà không cần công cụ hỗ trợ.
- Quản lý crontab của user (`crontab -e`, `-l`) và biết các vị trí crontab hệ thống (`/etc/crontab`, `/etc/cron.d/`, `/etc/cron.daily/`).
- Giải thích vì sao **"chạy tay được nhưng cron không chạy"** và sửa được lỗi đó.
- Ghi output của cron job ra log và kiểm tra được job có thực sự chạy hay không.
- 🟨 Chống chạy chồng bằng `flock`, và viết một **systemd timer** thay cho cron.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Nhiều việc vận hành cần chạy **định kỳ, không cần người bấm**:

| Tác vụ | Lịch điển hình |
|---|---|
| Backup database lên S3 | Mỗi đêm 2:00 |
| Dọn file tạm, log cũ | Mỗi ngày |
| Healthcheck, gửi cảnh báo | Mỗi 5 phút |
| Gia hạn chứng chỉ TLS | Mỗi ngày kiểm tra một lần |
| Báo cáo tổng hợp | Thứ Hai hằng tuần |

Cron có mặt trên hầu hết server Linux. Ở dự án `taskhub`, bạn sẽ dùng cron cho **backup PostgreSQL** (Module 08). Khái niệm lịch cron còn xuất hiện lại ở: **Kubernetes CronJob**, **GitHub Actions** `on: schedule`, **Amazon EventBridge Scheduler** — cùng cú pháp hoặc gần giống.

Điều quan trọng hơn cú pháp: một cron job **thất bại âm thầm** là thảm họa chậm. Backup hỏng 3 tuần mà không ai biết, đến lúc cần restore mới phát hiện. Bài này dạy bạn làm cho job **để lại dấu vết**.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Cron là gì?

**cron** là một **daemon** (tiến trình chạy nền liên tục — xem [bài 04](04-processes-systemd.md)). Mỗi phút, nó thức dậy, đọc các bảng lịch (**crontab** = *cron table*), và chạy những lệnh đến giờ.

Hệ quả quan trọng:

- Daemon `cron` **phải đang chạy** thì job mới chạy. Trên WSL, khi WSL tắt thì cron cũng tắt.
- Độ chính xác là **phút**. Cron không chạy được job mỗi 10 giây.
- Máy tắt đúng giờ hẹn → lần đó **bị bỏ qua**, cron không chạy bù.

### 3.2. Nhắc lại cần dùng

| Kiến thức | Học ở |
|---|---|
| systemd service, `systemctl`, `journalctl` | [Bài 04](04-processes-systemd.md) |
| Biến môi trường, `PATH`, `~/.bashrc` không được đọc khi chạy tự động | [Bài 06](06-bash-scripting.md#415--biến-shell-và-biến-môi-trường) |
| Đường dẫn tuyệt đối trong script | [Bài 01](01-linux-architecture-filesystem.md#42--đường-dẫn-tuyệt-đối-và-tương-đối) |
| Redirect `>>`, `2>&1` | [Bài 02](02-essential-commands-text.md) |
| `/var/log/syslog`, đọc log hệ thống | [Bài 07](07-logs-monitoring-troubleshooting.md) |

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Cú pháp 5 trường

Mỗi dòng trong crontab của user:

```text
┌───────────── phút        (0–59)
│ ┌─────────── giờ         (0–23)
│ │ ┌───────── ngày tháng  (1–31)
│ │ │ ┌─────── tháng       (1–12 hoặc jan–dec)
│ │ │ │ ┌───── thứ         (0–7, 0 và 7 đều là Chủ nhật; hoặc sun–sat)
│ │ │ │ │
* * * * *  lệnh cần chạy
```

Ký hiệu trong mỗi trường:

| Ký hiệu | Nghĩa | Ví dụ | Đọc là |
|---|---|---|---|
| `*` | Mọi giá trị | `*` ở trường giờ | Mọi giờ |
| `,` | Danh sách | `1,15` ở ngày | Ngày 1 và 15 |
| `-` | Khoảng | `1-5` ở thứ | Thứ Hai đến thứ Sáu |
| `/` | Bước nhảy | `*/5` ở phút | Mỗi 5 phút (0, 5, 10…) |

**Ví dụ — hãy che cột phải và tự đọc trước:**

| Biểu thức | Ý nghĩa |
|---|---|
| `* * * * *` | Mỗi phút |
| `*/5 * * * *` | Mỗi 5 phút |
| `0 * * * *` | Đầu mỗi giờ (phút 0) |
| `30 2 * * *` | 2:30 sáng mỗi ngày |
| `0 2 * * 0` | 2:00 sáng Chủ nhật |
| `0 9 * * 1-5` | 9:00 sáng thứ Hai–Sáu |
| `0 0 1 * *` | 0:00 ngày 1 hằng tháng |
| `15 8,20 * * *` | 8:15 và 20:15 mỗi ngày |
| `0 */6 * * *` | Mỗi 6 giờ: 0:00, 6:00, 12:00, 18:00 |
| `*/10 9-17 * * 1-5` | Mỗi 10 phút trong giờ hành chính |

> ⚠️ **Bẫy thường gặp:** `* 2 * * *` **không** phải "2 giờ sáng một lần" mà là **mỗi phút** từ 2:00 đến 2:59 — chạy 60 lần. Muốn một lần thì trường phút phải cụ thể: `0 2 * * *`.

> ⚠️ **Bẫy ngày tháng + thứ:** nếu cả trường *ngày tháng* và *thứ* đều khác `*`, cron chạy khi **một trong hai** khớp (phép HOẶC). `0 0 13 * 5` = ngày 13 **hoặc** mọi thứ Sáu, không phải "thứ Sáu ngày 13".

**Từ khóa viết tắt** (cron của Ubuntu hỗ trợ):

| Từ khóa | Tương đương |
|---|---|
| `@reboot` | Một lần khi cron khởi động |
| `@hourly` | `0 * * * *` |
| `@daily` | `0 0 * * *` |
| `@weekly` | `0 0 * * 0` |
| `@monthly` | `0 0 1 * *` |

**Múi giờ:** cron dùng múi giờ của hệ thống. Server EC2 mặc định là **UTC** — `0 2 * * *` trên EC2 là 9:00 sáng giờ Việt Nam (UTC+7). Kiểm tra bằng `date` hoặc `timedatectl`.

Không chắc biểu thức đúng? Dán vào [crontab.guru](https://crontab.guru/) để xem diễn giải bằng lời. Nhưng hãy tập tự đọc trước — phỏng vấn sẽ không cho bạn mở trang này.

### 4.2. 🟥 Crontab của user

Mỗi user có một crontab riêng. Không sửa file trực tiếp — luôn dùng lệnh `crontab`:

| Lệnh | Tác dụng |
|---|---|
| `crontab -e` | Mở crontab bằng editor để sửa. Lần đầu sẽ hỏi chọn editor (chọn `nano` nếu chưa quen `vim`) |
| `crontab -l` | In crontab hiện tại |
| `crontab -r` | ⚠️ **Xóa toàn bộ** crontab, **không hỏi lại**. Chữ `r` nằm ngay cạnh `e` trên bàn phím — gõ nhầm là mất hết |
| `sudo crontab -u <user> -l` | Xem crontab của user khác (cần quyền root) |

Khi lưu và thoát editor, `crontab -e` **kiểm tra cú pháp** và báo lỗi nếu có:

```text
crontab: installing new crontab
```

hoặc:

```text
"/tmp/crontab.Xb3kd2/crontab":3: bad minute
errors in crontab file, can't install.
Do you want to retry the same edit? (y/n)
```

> 💡 Thói quen an toàn: sao lưu trước khi sửa: `crontab -l > ~/crontab.bak`. Phục hồi: `crontab ~/crontab.bak`.

Crontab của user được lưu ở `/var/spool/cron/crontabs/<user>` — biết để tìm khi điều tra, không sửa tay.

### 4.3. 🟨 Crontab hệ thống

| Vị trí | Định dạng | Dùng cho |
|---|---|---|
| `/etc/crontab` | 5 trường + **cột user** + lệnh | Lịch hệ thống chính |
| `/etc/cron.d/<tên>` | Giống `/etc/crontab` (có cột user) | Gói phần mềm hoặc bạn thêm job riêng — **dễ quản lý bằng Ansible/Terraform hơn** crontab user |
| `/etc/cron.hourly/`, `cron.daily/`, `cron.weekly/`, `cron.monthly/` | Thư mục chứa **script**, không có dòng lịch | Đặt script vào là được chạy theo chu kỳ |

Ví dụ một file `/etc/cron.d/taskhub-backup`:

```text
# phút giờ ngày tháng thứ  USER     lệnh
30 2 * * *                 taskhub  /opt/taskhub/scripts/backup.sh >> /var/log/taskhub/backup.log 2>&1
```

Script trong `/etc/cron.daily/` được chạy bởi `run-parts`. Trên Debian/Ubuntu, `run-parts` **bỏ qua file có dấu chấm trong tên** — `backup.sh` sẽ không bao giờ chạy, phải đặt tên `backup`. Kiểm tra bằng:

```bash
run-parts --test /etc/cron.daily
```

Lệnh này liệt kê những script **sẽ** được chạy (không chạy thật).

### 4.4. 🟥 Môi trường của cron — nguyên nhân số 1 khiến job "không chạy"

Khi bạn gõ lệnh trong terminal, shell đã nạp `~/.bashrc`, có `PATH` đầy đủ, đang ở thư mục bạn chọn. **Cron không có những thứ đó.** Theo tài liệu `crontab(5)` của Ubuntu:

| Khía cạnh | Terminal của bạn | Cron job |
|---|---|---|
| Shell chạy lệnh | `bash` | **`/bin/sh`** (là `dash` trên Ubuntu) — trừ khi đặt `SHELL=` |
| `PATH` | Đầy đủ, gồm `~/.local/bin`, `~/bin`… | **Tối giản** (thường chỉ `/usr/bin:/bin`) |
| `~/.bashrc`, alias, biến đã `export` | Có | **Không** |
| Thư mục làm việc | Nơi bạn `cd` tới | Thư mục **home** của user |
| Terminal (TTY) | Có | **Không** — lệnh cần nhập liệu (`read`, `sudo` hỏi mật khẩu) sẽ treo hoặc lỗi |
| Output | Hiện trên màn hình | Gửi **email** cho user (nếu máy có cấu hình mail), không thì **mất** |

Ký tự `%` trong dòng lệnh crontab có nghĩa đặc biệt: được đổi thành **xuống dòng**, phần sau `%` đầu tiên bị đưa vào stdin. Vì vậy `date +%F` trong crontab phải viết thành `date +\%F`.

**Cách viết cron job đúng:**

1. Đưa logic vào **một script** (có shebang `#!/usr/bin/env bash`), crontab chỉ gọi script — tránh luôn vấn đề `sh` và `%`.
2. Dùng **đường dẫn tuyệt đối** cho script, file, và cả lệnh nếu không nằm trong `/usr/bin` hay `/bin`.
3. Trong script, đặt `PATH` rõ ràng hoặc `cd` vào thư mục cần thiết.
4. **Luôn ghi output ra log**: `>> /đường/dẫn/log 2>&1`.

Có thể đặt biến ngay đầu crontab, áp dụng cho các dòng phía dưới:

```text
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
MAILTO=""

*/5 * * * * /home/phuong/bin/healthcheck.sh >> /home/phuong/logs/healthcheck.log 2>&1
```

`MAILTO=""` (rỗng) = không gửi mail. Không đặt `MAILTO` = gửi cho chủ crontab — trên máy không có mail server, thư sẽ không đi đâu cả, chỉ để lại một dòng trong syslog.

### 4.5. 🟥 Ghi output của cron job

```text
*/5 * * * * /home/phuong/bin/job.sh >> /home/phuong/logs/job.log 2>&1
```

| Phần | Ý nghĩa |
|---|---|
| `>> file` | **Nối** stdout vào cuối file (`>` sẽ ghi đè, mất lịch sử) |
| `2>&1` | Gửi stderr vào cùng chỗ với stdout — **thứ tự quan trọng**, phải đứng **sau** `>> file` |

Thiếu `2>&1`, thông báo lỗi (thường ở stderr) sẽ bị mất — đúng phần bạn cần nhất khi debug.

Log sẽ lớn dần — dùng **logrotate** để giới hạn ([bài 07](07-logs-monitoring-troubleshooting.md)).

### 4.6. 🟥 Kiểm tra cron có chạy hay không

**Bước 1 — Daemon cron có đang chạy?**

```bash
systemctl status cron         # nếu WSL đã bật systemd (xem bài 04)
service cron status           # cách khác, chạy được cả khi không có systemd
```

Nếu chưa chạy:

```bash
sudo systemctl enable --now cron     # có systemd: chạy ngay + tự chạy khi WSL khởi động
sudo service cron start              # không có systemd: chạy cho phiên hiện tại
```

> Nếu báo không có gói `cron`: kiểm tra bằng `dpkg -l cron`. Bản Ubuntu tối giản có thể chưa cài — `sudo apt install cron` (bạn tự quyết định cài).

> ⚠️ **Đặc thù WSL:** WSL tự tắt sau một lúc không có terminal nào mở. Khi đó cron cũng dừng, job 2:00 sáng sẽ không chạy nếu laptop đang ngủ. Đây là lý do backup thật của dự án sẽ chạy trên EC2 (Module 06+), không chạy trên laptop.

**Bước 2 — Cron có kích hoạt job không?**

Cron ghi một dòng mỗi khi chạy job:

```bash
journalctl -u cron --since "10 min ago"        # có systemd
grep CRON /var/log/syslog | tail                # nếu có rsyslog ghi file syslog
```

```text
Oct 31 11:05:01 LEGION CRON[2841]: (phuong) CMD (/home/phuong/bin/healthcheck.sh >> /home/phuong/logs/healthcheck.log 2>&1)
```

Dòng này chứng minh cron **đã khởi chạy** lệnh — **không** chứng minh lệnh thành công. Thành công hay không phải xem log của chính job (vì vậy bắt buộc có `>> log 2>&1`).

**Bước 3 — Job tự báo cáo:** script nên ghi dòng bắt đầu/kết thúc kèm timestamp và exit code.

### 4.7. 🟨 Chống chạy chồng với `flock`

Job mỗi 5 phút nhưng có lần chạy mất 7 phút → lần sau bắt đầu khi lần trước chưa xong → hai bản cùng ghi một file, cùng backup một database. `flock` giải quyết bằng **khóa file**:

```text
*/5 * * * * /usr/bin/flock -n /tmp/healthcheck.lock /home/phuong/bin/healthcheck.sh >> /home/phuong/logs/healthcheck.log 2>&1
```

| Phần | Ý nghĩa |
|---|---|
| `flock <file-khóa> <lệnh>` | Giữ khóa trên file trong suốt thời gian lệnh chạy; tạo file nếu chưa có |
| `-n` | Nếu đã có ai giữ khóa → **bỏ qua ngay** (exit 1) thay vì chờ |
| `-w 30` | Chờ tối đa 30 giây rồi mới bỏ cuộc |

Khóa tự được nhả khi lệnh kết thúc — kể cả khi lệnh bị lỗi hay bị kill. Không cần tự xóa file khóa.

### 4.8. 🟨 systemd timer — lựa chọn hiện đại thay cho cron

Trên hệ thống dùng systemd, **timer** là một loại unit (xem [bài 04](04-processes-systemd.md)) dùng để kích hoạt một service theo lịch. Cần 2 file:

`/etc/systemd/system/healthcheck.service`:

```ini
[Unit]
Description=Healthcheck hệ thống

[Service]
Type=oneshot
User=phuong
ExecStart=/home/phuong/bin/healthcheck.sh
```

`/etc/systemd/system/healthcheck.timer`:

```ini
[Unit]
Description=Chạy healthcheck mỗi 5 phút

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
```

| Thành phần | Ý nghĩa |
|---|---|
| `Type=oneshot` | Service chạy một lần rồi kết thúc (không phải daemon chạy mãi) |
| `OnCalendar=*:0/5` | Mỗi giờ, từ phút 0, bước 5 phút. Kiểm tra biểu thức bằng `systemd-analyze calendar '*:0/5'` |
| `Persistent=true` | Nếu máy tắt lúc đến giờ, **chạy bù một lần** khi bật lại — điều cron không làm được |
| Tên `healthcheck.timer` | Mặc định kích hoạt service **cùng tên**: `healthcheck.service` |

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now healthcheck.timer
systemctl list-timers healthcheck.timer
journalctl -u healthcheck.service -n 20
```

**So sánh:**

| Tiêu chí | cron | systemd timer |
|---|---|---|
| Độ phổ biến, đơn giản | Rất cao, 1 dòng là xong | Cần 2 file |
| Log | Tự lo (`>> log 2>&1`) | Tự động vào journal, xem bằng `journalctl -u` |
| Chạy bù khi máy tắt | Không | Có (`Persistent=true`) |
| Chống chạy chồng | Cần `flock` | Mặc định — service đang chạy thì không khởi động thêm |
| Giới hạn tài nguyên, phụ thuộc service khác | Không | Có (dùng toàn bộ tính năng của unit file) |
| Có trong container tối giản | Thường không cả hai | |

Ở mức Junior: **thạo cron**, **đọc hiểu và viết được timer đơn giản**.

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Backup chạy tay thì được, đặt cron thì không"

Crontab:

```text
0 2 * * * backup.sh
```

Ba lỗi cùng lúc: (1) không có đường dẫn tuyệt đối — cron chạy ở `~` và `PATH` không có thư mục chứa `backup.sh`; (2) không ghi log nên không biết lỗi gì; (3) bên trong script có dùng `aws s3 cp` — lệnh `aws` cài ở `/usr/local/bin` không có trong `PATH` của cron.

Sửa:

```text
PATH=/usr/local/bin:/usr/bin:/bin
0 2 * * * /opt/taskhub/scripts/backup.sh >> /var/log/taskhub/backup.log 2>&1
```

### Ví dụ 2: Backup hỏng âm thầm 3 tuần

Job chạy đều, cron log có dòng `CMD (...)` mỗi đêm, nhưng file backup chỉ có 20 byte vì `pg_dump` báo lỗi xác thực. Không ai đọc log.

Bài học sẽ áp dụng ở Module 08: job phải **trả exit code khác 0 khi lỗi**, có **cảnh báo** khi thất bại, và định kỳ **thử restore** backup. Cron chỉ là bộ hẹn giờ — nó không biết job của bạn thành công hay không.

---

## 6. Sơ đồ luồng hoạt động

```text
             mỗi phút
 ┌──────────┐  đọc   ┌────────────────────────────────────────┐
 │ cron     │──────► │ crontab user: /var/spool/cron/crontabs │
 │ (daemon) │        │ /etc/crontab · /etc/cron.d/*           │
 └────┬─────┘        └────────────────────────────────────────┘
      │ đến giờ?  → có
      │ ghi 1 dòng "CMD (...)" vào syslog/journal
      ▼
 ┌──────────────────────────────────────────────────────────┐
 │ /bin/sh -c "<lệnh>"   (môi trường TỐI GIẢN)              │
 │   PATH=/usr/bin:/bin · cwd=$HOME · không .bashrc · no TTY│
 └────┬─────────────────────────────────────────────────────┘
      │
      ▼
 ┌──────────────┐    stdout + stderr     ┌──────────────────┐
 │ script.sh    │ ── >> log 2>&1 ──────► │ file log của job │
 └──────────────┘                        └──────────────────┘
       (không redirect → gửi mail → máy không có mail → MẤT)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `crontab -e` / `-l` | Sửa / xem crontab của mình | 🟥 |
| `crontab -r` | ⚠️ Xóa toàn bộ crontab | 🟥 (biết để tránh) |
| `crontab <file>` | Cài crontab từ file (phục hồi bản sao lưu) | 🟨 |
| `systemctl status cron`, `service cron status` | Daemon cron có chạy không | 🟥 |
| `journalctl -u cron`, `grep CRON /var/log/syslog` | Cron đã kích hoạt job chưa | 🟥 |
| `flock -n` | Chống chạy chồng | 🟨 |
| `run-parts --test` | Script nào trong `cron.daily` sẽ chạy | 🟨 |
| `systemctl list-timers` | Liệt kê systemd timer | 🟨 |
| `systemd-analyze calendar` | Kiểm tra biểu thức `OnCalendar` | 🟨 |
| `date`, `timedatectl` | Kiểm tra giờ và múi giờ hệ thống | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

### `crontab -l`

```bash
crontab -l
```

Khi chưa có crontab:

```text
no crontab for phuong
```

Khi đã có:

```text
SHELL=/bin/bash
MAILTO=""
*/5 * * * * /home/phuong/bin/healthcheck.sh >> /home/phuong/logs/healthcheck.log 2>&1
```

### `systemctl status cron`

```bash
systemctl status cron --no-pager
```

```text
● cron.service - Regular background program processing daemon
     Loaded: loaded (/lib/systemd/system/cron.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2026-10-31 08:01:15 +07; 3h ago
       Docs: man:cron(8)
   Main PID: 312 (cron)
```

Hai chữ cần nhìn: `enabled` (tự chạy khi khởi động) và `active (running)` (đang chạy). Cách đọc đầy đủ ở [bài 04](04-processes-systemd.md).

### `journalctl -u cron`

```bash
journalctl -u cron --since today --no-pager | tail -5
```

```text
Oct 31 11:05:01 LEGION CRON[2841]: pam_unix(cron:session): session opened for user phuong(uid=1000) by (uid=0)
Oct 31 11:05:01 LEGION CRON[2842]: (phuong) CMD (/home/phuong/bin/healthcheck.sh >> /home/phuong/logs/healthcheck.log 2>&1)
Oct 31 11:05:01 LEGION CRON[2841]: pam_unix(cron:session): session closed for user phuong
```

| Tham số | Ý nghĩa |
|---|---|
| `-u cron` | Chỉ log của unit `cron.service` |
| `--since today` / `"10 min ago"` | Lọc theo thời gian |
| `--no-pager` | In thẳng ra, không mở trình xem `less` |

### `flock`

```bash
flock -n /tmp/demo.lock sleep 30 &      # bản 1 giữ khóa trong 30 giây
flock -n /tmp/demo.lock echo "chạy được"
echo "exit code: $?"
```

```text
exit code: 1
```

Bản thứ hai không in `chạy được` vì khóa đang bị giữ, `flock -n` thoát ngay với exit code 1.

### `systemd-analyze calendar`

```bash
systemd-analyze calendar '*:0/5'
```

```text
  Original form: *:0/5
Normalized form: *-*-* *:00/5:00
    Next elapse: Fri 2026-10-31 11:10:00 +07
       From now: 3min 12s left
```

Dùng để kiểm tra biểu thức `OnCalendar` trước khi đưa vào timer.

### `date` và múi giờ

```bash
date
timedatectl | grep "Time zone"
```

```text
Fri Oct 31 11:06:48 +07 2026
                Time zone: Asia/Ho_Chi_Minh (+07, +0700)
```

---

## 9. Bài thực hành từng bước

**Lab: Cron job đầu tiên và bẫy môi trường** · `[WSL]` · ~45 phút

Mục tiêu: tự chứng minh môi trường cron khác terminal, gây lỗi "chạy tay được, cron không chạy", rồi sửa. Lab lớn hơn với script healthcheck ở [lab-03](labs/lab-03-healthcheck-cron.md).

### Bước 1 — Đảm bảo cron đang chạy

```bash
service cron status || sudo service cron start
```

(Nếu WSL đã bật systemd, dùng `systemctl status cron`.)

### Bước 2 — Chụp lại môi trường của cron

```bash
mkdir -p ~/devops-lab/01-linux/lab08
crontab -l > ~/devops-lab/01-linux/lab08/crontab.bak 2>/dev/null || true   # sao lưu nếu đã có
crontab -e
```

Thêm dòng:

```text
* * * * * env > /home/phuong/devops-lab/01-linux/lab08/cron-env.txt; pwd >> /home/phuong/devops-lab/01-linux/lab08/cron-env.txt
```

(Thay `phuong` bằng user của bạn — kiểm tra bằng `whoami`.) Lưu, chờ 1–2 phút.

```bash
cat ~/devops-lab/01-linux/lab08/cron-env.txt
env | wc -l
wc -l < ~/devops-lab/01-linux/lab08/cron-env.txt
```

❓ `PATH` và `SHELL` của cron là gì? Cron có bao nhiêu biến so với terminal? Cron chạy ở thư mục nào?

### Bước 3 — Tạo lỗi kinh điển

Tạo script trong `~/bin` (thư mục bạn đã thêm vào `PATH` ở bài 06):

```bash
mkdir -p ~/bin
cat > ~/bin/hello-cron <<'EOF'
#!/usr/bin/env bash
echo "$(date '+%F %T') hello từ cron, PWD=$PWD"
EOF
chmod +x ~/bin/hello-cron
hello-cron              # chạy tay: thành công
```

Sửa crontab (thay dòng `env` ở Bước 2):

```text
* * * * * hello-cron >> lab08-hello.log
```

Chờ 2 phút. Kiểm tra:

```bash
ls ~/lab08-hello.log && cat ~/lab08-hello.log
journalctl -u cron --since "5 min ago" --no-pager | tail -5     # hoặc grep CRON /var/log/syslog
```

❓ File log nằm ở đâu (lưu ý: đường dẫn tương đối)? Nó có nội dung không? Cron có ghi dòng `CMD` không? Vì sao job "chạy" nhưng không có kết quả?

### Bước 4 — Thêm `2>&1` để nhìn thấy lỗi

```text
* * * * * hello-cron >> lab08-hello.log 2>&1
```

Chờ 1 phút, `cat ~/lab08-hello.log`. ❓ Thông báo lỗi là gì? Exit code tương ứng là bao nhiêu (xem [bài 06, mục 8](06-bash-scripting.md#exit-code-đặc-biệt-bạn-sẽ-gặp))?

### Bước 5 — Sửa đúng cách

```text
MAILTO=""
* * * * * /home/phuong/bin/hello-cron >> /home/phuong/devops-lab/01-linux/lab08/hello.log 2>&1
```

Chờ 2–3 phút, kiểm tra `hello.log` có thêm dòng mới mỗi phút. ❓ `PWD` in ra là gì?

### Bước 6 — Thử bẫy `%`

Thêm một dòng:

```text
* * * * * date +%F >> /home/phuong/devops-lab/01-linux/lab08/date.log 2>&1
```

Chờ 1 phút, xem `date.log`. Sửa thành `date +\%F` và so sánh.

### Bước 7 — Dọn dẹp

⚠️ Không dùng `crontab -r` nếu bạn có job khác. Mở `crontab -e` và xóa các dòng của lab, hoặc phục hồi bản sao lưu:

```bash
crontab ~/devops-lab/01-linux/lab08/crontab.bak     # nếu có bản sao lưu từ Bước 2
crontab -l
rm -f ~/lab08-hello.log
```

Ghi kết quả và bài học vào `troubleshooting-journal.md`.

---

## 10. Kết quả mong đợi

- Bước 2: `cron-env.txt` chỉ có khoảng 6–8 biến (gồm `HOME`, `LOGNAME`, `PATH`, `SHELL`, `PWD`…), so với vài chục biến trong terminal. `SHELL=/bin/sh`, `PATH` ngắn (thường là `/usr/bin:/bin`), thư mục làm việc là `/home/<user>`. Không có `~/bin` trong `PATH`.
- Bước 3: file `~/lab08-hello.log` (ở **home**, vì cron chạy ở home) được tạo nhưng **rỗng**. Cron log **có** dòng `CMD (hello-cron >> lab08-hello.log)` → cron đã kích hoạt job, nhưng lệnh thất bại và thông báo lỗi (stderr) không được ghi lại.
- Bước 4: log hiện `/bin/sh: 1: hello-cron: not found` → `PATH` của cron không có `~/bin`, tương ứng exit code `127`. Chú ý: shell báo lỗi là `/bin/sh`, không phải bash.
- Bước 5: mỗi phút có một dòng mới, `PWD=/home/<user>`.
- Bước 6: với `date +%F`, file `date.log` **không được tạo** (hoặc không có dòng mới). Lý do: mọi thứ sau `%` đầu tiên — kể cả phần `>> date.log 2>&1` — bị chuyển thành stdin, lệnh thực tế chỉ còn `date +`. Output của nó không được redirect nên cron vứt đi; log cron có thể có dòng `No MTA installed, discarding output`. Với `date +\%F`, `date.log` có ngày dạng `2026-10-31`.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Job không chạy, không có dòng `CMD` trong log cron | Daemon cron không chạy (WSL vừa khởi động lại); sai cú pháp; sửa nhầm crontab của user khác (`sudo crontab -e` là crontab của **root**) | `service cron status`; `crontab -l` kiểm tra đúng user |
| Có dòng `CMD` nhưng không có kết quả | Lệnh lỗi, output không được ghi | Thêm `>> log 2>&1`, đọc log |
| `not found` / exit 127 | `PATH` của cron tối giản | Đường dẫn tuyệt đối, hoặc đặt `PATH=` đầu crontab/trong script |
| Script dùng cú pháp Bash lỗi khi chạy bằng cron | Lệnh trong crontab chạy bằng `/bin/sh` | Đưa vào script có shebang bash; hoặc `SHELL=/bin/bash` |
| File log/kết quả xuất hiện ở home | Cron chạy ở `$HOME`, dùng đường dẫn tương đối | Đường dẫn tuyệt đối mọi nơi |
| Lệnh có `%` chạy sai | `%` bị đổi thành xuống dòng | Viết `\%` hoặc chuyển lệnh vào script |
| Job chạy 60 lần trong một giờ | Viết `* 2 * * *` thay vì `0 2 * * *` | Trường phút phải cụ thể |
| Job chạy sai giờ | Múi giờ server là UTC | Kiểm tra `timedatectl`; quy đổi giờ |
| Script trong `/etc/cron.daily/` không bao giờ chạy | Tên file có dấu chấm (`backup.sh`) hoặc thiếu quyền `x` | Đổi tên bỏ đuôi; `chmod +x`; kiểm tra bằng `run-parts --test` |
| Biến môi trường (`DB_PASSWORD`…) rỗng khi chạy bằng cron | Biến đặt trong `~/.bashrc`, cron không đọc | Script tự `source` file cấu hình bằng đường dẫn tuyệt đối |
| Mất toàn bộ crontab | Gõ `crontab -r` | Phục hồi từ bản sao lưu; tập thói quen `crontab -l > backup` |
| Job lỗi `Permission denied` dù chạy tay được | Chạy tay bằng `sudo`, cron chạy bằng user thường (hoặc ngược lại) | Xác định job chạy bằng user nào; chạy thử đúng user đó |

---

## 12. Đọc log và xử lý lỗi

Có **ba nơi** phải nhìn, theo thứ tự. Mỗi nơi trả lời một câu hỏi khác nhau:

| # | Câu hỏi | Nhìn ở đâu | Không có gì → nghĩa là |
|---|---|---|---|
| 1 | Daemon cron có sống không? | `systemctl status cron` / `service cron status` | Cron chưa chạy → khởi động nó |
| 2 | Cron có kích hoạt job không? | `journalctl -u cron` / `grep CRON /var/log/syslog` | Lịch sai, crontab sai user, hoặc chưa đến giờ |
| 3 | Job có thành công không? | **Log riêng của job** (`>> log 2>&1`) | Job không ghi log → sửa crontab để ghi |

Một số dòng hay gặp trong log cron:

```text
CRON[2842]: (phuong) CMD (/home/phuong/bin/job.sh >> ... 2>&1)
```

→ Đã kích hoạt. Chuyển sang xem log của job.

```text
CRON[2850]: (CRON) info (No MTA installed, discarding output)
```

→ Lệnh có output nhưng **không được redirect**, cron định gửi mail mà máy không có mail server (MTA) nên **vứt bỏ**. Đây là dấu hiệu bạn quên `>> log 2>&1`.

```text
cron[312]: (phuong) RELOAD (crontabs/phuong)
```

→ Cron đã nạp lại crontab sau khi bạn sửa.

**Quy trình debug "cron không chạy":**

1. Kiểm tra 3 tầng ở bảng trên — xác định lỗi nằm ở tầng nào.
2. Chạy lại job **trong môi trường giống cron** để tái hiện lỗi:

   ```bash
   env -i HOME="$HOME" LOGNAME="$USER" PATH=/usr/bin:/bin SHELL=/bin/sh \
       /bin/sh -c '/home/phuong/bin/job.sh'
   echo "exit: $?"
   ```

   `env -i` xóa sạch môi trường hiện tại, chỉ giữ những biến bạn liệt kê — gần với những gì cron cung cấp.
3. Lỗi tái hiện được → sửa (đường dẫn tuyệt đối, `PATH`, `source` cấu hình) → chạy lại bước 2.
4. Đặt lịch `* * * * *` để thử nhanh, khi chạy đúng mới đổi về lịch thật.
5. Ghi vào `troubleshooting-journal.md`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Cron là gì? Vì sao trên WSL job hẹn 2:00 sáng có thể không bao giờ chạy?
2. Đọc các biểu thức: `0 3 * * *`, `*/15 * * * *`, `0 8 * * 1`, `30 23 L * *` (cái cuối có hợp lệ với cron của Ubuntu không?), `0 0 1 1 *`.
3. Viết biểu thức cho: (a) 1:30 sáng mỗi ngày; (b) mỗi 2 giờ; (c) 18:00 thứ Hai đến thứ Sáu; (d) 0:00 ngày 1 và 15 hằng tháng.
4. Vì sao `* 2 * * *` là một lỗi phổ biến? Nó thực sự chạy bao nhiêu lần?
5. Nêu 4 điểm khác nhau giữa môi trường của cron và terminal của bạn.
6. Dòng `CMD (...)` trong log cron chứng minh điều gì, và **không** chứng minh điều gì?
7. `>> job.log 2>&1` và `2>&1 >> job.log` khác nhau thế nào?
8. Ký tự `%` trong crontab có ý nghĩa gì? Xử lý thế nào?
9. `crontab -e` khác sửa trực tiếp `/etc/crontab` như thế nào? Định dạng `/etc/cron.d/*` khác crontab user ở điểm nào?
10. Vì sao `flock -n` cần thiết cho job chạy thường xuyên? Nếu job bị kill giữa chừng, khóa có bị kẹt không?
11. So sánh cron và systemd timer ở 3 tiêu chí. Ở tình huống nào bạn chọn timer?
12. Server EC2 dùng UTC. Bạn muốn backup lúc 2:00 sáng giờ Việt Nam. Viết biểu thức cron.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/08-solutions.md](solutions/08-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Đọc và viết lịch.** Không dùng công cụ, viết biểu thức cron cho 8 yêu cầu sau, rồi mới kiểm tra lại bằng [crontab.guru](https://crontab.guru/): (a) mỗi 10 phút; (b) 6:00 và 18:00 mỗi ngày; (c) mỗi 30 phút trong khung 8:00–18:00, thứ Hai–Sáu; (d) 23:59 ngày cuối tuần (thứ Bảy, Chủ nhật); (e) 4:00 sáng ngày 1 mỗi quý (tháng 1, 4, 7, 10); (f) mỗi phút trong giờ 3 giờ sáng ngày Chủ nhật; (g) một lần khi máy khởi động; (h) 2:00 sáng giờ Việt Nam trên server dùng UTC.

**Bài 2 — Dọn file tạm.** Viết script `cleanup-tmp.sh` xóa các file trong `~/devops-lab/tmp/` cũ hơn 2 ngày (dùng `find -mtime`), ghi số file đã xóa vào log có timestamp. Đặt cron chạy mỗi giờ. Kiểm thử bằng `touch -d "3 days ago"`. Chứng minh bằng log cron + log của script rằng nó đã chạy ít nhất 2 lần.

**Bài 3 — Chạy chồng.** Viết `slow-job.sh` ngủ 90 giây và ghi thời điểm bắt đầu/kết thúc vào log. Đặt cron mỗi phút **không có** `flock`, quan sát log trong 5 phút. Sau đó thêm `flock -n`, quan sát lại. Giải thích sự khác biệt bằng dòng log cụ thể.

**Bài 4 — Chuyển sang systemd timer** (chỉ làm nếu WSL đã bật systemd — xem [bài 04](04-processes-systemd.md)). Chuyển job của Bài 2 thành cặp `cleanup-tmp.service` + `cleanup-tmp.timer` chạy mỗi giờ với `Persistent=true`. Chứng minh bằng `systemctl list-timers` và `journalctl -u cleanup-tmp.service`. Viết 3 câu so sánh trải nghiệm debug giữa cron và timer.

**Bài 5 — Điều tra.** Một đồng nghiệp gửi crontab sau, nói "không cái nào chạy được". Tìm tất cả vấn đề (ít nhất 6) và viết lại:

```text
* 3 * * * backup.sh
*/5 * * * * cd /opt/app && ./check.sh > check.log
0 0 * * * tar -czf /backup/etc-$(date +%F).tar.gz /etc
@daily source ~/.bashrc && python3 report.py
```

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Đọc và viết biểu thức cron 5 trường không cần tra cứu, tránh được bẫy `* 2 * * *`.
- [ ] Mọi cron job bạn viết đều có đường dẫn tuyệt đối và `>> log 2>&1`.
- [ ] Được báo "cron job không chạy", bạn kiểm tra theo đúng 3 tầng: daemon → kích hoạt → kết quả job.
- [ ] Tái hiện được lỗi trong môi trường giống cron bằng `env -i`.
- [ ] Giải thích được khi nào nên dùng `flock`, khi nào nên dùng systemd timer.
- [ ] Hoàn thành Bài tập 1 và 5 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [crontab(5) — Ubuntu 24.04](https://manpages.ubuntu.com/manpages/noble/man5/crontab.5.html) | Cú pháp chính thức, biến `SHELL`/`PATH`/`MAILTO`, quy tắc `%` | 2026-10-31 |
| [flock(1) — Ubuntu 24.04](https://manpages.ubuntu.com/manpages/noble/man1/flock.1.html) | Tham số `-n`, `-w` | 2026-10-31 |
| [systemd.timer(5) — Ubuntu 24.04](https://manpages.ubuntu.com/manpages/noble/man5/systemd.timer.5.html) | `OnCalendar`, `Persistent`, timer kích hoạt service cùng tên | 2026-10-31 |
| [crontab.guru](https://crontab.guru/) | Kiểm tra nhanh biểu thức cron (sau khi đã tự đọc) | 2026-10-31 |
| [Ubuntu Server docs](https://ubuntu.com/server/docs) | Tra cứu chung | 2026-10-31 |
| `man 5 crontab`, `man cron`, `man systemd.time` (trên máy) | Tra cứu không cần mạng | — |
