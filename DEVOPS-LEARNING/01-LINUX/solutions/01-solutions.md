# Lời giải — Bài 01: Kiến trúc Linux & Filesystem

> ⚠️ Chỉ đọc sau khi đã tự làm và ghi câu trả lời của bạn. Nếu câu trả lời của bạn khác nhưng giải thích được bằng lập luận đúng, vẫn tính là đạt.

Quay lại bài: [01-linux-architecture-filesystem.md](../01-linux-architecture-filesystem.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Kernel, system call, userspace khi chạy `cat file.txt`?**
Bash (userspace) tìm chương trình `cat` trong `PATH` rồi nhờ kernel tạo process mới chạy `/usr/bin/cat`. `cat` (userspace) gọi system call `open()` để mở file và `read()` để đọc nội dung, rồi `write()` để in ra màn hình. Kernel thực hiện việc thật: kiểm tra quyền, tìm dữ liệu trên đĩa qua driver, đưa dữ liệu về cho process. System call là "cửa" giữa hai phía.

**2. Ubuntu và Linux có phải là một?**
Không. Linux là kernel. Ubuntu là một distribution: kernel Linux + công cụ userspace (GNU coreutils, bash) + trình quản lý gói `apt` + cấu hình mặc định + chu kỳ phát hành và hỗ trợ của Canonical.

**3. Terminal và Shell?**
Terminal hiển thị chữ và nhận bàn phím. Shell hiểu và thực thi lệnh. Cùng một terminal có thể chạy nhiều shell khác nhau (bash, zsh); cùng một shell có thể chạy trong nhiều terminal khác nhau.

**4. Server sắp đầy ổ cứng — 3 thư mục kiểm tra đầu tiên?**
- `/var/log` — log tăng liên tục, đặc biệt khi không có xoay vòng log (logrotate).
- `/var/lib` — dữ liệu dịch vụ: `/var/lib/docker` (image, container, volume), `/var/lib/postgresql`.
- `/tmp` hoặc `/home` — file tạm, file backup, file người dùng tải về để quên.
Câu trả lời khác cũng đúng nếu có lý do, ví dụ `/opt/<app>` nếu app ghi dữ liệu ở đó.

**5. File cấu hình SSH server ở đâu?**
`/etc/ssh/sshd_config` — theo nguyên tắc "cấu hình hệ thống nằm trong `/etc`, mỗi dịch vụ một thư mục con". Chữ `d` trong `sshd` là *daemon* (chương trình chạy nền — server); `ssh_config` không có `d` là cấu hình cho phía client.

**6. Vì sao `/proc` không chiếm dung lượng?**
`/proc` là filesystem ảo (procfs). Nội dung được kernel **tạo ra ngay khi bạn đọc**, lấy từ cấu trúc dữ liệu trong bộ nhớ của kernel. Không có gì được ghi xuống đĩa. Vì vậy `ls -l /proc/meminfo` báo kích thước 0 nhưng `cat` vẫn ra nội dung.

**7. Liên kết mềm và liên kết cứng?**
Liên kết mềm là một file nhỏ chứa đường dẫn tới file đích; xóa file đích → link gãy, `cat` báo `No such file or directory`. Liên kết cứng là một tên khác trỏ tới cùng inode; xóa "file gốc" chỉ là xóa một tên, dữ liệu vẫn còn và đọc được qua tên kia. Liên kết cứng không trỏ được tới thư mục và không vượt qua ranh giới giữa hai filesystem khác nhau; liên kết mềm thì được.

**8. Vì sao script nên dùng đường dẫn tuyệt đối?**
Đường dẫn tương đối phụ thuộc thư mục hiện tại. Khi script chạy bằng cron, systemd hoặc pipeline CI, thư mục hiện tại thường không phải nơi bạn nghĩ (ví dụ cron chạy ở home, systemd chạy ở `/`). Script sẽ không tìm thấy file hoặc tệ hơn — ghi/xóa nhầm chỗ.

**9. Exit code `0`? Ai dùng?**
`0` là thành công, khác `0` là lỗi. Người dùng: shell (`&&`, `||`, `if`), script với `set -e`, CI/CD pipeline (bước nào trả mã khác 0 thì pipeline đỏ), Docker `HEALTHCHECK`, systemd (`Restart=on-failure` dựa vào mã thoát), Kubernetes probe dạng `exec`.

**10. Ba khác biệt WSL2 vs EC2 có thể làm lệnh chạy khác nhau?**
Bất kỳ 3 trong số: systemd có thể chưa bật trên WSL (lệnh `systemctl` lỗi); mạng WSL đi qua NAT của Windows (IP khác, port mở trong WSL chưa chắc truy cập được từ máy khác); WSL có `/mnt/c` và tương tác với file Windows (quyền lạ, CRLF); kernel khác (tên `microsoft-standard-WSL2`, một số module kernel không có); không có firewall `ufw` thật sự quản lý mạng bên ngoài; WSL bị tắt khi không dùng nên cron/service không chạy liên tục.

**11. Container có kernel riêng không? Chứng minh?**
Không. Ở Bước 7, `uname -r` trong container cho ra **đúng** chuỗi kernel của WSL (`...microsoft-standard-WSL2`), trong khi `/etc/os-release` lại là của image Ubuntu 22.04. Nghĩa là container chỉ mang theo userspace (filesystem) riêng, còn kernel thì dùng chung với host.

**12. Vì sao không đặt dự án trong `/mnt/c`?**
(1) Chậm hơn nhiều vì mọi thao tác file đi qua lớp chia sẻ giữa Windows và Linux — build Maven, `npm install`, `git status` bị chậm rõ rệt. (2) Quyền Linux không được lưu thật (thường hiện `777`), dễ gây lỗi với SSH key (`UNPROTECTED PRIVATE KEY FILE`) và script. (3) Dễ lẫn xuống dòng CRLF do công cụ Windows sửa file.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Bản đồ của riêng bạn

Không có đáp án duy nhất. Đạt khi có ≥ 12 thư mục, mô tả đúng vai trò, mỗi thư mục có 1 file **thật** bạn tìm thấy. Ví dụ một dòng tốt:

```text
/etc/ssh/        cấu hình SSH       → ví dụ: /etc/ssh/ssh_config
/var/log/apt/    log cài gói apt    → ví dụ: /var/log/apt/history.log
/proc/self/      process đang đọc   → ví dụ: /proc/self/status
```

Lỗi hay gặp: mô tả `/usr` là "user files" — sai. `/usr` là chương trình và thư viện của hệ thống (*Unix System Resources* là cách giải thích phổ biến); file người dùng ở `/home`.

### Bài 2 — Thám tử link

Cách tìm:

```bash
ls -l / | grep '^l'
find /etc -maxdepth 1 -type l -exec ls -l {} \;
find /usr/bin -maxdepth 1 -type l | head
```

Ví dụ kết quả và lý do:

| Link | Trỏ tới | Lý do |
|---|---|---|
| `/bin` | `usr/bin` | Ubuntu gộp `/bin` vào `/usr/bin` ("usrmerge"); link giữ tương thích với script cũ viết `#!/bin/bash` |
| `/etc/localtime` | `/usr/share/zoneinfo/...` | Múi giờ hệ thống: đổi múi giờ = đổi đích của link, không phải sửa file |
| `/usr/bin/python3` | `python3.12` | Cho phép nhiều phiên bản cùng tồn tại, tên chung trỏ tới bản mặc định |
| `/etc/resolv.conf` (tùy cấu hình) | file do WSL hoặc systemd-resolved sinh | Cấu hình DNS do dịch vụ khác quản lý |

### Bài 3 — Không có công cụ

```bash
# (a) Tổng RAM
grep MemTotal /proc/meminfo

# (b) Số nhân CPU (logic)
grep -c '^processor' /proc/cpuinfo

# (c) PID của shell
echo $$
# hoặc: cách không dùng biến đặc biệt
grep '^Pid' /proc/self/status     # lưu ý: đây là PID của chính lệnh grep, không phải shell!
grep '^PPid' /proc/self/status    # PPid của grep = PID của shell
```

```bash
# (d) Lệnh khởi chạy process số 1
cat /proc/1/cmdline; echo
# Các tham số được ngăn cách bằng ký tự NUL, hiển thị liền nhau. Đổi NUL thành dấu cách:
tr '\0' ' ' < /proc/1/cmdline; echo
```

Trong container chạy bằng `docker run -it ubuntu:22.04 bash`, process 1 là `bash`. Trên WSL có systemd, process 1 là `/sbin/init` (systemd). Đây là gợi ý cho Module 04: **process số 1 trong container chính là lệnh bạn yêu cầu container chạy**. Khi nó thoát, container dừng.

Điểm tinh tế ở (c): `/proc/self` trỏ tới process **đang đọc nó**. Khi chạy `grep ... /proc/self/status`, "self" là `grep`, không phải shell. Nếu bạn nhận ra điều này, bạn đã hiểu `/proc` rất tốt.

### Bài 4 — Link gãy

```bash
cd ~/devops-lab/01-linux
echo data > target.txt
ln -s target.txt broken-link
rm target.txt
ls -l broken-link
cat broken-link
```

```text
lrwxrwxrwx 1 phuong phuong 10 Oct 31 10:00 broken-link -> target.txt
cat: broken-link: No such file or directory
```

`ls -l` vẫn hiện link bình thường (trên terminal có màu, link gãy thường hiện **đỏ nhấp nháy**). `cat` báo file không tồn tại dù `ls` thấy tên — đây là dấu hiệu đặc trưng của link gãy.

Liệt kê mọi link gãy:

```bash
find . -xtype l
```

`-type l` khớp mọi link. `-xtype l` kiểm tra **đích** của link: nếu sau khi đi theo link mà vẫn là link (tức không đi tới đâu được), đó là link gãy.

### Bài 5 — CRLF

Lỗi sẽ thấy:

```text
$ ./hello.sh
-bash: ./hello.sh: /bin/bash^M: bad interpreter: No such file or directory

$ bash hello.sh
hello            # có thể chạy được, hoặc báo lỗi kiểu "$'\r': command not found" ở các dòng khác
```

Chẩn đoán:

```bash
file hello.sh
cat -A hello.sh
```

```text
hello.sh: Bourne-Again shell script, ASCII text executable, with CRLF line terminators
#!/bin/bash^M$
echo hello^M$
```

`cat -A` hiện ký tự ẩn: `^M` là `\r` (carriage return), `$` là cuối dòng. Khi chạy `./hello.sh`, kernel đọc dòng shebang và tìm chương trình tên `/bin/bash\r` — không tồn tại, nên báo `bad interpreter`. Vì sao `bash hello.sh` có thể vẫn chạy? Vì lúc đó bạn gọi trực tiếp `/bin/bash`, dòng shebang chỉ còn là comment; nhưng `\r` ở cuối các lệnh khác vẫn có thể gây lỗi.

Sửa:

```bash
sed -i 's/\r$//' hello.sh   # xóa \r ở cuối mỗi dòng, sửa trực tiếp (-i) trên file
file hello.sh               # không còn "with CRLF line terminators"
./hello.sh
```

Phòng ngừa: VS Code dùng LF cho file trong WSL; `git config --global core.autocrlf input`; có thể thêm `.gitattributes` với dòng `*.sh text eol=lf` vào repo (học ở Module 03).

Mục nhật ký đạt yêu cầu khi có đủ: triệu chứng (thông báo lỗi nguyên văn), giả thuyết, lệnh kiểm tra và kết quả, nguyên nhân gốc, cách sửa, cách phòng ngừa.
