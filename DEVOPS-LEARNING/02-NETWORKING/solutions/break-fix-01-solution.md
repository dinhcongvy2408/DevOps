# Lời giải — Break-fix Network #1

> ⚠️ Chỉ đọc khi đã hoàn thành hoặc đã bị kẹt quá 30 phút sau khi xem hết gợi ý.
> Đầu ra mẫu dưới đây là **minh họa**: IP cụ thể (`172.28.5.x`), thời gian, số gói tin trên máy bạn sẽ khác. Cấu trúc thông báo lỗi mới là thứ cần nhận ra.

Quay lại đề bài: [labs/break-fix-01/README.md](../labs/break-fix-01/README.md)

## Mục lục

- [Tổng quan 5 lỗi](#tổng-quan-5-lỗi)
- [Lỗi 1 — nginx gửi tới sai port của api (#3001)](#lỗi-1--nginx-gửi-tới-sai-port-của-api-3001)
- [Lỗi 2 — api chỉ nghe trên loopback (#3001)](#lỗi-2--api-chỉ-nghe-trên-loopback-3001)
- [Lỗi 3 — firewall của reports cho phép dải IP cũ (#3002)](#lỗi-3--firewall-của-reports-cho-phép-dải-ip-cũ-3002)
- [Lỗi 4 — status nằm ở mạng khác (#3003)](#lỗi-4--status-nằm-ở-mạng-khác-3003)
- [Lỗi 5 — /etc/hosts cũ trên jump host (#3004)](#lỗi-5--etchosts-cũ-trên-jump-host-3004)
- [Bảng tổng kết 4 loại thông báo lỗi](#bảng-tổng-kết-4-loại-thông-báo-lỗi)
- [Tiêu chí tự chấm](#tiêu-chí-tự-chấm)

---

## Tổng quan 5 lỗi

| # | Ticket | Tầng | Thông báo đặc trưng | File sửa |
|---|---|---|---|---|
| 1 | #3001 | Cấu hình proxy (L7) | nginx: `Connection refused` tới `:8080` | `web/conf.d/default.conf` |
| 2 | #3001 | Socket / bind address (L4) | nginx: `Connection refused` tới `:8000`; log api: `listening on 127.0.0.1:8000` | `compose.yaml` (`BIND_ADDR`) |
| 3 | #3002 | Firewall (L3/L4) | nginx: `upstream timed out ... while connecting`; client: `nc ... timed out` | `reports/firewall.sh` |
| 4 | #3003 | DNS + phân tách mạng | nginx: `status could not be resolved (3: Host not found)` | `compose.yaml` (networks của `status`) |
| 5 | #3004 | Phân giải tên trên máy (`/etc/hosts`) | curl: `No route to host` trong khi `dig` trả IP đúng | `compose.yaml` (`extra_hosts` của `client`) |

Quy trình chung cho **mọi** ticket — đi từ dưới lên ([bài 08](../08-network-troubleshooting-tools.md)):

```text
1. Log reverse proxy nói gì?         docker compose logs web --tail 30
2. Tên có phân giải được không?      dig +short <tên> ; getent hosts <tên>
3. Có đường tới IP đó không?         ping -c 2 <tên> ; ip route
4. Port có nhận kết nối không?       nc -zv -w 3 <tên> <port>
5. HTTP trả gì khi gọi thẳng?        curl -v http://<tên>:<port>/
6. Dịch vụ nói gì về chính nó?       docker compose logs <tên>
```

---

## Lỗi 1 — nginx gửi tới sai port của api (#3001)

### Cách tìm ra

**Bước 1 — Log reverse proxy.**

```bash
docker compose logs web --tail 20
```

```text
web-1  | 2026/11/16 08:02:11 [error] 29#29: *3 connect() failed (111: Connection refused) while connecting to upstream,
         client: 172.28.1.1, server: _, request: "GET /api/health HTTP/1.1",
         upstream: "http://172.28.5.3:8080/api/health", host: "localhost:18080"
```

Đọc theo cấu trúc `chương trình: đối tượng: mô tả`:

- `connect() failed (111: Connection refused)` → nginx **đã tới được** máy `172.28.5.3` (có đường đi, có máy trả lời) nhưng máy đó **từ chối kết nối** → không có process nào nghe ở port đó.
- `upstream: "http://172.28.5.3:8080/..."` → nginx đang gọi **port 8080**.

**Bước 2 — Dịch vụ thực sự nghe ở port nào?**

```bash
docker compose logs api
```

```text
api-1  | api listening on 127.0.0.1:8000
```

api nghe port **8000**, không phải 8080. Sơ đồ trong đề bài cũng ghi `api :8000`.

### Nguyên nhân gốc

`web/conf.d/default.conf` có `set $api_upstream http://api:8080;` — sai port.

### Cách sửa

```nginx
location /api/ {
    set $api_upstream http://api:8000;
    proxy_pass $api_upstream;
}
```

```bash
docker compose exec web nginx -t && docker compose exec web nginx -s reload
curl -s -o /dev/null -w '%{http_code}\n' http://web/api/health    # từ jump host → vẫn 502!
```

Vẫn 502 → đọc lại log web: lần này `upstream: "http://172.28.5.3:8000/..."` nhưng **vẫn `Connection refused`**. Sang lỗi 2.

### Phòng tránh

Port của dịch vụ nên được định nghĩa ở **một nơi duy nhất** (biến môi trường, file cấu hình chung) và được kiểm tra tự động sau mỗi lần triển khai: một healthcheck gọi qua reverse proxy sẽ phát hiện lỗi này trong vài giây.

---

## Lỗi 2 — api chỉ nghe trên loopback (#3001)

### Cách tìm ra

Port đã đúng nhưng vẫn bị từ chối. Đi vòng qua nginx, gọi thẳng từ jump host:

```bash
nc -zv -w 3 api 8000
```

```text
nc: connect to api (172.28.5.3) port 8000 (tcp) failed: Connection refused
```

Lỗi xuất hiện **ngay lập tức** (không chờ 3 giây) → máy api có nhận gói tin và trả lời "không có ai nghe ở đây". Vậy mà log api ghi `listening`. Đọc kỹ lại log:

```text
api listening on 127.0.0.1:8000
```

`127.0.0.1` là địa chỉ **loopback** — chỉ dành cho kết nối từ **chính máy đó**. Kết nối tới `172.28.5.3:8000` (IP của máy trong mạng backend) không khớp với socket nào → kernel trả `RST` → `Connection refused`.

🟦 Kiểm chứng ngay bên trong máy api (image tối giản không có `ss`, nhưng luôn có `/proc`):

```bash
docker compose exec api bash -c 'cat /proc/net/tcp | head -3'
```

```text
  sl  local_address rem_address   st ...
   0: 0B00007F:9C2D 00000000:0000 0A ...
   1: 0100007F:1F40 00000000:0000 0A ...
```

Dòng `1`: `0100007F` là `127.0.0.1` viết ngược theo byte dạng hex, `1F40` = 8000, `st 0A` = LISTEN. So với `00000000:1F40` nếu nghe trên mọi địa chỉ (`0.0.0.0`). Dòng `0` (`0B00007F` = `127.0.0.11`, port ngẫu nhiên) là DNS nội bộ của Docker nằm trong network namespace của container — không phải của app (kết quả thật khi chạy lab, kiểm chứng 2026-10-31).

### Nguyên nhân gốc

`compose.yaml` đặt `BIND_ADDR: "127.0.0.1"` cho api. Đây là lỗi **cực kỳ phổ biến** khi chuyển ứng dụng từ máy dev (nơi mọi thứ chạy trên localhost) vào container hoặc server.

### Cách sửa

```yaml
  api:
    environment:
      BIND_ADDR: "0.0.0.0"
```

```bash
docker compose up -d                         # Compose thấy cấu hình api thay đổi → tạo lại api
docker compose logs api --tail 3             # api listening on 0.0.0.0:8000
# từ jump host:
curl -s http://web/api/health
```

```json
{"service": "api", "hostname": "...", "path": "/api/health", "host_header": "web", "x_real_ip": "172.28.5.5", ...}
```

### Phòng tránh và gặp lại ở đâu

- Với Spring Boot: `server.address` mặc định nghe mọi địa chỉ — đừng đặt `localhost` trong cấu hình production.
- **Docker (Module 04):** app trong container nghe `127.0.0.1` thì `docker run -p 8080:8080` cũng **không** truy cập được từ ngoài — triệu chứng giống hệt.
- **Kubernetes (Module 09):** Pod nghe `127.0.0.1` → Service không gửi traffic tới được, readiness probe thất bại.

---

## Lỗi 3 — firewall của reports cho phép dải IP cũ (#3002)

### Cách tìm ra

**Bước 1 — Log reverse proxy.**

```text
web-1  | ... [error] ... upstream timed out (110: Operation timed out) while connecting to upstream,
         ... request: "GET /reports/daily HTTP/1.1", upstream: "http://172.28.5.4:9000/reports/daily"
```

Khác hẳn lỗi 1–2: không phải `refused` mà là **`timed out` khi đang kết nối**. Nginx chờ hết `proxy_connect_timeout 5s` mà không nhận được trả lời nào → trả `504`. (Chuỗi trong ngoặc có thể là `Operation timed out` hoặc `Connection timed out` tùy thư viện C của image — cùng là mã lỗi 110.)

**Bước 2 — Tái hiện từ jump host, chú ý thời gian.**

```bash
time nc -zv -w 3 reports 9000
```

```text
nc: connect to reports (172.28.5.4) port 9000 (tcp) timed out: Operation now in progress
real    0m3.01s
```

Treo đủ 3 giây rồi mới báo → gói SYN **đi mất không có hồi âm**. Trong khi `ping -c 2 reports` vẫn có trả lời → máy sống, có đường đi. "Máy sống nhưng một port cụ thể im lặng hoàn toàn" là dấu hiệu kinh điển của **firewall DROP**.

**Bước 3 — Kiểm tra firewall trên máy reports.**

```bash
docker compose exec reports iptables -L INPUT -n -v --line-numbers
```

```text
Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
num   pkts bytes target  prot opt in  out  source           destination
1        0     0 ACCEPT  tcp  --  *   *    172.28.9.0/24    0.0.0.0/0    tcp dpt:9000
2        6   360 DROP    tcp  --  *   *    0.0.0.0/0        0.0.0.0/0    tcp dpt:9000
```

Gọi `/reports/daily` thêm một lần rồi chạy lại lệnh: cột `pkts` của **dòng 2 (DROP)** tăng, dòng 1 vẫn `0`. Luật ACCEPT chỉ cho phép `172.28.9.0/24` — một dải **không tồn tại** trong hệ thống hiện tại.

**Bước 4 — Web gọi tới từ IP nào?**

```bash
getent hosts web          # từ jump host
```

```text
172.28.5.5      web
```

Web nằm ở 2 mạng nên có 2 IP (`172.28.1.x` ở frontend, `172.28.5.x` ở backend — xem bằng `docker compose exec web ip -4 addr`), nhưng DNS nội bộ chỉ trả **một** IP cho jump host. Điều quan trọng: khi gọi reports (trong mạng backend), web dùng IP **trong mạng backend**: `172.28.5.x`. Dải này không khớp luật ACCEPT → rơi xuống DROP.

### Nguyên nhân gốc

`reports/firewall.sh` cho phép `172.28.9.0/24` — có lẽ là dải mạng của hệ thống cũ — thay vì dải mà web thực sự dùng.

### Cách sửa

**Thử giả thuyết nhanh** (mất khi tạo lại máy):

```bash
docker compose exec reports iptables -I INPUT 1 -p tcp --dport 9000 -s 172.28.5.0/24 -j ACCEPT
curl -s -o /dev/null -w '%{http_code}\n' http://web/reports/daily      # 200
```

**Sửa lâu dài** trong `reports/firewall.sh`:

```sh
# Cho phép mạng backend (nơi web gọi tới) truy cập reports
iptables -A INPUT -p tcp --dport 9000 -s 172.28.5.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 9000 -j DROP
```

```bash
docker compose up -d --force-recreate reports
```

**Về nguyên tắc tối thiểu:** cho phép cả `172.28.5.0/24` nghĩa là jump host (cũng ở backend) gọi được reports — chấp nhận được với máy vận hành. Chặt hơn nữa: gán IP cố định cho web (`ipv4_address` trong `compose.yaml`) rồi chỉ cho phép đúng `/32` của web. Cả hai đều đạt. **Không đạt:** xóa dòng DROP hoặc `iptables -F` — ticket yêu cầu giữ firewall.

### Gặp lại ở đâu

Đây chính là tư duy của **AWS Security Group**: "cho phép port 9000 **từ nguồn X**". Trên AWS bạn sẽ dùng luật kiểu "từ Security Group của web" thay vì dải IP — chính vì IP thay đổi, như bạn vừa thấy. Firewall chặn bằng DROP → triệu chứng là **timeout**, không phải refused — câu hỏi phỏng vấn rất hay gặp.

---

## Lỗi 4 — status nằm ở mạng khác (#3003)

### Cách tìm ra

**Bước 1 — Log reverse proxy.**

```text
web-1  | ... [error] ... status could not be resolved (2: Server failure), client: 172.28.1.1, server: _,
         request: "GET /status/ HTTP/1.1", host: "localhost:18080"
```

(Trên Docker Desktop, request treo khoảng 4 giây rồi mới báo `2: Server failure`; ở môi trường Docker khác có thể là `3: Host not found` ngay lập tức. Cả hai đều là **lỗi phân giải tên**.)

Lần này nginx **chưa hề kết nối** — nó thất bại ngay ở bước **phân giải tên**. Không có dòng `upstream:` vì chưa có IP nào để gọi.

**Bước 2 — Hỏi DNS nội bộ từ chính máy web.**

```bash
docker compose exec web nslookup status 127.0.0.11
```

```text
Server:     127.0.0.11
Address:    127.0.0.11:53

;; connection timed out; no servers could be reached
```

(Kết quả thật trên Docker Desktop. Ở môi trường khác bạn có thể thấy `** server can't find status: NXDOMAIN`.)

Trong khi `nslookup api 127.0.0.11` trả IP ngay lập tức. `127.0.0.11` là DNS nội bộ của Docker (đã thấy trong dòng `resolver` của cấu hình nginx) — nó chỉ biết tên của các máy **cùng mạng** với máy đang hỏi. Tên lạ thì nó chuyển tiếp ra DNS bên ngoài; DNS bên ngoài không biết `status` → trả lỗi hoặc không trả lời → timeout.

**Bước 3 — So sánh mạng.**

```bash
docker compose ps
```

Rồi đọc `compose.yaml`: web ở `frontend` + `backend`, còn status chỉ ở `ops`. Hai máy **không có mạng chung** → không thấy tên nhau, và kể cả biết IP cũng không có đường đi tới nhau.

🟦 Kiểm chứng thêm: `docker network inspect netbf01_ops` liệt kê các container trong mạng `ops` — chỉ có status.

### Nguyên nhân gốc

Khi "tách mạng", status bị đưa sang `ops` mà quên rằng web cần gọi nó.

### Cách sửa

Hai lựa chọn — cách 1 được khuyến nghị:

```yaml
  # Cách 1: đưa status vào mạng backend (nơi web gọi các dịch vụ nội bộ)
  status:
    networks:
      - backend
      - ops
```

```yaml
  # Cách 2: cho web tham gia mạng ops — hoạt động được nhưng mở rộng phạm vi của web
  web:
    networks:
      - frontend
      - backend
      - ops
```

```bash
docker compose up -d
# chờ ~10 giây (resolver valid=10s) rồi từ jump host:
curl -s http://web/status/
```

**Vì sao cách 1 tốt hơn:** web là máy hướng ra Internet — máy dễ bị tấn công nhất. Cho nó tham gia thêm mạng `ops` nghĩa là nếu web bị chiếm quyền, kẻ tấn công thấy được mọi thứ trong `ops`. Nguyên tắc: **máy hướng ra ngoài tham gia càng ít mạng càng tốt**.

🟨 **Vì sao cấu hình nginx dùng `resolver` + biến `$status_upstream`?** Nếu viết thẳng `proxy_pass http://status:9100;`, nginx phân giải tên **lúc khởi động** — không tìm thấy `status` thì nginx **từ chối khởi động** (`host not found in upstream`) và **toàn bộ trang web sập**, không chỉ `/status/`. Dùng biến buộc nginx phân giải **lúc có request** — lỗi chỉ ảnh hưởng đúng một đường dẫn. Bài 07 có giải thích chi tiết.

### Gặp lại ở đâu

**AWS VPC (Module 06):** hai subnet khác VPC không nói chuyện được với nhau nếu không có peering. **Kubernetes (Module 09):** Service ở namespace khác phải gọi bằng tên đầy đủ, và NetworkPolicy có thể chặn giữa các namespace.

---

## Lỗi 5 — /etc/hosts cũ trên jump host (#3004)

### Cách tìm ra

```bash
curl -v http://api.internal:8000/health
```

```text
*   Trying 172.28.5.99:8000...
* connect to 172.28.5.99 port 8000 failed: No route to host
* Failed to connect to api.internal port 8000 after 3071 ms: No route to host
curl: (7) Failed to connect to api.internal port 8000 after 3071 ms: No route to host
```

Hai điểm quan trọng:

- curl đang thử IP **`172.28.5.99`**.
- Lỗi là `No route to host` sau khoảng 3 giây: trong mạng cục bộ, máy gửi hỏi "ai là 172.28.5.99?" (ARP) mà không ai trả lời → kernel kết luận không tới được máy đó.

So sánh với DNS:

```bash
dig +short api.internal
getent hosts api.internal
```

```text
172.28.5.3
172.28.5.99     api.internal
```

**Hai câu trả lời khác nhau cho cùng một tên.** `dig` hỏi **thẳng DNS server**, còn `getent` (và curl, ping, mọi ứng dụng bình thường) hỏi theo thứ tự trong `/etc/nsswitch.conf`: **`files` (tức `/etc/hosts`) trước, `dns` sau**.

```bash
grep hosts /etc/nsswitch.conf      # hosts: files dns
grep api /etc/hosts                 # 172.28.5.99    api.internal
```

### Nguyên nhân gốc

`compose.yaml` có `extra_hosts: - "api.internal:172.28.5.99"` cho client → Docker ghi dòng đó vào `/etc/hosts` của jump host. Có lẽ đây là IP cũ của api trước khi mạng được đánh số lại. `/etc/hosts` được ưu tiên hơn DNS nên mọi ứng dụng trên jump host đều dùng IP sai.

### Cách sửa

Xóa khối `extra_hosts` của client trong `compose.yaml`, rồi:

```bash
docker compose up -d       # tạo lại client — chờ cài lại công cụ ~1–2 phút
docker compose logs -f client
```

🟨 **Thử nhanh trong container trước khi sửa file:** `sed -i` trên `/etc/hosts` sẽ báo `Device or resource busy`, vì Docker gắn `/etc/hosts` từ bên ngoài vào và `sed -i` cần **thay file mới** vào chỗ file cũ. Cách làm được: ghi đè **nội dung** thay vì thay file:

```bash
grep -v 'api.internal' /etc/hosts > /tmp/hosts && cat /tmp/hosts > /etc/hosts
```

### Phòng tránh và gặp lại ở đâu

- Tránh ghi cứng IP vào `/etc/hosts`; nếu buộc phải dùng (thử nghiệm), ghi chú rõ lý do và ngày xóa.
- Khi DNS "trả lời đúng mà app vẫn sai", **luôn so sánh `dig` với `getent hosts`**.
- **Gặp lại:** máy dev có dòng `/etc/hosts` cũ trỏ tên miền về server test, rồi quên mất; Kubernetes có `hostAliases` cho Pod với tác dụng tương tự.

---

## Bảng tổng kết 4 loại thông báo lỗi

Đây là phần quan trọng nhất của bài — học thuộc **ý nghĩa**, không cần học thuộc câu chữ:

| Thông báo | Điều đã xảy ra | Gợi ý nguyên nhân | Trong bài này |
|---|---|---|---|
| `Could not resolve host` / `Host not found` / `NXDOMAIN` | Không đổi được tên thành IP | Sai tên, sai DNS, khác mạng, chưa tạo record | Lỗi 4 |
| `No route to host` | Không tìm được đường hoặc máy đích không tồn tại trong mạng cục bộ | IP sai/cũ, máy tắt, sai route, firewall gửi ICMP từ chối | Lỗi 5 |
| `Connection timed out` (chờ lâu) | Gói tin đi mà **không có hồi âm** | Firewall **DROP**, Security Group chặn, máy quá tải | Lỗi 3 |
| `Connection refused` (ngay lập tức) | Máy đích **có trả lời**: không ai nghe ở port đó | Sai port, dịch vụ chết, dịch vụ nghe trên `127.0.0.1` | Lỗi 1, 2 |

Và phía reverse proxy:

| Mã HTTP từ nginx | Ý nghĩa | Trong bài này |
|---|---|---|
| `502 Bad Gateway` | Nginx **không nói chuyện được** với upstream (refused, không phân giải được tên, upstream đóng kết nối) | Lỗi 1, 2, 4 |
| `504 Gateway Time-out` | Nginx **chờ upstream quá lâu** (lúc kết nối hoặc lúc chờ response) | Lỗi 3 |

---

## Tiêu chí tự chấm

| Mức | Tiêu chí |
|---|---|
| ✅ Đạt | `verify` 6/6, nhật ký có đủ 5 lỗi, mỗi lỗi chỉ ra được **thông báo lỗi nào dẫn bạn tới tầng nào** |
| ⭐ Tốt | Thêm: giải thích được vì sao lỗi 3 là timeout còn lỗi 1–2 là refused; chọn cách 1 cho lỗi 4 và giải thích lý do bảo mật |
| ❌ Chưa đạt | Sửa bằng cách gỡ firewall, cho web vào mọi mạng, hoặc sửa `apps/server.py`; hoặc không giải thích được cách tìm ra |
