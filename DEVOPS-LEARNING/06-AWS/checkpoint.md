# Checkpoint Giai đoạn 6 — AWS

> ⏱️ Tổng ~4,5 giờ (nên chia 2 buổi: A + B một buổi, C một buổi) · Làm vào cuối tuần 14
> Bao phủ: Module 06 — AWS, bài [00](00-aws-account-setup-cost-safety.md) → [11](11-putting-it-together.md)
> Lời giải: [solutions/checkpoint-solutions.md](solutions/checkpoint-solutions.md) — **chỉ mở sau khi đã nộp bài cho chính mình** (commit vào repo).

> 💰 **Chi phí:** Phần A — 0 USD. Phần B — B1 dùng IAM Policy Simulator (miễn phí); B2 chạy 1 `t3.micro` + 1 Public IPv4 tối đa ~2 giờ. Phần C — 1 `t3.micro` + 1 Public IPv4 trong 1–2 giờ. Tổng thường **dưới 0,20 USD** nếu dọn dẹp đúng hạn (Public IPv4: 0,005 USD/giờ; giá `t3.micro` xem [trang giá EC2](https://aws.amazon.com/ec2/pricing/on-demand/)). ⚠️ Rủi ro duy nhất là **quên xóa** — mỗi phần có bước dọn dẹp bắt buộc và được tính điểm.

## Mục lục

- [Quy tắc](#quy-tắc)
- [Phần A — Lý thuyết (45 phút)](#phần-a--lý-thuyết-45-phút)
- [Phần B — Thực hành (120 phút)](#phần-b--thực-hành-120-phút)
- [Phần C — Break-fix (90 phút)](#phần-c--break-fix-90-phút)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [Nếu chưa đạt](#nếu-chưa-đạt)

---

## Quy tắc

1. **Không dùng AI và không xem lời giải** trong lúc làm.
2. **Được phép:** tài liệu AWS chính thức (docs.aws.amazon.com, `aws <lệnh> help`), các bài trong Module 02, 05 và 06, ghi chú của chính bạn.
3. Tự bấm giờ cho từng phần. Hết giờ thì dừng, ghi lại mình đang ở đâu — rồi **vẫn dọn dẹp** trước khi nghỉ.
4. Mọi lệnh AWS chạy bằng user admin qua `aws login` (profile `taskhub`), **không** dùng root, **không** tạo access key.
5. Nộp bài: tạo thư mục `~/devops-journey/week14/checkpoint/` gồm `part-a.md`, `part-b/` (file policy, user data, toàn bộ lệnh đã chạy và kết quả kiểm thử), `part-c.md` (nhật ký debug). Commit **trước** khi mở lời giải.

---

## Phần A — Lý thuyết (45 phút)

Trả lời bằng lời của bạn, 3–8 câu mỗi câu. Mục tiêu là giải thích **bản chất** và **vì sao**, không chép định nghĩa. Vẽ sơ đồ bằng chữ nếu giúp bạn giải thích.

### IAM và tài khoản

1. User `phuong-admin` có policy `AdministratorAccess` và thêm một policy có `"Effect": "Deny", "Action": "s3:DeleteBucket", "Resource": "*"`. Anh ấy xóa bucket được không? Mô tả **thứ tự đánh giá** của IAM (explicit deny, allow, implicit deny) và dùng nó để giải thích. Nếu bỏ cả hai policy thì sao?
2. Vì sao ứng dụng trên EC2 nên lấy quyền qua **instance profile (IAM role)** thay vì đặt access key vào file `.env`? Thông tin xác thực đến tay ứng dụng bằng đường nào, sống bao lâu? IMDSv2 chống được kiểu tấn công nào mà IMDSv1 không chống được?
3. GitHub Actions deploy lên AWS bằng **OIDC** khác gì với lưu access key trong GitHub Secrets? Điều kiện `sub` = `repo:<user>/taskhub:environment:production` trong trust policy chặn được tình huống cụ thể nào? Nếu bỏ điều kiện `sub`, chuyện gì có thể xảy ra?
4. Tài khoản của bạn dùng **Free plan**. Điều gì xảy ra khi hết credit hoặc hết 6 tháng? Vì sao bài 00 cảnh báo không bật AWS Organizations/IAM Identity Center dạng organization trong tài khoản này? Trước ngày hết hạn, bạn phải làm gì với dự án taskhub?

### Mạng

5. Security group và network ACL khác nhau thế nào (stateful/stateless, allow/deny, gắn vào đâu, thứ tự xét luật)? Dùng ví dụ cụ thể: vì sao web server sau một NACL tự tạo cần luật **outbound** cho dải cổng 1024-65535, còn security group thì không cần luật outbound nào cho gói trả lời?
6. Điều gì làm một subnet là **public**? Một EC2 trong subnet public nhưng **không có** public IPv4 thì truy cập từ Internet được không, vì sao? Một EC2 trong subnet private (không có NAT Gateway) chạy `apt-get update` được không? taskhub chọn kiến trúc không NAT Gateway — đánh đổi là gì?
7. Mô tả **đường đi đầy đủ** của một request `http://<public-ip>/api/tasks` từ trình duyệt tới container `taskhub` trên EC2 v2 và chiều về: Internet Gateway (làm gì với địa chỉ IP?), route table, NACL, security group, network interface, Docker publish port, nginx, mạng Docker nội bộ, Spring Boot. Đánh dấu chỗ nào **cấu hình sai sẽ cho timeout**, chỗ nào **cho connection refused**, chỗ nào **cho 502**.

### EC2, lưu trữ, chi phí

8. So sánh **reboot**, **stop**, **terminate** của một EC2 gốc EBS: cái gì còn tính tiền (giờ chạy instance, ổ EBS, Public IPv4), public IPv4 có đổi không, dữ liệu trên ổ gốc còn không? Ứng dụng của bạn đọc IP từ đâu nếu IP đổi sau stop/start?
9. Kể **5 bẫy chi phí** phổ biến với người mới học AWS (ít nhất 3 bẫy liên quan đến tài nguyên "quên xóa") và với mỗi bẫy: cách **phát hiện** (công cụ/trang nào) và cách **phòng tránh**.
10. S3 bucket backup của taskhub: Block Public Access, bucket policy, IAM policy, versioning và lifecycle lần lượt bảo vệ khỏi rủi ro gì? Versioning có thay thế được backup sang nơi khác không? Lifecycle policy giúp gì cho chi phí?

### Dịch vụ quản lý, mở rộng, giám sát

11. So sánh **RDS PostgreSQL** với **PostgreSQL trong container trên EC2** (như taskhub v2) theo: backup/khôi phục theo thời điểm, Multi-AZ, vá lỗi, chi phí, quyền kiểm soát. Khi nào bạn khuyên team chuyển sang RDS?
12. Trong kiến trúc **ALB + Auto Scaling group** ở lab tuần 14: target group health check gọi `/actuator/health` và nhận `503` liên tục thì ALB và ASG lần lượt làm gì? Vì sao **không** được chạy PostgreSQL bên trong các instance của ASG?
13. CloudWatch: metric, log và alarm khác nhau thế nào? Vì sao metric mặc định của EC2 **không có** RAM và dung lượng đĩa? Alarm `StatusCheckFailed` và một smoke test gọi `/actuator/health` phát hiện được những loại sự cố khác nhau nào?
14. Bạn trỏ `taskhub.example.com` (Route 53, bản ghi A, TTL 3600) vào public IP của EC2. Sau một lần stop/start, người dùng báo lỗi suốt gần một tiếng dù bạn đã sửa bản ghi ngay. Giải thích vì sao, và nêu 2 cách để lần sau không bị như vậy (kèm chi phí/đánh đổi của từng cách).

---

## Phần B — Thực hành (120 phút)

Hai nhiệm vụ **mới** — không có trong lab nào. Làm bằng **AWS CLI** (Console chỉ dùng để **xem** và để mở Session Manager / Policy Simulator).

### B1 — Policy quyền tối thiểu cho tác vụ backup (30 phút, 0 USD)

Ở v5, một script trên EC2 sẽ đẩy file `pg_dump` lên bucket `taskhub-backups-<account-id>`. Viết file `part-b/taskhub-backup-writer.json` — một **identity-based policy** cho phép **đúng và chỉ**:

- Tải file lên (upload) vào **prefix** `backups/` của bucket đó.
- Liệt kê nội dung bucket, nhưng **chỉ** trong prefix `backups/`.
- Không gì khác: không xóa, không tải về, không đụng bucket nào khác.

Kiểm tra bằng **IAM Policy Simulator** (`[AWS Console]` — dán policy vào phần mô phỏng, **không** cần tạo policy thật hay gắn vào ai). Ghi bảng kết quả 6 ca sau vào `part-b.md` (cột "Mong đợi" do bạn tự điền **trước** khi chạy):

| # | Action | Resource | Context key | Mong đợi | Kết quả |
|---|---|---|---|---|---|
| 1 | `s3:PutObject` | `arn:aws:s3:::taskhub-backups-<id>/backups/2027-01-20.sql.gz` | — | | |
| 2 | `s3:PutObject` | `arn:aws:s3:::taskhub-backups-<id>/other/x.txt` | — | | |
| 3 | `s3:DeleteObject` | `arn:aws:s3:::taskhub-backups-<id>/backups/2027-01-20.sql.gz` | — | | |
| 4 | `s3:ListBucket` | `arn:aws:s3:::taskhub-backups-<id>` | `s3:prefix` = `backups/` | | |
| 5 | `s3:ListBucket` | `arn:aws:s3:::taskhub-backups-<id>` | `s3:prefix` để trống | | |
| 6 | `s3:PutObject` | `arn:aws:s3:::bucket-khac/backups/x` | — | | |

Trả lời thêm trong `part-b.md`: vì sao `s3:ListBucket` và `s3:PutObject` cần **hai `Resource` khác nhau**? Vì sao ca 2 và ca 3 bị từ chối dù policy không có câu `Deny` nào?

### B2 — Dựng "trang trạng thái" hoàn toàn bằng CLI (90 phút, có chi phí)

> ⚠️ Mọi lệnh tạo tài nguyên trong phần này **tính phí** (mục chi phí ở đầu trang). Bắt đầu bấm giờ khi chạy lệnh tạo đầu tiên.

Dựng một EC2 nhỏ hiển thị thông tin của chính nó, **chỉ bằng AWS CLI**, đáp ứng **tất cả** yêu cầu:

| # | Yêu cầu |
|---|---|
| R1 | IAM role **mới** `ck06b-ssm-only` (trust: `ec2.amazonaws.com`) chỉ có `AmazonSSMManagedInstanceCore`, cùng instance profile tên `ck06b-ssm-only`. Không dùng lại `taskhub-ec2-role` — vì sao? (trả lời trong `part-b.md`) |
| R2 | Security group **mới** `ck06b-status-sg` trong VPC taskhub: inbound **chỉ** TCP 80 từ **IP công khai hiện tại của bạn** (`/32`). Không có cổng 22 |
| R3 | Một `t3.micro` trong subnet `taskhub-public-b`, AMI Ubuntu 24.04 lấy qua `resolve:ssm:` (không chép cứng AMI ID), **IMDSv2 bắt buộc** |
| R4 | Tag `Name=ck06b-status`, `Project=taskhub`, `Env=lab`, `Owner=<tên>`, `ManagedBy=manual` trên **cả instance lẫn ổ EBS**, gắn ngay trong lệnh tạo |
| R5 | User data (file `part-b/user-data.sh`): cài nginx; trang chủ hiển thị **instance ID** và **Availability Zone**, lấy từ instance metadata bằng **IMDSv2** (có bước lấy token) |
| R6 | **Chốt chặn chi phí:** máy **tự terminate** sau 90 phút kể cả khi bạn quên (gợi ý: hành vi khi hệ điều hành tắt máy + lệnh hẹn giờ tắt máy trong user data) |
| R7 | Dọn dẹp **bằng CLI** khi xong: instance, security group, instance profile, role — kèm lệnh chứng minh không còn gì |

**Kiểm thử bắt buộc** (ghi lệnh và kết quả vào `part-b.md`):

| # | Kiểm thử | Kết quả mong đợi |
|---|---|---|
| 1 | `curl -s http://<public-ip>/` từ laptop | Thấy instance ID và AZ, **trùng** với `aws ec2 describe-instances` |
| 2 | `aws ec2 describe-security-groups` cho `ck06b-status-sg` | Đúng một rule inbound: TCP 80 từ `<ip-của-bạn>/32` |
| 3 | Session Manager vào máy, chạy `curl -s -o /dev/null -w '%{http_code}\n' http://169.254.169.254/latest/meta-data/instance-id` | `401` — IMDSv1 bị từ chối. Giải thích vì sao trang chủ vẫn lấy được instance ID |
| 4 | `aws ec2 describe-instances` + `aws ec2 describe-instance-attribute --attribute instanceInitiatedShutdownBehavior` | `HttpTokens` = `required`; hành vi tắt máy = `terminate` |
| 5 | `aws ec2 describe-volumes --filters Name=tag:Name,Values=ck06b-status` | Ổ EBS có đủ 5 tag |
| 6 | Sau dọn dẹp: các lệnh `describe`/`get` cho instance, security group, role, instance profile | Không còn tài nguyên nào (terminated / NotFound / NoSuchEntity) |

**Không đạt nếu:** dùng Console để tạo/sửa tài nguyên, mở cổng 22, có rule `0.0.0.0/0`, hoặc kết thúc phần B mà còn tài nguyên `ck06b-*`.

---

## Phần C — Break-fix (90 phút)

### Khởi tạo

`[WSL]`:

```bash
export AWS_PROFILE=taskhub
mkdir -p ~/devops-lab/06-aws/ck06 && cd ~/devops-lab/06-aws/ck06
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/06-AWS/labs/checkpoint/{ck06-stack.yaml,verify.sh} .
sed -i 's/\r$//' ck06-stack.yaml verify.sh
```

⚠️ Tạo tài nguyên tính phí:

```bash
aws cloudformation deploy --stack-name ck06 --template-file ck06-stack.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Project=taskhub Env=lab Lab=ck06 ManagedBy=cloudformation Owner=<tên-bạn>
aws cloudformation describe-stacks --stack-name ck06 --query "Stacks[0].Outputs" --output table
bash verify.sh            # kiểm tra tiến độ bất cứ lúc nào
```

### Bối cảnh

Hệ thống `reports` có một trang trạng thái `http://<PublicIp>/` (nội dung chứa `ck06-ok`). Tuần trước, một đồng nghiệp làm đợt **"siết bảo mật"**: chặn quét cổng bằng NACL, chỉ cho web nhận traffic "từ load balancer", khóa outbound "chỉ cho phép cập nhật gói", và cho nginx "chỉ nghe nội bộ". Load balancer **chưa từng được tạo**. Từ đó trang không vào được, team vận hành cũng không vào được máy.

### Các ticket

| Ticket | Mô tả | Kết quả mong đợi |
|---|---|---|
| 🎫 #6201 | Trang trạng thái timeout từ mọi nơi | Gói tin TCP 80 từ Internet tới được instance |
| 🎫 #6202 | (tiếp) Vẫn timeout dù security group "đã cho HTTP" | Như trên — có **hai** lớp chặn độc lập |
| 🎫 #6203 | Session Manager không thấy instance, dù role có đúng `AmazonSSMManagedInstanceCore` | Instance **Online** trong Fleet Manager |
| 🎫 #6204 | Mạng thông rồi nhưng `curl` báo `Connection refused` | `curl http://<PublicIp>/` trả trang chứa `ck06-ok` |

### Luật chơi

- **Không đọc** `ck06-stack.yaml` và `verify.sh` trước khi nộp bài.
- Sửa **tài nguyên đang có**: không tạo VPC/subnet/route table/security group/NACL/role mới, không mở cổng 22, không Elastic IP, không stop/terminate instance (reboot được).
- **Giữ ý định bảo mật hợp lý** của đồng nghiệp ở mức có thể: ví dụ không xóa sạch NACL thành "allow all", không mở security group "All traffic". Mỗi thay đổi phải giải thích được: vì sao **đủ**, vì sao **không thừa**.
- Ghi nhật ký debug cho **từng ticket** theo mẫu ở [Break-fix AWS #1](labs/break-fix-01/README.md#8-sản-phẩm-phải-nộp) vào `part-c.md`.

### Dọn dẹp (bắt buộc, được tính điểm)

```bash
# Gỡ mọi policy bạn đã gắn tay vào ck06-ec2-role (nếu có), rồi:
aws cloudformation delete-stack --stack-name ck06        # ⚠️ xóa toàn bộ tài nguyên của phần C
aws cloudformation wait stack-delete-complete --stack-name ck06 && echo "deleted"
aws ec2 describe-vpcs --filters Name=cidr,Values=10.98.0.0/16 --query "Vpcs[].VpcId" --output text   # phải rỗng
```

Gặp `DELETE_FAILED`: xử lý như [mục 10 của Break-fix AWS #1](labs/break-fix-01/README.md#10-dọn-dẹp).

---

## Tiêu chí đạt

| Phần | Đạt khi | Trọng số |
|---|---|---|
| A | ≥ 11/14 câu đúng **bản chất** (tự chấm theo lời giải, trung thực). Câu **1, 5 và 8 bắt buộc đúng** | 30% |
| B | B1: policy cho đúng 6/6 ca và trả lời được 2 câu hỏi. B2: đạt R1–R7 và 6/6 kiểm thử trong 120 phút (cả B1 + B2), **kể cả dọn dẹp** | 35% |
| C | `bash verify.sh` đạt **4/4** trong 90 phút, mọi `WARN` được giải thích trong nhật ký, nhật ký nêu **cách tìm ra** từng lỗi (lệnh nào, thấy gì), và stack đã xóa sạch | 35% |

**Đạt Checkpoint** khi đạt cả 3 phần → tick vào checklist [Module 06](README.md) và cập nhật [ma trận kỹ năng](../00-ROADMAP/skill-matrix.md).

Ngày hôm sau: mở **Billing and Cost Management**, ghi chi phí thực tế của buổi checkpoint vào `part-c.md` và so với ước tính ở đầu trang.

---

## Nếu chưa đạt

Không chuyển sang Module 07 ngay (xem [quy tắc khi chậm tiến độ](../00-ROADMAP/weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ) — AWS VPC/EC2/IAM thuộc nhóm **không bao giờ cắt**):

| Sai ở | Ôn lại |
|---|---|
| Câu A1, A2, B1, R1 | [Bài 02 — IAM](02-iam.md) |
| Câu A3 | [Bài 02 — IAM](02-iam.md), [Module 05 bài 04](../05-CICD/04-secrets-environments.md) |
| Câu A4, A9 | [Bài 00 — Tài khoản, chi phí](00-aws-account-setup-cost-safety.md), [bài 01](01-cloud-fundamentals.md) |
| Câu A5, A6, A7, ticket #6201, #6202 | [Bài 03 — VPC](03-vpc-networking.md), [Network bài 04](../02-NETWORKING/04-routing-nat-switching.md), [Network bài 05](../02-NETWORKING/05-tcp-udp-ports-firewall.md) |
| Câu A8, R2–R6, ticket #6204 | [Bài 04 — EC2](04-ec2.md) |
| Câu A10 | [Bài 05 — S3](05-s3.md) |
| Phần B làm chậm vì không quen CLI, R7 | [Bài 06 — AWS CLI](06-aws-cli.md) |
| Câu A11 | [Bài 07 — RDS](07-rds.md) |
| Câu A12 | [Bài 08 — ELB, Auto Scaling](08-elb-autoscaling.md) |
| Câu A13, ticket #6203 | [Bài 10 — CloudWatch](10-cloudwatch.md), [Bài 04 — EC2](04-ec2.md) (Session Manager) |
| Câu A14 | [Bài 09 — Route 53](09-route53.md) |
| Không biết bắt đầu Phần C từ đâu | Làm lại [Break-fix AWS #1](labs/break-fix-01/README.md), rồi [bài 11](11-putting-it-together.md) |

Ôn xong 2–3 ngày rồi làm lại phần chưa đạt. Phần C: xóa stack `ck06` (nếu còn) rồi deploy lại — lỗi được cài lại y hệt.
