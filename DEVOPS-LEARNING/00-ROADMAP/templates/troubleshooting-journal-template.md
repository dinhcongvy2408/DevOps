# Mẫu nhật ký debug (Troubleshooting Journal)

> Copy file này thành `troubleshooting-journal.md` trong repo `devops-journey`. Mỗi lỗi bạn gặp trong suốt khóa học = một mục mới, **mới nhất ở trên cùng**.

## Mục lục

- [1. Vì sao phải ghi nhật ký debug?](#1-vì-sao-phải-ghi-nhật-ký-debug)
- [2. Mẫu một mục](#2-mẫu-một-mục)
- [3. Hướng dẫn điền từng phần](#3-hướng-dẫn-điền-từng-phần)
- [4. Ví dụ hoàn chỉnh](#4-ví-dụ-hoàn-chỉnh)
- [5. Dùng nhật ký khi phỏng vấn (STAR)](#5-dùng-nhật-ký-khi-phỏng-vấn-star)

---

## 1. Vì sao phải ghi nhật ký debug?

- **Biến lỗi thành kỹ năng.** Viết lại "tôi đã tìm ra nguyên nhân bằng cách nào" buộc bạn hiểu quy trình, không chỉ nhớ cách sửa.
- **Không mắc lại cùng một lỗi.** Lần thứ hai gặp, bạn tìm trong nhật ký thay vì tìm lại từ đầu.
- **Thấy mình tiến bộ.** Sau vài tuần, bạn sẽ thấy thời gian tìm nguyên nhân ngắn lại.
- **Kho câu chuyện phỏng vấn.** "Kể về một lỗi khó bạn đã xử lý" là câu hỏi gần như chắc chắn gặp (xem [mục 5](#5-dùng-nhật-ký-khi-phỏng-vấn-star)).
- **Tập viết postmortem.** Từ Module 08, bạn sẽ viết postmortem cho sự cố — nhật ký này là bản nháp nhỏ của kỹ năng đó.

---

## 2. Mẫu một mục

Copy khối dưới đây cho mỗi lỗi mới:

```markdown
## YYYY-MM-DD — <Tiêu đề ngắn mô tả triệu chứng>

- **Module / bài:** <ví dụ 01-LINUX / bài 06>
- **Mức độ khó:** ⭐ / ⭐⭐ / ⭐⭐⭐
- **Thời gian xử lý:** <ví dụ 25 phút>

### Triệu chứng
<Bạn thấy gì? Copy nguyên văn thông báo lỗi, không tóm tắt.>

### Bối cảnh
<Đang làm gì, ở môi trường nào ([WSL]/[Sandbox]/[EC2]…), vừa thay đổi gì trước đó?>

### Giả thuyết
1. <Giả thuyết 1> → ❌ loại vì ...
2. <Giả thuyết 2> → ✅ đúng

### Kiểm tra
<Các lệnh đã chạy để kiểm chứng giả thuyết, và kết quả quan trọng.>

### Nguyên nhân gốc (root cause)
<Một đến hai câu. Nguyên nhân thật, không phải triệu chứng.>

### Cách sửa
<Lệnh / thay đổi cụ thể.>

### Phòng ngừa
<Làm gì để lỗi không lặp lại: cấu hình, thói quen, kiểm tra tự động.>

### Bài học
<Điều bạn hiểu ra về hệ thống.>

### Nguồn
<Link docs / man page đã giúp bạn.>
```

---

## 3. Hướng dẫn điền từng phần

| Phần | Viết thế nào | Lỗi hay gặp khi viết |
|---|---|---|
| **Triệu chứng** | Copy nguyên văn thông báo lỗi, exit code, mã HTTP | Viết "nó bị lỗi" — không đủ thông tin để tìm lại sau này |
| **Bối cảnh** | Môi trường + thay đổi gần nhất. Phần lớn lỗi đến từ **thay đổi gần nhất** | Bỏ qua phần này |
| **Giả thuyết** | Ghi cả giả thuyết **sai** và lý do loại — đây là phần thể hiện tư duy | Chỉ ghi giả thuyết đúng |
| **Kiểm tra** | Lệnh quan sát (không sửa gì): `ls -l`, `stat`, `journalctl`, `curl -v`, `docker logs`… | Sửa nhiều thứ cùng lúc rồi không biết cái nào có tác dụng |
| **Nguyên nhân gốc** | Hỏi "tại sao?" cho đến khi gặp nguyên nhân có thể ngăn chặn được | Dừng ở triệu chứng ("vì service chết") |
| **Phòng ngừa** | Ưu tiên biện pháp **tự động** hơn là "lần sau cẩn thận hơn" | Chỉ viết "sẽ cẩn thận" |
| **Bài học** | Kiến thức tổng quát rút ra được | Lặp lại cách sửa |

**Không cần dài.** Một mục tốt thường 15–30 dòng. Viết ngay khi vừa xử lý xong, lúc còn nhớ rõ.

---

## 4. Ví dụ hoàn chỉnh

```markdown
## 2026-11-03 — Script báo `/bin/bash^M: bad interpreter`

- **Module / bài:** 01-LINUX / bài 01, bài tập 5
- **Mức độ khó:** ⭐
- **Thời gian xử lý:** 20 phút

### Triệu chứng
    $ ./hello.sh
    bash: ./hello.sh: /bin/bash^M: bad interpreter: No such file or directory
    $ echo $?
    126

Nhưng `bash hello.sh` lại chạy được (có in thêm `$'\r': command not found` ở vài dòng).

### Bối cảnh
- Môi trường: [WSL] Ubuntu 24.04.
- File `hello.sh` tạo bằng Notepad trên Windows, lưu vào `\\wsl.localhost\Ubuntu\home\phuong\devops-lab\01-linux\`.
- Đã `chmod +x hello.sh`.

### Giả thuyết
1. Thiếu quyền thực thi → ❌ `ls -l` cho thấy `-rwxr-xr-x`.
2. `/bin/bash` không tồn tại → ❌ `ls -l /bin/bash` có file.
3. Dòng đầu (shebang) chứa ký tự lạ, vì thông báo in `/bin/bash^M` thay vì `/bin/bash` → ✅

### Kiểm tra
    $ file hello.sh
    hello.sh: Bourne-Again shell script, ASCII text executable, with CRLF line terminators
    $ cat -A hello.sh
    #!/bin/bash^M$
    echo hello^M$

`^M` là ký tự `\r` (carriage return), `$` là cuối dòng. Mỗi dòng kết thúc bằng `\r\n` (CRLF).

### Nguyên nhân gốc
Notepad lưu file với kiểu xuống dòng Windows (CRLF). Kernel đọc shebang thành `/bin/bash\r`
và tìm chương trình có tên đúng như vậy — không tồn tại.

### Cách sửa
    sed -i 's/\r$//' hello.sh
    file hello.sh     # không còn "with CRLF line terminators"
    ./hello.sh        # in "hello"

### Phòng ngừa
- Không sửa file của WSL bằng Notepad. Dùng VS Code mở từ WSL (`code .`), đặt `"files.eol": "\n"`.
- `git config --global core.autocrlf input` trong WSL.
- Thêm `.gitattributes` với `* text=auto eol=lf` vào mọi repo.

### Bài học
- Kernel đọc dòng shebang **byte theo byte** — một ký tự vô hình cũng làm sai tên chương trình.
- `bash hello.sh` chạy được vì khi đó kernel không đọc shebang; bash tự đọc file — nhưng bash vẫn thấy `\r` ở cuối mỗi lệnh.
- `file` và `cat -A` là hai công cụ đầu tiên để kiểm tra "file này thực sự chứa gì".

### Nguồn
- Bài 01, mục 11 — Các lỗi thường gặp
- `man file`, `man cat` (tùy chọn `-A`)
```

---

## 5. Dùng nhật ký khi phỏng vấn (STAR)

Câu hỏi kiểu *"Kể về một lỗi khó nhất bạn từng xử lý"* hoặc *"Bạn debug một vấn đề như thế nào?"* đánh giá **tư duy**, không phải việc bạn có nhớ lệnh hay không. Trả lời theo cấu trúc **STAR**:

| Phần | Tiếng Việt | Lấy từ phần nào của nhật ký |
|---|---|---|
| **S**ituation | Bối cảnh | Bối cảnh |
| **T**ask | Nhiệm vụ / vấn đề cần giải quyết | Triệu chứng |
| **A**ction | Bạn đã làm gì | Giả thuyết + Kiểm tra + Cách sửa |
| **R**esult | Kết quả và bài học | Nguyên nhân gốc + Phòng ngừa + Bài học |

Ví dụ trả lời (~1 phút) từ mục ở trên:

> **S:** Trong dự án cá nhân, tôi viết script Bash trên Windows rồi chạy trong WSL. **T:** Script có quyền thực thi nhưng báo `bad interpreter`. **A:** Tôi để ý thông báo in `/bin/bash^M` chứ không phải `/bin/bash`, nên nghi ngờ dòng shebang. Tôi loại trừ lỗi quyền bằng `ls -l`, rồi dùng `file` và `cat -A` thì thấy file có kết thúc dòng CRLF. **R:** Tôi sửa bằng `sed`, và quan trọng hơn là chặn lỗi lặp lại: cấu hình `core.autocrlf`, thêm `.gitattributes` để cả repo luôn dùng LF. Bài học là đọc kỹ từng ký tự của thông báo lỗi trước khi đoán.

**Chuẩn bị trước phỏng vấn** (tuần 24): chọn 3–5 mục hay nhất trong nhật ký — ưu tiên lỗi liên quan nhiều tầng (ví dụ Nginx 502 do container chết vì sai biến môi trường) — và tập kể mỗi câu chuyện trong 1–2 phút.
