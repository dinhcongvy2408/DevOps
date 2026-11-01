# 03. DNS và DHCP

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc (DNS) · 🟨 Nên biết (DHCP) · Kiến thức cần có trước: [01. Mô hình OSI và TCP/IP](01-osi-tcpip-model.md), [02. IPv4, subnet mask, CIDR](02-ipv4-subnet-cidr.md)
> Môi trường: `[WSL]` Ubuntu 24.04, `[PowerShell]` Windows

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

- Giải thích **DNS** giải quyết vấn đề gì và mô tả từng bước một lần phân giải tên miền (root → TLD → authoritative).
- Phân biệt **recursive resolver** và **authoritative server**.
- Đọc và dùng đúng các loại record: `A`, `AAAA`, `CNAME`, `MX`, `TXT`, `NS`, `SOA` (và `PTR` ở mức nhận biết).
- Hiểu **TTL** và cache ở nhiều tầng — trả lời được câu "đổi DNS rồi sao chưa thấy?".
- Biết Linux tìm tên miền theo thứ tự nào (`/etc/hosts`, `/etc/nsswitch.conf`, `/etc/resolv.conf`) và WSL làm gì khác.
- Dùng thành thạo `dig`, `nslookup`, `host`, `getent hosts` — và biết khi nào kết quả của chúng **khác nhau**.
- Hiểu **DHCP** cấp những gì cho một máy và quy trình **DORA**.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Có một câu đùa nổi tiếng trong giới vận hành: *"It's not DNS. There's no way it's DNS. It was DNS."* — sự cố khó hiểu nhất thường lại do DNS.

| Tình huống thật | Bạn cần biết |
|---|---|
| "Đã trỏ domain sang server mới mà khách vẫn vào server cũ" | TTL và cache ở nhiều tầng |
| "App Spring Boot báo `UnknownHostException: postgres`" | App phân giải tên qua đâu; trong Docker, tên service được phân giải bởi DNS nội bộ của Docker |
| "Máy tôi vào được, máy đồng nghiệp không vào được" | Ai đó đang có dòng trong `/etc/hosts`, hoặc dùng DNS resolver khác |
| "Cấu hình domain cho dự án trên AWS" | Record `A`/`CNAME`, vì sao Route 53 có *alias* |
| "Xác minh domain để cấp chứng chỉ HTTPS / dùng dịch vụ email" | Record `TXT`, `CNAME`, `MX` |
| "EC2 trong VPC không phân giải được tên nào cả" | DNS server của VPC và DHCP option set |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Vấn đề DNS giải quyết

Máy tính kết nối với nhau bằng **địa chỉ IP** (bài 02). Con người thì nhớ **tên**: `github.com` dễ nhớ hơn `20.205.243.166`. Thêm nữa, IP của một dịch vụ **có thể thay đổi** (đổi server, đổi nhà cung cấp, load balancer có nhiều IP) — nhưng tên thì giữ nguyên.

**DNS (Domain Name System — hệ thống tên miền)** là "danh bạ điện thoại" của Internet: nhận vào một **tên**, trả về **thông tin** gắn với tên đó (thường là IP).

Ngày xưa, danh bạ này là **một file duy nhất** (`hosts.txt`) mọi máy tải về. Khi Internet lớn lên, không thể dùng một file nữa → DNS ra đời như một **cơ sở dữ liệu phân tán**: không ai giữ toàn bộ danh bạ, mỗi bên chỉ giữ phần của mình. Dấu vết của thời "một file" vẫn còn: chính là `/etc/hosts` trên máy bạn.

### 3.2. Cấu trúc tên miền

Đọc tên miền **từ phải sang trái**, mỗi phần cách nhau bằng dấu chấm:

```text
        api.taskhub.example.com.
        │   │       │       │  └── root (gốc) — dấu chấm cuối, thường bị ẩn
        │   │       │       └───── TLD (Top-Level Domain — tên miền cấp cao nhất): com
        │   │       └───────────── tên miền cấp 2: example  → "example.com" là domain bạn mua
        │   └───────────────────── subdomain (tên miền con): taskhub
        └───────────────────────── subdomain: api
```

Người sở hữu `example.com` toàn quyền tạo subdomain bên dưới mà không phải xin ai.

### 3.3. Hai vai trò của DNS server

| Vai trò | Tiếng Việt | Làm gì | Ví dụ |
|---|---|---|---|
| **Recursive resolver** | Máy chủ phân giải đệ quy | Nhận câu hỏi từ máy bạn, **đi hỏi giùm** các server khác cho đến khi có câu trả lời, rồi **cache** lại | DNS của nhà mạng, `8.8.8.8` (Google), `1.1.1.1` (Cloudflare), Amazon DNS trong VPC |
| **Authoritative server** | Máy chủ có thẩm quyền | **Giữ dữ liệu gốc** của một vùng tên miền (zone), chỉ trả lời về vùng của mình | Route 53 hosted zone của bạn, Cloudflare DNS của domain bạn |

Máy bạn **không tự đi hỏi** từng server. Nó chỉ hỏi **một** recursive resolver và chờ kết quả. Thành phần nhỏ trong máy bạn làm việc này gọi là **stub resolver** (thư viện phân giải của hệ điều hành).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Một lần phân giải tên miền diễn ra thế nào

Giả sử bạn gõ `curl https://www.github.com` và **không có cache nào**:

1. Stub resolver trên máy bạn hỏi recursive resolver: "`www.github.com` có IP gì?"
2. Resolver chưa biết. Nó hỏi một **root server**: "ai quản lý `.com`?" → root trả về danh sách server của TLD `.com`.
3. Resolver hỏi **server TLD `.com`**: "ai quản lý `github.com`?" → trả về danh sách **NS (name server)** của `github.com`.
4. Resolver hỏi **authoritative server** của `github.com`: "`www.github.com` là gì?" → trả lời.
5. Resolver **cache** kết quả trong thời gian TTL, rồi trả về cho máy bạn.

Root server không biết IP của `github.com`, nó chỉ biết **chỉ đường** tới bước tiếp theo. Đây là bản chất "phân tán" của DNS: mỗi tầng chỉ biết tầng ngay dưới nó.

> Trên thực tế, bước 2–3 hầu như luôn có sẵn trong cache của resolver (vì `.com` được hỏi liên tục). Lệnh `dig +trace` cho phép bạn **tự đi lại đủ cả quy trình** — làm ở lab.

### 4.2. 🟥 Các loại record

Mỗi mục dữ liệu trong DNS gọi là một **record** (bản ghi), có dạng: `tên  TTL  lớp  loại  giá-trị`.

