# Lời giải — Bài 08: Bộ công cụ chẩn đoán mạng

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [08-network-troubleshooting-tools.md](../08-network-troubleshooting-tools.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Sáu bước cây quyết định?**
(1) Tên → IP: `getent hosts` / `dig +short`. (2) Đường đi: `ip route get` / `traceroute -n`. (3) Port: `nc -zv` từ client, `ss -tlnp` ở server. (4) TLS: `openssl s_client -connect host:443 -servername host`. (5) HTTP: `curl -v`. (6) Log ứng dụng/proxy: `journalctl`, `docker logs`, `error.log`.

**2. Ping và tình trạng dịch vụ?**
Ping không được có thể vì ICMP bị firewall chặn (AWS Security Group mặc định chặn), máy vẫn sống và dịch vụ vẫn chạy. Ping được chỉ chứng minh ICMP đi về được — app có thể đã chết, port có thể bị chặn, vì ICMP không liên quan tới port nào.

**3. `Temporary failure in name resolution`?**
Lỗi DNS (tầng ứng dụng) — ping chưa gửi gói ICMP nào. Kiểm tra: `ping -c 3 1.1.1.1` (có mạng không), `cat /etc/resolv.conf` (DNS server là gì), `dig example.com` (DNS server trả lời gì), `getent hosts example.com`.

**4. `ttl=57`?**
TTL còn lại khi gói trả lời về tới bạn. Gói Linux xuất phát với TTL 64, mỗi router trừ 1 → khoảng 64 − 57 = 7 chặng từ server về bạn. (Chỉ là ước lượng: đường về có thể khác đường đi, và TTL ban đầu tùy hệ điều hành.)

**5. Dãy cờ TCP?**
(a) `[S]` → `[S.]` → `[.]` → `[P.]`... → `[F.]` (và ACK) — bình thường. (b) `[S]` → `[R.]` — port đóng. (c) `[S]` → không có trả lời → `[S]` lặp lại với khoảng cách tăng dần — bị DROP.

**6. Vì sao `-n` và `-c`?**
Không có `-n`, tcpdump tra DNS ngược cho mọi IP → chậm, output khó đọc, và tự sinh thêm traffic DNS làm nhiễu kết quả. Không có `-c` (hoặc bộ lọc chặt), tcpdump bắt vô hạn → output tràn màn hình, file pcap có thể đầy ổ đĩa, và có thể thu dữ liệu nhạy cảm không cần thiết.

**7. Interface cho `127.0.0.1:8080`?**
`lo` — mọi traffic tới địa chỉ loopback đi qua interface loopback, không bao giờ ra `eth0`. Không chắc thì dùng `-i any`.

**8. Chuyển lệnh?**
`netstat -tulpn` → `ss -tulpn`; `ifconfig` → `ip addr`; `route -n` → `ip route`; `arp -n` → `ip neigh`.

**9. Vì sao chạy từ máy chạy app?**
DNS (resolver, `/etc/hosts`), bảng route, Security Group/firewall áp lên từng máy/container khác nhau. Laptop của bạn kết nối được DB không chứng minh EC2/container app kết nối được — và ngược lại. Phải tái hiện lỗi đúng tại nơi nó xảy ra.

**10. Refused vs timeout?**
Refused: gói tới được máy đích, kernel ở đó trả RST vì không có process nghe port → điều tra process (chết? nghe `127.0.0.1`? sai port?). Timeout: không có trả lời → điều tra đường đi và firewall (Security Group, NACL, iptables DROP, sai IP, thiếu route chiều về).

**11. Câu "gõ URL" — bản 30 giây và lệnh chứng minh?**
Tóm tắt: trình duyệt phân tích URL → phân giải DNS ra IP → kernel chọn route qua default gateway, gói qua NAT ra Internet → TCP handshake tới port 443 → TLS handshake (SNI, chứng chỉ, khóa phiên) → gửi HTTP request có `Host` → phía server qua load balancer, reverse proxy, app, DB → trả HTTP response → trình duyệt render và tải tài nguyên phụ.
Chứng minh: DNS `dig example.com` / `dig +trace example.com`; TCP `nc -zv example.com 443` hoặc `tcpdump` thấy `[S] [S.] [.]`; TLS `openssl s_client -connect example.com:443 -servername example.com`.

**12. `mtr` chặng giữa 100% loss, chặng cuối 0%?**
Chặng giữa đó cấu hình không trả lời (hoặc giới hạn tốc độ trả lời) ICMP gửi tới **chính nó**, nhưng vẫn **chuyển tiếp** gói bình thường. Không có mất gói thật trên đường. Mất gói chỉ đáng lo khi nó **kéo dài tới chặng cuối**.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Đọc tcpdump

- Client: `10.0.2.9:40112` (port tạm). Server: `10.0.1.25:8080`.
- Handshake thành công (`S`, `S.`, `.`), client gửi `POST /api/tasks` 119 byte.
- Server **không trả lời gì trong 30 giây**, rồi gửi `[R.]` — **server (hoặc thứ gì đó đứng ở địa chỉ server) đóng đột ngột** kết nối.
- Hướng điều tra: **phía server**. Khoảng 30 giây trùng với một timeout nào đó: app xử lý quá lâu và bị một tầng cắt (proxy/app server có timeout 30s, hoặc app bị restart/crash giữa chừng, hoặc thread pool cạn kiệt). Xem log app tại thời điểm 10:01:00–10:01:30, log proxy nếu có, và `journalctl`/`dmesg` xem app có bị OOM kill không.

Câu hỏi phụ đáng hỏi lại: client có đứng sau NAT/load balancer không? Nếu có, RST có thể do thiết bị trung gian gửi (idle timeout) — nên bắt thêm gói **ở phía server** để xác nhận.

### Bài 2 — Chẩn đoán từ triệu chứng

| # | Tầng nghi ngờ | Hai lệnh đầu tiên (từ đâu) | Giả thuyết |
|---|---|---|---|
| 1 | DNS | Trên **máy bị lỗi**: `cat /etc/resolv.conf`, `dig api.example.com` (so với `dig @1.1.1.1 api.example.com`) | Máy dùng DNS server khác (VPN, DNS công ty) không biết record; hoặc `/etc/hosts` có dòng sai; hoặc record mới tạo, DNS máy này cache kết quả "không tồn tại" (negative caching) |
| 2 | Firewall / route | Trên **EC2 app**: `ip route get 10.0.11.7`; trên **máy DB**: `sudo ss -tlnp \| grep 5432` | Timeout → gói bị nuốt: Security Group của DB không cho port 5432 từ SG/IP của app, hoặc NACL chặn. Nếu `ss` cho thấy chỉ nghe `127.0.0.1` thì client sẽ nhận **refused**, không phải timeout — nên giả thuyết chính vẫn là firewall |
| 3 | TLS | Từ **máy bất kỳ**: `openssl s_client -connect shop.example.com:443 -servername shop.example.com </dev/null 2>/dev/null \| openssl x509 -noout -dates`, `curl -vI https://shop.example.com` | Chứng chỉ hết hạn: tự động gia hạn (certbot/ACM) thất bại hoặc chưa cấu hình; hoặc đã gia hạn nhưng Nginx chưa reload để nạp cert mới |
| 4 | Proxy ↔ upstream | Trên **máy Nginx**: `sudo tail -20 /var/log/nginx/error.log`, `sudo ss -tlnp \| grep <port app>` | Máy sống, Nginx sống (trả 502), app phía sau chết hoặc nghe sai địa chỉ/port — xác nhận bằng errno trong error log |

### Bài 3 — ICMP bị chặn, dịch vụ vẫn sống

Trước khi thêm luật:

```text
# ping -c 2 172.17.0.2
64 bytes from 172.17.0.2: icmp_seq=1 ttl=64 time=0.05 ms
...
2 packets transmitted, 2 received, 0% packet loss
# curl -s -o /dev/null -w "%{http_code}\n" http://172.17.0.2:8080/
200
```

Sau `iptables -A INPUT -p icmp -j DROP`:

```text
# ping -c 2 -W 1 172.17.0.2
2 packets transmitted, 0 received, 100% packet loss
# curl -s -o /dev/null -w "%{http_code}\n" http://172.17.0.2:8080/
200
```

(IP `172.17.0.2` là minh họa — dùng IP `hostname -I` in ra trên máy bạn.)

Ba câu giải thích mẫu:
1. Ping dùng ICMP, một giao thức riêng không có port; firewall có thể chặn ICMP mà vẫn cho TCP tới port dịch vụ.
2. Ở đây web server vẫn trả `200` trong khi ping mất 100% gói — máy và dịch vụ hoàn toàn bình thường.
3. Muốn biết dịch vụ còn sống, phải kiểm tra **đúng giao thức và port của dịch vụ** (`curl`, `nc -zv`), không dựa vào ping.

### Bài 4 — Runbook

Không có đáp án duy nhất. Đạt khi: đủ 6–7 bước theo đúng thứ tự; mỗi bước có lệnh, ví dụ đầu ra **khi OK** và **khi lỗi** lấy từ lab thật (ví dụ đầu ra `curl: (7) ... Connection refused` từ lab 08 bước 4, dòng `connect() failed (111...)` từ lab 07); ghi rõ "chạy từ đâu"; có mục "khi nào leo thang/hỏi người khác".

### Bài 5 — Câu phỏng vấn có bằng chứng

Đạt khi file `url-journey.md` có output thật cho ít nhất: `dig` (thấy IP và TTL), `ip route get` (thấy gateway và interface), `nc -zv ... 443` (succeeded), `openssl s_client` (thấy subject/issuer, chain, `Verify return code: 0 (ok)`), `curl -v` (thấy request line, `Host`, status, header phản hồi). Phần nói 2 phút đạt khi đi đúng thứ tự DNS → route/NAT → TCP → TLS → HTTP → server-side → response, không bỏ tầng nào, và nêu được ít nhất một lệnh kiểm chứng cho DNS, TCP, TLS.
