# 03. Permissions, Users & Groups

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Kiến trúc Linux & Filesystem](01-linux-architecture-filesystem.md), [02. Lệnh thiết yếu & xử lý văn bản](02-essential-commands-text.md)
> Môi trường: `[Sandbox]` container `ubuntu:22.04` (phần lớn bài), `[WSL]` Ubuntu 24.04 (bước chuẩn bị cho bài 04)

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

- Đọc và giải thích chuỗi quyền như `-rw-r-----`, `drwxr-s---`, và biết quyền `r`, `w`, `x` **khác nhau thế nào giữa file và thư mục**.
- Đổi quyền bằng `chmod` (dạng số và dạng ký hiệu), đổi chủ sở hữu bằng `chown`, `chgrp`; hiểu `umask` quyết định quyền mặc định ra sao.
- Hiểu các file `/etc/passwd`, `/etc/shadow`, `/etc/group`; tạo, sửa, xóa user và group.
- Phân biệt `su` và `sudo`, cấp quyền sudo có giới hạn qua `/etc/sudoers.d/`.
- Tạo **system user** (user hệ thống) cho ứng dụng và thiết kế quyền thư mục theo **nguyên tắc đặc quyền tối thiểu** (least privilege).
- Chẩn đoán và sửa lỗi `Permission denied` có phương pháp, không dùng `chmod 777`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

`Permission denied` có lẽ là lỗi bạn sẽ gặp **nhiều nhất** trong sự nghiệp. Nó xuất hiện ở mọi tầng:

| Tình huống | Gốc rễ là quyền |
|---|---|
| App Spring Boot không ghi được log: `FileNotFoundException: /var/log/taskhub/app.log (Permission denied)` | User chạy app không có quyền ghi vào thư mục log |
| Nginx trả 403, error log ghi `open() ... failed (13: Permission denied)` | User `www-data` không đi vào được một thư mục trên đường dẫn |
| `ssh` từ chối dùng private key: `UNPROTECTED PRIVATE KEY FILE!` | File key có quyền quá rộng (học ở [bài 05](05-packages-ssh.md)) |
| `docker ps` báo `permission denied while trying to connect to the Docker daemon socket` | User chưa thuộc group `docker` |
| Container chạy bằng non-root không ghi được volume | UID trong container không khớp chủ sở hữu thư mục trên host (Module 04) |

Ngoài ra là **bảo mật**: ứng dụng bị hack sẽ chỉ làm được những gì user chạy nó được phép làm. App chạy bằng `root` bị chiếm quyền = cả server bị chiếm quyền. Thiết kế quyền đúng là lớp phòng thủ đầu tiên.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Linux là hệ thống nhiều người dùng

Ngay cả khi chỉ có mình bạn dùng server, trên đó vẫn có hàng chục "user": `root`, `www-data` (Nginx), `postgres`, `systemd-network`… Mỗi **process** chạy dưới danh nghĩa một user, và kernel kiểm tra quyền dựa trên user đó.

Kernel không làm việc với **tên** user mà với **con số**:

- **UID** (User ID — mã số người dùng): `root` luôn là `0`.
- **GID** (Group ID — mã số nhóm).

Tên chỉ là nhãn cho con người đọc, được ánh xạ qua file `/etc/passwd` và `/etc/group`. Điều này rất quan trọng khi làm với container: trong container, UID `1000` có thể tên là `app`, trên host UID `1000` lại là `phuong` — kernel coi họ là **cùng một người**.

### 3.2. Mỗi file có 1 chủ, 1 nhóm, 3 bộ quyền

Mỗi file/thư mục lưu trong inode:

- **Owner** (chủ sở hữu) — một user.
- **Group** (nhóm sở hữu) — một group.
- **3 bộ quyền** cho 3 đối tượng:
  - `u` — user: chủ sở hữu.
  - `g` — group: thành viên của nhóm sở hữu.
  - `o` — others: tất cả những người còn lại.

### 3.3. Kernel kiểm tra quyền theo thứ tự — và dừng ở bước đầu tiên khớp

```text
Process (UID, các GID) muốn truy cập file
        │
        ├─ UID = 0 (root)?            → được phép (gần như mọi thứ)
        ├─ UID = owner của file?       → dùng bộ quyền "u", DỪNG
        ├─ Một GID thuộc group file?   → dùng bộ quyền "g", DỪNG
        └─ Còn lại                     → dùng bộ quyền "o"
```

Hệ quả bất ngờ: nếu file có quyền `---r--r--`, chính **chủ sở hữu lại không đọc được**, dù người khác đọc được — vì kernel dừng ở bộ "u" và không xét tiếp.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Đọc chuỗi quyền

```text
- rwx r-x ---
│ └┬┘ └┬┘ └┬┘
│  │   │   └ others: không có quyền gì
│  │   └ group: đọc + thực thi
│  └ user (owner): đọc + ghi + thực thi
└ loại file (đã học ở bài 01)
```

Dấu `-` ở vị trí quyền nghĩa là **không có** quyền đó.

### 4.2. 🟥 `r`, `w`, `x` với file và với thư mục — khác nhau hoàn toàn

Đây là phần người mới hay hiểu sai nhất. Hãy hình dung **thư mục là một danh bạ**: nó chỉ chứa danh sách `tên → inode`, không chứa nội dung file.

| Quyền | Với **file** | Với **thư mục** |
|---|---|---|
| `r` (read) | Đọc nội dung file | **Liệt kê tên** các mục bên trong (`ls`) |
| `w` (write) | Sửa nội dung file | **Tạo, xóa, đổi tên** các mục bên trong (cần kèm `x`) |
| `x` (execute) | Chạy file như chương trình | **Đi vào / đi xuyên qua** thư mục (`cd`, truy cập file bên trong nếu biết tên) |

Ba hệ quả quan trọng:

1. **Muốn đọc `/var/log/taskhub/app.log`, cần `x` trên MỌI thư mục** trên đường dẫn (`/`, `/var`, `/var/log`, `/var/log/taskhub`) **và** `r` trên file. Thiếu `x` ở bất kỳ thư mục nào → `Permission denied`, dù file có quyền `rw-rw-rw-`.
2. **Xóa file phụ thuộc vào quyền `w` của thư mục chứa nó**, không phải quyền của chính file. Một file chỉ đọc (`r--r--r--`) vẫn bị xóa được nếu bạn có `w` trên thư mục.
3. Thư mục có `r` nhưng không có `x`: bạn thấy **tên** file nhưng không đọc được nội dung hay thông tin của chúng.

### 4.3. 🟥 Quyền dạng số (octal)

Mỗi quyền có một giá trị: `r = 4`, `w = 2`, `x = 1`. Cộng lại cho từng đối tượng:

