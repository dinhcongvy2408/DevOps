# 05. Package management & SSH

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [03. Permissions, Users & Groups](03-permissions-users-groups.md), [04. Processes & systemd](04-processes-systemd.md), [Ôn tập Git nhanh](../03-GIT/00-git-quick-review.md)
> Môi trường: `[WSL]` Ubuntu 24.04, `[Sandbox]` container `ubuntu:22.04` (đóng vai server SSH)

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

- Giải thích **package**, **repository**, **dependency** là gì và `apt` hoạt động thế nào.
- Cài, gỡ, tra cứu gói bằng `apt` và `dpkg`; biết file của một gói nằm ở đâu, một file thuộc gói nào.
- Hiểu vì sao repository bên thứ ba cần **khóa GPG**, và vì sao Dockerfile dùng `apt-get` theo một mẫu cố định.
- Giải thích **mật mã khóa công khai** đủ rõ để hiểu SSH xác thực bằng key thế nào.
- Tạo SSH key, cấu hình `~/.ssh/config`, dùng `ssh-agent`, `scp`, `rsync`, và hiểu các tùy chọn bảo mật quan trọng của SSH server.
- Đọc được lỗi SSH phổ biến bằng `ssh -v` và log phía server.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Cài Nginx/PostgreSQL client lên server mới" | `apt` |
| "Dockerfile build ra image 900 MB" | Mẫu `apt-get install --no-install-recommends` + xóa cache |
| "Script provisioning lỗi `Unable to locate package`" | Thứ tự `apt-get update` → `install`, repository |
| "Bản OpenSSL trên server có lỗ hổng, đang ở phiên bản nào?" | `apt policy`, `dpkg -l` |
| "SSH vào EC2 báo `Permission denied (publickey)`" | Cặp key, quyền file, user mặc định của AMI |
| "Cảnh báo `REMOTE HOST IDENTIFICATION HAS CHANGED`" | `known_hosts` — có thể vô hại, cũng có thể là tấn công |
| "GitHub Actions cần deploy lên server" | SSH key riêng cho máy, không dùng key cá nhân |
| "Server bị dò mật khẩu SSH liên tục" | Tắt đăng nhập bằng mật khẩu, tắt đăng nhập root |

SSH là **cánh cửa chính** vào mọi server Linux. Cấu hình sai thì hoặc bạn bị khóa ngoài cửa, hoặc kẻ khác vào được.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Package, repository, dependency

- **Package (gói phần mềm)**: một file nén chứa chương trình + thông tin mô tả (tên, phiên bản, cần gói nào khác, chạy script gì khi cài). Trên Ubuntu/Debian là file `.deb`.
- **Repository (kho phần mềm)**: máy chủ chứa hàng chục nghìn package kèm **danh mục** (index) mô tả chúng. Ubuntu có kho chính thức, các hãng (Docker, PostgreSQL, HashiCorp) có kho riêng.
- **Dependency (gói phụ thuộc)**: gói A cần gói B mới chạy được. Trình quản lý gói tự cài B khi bạn cài A.

Trên Windows bạn tải `.exe` từ website. Trên Linux, bạn nói "cài cho tôi `nginx`" — hệ thống tự tìm trong kho, tự tải, tự xử lý dependency, và **tự cập nhật bảo mật** về sau.

### 3.2. apt và dpkg — hai tầng

| Công cụ | Tầng | Làm gì |
|---|---|---|
| `dpkg` | Thấp | Cài/gỡ **một file `.deb` có sẵn trên máy**. Không tự tải, không tự xử lý dependency |
| `apt` / `apt-get` | Cao | Đọc danh mục kho, tải gói, giải quyết dependency, rồi gọi `dpkg` để cài |

`apt` là bản thân thiện cho người gõ tay (có thanh tiến trình, màu). `apt-get` là bản cũ hơn nhưng có giao diện ổn định → **dùng `apt-get` trong script và Dockerfile**, dùng `apt` khi gõ tay. Tài liệu chính thức của Ubuntu cũng khuyến nghị như vậy.

### 3.3. Mật mã khóa công khai — giải thích bằng ổ khóa

SSH (và HTTPS ở Module 02) dựa trên **mật mã khóa công khai** (public-key cryptography). Mỗi người có một **cặp khóa** được tạo cùng lúc, liên kết với nhau bằng toán học:

| Khóa | Tương tự | Ai được giữ |
|---|---|---|
| **Private key** (khóa bí mật) | Chiếc **chìa** duy nhất | **Chỉ bạn**. Không bao giờ gửi đi, không commit lên Git |
| **Public key** (khóa công khai) | Hàng trăm chiếc **ổ khóa** giống nhau, chỉ chìa của bạn mở được | Ai cũng có thể có. Bạn phát cho GitHub, cho server |

Tính chất quan trọng: thứ được **ký** bằng private key thì ai có public key cũng **kiểm chứng** được, nhưng không ai có public key mà **giả mạo** được chữ ký đó.

Khi bạn SSH bằng key, đơn giản hóa:

1. Bạn đã đặt public key vào file `~/.ssh/authorized_keys` trên server từ trước.
2. Server gửi một thử thách ngẫu nhiên: "chứng minh anh có chìa đi".
3. Máy bạn **ký** thử thách bằng private key, gửi lại chữ ký. **Private key không bao giờ rời máy bạn.**
4. Server dùng public key trong `authorized_keys` kiểm chứng chữ ký → đúng thì cho vào.

So với mật khẩu: mật khẩu phải gửi tới server (dù được mã hóa trên đường truyền) và có thể bị đoán. Key không bị đoán được trong thực tế, và không có gì bí mật đi qua mạng.

### 3.4. Hai chiều xác thực trong SSH

Người mới thường chỉ biết một chiều. Thực ra có hai:

| Chiều | Câu hỏi | Dùng khóa nào | Lưu ở đâu |
|---|---|---|---|
| **Server → bạn** | "Đây có đúng là server tôi muốn vào, hay kẻ giả mạo đứng giữa?" | **Host key** của server | Máy bạn ghi nhớ trong `~/.ssh/known_hosts` |
| **Bạn → server** | "Người này có quyền vào không?" | **User key** của bạn | Server lưu public key trong `~/.ssh/authorized_keys` |

Câu hỏi `Are you sure you want to continue connecting (yes/no)?` ở lần đầu kết nối chính là chiều thứ nhất: máy bạn chưa biết host key của server này.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Vòng đời quản lý gói với apt

```text
apt update      → tải DANH MỤC mới nhất từ các kho về máy (/var/lib/apt/lists/)
                  KHÔNG cài, KHÔNG nâng cấp gì cả
apt upgrade     → nâng cấp các gói đã cài lên bản mới nhất có trong danh mục
apt install X   → cài X + dependency
apt remove X    → gỡ X, GIỮ file cấu hình trong /etc
apt purge X     → gỡ X và XÓA cả file cấu hình
apt autoremove  → gỡ các dependency không còn gói nào cần
```

Hai điểm người mới hay nhầm:

- **`update` không phải "cập nhật phần mềm"**, chỉ là cập nhật danh mục. Quên `update` trên máy mới (hoặc trong Dockerfile) → `Unable to locate package` hoặc tải về bản cũ không còn trên máy chủ (lỗi 404).
- `upgrade` không bao giờ gỡ gói. `full-upgrade` có thể gỡ gói nếu cần để nâng cấp → dùng cẩn thận trên server.

### 4.2. 🟥 Repository được cấu hình ở đâu

| File | Phiên bản Ubuntu |
|---|---|
| `/etc/apt/sources.list` | 22.04 trở về trước (định dạng một dòng) |
| `/etc/apt/sources.list.d/ubuntu.sources` | 24.04 trở về sau (định dạng mới gọi là deb822) |
| `/etc/apt/sources.list.d/*.list` hoặc `*.sources` | Kho bên thứ ba (Docker, PostgreSQL…) |

WSL của bạn là Ubuntu 24.04, nên kho chính nằm trong `/etc/apt/sources.list.d/ubuntu.sources` (định dạng deb822). Một khối trong file đó trông như sau (minh họa — địa chỉ mirror có thể khác):

```text
Types: deb                                         ← gói đã biên dịch (deb-src = mã nguồn)
URIs: http://archive.ubuntu.com/ubuntu/            ← địa chỉ kho
Suites: noble noble-updates noble-backports        ← tên mã phiên bản + "pocket"
Components: main restricted universe multiverse    ← nhóm gói
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
```

Tutorial cũ (và máy Ubuntu 22.04 trở về trước) viết cùng thông tin đó trên **một dòng** trong `/etc/apt/sources.list`:

```text
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
│   │                                 │             └ component (nhóm gói)
│   │                                 └ suite: tên mã phiên bản + "pocket"
│   └ địa chỉ kho
└ loại: gói đã biên dịch (deb-src = mã nguồn)
```

| Thành phần | Nghĩa |
|---|---|
| `noble` | Tên mã của Ubuntu 24.04 (22.04 là `jammy`) |
| `noble-updates`, `noble-security` | Kho bản cập nhật và bản vá bảo mật |
| `main` | Gói Canonical hỗ trợ chính thức |
| `universe` | Gói do cộng đồng duy trì — rất nhiều công cụ DevOps nằm ở đây |
| `restricted`, `multiverse` | Driver độc quyền, phần mềm có giới hạn bản quyền |

> WSL của bạn và server EC2 (tuần 12) đều chạy Ubuntu 24.04 → cùng định dạng `ubuntu.sources`. Hai cách viết mang ý nghĩa giống hệt nhau; bạn cần đọc được cả hai vì tutorial trên mạng vẫn dùng dạng một dòng.

### 4.3. 🟨 Khóa GPG và kho bên thứ ba

Làm sao `apt` biết gói tải về là của Docker thật, không bị ai sửa trên đường đi? Mỗi kho **ký** danh mục của mình bằng khóa GPG (lại là mật mã khóa công khai, giống mục 3.3). Máy bạn giữ **public key** của kho để kiểm chứng.

Cách làm hiện đại khi thêm kho bên thứ ba:

1. Tải public key của hãng về `/etc/apt/keyrings/`.
2. Thêm file kho vào `/etc/apt/sources.list.d/` với tùy chọn `signed-by=` trỏ tới đúng khóa đó → khóa này **chỉ** được dùng để kiểm chứng kho đó.
3. `apt update` rồi `apt install`.

Ví dụ (chỉ để **đọc hiểu**, đừng chạy): thêm kho Docker có dạng

```text
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable
```

> ⚠️ **Không cài Docker Engine vào WSL** khi bạn đang dùng Docker Desktop — hai thứ sẽ xung đột. Khi cần cài Docker lên EC2 (tuần 12), luôn làm theo **tài liệu chính thức của Docker** tại thời điểm đó, vì các hãng thỉnh thoảng đổi cách đóng gói khóa và định dạng file kho.
>
> Bạn sẽ còn gặp `apt-key add` trong tutorial cũ — cách này **đã lỗi thời** vì khóa được tin cậy cho *mọi* kho.

### 4.4. 🟨 apt trong Dockerfile (báo trước Module 04)

Mẫu chuẩn bạn sẽ viết nhiều lần:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

| Thành phần | Lý do |
|---|---|
| `apt-get` thay vì `apt` | Giao diện ổn định cho script |
| `update` và `install` trong **cùng một** `RUN` | Nếu tách riêng, Docker cache bước `update` cũ, lần build sau có thể cài gói từ danh mục đã lỗi thời |
| `-y` | Tự trả lời "yes" — không có ai gõ phím trong lúc build |
| `--no-install-recommends` | Chỉ cài dependency bắt buộc, bỏ gói "khuyến nghị" → image nhỏ hơn đáng kể |
| `rm -rf /var/lib/apt/lists/*` | Xóa danh mục đã tải — không cần nữa sau khi cài, giảm kích thước image |

### 4.5. Snap — chỉ cần biết tên

Ubuntu có thêm hệ thống gói **snap** (`snap install ...`): gói tự chứa mọi dependency, tự cập nhật, cần systemd. Một số phần mềm trên Ubuntu chỉ phát hành dạng snap. Trên server và trong container, DevOps chủ yếu dùng `apt`. Biết snap tồn tại để không bối rối khi gặp.

### 4.6. 🟥 SSH: client và server

- **SSH client** (`ssh`, gói `openssh-client`): chương trình trên máy bạn, dùng để kết nối đi.
- **SSH server** (`sshd`, gói `openssh-server`): daemon chạy trên server, mặc định lắng nghe port **22**, chấp nhận kết nối đến. Trên Ubuntu, tên service là `ssh.service`.

WSL của bạn có client. Server SSH sẽ được dựng trong container `[Sandbox]` ở bài thực hành, và trên EC2 ở tuần 12.

### 4.7. 🟥 SSH key: tạo, bảo vệ, sử dụng

**Loại key:** dùng **`ed25519`** — hiện đại, ngắn, nhanh, an toàn. Chỉ dùng `rsa` (4096 bit) khi phải kết nối với hệ thống rất cũ không hỗ trợ ed25519.

**Passphrase (cụm mật khẩu bảo vệ key):** mã hóa file private key trên đĩa. Nếu laptop bị mất hoặc file bị lộ, kẻ khác vẫn chưa dùng được key. Nên đặt passphrase cho key cá nhân.

**ssh-agent:** chương trình giữ private key đã mở khóa trong RAM, để bạn chỉ gõ passphrase một lần cho cả phiên làm việc.

**Quyền file — SSH rất khắt khe:**

| Đường dẫn | Quyền đúng | Nếu sai |
|---|---|---|
| `~/.ssh/` | `700` (`drwx------`) | Server từ chối dùng `authorized_keys` |
| `~/.ssh/id_ed25519` (private) | `600` (`-rw-------`) | Client từ chối dùng key: `UNPROTECTED PRIVATE KEY FILE!` |
| `~/.ssh/id_ed25519.pub` (public) | `644` | Không sao |
| `~/.ssh/authorized_keys` (trên server) | `600` | Server từ chối, log ghi `bad ownership or modes` |

