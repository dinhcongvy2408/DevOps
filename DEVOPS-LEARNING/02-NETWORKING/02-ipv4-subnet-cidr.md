# 02. IPv4, subnet mask và CIDR

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Mô hình OSI và TCP/IP](01-osi-tcpip-model.md)
> Môi trường: `[WSL]` Ubuntu 24.04 · Cần giấy bút — bài này **bắt buộc tính tay**

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

- Đổi qua lại giữa số nhị phân 8 bit và số thập phân — đủ để tính subnet.
- Giải thích cấu trúc địa chỉ IPv4: **phần mạng** (network) và **phần host**.
- Đọc và viết subnet mask theo cả hai cách: `255.255.255.0` và `/24` (**CIDR**).
- **Tự tính bằng tay**: số địa chỉ, network address, broadcast address, dải dùng được của một CIDR bất kỳ.
- Chia một dải lớn thành nhiều subnet nhỏ, và kiểm tra hai dải có **chồng lấn** (overlap) không.
- Nhận ra ngay các dải đặc biệt: private (RFC 1918), loopback, link-local, và biết vì sao chúng quan trọng trên AWS và Docker.
- Thiết kế bảng IP cho một VPC AWS gồm 4 subnet — có tính 5 địa chỉ AWS giữ lại.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Đây là kỹ năng mạng bạn sẽ dùng **nhiều nhất** khi làm cloud:

| Tình huống thật | Cần biết |
|---|---|
| Tạo VPC trên AWS: console hỏi "IPv4 CIDR block?" | Chọn dải đủ lớn, không trùng với mạng khác |
| Chia VPC thành subnet public/private ở 2 Availability Zone | Chia CIDR không chồng lấn, đủ IP cho từng subnet |
| Security Group rule: "Source: `0.0.0.0/0`" hay "`10.0.0.0/16`"? | Hiểu `/0`, `/16`, `/32` nghĩa là bao nhiêu địa chỉ |
| Terraform: `cidr_block = "10.0.1.0/24"` | Đọc và viết CIDR không cần công cụ |
| Docker container không truy cập được máy trong mạng công ty | Dải Docker `172.17.0.0/16` trùng dải mạng công ty |
| Kết nối VPC với VPN văn phòng / VPC khác (peering) | Hai bên **không được** trùng dải IP — sai từ đầu thì phải dựng lại |

> Sai CIDR khi tạo VPC rất **đắt**: không đổi được CIDR chính của VPC sau khi tạo. Muốn sửa phải tạo VPC mới và chuyển toàn bộ tài nguyên sang. Vì vậy kỹ năng này phải chắc chắn, không dựa vào may mắn.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Số nhị phân — chỉ cần đủ dùng

Máy tính lưu mọi thứ bằng **bit** (0 hoặc 1). 8 bit gọi là 1 **byte** (hay **octet** khi nói về IP). Một octet biểu diễn số từ 0 đến 255.

Mỗi vị trí bit có một "giá trị" — gấp đôi vị trí bên phải nó:

```text
Vị trí bit:   7    6    5    4    3    2    1    0
Giá trị:    128   64   32   16    8    4    2    1
```

**Nhị phân → thập phân:** cộng giá trị của các vị trí có bit `1`.

```text
1 1 0 0 0 0 0 0  = 128 + 64                         = 192
1 0 1 0 1 0 0 0  = 128 + 32 + 8                     = 168
1 1 1 1 1 1 1 1  = 128+64+32+16+8+4+2+1             = 255
```

**Thập phân → nhị phân:** lấy số, trừ dần cho 128, 64, 32… — trừ được thì ghi `1`, không trừ được ghi `0`.

```text
200: 200-128=72 (1) │ 72-64=8 (1) │ 8<32 (0) │ 8<16 (0) │ 8-8=0 (1) │ 0 (0) │ 0 (0) │ 0 (0)
     → 1 1 0 0 1 0 0 0
```

**Bảng phải thuộc lòng** — các giá trị của subnet mask chỉ có thể là một trong 9 số này (bit `1` luôn dồn về bên trái):

| Số bit 1 (từ trái) | Nhị phân | Thập phân |
|---|---|---|
| 0 | `00000000` | 0 |
| 1 | `10000000` | 128 |
| 2 | `11000000` | 192 |
| 3 | `11100000` | 224 |
| 4 | `11110000` | 240 |
| 5 | `11111000` | 248 |
| 6 | `11111100` | 252 |
| 7 | `11111110` | 254 |
| 8 | `11111111` | 255 |

Và lũy thừa của 2 (dùng để đếm số địa chỉ): 2¹=2, 2²=4, 2³=8, 2⁴=16, 2⁵=32, 2⁶=64, 2⁷=128, 2⁸=256, 2¹⁰=1024, 2¹²=4096, 2¹⁶=65.536.

### 3.2. Địa chỉ IPv4 là gì?

Một địa chỉ IPv4 là **32 bit**, viết thành 4 octet thập phân cách nhau bằng dấu chấm (dotted decimal):

```text
192      .168      .10       .25
11000000  10101000  00001010  00011001
```

32 bit → tổng cộng 2³² ≈ 4,3 tỷ địa chỉ. Con số này **không đủ** cho cả thế giới — đó là lý do có private IP, NAT ([bài 04](04-routing-nat-switching.md)) và IPv6.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Phần mạng và phần host

Mỗi địa chỉ IP gồm hai phần:

- **Phần mạng (network portion)**: các bit bên trái — giống nhau với mọi máy trong cùng một mạng. Giống **tên đường**.
- **Phần host (host portion)**: các bit bên phải — phân biệt từng máy trong mạng. Giống **số nhà**.

