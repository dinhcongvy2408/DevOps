# Lời giải — Bài 04: Routing, NAT và Switching

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [04-routing-nat-switching.md](../04-routing-nat-switching.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Switch làm việc ở tầng 2 với MAC, nối các máy trong **cùng một mạng**. Router làm việc ở tầng 3 với IP, nối **các mạng khác nhau** và chọn đường. Router Wi-Fi nhà kiêm: switch (cổng LAN + Wi-Fi), router, NAT/PAT, DHCP server, DNS forwarder, firewall cơ bản.

**2.** So IP đích với mạng của chính máy (IP + subnet mask/CIDR). Cùng mạng → gửi thẳng (ARP tìm MAC đích). Khác mạng → tra bảng định tuyến, gửi cho gateway phù hợp (thường là default gateway).

**3.** MAC đích là MAC của **default gateway**. `8.8.8.8` không cùng mạng nên máy chỉ cần giao gói tin cho router chặng đầu; IP đích vẫn là `8.8.8.8` suốt hành trình, còn MAC thay đổi ở mỗi chặng.

**4.** ARP tìm MAC từ IP trong mạng cục bộ. Request phải broadcast vì người hỏi **chưa biết MAC** của máy cần tìm — chỉ có cách hỏi tất cả.

**5.** Broadcast domain là tập các máy cùng nhận được một gói broadcast tầng 2. Router **không chuyển tiếp** broadcast sang mạng khác — đó là ranh giới của broadcast domain.

**6.** Default route là luật dùng khi không luật nào cụ thể hơn khớp. `0.0.0.0/0` có prefix dài 0 bit → khớp mọi địa chỉ IPv4, và vì ngắn nhất nên luôn thua mọi luật khác theo longest prefix match.

**7.** `10.0.8.0/22` bao phủ `10.0.8.0`–`10.0.11.255`.
- `10.0.9.5` → khớp `/16`, `/22`, `/0` → thắng `/22` → **vpn**.
- `10.0.12.5` → nằm ngoài `/22` (vượt `10.0.11.255`) → khớp `/16`, `/0` → **local**.
- `52.1.1.1` → chỉ khớp `/0` → **igw**.

**8.** Dựa vào TTL của gói IP: mỗi router giảm TTL đi 1, về 0 thì hủy gói và gửi ICMP Time Exceeded về. traceroute gửi gói với TTL = 1, 2, 3… để từng router lần lượt "lộ diện". `* * *` chỉ có nghĩa là router đó không trả lời trong thời gian chờ (thường do chính sách chặn ICMP); nếu các chặng sau vẫn có kết quả thì đường đi vẫn thông.

**9.** SNAT đổi **địa chỉ nguồn** khi đi ra (laptop `192.168.1.25` ra Internet thành IP public của router; container ra Internet thành IP của host). DNAT đổi **địa chỉ đích** khi đi vào (port forwarding trên router; Docker `-p 8080:80` chuyển `host:8080` → `container:80`).

**10.** PAT cho nhiều máy dùng chung một IP public, phân biệt từng kết nối bằng **port nguồn** đã được router đổi và ghi vào bảng conntrack. Gói trả về đến đúng port đó → router tra bảng để biết trả cho máy nào.

**11.** NAT chỉ dịch địa chỉ; việc khó kết nối từ ngoài vào là **tác dụng phụ** (thiếu luật DNAT thì router không biết chuyển cho ai). NAT không kiểm tra nội dung, không chặn theo chính sách; khi có luật DNAT/port forwarding thì mọi gói khớp đều đi vào. Kiểm soát truy cập phải dùng firewall/Security Group.

**12.** Localhost forwarding (`localhostForwarding=true` mặc định) chuyển `localhost:port` **trên Windows** vào WSL — chỉ áp dụng cho truy cập từ chính máy Windows. Điện thoại kết nối tới IP Wi-Fi của Windows; ở chế độ NAT, Windows không tự chuyển traffic đó vào WSL → cần `netsh interface portproxy` hoặc mirrored mode.

**13.** Internet Gateway: cửa ra/vào Internet của VPC, NAT 1-1 giữa IP private và IP public của instance, cho phép cả chiều ra và chiều vào (nếu Security Group cho phép), **không tính phí theo giờ**. NAT Gateway: cho instance **không có IP public** đi ra Internet bằng SNAT/PAT, **không cho** Internet khởi tạo kết nối vào, **tính phí theo giờ** cộng phí dữ liệu xử lý.

**14.** Khác nhau duy nhất ở **route table**: public subnet có route `0.0.0.0/0 → Internet Gateway`. Instance trong private subnet có IP public **vẫn không ra Internet được** — theo tài liệu AWS, không có route tới IGW thì không giao tiếp với Internet được dù có IP public.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Route table của VPC

**(a)** `10.20.1.0/24` (RT-A, có `0.0.0.0/0 → igw-111`) là **public**. `10.20.11.0/24` (RT-B, default route tới NAT) là **private**.

**(b)** Instance `10.20.11.8` dùng RT-B:
- `10.20.1.15` → khớp `10.20.0.0/16` và `0.0.0.0/0` → thắng `local` → đi thẳng trong VPC.
- `10.30.4.4` → khớp `10.30.0.0/16` (`pcx-222`) và `0.0.0.0/0` → thắng `pcx-222` → qua VPC peering.
- `140.82.112.3` → chỉ khớp `0.0.0.0/0` → `nat-333`. NAT Gateway (trong subnet public) SNAT rồi gửi tiếp qua route của **subnet chứa nó** (RT-A) → `igw-111` → Internet.

**(c)** Không. Instance không có IP public, subnet không có route tới IGW, và NAT Gateway chỉ cho phép kết nối **khởi tạo từ bên trong**. Không có thiết bị nào thực hiện DNAT từ Internet vào `10.20.11.8`.

**(d)** Còn: nói chuyện với mọi máy trong VPC (`local`) và với VPC `10.30.0.0/16` qua peering. Mất: mọi kết nối ra Internet — `apt update`, tải image, gọi API bên ngoài, gửi backup lên S3 qua endpoint public (trừ khi có VPC endpoint cho S3). Gói tin tới đích không khớp luật nào bị bỏ.

**(e)** IP public (Elastic IP) của **NAT Gateway** `nat-333`, không phải `10.20.11.8`.

### Bài 2 — Longest prefix match bằng tay

| Đích | Luật khớp | Thắng | Ra card / gateway |
|---|---|---|---|
| `10.42.3.7` | `default`, `10.0.0.0/8`, `10.42.0.0/16` | `/16` | `docker0`, trực tiếp |
| `10.1.2.3` | `default`, `10.0.0.0/8` | `/8` | `tun0` qua `10.8.0.1` (VPN) |
| `192.168.1.77` | `default`, `192.168.1.0/24` | `/24` | `wlan0`, trực tiếp |
| `1.1.1.1` | `default` | `/0` | `wlan0` qua `192.168.1.1` |
| `10.42.0.0` | `default`, `/8`, `/16` | `/16` | `docker0` (đây là địa chỉ mạng của dải Docker) |

Tình huống VPN: server công ty `10.42.5.10` khớp `10.42.0.0/16` của Docker (dài hơn `/8` của VPN) → gói tin bị gửi vào **docker0** thay vì VPN → không bao giờ tới server. Đây chính là xung đột dải IP ở Ví dụ 3. Cách xử lý: đổi dải mạng của Docker sang dải không trùng (cấu hình Docker — Module 04), hoặc yêu cầu VPN đẩy route cụ thể hơn. Bài học khi thiết kế: chọn dải IP không trùng với mạng công ty, VPN, các VPC khác.

### Bài 3 — Đọc traceroute

- Hop 1 `10.0.1.1`: gateway của subnet (ví dụ router của VPC hoặc router văn phòng) — trả lời bình thường.
- Hop 2 `100.66.8.17`: dải `100.64.0.0/10` → thiết bị NAT/CGNAT hoặc mạng nội bộ của nhà cung cấp.
- Từ hop 3 trở đi **toàn bộ** `* * *` cho tới hop 30, đích không bao giờ tới.

Kết luận hợp lý: gói tin đi được tới hop 2, sau đó **hoặc** bị chặn/bỏ, **hoặc** các chặng sau không trả lời ICMP *và* đích cũng không trả lời probe UDP. Chưa đủ để kết luận "mạng đứt ở hop 3".

Cần thu thập thêm:
- Thử giao thức khác: `sudo traceroute -T -p 443 -n <đích>` (TCP thường xuyên qua firewall dễ hơn), `sudo traceroute -I -n <đích>`.
- Kiểm tra kết nối ở tầng ứng dụng: `curl -v https://<đích>` hoặc `nc -vz <đích> 443` (bài 05) — có thể traceroute bị chặn nhưng kết nối thật vẫn được.
- Thử tới đích khác (`8.8.8.8`) để biết vấn đề chung hay riêng đích này.
- Xem route table/firewall/Security Group/NACL của phía mình (đường đi) và phía đích.

### Bài 4 — Bảng NAT

Router đổi port nguồn để hai kết nối không trùng nhau (port cụ thể do router chọn, đây là ví dụ):

| Bên trong (private) | Bên ngoài (sau NAT) | Đích |
|---|---|---|
| `192.168.1.25:51000` | `113.22.10.5:62001` | `140.82.112.3:443` |
| `192.168.1.40:51000` | `113.22.10.5:62002` | `140.82.112.3:443` |

Server trả lời về `113.22.10.5:62001` hoặc `:62002`. Router tra bảng theo **port đích của gói trả về** (cùng với IP/port của server) → đổi đích về đúng `192.168.1.25:51000` hoặc `192.168.1.40:51000`. Vì cả hai laptop dùng cùng port nguồn `51000`, nếu router **không** đổi port thì hai kết nối sẽ trùng nhau hoàn toàn từ góc nhìn của server — đó là lý do PAT phải đổi port.

### Bài 5 — Thiết kế cho taskhub

Không có đáp án duy nhất. Đạt khi nêu được những việc không làm được, ví dụ:
- `apt update`/cài package, cập nhật bảo mật.
- Gửi backup lên S3 qua endpoint public; gửi log/metric ra dịch vụ bên ngoài.
- Đăng nhập bằng SSM Session Manager cũng cần đường tới endpoint của dịch vụ (trừ khi có VPC endpoint) — điểm cộng nếu bạn đoán được.

Và các hướng giải quyết đã đoán (Module 06 sẽ phân tích đúng sai):
- Thêm NAT Gateway (dễ, tốn phí theo giờ).
- **VPC endpoint** — gateway endpoint cho S3 (theo tài liệu AWS trong ví dụ kiến trúc tham chiếu, S3 Gateway endpoint không mất phí), interface endpoint cho các dịch vụ khác (có phí).
- Chuẩn bị sẵn AMI/image có đủ package; cập nhật bằng cách thay instance mới.
- Tạm thời gắn route ra Internet khi cần bảo trì (rủi ro, nên tránh).
- Không tách DB ra EC2 riêng ở giai đoạn đầu — chạy cùng EC2 bằng Docker Compose như dự án v2 (đơn giản, rẻ, đánh đổi về tách biệt).

### Bài 6 — Câu hỏi phỏng vấn (phần routing)

Thứ tự hợp lý:
1. Instance đang **running** và vượt qua status check chưa? IP public đang dùng có đúng không (IP public tự động đổi khi stop/start, trừ khi dùng Elastic IP)?
2. **Route table** của subnet chứa instance có `0.0.0.0/0 → igw-...` không? Không có → đây là private subnet, IP public vô dụng.
3. VPC có **Internet Gateway được gắn** (attached) không?
4. (Phần bài 05) Security Group, **Network ACL** (stateless — phải cho phép cả chiều về với dải port tạm thời), firewall trên chính OS (`ufw`), `sshd` có đang chạy và nghe port 22 không.
5. Phía bạn: mạng công ty có chặn port 22 ra ngoài không? IP public của bạn (`curl https://checkip.amazonaws.com`) có đúng là IP đã khai báo trong Security Group không — nhất là khi có CGNAT/VPN, IP thật có thể khác bạn nghĩ.

Điểm cộng: nhắc tới **VPC Reachability Analyzer** của AWS (được giới thiệu trong tài liệu ví dụ kiến trúc VPC) để kiểm tra route table và Security Group tự động.
