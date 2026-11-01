# Lời giải — Bài 04. Processes & systemd

> ⚠️ Chỉ đọc sau khi đã **tự làm** và ghi câu trả lời của bạn. So sánh, tìm chỗ khác biệt, rồi quay lại bài học nếu cần.
> Quay lại bài: [04-processes-systemd.md](../04-processes-systemd.md)

## Mục lục

- [A. Câu hỏi kiểm tra kiến thức (mục 13)](#a-câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [B. Bài tập tự làm (mục 14)](#b-bài-tập-tự-làm-mục-14)
- [C. Câu hỏi sau Lab 02](#c-câu-hỏi-sau-lab-02)

---

## A. Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Chương trình là file nằm trên đĩa; process là chương trình đang chạy, có PID, vùng nhớ, user và file đang mở riêng. Mở 3 terminal Bash: **1 chương trình** (`/usr/bin/bash`), **3 process**.

**2.** *fork*: process tạo một bản sao của chính nó (process con). *exec*: process con thay toàn bộ code đang chạy bằng một chương trình khác, giữ nguyên PID. Gõ `ls`: Bash fork ra con, con exec thành `ls`. Bash (cha) không bị thay thế, chỉ chờ con kết thúc rồi nhận exit code → Bash vẫn còn.

**3.** Zombie là process đã kết thúc nhưng còn một dòng trong bảng process vì cha chưa gọi wait để nhận exit code. `kill -9` gửi signal tới một process — nhưng zombie đã chết, không còn code nào để nhận signal. Cách dọn: làm cho cha gọi wait (sửa bug ở cha), hoặc dừng process cha → zombie được PID 1 nhận nuôi và PID 1 dọn nó.

**4.** Orphan là process mà cha đã chết trong khi nó vẫn chạy. Nó được nhận nuôi, PPID thường trở thành **1** (hoặc một process "subreaper" được chỉ định, ví dụ một số trình quản lý phiên trên desktop/WSL).

**5.** `VSZ` là bộ nhớ ảo process đã xin (gồm cả vùng chưa thực sự dùng, thư viện dùng chung…). `RSS` là RAM vật lý đang thực sự chiếm. Hỏi "app tốn bao nhiêu RAM" → nhìn **`RSS`** (trong `top` là `RES`). App Java thường có `VSZ` rất lớn (vài GB) nhưng `RSS` nhỏ hơn nhiều — đừng hoảng khi thấy `VSZ`.

**6.** Máy 4 nhân:
- `6.0, 5.5, 5.0`: quá tải liên tục trong ít nhất 15 phút (load > số nhân), và đang **tăng dần**. Cần điều tra ngay: process nào ngốn CPU, hay nhiều process đang chờ I/O (`wa` cao)?
- `0.5, 2.0, 4.5`: 15 phút trước rất tải, giờ đã **giảm mạnh** — sự cố đang qua đi hoặc đã qua. Vẫn nên tìm hiểu chuyện gì xảy ra 15 phút trước (log, cron job?).

**7.** `SIGTERM` yêu cầu process dừng, process có thể bắt nó để dọn dẹp (graceful shutdown). `SIGKILL` do kernel thực hiện ngay, process không bắt được, không dọn dẹp được. Dùng `kill -9` ngay sẽ cắt ngang request đang xử lý, để lại giao dịch dở dang, file lock, file tạm, có thể ghi hỏng dữ liệu. Chỉ dùng `SIGKILL` khi `SIGTERM` đã không có tác dụng sau một khoảng chờ hợp lý.

**8.** `137` = 128 + 9 → bị `SIGKILL`. Khả năng:
- Hết bộ nhớ: kernel OOM killer giết process, hoặc container vượt giới hạn RAM được cấp.
- `docker stop` / Kubernetes gửi `SIGTERM` nhưng app không tắt kịp trong thời gian chờ → bị `SIGKILL`.
- Có người/script chạy `kill -9` hoặc `docker kill`.

**9.** `nohup ... &` không tự khởi động lại khi app chết, không tự chạy khi server reboot, không có chỗ quản lý log tập trung (chỉ có `nohup.out`), dễ chạy nhầm bằng root, khó biết app đang chạy hay không, và không có cách dừng chuẩn hóa.

**10.** `start` chạy service ngay bây giờ, không ảnh hưởng lần boot sau. `enable` đánh dấu service tự chạy khi boot (tạo symlink vào thư mục `.wants` của target), không chạy ngay. `enable --now` làm cả hai.

**11.** File trong `/lib/systemd/system/` thuộc về gói phần mềm. Lần `apt upgrade` sau sẽ ghi đè, mất thay đổi của bạn. Muốn tùy chỉnh: đặt file cùng tên trong `/etc/systemd/system/` (ưu tiên cao hơn), hoặc dùng `systemctl edit <service>` để tạo file ghi đè một phần (drop-in) — 🟨 sẽ gặp khi làm thật.

**12.** Với `Restart=on-failure`:
- (a) thoát code 0 → **không** restart (thoát bình thường).
- (b) thoát code 1 → **có**.
- (c) bị `kill -9` → **có** (chết vì signal không thuộc nhóm "sạch" SIGHUP/SIGINT/SIGTERM/SIGPIPE).
- (d) `systemctl stop` → **không** (dừng chủ động).

**13.** Khi nhận `SIGTERM`, JVM chạy shutdown hook rồi thoát với exit code 143. systemd mặc định coi 143 là một exit code khác 0 → đánh dấu service `failed` sau mỗi lần stop bình thường. Khai báo `SuccessExitStatus=143` để systemd coi đó là thoát thành công: trạng thái gọn gàng, không báo động giả trong hệ thống giám sát.

**14.** `203/EXEC` nghĩa là systemd **không exec được** chương trình — app chưa chạy dòng code nào, nên **không cần đọc code Java**. Kiểm tra: đường dẫn trong `ExecStart` có tồn tại không (`ls -l`), file có quyền thực thi không, user của service có vào được các thư mục cha không, shebang của script có đúng không, script có bị CRLF không.

---

## B. Bài tập tự làm (mục 14)

### Bài 1 — Top 5 process tốn RAM

```bash
ps -eo pid,user,rss,comm --sort=-rss | head -6 \
  | awk 'NR==1 {printf "%-8s %-12s %10s  %s\n", "PID", "USER", "RSS_MB", "COMMAND"; next}
         {printf "%-8s %-12s %10.1f  %s\n", $1, $2, $3/1024, $4}'
```

```text
PID      USER             RSS_MB  COMMAND
2741     phuong            326.7  java
55       root               15.5  systemd-journal
1        root               11.1  systemd
```

Giải thích:

- `ps -eo pid,user,rss,comm`: mọi process, chỉ lấy 4 cột. `comm` là tên chương trình (một từ, không có dấu cách) → `awk` tách cột dễ dàng. Nếu dùng `args`/`cmd` (có dấu cách) thì cột 4 trở đi bị tách thành nhiều trường.
- `--sort=-rss`: sắp giảm dần theo RSS.
- `head -6`: dòng tiêu đề + 5 dòng.
- `awk`: dòng 1 (`NR==1`) in tiêu đề mới rồi `next` sang dòng sau; các dòng khác chia cột 3 (KB) cho 1024 → MB, in 1 chữ số thập phân.

### Bài 2 — Tìm thủ phạm bằng `top`

1. `top` → bấm `P` (sắp theo CPU): hai process `bash` đứng đầu, mỗi cái ~100%.
2. (Tùy chọn) bấm `c` để hiện dòng lệnh đầy đủ, phân biệt với `bash` của shell bạn.
3. Bấm `k` → `top` hỏi `PID to signal/kill [default pid = ...]` → gõ PID của `bash` thứ nhất → Enter → hỏi signal, mặc định `15` (SIGTERM) → Enter.
4. Lặp lại cho process thứ hai.
5. `q` thoát. Kiểm tra lại: `jobs` hoặc `pgrep -a sleep` → `sleep 1000` vẫn còn.

Mẹo: trong `top`, bấm `o` rồi gõ `COMMAND=bash` để lọc chỉ hiện process tên `bash`.

### Bài 3 — Graceful shutdown bị cắt ngang

Sửa `trap` của `fake-app.sh`:

```bash
trap 'echo "Nhận SIGTERM, cần 15 giây để tắt..."; sleep 15; echo "Tắt xong."; exit 0' TERM
```

Unit file thêm `TimeoutStopSec=5`. Sau `systemctl stop`, journal có dạng:

```text
fake-app.sh[8102]: Nhận SIGTERM, cần 15 giây để tắt...
systemd[1]: fake-app.service: State 'stop-sigterm' timed out. Killing.
systemd[1]: fake-app.service: Killing process 8102 (fake-app.sh) with signal SIGKILL.
systemd[1]: fake-app.service: Main process exited, code=killed, status=9/KILL
systemd[1]: fake-app.service: Failed with result 'timeout'.
```

Dòng "Tắt xong." **không bao giờ xuất hiện**: sau 5 giây systemd hết kiên nhẫn và gửi `SIGKILL`.

Bài học: thời gian chờ của **trình quản lý** (`TimeoutStopSec`, `docker stop -t`, `terminationGracePeriodSeconds` của Kubernetes) phải **lớn hơn** thời gian app cần để tắt nhẹ nhàng (ví dụ `spring.lifecycle.timeout-per-shutdown-phase` của Spring Boot). Nếu không, graceful shutdown chỉ có trên giấy.

### Bài 4 — Ba service lỗi

| Lỗi | Triệu chứng điển hình | Sửa |
|---|---|---|
| (a) `ExecStart=bin/fake-app.sh` | Unit không nạp được: `systemctl status` báo `bad-setting`, journal có thông báo đường dẫn không hợp lệ (không phải tên trần, không phải đường dẫn tuyệt đối). Service chưa hề được khởi động | Đường dẫn tuyệt đối `/usr/local/bin/fake-app.sh`, `daemon-reload` |
| (b) `User=khongtontai` | `status=217/USER`, journal: `Failed to determine user credentials: No such process` | Tạo user hoặc sửa tên |
| (c) `WorkingDirectory=/opt/khongtontai` | `status=200/CHDIR`, journal: `Changing to the requested working directory failed: No such file or directory` | Tạo thư mục, kiểm tra quyền |

Câu chữ chính xác trong journal có thể khác chút theo phiên bản systemd — điều quan trọng là bạn **ghi lại đúng những gì máy bạn in ra**. Mỗi lỗi là một mục `troubleshooting-journal.md`.

### Bài 5 — Restart loop

```ini
[Service]
ExecStart=/bin/false
Restart=always
RestartSec=100ms
```

Sau khoảng 1 giây, systemd đã thử khởi động 5 lần trong vòng 10 giây (giới hạn mặc định `StartLimitBurst=5`, `StartLimitIntervalSec=10s`) và bỏ cuộc:

```text
systemd[1]: loop-test.service: Start request repeated too quickly.
systemd[1]: loop-test.service: Failed with result 'exit-code'.
```

`systemctl status` hiện `failed (Result: start-limit-hit)` hoặc tương tự. Sau khi sửa lỗi, phải `sudo systemctl reset-failed loop-test` rồi mới `start` lại được.

Bài học: `RestartSec` vài giây vừa giảm áp lực lên hệ thống, vừa tránh chạm giới hạn quá nhanh khi app lỗi tạm thời (ví dụ database chưa sẵn sàng).

Dọn dẹp: `sudo systemctl disable --now loop-test; sudo rm /etc/systemd/system/loop-test.service; sudo systemctl daemon-reload; sudo systemctl reset-failed`.

### Bài 6 — Zombie trong container

Trong `docker run --rm -it ubuntu:22.04 bash`, PID 1 là `bash`.

Tạo zombie mà cha chết trước:

```bash
(sleep 1 & exec sleep 10) &
sleep 2; ps -o pid,ppid,stat,cmd -e     # thấy [sleep] <defunct> với PPID = PID của "sleep 10"
sleep 10; ps -o pid,ppid,stat,cmd -e    # sau khi "sleep 10" chết
```

Thông thường bạn sẽ thấy zombie **được dọn**: khi cha chết, zombie được nhận nuôi bởi PID 1, và Bash có xử lý tín hiệu báo con kết thúc (`SIGCHLD`) bằng cách gọi wait. **Nhưng** nếu PID 1 là một chương trình không được viết để làm init — ví dụ `java -jar app.jar` chạy trực tiếp làm process chính của container — nó sẽ **không** dọn zombie mồ côi, và zombie tích tụ dần (mỗi cái chiếm một PID).

Với `docker run --rm -it --init ubuntu:22.04 bash`: `ps -o pid,cmd -p 1` cho thấy PID 1 là một init tối giản (`docker-init`, dựa trên `tini`), còn `bash` có PID khác. Init này chỉ làm hai việc: chuyển tiếp signal cho process chính và dọn zombie.

Nhận xét cần ghi: trong container, process chính chính là PID 1, nên nó gánh trách nhiệm của systemd — Module 04 sẽ quay lại vấn đề này cùng với cách `docker stop` gửi `SIGTERM` tới PID 1.

---

## C. Câu hỏi sau Lab 02

**1.** Nếu app lỗi khi chạy tay, nó chắc chắn lỗi dưới systemd. Chạy tay cho thấy lỗi trực tiếp trên terminal, loại bỏ các biến số do systemd thêm vào (user, thư mục làm việc, biến môi trường). Khi app chạy tay được mà không chạy được dưới systemd → lỗi khoanh vùng ở đúng những khác biệt đó.

**2.** Không có `User=`, service chạy bằng **root**. Nếu app có lỗ hổng (ví dụ cho phép thực thi lệnh từ xa), kẻ tấn công có toàn quyền trên server: đọc mọi bí mật, cài mã độc, xóa dữ liệu.

**3.** `systemctl restart` là thao tác chủ động: dừng (SIGTERM) rồi khởi động lại ngay, không quan tâm app có đang khỏe hay không. `Restart=on-failure` là phản ứng tự động của systemd **sau khi** app đã chết bất thường, có chờ `RestartSec` và có giới hạn số lần.

**4.** Sửa `APP_PORT=9090` trong `/etc/taskhub-demo.env`, rồi `sudo systemctl restart taskhub-demo`. **Không cần** `daemon-reload` vì unit file không đổi — file môi trường được đọc mỗi lần service khởi động. (Chỉ cần `daemon-reload` khi sửa chính file `.service`.)

**5.**

| Tiêu chí | `nohup java -jar app.jar &` | systemd service |
|---|---|---|
| Tự chạy khi boot | Không | Có (`enable`) |
| Tự khởi động lại khi chết | Không | Có (`Restart=on-failure`) |
| Log | File `nohup.out` ở đâu đó, không xoay vòng | Journal tập trung, lọc được theo thời gian/service |
| Bảo mật | Chạy bằng user đang đăng nhập (hay bị chạy bằng root) | User riêng, quyền tối thiểu |

**6.** Docker (Docker Engine) đóng vai **systemd**: khởi động process, theo dõi nó, khởi động lại theo chính sách `--restart`, thu stdout/stderr thành log (`docker logs` ≈ `journalctl -u`). Image đóng vai thư mục `/opt/taskhub` + JDK; biến môi trường truyền bằng `-e`/`--env-file` ≈ `EnvironmentFile`.
