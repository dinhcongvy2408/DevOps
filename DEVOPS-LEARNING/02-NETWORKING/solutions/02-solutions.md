# Lời giải — Bài 02: IPv4, subnet mask và CIDR

> ⚠️ Chỉ đọc sau khi đã tự làm **bằng tay**. Đối chiếu từng bước tính, không chỉ đáp số.

Quay lại bài: [02-ipv4-subnet-cidr.md](../02-ipv4-subnet-cidr.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** 32 bit, chia 4 octet. Mỗi octet từ 0 đến 255.

**2.** Phần mạng là các bit bên trái, giống nhau với mọi máy trong cùng một mạng; phần host là các bit bên phải, phân biệt từng máy. Hai máy có **cùng phần mạng** (theo cùng subnet mask) thì nói chuyện trực tiếp được ở tầng 2; khác phần mạng thì phải qua router.

**3.** `/20` = 20 bit `1`: octet 1 và 2 đủ 8 bit (`255.255`), octet 3 có 4 bit (`11110000` = 240), octet 4 = 0 → `255.255.240.0`.

**4.** Tổng = 2^(32 − n). Mạng thông thường trừ 2: network address và broadcast address. AWS trừ 5: network, router VPC (`.1`), DNS (`.2`), dự phòng (`.3`), và địa chỉ cuối (broadcast — VPC không hỗ trợ broadcast).

**5.** Network address: mọi bit host = 0, đại diện cho cả mạng. Broadcast: mọi bit host = 1, gửi tới mọi máy trong mạng. Cả hai **không** gán cho máy.

**6.** `10.20.77.130/19`: `/19` → octet 3 có 3 bit mạng → mask 224 → khối 32. Bội số 32: 0, 32, **64**, 96. 77 nằm giữa 64 và 96 → network `10.20.64.0`, broadcast `10.20.95.255`. Tổng 2¹³ = 8.192 địa chỉ.

**7.** 32 = 2⁵ → prefix mới `/16 + 5 = /21`. Mỗi subnet 2^(32−21) = 2.048 địa chỉ (2.043 dùng được trên AWS).

**8.** `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Các router trên Internet được cấu hình không định tuyến các dải này (chúng không duy nhất — hàng triệu mạng cùng dùng), nên máy có private IP muốn ra Internet phải qua NAT đổi sang IP public.

**9.** `0.0.0.0/0` = mọi địa chỉ IPv4 — "từ bất kỳ đâu". `x.x.x.x/32` = đúng một địa chỉ. Dùng `0.0.0.0/0` cho dịch vụ công khai (port 80/443 của web). Dùng `/32` cho truy cập quản trị từ một IP cố định (SSH từ IP nhà bạn) hoặc một máy cụ thể.

**10.** App nghe `127.0.0.1:8080` chỉ nhận kết nối từ **chính máy đó** (qua loopback). App nghe `0.0.0.0:8080` nhận kết nối tới **mọi interface** của máy, kể cả từ máy khác. Bài 05 dạy chi tiết.

**11.** Docker mặc định dùng `172.17.0.0/16` cho bridge `docker0`. Nếu VPC (hoặc subnet trong đó) cũng dùng dải này, trên EC2 chạy Docker, kernel sẽ coi các IP `172.17.x.x` là của bridge Docker → gói tin tới máy khác trong VPC có IP thuộc dải đó bị gửi nhầm vào bridge.

**12.** Hai VPC trùng CIDR không thể kết nối với nhau (VPC peering, Transit Gateway, VPN) vì router không phân biệt được một địa chỉ thuộc bên nào. Ngoài ra, khó tránh nhầm lẫn khi vận hành.

**13.** Địa chỉ link-local mà EC2 dùng để truy cập **dịch vụ metadata** (instance metadata): thông tin về chính instance, và thông tin đăng nhập tạm thời của IAM role gắn vào instance (Module 06).

**14.** Không đổi được CIDR chính của VPC sau khi tạo. Sửa nghĩa là tạo VPC mới và di chuyển mọi tài nguyên (EC2, RDS, load balancer, cấu hình peering/VPN) — tốn thời gian, có rủi ro gián đoạn.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Bảng IP cho dự án taskhub

Không có đáp án duy nhất. Một thiết kế đạt yêu cầu theo đúng quy ước của bài:

```markdown
# Network plan — taskhub

## VPC
| Thuộc tính | Giá trị | Lý do |
|---|---|---|
| CIDR | 10.20.0.0/16 | 65.536 địa chỉ, dư cho mở rộng; không trùng 172.17.0.0/16 của Docker, không trùng VPC mặc định 172.31.0.0/16 |
| Region | ap-southeast-1 | gần Việt Nam |

## Subnets
| Tên | AZ | CIDR | Dải | Public/Private | IP dùng được (AWS) | AWS giữ lại | Chứa gì |
|---|---|---|---|---|---|---|---|
| public-a | ap-southeast-1a | 10.20.1.0/24 | 10.20.1.0 → 10.20.1.255 | Public | 251 | .0 .1 .2 .3 .255 | EC2 taskhub |
| public-b | ap-southeast-1b | 10.20.2.0/24 | 10.20.2.0 → 10.20.2.255 | Public | 251 | .0 .1 .2 .3 .255 | (lab ALB tuần 14) |
| private-a | ap-southeast-1a | 10.20.11.0/24 | 10.20.11.0 → 10.20.11.255 | Private | 251 | .0 .1 .2 .3 .255 | (RDS — lab tuần 14) |
| private-b | ap-southeast-1b | 10.20.12.0/24 | 10.20.12.0 → 10.20.12.255 | Private | 251 | .0 .1 .2 .3 .255 | (RDS — lab tuần 14) |

Quy ước: octet 3 = 1x cho public, 1x+10 cho private; chữ cái cuối = AZ.
Để trống: 10.20.0.0/24, 10.20.3.0–10.20.10.255, 10.20.13.0 trở đi — dành cho AZ thứ ba hoặc tầng mới.

## Kiểm tra
- Mọi subnet nằm trong 10.20.0.0/16 (octet 1–2 đều là 10.20).
- Không chồng lấn: các subnet /24 khác nhau ở octet 3 (1, 2, 11, 12).
- Không chồng lấn với 172.17.0.0/16: khác ngay octet 1 (10 vs 172).

## Port cần mở
(điền sau bài 05)

## Câu hỏi còn mở
- Subnet private có cần ra Internet không? Nếu có thì cần NAT (tốn phí) — xem bài 04 và Module 06.
```

Tiêu chí chấm:

- [ ] Cả 4 subnet nằm trong VPC, không chồng lấn, network address ở dạng chuẩn.
- [ ] Số IP dùng được đã trừ 5.
- [ ] Có lý do cho kích thước đã chọn. Chọn `/20` hay `/26` cũng đạt nếu tính đúng và có lý do.
- [ ] Có chứng minh không trùng với dải Docker.

Kiểm tra lại bằng đoạn Python ở [Bước 6 của bài](../02-ipv4-subnet-cidr.md#bước-6--thiết-kế-bảng-ip-cho-vpc-mẫu-1000016), đổi `10.0` thành `10.20`.

### Bài 2 — Tính nhanh

| IP | Cách tính | Network | Broadcast | Tổng | Dùng được trên AWS |
|---|---|---|---|---|---|
| (a) `10.0.200.17/21` | Octet 3, mask 248, khối 8. 200 = 8 × 25 → đúng bội số | `10.0.200.0` | `10.0.207.255` | 2.048 | 2.043 |
| (b) `192.168.7.99/27` | Octet 4, mask 224, khối 32. Bội số ≤ 99: 96 | `192.168.7.96` | `192.168.7.127` | 32 | 27 |
| (c) `172.20.15.255/22` | Octet 3, mask 252, khối 4. Bội số ≤ 15: 12 | `172.20.12.0` | `172.20.15.255` | 1.024 | 1.019 |
| (d) `10.1.1.1/30` | Octet 4, mask 252, khối 4 | `10.1.1.0` | `10.1.1.3` | 4 | **Không tạo được trên AWS** — nhỏ hơn `/28` (mạng thông thường: 2 host) |
| (e) `10.255.255.254/8` | Octet 1, mask 255 → network giữ octet 1 | `10.0.0.0` | `10.255.255.255` | 16.777.216 | **Không tạo được làm subnet AWS** — lớn hơn `/16` |

Bẫy ở câu (c): `172.20.15.255` chính là **broadcast address** của mạng đó — không gán được cho máy nào. Nếu bạn nhận ra điều này, rất tốt.

### Bài 3 — Chọn kích thước

- 50 EC2 + 50% = 75 địa chỉ cần dùng. Trên AWS cần tổng ≥ 75 + 5 = 80.
  - `/26` = 64 tổng → 59 dùng được → **không đủ**.
  - `/25` = 128 tổng → 123 dùng được → **đủ**. Đáp án: **`/25`**.
- 1.000 IP: cần tổng ≥ 1.005. `/23` = 512 (thiếu), `/22` = 1.024 → 1.019 dùng được → **`/22`**.

### Bài 4 — Tìm lỗi thiết kế

| Dòng | Vấn đề |
|---|---|
| `public-b: 10.50.1.0/23` | Không ở dạng chuẩn: `/23` có khối 2 ở octet 3, mà 1 là số lẻ. Dạng chuẩn là `10.50.0.0/23` (10.50.0.0 → 10.50.1.255) → **chồng lấn** với `public-a` (`10.50.0.0/24`) |
| `private-b: 10.50.8.0/20` | Không ở dạng chuẩn: `/20` có khối 16, mà 8 không phải bội số của 16. Dạng chuẩn `10.50.0.0/20` (10.50.0.0 → 10.50.15.255) → **chồng lấn** với `public-a`, `public-b`, `private-a` |
| `db-a: 10.50.16.0/29` | `/29` nhỏ hơn `/28` — **AWS không cho phép** |
| Toàn bảng | Kích thước lộn xộn (`/24`, `/23`, `/20`, `/29`) không có lý do; không ghi AZ; không có quy ước đặt dải → khó đọc, khó mở rộng |

Bảng sửa lại (một phương án):

```text
VPC:        10.50.0.0/16
public-a:   10.50.1.0/24    (ap-southeast-1a)
public-b:   10.50.2.0/24    (ap-southeast-1b)
private-a:  10.50.11.0/24   (ap-southeast-1a)
private-b:  10.50.12.0/24   (ap-southeast-1b)
db-a:       10.50.21.0/24   (ap-southeast-1a)   — hoặc /28 nếu muốn nhỏ, vẫn hợp lệ
db-b:       10.50.22.0/24   (ap-southeast-1b)   — RDS cần subnet ở ít nhất 2 AZ
```

Điểm cộng nếu bạn nhận ra RDS cần một nhóm subnet trải trên **ít nhất 2 AZ** (sẽ học ở Module 06) nên chỉ có `db-a` là thiếu.

### Bài 5 — Docker đang dùng dải nào?

Kết quả thường gặp (minh họa):

```text
$ docker network inspect bridge --format '{{json .IPAM.Config}}'
[{"Subnet":"172.17.0.0/16","Gateway":"172.17.0.1"}]

$ docker network create labnet && docker network inspect labnet --format '{{json .IPAM.Config}}'
[{"Subnet":"172.18.0.0/16","Gateway":"172.18.0.1"}]
```

- Network `bridge` mặc định: `172.17.0.0/16`, gateway `172.17.0.1`.
- Network mới thường nhận dải kế tiếp: `172.18.0.0/16` (trên máy bạn có thể khác nếu đã có network khác).
- Với bảng ở Bài 1 (`10.20.0.0/16`): **không** chồng lấn — khác octet 1.
- Nếu VPN công ty dùng `172.18.0.0/16`: khi network `labnet` tồn tại, máy có route `172.18.0.0/16` đi vào bridge của Docker. Gói tin tới máy công ty trong dải đó sẽ bị gửi nhầm vào mạng Docker thay vì đi qua VPN → mất kết nối tới các máy đó cho đến khi xóa network hoặc đổi dải Docker.

Nhớ dọn dẹp: `docker network rm labnet`.
