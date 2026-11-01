# Module 06 — AWS Cloud

> Tuần 11–14 · ~68 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 01 — Linux](../01-LINUX/README.md), [Module 02 — Networking](../02-NETWORKING/README.md), [Module 04 — Docker](../04-DOCKER/README.md), [Module 05 — CI/CD](../05-CICD/README.md), dự án [taskhub v1](../12-PRACTICAL-PROJECT/milestones/v1-ci.md) đã xong

## Mục lục

- [1. Vì sao DevOps phải biết AWS?](#1-vì-sao-devops-phải-biết-aws)
- [2. Junior cần biết AWS đến mức nào?](#2-junior-cần-biết-aws-đến-mức-nào)
- [3. An toàn chi phí — đọc trước khi làm bất cứ gì](#3-an-toàn-chi-phí--đọc-trước-khi-làm-bất-cứ-gì)
- [4. Chuẩn bị trước khi học](#4-chuẩn-bị-trước-khi-học)
- [5. Thứ tự bài học](#5-thứ-tự-bài-học)
- [6. Lab, break-fix, checkpoint và dự án](#6-lab-break-fix-checkpoint-và-dự-án)
- [7. Quy ước dùng chung trong module](#7-quy-ước-dùng-chung-trong-module)
- [8. AWS trong các module sau](#8-aws-trong-các-module-sau)
- [9. Checklist hoàn thành module](#9-checklist-hoàn-thành-module)
- [10. Nguồn học](#10-nguồn-học)

---

## 1. Vì sao DevOps phải biết AWS?

Đến hết tuần 10, `taskhub` đã có image được build, test, quét lỗ hổng và đẩy lên GHCR tự động. Nhưng nó vẫn **chỉ chạy trên laptop của bạn**. Module này đưa nó lên một server thật trên Internet — và học cách làm điều đó **an toàn**, **rẻ**, và **giải thích được**.

| Bạn sẽ làm ở công việc thật | Cần kiến thức của module này |
|---|---|
| "Tạo môi trường staging cho service mới" | VPC, subnet, security group, EC2 (bài 03, 04) |
| "Ứng dụng không kết nối được database trên AWS" | Route table, security group, NACL — gỡ lỗi theo tầng (bài 03, [break-fix](labs/break-fix-01/README.md)) |
| "Đừng để access key trong pipeline" | IAM role, OIDC (bài 02, [dự án v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md)) |
| "Server không SSH được nữa, vào xem giúp" | SSM Session Manager, không cần mở port 22 (bài 04) |
| "Hóa đơn tháng này tăng vọt" | Billing, Budgets, những thứ âm thầm tốn tiền (bài 00) |
| "Dựng database có backup tự động" | RDS (bài 07) |
| "Website phải chịu được một AZ sập" | ALB, Auto Scaling, đa AZ (bài 08, 11) |
| "Khi server chết thì ai biết?" | CloudWatch metrics, alarm, logs (bài 10) |
| Phỏng vấn: "Vẽ kiến trúc dự án của bạn trên AWS và giải thích luồng request" | Toàn module + [bài 11](11-putting-it-together.md) |

> **AWS không phải một kỹ năng mới hoàn toàn.** VPC là mạng (Module 02), EC2 là máy Linux (Module 01), IAM là phân quyền (Linux bài 03), container vẫn là container (Module 04). Bài [01](01-cloud-fundamentals.md) có bảng ánh xạ đầy đủ. Học module này nhanh hay chậm phụ thuộc gần như hoàn toàn vào nền tảng của bạn ở 10 tuần trước.

---

## 2. Junior cần biết AWS đến mức nào?

| Chủ đề | Mức cần cho Junior | Có thể học sau |
|---|---|---|
| Tài khoản, root, MFA, Billing, Budgets | 🟥 Tự thiết lập an toàn; kể được những thứ âm thầm tốn tiền | AWS Organizations, nhiều tài khoản |
| Region, AZ, Shared Responsibility | 🟥 Giải thích bằng ví dụ của chính dự án | — |
| IAM: user, group, role, policy | 🟥 **Đọc và viết** policy JSON đơn giản; dùng role thay access key | Permission boundary, SCP, ABAC |
| VPC, subnet, route table, IGW, SG, NACL | 🟥 **Tự tạo bằng tay** theo bảng IP của mình; giải thích luồng gói tin vào/ra | Transit Gateway, VPN, PrivateLink |
| NAT Gateway | 🟨 Hiểu vì sao cần và vì sao đắt; dựng trong lab ngắn | — |
| EC2: AMI, instance type, EBS, user data, IMDSv2 | 🟥 Triển khai `taskhub` bằng Docker Compose trên EC2 | Spot, placement group |
| SSM Session Manager | 🟥 Vào server không cần SSH key, không mở port 22 | SSM Automation |
| S3 | 🟥 Bucket private, versioning, lifecycle, Block Public Access | Replication, Object Lock |
| AWS CLI | 🟥 `aws login`, profile, `--query`, đọc lỗi `AccessDenied` | Viết script phức tạp bằng SDK |
| RDS | 🟨 Dựng, kết nối, hiểu Multi-AZ và backup; so sánh với tự chạy | Aurora, read replica |
| ALB, target group, Auto Scaling | 🟨 Dựng trong lab ngắn, giải thích health check | Scaling policy nâng cao |
| Route 53 | 🟨 Hosted zone, bản ghi A/CNAME/alias | Routing policy phức tạp |
| CloudWatch | 🟥 Metrics, alarm qua email, log group có retention | Dashboard phức tạp, Logs Insights nâng cao |
| OIDC GitHub → AWS | 🟥 Pipeline deploy không có access key ([v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md)) | — |
| EKS, ECS, Lambda | 🟦 Biết là gì, khi nào dùng | Học khi công việc cần |

**Quy tắc vàng:** bạn phải **tự dựng lại được** toàn bộ hạ tầng của `taskhub` v2 từ tài khoản trống trong khoảng 3 giờ (đó cũng là [bài thi mốc 3 tháng](../00-ROADMAP/exam-month-3.md)), và khi có lỗi, **tự đi theo luồng gói tin** để tìm tầng hỏng — không bấm lung tung trên console cho đến khi "tự nhiên chạy".

---

## 3. An toàn chi phí — đọc trước khi làm bất cứ gì

> ⚠️ Module đầu tiên của giáo trình có thể tiêu credit. Đọc hết mục này trước bài 00.

Đây là module **đầu tiên** của giáo trình có thể tiêu tiền (credit). Toàn bộ chiến lược đã được thống nhất ở [Lộ trình §7](../00-ROADMAP/learning-roadmap.md#7-chiến-lược-kiểm-soát-chi-phí-aws). Tóm tắt:

| Nguyên tắc | Chi tiết |
|---|---|
| **Free plan**, tạo tài khoản ở tuần 11 | 100 USD credit + tối đa 100 USD nữa khi hoàn thành hoạt động gợi ý. Gói kết thúc sau **6 tháng hoặc khi hết credit** → tài khoản **tự đóng**, AWS giữ dữ liệu 90 ngày ([bài 00](00-aws-account-setup-cost-safety.md)) |
| Lưới an toàn ngay buổi đầu | Root có MFA, không access key · `phuong-admin` có MFA · Free Tier alerts · Budget `taskhub-monthly` (Unblended, 15 USD/tháng) |
| **Không NAT Gateway** trong dự án chính | Tính theo giờ + theo GB. Chỉ dựng trong [lab ngắn tuần 14](labs/lab-03-alb-asg-rds-short.md) rồi xóa ngay |
| **1 Public IPv4** | 0,005 USD/giờ mỗi địa chỉ, kể cả khi không dùng. Không giữ Elastic IP thừa |
| **1 EC2 `t3.small`** | Đủ cho Spring Boot + PostgreSQL + nginx; **tắt khi không học** |
| RDS, ALB, Auto Scaling | Chỉ trong lab ngắn **một buổi**, có checklist xóa và lệnh kiểm tra |
| Mỗi lab AWS | Mở đầu bằng **ước tính chi phí**, kết thúc bằng **dọn dẹp + lệnh CLI xác nhận không còn gì sót** |
| Lệnh nguy hiểm | Mọi lệnh **tạo** tài nguyên tính phí và mọi lệnh **xóa** đều đánh dấu ⚠️ |
| Thói quen hằng tuần | 15 phút: Billing Home → Cost Explorer → AWS Global View → Tag Editor ([bài 00 §4.9](00-aws-account-setup-cost-safety.md#49--thói-quen-dọn-dẹp-hằng-tuần-15-phút-mỗi-chủ-nhật)) |
| Ai chạy lệnh AWS | **Chỉ bạn.** Giáo trình hướng dẫn; trợ lý AI không bao giờ chạy lệnh tạo tài nguyên AWS thay bạn |

> 💡 **Ngân sách tham chiếu:** 100 USD / 6 tháng ≈ 16 USD/tháng. Một EC2 chạy 24/7 kèm ổ đĩa và Public IPv4 tiêu một phần đáng kể con số đó. Bài [01](01-cloud-fundamentals.md) có bài tập ước tính bằng AWS Pricing Calculator — làm **trước** khi tạo máy đầu tiên.

---

## 4. Chuẩn bị trước khi học

| Cần có | Kiểm tra | Nếu chưa có |
|---|---|---|
| `docs/network-plan.md` của `taskhub`: VPC CIDR + 4 subnet không chồng lấn | Tính lại được số địa chỉ dùng được của mỗi subnet | [v-pre tuần 4](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md), [Networking 02](../02-NETWORKING/02-ipv4-subnet-cidr.md) |
| Image `ghcr.io/<github-user>/taskhub:<tag>` **public** trên GHCR | Pull được khi chưa đăng nhập: `docker logout ghcr.io && docker pull ghcr.io/<user>/taskhub:v0.3.0` | [Docker 06](../04-DOCKER/06-registry.md), [dự án v1](../12-PRACTICAL-PROJECT/milestones/v1-ci.md) |
| Compose v0 chạy được trên laptop | `docker compose up -d` → `curl localhost:8000/actuator/health` → `UP` | [Dự án v0](../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md) |
| Environment `production` có required reviewer trên GitHub | `[GitHub]` Settings → Environments | [CI/CD bài 04](../05-CICD/04-secrets-environments.md) |
| Đọc được luồng gói tin qua route table, NAT, firewall | Giải thích được vì sao máy trong mạng riêng ra Internet được nhưng Internet không vào được | [Networking 04](../02-NETWORKING/04-routing-nat-switching.md), [Networking 05](../02-NETWORKING/05-tcp-udp-ports-firewall.md) |
| Thẻ thanh toán quốc tế, điện thoại có ứng dụng xác thực/passkey | — | Cần cho [bài 00](00-aws-account-setup-cost-safety.md) |

Thư mục làm việc cho bài tập ngoài repo:

```bash
mkdir -p ~/devops-lab/06-aws && cd ~/devops-lab/06-aws
```

**Nhãn môi trường dùng trong module:**

| Nhãn | Nghĩa |
|---|---|
| `[WSL]` | Terminal Ubuntu trên laptop (AWS CLI cài ở đây — [bài 06](06-aws-cli.md)) |
| `[PowerShell]` | Terminal Windows (hiếm khi cần) |
| `[AWS Console]` | Giao diện web console.aws.amazon.com |
| `[EC2]` | Lệnh chạy **bên trong** máy EC2 (qua SSM Session Manager) |
| `[GitHub]` | Giao diện web github.com |
| `[Runner]` | Lệnh chạy bên trong workflow GitHub Actions |

---

## 5. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 00 | [Tạo tài khoản AWS an toàn và kiểm soát chi phí](00-aws-account-setup-cost-safety.md) — **làm trước mọi thứ** | 11 | 3h | 🟥 |
| 01 | [Cloud fundamentals](01-cloud-fundamentals.md) — Region, AZ, Shared Responsibility, mô hình giá | 11 | 3h | 🟥 |
| 02 | [IAM](02-iam.md) — user, group, role, policy, quyền tối thiểu | 11 | 4h | 🟥 |
| 06 | [AWS CLI](06-aws-cli.md) — `aws login`, profile, `--query`, đọc lỗi | 11 | 2h | 🟥 |
| 03 | [VPC networking](03-vpc-networking.md) — subnet, route table, IGW, NAT, SG, NACL | 11 | 5h | 🟥 |
| 04 | [EC2](04-ec2.md) — AMI, instance type, EBS, user data, IMDSv2, SSM | 12 | 5h | 🟥 |
| 05 | [S3](05-s3.md) — bucket, policy, versioning, lifecycle | 12 | 3h | 🟥 |
| 10 | [CloudWatch](10-cloudwatch.md) — phần cơ bản: metrics EC2, xem log | 12 | 1h | 🟥 |
| 09 | [Route 53](09-route53.md) — DNS trên AWS | 13 | 2h | 🟨 |
| 10 | [CloudWatch](10-cloudwatch.md) — phần còn lại: log group, alarm, SNS | 13 | 3h | 🟥 |
| 11 | [Ghép các dịch vụ thành hệ thống](11-putting-it-together.md) — luồng request đầu-cuối, kiến trúc tham chiếu | 13 | 2h | 🟥 |
| 07 | [RDS](07-rds.md) — database được quản lý, Multi-AZ, backup | 14 | 3h | 🟨 |
| 08 | [ELB & Auto Scaling](08-elb-autoscaling.md) — ALB, target group, health check, ASG | 14 | 4h | 🟨 |

> **Vì sao bài 06 (CLI) học ngay sau bài 02?** Từ bài 03 trở đi, mỗi lab đều có lệnh CLI để **kiểm tra** và **dọn dẹp**. Thứ tự đánh số giữ theo [cấu trúc giáo trình](../00-ROADMAP/curriculum-structure.md); thứ tự **học** theo bảng trên.

Lời giải câu hỏi và bài tập: thư mục [solutions/](solutions/) — **chỉ mở sau khi đã tự làm**. Thuật ngữ: [glossary.md](glossary.md).

---

## 6. Lab, break-fix, checkpoint và dự án

| Hạng mục | Tuần | Mô tả |
|---|---|---|
| [Lab 01 — Dựng VPC bằng tay](labs/lab-01-vpc-by-hand.md) | 11 | **Lab bắt buộc:** tạo VPC, 4 subnet, IGW, route table theo đúng `docs/network-plan.md` của bạn |
| [Lab 02 — Triển khai taskhub lên EC2](labs/lab-02-ec2-deploy-taskhub.md) | 12 | **Lab bắt buộc:** EC2 Ubuntu 24.04, Docker Compose, SG chỉ mở 80, vào máy bằng SSM |
| [Dự án: taskhub v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) | 11–12 | Triển khai thủ công lên EC2 trong VPC tự tạo; release `v0.4.0` |
| [🎯 Bài thi mốc 3 tháng](../00-ROADMAP/exam-month-3.md) | 12 | Dựng server mới từ đầu, triển khai `taskhub` trong 3 giờ |
| [Dự án: taskhub v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md) | 13–14 | CD tự động qua OIDC + SSM, CloudWatch cơ bản; release `v0.5.0` |
| [Break-fix AWS #1](labs/break-fix-01/README.md) | 13–14 | Hạ tầng có lỗi cài sẵn — đi theo luồng gói tin để tìm tầng hỏng |
| [Lab 03 — ALB + ASG + RDS (lab ngắn)](labs/lab-03-alb-asg-rds-short.md) | 14 | ALB + ASG ở 2 public subnet (SG chỉ nhận traffic từ ALB) + RDS ở private subnet, **không NAT**, trong **một buổi** → kiểm tra → **xóa toàn bộ**. Kiến trúc có NAT chỉ học lý thuyết ở bài 08 |
| [Checkpoint Giai đoạn 6](checkpoint.md) | 14 | Lý thuyết + thực hành mới + break-fix, không dùng AI |

---

## 7. Quy ước dùng chung trong module

| Thành phần | Giá trị |
|---|---|
| Region | `ap-southeast-1` (Singapore), AZ `ap-southeast-1a` / `ap-southeast-1b` |
| Gói tài khoản | Free plan (tạo ở tuần 11) |
| Danh tính hằng ngày | IAM user `phuong-admin` (thay bằng tên bạn), group `admins`, MFA bắt buộc |
| AWS CLI | v2, đăng nhập bằng `aws login` (credential tạm thời), profile `taskhub`, `export AWS_PROFILE=taskhub`. **Không** có access key dài hạn trên laptop |
| Tag trên mọi tài nguyên | `Project=taskhub`, `Env=dev`, `Owner=<tên bạn>`, `ManagedBy=manual` (đổi thành `terraform` từ v4) |
| Tên tài nguyên | `taskhub-vpc`, `taskhub-public-a`, `taskhub-public-b`, `taskhub-private-a`, `taskhub-private-b`, `taskhub-igw`, `taskhub-public-rt`, `taskhub-private-rt`, `taskhub-web-sg`, `taskhub-app` (EC2), `taskhub-ec2-role` |
| VPC ví dụ | `10.20.0.0/16`; public-a `10.20.1.0/24`, public-b `10.20.2.0/24`, private-a `10.20.11.0/24`, private-b `10.20.12.0/24`. **Bạn dùng số của `docs/network-plan.md` của mình** |
| EC2 dự án | `t3.small`, Ubuntu Server 24.04 LTS, gp3 20 GiB mã hóa, IMDSv2 bắt buộc, public-a, Public IPv4 tự gán (không Elastic IP) |
| Truy cập server | SSM Session Manager. SG `taskhub-web-sg` chỉ mở 80 (443 sau). **Không mở port 22** |
| Ứng dụng trên EC2 | `/opt/taskhub`, Compose dùng `image: ghcr.io/<github-user>/taskhub:${TASKHUB_IMAGE_TAG}`, nginx publish cổng 80 |
| Secret | Mật khẩu PostgreSQL ở SSM Parameter Store SecureString `/taskhub/dev/postgres-password` — không nằm trong GitHub hay user data |
| Role của EC2 | `taskhub-ec2-role`: `AmazonSSMManagedInstanceCore` + policy tối thiểu `taskhub-ec2-app` (đọc `/taskhub/dev/*`, ghi log `/taskhub/dev/*`, S3 bucket backup) |
| Role deploy (v3) | `taskhub-github-deploy`, GitHub Actions nhận qua OIDC, chỉ được chạy SSM Run Command trên instance có tag `Project=taskhub` |
| Bucket backup | `taskhub-backups-<account-id>` — tạo ở v2, dùng thật ở v5 |
| Phát hành | v2 → `v0.4.0` · v3 → `v0.5.0` |
| Số tài khoản trong ví dụ | `111122223333` (số mẫu của tài liệu AWS) · GitHub user mẫu `phuong-dev` |

---

## 8. AWS trong các module sau

| Kiến thức ở đây | Gặp lại ở |
|---|---|
| VPC, subnet, SG, EC2, IAM role dựng bằng tay | Dựng lại **bằng Terraform**, state trên S3 với `use_lockfile` (Module 07, v4) |
| Cài Docker, đồng bộ `compose.yaml` lên EC2 bằng tay | Ansible làm thay (Module 07, v4) |
| CloudWatch cơ bản | Prometheus + Grafana + Loki + Alloy (Module 08, v5) |
| S3 bucket backup | `pg_dump` tự động lên S3 + diễn tập restore (Module 08, v5) |
| ALB, Auto Scaling, health check | Kubernetes Service, Deployment, readiness probe (Module 09, v6) |
| IAM, OIDC, SG, Parameter Store | Rà soát bảo mật AWS tổng thể (Module 10) |
| Region, AZ, Shared Responsibility | On-premises và hybrid cloud (Module 11) |

---

## 9. Checklist hoàn thành module

- [ ] 🟥 Tài khoản Free plan an toàn: root có MFA và không access key; `phuong-admin` có MFA; budget và Free Tier alerts đã bật.
- [ ] 🟥 Giải thích được Region/AZ, Shared Responsibility, vì sao `taskhub` v2 single-AZ là đánh đổi có chủ ý.
- [ ] 🟥 Đọc và viết được IAM policy JSON đơn giản; phân biệt user, group, role; không có access key dài hạn trên laptop.
- [ ] 🟥 Dùng AWS CLI với `aws login`, `--query`, và đọc được lỗi `AccessDenied`.
- [ ] 🟥 Tự tạo VPC + 4 subnet + IGW + route table theo bảng IP của mình; giải thích luồng gói tin vào/ra.
- [ ] 🟥 Phân biệt security group và network ACL (stateful/stateless, allow/deny).
- [ ] 🟥 Triển khai `taskhub` lên EC2 bằng Docker Compose, chỉ mở port 80, vào máy bằng SSM.
- [ ] 🟥 Bucket S3 private có versioning và lifecycle.
- [ ] 🟥 CloudWatch: xem metrics EC2, có alarm gửi email, log group có retention.
- [ ] 🟥 Pipeline deploy lên EC2 qua OIDC — không access key trong GitHub ([v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md)).
- [ ] 🟨 Dựng và **xóa sạch** kiến trúc ALB + ASG + RDS trong một buổi; viết so sánh với EC2 + Compose.
- [ ] 🟥 Tìm ra tầng hỏng trong [break-fix AWS](labs/break-fix-01/README.md) bằng cách đi theo luồng gói tin.
- [ ] 🟥 Đạt [bài thi mốc 3 tháng](../00-ROADMAP/exam-month-3.md) và [Checkpoint Giai đoạn 6](checkpoint.md).
- [ ] 🟥 Hoàn thành [taskhub v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) và [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md).
- [ ] 🟥 Sau mỗi buổi: không còn tài nguyên thừa; ghi số dư credit vào nhật ký.
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#aws).

---

## 10. Nguồn học

| Vai trò | Nguồn | Ghi chú | Kiểm tra ngày |
|---|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt, gắn với dự án `taskhub` | — |
| Chính | [AWS Documentation](https://docs.aws.amazon.com/) (VPC, EC2, IAM, S3, RDS, ELB, CloudWatch…) | Tra cứu chính thức; mỗi bài dẫn đúng trang cần đọc | 2026-10-31 |
| Chính | AWS Skill Builder — *AWS Cloud Practitioner Essentials* ([skillbuilder.aws](https://skillbuilder.aws/)) | Miễn phí, tự học song song tuần 11 (~6h), cần AWS Builder ID. Xem [khảo sát nguồn](../00-ROADMAP/source-survey.md) | 2026-10-31 |
| Chi phí | [AWS Free Tier](https://aws.amazon.com/free/) + [Choosing a plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) | Đọc **trước** khi tạo tài khoản | 2026-10-31 |
| Chi phí | [AWS Pricing Calculator](https://calculator.aws/) | Ước tính trước khi tạo tài nguyên | 2026-10-31 |
| Kiến trúc | [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html) | 6 trụ cột — khung để trình bày đánh đổi | 2026-10-31 |
| Kiến trúc | [VPC example: private subnets + NAT](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-example-private-subnets-nat.html) | Kiến trúc tham chiếu 2 AZ, dùng cho lab ngắn tuần 14 | 2026-10-31 |
| Bảo mật | [AWS Shared Responsibility Model](https://aws.amazon.com/compliance/shared-responsibility-model/) | Ranh giới trách nhiệm | 2026-10-31 |

Thuật ngữ của module: [glossary.md](glossary.md).
