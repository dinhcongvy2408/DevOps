# 05. TCP, UDP, port và firewall

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Mô hình OSI và TCP/IP](01-osi-tcpip-model.md), [02. IPv4, subnet mask, CIDR](02-ipv4-subnet-cidr.md), [04. Routing, NAT và switching](04-routing-nat-switching.md), [Linux 04. Processes & systemd](../01-LINUX/04-processes-systemd.md)
> Môi trường: `[WSL]` Ubuntu 24.04, `[Sandbox]` container `ubuntu:22.04` có quyền quản trị mạng (`--cap-add=NET_ADMIN`), `[PowerShell]`

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

- So sánh **TCP** và **UDP**, biết dịch vụ nào dùng giao thức nào và vì sao.
- Vẽ và giải thích **TCP 3-way handshake** (bắt tay 3 bước) và quá trình đóng kết nối; đọc được các trạng thái `LISTEN`, `ESTABLISHED`, `TIME_WAIT`, `CLOSE_WAIT`.
- Thuộc các **port** DevOps gặp hằng ngày và hiểu dải port nào dùng cho việc gì.
- Giải thích **bind address** (`0.0.0.0` vs `127.0.0.1`) — nguyên nhân của rất nhiều lỗi "chạy trên máy được, từ ngoài vào không được".
- Dùng thành thạo `ss` và `nc` để xem port nào đang mở và kiểm tra kết nối.
- **Phân biệt 4 lỗi kết nối** — `Connection refused`, `Connection timed out`, `No route to host`, `Name or service not known` — và biết mỗi lỗi chỉ ra chỗ hỏng ở đâu.
- Hiểu **firewall** stateful và stateless, đọc được luật iptables đơn giản, phân biệt `DROP` và `REJECT`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Spring Boot chạy rồi nhưng Nginx báo 502" | App đang nghe port nào, trên địa chỉ nào? → `ss -tlnp` |
| "Từ laptop `curl` tới EC2 bị treo rồi timeout" | Timeout = gói tin bị **chặn im lặng** → nghi Security Group/firewall trước, không nghi app |
| "Kết nối DB báo `Connection refused`" | Đến được máy, nhưng **không ai nghe** port 5432 → PostgreSQL chưa chạy hoặc nghe sai địa chỉ |
| "Container chạy app nhưng `docker run -p 8080:8080` vẫn không vào được" | App trong container nghe `127.0.0.1` thay vì `0.0.0.0` |
| "Server có hàng nghìn kết nối `CLOSE_WAIT`" | App không đóng kết nối — lỗi code, không phải lỗi mạng |
| "Mở Security Group rồi mà vẫn không vào được, NACL cũng mở inbound rồi" | NACL **stateless** — phải mở cả chiều trả về (ephemeral port) |

Chỉ cần đọc đúng thông báo lỗi kết nối, bạn đã loại được một nửa số nguyên nhân trước khi gõ thêm lệnh nào.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Tầng Transport làm gì?

Ở [bài 01](01-osi-tcpip-model.md), tầng **Internet (IP)** đưa gói tin từ **máy này tới máy kia**. Nhưng trên một máy có hàng chục chương trình đang chạy: Nginx, PostgreSQL, SSH server… Gói tin đến rồi thì giao cho **chương trình nào**?

Đó là việc của **tầng Transport (tầng giao vận)**, với hai giao thức chính: **TCP** và **UDP**. Chúng dùng **port (cổng)** — một con số từ 0 đến 65535 — để chỉ định chương trình nhận.

So sánh dễ nhớ:

- **Địa chỉ IP** = địa chỉ tòa nhà chung cư.
- **Port** = số căn hộ trong tòa nhà.
- **Chương trình đang nghe port** = người sống trong căn hộ đó.

### 3.2. Socket

**Socket** (điểm kết nối) là "đầu cuối" của một kết nối mạng, xác định bởi **giao thức + địa chỉ IP + port**. Ví dụ: `TCP 10.0.1.25:5432`.

Một **kết nối TCP** được xác định duy nhất bởi **4 thành phần** (bộ bốn — 4-tuple):

```text
(IP nguồn, port nguồn, IP đích, port đích)
(203.0.113.7, 51544, 10.0.1.25, 443)
```

Nhờ đó, một server nghe **một** port 443 vẫn phục vụ được hàng nghìn client cùng lúc: mỗi client có IP nguồn hoặc port nguồn khác nhau → bộ bốn khác nhau → là các kết nối khác nhau.

### 3.3. Ai mở port?

Port không tự "mở". Một **process** (học ở [Linux bài 04](../01-LINUX/04-processes-systemd.md)) gọi system call để **lắng nghe (listen)** trên một địa chỉ + port. Khi process đó dừng, port đóng lại. Vì vậy câu hỏi "port 8080 có mở không?" thực chất là "**có process nào đang nghe port 8080 không, và nghe trên địa chỉ nào?**".

---

## 4. Giải thích chi tiết

### 4.1. 🟥 TCP và UDP

| Tiêu chí | **TCP** (Transmission Control Protocol) | **UDP** (User Datagram Protocol) |
|---|---|---|
| Kết nối | Có — phải bắt tay trước khi gửi dữ liệu | Không — gửi thẳng |
| Đảm bảo đến nơi | Có: đánh số thứ tự, xác nhận (ACK), gửi lại gói bị mất | Không: mất thì thôi |
| Đúng thứ tự | Có | Không đảm bảo |
| Tốc độ / độ trễ | Chậm hơn một chút (do bắt tay, xác nhận) | Nhanh, độ trễ thấp |
| Ví dụ so sánh | Gọi điện thoại: nhấc máy, "alo", nói chuyện, chào tạm biệt | Gửi thiệp qua bưu điện: gửi đi, không biết đến chưa |
| Dùng cho | HTTP/HTTPS, SSH, PostgreSQL, MySQL, Redis, SMTP | DNS (truy vấn thường), NTP (đồng bộ giờ), DHCP, video call, game |

**Quy tắc ngón tay cái cho DevOps:** gần như mọi thứ bạn triển khai (web, API, database) dùng **TCP**. UDP gặp chủ yếu ở **DNS** (port 53) và **NTP** (port 123).

> 🟨 DNS dùng UDP cho truy vấn thường, nhưng **chuyển sang TCP** khi câu trả lời quá lớn hoặc khi đồng bộ dữ liệu giữa các DNS server. Vì vậy firewall cho DNS thường mở **cả UDP và TCP 53**.

> 🟦 HTTP/3 chạy trên **QUIC** — một giao thức xây trên UDP. Bạn chỉ cần biết nó tồn tại; bài 06 nhắc lại.

### 4.2. 🟥 TCP 3-way handshake

Trước khi gửi bất kỳ dữ liệu nào, client và server trao đổi **3 gói tin**:

