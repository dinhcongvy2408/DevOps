# Thuật ngữ Module 02 — Networking

> Mỗi nhóm ghi bài học giải thích kỹ thuật ngữ đó. Thuật ngữ Linux (process, socket file, signal…) xem [glossary Module 01](../01-LINUX/glossary.md).

## Mục lục

- [Mô hình phân tầng (bài 01)](#mô-hình-phân-tầng-bài-01)
- [Địa chỉ IP và subnet (bài 02)](#địa-chỉ-ip-và-subnet-bài-02)
- [DNS và DHCP (bài 03)](#dns-và-dhcp-bài-03)
- [Switching, routing, NAT (bài 04)](#switching-routing-nat-bài-04)
- [TCP, UDP, port, firewall (bài 05)](#tcp-udp-port-firewall-bài-05)
- [HTTP, HTTPS, TLS (bài 06)](#http-https-tls-bài-06)
- [Reverse proxy và load balancing (bài 07)](#reverse-proxy-và-load-balancing-bài-07)
- [Công cụ chẩn đoán (bài 08)](#công-cụ-chẩn-đoán-bài-08)

---

## Mô hình phân tầng (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Layer | Tầng | Nhóm chức năng mạng chỉ giao tiếp với tầng ngay trên và dưới nó. |
| OSI model | Mô hình OSI | Mô hình lý thuyết 7 tầng — nguồn gốc của cách gọi "L4", "L7". |
| TCP/IP model | Mô hình TCP/IP | Mô hình 4 tầng Internet thực sự dùng: Application, Transport, Internet, Link. |
| Protocol | Giao thức | Bộ quy tắc hai bên thống nhất để trao đổi dữ liệu. |
| Encapsulation / Decapsulation | Đóng gói / mở gói | Mỗi tầng thêm (hoặc gỡ) header của mình quanh dữ liệu tầng trên. |
| Header | Phần đầu | Thông tin điều khiển mỗi tầng gắn vào dữ liệu (địa chỉ, port, cờ…). |
| Frame / Packet / Segment | Khung / gói tin / đoạn | Đơn vị dữ liệu ở tầng 2 / 3 / 4 (TCP). |
| MAC address | Địa chỉ MAC | Địa chỉ 48 bit của card mạng, dùng trong một mạng nội bộ. |
| Interface | Giao diện mạng | Một card mạng thật hoặc ảo (`eth0`, `lo`). |
| Loopback (`lo`) | Giao diện vòng lặp | Mạng ảo nội bộ của một máy/container, địa chỉ `127.0.0.1`. |
| MTU | Đơn vị truyền tối đa | Kích thước dữ liệu lớn nhất một frame chở được (Ethernet thường 1500 byte). |
| ICMP | Giao thức thông báo điều khiển Internet | Giao thức tầng 3 cho `ping` và thông báo lỗi; không có port. |
| Bottom-up / Top-down | Từ dưới lên / từ trên xuống | Hai hướng debug theo tầng. |

## Địa chỉ IP và subnet (bài 02)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Bit / Octet | Bit / nhóm 8 bit | IPv4 gồm 4 octet = 32 bit. |
| Network / host portion | Phần mạng / phần host | Phần IP chung của cả mạng / phần phân biệt từng máy. |
| Subnet mask | Mặt nạ mạng con | Dãy 32 bit: bit 1 đánh dấu phần mạng, bit 0 phần host. |
| CIDR | Định tuyến liên miền không phân lớp | Viết mask bằng số bit mạng sau `/`, ví dụ `/24`. |
| Prefix length | Độ dài tiền tố | Con số sau `/`; càng lớn mạng càng nhỏ. |
| Network address | Địa chỉ mạng | Mọi bit host = 0; đại diện cho cả mạng. |
| Broadcast address | Địa chỉ quảng bá | Mọi bit host = 1; gửi tới mọi máy trong mạng. |
| Subnetting | Chia mạng con | Cắt dải lớn thành nhiều dải nhỏ bằng cách tăng prefix. |
| Block size | Kích thước khối | 256 − giá trị mask ở octet đang xét; mạng bắt đầu ở bội số của nó. |
| Overlap | Chồng lấn | Hai dải CIDR có chung ít nhất một địa chỉ. |
| Private IP (RFC 1918) | Địa chỉ riêng | `10/8`, `172.16/12`, `192.168/16` — không định tuyến trên Internet. |
| Public IP | Địa chỉ công cộng | Duy nhất trên Internet; trên AWS, Public IPv4 tính phí theo giờ. |
| Link-local | Liên kết cục bộ | Dải `169.254/16`; AWS dùng `169.254.169.254` cho metadata. |
| CGNAT | NAT cấp nhà mạng | Dải `100.64/10`, nhà mạng chia một IP public cho nhiều khách. |
| Canonical form | Dạng chuẩn | CIDR có network address đúng bội số của khối. |

## DNS và DHCP (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| DNS | Hệ thống tên miền | Cơ sở dữ liệu phân tán ánh xạ tên miền → IP và thông tin khác. |
| Recursive resolver | Máy chủ phân giải đệ quy | Đi hỏi giùm client qua root → TLD → authoritative rồi cache kết quả. |
| Authoritative server | Máy chủ có thẩm quyền | Giữ dữ liệu gốc của một zone. |
| Stub resolver | Bộ phân giải đầu cuối | Thư viện trong OS gửi câu hỏi DNS tới resolver. |
| Zone / zone apex | Vùng / đỉnh vùng | Phần tên miền do một bên quản lý; apex là tên gốc (`example.com`). |
| TLD | Tên miền cấp cao nhất | `.com`, `.vn`… |
| Record (A, AAAA, CNAME, MX, TXT, NS, SOA, PTR) | Bản ghi | IPv4, IPv6, bí danh, mail, văn bản, name server, thông tin zone, tra ngược. |
| Alias record | Bản ghi bí danh (Route 53) | Mở rộng của Route 53, đặt được ở apex, trả thẳng IP của tài nguyên AWS. |
| TTL (DNS) | Thời gian sống của bản ghi | Số giây một câu trả lời được phép nằm trong cache. |
| Negative caching | Cache phủ định | Cache cả câu trả lời "tên không tồn tại". |
| NXDOMAIN / SERVFAIL | Không tồn tại / lỗi máy chủ | Tên không tồn tại / resolver không lấy được câu trả lời hợp lệ. |
| nsswitch.conf | Cấu hình nguồn tra cứu | Thứ tự tra tên: `/etc/hosts` trước, rồi DNS. |
| systemd-resolved | Dịch vụ phân giải systemd | DNS cache cục bộ tại `127.0.0.53` trên Ubuntu server. |
| DNS tunneling (WSL) | Đường hầm DNS | WSL chuyển câu hỏi DNS sang Windows qua cơ chế ảo hóa. |
| Docker embedded DNS | DNS nội bộ Docker | Resolver `127.0.0.11` trong container, phân giải tên service trong cùng network. |
| `extra_hosts` | Dòng hosts bổ sung | Cấu hình Compose ghi thêm dòng vào `/etc/hosts` của container. |
| DHCP / DORA | Cấu hình máy động / 4 bước | Tự cấp IP, mask, gateway, DNS qua Discover–Offer–Request–Acknowledge. |
| Lease | Hợp đồng thuê IP | Thời hạn một IP được cấp qua DHCP. |
| DHCP option set | Bộ tùy chọn DHCP (AWS) | Cấu hình DNS server, domain, NTP cho mọi instance trong VPC. |

## Switching, routing, NAT (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| ARP / ARP cache | Phân giải địa chỉ | Tìm MAC từ IP trong mạng cục bộ; kết quả lưu ở `ip neigh`. |
| MAC address table | Bảng địa chỉ MAC | Switch ghi MAC nào ở cổng nào. |
| Broadcast domain | Miền quảng bá | Tập máy cùng nhận một gói broadcast; router là ranh giới. |
| VLAN | Mạng LAN ảo | Chia một switch thành nhiều broadcast domain tách biệt. |
| Routing table | Bảng định tuyến | Luật "đích thuộc dải X → gửi qua đâu". |
| Default route / gateway | Tuyến / cổng mặc định | `0.0.0.0/0`: mọi đích không khớp luật khác gửi cho router này. |
| Longest prefix match | Khớp tiền tố dài nhất | Nhiều luật cùng khớp thì luật cụ thể nhất thắng. |
| TTL (IP) | Số chặng tối đa | Mỗi router trừ 1; về 0 thì hủy gói và báo ICMP Time Exceeded. |
| Hop | Chặng | Một router trên đường đi của gói. |
| NAT | Biên dịch địa chỉ mạng | Thay IP/port của gói khi đi qua thiết bị biên. |
| SNAT / masquerade | NAT nguồn | Đổi địa chỉ nguồn khi đi ra; masquerade dùng IP hiện tại của card ra. |
| DNAT / port forwarding | NAT đích / chuyển tiếp cổng | Đổi địa chỉ đích khi đi vào, ví dụ Docker `-p 8080:80`. |
| PAT | NAT theo cổng | Nhiều máy dùng chung một IP public, phân biệt bằng port. |
| Conntrack | Theo dõi kết nối | Bảng ghi nhớ kết nối, giúp NAT trả gói về đúng máy và firewall hoạt động stateful. |
| Localhost forwarding / mirrored mode | Chuyển tiếp localhost / chế độ phản chiếu | Hai cách WSL cho Windows truy cập app trong WSL. |
| Internet Gateway | Cổng Internet (AWS) | Cửa ra/vào Internet của VPC, NAT 1-1 cho IP public. |
| NAT Gateway | Cổng NAT (AWS) | Cho private subnet đi ra Internet bằng SNAT; tính phí theo giờ. |
| Public / private subnet | Subnet công khai / riêng | Khác nhau ở việc route table có `0.0.0.0/0 → IGW` hay không. |

## TCP, UDP, port, firewall (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| TCP | Giao thức điều khiển truyền | Có kết nối, đảm bảo dữ liệu đến đủ và đúng thứ tự. |
| UDP | Giao thức gói tin người dùng | Gửi thẳng, không bắt tay, không đảm bảo đến nơi. |
| Port | Cổng | Số 0–65535 chỉ chương trình nào trên máy nhận dữ liệu. |
| Socket | Điểm kết nối | Giao thức + IP + port; kết nối TCP xác định bởi bộ bốn IP/port nguồn và đích. |
| 3-way handshake | Bắt tay 3 bước | SYN → SYN-ACK → ACK để mở kết nối TCP. |
| SYN / ACK / FIN / RST / PSH | Cờ TCP | Mở / xác nhận / đóng lịch sự / đóng đột ngột (từ chối) / đẩy dữ liệu. |
| LISTEN / ESTABLISHED / TIME_WAIT / CLOSE_WAIT | Trạng thái TCP | Đang nghe / đã thiết lập / chờ hết hạn / chờ app đóng — nhiều CLOSE_WAIT là app rò rỉ kết nối. |
| Ephemeral port | Port tạm | Port nguồn kernel tự chọn cho phía client (Linux thường 32768–60999). |
| Bind address | Địa chỉ lắng nghe | `127.0.0.1` chỉ cùng máy vào được; `0.0.0.0` nghe trên mọi địa chỉ. |
| Connection refused / timed out / No route to host | Bị từ chối / hết giờ / không có đường | Ba lỗi kết nối, mỗi lỗi chỉ ra một chỗ hỏng khác nhau. |
| Connect timeout / read timeout | Hết giờ kết nối / hết giờ đọc | Chưa kết nối được / đã kết nối nhưng bên kia trả lời quá chậm. |
| Firewall | Tường lửa | Bộ lọc gói tin theo IP, port, giao thức. |
| Stateful / stateless | Nhớ trạng thái / không nhớ | Tự cho gói trả lời đi qua (Security Group) / xét từng gói riêng (NACL). |
| iptables / chain / table | — / chuỗi luật / bảng luật | Công cụ cấu hình netfilter; luật trong chain INPUT/OUTPUT/FORWARD của bảng filter, nat. |
| DROP / REJECT | Vứt im lặng / từ chối có trả lời | Client thấy timeout / refused hoặc no route. |
| ufw | Firewall đơn giản | Giao diện dễ dùng của Ubuntu, bên dưới vẫn là iptables/nftables. |

## HTTP, HTTPS, TLS (bài 06)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| HTTP request / response | Yêu cầu / phản hồi | Method + path + header + body / status + header + body. |
| Stateless (HTTP) | Không trạng thái | Mỗi request độc lập; muốn nhớ người dùng phải dùng cookie/token. |
| Idempotent | Lũy đẳng | Gọi một hay nhiều lần cho cùng kết quả trên server. |
| Status code | Mã trạng thái | Số 3 chữ số, 5 nhóm 1xx–5xx. |
| Virtual host | Máy chủ ảo | Một IP phục vụ nhiều website, phân biệt bằng header `Host`. |
| Keep-alive | Giữ kết nối | Dùng lại một kết nối TCP cho nhiều request. |
| TTFB | Thời gian tới byte đầu tiên | Từ lúc gửi request tới byte đầu của response — phần lớn là thời gian server xử lý. |
| TLS | Bảo mật tầng giao vận | Mã hóa, toàn vẹn, xác thực server; tên cũ là SSL. |
| ALPN | Thỏa thuận giao thức ứng dụng | Chọn HTTP/2 hay HTTP/1.1 ngay trong TLS handshake. |
| Certificate (X.509) | Chứng chỉ | "Căn cước" website: subject, SAN, issuer, thời hạn, public key. |
| SAN | Tên thay thế của chủ thể | Danh sách tên miền mà chứng chỉ hợp lệ. |
| CA / Root CA / Intermediate CA | Tổ chức cấp chứng chỉ / gốc / trung gian | Các mắt xích của chuỗi tin cậy. |
| Chain of trust | Chuỗi tin cậy | leaf → intermediate → root nằm trong root store. |
| Root store | Kho chứng chỉ gốc | Danh sách root CA máy tin (`/etc/ssl/certs`, gói `ca-certificates`). |
| SNI | Chỉ định tên server | Tên miền gửi trong ClientHello để server chọn đúng chứng chỉ. |
| Self-signed certificate | Chứng chỉ tự ký | Subject trùng issuer; không được tin tự động. |

## Reverse proxy và load balancing (bài 07)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Proxy | Máy chủ trung gian | Nhận request rồi thay mặt gửi request mới — hai kết nối TCP riêng. |
| Forward / reverse proxy | Proxy chiều đi / chiều về | Đứng phía client giấu client / đứng phía server giấu backend. |
| Upstream | Máy chủ phía sau | Server mà proxy chuyển request tới. |
| Server block / default_server | Khối server / server mặc định | Một virtual host của Nginx; request không khớp `server_name` nào rơi vào `default_server`. |
| Location | Khối định tuyến | Cấu hình cho một nhóm đường dẫn URL. |
| TLS termination | Kết thúc TLS | Proxy giải mã HTTPS rồi nói HTTP với backend. |
| X-Forwarded-For / X-Real-IP / X-Forwarded-Proto | Header chuyển tiếp | Báo cho app IP thật của client và scheme gốc. |
| `proxy_connect_timeout` / `proxy_read_timeout` | Hết giờ kết nối / đọc upstream | Hai nguồn khác nhau của lỗi 504. |
| Load balancer | Bộ cân bằng tải | Reverse proxy chia request cho nhiều backend. |
| Round robin / least connections / IP hash | Xoay vòng / ít kết nối nhất / băm IP | Ba thuật toán chọn backend. |
| Health check (passive / active) | Kiểm tra sức khỏe (bị động / chủ động) | Dựa vào lỗi của request thật / gửi request kiểm tra định kỳ. |
| Sticky session | Phiên dính | Giữ một client luôn tới cùng một backend. |
| Stateless app | Ứng dụng không trạng thái | Không lưu phiên trong RAM, nên mọi instance tương đương. |
| L4 / L7 load balancer | Cân bằng tải tầng 4 / tầng 7 | Quyết định theo IP:port / theo nội dung HTTP. |
| 502 / 504 | Bad Gateway / Gateway Timeout | Proxy không nhận được phản hồi hợp lệ / chờ upstream quá hạn. |
| Graceful reload | Nạp lại nhẹ nhàng | Đọc lại cấu hình (SIGHUP) mà không rớt kết nối. |

## Công cụ chẩn đoán (bài 08)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| RTT | Thời gian khứ hồi | Thời gian gói đi và phản hồi quay về. |
| Packet loss | Mất gói | Tỉ lệ gói gửi đi không nhận được trả lời. |
| Jitter (mdev) | Độ dao động độ trễ | Mức chênh lệch RTT giữa các gói. |
| Packet capture (pcap) | Bắt gói tin | Ghi lại gói tin thật để phân tích (`tcpdump -w`). |
| net-tools / iproute2 | Bộ lệnh mạng cũ / mới | `netstat`, `ifconfig`, `route` so với `ss`, `ip`. |
| Runbook | Sổ tay vận hành | Các bước xử lý một loại sự cố, viết sẵn theo thứ tự. |