| Số | Quyền | Số | Quyền |
|---|---|---|---|
| 7 | `rwx` (4+2+1) | 3 | `-wx` (hiếm dùng) |
| 6 | `rw-` (4+2) | 2 | `-w-` (hiếm dùng) |
| 5 | `r-x` (4+1) | 1 | `--x` |
| 4 | `r--` | 0 | `---` |

Các bộ quyền gặp **hằng ngày** — nên thuộc:

| Quyền | Chuỗi | Dùng cho |
|---|---|---|
| `644` | `rw-r--r--` | File thường, file cấu hình không bí mật |
| `640` | `rw-r-----` | File log, cấu hình chỉ cho nhóm đọc |
| `600` | `rw-------` | **Bí mật**: private key SSH, file `.env` chứa mật khẩu |
| `755` | `rwxr-xr-x` | Thư mục thường, script/chương trình ai cũng chạy được |
| `750` | `rwxr-x---` | Thư mục/script chỉ cho chủ và nhóm |
| `700` | `rwx------` | Thư mục riêng tư: `~/.ssh` |
| `777` | `rwxrwxrwx` | ⚠️ **Gần như không bao giờ đúng.** Ai cũng sửa/xóa được |

### 4.4. 🟥 `umask` — quyền mặc định khi tạo file mới

Khi một chương trình tạo file mới, quyền "tối đa" là `666` cho file (không tự có `x`) và `777` cho thư mục. **`umask`** là "mặt nạ" **gỡ bớt** quyền khỏi giá trị tối đa đó.

| umask | File mới | Thư mục mới | Ghi chú |
|---|---|---|---|
| `022` | `644` | `755` | Phổ biến cho root và nhiều hệ thống |
| `002` | `664` | `775` | Ubuntu thường dùng cho user thường (mỗi user có group riêng cùng tên) |
| `027` | `640` | `750` | Tốt cho service: others không đọc được gì |
| `077` | `600` | `700` | Rất chặt |

> Cách tính đúng là "gỡ bit" (phép AND với phần bù), không phải phép trừ, nhưng với các giá trị thông dụng ở bảng trên thì kết quả giống phép trừ.

`umask` là thuộc tính của **từng process** và được kế thừa cho process con. Đặt `umask` trong shell chỉ ảnh hưởng shell đó. Với service chạy bằng systemd, có tùy chọn `UMask=` riêng (bài 04).

### 4.5. 🟨 Quyền đặc biệt: setuid, setgid, sticky bit

Có thêm một chữ số thứ tư **đứng đầu** (ví dụ `2750`):

| Bit | Số | Trên file | Trên thư mục | Ví dụ thật |
|---|---|---|---|---|
| **setuid** | `4` | Chạy chương trình **với quyền của chủ file**, không phải người chạy | (không dùng) | `/usr/bin/passwd`: `-rwsr-xr-x root` — user thường đổi được mật khẩu dù `/etc/shadow` chỉ root ghi được |
| **setgid** | `2` | Chạy với quyền của group file | File mới tạo bên trong **kế thừa group của thư mục** thay vì group của người tạo | Thư mục dùng chung của team, thư mục log |
| **sticky** | `1` | (không dùng) | Chỉ **chủ file** (hoặc root) mới xóa được file của mình, dù ai cũng có `w` trên thư mục | `/tmp`: `drwxrwxrwt` |

Hiển thị trong `ls -l`: setuid/setgid thay `x` bằng `s` (hoặc `S` nếu không có `x` bên dưới), sticky thay `x` của others bằng `t`.

> 🟦 Chương trình có setuid root là mục tiêu ưa thích của hacker. Kiểm tra định kỳ: `find / -perm -4000 -type f 2>/dev/null`. Sẽ gặp lại ở Module 10.

### 4.6. 🟥 User và group: các file cấu hình

**`/etc/passwd`** — danh sách user, **ai cũng đọc được** (quyền `644`). Mỗi dòng 7 trường, phân cách bởi `:`:

```text
phuong:x:1000:1000:,,,:/home/phuong:/bin/bash
│      │ │    │    │   │            └ 7. shell đăng nhập
│      │ │    │    │   └ 6. thư mục home
│      │ │    │    └ 5. GECOS: mô tả (họ tên, số phòng...) — thường để trống
│      │ │    └ 4. GID của group chính (primary group)
│      │ └ 3. UID
│      └ 2. "x" = mật khẩu nằm trong /etc/shadow
└ 1. tên đăng nhập
```

**`/etc/shadow`** — mật khẩu đã **băm** (hash), chỉ root đọc được (`640 root:shadow`):

```text
phuong:$y$j9T$...rút gọn...:20000:0:99999:7:::
│      └ hash mật khẩu ($y$ = thuật toán yescrypt, mặc định từ Ubuntu 22.04)
│        Nếu là "!" hoặc "*": tài khoản không đăng nhập bằng mật khẩu được
```

**`/etc/group`** — danh sách group và thành viên **phụ**:

```text
sudo:x:27:phuong
│      │  └ danh sách thành viên (phân cách bằng dấu phẩy)
│      └ GID
└ tên group
```

Mỗi user có **một group chính** (ghi trong `/etc/passwd`, quyết định group của file mới tạo) và có thể thuộc **nhiều group phụ** (supplementary groups, ghi trong `/etc/group`).

> ⚠️ Không sửa các file này trực tiếp bằng editor. Dùng `useradd`, `usermod`, `groupadd`, `passwd` — chúng khóa file và kiểm tra cú pháp. Sửa hỏng `/etc/passwd` có thể khiến không ai đăng nhập được.

### 4.7. 🟥 Dải UID và system user

| UID | Loại | Ví dụ |
|---|---|---|
| `0` | root | `root` |
| `1–999` | **System user** (user hệ thống) — chạy dịch vụ, không phải người | `www-data` (33), `postgres`, `systemd-network` |
| `1000+` | Người dùng thật | `phuong` (1000) |
| `65534` | `nobody` — user "không có quyền gì" | |

**System user cho ứng dụng** — thực hành tốt nhất khi triển khai app:

