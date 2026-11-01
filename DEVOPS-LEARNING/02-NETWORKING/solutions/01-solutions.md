# Lời giải — Bài 01: Mô hình OSI và TCP/IP

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng (dựa vào việc "thứ đó đọc/ghi header nào") vẫn tính là đạt.

Quay lại bài: [01-osi-tcpip-model.md](../01-osi-tcpip-model.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Vì sao chia tầng?**
Mỗi tầng chỉ giải quyết một nhóm bài toán và chỉ giao tiếp với tầng ngay trên/dưới, nên có thể thay đổi một tầng mà không phá các tầng khác, và mỗi phần được phát triển độc lập. Ví dụ: laptop chuyển từ Wi-Fi sang cáp Ethernet (tầng 1–2 đổi hoàn toàn) nhưng trình duyệt, HTTP, TCP, IP không cần thay đổi gì. Lợi ích thứ hai cho DevOps: có **khung để khoanh vùng lỗi**.

**2. Bốn tầng TCP/IP:** Application (OSI 5–7), Transport (OSI 4), Internet (OSI 3), Link (OSI 1–2). "L4", "L7" là số tầng của **OSI**.

**3. Đóng gói request HTTP:**
- Tầng ứng dụng tạo dữ liệu HTTP: method, đường dẫn, header `Host`.
- Tầng giao vận thêm TCP header: **port nguồn** (ngẫu nhiên), **port đích** (80/443), số thứ tự, cờ.
- Tầng liên mạng thêm IP header: **IP nguồn**, **IP đích**, **TTL**, Protocol = 6 (TCP).
- Tầng liên kết thêm Ethernet header: **MAC nguồn** (card mạng của máy), **MAC đích** (gateway nếu đích ở mạng khác), EtherType.
Máy nhận làm ngược lại (decapsulation).

**4. Frame / packet / segment:** frame là đơn vị tầng 2 (có MAC); packet là đơn vị tầng 3 (có IP); segment là đơn vị tầng 4 của TCP (có port, sequence). Một frame chở một packet, một packet chở một segment.

**5. MAC / IP / port:** MAC — card mạng nào trong mạng nội bộ; IP — máy nào trên toàn mạng; port — chương trình nào trên máy đó. Qua router (không NAT): **MAC thay đổi** ở mỗi chặng; IP và port **giữ nguyên**. TTL giảm 1 ở mỗi router.

**6. ARP:** tìm MAC tương ứng với một IP trong cùng mạng nội bộ. Khi đích ở mạng khác, máy hỏi ARP cho **IP của default gateway**, rồi gửi frame tới MAC của gateway.

**7. `ping`:** tầng 3, dùng ICMP — giao thức nằm ngay trên IP. ICMP không có tầng 4 nên không có khái niệm port.

**8. Security Group và `/admin`:** Security Group chỉ đọc thông tin tầng 3–4 (IP, protocol, port). Đường dẫn `/admin` nằm trong dữ liệu HTTP ở tầng 7 (và còn bị mã hóa nếu là HTTPS). Muốn chặn phải dùng thiết bị tầng 7: Nginx (`location /admin { deny all; }`), rule của ALB, hoặc WAF.

**9. DNS:** tầng 7 (giao thức ứng dụng), chủ yếu dùng **UDP port 53**, dùng **TCP port 53** khi câu trả lời lớn hoặc khi truyền zone.

**10. ALB vs NLB:** ALB tầng 7 — đọc HTTP, route theo host/path/header, kết thúc TLS. NLB tầng 4 — chuyển tiếp kết nối TCP/UDP theo port, không đọc HTTP, rất nhanh, giữ IP nguồn. Bắt buộc tầng 7 khi cần quyết định dựa trên nội dung HTTP (route `/api` và `/static` về hai backend, route theo tên miền).

**11. Từ dưới lên / từ trên xuống:**
- Từ dưới lên khi không có thông tin hoặc mọi thứ hỏng. Ví dụ: server mới tạo, SSH không vào được, không có log gì → kiểm tra interface/IP, route, firewall, rồi mới tới dịch vụ.
- Từ trên xuống khi có lỗi cụ thể ở tầng cao. Ví dụ: `502 Bad Gateway` → kết nối tới proxy đã ổn, chỉ cần xem phía sau proxy.

**12.** `ping 1.1.1.1` thành công chứng minh tầng 1–3 ổn (có IP, có route, ra được Internet). `ping google.com` báo lỗi phân giải tên → hỏng ở bước **DNS** (tầng 7), xảy ra trước khi ping gửi bất kỳ gói ICMP nào. Kiểm tra `/etc/resolv.conf` và dùng `dig` ([bài 03](../03-dns-dhcp.md)).

**13.** `example.com` ở mạng khác, nên WSL không bao giờ gửi frame trực tiếp tới nó — mọi frame đi tới gateway (Windows). ARP chỉ dùng trong cùng mạng nội bộ, nên bảng ARP chỉ có MAC của gateway. MAC của server `example.com` chỉ có ý nghĩa trong mạng nội bộ của chính nó.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Xếp tầng

| Mục | Tầng | Vì sao |
|---|---|---|
| `ssh` | 7 | Giao thức ứng dụng (chạy trên TCP 22) |
| `traceroute` | 3 | Dựa vào TTL trong IP header và thông báo ICMP từ router |
| Wi-Fi | 1–2 | Sóng radio (1) + frame 802.11 với MAC (2) |
| Kubernetes Ingress | 7 | Route theo hostname/path của HTTP |
| AWS Network ACL | 3–4 | Lọc theo IP, protocol, port (stateless) |
| `nc -vz host 5432` | 4 | Thử mở kết nối TCP tới một port |
| Header `Host:` | 7 | Một phần của dữ liệu HTTP |
| `ip neigh` | 2 (cầu nối 2–3) | Bảng ARP: IP ↔ MAC |
| Chứng chỉ TLS | 6/7 | TLS mã hóa dữ liệu ứng dụng, nằm giữa TCP và HTTP |
| Switch | 2 | Chuyển frame dựa trên MAC |
| Route 53 | 7 | Dịch vụ DNS |

### Bài 2 — Chặng tầng 2

- **(a)** 4 router (router nhà + 3 router trung gian) → **5 chặng** tầng 2: laptop→router nhà, router nhà→R1, R1→R2, R2→R3, R3→server. Số chặng = số router + 1.
- **(b)** MAC đích ở chặng đầu là MAC của **router nhà bạn** (default gateway).
- **(c)** IP đích vẫn là `13.250.10.20` — IP không đổi qua router (khi không có NAT).
- **(d)** Không đổi: IP nguồn, IP đích, port nguồn, port đích, toàn bộ dữ liệu TCP/HTTP. Thay đổi: MAC nguồn/đích ở mỗi chặng, TTL (giảm 1 qua mỗi router).
- Ghi chú thực tế: router nhà bạn **có** làm NAT, nên sau chặng đầu, IP nguồn bị đổi từ `192.168.1.10` thành IP public của nhà bạn ([bài 04](../04-routing-nat-switching.md)).

### Bài 3 — Đọc lỗi để chọn tầng

| Lỗi | Tầng nghi ngờ | Lệnh đầu tiên | Lý do |
|---|---|---|---|
| (a) `ssh ... port 22: Connection timed out` | 3–4 (firewall) | Kiểm tra Security Group/firewall cho port 22; `ip route get 10.0.1.25` để chắc có route; `nc -vz -w 3 10.0.1.25 22` | Timeout = không có phản hồi nào. Gói tin bị bỏ lặng lẽ (firewall) hoặc không tới được máy. Nếu không có ai nghe thì đã nhận `refused` chứ không phải timeout |
| (b) `Could not resolve host: taskhub.internal` | 7 (DNS) | `getent hosts taskhub.internal` hoặc `dig taskhub.internal`; xem `/etc/hosts`, `/etc/resolv.conf` | Lỗi xảy ra trước khi có kết nối — chưa cần kiểm tra mạng hay port |
| (c) `Network is unreachable` | 3 | `ip route` (có dòng `default` không?), `ip addr` (interface có IP không?) | Kernel không tìm được route nào tới đích |
| (d) `localhost port 8080: Connection refused` | 4 | `ss -tlnp \| grep 8080` | Máy (chính nó) trả lời ngay "không có ai nghe ở port này" → app chưa chạy, chạy ở port khác, hoặc chỉ nghe trên địa chỉ khác |
| (e) `502 Bad Gateway` từ Nginx | 7 — phía sau proxy | Xem `/var/log/nginx/error.log`; từ máy chạy Nginx `curl -v` thẳng tới upstream | Kết nối từ bạn tới Nginx đã thành công; Nginx không lấy được response hợp lệ từ app phía sau |

### Bài 4 — Mạng của container

Kết quả minh họa (trên máy bạn có thể khác):

```text
lo               UNKNOWN        127.0.0.1/8
eth0@if12        UP             172.17.0.2/16

default via 172.17.0.1 dev eth0
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2

172.17.0.1 dev eth0 lladdr 02:42:8e:1a:2b:3c REACHABLE
```

- Container có `lo` và `eth0` riêng — tên `eth0@if12` cho thấy nó là một đầu của cặp "dây cáp ảo", đầu kia (interface số 12) nằm ở máy host.
- IP thuộc dải `172.17.0.0/16` — dải mặc định của bridge Docker ([bài 02](../02-ipv4-subnet-cidr.md)).
- Gateway `172.17.0.1` là **bridge `docker0`** trên máy chạy Docker Engine (với Docker Desktop, đó là máy ảo Linux mà Docker Desktop quản lý). Bridge này đóng vai switch + router cho các container. Module 04 sẽ xác nhận.
- MAC bắt đầu bằng `02:42` là kiểu MAC Docker tự sinh cho interface ảo.

Đạt nếu bạn đoán được "gateway là một thiết bị ảo do Docker tạo ra trên máy host", dù chưa biết tên `docker0`.

### Bài 5 — Giải thích cho người khác

Mẫu tham khảo:

> `ping` dùng giao thức ICMP ở tầng 3 — nó chỉ chứng minh có **đường đi** tới máy database. Còn app Java kết nối database qua **TCP port 5432** (tầng 4), rồi nói giao thức PostgreSQL (tầng 7). Vì vậy ping được nhưng app vẫn có thể lỗi vì: firewall/Security Group cho phép ICMP nhưng chặn port 5432 (lỗi timeout); PostgreSQL không chạy hoặc chỉ lắng nghe trên `127.0.0.1` (lỗi connection refused); hoặc tới được nhưng sai user/mật khẩu (lỗi xác thực ở tầng 7). Cần kiểm tra từng tầng phía trên: `nc -vz db-host 5432`, rồi đọc log của app và của PostgreSQL.

Đạt khi: nói được ping chỉ chứng minh tầng 3, và nêu ít nhất hai nguyên nhân ở tầng cao hơn.
