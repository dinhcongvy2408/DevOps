# Thuật ngữ Module 01 — Linux

> Mỗi thuật ngữ ghi bài học lần đầu giải thích nó. Thuật ngữ Git ở [Ôn tập Git nhanh](../03-GIT/00-git-quick-review.md) sẽ được gom vào glossary của Module 03.

## Mục lục

- [Kiến trúc & filesystem (bài 01)](#kiến-trúc--filesystem-bài-01)
- [Lệnh & xử lý văn bản (bài 02)](#lệnh--xử-lý-văn-bản-bài-02)
- [Quyền, user, group (bài 03)](#quyền-user-group-bài-03)
- [Process & systemd (bài 04)](#process--systemd-bài-04)
- [Gói phần mềm & SSH (bài 05)](#gói-phần-mềm--ssh-bài-05)
- [Bash & biến môi trường (bài 06)](#bash--biến-môi-trường-bài-06)
- [Log, giám sát, xử lý sự cố (bài 07)](#log-giám-sát-xử-lý-sự-cố-bài-07)
- [Lập lịch (bài 08)](#lập-lịch-bài-08)

---

## Kiến trúc & filesystem (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Kernel | Nhân | Phần lõi của hệ điều hành, trực tiếp quản lý CPU, RAM, ổ đĩa, mạng. |
| System call | Lời gọi hệ thống | Cách chương trình nhờ kernel làm việc (mở file, tạo process…). |
| Userspace | Không gian người dùng | Nơi mọi chương trình bình thường chạy với quyền hạn chế. |
| Distribution (distro) | Bản phân phối | Kernel Linux + công cụ + trình quản lý gói + cấu hình, ví dụ Ubuntu. |
| Shell | Trình thông dịch lệnh | Chương trình hiểu và chạy lệnh bạn gõ, ví dụ Bash. |
| Terminal | Cửa sổ dòng lệnh | Chương trình hiển thị chữ và nhận bàn phím. |
| Filesystem Hierarchy | Cây thư mục chuẩn | Quy ước thư mục nào chứa gì (`/etc`, `/var`, `/usr`…). |
| Absolute / relative path | Đường dẫn tuyệt đối / tương đối | Bắt đầu từ `/` / tính từ thư mục hiện tại. |
| Mount / mount point | Gắn / điểm gắn | Gắn một ổ đĩa vào một thư mục trong cây. |
| Inode | Nút chỉ mục | Bản ghi chứa quyền, chủ sở hữu, vị trí dữ liệu của một file; tên file chỉ trỏ tới inode. |
| Symbolic link | Liên kết mềm | File nhỏ chứa đường dẫn tới file khác, như shortcut. |
| Hard link | Liên kết cứng | Thêm một tên nữa trỏ tới cùng inode. |
| procfs (`/proc`) | Filesystem tiến trình | Filesystem ảo do kernel sinh ra, mô tả process và hệ thống. |
| ELF | Định dạng thực thi | Định dạng file chương trình chạy được trên Linux. |
| Exit code | Mã thoát | Số một lệnh trả về khi kết thúc: `0` thành công, khác `0` lỗi. |
| CRLF / LF | Xuống dòng Windows / Linux | `\r\n` và `\n`; script Linux phải dùng LF. |
| WSL2 | Hệ thống con Linux cho Windows | Kernel Linux thật chạy trong máy ảo nhẹ do Windows quản lý. |

## Lệnh & xử lý văn bản (bài 02)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| stdin / stdout / stderr | Đầu vào / đầu ra / đầu ra lỗi chuẩn | Ba kênh vào/ra mặc định của mọi process, đánh số 0, 1, 2. |
| File descriptor | Bộ mô tả file | Con số kernel cấp cho process để chỉ một kênh vào/ra đang mở; trỏ tới inode, không trỏ tới tên. |
| Pipe (`\|`) | Đường ống | Nối stdout của lệnh trước vào stdin của lệnh sau. |
| Redirect | Chuyển hướng | Đưa luồng dữ liệu vào/ra file thay cho màn hình/bàn phím. |
| Globbing / Wildcard | Ký tự đại diện | Mẫu `*`, `?`, `[...]` được shell mở rộng thành danh sách tên file. |
| Brace expansion | Mở rộng ngoặc nhọn | `{a,b}` được Bash sinh thành nhiều chuỗi. |
| Regular expression (regex) | Biểu thức chính quy | Ngôn ngữ mẫu để khớp văn bản trong `grep`, `sed`, `awk`. |
| In-place edit | Sửa tại chỗ | `sed -i` ghi thay đổi thẳng vào file. |
| Here-document | Tài liệu nội tuyến | `<<'EOF'` đưa một khối nhiều dòng vào stdin của lệnh. |

## Quyền, user, group (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| UID / GID | Mã số người dùng / nhóm | Con số kernel thật sự dùng để kiểm tra quyền; tên chỉ là nhãn. |
| Owner / Group / Others (u/g/o) | Chủ sở hữu / nhóm / người khác | Ba đối tượng, mỗi đối tượng có một bộ quyền riêng trên file. |
| Permission (r/w/x) | Quyền đọc/ghi/thực thi | Với thư mục: liệt kê tên / tạo-xóa mục bên trong / đi xuyên qua. |
| Octal mode | Quyền dạng số bát phân | r=4, w=2, x=1, ví dụ `640`. |
| umask | Mặt nạ quyền | Các bit quyền bị gỡ khỏi file/thư mục mới tạo. |
| setuid / setgid | Đặt UID / GID khi chạy | Chạy chương trình với quyền của chủ/nhóm file; setgid trên thư mục làm file mới kế thừa group. |
| Sticky bit | Bit dính | Trên thư mục dùng chung như `/tmp`, chỉ chủ file mới xóa được file đó. |
| Primary / supplementary group | Nhóm chính / nhóm phụ | Nhóm chính quyết định group của file mới; nhóm phụ cấp thêm quyền. |
| System user | Người dùng hệ thống | User UID < 1000, không đăng nhập được, dùng để chạy dịch vụ. |
| nologin | Không cho đăng nhập | Shell `/usr/sbin/nologin` chặn đăng nhập tương tác. |
| sudo / sudoers | Chạy với quyền khác / cấu hình sudo | Cấp quyền root có kiểm soát và ghi log; sửa bằng `visudo`. |
| Least privilege | Đặc quyền tối thiểu | Chỉ cấp đúng quyền cần thiết, không hơn. |
| ACL | Danh sách kiểm soát truy cập | Cấp quyền cho thêm user/group cụ thể ngoài ba bộ u/g/o. |
| EACCES / ENOENT / EPERM | Mã lỗi 13 / 2 / 1 | Permission denied / No such file or directory / Operation not permitted. |

## Process & systemd (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Process | Tiến trình | Chương trình đang chạy, có PID, vùng nhớ và user riêng. |
| PID / PPID | Mã số process / process cha | Định danh của process và của process đã tạo ra nó. |
| fork / exec | Phân nhánh / thực thi | Tạo bản sao process, rồi thay code bản sao bằng chương trình khác. |
| Zombie | Process xác sống | Process đã chết nhưng cha chưa nhận exit code của nó. |
| Orphan | Process mồ côi | Process còn chạy khi cha đã chết, được PID 1 nhận nuôi. |
| Daemon | Tiến trình nền | Process chạy ngầm lâu dài, không gắn với terminal. |
| Signal | Tín hiệu | Thông điệp ngắn gửi tới process (SIGTERM, SIGKILL, SIGINT, SIGHUP). |
| Graceful shutdown | Tắt nhẹ nhàng | App xử lý nốt việc dở dang và dọn dẹp trước khi thoát. |
| RSS / VSZ | Bộ nhớ thực / bộ nhớ ảo | RAM vật lý đang chiếm so với vùng nhớ ảo đã xin. |
| Nice value | Độ nhường CPU | Từ -20 đến 19, quyết định mức ưu tiên CPU. |
| Job control | Điều khiển job | Chuyển lệnh giữa foreground/background bằng `&`, `fg`, `bg`, `jobs`. |
| systemd | Trình quản lý hệ thống | PID 1, khởi động và giám sát service, gom log vào journal. |
| Unit / unit file | Đơn vị / file mô tả | Thứ systemd quản lý (service, timer…) và file cấu hình của nó. |
| Target | Mục tiêu | Nhóm unit đại diện một trạng thái hệ thống, ví dụ `multi-user.target`. |
| journalctl | Công cụ đọc journal | Đọc kho log tập trung của systemd. |
| cgroup | Nhóm kiểm soát | Cơ chế kernel gom và giới hạn tài nguyên cho nhóm process — nền tảng của container. |

## Gói phần mềm & SSH (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Package | Gói phần mềm | File `.deb` chứa chương trình và thông tin phụ thuộc. |
| Repository | Kho phần mềm | Máy chủ chứa gói kèm danh mục đã được ký. |
| Dependency | Gói phụ thuộc | Gói khác cần có để một gói chạy được. |
| GPG key / keyring | Khóa GPG / chùm khóa | Khóa công khai để kiểm chứng gói đúng do kho phát hành. |
| Public / private key | Khóa công khai / khóa bí mật | Cặp khóa liên kết toán học: phát ổ khóa cho người khác, giữ chìa cho mình. |
| Passphrase | Cụm mật khẩu | Mật khẩu mã hóa file private key trên đĩa. |
| ssh-agent | Trình giữ khóa SSH | Giữ private key đã mở khóa trong RAM. |
| Host key / fingerprint | Khóa máy chủ / dấu vân tay | Khóa chứng minh danh tính server và chuỗi rút gọn của nó. |
| known_hosts / authorized_keys | — | Host key đã tin cậy (ở client) / public key được phép đăng nhập (ở server). |
| Man-in-the-middle | Tấn công kẻ đứng giữa | Kẻ chặn đường truyền và giả làm server. |
| Port forwarding | Chuyển tiếp cổng | Đưa traffic từ một port trên máy bạn qua đường SSH tới đích phía server. |

## Bash & biến môi trường (bài 06)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Script | Kịch bản | File văn bản chứa lệnh shell, chạy tuần tự, không cần biên dịch. |
| Shebang | Dòng shebang | Dòng `#!...` đầu file cho kernel biết chương trình nào thông dịch script. |
| Quoting | Đặt trong nháy | `"..."` / `'...'` kiểm soát việc thay biến, tách từ và glob. |
| Word splitting | Tách từ | Bash cắt kết quả không nằm trong nháy kép tại dấu cách, tab, xuống dòng. |
| Command substitution | Thay thế bằng kết quả lệnh | `$(lệnh)` được thay bằng output của lệnh. |
| Arithmetic expansion | Mở rộng số học | `$(( ))` tính toán số nguyên. |
| Here-string | Chuỗi nội tuyến | `<<<` đưa nội dung một biến vào stdin. |
| Array | Mảng | Biến chứa nhiều phần tử: `arr=()`, `arr+=(x)`, `${#arr[@]}`. |
| errexit / nounset / pipefail | Dừng khi lỗi / cấm biến chưa đặt / lỗi trong pipeline | Ba cờ của `set -euo pipefail`. |
| trap | Bẫy tín hiệu | Lệnh chạy khi script thoát (EXIT), gặp lỗi (ERR) hoặc nhận tín hiệu. |
| Environment variable | Biến môi trường | Biến đã `export`, được truyền cho mọi process con. |
| Shell variable | Biến shell | Biến chỉ tồn tại trong shell hiện tại. |
| PATH | Đường dẫn tìm lệnh | Danh sách thư mục, ngăn bởi `:`, nơi shell tìm chương trình. |
| source | Nạp vào shell hiện tại | Chạy một file trong chính shell đang dùng, không tạo process con. |
| ShellCheck | Công cụ kiểm tra script | Phân tích tĩnh, phát hiện lỗi quote và logic phổ biến. |

## Log, giám sát, xử lý sự cố (bài 07)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Log / log level | Nhật ký / mức độ log | Dòng ghi lại việc chương trình làm; mức từ `emerg` (0) đến `debug` (7). |
| systemd-journald | Dịch vụ nhật ký systemd | Thu log từ kernel và service, lưu dạng nhị phân, đọc bằng `journalctl`. |
| rsyslog | Dịch vụ syslog | Ghi log ra file văn bản trong `/var/log`. |
| Log rotation / logrotate | Xoay vòng log | Định kỳ đổi tên, nén, xóa log cũ để không đầy đĩa. |
| copytruncate | Sao chép rồi cắt rỗng | Chép log ra bản cũ rồi cắt rỗng file gốc tại chỗ; có thể mất vài dòng. |
| Stack trace | Vết ngăn xếp | Chuỗi lời gọi hàm dẫn tới exception, kèm dòng `Caused by:`. |
| Root cause | Nguyên nhân gốc | Lỗi thật sự; trong stack trace Java thường là `Caused by` cuối cùng. |
| Load average | Tải trung bình | Số process trung bình đang chạy hoặc chờ CPU/I/O trong 1/5/15 phút. |
| I/O wait (`wa`) | Thời gian chờ I/O | % thời gian CPU rảnh trong khi có process chờ ổ đĩa. |
| Steal time (`st`) | Thời gian bị lấy mất | CPU hypervisor lấy cho máy ảo khác. |
| Page cache / buff/cache | Bộ đệm trang | RAM dùng cache dữ liệu đĩa, giải phóng ngay khi cần. |
| Swap | Vùng trao đổi | Phần ổ đĩa dùng làm RAM tạm thời. |
| OOM killer | Bộ giết process khi hết RAM | Kernel giết process chiếm nhiều RAM khi máy hết bộ nhớ. |
| Saturation | Mức bão hòa | Lượng việc phải xếp hàng chờ một tài nguyên. |
| USE method | Phương pháp USE | Với mỗi tài nguyên kiểm tra Utilization, Saturation, Errors. |
| Listening socket | Socket đang lắng nghe | Port một process đang mở để nhận kết nối. |
| Heap dump | Bản chụp heap | Ảnh chụp bộ nhớ của JVM, thường rất lớn. |
| Runbook | Sổ tay vận hành | Các bước xử lý một loại sự cố, viết sẵn theo thứ tự. |
| Postmortem | Báo cáo sau sự cố | Phân tích nguyên nhân sự cố và cách phòng tránh. |

## Lập lịch (bài 08)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| cron | Bộ lập lịch cron | Daemon chạy lệnh theo lịch định kỳ, chính xác đến phút. |
| crontab | Bảng lịch cron | File mô tả lịch: 5 trường thời gian + lệnh. |
| MAILTO | Địa chỉ nhận thư cron | Quyết định output cron gửi mail cho ai; rỗng là không gửi. |
| MTA | Máy chủ chuyển thư | Phần mềm gửi mail; không có MTA thì output cron không redirect bị vứt bỏ. |
| run-parts | Chạy cả thư mục script | Chạy mọi script hợp lệ trong `/etc/cron.daily`…; bỏ qua tên có dấu chấm. |
| flock | Khóa file | Giữ khóa trên file trong lúc lệnh chạy để chống chạy chồng. |
| systemd timer | Bộ hẹn giờ systemd | Unit `.timer` kích hoạt `.service` theo lịch, thay thế được cron. |
| Persistent= | Chạy bù | Nếu máy tắt lúc đến giờ, timer chạy bù một lần khi bật lại. |