```text
   Client (203.0.113.7:51544)                 Server (10.0.1.25:443)
            │                                          │  trạng thái: LISTEN
            │ ── (1) SYN  "tôi muốn kết nối" ────────► │
 SYN-SENT   │                                          │
            │ ◄── (2) SYN-ACK "đồng ý, bạn nghe rõ?" ── │  SYN-RECEIVED
            │                                          │
            │ ── (3) ACK "nghe rõ" ──────────────────► │
ESTABLISHED │                                          │  ESTABLISHED
            │ ══════ dữ liệu (HTTP, TLS, SQL...) ══════ │
```

- **SYN** (synchronize — đồng bộ): yêu cầu mở kết nối.
- **ACK** (acknowledgment — xác nhận).
- Sau bước (3), hai bên ở trạng thái **ESTABLISHED** (đã thiết lập) và bắt đầu trao đổi dữ liệu.

**Vì sao DevOps cần biết điều này?** Vì mỗi lỗi kết nối tương ứng với một kiểu "handshake hỏng":

| Server phản ứng với gói SYN thế nào | Client thấy |
|---|---|
| Không có process nghe port → kernel server trả gói **RST** (reset — từ chối) | `Connection refused` — **ngay lập tức** |
| Firewall **DROP** (vứt bỏ im lặng) gói SYN | Client gửi lại SYN vài lần, chờ… → `Connection timed out` |
| Firewall **REJECT** gói SYN (từ chối có trả lời) | `Connection refused` hoặc `No route to host` — ngay lập tức, tùy kiểu trả lời |
| Router dọc đường báo không có đường tới đích | `No route to host` hoặc `Network is unreachable` |

