# Lời giải — Lab 01: Dựng VPC `taskhub` bằng tay

> Chỉ mở sau khi đã tự làm và tự trả lời. Lab: [lab-01-vpc-by-hand.md](../labs/lab-01-vpc-by-hand.md)

## Mục lục

- [Các câu hỏi ❓ trong Phần B](#các-câu-hỏi--trong-phần-b)
- [Câu hỏi về script ở C6](#câu-hỏi-về-script-ở-c6)
- [Phần D — Thí nghiệm](#phần-d--thí-nghiệm)
- [Câu hỏi sau lab](#câu-hỏi-sau-lab)

---

## Các câu hỏi ❓ trong Phần B

**B1 — "VPC only" mà Resource map đã có gì?** AWS tự tạo cùng VPC: một **main route table** (chỉ có route `local`), một **default network ACL** (cho phép tất cả hai chiều) và một **default security group** (cho phép mọi lưu lượng từ chính nó; outbound tất cả). Bạn không tạo chúng nhưng chúng tồn tại — đó là lý do console xóa VPC cũng xóa chúng.

**B2 — Ngay sau khi tạo, `taskhub-public-a` dùng route table nào?** **Main route table**, vì chưa có liên kết rõ ràng nào. Main route table chỉ có `local` → lúc này subnet là **private**, dù tên có chữ "public". Bằng chứng: tab **Route table** của subnet chỉ hiện `10.20.0.0/16 → local`.

**B4 — Gắn IGW xong, public-a đã public chưa?** **Chưa.** IGW tồn tại và gắn vào VPC, nhưng chưa route table nào trỏ `0.0.0.0/0` tới nó. Gắn IGW là điều kiện cần, không đủ — subnet chỉ thành public ở B5, khi được gắn vào route table có route tới IGW.

**B6 — Có lựa chọn deny không?** Không. Security Group **chỉ có luật allow**; thứ không được allow thì bị chặn. Muốn chặn một nguồn cụ thể phải dùng **Network ACL** (có luật deny, xét theo số thứ tự).

---

## Câu hỏi về script ở C6

Subnet không gắn rõ ràng với route table nào sẽ dùng **main route table**. Khi đó lệnh `describe-route-tables --filters Name=association.subnet-id,…` trả về **rỗng** (`None` ở dạng text), vì association "main" không ghi `SubnetId`.

Bỏ dòng `[[ "$rt" == "None" ]] && rt="$main_rt"` thì script gọi tiếp `describe-route-tables --route-table-ids None` → lỗi, hoặc (tùy cách viết) coi subnet là "không có route IGW". Script sẽ **sai đúng ở tình huống nguy hiểm nhất**: nếu ai đó thêm route IGW vào main route table, một subnet quên gắn đã thực sự thành public, nhưng script vẫn báo nó là private. Kiểm tra tự động mà bỏ qua trường hợp mặc định thì còn tệ hơn không kiểm tra — vì nó cho bạn cảm giác an toàn sai.

---

## Phần D — Thí nghiệm

> Thông báo lỗi dưới đây là **minh họa**; đọc **mã lỗi** trong ngoặc.

**D1 — Subnet chồng lấn** `10.20.1.128/25` (nằm trong `10.20.1.0/24` của public-a):

```text
An error occurred (InvalidSubnet.Conflict) when calling the CreateSubnet operation: The CIDR '10.20.1.128/25' conflicts with another subnet
```

Subnet trong cùng VPC không được chồng lấn. Đây là lý do kiểm tra bằng `ipaddress` trước khi click.

**D2 — Ngoài dải VPC** `10.30.0.0/24`:

```text
An error occurred (InvalidSubnet.Range) when calling the CreateSubnet operation: The CIDR '10.30.0.0/24' is invalid.
```

Subnet phải là tập con của một dải CIDR của VPC.

**D3 — Quá nhỏ** `/29`: cũng `InvalidSubnet.Range` — subnet IPv4 nhỏ nhất là `/28`. Một `/28` hợp lệ có 16 địa chỉ, trừ 5 → **11** IP dùng được. Đủ cho vài endpoint nhưng gần như vô dụng cho EC2/ALB/RDS.

**D4 — Subnet "quên gắn":**

- `describe-route-tables --filters Name=association.subnet-id,Values=<temp>` trả về **rỗng** → subnet tạm dùng **main route table** (`taskhub-main-rt`, chỉ `local`) → **private**.
- `verify-vpc.sh` đổi 2 dòng thành FAIL: **Số subnet** (5 thay vì 4) và **Cả 4 subnet có tag Project=taskhub** (5, vì subnet tạm cũng có tag `Project`). Dòng của chính subnet tạm vẫn **PASS** (route IGW `False`, auto-assign `False` — khớp nhau).
- Nếu ở B5 bạn đã thêm route IGW vào main route table: subnet tạm **thành public ngay lập tức** mà không ai chủ động quyết định. Script sẽ báo dòng của subnet tạm FAIL (route IGW `True` nhưng auto-assign `False`), và dòng "Main route table không có route ra Internet" FAIL.
- Quy tắc cho team: *"Main route table chỉ có route `local`. Mọi subnet phải được gắn **rõ ràng** vào một route table có tên thể hiện ý định (`-public-rt` / `-private-rt`)."*

**D5 — Gỡ route `0.0.0.0/0`:**

- `taskhub-public-a` thành **private** (route table của nó không còn route tới IGW). `verify-vpc.sh` báo FAIL cho cả hai subnet public: route IGW `False` nhưng auto-assign `True`.
- Nếu có EC2 chạy Nginx ở đó: gói request từ Internet **vẫn tới được** EC2 (IGW dịch public IP → private IP, route `local` đưa vào subnet, SG cho qua). Nhưng **gói trả lời** có đích là IP Internet, không khớp route nào ngoài `local` → **bị bỏ**. Client không nhận được gì → **timeout**, không phải *connection refused*. Log Nginx thậm chí có thể ghi đã nhận request — một manh mối đánh lừa nếu bạn không nghĩ tới chiều về.

**D6 — Security Group không có deny:** form luật chỉ có Type/Protocol/Port/Source/Description — không có cột Allow/Deny. Muốn chặn hẳn một IP xấu khỏi subnet: **Network ACL** với luật `DENY` có số nhỏ hơn các luật `ALLOW`. Nhớ xóa luật SSH tạm.

**D7 — Wizard "VPC and more":**

- Wizard tạo trong một lần: VPC, subnet public/private theo số AZ, route table cho từng loại, IGW, (tùy chọn) NAT Gateway, (tùy chọn) egress-only IGW, (tùy chọn) S3 Gateway endpoint, bật DNS options.
- Ô **NAT gateways** cho chọn số AZ đặt NAT Gateway (không đặt, một AZ, hoặc mỗi AZ một cái). Chọn khác *None* → khung **Preview** xuất hiện NAT Gateway trong mỗi public subnet được chọn, và route table của private subnet trỏ `0.0.0.0/0` vào đó. Mỗi NAT Gateway **tính tiền theo giờ** từ lúc tạo.
- **S3 Gateway** endpoint: **miễn phí** (không phí giờ, không phí xử lý dữ liệu) — nó thêm một route tới S3 vào route table.
- Thứ bạn không muốn wizard tạo cho dự án: NAT Gateway (và Elastic IP đi kèm). Cũng nên tự đặt tên thay vì để *Name tag auto-generation* sinh tên theo mẫu của nó, để khớp quy ước `taskhub-*`.

---

## Câu hỏi sau lab

**1.** Sau B2, cả 4 subnet đều **private**: chúng dùng main route table (chỉ `local`) và chưa có IGW. Bằng chứng: tab **Route table** của từng subnet; hoặc `describe-route-tables --filters Name=association.subnet-id,…` trả rỗng (→ main), và main không có `0.0.0.0/0`.

**2.** Không ảnh hưởng. *Auto-assign public IPv4* chỉ được dùng **tại thời điểm launch** instance (quyết định ENI có nhận public IP không). Route table quyết định gói tin đi đâu. Hai cấu hình độc lập; chỉ cần cả hai đúng **trước khi** launch EC2 ở bài 04. (Instance đã launch mà không có public IP thì bật thuộc tính subnet sau đó cũng không tự cấp IP cho nó.)

**3.** Subnet không gắn rõ ràng dùng main route table — nên main route table quyết định trạng thái "mặc định" của mọi subnet mới. Quy tắc: xem lời giải D4.

**4.**

| Tình huống | Client thấy | Vì sao |
|---|---|---|
| Thiếu route IGW | **Timeout** | Request tới nơi, trả lời không có đường ra |
| Thiếu luật SG inbound 80 | **Timeout** | SG bỏ gói SYN lặng lẽ |
| Nginx không chạy (route, SG đúng) | **Connection refused** | Kernel của EC2 trả RST vì không có process nghe port 80 |

Hai trường hợp đầu cùng là timeout → phải kiểm tra theo thứ tự gói tin (bài 03 mục 12), không đoán.

**5.** Thêm **Gateway VPC endpoint cho S3** (dịch vụ `com.amazonaws.ap-southeast-1.s3`, loại *Gateway*), chọn route table **`taskhub-private-rt`**. Endpoint thêm một route có đích là prefix list của S3 vào bảng đó. Chi phí: **0 USD** (theo trang giá VPC: không phí giờ, không phí xử lý dữ liệu). Kèm theo: instance profile/role của máy đó phải có quyền `s3:PutObject` trên bucket ([bài 05](../05-s3.md)).

**6.** Ví dụ rủi ro (chọn 3):

- **Gõ nhầm CIDR** hoặc chọn nhầm AZ — không có gì kiểm tra trước khi tạo (D1–D3 cho thấy AWS chỉ chặn một phần lỗi).
- **Quên một bước** (tag, gắn route table, bật DNS hostnames) — chỉ phát hiện nhờ `verify-vpc.sh`.
- **Không có lịch sử thay đổi**: không biết ai sửa route table lúc nào, vì sao (D5 có thể xảy ra ở production mà không có PR nào).
- **Không tái tạo được** chính xác ở Region/tài khoản khác hoặc cho môi trường prod.
- **Lệch cấu hình (drift)**: sửa tay trên console làm hạ tầng khác với tài liệu.

Terraform (Module 07) giải quyết bằng: kế hoạch hiển thị trước khi áp dụng (`terraform plan`), code review qua PR, tạo lại y hệt bằng `terraform apply`, phát hiện drift.
