# Lời giải — Bài 01: Cloud fundamentals

> Chỉ đọc sau khi đã tự làm. Quay lại bài: [01-cloud-fundamentals.md](../01-cloud-fundamentals.md)

## Câu hỏi trong bài thực hành (mục 9)

**Bước 1 — AZ ID của `ap-southeast-1a` có giống bảng minh họa không?** Không cần giống: AWS ánh xạ ngẫu nhiên tên AZ sang AZ vật lý cho từng tài khoản. AZ ID mới là định danh vật lý cố định.

**Bước 2 — Phạm vi dịch vụ:** IAM — Global (danh tính dùng cho cả tài khoản, mọi region). EC2 — Region (máy nằm trong data center cụ thể). S3 — console hiện *Global* vì **tên bucket** duy nhất toàn cầu và danh sách bucket xem chung, nhưng **mỗi bucket nằm ở một region**. Route 53 — Global (DNS phục vụ toàn cầu qua edge). VPC — Region (mạng gắn với hạ tầng của một region; subnet gắn với AZ).

**Bước 3 — Vì sao region Singapore ít sự kiện hơn?** Sự kiện của dịch vụ global (IAM, đăng nhập root) thường được ghi ở `us-east-1`. Ở Singapore chỉ có sự kiện của dịch vụ theo region mà bạn đã chạm vào (ví dụ mở console EC2 có thể sinh vài sự kiện đọc).

**Bước 4 — Kịch bản 100 giờ, phần nào vẫn tính đủ 730 giờ?** Ổ EBS gp3 (tính theo GB-tháng, tồn tại cả khi máy tắt). Public IPv4 **tự gán** bị thu hồi khi stop nên chỉ tính khi máy chạy; nếu dùng Elastic IP thì tính đủ tháng.

**Bước 5 — Shared Responsibility (ví dụ 10 dòng):**

| Việc | EC2 + Compose (v2) | Nếu DB chuyển sang RDS |
|---|---|---|
| Thay ổ cứng/server vật lý hỏng | AWS | AWS |
| An ninh vật lý data center | AWS | AWS |
| Vá Ubuntu | Bạn | Bạn (máy app vẫn là EC2) |
| Vá PostgreSQL | Bạn (đổi image `postgres:17.x`) | **AWS** (theo cửa sổ bảo trì) |
| Backup database | Bạn (`pg_dump`, v5) | **AWS** tự động, bạn chọn số ngày giữ |
| Đổi mật khẩu PostgreSQL | Bạn | Bạn |
| Chặn port 5432 khỏi Internet | Bạn (không publish port; SG) | Bạn (SG của RDS, đặt trong private subnet) |
| Cập nhật image Java/app | Bạn | Bạn |
| Mã hóa ổ đĩa | Bạn bật (EBS encrypted) | Bạn bật (RDS encryption) |
| Ai đọc được dữ liệu | Bạn | Bạn |

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** On-demand self-service (tự tạo EC2), broad network access (console/CLI qua Internet), resource pooling (EC2 chạy chung phần cứng, cô lập bằng hypervisor), rapid elasticity (Auto Scaling), measured service (tính tiền theo giờ, GB).

**2.** Khác ở **ranh giới quản lý**: IaaS bạn lo từ OS trở lên; PaaS nhà cung cấp lo cả OS và runtime, bạn lo app/dữ liệu/cấu hình; SaaS bạn chỉ dùng phần mềm. EC2 = IaaS, RDS = PaaS, GitHub = SaaS.

**3.** Region là khu vực địa lý; AZ là một hoặc nhiều data center tách biệt (điện, mạng, kết nối dự phòng riêng) trong region. Các AZ cách nhau đủ xa để sự cố cục bộ không lan sang, nhưng trong phạm vi 100 km để độ trễ giữa chúng thấp (đồng bộ dữ liệu, ví dụ RDS Multi-AZ, cần độ trễ thấp).

**4.** AWS ánh xạ ngẫu nhiên tên AZ cho từng tài khoản để tài nguyên của mọi người không dồn vào AZ "a". So sánh chính xác bằng **AZ ID** (ví dụ `apse1-az1`).

**5.** AZ: subnet, EBS volume, EC2 instance. Region: VPC, security group, RDS instance, CloudWatch log group. Global: IAM, Route 53, CloudFront.

**6.** *Of*: AWS bảo vệ data center, server, mạng vật lý, hypervisor nơi EC2 `taskhub-app` chạy. *In*: bạn vá Ubuntu, cấu hình `taskhub-web-sg` chỉ mở 80, giữ mật khẩu PostgreSQL trong Parameter Store, cấp `taskhub-ec2-role` quyền tối thiểu, bật mã hóa EBS.

**7.** Chuyển sang AWS: vá OS và phần mềm database, backup tự động, thay thế máy database hỏng, (nếu bật) failover Multi-AZ. Vẫn là của bạn: security group/vị trí mạng của RDS, mật khẩu và user database, bật mã hóa, chọn số ngày giữ backup, **dữ liệu** và ai được truy cập, schema/migration.

**8.** (1) Làm được trên console thì tự động hóa được (CLI/Terraform gọi cùng API). (2) Quyền IAM đặt theo tên API (`ec2:RunInstances`), nên đọc được policy khi biết API. (3) Mọi thao tác quản lý để lại dấu vết trong CloudTrail — điều tra được "ai làm gì". (Thêm: lỗi `AccessDenied` nêu đúng tên action thiếu.)

**9.** 90 ngày, management event (tạo/sửa/xóa, đăng nhập), theo từng region, miễn phí.

**10.** On-Demand: trả theo mức dùng, không cam kết. Savings Plans/RI: cam kết 1–3 năm để giảm giá. Spot: dùng dung lượng dư, rất rẻ, có thể bị thu hồi. Savings Plans/RI **không** có trên Free plan.

