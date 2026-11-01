# Lời giải — Bài 03. Permissions, Users & Groups

> ⚠️ Chỉ đọc sau khi đã tự làm. So sánh **cách suy luận**, không chỉ so lệnh.
> Quay lại bài học: [03-permissions-users-groups.md](../03-permissions-users-groups.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Tên hay UID?**
UID (và GID). Tên chỉ là nhãn tra trong `/etc/passwd`. Container có `/etc/passwd` riêng, nên UID `1000` trong container (tên `app`) và UID `1000` trên host (tên `phuong`) là **cùng một chủ thể** với kernel. Khi gắn volume, file do container tạo sẽ thuộc về user host có cùng UID — nguồn gốc của rất nhiều lỗi quyền với Docker.

**2. `r`, `w`, `x` trên thư mục:**
`r` = liệt kê tên các mục bên trong. `w` = tạo/xóa/đổi tên mục bên trong (cần kèm `x`). `x` = đi vào/đi xuyên qua thư mục để truy cập các mục bên trong.

**3. File `rw-rw-rw-` trong thư mục `rwx------` của người khác:**
Không đọc được. Muốn truy cập file phải có `x` trên thư mục chứa nó; bạn là "others" của thư mục đó với quyền `---`. Kernel dừng ở thư mục, không xét đến quyền của file.

**4. Xóa được file không có quyền ghi?**
Xóa file là **sửa thư mục** (gỡ một mục `tên → inode` khỏi danh sách). Nó cần `w` + `x` trên thư mục, không cần quyền gì trên file. (`rm` sẽ hỏi xác nhận khi file chỉ đọc, nhưng đó chỉ là `rm` lịch sự, không phải kernel chặn.) Ngoại lệ: thư mục có sticky bit.

**5. Chuyển đổi:**
`640` = `rw-r-----`; `750` = `rwxr-x---`; `2770` = `rwxrws---` (setgid hiện ở vị trí `x` của group); `rwxr-x---` = `750`.

**6. Private key, mật khẩu:** `600` (`rw-------`). `~/.ssh`: `700`. SSH client sẽ **từ chối** dùng private key có quyền rộng hơn (bài 05).

**7. `umask 027`:** file `640`, thư mục `750`.

**8. setgid trên thư mục:**
File/thư mục con mới tạo kế thừa **group của thư mục cha** thay vì group chính của người tạo. Ví dụ: thư mục log `/var/log/taskhub` thuộc group `devs` với setgid → mọi file log do user `taskhub` tạo ra tự thuộc `devs`, developer đọc được mà không cần `chgrp` thủ công. Tương tự với thư mục dùng chung của một team.

**9. `/tmp`:**
Sticky bit (`drwxrwxrwt`): ai cũng tạo được file, nhưng chỉ chủ file (chủ thư mục, hoặc root) mới xóa/đổi tên được file đó.

**10. `usermod -G docker phuong`:**
Thiếu `-a` → danh sách group phụ bị **thay thế** bằng mỗi `docker`. `phuong` mất group `sudo`, `adm`… Nếu là admin duy nhất, server mất khả năng làm việc với quyền root.

**11. Vừa thêm vào group `docker` vẫn lỗi:**
Danh sách group của process được xác định lúc đăng nhập. Shell hiện tại vẫn mang danh sách cũ. Cần đăng nhập lại, hoặc `newgrp docker`. `id` (không tham số) cho biết group của **phiên hiện tại**; `id phuong` đọc từ file cấu hình — so sánh hai lệnh này sẽ thấy khác biệt.

**12. `su` và `sudo`:**
`su` đổi hẳn sang user khác, cần mật khẩu của user đích (thường là root). `sudo` chạy từng lệnh với quyền khác, cần mật khẩu của chính bạn, ghi log từng lệnh và phân quyền chi tiết được. Ubuntu khóa mật khẩu root và dùng `sudo` vì: không phải chia sẻ mật khẩu root, biết ai làm gì (audit), và thu hồi quyền một người dễ dàng (gỡ khỏi group `sudo`).

**13. Vì sao dùng system user riêng cho app:**
Least privilege. Nếu app bị khai thác lỗ hổng, kẻ tấn công chỉ có quyền của user đó: không đọc được file của người khác, không sửa được code (owner là root), không cài phần mềm hệ thống. Shell `nologin` chặn việc đăng nhập tương tác bằng user này. Chạy bằng root = mất cả server; chạy bằng user của bạn = mất SSH key, lịch sử lệnh, quyền sudo của bạn.

**14. Group `docker` = root:**
Docker daemon chạy bằng root. Ai gửi lệnh được cho daemon (qua socket `/var/run/docker.sock`) thì yêu cầu được daemon chạy container gắn toàn bộ filesystem host (`-v /:/host`) với quyền root → đọc/sửa mọi file, kể cả `/etc/shadow` và `/etc/sudoers`.

**15. Nginx `(13: Permission denied)` với file `644`:**
Nginx worker chạy bằng `www-data`. Kiểm tra `namei -l /home/phuong/site/index.html`: gần như chắc chắn `/home/phuong` là `750` hoặc `700`, `www-data` thiếu `x` để đi qua. Cách sửa đúng: đặt site trong `/var/www/` với owner phù hợp, không mở quyền thư mục home.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Thư mục dùng chung cho team

```bash
groupadd backend
useradd -m -s /bin/bash -G backend dev1
useradd -m -s /bin/bash -G backend dev2
useradd -m -s /bin/bash bob
mkdir -p /srv/shared
chgrp backend /srv/shared
chmod 3770 /srv/shared         # 3 = setgid (2) + sticky (1); 770 = owner + group đầy đủ quyền
ls -ld /srv/shared
```

```text
drwxrws--T 2 root backend 4096 Oct 31 10:00 /srv/shared
```

(`T` viết hoa: sticky bit bật nhưng others không có `x`.)

Vấn đề còn lại: "sửa file của nhau". File mới tạo với `umask 022` có quyền `644` → group chỉ đọc được. Cần thành viên dùng `umask 002` (file `664`):

```bash
su - dev1 -c 'umask 002; echo "v1" > /srv/shared/a.txt; ls -l /srv/shared'
su - dev2 -c 'echo "v2 by dev2" >> /srv/shared/a.txt && cat /srv/shared/a.txt'   # sửa file của dev1: OK
su - dev2 -c 'rm /srv/shared/a.txt'                                              # xóa file của dev1: bị chặn
su - bob  -c 'ls /srv/shared'                                                     # người ngoài
```

```text
-rw-rw-r-- 1 dev1 backend 3 Oct 31 10:01 a.txt
v1
v2 by dev2
rm: cannot remove '/srv/shared/a.txt': Operation not permitted
ls: cannot open directory '/srv/shared': Permission denied
```

Phân tích từng yêu cầu:

| Yêu cầu | Cơ chế |
|---|---|
| Cả hai tạo được file | Group `backend` có `rwx` trên thư mục |
| Sửa được file của nhau | `umask 002` → file có `rw` cho group |
| File mới thuộc `backend` | setgid trên thư mục (`a.txt` thuộc `backend`, không phải `dev1`) |
| Không xóa được file của nhau | Sticky bit → `Operation not permitted` |
| Người ngoài không thấy gì | others = `---` |

Để `umask 002` có hiệu lực lâu dài: thêm vào `~/.bashrc` của từng thành viên. 🟦 Cách chặt chẽ hơn không phụ thuộc umask của từng người: ACL mặc định `setfacl -d -m g:backend:rwX /srv/shared`.

### Bài 2 — Quyền trên đường dẫn

```bash
mkdir -p /data/a/b/c && echo "top secret" > /data/a/b/c/secret.txt && chmod 644 /data/a/b/c/secret.txt
chmod o-x /data/a/b/c        # cách đã chọn
su - bob -c 'ls /data/a; cat /data/a/b/c/secret.txt'
```

```text
b
cat: /data/a/b/c/secret.txt: Permission denied
```

Có các cách sau (chỉ đổi một thư mục):

| Cách | Hậu quả |
|---|---|
| `chmod o-x /data/a/b/c` | Chặn đúng thư mục chứa file. Ít ảnh hưởng nhất → **nên chọn** |
| `chmod o-x /data/a/b` | Chặn được, nhưng bob mất quyền vào mọi thứ khác trong `b` |
| `chmod o-x /data/a` | Không thỏa yêu cầu: bob vẫn liệt kê được tên nhưng `ls` bắt đầu báo lỗi, và bob mất quyền vào mọi thứ bên dưới |
| `chmod o-x /data` | Không thỏa yêu cầu: `ls /data/a` thất bại |

Nguyên tắc: **siết quyền ở chỗ gần đối tượng cần bảo vệ nhất**, để không ảnh hưởng đến thứ khác.

### Bài 3 — Owner không đọc được file của mình

```bash
su - alice -c 'echo hello > /tmp/f047; chmod 047 /tmp/f047; ls -l /tmp/f047; cat /tmp/f047'
su - bob   -c 'cat /tmp/f047'
```

```text
----r--rwx 1 alice alice 6 Oct 31 10:10 /tmp/f047
cat: /tmp/f047: Permission denied
hello
```

- `alice` là owner → kernel dùng bộ quyền owner `---` và **dừng**, không xét đến group hay others → bị từ chối.
- `bob` không phải owner, không thuộc group `alice` → others `rwx` → đọc được.

Một điểm thú vị: `alice` vẫn **chạy được `chmod 600 /tmp/f047`** để lấy lại quyền, vì quyền đổi mode thuộc về chủ file, không phụ thuộc các bit rwx.

### Bài 4 — Quét quyền nguy hiểm

```bash
# (a) file thường mà others ghi được
find / \( -path /proc -o -path /sys \) -prune -o -type f -perm -0002 -print 2>/dev/null

# (b) file có setuid
find / \( -path /proc -o -path /sys \) -prune -o -type f -perm -4000 -print 2>/dev/null

# (c) file/thư mục mà UID owner không tồn tại
find / \( -path /proc -o -path /sys \) -prune -o -nouser -print 2>/dev/null
```

Giải thích:
- `-prune`: không đi vào thư mục khớp điều kiện bên trái. Cấu trúc `A -prune -o B -print` nghĩa là "nếu khớp A thì bỏ qua, ngược lại kiểm tra B và in". Phải có `-print` ở cuối, nếu không `find` cũng in luôn các đường dẫn bị prune.
- `-perm -0002`: dấu `-` đứng trước nghĩa là "có **ít nhất** các bit này" (ở đây: bit `w` của others).
- `-perm -4000`: có bit setuid.
- `-nouser`: UID owner không có trong `/etc/passwd`. Thường xuất hiện sau khi xóa user mà quên dọn file, hoặc file giải nén từ máy khác. Trên một sandbox mới, (a) và (c) gần như trống; (b) liệt kê vài chương trình như `passwd`, `su`, `mount`.

### Bài 5 — UID và container

```bash
mkdir -p ~/devops-lab/uid-test
docker run --rm -v ~/devops-lab/uid-test:/data ubuntu:22.04 touch /data/from-container
docker run --rm --user 1000:1000 -v ~/devops-lab/uid-test:/data ubuntu:22.04 touch /data/from-user1000
ls -ln ~/devops-lab/uid-test
ls -l  ~/devops-lab/uid-test
```

Kết quả mong đợi:

```text
-rw-r--r-- 1    0    0 0 Oct 31 10:20 from-container
-rw-r--r-- 1 1000 1000 0 Oct 31 10:20 from-user1000
-rw-r--r-- 1 root   root   0 Oct 31 10:20 from-container
-rw-r--r-- 1 phuong phuong 0 Oct 31 10:20 from-user1000
```

Giải thích:
- Container mặc định chạy bằng **root (UID 0)** → file tạo ra thuộc UID 0 → trên WSL hiện là `root`. Bạn (phuong) sẽ không xóa được nếu không có `sudo` — lỗi rất hay gặp khi dùng Docker cho môi trường dev (thư mục `target/`, `node_modules/` thuộc root).
- Với `--user 1000:1000`, process trong container có UID 1000. Trong container UID 1000 **không có tên** (image không có user nào UID 1000), nhưng kernel không quan tâm tên. Trên WSL, UID 1000 là `phuong` → file thuộc về bạn.

> Docker Desktop có lớp tích hợp WSL riêng. Nếu kết quả trên máy bạn khác bảng trên, hãy ghi lại chính xác những gì bạn thấy vào `troubleshooting-journal.md` — chúng ta sẽ phân tích ở Module 04.

### Bài 6 — Sudo cho người deploy

```bash
apt-get update -qq && apt-get install -y -qq sudo     # nếu sandbox mới
useradd -m -s /bin/bash deploy

# Container không có systemd → tạo systemctl "giả" chỉ in tham số
printf '#!/bin/bash\necho "fake systemctl $*"\n' > /usr/bin/systemctl
chmod 755 /usr/bin/systemctl

visudo -f /etc/sudoers.d/deploy
```

Nội dung file (trong editor `visudo` mở ra):

```text
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart taskhub, /usr/bin/systemctl status taskhub
```

```bash
chmod 440 /etc/sudoers.d/deploy
visudo -c
su - deploy
```

Trong shell của `deploy`:

```bash
sudo -l
sudo -n systemctl restart taskhub
sudo -n systemctl status taskhub
sudo -n systemctl stop taskhub
sudo -n bash
```

```text
User deploy may run the following commands on <tên-container>:
    (root) NOPASSWD: /usr/bin/systemctl restart taskhub, /usr/bin/systemctl status taskhub
fake systemctl restart taskhub
fake systemctl status taskhub
sudo: a password is required
sudo: a password is required
```

Giải thích:
- `sudo -l` chạy được không cần mật khẩu vì user có ít nhất một quy tắc `NOPASSWD`; nó liệt kê chính xác 2 lệnh được phép.
- Hai lệnh được phép chạy ngay.
- `stop` và `bash` không khớp quy tắc nào. sudo cần xác thực bằng mật khẩu, `-n` (non-interactive) khiến sudo từ chối thay vì hỏi. (Không có `-n`, sudo sẽ hỏi mật khẩu; `deploy` không có mật khẩu nên không bao giờ qua được. Tùy phiên bản và cấu hình, thông báo có thể là `Sorry, user deploy is not allowed to execute ...`.)

Lưu ý bảo mật quan trọng: quy tắc liệt kê **đầy đủ tham số** (`restart taskhub`). Nếu chỉ ghi `/usr/bin/systemctl`, `deploy` có thể chạy `sudo systemctl` với bất kỳ tham số nào — kể cả dừng mọi service hoặc tạo service mới chạy bằng root.