Đây là ứng dụng trực tiếp của [bài 03](03-permissions-users-groups.md): SSH từ chối làm việc nếu người khác có thể đọc chìa khóa của bạn hoặc sửa danh sách ổ khóa của bạn.

> ⚠️ **Một key cho một mục đích.** Key cá nhân trên laptop của bạn ≠ key để GitHub Actions deploy lên server. Nếu một key bị lộ, bạn chỉ phải thu hồi đúng key đó. Không bao giờ copy private key cá nhân lên server hay vào CI.

### 4.8. 🟥 known_hosts và cảnh báo host key thay đổi

Lần đầu kết nối, client hiện **fingerprint** (dấu vân tay — chuỗi rút gọn của host key) và hỏi bạn có tin không. Trả lời `yes` → host key được ghi vào `~/.ssh/known_hosts`. Những lần sau, client so host key của server với bản đã ghi.

Nếu khác, bạn sẽ thấy cảnh báo rất đáng sợ:

```text
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```

Hai khả năng:

| Khả năng | Thường gặp khi | Xử lý |
|---|---|---|
| **Vô hại** | Server được cài lại; EC2 bị xóa và tạo mới, nhận lại cùng IP; container SSH được tạo lại | Xác nhận server thực sự đã được tạo lại, rồi xóa dòng cũ: `ssh-keygen -R <host>` |
| **Tấn công man-in-the-middle** (kẻ đứng giữa) | Kẻ khác chặn đường truyền, giả làm server | **Không kết nối.** Báo cho người quản trị |

Quy tắc: **không bao giờ xóa cảnh báo theo phản xạ.** Luôn tự hỏi "mình có biết vì sao host key đổi không?".

Với GitHub, fingerprint chính thức được công bố trên [trang tài liệu của GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints) — so sánh trước khi gõ `yes`.

### 4.9. 🟥 `~/.ssh/config` — đặt tên tắt cho server

Thay vì gõ `ssh -i ~/.ssh/aws-lab.pem -p 22 ubuntu@54.169.12.34` mỗi lần:

```text
Host taskhub-dev
    HostName 54.169.12.34
    User ubuntu
    IdentityFile ~/.ssh/aws-lab
    IdentitiesOnly yes
```

Giờ chỉ cần `ssh taskhub-dev`. Tên tắt này còn dùng được với `scp`, `rsync`, `git` và VS Code Remote-SSH.

`IdentitiesOnly yes`: chỉ thử đúng key được chỉ định. Không có dòng này, client có thể thử lần lượt mọi key trong ssh-agent và bị server ngắt vì `Too many authentication failures`.

### 4.10. 🟨 Port forwarding (chuyển tiếp cổng) với `-L`

Bài toán: PostgreSQL trên server chỉ lắng nghe `localhost:5432` (đúng về bảo mật — không mở ra Internet). Bạn muốn dùng công cụ quản lý database trên laptop để kết nối vào.

```bash
ssh -L 5433:localhost:5432 taskhub-dev
```

Nghĩa: "mở port `5433` trên máy tôi; mọi thứ gửi vào đó, chuyển qua đường SSH đã mã hóa, rồi từ phía server gửi tới `localhost:5432`". Giờ kết nối tới `localhost:5433` trên laptop là tới được database trên server — không cần mở thêm port nào trên firewall.

Cú pháp: `-L <port-trên-máy-bạn>:<đích-nhìn-từ-phía-server>:<port-đích>`.

### 4.11. 🟥 Cấu hình SSH server an toàn (mức hiểu)

File cấu hình: `/etc/ssh/sshd_config`, và các file nhỏ trong `/etc/ssh/sshd_config.d/`. Ba tùy chọn quan trọng nhất:

| Tùy chọn | Giá trị an toàn | Ý nghĩa |
|---|---|---|
| `PasswordAuthentication` | `no` | Chỉ cho vào bằng key → chặn hoàn toàn tấn công dò mật khẩu |
| `PermitRootLogin` | `no` (hoặc `prohibit-password`) | Không cho đăng nhập trực tiếp bằng root. Vào bằng user thường rồi `sudo` → có dấu vết ai làm gì |
| `PubkeyAuthentication` | `yes` (mặc định) | Cho phép xác thực bằng key |

**Bẫy quan trọng trên Ubuntu:** `sshd_config` có dòng `Include /etc/ssh/sshd_config.d/*.conf` ở **đầu** file, và với phần lớn tùy chọn, **giá trị đọc được đầu tiên sẽ thắng**. Nghĩa là một file trong `sshd_config.d/` (ví dụ do cloud-init tạo trên máy cloud) có thể ghi `PasswordAuthentication yes` và **đè** lên chỉnh sửa của bạn ở cuối `sshd_config`. Vì vậy:

- Luôn kiểm tra **cấu hình có hiệu lực thực tế** bằng `sudo sshd -T | grep -i passwordauthentication`, không chỉ nhìn file.
- Luôn kiểm tra cú pháp bằng `sudo sshd -t` **trước** khi reload/restart.

> ⚠️ **Quy tắc sống còn khi sửa SSH trên server thật:** giữ nguyên một phiên SSH đang đăng nhập, mở **phiên thứ hai** để thử đăng nhập sau khi đổi cấu hình. Chỉ đóng phiên đầu khi phiên hai vào được. Sai một dòng có thể khóa bạn ngoài server vĩnh viễn (trên EC2 thì phải dùng cách khác để cứu, rất mất thời gian). Bạn sẽ thực hành điều này thật trên EC2 ở tuần 12.

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Server có đang dùng bản OpenSSL bị lỗ hổng không?"

Một bản tin bảo mật báo lỗ hổng trong OpenSSL, đã vá ở một phiên bản cụ thể. Bạn cần trả lời trong 5 phút:

```bash
apt policy openssl
```

```text
openssl:
  Installed: 3.0.13-0ubuntu3.14
  Candidate: 3.0.13-0ubuntu3.16
  Version table:
     3.0.13-0ubuntu3.16 500
        500 http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages
 *** 3.0.13-0ubuntu3.14 100
        100 /var/lib/dpkg/status
```

`Installed` thấp hơn `Candidate`, và bản mới đến từ kho `noble-security` → có bản vá chưa được cài. Hành động: `sudo apt update && sudo apt install --only-upgrade openssl`, rồi restart các dịch vụ dùng OpenSSL. (Số phiên bản ở trên là minh họa.)

### Ví dụ 2: Lỗi SSH vào EC2 phổ biến nhất của người mới

```text
ubuntu@54.169.12.34: Permission denied (publickey).
```

Ba nguyên nhân hay gặp nhất, theo thứ tự:

1. **Sai user**: AMI Ubuntu dùng user `ubuntu`, Amazon Linux dùng `ec2-user`. SSH bằng `root` hay tên của bạn sẽ bị từ chối.
2. **Sai key**: dùng key khác với key pair đã chọn khi tạo instance.
3. **Quyền file key quá rộng**: file `.pem` tải về có quyền `644` → client từ chối dùng.