| Record | Ý nghĩa | Ví dụ | DevOps dùng khi |
|---|---|---|---|
| `A` | Tên → **IPv4** | `taskhub.example.com. 300 IN A 203.0.113.10` | Trỏ domain vào EC2/IP public |
| `AAAA` | Tên → **IPv6** | `... IN AAAA 2001:db8::10` | Dịch vụ hỗ trợ IPv6 |
| `CNAME` | Tên → **một tên khác** (bí danh) | `www.example.com. IN CNAME example.com.` | Trỏ subdomain vào tên của load balancer, CDN |
| `MX` | Máy chủ **nhận email** của domain (kèm độ ưu tiên) | `example.com. IN MX 10 mail.example.com.` | Cấu hình email công ty |
| `TXT` | Văn bản tùy ý | `example.com. IN TXT "v=spf1 include:_spf.google.com ~all"` | **Xác minh sở hữu domain** (cấp chứng chỉ, Google, GitHub), SPF chống giả mạo email |
| `NS` | **Name server có thẩm quyền** của một zone | `example.com. IN NS ns-123.awsdns-45.com.` | Chuyển quản lý DNS sang Route 53 |
| `SOA` | Thông tin quản trị zone (server chính, số serial, TTL cho câu trả lời "không tồn tại"…) | — | Chủ yếu đọc khi debug |
| `PTR` 🟨 | **IP → tên** (tra ngược, reverse DNS) | `10.113.0.203.in-addr.arpa. IN PTR mail.example.com.` | Máy chủ email, log hiển thị tên thay vì IP |

**Về CNAME, cần nhớ 3 điều:**

1. CNAME trỏ tới **tên**, không trỏ tới IP. Resolver phải phân giải tiếp tên đích → có thể thành **chuỗi CNAME**.
2. Một tên đã có CNAME thì **không được có record nào khác**.
3. **Không được đặt CNAME ở zone apex** (tên gốc của domain, ví dụ `example.com` — không có subdomain). Lý do: apex bắt buộc có record `NS` và `SOA`, mà quy tắc 2 cấm CNAME đi chung với record khác.

> **Gặp lại ở Module 06:** bạn muốn `example.com` (apex) trỏ vào Application Load Balancer — nhưng ALB chỉ có **tên** (`xxx.elb.amazonaws.com`), không có IP cố định, mà CNAME thì không đặt được ở apex. Route 53 giải quyết bằng **alias record**: một phần mở rộng riêng của Route 53, đặt được ở apex, và khi được hỏi thì trả về luôn IP của tài nguyên AWS. Theo tài liệu AWS, truy vấn alias tới tài nguyên AWS cũng **không bị tính phí** như truy vấn CNAME.

### 4.3. 🟥 TTL và cache — vì sao "đổi DNS rồi mà chưa thấy"

**TTL (Time To Live — thời gian sống)** là số **giây** mà một câu trả lời DNS được phép nằm trong cache.

Cache tồn tại ở **nhiều tầng** — mỗi tầng giữ bản cũ cho đến khi TTL của nó hết:

```text
Ứng dụng (JVM, trình duyệt có cache riêng)
   └─► Hệ điều hành (systemd-resolved, Windows DNS Client)
          └─► Recursive resolver (nhà mạng, 8.8.8.8, Amazon DNS)
                 └─► Authoritative server (dữ liệu gốc — nơi bạn vừa sửa)
```

Bạn sửa record ở tầng dưới cùng. Nhưng các tầng trên **vẫn trả bản cũ** cho đến khi hết TTL. Nếu TTL là `86400` (1 ngày), có người sẽ thấy IP cũ suốt 1 ngày.

**Quy trình chuyển server đúng cách (rất hay hỏi phỏng vấn):**

1. **Trước** ngày chuyển ít nhất một khoảng bằng TTL hiện tại: hạ TTL xuống thấp (ví dụ `60`).
2. Chờ TTL cũ hết hạn ở mọi nơi.
3. Đổi record sang IP mới → mọi người nhận IP mới trong vòng ~60 giây.
4. Ổn định rồi thì tăng TTL trở lại.

**Cache phủ định (negative caching)** 🟨: câu trả lời "tên này **không tồn tại**" (`NXDOMAIN`) cũng được cache, theo một giá trị trong record `SOA`. Hậu quả: nếu bạn tra một tên **trước khi** tạo record, rồi mới tạo, thì có thể vẫn nhận `NXDOMAIN` thêm một lúc.

> ⚠️ **Lưu ý cho dân Java:** JVM có **cache DNS riêng**, cấu hình bằng security property `networkaddress.cache.ttl` (trong `$JAVA_HOME/conf/security/java.security`, không đặt được bằng `-D`). Theo tài liệu JDK 21, giá trị mặc định **tùy bản cài đặt** khi không có security manager; cache cho tra cứu thất bại (`networkaddress.cache.negative.ttl`) mặc định 10 giây. Khi debug "DNS đã đổi mà app Java vẫn gọi IP cũ", nhớ rằng còn một tầng cache bên trong app.

### 4.4. 🟥 Linux tìm tên miền theo thứ tự nào?

Khi một chương trình (curl, Java, ping) cần phân giải tên, nó gọi hàm thư viện hệ thống (`getaddrinfo`). Hàm này làm theo **`/etc/nsswitch.conf`**:

```text
hosts:          files dns
```

Nghĩa là: tra **`files`** (tức `/etc/hosts`) **trước**, không thấy mới hỏi **`dns`** (theo cấu hình trong `/etc/resolv.conf`). Trên Ubuntu bản desktop, dòng này có thể dài hơn (ví dụ có `mdns4_minimal` để tìm máy trong mạng LAN) — ý chính vẫn là thứ tự từ trái sang phải.

| File | Vai trò |
|---|---|
| `/etc/hosts` | Danh bạ tĩnh trong máy. **Thắng DNS** nếu có dòng khớp |
| `/etc/nsswitch.conf` | Thứ tự các nguồn tra cứu |
| `/etc/resolv.conf` | Hỏi DNS server nào (`nameserver ...`), tên miền tìm kèm (`search ...`) |

**`/etc/resolv.conf` trên các môi trường khác nhau:**