Hai máy có **cùng phần mạng** thì ở cùng một mạng → nói chuyện trực tiếp (qua ARP, tầng 2). Khác phần mạng → phải đi qua **router** ([bài 01](01-osi-tcpip-model.md#45--arp--nối-ip-với-mac)).

Câu hỏi là: **ranh giới** giữa hai phần nằm ở đâu? Đó là việc của subnet mask.

### 4.2. 🟥 Subnet mask và CIDR

**Subnet mask** (mặt nạ mạng con) là một dãy 32 bit: các bit `1` đánh dấu phần mạng, các bit `0` đánh dấu phần host. Bit `1` luôn liên tục từ trái sang.

```text
IP:     192.168.10.25    11000000.10101000.00001010.00011001
Mask:   255.255.255.0    11111111.11111111.11111111.00000000
                         └──────── phần mạng ─────┘└ host ┘
```

**CIDR** (Classless Inter-Domain Routing — đọc là "xai-đơ") là cách viết gọn: thay vì viết cả mask, chỉ ghi **số bit `1`** sau dấu `/`:

| CIDR | Subnet mask | Bit mạng | Bit host |
|---|---|---|---|
| `/8` | `255.0.0.0` | 8 | 24 |
| `/16` | `255.255.0.0` | 16 | 16 |
| `/20` | `255.255.240.0` | 20 | 12 |
| `/24` | `255.255.255.0` | 24 | 8 |
| `/26` | `255.255.255.192` | 26 | 6 |
| `/28` | `255.255.255.240` | 28 | 4 |
| `/32` | `255.255.255.255` | 32 | 0 |

`192.168.10.25/24` nghĩa là: máy có IP `192.168.10.25`, ở trong mạng mà 24 bit đầu là phần mạng.

> Bạn có thể gặp khái niệm **lớp mạng A, B, C** (classful) trong tài liệu cũ. Nó đã lỗi thời từ những năm 1990 — CIDR thay thế hoàn toàn. Không cần học, chỉ cần biết "Class C" người ta hay ngầm hiểu là `/24`.

### 4.3. 🟥 Bốn con số của một CIDR

Với mỗi CIDR `/n`, bạn phải tính được:

| Con số | Công thức / cách tính | Ví dụ với `192.168.10.0/24` |
|---|---|---|
| **Tổng số địa chỉ** | 2^(32 − n) | 2⁸ = 256 |
| **Network address** (địa chỉ mạng) | Tất cả bit host = 0. Đại diện cho cả mạng, không gán cho máy | `192.168.10.0` |
| **Broadcast address** (địa chỉ quảng bá) | Tất cả bit host = 1. Gửi tới mọi máy trong mạng | `192.168.10.255` |
| **Số địa chỉ dùng được** (mạng thông thường) | Tổng − 2 (trừ network và broadcast) | 254: `.1` → `.254` |

Những giá trị bạn sẽ gặp hằng ngày:

| CIDR | Tổng số địa chỉ | Dùng được (thông thường) | Dùng được trên AWS (trừ 5) |
|---|---|---|---|
| `/32` | 1 | — (một host cụ thể) | — |
| `/28` | 16 | 14 | 11 |
| `/27` | 32 | 30 | 27 |
| `/26` | 64 | 62 | 59 |
| `/24` | 256 | 254 | 251 |
| `/20` | 4.096 | 4.094 | 4.091 |
| `/16` | 65.536 | 65.534 | 65.531 |
| `/0` | toàn bộ 2³² | — (nghĩa là "mọi địa chỉ") | — |

**Quy luật cần cảm nhận:** mỗi khi số sau `/` **tăng 1**, số địa chỉ **giảm một nửa**. `/24` có 256, `/25` có 128, `/26` có 64.

> `/32` = đúng một địa chỉ. Bạn sẽ viết `203.0.113.45/32` trong Security Group để chỉ cho phép **riêng IP nhà bạn** SSH vào server. `0.0.0.0/0` = mọi địa chỉ IPv4 — "từ bất kỳ đâu trên Internet".

### 4.4. 🟥 Phương pháp tính nhanh: "kích thước khối" (block size)

Tính bằng nhị phân luôn đúng nhưng chậm. Cách nhanh mà kỹ sư hay dùng:

1. Xác định **octet "thú vị"** — octet mà ranh giới mạng/host rơi vào. Với `/24` trở lên thì là octet thứ 4; `/16` → `/23` là octet thứ 3; `/8` → `/15` là octet thứ 2.
2. **Kích thước khối** = 256 − giá trị mask ở octet đó. (Hoặc: 2^(số bit host trong octet đó).)
3. Các mạng bắt đầu ở **bội số của kích thước khối**: 0, khối, 2×khối, …
4. Mạng chứa IP của bạn là bội số **lớn nhất nhưng ≤** giá trị octet đó. Broadcast = mạng kế tiếp − 1.

**Ví dụ A — Tìm mạng của `172.30.98.229/20`** (chính là IP WSL ở [bài 01](01-osi-tcpip-model.md#8-giải-thích-câu-lệnh-và-tham-số)):

1. `/20` → ranh giới ở octet thứ 3 (bit 17–24). Mask octet 3 có 20 − 16 = 4 bit `1` → `11110000` = **240**.
2. Kích thước khối = 256 − 240 = **16**.
3. Bội số của 16: 0, 16, 32, 48, 64, 80, **96**, 112, …
4. Octet 3 là 98 → nằm giữa 96 và 112 → mạng bắt đầu ở **96**.

```text
Network:    172.30.96.0
Broadcast:  172.30.111.255   (mạng kế tiếp là 172.30.112.0, lùi 1)
Dùng được:  172.30.96.1 → 172.30.111.254
Tổng:       2^(32-20) = 4096 địa chỉ
```

Khớp với `brd 172.30.111.255` mà `ip addr` in ra ở bài 01. 

**Ví dụ B — Tìm mạng của `10.0.1.200/26`:**

1. `/26` → octet thứ 4, mask có 26 − 24 = 2 bit `1` → `11000000` = **192**.
2. Khối = 256 − 192 = **64**.
3. Bội số: 0, 64, 128, 192.
4. 200 nằm giữa 192 và 256 → mạng bắt đầu ở **192**.

```text
Network:    10.0.1.192
Broadcast:  10.0.1.255
Dùng được:  10.0.1.193 → 10.0.1.254   (62 địa chỉ)
```

### 4.5. 🟥 Chia subnet (subnetting) bằng tay

**Chia subnet** là cắt một dải lớn thành nhiều dải nhỏ bằng nhau. Quy tắc: muốn chia thành 2^k phần, **tăng prefix thêm k**.

| Muốn chia thành | Tăng prefix |
|---|---|
| 2 phần | +1 |
| 4 phần | +2 |
| 8 phần | +3 |
| 16 phần | +4 |
| 256 phần | +8 |

**Ví dụ C — Chia `192.168.10.0/24` thành 4 subnet:**

1. 4 = 2² → prefix mới = 24 + 2 = **/26**.
2. Mỗi subnet: 2^(32−26) = 64 địa chỉ. Khối = 64 ở octet 4.
3. Liệt kê:

| Subnet | Network | Dải dùng được | Broadcast |
|---|---|---|---|
| `192.168.10.0/26` | .0 | .1 → .62 | .63 |
| `192.168.10.64/26` | .64 | .65 → .126 | .127 |
| `192.168.10.128/26` | .128 | .129 → .190 | .191 |
| `192.168.10.192/26` | .192 | .193 → .254 | .255 |

Kiểm tra: 4 × 64 = 256 = đúng bằng `/24` ban đầu. Không có khoảng trống, không chồng lấn.

**Ví dụ D — Chia `10.0.0.0/16` thành các subnet `/24`:**

1. `/16` → `/24`: tăng 8 → 2⁸ = **256 subnet**.
2. Mỗi subnet 256 địa chỉ, khác nhau ở **octet thứ 3**:

```text
10.0.0.0/24    (10.0.0.0   → 10.0.0.255)
10.0.1.0/24    (10.0.1.0   → 10.0.1.255)
10.0.2.0/24    (10.0.2.0   → 10.0.2.255)
...
10.0.255.0/24  (10.0.255.0 → 10.0.255.255)
```

Đây là cách chia **dễ đọc nhất** và rất phổ biến trên AWS: nhìn octet thứ 3 là biết subnet nào.

**Ví dụ E — Chia `10.0.0.0/16` thành 16 subnet:**

1. 16 = 2⁴ → prefix mới = **/20**.
2. Mỗi subnet 4.096 địa chỉ. Ranh giới ở octet 3, khối = 256 − 240 = **16**.

| # | Subnet | Dải |
|---|---|---|
| 1 | `10.0.0.0/20` | 10.0.0.0 → 10.0.15.255 |
| 2 | `10.0.16.0/20` | 10.0.16.0 → 10.0.31.255 |
| 3 | `10.0.32.0/20` | 10.0.32.0 → 10.0.47.255 |
| … | … | … |
| 16 | `10.0.240.0/20` | 10.0.240.0 → 10.0.255.255 |

> **Một CIDR hợp lệ phải bắt đầu đúng ở bội số khối.** `10.0.8.0/20` **không** phải network address hợp lệ (8 không phải bội số của 16) — nó nằm bên trong `10.0.0.0/20`. AWS sẽ tự sửa nó về dạng chuẩn ([mục 4.9](#49--aws-giữ-lại-5-địa-chỉ-trong-mỗi-subnet)).

### 4.6. 🟥 Kiểm tra hai dải có chồng lấn không

Hai CIDR **chồng lấn** (overlap) nếu chúng có chung ít nhất một địa chỉ. Với CIDR, vì các khối luôn căn đúng bội số, chỉ có hai khả năng: **hoàn toàn tách biệt** hoặc **một dải nằm trọn trong dải kia**.

Cách kiểm tra bằng tay: đổi cả hai ra dạng **khoảng [đầu → cuối]** rồi so sánh.

| Dải A | Dải B | Đổi ra khoảng | Kết luận |
|---|---|---|---|
| `10.0.0.0/16` | `10.1.0.0/16` | 10.0.0.0–10.0.255.255 vs 10.1.0.0–10.1.255.255 | Tách biệt ✅ |
| `10.0.0.0/16` | `10.0.128.0/17` | 10.0.0.0–10.0.255.255 vs 10.0.128.0–10.0.255.255 | B nằm trong A ❌ |
| `172.16.0.0/12` | `172.17.0.0/16` | 172.16.0.0–172.31.255.255 vs 172.17.0.0–172.17.255.255 | B nằm trong A ❌ |
| `10.0.1.0/24` | `10.0.2.0/24` | khác octet 3 | Tách biệt ✅ |

Mẹo: dải nào có prefix **nhỏ hơn** (lớn hơn về kích thước) thì kiểm tra xem dải kia có nằm trong nó không.

### 4.7. 🟥 Các dải địa chỉ đặc biệt

| Dải | Tên | Ý nghĩa với DevOps |
|---|---|---|
| `10.0.0.0/8` | Private (RFC 1918) | Dải phổ biến nhất cho VPC: lớn, dễ chia |
| `172.16.0.0/12` | Private (RFC 1918) | Từ `172.16.0.0` đến `172.31.255.255`. Docker dùng một phần dải này; VPC mặc định của AWS dùng `172.31.0.0/16` |
| `192.168.0.0/16` | Private (RFC 1918) | Hay dùng ở mạng gia đình, văn phòng nhỏ |
| `127.0.0.0/8` | Loopback | `127.0.0.1` = `localhost` = chính máy này. Gói tin không bao giờ rời máy |
| `169.254.0.0/16` | Link-local | Địa chỉ tự sinh khi không có DHCP. AWS dùng `169.254.169.254` cho **dịch vụ metadata** của EC2 (Module 06) |
| `0.0.0.0` | "Không địa chỉ cụ thể" | Nghĩa tùy ngữ cảnh — xem bên dưới |
| `100.64.0.0/10` | 🟨 CGNAT (Carrier-Grade NAT) | Dải nhà mạng dùng khi chia một IP public cho nhiều khách hàng |

**Private IP** (địa chỉ riêng) — ba dải RFC 1918 — **không được định tuyến trên Internet**. Ai cũng dùng được trong mạng nội bộ của mình mà không cần xin phép. Hàng triệu mạng gia đình cùng dùng `192.168.1.0/24` mà không xung đột, vì các địa chỉ này không bao giờ ra Internet trực tiếp.

**Public IP** (địa chỉ công cộng) — mọi địa chỉ còn lại — là duy nhất trên toàn Internet, do các tổ chức quản lý cấp phát. Trên AWS, Public IPv4 **tính phí theo giờ** ([source-survey.md](../00-ROADMAP/source-survey.md#2-những-phát-hiện-quan-trọng-khi-khảo-sát)).

Máy có private IP muốn ra Internet phải đi qua **NAT** — thiết bị đổi IP private thành IP public ([bài 04](04-routing-nat-switching.md)).

**`0.0.0.0` có hai nghĩa thường gặp** (giới thiệu — dạy sâu ở [bài 05](05-tcp-udp-ports-firewall.md)):

- Trong **bảng route / Security Group**, `0.0.0.0/0` = **mọi địa chỉ** (route mặc định; "cho phép từ mọi nơi").
- Khi một chương trình **lắng nghe (bind)** trên `0.0.0.0` = nghe trên **mọi interface** của máy. Trái ngược với bind `127.0.0.1` = chỉ nhận kết nối từ chính máy đó. Đây là nguyên nhân của rất nhiều lỗi "chạy trên máy được, từ ngoài không vào được".

### 4.8. 🟥 Xung đột dải IP trong thực tế

Docker trên Linux mặc định tạo bridge `docker0` dùng dải **`172.17.0.0/16`** (container thường nhận `172.17.0.2`, `172.17.0.3`…), và các network bạn tạo thêm thường nhận các dải `172.18.0.0/16`, `172.19.0.0/16`, …

**Tình huống:** mạng công ty hoặc VPN dùng `172.17.0.0/16`. Bạn cài Docker trên laptop/server → kernel thấy `172.17.0.0/16` là **mạng nội bộ của `docker0`** → mọi gói tin tới máy công ty trong dải đó bị gửi vào bridge Docker thay vì đi qua VPN → không truy cập được.

Cách phòng tránh: **lập bảng IP trước** và chọn dải không trùng nhau cho: mạng văn phòng, VPN, VPC dev, VPC prod, Docker. Docker cho phép đổi dải mặc định (cấu hình `bip` / address pools trong `daemon.json` — Module 04).

Cùng lý do, khi thiết kế VPC hãy tránh `172.17.0.0/16`: nếu sau này chạy Docker trên EC2 trong VPC đó, sẽ có xung đột.

### 4.9. 🟥 AWS giữ lại 5 địa chỉ trong mỗi subnet

Theo [tài liệu AWS VPC — Subnet CIDR blocks](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html), **4 địa chỉ đầu và 1 địa chỉ cuối** của mỗi subnet không dùng được. Với subnet `10.0.0.0/24`:

| Địa chỉ | AWS dùng làm gì |
|---|---|
| `10.0.0.0` | Network address |
| `10.0.0.1` | Router của VPC |
| `10.0.0.2` | DNS server của AWS (địa chỉ gốc của VPC + 2) |
| `10.0.0.3` | Dự phòng cho tương lai |
| `10.0.0.255` | Broadcast — VPC không hỗ trợ broadcast nên giữ lại |

→ Số địa chỉ dùng được trên AWS = **tổng − 5**. Một subnet `/24` có **251** địa chỉ cho EC2, RDS, load balancer…

Các quy định khác từ cùng tài liệu:

- Kích thước subnet IPv4 cho phép: từ **`/28`** (16 địa chỉ) đến **`/16`** (65.536 địa chỉ).
- Các subnet trong cùng VPC **không được chồng lấn**.
- Nếu bạn nhập một CIDR chưa ở dạng chuẩn, AWS tự sửa: nhập `100.68.0.18/18` → AWS tạo `100.68.0.0/18`.

### 4.10. 🟦 IPv6 — chỉ cần nhận biết

IPv6 dùng **128 bit**, viết bằng hệ 16, chia 8 nhóm bằng dấu `:` — ví dụ `2001:db8:1234:1a00::1`. `::` là cách viết tắt cho một dãy nhóm toàn số 0. Những địa chỉ bạn sẽ gặp:

- `::1` — loopback (giống `127.0.0.1`).
- `fe80::...` — link-local, tự sinh trên mọi interface (bạn đã thấy trong `ip addr`).

Ở mức Junior, nhận ra được đó là IPv6 là đủ. Các lab trong khóa học dùng IPv4.

### 4.11. Gặp lại ở đâu

| Khái niệm | Gặp lại ở |
|---|---|
| CIDR, chia subnet, 5 địa chỉ AWS | Tạo VPC và subnet (Module 06), `cidr_block` trong Terraform (Module 07) |
| `/32`, `0.0.0.0/0` | Security Group rule (Module 06) |
| `127.0.0.1` vs `0.0.0.0` | Bind address của Spring Boot, Docker `-p` (Module 04) |
| Dải Docker `172.17.0.0/16` | Docker network (Module 04) |
| `169.254.169.254` | EC2 instance metadata, IAM role trên EC2 (Module 06) |
| Pod CIDR, Service CIDR | Kubernetes (Module 09) — lại là bài toán không chồng lấn |

---

## 5. Ví dụ thực tế

### Ví dụ 1: VPC quá nhỏ

Một nhóm tạo VPC `10.0.0.0/24` (256 địa chỉ) cho môi trường dev "vì chỉ có vài server". Sáu tháng sau họ chạy Kubernetes (EKS) — mỗi Pod cần một IP của VPC — và hết sạch IP. Không đổi được CIDR chính → phải thêm CIDR phụ hoặc dựng lại VPC.

**Bài học:** VPC nên rộng rãi (`/16` là lựa chọn phổ biến), subnet chia vừa đủ và **để dành khoảng trống** cho tương lai.

### Ví dụ 2: VPC dev và prod trùng nhau

Dev và prod đều dùng `10.0.0.0/16` vì "đó là giá trị mặc định trong tutorial". Sau này cần nối hai VPC (peering) để chạy job đồng bộ dữ liệu → **không thể**, vì AWS không cho peering hai VPC có CIDR chồng lấn.

**Bài học:** lập bảng IP cho toàn công ty, ví dụ: dev `10.10.0.0/16`, staging `10.20.0.0/16`, prod `10.30.0.0/16`, VPN văn phòng `10.100.0.0/16`.

### Ví dụ 3: Security Group mở quá rộng

Kỹ sư viết rule SSH (port 22) với source `0.0.0.0/0` "cho tiện". Ngay trong vài phút, log `/var/log/auth.log` ([Module 01 bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md)) xuất hiện hàng trăm lượt thử đăng nhập từ khắp thế giới.

**Bài học:** SSH chỉ cho phép từ `<IP-nhà-bạn>/32`, hoặc tốt hơn — không mở port 22 mà dùng SSM Session Manager (Module 06).

---

## 6. Sơ đồ kiến trúc

### 6.1. Cấu trúc một CIDR

```text
            10.0.1.0/24
 ┌──────────── 24 bit mạng ────────────┬─ 8 bit host ─┐
 │ 00001010 . 00000000 . 00000001 .    │  xxxxxxxx    │
 │    10    .     0    .     1    .    │   0 → 255    │
 └─────────────────────────────────────┴──────────────┘
   .0 = network      .1 → .254 = host      .255 = broadcast
   (trên AWS: .0 .1 .2 .3 .255 bị giữ lại → .4 → .254 dùng được)
```

### 6.2. VPC mẫu `10.0.0.0/16` chia cho 2 Availability Zone

```text
VPC 10.0.0.0/16  (65.536 địa chỉ) — ap-southeast-1
┌──────────────────────────────────┬──────────────────────────────────┐
│ AZ ap-southeast-1a               │ AZ ap-southeast-1b               │
│ ┌──────────────────────────────┐ │ ┌──────────────────────────────┐ │
│ │ public-a   10.0.1.0/24       │ │ │ public-b   10.0.2.0/24       │ │
│ │ (EC2 taskhub, Nginx)         │ │ │ (lab ALB tuần 14)            │ │
│ └──────────────────────────────┘ │ └──────────────────────────────┘ │
│ ┌──────────────────────────────┐ │ ┌──────────────────────────────┐ │
│ │ private-a  10.0.11.0/24      │ │ │ private-b  10.0.12.0/24      │ │
│ │ (RDS — lab tuần 14)          │ │ │ (RDS standby — lab tuần 14)  │ │
│ └──────────────────────────────┘ │ └──────────────────────────────┘ │
└──────────────────────────────────┴──────────────────────────────────┘
  Còn trống: 10.0.0.0/24, 10.0.3.0–10.0.10.x, 10.0.13.0 → 10.0.255.255 (dự phòng)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ip -4 addr` | Xem IPv4 và prefix của các interface | 🟥 |
| `ip route` | Xem các mạng mà máy biết (sơ lược — [bài 04](04-routing-nat-switching.md)) | 🟥 |
| `ipcalc <CIDR>` | **Kiểm tra lại** kết quả tự tính (cần cài gói `ipcalc`) | 🟨 |
| `python3 -c "import ipaddress; ..."` | Kiểm tra overlap, liệt kê subnet — có sẵn, không cần cài | 🟨 |

> ⚠️ **Quy tắc của bài này:** luôn **tự tính trên giấy trước**, sau đó mới dùng công cụ để **đối chiếu**. Phỏng vấn DevOps hay cho bài tính subnet không được dùng máy tính. Quan trọng hơn: khi đọc Terraform hay Security Group, bạn cần "nhìn là hiểu" `/20` lớn cỡ nào.

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa** trên Ubuntu 24.04. Định dạng `ipcalc` có thể khác chút tùy phiên bản gói.

### `ip -4 addr` — lấy IP và prefix của máy

```bash
ip -4 addr show eth0
```

```text
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet 172.30.98.229/20 brd 172.30.111.255 scope global eth0
       valid_lft forever preferred_lft forever
```

`-4` chỉ hiện IPv4. Thông tin cần cho bài này: `172.30.98.229/20` (IP + prefix) và `brd 172.30.111.255` (broadcast — dùng để kiểm tra kết quả tự tính).

### `ip route` — mạng nào là "nội bộ"

```bash
ip route
```

```text
default via 172.30.96.1 dev eth0 proto kernel
172.30.96.0/20 dev eth0 proto kernel scope link src 172.30.98.229
```

Dòng thứ hai chính là **network address + prefix** của mạng WSL — kernel đã tính sẵn. Mọi IP trong `172.30.96.0/20` được coi là cùng mạng.

### `ipcalc` — kiểm tra kết quả

Cài (bạn tự quyết định — chỉ là công cụ nhỏ):

```bash
sudo apt install ipcalc
```

```bash
ipcalc 192.168.10.64/26
```

```text
Address:   192.168.10.64        11000000.10101000.00001010.01 000000
Netmask:   255.255.255.192 = 26 11111111.11111111.11111111.11 000000
Wildcard:  0.0.0.63             00000000.00000000.00000000.00 111111
=>
Network:   192.168.10.64/26     11000000.10101000.00001010.01 000000
HostMin:   192.168.10.65        11000000.10101000.00001010.01 000001
HostMax:   192.168.10.126       11000000.10101000.00001010.01 111110
Broadcast: 192.168.10.127       11000000.10101000.00001010.01 111111
Hosts/Net: 62                    Class C, Private Internet
```

| Dòng | Ý nghĩa |
|---|---|
| `Address` / `Netmask` | IP và mask bạn nhập, kèm dạng nhị phân — **dấu cách** trong chuỗi nhị phân chính là ranh giới mạng/host |
| `Wildcard` | Mask đảo ngược (bit host = 1). Gặp trong cấu hình Cisco/ACL — Junior DevOps ít dùng |
| `Network` | Network address |
| `HostMin` / `HostMax` | Địa chỉ dùng được đầu tiên / cuối cùng (theo mạng thông thường, **chưa trừ** 3 địa chỉ AWS giữ thêm) |
| `Broadcast` | Broadcast address |
| `Hosts/Net` | Số host dùng được = tổng − 2 |
| `Class C, Private Internet` | Lớp mạng kiểu cũ (bỏ qua) + nhận diện dải private RFC 1918 |

Chia subnet bằng `ipcalc` (đối chiếu Ví dụ C):

```bash
ipcalc 192.168.10.0/24 -s 62 62 62 62
```

Tham số `-s` (split) nhận danh sách số host cần cho từng subnet. Kết quả liệt kê 4 subnet `/26`. Cú pháp này có thể khác giữa các phiên bản — xem `ipcalc --help`.

### `python3` + module `ipaddress` — có sẵn, không cần cài

Ubuntu có sẵn Python 3. Module chuẩn `ipaddress` rất tiện để kiểm tra:

```bash
python3 -c "
import ipaddress as ip
net = ip.ip_network('10.0.0.0/16')
print('Tổng địa chỉ:', net.num_addresses)
print('Có overlap 172.17.0.0/16?', net.overlaps(ip.ip_network('172.17.0.0/16')))
for s in list(net.subnets(new_prefix=20))[:3]:
    print(s, s[0], '->', s[-1])
"
```

```text
Tổng địa chỉ: 65536
Có overlap 172.17.0.0/16? False
10.0.0.0/20 10.0.0.0 -> 10.0.15.255
10.0.16.0/20 10.0.16.0 -> 10.0.31.255
10.0.32.0/20 10.0.32.0 -> 10.0.47.255
```

| Hàm | Ý nghĩa |
|---|---|
| `ip_network('10.0.0.0/16')` | Tạo đối tượng mạng. Báo lỗi `has host bits set` nếu CIDR không ở dạng chuẩn (ví dụ `10.0.8.0/20`) — rất tiện để bắt lỗi |
| `.num_addresses` | Tổng số địa chỉ |
| `.overlaps(other)` | `True` nếu chồng lấn |
| `.subnets(new_prefix=n)` | Chia thành các subnet `/n` |
| `s[0]`, `s[-1]` | Địa chỉ đầu (network) và cuối (broadcast) |

---

## 9. Bài thực hành từng bước

**Lab: Tính subnet bằng tay + thiết kế bảng IP cho VPC mẫu** · `[WSL]` + giấy bút · ~90 phút

Ghi kết quả vào `~/devops-lab/02-networking/lab02-answers.md`. Mỗi câu ghi **cách tính** chứ không chỉ đáp số.

### Bước 1 — Mạng của chính WSL

```bash
ip -4 addr show eth0
```

Lấy IP và prefix của bạn. **Trên giấy**, tính: kích thước khối, network address, broadcast, số địa chỉ. Sau đó đối chiếu với `brd` trong kết quả `ip addr` và dòng mạng trong `ip route`.

### Bước 2 — Luyện đổi nhị phân

Không dùng máy, đổi sang nhị phân: `10`, `172`, `224`, `248`, `99`. Đổi sang thập phân: `11110000`, `10101010`, `00111111`. Rồi kiểm tra bằng:

```bash
python3 -c "print(format(172,'08b'), int('10101010',2))"
```

### Bước 3 — Bốn con số

Với mỗi CIDR sau, tính tay: tổng địa chỉ, network, broadcast, dải dùng được, số dùng được trên AWS:

1. `10.0.5.77/24`
2. `192.168.1.130/25`
3. `10.0.37.4/20`
4. `172.31.200.9/28`

Đối chiếu bằng `ipcalc` (nếu đã cài) hoặc:

```bash
python3 -c "
import ipaddress as ip
for c in ['10.0.5.77/24','192.168.1.130/25','10.0.37.4/20','172.31.200.9/28']:
    n = ip.ip_interface(c).network
    print(c, '->', n, n[0], n[-1], n.num_addresses, 'AWS usable:', n.num_addresses-5)
"
```

> `ip_interface` chấp nhận IP có bit host (như `10.0.5.77/24`) và `.network` trả về mạng chứa nó — đúng việc bạn vừa làm bằng tay.

### Bước 4 — Chia subnet

Trên giấy:

1. Chia `10.0.0.0/22` thành 4 subnet bằng nhau. Liệt kê network và broadcast của từng cái.
2. Chia `192.168.50.0/24` thành 8 subnet bằng nhau.

Đối chiếu bằng `python3` với `.subnets(new_prefix=...)`.

### Bước 5 — Kiểm tra chồng lấn

Trên giấy, cho biết các cặp sau có chồng lấn không, giải thích bằng khoảng [đầu → cuối]:

1. `10.0.0.0/16` và `10.0.255.0/24`
2. `10.0.0.0/16` và `10.1.0.0/24`
3. `172.16.0.0/12` và `172.32.0.0/16`
4. `192.168.0.0/16` và `192.168.100.0/22`

Đối chiếu bằng `.overlaps()`.

### Bước 6 — Thiết kế bảng IP cho VPC mẫu `10.0.0.0/16`

Đây là bước chính. Yêu cầu (giống dự án thật):

- VPC `10.0.0.0/16` ở `ap-southeast-1`.
- 4 subnet `/24`: `public-a`, `private-a` ở `ap-southeast-1a`; `public-b`, `private-b` ở `ap-southeast-1b`.
- Quy ước dễ nhớ: public dùng octet 3 là **1, 2**; private dùng **11, 12**.
- Không chồng lấn với nhau và không chồng lấn với `172.17.0.0/16` (Docker).

Điền bảng sau vào file trả lời (tự tính cột "Dải" và "Dùng được trên AWS"):

| Tên | AZ | CIDR | Dải (đầu → cuối) | Dùng được trên AWS | Địa chỉ AWS giữ lại |
|---|---|---|---|---|---|
| public-a | ap-southeast-1a | `10.0.1.0/24` | ? | ? | ? |
| public-b | ap-southeast-1b | `10.0.2.0/24` | ? | ? | ? |
| private-a | ap-southeast-1a | `10.0.11.0/24` | ? | ? | ? |
| private-b | ap-southeast-1b | `10.0.12.0/24` | ? | ? | ? |

Rồi kiểm tra toàn bộ bằng một đoạn Python:

```bash
python3 -c "
import ipaddress as ip, itertools
vpc = ip.ip_network('10.0.0.0/16')
subs = {n: ip.ip_network(c) for n, c in [('public-a','10.0.1.0/24'),('public-b','10.0.2.0/24'),
        ('private-a','10.0.11.0/24'),('private-b','10.0.12.0/24')]}
for n, s in subs.items():
    print(f'{n:10} {s}  in VPC: {s.subnet_of(vpc)}  AWS usable: {s.num_addresses-5}')
for (a, x), (b, y) in itertools.combinations(subs.items(), 2):
    if x.overlaps(y): print('OVERLAP', a, b)
print('VPC overlap Docker 172.17.0.0/16:', vpc.overlaps(ip.ip_network('172.17.0.0/16')))
"
```

❓ Viết thêm 2–3 câu trả lời: vì sao chọn `/24` cho subnet mà không phải `/28` hay `/20`? Vì sao để trống `10.0.3.0` → `10.0.10.255`?

### Bước 7 — Commit

```bash
cp ~/devops-lab/02-networking/lab02-answers.md ~/devops-journey/week04/
cd ~/devops-journey
git add week04/lab02-answers.md
git commit -m "docs(network): lab 02 - subnetting and sample VPC plan"
git push
```

> Bảng IP **cho dự án taskhub** của riêng bạn (dùng dải khác) là [Bài tập 1](#14-bài-tập-tự-làm) — kết quả lưu vào repo `taskhub` theo [milestone tuần 4](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-4--kế-hoạch-mạng).

---

## 10. Kết quả mong đợi

- **Bước 1:** Với IP minh họa `172.30.98.229/20`: khối 16 ở octet 3, network `172.30.96.0`, broadcast `172.30.111.255`, 4.096 địa chỉ. Kết quả tự tính của bạn phải **khớp** `brd` và dòng route.
- **Bước 2:** `10`=`00001010`, `172`=`10101100`, `224`=`11100000`, `248`=`11111000`, `99`=`01100011`; `11110000`=240, `10101010`=170, `00111111`=63.
- **Bước 3:**

| CIDR | Network | Broadcast | Tổng | Dùng được (thường / AWS) |
|---|---|---|---|---|
| `10.0.5.77/24` | 10.0.5.0 | 10.0.5.255 | 256 | 254 / 251 |
| `192.168.1.130/25` | 192.168.1.128 | 192.168.1.255 | 128 | 126 / 123 |
| `10.0.37.4/20` | 10.0.32.0 | 10.0.47.255 | 4.096 | 4.094 / 4.091 |
| `172.31.200.9/28` | 172.31.200.0 | 172.31.200.15 | 16 | 14 / 11 |

- **Bước 4:** (1) `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`. (2) 8 subnet `/27`: `.0`, `.32`, `.64`, `.96`, `.128`, `.160`, `.192`, `.224` — broadcast lần lượt `.31`, `.63`, …, `.255`.
- **Bước 5:** (1) chồng lấn — nằm trong; (2) tách biệt; (3) tách biệt — `172.16.0.0/12` kết thúc ở `172.31.255.255`, còn `172.32.x.x` **không phải** private; (4) chồng lấn — nằm trong.
- **Bước 6:** Mỗi subnet `/24` có 256 địa chỉ, **251** dùng được trên AWS. Ví dụ `public-a`: dải `10.0.1.0 → 10.0.1.255`, AWS giữ `10.0.1.0`, `.1`, `.2`, `.3`, `.255`, dùng được `10.0.1.4 → 10.0.1.254`. Đoạn Python in `in VPC: True` cho cả 4, không có dòng `OVERLAP`, và `VPC overlap Docker ...: False`.
  - Vì sao `/24`: đủ rộng (251 IP) cho mọi lab và cả khi thêm container/Kubernetes sau này; dễ đọc (octet 3 = tên subnet); `/28` quá nhỏ, `/20` lãng phí với dự án nhỏ — nhưng cả hai đều "đúng" nếu có lý do.
  - Để trống: dành chỗ cho subnet mới (ví dụ thêm AZ thứ 3: `10.0.3.0/24` và `10.0.13.0/24`) mà không phá vỡ quy ước.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách tránh |
|---|---|---|
| Viết CIDR không ở dạng chuẩn: `10.0.8.0/20` | Không kiểm tra octet có phải bội số của khối không | Luôn tính khối trước. Python báo `has host bits set` |
| Tính số host dùng được trên AWS bằng tổng − 2 | Quên 3 địa chỉ AWS giữ thêm | Trên AWS luôn trừ **5** |
| Nghĩ `/16` nhỏ hơn `/24` | Nhầm chiều | Số sau `/` **càng lớn**, mạng **càng nhỏ** |
| Cho rằng `172.32.0.0` là private | Nhớ nhầm dải `172.16.0.0/12` | Dải chỉ tới `172.31.255.255` |
| Subnet chồng lấn khi thiết kế | Chia bằng mắt, không kiểm tra | Luôn đổi ra khoảng [đầu → cuối] hoặc dùng `.overlaps()` |
| VPC trùng dải với VPC khác, với VPN, hoặc với Docker `172.17.0.0/16` | Dùng giá trị mặc định của tutorial | Lập bảng IP cho mọi môi trường **trước khi** tạo |
| Security Group mở `0.0.0.0/0` cho SSH | Không hiểu `/0` là toàn bộ Internet | Dùng `/32` cho IP cụ thể |
| Dùng `ipcalc` thay cho việc tự tính | Ỷ lại công cụ | Tính tay trước, công cụ chỉ để đối chiếu |

---

## 12. Đọc thông báo lỗi và xử lý

Lỗi CIDR thường không xuất hiện dưới dạng log ứng dụng, mà dưới dạng **từ chối khi tạo tài nguyên** hoặc **mất kết nối khó hiểu**. Những thông báo bạn sẽ gặp:

| Thông báo (ví dụ) | Ở đâu | Nghĩa |
|---|---|---|
| `ValueError: 10.0.8.0/20 has host bits set` | Python `ipaddress` | CIDR không ở dạng chuẩn — network address phải là bội số của khối |
| `The CIDR '10.0.1.0/24' conflicts with another subnet` | AWS console / CLI khi tạo subnet | Subnet chồng lấn với subnet đã có trong VPC |
| `The CIDR '...' is invalid for this VPC` / không nằm trong VPC | AWS | Subnet nằm ngoài dải của VPC |
| `The new Subnet Mask is invalid` / prefix ngoài khoảng cho phép | AWS | Subnet nhỏ hơn `/28` hoặc lớn hơn `/16` |
| Container không ping được máy `172.17.x.x` trong mạng công ty, máy khác thì được | Docker host | Dải bị Docker chiếm — kiểm tra `ip route` xem `172.17.0.0/16 dev docker0` |

> Chữ của thông báo AWS ở trên là **minh họa** — câu chữ chính xác có thể khác. Từ khóa cần nhận ra: `conflicts`, `overlap`, `invalid CIDR`, `host bits`.

**Quy trình khi nghi xung đột dải IP:**

1. `ip route` — xem kernel coi những dải nào là "nội bộ" và gửi qua interface nào.
2. Tìm dải chứa IP đích. Nếu dòng route khớp là `dev docker0` hoặc `dev br-...` trong khi đích là máy công ty → xung đột với Docker.
3. Kiểm tra lại bằng tính tay hoặc `.overlaps()`.
4. Ghi vào `troubleshooting-journal.md`: dải nào trùng dải nào, ai chọn dải đó, đổi thế nào.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Một địa chỉ IPv4 có bao nhiêu bit? Mỗi octet biểu diễn được giá trị từ bao nhiêu đến bao nhiêu?
2. Phần mạng và phần host là gì? Hai máy phải giống nhau ở phần nào thì nói chuyện trực tiếp được?
3. `/20` tương ứng với subnet mask nào? Giải thích cách đổi.
4. Công thức tính tổng số địa chỉ của `/n`? Vì sao mạng thông thường trừ 2, còn AWS trừ 5?
5. Network address và broadcast address là gì? Có gán được cho máy không?
6. Tính tay network và broadcast của `10.20.77.130/19`.
7. Muốn chia `10.0.0.0/16` thành 32 subnet bằng nhau thì prefix mới là bao nhiêu, mỗi subnet có bao nhiêu địa chỉ?
8. Kể tên ba dải private RFC 1918. Vì sao private IP không đi thẳng ra Internet được?
9. `0.0.0.0/0` trong Security Group nghĩa là gì? `x.x.x.x/32` nghĩa là gì? Khi nào dùng mỗi cái?
10. App lắng nghe trên `127.0.0.1:8080` và trên `0.0.0.0:8080` khác nhau thế nào (ở mức giới thiệu)?
11. Vì sao không nên chọn `172.17.0.0/16` cho VPC sẽ chạy Docker?
12. Vì sao dev VPC và prod VPC không nên dùng cùng một CIDR?
13. `169.254.169.254` là gì trên EC2?
14. Vì sao chọn sai CIDR cho VPC lại là sai lầm "đắt"?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/02-solutions.md](solutions/02-solutions.md) — chỉ mở sau khi đã tự làm. Mọi bài tính **tay trước**, công cụ chỉ để đối chiếu.

**Bài 1 — Bảng IP cho dự án taskhub (bắt buộc).** Tạo file `docs/network-plan.md` trong repo `taskhub` theo đúng khung ở [milestone tuần 4](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-4--kế-hoạch-mạng). Yêu cầu:
- VPC dùng dải **`10.20.0.0/16`** (khác ví dụ trong bài để bạn phải tự tính).
- 4 subnet `public-a`, `private-a`, `public-b`, `private-b` ở `ap-southeast-1a`/`1b`, tự chọn kích thước, ghi lý do.
- Mỗi subnet: CIDR, dải đầu → cuối, số IP dùng được trên AWS, 5 địa chỉ AWS giữ lại.
- Chứng minh không chồng lấn với nhau, không chồng lấn với `172.17.0.0/16`.
- Bảng "Port cần mở" để trống phần chi tiết — sẽ điền sau [bài 05](05-tcp-udp-ports-firewall.md).
- Commit với message `docs(network): add VPC network plan`.

**Bài 2 — Tính nhanh (không dùng máy, giới hạn 10 phút).** Với mỗi IP, cho network/broadcast/số dùng được trên AWS:
(a) `10.0.200.17/21` (b) `192.168.7.99/27` (c) `172.20.15.255/22` (d) `10.1.1.1/30` (e) `10.255.255.254/8`.

**Bài 3 — Chọn kích thước.** Một subnet cần chứa tối đa 50 EC2 và để dư 50% cho tăng trưởng. Prefix nhỏ nhất (subnet nhỏ nhất) thỏa mãn trên AWS là bao nhiêu? Nếu cần 1000 IP thì sao?

**Bài 4 — Tìm lỗi thiết kế.** Một đồng nghiệp đề xuất:

```text
VPC:        10.50.0.0/16
public-a:   10.50.0.0/24
public-b:   10.50.1.0/23
private-a:  10.50.2.0/24
private-b:  10.50.8.0/20
db-a:       10.50.16.0/29
```

Tìm **tất cả** vấn đề (gợi ý: có ít nhất 3) và đề xuất bảng sửa lại.

**Bài 5 — Docker đang dùng dải nào?** (Cần Docker Desktop đang chạy.) Trong WSL chạy `docker network ls` và `docker network inspect bridge --format '{{json .IPAM.Config}}'`. Dải của network `bridge` là gì? Tạo thử một network: `docker network create labnet`, inspect nó, rồi xóa: `docker network rm labnet`. Network mới nhận dải nào? Viết 3 câu: dải này có chồng lấn với bảng IP ở Bài 1 không, và nếu công ty bạn dùng VPN `172.18.0.0/16` thì chuyện gì có thể xảy ra?

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Đổi được octet nhị phân ↔ thập phân trong vài giây, thuộc bảng 9 giá trị mask.
- [ ] Nhìn `/16`, `/20`, `/24`, `/26`, `/28`, `/32` là nói ngay được số địa chỉ.
- [ ] Tính tay network/broadcast của một IP bất kỳ bằng phương pháp kích thước khối, không cần nhị phân.
- [ ] Chia một dải thành 2^k subnet và liệt kê đúng network của từng cái.
- [ ] Kiểm tra được overlap bằng tay và giải thích vì sao.
- [ ] Hoàn thành Bài tập 1 (`network-plan.md`) và Bài tập 2 trong 10 phút không dùng công cụ.
- [ ] Giải thích được cho người khác vì sao AWS trừ 5 địa chỉ và vì sao phải tránh dải Docker.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS VPC — Subnet CIDR blocks](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html) | 5 địa chỉ AWS giữ lại, kích thước `/16`–`/28`, không chồng lấn | 2026-10-31 |
| [RFC 1918 — Address Allocation for Private Internets](https://www.rfc-editor.org/rfc/rfc1918) | Ba dải private chính thức | 2026-10-31 |
| [Docker docs — Bridge network driver](https://docs.docker.com/engine/network/drivers/bridge/) | Container trên bridge mặc định nhận địa chỉ `172.17.0.x/16`; cấu hình `bip` | 2026-10-31 |
| [Linux Journey — Networking Nomad: Subnetting](https://labex.io/linuxjourney) | Luyện thêm subnetting | 2026-10-31 |
| [Cisco Networking Academy — Networking Essentials](https://www.netacad.com/courses/networking/networking-essentials) | Học sâu IPv4/subnetting (tùy chọn) | 2026-10-31 (xác nhận qua tìm kiếm) |
| `python3 -c "help(__import__('ipaddress'))"` (chạy trên máy) | Tài liệu module `ipaddress` | — |
