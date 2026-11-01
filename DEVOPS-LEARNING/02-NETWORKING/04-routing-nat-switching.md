# 04. Routing, NAT và Switching

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc (routing, NAT) · 🟨 Nên biết (switching) · 🟦 Nâng cao (VLAN) · Kiến thức cần có trước: [01. Mô hình OSI và TCP/IP](01-osi-tcpip-model.md), [02. IPv4, subnet mask, CIDR](02-ipv4-subnet-cidr.md)
> Môi trường: `[WSL]` Ubuntu 24.04, `[PowerShell]` Windows

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

Sau bài này, bạn có thể:

- Giải thích một máy quyết định **gửi thẳng** hay **gửi qua gateway** như thế nào, và vai trò của **ARP** trong việc đó.
- Đọc được **bảng định tuyến** (routing table), hiểu **default gateway** và quy tắc **longest prefix match**.
- Dùng `ip route`, `ip route get`, `ip neigh`, `traceroute`, `tracepath` để biết gói tin đi đường nào.
- Giải thích **NAT**: SNAT/masquerade, DNAT/port forwarding, PAT — và vì sao gần như mọi kết nối của bạn đều đi qua NAT.
- Hiểu mạng của **WSL2** (chế độ NAT, localhost forwarding, mirrored mode).
- Chuẩn bị nền cho AWS: phân biệt **Internet Gateway** và **NAT Gateway**, đọc route table của public/private subnet.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "EC2 trong private subnet không `apt update` được" | Route table của subnet có đường ra Internet không (cần NAT Gateway) |
| "EC2 có public IP nhưng vẫn không SSH vào được" | Subnet có route tới Internet Gateway không, Security Group có mở không |
| "App chạy trong WSL, điện thoại cùng Wi-Fi không truy cập được" | WSL nằm sau một lớp NAT của Windows |
| "Container nghe port 80 nhưng phải gọi qua `localhost:8080`" | Docker `-p 8080:80` là **DNAT** |
| "Kết nối tới DB của đối tác bị timeout, chỉ từ server của mình" | Gói tin đi đường nào, IP nguồn sau NAT là gì (đối tác có thể chỉ cho phép một IP cụ thể) |
| "Mạng chậm/đứt ở đâu đó giữa server và người dùng" | `traceroute` để tìm đoạn có vấn đề |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Nhắc lại hai địa chỉ của một card mạng

Từ [bài 01](01-osi-tcpip-model.md), mỗi card mạng có:

- **Địa chỉ MAC** (tầng 2 — Data Link): gắn với phần cứng/card mạng ảo, dùng để giao gói tin **trong cùng một mạng cục bộ**.
- **Địa chỉ IP** (tầng 3 — Network): dùng để tìm đường **giữa các mạng**.

Một hình ảnh dễ nhớ: **IP giống địa chỉ nhà người nhận ghi trên bưu kiện** — giữ nguyên suốt hành trình. **MAC giống tên người giao hàng của từng chặng** — đổi ở mỗi bưu cục.

### 3.2. Switch và Router

| Thiết bị | Tầng | Làm việc với | Nhiệm vụ |
|---|---|---|---|
| **Switch** (bộ chuyển mạch) | 2 | Địa chỉ MAC | Nối các máy **trong cùng một mạng**, chuyển frame tới đúng cổng |
| **Router** (bộ định tuyến) | 3 | Địa chỉ IP | Nối **các mạng khác nhau**, chọn đường cho gói tin |

Router Wi-Fi ở nhà bạn thực chất là **nhiều thiết bị gộp một**: switch (các cổng LAN + Wi-Fi), router, NAT, DHCP server, DNS forwarder, firewall.

### 3.3. "Cùng mạng" nghĩa là gì?

Hai máy **cùng mạng** khi IP của chúng nằm trong **cùng một dải CIDR** ([bài 02](02-ipv4-subnet-cidr.md)). Ví dụ `192.168.1.25/24` và `192.168.1.40/24` cùng mạng `192.168.1.0/24`; còn `192.168.1.25/24` và `10.0.1.10` thì khác mạng.

Đây là câu hỏi đầu tiên **mọi máy** tự hỏi trước khi gửi bất kỳ gói tin nào: *"Người nhận có ở cùng mạng với mình không?"*

---

## 4. Giải thích chi tiết

### 4.1. 🟨 Switching: giao hàng trong cùng một mạng

**Switch học MAC như thế nào?** Switch giữ một **bảng MAC** (MAC address table): "MAC nào ở cổng nào".

1. Một frame đi vào cổng 3 với MAC nguồn `aa:aa` → switch ghi nhớ: `aa:aa` ở cổng 3.
2. Frame cần tới MAC đích `bb:bb`. Nếu bảng đã biết `bb:bb` ở cổng 5 → chỉ gửi ra cổng 5.
3. Nếu chưa biết → gửi ra **tất cả các cổng** (gọi là *flooding*), rồi học dần khi có trả lời.

