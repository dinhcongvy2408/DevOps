# Break-fix Linux #1 — Ca trực đêm

> ⏱️ 60–120 phút · Môi trường: `[Sandbox]` · Kiến thức cần có: bài [01](../../01-linux-architecture-filesystem.md) → [07](../../07-logs-monitoring-troubleshooting.md)
> Lời giải: [solutions/break-fix-01-solution.md](../../solutions/break-fix-01-solution.md) — **chỉ mở khi đã hoàn thành hoặc đã bị kẹt quá 30 phút sau khi xem hết gợi ý.**

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
- [2. Khởi tạo môi trường](#2-khởi-tạo-môi-trường)
- [3. Các ticket](#3-các-ticket)
- [4. Luật chơi](#4-luật-chơi)
- [5. Sản phẩm phải nộp](#5-sản-phẩm-phải-nộp)
- [6. Gợi ý](#6-gợi-ý)

---

## 1. Bối cảnh

Bạn là DevOps Engineer đang trực ca. Lúc 02:00 server `taskhub-prod-01` được khởi động lại sau đợt bảo trì. Người trực ca trước đã "chỉnh vài thứ" rồi đi ngủ, không để lại ghi chú nào. Giờ là 07:30 sáng, hệ thống ticket có 2 việc đang chờ bạn.

Server là một container Ubuntu 22.04 — bạn có quyền root, nhưng **không có systemd** (giống nhiều container thật). Mọi thứ bạn cần đều quan sát được bằng các lệnh đã học.

---

## 2. Khởi tạo môi trường

Trong WSL:

```bash
cd ~/devops-lab/01-linux
# Copy thư mục lab từ giáo trình về (đổi đường dẫn cho đúng nơi bạn lưu DEVOPS-LEARNING)
cp -r /mnt/d/HocDepOps/DEVOPS-LEARNING/01-LINUX/labs/break-fix-01 .
cd break-fix-01
sed -i 's/\r$//' setup.sh          # phòng trường hợp file bị đổi sang CRLF khi copy từ Windows
docker run --rm -it --name breakfix01 -v "$PWD":/lab ubuntu:22.04 bash
```

Bên trong container:

```bash
bash /lab/setup.sh
```

Chờ khoảng 1 phút cho đến khi thấy thông báo `Môi trường break-fix đã sẵn sàng`.

> - Cờ `--rm`: khi bạn `exit`, container và mọi thay đổi **bị xóa sạch**. Làm lại từ đầu chỉ cần chạy lại 2 lệnh trên.
> - Muốn mở thêm terminal vào cùng container (ví dụ để chạy `top` song song): mở terminal WSL khác và gõ `docker exec -it breakfix01 bash`.
> - Script tự kiểm tra và **từ chối chạy** nếu không ở trong container, nên không thể vô tình làm hỏng WSL của bạn.
> - ⚠️ Môi trường có một process ngốn 100% một nhân CPU cho đến khi bạn xử lý xong ticket #1043, hoặc thoát container. Quạt laptop có thể quay mạnh — đó là một phần của bài.

Kiểm tra tiến độ bất cứ lúc nào:

```bash
verify
```

---

## 3. Các ticket

### 🎫 Ticket #1042 — P1 — taskhub không khởi động sau bảo trì

> **Người báo:** Team QA
> **Mô tả:** Sau đợt bảo trì lúc 02:00, ứng dụng taskhub không chạy. Theo tài liệu vận hành, khởi động ứng dụng bằng lệnh:
>
> ```bash
> /opt/taskhub/bin/start.sh
> ```
>
> Ca trước có chỉnh sửa một số file trên laptop cá nhân rồi copy lên server.
> **Kết quả mong đợi:** chạy `start.sh` in ra `taskhub is up.` và log của ứng dụng có dòng `taskhub started` của hôm nay.

### 🎫 Ticket #1043 — P2 — CPU cao bất thường

> **Người báo:** Hệ thống monitoring (tự động)
> **Mô tả:** CPU của `taskhub-prod-01` tăng cao liên tục từ khoảng 02:00, trước cả khi ai đó đụng vào ứng dụng. Không ai trong team nhớ đã cài thêm gì.
> **Kết quả mong đợi:** xác định process gây ra, xử lý **triệt để** (không tự chạy lại sau vài giây), và giải thích nó là gì.

---

## 4. Luật chơi

1. **Không sửa** `/opt/taskhub/bin/taskhub-app` — đó là "ứng dụng của team dev". Bạn sửa **môi trường xung quanh** nó (quyền, cấu hình, file, process).
2. **Không** đọc `/lab/setup.sh` và `/usr/local/bin/verify` — chúng chứa đáp án.
3. **Không dùng AI.** Được dùng: `man`, `--help`, các bài học trong giáo trình.
4. **Quan sát trước khi sửa.** Mỗi thay đổi phải có lý do bạn ghi lại được.
5. Không có lời giải "tắt" như `chmod -R 777 /` — người chấm sẽ hỏi bạn vì sao chọn quyền đó. Hãy cấp **quyền tối thiểu cần thiết**.

---

## 5. Sản phẩm phải nộp

Tạo file `~/devops-journey/week03/break-fix-01.md` gồm:

1. **Timeline**: mỗi lỗi bạn gặp theo đúng thứ tự xuất hiện.
2. Với **mỗi lỗi**, theo mẫu nhật ký debug:

   ```markdown
   ### Lỗi N: <tên ngắn>
   - Triệu chứng (dán nguyên thông báo lỗi):
   - Giả thuyết:
   - Lệnh quan sát đã dùng và kết quả:
   - Nguyên nhân gốc:
   - Cách sửa (lệnh cụ thể):
   - Cách phòng tránh lần sau:
   ```

3. Kết quả `verify` cuối cùng (dán vào).
4. Một đoạn ngắn: **lỗi nào khó tìm nhất và vì sao?**

> Bạn phải copy nhật ký ra trước khi `exit` container — sau `exit` mọi thứ bên trong bị xóa. Cách đơn giản: viết nhật ký trong WSL (VS Code) song song, hoặc lưu vào `/lab` (thư mục này được gắn từ WSL nên còn lại sau khi thoát).

---

## 6. Gợi ý

Chỉ mở từng cấp khi đã thử ít nhất 15 phút ở cấp trước.

<details>
<summary>💡 Gợi ý cấp 1 — Hướng tiếp cận</summary>

- Ticket #1042 có **nhiều lỗi nối tiếp nhau**: sửa xong một lỗi, chạy lại `start.sh` sẽ thấy lỗi tiếp theo. Đừng nản — đó chính là trải nghiệm thật.
- Với mỗi lỗi: **đọc trọn** thông báo theo cấu trúc `chương trình: đối tượng: mô tả` (bài 01, mục 12).
- Ticket #1043: bắt đầu bằng checklist 60 giây (bài 07, mục 4.12).
- Đọc chính file `taskhub-app` để hiểu ứng dụng **cần gì** từ môi trường (được phép đọc, chỉ không được sửa).

</details>

<details>
<summary>💡 Gợi ý cấp 2 — Lệnh nên dùng</summary>

- `ls -l`, `file`, `cat -A` cho file script có vấn đề lạ.
- `ls /etc | grep -i taskhub`, `find / -name "*taskhub*" -not -path "/proc/*" 2>/dev/null` khi không tìm thấy thứ gì đó.
- `runuser -u taskhub -- <lệnh>` để thử một thao tác **với quyền của user taskhub**.
- `du -h --max-depth=1`, `du -ah | sort -h | tail`, `find -size +100M` — nhớ rằng `ls` mặc định **không hiện** thư mục bắt đầu bằng dấu chấm.
- `top` (nhấn `c`), `ps -ef --forest`, `ps -o pid,ppid,user,cmd -p <PID>`, `ls -l /proc/<PID>/exe`.

</details>

<details>
<summary>💡 Gợi ý cấp 3 — Gần như đáp án</summary>

- Ticket #1042 có 5 lỗi: (1) quyền thực thi + kiểu xuống dòng của `start.sh`, (2) ứng dụng tìm cấu hình ở một đường dẫn, nhưng file nằm chỗ khác, (3) trong file cấu hình có một tên biến bị gõ sai, (4) chủ sở hữu của **cả thư mục lẫn file** log, (5) một file rất lớn trong thư mục **ẩn** dưới `/var/lib/taskhub`.
- Ticket #1043: process ngốn CPU có một **tiến trình cha** liên tục bật lại nó. Kill con trước thì nó sống lại sau 5 giây. Tìm **PPID** của nó.

</details>
