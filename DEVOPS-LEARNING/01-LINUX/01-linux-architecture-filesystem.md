# 01. Kiến trúc Linux & Filesystem

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: không (đây là bài đầu tiên)
> Môi trường: `[WSL]` Ubuntu 24.04, `[Sandbox]` container `ubuntu:22.04`

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
12. [Đọc thông báo lỗi và xử lý](#12-đọc-thông-báo-lỗi-và-xử-lý)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Giải thích được **kernel**, **shell** và **userspace** là gì, và chúng phối hợp với nhau thế nào khi bạn gõ một lệnh.
- Hiểu **WSL2** khác một server Linux thật ở những điểm nào — để không bị bất ngờ khi lên EC2.
- Biết vai trò của các thư mục quan trọng: `/etc`, `/var/log`, `/home`, `/proc`, `/usr`, `/tmp`, `/opt`…
- Tự định hướng trong filesystem bằng `pwd`, `cd`, `ls`, và tra cứu thông tin file/hệ thống bằng `file`, `stat`, `uname`, `df`.
- Đọc được cấu trúc của một thông báo lỗi Linux và biết **exit code** là gì.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Tình huống thật bạn sẽ gặp khi đi làm:

| Tình huống | Bạn cần biết |
|---|---|
| "App không đọc được file cấu hình" | Cấu hình hệ thống nằm ở `/etc`, cấu hình app thường ở `/etc/<app>` hoặc `/opt/<app>` |
| "Server báo đầy ổ cứng" | Dữ liệu hay phình to ở `/var/log`, `/var/lib/docker`, `/tmp` |
| "Container không thấy file vừa copy vào" | Container có filesystem riêng — phải hiểu filesystem gốc trước |
| "Xem app đang dùng bao nhiêu RAM mà không cài thêm gì" | Đọc thẳng từ `/proc` |
| "Script chạy được trên máy tôi nhưng lỗi trên server" | Hiểu khác biệt giữa WSL/Windows và Linux thật (đường dẫn, xuống dòng CRLF) |

Nếu không nắm bản đồ filesystem, bạn sẽ mất rất nhiều thời gian chỉ để **tìm** thứ cần sửa.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Hệ điều hành làm gì?

Một chương trình (ví dụ app Spring Boot của bạn) không tự nói chuyện trực tiếp với ổ cứng, RAM hay card mạng. Nó **nhờ hệ điều hành** làm việc đó. Hệ điều hành đứng giữa phần mềm và phần cứng để:

- Chia CPU cho nhiều chương trình chạy cùng lúc.
- Cấp phát RAM và không cho chương trình này đọc trộm RAM của chương trình khác.
- Đọc/ghi file trên ổ đĩa.
- Gửi/nhận dữ liệu qua mạng.

### 3.2. Ba lớp của Linux

| Lớp | Tiếng Việt | Là gì | Ví dụ |
|---|---|---|---|
| **Kernel** | Nhân | Phần lõi, chạy với toàn quyền, trực tiếp quản lý phần cứng | Linux kernel 5.15, 6.x |
| **System call** | Lời gọi hệ thống | "Cửa giao dịch" để chương trình nhờ kernel làm việc | `open()`, `read()`, `fork()` |
| **Userspace** | Không gian người dùng | Mọi chương trình bình thường, chạy với quyền hạn chế | `bash`, `ls`, `java`, `nginx` |

> **Linux** đúng nghĩa chỉ là cái **kernel**. Thứ bạn dùng hằng ngày là một **distribution** (bản phân phối — ví dụ Ubuntu, Debian, Red Hat) = kernel Linux + bộ công cụ userspace + trình quản lý gói + cấu hình mặc định.

### 3.3. Shell và Terminal khác nhau thế nào?

Người mới hay nhầm hai thứ này:

- **Terminal** (cửa sổ dòng lệnh): chương trình hiển thị chữ và nhận bàn phím. Ví dụ: Windows Terminal.
- **Shell** (trình thông dịch lệnh): chương trình **hiểu** dòng lệnh bạn gõ và chạy nó. Ubuntu mặc định dùng **Bash**.

Khi bạn gõ `ls -l` trong Windows Terminal: Terminal gửi chữ cho Bash → Bash tìm chương trình `ls` → yêu cầu kernel chạy nó → `ls` gọi system call để đọc thư mục → kết quả trả về Terminal để hiển thị.

### 3.4. "Mọi thứ đều là file"

Đây là triết lý quan trọng nhất của Linux. Không chỉ tài liệu, mà cả:

- Ổ cứng → `/dev/sda`
- Thông tin process đang chạy → `/proc/1234/`
- Thông tin CPU → `/proc/cpuinfo`
- Một thiết bị "hố đen" nuốt mọi dữ liệu → `/dev/null`

Hệ quả thực tế: **cùng một bộ công cụ** (`cat`, `less`, `grep`) dùng được cho cả file văn bản, log, thông tin phần cứng và thông tin process.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Cây thư mục Linux (Filesystem Hierarchy)

Windows có nhiều ổ `C:\`, `D:\`. Linux chỉ có **một cây duy nhất** bắt đầu từ gốc `/` (đọc là "root"). Ổ đĩa khác được **gắn (mount)** vào một nhánh của cây này.

Các thư mục bạn cần nhớ, sắp theo mức độ hay dùng trong công việc DevOps:

| Thư mục | Chứa gì | Khi nào DevOps đụng tới |
|---|---|---|
| `/etc` | **Cấu hình** hệ thống và dịch vụ (file văn bản) | Liên tục: `/etc/nginx/`, `/etc/ssh/sshd_config`, `/etc/hosts` |
| `/var` | Dữ liệu **thay đổi** liên tục (variable) | `/var/log/` (log), `/var/lib/docker/` (dữ liệu Docker), `/var/lib/postgresql/` |
| `/home` | Thư mục riêng của từng người dùng: `/home/<tên>` | Nơi bạn làm việc, chứa `~/.ssh/`, `~/.bashrc` |
| `/root` | Thư mục home của user **root** (không nằm trong `/home`) | Khi làm việc bằng quyền root |
| `/tmp` | File tạm, có thể bị xóa khi khởi động lại | Debug, file trung gian của script |
| `/usr` | Chương trình và thư viện do hệ thống cài | `/usr/bin/` (lệnh), `/usr/lib/` (thư viện) |
| `/opt` | Phần mềm bên thứ ba cài thủ công | Hay đặt ứng dụng tự triển khai: `/opt/taskhub/` |
| `/proc` | Filesystem **ảo** do kernel tạo ra, mô tả process và hệ thống | Xem RAM, CPU, thông tin process |
| `/sys` | Filesystem ảo về thiết bị và kernel | Ít dùng ở mức Junior |
| `/dev` | File đại diện cho thiết bị | `/dev/null`, ổ đĩa `/dev/sda`, `/dev/nvme0n1` |
| `/run` | Dữ liệu lúc chạy (PID file, socket) | `/run/docker.sock` |
| `/mnt`, `/media` | Điểm gắn ổ đĩa | Trên WSL: `/mnt/c` chính là ổ `C:` của Windows |
| `/boot` | Kernel và bootloader | Trên server thật; trên WSL gần như trống |
| `/bin`, `/sbin`, `/lib` | Trên Ubuntu hiện đại chỉ là **liên kết** tới `/usr/bin`, `/usr/sbin`, `/usr/lib` | Biết để không bối rối |

**Mẹo nhớ:** cấu hình → `/etc`, log → `/var/log`, dữ liệu app → `/var/lib/<app>`, app tự cài → `/opt`.

### 4.2. 🟥 Đường dẫn tuyệt đối và tương đối

- **Đường dẫn tuyệt đối** (absolute path): bắt đầu bằng `/`, đúng ở mọi nơi. Ví dụ: `/etc/nginx/nginx.conf`.
- **Đường dẫn tương đối** (relative path): tính từ **thư mục hiện tại**. Ví dụ đang ở `/etc` thì `nginx/nginx.conf` trỏ tới cùng file trên.

Ký hiệu đặc biệt:

| Ký hiệu | Nghĩa |
|---|---|
| `.` | Thư mục hiện tại |
| `..` | Thư mục cha |
| `~` | Thư mục home của bạn (ví dụ `/home/phuong`) |
| `-` | (dùng với `cd`) Thư mục bạn vừa ở trước đó |

> **Quy tắc trong script:** luôn dùng **đường dẫn tuyệt đối**. Script chạy bằng cron hoặc systemd không chạy ở thư mục bạn nghĩ — đây là nguyên nhân lỗi rất phổ biến (sẽ gặp lại ở bài 08).

### 4.3. 🟥 Các loại file

Ký tự đầu tiên trong kết quả `ls -l` cho biết loại file:

| Ký tự | Loại | Ví dụ |
|---|---|---|
| `-` | File thường | `/etc/hostname` |
| `d` | Thư mục (directory) | `/etc` |
| `l` | Liên kết mềm (symbolic link) | `/bin` → `usr/bin` |
| `c` | Thiết bị ký tự (character device) | `/dev/null` |
| `b` | Thiết bị khối (block device) | `/dev/sda` |
| `s` | Socket | `/run/docker.sock` |
| `p` | Pipe có tên | Hiếm gặp |

**File ẩn**: tên bắt đầu bằng dấu chấm (`.bashrc`, `.ssh`). Không có thuộc tính "hidden" như Windows — chỉ là quy ước, `ls` mặc định không hiện. Dùng `ls -a` để thấy.

**Phần mở rộng (`.txt`, `.sh`) không quyết định loại file** trên Linux. Một file tên `backup` không đuôi vẫn có thể là script chạy được. Lệnh `file` đọc nội dung để đoán loại thật.

### 4.4. 🟨 Liên kết mềm và liên kết cứng

- **Symbolic link (liên kết mềm)**: giống shortcut — một file nhỏ chứa **đường dẫn** tới file khác. Xóa file gốc → link bị "gãy". Dùng rất nhiều trong thực tế, ví dụ Nginx: `/etc/nginx/sites-enabled/taskhub` → `/etc/nginx/sites-available/taskhub`.
- **Hard link (liên kết cứng)**: một **tên khác** cho cùng dữ liệu trên đĩa. Xóa một tên, dữ liệu vẫn còn cho đến khi xóa hết mọi tên. Ít dùng hằng ngày.

Để hiểu hard link, cần biết **inode**: mỗi file trên đĩa có một inode — bản ghi chứa quyền, chủ sở hữu, kích thước, vị trí dữ liệu. **Tên file chỉ là nhãn trỏ tới inode.** Hard link = thêm một nhãn nữa trỏ tới cùng inode.

> 🟨 Ổ đĩa có thể "đầy" dù còn dung lượng nếu **hết inode** (thường do hàng triệu file nhỏ). Kiểm tra bằng `df -i`. Sẽ gặp lại ở bài 07.

### 4.5. 🟥 Mount: gắn ổ đĩa vào cây thư mục

Ổ đĩa (hoặc phân vùng) muốn dùng được phải được **mount** (gắn) vào một thư mục — gọi là **mount point**. Ví dụ trên một server EC2:

- Ổ hệ điều hành gắn vào `/`.
- Ổ dữ liệu thêm vào gắn ở `/data`.

Trên WSL, ổ `C:` của Windows được gắn vào `/mnt/c`. Đây là lý do bạn đi được từ Linux sang file Windows.

### 4.6. 🟥 WSL2 khác server Linux thật ở đâu?

WSL2 chạy một **kernel Linux thật** bên trong một máy ảo nhẹ do Windows quản lý. Phần lớn lệnh chạy giống hệt server, nhưng có những khác biệt cần biết:

| Khía cạnh | WSL2 | Server Linux thật (EC2) |
|---|---|---|
| Kernel | Do Microsoft build, tên có chữ `microsoft-standard-WSL2` | Kernel của distribution hoặc AWS |
| Khởi động | Không có quá trình boot đầy đủ; `/boot` gần như trống | Boot đầy đủ qua bootloader |
| systemd | Chỉ có nếu được bật (bài 04 sẽ kiểm tra) | Luôn có |
| Mạng | Mặc định đi qua NAT của Windows | Card mạng thật/ảo, IP trong VPC |
| Ổ Windows | Có ở `/mnt/c` | Không có |
| Tắt máy | `wsl --shutdown` từ PowerShell | `sudo shutdown` / `reboot` |
| Firewall | Windows Firewall bên ngoài | `ufw`/`iptables` trên chính server + Security Group |

Kết luận: WSL rất tốt để **học lệnh và làm việc hằng ngày**. Những bài về mạng, firewall, SSH server sẽ được làm lại trên EC2 ở tuần 11–12 để có trải nghiệm thật.

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Nginx không khởi động được"

Một kỹ sư có kinh nghiệm sẽ đi theo bản đồ filesystem, không đoán mò:

1. Cấu hình ở đâu? → `/etc/nginx/nginx.conf` và `/etc/nginx/sites-enabled/`.
2. Log ở đâu? → `/var/log/nginx/error.log`.
3. Trang web được phục vụ từ đâu? → thường là `/var/www/`.
4. Process có đang chạy không? → xem trong `/proc` (hoặc dùng `ps`, học ở bài 04).

### Ví dụ 2: Xem RAM mà không cần cài công cụ

Trong một container tối giản không có `free` hay `top`, bạn vẫn đọc được:

```bash
head -3 /proc/meminfo
```

```text
MemTotal:        8029312 kB
MemFree:         5120044 kB
MemAvailable:    6823380 kB
```

Công cụ như `free` thực chất cũng chỉ đọc file này rồi trình bày lại cho đẹp.

---

## 6. Sơ đồ kiến trúc

### 6.1. Điều gì xảy ra khi bạn gõ `ls /etc`

```text
 ┌──────────────────────────────────────────────────────────┐
 │  Windows Terminal (hiển thị chữ, nhận bàn phím)          │
 └───────────────┬──────────────────────────────────────────┘
                 │ chữ "ls /etc"
 ┌───────────────▼──────────────────────────────────────────┐
 │ USERSPACE                                                │
 │  bash ──(1) tìm "ls" trong $PATH → /usr/bin/ls           │
 │       ──(2) yêu cầu kernel tạo process mới chạy ls       │
 │  ls   ──(3) system call: mở và đọc thư mục /etc          │
 └───────────────┬──────────────────────────────────────────┘
                 │ system call
 ┌───────────────▼──────────────────────────────────────────┐
 │ KERNEL: quản lý process · bộ nhớ · filesystem · mạng     │
 └───────────────┬──────────────────────────────────────────┘
                 │ driver
 ┌───────────────▼──────────────────────────────────────────┐
 │ PHẦN CỨNG: CPU · RAM · ổ đĩa · card mạng                 │
 └──────────────────────────────────────────────────────────┘
```

### 6.2. Một cây thư mục — nhiều ổ đĩa

```text
/                      ← ổ hệ điều hành
├── etc/               cấu hình
├── home/phuong/       dữ liệu của bạn
├── var/log/           log
├── proc/              (ảo — kernel tạo ra, không nằm trên đĩa)
└── mnt/
    └── c/             ← ổ C: của Windows được mount vào đây (chỉ có trên WSL)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `pwd` | Đang đứng ở thư mục nào | 🟥 |
| `cd` | Chuyển thư mục | 🟥 |
| `ls` | Liệt kê nội dung thư mục | 🟥 |
| `file` | Đoán loại file dựa vào nội dung | 🟥 |
| `stat` | Xem chi tiết một file (quyền, chủ, thời gian, inode) | 🟨 |
| `cat /etc/os-release` | Xem distribution và phiên bản | 🟥 |
| `uname -a` | Xem thông tin kernel | 🟥 |
| `df -h` | Dung lượng các ổ đã mount | 🟥 |
| `findmnt` | Xem cây mount | 🟨 |
| `ln -s` | Tạo liên kết mềm | 🟨 |
| `readlink -f` | Xem link thực sự trỏ tới đâu | 🟨 |
| `type`, `which` | Lệnh này là gì, nằm ở đâu | 🟥 |
| `man`, `--help` | Đọc hướng dẫn sử dụng | 🟥 |
| `echo $?` | Xem exit code của lệnh vừa chạy | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu dưới đây lấy từ Ubuntu 24.04 trên WSL. Số liệu trên máy bạn (kích thước, ngày giờ, phiên bản kernel) sẽ khác — **cấu trúc** mới là thứ cần hiểu.

### `pwd` — print working directory

```bash
pwd
```

```text
/home/phuong
```

Không có gì phức tạp, nhưng hãy tập thói quen chạy `pwd` mỗi khi không chắc mình đang ở đâu — **trước** khi chạy lệnh xóa hoặc ghi đè.

### `cd` — change directory

```bash
cd /etc          # đường dẫn tuyệt đối
cd nginx         # tương đối: vào /etc/nginx (nếu đã cài nginx)
cd ..            # lên thư mục cha
cd ~             # về home (gõ riêng "cd" cũng được)
cd -             # quay lại thư mục vừa ở trước đó
```

`cd` không in gì nếu thành công. Nếu lỗi:

```text
bash: cd: /etx: No such file or directory
```

### `ls` — list

```bash
ls -lah /etc/ssh
```

```text
total 600K
drwxr-xr-x   4 root root 4.0K Oct 20 09:12 .
drwxr-xr-x 104 root root 4.0K Oct 31 08:01 ..
-rw-r--r--   1 root root 1.6K Feb 26  2024 ssh_config
drwxr-xr-x   2 root root 4.0K Feb 26  2024 ssh_config.d
```

| Tham số | Ý nghĩa |
|---|---|
| `-l` | Dạng dài (long): hiện quyền, chủ sở hữu, kích thước, ngày sửa |
| `-a` | Hiện cả file ẩn (all), gồm `.` và `..` |
| `-h` | Kích thước dễ đọc (human-readable): `1.6K` thay vì `1600` |
| `-t` | Sắp theo thời gian sửa, mới nhất lên đầu — rất hay dùng khi tìm log mới |
| `-r` | Đảo thứ tự (reverse). `ls -ltr`: mới nhất ở **cuối**, ngay trên dấu nhắc lệnh |
| `-d` | Hiện chính thư mục, không hiện nội dung bên trong |

**Đọc một dòng `ls -l`:**

```text
-rw-r--r--  1   root  root  1.6K  Feb 26 2024  ssh_config
│└──┬────┘  │   │     │     │     │            └ tên
│   │       │   │     │     │     └ thời điểm sửa gần nhất
│   │       │   │     │     └ kích thước
│   │       │   │     └ group sở hữu
│   │       │   └ user sở hữu
│   │       └ số hard link
│   └ quyền (học kỹ ở bài 03)
└ loại file: "-" file thường, "d" thư mục, "l" link
```

### `file` — đoán loại file

```bash
file /etc/hostname /usr/bin/ls /bin
```

```text
/etc/hostname: ASCII text
/usr/bin/ls:   ELF 64-bit LSB pie executable, x86-64, dynamically linked, ...
/bin:          symbolic link to usr/bin
```

`ELF` là định dạng chương trình chạy được trên Linux (tương đương `.exe` trên Windows).

### `stat` — chi tiết một file

```bash
stat /etc/hostname
```

```text
  File: /etc/hostname
  Size: 7          Blocks: 8          IO Block: 4096   regular file
Device: 820h/2080d Inode: 2236        Links: 1
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2026-10-31 08:01:12.000000000 +0700
Modify: 2026-10-20 09:12:44.000000000 +0700
Change: 2026-10-20 09:12:44.000000000 +0700
```

Những dòng quan trọng: `Inode` (số inode), `Access: (0644/...)` (quyền dạng số và chữ), `Uid`/`Gid` (chủ sở hữu), `Modify` (nội dung sửa lần cuối), `Change` (thuộc tính như quyền đổi lần cuối).

### `cat /etc/os-release` và `uname` — mình đang chạy gì?

```bash
cat /etc/os-release
```

```text
PRETTY_NAME="Ubuntu 24.04.1 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION_CODENAME=noble
ID=ubuntu
...
```

```bash
uname -a
```

```text
Linux LEGION 5.15.167.4-microsoft-standard-WSL2 #1 SMP ... x86_64 x86_64 x86_64 GNU/Linux
```

| Tham số `uname` | Hiện |
|---|---|
| `-r` | Chỉ phiên bản kernel (dùng nhiều nhất) |
| `-m` | Kiến trúc CPU: `x86_64` hoặc `aarch64` (ARM — gặp lại khi chọn EC2 Graviton) |
| `-a` | Tất cả |

> Hai lệnh này là thói quen đầu tiên khi SSH vào một server lạ: biết distribution nào thì mới biết dùng `apt` hay `dnf`, biết kiến trúc nào thì mới tải đúng bản phần mềm.

### `df -h` — dung lượng ổ đĩa

```bash
df -h
```

```text
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdc       1007G   12G  944G   2% /
tmpfs           3.9G     0  3.9G   0% /mnt/wsl
C:\             476G  301G  176G  64% /mnt/c
...
```

| Cột | Ý nghĩa |
|---|---|
| `Filesystem` | Thiết bị hoặc nguồn được mount |
| `Size / Used / Avail` | Tổng / đã dùng / còn trống |
| `Use%` | **Cột cần nhìn đầu tiên** khi có cảnh báo đầy ổ |
| `Mounted on` | Gắn vào thư mục nào |

Tham số hay dùng: `-h` (dễ đọc), `-i` (xem inode thay vì dung lượng), `-T` (hiện loại filesystem: ext4, tmpfs…).

### `findmnt` — cây mount

```bash
findmnt -t ext4,9p
```

Hiện các mount point dạng cây. `-t` lọc theo loại filesystem. Trên WSL, ổ Windows thường có loại `9p`.

### `ln -s` và `readlink -f` — liên kết mềm

```bash
cd ~/devops-lab/01-linux
echo "hello" > original.txt
ln -s original.txt shortcut.txt     # ln -s <đích> <tên-link>
ls -l shortcut.txt
readlink -f shortcut.txt
```

```text
lrwxrwxrwx 1 phuong phuong 12 Oct 31 09:00 shortcut.txt -> original.txt
/home/phuong/devops-lab/01-linux/original.txt
```

> ⚠️ Thứ tự tham số của `ln -s` là **đích trước, tên link sau** — ngược với cảm giác của nhiều người. Nhớ: "`ln -s` cái-có-sẵn cái-mới".

### `type` và `which` — lệnh này là gì?

```bash
type cd ls
which ls
```

```text
cd is a shell builtin
ls is aliased to `ls --color=auto'
/usr/bin/ls
```

- `cd` là lệnh **có sẵn trong Bash** (builtin) — không có file chương trình riêng.
- `ls` là chương trình ở `/usr/bin/ls`, nhưng đang bị **alias** (tên tắt) thêm `--color=auto`.

Bash tìm chương trình trong các thư mục liệt kê ở biến `PATH` (`echo $PATH`). Lỗi `command not found` nghĩa là không thư mục nào trong `PATH` chứa chương trình đó. Biến môi trường được học kỹ ở bài 06.

### `man` và `--help` — tự tra cứu

```bash
ls --help | head -20     # bản tóm tắt nhanh
man ls                   # hướng dẫn đầy đủ
```

Trong `man`: phím `/` để tìm, `n` sang kết quả tiếp theo, `q` để thoát.

> Nếu `man` báo trang hướng dẫn đã bị lược bỏ: bản Ubuntu tối giản có thể không kèm man page. Lệnh `unminimize` sẽ cài lại đầy đủ, nhưng nó cài thêm nhiều gói — hãy tự quyết định có chạy hay không. Bạn luôn có thể dùng `--help` hoặc đọc man page online tại [manpages.ubuntu.com](https://manpages.ubuntu.com/).

### `echo $?` — exit code

Mỗi lệnh khi kết thúc trả về một con số gọi là **exit code** (mã thoát):

- `0` = thành công.
- Khác `0` = có lỗi. Ý nghĩa cụ thể tùy chương trình.

```bash
ls /etc > /dev/null
echo $?
ls /khong-ton-tai
echo $?
```

```text
0
ls: cannot access '/khong-ton-tai': No such file or directory
2
```

Exit code là thứ mà **script, CI/CD pipeline, Docker healthcheck và systemd** dùng để biết một bước thành công hay thất bại. Bạn sẽ gặp nó trong mọi module sau.

---

## 9. Bài thực hành từng bước

**Lab: Thám hiểm `/etc`, `/var/log`, `/proc`** · `[WSL]` · ~60 phút

Mục tiêu: tự tìm thông tin hệ thống bằng terminal. Ghi câu trả lời vào file `~/devops-lab/01-linux/lab01-answers.md` và commit vào repo `devops-journey` (xem [Ôn tập Git nhanh](../03-GIT/00-git-quick-review.md)).

### Bước 1 — Xác định mình đang chạy gì

```bash
cat /etc/os-release
uname -r
uname -m
```

❓ Ghi lại: tên + phiên bản Ubuntu, phiên bản kernel, kiến trúc CPU. Chuỗi kernel cho biết bạn đang trên WSL hay máy thật?

### Bước 2 — Khám phá `/etc`

```bash
cd /etc
ls | wc -l          # đếm số mục trong /etc ("wc -l" đếm dòng — học kỹ ở bài 02)
cat hostname
cat hosts
ls -l resolv.conf
```

❓ Tên máy (hostname) của bạn là gì? File `/etc/hosts` dùng để làm gì (đoán từ nội dung, sẽ học kỹ ở Module 02)? `resolv.conf` là file thường hay link? Nó trỏ tới đâu?

### Bước 3 — Khám phá `/var/log`

```bash
cd /var/log
ls -lt | head -10
```

❓ File log nào được sửa gần đây nhất? Có thư mục `journal` không? (Nếu có, hệ thống đang dùng systemd-journald — sẽ học ở bài 04 và 07.)

### Bước 4 — Khám phá `/proc`

```bash
cat /proc/cpuinfo | grep "model name" | head -1
grep -c processor /proc/cpuinfo
head -3 /proc/meminfo
cat /proc/uptime
```

❓ CPU của bạn là gì, bao nhiêu nhân logic? Tổng RAM WSL thấy được? (So sánh với RAM thật của laptop — WSL mặc định chỉ được dùng một phần.)

`/proc/uptime` có 2 số: số giây hệ thống đã chạy, và tổng thời gian nghỉ của các CPU.

### Bước 5 — Mỗi process là một thư mục trong `/proc`

```bash
echo $$                  # PID (mã số process) của shell bạn đang dùng
ls /proc/$$/
cat /proc/$$/status | head -10
readlink /proc/$$/cwd    # thư mục làm việc hiện tại của shell
cd /tmp && readlink /proc/$$/cwd
```

❓ Sau khi `cd /tmp`, kết quả `readlink` thay đổi thế nào? Điều này chứng minh điều gì về `/proc`?

### Bước 6 — Ổ đĩa và mount

```bash
df -h
findmnt /mnt/c
```

❓ Ổ `/` của WSL còn trống bao nhiêu? Ổ `C:` được mount vào đâu, loại filesystem gì?

### Bước 7 — So sánh với container `[Sandbox]`

Mở một terminal khác:

```bash
docker run --rm -it ubuntu:22.04 bash
```

Trong container chạy lại:

```bash
cat /etc/os-release
uname -r
ls /mnt
ps aux 2>/dev/null || ls /proc | grep -E '^[0-9]+$'
exit
```

❓ Phiên bản kernel trong container có giống WSL không? Vì sao? Container có thấy `/mnt/c` không? Container có bao nhiêu process?

> Câu trả lời của Bước 7 là một trong những ý quan trọng nhất của cả Module 04 (Docker). Hãy tự suy nghĩ trước khi đọc tiếp ở mục 10.

### Bước 8 — Commit kết quả

```bash
cd ~/devops-journey          # repo tạo ở bài Ôn tập Git
cp ~/devops-lab/01-linux/lab01-answers.md week01/
git add week01/lab01-answers.md
git commit -m "docs(linux): lab 01 - explore filesystem"
git push
```

---

## 10. Kết quả mong đợi

Sau lab, file `lab01-answers.md` của bạn phải trả lời được các ý sau:

- Bước 1: Ubuntu 24.04.x LTS, kernel có chữ `microsoft-standard-WSL2`, kiến trúc `x86_64`.
- Bước 2: `/etc/hosts` ánh xạ tên máy → địa chỉ IP trên máy cục bộ. Trên WSL, `resolv.conf` thường là **link** (hoặc file do WSL tự sinh) — WSL tự tạo cấu hình DNS.
- Bước 5: `readlink /proc/$$/cwd` đổi theo thư mục bạn `cd` tới → `/proc` không phải file lưu trên đĩa mà là **thông tin trực tiếp từ kernel**, cập nhật theo thời gian thực.
- Bước 7:
  - Kernel trong container **giống hệt** WSL. Container **không có kernel riêng** — nó dùng chung kernel với máy chủ. Đó là khác biệt cốt lõi giữa container và máy ảo.
  - Container có `/etc/os-release` của Ubuntu 22.04 riêng (trong khi WSL của bạn là 24.04), không thấy `/mnt/c`, chỉ có 1–2 process → nó có **filesystem riêng** và **danh sách process riêng** (nhờ cơ chế namespace — học ở Module 04).

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `No such file or directory` | Gõ sai tên, sai hoa/thường, sai thư mục hiện tại | Linux **phân biệt hoa/thường**: `Readme.md` ≠ `README.md`. Dùng phím **Tab** để tự hoàn thành tên — vừa nhanh vừa tránh sai |
| `cd: too many arguments` hoặc lỗi với tên có dấu cách | Tên file chứa dấu cách | Đặt trong nháy: `cd "My Folder"` hoặc `cd My\ Folder`. Tốt nhất: **không đặt tên có dấu cách** |
| `Not a directory` | `cd` vào một file | Kiểm tra bằng `ls -l` hoặc `file` |
| `Permission denied` khi `ls /root` | Thư mục của root, user thường không có quyền | Đúng như thiết kế. Học kỹ ở bài 03 |
| Thao tác file trong `/mnt/c/...` **rất chậm**, quyền file hiển thị lạ (`777`) | Truy cập ổ Windows từ Linux phải đi qua lớp chuyển đổi; quyền Linux không được lưu thật | **Để mọi dự án trong `~` của WSL.** Mở bằng VS Code: `code .` từ trong WSL |
| Script báo `/bin/bash^M: bad interpreter` | File được sửa trên Windows, xuống dòng kiểu **CRLF** (`\r\n`) thay vì **LF** (`\n`) | Chuyển editor sang LF (VS Code: góc dưới phải, bấm `CRLF` → chọn `LF`). Sửa file bằng `sed -i 's/\r$//' script.sh`. Đặt `git config --global core.autocrlf input` trong WSL |
| Xóa nhầm file bằng `rm` | Linux **không có thùng rác** cho `rm` | Chạy `pwd` và `ls` trước khi xóa. Thử nghiệm trong `[Sandbox]` |

---

## 12. Đọc thông báo lỗi và xử lý

Kỹ năng debug bắt đầu bằng việc **đọc hết thông báo lỗi** thay vì lướt qua. Phần lớn thông báo lỗi của công cụ Linux theo cấu trúc:

```text
<chương trình>: <đối tượng bị lỗi>: <mô tả lỗi>
```

Ví dụ:

```text
ls: cannot access '/var/log/nginx': No such file or directory
│    │                               └ mô tả: không tồn tại
│    └ đối tượng: đường dẫn /var/log/nginx
└ chương trình báo lỗi: ls
```

```text
bash: cd: /root: Permission denied
│     │   │      └ mô tả: không có quyền
│     │   └ đối tượng
│     └ lệnh builtin cd
└ shell bash báo lỗi
```

**Quy trình 4 bước khi gặp lỗi (áp dụng cho cả khóa học):**

1. **Đọc** toàn bộ thông báo. Xác định: chương trình nào? đối tượng nào? lỗi gì?
2. **Kiểm tra giả thuyết** bằng lệnh quan sát (không sửa gì): `ls -l`, `pwd`, `file`, `stat`, `echo $?`.
3. **Sửa một thứ** mỗi lần, chạy lại, quan sát kết quả.
4. **Ghi lại** vào `troubleshooting-journal.md`: triệu chứng → nguyên nhân → cách tìm ra → cách sửa.

Mẫu ghi nhật ký (lưu ở repo `devops-journey`):

```markdown
## 2026-11-02 — Script báo bad interpreter
- Triệu chứng: `./backup.sh` → `/bin/bash^M: bad interpreter: No such file or directory`
- Giả thuyết: có ký tự lạ trong dòng shebang
- Kiểm tra: `file backup.sh` → "with CRLF line terminators"
- Nguyên nhân: sửa file trên Windows, xuống dòng CRLF
- Cách sửa: `sed -i 's/\r$//' backup.sh`; đổi VS Code sang LF
- Bài học: bật `core.autocrlf input` trong WSL
```

Hai nguồn thông tin bổ sung khi lỗi không rõ ràng:

- `echo $?` — lệnh có thực sự thất bại không, mã lỗi bao nhiêu.
- `man <lệnh>` → tìm mục `EXIT STATUS` để biết ý nghĩa mã lỗi.

---

## 13. Câu hỏi kiểm tra kiến thức

Trả lời bằng lời của bạn, không chép lại bài.

1. Kernel, system call và userspace khác nhau thế nào? Khi bạn chạy `cat file.txt`, phần nào làm việc gì?
2. Ubuntu và Linux có phải là một không? Giải thích.
3. Terminal và Shell khác nhau thế nào?
4. Bạn được báo "server sắp đầy ổ cứng". Kể tên 3 thư mục bạn kiểm tra đầu tiên và lý do.
5. Bạn cần tìm file cấu hình SSH server. Bạn đoán nó nằm ở thư mục nào, dựa vào nguyên tắc gì?
6. Vì sao `/proc` không chiếm dung lượng ổ đĩa?
7. Liên kết mềm khác liên kết cứng thế nào? Xóa file gốc thì mỗi loại ra sao?
8. Vì sao trong script nên dùng đường dẫn tuyệt đối?
9. Exit code `0` nghĩa là gì? Ai/cái gì dùng exit code?
10. Nêu 3 khác biệt giữa WSL2 và một server EC2 có thể làm một lệnh chạy khác nhau.
11. Container có kernel riêng không? Bạn chứng minh bằng cách nào ở Bước 7?
12. Vì sao không nên đặt dự án trong `/mnt/c`?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/01-solutions.md](solutions/01-solutions.md) — chỉ mở sau khi đã tự làm và ghi câu trả lời.

**Bài 1 — Bản đồ của riêng bạn.** Vẽ (bằng chữ, như mục 6.2) cây thư mục gồm ít nhất 12 thư mục quan trọng trong WSL của bạn, kèm 1 dòng mô tả mỗi thư mục và 1 ví dụ file thật bạn tìm thấy trong đó.

**Bài 2 — Thám tử link.** Tìm 3 liên kết mềm có sẵn trong hệ thống (gợi ý: nhìn trong `/`, `/etc`, `/usr/bin`). Với mỗi link, cho biết nó trỏ tới đâu và đoán lý do hệ thống dùng link ở đó.

**Bài 3 — Không có công cụ.** Trong `[Sandbox]` (không cài thêm gói nào), chỉ dùng `cat`, `head`, `grep` và filesystem `/proc`, hãy tìm: (a) tổng RAM, (b) số nhân CPU, (c) PID của shell, (d) lệnh đã khởi chạy process số 1. Gợi ý cho (d): mỗi process có file `cmdline`.

**Bài 4 — Link gãy.** Tạo một symbolic link, rồi xóa file gốc. `ls -l` hiện link đó thế nào? `cat` link đó báo lỗi gì? Tìm cách liệt kê mọi link gãy trong một thư mục (gợi ý: `find` với `-xtype l` — đọc `man find`).

**Bài 5 — CRLF.** Trên Windows (Notepad), tạo một file `hello.sh` gồm 2 dòng `#!/bin/bash` và `echo hello`, lưu với CRLF vào thư mục WSL của bạn (đường dẫn `\\wsl.localhost\Ubuntu\home\<user>\` hoặc `\\wsl$\Ubuntu\home\<user>\` — tên distro xem bằng `wsl -l -v`). Trong WSL chạy `bash hello.sh` và `chmod +x hello.sh && ./hello.sh`. Ghi lại lỗi, chẩn đoán bằng `file` và `cat -A`, sửa nó, và viết một mục `troubleshooting-journal.md` hoàn chỉnh.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Giải thích được sơ đồ mục 6.1 cho một người khác mà không nhìn tài liệu.
- [ ] Được hỏi "cấu hình / log / dữ liệu / app tự cài của X nằm đâu", bạn trả lời được theo nguyên tắc chứ không phải học thuộc.
- [ ] Đọc được mọi cột của `ls -l` và `df -h`.
- [ ] Tự giải thích được vì sao kernel trong container giống WSL.
- [ ] Gặp lỗi, bạn tự động đọc theo cấu trúc `chương trình: đối tượng: mô tả` và kiểm tra `echo $?`.
- [ ] Làm xong Bài tập 3 và 5 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Linux Journey — Grasshopper: Getting Started, Command Line](https://labex.io/linuxjourney) | Ôn lại bằng bài ngắn, có playground | 2026-10-31 |
| [Ubuntu Server docs](https://ubuntu.com/server/docs) | Tra cứu chính thức | 2026-10-31 |
| [MIT Missing Semester — Introduction to the Shell](https://missing.csail.mit.edu/) | Hiểu shell sâu hơn | 2026-10-31 |
| [Microsoft Learn — systemd in WSL](https://learn.microsoft.com/en-us/windows/wsl/systemd) | Khác biệt WSL | 2026-10-31 |
| `man hier` (chạy trên máy) | Mô tả chính thức cây thư mục Linux | — |
