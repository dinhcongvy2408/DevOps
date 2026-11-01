# 08. Bộ công cụ chẩn đoán mạng

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: bài [01](01-osi-tcpip-model.md) → [07](07-load-balancing-reverse-proxy.md) của module này
> Môi trường: `[WSL]` Ubuntu 24.04, `[Sandbox]` container `ubuntu:22.04` (cần `--cap-add=NET_ADMIN` cho một bài tập), `[PowerShell]` (tùy chọn, mở file bằng Wireshark)

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

Đây là bài **tổng hợp** của Module 02. Sau bài này, bạn có thể:

- Áp dụng một **quy trình debug mạng theo tầng** thay vì thử lung tung: DNS → đường đi → port → TLS → HTTP → log ứng dụng.
- Dùng `ping` đúng cách và hiểu vì sao "ping không được" **chưa chắc** là máy chết.
- Bắt và đọc gói tin bằng `tcpdump`: nhận ra TCP handshake, dữ liệu, FIN, RST, truy vấn DNS.
- Đọc được tài liệu cũ dùng `netstat`, `ifconfig`, `route` và chuyển sang lệnh hiện đại.
- Trả lời trôi chảy câu phỏng vấn kinh điển **"Gõ `https://example.com` vào trình duyệt thì chuyện gì xảy ra?"** — kèm lệnh chứng minh từng bước.

> Bài này **không dạy lại** các lệnh đã học sâu: `dig`/`nslookup` ([bài 03](03-dns-dhcp.md)), `ip route`/`traceroute` ([bài 04](04-routing-nat-switching.md)), `ss`/`nc` ([bài 05](05-tcp-udp-ports-firewall.md)), `curl`/`openssl` ([bài 06](06-http-https-tls.md)). Ở đây bạn **ghép** chúng thành quy trình.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Người thiếu kinh nghiệm | Người có quy trình |
|---|---|---|
| "Service A không gọi được service B" | Restart cả hai, hy vọng | Kiểm tra lần lượt: B phân giải ra IP gì? Có đường tới không? Port có ai nghe? Trả lời gì? |
| "Ping server không được, chắc nó chết" | Báo động, tạo ticket khẩn | Biết ICMP thường bị chặn (AWS Security Group mặc định chặn), kiểm tra bằng `nc -zv` tới port dịch vụ |
| "Thỉnh thoảng request bị reset" | Đổ cho mạng | Bắt gói tin, thấy `RST` từ phía nào, xác định ai đóng kết nối |
| Phỏng vấn: "Gõ URL vào trình duyệt..." | Trả lời chung chung | Đi từng tầng, nêu lệnh kiểm chứng ở mỗi bước |

Debug mạng hiệu quả không phải là nhớ nhiều lệnh, mà là **loại trừ từng khả năng theo thứ tự**, mỗi bước có một lệnh trả lời "có" hoặc "không".

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Debug theo tầng: đi từ dưới lên hay trên xuống?

Một request web cần **mọi tầng** đều hoạt động. Nếu một tầng hỏng, mọi tầng phía trên đều hỏng theo. Vì vậy:

- Nếu triệu chứng rõ ở tầng cao (ví dụ trả về 500 kèm thông báo lỗi Java) → bắt đầu **từ trên** (log app).
- Nếu triệu chứng mơ hồ ("không vào được", "treo") → đi **từ dưới lên**: tên → đường → port → TLS → HTTP.

Quy trình ở bài này đi từ dưới lên, vì đó là trường hợp khó nhất.

### 3.2. Ba loại câu trả lời mạng có thể cho bạn

Nhớ lại [bài 05](05-tcp-udp-ports-firewall.md) — gần như mọi lỗi kết nối rơi vào một trong ba nhóm, mỗi nhóm chỉ thẳng tới một loại nguyên nhân:

| Triệu chứng | Ý nghĩa | Hướng điều tra |
|---|---|---|
| **Trả lời ngay "không"** (`Connection refused`, gói `RST`) | Đến được máy, không ai nghe port đó | Process có chạy không? Nghe đúng địa chỉ/port không? |
| **Im lặng rồi hết giờ** (`timed out`) | Gói tin bị nuốt hoặc không có đường về | Firewall/Security Group DROP, sai IP, thiếu route |
| **Báo không có đường** (`No route to host`, `Network unreachable`) | Hệ thống biết không đi được | Bảng route, gateway, interface tắt; hoặc firewall trả REJECT kiểu ICMP |

### 3.3. ICMP là gì?

**ICMP** (Internet Control Message Protocol — giao thức thông điệp điều khiển) là giao thức ở tầng Internet (tầng 3) dùng để **báo tình trạng mạng**, không chở dữ liệu ứng dụng. `ping` gửi ICMP *Echo Request* và chờ *Echo Reply*; `traceroute` dựa vào ICMP *Time Exceeded*. ICMP **không có port** — vì vậy ping được một máy không chứng minh port 443 của nó đang mở, và ngược lại.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Cây quyết định debug kết nối

Khi "client không kết nối được tới `service:port`", đi lần lượt từng câu hỏi. Mỗi câu chỉ chuyển sang câu sau khi câu trước trả lời **"có"**.

```text
 ① Tên có phân giải ra đúng IP không?
    dig +short service / getent hosts service              (bài 03)
    ├─ Không / sai IP → DNS: record, /etc/hosts, resolv.conf, TTL/cache
    ▼ Có
 ② Có đường tới IP đó không?
    ip route get <IP>, traceroute -n <IP>                   (bài 04)
    ├─ Không → route, gateway, NAT, VPC route table
    ▼ Có
 ③ Port có mở và có process nghe không?
    Phía client: nc -zv <IP> <port>                         (bài 05)
    Phía server: ss -tlnp | grep <port>                     (bài 05)
    ├─ refused → process chết / nghe 127.0.0.1 / sai port
    ├─ timeout → firewall, Security Group, NACL DROP
    ▼ Kết nối được
 ④ (Nếu HTTPS) TLS có bắt tay thành công không?
    openssl s_client -connect <host>:443 -servername <host> (bài 06)
    ├─ Lỗi → cert hết hạn, sai tên, thiếu chain, sai SNI
    ▼ OK
 ⑤ HTTP trả lời gì?
    curl -v https://<host>/path                             (bài 06)
    ├─ 4xx → request sai: đường dẫn, Host, xác thực
    ├─ 502/504 → proxy ↔ upstream (bài 07)
    ├─ 5xx khác → lỗi app
    ▼ 2xx nhưng sai nội dung / chậm
 ⑥ Log ứng dụng nói gì?
    journalctl -u app, docker logs, /var/log/...             (Linux bài 07)
```

