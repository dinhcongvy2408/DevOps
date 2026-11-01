# Lời giải — Checkpoint Module 02

> ⚠️ Chỉ đọc sau khi đã commit bài làm của bạn.
> Câu trả lời của bạn không cần giống từng chữ — đạt khi **đúng bản chất** và lập luận được. Đầu ra mẫu là **minh họa**; IP, thời gian trên máy bạn sẽ khác.

Quay lại đề: [checkpoint.md](../checkpoint.md)

## Mục lục

- [Phần A — Lý thuyết](#phần-a--lý-thuyết)
- [Phần B1 — Thiết kế subnet](#phần-b1--thiết-kế-subnet)
- [Phần B2 — Cấu hình Nginx](#phần-b2--cấu-hình-nginx)
- [Phần C — Break-fix](#phần-c--break-fix)

---

## Phần A — Lý thuyết

**1. Các tầng TCP/IP và xếp loại.**
4 tầng: Application (ứng dụng) · Transport (giao vận) · Internet (mạng) · Link/Network Access (liên kết).

| Thứ | Tầng | Lý do |
|---|---|---|
| `ping` | Internet | Dùng ICMP, chạy trực tiếp trên IP, **không có port** |
| DNS | Application | Giao thức ứng dụng, chạy trên UDP/TCP port 53 |
| Security Group | Transport + Internet | Luật theo IP nguồn/đích + giao thức + port (L3/L4) — không đọc được URL |
| Application Load Balancer | Application | Định tuyến theo HTTP: host, đường dẫn, header (L7) |
| Switch | Link | Chuyển frame theo địa chỉ MAC trong cùng mạng cục bộ (L2) |
| Địa chỉ MAC | Link | Địa chỉ phần cứng, chỉ có ý nghĩa trong một mạng cục bộ |
| `curl` | Application | Client HTTP — nhưng kết quả lỗi của nó cho biết lỗi ở tầng nào (DNS, TCP, TLS, HTTP) |

**2. Đóng gói và thay đổi địa chỉ.**
Dữ liệu HTTP → thêm TCP header (port nguồn tạm, port đích 80/443) → thêm IP header (IP laptop → IP server) → thêm Ethernet/Wi-Fi header (MAC laptop → MAC **router kế tiếp**, không phải MAC server). Qua mỗi router: router bóc lớp Link, xem IP đích, tra bảng route, đóng lớp Link **mới** với MAC của chặng tiếp theo. **MAC đổi ở mọi chặng, IP giữ nguyên từ đầu đến cuối** — trừ khi đi qua NAT (router nhà bạn đổi IP nguồn private thành IP public).

**3. Tính `10.20.32.0/19`.**
`/19` = 8 bit đầu của octet thứ ba thuộc phần mạng **3 bit** (16 + 3 = 19) → kích thước khối ở octet thứ ba = 2^(8−3) = **32**. Các khối: 0, 32, 64, 96… `32` chia hết cho 32 → `10.20.32.0` là địa chỉ mạng hợp lệ.

| Mục | Giá trị |
|---|---|
| Địa chỉ mạng | `10.20.32.0` |
| Broadcast | `10.20.63.255` (khối tiếp theo bắt đầu ở `10.20.64.0`) |
| Dùng được đầu / cuối (truyền thống) | `10.20.32.1` / `10.20.63.254` |
| Tổng số địa chỉ | 2^(32−19) = 2^13 = **8192** |
| Dùng được (truyền thống) | 8192 − 2 = 8190 |
| Dùng được trên AWS | 8192 − **5** = **8187** (AWS giữ địa chỉ mạng, +1 router, +2 DNS, +3 dự phòng, và địa chỉ cuối) |
| `10.20.64.1` thuộc dải? | **Không** — nằm ở khối `10.20.64.0/19` kế tiếp |

**4. Private IP và public IP.**
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Trong máy chỉ thấy `10.0.1.25` — IP public **không được gán vào card mạng** của EC2. Internet Gateway thực hiện NAT 1:1: gói đi ra có IP nguồn `10.0.1.25` được đổi thành `13.212.x.x`, gói đi vào làm ngược lại. Hệ quả thực tế: ứng dụng lấy "IP của mình" bằng `ip addr` sẽ ra IP private; muốn biết IP public phải hỏi metadata service hoặc dịch vụ bên ngoài.

**5. Quá trình phân giải DNS và TTL.**
Trình duyệt/OS xem cache và `/etc/hosts` → hỏi **recursive resolver** (DNS của ISP, của VPC, 8.8.8.8…). Resolver chưa có trong cache thì hỏi **root** ("ai quản lý `.com`?") → hỏi **TLD server** của `.com` ("ai quản lý `example.com`?") → hỏi **authoritative server** của `example.com` → nhận record A, **lưu cache trong TTL giây** rồi trả cho client. Đổi record khi TTL = 3600: resolver đã cache bản cũ sẽ tiếp tục trả IP cũ **tới 1 giờ**. Cách làm đúng: **hạ TTL xuống thấp (ví dụ 60) trước đợt chuyển ít nhất một khoảng bằng TTL cũ**, đổi record, xác nhận ổn định rồi nâng TTL lên lại. Giữ máy cũ chạy thêm một thời gian để không mất người dùng.

**6. `dig` đúng nhưng `curl` sai.**
(a) Có dòng trong `/etc/hosts` — `dig` không đọc file này, `curl` có. Xác nhận: `getent hosts api.internal`, `grep api /etc/hosts`. (b) Ứng dụng/OS dùng DNS server khác hoặc cache cũ (systemd-resolved, nscd, cache của chính ứng dụng — JVM cache DNS). Xác nhận: `resolvectl query api.internal`, so sánh `dig @<DNS-đang-dùng>`, xem `/etc/resolv.conf`. Cũng chấp nhận: `curl` đi qua proxy (`http_proxy`), hoặc `--resolve` trong alias.

**7. Bảng route.**
`8.8.8.8` → không khớp route cụ thể nào → **default** qua gateway `10.0.1.1`. `10.0.1.40` → khớp `10.0.1.0/24`, gửi **trực tiếp** trên `eth0` (dùng ARP tìm MAC, không qua gateway). `172.17.0.5` → khớp `172.17.0.0/16` → qua bridge `docker0` (một container). `10.0.2.7` → không khớp `10.0.1.0/24` → **default** qua `10.0.1.1`. `default via` = "mọi đích không có route cụ thể hơn thì gửi cho router này". Lệnh: `ip route get 10.0.2.7`.

**8. SNAT và DNAT.**
SNAT đổi **địa chỉ nguồn** (thường cho kết nối đi ra); DNAT đổi **địa chỉ đích** (thường cho kết nối đi vào). (a) **SNAT**: IP private của EC2 được đổi thành IP của NAT Gateway để ra Internet; Internet không chủ động kết nối vào được. (b) **DNAT**: kết nối tới `host:8080` được đổi đích thành `IP-container:80`. (c) **SNAT** (cụ thể là PAT/masquerade): nhiều thiết bị trong nhà dùng chung một IP public, phân biệt nhau bằng port nguồn.

**9. TCP handshake, DNS dùng UDP.**
Client gửi `SYN` → server trả `SYN-ACK` → client gửi `ACK` → kết nối thiết lập, hai bên thống nhất số thứ tự. DNS thường dùng UDP vì truy vấn/trả lời nhỏ, cần nhanh — không tốn một vòng handshake; nếu mất gói thì client hỏi lại. DNS dùng TCP khi câu trả lời quá lớn so với UDP (server đặt cờ truncated, client hỏi lại bằng TCP — ví dụ phản hồi DNSSEC lớn) và khi **chuyển vùng (zone transfer)** giữa các DNS server.

**10. Refused / timeout / no route.**

| Lỗi | Điều đã xảy ra | Kiểm tra tiếp |
|---|---|---|
| `Connection refused` (ngay lập tức) | Gói tới được máy đích, kernel trả `RST`: không có process nghe port đó | Dịch vụ có chạy không, nghe port nào, địa chỉ nào: `ss -tlnp` trên máy đích |
| `Connection timed out` (chờ lâu) | Gói đi mà không có hồi âm | Firewall/Security Group/NACL có DROP không; máy có quá tải không; route chiều về |
| `No route to host` | Không tìm được đường, hoặc trong mạng cục bộ không ai trả lời ARP cho IP đó, hoặc firewall trả ICMP host-unreachable | IP có đúng không (`getent hosts`), máy có tồn tại/bật không, `ip route get` |

**11. Nghe trên `127.0.0.1`.**
Máy khác nhận `Connection refused`: app chỉ nghe trên loopback, kết nối tới IP thật của server không khớp socket nào. Sửa ở cấu hình app (`server.address` của Spring Boot, `BIND_ADDR`…) thành `0.0.0.0` hoặc IP cụ thể của card mạng. Trong container với `-p 8080:8080`: Docker chuyển kết nối tới **IP của container** (không phải loopback của container) → app không nhận → client thấy lỗi kiểu `Connection reset by peer` / `Empty reply from server`. Đây là lỗi kinh điển khi container hóa ứng dụng.

**12. Stateful và stateless.**
Stateful nhớ trạng thái kết nối: đã cho phép chiều đi thì **tự cho phép chiều về** của chính kết nối đó. Stateless xét **từng gói độc lập**: chiều về phải có luật riêng. Security Group là **stateful**, NACL là **stateless**. Khi client kết nối tới server port 443, gói trả về đi tới **port tạm** của client (dải cao, ví dụ 1024–65535) — với NACL phải có luật outbound cho dải port tạm đó (và ngược lại ở NACL phía client), nếu không response bị chặn. Security Group tự cho phép vì nó nhớ kết nối.

**13. 502 / 503 / 504 sau reverse proxy.**

| Mã | Ý nghĩa | Xem đầu tiên |
|---|---|---|
| 502 | Proxy **không nhận được response hợp lệ** từ upstream: bị từ chối kết nối, không phân giải được tên, upstream đóng kết nối giữa chừng | `error.log` của nginx: `connect() failed (111: Connection refused)`, `could not be resolved`, `upstream prematurely closed connection` → rồi xem upstream có chạy/nghe đúng port không |
| 503 | Dịch vụ **tạm thời không phục vụ**: thường do chính upstream trả về (đang khởi động, bảo trì, quá tải), do proxy giới hạn (`limit_req`), hoặc load balancer không còn target khỏe (AWS ALB) | Phân biệt 503 do nginx sinh ra hay do backend trả về: `access.log` (trường upstream status nếu có cấu hình), log của app, health check của target |
| 504 | Proxy **chờ upstream quá lâu** — lúc kết nối hoặc lúc chờ response | `error.log`: `upstream timed out (110: ...) while connecting` (thường là firewall/mạng) hay `while reading response header` (backend chậm) |

**14. TLS handshake và lỗi thường gặp.**
Client gửi ClientHello (phiên bản TLS hỗ trợ, bộ mã hóa, **SNI** = tên miền muốn vào). Server trả lời chọn bộ mã hóa và gửi **chuỗi chứng chỉ**. Hai bên trao đổi khóa để tạo khóa phiên rồi mã hóa dữ liệu. Client kiểm tra chứng chỉ: (1) chuỗi dẫn tới một **CA tin cậy**, (2) **tên miền khớp SAN**, (3) **còn hạn**. Lỗi hay gặp: chứng chỉ **hết hạn**; **sai tên** (SAN không chứa tên miền đang truy cập); **thiếu chứng chỉ trung gian** hoặc chứng chỉ tự ký không được tin. Lệnh:

```bash
openssl s_client -connect app.example.com:443 -servername app.example.com -showcerts </dev/null
openssl s_client -connect app.example.com:443 -servername app.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

**15. Toàn bộ luồng `https://app.example.com/api/tasks`.**

| Bước | Có thể hỏng vì | Kiểm tra bằng |
|---|---|---|
| 1. DNS: tên → IP | Record sai/cũ, TTL cache, `/etc/hosts`, DNS server lỗi | `dig app.example.com`, `getent hosts` |
| 2. Định tuyến tới IP | Không có route, máy đích tắt | `ping`, `traceroute`, `ip route get` |
| 3. TCP handshake tới 443 | Firewall/SG chặn (timeout), không ai nghe (refused) | `nc -zv app.example.com 443`, `curl -v` dòng `Connected to` |
| 4. TLS handshake | Cert hết hạn, sai tên, thiếu chain | `curl -v` phần `SSL connection`, `openssl s_client` |
| 5. HTTP request tới reverse proxy | Host không khớp `server_name`, sai location | `curl -v` xem status code, `access.log` |
| 6. Proxy → app | App chết/sai port (502), chậm (504) | `error.log` của nginx, `curl` thẳng tới app |
| 7. App → database | App lỗi kết nối DB → 500 | Log ứng dụng (stack trace `Caused by`), `nc -zv db 5432` |
| 8. Response quay về | — | `curl -w '%{http_code} %{time_total}'` |

---

## Phần B1 — Thiết kế subnet

Kích thước nhỏ nhất đủ dùng (nhớ trừ 5 địa chỉ của AWS):

| Loại | Cần | `/27` (27 dùng được) | `/26` (59) | `/24` (251) | `/23` (507) | Chọn |
|---|---|---|---|---|---|---|
| public | 50 | ❌ | ✅ | | | **`/26`** |
| private-app | 400 | | | ❌ | ✅ | **`/23`** |
| private-db | 20 | ✅ (`/28` chỉ có 11 — thiếu) | | | | **`/27`** |

Xếp **khối lớn trước, khối nhỏ sau** để mọi khối tự động căn đúng biên và phần trống dồn về một phía:

| Tên | AZ | CIDR | Đầu – cuối | Dùng được (AWS) |
|---|---|---|---|---|
| private-app-a | a | `10.30.0.0/23` | `10.30.0.0` – `10.30.1.255` | 507 |
| private-app-b | b | `10.30.2.0/23` | `10.30.2.0` – `10.30.3.255` | 507 |
| public-a | a | `10.30.4.0/26` | `10.30.4.0` – `10.30.4.63` | 59 |
| public-b | b | `10.30.4.64/26` | `10.30.4.64` – `10.30.4.127` | 59 |
| private-db-a | a | `10.30.4.128/27` | `10.30.4.128` – `10.30.4.159` | 27 |
| private-db-b | b | `10.30.4.160/27` | `10.30.4.160` – `10.30.4.191` | 27 |

Ví dụ phần tính cho `10.30.4.64/26`: `/26` → octet cuối có 2 bit mạng, khối 2^6 = 64. Các khối: 0, 64, 128, 192. `64` là biên hợp lệ → đầu `10.30.4.64`, cuối `10.30.4.127` (64 + 64 − 1).

**Phần còn trống:** `10.30.4.192` – `10.30.15.255`, gồm `10.30.4.192/26`, `10.30.5.0/24`, `10.30.6.0/23`, `10.30.8.0/21`.
**Thêm một `/22`?** Được: `10.30.8.0/22` (hoặc `10.30.12.0/22`). Một `/22` phải bắt đầu ở bội số của 4 trong octet thứ ba: 0, 4, 8, 12 — `0` và `4` đã bị dùng một phần, `8` và `12` còn trống hoàn toàn.

Chấp nhận cách xếp khác nếu: không chồng lấn, căn đúng biên, kích thước nhỏ nhất đủ dùng. Trừ điểm nếu xếp xen kẽ làm phần trống bị chia vụn (ví dụ đặt `/27` ở `10.30.0.0` rồi mới đặt `/23` ở `10.30.2.0` — để lại lỗ khó dùng).

---

## Phần B2 — Cấu hình Nginx

Một cấu hình đạt:

```nginx
server {
    listen 80;                                   # nhận HTTP ở port 80 của container (18081 bên ngoài)

    # Header gửi kèm mọi request tới backend.
    # Lưu ý: location nào tự khai báo proxy_set_header thì KHÔNG kế thừa các dòng này nữa.
    proxy_set_header Host              $http_host;                  # Host gốc của client, gồm cả port
    proxy_set_header X-Real-IP         $remote_addr;                # IP của client gọi tới nginx
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;  # chuỗi IP các chặng đã đi qua
    proxy_set_header X-Forwarded-Proto $scheme;                     # client dùng http hay https

    # Healthcheck do chính nginx trả lời — không phụ thuộc backend
    location = /health {
        default_type text/plain;
        return 200 "ok\n";
    }

    # /api/... → backend A. Dấu "/" cuối proxy_pass thay phần khớp "/api/" bằng "/"
    location /api/ {
        proxy_pass http://api:8000/;
    }

    # Mọi thứ còn lại → backend B, giữ nguyên đường dẫn (proxy_pass không có phần URI)
    location / {
        proxy_pass http://frontend:3000;
    }
}
```

**Điểm then chốt — dấu `/` cuối `proxy_pass`:**

| Cấu hình | Request `/api/tasks?x=1` tới backend thành |
|---|---|
| `location /api/ { proxy_pass http://api:8000/; }` | `/tasks?x=1` ✅ |
| `location /api/ { proxy_pass http://api:8000; }` | `/api/tasks?x=1` (giữ nguyên) |

Quy tắc: nếu `proxy_pass` **có phần URI** (dù chỉ là `/`), nginx thay phần khớp với `location` bằng URI đó; **không có** thì chuyển nguyên đường dẫn gốc.

**Kiểm thử 5 — `curl -sI http://localhost:18081/api`:**

```text
HTTP/1.1 301 Moved Permanently
Location: http://localhost/api/
```

Request `/api` không khớp `location /api/` theo kiểu tiền tố (thiếu dấu `/`), nhưng nginx có quy tắc đặc biệt: khi location dạng tiền tố **kết thúc bằng `/`** và dùng `proxy_pass`, request tới đúng chuỗi đó **mà thiếu dấu `/` cuối** sẽ nhận **301** chuyển sang bản có dấu `/`. Chú ý: `Location` có thể **mất port 18081** (`http://localhost/api/`), vì nginx dựng URL bằng port nó đang nghe **bên trong** container (80). Đây là lỗi thật hay gặp sau reverse proxy/Docker. Cách sửa: `absolute_redirect off;` (nginx trả `Location: /api/` — đường dẫn tương đối, trình duyệt tự giữ host và port). Giải thích được hiện tượng là đạt, không bắt buộc sửa.

**Kiểm thử 6:** `host_header` là `localhost:18081` (với `$http_host`) hoặc `localhost` (với `$host`) — cả hai đều đạt. Nếu thấy `api:8000` → chưa đặt `proxy_set_header Host`, hoặc đặt ở `server` nhưng location lại khai báo `proxy_set_header` riêng nên mất kế thừa.

---

## Phần C — Break-fix

Thứ tự hợp lý: #4001 trước (vì nó chặn mọi thứ dùng tên miền), sau đó #4002–#4004 độc lập.

### Ticket #4001 — DNS trỏ về IP của máy cũ

**Cách tìm ra:**

```bash
curl -v --cacert /certs/edge.crt https://app.taskhub.test/
```

```text
*   Trying 172.29.1.50:443...
* connect to 172.29.1.50 port 443 failed: No route to host
curl: (7) Failed to connect to app.taskhub.test port 443 after 3062 ms: No route to host
```

curl thử `172.29.1.50` — trong khi bối cảnh nói edge mới là `172.29.1.10`. `No route to host` sau ~3 giây: không máy nào trong mạng trả lời ARP cho IP đó → máy cũ không còn tồn tại.

```bash
dig app.taskhub.test
```

```text
;; ANSWER SECTION:
app.taskhub.test.       300     IN      A       172.29.1.50
;; SERVER: 127.0.0.11#53(127.0.0.11)
```

Câu trả lời có TTL 300. Hỏi thẳng DNS server của miền để biết **nguồn** sai ở đâu:

```bash
dig @172.29.1.53 app.taskhub.test +short     # 172.29.1.50 → chính DNS server đang trả IP cũ
getent hosts edge                            # 172.29.1.10 → IP thật của edge
```

`/etc/hosts` của client không có gì về `app.taskhub.test` → không phải lỗi phía client như break-fix #1. Bản ghi trong `dns/hosts.taskhub` vẫn là IP cũ: người chuyển máy **quên cập nhật DNS**.

**Sửa:** trong `dns/hosts.taskhub` đổi thành `172.29.1.10   app.taskhub.test`, rồi `docker compose restart dns`. Kiểm tra: `dig @172.29.1.53 app.taskhub.test +short` → `172.29.1.10`.

**Bài học về TTL:** ở đây resolver chỉ cache rất ít nên đổi xong thấy ngay. Trên Internet thật, các resolver đã cache bản cũ sẽ tiếp tục trả `172.29.1.50` tới **300 giây**. Quy trình chuyển máy đúng: hạ TTL trước → đổi record → giữ máy cũ chạy (hoặc chuyển hướng) cho tới khi hết TTL cũ.

### Ticket #4002 — Chứng chỉ cấp cho sai tên miền

**Cách tìm ra:**

```text
curl: (60) SSL: no alternative certificate subject name matches target host name 'app.taskhub.test'
```

Lỗi nói rõ: chứng chỉ **không chứa** tên `app.taskhub.test` trong danh sách tên hợp lệ (SAN). Xem chứng chỉ server thực sự gửi:

```bash
openssl s_client -connect app.taskhub.test:443 -servername app.taskhub.test </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -ext subjectAltName -dates
```

```text
subject=CN = www.taskhub.test
X509v3 Subject Alternative Name:
    DNS:www.taskhub.test
notBefore=Nov 16 08:00:00 2026 GMT
notAfter=Nov 16 08:00:00 2027 GMT
```

Còn hạn, nhưng cấp cho `www.taskhub.test`. Truy ngược nơi sinh chứng chỉ: `edge/conf.d/default.conf` → `ssl_certificate /certs/edge.crt` → volume `certs` → do `certgen` sinh bằng `certs/gen.sh` → `DOMAIN="www.taskhub.test"`.

**Sửa:** `DOMAIN="app.taskhub.test"` trong `certs/gen.sh`, rồi:

```bash
docker compose up -d --force-recreate certgen
docker compose logs certgen                       # certgen: generated certificate for app.taskhub.test
docker compose exec edge nginx -s reload          # nginx chỉ đọc chứng chỉ mới khi reload
```

Nếu quên `reload`, `openssl s_client` vẫn thấy chứng chỉ cũ — một bẫy hay gặp khi gia hạn chứng chỉ trên server thật.

**Vì sao không dùng `curl -k`?** `-k` tắt **toàn bộ** việc kiểm tra chứng chỉ — monitoring sẽ báo "xanh" trong khi người dùng thật nhận cảnh báo bảo mật. Chỉ dùng `-k` để **tạm** loại trừ TLS khi debug tầng khác (như `verify-checkpoint` làm với #4003).

### Ticket #4003 — 504 do backend chậm hơn giới hạn chờ

**Cách tìm ra:**

```bash
curl -sk -o /dev/null -w '%{http_code} %{time_total}s\n' https://app.taskhub.test/api/report
# 504 5.01s
curl -sk -o /dev/null -w '%{http_code} %{time_total}s\n' https://app.taskhub.test/api/tasks
# 200 0.01s
```

Luôn 504 **đúng khoảng 5 giây**, chỉ với `/api/report` → dấu hiệu của một **giới hạn thời gian**, không phải lỗi ngẫu nhiên.

```bash
docker compose logs edge --tail 5
```

```text
... upstream timed out (110: Operation timed out) while reading response header from upstream,
    ... request: "GET /api/report HTTP/1.1", upstream: "http://172.29.1.4:8000/api/report"
```

So với break-fix #1 (lỗi 3): ở đó là `while connecting` (không kết nối được — firewall). Ở đây là **`while reading response header`**: kết nối **thành công**, backend nhận request nhưng trả lời chậm hơn `proxy_read_timeout 5s`. Log của api xác nhận request có tới, và có dòng báo client (nginx) đã đóng kết nối trước khi api trả lời xong.

**Sửa:** tăng giới hạn **chỉ cho đường dẫn chậm**, giữ các API khác "fail fast":

```nginx
    location /api/report {
        proxy_pass http://api:8000;
        proxy_connect_timeout 3s;
        proxy_read_timeout    15s;    # báo cáo ~8s là bình thường; 15s = mức tối đa chấp nhận được

        # Phải khai báo lại: location có proxy_* riêng không kế thừa từ location /api/
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Cũng đạt: tăng `proxy_read_timeout` của cả `location /api/` lên 12–15s, **nếu** giải thích được đánh đổi (mọi API chậm đều giữ kết nối lâu hơn). Không đạt: đặt `300s`, `3600s` mà không có lý do. Nêu thêm điểm cộng: về lâu dài báo cáo nặng nên chuyển sang xử lý **bất đồng bộ** (trả `202 Accepted` + kiểm tra trạng thái sau).

### Ticket #4004 — `server_name` gõ sai, request rơi vào server mặc định

**Cách tìm ra:**

```bash
curl -v http://app.taskhub.test/health
```

```text
> GET /health HTTP/1.1
> Host: app.taskhub.test
...
< HTTP/1.1 404 Not Found
unknown site
```

`unknown site` là nội dung của server block `default_server` → nginx **không tìm thấy** server block nào có `server_name` khớp với header `Host: app.taskhub.test`. Nginx chọn server block cho port 80 dựa vào **header Host** (name-based virtual hosting). Đọc cấu hình:

```bash
docker compose exec edge nginx -T | grep -n server_name
```

```text
server_name _;
server_name app.taskhub.tset;
server_name app.taskhub.test;
```

`tset` ≠ `test`. Chứng minh giả thuyết bằng cách tự đặt header Host:

```bash
curl -s -H 'Host: app.taskhub.tset' http://172.29.1.10/health      # ok   → đúng là do server_name
```

**Sửa:** `server_name app.taskhub.test;` trong server block port 80, rồi `nginx -t && nginx -s reload`.

**Vì sao HTTPS vẫn chạy dù HTTP hỏng?** Port 443 chỉ có **một** server block nên nó tự là mặc định cho mọi request vào 443, bất kể Host. Port 80 có hai block nên Host quyết định — và Host không khớp block nào thì rơi vào `default_server`.

### Tổng kết Phần C

| Ticket | Tầng | Thông báo dẫn đường | Lệnh then chốt |
|---|---|---|---|
| #4001 | DNS | `Trying 172.29.1.50` + `No route to host` | `dig`, `dig @<dns-server>` |
| #4002 | TLS | `no alternative certificate subject name matches` | `openssl s_client … \| openssl x509 -ext subjectAltName` |
| #4003 | HTTP / proxy timeout | `504` đúng 5s, `while reading response header` | `curl -w '%{time_total}'`, `docker compose logs edge` |
| #4004 | HTTP / virtual host | `404 unknown site` từ `default_server` | `curl -H 'Host: …'`, `nginx -T` |