Chi tiết ở [mục 4.7](#47--phân-biệt-4-lỗi-kết-nối-quan-trọng-nhất).

### 4.3. 🟨 Đóng kết nối và các trạng thái TCP

Đóng kết nối dùng gói **FIN** (finish — kết thúc). Mỗi chiều đóng riêng nên thường có 4 gói: FIN → ACK → FIN → ACK.

```text
  Bên đóng trước (thường là client)           Bên kia
        │ ── FIN ─────────────────────────────► │
FIN_WAIT_1                                      │ CLOSE_WAIT  ← chờ ỨNG DỤNG gọi close()
        │ ◄── ACK ───────────────────────────── │
FIN_WAIT_2                                      │
        │ ◄── FIN ───────────────────────────── │ LAST_ACK    (ứng dụng đã close())
        │ ── ACK ─────────────────────────────► │
TIME_WAIT (chờ ~60 giây rồi mới giải phóng)     │ CLOSED
```

Bốn trạng thái bạn **sẽ gặp** khi chạy `ss`:

| Trạng thái | Nghĩa | Ý nghĩa vận hành |
|---|---|---|
| `LISTEN` | Đang lắng nghe, chờ kết nối mới | Đây là "port đang mở". Không có dòng `LISTEN` → không có dịch vụ |
| `ESTABLISHED` | Kết nối đang hoạt động | Đếm số này để biết có bao nhiêu client/kết nối DB đang mở |
| `TIME_WAIT` | Bên đóng trước chờ một lúc trước khi giải phóng hẳn | **Bình thường**, kể cả khi có hàng trăm. Chỉ đáng lo khi lên tới hàng chục nghìn trên một máy gọi đi liên tục (có thể cạn ephemeral port) |
| `CLOSE_WAIT` | Bên kia đã đóng, **ứng dụng bên này chưa đóng** socket | **Đáng lo** nếu số lượng tăng mãi: ứng dụng bị rò rỉ kết nối (connection leak) — lỗi code hoặc connection pool, không phải lỗi mạng |

> Mẹo nhớ: `CLOSE_WAIT` = "đang **chờ ứng dụng của mình** gọi close". Mạng đã làm xong phần việc của nó.

### 4.4. 🟥 Port: các dải và những port phải thuộc

Theo [IANA](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml) — tổ chức quản lý số hiệu Internet:

| Dải | Tên | Ý nghĩa |
|---|---|---|
| 0–1023 | **System / well-known ports** (port hệ thống) | Dịch vụ chuẩn. Trên Linux, process thường cần quyền root mới được nghe các port này |
| 1024–49151 | **User / registered ports** (port đã đăng ký) | Ứng dụng: 3306, 5432, 8080… |
| 49152–65535 | **Dynamic / private ports** (port động) | Dùng tạm thời |

**Ephemeral port (port tạm thời):** khi client mở kết nối đi ra, kernel tự chọn một port nguồn ngẫu nhiên. Trên Linux, dải mặc định thường là **32768–60999** (không trùng hẳn dải IANA). Xem bằng:

```bash
cat /proc/sys/net/ipv4/ip_local_port_range
```

```text
32768	60999
```

Bạn sẽ gặp lại ephemeral port khi cấu hình **Network ACL trên AWS** (Module 06): vì NACL không nhớ trạng thái, chiều trả về phải mở dải port này.

**Bảng port DevOps phải thuộc:**

| Port | Giao thức | Dịch vụ | Mức | Ghi chú |
|---|---|---|---|---|
| 22 | TCP | SSH | 🟥 | **Không bao giờ** mở ra `0.0.0.0/0` trên server thật |
| 53 | UDP + TCP | DNS | 🟥 | |
| 80 | TCP | HTTP | 🟥 | |
| 443 | TCP | HTTPS | 🟥 | |
| 123 | UDP | NTP | 🟨 | Đồng bộ giờ — lệch giờ làm hỏng TLS, token |
| 3306 | TCP | MySQL / MariaDB | 🟥 | Chỉ mở nội bộ |
| 5432 | TCP | PostgreSQL | 🟥 | Dự án taskhub. Chỉ mở nội bộ |
| 6379 | TCP | Redis | 🟥 | Chỉ mở nội bộ |
| 8080 | TCP | HTTP thay thế — **mặc định của Spring Boot**, Jenkins | 🟥 | |
| 9090 | TCP | Prometheus | 🟨 | Module 08 |
| 3000 | TCP | Grafana | 🟨 | Module 08 |
| 9100 | TCP | Node Exporter | 🟨 | Module 08 |
| 9200 / 5601 | TCP | Elasticsearch / OpenSearch, Kibana | 🟦 | Nhận biết |
| 2375 / 2376 | TCP | Docker Engine API | 🟨 | ⚠️ Lộ port này ra Internet = trao quyền root cho người lạ |

### 4.5. 🟥 Bind address: `0.0.0.0` vs `127.0.0.1` vs IP cụ thể

Đây là **phần quan trọng nhất** của bài. Khi một process lắng nghe, nó chọn **cả port lẫn địa chỉ** để nghe:

| Bind address | Nghĩa | Ai kết nối được |
|---|---|---|
| `127.0.0.1` (localhost, loopback) | Chỉ nghe trên giao diện **loopback** — mạng "ảo" bên trong chính máy đó | **Chỉ các process trên cùng máy** (cùng network namespace). Máy khác, container khác: **không** |
| `0.0.0.0` | Nghe trên **tất cả** địa chỉ IPv4 của máy | Bất kỳ ai **đến được** máy (sau khi qua firewall) |
| `10.0.1.25` (IP cụ thể) | Chỉ nghe trên đúng một card mạng | Ai kết nối tới đúng IP đó |
| `::` / `[::]` | Tương tự `0.0.0.0` cho IPv6 (trên Linux thường nhận cả IPv4) | |

Vì sao có lỗi "chạy được trên máy nhưng từ ngoài vào không được"?

```text
            ┌────────────────── Server 10.0.1.25 ──────────────────┐
            │                                                      │
 Client ──► │ eth0: 10.0.1.25 ──X──┐   (không ai nghe trên eth0)   │
 bên ngoài  │                      │                               │
            │ lo:   127.0.0.1 ─────┴──► app LISTEN 127.0.0.1:8080  │
            │                      ▲                               │
            │        curl localhost:8080 trên chính server ✅      │
            └──────────────────────────────────────────────────────┘
 Client gửi SYN tới 10.0.1.25:8080 → không có socket nào nghe trên địa chỉ đó
 → kernel trả RST → client thấy "Connection refused".
```

**Khi nào dùng cái nào?**

- Dịch vụ chỉ dùng nội bộ trên máy (ví dụ app đứng sau Nginx trên cùng server, database chỉ app cùng máy dùng): nghe `127.0.0.1` → **an toàn hơn**, kể cả khi firewall cấu hình sai.
- Dịch vụ cần nhận kết nối từ máy khác **hoặc từ ngoài container**: phải nghe `0.0.0.0` (và dùng firewall/Security Group để giới hạn ai được vào).

Ví dụ cấu hình thực tế:

| Phần mềm | Cấu hình bind | Mặc định |
|---|---|---|
| Spring Boot | `server.address` (bỏ trống = mọi địa chỉ) | Nghe mọi địa chỉ |
| Python `http.server` | `python3 -m http.server 8000 --bind 127.0.0.1` | Mọi địa chỉ |
| PostgreSQL | `listen_addresses` trong `postgresql.conf` | `localhost` (chỉ máy cục bộ) |
| Redis | `bind` trong `redis.conf` | Chỉ loopback (các bản mới) |

> **Gặp lại ở Module 04 (Docker):** mỗi container có loopback **riêng**. App trong container nghe `127.0.0.1:8080` thì `docker run -p 8080:8080` vẫn **không** vào được, vì traffic đi vào container qua card mạng `eth0` của container, không qua loopback. App trong container **phải** nghe `0.0.0.0`.

### 4.6. 🟥 Kiểm tra port bằng `ss` và `nc` (tóm tắt)

- **`ss`** (socket statistics — thống kê socket): xem **máy này** đang nghe port nào, process nào, có những kết nối nào. Thay thế cho `netstat` (cũ, thuộc gói `net-tools`, không còn được cài sẵn trên nhiều bản phân phối mới).
- **`nc`** (netcat — "con dao đa năng" của mạng): **thử kết nối** tới một host:port từ phía client, hoặc **mở tạm một port** để nghe.

Chi tiết tham số ở [mục 8](#8-giải-thích-câu-lệnh-và-tham-số).

Quy trình kiểm tra một dịch vụ luôn đi theo hai phía:

1. **Phía server:** `ss -tlnp` → dịch vụ có `LISTEN` không? Trên địa chỉ nào?
2. **Phía client:** `nc -zv <host> <port>` → kết nối được không? Nếu không, lỗi gì?

### 4.7. 🟥 Phân biệt 4 lỗi kết nối quan trọng nhất

Học thuộc bảng này. Nó sẽ tiết kiệm cho bạn hàng giờ debug trong suốt sự nghiệp.

| Thông báo lỗi | Xảy ra ở bước | Đến được máy đích chưa? | Thời gian | Nguyên nhân thường gặp | Kiểm tra tiếp |
|---|---|---|---|---|---|
| `Name or service not known` / `Could not resolve host` | **Trước** khi gửi gói tin — phân giải tên miền | Chưa gửi gì cả | Nhanh (hoặc chậm nếu DNS server không trả lời) | Gõ sai tên, DNS sai, `/etc/hosts` thiếu, tên service Docker sai | `getent hosts <tên>`, `dig <tên>` ([bài 03](03-dns-dhcp.md)) |
| `Connection refused` | Gửi SYN, nhận **RST** (hoặc ICMP port unreachable) | **Đến được** máy đích | **Ngay lập tức** | Không process nào nghe port đó; app nghe `127.0.0.1`; app đã chết; firewall REJECT | Trên server: `ss -tlnp \| grep <port>` |
| `Connection timed out` | Gửi SYN, **không nhận được gì** | Không biết — gói tin bị mất dọc đường | **Chậm** — chờ hết thời gian (mặc định có thể tới hơn 2 phút) | Firewall/Security Group/NACL **DROP**; máy đích tắt; sai route; IP sai (không có máy nào) | Security Group, NACL, firewall trên máy, route table |
| `No route to host` | Kernel hoặc router báo **không có đường** tới đích | Không | Thường nhanh | Không có route; máy đích không trả lời ARP trong cùng mạng; firewall REJECT kiểu `icmp-host-unreachable` | `ip route`, `ip route get <IP>` ([bài 04](04-routing-nat-switching.md)) |

**Suy luận nhanh:**

```text
Lỗi DNS?        → chưa đi tới tầng mạng: sửa tên/DNS trước.
Refused nhanh?  → mạng THÔNG, máy đích còn sống: vấn đề ở APP (không nghe / nghe sai địa chỉ).
Timeout chậm?   → có thứ gì đó VỨT gói tin im lặng: nghi FIREWALL / SECURITY GROUP trước.
No route?       → vấn đề ĐỊNH TUYẾN hoặc máy đích không tồn tại trong mạng.
```

> Trên AWS, gần như mọi trường hợp "timeout" khi bạn mới tạo EC2 là do **Security Group chưa mở port**. Security Group không trả lời gói bị chặn — nó DROP — nên bạn thấy timeout chứ không phải refused.

### 4.8. 🟥 Firewall: stateful và stateless

**Firewall (tường lửa)** quyết định gói tin nào được đi qua dựa trên luật: IP nguồn/đích, port, giao thức.

**Nguyên tắc allow-list (danh sách cho phép):** mặc định **chặn tất cả**, chỉ mở đúng những gì cần. Đây là cách Security Group của AWS hoạt động: Security Group mới tạo **không có luật inbound nào** → mọi kết nối vào đều bị chặn.

| | **Stateful** (có nhớ trạng thái) | **Stateless** (không nhớ trạng thái) |
|---|---|---|
| Cách hoạt động | Nhớ các kết nối đã cho phép (connection tracking). Gói **trả lời** của kết nối đã được phép tự động được cho qua | Xét **từng gói** độc lập, không biết gói đó thuộc kết nối nào |
| Muốn cho client vào port 443 | Chỉ cần 1 luật inbound `443` | Cần luật inbound `443` **và** luật outbound cho chiều trả về (tới ephemeral port của client) |
| Ví dụ | iptables với `conntrack`, ufw, **AWS Security Group** | **AWS Network ACL** |

> **Gặp lại ở Module 06:** theo [tài liệu AWS](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html), Security Group là stateful — phản hồi của một request được phép sẽ tự được cho qua bất kể luật chiều ngược lại. Network ACL thì stateless, nên bạn phải tự mở chiều trả về.

### 4.9. 🟨 iptables và ufw ở mức cần dùng

**iptables** là công cụ cấu hình bộ lọc gói tin trong kernel Linux (netfilter). Các khái niệm cần biết:

| Khái niệm | Nghĩa |
|---|---|
| **Table `filter`** (bảng lọc) | Bảng mặc định, chứa luật cho phép/chặn |
| **Table `nat`** | Luật đổi địa chỉ (NAT — [bài 04](04-routing-nat-switching.md)). Docker dùng bảng này cho `-p` |
| **Chain `INPUT`** | Gói tin **đi vào** chính máy này |
| **Chain `OUTPUT`** | Gói tin **do máy này gửi ra** |
| **Chain `FORWARD`** | Gói tin **đi xuyên qua** máy này sang máy khác (máy đóng vai router — ví dụ host chuyển gói cho container) |
| **Target `ACCEPT`** | Cho qua |
| **Target `DROP`** | Vứt bỏ **im lặng** → client thấy **timeout** |
| **Target `REJECT`** | Vứt bỏ và **gửi thông báo từ chối** → client thấy **refused** (hoặc no route, tùy loại thông báo) ngay lập tức |

Luật được xét **từ trên xuống**, gặp luật khớp đầu tiên thì áp dụng. Không luật nào khớp → áp dụng **policy** (chính sách mặc định) của chain.

**DROP hay REJECT?** Firewall hướng ra Internet thường dùng DROP: không tiết lộ thông tin cho kẻ dò quét, và không tốn công trả lời. Firewall nội bộ có khi dùng REJECT để client báo lỗi nhanh hơn, dễ debug hơn.

**ufw** (Uncomplicated Firewall — firewall đơn giản) là lớp giao diện dễ dùng của Ubuntu, bên dưới vẫn sinh ra luật iptables:

```bash
sudo ufw default deny incoming     # mặc định chặn mọi kết nối vào
sudo ufw default allow outgoing    # cho phép mọi kết nối đi ra
sudo ufw allow 22/tcp              # PHẢI có trước khi enable trên server qua SSH
sudo ufw allow 80,443/tcp
sudo ufw enable
sudo ufw status verbose
```

> ⚠️ **Trên server thật qua SSH:** bật ufw (hoặc đặt policy DROP cho iptables) **trước khi** cho phép port 22 = tự khóa mình ở ngoài. Trên EC2, lúc đó bạn chỉ còn cách dùng SSM Session Manager hoặc tạo lại instance.

> ⚠️ Bài này **không** chạy ufw/iptables trên WSL của bạn: WSL nằm sau Windows Firewall, và sửa luật trên WSL dễ làm hỏng kết nối của Docker Desktop. Mọi thực hành firewall làm trong `[Sandbox]`. Thực hành ufw thật sẽ làm trên EC2 ở tuần 12.

### 4.10. Gặp lại ở đâu

| Khái niệm trong bài | Gặp lại ở |
|---|---|
| Bind `0.0.0.0` vs `127.0.0.1` | Docker: app trong container phải nghe `0.0.0.0`; `-p 127.0.0.1:5432:5432` để chỉ máy host vào được DB (Module 04) |
| Port publish | Docker `-p` dùng NAT trong iptables (Module 04) |
| Firewall stateful / stateless | Security Group / Network ACL (Module 06) |
| Timeout vs refused | Debug EC2, RDS, ALB health check (Module 06) |
| `ss`, `nc` | Debug container: `docker exec <c> ss -tlnp` (Module 04); Kubernetes Pod (Module 09) |
| Port nội bộ (5432, 6379) | Không bao giờ mở ra Internet — Security (Module 10) |
| Kubernetes | Service, `containerPort`, NetworkPolicy là firewall cho Pod (Module 09) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Spring Boot chạy rồi mà Nginx vẫn báo 502"

Kỹ sư kinh nghiệm không đoán mà kiểm tra lần lượt:

```bash
sudo ss -tlnp | grep -E ':80|:8080'
```

```text
LISTEN 0  511   0.0.0.0:80    0.0.0.0:*  users:(("nginx",pid=812,fd=6),("nginx",pid=811,fd=6))
LISTEN 0  100         *:8081        *:*  users:(("java",pid=2045,fd=19))
```

App đang nghe **8081**, còn Nginx cấu hình `proxy_pass http://127.0.0.1:8080`. Không ai nghe 8080 → Nginx nhận `Connection refused` → trả 502 cho người dùng. Sửa: thống nhất port. Không cần đọc một dòng code nào.

### Ví dụ 2: "Kết nối DB từ máy app bị treo 2 phút rồi báo lỗi"

```text
org.postgresql.util.PSQLException: The connection attempt failed.
Caused by: java.net.SocketTimeoutException: Connect timed out
```

**Timeout**, không phải refused → gói tin bị vứt im lặng. Kiểm tra theo thứ tự: Security Group của DB có cho Security Group của app vào port 5432 không? NACL? Route table? Kỹ sư mới thường đi kiểm tra mật khẩu DB — vô ích, vì kết nối còn chưa tới được PostgreSQL.

### Ví dụ 3: Hàng nghìn `CLOSE_WAIT`

```bash
ss -tan state close-wait | wc -l
```

```text
3842
```

Số này tăng dần theo thời gian, rồi app báo `Too many open files`. Nguyên nhân: code gọi HTTP tới dịch vụ khác nhưng không đóng response/connection. Mạng không có lỗi gì — **cần báo lại cho developer**, kèm số liệu `ss` làm bằng chứng.

---

## 6. Sơ đồ kiến trúc

### 6.1. Một request đi qua các lớp kiểm tra

```text
Client ──SYN──►  [Security Group / firewall]  ──►  [máy đích]  ──►  [socket đang LISTEN?]  ──►  App
                         │                              │                     │
                   bị DROP → TIMEOUT          không có route →          không ai nghe /
                   bị REJECT → REFUSED        NO ROUTE TO HOST          nghe 127.0.0.1 → REFUSED
```

### 6.2. Stateful vs stateless với một request HTTPS

```text
                    STATEFUL (Security Group)            STATELESS (Network ACL)
Client:51544 ─► Server:443   luật inbound 443 ✅          luật inbound 443 ✅
Server:443  ─► Client:51544  tự cho qua (nhớ kết nối) ✅   cần luật outbound tới 1024–65535 ❗
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ss -tlnp` | Liệt kê port TCP đang nghe kèm process | 🟥 |
| `ss -tulnp` | Như trên, thêm UDP | 🟥 |
| `ss -tan` / `ss -tn state <trạng thái>` | Xem mọi kết nối TCP / lọc theo trạng thái | 🟥 |
| `ss -tn sport = :<port>` | Lọc theo port | 🟨 |
| `nc -zv <host> <port>` | Kiểm tra kết nối tới một port | 🟥 |
| `nc -l <port>` | Mở tạm một port để nghe | 🟥 |
| `python3 -m http.server <port> --bind <địa chỉ>` | Dựng nhanh một web server để thử | 🟥 |
| `curl --connect-timeout <giây>` | Giới hạn thời gian chờ kết nối khi thử | 🟥 |
| `cat /proc/sys/net/ipv4/ip_local_port_range` | Xem dải ephemeral port | 🟨 |
| `iptables -L -n -v --line-numbers` | Xem luật firewall | 🟨 |
| `iptables -A/-I/-D` | Thêm/chèn/xóa luật | 🟨 |
| `ufw status verbose` / `ufw allow` | Firewall đơn giản của Ubuntu | 🟨 |
| `netstat -tlnp` | Lệnh cũ tương đương `ss -tlnp` | 🟦 nhận biết |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa** trên Ubuntu 24.04/WSL. PID, IP, số liệu trên máy bạn sẽ khác.

### `ss` — socket statistics

```bash
ss -tlnp
```

```text
State   Recv-Q  Send-Q   Local Address:Port    Peer Address:Port  Process
LISTEN  0       5            127.0.0.1:8001         0.0.0.0:*      users:(("python3",pid=2101,fd=3))
LISTEN  0       5              0.0.0.0:8002         0.0.0.0:*      users:(("python3",pid=2102,fd=3))
LISTEN  0       4096     127.0.0.53%lo:53           0.0.0.0:*
```

| Tham số | Ý nghĩa |
|---|---|
| `-t` | Chỉ TCP |
| `-u` | Chỉ UDP |
| `-l` | Chỉ socket đang **LISTEN** (nghe) |
| `-a` | Tất cả: cả đang nghe lẫn đã kết nối |
| `-n` | Hiện **số** port và IP, không đổi thành tên (`:http`, `localhost`) — nhanh hơn và rõ hơn |
| `-p` | Hiện **process** dùng socket. Process của user khác (ví dụ của root) chỉ hiện khi chạy bằng `sudo` |

**Đọc từng cột:**

| Cột | Ý nghĩa |
|---|---|
| `State` | Trạng thái TCP |
| `Recv-Q` / `Send-Q` | Với socket `LISTEN`: `Recv-Q` = số kết nối đang chờ app nhận (accept), `Send-Q` = kích thước hàng đợi tối đa (backlog). `Recv-Q` thường xuyên chạm `Send-Q` → app không kịp nhận kết nối |
| `Local Address:Port` | **Bind address** và port. Đây là cột trả lời câu hỏi "ai vào được" |
| `Peer Address:Port` | Đầu bên kia. Với `LISTEN` là `*` hoặc `0.0.0.0:*` |
| `Process` | Tên process, PID, file descriptor |

Dòng `127.0.0.53%lo:53` là **systemd-resolved** — DNS cache cục bộ của Ubuntu (học ở [bài 03](03-dns-dhcp.md)). `%lo` nghĩa là chỉ nghe trên giao diện loopback. Trên WSL dòng này có thể không có, tùy cấu hình.

**Lọc theo trạng thái và port:**

```bash
ss -tan                                  # mọi kết nối TCP, kèm trạng thái
ss -tn state established                 # chỉ kết nối đang hoạt động
ss -tn state time-wait | wc -l           # đếm TIME_WAIT (trừ 1 dòng tiêu đề)
ss -tn state close-wait
ss -tn sport = :8002                     # kết nối có port NGUỒN 8002 (phía server)
ss -tn dport = :443                      # kết nối có port ĐÍCH 443 (máy này gọi đi)
```

> Khi có bộ lọc `state`, cột `State` không còn được in ra (vì đã biết trạng thái).

### `nc` — netcat

Ubuntu dùng bản **netcat-openbsd**. Kiểm tra: `nc -h 2>&1 | head -1`. Cài nếu thiếu: `sudo apt install netcat-openbsd`.

**Kiểm tra kết nối (phía client):**

```bash
nc -zv 127.0.0.1 8002
nc -zv 127.0.0.1 8009
nc -zv -w 3 10.255.255.1 80
```

```text
Connection to 127.0.0.1 8002 port [tcp/*] succeeded!
nc: connect to 127.0.0.1 port 8009 (tcp) failed: Connection refused
nc: connect to 10.255.255.1 port 80 (tcp) timed out: Operation now in progress
```

| Tham số | Ý nghĩa |
|---|---|
| `-z` | Chỉ thử kết nối, không gửi dữ liệu (zero-I/O) |
| `-v` | In chi tiết kết quả (verbose) |
| `-w <giây>` | Thời gian chờ tối đa — luôn đặt khi thử host có thể bị chặn, để không phải chờ quá lâu |
| `-u` | Dùng UDP thay vì TCP (kết quả UDP khó tin cậy vì UDP không có handshake) |

> `nc -zv` hữu ích khi server/container **không có `curl`** hoặc khi dịch vụ không nói HTTP (PostgreSQL, Redis): `nc -zv db.internal 5432`.

**Mở tạm một port để nghe (phía server):**

```bash
nc -l 9999          # terminal 1: nghe port 9999, in ra mọi thứ nhận được
nc 127.0.0.1 9999   # terminal 2: kết nối tới, gõ chữ → hiện bên terminal 1
```

Dùng để trả lời câu hỏi "**firewall có cho qua port X không?**" khi chưa có ứng dụng thật: dựng `nc -l X` ở máy đích, thử `nc -zv` từ máy nguồn.

### `python3 -m http.server` — web server dựng nhanh

```bash
python3 -m http.server 8001 --bind 127.0.0.1
```

```text
Serving HTTP on 127.0.0.1 port 8001 (http://127.0.0.1:8001/) ...
```

Phục vụ file trong thư mục hiện tại. `--bind` chọn địa chỉ nghe; bỏ qua thì nghe tất cả. `Ctrl+C` để dừng. Python 3 (3.12) có sẵn trên Ubuntu 24.04.

### `curl --connect-timeout` — thử kết nối HTTP có giới hạn thời gian

```bash
curl -sS --connect-timeout 5 http://10.255.255.1/
echo "exit code: $?"
```

```text
curl: (28) Connection timed out after 5001 milliseconds
exit code: 28
```

| Exit code của curl | Nghĩa | Tương ứng |
|---|---|---|
| `6` | Không phân giải được tên | Lỗi DNS |
| `7` | Không kết nối được (refused, no route) | Refused / no route |
| `28` | Hết thời gian chờ **do curl đặt** (`--connect-timeout`, `--max-time`) | Timeout |

> Nếu bạn **không** đặt `--connect-timeout`, hệ điều hành sẽ tự bỏ cuộc sau một thời gian dài và curl có thể báo exit code `7` kèm dòng chữ `Connection timed out`. Vì vậy: **luôn đọc phần chữ** của thông báo lỗi, đừng chỉ nhìn con số.

`-sS`: ẩn thanh tiến trình (`-s`) nhưng vẫn in lỗi (`-S`). Bài 06 dạy `curl` chi tiết.

### `iptables` — xem và sửa luật firewall (chỉ trong `[Sandbox]`)

```bash
iptables -L INPUT -n -v --line-numbers
```

```text
Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
num   pkts bytes target  prot opt in  out  source      destination
1        3   180 DROP    tcp  --  *   *    0.0.0.0/0   0.0.0.0/0    tcp dpt:9001
2        2   120 REJECT  tcp  --  *   *    0.0.0.0/0   0.0.0.0/0    tcp dpt:9002 reject-with icmp-port-unreachable
```

| Tham số | Ý nghĩa |
|---|---|
| `-L [chain]` | Liệt kê luật (list) |
| `-n` | Hiện số, không tra tên |
| `-v` | Hiện bộ đếm gói/byte — **cột `pkts` tăng = luật đang khớp**, rất hữu ích khi debug |
| `--line-numbers` | Đánh số luật, dùng để xóa theo số |
| `-A INPUT ...` | Thêm luật vào **cuối** chain (append) |
| `-I INPUT ...` | Chèn luật lên **đầu** chain (insert) |
| `-D INPUT <số>` | Xóa luật theo số thứ tự |
| `-p tcp --dport 9001` | Khớp gói TCP có port đích 9001 |
| `-j DROP` / `-j REJECT` | Hành động (jump to target) |
| `--reject-with tcp-reset` | Từ chối bằng gói RST (giống hệt "không ai nghe") |
| `--reject-with icmp-host-unreachable` | Từ chối bằng thông báo "không tới được host" → client thấy `No route to host` |

### `netstat` — nhận biết

```bash
netstat -tlnp     # cùng ý nghĩa với ss -tlnp
```

Bạn sẽ thấy lệnh này trong tài liệu và blog cũ. Gói `net-tools` không còn được cài sẵn trên nhiều bản phân phối. Hãy dùng `ss`; nếu gặp `netstat` trong tài liệu, các tham số `-tlnp` có cùng ý nghĩa.

---

## 9. Bài thực hành từng bước

**Lab: Bind address, 4 lỗi kết nối và DROP vs REJECT** · `[WSL]` + `[PowerShell]` + `[Sandbox]` · ~90 phút

Ghi kết quả vào `~/devops-lab/02-networking/lab05-answers.md`, cuối lab commit vào `~/devops-journey/week05/`.

### Phần A — Bind address trên WSL `[WSL]`

**Bước 1 — Dựng 2 server.** Mở 2 terminal WSL:

```bash
# Terminal 1
mkdir -p ~/devops-lab/02-networking && cd ~/devops-lab/02-networking
echo "hello from 8001 (127.0.0.1)" > index.html
python3 -m http.server 8001 --bind 127.0.0.1
```

```bash
# Terminal 2
mkdir -p /tmp/srv8002 && cd /tmp/srv8002
echo "hello from 8002 (0.0.0.0)" > index.html
python3 -m http.server 8002 --bind 0.0.0.0
```

**Bước 2 — Quan sát phía server.** Terminal thứ 3:

```bash
ss -tlnp | grep -E ':800[12]'
```

❓ Cột `Local Address` của hai dòng khác nhau thế nào?

**Bước 3 — Thử qua loopback.**

```bash
curl -s http://127.0.0.1:8001
curl -s http://127.0.0.1:8002
```

❓ Cả hai đều trả lời được không? Vì sao?

**Bước 4 — Thử qua IP của card mạng `eth0`.**

```bash
WSL_IP=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)
echo "$WSL_IP"
curl -sS --connect-timeout 5 "http://$WSL_IP:8001"; echo "exit=$?"
curl -sS --connect-timeout 5 "http://$WSL_IP:8002"; echo "exit=$?"
```

❓ Server 8001 trả lỗi gì? Lỗi đến nhanh hay chậm? Exit code là bao nhiêu? Giải thích bằng sơ đồ mục 4.5.

**Bước 5 — Thử từ Windows `[PowerShell]`.**

```powershell
curl.exe -s --connect-timeout 5 http://localhost:8001
curl.exe -s --connect-timeout 5 http://localhost:8002
```

> Dùng `curl.exe` chứ không phải `curl`: trong Windows PowerShell 5.1, `curl` là tên tắt của một lệnh PowerShell khác.

❓ Ghi lại kết quả. **Kết quả này phụ thuộc chế độ mạng của WSL** (NAT mặc định có tính năng chuyển tiếp `localhost` từ Windows vào WSL; chế độ *mirrored* chia sẻ mạng với Windows). Đừng lo nếu kết quả của bạn khác bạn bè — điều quan trọng là **Bước 4**, nơi kết quả luôn nhất quán. Ghi lại chế độ mạng của bạn để đối chiếu khi học [bài 04](04-routing-nat-switching.md).

**Bước 6 — Tắt server 8001** (`Ctrl+C` ở terminal 1), rồi chạy lại `curl -sS http://127.0.0.1:8001; echo "exit=$?"`.

❓ Lỗi bây giờ là gì? So sánh với lỗi ở Bước 4: giống hay khác? Vì sao hai nguyên nhân khác nhau lại cho **cùng một** thông báo lỗi?

### Phần B — Lỗi DNS `[WSL]`

**Bước 7.**

```bash
curl -sS --connect-timeout 5 http://taskhub-db.invalid:5432; echo "exit=$?"
nc -zv -w 3 taskhub-db.invalid 5432
getent hosts taskhub-db.invalid; echo "exit=$?"
```

❓ Ba lệnh báo lỗi khác nhau thế nào? Lỗi xảy ra trước hay sau khi gửi gói tin tới máy đích? (Tên miền `.invalid` được dành riêng để **không bao giờ** phân giải được — rất tiện cho thử nghiệm.)

### Phần C — DROP vs REJECT vs no route `[Sandbox]`

**Bước 8 — Khởi động sandbox có quyền quản trị mạng:**

```bash
docker run --rm -it --cap-add=NET_ADMIN --name netlab ubuntu:22.04 bash
```

`--cap-add=NET_ADMIN` cấp cho container quyền sửa luật firewall và bảng route **của riêng nó** — không ảnh hưởng WSL.

Trong container:

```bash
apt-get update -qq && apt-get install -y -qq iproute2 iptables curl netcat-openbsd python3 >/dev/null
MYIP=$(hostname -I | awk '{print $1}'); echo "$MYIP"
cd /tmp && echo ok > index.html
python3 -m http.server 9000 --bind 0.0.0.0 >/dev/null 2>&1 &
python3 -m http.server 9001 --bind 0.0.0.0 >/dev/null 2>&1 &
python3 -m http.server 9002 --bind 0.0.0.0 >/dev/null 2>&1 &
sleep 1; ss -tln
```

**Bước 9 — Thêm luật firewall:**

```bash
iptables -A INPUT -p tcp --dport 9001 -j DROP
iptables -A INPUT -p tcp --dport 9002 -j REJECT
iptables -L INPUT -n -v --line-numbers
```

> Nếu `iptables` báo lỗi kiểu `can't initialize iptables table` (do khác biệt giữa iptables-nft và iptables-legacy với kernel), thử: `update-alternatives --set iptables /usr/sbin/iptables-legacy` rồi chạy lại. Ghi lại nếu bạn gặp lỗi này.

**Bước 10 — Thử cả 3 port, đo thời gian:**

```bash
for p in 9000 9001 9002; do
  echo "== port $p"
  time curl -sS --connect-timeout 5 "http://$MYIP:$p/" ; echo "exit=$?"
done
iptables -L INPUT -n -v --line-numbers
```

❓ Điền bảng: port | thông báo lỗi | thời gian | exit code | cột `pkts` của luật tương ứng.

**Bước 11 — No route to host:**

```bash
ip route add unreachable 10.99.0.0/16
ip route
curl -sS --connect-timeout 5 http://10.99.0.10/ ; echo "exit=$?"
iptables -I INPUT 1 -p tcp --dport 9000 -j REJECT --reject-with icmp-host-unreachable
curl -sS --connect-timeout 5 "http://$MYIP:9000/" ; echo "exit=$?"
```

❓ Hai cách tạo ra `No route to host` khác nhau ở đâu? Cách nào là "giả" do firewall?

**Bước 12 — Dọn dẹp:** gõ `exit`. Container tự xóa (`--rm`), mọi luật iptables và route biến mất theo.

### Phần D — Commit

```bash
cp ~/devops-lab/02-networking/lab05-answers.md ~/devops-journey/week05/
cd ~/devops-journey && git add week05/lab05-answers.md
git commit -m "docs(network): lab 05 - bind address, connection errors, firewall"
git push
```

Dừng server 8002 bằng `Ctrl+C`.

---

## 10. Kết quả mong đợi

- **Bước 2:** 8001 hiện `127.0.0.1:8001`, 8002 hiện `0.0.0.0:8002`.
- **Bước 3:** cả hai trả lời được — kết nối tới `127.0.0.1` đi qua loopback, và `0.0.0.0` bao gồm cả loopback.
- **Bước 4:** 8001 báo `curl: (7) Failed to connect to <IP> port 8001 ... Connection refused` **ngay lập tức**, exit code `7`. 8002 trả nội dung. Lý do: không có socket nào nghe trên địa chỉ `eth0` port 8001 → kernel trả RST.
- **Bước 6:** cũng là `Connection refused`. Từ phía client, "không ai nghe trên địa chỉ này" và "không ai nghe port này" giống hệt nhau — đều là kernel trả RST. Vì vậy khi thấy refused, phải sang **phía server** chạy `ss -tlnp` để phân biệt.
- **Bước 7:** `curl: (6) Could not resolve host`, `nc: getaddrinfo ... Name or service not known`, `getent` không in gì và exit code khác 0. Lỗi xảy ra **trước** khi gửi bất kỳ gói tin nào tới đích.
- **Bước 10:**

| Port | Thông báo | Thời gian | Exit |
|---|---|---|---|
| 9000 | Trả `ok` | Tức thì | 0 |
| 9001 (DROP) | `Connection timed out after 5001 milliseconds` | ~5 giây (đúng bằng `--connect-timeout`) | 28 |
| 9002 (REJECT) | `Connection refused` | Tức thì | 7 |

  Cột `pkts` của luật DROP tăng nhiều hơn 1 (client gửi lại SYN), của luật REJECT tăng 1.
- **Bước 11:** cả hai đều ra `No route to host` (exit 7). Route `unreachable` là lỗi định tuyến thật; luật REJECT `icmp-host-unreachable` là firewall **giả vờ** host không tới được. Bài học: thông báo lỗi cho biết **triệu chứng**, cần thêm bằng chứng (route table, luật firewall) để kết luận **nguyên nhân**.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `ss -tlnp` không hiện cột Process cho một số dòng | Process thuộc user khác (root, postgres) | Chạy `sudo ss -tlnp` |
| App báo `Address already in use` / `Port 8080 was already in use` khi khởi động | Port đã có process khác nghe (thường là bản cũ của chính app chưa tắt) | `sudo ss -tlnp \| grep :8080` → tìm PID → dừng process đó hoặc đổi port |
| App nghe port < 1024 báo `Permission denied` | Port hệ thống cần quyền root | Cho app nghe port cao (8080) và để Nginx nghe 80/443 — chính là mô hình reverse proxy ở [bài 07](07-load-balancing-reverse-proxy.md) |
| Từ máy khác báo refused dù `ss` thấy `LISTEN` | App nghe `127.0.0.1` | Đổi bind address (ví dụ `server.address` của Spring Boot, `listen_addresses` của PostgreSQL) |
| Thử kết nối bị treo rất lâu | Gói bị DROP; mặc định hệ điều hành chờ lâu | Luôn dùng `--connect-timeout` (curl) hoặc `-w` (nc) khi thử |
| Mở port trong firewall rồi mà vẫn timeout | Còn lớp chặn khác: Security Group, NACL, firewall trên máy, Windows Firewall | Liệt kê **mọi lớp** giữa client và server, kiểm tra từng lớp |
| `nc -zv` UDP báo "succeeded" nhưng dịch vụ không hoạt động | UDP không có handshake, nc không biết chắc gói có tới không | Kiểm tra bằng công cụ của chính giao thức (ví dụ `dig` cho DNS) |
| Lỡ `iptables -P INPUT DROP` trên máy đang SSH vào | Tự khóa mình | Trên máy thật: dùng console/SSM. Phòng ngừa: luôn thêm luật cho SSH và `ESTABLISHED,RELATED` **trước** khi đổi policy |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Lỗi kết nối trong log ứng dụng Java

Thông báo lỗi kết nối trong Java nằm ở các dòng `Caused by` (xem lại cách đọc stack trace ở [Linux bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md)). Ánh xạ sang bảng 4 lỗi:

| Trong log Java | Tương ứng |
|---|---|
| `java.net.ConnectException: Connection refused` | Refused → kiểm tra dịch vụ đích có nghe không |
| `java.net.SocketTimeoutException: Connect timed out` | Timeout → kiểm tra firewall/Security Group |
| `java.net.NoRouteToHostException: No route to host` | No route → kiểm tra route, IP đích |
| `java.net.UnknownHostException: taskhub-db` | Lỗi DNS → kiểm tra tên host |
| `java.net.SocketTimeoutException: Read timed out` | ⚠️ Khác hẳn: kết nối **đã thành công**, nhưng bên kia trả lời quá chậm → vấn đề hiệu năng của dịch vụ đích, không phải firewall |

Phân biệt **connect timeout** (chưa kết nối được) và **read timeout** (kết nối rồi nhưng chờ dữ liệu quá lâu) là kỹ năng rất được đánh giá cao khi phỏng vấn.

### 12.2. Quy trình debug "không kết nối được tới dịch vụ X"

```text
1. Đọc nguyên văn thông báo lỗi → xếp vào 1 trong 4 loại (mục 4.7).
2. Lỗi DNS?       → getent hosts / dig (bài 03). Dừng ở đây cho tới khi phân giải đúng.
3. Phía SERVER:   sudo ss -tlnp | grep <port>
                  - Không có LISTEN → dịch vụ chưa chạy: systemctl status / journalctl (Linux bài 04, 07)
                  - LISTEN 127.0.0.1 → sửa bind address
4. Phía CLIENT:   nc -zv -w 3 <host> <port>
                  - Refused → quay lại bước 3 / firewall REJECT
                  - Timeout → kiểm tra từng lớp firewall/SG/NACL; route
5. Thử từ CHÍNH server: curl localhost:<port>
                  - OK trên server, lỗi từ ngoài → vấn đề nằm giữa (firewall, bind address)
6. Ghi lại vào troubleshooting-journal.md.
```

Bước 5 là kỹ thuật **chia đôi (bisect)**: thu hẹp phạm vi lỗi bằng cách thử từ các điểm khác nhau trên đường đi.

### 12.3. Bộ đếm của firewall là "log" miễn phí

Khi nghi firewall chặn, chạy `iptables -L -n -v` hai lần, trước và sau khi thử kết nối. Luật nào có cột `pkts` tăng → luật đó đang khớp với traffic của bạn. Trên AWS, công cụ tương đương là **VPC Flow Logs** và **Reachability Analyzer** (Module 06).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Vì sao HTTP, SSH, PostgreSQL dùng TCP còn DNS dùng chủ yếu UDP?
2. Vẽ TCP 3-way handshake. Gói nào bị thiếu khi client thấy "timeout"? Khi thấy "refused", server đã gửi gì?
3. Một server chỉ nghe port 443 làm sao phục vụ được 10.000 client cùng lúc?
4. `TIME_WAIT` và `CLOSE_WAIT` khác nhau thế nào? Cái nào đáng lo hơn và vì sao?
5. Ephemeral port là gì? Vì sao nó quan trọng khi cấu hình Network ACL?
6. App nghe `127.0.0.1:8080`. Ai truy cập được, ai không? Nếu app chạy trong container thì sao?
7. Khi nào **nên** cho dịch vụ nghe `127.0.0.1`?
8. Phân biệt `Connection refused` và `Connection timed out`: nguyên nhân, thời gian xuất hiện, bước kiểm tra tiếp theo.
9. Bạn nhận được cùng một lỗi `Connection refused` trong hai tình huống khác nhau. Kể hai tình huống đó và cách phân biệt.
10. `DROP` và `REJECT` khác nhau thế nào từ góc nhìn client? Vì sao firewall hướng Internet thường dùng `DROP`?
11. Stateful và stateless firewall khác nhau thế nào? Security Group thuộc loại nào? Network ACL thuộc loại nào?
12. `SocketTimeoutException: Connect timed out` và `Read timed out` khác nhau thế nào? Mỗi loại gợi ý kiểm tra gì?
13. Vì sao không bao giờ mở port 22, 5432, 2375 ra `0.0.0.0/0`?
14. Liệt kê port mặc định của: SSH, DNS, HTTPS, PostgreSQL, Redis, Spring Boot, Prometheus, Grafana.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/05-solutions.md](solutions/05-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Kiểm kê port.** Trên WSL, chạy `sudo ss -tulnp`. Với **mỗi** dòng `LISTEN`/`UNCONN`: process nào, bind address nào, theo bạn dịch vụ đó có cần mở ra ngoài không? Trình bày dưới dạng bảng.

**Bài 2 — Đọc bối cảnh.** Đọc từng đoạn log sau và trả lời: (a) thuộc loại lỗi nào, (b) chỗ hỏng **có thể** nằm ở đâu, (c) 2 lệnh đầu tiên bạn chạy để kiểm chứng.

```text
(1) Caused by: java.net.UnknownHostException: postgres
(2) Caused by: java.net.ConnectException: Connection refused
        at ... PgConnection ... 10.0.11.20:5432
(3) curl: (7) Failed to connect to 13.250.10.4 port 443 after 130204 ms: Connection timed out
(4) java.net.SocketTimeoutException: Read timed out
        at ... RestTemplate ... http://payment-service:8080/api/charge
```

**Bài 3 — CLOSE_WAIT.** Viết một script Bash (dùng kiến thức [Linux bài 06](../01-LINUX/06-bash-scripting.md)) in ra số kết nối TCP theo từng trạng thái (`ESTAB`, `TIME-WAIT`, `CLOSE-WAIT`…) và cảnh báo khi `CLOSE-WAIT` vượt ngưỡng truyền qua biến môi trường. Gợi ý: `ss -tan | awk ...`.

**Bài 4 — Firewall stateful.** Trong `[Sandbox]` có `NET_ADMIN`, hãy cấu hình iptables sao cho: chỉ cho phép kết nối **vào** port 9000; chặn mọi kết nối vào khác; nhưng container vẫn `curl` ra Internet được (ví dụ `curl -I https://example.com`). Gợi ý: luật `-m conntrack --ctstate ESTABLISHED,RELATED` và policy. Giải thích vì sao thiếu luật conntrack thì `curl` ra ngoài bị hỏng.

**Bài 5 — Port bị chiếm.** Mở `python3 -m http.server 8080` ở một terminal. Ở terminal khác, chạy lại đúng lệnh đó. Ghi lại lỗi. Viết các bước tìm và dừng process đang chiếm port **chỉ dùng** `ss` và `kill` (không dùng `fuser`, `lsof`). Viết một mục `troubleshooting-journal.md` hoàn chỉnh.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Nghe một thông báo lỗi kết nối, bạn nói ngay được nó thuộc loại nào và **lệnh đầu tiên** cần chạy.
- [ ] Giải thích được bằng sơ đồ vì sao app nghe `127.0.0.1` thì từ ngoài vào bị refused.
- [ ] Đọc được mọi cột của `ss -tlnp`.
- [ ] Tự tái hiện được timeout, refused, no route trong sandbox mà không nhìn hướng dẫn.
- [ ] Giải thích được vì sao NACL phải mở dải ephemeral port còn Security Group thì không cần.
- [ ] Làm xong Bài tập 2 và 4 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [IANA Service Name and Transport Protocol Port Number Registry](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml) | Dải port chính thức | 2026-10-31 |
| [AWS — Control traffic using security groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html) | Security Group stateful | 2026-10-31 |
| [Linux Journey — Networking Nomad](https://labex.io/linuxjourney) | Ôn lại TCP/UDP, port | 2026-10-31 |
| [Cisco Networking Academy — Networking Essentials](https://www.netacad.com/courses/networking/networking-essentials) | Module về tầng Transport (tùy chọn) | 2026-10-31 (🔎 qua tìm kiếm) |
| `man ss`, `man nc`, `man iptables` (chạy trên máy) | Tham số đầy đủ | — |
