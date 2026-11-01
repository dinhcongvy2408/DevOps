# 03. VPC — mạng riêng của bạn trên AWS

> Thời lượng ước tính: 4–5 giờ (đọc + bài thực hành chỉ đọc) · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Network 02 — IPv4 & CIDR](../02-NETWORKING/02-ipv4-subnet-cidr.md), [Network 04 — Routing & NAT](../02-NETWORKING/04-routing-nat-switching.md), [Network 05 — TCP/UDP & firewall](../02-NETWORKING/05-tcp-udp-ports-firewall.md), [bài 02 — IAM](02-iam.md)
>
> Lab bắt buộc đi kèm: [Lab 01 — Dựng VPC taskhub bằng tay](labs/lab-01-vpc-by-hand.md)

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

Sau bài này bạn có thể:

- Giải thích **VPC** là gì bằng các khái niệm đã học ở Module 02: dải CIDR, subnet, route table, NAT, firewall.
- Chọn dải CIDR cho VPC **không trùng** với mạng nhà, WSL, Docker và các VPC khác.
- Tính số địa chỉ dùng được trong một subnet AWS (trừ 5 địa chỉ bị giữ lại).
- Giải thích vì sao **public subnet hay private subnet là do route table quyết định**, không phải một ô tích.
- Phân biệt **Internet Gateway** và **NAT Gateway**; giải thích vì sao dự án `taskhub` **không** dùng NAT Gateway.
- So sánh **Security Group** (stateful) và **Network ACL** (stateless), viết được luật NACL có tính đến ephemeral port.
- Đi lại được hành trình của một gói tin HTTP từ Internet vào EC2 và trở ra, chỉ ra từng "trạm kiểm soát".
- Đọc cấu hình VPC bằng AWS CLI (`describe-*` + `--query`).

## 2. Tại sao DevOps Engineer cần kiến thức này?

Gần như mọi sự cố "không truy cập được" trên AWS đều là sự cố mạng VPC:

| Tình huống khi đi làm | Kiến thức cần |
|---|---|
| "Vừa tạo EC2 mà không SSH/HTTP vào được" | Route tới IGW, public IP, Security Group, NACL — kiểm tra theo đúng thứ tự gói tin đi qua |
| "Server trong private subnet không `apt update` được" | Private subnet không có đường ra Internet — cần NAT Gateway (tốn tiền) hoặc thiết kế khác |
| "Hóa đơn tháng này tăng 40 USD không rõ lý do" | NAT Gateway quên xóa, Public IPv4 không dùng, interface endpoint — đều tính tiền theo giờ |
| "Kết nối VPN tới công ty xong thì mất truy cập một số máy" | Dải CIDR trùng nhau — lỗi thiết kế từ ngày đầu, rất khó sửa sau |
| "RDS phải nằm ở đâu, ai được kết nối tới nó?" | Private subnet + Security Group tham chiếu Security Group của app |
| Phỏng vấn: "Public subnet khác private subnet ở điểm nào?" | Câu hỏi gần như chắc chắn gặp. Trả lời đúng: **route table** |

Terraform (Module 07) và Kubernetes (Module 09) đều giả định bạn hiểu VPC. Viết `aws_route_table` trong Terraform mà không hiểu route table là gì thì chỉ là chép code.

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Bạn đã biết 90% bài này

VPC không phải công nghệ mới. Nó là **mạng máy tính bình thường** mà AWS ảo hóa cho bạn. Hãy đối chiếu:

| Khái niệm Module 02 | Trên AWS gọi là | Đã học ở |
|---|---|---|
| Một mạng private dải `10.x.0.0/16` | **VPC** (Virtual Private Cloud) | [Network 02 §4.7](../02-NETWORKING/02-ipv4-subnet-cidr.md#47--các-dải-địa-chỉ-đặc-biệt) |
| Chia mạng thành các mạng con | **Subnet** | [Network 02 §4.5](../02-NETWORKING/02-ipv4-subnet-cidr.md#45--chia-subnet-subnetting-bằng-tay) |
| Bảng định tuyến (`ip route`) | **Route table** | [Network 04 §4.2](../02-NETWORKING/04-routing-nat-switching.md#42--routing-quyết-định-đường-đi) |
| Router nhà bạn làm NAT ra Internet | **Internet Gateway** (NAT 1-1) / **NAT Gateway** (NAT nhiều-1) | [Network 04 §4.6](../02-NETWORKING/04-routing-nat-switching.md#46--chuẩn-bị-cho-aws-internet-gateway-và-nat-gateway) |
| Firewall stateful (iptables + conntrack, ufw) | **Security Group** | [Network 05 §4.8](../02-NETWORKING/05-tcp-udp-ports-firewall.md#48--firewall-stateful-và-stateless) |
| Firewall stateless | **Network ACL** | [Network 05 §4.8](../02-NETWORKING/05-tcp-udp-ports-firewall.md#48--firewall-stateful-và-stateless) |
| DHCP cấp IP, DNS server của mạng | DHCP option set, **Amazon DNS** tại địa chỉ VPC+2 | [Network 03](../02-NETWORKING/03-dns-dhcp.md) |
| Card mạng | **ENI** (Elastic Network Interface) | [Network 04 §3.1](../02-NETWORKING/04-routing-nat-switching.md#31-nhắc-lại-hai-địa-chỉ-của-một-card-mạng) |

Điểm khác duy nhất: bạn không cắm dây, không mua router. Mọi thứ là **cấu hình**, tạo bằng console, CLI hoặc Terraform — và vì là cấu hình nên **sai một dòng là mất kết nối**, cũng như **quên một dòng là mất tiền**.

### 3.2. Region, Availability Zone và VPC

- Một **VPC** nằm trong **một Region** (ví dụ `ap-southeast-1`) và trải trên **mọi AZ** của Region đó.
- Một **subnet** nằm trong **đúng một AZ**. Muốn chạy trên 2 AZ (chịu được một AZ sự cố) → cần ít nhất 2 subnet.
- Vì vậy kế hoạch mạng tuần 4 của bạn có `public-a`/`public-b`, `private-a`/`private-b`: chữ cái cuối là AZ.

(Region và AZ đã học ở [bài 01](01-cloud-fundamentals.md).)

### 3.3. Ôn nhanh 3 công thức

- `/n` → số địa chỉ = 2^(32−n). `/16` = 65.536; `/24` = 256; `/28` = 16.
- Hai dải chồng lấn khi dải nhỏ hơn nằm trong (hoặc giao với) dải lớn hơn — kiểm tra bằng `python3 -c "import ipaddress as i; print(i.ip_network('10.20.0.0/16').overlaps(i.ip_network('10.20.1.0/24')))"`.
- Số IP dùng được trên AWS = tổng − **5** ([Network 02 §4.9](../02-NETWORKING/02-ipv4-subnet-cidr.md#49--aws-giữ-lại-5-địa-chỉ-trong-mỗi-subnet)).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 VPC và dải CIDR — quyết định khó sửa nhất

**VPC** (Virtual Private Cloud — đám mây riêng ảo) là một mạng logic cô lập trong một Region, thuộc về tài khoản của bạn. Khi tạo VPC, bạn phải khai báo **một dải IPv4 CIDR chính**.

Quy định theo [Amazon VPC FAQ](https://aws.amazon.com/vpc/faqs/): mỗi dải IPv4 của VPC có kích thước từ **`/28` đến `/16`**; một VPC có tối đa 5 dải IPv4 (1 chính + 4 phụ). Bạn có thể **thêm** dải phụ sau, nhưng **không đổi được dải chính** — muốn đổi phải tạo VPC mới và chuyển mọi thứ sang. Vì vậy chọn CIDR là quyết định cần suy nghĩ kỹ nhất của cả bài.

**Nguyên tắc chọn dải cho `taskhub`:**

1. **Dùng dải private RFC 1918.** Gần như mọi người chọn trong `10.0.0.0/8` vì nó rộng nhất.
2. **Đủ lớn để không phải mở rộng.** `/16` (65.536 địa chỉ) là lựa chọn phổ biến: thừa nhiều nhưng không tốn tiền — địa chỉ private miễn phí.
3. **Không trùng bất kỳ mạng nào bạn có thể phải nối tới.** Danh sách cần tránh với máy của bạn:

| Mạng | Dải thường gặp | Vì sao phải tránh |
|---|---|---|
| Mạng Wi-Fi nhà, văn phòng nhỏ | `192.168.0.0/24`, `192.168.1.0/24` | Sau này VPN từ laptop vào VPC → route bị trùng |
| WSL2 (chế độ NAT) | Một dải trong `172.16.0.0/12` — bạn đã thấy IP dạng `172.29.x.x` ở [Network 04 §4.5](../02-NETWORKING/04-routing-nat-switching.md#45--mạng-của-wsl2) | Dải đổi theo máy; tránh cả khối `172.16/12` là an toàn nhất |
| Docker bridge `docker0` | `172.17.0.0/16`, network tự tạo `172.18+.0.0/16` | Chạy Docker trên EC2 trong VPC dùng `172.17/16` → xung đột ([Network 02 §4.8](../02-NETWORKING/02-ipv4-subnet-cidr.md#48--xung-đột-dải-ip-trong-thực-tế)) |
| Mạng nội bộ của Docker Desktop | `192.168.65.0/24` (mặc định, theo docs Docker Desktop) | Ít khi gặp, nhưng cùng khối `192.168/16` |
| VPC mặc định của AWS | `172.31.0.0/16` | Nếu sau này nối hai VPC (peering) → trùng |
| VPC khác của bạn (dev/prod) | Tự đặt | Dev `10.20.0.0/16`, prod `10.30.0.0/16` → nối được với nhau |

→ Ví dụ dùng trong giáo trình: **`10.20.0.0/16`**. Bạn dùng đúng dải trong `docs/network-plan.md` của mình ([tuần 4](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-4--kế-hoạch-mạng)); nếu dải đó vi phạm bảng trên, sửa kế hoạch **trước** khi làm lab.

### 4.2. 🟥 Subnet và 5 địa chỉ bị giữ lại

**Subnet** là một phần của dải VPC, nằm trong **một AZ**. Theo [AWS — Subnet CIDR blocks](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html), mỗi subnet mất **4 địa chỉ đầu và 1 địa chỉ cuối**. Với `10.20.1.0/24`:

| Địa chỉ | AWS dùng làm gì |
|---|---|
| `10.20.1.0` | Địa chỉ mạng (network address) |
| `10.20.1.1` | Router của VPC |
| `10.20.1.2` | DNS server (quy ước: địa chỉ gốc của **VPC** + 2 — xem §4.10) |
| `10.20.1.3` | Dự phòng cho tương lai |
| `10.20.1.255` | Địa chỉ broadcast — VPC không hỗ trợ broadcast nên giữ lại |

→ `/24` có **251** địa chỉ dùng được. Ở lab bạn sẽ thấy đúng con số này trong cột `AvailableIpAddressCount`.

Kế hoạch mẫu (khớp [quy ước dự án](README.md)):

| Tên | AZ | CIDR | Loại | IP dùng được | Chứa gì |
|---|---|---|---|---|---|
| `taskhub-public-a` | ap-southeast-1a | `10.20.1.0/24` | Public | 251 | EC2 `taskhub-app` (v2) |
| `taskhub-public-b` | ap-southeast-1b | `10.20.2.0/24` | Public | 251 | ALB ở lab tuần 14 (ALB cần ≥ 2 AZ) |
| `taskhub-private-a` | ap-southeast-1a | `10.20.11.0/24` | Private | 251 | RDS ở lab tuần 14 |
| `taskhub-private-b` | ap-southeast-1b | `10.20.12.0/24` | Private | 251 | RDS (DB subnet group cần ≥ 2 AZ) |

Vì sao đánh số `1, 2` cho public và `11, 12` cho private? Để nhìn IP là đoán được loại subnet (`10.20.1x.x` = private) và còn chỗ thêm `public-c` = `10.20.3.0/24` nếu Region có AZ thứ ba. Đây là thói quen, không phải quy định của AWS.

### 4.3. 🟥 Route table — thứ quyết định public hay private

**Route table** (bảng định tuyến) gồm các dòng `Đích → Target`. Router của VPC chọn dòng **khớp dài nhất** (longest prefix match — y hệt [Network 04 §4.2](../02-NETWORKING/04-routing-nat-switching.md#42--routing-quyết-định-đường-đi)).

Ba sự thật cần nhớ:

1. **Mỗi VPC có một main route table** (bảng chính) được tạo sẵn. Nó chứa sẵn route **`local`**: `10.20.0.0/16 → local` — mọi máy trong VPC nói chuyện được với nhau. Route `local` không xóa được.
2. **Mỗi subnet được gắn với đúng một route table.** Subnet không được gắn rõ ràng (explicit association) sẽ **tự dùng main route table**.
3. Theo [AWS — Internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html): subnet gắn với route table **có route tới Internet Gateway** gọi là **public subnet**; không có route đó gọi là **private subnet** — và instance trong private subnet **không ra Internet được kể cả khi có public IP**.

→ Không có ô tích "public subnet" nào. Ở console, khi tạo subnet bạn **không** chọn public/private. Bạn tạo subnet, rồi **gắn nó vào route table có hoặc không có `0.0.0.0/0 → igw`**.

**Thực hành tốt: để main route table "sạch" (chỉ có `local`)** và tạo route table riêng cho public subnet. Lý do: subnet mới tạo mà quên gắn route table sẽ rơi vào main route table → mặc định thành **private** (an toàn). Nếu bạn thêm route IGW vào main route table, mọi subnet quên gắn đều thành public — một lỗi bảo mật âm thầm.

```text
taskhub-public-rt (custom)              taskhub-private-rt (custom, hoặc dùng main)
┌────────────────┬──────────────┐       ┌────────────────┬──────────────┐
│ 10.20.0.0/16   │ local        │       │ 10.20.0.0/16   │ local        │
│ 0.0.0.0/0      │ igw-0abc…    │       └────────────────┴──────────────┘
└────────────────┴──────────────┘        gắn: private-a, private-b
 gắn: public-a, public-b                 → không có đường ra Internet
```

### 4.4. 🟥 Internet Gateway (IGW)

Theo [AWS — Internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html):

- IGW là thành phần **mở rộng ngang, dự phòng, sẵn sàng cao**, không gây giới hạn băng thông. Một VPC gắn **một** IGW.
- **Không tính phí cho bản thân IGW**; chỉ tính phí truyền dữ liệu của EC2 đi qua nó.
- Với IPv4, IGW "**logically provides the one-to-one NAT**": instance chỉ biết IP private của nó; khi gói tin ra Internet, IGW đổi địa chỉ nguồn thành **public IPv4** của instance, và chiều ngược lại.

Điều kiện để một instance nói chuyện được với Internet qua IPv4 — **thiếu một là hỏng**:

| # | Điều kiện | Nằm ở đâu |
|---|---|---|
| 1 | VPC có IGW **attached** | VPC → Internet gateways |
| 2 | Route table của subnet có `0.0.0.0/0 → igw-…` | VPC → Route tables |
| 3 | Instance có **public IPv4** (auto-assign hoặc Elastic IP) | Subnet setting / lúc launch |
| 4 | **NACL** của subnet cho phép cả hai chiều (kể cả ephemeral port) | VPC → Network ACLs |
| 5 | **Security Group** của instance cho phép inbound port cần thiết | EC2 → Security groups |
| 6 | Ứng dụng **lắng nghe** trên `0.0.0.0` (không phải `127.0.0.1`) | Trong máy — [Network 05 §4.5](../02-NETWORKING/05-tcp-udp-ports-firewall.md#45--bind-address-0000-vs-127001-vs-ip-cụ-thể) |

Bảng này là **checklist debug** bạn sẽ dùng suốt Module 06. In ra, dán cạnh màn hình.

### 4.5. 🟥 Public IPv4: auto-assign và chi phí

- Subnet có thuộc tính **Enable auto-assign public IPv4 address**. Theo [AWS docs](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-public-ip.html), subnet **không mặc định** (do bạn tạo) có thuộc tính này là `false`; subnet mặc định là `true`.
- Bật thuộc tính này trên `taskhub-public-a/b` → EC2 launch vào đó tự nhận public IP. Không bật trên private subnet.
- **Giá:** theo [bảng giá VPC](https://aws.amazon.com/vpc/pricing/) và bảng giá API cho `ap-southeast-1` (kiểm tra 2026-10-31): **0,005 USD/giờ cho mỗi public IPv4**, dù đang dùng (in-use) hay để không (idle). ≈ 3,65 USD/tháng nếu chạy cả tháng.
- Public IP tự cấp **đổi** khi instance stop rồi start. Elastic IP giữ cố định nhưng **cùng giá** khi đang gắn — và vẫn tính tiền khi không gắn vào đâu.

> 💰 Bật auto-assign trên subnet **không tốn tiền**. Tiền chỉ phát sinh khi có ENI (EC2, NAT Gateway, ALB…) thực sự nhận public IP.

### 4.6. 🟥 NAT Gateway — hiểu để không phải dùng

**Vấn đề:** máy trong private subnet (không public IP, không route IGW) muốn **đi ra** Internet (tải package, gọi API) nhưng không muốn Internet **đi vào**. Đó là SNAT/PAT ([Network 04 §4.4](../02-NETWORKING/04-routing-nat-switching.md#44--nat-vì-sao-gần-như-mọi-kết-nối-đều-đi-qua-nó)).

**NAT Gateway** của AWS:

- Đặt **trong public subnet**, có một Elastic IP.
- Route table của private subnet: `0.0.0.0/0 → nat-…`.
- Internet không khởi tạo kết nối vào được.
- Production thường đặt **một NAT Gateway mỗi AZ** (để một AZ chết không kéo theo AZ kia).

**Chi phí** (theo [bảng giá VPC](https://aws.amazon.com/vpc/pricing/), kiểm tra 2026-10-31): ví dụ trên trang cho US East (Ohio) là **0,045 USD/giờ + 0,045 USD/GB dữ liệu đi qua**, cộng phí truyền dữ liệu thông thường. Trang không in sẵn giá Singapore — khi cần con số chính xác, mở trang giá, chọn Region **Asia Pacific (Singapore)** hoặc dùng [AWS Pricing Calculator](https://calculator.aws/). Chỉ tính phần theo giờ ở mức 0,045 USD: ≈ **32 USD/tháng cho mỗi NAT Gateway**, chưa có dữ liệu — tức gần 1/3 tổng credit 100 USD ban đầu của Free plan chỉ trong một tháng.

**Vì sao `taskhub` không dùng NAT Gateway:** EC2 duy nhất nằm ở public subnet, có public IP, tự ra Internet qua IGW (miễn phí). Private subnet chỉ chứa RDS ở lab tuần 14 — RDS không cần ra Internet. Ghi quyết định này thành ADR (gợi ý trong [README dự án §7](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr)).

**Các lựa chọn thay thế, khi máy private thực sự cần gọi ra ngoài:**

| Lựa chọn | Chi phí | Dùng khi |
|---|---|---|
| 🟥 **Gateway VPC endpoint** cho S3 / DynamoDB | **Miễn phí** — theo trang giá: *"no data processing or hourly charges for using Gateway Type VPC endpoints"* | Máy private chỉ cần đọc/ghi S3 (ví dụ backup). Endpoint thêm một route (prefix list) vào route table |
| 🟨 **Interface VPC endpoint** (PrivateLink) cho dịch vụ khác (SSM, ECR, CloudWatch…) | **0,013 USD/giờ mỗi endpoint mỗi AZ** ở Singapore (bảng giá API, 2026-10-31) + phí dữ liệu | Muốn quản lý EC2 private bằng SSM mà không có NAT: cần vài endpoint (`ssm`, `ssmmessages`…) → cộng lại cũng gần bằng một NAT Gateway |
| 🟦 **Egress-only Internet Gateway** (IPv6) | Theo [AWS docs](https://docs.aws.amazon.com/vpc/latest/userguide/create-vpc.html), dùng cho chiều **ra** qua IPv6 | VPC dual-stack; máy private ra Internet bằng IPv6 mà Internet không vào được. Cần đích hỗ trợ IPv6 |
| 🟦 NAT instance (tự chạy NAT trên một EC2 nhỏ) | Giá EC2 | Mô hình cũ, tự vá lỗi, tự lo sẵn sàng cao. Chỉ cần biết tên |

### 4.7. 🟥 Security Group — firewall stateful gắn vào ENI

Theo [AWS — Security groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html):

- Security Group (SG) gắn vào **tài nguyên** (chính xác là ENI của EC2, RDS, ALB…), không gắn vào subnet. Một tài nguyên có thể có nhiều SG.
- **Stateful:** *"if you send a request from an instance, the response traffic for that request is allowed to reach the instance regardless of the inbound security group rules"*. Bạn chỉ viết luật cho chiều **khởi tạo**.
- **Chỉ có luật allow.** Không có luật deny. Thứ không được allow thì bị chặn.
- Không tính phí.
- Khi tạo SG mới: không có luật inbound nào (chặn hết chiều vào), có sẵn một luật outbound cho phép **mọi** lưu lượng ra.
- SG **không lọc** lưu lượng tới Amazon DNS, DHCP, instance metadata (`169.254.169.254`), Amazon Time Sync.

**Nguồn (source) của một luật inbound có thể là:**

| Loại nguồn | Ví dụ | Dùng khi |
|---|---|---|
| CIDR IPv4 | `0.0.0.0/0` (mọi nơi), `203.0.113.7/32` (đúng một IP) | Web public: `80, 443` từ `0.0.0.0/0`. SSH tạm thời: `22` từ `<IP-nhà-bạn>/32` |
| **Một Security Group khác** | `sg-0app…` | "Chỉ máy nào mang SG `app` mới được vào port 5432 của RDS" — không cần biết IP, IP đổi vẫn đúng |
| Prefix list | `pl-…` | Danh sách dải IP do AWS hoặc bạn quản lý (🟨) |

**Tham chiếu SG là kỹ năng quan trọng nhất của mục này.** Kiến trúc tuần 14:

```text
Internet ──80/443──► [SG alb]  ALB
                        │  luật inbound của SG app: 8080 từ sg-alb
                        ▼
                     [SG app]  EC2
                        │  luật inbound của SG db: 5432 từ sg-app
                        ▼
                     [SG db]   RDS
```

Không dòng nào ghi IP. Thêm/bớt EC2 trong Auto Scaling group, luật vẫn đúng.

**SG của `taskhub` v2** — `taskhub-web-sg`:

| Chiều | Giao thức | Port | Nguồn/Đích | Lý do |
|---|---|---|---|---|
| Inbound | TCP | 80 | `0.0.0.0/0` | Nginx phục vụ HTTP |
| Inbound | TCP | 443 | `0.0.0.0/0` | HTTPS (dùng khi có domain + chứng chỉ) |
| Outbound | Tất cả | Tất cả | `0.0.0.0/0` | Mặc định: pull image GHCR, `apt`, gọi SSM |

**Không có port 22.** Quản trị bằng SSM Session Manager ([bài 04](04-ec2.md)). Port 5432 của PostgreSQL **không** cần luật nào: nó chỉ nói chuyện với app **trong cùng Docker network** trên cùng một máy, không đi qua ENI.

### 4.8. 🟥 Network ACL — firewall stateless gắn vào subnet

Theo [AWS — Network ACLs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html):

- NACL gắn vào **subnet**. Mỗi subnet có đúng **một** NACL; một NACL gắn được nhiều subnet. Subnet không gắn rõ ràng → dùng **NACL mặc định** của VPC.
- **NACL mặc định cho phép mọi lưu lượng** cả hai chiều. NACL **tự tạo** (custom) thì ngược lại: chỉ có luật `*` cuối cùng **chặn tất cả** cho đến khi bạn thêm luật.
- Có cả **allow và deny**. Luật đánh số 1–32766, xét **từ số nhỏ đến lớn, khớp luật đầu tiên là dừng**. AWS khuyên đánh số cách quãng (100, 110, 120…) để sau này chèn luật vào giữa.
- **Stateless:** *"If, for example, you create a NACL rule to allow specific inbound traffic to a subnet, responses to that traffic are not automatically allowed."*
- NACL chỉ xét gói tin khi **vào và ra khỏi subnet**, không xét lưu lượng bên trong cùng subnet.
- NACL không chặn được Amazon DNS, DHCP, instance metadata. Không tính phí.

**Ephemeral port — chỗ ai cũng sai lần đầu.** Client chọn port nguồn tạm thời; chiều **trả lời** đi tới port đó. Vì NACL không nhớ trạng thái, bạn phải tự mở. Theo [AWS — Ephemeral ports](https://docs.aws.amazon.com/vpc/latest/userguide/custom-network-acl.html):

| Client | Dải ephemeral port |
|---|---|
| Nhiều kernel Linux (gồm Amazon Linux) | 32768–61000 |
| Windows Server 2008 trở lên | 49152–65535 |
| Elastic Load Balancing | 1024–65535 |
| NAT Gateway, AWS Lambda | 1024–65535 |

(Trên WSL bạn đã đo được `32768 60999` ở [Network 05 §4.4](../02-NETWORKING/05-tcp-udp-ports-firewall.md#44--port-các-dải-và-những-port-phải-thuộc) — gần khớp.)

AWS kết luận: *"to cover the different types of clients… you can open ephemeral ports 1024-65535"*, và nếu muốn chặn port độc hại trong dải đó thì đặt luật deny **trước** luật allow.

**Ví dụ NACL cho một public subnet web** (chỉ để hiểu — `taskhub` dùng NACL mặc định):

| Hướng | # | Giao thức | Port | Nguồn/Đích | Allow/Deny | Vì sao |
|---|---|---|---|---|---|---|
| Inbound | 100 | TCP | 80 | 0.0.0.0/0 | ALLOW | Client gọi HTTP vào |
| Inbound | 110 | TCP | 443 | 0.0.0.0/0 | ALLOW | Client gọi HTTPS vào |
| Inbound | 140 | TCP | 1024–65535 | 0.0.0.0/0 | ALLOW | **Trả lời** cho kết nối do máy trong subnet khởi tạo (apt, docker pull) |
| Inbound | * | Tất cả | Tất cả | 0.0.0.0/0 | DENY | Luật cuối, không sửa được |
| Outbound | 100 | TCP | 80 | 0.0.0.0/0 | ALLOW | Máy trong subnet gọi HTTP ra (apt) |
| Outbound | 110 | TCP | 443 | 0.0.0.0/0 | ALLOW | Gọi HTTPS ra (GHCR, SSM) |
| Outbound | 140 | TCP | 1024–65535 | 0.0.0.0/0 | ALLOW | **Trả lời** cho client Internet đã gọi vào port 80/443 |
| Outbound | * | Tất cả | Tất cả | 0.0.0.0/0 | DENY | |

Quên dòng outbound 140 → client gửi được request vào, server xử lý xong, nhưng **gói trả lời bị chặn ở biên subnet** → phía client thấy **timeout**, log Nginx vẫn ghi đã trả 200. Đây là kiểu lỗi làm mất cả buổi chiều nếu không hiểu stateless.

**So sánh SG và NACL:**

| | Security Group | Network ACL |
|---|---|---|
| Gắn vào | ENI (tài nguyên) | Subnet |
| Trạng thái | **Stateful** — chiều trả lời tự cho qua | **Stateless** — phải mở cả chiều trả lời |
| Loại luật | Chỉ **allow** | **Allow và deny** |
| Thứ tự | Xét **tất cả** luật, có luật nào allow là qua | Xét **theo số**, khớp luật đầu tiên thì dừng |
| Mặc định khi tạo mới | Inbound: không gì; Outbound: tất cả | Custom: chặn tất cả. Mặc định của VPC: cho tất cả |
| Tham chiếu SG khác | Có | Không (chỉ CIDR) |
| Dùng khi | **Luôn luôn** — lớp chính | Lớp phụ: chặn hẳn một dải IP xấu, yêu cầu tuân thủ |

> **Quy tắc thực tế cho Junior:** làm mọi việc bằng Security Group, để NACL mặc định (cho tất cả). Chỉ sửa NACL khi có lý do cụ thể, và khi sửa thì nhớ ephemeral port.

### 4.9. 🟨 VPC mặc định — vì sao ta tự xây

Theo [AWS — Default VPC components](https://docs.aws.amazon.com/vpc/latest/userguide/default-vpc-components.html), mỗi Region có sẵn một **default VPC**:

- CIDR `172.31.0.0/16`, một subnet `/20` (4.096 địa chỉ) ở **mỗi** AZ.
- Có IGW, main route table có sẵn `0.0.0.0/0 → igw` → **mọi** subnet đều public.
- Subnet mặc định tự cấp public IPv4.
- Có default SG và default NACL (cho phép tất cả).

Nó tồn tại để người mới launch EC2 ngay được. Lý do `taskhub` **không** dùng:

| Default VPC | VPC tự xây |
|---|---|
| Mọi subnet public → RDS đặt vào cũng có route ra Internet | Có private subnet thật |
| `172.31.0.0/16` — trùng với mọi default VPC khác, nằm trong khối `172.16/12` cùng Docker/WSL | Dải bạn chọn theo kế hoạch |
| Bạn không học được gì về route table, IGW | Hiểu từng mảnh — đúng mục tiêu của tuần 11 |
| Không tái tạo được bằng code nếu không xóa default VPC | Tuần 15–16 Terraform dựng lại y hệt |

Đừng xóa default VPC trong bài này — để nguyên, chỉ đọc nó (mục 9).

### 4.10. 🟨 DNS trong VPC

Theo [AWS — Understanding Amazon DNS](https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html):

- **Amazon DNS** (Route 53 Resolver) nằm ở `169.254.169.253` và ở **địa chỉ gốc của dải VPC chính + 2**: VPC `10.20.0.0/16` → `10.20.0.2`. Đây là lý do mọi subnet mất địa chỉ `.2` ([Network 03](../02-NETWORKING/03-dns-dhcp.md) đã báo trước).
- Hai thuộc tính của VPC:

| Thuộc tính | Mặc định (VPC tự tạo) | Điều khiển |
|---|---|---|
| `enableDnsSupport` | `true` | Truy vấn tới Amazon DNS có được trả lời không |
| `enableDnsHostnames` | **`false`** (chỉ VPC mặc định là `true`) | Instance có public IP có được cấp **public DNS hostname** (`ec2-…compute.amazonaws.com`) không |

Hai thuộc tính đều phải `true` thì instance mới có public DNS name, và mới dùng được private hosted zone của Route 53 hoặc private DNS của interface endpoint. Ở lab, bạn **bật `enableDnsHostnames`** cho `taskhub-vpc`.

- NACL và SG **không chặn được** truy vấn tới Amazon DNS.

### 4.11. 🟨 Công cụ quan sát mạng: Flow Logs và Reachability Analyzer

| Công cụ | Làm gì | Chi phí (kiểm tra 2026-10-31) | Khi nào dùng |
|---|---|---|---|
| **VPC Flow Logs** | Ghi lại metadata từng luồng IP qua ENI: IP/port nguồn-đích, số byte, **ACCEPT/REJECT**. Gửi tới CloudWatch Logs, S3 hoặc Firehose. Không ảnh hưởng hiệu năng | Phí **vended logs** (thu thập + lưu trữ) theo [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) | Debug "gói tin có tới ENI không, bị SG/NACL từ chối không". Bật trong lúc debug, tắt sau đó |
| **Reachability Analyzer** | Phân tích **tĩnh** cấu hình (không gửi gói tin): từ nguồn A tới đích B có đường không, nếu không thì **thành phần nào chặn** (thiếu route, SG, NACL…) | **0,10 USD mỗi lần phân tích** ([bảng giá VPC](https://aws.amazon.com/vpc/pricing/)) | Khi đã kiểm tra checklist §4.4 mà vẫn không ra. Dùng ở bài 04 khi đã có EC2 |

### 4.12. 🟥 Hành trình của một gói tin

Người dùng ở Việt Nam gọi `http://<public-ip>/actuator/health`. EC2 `taskhub-app` có private IP `10.20.1.25`, public IP `203.0.113.10`.

**Chiều đi vào (request):**

1. Gói tin `client:51514 → 203.0.113.10:80` đi qua Internet tới AWS.
2. **IGW** thấy đích là public IP của một ENI trong VPC → **đổi đích** thành `10.20.1.25:80` (NAT 1-1).
3. **Router VPC** tra route table — đích `10.20.1.25` khớp `10.20.0.0/16 → local` → chuyển vào subnet `public-a`.
4. **NACL** của `public-a`, luật **inbound**: có allow TCP 80 từ `0.0.0.0/0` không? (NACL mặc định: có.)
5. **Security Group** `taskhub-web-sg` của ENI, luật **inbound**: có allow TCP 80 không? Có → SG **ghi nhớ** kết nối này.
6. **ENI → hệ điều hành → Docker → Nginx** đang nghe `0.0.0.0:80`.

**Chiều trả về (response):**

7. Nginx trả lời `10.20.1.25:80 → client:51514`.
8. **SG outbound:** không cần xét luật — kết nối đã được ghi nhớ (stateful).
9. **NACL outbound** của `public-a`: có allow TCP **51514** (ephemeral port của client) tới `0.0.0.0/0` không? (Mặc định: có. NACL tự tạo mà quên dải 1024–65535: **gói bị chặn ở đây**.)
10. **Route table:** đích là IP Internet → khớp `0.0.0.0/0 → igw`.
11. **IGW** đổi **nguồn** `10.20.1.25` thành `203.0.113.10` → gửi ra Internet.

Hãy tự hỏi: nếu bỏ đi **bất kỳ** bước nào trong 11 bước trên, triệu chứng phía client là gì — "connection refused" hay "timeout"? (Câu hỏi 9 ở mục 13; gợi ý ở [Network 05 §4.7](../02-NETWORKING/05-tcp-udp-ports-firewall.md#47--phân-biệt-4-lỗi-kết-nối-quan-trọng-nhất).)

### 4.13. Gặp lại ở đâu

| Kiến thức bài này | Dùng lại ở |
|---|---|
| VPC, subnet, route table, IGW, SG | [Lab 01](labs/lab-01-vpc-by-hand.md) (tự tay dựng), [bài 04 — EC2](04-ec2.md) (launch vào `public-a`), dự án v2 |
| Checklist 6 điều kiện ra Internet | Mọi lần debug "không vào được EC2" ở [bài 04](04-ec2.md), break-fix của module |
| Private subnet, SG tham chiếu SG | [bài 07 — RDS](07-rds.md), [bài 08 — ALB + Auto Scaling](08-elb-autoscaling.md) |
| NAT Gateway, endpoint, chi phí | Kiến trúc tham chiếu 2 AZ có NAT (lab tuần 14 — dựng xong xóa ngay) |
| Dựng VPC bằng tay | Module 07 — viết lại toàn bộ bằng Terraform (`aws_vpc`, `aws_subnet`, `aws_route_table`…) |
| CIDR không trùng Docker | Module 09 — dải Pod/Service của Kubernetes cũng phải không trùng VPC |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Tạo EC2 trong subnet public rồi mà không ra Internet"

Một bạn tạo subnet tên `public-subnet`, launch EC2, không `apt update` được. Kiểm tra: subnet **chưa được gắn** vào route table có IGW → đang dùng main route table (chỉ `local`). Cái tên "public" không làm nó public. Sửa: gắn subnet vào `public-rt`. Bài học: **tên chỉ là tag**, route table mới là sự thật.

### Ví dụ 2: Hóa đơn tăng sau buổi học "VPC and more"

Dùng wizard **VPC and more**, chọn **NAT gateways: In 1 AZ** cho "đầy đủ", học xong quên xóa. Cuối tháng: NAT Gateway chạy 24/7 ≈ 32 USD (ở mức giá 0,045 USD/giờ) + Elastic IP của nó. Với Free plan, chừng đó trừ thẳng vào credit — và credit hết thì **tài khoản bị đóng**. Bài học: đọc kỹ từng ô của wizard, kiểm tra Billing sau mỗi buổi.

### Ví dụ 3: VPN nối văn phòng không vào được một nửa máy

Công ty dùng `10.0.0.0/16` cho văn phòng, VPC prod cũng `10.0.0.0/16` (giá trị mặc định nhiều người gõ). Khi dựng Site-to-Site VPN, route trùng nhau → không định tuyến được. Phải tạo VPC mới với dải khác và di chuyển toàn bộ hệ thống. Bài học: bảng IP của cả công ty phải được lập **trước** khi tạo VPC đầu tiên.

### Ví dụ 4: Đóng NACL "cho chặt" làm sập web

Ai đó sửa NACL của public subnet thành chỉ allow inbound 80/443 và outbound 80/443 "cho an toàn". Web lập tức timeout: chiều trả lời tới ephemeral port của client bị chặn ở outbound; và chính server cũng không `apt` được vì chiều trả lời từ mirror tới ephemeral port của server bị chặn ở inbound. SG thì đúng, nên ai chỉ nhìn SG sẽ không tìm ra.

---

## 6. Sơ đồ kiến trúc

### 6.1. VPC của `taskhub` (v2)

```text
                              Internet
                                 │
                        ┌────────┴────────┐
                        │  taskhub-igw    │  (NAT 1-1 cho public IPv4, miễn phí)
                        └────────┬────────┘
┌─────────────────────── taskhub-vpc  10.20.0.0/16  (ap-southeast-1) ────────────────────────┐
│  DNS: 10.20.0.2 · enableDnsSupport=true · enableDnsHostnames=true                           │
│                                                                                              │
│  taskhub-public-rt: 10.20.0.0/16→local · 0.0.0.0/0→igw      taskhub-private-rt: local only   │
│                                                                                              │
│ ┌──────────── AZ ap-southeast-1a ─────────────┐   ┌──────────── AZ ap-southeast-1b ─────────┐│
│ │ ┌─ taskhub-public-a 10.20.1.0/24 ────────┐  │   │ ┌─ taskhub-public-b 10.20.2.0/24 ─────┐ ││
│ │ │ auto-assign public IPv4: ON            │  │   │ │ auto-assign public IPv4: ON         │ ││
│ │ │  [taskhub-web-sg] EC2 taskhub-app (v2) │  │   │ │  (ALB — lab tuần 14)                │ ││
│ │ └────────────────────────────────────────┘  │   │ └─────────────────────────────────────┘ ││
│ │ ┌─ taskhub-private-a 10.20.11.0/24 ──────┐  │   │ ┌─ taskhub-private-b 10.20.12.0/24 ───┐ ││
│ │ │ (RDS — lab tuần 14) · không ra Internet│  │   │ │ (RDS — lab tuần 14)                 │ ││
│ │ └────────────────────────────────────────┘  │   │ └─────────────────────────────────────┘ ││
│ └─────────────────────────────────────────────┘   └─────────────────────────────────────────┘│
│  NACL: mặc định (allow all) cho cả 4 subnet · Không có NAT Gateway                           │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.2. Các lớp kiểm soát gói tin đi vào

```text
Client ──► IGW ──► Route table ──► NACL (subnet, stateless) ──► SG (ENI, stateful) ──► OS/Docker ──► Nginx :80
           NAT 1-1   "có đường?"      "số nhỏ trước,              "có luật allow?"        "đang nghe
           public→     local/igw       khớp là dừng"                                        0.0.0.0?"
           private
Chiều về:  Nginx ──► SG (tự cho qua) ──► NACL outbound (ephemeral port!) ──► Route 0.0.0.0/0→igw ──► IGW (private→public) ──► Client
```

### 6.3. Kiến trúc tham chiếu có NAT (chỉ để hiểu — không dựng trong dự án chính)

```text
            Internet
               │
             [IGW]
     ┌─────────┴─────────┐
 public-a             public-b
 [NAT GW a] ◄┐     ┌► [NAT GW b]      ← mỗi NAT ≈ 32 USD/tháng chỉ riêng phí giờ (ở giá 0,045)
             │     │
 private-a ──┘     └── private-b      route: 0.0.0.0/0 → NAT cùng AZ
 [app] [db]            [app] [db]
```

---

## 7. Các câu lệnh cần biết

Mọi lệnh trong bài này **chỉ đọc** (`describe-*`) — không tạo tài nguyên, không tốn tiền. Chạy ở `[WSL]` sau khi đã đăng nhập CLI theo [bài 06 — AWS CLI](06-aws-cli.md) (`aws login`, profile `taskhub`).

| Lệnh | Mục đích | Mức |
|---|---|---|
| `aws ec2 describe-vpcs` | Liệt kê VPC, CIDR, có phải default không | 🟥 |
| `aws ec2 describe-subnets` | Subnet: CIDR, AZ, số IP còn trống, auto-assign public IP | 🟥 |
| `aws ec2 describe-route-tables` | Route table, các route, subnet nào gắn vào | 🟥 |
| `aws ec2 describe-internet-gateways` | IGW và VPC nó đang gắn | 🟥 |
| `aws ec2 describe-security-groups` | Luật inbound/outbound của SG | 🟥 |
| `aws ec2 describe-network-acls` | Luật NACL và subnet gắn vào | 🟨 |
| `aws ec2 describe-vpc-attribute` | `enableDnsSupport`, `enableDnsHostnames` | 🟨 |
| `aws ec2 describe-availability-zones` | AZ của Region | 🟨 |
| `python3 -c "import ipaddress …"` | Kiểm tra CIDR, chồng lấn (đã học ở Network 02) | 🟥 |

## 8. Giải thích câu lệnh và tham số

> Đầu ra trong mục này là **minh họa** (ID, số liệu là giả). Kết quả của bạn sẽ khác.

Chuẩn bị một lần cho cả phiên `[WSL]`:

```bash
export AWS_PROFILE=taskhub
export AWS_REGION=ap-southeast-1
aws sts get-caller-identity --query Arn --output text   # đang đăng nhập là ai?
```

```text
arn:aws:iam::111122223333:user/phuong-admin
```

### `describe-vpcs` — tìm VPC mặc định

```bash
aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock,Default:IsDefault}' \
  --output table
```

```text
-------------------------------------------------------
|                    DescribeVpcs                     |
+----------------+----------+-------------------------+
|      Cidr      | Default  |           Id            |
+----------------+----------+-------------------------+
|  172.31.0.0/16 |  True    |  vpc-0a1b2c3d4e5f60718  |
+----------------+----------+-------------------------+
```

| Phần | Ý nghĩa |
|---|---|
| `--filters Name=isDefault,Values=true` | **Lọc phía server** — AWS chỉ trả VPC mặc định. Tên filter có trong trang tài liệu của từng lệnh |
| `--query '…'` | **Lọc phía client** bằng ngôn ngữ JMESPath: chọn trường cần xem |
| `Vpcs[]` | Duyệt mảng `Vpcs` trong JSON trả về |
| `{Id:VpcId,Cidr:CidrBlock}` | Tạo object mới với tên cột tự đặt |
| `--output table` | Dạng bảng cho người đọc. `text` cho script, `json` (mặc định) khi cần đầy đủ |

Không thấy gì? Gần như chắc chắn là **sai Region** — kiểm tra `echo $AWS_REGION`. Mỗi Region có VPC riêng.

### `describe-subnets` — đếm IP dùng được

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
           --query 'Vpcs[0].VpcId' --output text)

aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'Subnets[].{AZ:AvailabilityZone,Cidr:CidrBlock,Free:AvailableIpAddressCount,PublicIp:MapPublicIpOnLaunch}' \
  --output table
```

```text
---------------------------------------------------------------
|                       DescribeSubnets                       |
+------------------+-----------------+--------+---------------+
|        AZ        |      Cidr       | Free   |   PublicIp    |
+------------------+-----------------+--------+---------------+
|  ap-southeast-1a |  172.31.32.0/20 |  4091  |  True         |
|  ap-southeast-1b |  172.31.0.0/20  |  4091  |  True         |
|  ap-southeast-1c |  172.31.16.0/20 |  4091  |  True         |
+------------------+-----------------+--------+---------------+
```

| Trường | Ý nghĩa |
|---|---|
| `AvailableIpAddressCount` | IP còn trống = 4.096 (của `/20`) − 5 (AWS giữ) − số IP đang dùng. Subnet trống: **4091** |
| `MapPublicIpOnLaunch` | Thuộc tính *auto-assign public IPv4* |
| `$(...)` + `--output text` | Lấy một giá trị thô để gán vào biến shell — mẫu dùng rất nhiều trong script |

### `describe-route-tables` — subnet nào public?

```bash
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'RouteTables[].{Id:RouteTableId,Main:Associations[0].Main,Routes:Routes[].[DestinationCidrBlock,GatewayId]}' \
  --output json
```

```json
[
  {
    "Id": "rtb-0123456789abcdef0",
    "Main": true,
    "Routes": [
      ["172.31.0.0/16", "local"],
      ["0.0.0.0/0", "igw-0fedcba9876543210"]
    ]
  }
]
```

Đọc: VPC mặc định chỉ có **main route table**, chứa route tới IGW → mọi subnet không gắn route table riêng (tức là cả ba) đều **public**.

| Trường | Ý nghĩa |
|---|---|
| `Associations[].Main` | `true` = đây là main route table |
| `Associations[].SubnetId` | Subnet được gắn **rõ ràng** vào bảng này |
| `Routes[].GatewayId` | `local`, `igw-…`, hoặc trống nếu target là NAT (`NatGatewayId`), endpoint… |

### `describe-security-groups` — đọc luật

```bash
aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values=default \
  --query 'SecurityGroups[].IpPermissions[].{Proto:IpProtocol,From:FromPort,To:ToPort,SrcCidr:IpRanges[].CidrIp,SrcSG:UserIdGroupPairs[].GroupId}' \
  --output json
```

```json
[
  {
    "Proto": "-1",
    "From": null,
    "To": null,
    "SrcCidr": [],
    "SrcSG": ["sg-0aaaabbbbccccdddd"]
  }
]
```

Đọc: default SG cho phép **mọi giao thức** (`-1`) từ **chính nó** (nguồn là SG của chính nó) — các máy cùng mang default SG nói chuyện được với nhau. Đây là ví dụ đầu tiên của "SG tham chiếu SG".

| Trường | Ý nghĩa |
|---|---|
| `IpPermissions` | Luật **inbound**. Luật outbound nằm ở `IpPermissionsEgress` |
| `IpProtocol: "-1"` | Mọi giao thức |
| `IpRanges[].CidrIp` | Nguồn là dải IPv4 |
| `UserIdGroupPairs[].GroupId` | Nguồn là một Security Group |

### `describe-network-acls` và `describe-vpc-attribute`

```bash
aws ec2 describe-network-acls \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'NetworkAcls[].Entries[].{N:RuleNumber,Out:Egress,Action:RuleAction,Cidr:CidrBlock,Proto:Protocol}' \
  --output table

aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames \
  --query 'EnableDnsHostnames.Value'
```

```text
----------------------------------------------------
|               DescribeNetworkAcls                |
+--------+-------------+--------+--------+---------+
| Action |    Cidr     |   N    |  Out   |  Proto  |
+--------+-------------+--------+--------+---------+
|  allow |  0.0.0.0/0  |  100   |  True  |  -1     |
|  deny  |  0.0.0.0/0  |  32767 |  True  |  -1     |
|  allow |  0.0.0.0/0  |  100   |  False |  -1     |
|  deny  |  0.0.0.0/0  |  32767 |  False |  -1     |
+--------+-------------+--------+--------+---------+
true
```

- Luật `32767` là luật `*` hiển thị trên console — chặn mọi thứ không khớp luật trước. Ở NACL mặc định, luật 100 đã allow tất cả nên luật `*` không bao giờ được dùng tới.
- `Egress: True` = luật outbound.
- VPC mặc định có `enableDnsHostnames = true`. VPC bạn tạo ở lab sẽ là `false` cho đến khi bạn bật.

### `python3 ipaddress` — kiểm tra kế hoạch trước khi click

```bash
python3 - <<'EOF'
import ipaddress as ip
vpc = ip.ip_network("10.20.0.0/16")
subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.11.0/24", "10.20.12.0/24"]
avoid = ["172.16.0.0/12", "192.168.0.0/16", "172.31.0.0/16"]
for s in map(ip.ip_network, subnets):
    print(s, "trong VPC:", s.subnet_of(vpc), "| dùng được trên AWS:", s.num_addresses - 5)
for a in map(ip.ip_network, avoid):
    print("VPC trùng", a, "?", vpc.overlaps(a))
EOF
```

```text
10.20.1.0/24 trong VPC: True | dùng được trên AWS: 251
10.20.2.0/24 trong VPC: True | dùng được trên AWS: 251
10.20.11.0/24 trong VPC: True | dùng được trên AWS: 251
10.20.12.0/24 trong VPC: True | dùng được trên AWS: 251
VPC trùng 172.16.0.0/12 ? False
VPC trùng 192.168.0.0/16 ? False
VPC trùng 172.31.0.0/16 ? False
```

---

## 9. Bài thực hành từng bước

> Bài thực hành này **chỉ đọc** VPC mặc định và kiểm tra kế hoạch trên giấy — **0 USD**. Việc tạo VPC thật nằm ở [Lab 01](labs/lab-01-vpc-by-hand.md).
>
> Nếu chưa cấu hình CLI, làm Bước 2–4 trên console: **VPC console** → **Your VPCs / Subnets / Route tables / Security groups / Network ACLs**, chọn Region **Asia Pacific (Singapore)** ở góc phải trên.

### Bước 1 — Rà soát kế hoạch mạng `[WSL]`

1. Mở `~/projects/taskhub/docs/network-plan.md` (tuần 4).
2. Đối chiếu dải VPC với bảng "cần tránh" ở §4.1. Chạy đoạn Python ở mục 8 với **số liệu của bạn**.
3. Bổ sung vào file: cột "IP dùng được trên AWS" (= tổng − 5), tên đầy đủ theo quy ước (`taskhub-public-a`…), và một dòng "Không dùng NAT Gateway — lý do: …".

### Bước 2 — Đọc VPC mặc định `[WSL]`

Chạy lần lượt các lệnh ở mục 8 (`describe-vpcs`, `describe-subnets`, `describe-route-tables`, `describe-security-groups`, `describe-network-acls`, `describe-vpc-attribute`). Ghi vào `week11/vpc-notes.md`:

- CIDR của default VPC, số subnet, mỗi subnet ở AZ nào, bao nhiêu IP trống.
- Route table: có bao nhiêu bảng? Bảng nào là main? Có route tới IGW không?
- Vì sao **mọi** subnet của default VPC đều là public? (Trả lời bằng dữ liệu bạn vừa đọc, không chép lý thuyết.)

### Bước 3 — Đếm AZ của Region `[WSL]`

```bash
aws ec2 describe-availability-zones \
  --query 'AvailabilityZones[].{Name:ZoneName,Id:ZoneId,State:State}' --output table
```

So sánh số AZ với số subnet của default VPC. Ghi lại: `ZoneName` (`ap-southeast-1a`) và `ZoneId` (`apse1-az1`…) khác nhau thế nào? Theo [tài liệu AZ](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-availability-zones.html): **AZ ID** luôn chỉ cùng một địa điểm vật lý ở mọi tài khoản; còn **tên** `a/b/c` thì ở các tài khoản tạo trước tháng 11/2025 (tại các Region lâu đời) được ánh xạ **riêng cho từng tài khoản**, từ tháng 11/2025 thì tài khoản mới được ánh xạ giống nhau. Khi trao đổi với người ở tài khoản khác (ví dụ "đặt RDS cùng AZ với hệ thống của đối tác"), hãy dùng **AZ ID**.

### Bước 4 — Vẽ hành trình gói tin `[giấy hoặc file]`

Không nhìn §4.12, vẽ lại 11 bước của một request HTTP vào EC2 trong **default VPC** (EC2 giả định ở `ap-southeast-1a`, SG chỉ mở 80). Với mỗi bước ghi: thành phần, bảng/luật được xét, kết quả. Sau đó so với §4.12.

### Bước 5 — Thiết kế NACL trên giấy

Viết bảng NACL (inbound + outbound) cho `taskhub-private-a` biết rằng: chỉ RDS PostgreSQL (5432) nằm trong đó, chỉ subnet `taskhub-public-a` (`10.20.1.0/24`) được kết nối tới, và RDS không cần ra Internet. Nhớ chiều trả lời. (Đây là bài tập thiết kế — **không** tạo trên AWS. Lời giải trong [solutions/03-solutions.md](solutions/03-solutions.md).)

### Bước 6 — Commit `[WSL]`

```bash
cd ~/projects/taskhub
git switch -c docs/network-plan-aws
git add docs/network-plan.md
git commit -m "docs(network): finalize VPC plan for AWS (reserved IPs, names, no NAT)"
git push -u origin docs/network-plan-aws
```

Mở PR, CI phải xanh (thay đổi chỉ là tài liệu nhưng workflow `CI` vẫn chạy), squash merge.

## 10. Kết quả mong đợi

- [ ] `docs/network-plan.md` có dải VPC không trùng `172.16.0.0/12`, `192.168.0.0/16`, `172.31.0.0/16`; 4 subnet trong 2 AZ; cột IP dùng được = tổng − 5; ghi chú "không NAT Gateway" kèm lý do.
- [ ] `week11/vpc-notes.md` mô tả default VPC bằng **dữ liệu thật** của tài khoản bạn (CIDR, subnet, route, SG, NACL, DNS attribute).
- [ ] Giải thích được bằng lời: vì sao mọi subnet của default VPC là public.
- [ ] Bảng NACL thiết kế cho `private-a` có luật chiều trả lời đúng.
- [ ] Không có tài nguyên nào được tạo (kiểm tra: **Billing → Bills** không có dòng VPC/EC2 mới).

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách tránh / sửa |
|---|---|---|
| `describe-*` trả mảng rỗng | Sai Region (CLI mặc định `us-east-1` hoặc Region khác) | `export AWS_REGION=ap-southeast-1` hoặc `--region ap-southeast-1` |
| Đặt tên subnet "public" và nghĩ thế là đủ | Subnet chưa gắn route table có IGW → dùng main route table | Luôn kiểm tra tab **Route table** của subnet |
| Thêm route IGW vào **main** route table | Mọi subnet "quên gắn" thành public | Để main route table chỉ có `local` |
| Chọn VPC `172.17.0.0/16` hoặc `192.168.1.0/24` | Trùng Docker hoặc mạng nhà | Dùng khối `10.0.0.0/8`, kiểm tra bằng Python trước |
| NACL custom chỉ mở 80/443 hai chiều | Quên ephemeral port | Mở 1024–65535 cho chiều trả lời |
| Tưởng SG có luật deny để "chặn một IP" | SG chỉ có allow | Chặn IP cụ thể bằng NACL (luật deny số nhỏ) |
| Bật wizard "VPC and more" để "nhanh" | Có thể tạo NAT Gateway nếu ô NAT không phải *None* | Đọc từng ô; trong giáo trình, dựng bằng tay ở lab |
| EC2 không có public DNS name | `enableDnsHostnames = false` (mặc định cho VPC tự tạo) | Bật trong **Edit VPC settings** |

## 12. Đọc thông báo lỗi và xử lý

> Thông báo dưới đây là **minh họa** theo dạng lỗi của AWS CLI (`An error occurred (<Mã lỗi>) when calling the <Thao tác> operation: <thông điệp>`). Chữ chính xác có thể khác; hãy đọc **mã lỗi** trong ngoặc.

| Thông báo (rút gọn) | Ý nghĩa | Xử lý |
|---|---|---|
| `(UnauthorizedOperation) … You are not authorized to perform this operation` | User/role thiếu quyền IAM cho thao tác đó | Xem lại policy ([bài 02](02-iam.md)); thông điệp thường kèm *encoded authorization message* — giải mã bằng `aws sts decode-authorization-message` |
| `(ExpiredToken)` hoặc yêu cầu đăng nhập lại | Phiên `aws login` hết hạn (tối đa 12 giờ) | `aws login --profile taskhub` |
| `(InvalidSubnet.Conflict) The CIDR '…' conflicts with another subnet` | Subnet mới chồng lấn subnet đã có | Tính lại bằng `ipaddress` |
| `(InvalidSubnet.Range) The CIDR '…' is invalid` | Subnet nằm ngoài dải VPC hoặc nhỏ hơn `/28` | Kiểm tra `subnet_of(vpc)` và prefix |
| `(DependencyViolation) The vpc '…' has dependencies and cannot be deleted` | Còn subnet, IGW, ENI, SG… trong VPC | Xóa theo thứ tự ở [Lab 01 — Dọn dẹp](labs/lab-01-vpc-by-hand.md) |
| `(RouteAlreadyExists)` | Đã có route cùng đích trong bảng | Sửa (replace) route thay vì tạo mới |

**Quy trình khi "không vào được EC2"** — đi theo đúng thứ tự gói tin, đừng nhảy cóc:

1. Instance có **public IP** không? (`describe-instances … PublicIpAddress`)
2. Subnet của nó gắn **route table nào**, có `0.0.0.0/0 → igw` không?
3. IGW có **attached** vào đúng VPC không?
4. **NACL** của subnet: inbound port đích + outbound ephemeral?
5. **SG**: inbound đúng port, đúng nguồn?
6. Trong máy: dịch vụ có nghe `0.0.0.0:<port>` không? (`ss -ltnp` qua SSM)
7. Vẫn không ra → **Reachability Analyzer** (0,10 USD/lần) hoặc bật **Flow Logs** tạm thời để xem `REJECT`.

## 13. Câu hỏi kiểm tra kiến thức

1. VPC thuộc phạm vi nào (toàn cầu, Region hay AZ)? Subnet thì sao? Hệ quả với thiết kế 2 AZ?
2. Kích thước dải IPv4 cho phép của VPC và subnet? Có đổi được dải chính của VPC sau khi tạo không?
3. Subnet `10.20.11.0/24`: liệt kê 5 địa chỉ AWS giữ lại và vai trò của từng địa chỉ. Còn bao nhiêu IP dùng được?
4. "Public subnet" và "private subnet" khác nhau ở điểm nào? Instance có public IP trong private subnet có ra Internet được không? Vì sao?
5. Main route table là gì? Vì sao nên để nó chỉ có route `local`?
6. Liệt kê 6 điều kiện để một EC2 phục vụ được HTTP ra Internet qua IPv4.
7. IGW làm NAT kiểu gì? NAT Gateway làm NAT kiểu gì? Cái nào tốn tiền theo giờ?
8. Vì sao `taskhub` không dùng NAT Gateway? Nếu sau này cần cho máy private ghi backup lên S3 thì dùng gì, giá bao nhiêu?
9. Trong 11 bước ở §4.12: nếu thiếu luật SG inbound port 80 thì client thấy "connection refused" hay "timeout"? Nếu Nginx không chạy (SG đúng) thì sao?
10. Stateful và stateless khác nhau thế nào? Áp vào SG và NACL.
11. Viết luật NACL outbound tối thiểu để web server trong subnet trả lời được client Windows 11 trên Internet.
12. Vì sao "SG tham chiếu SG" tốt hơn ghi IP của EC2 vào luật SG của RDS?
13. `enableDnsHostnames` mặc định là gì với VPC bạn tự tạo? Ảnh hưởng gì?
14. Default VPC có những gì sẵn? Nêu 2 lý do dự án không dùng nó.
15. Flow Logs và Reachability Analyzer khác nhau thế nào về cách hoạt động và chi phí?

## 14. Bài tập tự làm

**Bài 1 — Chia VPC cho môi trường thứ hai.** Thiết kế VPC `prod` cho `taskhub`: không trùng `taskhub-vpc` dev, có 3 AZ, mỗi AZ một public `/24` và một private `/22`. Viết bảng đầy đủ (tên, AZ, CIDR, số IP dùng được). Kiểm tra bằng Python: không subnet nào chồng lấn, VPC dev và prod không chồng lấn.

**Bài 2 — Đọc route table lạ.** Một VPC `10.50.0.0/16` có các route table sau. Với mỗi subnet, cho biết public hay private, và một instance trong đó có `apt update` được không (giả sử SG/NACL mở hết):

```text
rtb-A (main):  10.50.0.0/16 local
rtb-B:         10.50.0.0/16 local ; 0.0.0.0/0 igw-1
rtb-C:         10.50.0.0/16 local ; 0.0.0.0/0 nat-1   (nat-1 nằm trong subnet S1)
Subnet S1 → rtb-B · S2 → rtb-C · S3 → (không gắn) · S4 → rtb-C, nhưng nat-1 đã bị xóa
```

**Bài 3 — NACL bẫy.** Một bạn sửa NACL của public subnet thành: inbound `100 allow TCP 80 0.0.0.0/0`, `110 allow TCP 443 0.0.0.0/0`; outbound `100 allow TCP 1024-65535 0.0.0.0/0`. Website chạy được, nhưng `docker pull` trên EC2 bị treo. Giải thích chính xác gói tin nào bị chặn ở đâu, và sửa tối thiểu.

**Bài 4 — Thứ tự luật.** NACL inbound: `90 deny TCP 22 0.0.0.0/0`, `100 allow TCP 22 203.0.113.7/32`. SSH từ `203.0.113.7` có vào được không? Đổi số 90 thành 120 thì sao? Từ đó rút ra quy tắc đặt luật deny.

**Bài 5 — Ước tính chi phí.** Dùng [AWS Pricing Calculator](https://calculator.aws/), Region Asia Pacific (Singapore), ước tính chi phí tháng của kiến trúc §6.3 (2 NAT Gateway, 10 GB dữ liệu mỗi tháng qua mỗi NAT) so với kiến trúc §6.1 (không NAT, 1 public IPv4). Chụp/ghi lại cấu hình bạn nhập. Viết 3 câu kết luận cho ADR "không dùng NAT Gateway".

**Bài 6 — Giải thích cho người không chuyên.** Viết một đoạn ≤ 150 từ giải thích cho một bạn lập trình viên front-end: "VPC, subnet, route table, Security Group" bằng một phép so sánh đời thường (tòa nhà, tầng, thang máy, bảo vệ…). Chỉ ra **một** chỗ phép so sánh của bạn bị sai so với thực tế.

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Vẽ được VPC `taskhub` từ trí nhớ: CIDR, 4 subnet, 2 route table, IGW, SG — và giải thích từng mảnh.
- [ ] Nói được trong một câu: "public subnet là subnet gắn với route table có route `0.0.0.0/0` tới Internet Gateway."
- [ ] Đi lại hành trình gói tin vào/ra EC2 mà không nhìn tài liệu, chỉ ra chỗ SG và NACL khác nhau.
- [ ] Viết đúng NACL có ephemeral port cho một tình huống mới.
- [ ] Ước tính được một NAT Gateway tốn bao nhiêu mỗi tháng và chỉ ra 2 cách tránh nó.
- [ ] Đọc được cấu hình VPC bằng CLI với `--filters` và `--query`.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Amazon VPC FAQ](https://aws.amazon.com/vpc/faqs/) | VPC không tính phí; dải `/28`–`/16`, tối đa 5 dải IPv4 | 2026-10-31 |
| [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Public IPv4 0,005 USD/giờ; NAT Gateway (ví dụ US East Ohio 0,045 USD/giờ + 0,045 USD/GB); gateway endpoint miễn phí; Reachability Analyzer 0,10 USD/lần | 2026-10-31 |
| [AWS Price List — AmazonVPC, ap-southeast-1](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/ap-southeast-1/index.json) | Giá Singapore: public IPv4 0,005; interface endpoint 0,013 USD/giờ; Reachability Analyzer 0,10 | 2026-10-31 |
| [AWS — Subnet CIDR blocks](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html) | 5 địa chỉ bị giữ lại | 2026-10-31 |
| [AWS — Internet gateways](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html) | Định nghĩa public/private subnet, NAT 1-1, IGW không tính phí | 2026-10-31 |
| [AWS — Subnet IP addressing attributes](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-public-ip.html) | *Enable auto-assign public IPv4 address*, mặc định `false` cho subnet tự tạo | 2026-10-31 |
| [AWS — Security groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html) | Stateful, chỉ allow, không tính phí, lưu lượng không bị lọc | 2026-10-31 |
| [AWS — Network ACLs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html) | Stateless, thứ tự luật, một NACL mỗi subnet | 2026-10-31 |
| [AWS — Custom network ACLs & ephemeral ports](https://docs.aws.amazon.com/vpc/latest/userguide/custom-network-acl.html) | Bảng ephemeral port theo client, khuyến nghị 1024–65535, luật `*` | 2026-10-31 |
| [AWS — Default VPC components](https://docs.aws.amazon.com/vpc/latest/userguide/default-vpc-components.html) | `172.31.0.0/16`, subnet `/20` mỗi AZ | 2026-10-31 |
| [AWS — Understanding Amazon DNS](https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html) | VPC+2, `169.254.169.253`, `enableDnsHostnames`/`enableDnsSupport` | 2026-10-31 |
| [AWS — Create a VPC](https://docs.aws.amazon.com/vpc/latest/userguide/create-vpc.html) | *VPC only* vs *VPC and more*, egress-only IGW, lệnh CLI | 2026-10-31 |
| [AWS — VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html) | Đích lưu log, phí vended logs | 2026-10-31 |
| [Docker Desktop — Settings](https://docs.docker.com/desktop/settings-and-maintenance/settings/) | Dải nội bộ mặc định `192.168.65.0/24` | 2026-10-31 |
| [AWS CLI — ec2 reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/) | Tham số và filter của các lệnh `describe-*` | 2026-10-31 |