- Không có mật khẩu, không đăng nhập được: shell là `/usr/sbin/nologin`.
- Thường không có thư mục home.
- Chỉ sở hữu đúng những thư mục app cần ghi.

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin taskhub
```

### 4.8. 🟥 `useradd` và `adduser`

| | `useradd` | `adduser` |
|---|---|---|
| Bản chất | Công cụ cấp thấp, có trên mọi distribution | Script thân thiện của Debian/Ubuntu, gọi `useradd` bên dưới |
| Tạo home | Chỉ khi có `-m` | Có, mặc định |
| Hỏi mật khẩu | Không (đặt sau bằng `passwd`) | Có, hỏi tương tác |
| Shell mặc định | `/bin/sh` nếu không chỉ định `-s` | `/bin/bash` |
| Dùng khi | **Script, tự động hóa** (không hỏi gì) | Tạo người dùng bằng tay |

Trong DevOps, ưu tiên `useradd` với đầy đủ tham số — vì nó chạy giống nhau trên Ubuntu, Red Hat, trong Dockerfile và trong Ansible.

### 4.9. 🟥 `usermod -aG` — và cái bẫy kinh điển

```bash
sudo usermod -aG docker phuong      # ĐÚNG: thêm (append) group docker
sudo usermod -G docker phuong       # ⚠️ SAI: THAY THẾ toàn bộ group phụ bằng mỗi "docker"
```

Thiếu `-a`, user bị loại khỏi mọi group phụ khác — **kể cả group `sudo`**. Nếu đó là user admin duy nhất, bạn vừa tự khóa mình khỏi quyền root.

Group mới **chỉ có hiệu lực ở phiên đăng nhập mới**. Process đang chạy giữ nguyên danh sách group cũ. Cần đăng xuất/đăng nhập lại, hoặc `newgrp <group>` để mở shell mới với group đó.

### 4.10. 🟥 `su` và `sudo`

| | `su` | `sudo` |
|---|---|---|
| Nghĩa | Switch user — đổi sang user khác | Superuser do — chạy **một lệnh** với quyền user khác (mặc định root) |
| Mật khẩu cần nhập | Của **user đích** (ví dụ mật khẩu root) | Của **chính bạn** |
| Ghi log | Ít | Mỗi lệnh được ghi vào `/var/log/auth.log` |
| Kiểm soát chi tiết | Không | Có: ai được chạy lệnh gì, với tư cách ai |
| Trên Ubuntu | Root mặc định **không có mật khẩu** → `su` thường không dùng được | Cách chuẩn để làm việc quản trị |

Các dạng `sudo` hay dùng:

```bash
sudo apt update                  # chạy 1 lệnh bằng root
sudo -u taskhub whoami           # chạy 1 lệnh bằng user taskhub
sudo -u taskhub bash             # mở shell bằng user taskhub (dùng được cả khi shell của nó là nologin)
sudo -i                          # mở shell đăng nhập của root (cẩn thận!)
sudo -l                          # xem mình được phép chạy những gì
```

Ai được dùng `sudo` do file `/etc/sudoers` và thư mục `/etc/sudoers.d/` quy định. Trên Ubuntu, thành viên group `sudo` được chạy mọi lệnh.

### 4.11. 🟨 Cấp quyền sudo giới hạn qua `/etc/sudoers.d/`

Thực tế bạn hay cần: "user deploy chỉ được restart service taskhub, không được làm gì khác".

```text
# /etc/sudoers.d/taskhub-deploy
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart taskhub
│      │   │      │         └ lệnh được phép (đường dẫn tuyệt đối)
│      │   │      └ không hỏi mật khẩu
│      │   └ được chạy với tư cách user root
│      └ trên mọi máy (host)
└ user được cấp quyền
```

> ⚠️ **Luôn sửa bằng `visudo`** (`sudo visudo -f /etc/sudoers.d/taskhub-deploy`). `visudo` kiểm tra cú pháp trước khi lưu. File sudoers sai cú pháp làm **`sudo` ngừng hoạt động hoàn toàn** — trên server không có mật khẩu root, đó là thảm họa. File trong `sudoers.d` nên có quyền `440`.

### 4.12. 🟥 Group `docker` tương đương quyền root

Tài liệu chính thức của Docker ghi rõ: *"The `docker` group grants root-level privileges to the user"* ([nguồn](https://docs.docker.com/engine/install/linux-postinstall/)). Lý do: ai điều khiển được Docker thì chạy được lệnh như:

```bash
docker run --rm -it -v /:/host ubuntu bash    # gắn toàn bộ ổ đĩa host vào container, với quyền root
```

→ đọc/sửa `/etc/shadow`, `/etc/sudoers` của host. Vì vậy: chỉ thêm vào group `docker` những người bạn tin tưởng như admin. Không bao giờ thêm user của ứng dụng vào group `docker`.

> Trên máy bạn, Docker Desktop tích hợp với WSL theo cách riêng nên có thể bạn chưa từng phải thêm group này. Trên EC2 cài Docker Engine thì sẽ phải (Module 06).

### 4.13. 🟦 ACL — khi 3 bộ quyền không đủ

Muốn cho **thêm một user cụ thể** đọc file mà không đổi group? Linux có ACL (Access Control List — danh sách kiểm soát truy cập): `setfacl -m u:alice:r file`, xem bằng `getfacl file`. Dấu `+` cuối chuỗi quyền (`-rw-r-----+`) cho biết file có ACL. Junior chỉ cần **nhận ra** dấu `+` khi gặp.

---

## 5. Ví dụ thực tế

### Ví dụ 1: Thiết kế quyền cho ứng dụng taskhub trên server

Yêu cầu: app chạy bằng user `taskhub`; đọc được code và cấu hình nhưng **không được sửa** chính nó; ghi được log; developer đọc được log; người khác không thấy gì.

| Đường dẫn | Owner:Group | Quyền | Lý do |
|---|---|---|---|
| `/opt/taskhub/` | `root:taskhub` | `750` | Root triển khai code; app chỉ đọc + đi vào |
| `/opt/taskhub/taskhub.jar` | `root:taskhub` | `640` | App đọc được, không sửa được — nếu bị hack cũng không ghi đè được code |
| `/opt/taskhub/application.yml` | `root:taskhub` | `640` | Chứa mật khẩu DB → others không đọc được |
| `/var/log/taskhub/` | `taskhub:devs` | `2750` | App tạo file log; setgid để file mới thuộc group `devs`; others không vào được |
| `/var/log/taskhub/app.log` | `taskhub:devs` | `640` | App ghi, devs đọc |

Đây chính là thiết kế bạn sẽ dựng trong lab.

### Ví dụ 2: Nginx trả 403 dù file `index.html` có quyền `644`

```text
2026/10/31 09:15:02 [error] 1234#1234: *1 open() "/home/phuong/site/index.html" failed (13: Permission denied)
```

File `644` — others đọc được. Nhưng Nginx chạy bằng `www-data`, và `/home/phuong` có quyền `750` → `www-data` không có `x` để đi qua. Kiểm tra cả đường dẫn bằng `namei -l` (mục 8) sẽ thấy ngay. Cách sửa đúng: đặt site ở `/var/www/`, **không** `chmod 777 /home/phuong`.

### Ví dụ 3: "Tôi chạy thử bằng sudo, giờ service không chạy được nữa"

Kỹ sư chạy thử `sudo java -jar /opt/taskhub/taskhub.jar` → app tạo `/var/log/taskhub/app.log` với owner **root**. Sau đó service chạy bằng user `taskhub` không ghi được file này nữa:

```text
java.io.FileNotFoundException: /var/log/taskhub/app.log (Permission denied)
```

Cách sửa: `sudo chown taskhub:devs /var/log/taskhub/app.log`. Bài học: **chạy thử bằng đúng user của service** — `sudo -u taskhub java -jar ...`.

---

## 6. Sơ đồ kiến trúc

### 6.1. Kiểm tra quyền dọc theo đường dẫn

Process của `alice` (UID 1000, thuộc group `devs`) chạy `cat /var/log/taskhub/app.log`:

```text
 /                drwxr-xr-x root    root     → alice là "others", có x  ✔ đi qua
 └─ var           drwxr-xr-x root    root     → others có x              ✔ đi qua
    └─ log        drwxrwxr-x root    syslog   → others có x              ✔ đi qua
       └─ taskhub drwxr-s--- taskhub devs     → alice thuộc devs, g có x ✔ đi qua
          └─ app.log -rw-r----- taskhub devs  → alice thuộc devs, g có r ✔ ĐỌC ĐƯỢC

 Cùng lệnh đó với bob (không thuộc devs):
          taskhub drwxr-s--- → bob là "others", o = ---  ✘ DỪNG: Permission denied
          (không cần xét đến quyền của app.log)
