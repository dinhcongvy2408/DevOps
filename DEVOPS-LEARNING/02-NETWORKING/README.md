# Module 02 — Networking Fundamentals

> Tuần 4–5 · ~32 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 01 — Linux](../01-LINUX/README.md)

## Mục lục

- [1. Vì sao DevOps phải giỏi mạng?](#1-vì-sao-devops-phải-giỏi-mạng)
- [2. DevOps cần biết mạng đến mức nào?](#2-devops-cần-biết-mạng-đến-mức-nào)
- [3. Môi trường thực hành](#3-môi-trường-thực-hành)
- [4. Thứ tự bài học](#4-thứ-tự-bài-học)
- [5. Lab bắt buộc và break-fix](#5-lab-bắt-buộc-và-break-fix)
- [6. Mạng trong các module sau](#6-mạng-trong-các-module-sau)
- [7. Checklist hoàn thành module](#7-checklist-hoàn-thành-module)
- [8. Nguồn học](#8-nguồn-học)

---

## 1. Vì sao DevOps phải giỏi mạng?

Phần lớn sự cố "app không chạy" mà DevOps nhận được **thực chất là sự cố mạng**:

| Triệu chứng người khác báo | Nguyên nhân thật thường gặp | Bài học |
|---|---|---|
| "Web không vào được" | DNS sai, firewall chặn, app chỉ nghe trên `127.0.0.1` | 03, 05 |
| "App không kết nối được database" | Sai host/port, Security Group chưa mở, khác mạng Docker | 05, 04 |
| "Trang trả về 502 Bad Gateway" | Reverse proxy không nói chuyện được với app phía sau | 06, 07 |
| "Server trong private subnet không tải được package" | Không có đường ra Internet (thiếu NAT) | 04 |
| "Chỗ tôi chạy được, chỗ anh ấy thì không" | DNS cache, `/etc/hosts`, khác mạng | 03 |
| "Chứng chỉ báo lỗi" | Cert hết hạn, sai tên miền, thiếu chain | 06 |

Không hiểu mạng, bạn sẽ không hiểu được **AWS VPC, Docker network, Kubernetes Service, Load Balancer** — những thứ chiếm phần lớn công việc ở các module sau.

---

## 2. DevOps cần biết mạng đến mức nào?

DevOps **không phải** Network Engineer. Bạn không cần cấu hình router Cisco hay thiết kế mạng doanh nghiệp. Bạn cần **đủ để thiết kế mạng cloud đơn giản và debug được kết nối giữa các dịch vụ**.

| Chủ đề | Mức cần cho Junior DevOps | Không cần (để Network Engineer) |
|---|---|---|
| OSI / TCP-IP | 🟥 Xếp được một lỗi vào đúng tầng; biết công cụ/dịch vụ nào hoạt động ở tầng nào | Thuộc lòng chi tiết từng tầng theo sách CCNA |
| IPv4, CIDR, subnet | 🟥 **Tự tính bằng tay** dải IP, số địa chỉ; chia VPC thành subnet không chồng lấn | VLSM phức tạp, tính toán supernetting cho mạng lớn |
| Public / private IP | 🟥 Biết dải private, biết khi nào cần public IP | — |
| DNS | 🟥 Hiểu quá trình phân giải, record A/CNAME/TXT, TTL; debug bằng `dig` | Vận hành DNS server riêng (BIND) |
| DHCP | 🟨 Hiểu khái niệm và quá trình cấp IP | Cấu hình DHCP server |
| Routing | 🟥 Đọc bảng route, hiểu default gateway, đi theo được đường gói tin trong VPC | Giao thức định tuyến động (OSPF, BGP) |
| Switching, VLAN | 🟨 Hiểu MAC, ARP, khác biệt tầng 2 và tầng 3 | Cấu hình switch, STP, VLAN trunking |
| NAT | 🟥 Hiểu SNAT/DNAT; giải thích được NAT Gateway và Docker port publish | — |
| TCP / UDP, port | 🟥 Handshake, trạng thái kết nối, phân biệt **refused / timeout / no route** | Tinh chỉnh TCP stack |
| HTTP / HTTPS | 🟥 Đọc request/response, ý nghĩa status code trong bối cảnh proxy | — |
| TLS | 🟥 Chứng chỉ, CA, chain, SNI, hạn dùng; debug bằng `openssl` | Toán học mật mã |
| Firewall | 🟥 Stateful vs stateless; tư duy Security Group | Viết luật iptables phức tạp cho router |
| Load balancer, reverse proxy | 🟥 Cấu hình Nginx reverse proxy + load balancing; phân biệt L4/L7 | — |
| `tcpdump` | 🟨 Bắt và đọc được gói tin cơ bản | Phân tích sâu bằng Wireshark |
| IPv6 | 🟦 Nhận biết địa chỉ, biết nó tồn tại | Thiết kế mạng IPv6 |

**Quy tắc vàng:** học đến mức **giải thích được luồng đi của một request** từ trình duyệt đến database và **chỉ ra được nó có thể hỏng ở đâu**.

---

## 3. Môi trường thực hành

| Nhãn | Môi trường | Dùng cho |
|---|---|---|
| `[WSL]` | Ubuntu 24.04 trên WSL | Phần lớn lệnh, lab Nginx |
| `[Sandbox]` | Container dùng xong bỏ | Thử firewall (cần `--cap-add=NET_ADMIN`), thử lệnh có thể làm hỏng mạng |
| `[Lab Compose]` | Nhiều container nối với nhau bằng Docker Compose | Mô phỏng nhiều "máy" trong một mạng — dùng cho break-fix và checkpoint |
| `[PowerShell]` | Windows | So sánh cấu hình mạng Windows với WSL |

> Bạn **chưa cần hiểu Docker** để làm các lab `[Lab Compose]`: chỉ chạy đúng các lệnh `docker compose ...` được hướng dẫn. Module 04 sẽ giải thích chi tiết. Hãy coi mỗi container là một "máy tính nhỏ" có IP riêng.

**Mạng của WSL khác server thật:** mặc định WSL2 dùng chế độ NAT — WSL có IP riêng nằm sau Windows. Bài 04 giải thích chi tiết. Những gì cần mạng "thật" (Security Group, IP public) sẽ được làm lại trên EC2 ở tuần 11–12.

Một số công cụ cần cài thêm trong WSL (mỗi bài sẽ nhắc, **bạn tự quyết định cài**): `dnsutils` (dig, nslookup), `traceroute`, `tcpdump`, `netcat-openbsd`, `nginx`.

---

## 4. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 01 | [Mô hình OSI và TCP/IP](01-osi-tcpip-model.md) | 4 | 3h | 🟥 |
| 02 | [IPv4, subnet mask, CIDR](02-ipv4-subnet-cidr.md) | 4 | 4h | 🟥 |
| 03 | [DNS và DHCP](03-dns-dhcp.md) | 4 | 3h | 🟥 |
| 04 | [Routing, NAT và switching](04-routing-nat-switching.md) | 4 | 3h | 🟥 |
| 05 | [TCP, UDP, port và firewall](05-tcp-udp-ports-firewall.md) | 5 | 4h | 🟥 |
| 06 | [HTTP, HTTPS và TLS](06-http-https-tls.md) | 5 | 4h | 🟥 |
| 07 | [Load balancing và reverse proxy](07-load-balancing-reverse-proxy.md) | 5 | 3h | 🟥 |
| 08 | [Bộ công cụ chẩn đoán mạng](08-network-troubleshooting-tools.md) | 5 | 3h | 🟥 |

Mỗi công cụ được dạy sâu ở bài có khái niệm liên quan (ví dụ `dig` ở bài 03, `ss` ở bài 05, `curl` và `openssl` ở bài 06). Bài 08 tổng hợp chúng thành **một quy trình debug theo tầng** và dạy thêm `tcpdump`.

---

## 5. Lab bắt buộc và break-fix

| Lab | Tuần | Mô tả |
|---|---|---|
| Thiết kế bảng IP cho VPC | 4 | Trong [bài 02](02-ipv4-subnet-cidr.md#9-bài-thực-hành-từng-bước) — kết quả dùng cho `docs/network-plan.md` của dự án và VPC thật ở tuần 11 |
| Truy vết DNS với `dig +trace` | 4 | Trong [bài 03](03-dns-dhcp.md#9-bài-thực-hành-từng-bước) |
| Nginx reverse proxy + load balancing | 5 | Trong [bài 07](07-load-balancing-reverse-proxy.md#9-bài-thực-hành-từng-bước) — kết quả dùng cho `docs/experiments/` của dự án |
| Bắt gói tin HTTP bằng `tcpdump` | 5 | Trong [bài 08](08-network-troubleshooting-tools.md#9-bài-thực-hành-từng-bước) |
| [Break-fix Network #1](labs/break-fix-01/README.md) | 5 | Hệ thống nhiều container có lỗi mạng cài sẵn |

Phần dự án tương ứng: [milestone v-pre, tuần 4–5](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-4--kế-hoạch-mạng).

---

## 6. Mạng trong các module sau

Kiến thức module này sẽ được dùng lại như sau — mỗi bài có mục "Gặp lại ở đâu":

| Khái niệm ở đây | Gặp lại ở |
|---|---|
| CIDR, subnet, route table, NAT | AWS VPC, subnet, Internet Gateway, NAT Gateway (Module 06), Terraform (Module 07) |
| DNS | Docker DNS nội bộ (Module 04), Route 53 (Module 06), Kubernetes Service DNS (Module 09) |
| Port, bind address, firewall | Docker `-p`, Security Group, NACL, Kubernetes Service/NetworkPolicy |
| Reverse proxy, load balancing | Nginx trong dự án v0, ALB (Module 06), Ingress (Module 09) |
| TLS | HTTPS cho dự án, ACM/Let's Encrypt, secrets (Module 10) |

---

## 7. Checklist hoàn thành module

- [ ] 🟥 Giải thích được chi tiết "gõ `https://example.com` vào trình duyệt thì chuyện gì xảy ra", gồm DNS → TCP → TLS → HTTP.
- [ ] 🟥 Chia `10.0.0.0/16` thành các subnet `/24` và tính số địa chỉ **bằng tay**.
- [ ] 🟥 Dùng `dig` truy vết được một domain và giải thích TTL.
- [ ] 🟥 Đọc được bảng route và giải thích vai trò của default gateway và NAT.
- [ ] 🟥 Phân biệt được `Connection refused`, `Connection timed out`, `No route to host` và biết mỗi lỗi gợi ý điều gì.
- [ ] 🟥 Giải thích được vì sao app nghe trên `127.0.0.1` thì máy khác không truy cập được.
- [ ] 🟥 Đọc được kết quả `curl -v` và kiểm tra được chứng chỉ bằng `openssl`.
- [ ] 🟥 Cấu hình Nginx reverse proxy và giải thích được lỗi 502 / 504.
- [ ] 🟨 Bắt được gói tin bằng `tcpdump` và nhận ra TCP handshake.
- [ ] 🟥 Đạt [Checkpoint Module 02](checkpoint.md).
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#networking).

---

## 8. Nguồn học

| Vai trò | Nguồn | Ghi chú |
|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt, chỉ phần DevOps cần |
| Bổ sung | [Cisco Networking Academy — Networking Essentials](https://www.netacad.com/courses/networking/networking-essentials) | Miễn phí, ~70 giờ. **Chỉ học module về IP, subnet, DNS, TCP/UDP** — không cần học hết |
| Bổ sung | [Linux Journey — Networking Nomad](https://labex.io/linuxjourney) | Ngắn, gắn với lệnh Linux |
| Tra cứu | [nginx Beginner's Guide](https://nginx.org/en/docs/beginners_guide.html) | Tài liệu chính thức cho bài 07 |

Thuật ngữ của module: [glossary.md](glossary.md).
