# Lời giải — Bài 05: TCP, UDP, port và firewall

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [05-tcp-udp-ports-firewall.md](../05-tcp-udp-ports-firewall.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Vì sao HTTP/SSH/PostgreSQL dùng TCP, DNS dùng UDP?**
HTTP, SSH, SQL cần dữ liệu đến **đủ và đúng thứ tự** — mất một byte là hỏng cả trang web hoặc câu lệnh SQL. TCP đảm bảo điều đó. Truy vấn DNS thường rất nhỏ (một gói hỏi, một gói trả lời). Dùng UDP tránh được chi phí bắt tay 3 bước, nhanh hơn; nếu mất gói thì client chỉ cần hỏi lại. DNS chuyển sang TCP khi câu trả lời quá lớn hoặc khi các DNS server đồng bộ dữ liệu với nhau.

**2. Handshake và timeout/refused.**
SYN → SYN-ACK → ACK. Khi **timeout**: client gửi SYN nhưng không bao giờ nhận được SYN-ACK (hay bất kỳ phản hồi nào) — gói SYN bị vứt dọc đường hoặc máy đích không tồn tại. Khi **refused**: server (kernel của nó) trả về gói **RST** thay cho SYN-ACK, vì không có socket nào nghe trên địa chỉ:port đó (hoặc firewall REJECT bằng RST/ICMP port unreachable).

**3. Một port, 10.000 client?**
Kết nối TCP được xác định bởi bộ bốn (IP nguồn, port nguồn, IP đích, port đích). Phía server, IP đích và port đích giống nhau, nhưng mỗi client có IP nguồn hoặc port nguồn khác nhau → 10.000 bộ bốn khác nhau = 10.000 kết nối riêng biệt. Socket `LISTEN` chỉ là "cửa nhận", mỗi kết nối được chấp nhận sẽ có socket riêng.

**4. TIME_WAIT vs CLOSE_WAIT.**
`TIME_WAIT`: bên **đóng trước** chờ một khoảng ngắn để chắc chắn gói cuối đã tới và không lẫn gói cũ vào kết nối mới — hoàn toàn bình thường. `CLOSE_WAIT`: bên kia đã đóng, nhưng **ứng dụng bên này chưa gọi close()**. `CLOSE_WAIT` đáng lo hơn: nếu số lượng tăng mãi, ứng dụng đang rò rỉ kết nối, cuối cùng sẽ cạn file descriptor (`Too many open files`). Đây là lỗi code/cấu hình connection pool, không phải lỗi mạng.

**5. Ephemeral port và Network ACL.**
Ephemeral port là port nguồn tạm thời kernel tự chọn khi client mở kết nối ra ngoài (Linux mặc định thường 32768–60999). NACL là stateless: nó không biết gói trả lời thuộc kết nối đã được phép. Gói trả lời của server đi tới **ephemeral port của client**, nên NACL phải có luật outbound (phía server) / inbound (phía client) cho dải port này, nếu không traffic trả về bị chặn.

**6. App nghe `127.0.0.1:8080`.**
Chỉ process trên **cùng máy** (cùng network namespace) truy cập được qua `127.0.0.1` / `localhost`. Máy khác, container khác, kể cả kết nối tới chính IP `eth0` của máy đó đều bị refused. Nếu app chạy **trong container**: loopback là của **riêng container**, nên ngay cả máy host với `docker run -p 8080:8080` cũng không vào được — traffic từ host đi vào container qua `eth0` của container.

**7. Khi nào nên nghe `127.0.0.1`?**
Khi dịch vụ chỉ phục vụ các process khác trên cùng máy: app Spring Boot đứng sau Nginx trên **cùng** server; PostgreSQL chỉ app cùng máy dùng; trang quản trị/metrics chỉ truy cập qua SSH tunnel. Lợi ích: kể cả khi firewall/Security Group bị cấu hình sai, dịch vụ vẫn không lộ ra ngoài (phòng thủ nhiều lớp — defense in depth).

**8. Refused vs timed out.**

| | Refused | Timed out |
|---|---|---|
| Nguyên nhân | Đến được máy đích, nhưng không ai nghe port/địa chỉ đó; hoặc firewall REJECT | Gói tin bị vứt im lặng (firewall/SG/NACL DROP), máy đích tắt, sai IP, sai route |
| Thời gian | Ngay lập tức | Chờ hết thời gian chờ |
| Kiểm tra tiếp | Phía server: `ss -tlnp`, trạng thái dịch vụ | Các lớp firewall, Security Group, NACL, route |

**9. Hai tình huống cùng ra refused.**
(a) Dịch vụ đã dừng — không có process nghe port. (b) Dịch vụ đang chạy nhưng nghe `127.0.0.1`, client kết nối qua IP khác. Ngoài ra còn (c) firewall REJECT. Phân biệt bằng cách sang phía server chạy `sudo ss -tlnp | grep <port>`: không có dòng nào → (a); có dòng `127.0.0.1:<port>` → (b); có dòng `0.0.0.0:<port>` nhưng vẫn refused từ ngoài → nghi (c), xem `iptables -L -n -v`.

**10. DROP vs REJECT.**
DROP: client không nhận được gì → gửi lại và cuối cùng báo timeout (chậm). REJECT: client nhận ngay thông báo từ chối → refused hoặc no route (nhanh). Firewall hướng Internet hay dùng DROP vì: không tiết lộ cho kẻ dò quét rằng có máy tồn tại ở đó; không tốn tài nguyên gửi phản hồi cho lượng lớn traffic rác; làm chậm công cụ quét port.

**11. Stateful vs stateless.**
Stateful nhớ các kết nối đã được phép và tự cho gói trả lời đi qua; chỉ cần viết luật cho chiều khởi tạo. Stateless xét từng gói độc lập; phải viết luật cho cả hai chiều. Security Group: **stateful**. Network ACL: **stateless**.

**12. Connect timed out vs read timed out.**
`Connect timed out`: chưa thiết lập được kết nối TCP → kiểm tra firewall/SG/NACL/route, máy đích có sống không. `Read timed out`: kết nối **đã** thành công, request đã gửi, nhưng dịch vụ đích trả lời quá chậm → kiểm tra hiệu năng dịch vụ đích (CPU, DB chậm, query nặng, thread bị treo), timeout cấu hình có quá ngắn không. Mạng gần như chắc chắn không phải nguyên nhân.

**13. Vì sao không mở 22, 5432, 2375 ra `0.0.0.0/0`?**
Bot quét toàn bộ Internet liên tục. Port 22 sẽ bị dò mật khẩu/khai thác lỗ hổng SSH ngay lập tức; chỉ nên mở cho IP cụ thể hoặc dùng SSM thay thế. 5432: database không bao giờ cần truy cập trực tiếp từ Internet, lộ ra là mời tấn công dò mật khẩu và khai thác lỗ hổng. 2375: Docker API không mã hóa, không xác thực — ai kết nối được là chạy được container với quyền root trên máy chủ.

**14. Port mặc định.**
SSH 22, DNS 53, HTTPS 443, PostgreSQL 5432, Redis 6379, Spring Boot 8080, Prometheus 9090, Grafana 3000.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Kiểm kê port

Kết quả phụ thuộc máy bạn. Một bảng đạt yêu cầu trông như sau (minh họa):

| Proto | Bind address:port | Process | Cần mở ra ngoài? | Lý do |
|---|---|---|---|---|
| tcp | `127.0.0.53%lo:53` | systemd-resolved | Không | DNS cache chỉ phục vụ máy cục bộ — đã nghe loopback, đúng |
| udp | `127.0.0.53%lo:53` | systemd-resolved | Không | Như trên, DNS dùng cả UDP |
| tcp | `0.0.0.0:8002` | python3 | Không (chỉ để thử) | Lẽ ra nên nghe `127.0.0.1` nếu chỉ thử cục bộ |
| tcp | `127.0.0.1:5432` | postgres (nếu bạn có cài) | Không | Database chỉ cho máy cục bộ |

Tiêu chí: đọc đúng bind address, gắn đúng process, có lý do cho từng quyết định. Nếu không có cột Process, bạn đã quên `sudo`.

### Bài 2 — Đọc bối cảnh

**(1) `UnknownHostException: postgres`** — lỗi **DNS**. Tên `postgres` không phân giải được. Hay gặp khi app chạy ngoài Docker network nhưng cấu hình dùng tên service của Docker Compose, hoặc gõ sai tên. Lệnh: `getent hosts postgres`, `cat /etc/hosts` / `cat /etc/resolv.conf` (hoặc `dig postgres`).

**(2) `ConnectException: Connection refused ... 10.0.11.20:5432`** — **refused**: đã tới được máy `10.0.11.20`, mạng thông, nhưng không có gì nghe 5432 trên địa chỉ đó. Nghi: PostgreSQL chưa chạy/đã chết, hoặc `listen_addresses = 'localhost'`. Lệnh (trên máy DB): `sudo ss -tlnp | grep 5432`, `systemctl status postgresql`.

**(3) `curl: (7) ... after 130204 ms: Connection timed out`** — **timeout** (130 giây = hệ điều hành tự bỏ cuộc vì không đặt `--connect-timeout`). Gói tin bị vứt im lặng. Trên AWS: Security Group chưa mở 443, NACL, instance chưa chạy, sai IP. Lệnh: kiểm tra luật inbound Security Group của instance; `nc -zv -w 3 13.250.10.4 443`; từ chính instance: `sudo ss -tlnp | grep 443` và `curl -I localhost`.

**(4) `SocketTimeoutException: Read timed out ... payment-service:8080`** — **read timeout**: DNS ổn, kết nối TCP **đã thành công**, nhưng `payment-service` trả lời quá chậm. Không phải firewall. Lệnh: xem log/metrics của `payment-service` (CPU, thời gian xử lý, DB), `curl -w '%{time_total}\n' -o /dev/null -s http://payment-service:8080/...` để đo; kiểm tra cấu hình read timeout của client có hợp lý không.

### Bài 3 — Script đếm trạng thái TCP

```bash
#!/usr/bin/env bash
# tcp-states.sh — đếm kết nối TCP theo trạng thái, cảnh báo khi CLOSE-WAIT quá ngưỡng
set -euo pipefail

THRESHOLD="${CLOSE_WAIT_THRESHOLD:-100}"

# NR>1 bỏ dòng tiêu đề; cột 1 của "ss -tan" là trạng thái
ss -tan | awk 'NR > 1 { count[$1]++ } END { for (s in count) printf "%-12s %d\n", s, count[s] }' | sort

close_wait=$(ss -tan | awk 'NR > 1 && $1 == "CLOSE-WAIT"' | wc -l)

if (( close_wait > THRESHOLD )); then
  echo "WARN: CLOSE-WAIT=${close_wait} vượt ngưỡng ${THRESHOLD}" >&2
  exit 1
fi
echo "OK: CLOSE-WAIT=${close_wait} (ngưỡng ${THRESHOLD})"
```

Chạy thử: `CLOSE_WAIT_THRESHOLD=0 ./tcp-states.sh; echo $?`. Lưu ý `ss -tan` in trạng thái dạng `ESTAB`, `TIME-WAIT`, `CLOSE-WAIT` (có gạch nối, viết tắt), khác với tên trong tài liệu TCP (`ESTABLISHED`, `TIME_WAIT`). Lỗi hay gặp: so sánh với `CLOSE_WAIT` (gạch dưới) → luôn ra 0.

### Bài 4 — Firewall stateful trong sandbox

```bash
# Trong: docker run --rm -it --cap-add=NET_ADMIN ubuntu:22.04 bash  (đã cài iptables, curl, python3)
python3 -m http.server 9000 --bind 0.0.0.0 >/dev/null 2>&1 &

iptables -A INPUT -i lo -j ACCEPT                                        # 1. cho phép loopback
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT   # 2. gói trả lời của kết nối đã có
iptables -A INPUT -p tcp --dport 9000 -j ACCEPT                          # 3. dịch vụ cần mở
iptables -P INPUT DROP                                                   # 4. còn lại: chặn

iptables -L INPUT -n -v --line-numbers
curl -sI https://example.com | head -1          # ra ngoài vẫn được
curl -s "http://$(hostname -I | awk '{print $1}'):9000/" >/dev/null && echo "9000 OK"
```

**Vì sao thiếu luật conntrack (luật 2) thì `curl` ra ngoài hỏng?** Khi container gọi `example.com`, gói **trả lời** (SYN-ACK từ example.com tới ephemeral port của container, và gói trả lời DNS qua UDP) đi vào chain `INPUT`. Không có luật nào cho phép → rơi vào policy `DROP` → DNS không phân giải được (`Could not resolve host` sau khi chờ) hoặc kết nối timeout. Luật conntrack biến iptables thành firewall **stateful**: "gói thuộc kết nối do mình khởi tạo thì cho vào". Đây chính là điều Security Group làm tự động.

Luật 4 đặt **cuối cùng** là có chủ đích: nếu đổi policy sang `DROP` trước khi có các luật cho phép trên một máy đang SSH vào, bạn tự khóa mình ở ngoài.

### Bài 5 — Port bị chiếm

Lỗi ở terminal thứ hai (minh họa):

```text
OSError: [Errno 98] Address already in use
```

`Errno 98` = `EADDRINUSE`. Spring Boot báo tương tự: `Web server failed to start. Port 8080 was already in use.`

Tìm và dừng chỉ bằng `ss` và `kill`:

```bash
ss -tlnp 'sport = :8080'
```

```text
State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
LISTEN 0      5            0.0.0.0:8080      0.0.0.0:*     users:(("python3",pid=3310,fd=3))
```

```bash
kill 3310                       # SIGTERM — cho process tắt nhẹ nhàng (Linux bài 04)
sleep 1; ss -tlnp 'sport = :8080'   # không còn dòng LISTEN → port đã được giải phóng
# Chỉ khi process không chịu tắt: kill -9 3310
```

Nếu process thuộc user khác, cột Process trống → thêm `sudo` cho `ss` và `kill`.

Mục nhật ký đạt yêu cầu khi có: triệu chứng (thông báo lỗi nguyên văn), giả thuyết ("port đã bị process khác chiếm"), lệnh kiểm tra và kết quả, nguyên nhân gốc (bản chạy trước chưa tắt), cách sửa, cách phòng ngừa (dừng bằng `systemctl stop` hoặc `Ctrl+C` đúng cách; không chạy app bằng `&` rồi quên).
