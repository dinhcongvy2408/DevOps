# Lời giải — Bài 03: VPC

> Chỉ mở sau khi đã tự làm. Bài: [03-vpc-networking.md](../03-vpc-networking.md)

## Mục lục

- [Bài thực hành mục 9 — Bước 5: NACL cho private-a](#bài-thực-hành-mục-9--bước-5-nacl-cho-private-a)
- [Câu hỏi kiểm tra kiến thức (mục 13)](#câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Bài tập tự làm (mục 14)](#bài-tập-tự-làm-mục-14)

---

## Bài thực hành mục 9 — Bước 5: NACL cho private-a

Yêu cầu: chỉ PostgreSQL 5432, chỉ từ `taskhub-public-a` (`10.20.1.0/24`), RDS không ra Internet.

**Inbound**

| # | Giao thức | Port | Nguồn | Allow/Deny | Lý do |
|---|---|---|---|---|---|
| 100 | TCP | 5432 | `10.20.1.0/24` | ALLOW | App ở public-a mở kết nối tới PostgreSQL |
| * | Tất cả | Tất cả | `0.0.0.0/0` | DENY | Mọi thứ khác |

**Outbound**

| # | Giao thức | Port | Đích | Allow/Deny | Lý do |
|---|---|---|---|---|---|
| 100 | TCP | 1024–65535 | `10.20.1.0/24` | ALLOW | **Gói trả lời** của PostgreSQL về ephemeral port của app |
| * | Tất cả | Tất cả | `0.0.0.0/0` | DENY | RDS không cần chủ động gọi ra đâu |

Giải thích các điểm hay sai:

- **Chiều trả lời đi ra (outbound) tới ephemeral port của client.** NACL stateless nên không có dòng outbound 100 thì app gửi được câu truy vấn, nhưng không bao giờ nhận được kết quả → treo tới khi timeout.
- **Vì sao 1024–65535 mà không phải 32768–60999?** App chạy trong container trên EC2; port nguồn thực tế do kernel của EC2 chọn (sau khi Docker NAT). Dải chính xác phụ thuộc hệ điều hành. AWS khuyên mở 1024–65535 để bao mọi loại client. Hẹp hơn vẫn đúng nếu bạn chắc chắn về client, nhưng dễ vỡ khi đổi AMI.
- **Không cần luật cho DNS.** NACL không lọc được lưu lượng tới Amazon DNS.
- 🟨 Nếu dùng RDS **Multi-AZ** (bản chính ở private-a, bản dự phòng ở private-b), AWS quản lý việc đồng bộ giữa hai bản. Khi làm lab tuần 14, giữ NACL mặc định (cho tất cả) để không phải đoán các luồng nội bộ của dịch vụ được quản lý; đây chỉ là bài tập thiết kế.
- Bảo vệ chính vẫn là **Security Group** của RDS: inbound 5432 từ **SG của app** (tham chiếu SG). NACL chỉ là lớp phụ.

---

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** VPC thuộc phạm vi **Region** và trải trên mọi AZ của Region đó. Subnet thuộc **đúng một AZ**. Hệ quả: muốn chịu được sự cố một AZ thì cần ít nhất 2 subnet ở 2 AZ cho mỗi tầng (public, private) — đó là lý do có `-a` và `-b`. ALB và DB subnet group của RDS bắt buộc chọn subnet ở ≥ 2 AZ.

**2.** Mỗi dải IPv4 của VPC: từ `/28` đến `/16`; tối đa 5 dải (1 chính + 4 phụ). Subnet IPv4 cũng trong khoảng `/28`–`/16` và nằm trong dải VPC. **Không** đổi được dải chính sau khi tạo — chỉ thêm dải phụ, hoặc tạo VPC mới và di chuyển.

**3.** `10.20.11.0` (địa chỉ mạng), `10.20.11.1` (router VPC), `10.20.11.2` (theo quy ước dành cho DNS — DNS thực sự của VPC nằm ở địa chỉ gốc VPC + 2 = `10.20.0.2`), `10.20.11.3` (dự phòng), `10.20.11.255` (broadcast, VPC không hỗ trợ nên giữ lại). Còn **251** IP dùng được.

**4.** Khác nhau ở **route table** gắn với subnet: có route `0.0.0.0/0` tới Internet Gateway → public; không có → private. Instance có public IP nằm trong private subnet **không** ra Internet được, vì gói trả lời (và gói đi ra) không có route tới IGW — IGW chỉ dịch địa chỉ cho lưu lượng được định tuyến tới nó.

**5.** Main route table là bảng tạo sẵn cùng VPC; mọi subnet không gắn rõ ràng vào bảng nào sẽ dùng nó. Để nó chỉ có `local` thì subnet mới "quên gắn" mặc định thành **private** — sai theo hướng an toàn. Nếu main có route IGW, subnet quên gắn tự thành public — lỗ hổng âm thầm.

**6.** (1) IGW gắn vào VPC; (2) route table của subnet có `0.0.0.0/0 → igw`; (3) instance có public IPv4 (auto-assign hoặc Elastic IP); (4) NACL cho phép port đích vào và ephemeral port ra; (5) Security Group cho phép inbound port đó; (6) ứng dụng lắng nghe trên `0.0.0.0` chứ không phải `127.0.0.1`.

**7.** IGW: NAT **1-1** giữa IP private và public IP **riêng** của từng instance; Internet khởi tạo kết nối vào được. NAT Gateway: SNAT/PAT **nhiều-1** — nhiều máy private dùng chung một Elastic IP để **đi ra**, Internet không khởi tạo vào được. NAT Gateway tính tiền theo giờ + theo GB; IGW không tính phí (chỉ phí truyền dữ liệu).

**8.** EC2 duy nhất nằm ở public subnet, ra Internet qua IGW miễn phí; private subnet chỉ chứa RDS ở lab, không cần ra Internet. Một NAT Gateway ≈ 32 USD/tháng chỉ phần theo giờ (ở mức giá 0,045 USD/giờ) — quá đắt so với lợi ích cho dự án học. Ghi S3 từ máy private: **Gateway VPC endpoint cho S3**, thêm vào `taskhub-private-rt`, **miễn phí** (không phí giờ, không phí xử lý dữ liệu).

**9.** Thiếu luật SG inbound 80: SG **lặng lẽ bỏ** gói SYN → client không nhận được gì → **timeout**. SG đúng nhưng Nginx không chạy: gói tới được hệ điều hành, không có process nghe port 80 → kernel trả **RST** → client thấy **connection refused** ngay lập tức. Phân biệt hai triệu chứng này giúp khoanh vùng: refused = mạng thông, lỗi ở dịch vụ; timeout = bị chặn/không có đường ở đâu đó.

**10.** Stateful: thiết bị nhớ kết nối đã cho phép, gói trả lời tự được cho qua — **Security Group**. Stateless: xét từng gói độc lập, phải viết luật cho cả hai chiều — **Network ACL**.

**11.** Client Windows (Server 2008 trở lên, gồm Windows 10/11) dùng ephemeral port 49152–65535. Tối thiểu: outbound `ALLOW TCP 49152–65535 → 0.0.0.0/0`. Thực tế nên dùng `1024–65535` để bao cả client Linux, ELB, NAT.

**12.** IP của EC2 thay đổi (stop/start, Auto Scaling thêm/bớt máy); luật ghi IP sẽ sai mà không ai biết. Luật "5432 từ `sg-app`" đúng với **mọi** ENI mang SG đó, bất kể IP — vừa đúng hơn, vừa không phải sửa khi hạ tầng co giãn. Nó cũng diễn đạt ý định ("chỉ tầng app được nói chuyện với DB") thay vì một con số.

**13.** `false`. Instance có public IP sẽ **không** được cấp public DNS hostname; nếu tắt cả `enableDnsSupport` thì Amazon DNS không phân giải được hostname private. Private hosted zone của Route 53 và private DNS của interface endpoint yêu cầu cả hai thuộc tính là `true`.

**14.** CIDR `172.31.0.0/16`, một subnet `/20` mỗi AZ, IGW, main route table có `0.0.0.0/0 → igw` (mọi subnet đều public), subnet tự cấp public IP, default SG, default NACL. Lý do không dùng (chọn 2): không có private subnet thật; dải `172.31/16` trùng mọi default VPC khác và nằm trong khối `172.16/12` của Docker/WSL; không học được gì về từng thành phần; không tái tạo bằng Terraform một cách sạch sẽ.

**15.** Flow Logs **ghi lại** metadata lưu lượng thật đi qua ENI (gồm ACCEPT/REJECT), gửi tới CloudWatch Logs/S3/Firehose — tính phí vended logs theo dung lượng. Reachability Analyzer **phân tích tĩnh** cấu hình (không gửi gói tin), chỉ ra thành phần chặn đường — 0,10 USD mỗi lần phân tích. Flow Logs trả lời "chuyện gì đã xảy ra"; Reachability Analyzer trả lời "theo cấu hình thì có đi được không, kẹt ở đâu".

---

## Bài tập tự làm (mục 14)

### Bài 1 — VPC prod

Ví dụ một đáp án (nhiều đáp án đúng):

| Tên | AZ | CIDR | IP dùng được |
|---|---|---|---|
| VPC `taskhub-prod-vpc` | — | `10.30.0.0/16` | — |
| public-a / b / c | 1a / 1b / 1c | `10.30.1.0/24`, `10.30.2.0/24`, `10.30.3.0/24` | 251 mỗi subnet |
| private-a / b / c | 1a / 1b / 1c | `10.30.16.0/22`, `10.30.20.0/22`, `10.30.24.0/22` | 1.019 mỗi subnet |

Bẫy: một `/22` phải **bắt đầu ở bội số của 4** ở octet thứ ba (block size 4 — [Network 02 §4.4](../../02-NETWORKING/02-ipv4-subnet-cidr.md#44--phương-pháp-tính-nhanh-kích-thước-khối-block-size)). `10.30.11.0/22` là CIDR không chuẩn — AWS sẽ tự sửa thành `10.30.8.0/22`, có thể chồng lên subnet khác.

Kiểm tra:

```bash
python3 - <<'EOF'
import ipaddress as ip, itertools
dev = ip.ip_network("10.20.0.0/16")
prod = ip.ip_network("10.30.0.0/16")
subnets = [ip.ip_network(c) for c in ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24",
                                      "10.30.16.0/22", "10.30.20.0/22", "10.30.24.0/22"]]
print("dev/prod chồng lấn:", dev.overlaps(prod))
print("subnet ngoài VPC:", [str(s) for s in subnets if not s.subnet_of(prod)])
print("cặp chồng lấn:", [(str(a), str(b)) for a, b in itertools.combinations(subnets, 2) if a.overlaps(b)])
EOF
```

```text
dev/prod chồng lấn: False
subnet ngoài VPC: []
cặp chồng lấn: []
```

### Bài 2 — Đọc route table lạ

| Subnet | Route table | Loại | `apt update` được? |
|---|---|---|---|
| S1 | rtb-B (`0.0.0.0/0 → igw-1`) | **Public** | Được — **nếu instance có public IP**. Không có public IP thì không (IGW chỉ NAT 1-1 cho instance có public IP) |
| S2 | rtb-C (`0.0.0.0/0 → nat-1`) | **Private** | Được — đi ra qua NAT Gateway nằm ở S1 (S1 public, NAT có Elastic IP) |
| S3 | Không gắn → main rtb-A (chỉ `local`) | **Private** | Không — không có đường ra |
| S4 | rtb-C, nhưng nat-1 đã xóa | **Private** | Không — route trỏ tới target không còn tồn tại chuyển sang trạng thái **blackhole**; gói tin khớp route đó bị bỏ |

Cách kiểm tra blackhole: `aws ec2 describe-route-tables … --query 'RouteTables[].Routes[].[DestinationCidrBlock,State]'` — trường `State` là `active` hoặc `blackhole`.

### Bài 3 — NACL bẫy

Cấu hình: inbound cho 80, 443; outbound cho 1024–65535.

- **Website chạy:** client → EC2:80 (inbound 100 cho qua) → trả lời EC2:80 → client:ephemeral (outbound 100 cho qua).
- **`docker pull` treo:** lần này **EC2 là client**. Gói SYN `EC2:ephemeral → registry:443` có port đích **443**, không nằm trong 1024–65535 → **bị chặn ở outbound**. (Kể cả khi đi qua được, gói trả lời `registry:443 → EC2:ephemeral` có port đích là ephemeral port, không phải 80/443 → **bị chặn ở inbound**.) Gói bị bỏ lặng lẽ → treo tới timeout.

Sửa tối thiểu:

| Hướng | # | Giao thức | Port | Nguồn/Đích | Allow |
|---|---|---|---|---|---|
| Outbound | 110 | TCP | 443 | `0.0.0.0/0` | ALLOW (gọi HTTPS ra: GHCR, SSM) |
| Outbound | 120 | TCP | 80 | `0.0.0.0/0` | ALLOW (nếu mirror `apt` dùng HTTP) |
| Inbound | 120 | TCP | 1024–65535 | `0.0.0.0/0` | ALLOW (trả lời cho kết nối do EC2 khởi tạo) |

Bài học: với NACL, mỗi luồng cần **hai luật** (một chiều đi, một chiều về), và phải xét cả trường hợp máy của bạn là **server** lẫn **client**.

### Bài 4 — Thứ tự luật

- `90 deny 22 0.0.0.0/0` rồi `100 allow 22 203.0.113.7/32`: gói từ `203.0.113.7` khớp luật **90** trước → **bị chặn**. Luật 100 không bao giờ được xét.
- Đổi 90 thành 120: gói từ `203.0.113.7` khớp **100** → cho qua; IP khác không khớp 100, rơi xuống 120 → chặn. Đúng ý định.
- Quy tắc: NACL dừng ở luật khớp **đầu tiên** → đặt luật **cụ thể** (ngoại lệ) ở số **nhỏ**, luật **chung** ở số lớn. Muốn chặn một IP xấu nằm trong dải bạn đang cho phép → luật deny cho IP đó phải có số **nhỏ hơn** luật allow dải.

### Bài 5 — Ước tính chi phí

Không có đáp án số duy nhất — giá Singapore bạn tự tra trong Calculator. Cách tính phải có:

```text
Kiến trúc có NAT (§6.3):
  2 NAT Gateway × giá_giờ × 730 giờ
+ 2 × 10 GB × giá_xử_lý_mỗi_GB
+ public IPv4 của mỗi NAT Gateway (Elastic IP) × 0,005 × 730   ← kiểm tra Calculator có tính dòng này
+ phí truyền dữ liệu ra Internet (giống nhau ở cả hai kiến trúc, có thể bỏ khi so sánh)

Kiến trúc không NAT (§6.1):
  1 public IPv4 × 0,005 × 730 ≈ 3,65 USD
```

Tham khảo với giá US East (Ohio) đã kiểm chứng (0,045 USD/giờ, 0,045 USD/GB): 2 × 0,045 × 730 ≈ 65,7 USD + 20 × 0,045 = 0,9 USD → **≈ 66,6 USD/tháng** chỉ riêng NAT, gấp khoảng 18 lần phương án một public IP. Ba câu kết luận cho ADR nên nêu: con số so sánh, lý do kỹ thuật không cần NAT (không có máy private nào phải ra Internet), và điều kiện sẽ xem xét lại (ví dụ: khi chuyển app sang private subnet sau ALB).

### Bài 6 — Giải thích cho người không chuyên

Ví dụ:

> VPC giống một **khu chung cư có tường rào**, mỗi tầng là một **subnet**. **Route table** là **sơ đồ chỉ đường dán ở mỗi tầng**: tầng nào có mũi tên "ra cổng chính" (Internet Gateway) thì người ở đó đi ra phố được — đó là tầng public. **Security Group** là **bảo vệ đứng trước cửa từng căn hộ**, cầm danh sách khách được vào; ai đã được mời vào thì lúc ra không bị hỏi lại. **NACL** là **barie ở đầu mỗi tầng**, kiểm tra cả lúc vào lẫn lúc ra.

Chỗ sai của phép so sánh (một ví dụ): ngoài đời, người ở tầng "không có mũi tên ra cổng" vẫn có thể tự tìm cầu thang đi ra; trong VPC, gói tin **không có route thì không đi được** — không có đường tắt. Ngoài ra, "bảo vệ" Security Group không chặn được một số lưu lượng (Amazon DNS, metadata), điều mà phép so sánh không thể hiện.

Đạt khi: đoạn văn đúng về bản chất (route table quyết định public/private, SG stateful theo tài nguyên, NACL stateless theo subnet) và tự chỉ ra được ít nhất một giới hạn của phép so sánh.