Hai nguyên tắc đi kèm:

- **Kiểm tra từ đúng chỗ.** Lỗi "app không kết nối DB" phải được kiểm tra **từ máy/container chạy app**, không phải từ laptop của bạn. DNS, route, firewall đều phụ thuộc vào vị trí đứng.
- **Kiểm tra cả hai phía.** `nc` từ client cho biết "kết nối được không"; `ss` ở server cho biết "có ai nghe không". Kết hợp hai cái mới khoanh vùng được firewall.

### 4.2. 🟥 `ping`: dùng đúng cách

`ping` trả lời đúng **một** câu hỏi: "ICMP Echo có đi tới và quay về được không?" Nó hữu ích để:

- Kiểm tra nhanh có kết nối Internet không (`ping -c 3 1.1.1.1`).
- Đo **độ trễ** (latency) và **mất gói** (packet loss).
- Phân biệt lỗi DNS và lỗi kết nối: `ping 1.1.1.1` được nhưng `ping example.com` báo `Temporary failure in name resolution` → lỗi DNS, không phải mất mạng.

**"Ping không được" không có nghĩa là máy chết**, vì:

- Firewall nhiều nơi **chặn ICMP**. Trên AWS, Security Group mặc định **không cho ICMP vào** — EC2 đang chạy tốt vẫn không ping được (Module 06).
- Nhiều website lớn bỏ qua ICMP.
- Ngược lại, ping được nhưng web vẫn sập là chuyện bình thường (app chết, port đóng).

→ Để kiểm tra dịch vụ, luôn kiểm tra **đúng port của dịch vụ** bằng `nc -zv` hoặc `curl`.

### 4.3. 🟨 `mtr`: ping + traceroute liên tục

`mtr` kết hợp `traceroute` và `ping`: liên tục gửi gói tới từng chặng (hop) và thống kê mất gói, độ trễ của mỗi chặng. Hữu ích khi mạng **chập chờn**, vì `traceroute` chỉ chụp một khoảnh khắc. Lưu ý khi đọc: một chặng giữa đường báo mất gói nhưng các chặng sau **không** mất → chặng đó chỉ ưu tiên thấp việc trả lời ICMP, không phải đang rớt gói thật.

### 4.4. 🟥 `tcpdump`: nhìn tận mắt gói tin

Mọi công cụ khác **suy luận** về mạng; `tcpdump` cho bạn **thấy** gói tin thật. Dùng khi:

- Muốn biết request có thực sự **ra khỏi** máy không, hay có **về tới** máy không.
- Muốn biết **ai** gửi `RST` đóng kết nối.
- Muốn xem DNS query thật sự gửi đi đâu, nhận gì.
- App nói "đã gửi" còn bên kia nói "không nhận được".

Cách đọc một dòng TCP (tcpdump 4.99 trên Ubuntu 24.04):

```text
20:15:01.123456 lo    In  IP 127.0.0.1.45678 > 127.0.0.1.8080: Flags [S], seq 1234567890, win 65495, length 0
│               │     │      │                  │               │            │                          │
│               │     │      │                  │               │            │                          └ số byte dữ liệu
│               │     │      │                  │               │            └ số thứ tự (sequence)
│               │     │      │                  │               └ cờ TCP
│               │     │      │                  └ đích: IP.port
│               │     │      └ nguồn: IP.port
│               │     └ chiều (khi dùng -i any)
│               └ interface (khi dùng -i any)
└ thời điểm
```

Ký hiệu cờ TCP (theo man page `tcpdump`):

| Ký hiệu | Cờ | Ý nghĩa |
|---|---|---|
| `[S]` | SYN | Xin mở kết nối (bước 1 handshake) |
| `[S.]` | SYN + ACK | Đồng ý mở (bước 2) |
| `[.]` | ACK | Xác nhận (bước 3, và mọi gói xác nhận sau đó) |
| `[P.]` | PUSH + ACK | Gói chứa dữ liệu, đẩy ngay lên ứng dụng |
| `[F.]` | FIN + ACK | Xin đóng kết nối một cách lịch sự |
| `[R]` / `[R.]` | RST | Đóng **đột ngột** — hoặc "không có ai nghe port này" |

Ba mẫu hình bạn phải nhận ra ngay:

| Mẫu hình | Nghĩa |
|---|---|
| `[S]` → `[S.]` → `[.]` → `[P.]`... → `[F.]` | Kết nối bình thường |
| `[S]` → `[R.]` | Port đóng → client báo `Connection refused` |
| `[S]` → (im lặng) → `[S]` → (im lặng) → `[S]`... | Gói bị nuốt → client báo `timed out`. Gửi lại SYN là cơ chế tự thử lại của TCP |

> ⚠️ `tcpdump` cần quyền root và có thể thấy dữ liệu nhạy cảm (mật khẩu trong HTTP không mã hóa, token). Chỉ bắt trên máy bạn được phép, giới hạn bằng bộ lọc và `-c`, không để file `.pcap` bừa bãi.

### 4.5. 🟥 Bộ lọc của `tcpdump`

Bộ lọc viết ở cuối lệnh, ghép bằng `and`, `or`, `not`:

| Bộ lọc | Bắt |
|---|---|
| `port 8080` | Gói có port nguồn **hoặc** đích là 8080 |
| `host 10.0.1.25` | Gói tới hoặc từ IP đó |
| `src host 10.0.1.25` / `dst port 443` | Chỉ một chiều |
| `tcp` / `udp` / `icmp` | Theo giao thức |
| `port 53` | DNS |
| `tcp port 5432 and host 10.0.11.7` | Kết nối PostgreSQL tới một máy cụ thể |
| `'tcp[tcpflags] & tcp-rst != 0'` | 🟨 Chỉ gói có cờ RST |

### 4.6. 🟥 Lệnh cũ và lệnh mới

Nhiều tài liệu, Stack Overflow và server cũ vẫn dùng bộ `net-tools` (`netstat`, `ifconfig`, `route`, `arp`). Trên Ubuntu hiện đại chúng **không cài sẵn**; bộ thay thế là `iproute2` (`ip`, `ss`). Bạn cần **đọc hiểu** cả hai:

| Việc | Lệnh cũ (`net-tools`) | Lệnh hiện đại (`iproute2`) |
|---|---|---|
| Port đang nghe + process | `netstat -tulpn` | `ss -tulpn` |
| Mọi kết nối TCP | `netstat -ant` | `ss -ant` |
| Địa chỉ IP các interface | `ifconfig` | `ip addr` (`ip a`) |
| Bảng route | `route -n` / `netstat -rn` | `ip route` |
| Bảng ARP | `arp -n` | `ip neigh` |
| Thống kê interface | `netstat -i` | `ip -s link` |

Ý nghĩa các chữ trong `-tulpn` giống nhau ở cả hai: **t**cp, **u**dp, **l**istening, **p**rocess, **n**umeric (không đổi số thành tên).

### 4.7. 🟨 `wget` và `curl`

| | `curl` | `wget` |
|---|---|---|
| Mục đích chính | Thử nghiệm và gọi API: mọi method, header, chi tiết kết nối | **Tải file** về đĩa, tải đệ quy |
| Mặc định | In nội dung ra màn hình | Lưu thành file |
| Debug | `-v`, `-w` rất mạnh | Ít chi tiết hơn |
| Gặp ở đâu | Mọi nơi | Script cài đặt, image Docker tối giản có sẵn `wget` (BusyBox) nhưng không có `curl` |

Trong image Alpine/BusyBox, healthcheck thường viết `wget -qO- http://localhost:8080/actuator/health` vì không có `curl`. Biết đọc là đủ.

### 4.8. 🟨 `ip -s link`: lỗi ở tầng vật lý/liên kết

`ip -s link` hiện bộ đếm byte, gói, **errors**, **dropped** của mỗi interface. Nếu `errors` hoặc `dropped` **tăng liên tục** → vấn đề ở card mạng, driver, hoặc quá tải hàng đợi. Trên cloud hiếm gặp, nhưng là một ô cần đánh dấu khi loại trừ.

### 4.9. 🟥 Câu phỏng vấn: "Gõ `https://example.com` vào trình duyệt thì chuyện gì xảy ra?"

Câu này kiểm tra bạn có **ghép** được mọi tầng hay không. Trả lời theo từng bước, mỗi bước nêu **lệnh chứng minh** — đây là điểm khiến bạn khác những ứng viên học thuộc.

| # | Điều xảy ra | Tầng | Lệnh chứng minh (`[WSL]`) | Bài |
|---|---|---|---|---|
| 1 | Trình duyệt phân tích URL: scheme `https` → port mặc định 443, host `example.com`, path `/` | Ứng dụng | — | 06 |
| 2 | Hệ điều hành phân giải tên: cache → `/etc/hosts` → DNS resolver trong `/etc/resolv.conf` → resolver đệ quy hỏi root → `.com` → máy chủ authoritative của `example.com` | Ứng dụng (DNS, UDP 53) | `getent hosts example.com` · `dig example.com` · `dig +trace example.com` | 03 |
| 3 | Có IP đích. Kernel tra **bảng route**: IP đích không cùng subnet → gửi qua **default gateway** | Internet | `ip route get <IP>` | 04 |
| 4 | Cần địa chỉ MAC của gateway → **ARP** trong mạng LAN | Liên kết | `ip neigh` | 04 |
| 5 | Gói đi qua router nhà/công ty, được **NAT** đổi IP nguồn private thành IP public, đi qua nhiều router tới server | Internet | `traceroute -n <IP>` · `curl -s ifconfig.me` 🟨 | 04 |
| 6 | **TCP handshake** tới IP:443: SYN → SYN-ACK → ACK | Giao vận | `nc -zv example.com 443` · `tcpdump` thấy `[S] [S.] [.]` | 05 |
| 7 | **TLS handshake**: client gửi SNI `example.com`, server gửi chứng chỉ, client kiểm tra chain + tên + hạn, hai bên thỏa thuận khóa phiên | Trình diễn/Ứng dụng | `openssl s_client -connect example.com:443 -servername example.com` | 06 |
| 8 | Gửi **HTTP request** đã mã hóa: `GET / HTTP/1.1` (hoặc HTTP/2) + `Host: example.com` + header | Ứng dụng | `curl -v https://example.com/` | 06 |
| 9 | Phía server: thường qua **load balancer** → **reverse proxy** → **ứng dụng** → có thể **database/cache** | Ứng dụng | (phía server) `access.log`, log app | 07 |
| 10 | Server trả **HTTP response**: status, header, body. Trình duyệt parse HTML, tải thêm CSS/JS/ảnh (lặp lại bước 2–8 cho các domain khác), hiển thị | Ứng dụng | `curl -sI https://example.com/` | 06 |
| 11 | Kết nối được giữ lại để tái sử dụng (keep-alive) hoặc đóng bằng FIN | Giao vận | `tcpdump` thấy `[F.]` | 05 |

Cách trình bày khi phỏng vấn: nói bản tóm tắt 30 giây (DNS → TCP → TLS → HTTP → server trả về → render), rồi **hỏi người phỏng vấn muốn đi sâu tầng nào**. Mỗi tầng bạn đều có lệnh để chứng minh.

### 4.10. Gặp lại ở đâu