Bạn sẽ debug được cả ba bằng `ssh -v` (mục 12).

---

## 6. Sơ đồ kiến trúc

### 6.1. apt hoạt động thế nào

```text
 apt update                          apt install nginx
     │                                     │
     ▼                                     ▼
┌─────────────────────┐   1. đọc   ┌──────────────────────────┐
│ /etc/apt/sources.list│──────────►│ apt: giải quyết dependency│
│ sources.list.d/      │           └────────────┬─────────────┘
└─────────────────────┘                         │ 3. tải .deb
     │ 2. tải danh mục (đã ký GPG)               ▼
     ▼                              ┌──────────────────────────┐
┌─────────────────────┐             │ /var/cache/apt/archives/ │
│ /var/lib/apt/lists/  │             └────────────┬─────────────┘
└─────────────────────┘                         │ 4. dpkg cài đặt
                                                ▼
                         /usr/sbin/nginx, /etc/nginx/, nginx.service ...
                         ghi lại vào /var/lib/dpkg/ và /var/log/dpkg.log
```

### 6.2. Xác thực SSH bằng key

```text
  Máy bạn (WSL)                                       Server (sshd :22)
  ~/.ssh/id_ed25519        (private)                  ~/.ssh/authorized_keys
  ~/.ssh/known_hosts                                  /etc/ssh/ssh_host_ed25519_key

  1. Mở kết nối TCP tới port 22 ─────────────────────────────►
  2.                     ◄──────────── Gửi host key của server
     So với known_hosts: khớp? → tiếp tục; chưa có → hỏi yes/no; khác → CẢNH BÁO
  3. Thiết lập kênh mã hóa (mọi thứ từ đây đều được mã hóa)
  4. "Tôi là user phuong, có public key này" ─────────────────►
  5.                     ◄──────────── Key có trong authorized_keys. Ký thử thách này đi
  6. Ký bằng private key (key KHÔNG rời máy) ─────────────────►
  7.                     ◄──────────── Kiểm chứng bằng public key: hợp lệ → mở shell
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `apt update` | Tải danh mục gói mới nhất | 🟥 |
| `apt upgrade` | Nâng cấp gói đã cài | 🟥 |
| `apt install / remove / purge / autoremove` | Cài / gỡ | 🟥 |
| `apt search`, `apt show` | Tìm gói, xem thông tin gói | 🟥 |
| `apt policy` | Phiên bản đã cài và có sẵn, từ kho nào | 🟥 |
| `apt list --installed / --upgradable` | Liệt kê gói | 🟨 |
| `dpkg -l`, `dpkg -L`, `dpkg -S` | Liệt kê gói, file của gói, file thuộc gói nào | 🟥 |
| `ssh-keygen -t ed25519` | Tạo cặp key | 🟥 |
| `ssh-keygen -R`, `ssh-keygen -lf` | Xóa host khỏi known_hosts, xem fingerprint | 🟥 |
| `eval "$(ssh-agent -s)"`, `ssh-add` | Dùng ssh-agent | 🟨 |
| `ssh`, `ssh -v`, `ssh -p` | Kết nối, xem chi tiết để debug, đổi port | 🟥 |
| `ssh-copy-id` | Đưa public key lên server | 🟥 |
| `scp`, `rsync` | Copy file qua SSH | 🟥 |
| `ssh -L` | Port forwarding | 🟨 |
| `sshd -t`, `sshd -T` | Kiểm tra cú pháp, xem cấu hình có hiệu lực | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu minh họa trên Ubuntu 24.04 (WSL của bạn). Phiên bản gói và fingerprint trên máy bạn sẽ khác.

### `apt update`

```bash
sudo apt update
```

```text
Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease
Get:2 http://security.ubuntu.com/ubuntu noble-security InRelease [129 kB]
Get:3 http://archive.ubuntu.com/ubuntu noble-updates InRelease [128 kB]
Fetched 1,250 kB in 3s (420 kB/s)
Reading package lists... Done
12 packages can be upgraded. Run 'apt list --upgradable' to see them.
```

`Hit` = danh mục không đổi kể từ lần trước, `Get` = tải bản mới, `Err` = lỗi (đọc kỹ dòng này — thường do mạng, DNS hoặc kho không tồn tại).

### `apt install`, `remove`, `purge`, `autoremove`

```bash
sudo apt install -y tree
sudo apt remove tree
sudo apt purge nginx        # xóa cả /etc/nginx — ⚠️ mất cấu hình bạn đã viết
sudo apt autoremove
```

| Tham số | Ý nghĩa |
|---|---|
| `-y` | Tự đồng ý, không hỏi lại |
| `--no-install-recommends` | Không cài gói khuyến nghị |
| `--only-upgrade` | Chỉ nâng cấp nếu đã cài, không cài mới |
| `<gói>=<phiên bản>` | Cài đúng một phiên bản (ví dụ `nginx=1.24.0-2ubuntu7.19`) |

### `apt search`, `apt show`, `apt policy`

```bash
apt search --names-only postgresql-client
apt show curl
apt policy curl
```

```text
Package: curl
Version: 8.5.0-2ubuntu10.16
Priority: optional
Section: web
Depends: libc6 (>= 2.34), libcurl4t64 (= 8.5.0-2ubuntu10.16), zlib1g (>= 1:1.1.4)
Description: command line tool for transferring data with URL syntax
```

`apt show` cho biết dependency (`Depends`), nhóm, mô tả. `apt policy` cho biết bản đã cài (`Installed`), bản sẽ được cài nếu nâng cấp (`Candidate`) và đến từ kho nào.

### `dpkg -l`, `-L`, `-S`

```bash
dpkg -l | grep openssh        # các gói tên chứa openssh và trạng thái
dpkg -L openssh-client | grep bin/   # gói này cài những file thực thi nào
dpkg -S /usr/bin/ssh          # file này thuộc gói nào
```

```text
ii  openssh-client  1:9.6p1-3ubuntu13.20  amd64  secure shell (SSH) client, for secure access to remote machines
/usr/bin/ssh
/usr/bin/scp
/usr/bin/ssh-keygen
...
openssh-client: /usr/bin/ssh
```

Hai ký tự đầu của `dpkg -l`: `ii` = đã cài đầy đủ; `rc` = đã gỡ nhưng còn file cấu hình (dùng `purge` để xóa hẳn).

### `ssh-keygen` — tạo key

Bạn đã tạo key cho GitHub ở [bài Ôn tập Git](../03-GIT/00-git-quick-review.md). Nếu chưa có, lệnh là:

```bash
ssh-keygen -t ed25519 -C "phuong@LEGION"
```

```text
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/phuong/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /home/phuong/.ssh/id_ed25519
Your public key has been saved in /home/phuong/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:Xq3c...tY8 phuong@LEGION
```

| Tham số | Ý nghĩa |
|---|---|
| `-t ed25519` | Loại key |
| `-C "..."` | Comment gắn vào cuối public key — giúp nhận ra key của ai/máy nào khi nhìn `authorized_keys` |
| `-f <file>` | Đặt tên file khác mặc định — dùng khi tạo key cho mục đích riêng, ví dụ `-f ~/.ssh/ssh-lab` |
| `-N ""` | Passphrase rỗng (chỉ dùng cho key của máy/CI, không dùng cho key cá nhân) |

Public key là **một dòng** văn bản:

```bash
cat ~/.ssh/id_ed25519.pub
```

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK3n...q7Vw phuong@LEGION
```