| Môi trường | `nameserver` thường thấy | Ai quản lý |
|---|---|---|
| Ubuntu server/EC2 | `127.0.0.53` | **systemd-resolved** — một DNS cache chạy cục bộ, chuyển tiếp lên DNS thật (trên EC2 là Amazon DNS) |
| WSL2 (mặc định) | Một IP do WSL đặt, ví dụ `10.255.255.254` khi bật DNS tunneling | **WSL tự sinh file** (`generateResolvConf=true` trong `/etc/wsl.conf` là mặc định) và chuyển câu hỏi DNS sang Windows |
| Container Docker trong network tự tạo | `127.0.0.11` | DNS nội bộ của Docker |

Về WSL, theo tài liệu Microsoft:

- `generateResolvConf` (mặc định `true`): WSL tự tạo `/etc/resolv.conf`.
- `generateHosts` (mặc định `true`): WSL tự tạo `/etc/hosts` — sửa tay có thể bị ghi đè khi WSL khởi động lại.
- Trên Windows 11 22H2 trở lên, **DNS tunneling** bật mặc định: câu hỏi DNS trong WSL được trả lời qua một cơ chế ảo hóa của Windows thay vì đi qua mạng như thường. Địa chỉ nameserver mặc định khi bật là `10.255.255.254`.

Vì vậy, trên WSL bạn **có thể không thấy** systemd-resolved và `127.0.0.53`. Đừng ngạc nhiên — bài thực hành sẽ cho bạn tự kiểm tra.

> **Hệ quả quan trọng:** `dig` **không đọc** `/etc/hosts` và không đi qua `nsswitch` — nó hỏi DNS server trực tiếp. Còn `curl`, Java, `ping`, `getent` thì **có**. Đây là nguồn gốc của rất nhiều tình huống "dig ra đúng mà app vẫn sai".

### 4.5. 🟥 DNS dùng port nào?

- **UDP port 53** cho hầu hết truy vấn (nhanh, gói tin nhỏ).
- **TCP port 53** khi câu trả lời quá lớn (bị đánh dấu *truncated*) và khi đồng bộ zone giữa các server.

Hệ quả cho firewall/Security Group (bài 05, Module 06): chặn port 53 ra ngoài → mọi thứ cần tên miền đều hỏng, dù kết nối tới IP vẫn được.

🟦 Nâng cao: DNS over HTTPS (DoH) và DNS over TLS (DoT) mã hóa truy vấn DNS — chỉ cần biết là có tồn tại.

### 4.6. 🟨 DHCP — máy mới vào mạng lấy IP từ đâu?

Khi laptop bạn vào Wi-Fi, bạn không tự gõ IP. **DHCP (Dynamic Host Configuration Protocol — giao thức cấu hình máy động)** cấp cho máy:

| Thông tin | Ví dụ |
|---|---|
| Địa chỉ IP | `192.168.1.25` |
| Subnet mask | `255.255.255.0` (= `/24`, bài 02) |
| Default gateway | `192.168.1.1` (router — bài 04) |
| DNS server | `192.168.1.1` hoặc DNS nhà mạng |
| Thời hạn thuê (lease) | Ví dụ 24 giờ |

**Quy trình DORA** (4 bước):

```text
Máy mới (chưa có IP)                        DHCP server (thường là router nhà)
   │  1. DISCOVER  (broadcast: "có DHCP server nào không?")  ─►│
   │◄─  2. OFFER   ("tôi đề nghị cho bạn 192.168.1.25")         │
   │  3. REQUEST   ("tôi lấy 192.168.1.25 nhé")               ─►│
   │◄─  4. ACK     ("đồng ý, dùng trong 24 giờ")                │
```

Bước 1 phải **broadcast** (gửi cho cả mạng) vì máy chưa có IP và chưa biết server ở đâu. DHCP dùng **UDP port 67** (server) và **68** (client).

**Lease (hợp đồng thuê):** IP chỉ được cho mượn có thời hạn. Máy tự gia hạn trước khi hết hạn (thường khi đi được nửa thời hạn). Máy rời mạng → IP được thu hồi cho máy khác. Đây là lý do IP của laptop, và cả IP của WSL, **thay đổi** theo thời gian.

| | IP động (DHCP) | IP tĩnh |
|---|---|---|
| Dùng cho | Laptop, điện thoại | Server, router, máy in |
| Ưu điểm | Không phải cấu hình | IP không đổi, dễ trỏ DNS |
| Thực tế | Có thể đặt **DHCP reservation**: luôn cấp cùng một IP cho cùng một MAC | |

**Trên cloud:** EC2 cũng nhận IP qua DHCP, nhưng bạn không chạy DHCP server — AWS lo. Thứ bạn cấu hình là **DHCP option set** của VPC: domain name, DNS server (mặc định là `AmazonProvidedDNS`), NTP server. Theo tài liệu AWS, Amazon DNS (Route 53 Resolver) nằm ở `169.254.169.253` và ở **địa chỉ thứ 2 của dải VPC** — ví dụ VPC `10.0.0.0/16` thì là `10.0.0.2`. Đây là một trong những địa chỉ AWS giữ lại trong mỗi subnet mà bài 02 nhắc tới.

### 4.7. Gặp lại ở đâu

