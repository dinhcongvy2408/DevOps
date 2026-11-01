# 01. Mô hình OSI và TCP/IP

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 01 — Linux](../01-LINUX/README.md) (đặc biệt [bài 01](../01-LINUX/01-linux-architecture-filesystem.md) và [bài 02](../01-LINUX/02-essential-commands-text.md))
> Môi trường: `[WSL]` Ubuntu 24.04, `[PowerShell]` Windows 11

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
12. [Đọc thông báo lỗi và xử lý](#12-đọc-thông-báo-lỗi-và-xử-lý)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Giải thích được **vì sao** mạng máy tính được chia thành nhiều tầng (layer), và mỗi tầng giải quyết vấn đề gì.
- Đối chiếu được mô hình **OSI 7 tầng** với mô hình **TCP/IP 4 tầng** — mô hình mà Internet thực sự dùng.
- Mô tả quá trình **đóng gói (encapsulation)**: một request HTTP được bọc qua TCP, IP, Ethernet như thế nào trước khi ra dây mạng.
- Phân biệt ba loại "địa chỉ": **MAC**, **IP**, **port** — mỗi loại dùng ở tầng nào, để làm gì.
- Xếp một công cụ hoặc dịch vụ (ping, Security Group, Nginx, ALB, NLB, DNS…) vào đúng tầng.
- Dùng tư duy phân tầng để **khoanh vùng lỗi mạng** thay vì đoán mò.
- Xem interface, IP, MAC, bảng ARP trên WSL bằng `ip`, và so sánh với Windows bằng `ipconfig`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Mô hình phân tầng nghe có vẻ lý thuyết, nhưng nó là **ngôn ngữ chung** khi nói chuyện về sự cố và kiến trúc:

| Tình huống thật | Câu nói bạn sẽ nghe | Cần hiểu |
|---|---|---|
| Chọn load balancer trên AWS | "Dùng ALB vì cần route theo path — đó là L7" | ALB làm việc ở tầng 7, NLB ở tầng 4 |
| Debug "web không vào được" | "Ping được, nhưng port 443 timeout → không phải lỗi L3, nghi firewall ở L4" | Lỗi ở tầng nào thì dùng công cụ tầng đó |
| Đọc tài liệu Security Group | "Security Group lọc theo IP, protocol, port" | Đó là thông tin của tầng 3 và 4, nó **không** đọc được URL |
| Phỏng vấn | "Khi gõ URL vào trình duyệt, chuyện gì xảy ra?" | Câu hỏi kinh điển — trả lời theo từng tầng |
| Container không nói chuyện được với nhau | "Hai container không cùng network nên không có đường L3" | Docker network chính là mạng tầng 2/3 ảo |

Nếu không có mô hình phân tầng trong đầu, mỗi lỗi mạng sẽ là một bí ẩn riêng. Có nó, bạn có **một quy trình**: kiểm tra từng tầng, loại trừ dần.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Mạng máy tính giải quyết bài toán gì?

Hai chương trình chạy trên hai máy khác nhau muốn trao đổi dữ liệu. Ví dụ: trình duyệt trên laptop muốn lấy trang web từ Nginx trên một server ở Singapore. Để làm được, cần giải quyết **rất nhiều bài toán nhỏ** cùng lúc:

1. Truyền tín hiệu điện/sóng qua dây cáp hoặc Wi-Fi.
2. Gửi dữ liệu tới **đúng máy** trong cùng một mạng nội bộ.
3. Tìm **đường đi** qua nhiều mạng (nhà bạn → nhà mạng → Internet → AWS).
4. Giao dữ liệu tới **đúng chương trình** trên máy đích (Nginx, không phải SSH).
5. Đảm bảo dữ liệu tới **đủ và đúng thứ tự**, gửi lại nếu bị mất.
6. Hai chương trình hiểu được nhau (cùng nói HTTP).

### 3.2. Ý tưởng chia tầng

Thay vì một chương trình khổng lồ giải quyết hết, người ta **chia thành các tầng**. Mỗi tầng:

- Chỉ lo **một nhóm bài toán**.
- Dùng dịch vụ của tầng **ngay dưới** nó.
- Cung cấp dịch vụ cho tầng **ngay trên** nó.
- Không cần biết tầng khác làm việc **thế nào**.

**Ví dụ đời thường — gửi một bưu kiện:**

| Việc | Ai làm | Tương ứng tầng mạng |
|---|---|---|
| Viết thư bằng tiếng Việt | Bạn | Ứng dụng (HTTP) |
| Ghi tên người nhận trong công ty | Bạn | Port (giao cho đúng người/chương trình) |
| Ghi địa chỉ nhà ngoài phong bì | Bạn | IP (địa chỉ máy) |
| Bưu điện chọn tuyến xe Hà Nội → TP.HCM | Bưu điện | Routing |
| Xe tải chạy giữa hai bưu cục | Nhà xe | Ethernet/Wi-Fi (chặng ngắn) |

Bạn viết thư mà không cần biết xe tải chạy đường nào. Nhà xe chở thư mà không cần đọc nội dung. **Đó chính là sức mạnh của phân tầng**: thay đổi một tầng (đổi từ Wi-Fi sang cáp quang) không làm hỏng các tầng khác (HTTP vẫn chạy y nguyên).

### 3.3. Giao thức (protocol) là gì?

**Protocol** (giao thức) là một bộ **quy tắc** mà hai bên thống nhất để nói chuyện với nhau: định dạng dữ liệu, thứ tự gửi nhận, xử lý lỗi. Ví dụ: HTTP, TCP, IP, Ethernet đều là giao thức. Mỗi tầng có giao thức riêng.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Mô hình OSI 7 tầng

**OSI** (Open Systems Interconnection) là mô hình lý thuyết do ISO đưa ra, chia mạng thành 7 tầng. Nó **không** phải là thứ Internet chạy thật, nhưng là **từ vựng** cả ngành dùng: "lỗi L3", "load balancer L7".

| Tầng | Tên | Tiếng Việt | Lo việc gì | Ví dụ |
|---|---|---|---|---|
| 7 | Application | Ứng dụng | Giao thức mà chương trình dùng để nói chuyện | HTTP, DNS, SSH, SMTP |
| 6 | Presentation | Trình bày | Định dạng, mã hóa, nén dữ liệu | TLS (một phần), mã hóa ký tự |
| 5 | Session | Phiên | Mở, duy trì, đóng phiên làm việc | (thường gộp vào ứng dụng) |
| 4 | Transport | Giao vận | Giao dữ liệu tới **đúng chương trình** (port); đảm bảo tin cậy | TCP, UDP |
| 3 | Network | Mạng | Địa chỉ **IP**, tìm **đường đi** qua nhiều mạng | IP, ICMP, routing |
| 2 | Data Link | Liên kết dữ liệu | Gửi trong **cùng một mạng nội bộ**, địa chỉ **MAC** | Ethernet, Wi-Fi, ARP, switch |
| 1 | Physical | Vật lý | Tín hiệu điện, ánh sáng, sóng radio | Cáp mạng, cáp quang, sóng Wi-Fi |

**Mẹo nhớ** (từ dưới lên): **P**lease **D**o **N**ot **T**hrow **S**ausage **P**izza **A**way — Physical, Data Link, Network, Transport, Session, Presentation, Application.

> DevOps dùng nhiều nhất **tầng 3, 4 và 7**. Tầng 5 và 6 gần như không ai nhắc riêng trong công việc hằng ngày. Tầng 1 và 2 quan trọng ở data center, nhưng trên cloud thì nhà cung cấp lo.

### 4.2. 🟥 Mô hình TCP/IP 4 tầng — mô hình Internet thật sự dùng

Internet được xây dựng dựa trên bộ giao thức **TCP/IP**, chỉ có 4 tầng. Đối chiếu:

| TCP/IP | Tương ứng OSI | Giao thức tiêu biểu | Đơn vị dữ liệu |
|---|---|---|---|
| **Application** (Ứng dụng) | 5, 6, 7 | HTTP, HTTPS/TLS, DNS, SSH | Message / data |
| **Transport** (Giao vận) | 4 | TCP, UDP | Segment (TCP) / Datagram (UDP) |
| **Internet** (Liên mạng) | 3 | IP, ICMP | Packet (gói tin) |
| **Link** (Liên kết) | 1, 2 | Ethernet, Wi-Fi, ARP | Frame (khung) |

> Một số tài liệu chia TCP/IP thành 5 tầng (tách Link thành Data Link + Physical). Không quan trọng — điều quan trọng là bạn biết **giao thức nào nằm ở đâu**.

Khi người ta nói "L4", "L7", họ dùng **số tầng của OSI**, kể cả khi đang nói về TCP/IP.

### 4.3. 🟥 Đóng gói dữ liệu (Encapsulation)

Khi trình duyệt gửi một request HTTP, dữ liệu đi **từ trên xuống** qua các tầng. Mỗi tầng **bọc thêm một header** (phần đầu chứa thông tin điều khiển) của riêng mình:

```text
Tầng ứng dụng:                                   [ GET / HTTP/1.1 ... ]          ← dữ liệu HTTP
Tầng giao vận:                         [TCP hdr ][ GET / HTTP/1.1 ... ]          ← segment
Tầng liên mạng:              [ IP hdr ][TCP hdr ][ GET / HTTP/1.1 ... ]          ← packet
Tầng liên kết:  [ Eth hdr ][ IP hdr ][TCP hdr ][ GET / HTTP/1.1 ... ][ FCS ]     ← frame
```

Ở máy nhận, quá trình đi **ngược lại** — gọi là **mở gói (decapsulation)**: mỗi tầng đọc header của mình, gỡ nó ra, chuyển phần còn lại lên tầng trên.

**Mỗi header chứa gì (những trường DevOps cần biết):**

| Header | Trường quan trọng | Dùng để |
|---|---|---|
| **Ethernet** (~14 byte) | MAC nguồn, MAC đích, EtherType (loại dữ liệu bên trong, ví dụ IPv4) | Giao frame tới đúng card mạng trong cùng mạng nội bộ |
| **IPv4** (≥ 20 byte) | IP nguồn, IP đích, **TTL**, Protocol (6 = TCP, 17 = UDP, 1 = ICMP) | Đưa packet qua nhiều mạng tới đúng máy |
| **TCP** (≥ 20 byte) | Port nguồn, port đích, số thứ tự (sequence), cờ (SYN, ACK, FIN, RST) | Giao tới đúng chương trình, đảm bảo đủ và đúng thứ tự |
| **HTTP** | Method, đường dẫn, `Host`, các header khác | Chương trình hiểu yêu cầu là gì |

> **TTL (Time To Live)**: một con số giảm đi 1 mỗi khi packet đi qua một router. Về 0 thì packet bị bỏ. Nó chống việc packet chạy vòng tròn mãi trong mạng. Lệnh `traceroute` ([bài 04](04-routing-nat-switching.md)) lợi dụng chính cơ chế này.

**Một hệ quả quan trọng:** thiết bị ở tầng nào thì **chỉ đọc được header đến tầng đó**:

- **Switch** (tầng 2) chỉ nhìn MAC.
- **Router** (tầng 3) nhìn IP.
- **Firewall / Security Group** (tầng 3–4) nhìn IP, protocol, port.
- **Reverse proxy / ALB** (tầng 7) mở hết các lớp và đọc được URL, header HTTP.

Đó là lý do Security Group **không thể** chặn theo đường dẫn URL `/admin` — nó không đọc tới tầng 7.

### 4.4. 🟥 Ba loại "địa chỉ": MAC, IP, port

Người mới hay lẫn lộn. Hãy nhớ: mỗi loại trả lời một câu hỏi khác nhau.

| Địa chỉ | Tầng | Trả lời câu hỏi | Ví dụ | Thay đổi khi đi qua router? |
|---|---|---|---|---|
| **MAC** | 2 | Card mạng **nào** trong mạng nội bộ này? | `00:15:5d:a1:b2:c3` | **Có** — mỗi chặng một cặp MAC mới |
| **IP** | 3 | **Máy nào** trên toàn mạng (có thể ở rất xa)? | `172.30.98.229` | Không (trừ khi đi qua NAT — [bài 04](04-routing-nat-switching.md)) |
| **Port** | 4 | **Chương trình nào** trên máy đó? | `443` (HTTPS), `5432` (PostgreSQL) | Không (trừ khi đi qua NAT) |

**Ví dụ đời thường:** IP là địa chỉ tòa nhà, port là số phòng, MAC giống biển số xe của chặng giao hàng hiện tại — mỗi chặng đổi xe thì đổi biển số, nhưng địa chỉ tòa nhà trên bưu kiện không đổi.

- **MAC address** (địa chỉ vật lý): 48 bit, viết thành 6 cặp hệ 16. Gắn với card mạng (thật hoặc ảo). 3 byte đầu cho biết nhà sản xuất — ví dụ `00:15:5d` là card mạng ảo của Hyper-V, thứ mà WSL2 dùng.
- **IP address**: học kỹ ở [bài 02](02-ipv4-subnet-cidr.md).
- **Port**: số từ 0 đến 65535. Học kỹ ở [bài 05](05-tcp-udp-ports-firewall.md).

### 4.5. 🟥 ARP — nối IP với MAC

Khi máy A muốn gửi packet tới máy B **trong cùng mạng nội bộ**, nó biết IP của B nhưng tầng 2 lại cần **MAC** của B. **ARP** (Address Resolution Protocol — giao thức phân giải địa chỉ) giải quyết việc này:

1. A hét lên toàn mạng (broadcast): "Ai có IP `172.30.96.1`? Báo MAC cho `172.30.98.229` nhé."
2. Máy có IP đó trả lời riêng: "Là tôi, MAC của tôi là `00:15:5d:...`".
3. A lưu kết quả vào **bảng ARP** (ARP cache) để lần sau không phải hỏi lại.

Nếu B ở **mạng khác**, A không hỏi MAC của B. A hỏi MAC của **default gateway** (router) và gửi frame cho router. Router lo phần còn lại. Đây là điểm mấu chốt nối tầng 2 và tầng 3, sẽ gặp lại ở [bài 04](04-routing-nat-switching.md).

Xem bảng ARP trên Linux bằng `ip neigh` (mục 8).

### 4.6. 🟨 MTU — kích thước tối đa của một frame

**MTU** (Maximum Transmission Unit) là kích thước dữ liệu tối đa một frame chở được, Ethernet thường là **1500 byte**. Packet lớn hơn phải bị chia nhỏ hoặc bị bỏ. Ở mức Junior chỉ cần biết: khi dùng VPN hoặc mạng overlay (Docker Swarm, một số mạng Kubernetes), MTU nhỏ hơn có thể gây lỗi "kết nối được nhưng tải trang lớn thì treo". `ip link` hiển thị MTU của từng interface.

### 4.7. 🟥 Công cụ và dịch vụ làm việc ở tầng nào?

Bảng này sẽ theo bạn suốt khóa học. Đừng học thuộc — hãy hiểu **vì sao** mỗi thứ nằm ở đó (dựa vào việc nó đọc header nào).

| Công cụ / dịch vụ | Tầng (OSI) | Vì sao |
|---|---|---|
| Cáp mạng, Wi-Fi | 1 | Truyền tín hiệu |
| Switch, ARP, `ip neigh` | 2 | Làm việc với MAC |
| Router, `ip route` | 3 | Chuyển packet dựa trên IP đích |
| `ping` (giao thức ICMP) | 3 | ICMP nằm ngay trên IP, **không có port** |
| `traceroute` | 3 | Dựa vào TTL trong IP header |
| AWS **Security Group**, **Network ACL**, `iptables`/`ufw` | 3–4 | Lọc theo IP, protocol, port |
| `nc` (netcat), `ss` | 4 | Kiểm tra/kết nối tới một port TCP/UDP |
| AWS **NLB** (Network Load Balancer) | 4 | Phân phối kết nối TCP/UDP, không đọc HTTP |
| TLS / HTTPS | giữa 4 và 7 (thường xếp vào 6 hoặc 7) | Mã hóa dữ liệu ứng dụng trước khi đưa xuống TCP |
| **DNS** | 7 | Là một giao thức ứng dụng, chạy trên **UDP/TCP port 53** |
| `curl`, trình duyệt | 7 | Nói HTTP |
| **Nginx** (reverse proxy), AWS **ALB** | 7 | Đọc URL, header `Host`, cookie để quyết định chuyển request đi đâu |
| Kubernetes **Service** (ClusterIP) | 3–4 | Chuyển tiếp theo IP/port |
| Kubernetes **Ingress** | 7 | Route theo hostname/path |

> 🟨 Nginx cũng có chế độ proxy tầng 4 (module `stream`), nhưng khi nói "Nginx reverse proxy" trong khóa học này là nói về tầng 7.

### 4.8. 🟥 Dùng tư duy phân tầng để khoanh vùng lỗi

Một quy tắc then chốt: **tầng trên chỉ hoạt động được khi các tầng dưới đã hoạt động**. HTTP không thể chạy nếu TCP không kết nối được; TCP không kết nối được nếu IP không tới được máy đích.

Có hai cách đi:

**Từ dưới lên (bottom-up)** — dùng khi không biết gì, hoặc khi mọi thứ đều hỏng:

| Bước | Tầng | Câu hỏi | Công cụ (học ở bài nào) |
|---|---|---|---|
| 1 | 1–2 | Interface có `UP` không? Có IP không? | `ip addr`, `ip link` (bài này) |
| 2 | 3 | Có tới được gateway không? Có route tới đích không? | `ping`, `ip route` ([bài 04](04-routing-nat-switching.md)) |
| 3 | 7 (DNS) | Tên miền phân giải ra IP đúng không? | `dig` ([bài 03](03-dns-dhcp.md)) |
| 4 | 4 | Port đích có mở không? | `nc -vz`, `ss` ([bài 05](05-tcp-udp-ports-firewall.md)) |
| 5 | 6–7 | TLS có hợp lệ không? HTTP trả mã gì? | `openssl`, `curl -v` ([bài 06](06-http-https-tls.md)) |

**Từ trên xuống (top-down)** — dùng khi có thông báo lỗi cụ thể ở tầng cao. Ví dụ `curl` báo `502 Bad Gateway`: tức là đã có kết nối HTTP tới proxy (tầng 1–7 giữa bạn và proxy đều ổn), vấn đề nằm ở **phía sau** proxy. Không cần ping, không cần kiểm tra DNS của bạn.

> Kỹ sư giỏi **đọc thông báo lỗi để chọn điểm bắt đầu**, rồi mới đi lên hoặc xuống. [Bài 08](08-network-troubleshooting-tools.md) sẽ ghép tất cả thành một quy trình hoàn chỉnh.

### 4.9. Gặp lại ở đâu

| Khái niệm | Gặp lại ở |
|---|---|
| L4 vs L7 | AWS NLB vs ALB (Module 06), Kubernetes Service vs Ingress (Module 09) |
| Security Group lọc tầng 3–4 | Module 06 — vì sao không chặn URL được bằng Security Group |
| Encapsulation | Docker network, overlay network — gói tin bọc trong gói tin (Module 04, 09) |
| MAC, interface ảo | Mỗi container có interface `eth0` và MAC riêng (Module 04) |
| Debug theo tầng | Mọi bài break-fix từ đây về sau |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Ticket "Website công ty không vào được"

Kỹ sư A đoán mò: restart Nginx, restart server, vẫn không được. Mất 1 giờ.

Kỹ sư B đi theo tầng:

1. `curl -v https://shop.example.com` → `Could not resolve host`. Lỗi xảy ra **trước khi** có kết nối TCP → nghi DNS.
2. `dig shop.example.com` → không có bản ghi A. Hóa ra ai đó vừa xóa nhầm bản ghi DNS.
3. Khôi phục bản ghi. Xong trong 10 phút. Server và Nginx chưa từng có vấn đề gì.

### Ví dụ 2: "Ping được nhưng web không vào được"

- `ping 13.250.x.x` thành công → tầng 3 ổn: có đường đi tới máy.
- `nc -vz 13.250.x.x 443` → treo rồi timeout → tầng 4 có vấn đề.
- Nguyên nhân thường gặp: Security Group chưa mở port 443, hoặc Nginx chưa chạy.

> ⚠️ Ngược lại thì không đúng: **ping thất bại chưa chắc máy chết**. Rất nhiều server (và mặc định Security Group của AWS) **chặn ICMP**. Đừng kết luận "server down" chỉ vì ping không được.

### Ví dụ 3: Chọn load balancer

Dự án cần: `/api/*` đi tới service Java, `/static/*` đi tới service khác. Việc này cần **đọc URL** → cần load balancer **tầng 7** (ALB hoặc Nginx), không phải NLB.

---

## 6. Sơ đồ kiến trúc

### 6.1. Đóng gói và mở gói khi trình duyệt gọi Nginx

```text
   LAPTOP (trình duyệt)                                   SERVER (Nginx)
 ┌────────────────────────┐                         ┌────────────────────────┐
 │ L7  HTTP: GET /        │                         │ L7  Nginx đọc GET /    │
 │        ▼ thêm TCP hdr  │                         │        ▲ gỡ TCP hdr    │
 │ L4  TCP: port 51514→443│                         │ L4  TCP: đến port 443  │
 │        ▼ thêm IP hdr   │                         │        ▲ gỡ IP hdr     │
 │ L3  IP: 192.168.1.10 → │                         │ L3  IP: đúng IP mình   │
 │         13.250.10.20   │                         │        ▲ gỡ Eth hdr    │
 │        ▼ thêm Eth hdr  │                         │ L2  Eth: đúng MAC mình │
 │ L2  Eth: MAC laptop →  │                         │                        │
 │          MAC router    │                         │                        │
 └──────────┬─────────────┘                         └──────────▲─────────────┘
            │  L1 (Wi-Fi)                                      │ L1
            ▼                                                  │
      ┌───────────┐   L1/L2 mới   ┌───────────┐  ...  ┌────────┴──┐
      │ Router    │──────────────►│ Router    │──────►│ Router    │
      │ nhà bạn   │ (đổi MAC,     │ nhà mạng  │       │ AWS       │
      │ L1→L3     │  giữ IP*)     │ L1→L3     │       │ L1→L3     │
      └───────────┘               └───────────┘       └───────────┘
   * Router nhà bạn còn làm NAT — đổi IP nguồn thành IP public (bài 04)
```

Điều cần thấy trong sơ đồ: **router chỉ mở gói tới tầng 3**, đổi header tầng 2 (MAC) ở mỗi chặng; header tầng 4 và dữ liệu HTTP đi nguyên vẹn từ đầu đến cuối (nếu không có NAT).

### 6.2. Bản đồ tầng ↔ thứ DevOps chạm vào

```text
 L7  Application │ HTTP, DNS, SSH │ curl, Nginx, ALB, Ingress, Route 53
 L4  Transport   │ TCP, UDP, port │ ss, nc, NLB, Security Group (port)
 L3  Network     │ IP, ICMP       │ ping, traceroute, ip route, Security Group (IP), route table VPC
 L2  Data Link   │ Ethernet, ARP  │ ip link, ip neigh, switch, Docker bridge
 L1  Physical    │ cáp, sóng      │ (trên cloud: AWS lo)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ip addr` (`ip a`) | Xem interface và địa chỉ IP | 🟥 |
| `ip -br addr` | Xem gọn mỗi interface một dòng | 🟥 |
| `ip link` | Xem interface, trạng thái UP/DOWN, MAC, MTU | 🟥 |
| `ip neigh` | Xem bảng ARP (IP ↔ MAC trong mạng nội bộ) | 🟨 |
| `ip route` | Xem bảng định tuyến (giới thiệu — học kỹ ở [bài 04](04-routing-nat-switching.md)) | 🟥 |
| `hostname -I` | In nhanh các IP của máy | 🟥 |
| `ipconfig /all` `[PowerShell]` | Tương đương `ip addr` trên Windows | 🟨 |

> Bạn có thể gặp `ifconfig` và `arp` trong tài liệu cũ. Chúng thuộc gói `net-tools` đã cũ và không có sẵn trên Ubuntu mới. Hãy dùng bộ lệnh `ip` (gói `iproute2`, có sẵn).

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu dưới đây là **minh họa** theo WSL2 chế độ mạng NAT mặc định. Tên interface, IP, MAC trên máy bạn sẽ khác — hãy tập trung vào **cấu trúc**.

### `ip addr` — xem interface và địa chỉ

```bash
ip addr
```

```text
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:15:5d:a1:b2:c3 brd ff:ff:ff:ff:ff:ff
    inet 172.30.98.229/20 brd 172.30.111.255 scope global eth0
       valid_lft forever preferred_lft forever
```

Đọc từng phần của interface `eth0`:

```text
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ... state UP
│  │      │                   │  │          │          └ trạng thái thực tế: UP
│  │      │                   │  │          └ MTU 1500 byte (mục 4.6)
│  │      │                   │  └ LOWER_UP: có "dây cắm" — tầng 1 hoạt động
│  │      │                   └ UP: interface được bật (bởi phần mềm)
│  │      └ các cờ khả năng
│  └ tên interface
└ số thứ tự

    link/ether 00:15:5d:a1:b2:c3 brd ff:ff:ff:ff:ff:ff
               │                     └ MAC broadcast (gửi cho mọi máy trong mạng)
               └ MAC của interface — tầng 2

    inet 172.30.98.229/20 brd 172.30.111.255 scope global eth0
         │             │      │                  └ dùng được ra ngoài máy
         │             │      └ địa chỉ broadcast của mạng (bài 02)
         │             └ /20 = độ dài phần mạng (bài 02)
         └ IPv4 của máy — tầng 3
```

| Interface hay gặp | Là gì |
|---|---|
| `lo` | **Loopback** — mạng ảo nội bộ trong chính máy, địa chỉ `127.0.0.1`. Gói tin không bao giờ rời máy |
| `eth0`, `ens5`, `enp0s3` | Card mạng (thật hoặc ảo). Trên EC2 Ubuntu thường là `ens5` |
| `docker0` | Bridge của Docker (khi Docker Engine chạy trực tiếp trong Linux) |
| `veth...` | Một đầu của "dây cáp ảo" nối container với bridge (Module 04) |

Tham số hay dùng:

| Lệnh | Ý nghĩa |
|---|---|
| `ip -br addr` | `-br` (brief): mỗi interface một dòng — dễ đọc nhất |
| `ip -4 addr` | Chỉ hiện IPv4 |
| `ip addr show eth0` | Chỉ hiện một interface |

```bash
ip -br addr
```

```text
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             172.30.98.229/20 fe80::215:5dff:fea1:b2c3/64
```

> Địa chỉ bắt đầu bằng `fe80::` là địa chỉ IPv6 link-local — tự sinh, chỉ dùng trong mạng nội bộ. Ở mức Junior chỉ cần nhận ra nó là IPv6 (🟦, [bài 02](02-ipv4-subnet-cidr.md)).

### `ip link` — trạng thái tầng 2

```bash
ip link show eth0
```

```text
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 00:15:5d:a1:b2:c3 brd ff:ff:ff:ff:ff:ff
```

Giống `ip addr` nhưng **không có IP** — chỉ thông tin tầng 2. Dùng khi nghi interface bị tắt: `state DOWN` hoặc thiếu `LOWER_UP`.

> ⚠️ `sudo ip link set eth0 down` sẽ **tắt mạng** của máy. Trên server từ xa qua SSH, đây là cách nhanh nhất để tự khóa mình ra ngoài. Chỉ thử trong `[Sandbox]`.

### `ip neigh` — bảng ARP

```bash
ip neigh
```

```text
172.30.96.1 dev eth0 lladdr 00:15:5d:d4:e5:f6 REACHABLE
```

| Phần | Ý nghĩa |
|---|---|
| `172.30.96.1` | IP của "hàng xóm" (máy trong cùng mạng) — ở đây là Windows host, đóng vai gateway của WSL |
| `dev eth0` | Học được qua interface nào |
| `lladdr 00:15:5d:...` | MAC tương ứng (link-layer address) |
| `REACHABLE` | Mới xác nhận gần đây. Khác: `STALE` (lâu chưa xác nhận), `FAILED` (hỏi ARP không ai trả lời) |

`FAILED` là manh mối mạnh: máy có IP đó không tồn tại trong mạng nội bộ, hoặc bị chặn ở tầng 2.

### `ip route` — giới thiệu

```bash
ip route
```

```text
default via 172.30.96.1 dev eth0 proto kernel
172.30.96.0/20 dev eth0 proto kernel scope link src 172.30.98.229
```

Đọc nhanh:

- Dòng 2: các máy trong dải `172.30.96.0/20` ở **cùng mạng** → gửi thẳng qua `eth0` (dùng ARP để tìm MAC).
- Dòng 1: mọi đích khác (`default`) → gửi cho **gateway** `172.30.96.1`.

Đây chính là logic "cùng mạng thì hỏi ARP của đích, khác mạng thì gửi cho gateway" ở mục 4.5. Học kỹ ở [bài 04](04-routing-nat-switching.md).

### `hostname -I` — IP nhanh

```bash
hostname -I
```

```text
172.30.98.229
```

> Chữ **I hoa**. `hostname -i` (i thường) cho kết quả khác — thường là địa chỉ `127.0.1.1` dùng cho tên máy trong `/etc/hosts`, không phải IP mạng thật.

### `ipconfig /all` — phía Windows `[PowerShell]`

```powershell
ipconfig /all
```

```text
Ethernet adapter vEthernet (WSL (Hyper-V firewall)):
   Physical Address. . . . . . . . . : 00-15-5D-D4-E5-F6
   IPv4 Address. . . . . . . . . . . : 172.30.96.1(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.240.0

Wireless LAN adapter Wi-Fi:
   Physical Address. . . . . . . . . : 3C-A9-F4-11-22-33
   IPv4 Address. . . . . . . . . . . : 192.168.1.10(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . : 192.168.1.1
```

Để ý: Windows có một card mạng ảo dành cho WSL với IP `172.30.96.1` — chính là địa chỉ gateway mà WSL thấy trong `ip route`. Windows ghi MAC bằng dấu `-` và chữ hoa, Linux dùng dấu `:` và chữ thường — cùng một kiểu địa chỉ. `255.255.240.0` và `/20` là cùng một subnet mask viết theo hai cách ([bài 02](02-ipv4-subnet-cidr.md)).

---

## 9. Bài thực hành từng bước

**Lab: Bản đồ mạng của laptop bạn** · `[WSL]` + `[PowerShell]` · ~60 phút

Mục tiêu: vẽ được sơ đồ mạng thật giữa WSL, Windows và router nhà bạn; quan sát ARP; mô tả một request HTTP qua các tầng. Ghi câu trả lời vào `~/devops-lab/02-networking/lab01-answers.md`.

```bash
mkdir -p ~/devops-lab/02-networking
cd ~/devops-lab/02-networking
```

### Bước 1 — Interface và IP của WSL `[WSL]`

```bash
ip -br addr
ip link show eth0
hostname -I
```

❓ WSL có mấy interface? IP của `eth0` là gì, độ dài prefix (số sau dấu `/`) là bao nhiêu? MAC là gì, 3 byte đầu gợi ý gì? MTU bao nhiêu?

### Bước 2 — Gateway của WSL `[WSL]`

```bash
ip route
```

❓ Gateway mặc định của WSL là IP nào?

### Bước 3 — Phía Windows `[PowerShell]`

```powershell
ipconfig /all
```

❓ Tìm card mạng ảo dành cho WSL. IP của nó có trùng với gateway ở Bước 2 không? Card mạng thật (Wi-Fi hoặc Ethernet) của laptop có IP gì, gateway là gì (thường là router nhà bạn)?

### Bước 4 — Quan sát ARP `[WSL]`

```bash
ip neigh                       # bảng ARP hiện tại
ping -c 2 $(ip route | awk '/default/ {print $3}')   # ping gateway 2 lần
ip neigh                       # xem lại
```

> `$(...)` chạy lệnh bên trong và thay bằng kết quả ([bài 06 Linux](../01-LINUX/06-bash-scripting.md)). Ở đây: lấy cột thứ 3 của dòng `default` trong `ip route` = IP gateway.

❓ Sau khi ping, bảng ARP có mục cho gateway không? Trạng thái là gì? MAC của gateway có khớp với MAC của card mạng ảo WSL bên Windows (Bước 3) không?

### Bước 5 — Ping một máy ngoài Internet `[WSL]`

```bash
ping -c 3 1.1.1.1
ip neigh
```

❓ Ping `1.1.1.1` có thành công không? Bảng ARP có thêm mục `1.1.1.1` không? Vì sao? (Gợi ý: mục 4.5.)

### Bước 6 — Vẽ sơ đồ

Trong file trả lời, vẽ sơ đồ dạng chữ như mục 6.1, gồm: WSL (IP, MAC) → card ảo WSL trên Windows (IP, MAC) → Wi-Fi của laptop (IP) → router nhà bạn (IP gateway) → Internet. Ghi rõ mỗi mũi tên là chặng **tầng 2** nào.

### Bước 7 — Một request HTTP qua các tầng

Chạy:

```bash
curl -sI http://example.com | head -5
```

Lập bảng sau trong file trả lời, điền những gì bạn **biết được** hoặc **suy ra được** từ các bước trước (ô nào chưa biết, ghi "học ở bài X"):

| Tầng | Giao thức | Thông tin "địa chỉ" | Giá trị trong request này |
|---|---|---|---|
| 7 | ? | Tên miền, đường dẫn | ? |
| 4 | ? | Port nguồn, port đích | ? |
| 3 | ? | IP nguồn, IP đích | ? |
| 2 | ? | MAC nguồn, MAC đích (chặng đầu tiên) | ? |

### Bước 8 — Commit

```bash
mkdir -p ~/devops-journey/week04
cp ~/devops-lab/02-networking/lab01-answers.md ~/devops-journey/week04/
cd ~/devops-journey
git add week04/lab01-answers.md
git commit -m "docs(network): lab 01 - map my network by layers"
git push
```

---

## 10. Kết quả mong đợi

- **Bước 1:** 2 interface: `lo` (`127.0.0.1/8`) và `eth0` (IP dạng `172.x.x.x`, thường `/20`). MAC bắt đầu bằng `00:15:5d` → card mạng ảo Hyper-V. MTU thường là `1500`.
- **Bước 2–3:** Gateway của WSL **trùng** IP của card `vEthernet (WSL ...)` trên Windows. Nghĩa là: với WSL, **Windows chính là router**. Card Wi-Fi thật có IP kiểu `192.168.x.x` với gateway là router nhà bạn (thường `192.168.1.1` hoặc `192.168.0.1`).
- **Bước 4:** Sau khi ping, `ip neigh` có mục gateway ở trạng thái `REACHABLE`, MAC khớp với card ảo WSL bên Windows (khác cách viết hoa/thường và dấu `-`/`:`).
- **Bước 5:** Bảng ARP **không** có mục `1.1.1.1`. Vì `1.1.1.1` ở mạng khác → WSL gửi frame tới **MAC của gateway**, không bao giờ cần MAC của `1.1.1.1`. Nếu ping `1.1.1.1` thất bại trong khi các bước khác bình thường, có thể mạng của bạn chặn ICMP — chưa kết luận gì cả.
- **Bước 7:** Tầng 7: HTTP, `example.com`, `/`. Tầng 4: TCP, port đích `80`, port nguồn là một số lớn ngẫu nhiên (học ở [bài 05](05-tcp-udp-ports-firewall.md)). Tầng 3: IP nguồn là IP WSL, IP đích là IP của `example.com` (tìm bằng `dig` ở [bài 03](03-dns-dhcp.md)). Tầng 2 chặng đầu: MAC nguồn là MAC `eth0` của WSL, MAC đích là **MAC của gateway** (Windows), không phải MAC của server `example.com`.

---

## 11. Các lỗi thường gặp

| Lỗi / hiểu nhầm | Thực tế | Cách xử lý |
|---|---|---|
| `ifconfig: command not found` | `net-tools` đã cũ, không cài sẵn | Dùng `ip addr`. Bảng đối chiếu: `ifconfig` → `ip addr`, `route` → `ip route`, `arp` → `ip neigh` |
| "Ping không được → server chết" | Nhiều server chặn ICMP | Kiểm tra trực tiếp port dịch vụ (`nc -vz`, `curl`) trước khi kết luận |
| "Security Group chặn được URL `/admin`" | Security Group chỉ thấy đến tầng 4 | Chặn theo URL phải làm ở tầng 7: Nginx, ALB rule, WAF |
| Nhầm `hostname -i` với `hostname -I` | `-i` thường trả `127.0.1.1` | Dùng `-I` hoặc `ip -br addr` |
| Thấy IP WSL thay đổi sau khi khởi động lại | Ở chế độ NAT, WSL có thể nhận IP mới mỗi lần khởi động | Đừng hard-code IP WSL. Từ Windows, truy cập dịch vụ trong WSL bằng `localhost` |
| Lẫn tầng khi mô tả: "lỗi DNS là lỗi tầng 3" | DNS là giao thức **ứng dụng** (tầng 7) chạy trên UDP/TCP 53 | DNS hỏng thì tầng 3 vẫn có thể bình thường: `ping 1.1.1.1` được nhưng `ping google.com` không |
| Học thuộc 7 tầng nhưng không áp dụng | Phỏng vấn không hỏi tên tầng 5, mà hỏi "debug thế nào" | Luyện bảng mục 4.7 và quy trình mục 4.8 |

---

## 12. Đọc thông báo lỗi và xử lý

Mỗi thông báo lỗi mạng **gợi ý tầng** đang có vấn đề. Đây là bảng tra bạn sẽ dùng xuyên suốt module (các lỗi tầng 4 và 7 sẽ được giải thích kỹ ở bài 05, 06):

| Thông báo | Ví dụ xuất hiện | Gợi ý tầng | Ý nghĩa sơ bộ |
|---|---|---|---|
| `Network is unreachable` | `ping`, `curl` | 3 | Không có route nào tới đích — thường là thiếu default gateway hoặc interface không có IP |
| `Destination Host Unreachable` | `ping` | 2–3 | Có route, nhưng router/máy không tìm thấy đích (thường ARP thất bại trong mạng nội bộ) |
| `100% packet loss` (không có lỗi khác) | `ping` | 3 (hoặc firewall) | Không có phản hồi — có thể mất kết nối, **hoặc** ICMP bị chặn |
| `Could not resolve host` / `Temporary failure in name resolution` | `curl`, `ping`, `apt` | 7 (DNS) | Không đổi được tên ra IP — lỗi xảy ra **trước khi** có bất kỳ kết nối nào |
| `Connection refused` | `curl`, `nc`, app Java | 4 | Tới được máy, nhưng **không có chương trình nào nghe** ở port đó ([bài 05](05-tcp-udp-ports-firewall.md)) |
| `Connection timed out` | `curl`, `nc`, `ssh` | 3–4 | Không có phản hồi — thường do firewall/Security Group lặng lẽ bỏ gói tin ([bài 05](05-tcp-udp-ports-firewall.md)) |
| `SSL certificate problem` | `curl` | 6–7 | Kết nối TCP ổn, TLS có vấn đề ([bài 06](06-http-https-tls.md)) |
| `502 Bad Gateway`, `504 Gateway Timeout` | trình duyệt, `curl` | 7 (phía sau proxy) | Proxy hoạt động, app phía sau có vấn đề ([bài 06](06-http-https-tls.md), [bài 07](07-load-balancing-reverse-proxy.md)) |

**Cách dùng bảng này — áp dụng quy trình 4 bước của [Module 01](../01-LINUX/01-linux-architecture-filesystem.md#12-đọc-thông-báo-lỗi-và-xử-lý):**

1. **Đọc** thông báo → tra bảng → xác định tầng nghi ngờ.
2. **Kiểm tra** tầng ngay **dưới** tầng nghi ngờ (để chắc nó ổn) và chính tầng nghi ngờ.
3. **Sửa một thứ**, thử lại.
4. **Ghi** vào `troubleshooting-journal.md`, có ghi rõ "lỗi ở tầng X".

Ví dụ ghi nhật ký:

```markdown
## 2026-11-23 — apt update báo Temporary failure in name resolution
- Triệu chứng: `sudo apt update` → `Temporary failure resolving 'archive.ubuntu.com'`
- Tầng nghi ngờ: 7 (DNS) — lỗi xảy ra trước khi kết nối
- Kiểm tra tầng dưới: `ping -c 2 1.1.1.1` → thành công → tầng 3 ổn
- Kiểm tra DNS: `cat /etc/resolv.conf` → nameserver trỏ tới IP không phản hồi
- Nguyên nhân: VPN công ty vừa ngắt, cấu hình DNS cũ còn lại
- Cách sửa: khởi động lại WSL (`wsl --shutdown` từ PowerShell) để WSL sinh lại resolv.conf
- Bài học: "ping IP được, ping tên không được" = lỗi DNS
```

---

## 13. Câu hỏi kiểm tra kiến thức

1. Vì sao mạng được chia thành nhiều tầng? Lợi ích lớn nhất là gì? Cho một ví dụ thay đổi ở một tầng mà không ảnh hưởng tầng khác.
2. Liệt kê 4 tầng của TCP/IP và các tầng OSI tương ứng. Khi kỹ sư nói "L4", "L7", họ dùng số tầng của mô hình nào?
3. Mô tả quá trình đóng gói một request HTTP từ trình duyệt. Mỗi tầng thêm header chứa thông tin gì quan trọng?
4. Frame, packet, segment khác nhau thế nào?
5. MAC, IP, port lần lượt trả lời câu hỏi gì? Khi packet đi qua một router, cái nào thay đổi, cái nào giữ nguyên (không có NAT)?
6. ARP dùng để làm gì? Khi gửi tới một IP ở **mạng khác**, máy hỏi ARP cho IP nào?
7. `ping` làm việc ở tầng nào? Vì sao ping không có port?
8. Vì sao Security Group không chặn được request tới đường dẫn `/admin`? Muốn chặn thì cần thứ gì?
9. DNS thuộc tầng nào? Nó dùng giao thức tầng 4 nào, port bao nhiêu?
10. Phân biệt ALB và NLB theo mô hình phân tầng. Khi nào bắt buộc phải dùng loại tầng 7?
11. Khi nào nên debug từ dưới lên, khi nào từ trên xuống? Cho ví dụ cho mỗi cách.
12. `ping 1.1.1.1` thành công nhưng `ping google.com` báo `Temporary failure in name resolution`. Lỗi ở đâu? Vì sao bạn kết luận được như vậy?
13. Trong WSL, vì sao bảng ARP có MAC của gateway nhưng không bao giờ có MAC của `example.com`?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/01-solutions.md](solutions/01-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Xếp tầng.** Xếp các mục sau vào đúng tầng OSI và giải thích bằng một câu "vì nó đọc/ghi thông tin gì": `ssh`, `traceroute`, Wi-Fi, Kubernetes Ingress, AWS Network ACL, `nc -vz host 5432`, header `Host:` của HTTP, `ip neigh`, chứng chỉ TLS, switch trong phòng server, Route 53.

**Bài 2 — Chặng tầng 2.** Laptop (`192.168.1.10`) gọi `https://api.example.com` (IP `13.250.10.20`), đi qua router nhà bạn và 3 router trung gian. Hỏi: (a) có bao nhiêu chặng tầng 2? (b) ở chặng đầu tiên, MAC đích là của ai? (c) ở chặng cuối, IP đích là gì? (d) giả sử không có NAT, thông tin nào trong packet **không đổi** suốt hành trình?

**Bài 3 — Đọc lỗi để chọn tầng.** Với mỗi thông báo sau, cho biết tầng nghi ngờ đầu tiên, lệnh kiểm tra đầu tiên bạn chạy, và vì sao:
(a) `ssh: connect to host 10.0.1.25 port 22: Connection timed out`
(b) `curl: (6) Could not resolve host: taskhub.internal`
(c) `ping: connect: Network is unreachable`
(d) `curl: (7) Failed to connect to localhost port 8080: Connection refused`
(e) Trình duyệt hiện `502 Bad Gateway` từ Nginx.

**Bài 4 — Mạng của container `[Sandbox]`.** Chạy `docker run --rm -it ubuntu:22.04 bash`, trong container cài `iproute2` (`apt-get update && apt-get install -y iproute2 iputils-ping`) rồi chạy `ip -br addr`, `ip route`, `ip neigh`, ping gateway, `ip neigh` lần nữa. So sánh với WSL: container có interface nào? IP thuộc dải nào? Gateway là gì? Theo bạn, "gateway" của container là thứ gì (đoán trước, Module 04 sẽ xác nhận)?

**Bài 5 — Giải thích cho người khác.** Viết một đoạn ≤ 200 chữ giải thích cho một bạn lập trình viên Java mới vào nghề: "vì sao ping server được mà app vẫn không kết nối được database". Dùng ít nhất hai khái niệm từ bài này.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Vẽ lại được sơ đồ mục 6.1 và giải thích router đổi gì, giữ gì ở mỗi chặng.
- [ ] Xếp được bất kỳ công cụ/dịch vụ nào trong bảng mục 4.7 vào tầng và **giải thích lý do** (không học thuộc).
- [ ] Đọc được mọi phần của `ip addr` và `ip neigh` trên máy mình.
- [ ] Nhìn một thông báo lỗi mạng, nói ngay được tầng nghi ngờ và lệnh kiểm tra đầu tiên.
- [ ] Giải thích được vì sao "ping thất bại" không đủ để kết luận server chết.
- [ ] Làm được Bài tập 2 và 3 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Linux Journey — Networking Nomad: Network Basics](https://labex.io/linuxjourney) | Ôn bằng bài ngắn | 2026-10-31 |
| [Cisco Networking Academy — Networking Essentials](https://www.netacad.com/courses/networking/networking-essentials) | Học sâu hơn về mô hình phân tầng (tùy chọn) | 2026-10-31 (xác nhận qua tìm kiếm) |
| [Microsoft Learn — Accessing network applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking) | Mạng của WSL2: NAT, IP của WSL và Windows | 2026-10-31 |
| `man ip-address`, `man ip-link`, `man ip-neighbour` (chạy trên máy) | Tham số chính thức của bộ lệnh `ip` | — |