Các lệnh `ssh-keygen` khác hay dùng:

```bash
ssh-keygen -lf ~/.ssh/id_ed25519.pub     # xem fingerprint của key
ssh-keygen -R "[localhost]:2222"         # xóa host khỏi known_hosts
```

### `ssh-agent` và `ssh-add`

```bash
eval "$(ssh-agent -s)"      # khởi động agent cho phiên terminal này
ssh-add ~/.ssh/id_ed25519   # nạp key, gõ passphrase một lần
ssh-add -l                  # liệt kê key đang được agent giữ
```

```text
Agent pid 7012
Enter passphrase for /home/phuong/.ssh/id_ed25519:
Identity added: /home/phuong/.ssh/id_ed25519 (phuong@LEGION)
256 SHA256:Xq3c...tY8 phuong@LEGION (ED25519)
```

`eval "$(...)"` chạy các lệnh `export` mà `ssh-agent -s` in ra, để shell biết cách liên lạc với agent.

### `ssh` — kết nối

```bash
ssh devops@localhost -p 2222              # user@host, port khác 22
ssh -i ~/.ssh/ssh-lab devops@localhost -p 2222   # chỉ định private key
ssh ssh-lab                               # dùng tên tắt trong ~/.ssh/config
ssh ssh-lab 'uptime; df -h /'             # chạy lệnh từ xa rồi thoát
ssh -v ssh-lab                            # in chi tiết quá trình kết nối (debug)
```

| Tham số | Ý nghĩa |
|---|---|
| `-p <port>` | Port của server (chữ `p` thường) |
| `-i <file>` | Private key dùng để xác thực |
| `-v`, `-vv`, `-vvv` | Mức chi tiết tăng dần |
| `-L` | Port forwarding (mục 4.10) |
| `-o <tùy chọn>=<giá trị>` | Ghi đè tùy chọn cấu hình cho một lần, ví dụ `-o PreferredAuthentications=password` |

### `ssh-copy-id` — đưa public key lên server

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2222 devops@localhost
```

```text
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
devops@localhost's password:
Number of key(s) added: 1
```

Nó đăng nhập bằng mật khẩu (lần cuối cùng), thêm public key vào `~/.ssh/authorized_keys` của user trên server, và tự đặt quyền đúng. Trên EC2 bạn không cần bước này: AWS tự đặt public key của key pair vào server lúc khởi tạo.

### `scp` và `rsync` — copy file qua SSH

```bash
scp app.jar ssh-lab:/tmp/                    # máy bạn → server
scp ssh-lab:/var/log/syslog ./               # server → máy bạn
scp -P 2222 app.jar devops@localhost:/tmp/   # chú ý: -P HOA cho port (khác ssh)

rsync -avz --progress ./site/ ssh-lab:/tmp/site/
```

| Tham số `rsync` | Ý nghĩa |
|---|---|
| `-a` | Archive: giữ quyền, thời gian, symlink, copy đệ quy |
| `-v` | In chi tiết |
| `-z` | Nén khi truyền |
| `--delete` | ⚠️ Xóa file ở đích nếu nguồn không còn — đồng bộ tuyệt đối. Thử với `--dry-run` trước |
| `--dry-run` / `-n` | Chỉ in ra sẽ làm gì, không làm thật |

`rsync` chỉ truyền **phần thay đổi** → lần sau nhanh hơn nhiều so với `scp`. Cần cài `rsync` ở **cả hai phía**. Dấu `/` cuối đường dẫn nguồn có ý nghĩa: `site/` = copy **nội dung** thư mục, `site` = copy **cả thư mục**.

### `sshd -t` và `sshd -T` — kiểm tra cấu hình server

```bash
sudo sshd -t                                         # không in gì = cú pháp đúng
sudo sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'
```

```text
permitrootlogin no
passwordauthentication no
```

`-T` in ra **cấu hình có hiệu lực thực tế** sau khi đã gộp mọi file — cách duy nhất chắc chắn để biết tùy chọn nào đang thắng.

---

## 9. Bài thực hành từng bước

**Lab: Package và SSH** · `[WSL]` + `[Sandbox]` · ~90 phút

Ghi câu trả lời vào `~/devops-lab/01-linux/lab05-answers.md`.

### Phần A — Quản lý gói (`[WSL]`)

**Bước A1 — Đọc cấu hình kho**

```bash
cat /etc/apt/sources.list.d/ubuntu.sources | grep -v '^#' | grep -v '^$'
ls /etc/apt/sources.list.d/
```

❓ Máy bạn đang dùng những suite nào (`noble`, `noble-updates`, `noble-security`…) và component nào? (Mở thêm `/etc/apt/sources.list` — trên 24.04 file này thường chỉ còn một dòng chú thích trỏ sang `ubuntu.sources`.)

**Bước A2 — Tra cứu không cài gì**

```bash
apt policy openssh-client curl
dpkg -L openssh-client | grep bin/
dpkg -S "$(readlink -f /usr/bin/python3)" 2>/dev/null || echo "không tìm thấy python3"
apt list --upgradable 2>/dev/null | head
```

❓ `ssh-keygen` thuộc gói nào? Có bao nhiêu gói có thể nâng cấp?

**Bước A3 — Cài và gỡ một gói nhỏ** (cài thêm phần mềm — gói `tree` rất nhỏ và vô hại, nhưng bạn tự quyết định)

```bash
sudo apt update
sudo apt install -y tree
dpkg -L tree
tree -L 1 ~/devops-lab
sudo apt remove -y tree
dpkg -l tree
```

❓ Sau khi `remove`, dòng `dpkg -l tree` bắt đầu bằng ký tự gì? Nghĩa là gì?

**Bước A4 — Xem lịch sử cài đặt**

```bash
tail -20 /var/log/apt/history.log
grep " install " /var/log/dpkg.log | tail -5
```

❓ Hai file log này ghi những gì khác nhau?

### Phần B — SSH với GitHub (`[WSL]`)

**Bước B1 — Kiểm tra key và kết nối**

Nếu đã làm theo [bài Ôn tập Git](../03-GIT/00-git-quick-review.md), bạn đã có key và đã thêm vào GitHub. Kiểm tra:

```bash
ls -la ~/.ssh/
ssh-keygen -lf ~/.ssh/id_ed25519.pub
ssh -T git@github.com
```

```text
Hi <tên-github-của-bạn>! You've successfully authenticated, but GitHub does not provide shell access.
```

Nếu chưa có key hoặc chưa thêm vào GitHub, làm theo [GitHub Docs — Connecting to GitHub with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh).

❓ Quyền của `~/.ssh/`, private key và public key là gì? Có khớp bảng ở mục 4.7 không?

**Bước B2 — Kiểm chứng host key của GitHub**

```bash
ssh-keygen -lF github.com
```

`-F` tìm host trong `known_hosts`, `-l` in fingerprint. (Không dùng `grep github.com ~/.ssh/known_hosts` được, vì Ubuntu mặc định **băm (hash)** tên host trong `known_hosts` — tùy chọn `HashKnownHosts yes` — để kẻ đọc trộm file không biết bạn từng vào những server nào.)

So fingerprint `ED25519` in ra với fingerprint công bố trên [trang chính thức của GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).

❓ Có khớp không? Nếu không khớp, bạn sẽ làm gì?

### Phần C — Dựng SSH server trong `[Sandbox]` và làm cứng nó

Bạn cần **3 terminal**: T1 chạy server, T2 để cấu hình bên trong container, T3 là client trên WSL.

**Bước C1 — T1: khởi động container và cài SSH server**

```bash
docker run --rm -it --name ssh-lab -p 2222:22 ubuntu:22.04 bash
```

`-p 2222:22`: port `2222` trên máy bạn được chuyển vào port `22` của container (Module 04 giải thích kỹ). Trong container:

```bash
export DEBIAN_FRONTEND=noninteractive     # không cho apt hỏi tương tác trong lúc cài
apt-get update && apt-get install -y --no-install-recommends openssh-server
useradd -m -s /bin/bash devops
passwd devops                 # đặt một mật khẩu tạm, ví dụ: Lab05-temp
mkdir -p /run/sshd
/usr/sbin/sshd -D -e
```

`-D` = chạy ở foreground (không tách thành daemon), `-e` = in log ra terminal. T1 giờ hiển thị log của SSH server theo thời gian thực — giữ nó mở để quan sát.

**Bước C2 — T3: kết nối lần đầu bằng mật khẩu**

```bash
ssh -p 2222 devops@localhost
```

```text
The authenticity of host '[localhost]:2222 ([127.0.0.1]:2222)' can't be established.
ED25519 key fingerprint is SHA256:b1n...Qe4.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '[localhost]:2222' (ED25519) to the list of known hosts.
devops@localhost's password:
```

Gõ `yes`, nhập mật khẩu, rồi `whoami; hostname; exit`. Nhìn sang T1 xem log ghi gì.

❓ Dòng log nào trong T1 cho biết bạn đăng nhập bằng mật khẩu?

**Bước C3 — T3: tạo key riêng cho lab và đưa lên server**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ssh-lab -C "ssh-lab@LEGION" -N ""
ssh-copy-id -i ~/.ssh/ssh-lab.pub -p 2222 devops@localhost
ssh -i ~/.ssh/ssh-lab -p 2222 devops@localhost 'ls -la ~/.ssh; cat ~/.ssh/authorized_keys'
```