```

### 6.2. Quan hệ user — group — file

```text
  /etc/passwd                 /etc/group                     inode của file
 ┌─────────────────────┐     ┌──────────────────────┐      ┌─────────────────────────┐
 │ taskhub  UID 999    │     │ taskhub GID 999      │      │ owner UID = 999         │
 │          GID 999 ───┼────►│ devs    GID 1000     │◄─────┤ group GID = 1000        │
 │ alice    UID 1000   │     │   members: alice     │      │ mode = 0640 (rw-r-----) │
 │ bob      UID 1001   │     └──────────────────────┘      └─────────────────────────┘
 └─────────────────────┘
   Kernel chỉ so sánh SỐ (UID/GID). Tên chỉ để con người đọc.
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ls -l`, `ls -ld`, `stat -c` | Xem quyền và chủ sở hữu | 🟥 |
| `chmod` | Đổi quyền | 🟥 |
| `chown`, `chgrp` | Đổi chủ / nhóm sở hữu | 🟥 |
| `umask` | Xem/đặt quyền mặc định | 🟥 |
| `namei -l` | Xem quyền của **từng thư mục** trên đường dẫn | 🟥 |
| `whoami`, `id`, `groups` | Mình là ai, thuộc nhóm nào | 🟥 |
| `useradd`, `usermod`, `userdel` | Quản lý user | 🟥 |
| `groupadd`, `groupdel` | Quản lý group | 🟥 |
| `passwd` | Đặt mật khẩu, khóa tài khoản | 🟥 |
| `getent passwd/group` | Tra cứu user/group | 🟨 |
| `sudo`, `sudo -u`, `sudo -l` | Chạy lệnh với quyền khác | 🟥 |
| `su -` | Đổi sang user khác | 🟨 |
| `visudo` | Sửa sudoers an toàn | 🟨 |
| `getfacl`, `setfacl` | ACL | 🟦 |

---

## 8. Giải thích câu lệnh và tham số

> Phần này chạy trong `[Sandbox]` — bạn là root trong container, thoải mái thử. Mở sandbox:
> ```bash
> docker run --rm -it --name perm-lab ubuntu:22.04 bash
> ```
> Lệnh bắt đầu bằng `sudo` dưới đây là cách bạn sẽ gõ trên server thật. Trong sandbox bạn đã là root nên có thể bỏ `sudo`.

### `whoami`, `id`, `groups`

Trên WSL (user thường):

```bash
whoami
id
groups
```

```text
phuong
uid=1000(phuong) gid=1000(phuong) groups=1000(phuong),4(adm),20(dialout),24(cdrom),25(floppy),27(sudo),29(audio),30(dip),44(video),46(plugdev)
phuong adm dialout cdrom floppy sudo audio dip video plugdev
```

- `gid=1000(phuong)`: group chính — file bạn tạo sẽ thuộc group này.
- `groups=...`: mọi group bạn thuộc. Có `27(sudo)` → bạn được dùng `sudo`. Có `4(adm)` → bạn đọc được nhiều log hệ thống trong `/var/log`.

`id <tên-user>` xem thông tin của user khác.

### `chmod` — dạng số và dạng ký hiệu

```bash
mkdir -p /tmp/perm && cd /tmp/perm
touch script.sh secret.env
chmod 750 script.sh
chmod 600 secret.env
ls -l
```

```text
-rwxr-x--- 1 root root 0 Oct 31 09:00 script.sh
-rw------- 1 root root 0 Oct 31 09:00 secret.env
```

Dạng ký hiệu — sửa **một phần** quyền mà không cần tính lại cả con số:

```bash
chmod u+x file      # thêm x cho owner
chmod g-w file      # bỏ w của group
chmod o= file       # others: không có quyền gì
chmod a+r file      # all (u+g+o): thêm r
chmod u=rw,g=r,o= file   # đặt chính xác = 640
```

| Phần | Giá trị |
|---|---|
| Ai | `u` owner, `g` group, `o` others, `a` tất cả |
| Phép | `+` thêm, `-` bỏ, `=` đặt chính xác |
| Quyền | `r`, `w`, `x`, `s` (setuid/setgid), `t` (sticky) |

| Tham số | Ý nghĩa |
|---|---|
| `-R` | Đệ quy. ⚠️ `chmod -R 755` đặt cả file **và** thư mục giống nhau → mọi file thành chạy được |
| `X` (viết hoa) | 🟨 Chỉ thêm `x` cho thư mục (và file đã có x sẵn). `chmod -R u=rwX,g=rX,o= dir` là cách đúng để sửa quyền cả cây |
| `-v` | In từng thay đổi |

### `chown`, `chgrp`

```bash
groupadd devs
useradd --system --no-create-home --shell /usr/sbin/nologin taskhub
chown taskhub:devs secret.env      # đổi cả owner và group
chown root secret.env              # chỉ đổi owner
chown :taskhub secret.env          # chỉ đổi group (tương đương chgrp taskhub)
chgrp devs secret.env
ls -l secret.env
```

```text
-rw------- 1 root devs 0 Oct 31 09:00 secret.env
```

| Tham số | Ý nghĩa |
|---|---|
| `user:group` | Đổi cả hai |
| `-R` | Đệ quy |
| `--reference=file2` | 🟨 Đặt giống hệt `file2` |

Chỉ **root** đổi được owner của file. User thường chỉ đổi được group sang một group mà họ thuộc về.

### `stat -c` — in quyền gọn

```bash
stat -c '%a %A %U:%G %n' /etc/passwd /etc/shadow /tmp
```

```text
644 -rw-r--r-- root:root /etc/passwd
640 -rw-r----- root:shadow /etc/shadow
1777 drwxrwxrwt root:root /tmp
```

`%a` quyền dạng số, `%A` dạng chữ, `%U`/`%G` owner/group, `%n` tên. Rất tiện trong script kiểm tra cấu hình.

### `umask`

```bash
umask
umask -S
touch f1 && mkdir d1 && ls -ld f1 d1
umask 027
touch f2 && mkdir d2 && ls -ld f2 d2
```

```text
0022
u=rwx,g=rx,o=rx
-rw-r--r-- 1 root root    0 Oct 31 09:00 f1
drwxr-xr-x 2 root root 4096 Oct 31 09:00 d1
-rw-r----- 1 root root    0 Oct 31 09:00 f2
drwxr-x--- 2 root root 4096 Oct 31 09:00 d2
```

Trên WSL với user thường, bạn có thể thấy `0022` hoặc `0002` tùy cấu hình — hãy tự kiểm tra.

### Quyền đặc biệt

```bash
ls -l /usr/bin/passwd
ls -ld /tmp
mkdir shared && chgrp devs shared && chmod 2770 shared
ls -ld shared
```

```text
-rwsr-xr-x 1 root root 59976 Feb  6  2024 /usr/bin/passwd
drwxrwxrwt 1 root root  4096 Oct 31 09:00 /tmp
drwxrws--- 2 root devs  4096 Oct 31 09:00 shared
```

- `rws` ở owner của `passwd` → setuid.
- `rwt` ở others của `/tmp` → sticky.
- `rws` ở group của `shared` → setgid: file tạo trong đó sẽ thuộc group `devs`.

### `namei -l` — công cụ debug quyền tốt nhất

```bash
mkdir -p /var/log/taskhub && touch /var/log/taskhub/app.log
chown -R taskhub:devs /var/log/taskhub && chmod 2750 /var/log/taskhub && chmod 640 /var/log/taskhub/app.log
namei -l /var/log/taskhub/app.log
```

```text
f: /var/log/taskhub/app.log
drwxr-xr-x root    root   /
drwxr-xr-x root    root   var
drwxrwxr-x root    syslog log
drwxr-s--- taskhub devs   taskhub
-rw-r----- taskhub devs   app.log
```

Một lệnh cho thấy quyền của mọi thành phần trên đường dẫn — đúng thứ bạn cần khi debug `Permission denied`. (Owner/group của `/var/log` có thể khác trên máy bạn.)

### `useradd`, `usermod`, `passwd`, `userdel`

```bash
useradd -m -s /bin/bash -G devs alice
useradd -m -s /bin/bash bob
id alice
grep -E "^(alice|bob|taskhub):" /etc/passwd
```

```text
uid=1000(alice) gid=1001(alice) groups=1001(alice),1000(devs)
alice:x:1000:1001::/home/alice:/bin/bash
bob:x:1001:1002::/home/bob:/bin/bash
taskhub:x:999:999::/home/taskhub:/usr/sbin/nologin
```

(Số UID/GID trên máy bạn có thể khác. Ở đây group `devs` được tạo trước nên chiếm GID 1000, vì vậy group riêng của `alice` nhận GID 1001 — UID và GID của một user **không bắt buộc** bằng nhau. `taskhub` hiện home là `/home/taskhub` trong `/etc/passwd` nhưng thư mục đó **không được tạo** vì có `--no-create-home`.)

| Lệnh / tham số | Ý nghĩa |
|---|---|
| `useradd -m` | Tạo thư mục home |
| `useradd -s /bin/bash` | Shell đăng nhập |
| `useradd -G g1,g2` | Group phụ |
| `useradd --system` (`-r`) | System user: UID < 1000, không hết hạn mật khẩu |
| `useradd -u 1500` | Chỉ định UID (hữu ích khi cần khớp UID với container) |
| `usermod -aG g user` | **Thêm** group phụ (luôn có `-a`!) |
| `usermod -s /usr/sbin/nologin user` | Đổi shell — chặn đăng nhập |
| `usermod -L user` / `-U` | Khóa / mở khóa mật khẩu |
| `passwd user` | Đặt mật khẩu (root đặt cho người khác, user tự đổi của mình) |
| `passwd -l user` | Khóa mật khẩu |
| `userdel user` | Xóa user, **giữ** home |
| `userdel -r user` | ⚠️ Xóa user **và** home + mail spool |
| `groupadd g`, `groupdel g` | Tạo / xóa group |
| `gpasswd -d user g` | 🟨 Gỡ user khỏi một group |

### `su` và `sudo` trong sandbox

```bash
apt-get update -qq && apt-get install -y -qq sudo      # image tối giản chưa có sudo
su - taskhub
sudo -u taskhub whoami
sudo -u taskhub bash -c 'id; umask'
```

```text
This account is currently not available.
taskhub
uid=999(taskhub) gid=999(taskhub) groups=999(taskhub)
0022
```

- `su - taskhub` thất bại vì shell của `taskhub` là `nologin` — **đúng như mong muốn**.
- `sudo -u taskhub <lệnh>` vẫn chạy được lệnh bằng user đó → cách chuẩn để **thử app bằng đúng user của service**.

### `visudo` và `/etc/sudoers.d/`

```bash
echo 'alice ALL=(taskhub) NOPASSWD: /opt/taskhub/start.sh' > /etc/sudoers.d/taskhub-ops
chmod 440 /etc/sudoers.d/taskhub-ops
visudo -c
```

```text
/etc/sudoers: parsed OK
/etc/sudoers.d/README: parsed OK
/etc/sudoers.d/taskhub-ops: parsed OK
```

`visudo -c` kiểm tra cú pháp **mọi** file sudoers. Trên server thật, luôn chạy nó sau khi thêm file vào `sudoers.d` — tốt nhất là tạo file bằng `visudo -f` ngay từ đầu.

---

## 9. Bài thực hành từng bước

**Lab: Thiết kế quyền cho ứng dụng taskhub + sửa 3 lỗi Permission denied** · `[Sandbox]` + `[WSL]` · ~90 phút

Mục tiêu: dựng đúng thiết kế ở [Ví dụ 1](#ví-dụ-1-thiết-kế-quyền-cho-ứng-dụng-taskhub-trên-server), kiểm chứng bằng cách đóng vai từng user, rồi tự gây và sửa lỗi.

Ghi lại lệnh và kết quả vào `~/devops-journey/week02/lab03-permissions.md`.

### Bước 1 — Mở sandbox mới và cài sudo

```bash
docker run --rm -it --name perm-lab ubuntu:22.04 bash
```

Trong container:

```bash
apt-get update -qq && apt-get install -y -qq sudo
```

### Bước 2 — Tạo group và user

```bash
groupadd devs
useradd -m -s /bin/bash -G devs alice                                   # developer
useradd -m -s /bin/bash bob                                             # người ngoài
useradd --system --no-create-home --shell /usr/sbin/nologin taskhub     # user của app
id alice; id bob; id taskhub
```

❓ UID của `taskhub` nằm trong dải nào? Vì sao?

### Bước 3 — Thư mục ứng dụng `/opt/taskhub`

```bash
mkdir -p /opt/taskhub
cat > /opt/taskhub/start.sh << 'EOF'
#!/bin/bash
echo "$(date '+%F %T') taskhub started as $(whoami)" >> /var/log/taskhub/app.log
echo "OK: started as $(whoami)"
EOF
chown -R root:taskhub /opt/taskhub
chmod 750 /opt/taskhub
chmod 750 /opt/taskhub/start.sh
ls -la /opt/taskhub
```

❓ Vì sao owner là `root` mà không phải `taskhub`?

### Bước 4 — Thư mục log (cố ý thiếu setgid)

```bash
mkdir -p /var/log/taskhub
chown taskhub:devs /var/log/taskhub
chmod 750 /var/log/taskhub
```

Chạy app bằng user `taskhub` với `umask 027` (giống cách cấu hình service thật):

```bash
sudo -u taskhub bash -c 'umask 027; /opt/taskhub/start.sh'
ls -l /var/log/taskhub/
```

Đóng vai `alice` đọc log:

```bash
sudo -u alice cat /var/log/taskhub/app.log
```

❓ `alice` thuộc group `devs`, thư mục thuộc group `devs` — vì sao vẫn `Permission denied`? Đọc kỹ cột group của `app.log`.

### Bước 5 — Sửa bằng setgid

```bash
chmod 2750 /var/log/taskhub        # bật setgid trên thư mục
chgrp devs /var/log/taskhub/app.log  # sửa file đã tạo trước đó (setgid chỉ áp dụng cho file MỚI)
sudo -u taskhub bash -c 'umask 027; /opt/taskhub/start.sh'
ls -l /var/log/taskhub/
sudo -u alice cat /var/log/taskhub/app.log
```

### Bước 6 — Kiểm chứng ma trận quyền

Chạy từng lệnh, ghi kết quả ✔/✘ vào bảng trong file ghi chú:

```bash
sudo -u taskhub bash -c 'echo test >> /var/log/taskhub/app.log' && echo "taskhub ghi log: OK"
sudo -u taskhub bash -c 'echo hack >> /opt/taskhub/start.sh'    ; echo "taskhub sửa code: exit $?"
sudo -u alice   cat /var/log/taskhub/app.log > /dev/null         && echo "alice đọc log: OK"
sudo -u alice   bash -c 'echo hack >> /var/log/taskhub/app.log' ; echo "alice ghi log: exit $?"
sudo -u bob     cat /var/log/taskhub/app.log                     ; echo "bob đọc log: exit $?"
sudo -u bob     ls /opt/taskhub                                  ; echo "bob xem code: exit $?"
```

| Hành động | taskhub | alice | bob |
|---|---|---|---|
| Đọc log | | | |
| Ghi log | | | |
| Sửa code `/opt/taskhub` | | | |
| Xem thư mục code | | | |

### Bước 7 — Sửa 3 lỗi Permission denied

Mỗi tình huống: **chạy lệnh gây lỗi → đọc thông báo → dùng `ls -l`/`namei -l` tìm nguyên nhân → sửa → kiểm tra lại**. Không xem gợi ý cho tới khi đã thử ít nhất 10 phút.

**Tình huống A — Script mất quyền chạy** (giả lập: code được copy từ máy Windows sang và mất bit `x`):

```bash
chmod 640 /opt/taskhub/start.sh
sudo -u taskhub bash -c '/opt/taskhub/start.sh'
```

**Tình huống B — Thư mục log có `r` nhưng thiếu `x`** (giả lập: ai đó "siết" quyền sai):

```bash
chmod 2740 /var/log/taskhub
sudo -u alice ls /var/log/taskhub
sudo -u alice cat /var/log/taskhub/app.log
```

❓ Vì sao `ls` vẫn in được tên file mà `cat` thì không?

**Tình huống C — Log bị root chiếm** (giả lập: ai đó chạy thử app bằng root):

```bash
chmod 2750 /var/log/taskhub        # trả lại quyền thư mục từ tình huống B
rm /var/log/taskhub/app.log
/opt/taskhub/start.sh               # chạy bằng root — sai lầm phổ biến
sudo -u taskhub bash -c 'umask 027; /opt/taskhub/start.sh'
```

<details>
<summary>Gợi ý (chỉ mở khi đã thử)</summary>

- A: nhìn bit `x` của file; nhớ trả lại đúng quyền thiết kế ban đầu, không phải `777`.
- B: so sánh ý nghĩa `r` và `x` của **thư mục** ở mục 4.2.
- C: nhìn cột owner của `app.log`. App cần ghi được, devs cần đọc được.

</details>

### Bước 8 — Sudo giới hạn

Cho phép `alice` chạy **đúng** script khởi động bằng user `taskhub`, không gì khác:

```bash
echo 'alice ALL=(taskhub) NOPASSWD: /opt/taskhub/start.sh' > /etc/sudoers.d/taskhub-ops
chmod 440 /etc/sudoers.d/taskhub-ops
visudo -c
su - alice
```

Trong shell của `alice`:

```bash
sudo -u taskhub /opt/taskhub/start.sh     # được phép
sudo -u taskhub cat /etc/shadow           # không được phép
sudo whoami                               # không được phép
exit
```

Gõ `exit` lần nữa để thoát container — mọi thứ trong sandbox biến mất.

### Bước 9 — Chuẩn bị cho bài 04 trên WSL `[WSL]`

Bài 04 sẽ chạy một ứng dụng Java thành systemd service bằng user `taskhub`. Tạo user và thư mục **thật** trên WSL. Ở đây dùng group `adm` cho thư mục log — theo quy ước của Ubuntu, các file log hệ thống cho phép group `adm` đọc, và user mặc định của bạn thường đã thuộc group này.

```bash
id | grep -o "adm"                    # kiểm tra bạn có thuộc group adm không
sudo useradd --system --no-create-home --shell /usr/sbin/nologin taskhub
sudo mkdir -p /opt/taskhub /var/log/taskhub
sudo chown root:taskhub /opt/taskhub && sudo chmod 750 /opt/taskhub
sudo chown taskhub:adm /var/log/taskhub && sudo chmod 2750 /var/log/taskhub
namei -l /var/log/taskhub
id taskhub
```

Nếu `id` không có `adm`: `sudo usermod -aG adm $USER`, rồi mở terminal WSL mới. Nếu vẫn chưa thấy, từ PowerShell chạy `wsl -l -v` để xem tên distro, rồi `wsl --terminate <tên-distro>` và mở lại.

> Gỡ bỏ nếu muốn làm lại từ đầu (⚠️ xóa thư mục): `sudo userdel taskhub && sudo rm -rf /opt/taskhub /var/log/taskhub`.

### Bước 10 — Commit

```bash
cd ~/devops-journey
git add week02/lab03-permissions.md
git commit -m "docs(linux): lab 03 - permissions design for taskhub"
git push
```

---

## 10. Kết quả mong đợi

- **Bước 2:** `taskhub` có UID < 1000 (thường là 999) vì `--system` → dải system user. `alice` có group phụ `devs`.
- **Bước 3:** Owner `root` để app **không sửa được chính code của nó**. Nếu app bị chiếm quyền, kẻ tấn công không cài được mã độc vào `/opt/taskhub`.
- **Bước 4:** `app.log` có group là `taskhub` (group chính của user tạo file), quyền `640`. `alice` không thuộc group `taskhub` → rơi vào "others" = `---` → `Permission denied`. Thư mục thuộc `devs` không đủ — **group của chính file** mới quyết định.
- **Bước 5:** Sau khi bật setgid, file mới tạo trong thư mục tự thuộc group `devs`. `alice` đọc được.
- **Bước 6:**

  | Hành động | taskhub | alice | bob |
  |---|---|---|---|
  | Đọc log | ✔ | ✔ | ✘ |
  | Ghi log | ✔ | ✘ | ✘ |
  | Sửa code | ✘ | ✘ | ✘ |
  | Xem thư mục code | ✔ | ✘ | ✘ |

- **Bước 7:**
  - A: `bash: line 1: /opt/taskhub/start.sh: Permission denied`. `ls -l` thấy `-rw-r-----` — thiếu `x`. Sửa: `chmod 750 /opt/taskhub/start.sh`.
  - B: `ls` in được tên `app.log` (vì group có `r` trên thư mục = đọc được danh sách tên) nhưng `cat` báo `Permission denied` (thiếu `x` = không truy cập được inode bên trong). Sửa: `chmod 2750 /var/log/taskhub`.
  - C: script in ra `/opt/taskhub/start.sh: line 2: /var/log/taskhub/app.log: Permission denied` rồi **vẫn in tiếp** `OK: started as taskhub` — script không dừng khi gặp lỗi, nên nhìn dòng cuối dễ tưởng mọi thứ ổn ([bài 06](06-bash-scripting.md) sẽ dạy cách để script dừng khi lỗi). `app.log` mới có owner `root` (group vẫn là `devs` nhờ setgid), quyền `644`. `taskhub` là "others" → chỉ có `r` → không ghi được. Sửa: `chown taskhub:devs /var/log/taskhub/app.log && chmod 640 /var/log/taskhub/app.log`.
- **Bước 8:** Lệnh đầu chạy được. Hai lệnh sau bị từ chối với thông báo dạng `Sorry, user alice is not allowed to execute ... as ...` hoặc yêu cầu mật khẩu (alice không có mật khẩu nên thất bại) — đúng nguyên tắc least privilege.
- **Bước 9:** `namei -l` hiện `drwxr-s--- taskhub adm taskhub`.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| "Sửa" lỗi bằng `chmod -R 777` | Không tìm nguyên nhân, mở toang quyền | **Không bao giờ.** Tìm đúng user nào cần quyền gì trên đối tượng nào, cấp đúng mức đó. `777` trên server production là lỗi bảo mật nghiêm trọng |
| `usermod -G docker phuong` → mất quyền sudo | Thiếu `-a`, group phụ bị thay thế | Luôn `-aG`. Nếu đã lỡ và vẫn còn phiên root: thêm lại `usermod -aG sudo phuong` |
| Vừa thêm vào group mà vẫn `Permission denied` | Phiên đăng nhập hiện tại giữ danh sách group cũ | Đăng xuất/đăng nhập lại hoặc `newgrp <group>`. Kiểm tra bằng `id` (không có tham số) |
| File có quyền `644` nhưng service vẫn không đọc được | Thiếu `x` trên một thư mục cha | `namei -l <đường-dẫn>` |
| Xóa được file "chỉ đọc" của người khác | Có `w` trên thư mục chứa nó | Đúng thiết kế. Dùng sticky bit nếu thư mục dùng chung |
| `chmod -R 755` làm mọi file trở nên "chạy được" | `-R` áp dụng giống nhau cho file và thư mục | `chmod -R u=rwX,g=rX,o= dir` hoặc dùng `find -type d` / `-type f` riêng |
| `sudo: unable to ...` / sudo hỏng hoàn toàn sau khi sửa sudoers | Sửa bằng editor thường, sai cú pháp | Luôn dùng `visudo`. Nếu đã hỏng: trên EC2 có thể phải dùng EC2 Serial Console hoặc gắn ổ sang máy khác để sửa |
| App chạy thử bằng `sudo` rồi service hỏng | File tạo ra thuộc root | Chạy thử bằng `sudo -u <user-của-app>`; sửa bằng `chown` |
| `chown: changing ownership of 'x': Operation not permitted` | User thường không đổi được owner | Dùng `sudo`. Trên `/mnt/c` (ổ Windows) chown có thể không có tác dụng — làm việc trong `~` |
| Script chạy được bằng `bash script.sh` nhưng `./script.sh` báo `Permission denied` | Thiếu bit `x`. `bash script.sh` chỉ cần quyền `r` vì bash đọc file như dữ liệu | `chmod u+x script.sh` |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Nhận diện lỗi quyền ở các tầng khác nhau

Cùng một nguyên nhân (thiếu quyền) nhưng mỗi phần mềm báo một kiểu. Học cách nhận ra:

| Nguồn | Thông báo | Ghi chú |
|---|---|---|
| Shell | `bash: ./start.sh: Permission denied` | |
| Lệnh coreutils | `cat: /var/log/taskhub/app.log: Permission denied` | Cấu trúc `chương trình: đối tượng: mô tả` |
| Java | `java.io.FileNotFoundException: /var/log/taskhub/app.log (Permission denied)` | Tên exception là "FileNotFound" nhưng mô tả trong ngoặc mới là nguyên nhân thật |
| Nginx error log | `open() "/var/www/html/index.html" failed (13: Permission denied)` | Số `13` là mã lỗi hệ thống `EACCES` |
| Docker CLI | `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock` | Quyền trên **socket** — group `docker` |
| sudo | `phuong is not in the sudoers file.` | Không thuộc group `sudo`/không có trong sudoers |
| su | `This account is currently not available.` | Shell của user là `nologin` |

**Mã lỗi hệ thống** hay gặp trong log (con số trong ngoặc):

| Mã | Tên | Nghĩa |
|---|---|---|
| `2` | `ENOENT` | No such file or directory |
| `13` | `EACCES` | Permission denied |
| `1` | `EPERM` | Operation not permitted (thường: thao tác chỉ root được làm) |

### 12.2. Quy trình 5 bước debug Permission denied

1. **Ai?** Process đang chạy bằng user nào? (`ps -o user,cmd -p <PID>` — bài 04; với service: xem `User=` trong unit file.) Đừng giả định — rất nhiều lỗi là do process chạy bằng user khác với bạn nghĩ.
2. **Cái gì?** Đọc đúng **đường dẫn** trong thông báo lỗi.
3. **Toàn bộ đường đi:** `namei -l <đường-dẫn>` — kiểm tra `x` trên mọi thư mục cha.
4. **Tái hiện bằng đúng user đó:** `sudo -u <user> cat <file>` hoặc `sudo -u <user> test -w <file> && echo writable`.
5. **Sửa tối thiểu** (đổi owner/group, thêm một bit) → kiểm tra lại bằng bước 4 → ghi vào `troubleshooting-journal.md`.

### 12.3. Log của sudo

Mọi lệnh `sudo` (thành công hay bị từ chối) được ghi lại. Trên server thật:

```bash
sudo grep sudo /var/log/auth.log | tail -5
```

```text
Oct 31 09:20:11 LEGION sudo:   phuong : TTY=pts/0 ; PWD=/home/phuong ; USER=root ; COMMAND=/usr/bin/apt update
```

Đây là nơi trả lời câu hỏi "ai đã chạy lệnh gì với quyền root, lúc nào" khi điều tra sự cố. (Trên WSL, file này chỉ có nếu dịch vụ ghi log hệ thống đang chạy — sẽ tìm hiểu ở [bài 07](07-logs-monitoring-troubleshooting.md).)

---

## 13. Câu hỏi kiểm tra kiến thức

1. Kernel dùng tên user hay UID để kiểm tra quyền? Điều này ảnh hưởng gì khi làm việc với container?
2. Giải thích ý nghĩa của `r`, `w`, `x` trên **thư mục**.
3. File `-rw-rw-rw-` nằm trong thư mục `drwx------` của user khác. Bạn đọc được file đó không? Vì sao?
4. Vì sao bạn xóa được một file mà bạn không có quyền ghi?
5. Chuyển đổi: `640`, `750`, `2770` sang dạng chữ. `rwxr-x---` sang dạng số.
6. File chứa private key hoặc mật khẩu nên có quyền gì? Thư mục `~/.ssh`?
7. `umask 027` thì file và thư mục mới có quyền gì?
8. setgid trên thư mục để làm gì? Cho một ví dụ trong DevOps.
9. Vì sao `/tmp` cho mọi người ghi mà bạn không xóa được file của người khác?
10. `usermod -G docker phuong` nguy hiểm thế nào?
11. Vừa được thêm vào group `docker` mà `docker ps` vẫn báo lỗi quyền. Vì sao?
12. Khác nhau giữa `su` và `sudo`? Vì sao Ubuntu khuyến khích `sudo`?
13. Vì sao ứng dụng nên chạy bằng system user riêng với shell `nologin`, không chạy bằng root hay bằng user của bạn?
14. Vì sao thêm user vào group `docker` tương đương cho quyền root?
15. Nginx báo `(13: Permission denied)` khi đọc `/home/phuong/site/index.html` dù file có quyền `644`. Bạn kiểm tra gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/03-solutions.md](solutions/03-solutions.md) — chỉ mở sau khi đã tự làm và ghi câu trả lời.
> Làm trong `[Sandbox]` mới.

**Bài 1 — Thư mục dùng chung cho team.** Tạo group `backend` với 2 user `dev1`, `dev2`. Tạo `/srv/shared` sao cho: cả hai tạo và sửa được file của nhau; file mới tự thuộc group `backend`; không ai xóa được file của người kia; người ngoài không thấy gì. Chứng minh từng yêu cầu bằng lệnh.

**Bài 2 — Quyền trên đường dẫn.** Tạo `/data/a/b/c/secret.txt` có quyền `644`. Chỉ thay đổi quyền **một** thư mục để user `bob` không đọc được file nhưng vẫn `ls /data/a` được. Có mấy cách? Giải thích cách nào bạn chọn và vì sao.

**Bài 3 — Owner không đọc được file của mình.** Tạo file thuộc `alice` với quyền `047`. `alice` đọc được không? `bob` thì sao? Giải thích bằng thứ tự kiểm tra quyền của kernel.

**Bài 4 — Quét quyền nguy hiểm.** Viết các lệnh `find` để liệt kê trong toàn hệ thống (bỏ qua `/proc`): (a) file mà others ghi được, (b) file có setuid, (c) file không có owner hợp lệ (UID không tồn tại trong `/etc/passwd`). Gợi ý: `man find`, tìm `-perm`, `-nouser`.

**Bài 5 — UID và container.** Trên WSL, tạo thư mục `~/devops-lab/uid-test`. Chạy `docker run --rm -v ~/devops-lab/uid-test:/data ubuntu:22.04 touch /data/from-container`. Xem owner của file tạo ra trên WSL bằng `ls -ln` (`-n` hiện số thay vì tên). Sau đó chạy lại với `--user 1000:1000`. Giải thích kết quả bằng kiến thức mục 3.1. (Bài này chuẩn bị cho Module 04.)

**Bài 6 — Sudo cho người deploy.** Tạo user `deploy` chỉ được phép chạy **không cần mật khẩu** đúng 2 lệnh: `systemctl restart taskhub` và `systemctl status taskhub`. Dùng `visudo -f`. Chứng minh `deploy` không chạy được `systemctl stop taskhub` hay `bash`. (Container `ubuntu:22.04` không cài systemd nên không có lệnh `systemctl`. Hãy tạo một script giả tại `/usr/bin/systemctl` chỉ in ra tham số nhận được, ví dụ `fake systemctl restart taskhub`. Điều cần kiểm chứng ở đây là sudo **cho phép hay từ chối**. Gợi ý: `sudo -n` chạy không hỏi mật khẩu, `sudo -l` liệt kê quyền.)

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Đọc bất kỳ chuỗi quyền nào (kể cả có `s`, `t`) và chuyển đổi qua lại dạng số trong vài giây.
- [ ] Giải thích được vì sao `alice` bị từ chối ở Bước 4 dù thư mục thuộc group `devs`.
- [ ] Gặp `Permission denied`, phản xạ đầu tiên là `namei -l` và "process chạy bằng user nào?", không phải `chmod 777`.
- [ ] Thiết kế được bộ quyền cho một ứng dụng mới (code, config, log, data) và giải thích từng lựa chọn.
- [ ] Không bao giờ quên `-a` trong `usermod -aG`.
- [ ] Hiểu và giải thích được vì sao group `docker` = root.
- [ ] Làm xong Bài tập 1, 2, 5 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Linux Journey — Grasshopper: User Management, Permissions](https://labex.io/linuxjourney) | Ôn lại bằng bài ngắn | 2026-10-31 |
| [Docker docs — Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/) | Cảnh báo group `docker` = quyền root | 2026-10-31 |
| [Ubuntu Server docs](https://ubuntu.com/server/docs) | Tra cứu quản trị user, bảo mật | 2026-10-31 |
| `man chmod`, `man useradd`, `man sudoers`, `man 5 passwd`, `man namei` (chạy trên máy) | Tra cứu đầy đủ | — |