**Broadcast domain** (miền quảng bá): tập hợp các máy nhận được một gói **broadcast** (gửi tới MAC `ff:ff:ff:ff:ff:ff` — "gửi cho tất cả"). Mọi máy nối với cùng một switch (hoặc chuỗi switch) nằm chung một broadcast domain. **Router chặn broadcast** — broadcast không đi sang mạng khác. DHCP DISCOVER ở [bài 03](03-dns-dhcp.md#46--dhcp--máy-mới-vào-mạng-lấy-ip-từ-đâu) chính là một broadcast.

**ARP — từ IP tìm ra MAC.** Máy bạn biết IP người nhận (`192.168.1.40`) nhưng frame tầng 2 cần MAC. Nó hỏi bằng broadcast:

```text
ARP request (broadcast):  "Ai có IP 192.168.1.40? Hãy báo cho 192.168.1.25 (MAC aa:aa)"
ARP reply   (unicast):    "192.168.1.40 là tôi, MAC của tôi là bb:bb"
```

Kết quả được lưu trong **ARP cache** (xem bằng `ip neigh`) để không phải hỏi lại liên tục.

🟦 **VLAN (Virtual LAN — mạng LAN ảo):** chia **một** switch vật lý thành **nhiều** broadcast domain tách biệt, như thể có nhiều switch. Doanh nghiệp dùng để tách mạng phòng kế toán, phòng kỹ thuật, máy khách… Ở mức Junior DevOps chỉ cần biết khái niệm: trên cloud, việc tách mạng làm bằng **VPC và subnet** chứ không cấu hình VLAN.

### 4.2. 🟥 Routing: quyết định đường đi

**Quy tắc ra quyết định của mọi máy** khi gửi gói tin tới IP đích `D`:

```text
D có nằm trong mạng của mình không?
 ├─ CÓ  → ARP tìm MAC của D → gửi THẲNG cho D
 └─ KHÔNG → tra bảng định tuyến → gửi cho router (gateway) phù hợp
            → ARP tìm MAC của GATEWAY (không phải của D!) → gửi cho gateway
```

Điểm hay bị hiểu nhầm: khi gửi ra Internet, máy bạn **không bao giờ** biết MAC của server đích. Nó chỉ cần MAC của gateway. Gateway lại làm y hệt với router kế tiếp — từng chặng một.

**Bảng định tuyến (routing table)** là danh sách các luật dạng: *"đích thuộc dải X → gửi qua cổng Y / tới router Z"*.

Ví dụ bảng định tuyến của một máy trong mạng nhà:

| Đích | Đi qua (gateway) | Card mạng | Ý nghĩa |
|---|---|---|---|
| `192.168.1.0/24` | — (trực tiếp) | `wlan0` | Máy trong cùng mạng: gửi thẳng |
| `0.0.0.0/0` | `192.168.1.1` | `wlan0` | **Mọi đích khác**: gửi cho router nhà |

**`0.0.0.0/0` là default route** (tuyến mặc định) — khớp với **mọi** IP (prefix `/0` nghĩa là không cần bit nào giống nhau). Router được chỉ định trong default route gọi là **default gateway**.

**Longest prefix match (khớp tiền tố dài nhất):** khi nhiều luật cùng khớp, luật có **prefix dài hơn** (cụ thể hơn) thắng.

Ví dụ bảng có `10.0.0.0/16 → local`, `10.0.5.0/24 → vpn`, `0.0.0.0/0 → internet`:

| Đích | Các luật khớp | Thắng | Lý do |
|---|---|---|---|
| `10.0.5.20` | `/16`, `/24`, `/0` | `10.0.5.0/24 → vpn` | `/24` dài nhất |
| `10.0.9.20` | `/16`, `/0` | `10.0.0.0/16 → local` | `/16` dài hơn `/0` |
| `8.8.8.8` | `/0` | `0.0.0.0/0 → internet` | Chỉ có default route khớp |

Theo tài liệu AWS, route table của VPC cũng hoạt động đúng như vậy: *"we direct traffic using the most specific route that matches the traffic. This is known as the longest prefix match."*

**Không có route nào khớp** và cũng không có default route → gói tin không đi được: lỗi `Network is unreachable`.

### 4.3. 🟥 TTL và `traceroute`

Mỗi gói IP có trường **TTL (Time To Live)** — khác với TTL của DNS, đây là **số chặng tối đa** gói tin được đi. Mỗi router giảm TTL đi 1. Khi TTL về 0, router **hủy gói** và gửi về thông báo ICMP *"Time Exceeded"* cho người gửi. Cơ chế này chống gói tin đi vòng vòng mãi khi cấu hình định tuyến bị lặp.

`traceroute` lợi dụng chính cơ chế đó:

1. Gửi gói với TTL = 1 → router **thứ 1** hủy và báo về → biết router thứ 1 là ai.
2. Gửi gói với TTL = 2 → router **thứ 2** báo về.
3. Cứ thế tăng TTL cho tới khi tới đích.

Mỗi chặng gửi **3 gói thử** → in 3 thời gian. Dấu `* * *` nghĩa là **không nhận được phản hồi trong thời gian chờ** — thường do router đó được cấu hình không trả lời ICMP hoặc firewall chặn, **không có nghĩa là mạng đứt ở đó**. Chỉ khi từ một chặng trở đi **toàn bộ** là `* * *` và đích không bao giờ tới, mới đáng nghi có vấn đề quanh chặng đó.

### 4.4. 🟥 NAT: vì sao gần như mọi kết nối đều đi qua nó

IPv4 chỉ có khoảng 4,3 tỷ địa chỉ — **không đủ** cho mọi thiết bị trên thế giới. Giải pháp: các mạng dùng **IP private** ([bài 02](02-ipv4-subnet-cidr.md)) bên trong, và một thiết bị ở biên dịch địa chỉ khi đi ra Internet. Việc dịch đó gọi là **NAT (Network Address Translation — biên dịch địa chỉ mạng)**.

**SNAT (Source NAT — đổi địa chỉ nguồn) / masquerade:** dùng khi **đi ra**.

```text
Laptop 192.168.1.25:51000 ──► Router ──► Internet
                                │ đổi NGUỒN thành IP public của router: 113.22.10.5:62001
                                │ ghi vào bảng: 62001 ↔ 192.168.1.25:51000
Server trả lời về 113.22.10.5:62001 ──► Router tra bảng ──► đổi ĐÍCH về 192.168.1.25:51000
```

- **Masquerade** là kiểu SNAT dùng IP hiện tại của card mạng đi ra (tiện khi IP public thay đổi — như mạng nhà).
- **PAT (Port Address Translation)** — hay "NAT overload": **nhiều** máy private dùng chung **một** IP public, phân biệt bằng **port**. Mạng nhà bạn chính là PAT.
- Bảng ghi nhớ ở giữa gọi là **bảng theo dõi kết nối** (connection tracking — *conntrack*).

**DNAT (Destination NAT — đổi địa chỉ đích) / port forwarding:** dùng khi **từ ngoài đi vào**.

```text
Internet ──► 113.22.10.5:8080 ──► Router: "port 8080 → 192.168.1.25:80" ──► Laptop :80
```

Không có luật DNAT thì từ Internet **không thể chủ động** kết nối vào máy private — router không biết chuyển cho ai. Đây là lý do máy sau NAT "tự nhiên" khó bị truy cập từ ngoài.

> ⚠️ NAT **không phải** firewall. Nó chỉ làm việc kết nối từ ngoài vào khó hơn như một tác dụng phụ. Kiểm soát truy cập thật sự là việc của firewall ([bài 05](05-tcp-udp-ports-firewall.md)) và Security Group.

**CGNAT (Carrier-Grade NAT) 🟨:** nhiều nhà mạng không cấp IP public cho router nhà bạn mà đặt thêm **một lớp NAT nữa** ở phía nhà mạng. Dấu hiệu: IP WAN trên trang quản trị router nằm trong dải `100.64.0.0/10` (dải dành riêng cho CGNAT) hoặc khác hẳn IP public mà trang kiểm tra IP báo về. Hệ quả: dù bạn cấu hình port forwarding trên router, từ Internet vẫn không vào được.

### 4.5. 🟥 Mạng của WSL2

Theo tài liệu Microsoft, mặc định WSL2 dùng **kiến trúc dựa trên NAT**: WSL là một máy ảo có card mạng ảo và **IP riêng**, nằm **phía sau Windows**. Windows đóng vai router + NAT cho WSL.

```text
WSL (172.29.214.55) ──► Windows (vEthernet WSL: 172.29.208.1) ──NAT──► Wi-Fi 192.168.1.25 ──► Router nhà ──NAT──► Internet
```

Hệ quả thực tế:

| Việc | Có được không (chế độ NAT mặc định) | Vì sao |
|---|---|---|
| Từ WSL ra Internet | Được | SNAT qua Windows rồi qua router |
| Trình duyệt Windows mở `http://localhost:8080` tới app trong WSL | Được | **localhost forwarding** (`localhostForwarding=true` mặc định): Windows chuyển `localhost:port` vào WSL |
| Từ WSL gọi app chạy trên Windows | Được, nhưng phải dùng **IP của Windows** nhìn từ WSL (IP default gateway trong WSL) | Với WSL, `localhost` là chính WSL |
| Điện thoại cùng Wi-Fi truy cập app trong WSL | **Không** (mặc định) | WSL nằm sau NAT của Windows; cần port proxy (`netsh interface portproxy`) hoặc mirrored mode |
| IP của WSL giữ nguyên qua các lần khởi động | **Không** | IP được cấp lại mỗi lần WSL khởi động |

**Mirrored mode 🟨:** trên Windows 11 22H2 trở lên, đặt `networkingMode=mirrored` trong mục `[wsl2]` của file `%UserProfile%\.wslconfig` sẽ chuyển WSL sang kiến trúc "phản chiếu" card mạng của Windows vào Linux. Theo Microsoft, lợi ích gồm: hỗ trợ IPv6, Windows và WSL gọi nhau bằng `127.0.0.1`, tương thích VPN tốt hơn, truy cập WSL trực tiếp từ mạng LAN. Đây là **thay đổi cấu hình máy** — giáo trình không yêu cầu bạn bật; nếu bật, bạn tự quyết định và nhớ rằng các ví dụ IP trong bài sẽ khác.

> Vì những khác biệt này, phần mạng "thật" (IP public, Security Group, route table) sẽ được làm lại trên EC2 ở tuần 11–12.

### 4.6. 🟥 Chuẩn bị cho AWS: Internet Gateway và NAT Gateway

Một VPC (học chi tiết ở Module 06) thực chất là một mạng private của bạn trên AWS, với các subnet và **route table** — đúng những khái niệm ở bài này.

| Thành phần | Vai trò | Kiểu NAT |
|---|---|---|
| **Internet Gateway (IGW)** | Cửa ra/vào Internet của VPC | **NAT 1-1**: theo tài liệu AWS, IGW *"logically provides the one-to-one NAT"* giữa IP private của instance và **IP public** của nó. Instance phải **có IP public** mới dùng được |
| **NAT Gateway** | Cho instance **không có IP public** (private subnet) **đi ra** Internet | **SNAT/PAT**: nhiều instance dùng chung IP public của NAT Gateway. Từ Internet **không** khởi tạo kết nối vào được |

**Public subnet và private subnet** khác nhau **chỉ ở route table**:

```text
Route table của PUBLIC subnet            Route table của PRIVATE subnet
┌───────────────┬────────────┐           ┌───────────────┬──────────────┐
│ Đích          │ Target     │           │ Đích          │ Target       │
├───────────────┼────────────┤           ├───────────────┼──────────────┤
│ 10.0.0.0/16   │ local      │           │ 10.0.0.0/16   │ local        │
│ 0.0.0.0/0     │ igw-xxxx   │           │ 0.0.0.0/0     │ nat-xxxx     │
└───────────────┴────────────┘           └───────────────┴──────────────┘
```

- `10.0.0.0/16 → local`: mọi máy trong VPC nói chuyện trực tiếp với nhau.
- Subnet có route `0.0.0.0/0` tới **IGW** → gọi là **public subnet**. Theo tài liệu AWS, subnet không có route tới IGW là private subnet — **kể cả khi** instance trong đó có IP public, nó vẫn không ra Internet được.
- NAT Gateway **nằm trong public subnet**, private subnet trỏ default route vào nó.

> 💰 **Chi phí:** Internet Gateway không tính phí (chỉ tính phí truyền dữ liệu). **NAT Gateway tính phí theo giờ** (khoảng 32 USD/tháng chưa kể phí dữ liệu) — đây là lý do dự án `taskhub` **không dùng NAT Gateway** trong kiến trúc chính. Xem [chiến lược chi phí](../00-ROADMAP/learning-roadmap.md#7-chiến-lược-kiểm-soát-chi-phí-aws).

### 4.7. Gặp lại ở đâu

| Khái niệm | Gặp lại |
|---|---|
| Route table, default route, longest prefix match | AWS VPC route table, VPC peering (Module 06), Terraform `aws_route_table` (Module 07) |
| SNAT / PAT | NAT Gateway (Module 06); container đi ra Internet qua NAT của Docker (Module 04) |
| DNAT / port forwarding | Docker `-p 8080:80`: Docker tạo luật DNAT (trên Linux dùng iptables) để chuyển `host:8080` vào `container:80` (Module 04); Kubernetes NodePort (Module 09) |
| Broadcast domain, ARP | Docker bridge network là một "switch ảo" (Module 04) |
| `traceroute` | Debug kết nối giữa server và dịch vụ bên ngoài (bài 08) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Server private không cài được package"

EC2 chạy PostgreSQL đặt trong private subnet. `sudo apt update` treo rồi báo timeout. Phân tích:

1. `ip route` trên EC2: default route trỏ tới router của VPC — bình thường, mọi instance đều vậy.
2. Quyết định thật nằm ở **route table của subnet** trên AWS: không có `0.0.0.0/0 → nat-...` → gói tin ra Internet bị bỏ.
3. Hướng giải quyết: thêm NAT Gateway (tốn phí), hoặc dùng VPC endpoint cho dịch vụ AWS, hoặc chuẩn bị sẵn image/package. Mỗi cách có chi phí và đánh đổi riêng — bạn sẽ quyết định ở Module 06.

### Ví dụ 2: Đối tác chỉ cho phép một IP

API của đối tác chỉ chấp nhận kết nối từ IP đã đăng ký. Bạn đăng ký IP **private** của server (`10.0.1.15`) → bị từ chối. Lý do: gói tin đi ra Internet đã bị **SNAT** thành IP public. Cái đối tác nhìn thấy là **IP sau NAT** — IP public của instance (qua IGW) hoặc IP của NAT Gateway. Kiểm tra từ chính server: `curl -s https://checkip.amazonaws.com`.

### Ví dụ 3: Hai mạng trùng dải IP

Công ty dùng VPN với dải `172.17.0.0/16`. Docker mặc định cũng dùng `172.17.0.0/16` cho mạng bridge. Kết quả: trên máy bật Docker, gói tin tới máy chủ công ty bị route vào Docker thay vì qua VPN — vì bảng định tuyến có một route **cụ thể hơn hoặc trùng** cho dải đó. Đây là lý do khi thiết kế VPC phải tránh dải IP **trùng** với mạng công ty và các VPC khác ([bài 02](02-ipv4-subnet-cidr.md)).

---

## 6. Sơ đồ kiến trúc

### 6.1. Đường đi từ WSL ra Internet qua nhiều lớp NAT

```text
 ┌─────────────── Laptop ────────────────────────────────┐
 │  WSL2  172.29.214.55                                   │
 │    │ default via 172.29.208.1                          │
 │    ▼                                                   │
 │  Windows (vEthernet WSL) 172.29.208.1   ← NAT lớp 1    │
 │    │ SNAT → 192.168.1.25                               │
 │  Card Wi-Fi 192.168.1.25                               │
 └────┼───────────────────────────────────────────────────┘
      ▼
 Router nhà  LAN 192.168.1.1 │ WAN 113.22.10.5   ← NAT lớp 2 (SNAT/PAT)
      ▼                         (nếu WAN là 100.64.x.x → còn NAT lớp 3: CGNAT của nhà mạng)
 Nhà mạng (ISP) ──► các router trên Internet ──► github.com
```

Server `github.com` chỉ thấy **IP public cuối cùng**, không biết gì về `172.29.x.x` hay `192.168.1.x`.

### 6.2. VPC với public subnet và private subnet

```text
                              Internet
                                  │
                         ┌────────▼────────┐
                         │ Internet Gateway│  (NAT 1-1 cho IP public)
                         └────────┬────────┘
 VPC 10.0.0.0/16                  │
 ┌────────────────────────────────┼──────────────────────────────────────┐
 │  PUBLIC subnet 10.0.1.0/24     │        PRIVATE subnet 10.0.11.0/24   │
 │  RT: 0.0.0.0/0 → igw           │        RT: 0.0.0.0/0 → nat           │
 │  ┌──────────────┐   ┌──────────▼──┐     ┌──────────────┐              │
 │  │ EC2 taskhub  │   │ NAT Gateway │◄────│ EC2 database │  đi ra:      │
 │  │ 10.0.1.15    │   │ (IP public) │     │ 10.0.11.20   │  SNAT qua NAT│
 │  │ + IP public  │   └─────────────┘     │ không IP     │  đi vào từ   │
 │  └──────────────┘                       │ public       │  Internet: ✗ │
 │        ▲ 10.0.0.0/16 → local ───────────►└──────────────┘              │
 └────────────────────────────────────────────────────────────────────────┘
```

> Kiến trúc trên là để **hiểu khái niệm**. Dự án `taskhub` chính sẽ đơn giản hơn để tránh phí NAT Gateway — chi tiết ở Module 06.

---

## 7. Các câu lệnh cần biết

> `traceroute` có thể chưa có trong WSL. Kiểm tra: `which traceroute tracepath`. Nếu cần và bạn đồng ý cài: `sudo apt install -y traceroute`.

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ip addr` (`ip a`) | Card mạng và IP của máy | 🟥 |
| `ip route` (`ip r`) | Xem bảng định tuyến | 🟥 |
| `ip route get <ip>` | Hỏi kernel: gửi tới IP này sẽ đi đường nào | 🟥 |
| `ip neigh` | Xem ARP cache (IP ↔ MAC trong mạng cục bộ) | 🟨 |
| `traceroute <đích>` | Liệt kê các router trên đường tới đích | 🟥 |
| `tracepath <đích>` | Giống traceroute, không cần root, kèm thông tin MTU | 🟨 |
| `curl -s https://checkip.amazonaws.com` | Xem IP public mà Internet nhìn thấy (sau mọi lớp NAT) | 🟥 |
| `ipconfig` / `route print` / `tracert` | `[PowerShell]` Tương đương phía Windows | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra dưới đây là **minh họa** từ WSL2 chế độ NAT. Dải IP của WSL (`172.x.x.x`) thay đổi theo máy và theo lần khởi động.

### `ip addr` — máy mình có những IP nào

```bash
ip -brief addr
```

```text
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             172.29.214.55/20 fe80::215:5dff:fe3a:1b2c/64
```

`-brief` (`-br`) in mỗi card một dòng. `eth0` có IP `172.29.214.55` trong mạng `/20`. `lo` là **loopback** — card mạng ảo chỉ dùng nội bộ máy (`127.0.0.1`).

### `ip route` — bảng định tuyến

```bash
ip route
```

```text
default via 172.29.208.1 dev eth0 proto kernel
172.29.208.0/20 dev eth0 proto kernel scope link src 172.29.214.55
```

| Phần | Ý nghĩa |
|---|---|
| `default via 172.29.208.1` | Default route (`0.0.0.0/0`): mọi đích không khớp luật khác → gửi cho gateway `172.29.208.1` (chính là Windows) |
| `dev eth0` | Đi ra qua card `eth0` |
| `172.29.208.0/20 ... scope link` | Mạng **kết nối trực tiếp**: đích trong dải này được gửi **thẳng** (không qua gateway) |
| `src 172.29.214.55` | IP nguồn sẽ dùng khi gửi theo luật này |
| `proto kernel` | Luật được tạo tự động khi cấu hình IP (không phải do người thêm tay) |

> Trên một server có Docker, bạn sẽ thấy thêm dòng như `172.17.0.0/16 dev docker0` — đó là mạng của container (Module 04).

### `ip route get` — hỏi thẳng kernel

```bash
ip route get 8.8.8.8
ip route get 172.29.208.1
ip route get 127.0.0.1
```

```text
8.8.8.8 via 172.29.208.1 dev eth0 src 172.29.214.55 uid 1000
    cache
172.29.208.1 dev eth0 src 172.29.214.55 uid 1000
    cache
local 127.0.0.1 dev lo src 127.0.0.1 uid 1000
    cache <local>
```

- `8.8.8.8` → có chữ **`via`** → đi qua gateway.
- `172.29.208.1` → **không có `via`** → cùng mạng, gửi thẳng.
- `127.0.0.1` → **`local ... dev lo`** → không hề ra khỏi máy.

Đây là lệnh debug routing tốt nhất: không cần tự đọc và áp quy tắc longest prefix match bằng mắt — kernel làm giúp và trả lời đúng điều nó sẽ làm.

### `ip neigh` — ARP cache

```bash
ping -c 1 172.29.208.1 > /dev/null
ip neigh
```

```text
172.29.208.1 dev eth0 lladdr 00:15:5d:a1:b2:c3 REACHABLE
```

`lladdr` (link-layer address) là **MAC** của gateway. Trạng thái `REACHABLE` = vừa xác nhận liên lạc được; `STALE` = đã lâu chưa xác nhận lại (vẫn dùng được); `FAILED` = hỏi ARP mà không ai trả lời → có thể máy đích không tồn tại hoặc không cùng mạng thật.

> Bạn sẽ **chỉ** thấy MAC của các máy trong cùng mạng — thường chỉ là gateway. Không bao giờ thấy MAC của `github.com`.

### `traceroute` — các chặng trên đường đi

```bash
traceroute -n 8.8.8.8
```

```text
traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 60 byte packets
 1  172.29.208.1   0.412 ms  0.380 ms  0.371 ms
 2  192.168.1.1    2.105 ms  2.090 ms  2.311 ms
 3  100.72.0.1     8.551 ms  8.902 ms  9.013 ms
 4  * * *
 5  113.171.35.1   10.204 ms  10.155 ms  11.021 ms
 ...
11  8.8.8.8        32.118 ms  31.904 ms  32.402 ms
```

| Phần | Ý nghĩa |
|---|---|
| `30 hops max` | Tối đa 30 chặng (TTL tối đa 30) |
| Hop 1 `172.29.208.1` | Windows — gateway của WSL |
| Hop 2 `192.168.1.1` | Router nhà |
| Hop 3 `100.72.0.1` | Dải `100.64.0.0/10` → dấu hiệu **CGNAT** của nhà mạng |
| Hop 4 `* * *` | Router này không trả lời — **bình thường** vì các chặng sau vẫn tiếp tục |
| 3 con số mỗi dòng | Thời gian khứ hồi của 3 gói thử |

| Tham số | Ý nghĩa |
|---|---|
| `-n` | Không tra tên DNS cho từng IP → nhanh hơn nhiều, nên dùng mặc định |
| `-I` | Dùng gói ICMP thay vì UDP (cần `sudo`) — thử khi bị chặn |
| `-T -p 443` | Dùng gói TCP tới port 443 (cần `sudo`) — xuyên qua được firewall chỉ mở web |
| `-m 15` | Giới hạn số chặng tối đa |

> ⚠️ Trên WSL chế độ NAT, `traceroute` có thể chỉ thấy hop 1 rồi toàn `* * *`, do lớp NAT/firewall của Windows không chuyển gói ICMP "Time Exceeded" về. Nếu gặp: thử `sudo traceroute -I -n 8.8.8.8`, và so sánh với `tracert -d 8.8.8.8` chạy trong PowerShell. Ghi lại khác biệt vào báo cáo lab.

### `tracepath` 🟨

```bash
tracepath -n 8.8.8.8
```

Giống `traceroute` nhưng không cần quyền root, và in thêm `pmtu` (*path MTU* — kích thước gói lớn nhất đi được trên đường). Thường có sẵn trên Ubuntu.

### `curl checkip` — IP mà Internet nhìn thấy

```bash
curl -s https://checkip.amazonaws.com
```

```text
113.22.10.5
```

Dịch vụ này của AWS trả về đúng một dòng: **IP nguồn của bạn sau mọi lớp NAT**. So sánh với `ip addr` để thấy NAT đã thay đổi IP như thế nào.

### Phía Windows `[PowerShell]`

```powershell
ipconfig | Select-String -Context 0,4 "WSL"
route print -4 | Select-Object -First 25
tracert -d 8.8.8.8
```

- `ipconfig`: tìm card `vEthernet (WSL...)` — IP của nó chính là **gateway** trong `ip route` của WSL.
- `route print -4`: bảng định tuyến IPv4 của Windows. Dòng `0.0.0.0  0.0.0.0  192.168.1.1 ...` là default route của Windows.
- `tracert -d`: traceroute của Windows (`-d` = không tra DNS). Windows dùng ICMP thay vì UDP.

---

## 9. Bài thực hành từng bước

**Lab: Vẽ bản đồ đường đi từ WSL ra Internet** · `[WSL]` + `[PowerShell]` · ~60 phút

Ghi câu trả lời và sơ đồ vào `~/devops-lab/02-networking/lab04-routing.md`.

### Bước 1 — IP và bảng định tuyến của WSL

```bash
ip -brief addr
ip route
```

❓ IP của WSL là gì, thuộc mạng nào (CIDR)? Default gateway là IP nào? Card `lo` dùng làm gì?

### Bước 2 — Hỏi kernel từng đích

```bash
GW=$(ip route show default | awk '{print $3}')
echo "Gateway: $GW"
for dst in 8.8.8.8 "$GW" 127.0.0.1 10.0.0.1; do
  echo "== $dst =="; ip route get "$dst"
done
```

❓ Với mỗi đích, gói tin đi **thẳng**, qua **gateway**, hay **không rời khỏi máy**? Vì sao `10.0.0.1` (một IP private) cũng đi qua gateway?

### Bước 3 — ARP

```bash
ping -c 2 "$GW"
ip neigh
```

❓ MAC của gateway là gì? Trạng thái là gì? Vì sao không thấy MAC của `8.8.8.8` dù vừa định tuyến tới nó?

### Bước 4 — Phía Windows `[PowerShell]`

```powershell
ipconfig
route print -4 | Select-Object -First 25
```

❓ Card nào có IP trùng với gateway của WSL? IP Wi-Fi/Ethernet của Windows là gì? Default gateway của Windows là gì?

### Bước 5 — Traceroute

```bash
traceroute -n -m 15 8.8.8.8 || sudo traceroute -I -n -m 15 8.8.8.8
```

Và trong PowerShell:

```powershell
tracert -d -h 15 8.8.8.8
```

❓ Ghi lại từng hop: IP, đoán đó là thiết bị gì (Windows, router nhà, nhà mạng…). Có hop nào `* * *` không, và có phải mạng đứt ở đó không? WSL và Windows cho kết quả khác nhau ở đâu? Hop nào trong dải `100.64.0.0/10` không?

### Bước 6 — IP mà Internet nhìn thấy

```bash
curl -s https://checkip.amazonaws.com
```

❓ IP này có xuất hiện trong `ip addr` của WSL hay `ipconfig` của Windows không? Nếu bạn vào được trang quản trị router nhà, so sánh với IP WAN của router: giống nhau hay khác (khác → có CGNAT)?

> Không vào được trang quản trị router cũng không sao — ghi "chưa kiểm tra được" và dựa vào kết quả traceroute.

### Bước 7 — Vẽ bản đồ

Dựa vào Bước 1–6, vẽ lại sơ đồ giống mục 6.1 **bằng số liệu thật của bạn**: có bao nhiêu lớp NAT, mỗi lớp đổi IP nguồn từ đâu sang đâu.

### Bước 8 — Commit

```bash
cp ~/devops-lab/02-networking/lab04-routing.md ~/devops-journey/week04/
cd ~/devops-journey
git add week04/lab04-routing.md
git commit -m "docs(network): lab 04 - routing and NAT map from WSL"
git push
```

---

## 10. Kết quả mong đợi

- **Bước 1:** WSL có IP trong dải private (thường `172.16.0.0/12`, mạng `/20`), default gateway là IP `.1` của dải đó. `lo` = `127.0.0.1`, chỉ dùng nội bộ.
- **Bước 2:** `8.8.8.8` và `10.0.0.1` có `via <gateway>` (đi qua gateway); gateway không có `via` (cùng mạng); `127.0.0.1` là `local dev lo`. `10.0.0.1` đi qua gateway vì nó **không nằm trong mạng của WSL** — "private" không có nghĩa là "cùng mạng"; chỉ có default route khớp với nó.
- **Bước 3:** Thấy MAC của gateway với trạng thái `REACHABLE`. Không thấy MAC của `8.8.8.8` vì nó **không cùng mạng** — máy bạn chỉ cần MAC của gateway; các chặng sau tự lo.
- **Bước 4:** Card `vEthernet (WSL...)` có IP **trùng** gateway của WSL → Windows chính là router của WSL.
- **Bước 5:** Hop 1 là gateway WSL (chỉ có ở kết quả WSL), hop tiếp theo là router nhà, rồi tới mạng nhà cung cấp. `* * *` lẻ tẻ là bình thường. Kết quả `tracert` của Windows **thiếu** hop WSL và có thể **đầy đủ hơn** ở các hop sau.
- **Bước 6:** IP public **không xuất hiện** trong cấu hình máy bạn → nó thuộc về router (hoặc thiết bị CGNAT của nhà mạng). Thường có **2 lớp NAT** (Windows + router), có thể **3** nếu có CGNAT.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `connect: Network is unreachable` | Không có route nào khớp đích (thiếu default route, card mạng chưa có IP) | `ip route` — có `default via ...` không? `ip addr` — card có IP chưa? |
| Ping gateway được nhưng ra Internet không được | Gateway không có đường ra tiếp, NAT phía router/Windows có vấn đề, hoặc DNS hỏng (ping theo tên) | Ping theo **IP**: `ping 8.8.8.8`. Được → nghi DNS ([bài 03](03-dns-dhcp.md)). Không được → `traceroute -n 8.8.8.8` xem dừng ở đâu |
| Traceroute toàn `* * *` từ hop 2 trên WSL | NAT/firewall của Windows không chuyển ICMP Time Exceeded | Thử `sudo traceroute -I`, so sánh với `tracert` trên Windows |
| Thiết bị khác trong LAN không vào được app trong WSL | WSL nằm sau NAT của Windows | Bình thường ở chế độ NAT. Dùng `netsh interface portproxy` hoặc mirrored mode (thay đổi cấu hình — tự quyết định) |
| Từ WSL gọi `localhost:5432` không tới PostgreSQL cài trên Windows | Trong WSL, `localhost` là chính WSL | Dùng IP gateway của WSL; hoặc chạy PostgreSQL trong Docker/WSL |
| Bật VPN công ty thì Docker hoặc WSL mất mạng | Dải IP trùng nhau hoặc VPN đè route | `ip route` trước và sau khi bật VPN, tìm dải trùng; đổi dải của Docker/VPC khi thiết kế |
| EC2 có public IP nhưng không vào được | Subnet thiếu route `0.0.0.0/0 → igw`, hoặc Security Group/NACL chặn | Kiểm tra route table của subnet trước, rồi tới Security Group (Module 06) |

---

## 12. Đọc log và xử lý lỗi

Lỗi định tuyến hiếm khi nằm trong file log — chúng hiện ra dưới dạng **thông báo lỗi kết nối**. Học cách đọc chúng:

| Thông báo | Ở tầng nào | Gợi ý |
|---|---|---|
| `Network is unreachable` | 3 — máy **của bạn** không có route | Xem `ip route` trên chính máy này |
| `No route to host` | 3 — thường là có route nhưng **không tới được máy đích** (ARP thất bại trong cùng mạng, hoặc router/firewall báo không tới được) | `ip neigh` (thấy `FAILED`?), máy đích có đang bật không, firewall |
| `Destination Host Unreachable` (trong output ping) | 3 — router hoặc chính máy bạn báo không tìm được máy đích | Nếu do `From <IP của bạn>` → máy bạn hỏi ARP không có ai trả lời |
| `Time to live exceeded` (trong output ping) | 3 — gói tin đi quá số chặng, có thể có **vòng lặp định tuyến** | `traceroute` xem có IP nào lặp lại liên tục |
| `Connection timed out` | Có thể ở tầng 3 hoặc 4 — gói tin đi mà **không ai trả lời** | Thường do firewall **bỏ gói im lặng** hoặc thiếu route ở phía trả về. Bài 05 phân tích kỹ |

**Quy trình debug "không kết nối được ra ngoài" (theo hướng từ trong ra ngoài):**

```text
1. ip addr                    → card có IP chưa?
2. ip route                   → có default route chưa?
3. ping <gateway>             → tới được router đầu tiên chưa? (ip neigh: MAC có REACHABLE?)
4. ping 8.8.8.8               → ra được Internet theo IP chưa?
5. traceroute -n 8.8.8.8      → nếu không, dừng ở chặng nào?
6. ping github.com            → DNS hoạt động chưa? (bài 03)
```

Mỗi bước thành công thì loại trừ được một tầng. Dừng ở bước nào → vấn đề nằm giữa bước đó và bước trước. Ghi lại vào `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Switch và router khác nhau thế nào? Router Wi-Fi nhà bạn đóng những vai trò gì?
2. Một máy quyết định gửi thẳng hay gửi qua gateway dựa vào đâu?
3. Khi máy bạn gửi gói tin tới `8.8.8.8`, frame tầng 2 mang MAC đích của ai? Vì sao?
4. ARP để làm gì? Vì sao ARP request phải là broadcast?
5. Broadcast domain là gì? Router làm gì với broadcast?
6. Default route là gì? Vì sao viết là `0.0.0.0/0`?
7. Bảng route có `10.0.0.0/16 → local`, `10.0.8.0/22 → vpn`, `0.0.0.0/0 → igw`. Gói tin tới `10.0.9.5`, `10.0.12.5`, `52.1.1.1` đi đâu? Giải thích.
8. `traceroute` hoạt động dựa trên cơ chế gì? Dấu `* * *` có nghĩa là mạng đứt không?
9. SNAT và DNAT khác nhau thế nào? Cho một ví dụ mỗi loại trong đời thường hoặc trong Docker.
10. PAT là gì? Vì sao cả nhà bạn dùng chung được một IP public?
11. Vì sao NAT không phải là firewall?
12. Trong WSL2 chế độ NAT, vì sao trình duyệt Windows vào được `localhost:8080` của WSL nhưng điện thoại cùng Wi-Fi thì không?
13. Internet Gateway và NAT Gateway khác nhau thế nào về chức năng, kiểu NAT và chi phí?
14. Public subnet và private subnet trên AWS khác nhau ở điểm nào duy nhất? Instance trong private subnet có IP public thì có ra Internet được không?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/04-solutions.md](solutions/04-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Đọc route table của VPC.** Cho VPC `10.20.0.0/16` với hai route table:

```text
RT-A (gắn với subnet 10.20.1.0/24)      RT-B (gắn với subnet 10.20.11.0/24)
10.20.0.0/16     local                  10.20.0.0/16     local
0.0.0.0/0        igw-111                10.30.0.0/16     pcx-222   (VPC peering)
                                        0.0.0.0/0        nat-333   (NAT Gateway nằm trong 10.20.1.0/24)
```

Trả lời và giải thích:
(a) Subnet nào là public, subnet nào là private?
(b) Instance `10.20.11.8` gửi tới `10.20.1.15`, `10.30.4.4`, `140.82.112.3` — mỗi gói đi qua target nào?
(c) Từ Internet có kết nối thẳng tới `10.20.11.8` được không? Vì sao?
(d) Nếu xóa route `0.0.0.0/0 → nat-333`, instance `10.20.11.8` còn làm được gì và mất gì?
(e) Đối tác bên ngoài thấy IP nguồn nào khi `10.20.11.8` gọi API của họ?

**Bài 2 — Longest prefix match bằng tay.** Một máy Linux có bảng route:

```text
default via 192.168.1.1 dev wlan0
10.0.0.0/8 via 10.8.0.1 dev tun0
10.42.0.0/16 dev docker0
192.168.1.0/24 dev wlan0
```

Gói tin tới các đích sau đi ra card nào, qua gateway nào: `10.42.3.7`, `10.1.2.3`, `192.168.1.77`, `1.1.1.1`, `10.42.0.0`? Giải thích tình huống khi bạn cần vào một server công ty có IP `10.42.5.10` qua VPN (`tun0`).

**Bài 3 — Đọc traceroute.** Phân tích output sau và cho biết vấn đề có thể nằm ở đâu, cần thu thập thêm thông tin gì:

```text
 1  10.0.1.1      0.5 ms   0.4 ms   0.4 ms
 2  100.66.8.17   1.2 ms   1.1 ms   1.3 ms
 3  * * *
 4  * * *
 5  * * *
 ...
30  * * *
```

**Bài 4 — NAT table.** Hai laptop `192.168.1.25` và `192.168.1.40` trong nhà cùng mở kết nối từ port nguồn `51000` tới `140.82.112.3:443`. Router có IP public `113.22.10.5`. Viết bảng NAT (conntrack) router có thể tạo ra, và giải thích router làm sao biết gói trả về thuộc laptop nào.

**Bài 5 — Thiết kế cho taskhub.** Viết một đoạn ngắn (đưa vào phần "Câu hỏi còn mở" của `docs/network-plan.md` trong [milestone v-pre](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-4--kế-hoạch-mạng)): nếu đặt PostgreSQL trên một EC2 riêng trong private subnet **không có NAT Gateway**, những việc gì sẽ không làm được (cập nhật package, backup lên S3…), và liệt kê các hướng giải quyết bạn đoán ra (không cần đúng hết — Module 06 sẽ trả lời).

**Bài 6 — Câu hỏi phỏng vấn.** Trả lời trong 2 phút: *"EC2 của bạn có public IP, Security Group đã mở port 22 cho IP của bạn, nhưng SSH vẫn timeout. Bạn kiểm tra những gì, theo thứ tự nào?"* (Chỉ tập trung phần routing của bài này; phần firewall sẽ bổ sung ở bài 05.)

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được quy tắc "cùng mạng → gửi thẳng, khác mạng → gửi gateway", và vì sao MAC đích là MAC của gateway.
- [ ] Đọc được output `ip route`, và dự đoán đúng kết quả `ip route get` trước khi chạy lệnh.
- [ ] Áp dụng longest prefix match đúng cho bất kỳ bảng route nào (Bài tập 1, 2).
- [ ] Vẽ được bản đồ NAT từ WSL ra Internet bằng số liệu thật của máy mình.
- [ ] Giải thích được Internet Gateway vs NAT Gateway và public vs private subnet chỉ bằng route table.
- [ ] Đọc được traceroute và không kết luận sai từ `* * *`.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Microsoft Learn — Accessing network applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking) | Chế độ NAT, localhost, mirrored mode | 2026-10-31 |
| [Microsoft Learn — Advanced settings configuration in WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) | `networkingMode`, `localhostForwarding` | 2026-10-31 |
| [AWS — How route priority works](https://docs.aws.amazon.com/vpc/latest/userguide/route-tables-priority.html) | Longest prefix match trong VPC | 2026-10-31 |
| [AWS — Enable internet access using an internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html) | IGW, NAT 1-1, public/private subnet | 2026-10-31 |
| [AWS — VPC with servers in private subnets and NAT](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-example-private-subnets-nat.html) | Kiến trúc tham chiếu có NAT Gateway | 2026-10-31 |
| [AWS — VPC Pricing](https://aws.amazon.com/vpc/pricing/) | Chi phí NAT Gateway | 2026-10-31 |
| [Linux Journey — Networking Nomad: Routing](https://labex.io/linuxjourney) | Ôn tập ngắn | 2026-10-31 |
| `man ip-route`, `man traceroute` (chạy trên máy) | Tra cứu chính thức | — |
