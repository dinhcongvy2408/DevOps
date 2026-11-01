# Lời giải — Bài 05. Package management & SSH

> ⚠️ Chỉ đọc sau khi đã **tự làm** và ghi câu trả lời của bạn.
> Quay lại bài: [05-packages-ssh.md](../05-packages-ssh.md)

## Mục lục

- [A. Câu hỏi kiểm tra kiến thức (mục 13)](#a-câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [B. Bài tập tự làm (mục 14)](#b-bài-tập-tự-làm-mục-14)

---

## A. Câu hỏi kiểm tra kiến thức (mục 13)

**1.** `apt update` chỉ tải **danh mục** gói mới nhất từ các kho về `/var/lib/apt/lists/`. `apt upgrade` nâng cấp gói đã cài dựa trên danh mục đó. Trên máy mới hoặc container, danh mục trống hoặc cũ → apt không biết gói tồn tại (`Unable to locate package`) hoặc trỏ tới phiên bản đã bị xóa khỏi kho (404).

**2.** `remove` gỡ chương trình nhưng giữ file cấu hình trong `/etc` — dùng khi có thể cài lại sau và muốn giữ cấu hình. `purge` xóa cả cấu hình — dùng khi muốn gỡ sạch hoặc cấu hình bị hỏng và muốn bắt đầu lại từ mặc định.

**3.** `dpkg` cài một file `.deb` có sẵn, không tự tải và không tự giải quyết dependency. `apt` tìm gói trong kho, giải quyết dependency, tải về rồi gọi `dpkg`. Cài bằng `dpkg -i` dễ gặp dependency thiếu, và gói đó không nhận bản cập nhật bảo mật tự động từ kho. Nếu buộc phải cài `.deb` tải về, dùng `sudo apt install ./ten-goi.deb` để apt vẫn xử lý dependency.

**4.** `dpkg -S /usr/bin/xyz`. Nếu ra tên gói → được cài qua hệ thống gói. Nếu báo `no path found matching pattern` → được cài thủ công (copy tay, script cài đặt, `make install`…) hoặc do một công cụ khác (snap, pip…) — cần điều tra thêm (`ls -l`, ngày tạo file, `history.log`).

**5.** Khóa GPG cho phép apt kiểm chứng danh mục và gói thực sự do hãng phát hành và không bị sửa trên đường truyền. `apt-key add` đưa khóa vào kho tin cậy **chung** → khóa của hãng A cũng được dùng để kiểm chứng kho của hãng B, của Ubuntu… Nếu một khóa bên thứ ba bị lộ, kẻ tấn công có thể giả mạo gói của bất kỳ kho nào. `signed-by=` giới hạn: khóa này **chỉ** dùng cho đúng kho đó.

**6.** Xem bảng mục 4.4 của bài: `apt-get` vì giao diện ổn định cho script; `update` + `install` chung một `RUN` để không dùng danh mục cũ từ cache của Docker; `-y` vì không có tương tác; `--no-install-recommends` để image nhỏ; xóa `/var/lib/apt/lists/*` vì danh mục không cần sau khi cài và làm image nặng thêm.

**7.** Mẫu trả lời: "Bạn có một chiếc chìa duy nhất và rất nhiều ổ khóa chỉ chìa đó mở được. Bạn gửi ổ khóa cho server từ trước. Khi bạn đến, server đưa ra một câu đố mà chỉ người cầm chìa mới giải được. Máy bạn giải bằng chìa và đưa lại lời giải, server kiểm tra bằng ổ khóa. Chìa không bao giờ rời túi bạn." Private key **không bao giờ** được gửi tới server.

**8.** Chiều 1 — server chứng minh danh tính với bạn bằng **host key**; máy bạn ghi nhớ trong **`~/.ssh/known_hosts` trên máy bạn**. Chiều 2 — bạn chứng minh danh tính với server bằng **user key**; server lưu public key của bạn trong **`~/.ssh/authorized_keys` của user tương ứng trên server**.

**9.** Dừng lại, không kết nối tiếp. Tự hỏi: server này có vừa được cài lại / tạo lại / đổi IP không? Có ai báo trước không? Nếu biết chắc lý do (ví dụ chính mình vừa tạo lại EC2) → xác minh fingerprint mới nếu có thể (ví dụ từ console output của EC2), rồi `ssh-keygen -R <host>` và kết nối lại. Nếu không giải thích được → coi như có thể bị tấn công, không nhập gì, báo cho người phụ trách.

**10.** Key cá nhân thường có quyền vào nhiều nơi (GitHub, nhiều server). Đưa nó vào CI nghĩa là mọi người có quyền sửa pipeline, và mọi lỗ hổng của hệ thống CI, đều có thể lấy được nó. Key riêng cho CI: chỉ cấp đúng quyền cần thiết (ví dụ chỉ vào một server, bằng một user deploy), lộ thì thu hồi riêng mà không ảnh hưởng công việc của bạn, và nhìn log biết ngay hành động nào do CI làm.

**11.** `PasswordAuthentication no`: chặn tấn công dò/đoán mật khẩu (brute force) và mật khẩu bị lộ ở nơi khác. `PermitRootLogin no`: kẻ tấn công phải đoán thêm tên user (không thể nhắm thẳng vào `root` — user chắc chắn tồn tại); mọi thao tác quản trị phải qua `sudo` → có log ai làm gì.

**12.** Nguyên nhân khả dĩ nhất: một file trong `/etc/ssh/sshd_config.d/` (được `Include` ở đầu `sshd_config`) đặt `PasswordAuthentication yes`. Với tùy chọn này, giá trị đọc được **đầu tiên** thắng, nên dòng bạn thêm ở cuối bị bỏ qua. Kiểm tra: `sudo sshd -T | grep -i passwordauthentication` và `grep -ri passwordauthentication /etc/ssh/sshd_config.d/`. Sửa ở đúng file, `sudo sshd -t`, rồi reload. (Khả năng khác: chưa reload/restart dịch vụ.)

**13.** Tránh bị khóa ngoài server. Phiên SSH đang mở không bị ảnh hưởng bởi cấu hình mới. Nếu cấu hình mới sai (phiên thứ hai không vào được), bạn vẫn dùng phiên cũ để sửa lại.

**14.** Mở port `8080` trên **máy bạn**; kết nối vào `localhost:8080` trên máy bạn được chuyển qua đường SSH tới server, rồi từ **phía server** kết nối tới `localhost:80` — tức là `localhost` ở đây là **chính server**. Kết quả: xem được web server trên server (đang chỉ lắng nghe nội bộ) từ trình duyệt trên máy bạn.

**15.** Không. Không có `Connection established` nghĩa là chưa thiết lập được kết nối TCP — vấn đề nằm ở tầng mạng (sai IP/port, sshd không chạy, firewall/Security Group chặn). Quyền file key chỉ được dùng tới **sau khi** đã kết nối và bắt đầu xác thực. Kiểm tra quyền file lúc này là lãng phí thời gian. Đây là nguyên tắc debug theo tầng: tìm tầng đầu tiên bị hỏng.

---

## B. Bài tập tự làm (mục 14)

### Bài 1 — Kiểm kê server

```bash
# (a) Số gói đang cài — nguồn: cơ sở dữ liệu dpkg
dpkg -l | grep -c '^ii'

# (b) Gói có thể nâng cấp từ kho security — nguồn: danh mục apt (chạy apt update trước)
apt list --upgradable 2>/dev/null | grep -- '-security'

# (c) 5 gói được cài gần đây nhất — nguồn: log của dpkg
grep " install " /var/log/dpkg.log | tail -5
```

```text
612
openssl/noble-security 3.0.13-0ubuntu3.16 amd64 [upgradable from: 3.0.13-0ubuntu3.14]
2026-10-31 10:02:14 install tree:amd64 <none> 2.1.1-2ubuntu3
```

Ghi chú:

- `grep -c '^ii'` đếm dòng bắt đầu bằng `ii` (đã cài đầy đủ), loại bỏ dòng tiêu đề và gói trạng thái `rc`.
- `2>/dev/null` giấu cảnh báo "apt does not have a stable CLI interface" — chính cảnh báo này là lý do dùng `apt-get` trong script.
- `--` trong `grep -- '-security'` báo cho `grep` rằng phần sau không phải tùy chọn (vì mẫu bắt đầu bằng dấu `-`).
- `dpkg.log` được xoay vòng (log rotation — bài 07). Gói cài lâu hơn có thể nằm trong `/var/log/dpkg.log.1` hoặc file `.gz` (đọc bằng `zgrep`).

### Bài 2 — Dockerfile tồi

Vấn đề:

1. Dùng `apt` thay vì `apt-get` trong script (cảnh báo giao diện không ổn định).
2. `update` và `install` ở hai `RUN` khác nhau → layer `update` bị cache, lần build sau `install` có thể dùng danh mục cũ, gây 404 hoặc cài bản cũ.
3. Thiếu `-y` → apt hỏi xác nhận, build bị dừng/lỗi vì không có ai trả lời.
4. Thiếu `--no-install-recommends` → cài thêm nhiều gói không cần.
5. Không xóa `/var/lib/apt/lists/*` → image to hơn.
6. Cài công cụ tương tác (`vim`, `htop`) vào image chạy app → image to, bề mặt tấn công lớn. Image production chỉ nên chứa thứ app cần. (Công cụ debug có cách khác — Module 04.)

Viết lại:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

(`ca-certificates` thường cần để `curl`/`git` kết nối HTTPS khi đã bỏ gói khuyến nghị.)

### Bài 3 — Ba người dùng, ba quyền

Trong container (sau khi dựng lại theo phần C):

```bash
useradd -m -s /bin/bash alice
```

Trên WSL tạo key riêng cho alice và đưa lên (trước khi tắt mật khẩu: đặt mật khẩu tạm cho alice và dùng `ssh-copy-id`; hoặc sau khi tắt mật khẩu: copy public key vào bằng `docker exec`):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ssh-lab-alice -N "" -C "alice@ssh-lab"
docker exec -i ssh-lab bash -c 'mkdir -p /home/alice/.ssh && cat >> /home/alice/.ssh/authorized_keys \
  && chown -R alice:alice /home/alice/.ssh && chmod 700 /home/alice/.ssh && chmod 600 /home/alice/.ssh/authorized_keys' \
  < ~/.ssh/ssh-lab-alice.pub
ssh -i ~/.ssh/ssh-lab-alice -o IdentitiesOnly=yes -p 2222 alice@localhost whoami
```

File `10-hardening.conf` như phần C5 đã đủ cho yêu cầu "không ai vào bằng mật khẩu, root không vào được". Bằng chứng trong log server: hai dòng `Accepted publickey for devops ...` và `Accepted publickey for alice ...`, kèm lần thử mật khẩu bị từ chối.

Sau `chmod 777 /home/alice/.ssh`:

- Phía client: `alice@localhost: Permission denied (publickey).` — không có gợi ý gì thêm.
- Phía server: `Authentication refused: bad ownership or modes for directory /home/alice/.ssh`.

Bài học: một số lỗi chỉ nhìn thấy được ở phía server. Sửa: `chmod 700 /home/alice/.ssh`.

### Bài 4 — Debug mù bằng `ssh -v`

| Lỗi được gây ra | Dấu hiệu trong `ssh -v` |
|---|---|
| sshd không chạy | Không có `Connection established`; báo `Connection refused` (port không có ai lắng nghe) |
| Sai user (user không tồn tại) | Kết nối và host key bình thường, `Offering public key` rồi bị từ chối, kết thúc `Permission denied (publickey)`. Từ phía client **không phân biệt được** với lỗi key — server cố tình không tiết lộ user có tồn tại hay không |
| Quyền `authorized_keys` sai | Giống hệt dòng trên |
| Public key bị dán thiếu ký tự | Giống hệt dòng trên |

Kết luận quan trọng: từ client, bạn chỉ khoanh vùng được tới **tầng** ("mạng OK, host key OK, xác thực thất bại"). Để biết chính xác lý do xác thực thất bại, phải đọc **log server**: `Invalid user ...`, `bad ownership or modes ...`, hoặc không có dòng nào đặc biệt (key không khớp — so sánh fingerprint `ssh-keygen -lf` hai phía). Ghi tất cả vào `troubleshooting-journal.md`.

### Bài 5 — Port forwarding

Trong container (qua `docker exec -it ssh-lab bash`):

```bash
apt-get update && apt-get install -y --no-install-recommends python3
cd /tmp && echo "Xin chào từ bên trong container" > index.html
python3 -m http.server 8000 --bind 127.0.0.1
```

Trên WSL:

```bash
curl -m 3 localhost:8000          # thất bại: Connection refused (port 8000 không được publish ra ngoài)
ssh -N -L 8000:127.0.0.1:8000 ssh-lab &
curl localhost:8000               # thành công
kill %1                           # đóng đường hầm
```

`-N`: không mở shell, chỉ giữ kết nối để chuyển tiếp port.

Sơ đồ:

```text
curl (WSL) ──► localhost:8000 (WSL, ssh client lắng nghe)
                   │  đi trong kết nối SSH đã mã hóa
                   ▼
           localhost:2222 ──Docker──► container:22 (sshd)
                                          │ sshd tự kết nối tới
                                          ▼
                                   127.0.0.1:8000 (bên trong container, python http.server)
```

Đây chính là cách bạn sẽ truy cập database trên EC2 (chỉ lắng nghe nội bộ) mà không mở port ra Internet.

### Bài 6 — rsync

Cần `rsync` ở **cả hai phía**: trên WSL (`rsync --version`; thường có sẵn trên Ubuntu) và trong container (`apt-get install -y rsync`).

```bash
rsync -av ~/devops-lab/01-linux/ ssh-lab:/tmp/backup/
echo "thay đổi" >> ~/devops-lab/01-linux/lab05-answers.md
rsync -av ~/devops-lab/01-linux/ ssh-lab:/tmp/backup/     # chỉ liệt kê lab05-answers.md
rm ~/devops-lab/01-linux/deploy.txt
rsync -av --delete --dry-run ~/devops-lab/01-linux/ ssh-lab:/tmp/backup/
```

```text
sending incremental file list
deleting deploy.txt

sent 512 bytes  received 35 bytes ... (DRY RUN)
```

`--dry-run` báo nó **sẽ** xóa `deploy.txt` ở đích (vì nguồn không còn), nhưng chưa xóa thật. Đây là thói quen bắt buộc trước mọi lệnh `rsync --delete`: nếu gõ nhầm thứ tự nguồn/đích, `--delete` có thể xóa sạch dữ liệu thật.

Dọn dẹp:

```bash
rm ~/.ssh/ssh-lab ~/.ssh/ssh-lab.pub ~/.ssh/ssh-lab-alice ~/.ssh/ssh-lab-alice.pub
nano ~/.ssh/config                       # xóa khối "Host ssh-lab"
ssh-keygen -R "[localhost]:2222"
```

`ssh-keygen -R` là cách đúng để xóa host khỏi `known_hosts`, vì Ubuntu mặc định băm tên host trong file này nên không thể tìm dòng bằng mắt.
