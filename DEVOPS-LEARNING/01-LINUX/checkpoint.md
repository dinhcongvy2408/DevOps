# Checkpoint Module 01 — Linux & System Administration

> ⏱️ Tổng ~4 giờ (có thể chia 2 buổi) · Làm vào cuối tuần 3
> Lời giải: [solutions/checkpoint-solutions.md](solutions/checkpoint-solutions.md) — **chỉ mở sau khi đã nộp bài cho chính mình** (commit vào repo).

## Mục lục

- [Quy tắc](#quy-tắc)
- [Phần A — Lý thuyết (45 phút)](#phần-a--lý-thuyết-45-phút)
- [Phần B — Thực hành (90 phút)](#phần-b--thực-hành-90-phút)
- [Phần C — Break-fix (90 phút)](#phần-c--break-fix-90-phút)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [Nếu chưa đạt](#nếu-chưa-đạt)

---

## Quy tắc

1. **Không dùng AI và không xem lời giải** trong lúc làm.
2. **Được phép**: `man`, `--help`, tài liệu chính thức (Ubuntu docs), các bài học trong module này.
3. Tự bấm giờ cho từng phần. Hết giờ thì dừng và ghi lại mình đang ở đâu — đó cũng là dữ liệu đánh giá.
4. Nộp bài: tạo thư mục `~/devops-journey/week03/checkpoint/` gồm `part-a.md`, `part-b/` (script + ghi chú), `part-c.md` (nhật ký debug). Commit **trước** khi mở lời giải.

---

## Phần A — Lý thuyết (45 phút)

Trả lời ngắn gọn bằng lời của bạn (2–5 câu mỗi câu). Mục tiêu là giải thích **bản chất**, không phải chép định nghĩa.

1. Khi bạn gõ `cat /etc/hostname` trong terminal, mô tả vai trò của terminal, shell, kernel và system call trong quá trình đó.
2. Bạn SSH vào một server lạ. Kể 3 lệnh đầu tiên bạn chạy để biết đây là hệ thống gì, và mỗi lệnh cho bạn biết điều gì.
3. Cấu hình, log, dữ liệu ứng dụng và phần mềm tự cài thủ công thường nằm ở những thư mục nào? Vì sao biết điều này giúp debug nhanh hơn?
4. Giải thích ý nghĩa đầy đủ của `drwxr-x--- 2 taskhub adm 4096 ... /var/log/taskhub`. User `phuong` (không thuộc group `adm`) có `cd` vào được không? User trong group `adm` có tạo file mới trong đó được không?
5. Vì sao root vẫn nhận `Permission denied` khi chạy một script có quyền `644`?
6. Bạn vừa thêm user `phuong` vào group `docker` bằng `usermod -aG docker phuong`, nhưng `docker ps` vẫn báo không có quyền. Vì sao? Cách khắc phục?
7. `SIGTERM` và `SIGKILL` khác nhau thế nào? Vì sao nên thử `SIGTERM` trước? Khi nào một process "không kill được" bằng `kill -9`?
8. `systemctl start` và `systemctl enable` khác nhau thế nào? Một service cần cả hai trong trường hợp nào?
9. `apt update` và `apt upgrade` làm gì khác nhau? Vì sao trên production không nên chạy `apt upgrade` tùy tiện?
10. Trong SSH key-based authentication, public key và private key nằm ở đâu, ai giữ cái nào? Vì sao `sshd` từ chối key khi thư mục `~/.ssh` có quyền `777`?
11. Trong Bash, `set -euo pipefail` gồm những tùy chọn nào, mỗi cái để làm gì? Vì sao nên viết `"$file"` thay vì `$file`?
12. Biến môi trường được export trong `~/.bashrc` của bạn có tồn tại khi: (a) chạy script qua `sudo`, (b) chạy bằng cron, (c) chạy bằng systemd service? Giải thích.
13. Viết dòng crontab chạy `/opt/taskhub/bin/backup.sh` lúc 02:30 mỗi ngày và ghi cả stdout lẫn stderr vào `/var/log/taskhub/backup.log`. Nêu 2 lý do phổ biến khiến một script chạy tay được nhưng chạy bằng cron thì lỗi.
14. Máy 2 nhân có load average `5.10, 4.80, 4.20`, `top` hiện `85.0 wa`. Bạn kết luận gì và làm gì tiếp theo?
15. Ứng dụng Java bị chết lúc 03:00, log ứng dụng dừng đột ngột không có dòng lỗi nào. Nêu giả thuyết hàng đầu và 2 lệnh để xác nhận.

---

## Phần B — Thực hành (90 phút)

### Môi trường

Làm trong `[Sandbox]` có cron:

```bash
mkdir -p ~/devops-journey/week03/checkpoint/part-b
cd ~/devops-journey/week03/checkpoint/part-b
docker run --rm -it -v "$PWD":/work ubuntu:22.04 bash
# trong container:
apt-get update && apt-get install -y cron procps nano
service cron start
```

Viết script trong `/work` (thư mục này được gắn từ WSL, nên còn lại sau khi thoát container).

### Đề bài: `disk-guard.sh`

Team vận hành cần một script cảnh báo sớm khi ổ đĩa sắp đầy. Viết `/work/disk-guard.sh` đáp ứng:

1. Kiểm tra **mọi filesystem thật** (bỏ qua `tmpfs`, `devtmpfs`, `overlay`, `squashfs`).
2. Ngưỡng cảnh báo nhận từ **tham số thứ nhất**, mặc định `80` (đơn vị %). Nếu tham số không phải số nguyên từ 1–99 → in hướng dẫn sử dụng ra **stderr** và thoát với exit code `2`.
3. Với mỗi filesystem có `Use%` **lớn hơn hoặc bằng** ngưỡng: ghi một dòng vào file log theo định dạng:

   ```text
   2026-11-15T02:30:00+00:00 WARN disk-guard: /data at 91% (threshold 80%)
   ```

4. Đồng thời kiểm tra **inode**: nếu `IUse%` ≥ ngưỡng thì ghi dòng `WARN ... inodes at N%`.
5. Đường dẫn file log lấy từ biến môi trường `DISK_GUARD_LOG`, mặc định `/var/log/disk-guard.log`.
6. Exit code: `0` nếu không có cảnh báo nào, `1` nếu có ít nhất một cảnh báo, `2` nếu tham số sai.
7. Script phải chạy đúng khi được gọi từ **bất kỳ thư mục nào** và **bởi cron** (môi trường tối giản).
8. Lập lịch chạy mỗi 10 phút bằng cron với ngưỡng 85, và kiểm chứng được là cron **thực sự đã chạy** nó.

### Kiểm thử bắt buộc

Ghi lại lệnh và kết quả vào `part-b/test-results.md`:

| # | Kiểm thử | Kết quả mong đợi |
|---|---|---|
| 1 | `./disk-guard.sh abc` | Hướng dẫn sử dụng trên stderr, `echo $?` → `2` |
| 2 | `./disk-guard.sh 99` | Không cảnh báo (trừ khi ổ thật sự gần đầy), exit `0` |
| 3 | `./disk-guard.sh 1` | Ít nhất 1 dòng WARN trong log, exit `1` |
| 4 | `DISK_GUARD_LOG=/tmp/dg.log ./disk-guard.sh 1` | Log ghi vào `/tmp/dg.log` |
| 5 | `cd / && /work/disk-guard.sh 1` | Chạy đúng từ thư mục khác |
| 6 | Chạy bằng cron | Có dòng trong log do cron tạo ra; chỉ ra bằng chứng cron đã chạy |

### Yêu cầu chất lượng

- Có `set -euo pipefail` (hoặc giải thích vì sao không dùng một phần nào đó).
- Biến luôn được đặt trong nháy kép.
- Có comment ngắn giải thích từng khối.
- Không hard-code tên ổ đĩa.

---

## Phần C — Break-fix (90 phút)

### Khởi tạo

```bash
cd ~/devops-lab/01-linux
cp -r /mnt/d/HocDepOps/DEVOPS-LEARNING/01-LINUX/labs/checkpoint .
cd checkpoint
sed -i 's/\r$//' setup.sh
docker run --rm -it --name checkpoint01 --cap-add SYS_PTRACE -v "$PWD":/lab ubuntu:22.04 bash
```

> `--cap-add SYS_PTRACE`: mặc định Docker bỏ quyền này, nên root trong container **không** đọc được `/proc/<PID>/fd` và `/proc/<PID>/environ` của process thuộc user khác (`ls` báo `cannot read symbolic link ... Permission denied`). Trên server thật, root đọc được. Thêm cờ này để môi trường giống server thật hơn.

Trong container:

```bash
bash /lab/setup.sh
exec bash          # bắt buộc: nạp lại cấu hình shell của root
verify-checkpoint  # kiểm tra tiến độ bất cứ lúc nào
```

Mở thêm terminal vào cùng container: `docker exec -it checkpoint01 bash`.

### Bối cảnh

Server `taskhub-prod-02` có user `deploy` dành cho pipeline triển khai tự động. Pipeline cần: SSH vào bằng key → chạy `sudo /opt/taskhub/bin/restart.sh` để khởi động lại ứng dụng. Ngoài ra cron chạy backup mỗi phút (để demo). Từ sáng nay mọi thứ đều hỏng.

Private key của pipeline được đặt sẵn ở `/root/.ssh/deploy_ed25519` để bạn thử:

```bash
ssh -i /root/.ssh/deploy_ed25519 deploy@localhost
```

### Các ticket

| Ticket | Mô tả | Kết quả mong đợi |
|---|---|---|
| 🎫 #2001 | Pipeline báo `Permission denied (publickey)` khi SSH vào bằng user `deploy`. Key không hề thay đổi. | SSH bằng key thành công |
| 🎫 #2002 | Đăng nhập được rồi nhưng `sudo /opt/taskhub/bin/restart.sh` đòi mật khẩu (deploy không có mật khẩu). Sau khi sửa, script lại báo thiếu biến môi trường — dù `echo $TASKHUB_DB_URL` trong shell của deploy vẫn ra giá trị. | `deploy` chạy được `sudo /opt/taskhub/bin/restart.sh` và in ra `taskhub restarted` |
| 🎫 #2003 | Không có file backup mới nào trong `/var/backups/taskhub`. Admin chạy tay `/opt/taskhub/bin/backup.sh` bằng root thì vẫn chạy bình thường. | Cron tự tạo được backup mỗi phút |
| 🎫 #2004 | Từ sáng nay `/var/log/taskhub/app.log` biến mất. Một đồng nghiệp đã tạo lại file nhưng file vẫn rỗng, không có heartbeat nào, dù process vẫn chạy. | `app.log` có heartbeat mới mỗi 5 giây |

### Luật chơi

- **Không sửa** `/opt/taskhub/bin/taskhub-app`.
- **Không đọc** `/lab/setup.sh` và `/usr/local/bin/verify-checkpoint`.
- Mọi thay đổi quyền phải theo nguyên tắc **tối thiểu cần thiết**.
- Sửa sudoers **chỉ bằng `visudo`**.
- Ghi nhật ký debug cho **từng ticket** theo mẫu của [break-fix #1](labs/break-fix-01/README.md#5-sản-phẩm-phải-nộp), lưu vào `/lab/part-c.md` để còn lại sau khi thoát.

---

## Tiêu chí đạt

| Phần | Đạt khi | Trọng số |
|---|---|---|
| A | ≥ 12/15 câu đúng **bản chất** (tự chấm theo lời giải, trung thực) | 30% |
| B | Qua cả 6 kiểm thử + đủ yêu cầu chất lượng, trong 90 phút | 35% |
| C | `verify-checkpoint` đạt 6/6 trong 90 phút **và** nhật ký debug nêu được **cách tìm ra** từng lỗi | 35% |

**Đạt Checkpoint** khi đạt cả 3 phần. Đạt Checkpoint → tick vào [checklist module](README.md#5-checklist-hoàn-thành-module) và cập nhật [ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#linux).

---

## Nếu chưa đạt

Không chuyển sang Module 02 ngay (xem [quy tắc khi chậm tiến độ](../00-ROADMAP/weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ)):

| Sai ở | Ôn lại |
|---|---|
| Câu A1–A3 | [Bài 01](01-linux-architecture-filesystem.md) |
| Câu A4–A6, ticket #2001 | [Bài 03](03-permissions-users-groups.md) |
| Câu A7–A8, ticket #2004 | [Bài 04](04-processes-systemd.md), [bài 07 mục 4.9](07-logs-monitoring-troubleshooting.md#49--vì-sao-df-báo-đầy-mà-du-không-thấy) |
| Câu A9–A10 | [Bài 05](05-packages-ssh.md) |
| Câu A11–A12, ticket #2002, Phần B | [Bài 06](06-bash-scripting.md) |
| Câu A13, ticket #2003 | [Bài 08](08-cron-scheduling.md) |
| Câu A14–A15 | [Bài 07](07-logs-monitoring-troubleshooting.md) |

Ôn xong 2–3 ngày rồi làm lại phần chưa đạt (Phần C: chạy lại `setup.sh` sẽ có môi trường mới).
