# Module 01 — Linux & System Administration

> Tuần 1–3 · ~48 giờ · Mức độ: 🟥 Bắt buộc — đây là nền móng của mọi thứ phía sau.

## Mục lục

- [1. Vì sao học Linux đầu tiên?](#1-vì-sao-học-linux-đầu-tiên)
- [2. Môi trường thực hành](#2-môi-trường-thực-hành)
- [3. Thứ tự bài học](#3-thứ-tự-bài-học)
- [4. Lab bắt buộc và break-fix](#4-lab-bắt-buộc-và-break-fix)
- [5. Checklist hoàn thành module](#5-checklist-hoàn-thành-module)
- [6. Nguồn học](#6-nguồn-học)

---

## 1. Vì sao học Linux đầu tiên?

Gần như mọi thứ DevOps Engineer chạm vào đều chạy trên Linux:

- Server EC2 trên AWS → Linux.
- Docker container → thực chất là **process Linux** bị cô lập.
- Kubernetes node → Linux.
- GitHub Actions runner → mặc định là Ubuntu.

Khi có sự cố lúc 2 giờ sáng, bạn sẽ không có giao diện đồ họa. Bạn chỉ có **terminal, log và kiến thức của mình**. Module này rèn đúng những thứ đó.

---

## 2. Môi trường thực hành

Module dùng 2 môi trường, mỗi bài ghi rõ lệnh chạy ở đâu:

| Nhãn | Môi trường | Dùng cho |
|---|---|---|
| `[WSL]` | Ubuntu 24.04 trên WSL của bạn | Phần lớn bài học |
| `[Sandbox]` | Container Ubuntu dùng xong bỏ: `docker run --rm -it ubuntu:22.04 bash` | Thử những thứ có thể làm hỏng hệ thống (xóa file hệ thống, đổi quyền, tạo/xóa user) và các bài break-fix |
| `[PowerShell]` | Windows PowerShell | Rất ít — chỉ khi cần thao tác với WSL từ Windows |

> **Vì sao cần `[Sandbox]`?** Container này bị xóa ngay khi bạn gõ `exit` (nhờ cờ `--rm`). Làm hỏng gì trong đó cũng không ảnh hưởng đến WSL hay Windows. Hãy dùng nó thoải mái để thử nghiệm.

**Thư mục làm việc chung** cho mọi bài lab trong WSL:

```bash
mkdir -p ~/devops-lab/01-linux
cd ~/devops-lab/01-linux
```

> ⚠️ Luôn làm việc trong thư mục home của WSL (`~`), **không** làm trong `/mnt/c/...`. Lý do ở [bài 01, mục 11](01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp).

---

## 3. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 01 | [Kiến trúc Linux & Filesystem](01-linux-architecture-filesystem.md) | 1 | 3h | 🟥 |
| 02 | [Lệnh thiết yếu & xử lý văn bản](02-essential-commands-text.md) | 1 | 4h | 🟥 |
| — | [Ôn tập Git nhanh](../03-GIT/00-git-quick-review.md) | 1 | 2h | 🟥 |
| 03 | [Permissions, Users & Groups](03-permissions-users-groups.md) | 2 | 4h | 🟥 |
| 04 | [Processes & systemd](04-processes-systemd.md) | 2 | 4h | 🟥 |
| 05 | [Package management & SSH](05-packages-ssh.md) | 3 | 3h | 🟥 |
| 06 | [Bash scripting & biến môi trường](06-bash-scripting.md) | 3 | 4h | 🟥 |
| 07 | [Logs, monitoring & troubleshooting](07-logs-monitoring-troubleshooting.md) | 3 | 4h | 🟥 |
| 08 | [Cron & lập lịch tác vụ](08-cron-scheduling.md) | 3 | 2h | 🟨 |

Thời lượng trên là thời gian học bài. Phần còn lại của ~16 giờ/tuần dành cho lab, bài tập tự làm và dự án.

---

## 4. Lab bắt buộc và break-fix

| Lab | Tuần | Mô tả |
|---|---|---|
| Thám hiểm `/etc`, `/var/log`, `/proc` | 1 | Nằm trong [bài 01, mục 9](01-linux-architecture-filesystem.md#9-bài-thực-hành-từng-bước) |
| [Chạy ứng dụng Java thành systemd service](labs/lab-02-java-systemd-service.md) | 2 | User riêng, tự khởi động lại khi bị kill |
| [Script healthcheck chạy bằng cron](labs/lab-03-healthcheck-cron.md) | 3 | Bash + cron + log |
| [Break-fix Linux #1](labs/break-fix-01/README.md) | 3 | Môi trường có lỗi cài sẵn — tự tìm và sửa |

Lời giải bài tập tự làm nằm trong [solutions/](solutions/). **Chỉ mở sau khi đã tự làm.**

---

## 5. Checklist hoàn thành module

Chỉ chuyển sang Module 02 khi tick được hết các mục 🟥:

- [ ] 🟥 Di chuyển, tìm file, đọc log hoàn toàn bằng terminal.
- [ ] 🟥 Giải thích được ý nghĩa `drwxr-x---` và sửa được lỗi `Permission denied`.
- [ ] 🟥 Tìm được process đang dùng nhiều CPU/RAM nhất và dừng nó an toàn.
- [ ] 🟥 Tạo, khởi động, xem log của một systemd service.
- [ ] 🟥 SSH bằng key, giải thích được public key và private key khác nhau thế nào.
- [ ] 🟥 Viết script Bash có kiểm tra lỗi và trả về exit code đúng.
- [ ] 🟥 Có quy trình rõ ràng khi được báo "server chậm" hoặc "ứng dụng chết".
- [ ] 🟨 Lập lịch được tác vụ bằng cron và kiểm tra được nó có chạy hay không.
- [ ] 🟥 Đạt [Checkpoint Module 01](checkpoint.md).
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#linux).

---

## 6. Nguồn học

| Vai trò | Nguồn | Ghi chú |
|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt |
| Tra cứu | [Ubuntu Server docs](https://ubuntu.com/server/docs) | Tài liệu chính thức |
| Bổ sung | [Linux Journey](https://labex.io/linuxjourney) | Phần *Grasshopper* + *Journeyman* |
| Bổ sung | [MIT Missing Semester 2026](https://missing.csail.mit.edu/) | Bài *Shell*, *Command-line Environment*, *Debugging* |
| Tra cứu nhanh | `man <lệnh>`, `<lệnh> --help` | Có sẵn trên máy — tập thói quen dùng trước khi Google |

Thuật ngữ của module: [glossary.md](glossary.md).