**11.** Operational excellence, Security, Reliability, Performance efficiency, Cost optimization, Sustainability. Yếu nhất: **Reliability** (1 EC2, 1 AZ, database cùng máy). Chấp nhận được vì là dự án học tập với ngân sách credit; bù lại bằng backup (v5) và khả năng dựng lại nhanh bằng Terraform (v4); và bạn **nói rõ** đánh đổi này.

**12.** HA cần **bản sao đang chạy** ở nhiều AZ **và** cơ chế chuyển traffic khi một bản sao chết (load balancer + health check). Subnet ở 2 AZ chỉ là "chỗ trống để đặt máy"; 1 máy duy nhất vẫn là single point of failure.

**13.** `ufw` → security group (và NACL); router + NAT → route table + Internet Gateway + NAT Gateway; `journalctl` → CloudWatch Logs; thư mục backup → S3; SSH → SSM Session Manager.

---

## Bài tập tự làm (mục 14)

### Bài 1 — Chọn region

Bốn tiêu chí thường dùng: (1) **Tuân thủ/pháp lý** — dữ liệu phải ở đâu; (2) **Độ trễ** tới người dùng; (3) **Dịch vụ có sẵn** ở region đó; (4) **Giá** (cùng dịch vụ, mỗi region giá khác nhau). Áp dụng: N. Virginia bị loại vì yêu cầu lưu dữ liệu ở châu Á; giữa Singapore và Tokyo, Singapore thường gần Việt Nam hơn về độ trễ — kiểm chứng bằng đo thực tế, không đoán. Tiêu chí **không** kiểm tra được chỉ bằng tài liệu kỹ thuật: yêu cầu pháp lý cụ thể (cần bộ phận pháp chế/luật sư đọc quy định), và độ trễ thật từ mạng của khách hàng (cần đo).

### Bài 2 — Ma trận trách nhiệm 3 phương án

Điểm chính phải có:

- (a) EC2 + Compose: bạn lo gần hết từ OS trở lên (vá OS, Docker, PostgreSQL, backup, giám sát, thay máy khi hỏng).
- (b) EC2 + RDS: database chuyển phần vá, backup tự động, failover (nếu Multi-AZ) sang AWS; app vẫn như (a).
- (c) ECS Fargate (theo trang giới thiệu của AWS, bạn không quản lý server/cluster EC2 cho container): AWS lo OS và hạ tầng chạy container; bạn lo image (bao gồm lỗ hổng trong image), cấu hình task, IAM role, mạng, dữ liệu.
- Dòng **không bao giờ đổi chủ**: dữ liệu, IAM, cấu hình security group, mã hóa (bật hay không), secret.

### Bài 3 — Sống sót khi `ap-southeast-1a` sập

Cần thêm: app chạy ≥ 2 bản (ví dụ Auto Scaling group trải public-a và public-b, hoặc app trong private subnet + NAT Gateway mỗi AZ), **ALB** phía trước với health check, database tách khỏi máy app và có bản dự phòng ở AZ khác (**RDS Multi-AZ**), dữ liệu tĩnh/backup ở S3 (đã là dịch vụ cấp region). Chi phí tăng: thêm ít nhất một máy, ALB (theo giờ), RDS Multi-AZ (khoảng gấp đôi một instance RDS), có thể NAT Gateway — dùng calculator để ra số. Ba câu "vì sao không làm": dự án học tập không có người dùng thật cần cam kết uptime; chi phí sẽ vượt ngân sách credit nhiều lần; mục tiêu học HA được đáp ứng bằng lab ngắn tuần 14 rồi xóa.

### Bài 4 — Console sang API

| Thao tác | `eventName` | Lệnh CLI |
|---|---|---|
| Tạo group | `CreateGroup` | `aws iam create-group` |
| Tạo user | `CreateUser` (+ `CreateLoginProfile` cho mật khẩu console) | `aws iam create-user`, `aws iam create-login-profile` |
| Gắn policy vào group | `AttachGroupPolicy` | `aws iam attach-group-policy` |
| Thêm user vào group | `AddUserToGroup` | `aws iam add-user-to-group` |
| Bật MFA | `CreateVirtualMFADevice` + `EnableMFADevice` (với passkey có thể khác — đọc đúng `eventName` trong CloudTrail của bạn) | `aws iam enable-mfa-device` |

Vì sao quyền đặt theo API: IAM kiểm tra **mỗi lời gọi API** — câu hỏi duy nhất IAM trả lời là "danh tính X có được gọi action Y trên tài nguyên Z không?". Console chỉ là một client gọi API, nên quyền phải gắn với API chứ không gắn với nút bấm.

### Bài 5 — Well-Architected mini

| Trụ cột | Rủi ro của v2 | Cải tiến ở |
|---|---|---|
| Operational excellence | Deploy bằng tay, dễ sai bước | v3 (CD qua SSM), v1.0 (runbook) |
| Security | Đồng bộ file cấu hình lên EC2 bằng tay, dễ lệch; chưa rà soát tổng thể | v4 (Ansible), Module 10 / v1.0 |
| Reliability | 1 EC2, 1 AZ, DB cùng máy, chưa có backup tự động | v5 (backup + diễn tập restore), v4 (dựng lại nhanh bằng Terraform) |
| Performance efficiency | Không có số liệu để biết `t3.small` đủ hay thừa | v3 (CloudWatch), v5 (Prometheus/Grafana) |
| Cost optimization | Quên tắt máy → tiêu credit | v4 (`terraform destroy`), thói quen dọn dẹp hằng tuần |
| Sustainability | Chạy 24/7 khi không ai dùng | v4 (tắt/xóa khi không học) |