(Key lab không đặt passphrase cho tiện — chỉ dùng cho container dùng xong bỏ. Key cá nhân thì nên có passphrase.)

❓ Lần này có bị hỏi mật khẩu không? T1 ghi `Accepted password` hay `Accepted publickey`?

**Bước C4 — T3: tạo tên tắt trong `~/.ssh/config`**

```bash
cat >> ~/.ssh/config <<'EOF'

Host ssh-lab
    HostName localhost
    Port 2222
    User devops
    IdentityFile ~/.ssh/ssh-lab
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
ssh ssh-lab 'echo "Xin chào từ $(hostname)"'
```

**Bước C5 — T2: tắt đăng nhập bằng mật khẩu và root**

```bash
docker exec -it ssh-lab bash
```

Trong container:

```bash
ls /etc/ssh/sshd_config.d/
sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'
cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin no
EOF
sshd -t && echo "Cú pháp OK"
sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'
pkill -HUP -f "sshd -D"
```

`SIGHUP` (học ở [bài 04](04-processes-systemd.md#43--signal--cách-nói-chuyện-với-process)) yêu cầu `sshd` đọc lại cấu hình mà không ngắt các phiên đang mở. Trên server thật bạn sẽ dùng `sudo systemctl reload ssh` — thực chất cũng gửi tín hiệu tương tự.

❓ Trước khi sửa, giá trị `passwordauthentication` có hiệu lực là gì? Sau khi sửa là gì?

**Bước C6 — T3: kiểm chứng**

```bash
ssh ssh-lab 'echo key vẫn vào được'
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password -p 2222 devops@localhost
```

```text
key vẫn vào được
devops@localhost: Permission denied (publickey).
```

❓ Thông báo `Permission denied (publickey)` cho bạn biết server **chỉ còn chấp nhận** phương thức nào?

**Bước C7 — T3: copy file bằng scp**

```bash
echo "deploy test $(date)" > ~/devops-lab/01-linux/deploy.txt
scp ~/devops-lab/01-linux/deploy.txt ssh-lab:/tmp/
ssh ssh-lab 'cat /tmp/deploy.txt'
```

**Bước C8 — Gặp cảnh báo host key thay đổi**

Ở T1, bấm `Ctrl+C` để dừng `sshd`, rồi `exit` — container bị xóa (nhờ `--rm`). Lặp lại bước C1 để tạo container mới (cài lại openssh-server, tạo lại user `devops`). Ở T3:

```bash
ssh -p 2222 devops@localhost
```

❓ Bạn thấy cảnh báo gì? Vì sao host key đổi (gợi ý: host key được tạo ra khi nào)? Trong tình huống này cảnh báo là vô hại hay đáng lo — bạn dựa vào đâu để kết luận? Xử lý:

```bash
ssh-keygen -R "[localhost]:2222"
```

**Bước C9 — Dọn dẹp**

- T1: `Ctrl+C`, `exit` (container tự bị xóa).
- Giữ lại `~/.ssh/ssh-lab*` và mục `Host ssh-lab` cho bài tập tự làm; xóa sau khi xong (bài tập 6).

### Bước cuối — Commit

```bash
cp ~/devops-lab/01-linux/lab05-answers.md ~/devops-journey/week03/
cd ~/devops-journey && git add week03/ && git commit -m "docs(linux): lab 05 - packages and ssh" && git push
```

> ⚠️ Kiểm tra `git status` trước khi commit: **không bao giờ** có file `id_ed25519` hay `ssh-lab` (private key) trong danh sách.

---

## 10. Kết quả mong đợi

- **A1:** Ubuntu 24.04 dùng `/etc/apt/sources.list.d/ubuntu.sources` (deb822) với `noble`, `noble-updates`, `noble-backports`, `noble-security`, các component `main restricted universe multiverse`.
- **A2:** `ssh-keygen` thuộc gói `openssh-client`.
- **A3:** sau `remove`, `dpkg -l tree` hiện `rc` (hoặc báo không còn gói nếu `tree` không có file cấu hình) — `r` = removed, `c` = còn config.
- **A4:** `history.log` ghi theo **lệnh apt** (ai chạy, lệnh gì, lúc nào, cài/gỡ những gì). `dpkg.log` ghi từng **bước của dpkg** cho từng gói (unpack, configure, status) — chi tiết hơn, dùng khi một gói cài lỗi giữa chừng.
- **B1:** `~/.ssh` là `drwx------` (700), private key `-rw-------` (600), public key `-rw-r--r--` (644). `ssh -T` chào bằng tên tài khoản GitHub của bạn.
- **B2:** fingerprint ED25519 phải khớp với giá trị GitHub công bố. Nếu không khớp: không push/pull gì, kiểm tra mạng (Wi-Fi công cộng?), hỏi người có trách nhiệm.
- **C2:** T1 có dòng dạng `Accepted password for devops from 172.17.0.1 port 51234 ssh2`. IP nguồn trên máy bạn có thể khác (ví dụ `172.17.0.1` hoặc `192.168.65.x`), nhưng thường **không** phải `127.0.0.1`: kết nối đi qua lớp mạng của Docker — Module 04 giải thích.
- **C3:** không bị hỏi mật khẩu; T1 ghi `Accepted publickey for devops ... ED25519 SHA256:...`.
- **C5:** trước khi sửa, `passwordauthentication yes` (mặc định của OpenSSH); sau khi sửa: `no`. `permitrootlogin` đổi từ giá trị mặc định (`without-password`, tương đương `prohibit-password`) thành `no`.
- **C6:** đăng nhập bằng key vẫn thành công; ép dùng mật khẩu bị từ chối với `Permission denied (publickey)` — danh sách trong ngoặc là các phương thức server còn cho phép.
- **C8:** cảnh báo `REMOTE HOST IDENTIFICATION HAS CHANGED`. Host key được `openssh-server` **tạo lúc cài đặt** → container mới = cài mới = host key mới. Vô hại vì **chính bạn** vừa tạo lại server và biết rõ lý do. Nếu bạn không làm gì mà cảnh báo xuất hiện, đó là lúc phải lo.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `E: Unable to locate package X` | Chưa `apt update`; sai tên gói; gói nằm trong component chưa bật | `sudo apt update`, `apt search X` |
| `E: Could not get lock /var/lib/dpkg/lock-frontend` | Một tiến trình apt khác đang chạy (thường là cập nhật tự động — `unattended-upgrades`) | **Chờ** vài phút. Xem ai đang giữ: `ps aux \| grep -E 'apt\|dpkg'`. ⚠️ **Không xóa file lock** — có thể làm hỏng cơ sở dữ liệu gói |
| `dpkg was interrupted, you must manually run 'sudo dpkg --configure -a'` | Lần cài trước bị ngắt giữa chừng | Chạy đúng lệnh được gợi ý |
| `404 Not Found` khi `apt update` | Danh mục cũ trỏ tới file không còn; hoặc phiên bản Ubuntu đã hết hỗ trợ | `apt update` lại; kiểm tra vòng đời phiên bản |
| `NO_PUBKEY ...` / `The following signatures couldn't be verified` | Thiếu khóa GPG của kho bên thứ ba | Làm lại bước thêm khóa theo tài liệu chính thức của hãng |
| `Permission denied (publickey)` | Sai user, sai key, key chưa có trong `authorized_keys`, hoặc quyền file sai phía server | `ssh -v` (mục 12); kiểm tra log server |
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` … `bad permissions` | Private key có quyền rộng hơn `600` | `chmod 600 ~/.ssh/<key>` |
| Private key nằm trong `/mnt/c/...` không `chmod` được | Ổ Windows không lưu quyền Linux thật | Copy key vào `~/.ssh/` trong WSL rồi `chmod 600` |
| `Connection refused` | Server không có process nào lắng nghe ở port đó (sshd chưa chạy, sai port) | Kiểm tra port, kiểm tra `sshd` đang chạy |
| `Connection timed out` | Gói tin bị chặn trên đường đi (firewall, Security Group, sai IP) | Module 02 và Module 06 — thường là Security Group trên AWS |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Host key server đổi | Mục 4.8 — xác định lý do trước khi `ssh-keygen -R` |
| `Too many authentication failures` | Agent đưa ra quá nhiều key trước khi tới key đúng | `IdentitiesOnly yes` + `IdentityFile` trong `~/.ssh/config` |
| `scp: ... Connection refused` khi đã dùng `-p 2222` | `scp` dùng `-P` (hoa) cho port | `scp -P 2222 ...` hoặc dùng tên tắt trong config |
| Sửa `sshd_config` mà không có tác dụng | File trong `sshd_config.d/` đè lên, hoặc chưa reload | `sshd -T` để xem giá trị thực, reload sau khi sửa |

---

## 12. Đọc log và xử lý lỗi

### Log của apt/dpkg

| File | Dùng khi |
|---|---|
| `/var/log/apt/history.log` | "Ai đã cài/gỡ gì, lúc nào?" — điều tra sau sự cố |
| `/var/log/apt/term.log` | Toàn bộ đầu ra terminal của các lần chạy apt |
| `/var/log/dpkg.log` | Một gói cài lỗi giữa chừng — xem nó dừng ở bước nào |

### Debug phía client: `ssh -v`

```bash
ssh -v -i ~/.ssh/wrong-key -p 2222 devops@localhost
```

Đọc những dòng quan trọng (đã lược bớt):

```text
debug1: Connecting to localhost [127.0.0.1] port 2222.
debug1: Connection established.                          ← TCP thông, mạng không có vấn đề
debug1: Server host key: ssh-ed25519 SHA256:b1n...Qe4
debug1: Host '[localhost]:2222' is known and matches the ED25519 host key.   ← host key khớp
debug1: Authentications that can continue: publickey     ← server chỉ nhận publickey
debug1: Offering public key: /home/phuong/.ssh/wrong-key ED25519 SHA256:Zz9... explicit
debug1: Authentications that can continue: publickey     ← key bị từ chối
debug1: No more authentication methods to try.
devops@localhost: Permission denied (publickey).
```

Cách đọc theo tầng — dừng ở tầng đầu tiên bị hỏng:

| Dấu hiệu dừng | Vấn đề ở tầng | Hướng điều tra |
|---|---|---|
| Không có `Connection established` (timeout/refused) | Mạng / server không lắng nghe | Module 02: firewall, port, IP |
| Lỗi ở `Server host key` | Host key / known_hosts | Mục 4.8 |
| `Offering public key` rồi bị từ chối | Xác thực | Key đúng chưa? Public key có trong `authorized_keys` của **đúng user** chưa? Quyền phía server? |
| Không có dòng `Offering public key` nào | Client không tìm thấy key | Sai đường dẫn `-i`/`IdentityFile`, quyền key sai |

### Debug phía server: log của sshd

- Trong lab (`sshd -D -e`): log hiện ngay trên T1.
- Trên server Ubuntu thật: `sudo journalctl -u ssh -f` hoặc `sudo tail -f /var/log/auth.log`.

Những dòng cần nhận ra:

```text
Accepted publickey for devops from 172.17.0.1 port 51302 ssh2: ED25519 SHA256:Kp2...
Failed password for devops from 172.17.0.1 port 51310 ssh2
Invalid user admin from 203.0.113.50 port 40122
Authentication refused: bad ownership or modes for directory /home/devops/.ssh
```

- `Invalid user admin from <IP lạ>`: trên server mở ra Internet, bạn sẽ thấy hàng trăm dòng này mỗi ngày — robot dò mật khẩu. Đây là lý do phải `PasswordAuthentication no`.
- `bad ownership or modes`: lỗi chỉ hiện **phía server**. Client chỉ thấy `Permission denied (publickey)` — nên khi được, luôn xem log cả hai phía.

---

## 13. Câu hỏi kiểm tra kiến thức

1. `apt update` và `apt upgrade` khác nhau thế nào? Vì sao quên `update` gây lỗi `Unable to locate package`?
2. `apt remove` và `apt purge` khác nhau thế nào? Khi nào bạn chọn cái nào?
3. `apt` và `dpkg` khác nhau thế nào? Vì sao không nên cài `.deb` bằng `dpkg -i` nếu có cách dùng `apt`?
4. Bạn tìm thấy file lạ `/usr/bin/xyz`. Làm sao biết nó thuộc gói nào, hay được cài thủ công?
5. Vì sao kho bên thứ ba cần khóa GPG? `signed-by=` giải quyết vấn đề gì so với `apt-key add`?
6. Giải thích từng thành phần của mẫu `apt-get` trong Dockerfile ở mục 4.4.
7. Giải thích xác thực SSH bằng key cho một người không biết gì về mật mã. Private key có bao giờ được gửi tới server không?
8. Hai chiều xác thực trong SSH là gì? `known_hosts` và `authorized_keys` thuộc chiều nào, nằm ở máy nào?
9. Gặp cảnh báo `REMOTE HOST IDENTIFICATION HAS CHANGED`, bạn suy nghĩ và hành động thế nào?
10. Vì sao nên dùng key riêng cho CI/CD thay vì dùng private key cá nhân?
11. `PasswordAuthentication no` và `PermitRootLogin no` chống lại những rủi ro nào?
12. Bạn đã thêm `PasswordAuthentication no` vào cuối `sshd_config`, reload, nhưng vẫn đăng nhập bằng mật khẩu được. Nguyên nhân khả dĩ nhất trên Ubuntu là gì? Bạn kiểm tra thế nào?
13. Nguyên tắc "giữ một phiên SSH cũ" khi sửa cấu hình SSH nhằm tránh điều gì?
14. `ssh -L 8080:localhost:80 server` làm gì? `localhost` trong lệnh này là máy nào?
15. Trong output `ssh -v`, nếu không thấy dòng `Connection established`, bạn có nên kiểm tra quyền file key không? Vì sao?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/05-solutions.md](solutions/05-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Kiểm kê server.** Viết một chuỗi lệnh (hoặc vài lệnh) trả lời: (a) có bao nhiêu gói đang được cài, (b) gói nào có thể nâng cấp từ kho `security`, (c) 5 gói được cài gần đây nhất và thời điểm cài. Ghi rõ nguồn dữ liệu của từng câu trả lời.

**Bài 2 — Dockerfile tồi.** Đoạn sau có ít nhất 4 vấn đề. Liệt kê và viết lại cho đúng:

```dockerfile
RUN apt update
RUN apt install curl vim git htop
```

**Bài 3 — Ba người dùng, ba quyền.** Trong `[Sandbox]` SSH server (dựng lại theo phần C), tạo thêm user `alice`. Cấu hình để: `devops` vào bằng key, `alice` vào bằng key khác, không ai vào được bằng mật khẩu, root không vào được. Chứng minh bằng log server. Sau đó cố tình `chmod 777 /home/alice/.ssh` và ghi lại chính xác thông báo phía client và phía server.

**Bài 4 — Debug mù.** Nhờ ai đó (hoặc tự làm rồi quên đi vài ngày) gây ra **một** trong các lỗi sau trên container SSH: sai quyền `authorized_keys`, public key bị dán thiếu ký tự, sai user, sshd không chạy. Chỉ dùng `ssh -v` từ phía client (không xem log server) để đoán đúng lỗi. Sau đó mới xem log server để xác nhận. Ghi vào `troubleshooting-journal.md`.

**Bài 5 — Port forwarding.** Trong container SSH, cài `python3` và chạy `python3 -m http.server 8000 --bind 127.0.0.1` (web server chỉ lắng nghe **bên trong** container — port 8000 **không** được publish ra ngoài). Từ WSL, chứng minh rằng `curl localhost:8000` thất bại, rồi dùng `ssh -L` để `curl` thành công. Vẽ sơ đồ đường đi của request.

**Bài 6 — rsync và dọn dẹp.** Dùng `rsync` đồng bộ thư mục `~/devops-lab/01-linux` lên `/tmp/backup` trong container. Sửa một file, chạy lại, dùng `-v` để chứng minh chỉ file đó được truyền. Thử `--delete` với `--dry-run` và giải thích kết quả. Cuối cùng: xóa key `~/.ssh/ssh-lab*`, xóa mục `Host ssh-lab` khỏi `~/.ssh/config`, xóa `[localhost]:2222` khỏi `known_hosts` (bằng công cụ phù hợp — không sửa tay vì tên host đã bị băm).

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Trả lời được "phiên bản X đang cài là bao nhiêu, có bản vá không, đến từ kho nào" trong 2 phút.
- [ ] Viết đúng mẫu `apt-get` cho Dockerfile và giải thích được từng phần.
- [ ] Giải thích xác thực SSH bằng key mà không nói sai "gửi private key lên server".
- [ ] Không bao giờ xóa cảnh báo host key theo phản xạ.
- [ ] Đặt đúng quyền cho `~/.ssh` và key mà không cần tra.
- [ ] Gặp `Permission denied (publickey)`, bạn dùng `ssh -v` và log server để khoanh vùng đúng tầng.
- [ ] Biết kiểm tra cấu hình SSH có hiệu lực bằng `sshd -T`, và luôn `sshd -t` trước khi reload.
- [ ] Làm xong Bài tập 3 và 4 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Ubuntu Server — Install and manage packages](https://ubuntu.com/server/docs/how-to/software/package-management/) | apt, dpkg, vị trí file sources, log | 2026-10-31 |
| [Ubuntu Server — OpenSSH server](https://ubuntu.com/server/docs/how-to/security/openssh-server/) | `sshd_config`, `sshd_config.d`, `sshd -t`, `ssh.service` | 2026-10-31 |
| [GitHub Docs — Connecting to GitHub with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) | Tạo key, thêm vào GitHub, kiểm tra kết nối | 2026-10-31 |
| [GitHub Docs — GitHub's SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints) | Kiểm chứng host key của GitHub | 2026-10-31 |
| [Linux Journey — Packages](https://labex.io/linuxjourney) | Ôn tập ngắn | 2026-10-31 |
| `man apt`, `man apt-get`, `man dpkg`, `man ssh`, `man ssh_config`, `man sshd_config`, `man rsync` (chạy trên máy) | Tra cứu đầy đủ tham số | — |