| Khái niệm | Gặp lại |
|---|---|
| `/etc/hosts`, resolver | Docker: mỗi container có `/etc/hosts` và `/etc/resolv.conf` riêng (Module 04) |
| DNS nội bộ | Docker Compose: app gọi `postgres:5432` — tên service được **DNS nhúng của Docker** (`127.0.0.11`) phân giải (Module 04) |
| Record A/CNAME/alias, TTL | Route 53, trỏ domain vào EC2/ALB (Module 06) |
| TXT xác minh domain | Cấp chứng chỉ TLS (ACM, Let's Encrypt — bài 06, Module 06) |
| DHCP option set, Amazon DNS | VPC (Module 06) |
| DNS trong cluster | Kubernetes: **CoreDNS** cho phép gọi `taskhub.default.svc.cluster.local` (Module 09) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Thử server mới **trước khi** đổi DNS

Bạn chuyển `taskhub.example.com` sang server mới `203.0.113.50`, nhưng muốn kiểm tra trước khi trỏ DNS cho mọi người. Thêm vào `/etc/hosts` **trên máy bạn**:

```text
203.0.113.50  taskhub.example.com
```

Giờ trình duyệt và `curl` của **riêng bạn** vào server mới, còn cả thế giới vẫn vào server cũ. Kiểm tra xong thì **xóa dòng đó** — quên xóa là nguồn gốc của tình huống "máy tôi khác máy mọi người".

> `curl` có cách gọn hơn, không cần sửa file: `curl --resolve taskhub.example.com:443:203.0.113.50 https://taskhub.example.com` (học ở bài 06).

### Ví dụ 2: `UnknownHostException` trong Spring Boot

```text
Caused by: java.net.UnknownHostException: postgres
```

Đọc là: JVM hỏi hệ thống "tên `postgres` là IP nào?" và không ai trả lời được. Nguyên nhân thường gặp:

- App chạy **ngoài** Docker (ví dụ chạy từ IntelliJ) nhưng cấu hình kết nối dùng tên service Docker `postgres` — tên này chỉ tồn tại **bên trong** Docker network.
- App và database ở **hai Docker network khác nhau**.
- Gõ sai tên (`postgress`).

Bước kiểm tra đầu tiên luôn là: **chạy `getent hosts postgres` từ đúng nơi app đang chạy** (trên máy hay trong container).

### Ví dụ 3: Có website, không nhận được email

Domain trỏ web đúng (record `A`), nhưng email gửi tới `support@example.com` bị trả lại. Kiểm tra `dig MX example.com` → không có record MX. Web và email dùng **record khác nhau**, cấu hình một cái không có nghĩa là cái kia chạy.

---

## 6. Sơ đồ kiến trúc

### 6.1. Phân giải `www.github.com` khi không có cache

```text
  Máy bạn (WSL)                  Recursive resolver                 Các DNS server trên Internet
 ┌──────────────┐               ┌──────────────────┐
 │ curl         │               │ (8.8.8.8, nhà    │      ② "ai quản lý .com?"
 │  getaddrinfo │ ① "www.github │  mạng, Amazon    │ ──────────────────────────►  Root server (.)
 │  ├ /etc/hosts│    .com = ?"  │  DNS...)         │ ◄──────── "hỏi server .com"
 │  └ resolv.conf──────────────►│                  │      ③ "ai quản lý github.com?"
 │              │               │                  │ ──────────────────────────►  TLD server (.com)
 │              │               │   ┌──────────┐   │ ◄──────── "hỏi NS của github.com"
 │              │ ⑤ IP + TTL    │   │  CACHE   │   │      ④ "www.github.com = ?"
 │              │◄──────────────│   └──────────┘   │ ──────────────────────────►  Authoritative
 └──────────────┘               └──────────────────┘ ◄──────── record + TTL         (github.com)
```

### 6.2. Cùng một tên — hai con đường tra cứu

```text
          ┌────────────── getent / curl / Java / ping ─────────────┐
          │  /etc/nsswitch.conf: "hosts: files dns"                │
          │      ① /etc/hosts  ── có dòng khớp? ── CÓ ──► dùng luôn│
          │                         │ KHÔNG                        │
          │      ② DNS server trong /etc/resolv.conf               │
          └────────────────────────────────────────────────────────┘

          ┌────────────── dig / nslookup / host ───────────────────┐
          │  Hỏi THẲNG DNS server (mặc định trong resolv.conf,      │
          │  hoặc server chỉ định bằng @...). BỎ QUA /etc/hosts     │
          └────────────────────────────────────────────────────────┘
```

---

## 7. Các câu lệnh cần biết

> `dig`, `nslookup`, `host` nằm trong gói `dnsutils`, có thể chưa có trong WSL. Kiểm tra: `which dig`. Nếu chưa có và bạn đồng ý cài: `sudo apt update && sudo apt install -y dnsutils`.

| Lệnh | Mục đích | Mức |
|---|---|---|
| `dig <tên>` | Hỏi DNS, xem đầy đủ chi tiết câu trả lời | 🟥 |
| `dig +short <tên>` | Chỉ in kết quả | 🟥 |
| `dig -t <loại> <tên>` / `dig <tên> <loại>` | Hỏi loại record cụ thể (MX, TXT, NS…) | 🟥 |
| `dig @<server> <tên>` | Hỏi một DNS server cụ thể | 🟥 |
| `dig +trace <tên>` | Tự đi từ root xuống, thấy từng bước | 🟥 |
| `dig -x <ip>` | Tra ngược IP → tên (PTR) | 🟨 |
| `nslookup <tên> [server]` | Tra cứu đơn giản, có cả trên Windows | 🟥 |
| `host <tên>` | Tra cứu gọn, dễ đọc | 🟨 |
| `getent hosts <tên>` | Phân giải **giống hệt như ứng dụng** (qua nsswitch, có `/etc/hosts`) | 🟥 |
| `cat /etc/resolv.conf`, `cat /etc/nsswitch.conf` | Xem cấu hình phân giải | 🟥 |
| `resolvectl status` | Trạng thái systemd-resolved (nếu có) | 🟨 |
| `ipconfig /all` | `[PowerShell]` Xem thông tin DHCP/DNS phía Windows | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra dưới đây là **minh họa**. IP, TTL, phiên bản, thời gian trên máy bạn sẽ khác — các domain lớn có nhiều IP và đổi IP thường xuyên. Hãy tập trung vào **cấu trúc**.

### `dig` — đọc từng phần của câu trả lời

```bash
dig github.com
```

```text
; <<>> DiG 9.18.39-0ubuntu0.24.04.8-Ubuntu <<>> github.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 41234
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; QUESTION SECTION:
;github.com.                    IN      A

;; ANSWER SECTION:
github.com.             60      IN      A       20.205.243.166

;; Query time: 23 msec
;; SERVER: 10.255.255.254#53(10.255.255.254) (UDP)
;; WHEN: Sat Oct 31 10:15:02 +07 2026
;; MSG SIZE  rcvd: 55
```

| Phần | Đọc thế nào |
|---|---|
| `status: NOERROR` | **Dòng quan trọng nhất.** `NOERROR` = thành công. `NXDOMAIN` = tên **không tồn tại**. `SERVFAIL` = server gặp lỗi khi phân giải (thường do authoritative server hỏng hoặc lỗi DNSSEC). `REFUSED` = server từ chối trả lời bạn |
| `flags: qr rd ra` | `qr` = đây là câu trả lời; `rd` = bạn yêu cầu đệ quy; `ra` = server hỗ trợ đệ quy. Nếu có `aa` (*authoritative answer*) → câu trả lời đến **trực tiếp từ authoritative server**, không phải từ cache |
| `ANSWER: 1` | Có bao nhiêu record trong phần trả lời. `ANSWER: 0` với `NOERROR` = tên tồn tại nhưng **không có record loại bạn hỏi** |
| `QUESTION SECTION` | Bạn đã hỏi gì: tên `github.com.`, lớp `IN` (Internet), loại `A` |
| `ANSWER SECTION` | `tên  TTL  lớp  loại  giá-trị`. TTL `60` = còn được cache 60 giây |
| `SERVER` | **Ai** đã trả lời — kiểm tra xem có đúng server bạn nghĩ không. Ở đây là DNS của WSL |
| `Query time` | Thời gian phản hồi. Hỏi lần 2 nhanh hơn hẳn → đã có trong cache |

### `dig +short`, chọn loại record, chọn server

```bash
dig +short github.com
dig +short www.github.com
dig github.com MX +short
dig -t TXT github.com +short
dig @1.1.1.1 github.com +short
```

```text
20.205.243.166
github.com.
20.205.243.166
1 aspmx.l.google.com.
10 alt3.aspmx.l.google.com.
"v=spf1 ip4:192.30.252.0/22 include:_netblocks.google.com ... ~all"
20.205.243.166
```

| Tham số | Ý nghĩa |
|---|---|
| `+short` | Chỉ in giá trị. Dùng nhiều trong script |
| `MX`, `-t TXT` | Hỏi loại record cụ thể. Đặt loại sau tên hoặc dùng `-t` đều được |
| `@1.1.1.1` | Hỏi server chỉ định thay vì server trong `resolv.conf`. Dùng để **so sánh** khi nghi resolver của mình trả kết quả cũ hoặc sai |
| `www.github.com` → `github.com.` → IP | Đây là **chuỗi CNAME**: `+short` in ra từng bước |

Số trước tên trong MX (`1`, `10`) là **độ ưu tiên** — số **nhỏ hơn** được thử trước.

### `dig +noall +answer` — gọn mà vẫn thấy TTL

```bash
dig +noall +answer www.github.com
```

```text
www.github.com.         3600    IN      CNAME   github.com.
github.com.             60      IN      A       20.205.243.166
```

`+noall` tắt mọi phần, `+answer` bật lại riêng phần trả lời. Rất tiện để xem **TTL** và chuỗi CNAME mà không bị rối mắt.

### `dig +trace` — tự đi từ root xuống

```bash
dig +trace github.com
```

```text
.                       518400  IN      NS      a.root-servers.net.
.                       518400  IN      NS      b.root-servers.net.
...
;; Received 239 bytes from 10.255.255.254#53(10.255.255.254) in 4 ms

com.                    172800  IN      NS      a.gtld-servers.net.
com.                    172800  IN      NS      b.gtld-servers.net.
...
;; Received 1170 bytes from 198.41.0.4#53(a.root-servers.net) in 52 ms

github.com.             172800  IN      NS      dns1.p08.nsone.net.
github.com.             172800  IN      NS      ns-1283.awsdns-32.org.
...
;; Received 820 bytes from 192.5.6.30#53(a.gtld-servers.net) in 180 ms

github.com.             60      IN      A       20.205.243.166
;; Received 55 bytes from 205.251.196.3#53(ns-1283.awsdns-32.org) in 35 ms
```

Đọc từng khối theo dòng `Received ... from`: hỏi **root** → được chỉ tới các server **`.com`** → được chỉ tới **NS của github.com** → authoritative server trả về record `A`. Đây chính là mục 4.1 hiện ra trước mắt.

> Trên WSL, `+trace` có thể gặp lỗi hoặc timeout ở bước hỏi trực tiếp root/TLD, tùy cách DNS của WSL và mạng nhà/công ty xử lý truy vấn ra ngoài. Nếu bị, ghi lại lỗi và thử lại với `dig +trace @1.1.1.1 github.com`. Không chạy được `+trace` cũng không sao — hãy đọc output mẫu ở trên.

### `nslookup` — có cả trên Windows

```bash
nslookup github.com
nslookup github.com 8.8.8.8
```

```text
Server:         10.255.255.254
Address:        10.255.255.254#53

Non-authoritative answer:
Name:   github.com
Address: 20.205.243.166
```

`Non-authoritative answer` = câu trả lời đến từ **cache của resolver**, không phải từ authoritative server. Đây là bình thường. Tham số thứ hai (`8.8.8.8`) chỉ định server hỏi, giống `@` của dig.

> Trên Windows, `nslookup` cũng có sẵn trong PowerShell — tiện khi debug từ máy người dùng không có `dig`.

### `host` — gọn, dễ đọc

```bash
host github.com
```

```text
github.com has address 20.205.243.166
github.com mail is handled by 1 aspmx.l.google.com.
...
```

### `getent hosts` — phân giải "y như ứng dụng"

```bash
getent hosts github.com
getent hosts localhost
getent hosts khong-ton-tai.example
echo $?
```

```text
20.205.243.166  github.com
::1             localhost ip6-localhost ip6-loopback
2
```

- `getent` (*get entries*) đọc từ các nguồn trong `nsswitch.conf` → **có tính `/etc/hosts`**.
- Không tìm thấy → không in gì và trả exit code `2`. Rất tiện cho script: `getent hosts db.internal > /dev/null || echo "Không phân giải được db.internal"`.

**Quy tắc chọn công cụ:**

- Muốn biết **DNS server nói gì** → `dig`.
- Muốn biết **ứng dụng của mình sẽ thấy gì** → `getent hosts`.
- Hai cái khác nhau → nghi ngay `/etc/hosts`, hoặc cấu hình `nsswitch`.

### `dig -x` — tra ngược 🟨

```bash
dig -x 8.8.8.8 +short
```

```text
dns.google.
```

`-x` tự đổi IP thành tên dạng `8.8.8.8.in-addr.arpa` và hỏi record `PTR`.

### Xem cấu hình phân giải trên máy

```bash
cat /etc/resolv.conf
cat /etc/nsswitch.conf | grep hosts
ls -l /etc/resolv.conf
```

```text
# This file was automatically generated by WSL. To stop automatic generation of this file, add the following entry to /etc/wsl.conf:
# [network]
# generateResolvConf = false
nameserver 10.255.255.254
hosts:          files dns
-rw-r--r-- 1 root root 190 Oct 31 08:01 /etc/resolv.conf
```

Dòng comment cho biết **WSL** sinh ra file này. Trên Ubuntu server, bạn sẽ thấy file là **link** tới `/run/systemd/resolve/stub-resolv.conf` với `nameserver 127.0.0.53`.

```bash
resolvectl status
```

Nếu systemd-resolved đang chạy, lệnh in DNS server thật mà nó chuyển tiếp tới. Nếu báo lỗi kiểu không kết nối được tới service — trên WSL đây là điều bình thường khi WSL tự quản lý DNS (hoặc khi systemd chưa bật — xem [bài 04 Module 01](../01-LINUX/04-processes-systemd.md)).

### `ipconfig /all` — thông tin DHCP phía Windows `[PowerShell]`

```powershell
ipconfig /all
```

```text
Wireless LAN adapter Wi-Fi:
   DHCP Enabled. . . . . . . . . . . : Yes
   IPv4 Address. . . . . . . . . . . : 192.168.1.25(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Lease Obtained. . . . . . . . . . : Saturday, October 31, 2026 7:58:10 AM
   Lease Expires . . . . . . . . . . : Sunday, November 1, 2026 7:58:10 AM
   Default Gateway . . . . . . . . . : 192.168.1.1
   DHCP Server . . . . . . . . . . . : 192.168.1.1
   DNS Servers . . . . . . . . . . . : 192.168.1.1
```

Mọi thông tin DHCP cấp ở mục 4.6 đều hiện ở đây: IP, mask, gateway, DNS, thời điểm thuê và hết hạn lease. Trong mạng nhà, router Wi-Fi thường kiêm luôn **DHCP server**, **DNS resolver** (chuyển tiếp) và **default gateway**.

---

## 9. Bài thực hành từng bước

**Lab: Truy vết DNS và so sánh các con đường phân giải** · `[WSL]` + `[PowerShell]` · ~60 phút

Ghi câu trả lời vào `~/devops-lab/02-networking/lab03-dns.md`, cuối lab copy vào `~/devops-journey/week04/`.

```bash
mkdir -p ~/devops-lab/02-networking && cd ~/devops-lab/02-networking
which dig || echo "Chưa có dig — xem mục 7 để cài dnsutils"
```

### Bước 1 — Cấu hình phân giải của bạn

```bash
cat /etc/resolv.conf
grep '^hosts' /etc/nsswitch.conf
ls -l /etc/resolv.conf
resolvectl status 2>&1 | head -5
```

❓ WSL của bạn hỏi DNS server nào? File `resolv.conf` do ai sinh ra? Có systemd-resolved không? Thứ tự tra cứu trong `nsswitch.conf` là gì?

### Bước 2 — Tra nhiều loại record

```bash
dig +noall +answer github.com A
dig +noall +answer www.github.com
dig +short github.com MX
dig +short github.com TXT
dig +short github.com NS
dig +noall +answer google.com AAAA
dig +noall +answer github.com SOA
```

❓ `www.github.com` có phải record `A` không? Email của `github.com` do dịch vụ nào xử lý (nhìn tên server MX)? DNS của `github.com` được host ở đâu (nhìn NS)? Tìm trong TXT một chuỗi bắt đầu bằng `v=spf1` và đoán công dụng.

### Bước 3 — Đi lại toàn bộ quy trình phân giải

```bash
dig +trace github.com
```

❓ Có bao nhiêu khối `Received ... from`? Mỗi khối đến từ loại server nào (root / TLD / authoritative)? Khối cuối có record gì?

### Bước 4 — So sánh các resolver

```bash
for s in 8.8.8.8 1.1.1.1; do
  echo "== $s =="
  dig @"$s" +noall +answer +stats github.com | grep -E 'IN|Query time|SERVER'
done
```

❓ Hai resolver trả về IP giống hay khác nhau? Thời gian phản hồi thế nào? Nếu khác IP, có phải một bên sai không? (Gợi ý: các dịch vụ lớn có nhiều IP và có thể trả IP khác nhau theo vị trí.)

### Bước 5 — Xem TTL giảm dần trong cache

```bash
dig @1.1.1.1 +noall +answer github.com
sleep 15
dig @1.1.1.1 +noall +answer github.com
```

❓ TTL lần 2 so với lần 1 thế nào? Giải thích bằng cache của resolver.

> Resolver lớn như `1.1.1.1` có rất nhiều máy chủ phía sau, hai lần hỏi có thể rơi vào hai cache khác nhau nên TTL không phải lúc nào cũng giảm đúng 15. Chạy thêm vài lần để thấy xu hướng.

### Bước 6 — `/etc/hosts` thắng DNS (nhưng chỉ với một số công cụ)

> ⚠️ Bước này sửa file hệ thống `/etc/hosts`. Làm đúng thứ tự: **sao lưu → thêm → quan sát → xóa**. Dòng thêm vào có comment đánh dấu để xóa chính xác.

```bash
sudo cp /etc/hosts /etc/hosts.bak.lab03          # sao lưu

echo "203.0.113.10  example.com   # lab03-networking" | sudo tee -a /etc/hosts

getent hosts example.com          # ứng dụng sẽ thấy gì?
dig +short example.com            # DNS server nói gì?
curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://example.com || echo "curl thất bại, exit code $?"
```

`203.0.113.0/24` là dải IP dành riêng cho **tài liệu và ví dụ** — không có máy thật nào ở đó, nên `curl` sẽ hết thời gian chờ.

❓ `getent` và `dig` trả về gì? Vì sao khác nhau? `curl` thành công hay thất bại, và vì sao?

**Bắt buộc dọn dẹp:**

```bash
sudo sed -i '/# lab03-networking$/d' /etc/hosts   # xóa đúng dòng đã thêm
getent hosts example.com                          # đã trở lại IP thật
diff /etc/hosts /etc/hosts.bak.lab03 && sudo rm /etc/hosts.bak.lab03
```

`diff` không in gì nghĩa là file đã giống hệt bản sao lưu → mới xóa bản sao lưu.

### Bước 7 — Tên không tồn tại

```bash
dig khong-ton-tai-abc123.example.com | grep status
dig github.com AAAA +noall +answer +comments | grep -E 'status|ANSWER:'
getent hosts khong-ton-tai-abc123.example.com; echo "exit code: $?"
```

❓ Status của tên không tồn tại là gì? `github.com AAAA` có `ANSWER` bao nhiêu? `NXDOMAIN` khác "`NOERROR` nhưng `ANSWER: 0`" thế nào?

### Bước 8 — DHCP phía Windows `[PowerShell]`

```powershell
ipconfig /all
```

❓ Card mạng Wi-Fi/Ethernet của bạn có `DHCP Enabled: Yes` không? DHCP server, default gateway, DNS server là địa chỉ nào? Lease hết hạn khi nào? Có phải cùng một thiết bị (router nhà) kiêm nhiều vai trò không?

Tìm thêm card mạng có tên chứa `WSL` trong kết quả. IP của nó liên quan gì tới DNS server trong `/etc/resolv.conf` ở Bước 1? (Không chắc thì ghi lại để đối chiếu ở bài 04.)

### Bước 9 — Commit

```bash
mkdir -p ~/devops-journey/week04
cp ~/devops-lab/02-networking/lab03-dns.md ~/devops-journey/week04/
cd ~/devops-journey
git add week04/lab03-dns.md
git commit -m "docs(network): lab 03 - dns tracing and resolution paths"
git push
```

---

## 10. Kết quả mong đợi

- **Bước 1:** Trên WSL mặc định, `resolv.conf` có comment "automatically generated by WSL", `nameserver` là IP do WSL đặt (thường `10.255.255.254` khi bật DNS tunneling, hoặc IP gateway của WSL). `resolvectl` có thể không dùng được — bình thường. `nsswitch.conf` có `files` đứng trước `dns`.
- **Bước 2:** `www.github.com` là **CNAME** trỏ tới `github.com`. MX trỏ tới server của Google → GitHub dùng Google cho email. NS cho thấy DNS được host ở nhiều nhà cung cấp (nhiều nhà cung cấp → dự phòng). TXT `v=spf1 ...` liệt kê những server được phép gửi email thay mặt domain (chống giả mạo).
- **Bước 3:** Thường có 4 khối: root → TLD `.com` → authoritative của `github.com` → record `A`.
- **Bước 4:** IP có thể giống hoặc khác — **không có nghĩa là sai**: dịch vụ lớn có nhiều IP và có thể trả lời khác nhau theo vị trí người hỏi.
- **Bước 5:** TTL lần 2 nhỏ hơn lần 1 (giảm khoảng 15) → câu trả lời được lấy từ **cache của resolver**, đang đếm ngược tới lúc hết hạn.
- **Bước 6:** `getent` trả `203.0.113.10` (đọc `/etc/hosts` trước), `dig` trả IP thật (bỏ qua `/etc/hosts`), `curl` **thất bại do timeout** (vì curl phân giải qua hệ thống → đi tới IP giả). Đây là minh họa hoàn hảo cho "dig đúng mà app sai".
- **Bước 7:** Tên không tồn tại → `NXDOMAIN`, `getent` trả exit code `2`. `github.com AAAA` có thể là `NOERROR` với `ANSWER: 0` → tên **tồn tại** nhưng **không có** record IPv6.
- **Bước 8:** Trong mạng nhà, router thường kiêm DHCP server + gateway + DNS. Card `vEthernet (WSL...)` có IP cùng dải với gateway mà WSL dùng — WSL nằm "phía sau" Windows (giải thích ở bài 04).

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `dig: command not found` | Chưa cài `dnsutils` | Xem mục 7 |
| `dig` đúng nhưng `curl`/app sai | Có dòng trong `/etc/hosts`, hoặc app có cache DNS riêng (JVM, trình duyệt) | So sánh `getent hosts` với `dig`; kiểm tra `/etc/hosts`; khởi động lại app |
| Đổi record rồi mà vẫn thấy IP cũ | TTL chưa hết ở resolver/OS/app | `dig @<authoritative-ns> <tên>` để xem dữ liệu gốc đã đúng chưa; nếu đúng thì chỉ còn chờ cache hết hạn |
| Tạo record mới nhưng vẫn `NXDOMAIN` một lúc | **Negative caching** — bạn (hoặc ai đó) đã hỏi tên này trước khi tạo | Chờ; hỏi thẳng authoritative server để xác nhận record đã tồn tại |
| Sửa `/etc/hosts` trên WSL, khởi động lại thì mất | `generateHosts=true` — WSL tự sinh lại file | Bình thường. Dùng `/etc/hosts` chỉ để thử nghiệm tạm thời |
| `;; connection timed out; no servers could be reached` | Không liên lạc được DNS server: mất mạng, firewall chặn port 53, VPN, `resolv.conf` sai | Thử `dig @8.8.8.8 github.com`: được → resolver mặc định có vấn đề; không được → vấn đề kết nối mạng/firewall |
| `SERVFAIL` | Resolver không lấy được câu trả lời hợp lệ (authoritative server hỏng, cấu hình NS sai, lỗi DNSSEC) | Thử resolver khác; `dig +trace` để xem đứt ở bước nào |
| Đặt CNAME cho apex bị từ chối | Vi phạm quy tắc DNS (mục 4.2) | Dùng record `A`, hoặc alias của Route 53 |
| Quên dấu chấm cuối khi khai báo record trong zone file | Tên không có dấu chấm cuối bị hiểu là **tương đối** và được nối thêm tên zone (`mail.example.com.example.com`) | Trong zone file, viết đầy đủ tên kèm dấu chấm cuối (giao diện web như Route 53 thường tự xử lý) |

---

## 12. Đọc log và xử lý lỗi

DNS không ghi log ở một chỗ cố định trên máy bạn. Thay vào đó, bạn **đọc thông báo lỗi của ứng dụng** và dùng công cụ để kiểm chứng.

**Nhận diện lỗi DNS trong thông báo của các công cụ:**

| Thông báo | Công cụ | Nghĩa là |
|---|---|---|
| `curl: (6) Could not resolve host: taskhub.example.com` | curl | Không phân giải được tên (exit code 6 của curl = lỗi phân giải) |
| `java.net.UnknownHostException: postgres` | Java | JVM không phân giải được tên |
| `ping: taskhub.example.com: Name or service not known` | ping | Tên không tồn tại hoặc không phân giải được |
| `Temporary failure in name resolution` | nhiều công cụ | **Không liên lạc được DNS server** — khác với "tên không tồn tại" |
| `getaddrinfo ENOTFOUND` | Node.js | Không phân giải được |

Hai nhóm này cần phân biệt rõ:

- **"Không tồn tại"** (`Name or service not known`, `NXDOMAIN`) → DNS server **đã trả lời**: không có. Kiểm tra lại tên, record.
- **"Tạm thời thất bại"** (`Temporary failure`, timeout) → **không hỏi được** DNS server. Kiểm tra mạng, firewall, `resolv.conf`.

**Quy trình 5 bước khi nghi ngờ DNS:**

```text
1. Ứng dụng thấy gì?      getent hosts <tên>         (chạy ĐÚNG nơi app chạy: máy / container / server)
2. DNS server nói gì?     dig <tên>                   → xem status, ANSWER, SERVER
3. Có phải do resolver?   dig @8.8.8.8 <tên>          → khác bước 2 = resolver/cache của bạn có vấn đề
4. Dữ liệu gốc đúng chưa? dig +short NS <domain>      → lấy authoritative server
                          dig @<ns> <tên>             → đây là sự thật, không qua cache
5. Còn khác nhau?         kiểm tra /etc/hosts, cache của app (khởi động lại app), TTL
```

Ghi lại mỗi lần debug vào `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. DNS giải quyết những vấn đề gì? Vì sao không dùng một file danh bạ chung như ngày xưa?
2. Recursive resolver và authoritative server khác nhau thế nào? `8.8.8.8` thuộc loại nào? Route 53 hosted zone thuộc loại nào?
3. Mô tả các bước phân giải `api.taskhub.example.com` khi không có cache.
4. Khi nào dùng `A`, khi nào dùng `CNAME`? Vì sao không đặt được CNAME ở `example.com`?
5. TTL là gì? Bạn sắp chuyển `taskhub.example.com` (TTL hiện tại 86400) sang server mới. Lập kế hoạch để thời gian "người dùng vào server cũ" là ngắn nhất.
6. Kể tên ít nhất 3 tầng có thể cache DNS giữa ứng dụng Java và authoritative server.
7. Thứ tự Linux tra một tên miền là gì? File nào quy định thứ tự đó?
8. Vì sao `dig` và `getent hosts` có thể cho kết quả khác nhau? Muốn biết ứng dụng của bạn sẽ thấy gì thì dùng lệnh nào?
9. `NXDOMAIN`, `SERVFAIL`, `NOERROR` với `ANSWER: 0` khác nhau thế nào?
10. `Name or service not known` và `Temporary failure in name resolution` gợi ý hai hướng điều tra khác nhau nào?
11. DNS dùng giao thức và port nào? Chặn port đó thì chuyện gì xảy ra?
12. DHCP cấp những thông tin gì cho một máy? Mô tả quy trình DORA. Vì sao bước đầu phải broadcast?
13. Trên WSL, ai sinh ra `/etc/resolv.conf`? Vì sao có thể không thấy `127.0.0.53`?
14. Trong VPC `10.0.0.0/16`, Amazon DNS nằm ở địa chỉ nào? Cấu hình DNS server cho EC2 ở đâu?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/03-solutions.md](solutions/03-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Chân dung DNS của một domain.** Chọn một domain bạn hay dùng (không phải github.com). Lập bảng gồm: các record `A`/`AAAA`, chuỗi CNAME của `www`, MX, NS, TTL của từng record, và authoritative server trả lời gì khi bạn hỏi trực tiếp nó (`dig @<ns>`). Câu trả lời từ authoritative có cờ `aa` không?

**Bài 2 — Đọc output.** Giải thích từng dòng của output sau, và cho biết người chạy lệnh nên làm gì tiếp theo:

```text
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 5512
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1
;; QUESTION SECTION:
;api.taskhub.example.com.        IN      A
;; AUTHORITY SECTION:
example.com.     900     IN      SOA     ns-1.example.com. admin.example.com. 2026103101 7200 900 1209600 300
;; SERVER: 10.255.255.254#53(10.255.255.254) (UDP)
```

**Bài 3 — Kế hoạch chuyển server.** Bạn phụ trách chuyển `taskhub.example.com` từ EC2 cũ (`203.0.113.10`) sang EC2 mới (`203.0.113.50`) vào 20:00 thứ Bảy. TTL hiện tại là `3600`. Viết **runbook** (các bước theo thời gian, lệnh kiểm tra ở mỗi bước, tiêu chí rollback). Thêm một mục: làm sao bạn tự kiểm tra server mới trước giờ chuyển mà không ảnh hưởng ai.

**Bài 4 — "Chỉ máy tôi bị".** Đồng nghiệp nói: "Từ máy em vào `staging.taskhub.example.com` ra trang cũ, mọi người khác ra trang mới". Liệt kê ít nhất 4 nguyên nhân có thể, và lệnh để kiểm chứng từng nguyên nhân.

**Bài 5 — DNS trong script.** Viết script `check-dns.sh` nhận vào danh sách tên miền (tham số dòng lệnh), với mỗi tên in ra: IP mà **ứng dụng** sẽ dùng (getent), IP mà **DNS** trả về (dig), và cảnh báo `MISMATCH` nếu hai giá trị không có điểm chung. Script trả exit code `1` nếu có ít nhất một tên không phân giải được. (Dùng kiến thức [Bash ở Module 01](../01-LINUX/06-bash-scripting.md).)

**Bài 6 — Câu hỏi phỏng vấn.** Trả lời trong 2 phút (tự ghi âm hoặc viết ra): *"Bạn gõ `https://taskhub.example.com` vào trình duyệt. Hãy giải thích riêng phần DNS: từ lúc nhấn Enter cho đến khi trình duyệt có IP."*

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ lại sơ đồ 6.1 và giải thích từng mũi tên không cần nhìn tài liệu.
- [ ] Đọc được mọi phần quan trọng của output `dig` (status, flags, answer, TTL, server).
- [ ] Giải thích được vì sao Bước 6 cho kết quả khác nhau giữa `getent`, `dig` và `curl`.
- [ ] Trả lời trôi chảy câu hỏi "đổi DNS rồi sao chưa thấy?" và lập được kế hoạch hạ TTL.
- [ ] Phân biệt được lỗi "tên không tồn tại" và "không hỏi được DNS server" chỉ từ thông báo lỗi.
- [ ] Làm được Bài tập 3 và 4 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Microsoft Learn — Advanced settings configuration in WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) | `generateResolvConf`, `generateHosts`, `dnsTunneling` | 2026-10-31 |
| [Microsoft Learn — Accessing network applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking) | DNS tunneling trên WSL | 2026-10-31 |
| [AWS — Choosing between alias and non-alias records (Route 53)](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html) | CNAME ở apex, alias record | 2026-10-31 |
| [AWS — Understanding Amazon DNS](https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html) | Amazon DNS ở `169.254.169.253` và VPC+2 | 2026-10-31 |
| [AWS — Work with DHCP option sets](https://docs.aws.amazon.com/vpc/latest/userguide/DHCPOptionSet.html) | DHCP option set của VPC | 2026-10-31 |
| [Oracle — Java Networking (JDK 21)](https://docs.oracle.com/en/java/javase/21/core/java-networking.html) | `networkaddress.cache.ttl` | 2026-10-31 |
| [Docker docs — Networking overview](https://docs.docker.com/engine/network/) | DNS nhúng `127.0.0.11` | 2026-10-31 |
| [Linux Journey — Networking Nomad: DNS](https://labex.io/linuxjourney) | Ôn tập ngắn | 2026-10-31 |
| `man dig`, `man resolv.conf`, `man nsswitch.conf` (chạy trên máy) | Tra cứu chính thức | — |
