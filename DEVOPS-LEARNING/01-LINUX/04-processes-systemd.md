# 04. Processes & systemd

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Kiến trúc Linux](01-linux-architecture-filesystem.md), [03. Permissions, Users & Groups](03-permissions-users-groups.md)
> Môi trường: `[WSL]` Ubuntu 24.04 (cần systemd — mục 9 bước 6 sẽ kiểm tra), `[Sandbox]` container `ubuntu:22.04`

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc](#6-sơ-đồ-kiến-trúc)
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

- Giải thích được **process** là gì, **PID/PPID** là gì, và một process mới được sinh ra thế nào.
- Đọc được các trạng thái process (`R`, `S`, `D`, `Z`, `T`) và biết **zombie**, **orphan** là gì.
- Dùng `ps`, `pstree`, `top` để tìm process và đọc đúng các con số quan trọng.
- Hiểu **signal**, biết vì sao phải gửi `SIGTERM` trước `SIGKILL`, và đọc được exit code `137`, `143`.
- Quản lý **systemd service**: start/stop/enable, viết unit file, xem log cơ bản bằng `journalctl`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "App Spring Boot trên server tự nhiên chết, phải SSH vào khởi động lại bằng tay" | Biến app thành **systemd service** với `Restart=on-failure` |
| "Server chậm, CPU 100%" | Dùng `top`/`ps` tìm process thủ phạm |
| "Container bị kill, exit code 137" | 137 = 128 + 9 → bị `SIGKILL` (thường do hết RAM hoặc dừng quá lâu) |
| "Deploy bản mới làm rơi request đang xử lý" | App phải được dừng bằng `SIGTERM` để **graceful shutdown** (tắt nhẹ nhàng) |
| "Port 8080 đang bị chiếm" | Tìm PID đang dùng port, xem nó là gì, rồi quyết định dừng |
| "Ở Kubernetes, Pod bị `CrashLoopBackOff`" | Tư duy giống hệt systemd: process chết → hệ thống khởi động lại → lại chết |

Docker, Kubernetes, systemd đều là **trình quản lý process**. Hiểu process trên Linux là hiểu nền của cả ba.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Chương trình và process khác nhau thế nào?

- **Chương trình (program)**: file nằm yên trên đĩa, ví dụ `/usr/bin/java`, `app.jar`.
- **Process (tiến trình)**: một chương trình **đang chạy**, được kernel cấp cho: một vùng RAM riêng, một số hiệu riêng, quyền của một user cụ thể, danh sách file đang mở.

Một chương trình có thể chạy thành nhiều process cùng lúc (mở 3 terminal → 3 process `bash`).

### 3.2. PID và PPID

- **PID (Process ID — mã số process)**: số nguyên duy nhất kernel gán cho mỗi process.
- **PPID (Parent PID — mã số process cha)**: PID của process đã tạo ra nó.

Mọi process đều có cha, tạo thành **cây process**. Gốc của cây là **PID 1** — process đầu tiên kernel khởi chạy. Trên Ubuntu hiện đại, PID 1 là **systemd**.

### 3.3. Process mới được sinh ra thế nào? (fork/exec — mức khái niệm)

Khi bạn gõ `ls` trong Bash, có hai bước:

1. **fork** (phân nhánh): Bash tạo ra một **bản sao** của chính nó → process con.
2. **exec** (thực thi): process con **thay ruột** bằng chương trình `ls`. PID giữ nguyên, nhưng giờ nó chạy code của `ls`.

Bash (cha) chờ con kết thúc, nhận lại **exit code** (bạn đã gặp ở [bài 01](01-linux-architecture-filesystem.md#echo---exit-code)). Việc cha "nhận" exit code của con gọi là **wait**. Ghi nhớ ý này — nó giải thích zombie ở mục 4.2.

### 3.4. Daemon và service

- **Daemon** (tiến trình nền): process chạy ngầm lâu dài, không gắn với terminal nào. Tên thường kết thúc bằng `d`: `sshd`, `systemd-journald`, `dockerd`.
- **Service** (dịch vụ): cách systemd gọi một daemon mà nó quản lý. Ví dụ `ssh.service`, `cron.service`.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Trạng thái process

Một process không phải lúc nào cũng "đang chạy". Cột `STAT` trong `ps` (hoặc `S` trong `top`) cho biết trạng thái:

| Ký hiệu | Tên | Nghĩa | Bình thường không? |
|---|---|---|---|
| `R` | Running | Đang chạy hoặc đang xếp hàng chờ CPU | Có |
| `S` | Sleeping (interruptible) | Đang ngủ chờ sự kiện (chờ request, chờ input). **Phần lớn process ở trạng thái này** | Có |
| `D` | Uninterruptible sleep | Đang chờ I/O (ổ đĩa, mạng lưu trữ), không thể ngắt kể cả bằng `SIGKILL` | Thỉnh thoảng thì có. Nhiều process `D` kéo dài → ổ đĩa có vấn đề |
| `Z` | Zombie | Đã chết nhưng cha chưa nhận exit code | Vài cái thoáng qua thì có. Tích tụ nhiều → bug ở process cha |
| `T` | Stopped | Bị tạm dừng (ví dụ bấm `Ctrl+Z`) | Có, nếu bạn chủ động dừng |
| `I` | Idle | Luồng kernel đang rảnh | Có |

Ký tự phụ đi sau (ví dụ `Ss`, `R+`, `Sl`):

| Ký tự | Nghĩa |
|---|---|
| `s` | Session leader (thường là shell) |
| `+` | Đang ở foreground của terminal |
| `l` | Có nhiều thread (process Java luôn có `l`) |
| `<` / `N` | Ưu tiên cao / ưu tiên thấp (xem `nice` ở 4.5) |

### 4.2. 🟥 Zombie và orphan

**Zombie (process xác sống)**: con đã kết thúc, đã giải phóng RAM, nhưng vẫn còn một dòng trong bảng process vì **cha chưa gọi wait** để nhận exit code.

- Zombie **không tốn CPU/RAM**, chỉ chiếm một PID.
- **Không thể kill zombie** — nó đã chết rồi. Muốn dọn, phải làm cho cha gọi wait, hoặc dừng process cha.
- Khi cha chết, zombie được PID 1 "nhận nuôi" và PID 1 sẽ dọn nó.

**Orphan (process mồ côi)**: cha chết trước khi con kết thúc. Con vẫn chạy bình thường và được **PID 1 nhận làm con nuôi** (PPID đổi thành 1).

> 🟨 **Liên hệ Docker (Module 04):** trong container, process chính của bạn là PID 1. Nếu nó không biết dọn zombie, zombie sẽ tích tụ. Đó là lý do có tùy chọn `docker run --init`. Ghi nhớ để gặp lại sau.

### 4.3. 🟥 Signal — cách nói chuyện với process

**Signal (tín hiệu)** là thông điệp ngắn kernel gửi tới process, yêu cầu nó làm gì đó. Process có thể **bắt (trap)** signal để xử lý theo ý mình — trừ `SIGKILL` và `SIGSTOP`.

| Signal | Số | Gửi khi nào | Process có bắt được không |
|---|---|---|---|
| `SIGHUP` | 1 | Terminal bị đóng; nhiều daemon dùng nó nghĩa là "đọc lại cấu hình" | Có |
| `SIGINT` | 2 | Bạn bấm `Ctrl+C` | Có |
| `SIGKILL` | 9 | `kill -9` — kernel giết ngay lập tức | **Không** |
| `SIGTERM` | 15 | `kill` mặc định, `systemctl stop`, `docker stop` — "làm ơn dừng lại" | Có |
| `SIGSTOP` | 19 | Tạm dừng bắt buộc | **Không** |
| `SIGTSTP` | 20 | Bạn bấm `Ctrl+Z` | Có |
| `SIGCONT` | 18 | Cho process đang dừng chạy tiếp | — |

(Số hiệu trên là của Linux x86_64. Dùng **tên** thay vì số khi viết script để không phụ thuộc nền tảng: `kill -TERM` thay vì `kill -15`.)

#### Vì sao phải `SIGTERM` trước, `SIGKILL` sau?

Tưởng tượng app Spring Boot đang xử lý 20 request và đang ghi dở vào database:

- **`SIGTERM`**: app nhận được, ngừng nhận request mới, xử lý nốt request đang chạy, đóng kết nối database gọn gàng, rồi tự thoát. Đây gọi là **graceful shutdown**. Spring Boot bật graceful shutdown mặc định cho web server nhúng (cấu hình bằng `server.shutdown`).
- **`SIGKILL`**: kernel xóa process ngay lập tức. Request đang xử lý bị cắt ngang, giao dịch dở dang, file có thể bị ghi hỏng.

Quy trình chuẩn — **các công cụ chuyên nghiệp đều làm đúng như vậy**:

```text
Gửi SIGTERM ──► chờ một khoảng thời gian (grace period) ──► vẫn chưa chết? ──► SIGKILL
```

| Công cụ | Thời gian chờ mặc định trước khi `SIGKILL` |
|---|---|
| `systemctl stop` | `TimeoutStopSec` (mặc định 90 giây) |
| `docker stop` | 10 giây (gặp lại ở Module 04) |
| Kubernetes xóa Pod | `terminationGracePeriodSeconds` (gặp lại ở Module 09) |

#### Exit code khi bị signal giết

Khi process chết vì signal, shell báo exit code = **128 + số signal**:

| Exit code | Nghĩa | Gặp ở đâu |
|---|---|---|
| `130` | 128 + 2 → bị `SIGINT` (Ctrl+C) | Terminal |
| `137` | 128 + 9 → bị `SIGKILL` | Container bị OOM kill, `docker stop` quá hạn |
| `143` | 128 + 15 → bị `SIGTERM` | Java thoát sau khi nhận `SIGTERM` |

Thuộc lòng `137` và `143` — bạn sẽ gặp chúng hằng tuần khi làm DevOps.

### 4.4. 🟥 Foreground, background và job control

- **Foreground** (tiền cảnh): lệnh chiếm terminal, bạn phải chờ nó xong.
- **Background** (hậu cảnh): thêm `&` cuối lệnh, terminal trả lại dấu nhắc ngay.

**Job** là process bạn khởi chạy từ shell hiện tại. `jobs` liệt kê, `fg`/`bg` chuyển qua lại, `%1` là job số 1.

Process chạy nền bằng `&` vẫn **gắn với terminal**: đóng terminal → nó nhận `SIGHUP` và thường chết theo. Muốn sống sót: `nohup lệnh &`.

> ⚠️ `nohup` và `&` chỉ dùng để thử nghiệm nhanh. **Không bao giờ chạy app thật trên server bằng `nohup java -jar app.jar &`**: không tự khởi động lại khi chết, không tự chạy khi server reboot, log nằm lung tung. Cách đúng là systemd (mục 4.6) hoặc container.

### 4.5. 🟨 Độ ưu tiên: nice và renice

**Nice value** quyết định process được ưu tiên dùng CPU nhiều hay ít: từ `-20` (ưu tiên cao nhất) đến `19` (nhường nhất), mặc định `0`. Càng "nice" (tử tế) thì càng nhường CPU cho người khác.

- `nice -n 10 lệnh` — chạy lệnh với độ ưu tiên thấp (ví dụ script nén backup, để không làm chậm app).
- `renice -n 10 -p <PID>` — đổi độ ưu tiên của process đang chạy.
- Chỉ root mới được **giảm** nice value (tăng ưu tiên).

### 4.6. 🟥 systemd — trình quản lý hệ thống

**systemd** là PID 1 trên Ubuntu, Debian, RHEL, Amazon Linux. Nó:

- Khởi động mọi dịch vụ khi máy boot, theo đúng thứ tự phụ thuộc.
- Giám sát dịch vụ, **khởi động lại khi dịch vụ chết** (nếu được cấu hình).
- Gom log của mọi dịch vụ vào **journal** (đọc bằng `journalctl`).

#### Unit — đơn vị quản lý

Mọi thứ systemd quản lý gọi là **unit**, mô tả trong một file văn bản. Loại unit nhận biết qua đuôi file:

| Đuôi | Loại | Ví dụ |
|---|---|---|
| `.service` | Dịch vụ (process chạy lâu dài hoặc chạy một lần) | `ssh.service`, `taskhub.service` |
| `.timer` | Lập lịch (thay thế cron — [bài 08](08-cron-scheduling.md)) | `apt-daily.timer` |
| `.target` | Nhóm unit, đại diện một "trạng thái" của hệ thống | `multi-user.target` (hệ thống chạy đầy đủ, không giao diện đồ họa) |
| `.socket`, `.mount` | Socket, điểm mount | 🟦 |

#### Unit file nằm ở đâu?

| Thư mục | Ai đặt file vào | Ưu tiên |
|---|---|---|
| `/etc/systemd/system/` | **Bạn** (quản trị viên) | Cao nhất — đè lên file cùng tên ở dưới |
| `/run/systemd/system/` | Tạo lúc chạy, mất khi reboot | Trung bình |
| `/lib/systemd/system/` (= `/usr/lib/systemd/system/`) | Gói phần mềm khi cài qua `apt` | Thấp nhất |

> **Quy tắc:** không sửa file trong `/lib/systemd/system/` — lần cập nhật gói sau sẽ ghi đè mất. Tự viết service mới hoặc ghi đè → đặt ở `/etc/systemd/system/`.

#### Cấu trúc một unit file `.service`

```ini
[Unit]
Description=Taskhub demo HTTP service       # mô tả, hiện trong systemctl status
After=network.target                        # khởi động SAU khi mạng sẵn sàng

[Service]
Type=simple                                 # process ExecStart chính là dịch vụ
User=taskhub                                # chạy bằng user này, KHÔNG phải root
Group=taskhub
WorkingDirectory=/opt/taskhub               # thư mục làm việc của process
EnvironmentFile=/etc/taskhub-demo.env       # nạp biến môi trường từ file
Environment=JAVA_OPTS=-Xmx256m              # hoặc khai báo trực tiếp
ExecStart=/usr/bin/java -jar /opt/taskhub/app.jar   # lệnh chạy — nên dùng đường dẫn tuyệt đối
Restart=on-failure                          # tự khởi động lại khi chết bất thường
RestartSec=5                                # chờ 5 giây trước khi khởi động lại
SuccessExitStatus=143                       # coi exit code 143 (Java thoát sau SIGTERM) là bình thường

[Install]
WantedBy=multi-user.target                  # "enable" = gắn vào trạng thái hệ thống chạy bình thường
```

> Lưu ý: comment `#` ở cuối dòng như trên chỉ để giải thích trong bài. Trong unit file thật, **comment phải nằm trên dòng riêng** — systemd không hiểu comment cuối dòng và sẽ coi nó là một phần giá trị.

Giải thích các tùy chọn quan trọng:

- **`ExecStart=`**: chương trình đầu tiên phải là **đường dẫn tuyệt đối** (`/usr/bin/java`) hoặc **tên trần không có dấu `/`** (`java`). Với tên trần, systemd tìm trong một danh sách thư mục **cố định** (`/usr/local/bin`, `/usr/bin` và các thư mục `sbin` tương ứng) — **không** dùng biến `PATH` của bạn. Đường dẫn tương đối có dấu `/` như `bin/app.sh` hay `./app.sh` bị từ chối. Quy tắc an toàn, rõ ràng nhất: **luôn dùng đường dẫn tuyệt đối**.
- **`Restart=`**: `no` (mặc định — chết là thôi), `on-failure` (khởi động lại khi exit code khác 0, bị signal giết bất thường như `SIGKILL`, bị timeout), `always` (luôn khởi động lại, kể cả khi thoát bình thường). Dùng `on-failure` cho phần lớn ứng dụng web. `systemctl stop` **không** kích hoạt restart.
- **`RestartSec=`**: mặc định chỉ 100 ms. Đặt vài giây để tránh vòng lặp khởi động lại quá dồn dập khi app lỗi cấu hình.
- **`SuccessExitStatus=143`**: khi nhận `SIGTERM`, JVM chạy shutdown hook rồi thoát với code 143. Nếu không khai báo dòng này, mỗi lần `systemctl stop` service Java sẽ hiện trạng thái `failed`, dù thực ra nó tắt đúng cách.
- **`User=`**: nguyên tắc **least privilege** (đặc quyền tối thiểu) từ [bài 03](03-permissions-users-groups.md). App bị hack thì kẻ tấn công chỉ có quyền của user `taskhub`, không phải root.

#### Hai khái niệm hay bị nhầm: start và enable

| Lệnh | Tác dụng | Khi reboot |
|---|---|---|
| `systemctl start X` | Chạy X **ngay bây giờ** | Không tự chạy lại |
| `systemctl enable X` | Đánh dấu X **tự chạy khi boot** (tạo symlink vào `multi-user.target.wants/`) | Tự chạy |
| `systemctl enable --now X` | Cả hai | Tự chạy |

### 4.7. 🟥 systemd trên WSL

Như đã nói ở [bài 01 mục 4.6](01-linux-architecture-filesystem.md#46--wsl2-khác-server-linux-thật-ở-đâu), WSL **chỉ có systemd nếu được bật**. Ubuntu cài bằng `wsl --install` gần đây đã bật sẵn; bản cài từ lâu có thể chưa bật. Mục 9 bước 6 hướng dẫn kiểm tra và (nếu bạn đồng ý) cách bật.

Ngoài ra trên WSL: dịch vụ systemd **không giữ WSL sống**. Đóng hết terminal một lúc, WSL có thể tự tắt và dịch vụ dừng theo. Trên server thật không có chuyện này.

---

## 5. Ví dụ thực tế

### Ví dụ 1: App Java tự chết lúc nửa đêm

Trước đây, team chạy app bằng `nohup java -jar app.jar &`. Một đêm app bị lỗi hết bộ nhớ và chết. Không ai biết cho đến sáng.

Sau khi chuyển sang systemd với `Restart=on-failure`:

```text
02:13:05 java[4410]: java.lang.OutOfMemoryError: Java heap space
02:13:06 systemd[1]: taskhub.service: Main process exited, code=exited, status=1/FAILURE
02:13:06 systemd[1]: taskhub.service: Failed with result 'exit-code'.
02:13:11 systemd[1]: taskhub.service: Scheduled restart job, restart counter is at 1.
02:13:11 systemd[1]: Started Taskhub service.
```

App chỉ gián đoạn 5 giây, và log ghi rõ nguyên nhân để sáng hôm sau team điều tra. Lưu ý: systemd **giảm thời gian chết**, nhưng **không sửa lỗi gốc** — vẫn phải tìm vì sao hết bộ nhớ.

### Ví dụ 2: "Port 8080 already in use"

```bash
sudo ss -tlnp | grep 8080      # ss học kỹ ở Module 02
```

```text
LISTEN 0  100  *:8080  *:*  users:(("java",pid=2741,fd=12))
```

```bash
ps -o pid,ppid,user,etime,cmd -p 2741
```

```text
    PID    PPID USER     ELAPSED CMD
   2741       1 phuong  03:12:45 java -jar target/taskhub-0.0.1.jar
```

PPID = 1 → process mồ côi, chạy được 3 tiếng — là bản bạn chạy nền từ chiều rồi quên. Dừng nó an toàn bằng `kill 2741` (SIGTERM), không phải `kill -9`.

---

## 6. Sơ đồ kiến trúc

### 6.1. Cây process

```text
systemd (PID 1)
├── systemd-journald         ← gom log
├── cron                     ← chạy tác vụ định kỳ
├── sshd                     ← chờ kết nối SSH (trên server)
│   └── sshd: phuong         ← một phiên SSH
│       └── bash (PID 1203)  ← shell của bạn
│           ├── top          ← lệnh bạn đang chạy (foreground)
│           └── sleep (job &) ← lệnh chạy nền
└── java (User=taskhub)      ← app do systemd quản lý, PPID = 1
```

### 6.2. Vòng đời một service với `Restart=on-failure`

```text
            systemctl start
 inactive ───────────────────► activating ──► active (running)
    ▲                                              │
    │ systemctl stop                               │ process chết
    │ (SIGTERM → chờ → SIGKILL)                    ▼
    └────────────────────────────── exit code / signal là gì?
                                     │                    │
                          bình thường (0, 143*)    bất thường (1, SIGKILL…)
                                     │                    │
                                     ▼                    ▼
                                 inactive         chờ RestartSec ──► start lại
                                                  (quá nhiều lần → failed)
 * 143 chỉ được coi là bình thường khi khai báo SuccessExitStatus=143
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ps aux`, `ps -ef` | Liệt kê mọi process | 🟥 |
| `ps -o <cột> -p <PID>` | Xem cột tùy chọn của process cụ thể | 🟥 |
| `pstree -p` | Xem cây process | 🟨 |
| `top` | Theo dõi process theo thời gian thực | 🟥 |
| `pgrep`, `pkill` | Tìm / gửi signal theo tên | 🟥 |
| `kill` | Gửi signal theo PID | 🟥 |
| `jobs`, `fg`, `bg`, `&`, `nohup` | Job control | 🟨 |
| `nice`, `renice` | Độ ưu tiên CPU | 🟨 |
| `systemctl start/stop/restart/reload/status` | Điều khiển service | 🟥 |
| `systemctl enable/disable/is-active/is-enabled` | Tự chạy khi boot, kiểm tra trạng thái | 🟥 |
| `systemctl daemon-reload` | Nạp lại unit file sau khi sửa | 🟥 |
| `systemctl list-units --failed` | Liệt kê service bị lỗi | 🟥 |
| `systemctl cat` | Xem nội dung unit file đang dùng | 🟨 |
| `journalctl -u <service>` | Xem log của một service | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu minh họa từ Ubuntu 24.04 trên WSL. PID, thời gian, số liệu trên máy bạn sẽ khác.

### `ps aux` — ảnh chụp mọi process

```bash
ps aux | head -5
```

```text
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.1 166140 11356 ?        Ss   08:01   0:01 /sbin/init
root          55  0.0  0.2  47776 15872 ?        S<s  08:01   0:00 /lib/systemd/systemd-journald
phuong      1203  0.0  0.0  10172  5288 pts/0    Ss   08:05   0:00 -bash
phuong      2741  1.2  4.1 3612480 334520 ?      Sl   09:10   0:42 java -jar target/taskhub-0.0.1.jar
```

`aux` là cú pháp kiểu BSD (không có dấu `-`): `a` = process của mọi user, `u` = hiển thị dạng hướng người dùng (có cột USER, %CPU…), `x` = gồm cả process không gắn terminal (daemon).

| Cột | Ý nghĩa |
|---|---|
| `PID` | Mã số process |
| `%CPU`, `%MEM` | Phần trăm CPU, RAM đang dùng |
| `VSZ` | Virtual size (KB) — bộ nhớ ảo đã **xin**, không phải đang dùng thật |
| `RSS` | Resident set size (KB) — RAM **thực sự đang chiếm**. Nhìn cột này khi hỏi "app tốn bao nhiêu RAM" |
| `TTY` | Terminal gắn với process; `?` = không có (daemon) |
| `STAT` | Trạng thái (mục 4.1) |
| `START`, `TIME` | Thời điểm bắt đầu; tổng thời gian CPU đã dùng |
| `COMMAND` | Lệnh đầy đủ |

> `/sbin/init` ở PID 1 là symlink tới systemd. Nếu trên WSL bạn thấy `/init` thay vì `/sbin/init` → systemd chưa được bật.

### `ps -ef` — cú pháp kiểu Unix, có PPID

```bash
ps -ef | grep [j]ava
```

```text
phuong      2741    1203  1 09:10 pts/0    00:00:42 java -jar target/taskhub-0.0.1.jar
```

`-e` = mọi process, `-f` = full format (có cột `PPID`). Mẹo `grep [j]ava`: dấu ngoặc làm cho chính dòng lệnh `grep` không khớp mẫu, nên không bị lẫn vào kết quả.

### `ps -o` — chọn đúng cột cần xem

```bash
ps -o pid,ppid,user,stat,etime,rss,cmd -p 2741
ps -eo pid,user,%cpu,%mem,cmd --sort=-%mem | head -6     # 5 process tốn RAM nhất
```

```text
    PID    PPID USER     STAT     ELAPSED   RSS CMD
   2741    1203 phuong   Sl         05:12 334520 java -jar target/taskhub-0.0.1.jar
```

| Tham số | Ý nghĩa |
|---|---|
| `-o <cột,...>` | Chọn cột hiển thị. `etime` = thời gian đã chạy |
| `-p <PID>` | Chỉ xem process này |
| `--sort=-%mem` | Sắp giảm dần theo RAM (`-` = giảm dần) |

### `pstree` — cây process

```bash
pstree -p $$          # cây bắt đầu từ shell hiện tại
pstree -ps $$         # đường đi từ PID 1 xuống shell hiện tại
```

```text
systemd(1)───init-systemd(Ub(2)───SessionLeader(410)───Relay(412)───bash(1203)───pstree(3010)
```

`-p` hiện PID, `-s` hiện các process cha. Nếu không có `pstree` (nằm trong gói `psmisc`), dùng `ps -ef --forest`.

### `top` — theo dõi theo thời gian thực

```text
top - 09:32:10 up  1:31,  1 user,  load average: 0.52, 0.31, 0.20
Tasks:  38 total,   1 running,  37 sleeping,   0 stopped,   0 zombie
%Cpu(s):  3.1 us,  0.8 sy,  0.0 ni, 95.9 id,  0.1 wa,  0.0 hi,  0.1 si,  0.0 st
MiB Mem :   7841.2 total,   5012.4 free,   1630.7 used,   1198.1 buff/cache
MiB Swap:   2048.0 total,   2048.0 free,      0.0 used.   5940.3 avail Mem

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
   2741 phuong    20   0 3612480 334520  24120 S   1.3   4.2   0:42.15 java
```

Đọc từng dòng:

| Dòng | Đọc gì |
|---|---|
| 1 | `up 1:31` = đã chạy 1 giờ 31 phút. **`load average`**: số process trung bình đang chạy hoặc chờ CPU/I/O trong 1, 5, 15 phút. So với **số nhân CPU**: máy 8 nhân có load 2.0 là nhàn; load 12 là quá tải. Bài 07 phân tích sâu |
| 2 | Tổng số process theo trạng thái. Chú ý số `zombie` |
| 3 | Phân bổ CPU: `us` = code ứng dụng, `sy` = kernel, `id` = rảnh, **`wa` = chờ I/O** (cao → ổ đĩa chậm), `st` = bị máy chủ ảo hóa "lấy mất" (gặp trên cloud) |
| 4–5 | RAM và swap. Nhìn **`avail Mem`**, không nhìn `free` — Linux dùng RAM trống làm cache, `free` thấp là bình thường |
| Bảng | `VIRT` (ảo) ≈ `VSZ`, **`RES` (thực) ≈ `RSS`**, `NI` = nice value, `S` = trạng thái |

Phím tắt trong `top`: `P` sắp theo CPU, `M` sắp theo RAM, `1` hiện từng nhân CPU, `k` gửi signal, `q` thoát.

### `kill`, `pkill`, `pgrep` — gửi signal

```bash
kill 2741                 # mặc định gửi SIGTERM
kill -TERM 2741           # viết rõ ràng — tương đương dòng trên
kill -KILL 2741           # ⚠️ SIGKILL — chỉ dùng khi SIGTERM không hiệu quả
kill -HUP 1500            # yêu cầu daemon đọc lại cấu hình (nếu daemon hỗ trợ)
kill -l                   # liệt kê mọi signal
```

```bash
pgrep -a java             # tìm process có tên chứa "java", -a hiện cả dòng lệnh
pkill -f "taskhub-0.0.1.jar"   # gửi SIGTERM cho mọi process có dòng lệnh khớp mẫu
```

```text
2741 java -jar target/taskhub-0.0.1.jar
```

| Tham số | Ý nghĩa |
|---|---|
| `-a` (pgrep) | Hiện cả dòng lệnh, không chỉ PID |
| `-f` | So khớp trên **toàn bộ dòng lệnh**, không chỉ tên chương trình. Mọi app Java đều tên `java`, nên cần `-f` để phân biệt |
| `-u <user>` | Chỉ process của user đó |

> ⚠️ `pkill` có thể trúng nhiều process một lúc. Luôn chạy `pgrep -a <mẫu>` trước để xem sẽ trúng những gì, rồi mới `pkill`.

`kill` không in gì nếu thành công. Lỗi thường gặp: `kill: (2741) - No such process` (process đã chết) và `kill: (1) - Operation not permitted` (không có quyền gửi signal cho process của user khác).

### `jobs`, `fg`, `bg`, `nohup`

```bash
sleep 300 &               # chạy nền
jobs                      # [1]+  Running    sleep 300 &
fg %1                     # đưa lên foreground, giờ bấm Ctrl+Z để tạm dừng
bg %1                     # cho chạy tiếp ở nền
kill %1                   # gửi SIGTERM cho job 1
nohup ./long-task.sh > task.log 2>&1 &   # chạy nền, sống sót khi đóng terminal
```

`> task.log 2>&1` ghi cả đầu ra thường và lỗi vào file — sẽ học kỹ ở [bài 02](02-essential-commands-text.md).

### `nice` và `renice`

```bash
nice -n 10 tar -czf backup.tar.gz ~/devops-lab     # nén với ưu tiên thấp
renice -n 15 -p 2741                                # giảm ưu tiên process đang chạy
```

```text
2741 (process ID) old priority 0, new priority 15
```

### `systemctl status` — câu lệnh dùng nhiều nhất của systemd

```bash
systemctl status systemd-journald
```

```text
● systemd-journald.service - Journal Service
     Loaded: loaded (/lib/systemd/system/systemd-journald.service; static)
     Active: active (running) since Fri 2026-10-31 08:01:12 +07; 1h 31min ago
TriggeredBy: ● systemd-journald.socket
   Main PID: 55 (systemd-journal)
     Status: "Processing requests..."
      Tasks: 1 (limit: 9456)
     Memory: 12.1M
     CGroup: /system.slice/systemd-journald.service
             └─55 /lib/systemd/systemd-journald

Oct 31 08:01:12 LEGION systemd-journald[55]: Journal started
```

| Dòng | Đọc gì |
|---|---|
| `●` đầu dòng | Xanh = đang chạy, đỏ = lỗi, trắng = không chạy |
| `Loaded` | Unit file nằm ở đâu; `enabled`/`disabled`/`static` = có tự chạy khi boot không |
| `Active` | **Dòng quan trọng nhất**: `active (running)`, `inactive (dead)`, `failed`, `activating (auto-restart)` |
| `Main PID` | PID của process chính |
| `CGroup` | Mọi process thuộc service này. **cgroup** cũng là nền tảng của container (Module 04) |
| Cuối | Vài dòng log gần nhất — thường đủ để thấy nguyên nhân lỗi |

`systemctl status` tự mở trình xem trang khi đầu ra dài — bấm `q` để thoát, hoặc thêm `--no-pager`.

### Các lệnh `systemctl` điều khiển

```bash
sudo systemctl start   taskhub-demo     # chạy ngay
sudo systemctl stop    taskhub-demo     # SIGTERM → chờ → SIGKILL
sudo systemctl restart taskhub-demo     # stop rồi start — có gián đoạn
sudo systemctl reload  nginx            # đọc lại cấu hình, không dừng process (chỉ khi service hỗ trợ)
sudo systemctl enable --now taskhub-demo
sudo systemctl disable taskhub-demo
systemctl is-active  taskhub-demo       # in "active"/"inactive"/"failed" — hợp để dùng trong script
systemctl is-enabled taskhub-demo
systemctl list-units --type=service --state=running
systemctl list-units --failed
systemctl cat taskhub-demo              # xem unit file systemd đang thực sự dùng
sudo systemctl daemon-reload            # BẮT BUỘC sau khi tạo/sửa unit file
```

- Lệnh làm **thay đổi** trạng thái cần `sudo`; lệnh **xem** thì không.
- `is-active` trả exit code `0` khi service đang chạy → dùng trực tiếp trong script: `if systemctl is-active --quiet nginx; then ...` (Bash ở [bài 06](06-bash-scripting.md)).
- Quên `daemon-reload` sau khi sửa unit file → systemd vẫn dùng bản cũ và in cảnh báo `Warning: The unit file ... changed on disk. Run 'systemctl daemon-reload'`.

### `journalctl` — mức cơ bản

```bash
journalctl -u taskhub-demo              # toàn bộ log của service
journalctl -u taskhub-demo -n 50        # 50 dòng cuối
journalctl -u taskhub-demo -f           # theo dõi trực tiếp (như tail -f), Ctrl+C để thoát
journalctl -u taskhub-demo --since "10 min ago"
journalctl -u taskhub-demo -b --no-pager   # từ lần boot hiện tại, in thẳng ra terminal
```

| Tham số | Ý nghĩa |
|---|---|
| `-u <unit>` | Lọc theo unit |
| `-n <số>` | Số dòng cuối |
| `-f` | Follow — hiện log mới liên tục |
| `--since`, `--until` | Lọc theo thời gian: `"2026-10-31 09:00"`, `"1 hour ago"`, `today` |
| `-b` | Chỉ lần boot hiện tại |
| `--no-pager` | Không mở trình xem trang |

Mọi thứ app in ra `stdout`/`stderr` khi chạy dưới systemd đều vào journal. Lọc theo mức độ (`-p err`), định dạng JSON, dung lượng journal… ở [bài 07](07-logs-monitoring-troubleshooting.md).

> Nếu `journalctl` báo không có quyền xem log, user của bạn cần thuộc nhóm `adm` hoặc `systemd-journal` (kiểm tra bằng lệnh `groups`, đã học ở bài 03), hoặc dùng `sudo journalctl`.

---

## 9. Bài thực hành từng bước

**Lab: Process, signal và systemd** · `[WSL]` + `[Sandbox]` · ~75 phút

Ghi câu trả lời vào `~/devops-lab/01-linux/lab04-answers.md`.

### Bước 1 — Cây process của chính bạn

```bash
echo "PID của shell: $$"
ps -o pid,ppid,stat,cmd -p $$
pstree -ps $$ 2>/dev/null || ps -ef --forest | grep -B3 -A1 " $$ "
```

❓ Cha của shell bạn là process nào? Đi ngược lên đến PID 1 phải qua những process nào?

### Bước 2 — Job control

```bash
sleep 300 &
sleep 400 &
jobs
fg %1            # sau đó bấm Ctrl+Z
jobs             # job 1 giờ ở trạng thái gì?
ps -o pid,stat,cmd -C sleep
bg %1
kill %1 %2
jobs
```

❓ Khi bị `Ctrl+Z`, cột `STAT` của `sleep` là gì? Sau `bg` là gì?

### Bước 3 — Bắt signal và quan sát exit code

Tạo script giả lập một app biết graceful shutdown (cú pháp Bash sẽ học kỹ ở [bài 06](06-bash-scripting.md) — ở đây chỉ cần hiểu `trap` = "khi nhận signal X thì chạy lệnh Y"):

```bash
cd ~/devops-lab/01-linux
cat > fake-app.sh <<'EOF'
#!/bin/bash
trap 'echo "[$(date +%T)] Nhận SIGTERM: đóng kết nối DB, xử lý nốt request..."; sleep 2; echo "Tắt xong."; exit 0' TERM
trap 'echo "[$(date +%T)] Nhận SIGINT (Ctrl+C)"; exit 130' INT
echo "fake-app chạy với PID $$"
while true; do sleep 1; done
EOF
chmod +x fake-app.sh
```

**3a.** Chạy ở foreground, bấm `Ctrl+C`:

```bash
./fake-app.sh
echo "exit code: $?"
```

**3b.** Chạy nền, gửi `SIGTERM`:

```bash
./fake-app.sh &
sleep 1
kill -TERM $!            # $! = PID của lệnh chạy nền gần nhất
wait $!; echo "exit code: $?"
```

**3c.** Chạy nền, gửi `SIGKILL`:

```bash
./fake-app.sh &
sleep 1
kill -KILL $!
wait $!; echo "exit code: $?"
```

❓ Ở 3c, dòng "Nhận SIGTERM..." có xuất hiện không? Exit code là bao nhiêu và vì sao? Nếu đây là app thật đang ghi database, điều gì có thể xảy ra?

### Bước 4 — Tạo một zombie và quan sát

```bash
(sleep 1 & exec sleep 30) &
sleep 2
ps -o pid,ppid,stat,cmd --ppid $!
```

Giải thích dòng lệnh: một subshell chạy `sleep 1` ở nền, rồi **thay ruột chính nó** thành `sleep 30` (`exec`). `sleep 30` không biết mình có con, nên không bao giờ gọi wait. Khi `sleep 1` kết thúc → thành zombie.

❓ Trạng thái của process con là gì? Thử `kill -9` PID của zombie — có biến mất không? Chờ 30 giây rồi chạy lại lệnh `ps` — chuyện gì xảy ra và vì sao?

### Bước 5 — Đọc `top` khi có process ngốn CPU

```bash
yes > /dev/null &        # "yes" in chữ y liên tục — ngốn 1 nhân CPU
top                      # bấm P, rồi 1, quan sát, rồi q
```

❓ Process nào đứng đầu? `%CPU` khoảng bao nhiêu? Bấm `1` thấy gì? Dòng `%Cpu(s)` cột `us` thay đổi thế nào?

Dừng nó đúng cách:

```bash
pgrep -a yes
pkill yes
```

### Bước 6 — Kiểm tra systemd trên WSL

```bash
ps -p 1 -o comm=
```

- In ra **`systemd`** → tiếp tục bước 7.
- In ra **`init`** → WSL của bạn chưa bật systemd. Các bước còn lại và [lab-02](labs/lab-02-java-systemd-service.md) cần systemd.

**Bật systemd (chỉ làm nếu bạn đồng ý — đây là thay đổi cấu hình WSL do bạn tự quyết định):** làm theo hướng dẫn chính thức của [Microsoft Learn](https://learn.microsoft.com/en-us/windows/wsl/systemd). Tóm tắt:

1. `[PowerShell]` kiểm tra `wsl --version` (cần WSL 0.67.6 trở lên; nếu cũ hơn thì `wsl --update`).
2. `[WSL]` mở file cấu hình: `sudo nano /etc/wsl.conf`, thêm (hoặc sửa) thành:

   ```ini
   [boot]
   systemd=true
   ```

3. `[PowerShell]` chạy `wsl --shutdown` để tắt toàn bộ WSL (⚠️ mọi terminal WSL và container Docker đang chạy sẽ bị đóng — lưu công việc trước).
4. Mở lại Ubuntu, chạy lại `ps -p 1 -o comm=`.

### Bước 7 — Khám phá service có sẵn

```bash
systemctl list-units --type=service --state=running --no-pager
systemctl list-units --failed --no-pager
systemctl status systemd-journald --no-pager
systemctl cat systemd-journald | head -20
journalctl -u systemd-journald -n 10 --no-pager
```

❓ Có bao nhiêu service đang chạy? Có service nào `failed` không? Unit file của `systemd-journald` nằm ở thư mục nào, và vì sao nó nằm ở đó chứ không phải `/etc/systemd/system/`?

### Bước 8 — Service đầu tiên của bạn (bản tối giản)

Biến `fake-app.sh` thành service. (Bản đầy đủ với app Java, user riêng, tự khởi động lại nằm ở [lab-02](labs/lab-02-java-systemd-service.md).)

```bash
sudo cp ~/devops-lab/01-linux/fake-app.sh /usr/local/bin/fake-app.sh
sudo tee /etc/systemd/system/fake-app.service > /dev/null <<'EOF'
[Unit]
Description=Fake app for lesson 04

[Service]
ExecStart=/usr/local/bin/fake-app.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl start fake-app
systemctl status fake-app --no-pager
```

Thử nghiệm:

```bash
sudo systemctl stop fake-app
journalctl -u fake-app -n 10 --no-pager           # có thấy dòng "Nhận SIGTERM" không?

sudo systemctl start fake-app
sudo kill -KILL "$(systemctl show -p MainPID --value fake-app)"
sleep 5
systemctl status fake-app --no-pager              # PID có đổi không?
systemctl show -p NRestarts --value fake-app      # đã restart bao nhiêu lần?
```

❓ Sau `systemctl stop`, service có tự khởi động lại không? Sau `kill -KILL` thì sao? Giải thích bằng quy tắc của `Restart=on-failure`.

Dọn dẹp:

```bash
sudo systemctl stop fake-app
sudo rm /etc/systemd/system/fake-app.service /usr/local/bin/fake-app.sh
sudo systemctl daemon-reload
```

### Bước 9 — Commit

```bash
cp ~/devops-lab/01-linux/lab04-answers.md ~/devops-journey/week02/
cd ~/devops-journey && git add week02/ && git commit -m "docs(linux): lab 04 - processes and systemd" && git push
```

---

## 10. Kết quả mong đợi

- **Bước 1:** trên WSL có systemd, cây đi từ `systemd(1)` qua vài process của WSL (`init-systemd`, `SessionLeader`, `Relay`…) rồi tới `bash`. Tên cụ thể có thể khác theo phiên bản WSL.
- **Bước 2:** sau `Ctrl+Z` job ở trạng thái `Stopped`, `STAT` là `T`; sau `bg` là `S` (đang ngủ trong `sleep`).
- **Bước 3:**
  - 3a: in "Nhận SIGINT", exit code `130`.
  - 3b: in "Nhận SIGTERM… Tắt xong.", exit code `0` (vì script chủ động `exit 0`).
  - 3c: **không** in gì, exit code `137` = 128 + 9. `SIGKILL` không bắt được → app không kịp dọn dẹp. Với app thật: giao dịch dở dang, request bị cắt, file có thể bị hỏng.
- **Bước 4:** process con có `STAT` = `Z`, cột CMD hiện `[sleep] <defunct>`. `kill -9` **không** làm nó biến mất (đã chết rồi). Sau 30 giây, `sleep 30` (cha) kết thúc → zombie được PID 1 nhận nuôi và dọn ngay → `ps` không còn thấy.
- **Bước 5:** `yes` đứng đầu với ~100% CPU (tức 100% của **một nhân**). Bấm `1` thấy một nhân gần 100%, các nhân khác rảnh.
- **Bước 7:** unit file của `systemd-journald` nằm ở `/lib/systemd/system/` vì nó được cài bởi gói phần mềm, không phải do quản trị viên viết.
- **Bước 8:** `systemctl stop` → journal có dòng "Nhận SIGTERM", service **không** tự chạy lại. `kill -KILL` → service tự khởi động lại sau ~3 giây với PID mới, `NRestarts` = 1. Lý do: `on-failure` coi chết vì `SIGKILL` là bất thường, còn `systemctl stop` là chủ động.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `System has not been booted with systemd as init system (PID 1). Can't operate.` | WSL chưa bật systemd | Xem mục 9 bước 6 |
| `Failed to start X.service: Unit X.service not found.` | Sai tên, file không nằm trong `/etc/systemd/system/`, hoặc quên `daemon-reload` | `ls /etc/systemd/system/`, `sudo systemctl daemon-reload` |
| `Warning: The unit file ... changed on disk` | Sửa unit file mà chưa nạp lại | `sudo systemctl daemon-reload` |
| Service chết ngay, `status=203/EXEC` | Chương trình trong `ExecStart` không tồn tại, không có quyền thực thi (thiếu `chmod +x`, hoặc user của service không vào được thư mục chứa nó), shebang sai, file có CRLF | Kiểm tra đường dẫn (`which java`), `chmod +x` script, kiểm tra shebang và CRLF ([bài 01](01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp)) |
| `systemctl status` báo `bad-setting`, journal có dòng `Neither a valid executable name nor an absolute path` (hoặc tương tự) | `ExecStart` dùng đường dẫn tương đối có dấu `/` (ví dụ `bin/app.sh`) | Đổi sang đường dẫn tuyệt đối, `daemon-reload` |
| `status=200/CHDIR` | `WorkingDirectory` không tồn tại hoặc user không vào được | Tạo thư mục, kiểm tra quyền ([bài 03](03-permissions-users-groups.md)) |
| `status=217/USER` | User trong `User=` không tồn tại | `id taskhub` để kiểm tra |
| `Start request repeated too quickly` / `start-limit-hit` | App chết liên tục, systemd ngừng thử (mặc định quá 5 lần trong 10 giây) | Sửa lỗi gốc trong log, rồi `sudo systemctl reset-failed X` và start lại. Đặt `RestartSec` vài giây |
| Service Java luôn `failed` sau khi `stop` dù tắt bình thường | JVM thoát với code 143 | Thêm `SuccessExitStatus=143` |
| `kill: (PID) - Operation not permitted` | Process thuộc user khác | Dùng `sudo`, nhưng hỏi lại bản thân: có nên dừng process của người khác không? |
| Process vẫn còn sau `kill` | Process bỏ qua/xử lý chậm `SIGTERM`, hoặc đang ở trạng thái `D` | Chờ vài giây, kiểm tra `STAT`. Nếu `D`: đang kẹt I/O, ngay cả `SIGKILL` cũng phải chờ |
| App chạy bằng `nohup ... &` biến mất sau khi server reboot | `nohup` không phải trình quản lý dịch vụ | Chuyển sang systemd |

---

## 12. Đọc log và xử lý lỗi

### Quy trình khi một service không chạy

```text
1. systemctl status X --no-pager        → Active là gì? exit code / signal là gì? vài dòng log cuối
2. journalctl -u X -n 50 --no-pager     → đọc từ dưới lên, tìm dòng lỗi ĐẦU TIÊN, không phải dòng cuối
3. systemctl cat X                      → unit file systemd đang dùng có đúng như bạn nghĩ?
4. Chạy tay lệnh ExecStart bằng đúng user đó:
   sudo -u taskhub /usr/bin/java -jar /opt/taskhub/app.jar
   → thấy lỗi trực tiếp trên terminal
5. Sửa → daemon-reload (nếu sửa unit file) → restart → quay lại bước 1
```

### Đọc dòng `Active` và `Main process exited`

```text
Active: failed (Result: exit-code) since Fri 2026-10-31 10:02:11 +07; 3s ago
Process: 4120 ExecStart=/opt/taskhub/run.sh (code=exited, status=203/EXEC)
```

- `Result: exit-code` → process thoát với exit code khác 0.
- `status=203/EXEC` → systemd **không chạy được** chương trình. App chưa hề khởi động, nên đừng tìm lỗi trong code — tìm ở đường dẫn và quyền.

```text
Main process exited, code=killed, status=9/KILL
```

- `code=killed` → chết vì signal, ở đây là `SIGKILL`. Ai gửi? Bạn, một script, hay kernel (hết RAM — "OOM killer")? Kiểm tra bằng `journalctl -k | grep -i oom` (bài 07 dạy sâu).

```text
Main process exited, code=exited, status=1/FAILURE
```

- App tự thoát với code 1 → lỗi nằm trong **app**: đọc stack trace Java ở các dòng phía trên.

### Đọc stack trace Java trong journal (làm quen)

```text
java[4410]: Exception in thread "main" java.net.BindException: Address already in use
java[4410]:         at java.base/sun.nio.ch.Net.bind0(Native Method)
java[4410]:         at ...
```

Đọc **dòng đầu tiên** của exception: loại lỗi (`BindException`) + mô tả (`Address already in use`) → port đã bị process khác chiếm → xem mục 5, ví dụ 2. Các dòng `at ...` cho lập trình viên biết lỗi xảy ra ở đâu trong code; với DevOps, thường dòng đầu tiên và dòng `Caused by:` là đủ để xác định hướng điều tra.

Ghi mỗi lần debug service vào `troubleshooting-journal.md` theo mẫu ở [bài 01 mục 12](01-linux-architecture-filesystem.md#12-đọc-thông-báo-lỗi-và-xử-lý).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Chương trình và process khác nhau thế nào? Mở 3 terminal Bash thì có mấy chương trình, mấy process?
2. Giải thích fork và exec bằng lời của bạn. Vì sao gõ `ls` trong Bash xong thì Bash vẫn còn?
3. Zombie là gì? Vì sao `kill -9` không xóa được zombie? Làm sao để dọn?
4. Orphan là gì? PPID của nó trở thành bao nhiêu?
5. `VSZ` và `RSS` khác nhau thế nào? Khi được hỏi "app Java tốn bao nhiêu RAM", bạn nhìn cột nào?
6. Máy 4 nhân có load average `6.0, 5.5, 5.0`. Bạn nhận xét gì? Còn `0.5, 2.0, 4.5` thì sao?
7. `SIGTERM` và `SIGKILL` khác nhau thế nào? Vì sao không nên dùng `kill -9` ngay từ đầu?
8. Một container dừng với exit code `137`. Có những khả năng nào?
9. Vì sao `nohup java -jar app.jar &` không phù hợp cho môi trường production?
10. `systemctl start` và `systemctl enable` khác nhau thế nào?
11. Vì sao không nên sửa unit file trong `/lib/systemd/system/`?
12. Với `Restart=on-failure`, service có tự khởi động lại trong các trường hợp sau không: (a) app thoát code 0, (b) app thoát code 1, (c) bị `kill -9`, (d) `systemctl stop`?
13. Vì sao service Java nên có `SuccessExitStatus=143`?
14. Service báo `status=203/EXEC`. Bạn kiểm tra những gì? Có nên đọc code Java không?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/04-solutions.md](solutions/04-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Top 5.** Viết **một dòng lệnh** in ra 5 process tốn RAM nhất, gồm các cột: PID, user, RSS tính bằng MB (gợi ý: `ps` + `awk` từ [bài 02](02-essential-commands-text.md)), lệnh. Giải thích từng phần của dòng lệnh.

**Bài 2 — Ai là thủ phạm?** Chạy `bash -c 'while true; do :; done' &` hai lần và `sleep 1000 &` một lần. Chỉ dùng `top` (không dùng `ps`), hãy tìm và dừng đúng hai process ngốn CPU mà không đụng tới `sleep`. Viết lại các phím bạn đã bấm trong `top`.

**Bài 3 — Graceful hay không?** Sửa `fake-app.sh` để khi nhận `SIGTERM` nó mất **15 giây** mới tắt xong. Chạy nó bằng một systemd service có `TimeoutStopSec=5`. Chạy `systemctl stop` và đọc journal. Điều gì xảy ra sau 5 giây? Exit status trong journal là gì? Rút ra bài học gì khi cấu hình thời gian chờ cho app thật?

**Bài 4 — Service lỗi cố ý.** Tạo ba unit file lỗi, mỗi cái một lỗi: (a) `ExecStart` dùng đường dẫn tương đối có dấu `/` (ví dụ `ExecStart=bin/fake-app.sh`), (b) `User=` là user không tồn tại, (c) `WorkingDirectory=` trỏ tới thư mục không tồn tại. Với mỗi cái: ghi lại chính xác dòng `status=` và thông báo trong journal, rồi sửa. Đây sẽ là 3 mục trong `troubleshooting-journal.md`.

**Bài 5 — Restart loop.** Tạo service chạy lệnh `/bin/false` (luôn thoát code 1) với `Restart=always` và `RestartSec=100ms`. Chuyện gì xảy ra sau vài giây? Tìm dòng journal cho biết systemd đã bỏ cuộc. Làm sao để service chạy lại được sau khi đã sửa? (Nhớ dọn dẹp sau khi làm.)

**Bài 6 — Zombie trong `[Sandbox]`.** Trong container `ubuntu:22.04`, process số 1 là `bash`. Lặp lại bước 4 nhưng làm cho cha của zombie chết trước. Zombie có được dọn không? So sánh với khi chạy `docker run --rm -it --init ubuntu:22.04 bash` (xem PID 1 là gì). Ghi nhận xét — bạn sẽ gặp lại chủ đề này ở Module 04.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Vẽ được cây process từ PID 1 tới lệnh đang chạy trong terminal và giải thích PPID.
- [ ] Nghe "exit code 137" hoặc "143" là giải thích ngay được nghĩa.
- [ ] Đọc đúng `load average`, `wa`, `avail Mem`, `RES` trong `top`.
- [ ] Luôn gửi `SIGTERM` trước, và giải thích được cho đồng nghiệp vì sao.
- [ ] Tự viết unit file cho một ứng dụng mới không cần chép mẫu, giải thích được từng dòng.
- [ ] Gặp service lỗi, bạn đi theo quy trình 5 bước ở mục 12 thay vì đoán mò.
- [ ] Hoàn thành [lab-02](labs/lab-02-java-systemd-service.md) và Bài tập 4 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) | `Restart=`, `RestartSec=`, `SuccessExitStatus=` — tài liệu gốc | 2026-10-31 |
| [systemd.exec(5) — Process Exit Codes](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html) | Ý nghĩa `200/CHDIR`, `203/EXEC`, `217/USER` | 2026-10-31 |
| [Microsoft Learn — systemd in WSL](https://learn.microsoft.com/en-us/windows/wsl/systemd) | Kiểm tra và bật systemd trên WSL | 2026-10-31 |
| [Spring Boot — Graceful Shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html) | Graceful shutdown bật mặc định, `server.shutdown` | 2026-10-31 |
| [Linux Journey — Processes, Init, Process Utilization](https://labex.io/linuxjourney) | Ôn tập bằng bài ngắn | 2026-10-31 |
| `man ps`, `man top`, `man 7 signal`, `man systemctl`, `man journalctl` (chạy trên máy) | Tra cứu đầy đủ tham số | — |