| Ở đây | Gặp lại |
|---|---|
| Cây quyết định 6 bước | Debug Docker Compose (Module 04): "container app không gọi được `postgres`" — đi đúng 6 bước, **từ bên trong container** (`docker exec`) |
| `ping` bị chặn | Security Group không mở ICMP (Module 06) — EC2 sống nhưng không ping được |
| `nc -zv` / timeout vs refused | Kiểm tra Security Group, NACL, RDS endpoint (Module 06) |
| `tcpdump` | Debug trong container/Pod bằng image công cụ mạng; VPC Flow Logs trên AWS là "tcpdump ở mức metadata" (Module 06, 08) |
| Câu "gõ URL" | Phần phỏng vấn ([13-INTERVIEW-PREPARATION](../00-ROADMAP/curriculum-structure.md#3-danh-sách-bài-học-theo-module)) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Spring Boot không kết nối được PostgreSQL"

Log app: `Connection to db.internal:5432 refused`. Áp dụng cây quyết định **từ máy chạy app**:

1. `getent hosts db.internal` → `10.0.11.7` ✅ (đúng IP database)
2. `ip route get 10.0.11.7` → đi qua `eth0` ✅
3. `nc -zv 10.0.11.7 5432` → `Connection refused` ❌ → đến được máy nhưng không ai nghe 5432.
4. Lên máy DB: `sudo ss -tlnp | grep 5432` → `127.0.0.1:5432` — PostgreSQL chỉ nghe loopback.

Nguyên nhân gốc: `listen_addresses = 'localhost'` trong cấu hình PostgreSQL. Không cần restart app lần nào.

Nếu bước 3 là **timeout** thay vì refused → hướng điều tra đổi hẳn sang firewall/Security Group.

### Ví dụ 2: "Ping được nhưng web không vào"

`ping -c 3 10.0.1.25` thành công, `curl http://10.0.1.25/` treo rồi timeout. Kết luận đúng: máy sống, ICMP được phép, nhưng port 80 bị firewall nuốt. Kết luận **sai** thường gặp: "mạng ổn, chắc app lỗi" — nếu app lỗi mà port vẫn mở, bạn sẽ nhận `refused` hoặc mã HTTP 5xx, không phải timeout.

### Ví dụ 3: Ai đóng kết nối?

Client thỉnh thoảng nhận `Connection reset by peer`. Bắt gói ở phía client:

```bash
sudo tcpdump -i any -n 'host 10.0.1.25 and tcp[tcpflags] & tcp-rst != 0'
```

Thấy `IP 10.0.1.25.80 > 10.0.2.9.51322: Flags [R.]` → RST đến **từ server** → điều tra phía server (proxy timeout, app crash giữa chừng, giới hạn kết nối). Nếu RST xuất hiện từ một IP ở giữa (load balancer) → điều tra idle timeout của load balancer.

---

## 6. Sơ đồ kiến trúc

### 6.1. Mỗi công cụ "nhìn" ở tầng nào

```text
 Tầng TCP/IP           Câu hỏi                          Công cụ
┌──────────────────┬─────────────────────────────────┬──────────────────────────────┐
│ Ứng dụng         │ HTTP trả gì? TLS ổn? Tên ra IP? │ curl, wget, openssl, dig     │
├──────────────────┼─────────────────────────────────┼──────────────────────────────┤
│ Giao vận         │ Port mở? Ai nghe? Kết nối nào?  │ nc, ss, (netstat)            │
├──────────────────┼─────────────────────────────────┼──────────────────────────────┤
│ Internet         │ Có đường? Trễ? Mất gói?         │ ping, traceroute, mtr,       │
│                  │                                 │ ip route                     │
├──────────────────┼─────────────────────────────────┼──────────────────────────────┤
│ Liên kết         │ Interface lên? Lỗi? MAC?        │ ip link, ip -s link, ip neigh│
└──────────────────┴─────────────────────────────────┴──────────────────────────────┘
        tcpdump nhìn xuyên mọi tầng — thấy gói tin thật
```

### 6.2. Ba kịch bản TCP qua mắt `tcpdump`

```text
 BÌNH THƯỜNG              PORT ĐÓNG                 BỊ FIREWALL NUỐT
 client     server        client     server         client     server
   │──[S]───►│              │──[S]───►│               │──[S]───►✖
   │◄─[S.]───│              │◄─[R.]───│               │  (1s)
   │──[.]───►│              │                         │──[S]───►✖
   │──[P.]──►│ GET /        "Connection refused"      │  (2s)
   │◄─[P.]───│ 200 OK       ngay lập tức              │──[S]───►✖
   │──[F.]──►│                                        │   ...
   │◄─[F.]───│                                        "Connection timed out"
   │──[.]───►│                                        sau nhiều giây
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ping -c N` | Kiểm tra ICMP, độ trễ, mất gói | 🟥 |
| `tcpdump` | Bắt và đọc gói tin | 🟥 |
| `netstat` (đọc hiểu) | Lệnh cũ — gặp trong tài liệu và server cũ | 🟥 |
| `mtr` | Theo dõi đường đi liên tục | 🟨 |
| `wget` | Tải file; healthcheck trong image tối giản | 🟨 |
| `ip -s link` | Bộ đếm lỗi interface | 🟨 |
| Wireshark (Windows) | Xem file `.pcap` bằng giao diện đồ họa | 🟦 |
| `dig`, `ip route get`, `traceroute`, `nc`, `ss`, `openssl s_client`, `curl -v` | Đã học — dùng trong cây quyết định | 🟥 |

Cài các công cụ còn thiếu (bạn tự quyết định — đây là cài phần mềm vào WSL):

```bash
sudo apt install -y iputils-ping tcpdump mtr-tiny net-tools
```

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra dưới đây là **minh họa** trên Ubuntu 24.04 WSL. IP, thời gian, độ trễ trên máy bạn sẽ khác. Trên WSL, gói tin đi qua lớp NAT của Windows nên một số con số (TTL, số chặng) khác với máy thật.

### `ping`

```bash
ping -c 4 1.1.1.1
```

```text
PING 1.1.1.1 (1.1.1.1) 56(84) bytes of data.
64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms
64 bytes from 1.1.1.1: icmp_seq=2 ttl=57 time=11.8 ms
64 bytes from 1.1.1.1: icmp_seq=3 ttl=57 time=13.1 ms
64 bytes from 1.1.1.1: icmp_seq=4 ttl=57 time=12.4 ms

--- 1.1.1.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3005ms
rtt min/avg/max/mdev = 11.8/12.4/13.1/0.5 ms
```

| Thành phần | Ý nghĩa |
|---|---|
| `-c 4` | Gửi 4 gói rồi dừng. **Không có `-c`, ping trên Linux chạy mãi** (Ctrl+C để dừng) — trong script luôn dùng `-c` |
| `-i 0.5` | Khoảng cách giữa các gói (giây). Mặc định 1 |
| `-W 2` | Chờ mỗi phản hồi tối đa 2 giây |
| `icmp_seq` | Số thứ tự — thứ tự bị nhảy cóc = có gói mất |
| `ttl=57` | Time To Live còn lại khi gói về. Mỗi router trừ 1. Gói xuất phát thường với TTL 64 (Linux) hoặc 128 (Windows) → `57` gợi ý khoảng 7 chặng |
| `time=12.3 ms` | Thời gian khứ hồi (round-trip time, RTT) |
| `0% packet loss` | Tỉ lệ mất gói — **chỉ số quan trọng nhất** khi mạng chập chờn |
| `mdev` | Độ dao động độ trễ (jitter) |

Các thông báo lỗi cần phân biệt:

```text
ping: example.invalid: Temporary failure in name resolution   ← lỗi DNS, chưa gửi gói nào
From 10.0.0.1 icmp_seq=1 Destination Host Unreachable         ← router/máy báo không tới được
(không in gì, cuối cùng: 100% packet loss)                     ← gói đi mà không có trả lời: bị chặn hoặc máy không tồn tại
```

### `tcpdump`

```bash
sudo tcpdump -i lo -n -c 10 port 8080
```

| Tham số | Ý nghĩa |
|---|---|
| `-i lo` / `-i eth0` / `-i any` | Interface để bắt. `lo` = loopback (`127.0.0.1`); `any` = mọi interface, kèm tên interface và chiều `In`/`Out` |
| `-n` | Không đổi IP thành tên miền và port thành tên dịch vụ. Trên tcpdump 4.99 (Ubuntu 24.04), `-n` đã áp dụng cho cả port. Nhiều tài liệu viết `-nn` — thói quen từ bản cũ, dùng vẫn đúng |
| `-c 10` | Dừng sau 10 gói — tránh bắt vô hạn |
| `-A` | In nội dung gói dạng ASCII — đọc được HTTP không mã hóa |
| `-w file.pcap` | Ghi gói thô ra file (không in ra màn hình) |
| `-r file.pcap` | Đọc lại từ file đã ghi |
| `-v` | Chi tiết hơn (TTL, độ dài IP...) |
| `port 8080` | Bộ lọc (mục 4.5) |

Một kết nối HTTP hoàn chỉnh tới server python cục bộ (minh họa, đã rút gọn phần `options`):

```text
20:15:01.123456 IP 127.0.0.1.45678 > 127.0.0.1.8080: Flags [S], seq 1234567890, win 65495, length 0
20:15:01.123470 IP 127.0.0.1.8080 > 127.0.0.1.45678: Flags [S.], seq 987654321, ack 1234567891, win 65483, length 0
20:15:01.123480 IP 127.0.0.1.45678 > 127.0.0.1.8080: Flags [.], ack 1, win 512, length 0
20:15:01.123520 IP 127.0.0.1.45678 > 127.0.0.1.8080: Flags [P.], seq 1:78, ack 1, win 512, length 77: HTTP: GET / HTTP/1.1
20:15:01.123530 IP 127.0.0.1.8080 > 127.0.0.1.45678: Flags [.], ack 78, win 512, length 0
20:15:01.124100 IP 127.0.0.1.8080 > 127.0.0.1.45678: Flags [P.], seq 1:156, ack 78, win 512, length 155: HTTP: HTTP/1.0 200 OK
20:15:01.124300 IP 127.0.0.1.8080 > 127.0.0.1.45678: Flags [FP.], seq 156:400, ack 78, win 512, length 244: HTTP
20:15:01.124350 IP 127.0.0.1.45678 > 127.0.0.1.8080: Flags [.], ack 401, win 510, length 0
20:15:01.124400 IP 127.0.0.1.45678 > 127.0.0.1.8080: Flags [F.], seq 78, ack 401, win 512, length 0
20:15:01.124410 IP 127.0.0.1.8080 > 127.0.0.1.45678: Flags [.], ack 79, win 512, length 0
```

Đọc: 3 dòng đầu là **handshake**; dòng 4 client gửi request 77 byte; dòng 6–7 server gửi response và **chủ động đóng** (`F` — server HTTP/1.0 của python đóng kết nối sau mỗi response); dòng 9 client đóng chiều của mình. Port `45678` của client là **port tạm** (ephemeral port) do kernel chọn ngẫu nhiên.

> Sau khi bắt tay, tcpdump hiển thị `seq`/`ack` dạng **tương đối** (bắt đầu từ 1) cho dễ đọc. Thêm `-S` để xem số tuyệt đối.

Kết nối tới port **không ai nghe**:

```text
20:16:10.000100 IP 127.0.0.1.50122 > 127.0.0.1.9999: Flags [S], seq 55501, win 65495, length 0
20:16:10.000110 IP 127.0.0.1.9999 > 127.0.0.1.50122: Flags [R.], seq 0, ack 55502, win 0, length 0
```

Một truy vấn DNS (bắt bằng `-i any port 53`):

```text
20:17:30.100000 eth0  Out IP 172.24.80.5.51234 > 10.255.255.254.53: 12345+ [1au] A? example.com. (52)
20:17:30.118000 eth0  In  IP 10.255.255.254.53 > 172.24.80.5.51234: 12345 1/0/1 A 93.184.215.14 (56)
```

| Phần | Ý nghĩa |
|---|---|
| `.53` | Port 53 = DNS, chạy trên **UDP** (không có `Flags [...]` vì UDP không có cờ) |
| `12345+` | ID truy vấn; `+` = yêu cầu đệ quy |
| `A? example.com.` | Hỏi record A của `example.com` |
| `1/0/1` | Câu trả lời có 1 record answer / 0 authority / 1 additional |
| `A 93.184.215.14` | Kết quả (IP minh họa — IP thật của example.com có thể khác) |

> Địa chỉ DNS server trên WSL tùy cấu hình (ví dụ `10.255.255.254` khi WSL bật DNS tunneling, hoặc IP của Windows trong mạng NAT). Xem `cat /etc/resolv.conf` ([bài 03](03-dns-dhcp.md)).

Ghi ra file để mở bằng Wireshark trên Windows 🟦:

```bash
sudo tcpdump -i any -n -c 200 -w ~/devops-lab/02-networking/capture.pcap port 8080
cp ~/devops-lab/02-networking/capture.pcap /mnt/c/Users/<tên-user-Windows>/Desktop/   # đưa sang Windows
tcpdump -n -r ~/devops-lab/02-networking/capture.pcap | head                          # đọc lại không cần sudo
```

### `netstat` (để đọc hiểu)

```bash
netstat -tulpn          # cần gói net-tools; sudo để thấy cột PID/Program của mọi process
```

```text
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      2710/nginx: master
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN      3120/python3
```

Thông tin giống `ss -tulpn` ([bài 05](05-tcp-udp-ports-firewall.md)), chỉ khác cách trình bày. Khi gặp hướng dẫn dùng `netstat`, chuyển sang `ss` theo bảng mục 4.6.

### 🟨 `mtr`

```bash
mtr -rwnc 10 1.1.1.1
```

| Tham số | Ý nghĩa |
|---|---|
| `-r` | Chế độ báo cáo: chạy xong in bảng rồi thoát (thay vì giao diện tương tác) |
| `-w` | Báo cáo dạng rộng, không cắt tên |
| `-n` | Không phân giải tên |
| `-c 10` | Gửi 10 gói tới mỗi chặng |

```text
HOST: LEGION                 Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 172.24.80.1           0.0%    10    0.4   0.5   0.3   0.9   0.2
  2.|-- 192.168.1.1           0.0%    10    2.1   2.4   1.9   3.5   0.5
  3.|-- ???                  100.0    10    0.0   0.0   0.0   0.0   0.0
  4.|-- 100.64.12.1           0.0%    10    8.0   8.6   7.7  11.2   1.0
  ...
  9.|-- 1.1.1.1               0.0%    10   12.1  12.4  11.8  13.3   0.4
```

Chặng 1 là cổng NAT của Windows cho WSL, chặng 2 là router nhà. Chặng 3 `???` 100% nhưng các chặng sau 0% → chặng đó chỉ không trả lời ICMP, **không phải** đang rớt gói.

### 🟨 `wget`

```bash
wget -qO- http://127.0.0.1:8080/         # -q: im lặng; -O-: ghi nội dung ra stdout thay vì file
wget https://example.com/file.tar.gz     # tải file về thư mục hiện tại
```

### 🟨 `ip -s link`

```bash
ip -s link show eth0
```

```text
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 00:15:5d:a1:b2:c3 brd ff:ff:ff:ff:ff:ff
    RX:  bytes packets errors dropped  missed   mcast
     98234112   81234      0       0       0       0
    TX:  bytes packets errors dropped carrier collsns
      7123456   41234      0       0       0       0
```

Chạy hai lần cách nhau vài giây; nếu `errors`/`dropped` tăng → có vấn đề ở tầng liên kết. `UP,LOWER_UP` = interface bật và có kết nối vật lý/ảo.

---

## 9. Bài thực hành từng bước

**Lab: Nhìn tận mắt TCP và DNS bằng `tcpdump`** · `[WSL]` · ~60 phút

Mục tiêu: tự bắt và chú thích một kết nối HTTP hoàn chỉnh, một kết nối bị từ chối, và một truy vấn DNS. Ghi kết quả vào `~/devops-lab/02-networking/lab08.md`, sau đó commit vào `~/devops-journey/week05/`.

Cần 3 terminal: **T1** server, **T2** tcpdump, **T3** client.

### Bước 1 — Chuẩn bị

```bash
# T3
mkdir -p ~/devops-lab/02-networking/lab08 && cd ~/devops-lab/02-networking/lab08
which tcpdump ping || sudo apt install -y tcpdump iputils-ping   # bạn tự quyết định cài
echo "hello from lab08" > index.html
```

```bash
# T1
cd ~/devops-lab/02-networking/lab08
python3 -m http.server 8080 --bind 127.0.0.1
```

### Bước 2 — Bắt một kết nối HTTP bình thường

```bash
# T2
sudo tcpdump -i lo -n port 8080
```

```bash
# T3
curl -s http://127.0.0.1:8080/
```

Dừng T2 bằng Ctrl+C. Copy toàn bộ output vào `lab08.md`.

❓ Đánh dấu trong output: 3 gói của handshake, gói chứa request (độ dài bao nhiêu byte?), gói chứa response, các gói `F`. **Bên nào đóng kết nối trước?** Port của client là bao nhiêu, có giống lần chạy sau không?

### Bước 3 — Xem nội dung HTTP

```bash
# T2
sudo tcpdump -i lo -n -A -c 12 port 8080
```

```bash
# T3
curl -s -H "X-Lab: tcpdump-08" http://127.0.0.1:8080/
```

❓ Tìm thấy dòng `GET / HTTP/1.1`, header `Host`, `User-Agent`, `X-Lab` trong output không? Điều này nói gì về độ an toàn của **HTTP không mã hóa** trên mạng công cộng? (Liên hệ [bài 06](06-http-https-tls.md).)

### Bước 4 — Bắt kết nối bị từ chối

```bash
# T2
sudo tcpdump -i lo -n port 9999
```

```bash
# T3
curl -v http://127.0.0.1:9999/
echo "exit code: $?"
```

❓ Có bao nhiêu gói? Cờ là gì? `curl` báo lỗi gì, exit code bao nhiêu? Ghép với bảng "ba mẫu hình" ở mục 4.4.

### Bước 5 — Bắt truy vấn DNS

```bash
# T3
cat /etc/resolv.conf | grep nameserver
```

```bash
# T2
sudo tcpdump -i any -n port 53
```

```bash
# T3
dig example.com +short
dig example.com +short          # chạy lại ngay
```

❓ Truy vấn được gửi tới IP nào? Có khớp `nameserver` trong `resolv.conf` không? Giao thức là TCP hay UDP? Lần `dig` thứ hai có sinh gói DNS không? (Gợi ý: `dig` luôn hỏi trực tiếp DNS server, không dùng cache của hệ điều hành — thử thay bằng `getent hosts example.com` và so sánh.)

### Bước 6 — Ping và mất gói

```bash
# T3
ping -c 5 1.1.1.1
ping -c 3 -W 1 10.255.255.1      # một IP private gần như chắc chắn không tồn tại trong mạng của bạn
```

❓ Ghi lại RTT trung bình và % mất gói của lệnh 1. Lệnh 2 báo gì? Theo mục 4.2, bạn có thể kết luận "máy 10.255.255.1 chết" không?

### Bước 7 — Ghi file pcap

```bash
# T2
sudo tcpdump -i lo -n -c 20 -w ~/devops-lab/02-networking/lab08/http.pcap port 8080
```

```bash
# T3
curl -s http://127.0.0.1:8080/ > /dev/null
tcpdump -n -r ~/devops-lab/02-networking/lab08/http.pcap
```

🟦 Tùy chọn: copy file sang Windows và mở bằng Wireshark, chọn một gói rồi xem *Follow → TCP Stream*.

### Bước 8 — Lưu kết quả và dọn dẹp

```bash
# T1: Ctrl+C dừng server
mkdir -p ~/devops-journey/week05
cp ~/devops-lab/02-networking/lab08/lab08.md ~/devops-journey/week05/
cd ~/devops-journey && git add week05/lab08.md && git commit -m "docs(network): lab 08 - tcpdump handshake, RST, DNS" && git push
rm -f ~/devops-lab/02-networking/lab08/http.pcap      # file pcap có thể chứa dữ liệu nhạy cảm — không commit
```

---

## 10. Kết quả mong đợi

- **Bước 2:** Khoảng 10 gói như mẫu ở mục 8. Request khoảng 77–90 byte (tùy độ dài `User-Agent` của curl). Server python (HTTP/1.0) gửi `F` **trước** — server chủ động đóng. Port client là một số lớn (dải port tạm, thường 32768–60999 trên Linux), đổi sau mỗi lần chạy.
- **Bước 3:** Thấy rõ `GET / HTTP/1.1`, `Host: 127.0.0.1:8080`, `User-Agent: curl/...`, `X-Lab: tcpdump-08` dạng chữ thường → **mọi ai bắt được gói đều đọc được HTTP**. Đó là lý do bắt buộc HTTPS.
- **Bước 4:** Đúng **2 gói**: `[S]` từ client và `[R.]` từ phía 9999. `curl: (7) Failed to connect to 127.0.0.1 port 9999 ... Connection refused`, exit code `7`.
- **Bước 5:** Gói UDP tới IP `nameserver` trong `/etc/resolv.conf`, port 53. Cả hai lần `dig` đều sinh gói vì `dig` hỏi thẳng DNS server. `getent hosts` đi qua cơ chế phân giải của hệ thống (có thể có cache tùy cấu hình).
- **Bước 6:** Lệnh 1 có 0% (hoặc rất thấp) packet loss, RTT vài chục ms. Lệnh 2: `100% packet loss` (có thể kèm `Destination Host Unreachable`). **Không** kết luận được máy chết — có thể IP không tồn tại, có thể bị chặn ICMP; muốn biết dịch vụ có chạy phải kiểm tra port của dịch vụ.
- **Bước 7:** `tcpdump -r` in lại đúng các gói đã bắt, không cần `sudo` vì chỉ đọc file của bạn.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `tcpdump: eth0: You don't have permission to capture on that device` | Thiếu quyền root | Chạy với `sudo` |
| tcpdump không bắt được gì khi test `127.0.0.1` | Bắt nhầm interface (`eth0` thay vì `lo`) | Traffic tới `127.0.0.1` đi qua `lo`. Không chắc → `-i any` |
| tcpdump in tên thay vì IP, chạy chậm | Thiếu `-n` → tcpdump tra DNS ngược cho mọi IP (và tự sinh thêm traffic DNS) | Luôn dùng `-n` |
| Ping không bao giờ dừng | Linux ping chạy mãi khi không có `-c` | Ctrl+C; trong script luôn có `-c` |
| `ping: socket: Operation not permitted` trong container | Image thiếu quyền gửi ICMP thô hoặc thiếu gói | Cài `iputils-ping`; một số runtime cần thêm capability `NET_RAW` |
| `netstat: command not found` | Ubuntu mới không cài `net-tools` | Dùng `ss` — hoặc cài `net-tools` nếu thật cần |
| Kết luận "máy chết" vì không ping được | ICMP bị chặn | Kiểm tra port dịch vụ bằng `nc -zv` / `curl` |
| Debug từ laptop trong khi lỗi xảy ra trong container | Sai vị trí đứng — DNS/route/firewall khác nhau | Chạy lệnh **từ nơi gặp lỗi** (`docker exec`, SSH vào máy) |
| File `.pcap` lớn đầy ổ đĩa | Bắt không giới hạn | Dùng `-c`, bộ lọc chặt, hoặc `-C`/`-W` 🟦 để xoay vòng file |

---

## 12. Đọc log và xử lý lỗi

Bài này **chính là** phần "xử lý lỗi" của cả module. Tóm tắt thành **runbook** (sổ tay vận hành) bạn có thể dán vào repo:

```markdown
# Runbook: "Không kết nối được tới <service>:<port>"

Chạy TỪ máy/container đang gặp lỗi.

1. Tên → IP:        getent hosts <service>      | dig +short <service>
2. Đường đi:         ip route get <IP>           | traceroute -n <IP>
3. Port (client):    nc -zv -w 3 <IP> <port>
      refused  → bước 3b
      timeout  → firewall / Security Group / NACL / route chiều về
3b. Port (server):   sudo ss -tlnp | grep <port>
      không có → process chết: systemctl status / docker ps / journalctl
      127.0.0.1 → đổi bind address sang 0.0.0.0 hoặc IP nội bộ
4. TLS:              openssl s_client -connect <host>:443 -servername <host> </dev/null
5. HTTP:             curl -sv https://<host>/<path> -o /dev/null
6. Log:              log reverse proxy (error.log) → log app
7. Vẫn chưa rõ:      sudo tcpdump -i any -n host <IP> and port <port>
                     → gói có ra không? có về không? ai gửi RST?
Ghi lại: troubleshooting-journal.md
```

Khi đọc thông báo lỗi của công cụ, map ngay về tầng:

| Thông báo | Tầng | Bước trong runbook |
|---|---|---|
| `Could not resolve host`, `Name or service not known`, `NXDOMAIN` | DNS | 1 |
| `Network is unreachable`, `No route to host` | Route / firewall REJECT | 2 |
| `Connection refused` | Port không ai nghe | 3b |
| `Connection timed out`, `Operation timed out` | Gói bị nuốt | 3 → firewall |
| `SSL certificate problem`, `certificate has expired`, `hostname mismatch` | TLS | 4 |
| `HTTP 4xx/5xx` | HTTP / app | 5, 6 |
| `Connection reset by peer` | Ai đó gửi RST giữa chừng | 7 |

---

## 13. Câu hỏi kiểm tra kiến thức

1. Kể 6 bước của cây quyết định debug kết nối theo thứ tự, mỗi bước một lệnh.
2. Vì sao "ping không được" chưa chắc là máy chết? Vì sao "ping được" chưa chắc là web chạy?
3. `ping example.com` báo `Temporary failure in name resolution` — lỗi ở tầng nào? Bạn kiểm tra gì tiếp?
4. Trong output `ping`, `ttl=57` cho bạn biết điều gì?
5. Viết lại dãy cờ TCP `tcpdump` hiển thị cho: (a) kết nối bình thường; (b) port đóng; (c) bị firewall DROP.
6. Vì sao nên luôn dùng `-n` và `-c` với `tcpdump`?
7. Muốn bắt traffic tới `127.0.0.1:8080`, dùng interface nào? Vì sao?
8. Chuyển các lệnh sau sang bộ `iproute2`: `netstat -tulpn`, `ifconfig`, `route -n`, `arp -n`.
9. Vì sao debug lỗi "app không kết nối được DB" phải chạy lệnh từ máy chạy app?
10. `Connection refused` và `Connection timed out` dẫn bạn tới hai hướng điều tra khác nhau thế nào?
11. Trình bày tóm tắt 30 giây câu "gõ `https://example.com` vào trình duyệt", rồi nêu lệnh chứng minh cho bước DNS, TCP và TLS.
12. Trong `mtr`, một chặng giữa báo 100% loss nhưng chặng cuối 0% loss — kết luận gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/08-solutions.md](solutions/08-solutions.md) — chỉ mở sau khi tự làm.

**Bài 1 — Đọc tcpdump không cần chạy.** Đoạn sau bắt ở phía client. Hãy cho biết: client và server là IP:port nào? Kết nối có thành công không? Ai đóng? Nếu đây là lời phàn nàn "app báo lỗi khi gọi API", bạn điều tra phía nào?

```text
10:01:00.000 IP 10.0.2.9.40112 > 10.0.1.25.8080: Flags [S], seq 100, win 64240, length 0
10:01:00.001 IP 10.0.1.25.8080 > 10.0.2.9.40112: Flags [S.], seq 500, ack 101, win 65160, length 0
10:01:00.001 IP 10.0.2.9.40112 > 10.0.1.25.8080: Flags [.], ack 1, win 502, length 0
10:01:00.002 IP 10.0.2.9.40112 > 10.0.1.25.8080: Flags [P.], seq 1:120, ack 1, win 502, length 119: HTTP: POST /api/tasks HTTP/1.1
10:01:30.003 IP 10.0.1.25.8080 > 10.0.2.9.40112: Flags [R.], seq 1, ack 120, win 0, length 0
```

**Bài 2 — Chẩn đoán từ triệu chứng.** Với mỗi tình huống, ghi (a) tầng nghi ngờ, (b) 2 lệnh đầu tiên bạn chạy và **từ máy nào**, (c) giả thuyết nguyên nhân:
1. `curl https://api.example.com` → `curl: (6) Could not resolve host`. Đồng nghiệp ở máy khác gọi được.
2. Từ EC2 app, `nc -zv 10.0.11.7 5432` treo 3 giây rồi báo timeout. Trên máy DB, PostgreSQL đang chạy.
3. `curl -I https://shop.example.com` → `SSL certificate problem: certificate has expired`.
4. Ping server được, `curl http://server/` trả `502 Bad Gateway`, header `Server: nginx`.

**Bài 3 — ICMP bị chặn, dịch vụ vẫn sống.** Trong `[Sandbox]` có quyền chỉnh firewall:

```bash
docker run --rm -it --cap-add=NET_ADMIN ubuntu:22.04 bash
# bên trong container:
apt-get update && apt-get install -y iputils-ping iptables python3 curl
python3 -m http.server 8080 &
```

Ping chính container qua IP của nó (`hostname -I`) và curl tới port 8080. Sau đó thêm luật chặn ICMP: `iptables -A INPUT -p icmp -j DROP`. Lặp lại ping và curl. Ghi lại kết quả và viết 3 câu giải thích cho một người chỉ dựa vào ping để kết luận "server chết". (Cú pháp iptables đã học ở [bài 05](05-tcp-udp-ports-firewall.md).)

**Bài 4 — Runbook của riêng bạn.** Viết lại runbook ở mục 12 thành file `docs/runbooks/network-connectivity.md` trong repo `taskhub`, thêm cột "Ví dụ đầu ra khi OK / khi lỗi" cho từng bước, lấy đầu ra **thật** từ các lab bạn đã làm trong module.

**Bài 5 — Câu phỏng vấn có bằng chứng.** Chạy tuần tự các lệnh ở bảng mục 4.9 cho một website thật bạn chọn (không phải example.com). Lưu output của mỗi bước vào `week05/url-journey.md`, kèm 1–2 câu giải thích. Sau đó tự ghi âm hoặc nói to câu trả lời phỏng vấn trong 2 phút mà không nhìn ghi chú.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Viết lại được cây quyết định 6 bước từ trí nhớ, mỗi bước có lệnh và cách đọc kết quả.
- [ ] Nhìn output `tcpdump` là nhận ra ngay: kết nối bình thường, port đóng, hay bị DROP.
- [ ] Không bao giờ kết luận "máy chết" chỉ vì ping không được.
- [ ] Đọc được hướng dẫn cũ dùng `netstat`/`ifconfig` và chuyển sang `ss`/`ip`.
- [ ] Trả lời câu "gõ URL vào trình duyệt" trong 2 phút, có lệnh chứng minh từng tầng.
- [ ] Hoàn thành Bài tập 1 và 2 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [tcpdump(8) — Ubuntu 24.04 manpage](https://manpages.ubuntu.com/manpages/noble/man8/tcpdump.8.html) | Tham số `-i`, `-n`, `-A`, `-c`, `-w`, `-r`; ký hiệu cờ TCP (tcpdump 4.99.4) | 2026-10-31 |
| [Linux Journey — Networking Nomad](https://labex.io/linuxjourney) | Ôn tập các lệnh mạng cơ bản | 2026-10-31 |
| [Cisco Networking Academy — Networking Essentials](https://www.netacad.com/courses/networking/networking-essentials) | Đọc thêm về ICMP, TCP, mô hình phân tầng (chỉ chọn module liên quan) | 2026-10-31 (xác nhận qua tìm kiếm) |
| `man ping`, `man mtr`, `man ss`, `man ip` (chạy trên máy) | Tham số đầy đủ | — |
