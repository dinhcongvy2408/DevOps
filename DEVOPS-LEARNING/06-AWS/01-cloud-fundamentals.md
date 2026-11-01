# 01. Cloud fundamentals — điện toán đám mây và hạ tầng toàn cầu của AWS

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [00. Tạo tài khoản AWS an toàn](00-aws-account-setup-cost-safety.md), [Networking 02 — IPv4 & CIDR](../02-NETWORKING/02-ipv4-subnet-cidr.md), [Docker 01 — VM vs container](../04-DOCKER/01-vm-vs-container-architecture.md)
> Môi trường: `[AWS Console]` (chỉ xem, không tạo tài nguyên), giấy bút hoặc file Markdown

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

- Định nghĩa **cloud computing** theo 5 đặc tính của NIST và phân biệt **IaaS, PaaS, SaaS** bằng ví dụ AWS.
- Giải thích **Region, Availability Zone (AZ), edge location** và vì sao kiến trúc "chịu lỗi" phải trải trên nhiều AZ.
- Áp dụng **Shared Responsibility Model** để nói rõ ở `taskhub` phần nào AWS lo, phần nào bạn lo.
- Kể được các **mô hình tính giá** (On-Demand, Savings Plans/Reserved, Spot) và 6 trụ cột **Well-Architected**.
- Hiểu rằng **mọi thao tác trên AWS đều là một lời gọi API** — console, CLI, Terraform chỉ là các cách khác nhau để gọi cùng một API, và CloudTrail ghi lại chúng.
- Ánh xạ những thứ bạn đã làm trên laptop (Linux, mạng, Docker Compose) sang dịch vụ AWS tương ứng.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Cần kiến thức của bài này |
|---|---|
| "Region Singapore có sự cố một AZ, hệ thống của mình có sập không?" | AZ, thiết kế đa AZ |
| "Database bị lộ dữ liệu — lỗi của AWS hay của mình?" | Shared Responsibility |
| "Có nên dùng RDS thay vì tự chạy PostgreSQL trên EC2?" | IaaS vs PaaS, ai lo vá lỗi, backup |
| "Môi trường dev có cần chạy 24/7 không? Có cách nào rẻ hơn?" | Mô hình tính giá, Spot, tắt khi không dùng |
| "Ai đã xóa security group này?" | Mọi thứ là API call → CloudTrail |
| Phỏng vấn: "Giải thích Region và AZ", "IaaS khác PaaS thế nào", "Shared Responsibility là gì" | Đây là nhóm câu hỏi **gần như chắc chắn** gặp với vị trí Junior Cloud |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Trước khi có cloud

Đến tuần 8, `taskhub` chạy trên laptop của bạn. Muốn cho người khác truy cập 24/7 theo cách "truyền thống", bạn phải: mua server, thuê chỗ đặt trong data center, kéo đường mạng, có IP tĩnh, tự thay ổ cứng hỏng, tự lo điện và làm mát. Mất nhiều tuần, trả tiền trước cho phần cứng có thể không dùng hết.

### 3.2. Cloud computing là gì — định nghĩa NIST

Định nghĩa được trích dẫn rộng rãi nhất là [NIST SP 800-145 — *The NIST Definition of Cloud Computing*](https://csrc.nist.gov/pubs/sp/800/145/final) (2011): cloud là mô hình cho phép truy cập qua mạng, theo nhu cầu, vào một **kho tài nguyên điện toán dùng chung** (mạng, server, lưu trữ, ứng dụng, dịch vụ) có thể **cấp phát và thu hồi nhanh** với rất ít công quản lý. NIST nêu **5 đặc tính cốt lõi**, **3 mô hình dịch vụ**, **4 mô hình triển khai**.

| 5 đặc tính (NIST) | Nghĩa | Ví dụ bạn sẽ làm |
|---|---|---|
| On-demand self-service | Tự cấp tài nguyên, không cần gọi ai | Bấm nút / chạy lệnh tạo EC2 |
| Broad network access | Truy cập qua mạng bằng thiết bị thông thường | Console trên trình duyệt, CLI trên WSL |
| Resource pooling | Tài nguyên vật lý dùng chung cho nhiều khách hàng, được cô lập | EC2 của bạn chạy chung phần cứng với người khác |
| Rapid elasticity | Tăng/giảm nhanh theo nhu cầu | Auto Scaling group (tuần 14) |
| Measured service | Đo đếm và tính tiền theo mức dùng | Hóa đơn theo giờ máy, GB lưu trữ |

### 3.3. Ba mô hình dịch vụ

| Mô hình | Nhà cung cấp lo | Bạn lo | Ví dụ AWS | So với `taskhub` |
|---|---|---|---|---|
| **IaaS** — Infrastructure as a Service | Phần cứng, mạng vật lý, ảo hóa | Hệ điều hành, vá lỗi OS, runtime, app, dữ liệu | **EC2**, EBS, VPC | v2: bạn tự cài Docker, tự chạy PostgreSQL trên EC2 |
| **PaaS** — Platform as a Service | Thêm OS, runtime, vá lỗi nền tảng | App và dữ liệu, cấu hình | **RDS** (database được quản lý), Elastic Beanstalk | Lab tuần 14: PostgreSQL trên RDS — không SSH vào được máy database |
| **SaaS** — Software as a Service | Gần như mọi thứ | Dữ liệu và người dùng của bạn | Gmail, GitHub | GitHub chính là SaaS bạn đang dùng |

Ranh giới không phải lúc nào cũng rõ: S3, Lambda thường được gọi là dịch vụ **được quản lý** (managed service) — bạn không thấy server nào cả.

### 3.4. Bốn mô hình triển khai

**Public cloud** (AWS, Azure, GCP) · **Private cloud** (hạ tầng riêng của một tổ chức, ví dụ chạy VMware/OpenStack trong data center của công ty) · **Hybrid cloud** (kết hợp hai loại, có kết nối giữa chúng) · **Community cloud** (dùng chung cho một nhóm tổ chức cùng yêu cầu). Hybrid và on-premises được học ở Module 11 (tuần 22).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Hạ tầng toàn cầu: Region, AZ, edge

**Region** — khu vực địa lý độc lập. Theo [trang Global Infrastructure](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/) (kiểm tra 2026-10-31), AWS có **39 Region** với **124 Availability Zone**, và đã công bố thêm Region mới. Con số này tăng dần — đừng học thuộc, hãy biết **cách tra**.

**Availability Zone (AZ)** — theo AWS: "một hoặc nhiều data center tách biệt, có nguồn điện, mạng và kết nối dự phòng riêng, trong một Region". Các AZ cách nhau một khoảng đủ xa để một sự cố cục bộ (cháy, mất điện, ngập) không ảnh hưởng tới AZ khác, nhưng vẫn trong phạm vi **100 km** để độ trễ giữa chúng thấp.

| Khái niệm | Ví dụ | Ý nghĩa với bạn |
|---|---|---|
| Region | `ap-southeast-1` (Singapore) | Chọn một lần cho dự án; dữ liệu nằm ở đó |
| Tên AZ | `ap-southeast-1a`, `ap-southeast-1b` | Chọn khi tạo **subnet** (bài 03) |
| AZ ID | `apse1-az1`, `apse1-az2` | Định danh vật lý **cố định** giữa mọi tài khoản |
| Edge location | Điểm phân phối của CloudFront, Route 53 | Gần người dùng cuối; giáo trình chỉ cần biết tên |

**Bẫy thú vị:** theo [tài liệu AZ ID](https://docs.aws.amazon.com/ram/latest/userguide/working-with-az-ids.html), AWS **ánh xạ ngẫu nhiên** tên AZ sang AZ vật lý cho **mỗi tài khoản**. `ap-southeast-1a` của bạn có thể là một data center khác với `ap-southeast-1a` của đồng nghiệp ở tài khoản khác. Khi cần so sánh giữa các tài khoản, dùng **AZ ID**.

**Vì sao đa AZ quan trọng?** Một AZ có thể gặp sự cố. Hệ thống chỉ ở một AZ thì sập theo. Kiến trúc "chuẩn" đặt ít nhất hai bản sao ở hai AZ phía sau load balancer (lab tuần 14).

> **Dự án `taskhub` chạy 1 EC2 ở 1 AZ** — đây là **đánh đổi có chủ ý** để tiết kiệm credit, không phải thiết kế production. Bạn phải nói được điều này trong phỏng vấn: "Tôi biết nó là single point of failure; nếu cần HA tôi sẽ làm X" (X ở bài 08 và [bài 11](11-putting-it-together.md)).

### 4.2. 🟥 Dịch vụ theo Region và dịch vụ global

| Phạm vi | Ví dụ | Hệ quả |
|---|---|---|
| **AZ** | Subnet, EBS volume, EC2 instance | Ổ EBS ở AZ `a` không gắn được vào máy ở AZ `b` |
| **Region** | VPC, security group, RDS, CloudWatch log group | Đổi region trên console → không thấy |
| **Global** | IAM, Route 53, CloudFront, Billing | Thấy ở mọi region |
| Đặc biệt | S3: **tên bucket** là duy nhất toàn cầu, nhưng **dữ liệu** nằm ở một region | Bài 05 |

### 4.3. 🟥 Shared Responsibility Model — trách nhiệm chia đôi

Theo [AWS Shared Responsibility Model](https://aws.amazon.com/compliance/shared-responsibility-model/): AWS chịu trách nhiệm **bảo mật *của* cloud** (security **of** the cloud) — hạ tầng chạy mọi dịch vụ: data center vật lý, phần cứng, mạng, lớp ảo hóa. Khách hàng chịu trách nhiệm **bảo mật *trong* cloud** (security **in** the cloud) — ví dụ với EC2, khách hàng quản lý hệ điều hành khách, vá lỗi OS và ứng dụng, cấu hình security group, mã hóa dữ liệu, phân quyền IAM.

Có những **kiểm soát dùng chung** (shared controls) như vá lỗi, quản lý cấu hình, đào tạo: AWS làm phần của hạ tầng, bạn làm phần của hệ thống và con người bên bạn.

Ranh giới **dịch chuyển theo loại dịch vụ**:

| Việc | EC2 (IaaS) | RDS (PaaS) | S3 (managed) |
|---|---|---|---|
| Data center, phần cứng, mạng vật lý | AWS | AWS | AWS |
| Vá lỗi hệ điều hành | **Bạn** | AWS | AWS |
| Vá lỗi phần mềm database | **Bạn** (PostgreSQL trong container) | AWS (trong cửa sổ bảo trì bạn chọn) | — |
| Backup | **Bạn** (`pg_dump` ở v5) | AWS tự động, **bạn** cấu hình số ngày giữ | Bạn bật versioning |
| Firewall (security group) | **Bạn** | **Bạn** | — (dùng bucket policy, Block Public Access) |
| Phân quyền (IAM, mật khẩu DB) | **Bạn** | **Bạn** | **Bạn** |
| Mã hóa dữ liệu | **Bạn** bật | **Bạn** bật | Mặc định bật, bạn chọn loại khóa |
| Dữ liệu và ai được đọc nó | **Luôn là bạn** | **Luôn là bạn** | **Luôn là bạn** |

> **Quy tắc nhớ:** AWS không bao giờ chịu trách nhiệm cho việc **bạn** cấu hình sai. Bucket public do bạn tắt Block Public Access, security group mở port 5432 ra `0.0.0.0/0`, access key lộ trên GitHub — đều là phần "**in** the cloud".

### 4.4. 🟥 Mọi thứ là API

Khi bạn bấm **Launch instance** trên console, trình duyệt gửi một **lời gọi API** `RunInstances` tới endpoint của EC2 ở region đang chọn, được **ký** bằng thông tin xác thực của bạn. CLI, SDK, Terraform, CloudFormation — tất cả đều gọi **cùng những API đó**.

```text
 Console (trình duyệt) ─┐
 AWS CLI (WSL)         ─┤                                   ┌──► EC2 tạo máy
 Terraform (tuần 15)   ─┼──► API endpoint ec2.ap-southeast-1 ┤
 GitHub Actions (v3)   ─┘    (HTTPS + chữ ký + kiểm tra IAM) └──► CloudTrail ghi: ai, lúc nào, từ đâu
```

Hệ quả cho DevOps:

1. **Làm được trên console thì tự động hóa được** — chỉ cần biết tên API (CLI: `aws ec2 run-instances`).
2. **Quyền IAM đặt theo tên API**: `ec2:RunInstances`, `s3:GetObject`. Hiểu điều này thì đọc được policy ([bài 02](02-iam.md)).
3. **Mọi hành động quản lý đều để lại dấu vết**: theo [tài liệu CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html), event history bật sẵn, lưu **90 ngày** management event theo từng region, xem **miễn phí**.
4. **Console tiện để học, nhưng không lặp lại được.** Đó là lý do tuần 15 chuyển sang Terraform: hạ tầng dựng bằng code thì dựng lại giống hệt và review được trong PR.

### 4.5. 🟥 Mô hình tính giá

| Mô hình | Cách hoạt động | Hợp với | Trên Free plan? |
|---|---|---|---|
| **On-Demand** | Trả theo giờ/giây, không cam kết | Học tập, tải không đoán trước | ✅ Giáo trình dùng cái này |
| **Savings Plans / Reserved Instances** | Cam kết dùng 1 hoặc 3 năm để được giảm giá | Production chạy ổn định 24/7 | ❌ Không có trên Free plan (bài 00) |
| **Spot Instances** | Dùng dung lượng dư của AWS, rẻ hơn nhiều nhưng **có thể bị thu hồi** với thông báo ngắn | Job chạy lại được: CI runner, xử lý batch | 🟦 Biết khái niệm |

Ba "đồng hồ" tính tiền phổ biến nhất mà bạn cần nhớ: **compute** (giờ máy), **storage** (GB-tháng), **data transfer** (GB ra khỏi AWS). Thêm những thứ tính theo giờ dù không dùng: Public IPv4, NAT Gateway, load balancer (xem [bài 00 §4.8](00-aws-account-setup-cost-safety.md#48--những-thứ-âm-thầm-tốn-tiền)).

**AWS Pricing Calculator** ([calculator.aws](https://calculator.aws/)) cho phép ước tính chi phí **trước khi tạo** — dùng ở lab của bài này.

### 4.6. 🟨 AWS Well-Architected Framework — 6 trụ cột

[Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html) là bộ câu hỏi AWS dùng để đánh giá một kiến trúc. Sáu trụ cột (kiểm tra 2026-10-31):

| Trụ cột | Câu hỏi cốt lõi | `taskhub` v2 trả lời thế nào |
|---|---|---|
| **Operational excellence** | Vận hành, thay đổi, phát hiện lỗi thế nào? | CI/CD (v1, v3), runbook (v1.0) |
| **Security** | Bảo vệ dữ liệu, danh tính, hạ tầng thế nào? | IAM role, SG chỉ 80/443, không access key, SSM thay SSH |
| **Reliability** | Hệ thống chịu lỗi và phục hồi thế nào? | ⚠️ Yếu: 1 EC2, 1 AZ. Bù lại: backup (v5), dựng lại nhanh bằng Terraform (v4) |
| **Performance efficiency** | Dùng tài nguyên hiệu quả không? | `t3.small` đủ cho tải học tập |
| **Cost optimization** | Có tiêu tiền thừa không? | Không NAT, 1 IPv4, tắt khi không học |
| **Sustainability** | Giảm tác động môi trường? | Không chạy tài nguyên thừa |

Bạn không cần thuộc bộ câu hỏi chi tiết. Nhưng biết 6 trụ cột giúp bạn **trình bày đánh đổi** của dự án một cách có cấu trúc.

### 4.7. 🟥 Ánh xạ từ những gì bạn đã biết sang AWS

| Bạn đã làm ở | Trên laptop / on-premises | Trên AWS | Bài |
|---|---|---|---|
| Linux 03 | User, group, `sudo` | IAM user, group, policy, role | 02 |
| Linux 04, Docker | Một máy Linux chạy dịch vụ | **EC2** instance | 04 |
| Linux 01 | Ổ đĩa, filesystem | **EBS** volume | 04 |
| Linux 07 | Thư mục backup, NAS | **S3** bucket | 05 |
| Networking 02 | Dải IP, chia subnet | **VPC**, subnet | 03 |
| Networking 04 | Router, default gateway, NAT | Route table, **Internet Gateway**, NAT Gateway | 03 |
| Networking 05 | Firewall `ufw`/iptables | **Security group**, network ACL | 03 |
| Networking 03 | DNS | **Route 53** | 09 |
| Networking 07 | Nginx làm load balancer | **ALB** (Application Load Balancer) | 08 |
| Docker 05 | Container `postgres` | PostgreSQL trên EC2 (v2) hoặc **RDS** (lab) | 07 |
| Linux 07 | `journalctl`, `/var/log` | **CloudWatch Logs**, metrics, alarm | 10 |
| Linux 05 | SSH vào server | **SSM Session Manager** (không mở port 22) | 04 |
| Docker 06 | Registry GHCR | GHCR (giữ nguyên) hoặc **ECR** | 04 |

> Đây là lý do 10 tuần đầu dành cho nền tảng: **VPC chỉ là mạng**, **EC2 chỉ là máy Linux**, **IAM chỉ là phân quyền**. Nếu bạn hiểu bản chất, AWS chỉ là giao diện mới.

### 4.8. Gặp lại ở đâu

| Kiến thức ở đây | Gặp lại |
|---|---|
| Region, AZ, subnet theo AZ | [Bài 03 — VPC](03-vpc-networking.md), [bài 08 — ALB & Auto Scaling](08-elb-autoscaling.md) |
| Shared Responsibility với EC2 vs RDS | [Bài 07 — RDS](07-rds.md) |
| Mọi thứ là API, tên action trong policy | [Bài 02 — IAM](02-iam.md), [bài 06 — AWS CLI](06-aws-cli.md), Module 07 Terraform |
| Well-Architected, đánh đổi 1 AZ | [Bài 11 — Ghép các dịch vụ thành hệ thống](11-putting-it-together.md) |
| Ước tính chi phí trước khi tạo | Mọi lab AWS, [dự án v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) |
| CloudTrail | [Bài 10 — CloudWatch](10-cloudwatch.md), Module 10 Security |

---

## 5. Ví dụ thực tế

**Ví dụ 1 — Sự cố một AZ.** Một công ty chạy toàn bộ web server trong một AZ để "đơn giản". Khi AZ đó gặp sự cố điện, website sập vài giờ dù các AZ khác trong cùng region vẫn bình thường. Công ty bên cạnh chạy hai bản sao ở hai AZ sau load balancer: load balancer ngừng gửi traffic tới AZ lỗi, người dùng gần như không nhận ra. Chi phí thêm: một máy và một load balancer. Đây là phép tính kinh doanh, không phải kỹ thuật thuần túy — và là lý do dự án học tập của bạn **chấp nhận** 1 AZ.

**Ví dụ 2 — "Lỗi của AWS?"** Một startup bị lộ dữ liệu khách hàng vì bucket S3 public. Theo Shared Responsibility, đây là phần "in the cloud": cấu hình quyền truy cập dữ liệu là trách nhiệm khách hàng. Từ năm 2023, bucket mới mặc định bật Block Public Access — một ví dụ AWS thay đổi **mặc định an toàn** nhưng không thay đổi **trách nhiệm** (bài 05).

**Ví dụ 3 — EC2 hay RDS cho `taskhub`?** v2 chạy PostgreSQL trong container trên EC2: rẻ (không thêm tiền), nhưng bạn tự lo backup, vá lỗi, phục hồi. RDS: AWS lo backup tự động, vá lỗi, Multi-AZ chỉ bằng một tùy chọn — nhưng thêm chi phí theo giờ. Câu trả lời đúng phụ thuộc yêu cầu; bạn sẽ viết so sánh này ở lab tuần 14.

---

## 6. Sơ đồ kiến trúc

**Region, AZ và nơi `taskhub` v2 nằm:**

```text
┌──────────────────────────── Region ap-southeast-1 (Singapore) ────────────────────────────┐
│                                                                                           │
│  ┌──── AZ ap-southeast-1a ─────┐  ┌──── AZ ap-southeast-1b ─────┐  ┌── AZ ap-southeast-1c ─┐ │
│  │  data center(s) riêng       │  │  data center(s) riêng       │  │  (giáo trình không     │ │
│  │                             │  │                             │  │   dùng)                │ │
│  │  ┌ VPC taskhub-vpc (trải qua các AZ — bài 03) ──────────────────────────────────┐       │ │
│  │  │ public-a 10.20.1.0/24   │  │ public-b 10.20.2.0/24       │                   │       │ │
│  │  │  └─ EC2 taskhub-app ◄── v2: 1 máy, 1 AZ (đánh đổi chi phí)                   │       │ │
│  │  │ private-a 10.20.11.0/24 │  │ private-b 10.20.12.0/24     │                   │       │ │
│  │  └──────────────────────────────────────────────────────────────────────────────┘       │ │
│  └─────────────────────────────┘  └─────────────────────────────┘  └────────────────────────┘ │
│  Dịch vụ cấp Region: VPC, security group, CloudWatch, S3 bucket (dữ liệu)                │
└───────────────────────────────────────────────────────────────────────────────────────────┘
 Global: IAM · Route 53 · Billing             Edge locations: CloudFront, Route 53 (gần người dùng)
```

*(Số AZ của Singapore và các dải IP chỉ là ví dụ minh họa; bạn dùng `docs/network-plan.md` của mình. Tra số AZ bằng lệnh ở §8.)*

**Shared Responsibility với EC2:**

```text
          ┌──────────────────────────────────────────────┐
  BẠN     │ Dữ liệu taskhub · mật khẩu DB · IAM          │  ← security IN the cloud
          │ App Spring Boot · container · Docker         │
          │ Ubuntu 24.04: vá lỗi, user, SSH/SSM          │
          │ Security group · mã hóa EBS (bật)            │
          ├──────────────────────────────────────────────┤
  AWS     │ Hypervisor · server vật lý · mạng vật lý     │  ← security OF the cloud
          │ Data center: điện, làm mát, an ninh vật lý   │
          └──────────────────────────────────────────────┘
```

---

## 7. Các câu lệnh cần biết

Bài này chủ yếu là khái niệm. Các lệnh dưới đây **chỉ đọc, không tốn tiền**, chạy được sau khi cấu hình CLI ở [bài 06](06-aws-cli.md) — quay lại làm phần §9 Bước 6 khi đã xong bài 06.

| Lệnh | Mục đích |
|---|---|
| `aws ec2 describe-regions` | Liệt kê region tài khoản đang bật |
| `aws ec2 describe-availability-zones --region ap-southeast-1` | AZ của Singapore: tên AZ ↔ AZ ID |
| `aws cloudtrail lookup-events` | Tra event history (90 ngày, management event) |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. `aws ec2 describe-availability-zones`

```bash
# [WSL] — sau bài 06
aws ec2 describe-availability-zones \
  --region ap-southeast-1 \
  --query 'AvailabilityZones[].[ZoneName,ZoneId,State]' \
  --output table
```

```text
-------------------------------------------------
|           DescribeAvailabilityZones           |
+------------------+--------------+-------------+
|  ap-southeast-1a |  apse1-az2   |  available  |
|  ap-southeast-1b |  apse1-az1   |  available  |
|  ap-southeast-1c |  apse1-az3   |  available  |
+------------------+--------------+-------------+
```

*(Đầu ra minh họa. Cột AZ ID của bạn có thể ghép khác — đúng như §4.1 giải thích.)*

| Phần | Ý nghĩa |
|---|---|
| `--region ap-southeast-1` | Hỏi region nào (ghi đè cấu hình mặc định của profile) |
| `--query '...[ZoneName,ZoneId,State]'` | JMESPath: lấy ba trường của mỗi AZ |
| `--output table` | Hiển thị dạng bảng (khác: `json`, `text`, `yaml`) |

### 8.2. `aws ec2 describe-regions`

```bash
aws ec2 describe-regions --query 'Regions[].RegionName' --output text | tr '\t' '\n' | sort
```

Chỉ liệt kê region **đang bật** cho tài khoản. Một số region mới cần *opt-in* trước khi dùng. Câu hỏi để suy nghĩ: vì sao nhiều công ty **cố ý tắt** những region họ không dùng? (gợi ý: bài 00 §4.8, dòng cuối của bảng).

### 8.3. `aws cloudtrail lookup-events`

```bash
aws cloudtrail lookup-events \
  --region us-east-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser \
  --max-results 5 \
  --query 'Events[].[EventTime,Username,EventName]' \
  --output table
```

| Tham số | Ý nghĩa |
|---|---|
| `--region us-east-1` | Sự kiện của dịch vụ global như IAM thường được ghi ở `us-east-1`. Sự kiện EC2/VPC thì tìm ở `ap-southeast-1` |
| `--lookup-attributes` | **Một** điều kiện lọc mỗi lần (giới hạn của event history) |
| `--max-results 5` | Giới hạn số kết quả |

---

## 9. Bài thực hành từng bước

> **Ước tính chi phí:** 0 USD. Bài thực hành chỉ đọc trên console, dùng Pricing Calculator (công cụ web) và làm bài trên giấy. **Không tạo tài nguyên nào.**
> Ghi kết quả vào `~/projects/devops-journey/week11/cloud-fundamentals.md`.

### Bước 1 — Region và AZ trên console `[AWS Console]`

Đăng nhập bằng `phuong-admin`, region **Singapore**.

1. Mở **EC2** → trên dashboard tìm mục liệt kê **Zones** / trạng thái các AZ. Ghi lại tên các AZ.
2. Mở **AWS Global View** (tìm "Global View" trên thanh tìm kiếm) → tab **Regions and Zones** → chọn Singapore → ghi số AZ và **AZ ID** tương ứng với tên AZ của tài khoản bạn.
3. Trả lời: AZ ID của `ap-southeast-1a` trong tài khoản bạn là gì? Có giống bảng minh họa ở §8.1 không? Vì sao không cần giống?

### Bước 2 — Phân loại dịch vụ theo phạm vi `[AWS Console]`

Mở lần lượt **IAM**, **EC2**, **S3**, **Route 53**, **VPC**. Với mỗi dịch vụ, quan sát ô chọn region góc trên phải: nó hiện tên region, hay hiện **Global**? Điền bảng:

| Dịch vụ | Region hay Global? | Giải thích vì sao hợp lý |
|---|---|---|
| IAM | | |
| EC2 | | |
| S3 | | |
| Route 53 | | |
| VPC | | |

### Bước 3 — CloudTrail: tìm lại dấu vết của chính bạn `[AWS Console]`

**CloudTrail** → **Event history**:

1. Chọn region **US East (N. Virginia)**, lọc *Event name* = `CreateUser` → tìm sự kiện tạo `phuong-admin` ở bài 00. Mở chi tiết, ghi lại: `userIdentity.type`, `sourceIPAddress`, `eventTime` (đổi sang giờ Việt Nam).
2. Đổi sang region **Singapore** → có sự kiện nào không? Vì sao ít hơn?
3. Lọc *Event name* = `ConsoleLogin` (thử cả hai region) → đếm số lần bạn đăng nhập tuần này.

### Bước 4 — Ước tính chi phí `taskhub` v2 bằng Pricing Calculator `[trình duyệt]`

Mở [calculator.aws](https://calculator.aws/) → **Create estimate**:

1. Region **Asia Pacific (Singapore)**.
2. Thêm **Amazon EC2**: Linux, `t3.small`, On-Demand, số lượng 1, ổ **gp3 20 GiB**.
3. Thêm **Amazon VPC** → phần **Public IPv4 address**: 1 địa chỉ (nếu calculator tách mục này; nếu không, tự cộng 0,005 USD × số giờ).
4. Ghi tổng tiền/tháng cho hai kịch bản: **730 giờ** (24/7) và **100 giờ** (học ~4 giờ/ngày, tắt khi nghỉ).
5. Lưu estimate (hoặc chụp màn hình) — dùng lại ở bài tập 1 của [bài 00](00-aws-account-setup-cost-safety.md) và ở [dự án v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md).

> Lưu ý: khi **stop** máy, phần giờ máy dừng nhưng ổ gp3 vẫn tính đủ tháng, và Public IPv4 tự gán sẽ **được thu hồi** khi stop (máy nhận IP mới khi start lại — bài 04). Ghi ra: kịch bản 100 giờ thì phần nào vẫn tính đủ 730 giờ?

### Bước 5 — Shared Responsibility cho `taskhub` `[giấy]`

Liệt kê 10 việc cần làm để `taskhub` v2 an toàn và chạy ổn định (ví dụ: vá Ubuntu, đổi mật khẩu PostgreSQL, backup, chặn port 5432, thay ổ cứng hỏng, cập nhật image Java…). Với mỗi việc: **AWS** hay **bạn**? Nếu chuyển PostgreSQL sang RDS thì những dòng nào đổi chủ?

### Bước 6 — CLI (làm sau bài 06) `[WSL]`

Chạy ba lệnh ở §8 và so sánh với kết quả bạn thấy trên console ở Bước 1 và Bước 3.

### Bước 7 — Vẽ kiến trúc v0 → v2 `[giấy hoặc Markdown]`

Vẽ hai sơ đồ cạnh nhau:

- **v0** (tuần 8): laptop → Docker Compose → nginx, taskhub, postgres ([sơ đồ v0](../12-PRACTICAL-PROJECT/README.md#31-v0--laptop-docker-compose-tuần-8)).
- **v2** (tuần 12): Internet → Security group → EC2 trong public subnet của VPC → **cùng** Docker Compose. Thêm: IAM role của EC2, SSM Session Manager, S3 bucket backup, GHCR.

Đánh dấu trên sơ đồ v2: thành phần nào **mới**, thành phần nào **giữ nguyên** từ v0, và mỗi thành phần mới tương ứng với dòng nào trong bảng ánh xạ ở §4.7.

### Dọn dẹp

Không có gì để dọn: bài này không tạo tài nguyên. Nếu bạn lưu estimate trên Pricing Calculator, đó chỉ là một liên kết chia sẻ, không tính tiền.

---

## 10. Kết quả mong đợi

- File `week11/cloud-fundamentals.md` có: bảng AZ ↔ AZ ID của tài khoản bạn, bảng phạm vi 5 dịch vụ, 3 sự kiện CloudTrail đã đọc được, estimate chi phí cho hai kịch bản, bảng Shared Responsibility 10 dòng, hai sơ đồ v0 và v2.
- Bạn giải thích được trong 2 phút, không nhìn tài liệu: Region vs AZ, IaaS vs PaaS, Shared Responsibility với EC2.

---

## 11. Các lỗi thường gặp

| Nhầm lẫn | Thực tế |
|---|---|
| "AZ là một data center" | Một AZ là **một hoặc nhiều** data center |
| "Chọn 2 AZ là có HA" | Chỉ khi **có bản sao chạy** ở cả hai và có thứ chuyển traffic (load balancer). 1 EC2 trong VPC trải 2 AZ vẫn là 1 điểm lỗi |
| "`ap-southeast-1a` của tôi và của bạn là cùng một chỗ" | Ánh xạ tên AZ khác nhau giữa các tài khoản; dùng AZ ID để so |
| "Dùng cloud thì AWS lo bảo mật" | AWS lo **của** cloud; cấu hình, dữ liệu, quyền là **của bạn** |
| "Stop máy là hết tốn tiền" | Ổ EBS, Elastic IP vẫn tính (bài 00) |
| "Free tier eligible = miễn phí" | Trên tài khoản mới: được chạy trên Free plan và **trừ credit** |
| "Console và CLI là hai hệ thống khác nhau" | Cùng một API; khác cách gọi |
| "Thấy region trống nghĩa là tài khoản không có gì" | Có thể tài nguyên ở region khác → AWS Global View |

---

## 12. Đọc log và xử lý lỗi

Ở giai đoạn khái niệm, "lỗi" thường là **không tìm thấy tài nguyên** hoặc **không hiểu ai đã thay đổi gì**. Quy trình 3 câu hỏi:

1. **Đúng tài khoản chưa?** Góc trên phải console hiện tên user và số tài khoản; trên CLI: `aws sts get-caller-identity`.
2. **Đúng region chưa?** Ô region trên console; trên CLI: `aws configure get region --profile taskhub` hoặc tham số `--region`.
3. **Ai đã làm gì?** CloudTrail event history ở **đúng region** (sự kiện global → `us-east-1`).

Ví dụ đọc một kết quả `lookup-events` (minh họa):

```text
-------------------------------------------------------------
|                       LookupEvents                        |
+----------------------------+---------------+--------------+
|  2027-01-04T09:15:31+07:00 |  root         |  CreateUser  |
|  2027-01-04T09:12:02+07:00 |  root         |  CreateGroup |
+----------------------------+---------------+--------------+
```

Đọc: hai hành động quản trị bằng **root** — hợp lệ vì đây là lúc bạn dựng tài khoản (bài 00, Bước 6). Từ sau thời điểm đó, cột `Username` chỉ nên là `phuong-admin` hoặc tên role (v2, v3). Ghi các phát hiện vào `troubleshooting-journal.md` nếu có điều bất thường.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Nêu 5 đặc tính cốt lõi của cloud theo NIST, mỗi đặc tính một ví dụ AWS.
2. IaaS, PaaS, SaaS khác nhau ở đâu? Xếp EC2, RDS, GitHub vào đúng nhóm.
3. Region và AZ khác nhau thế nào? Theo AWS, các AZ trong một region cách nhau trong phạm vi bao xa và vì sao?
4. Vì sao `ap-southeast-1a` của hai tài khoản có thể là hai nơi khác nhau? Dùng gì để so sánh chính xác?
5. Kể một tài nguyên cấp AZ, một tài nguyên cấp Region, một dịch vụ Global.
6. Giải thích "security **of** the cloud" và "security **in** the cloud" bằng ví dụ `taskhub`.
7. Khi chuyển PostgreSQL từ container trên EC2 sang RDS, trách nhiệm nào chuyển từ bạn sang AWS? Trách nhiệm nào **vẫn** là của bạn?
8. "Mọi thứ trên AWS là API" — kể ba hệ quả thực tế của câu này với DevOps.
9. CloudTrail event history lưu bao lâu, ghi loại sự kiện nào, có mất phí không?
10. On-Demand, Savings Plans, Spot khác nhau thế nào? Cái nào **không** dùng được trên Free plan?
11. Kể 6 trụ cột Well-Architected. `taskhub` v2 yếu nhất ở trụ cột nào và vì sao chấp nhận được?
12. Vì sao chạy 1 EC2 trong VPC có subnet ở 2 AZ vẫn **không** phải là high availability?
13. Ánh xạ sang AWS: `ufw`, router + NAT, `journalctl`, thư mục backup, SSH.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/01-solutions.md](solutions/01-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Chọn region có lý do.** Một công ty bán hàng online cho khách ở Việt Nam, có yêu cầu pháp lý lưu dữ liệu khách hàng ở châu Á. Liệt kê 4 tiêu chí chọn region và áp dụng để chọn giữa Singapore, Tokyo, N. Virginia. Ghi rõ tiêu chí nào bạn **không thể** kiểm tra chỉ bằng tài liệu kỹ thuật.

**Bài 2 — Ma trận trách nhiệm.** Lập bảng Shared Responsibility cho ba phương án chạy `taskhub`: (a) EC2 + Docker Compose (v2), (b) EC2 cho app + RDS cho database, (c) một dịch vụ container được quản lý (ví dụ ECS Fargate — đọc trang giới thiệu của AWS để biết nó lo gì). Ít nhất 8 dòng việc.

**Bài 3 — Kiến trúc cho sự cố một AZ.** Vẽ lại sơ đồ `taskhub` để sống sót khi `ap-southeast-1a` sập hoàn toàn. Liệt kê các dịch vụ cần thêm, và ước tính bằng Pricing Calculator chi phí tăng thêm mỗi tháng. Viết 3 câu giải thích vì sao **không** làm điều này cho dự án học tập.

**Bài 4 — Từ console sang API.** Trên console, bạn đã: tạo group, tạo user, gắn policy, bật MFA (bài 00). Với mỗi thao tác, tìm trong CloudTrail tên API tương ứng (`eventName`) và tên lệnh CLI tương ứng trong [AWS CLI reference](https://docs.aws.amazon.com/cli/latest/reference/iam/). Giải thích vì sao quyền IAM được đặt tên theo đúng các API này.

**Bài 5 — Well-Architected review mini.** Với mỗi trụ cột, viết một rủi ro cụ thể của `taskhub` v2 và một cải tiến sẽ làm ở phiên bản nào (v3, v4, v5, v6, v1.0) theo [lộ trình dự án](../12-PRACTICAL-PROJECT/README.md#5-danh-sách-milestones).

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được cloud theo NIST và phân biệt IaaS/PaaS/SaaS bằng ví dụ của chính dự án.
- [ ] Vẽ được region → AZ → subnet → EC2 và nói rõ `taskhub` v2 là single-AZ có chủ đích.
- [ ] Phân chia trách nhiệm AWS/bạn cho EC2 và RDS không cần nhìn tài liệu.
- [ ] Đọc được một sự kiện CloudTrail và biết tìm ở region nào.
- [ ] Ước tính được chi phí tháng của v2 bằng Pricing Calculator cho hai kịch bản sử dụng.
- [ ] Ánh xạ được ít nhất 10 khái niệm từ laptop/on-premises sang AWS.

---

## Nguồn tham khảo

| Vai trò | Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|---|
| Chính | [NIST SP 800-145 — The NIST Definition of Cloud Computing](https://csrc.nist.gov/pubs/sp/800/145/final) | Định nghĩa cloud, 5 đặc tính, 3 mô hình dịch vụ, 4 mô hình triển khai | 2026-10-31 |
| Chính | [AWS Global Infrastructure — Regions and AZs](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/) | Số region/AZ, định nghĩa AZ, khoảng cách 100 km | 2026-10-31 |
| Chính | [AWS Shared Responsibility Model](https://aws.amazon.com/compliance/shared-responsibility-model/) | Security of / in the cloud, shared controls | 2026-10-31 |
| Chính | [AWS Well-Architected — The pillars of the framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html) | 6 trụ cột | 2026-10-31 |
| Bổ sung | [AZ IDs for your AWS resources](https://docs.aws.amazon.com/ram/latest/userguide/working-with-az-ids.html) | Ánh xạ ngẫu nhiên tên AZ, AZ ID | 2026-10-31 |
| Bổ sung | [CloudTrail event history](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html) | 90 ngày, miễn phí, management event | 2026-10-31 |
| Bổ sung | [AWS Pricing Calculator](https://calculator.aws/) | Ước tính chi phí trước khi tạo | 2026-10-31 |
| Bổ sung | AWS Skill Builder — *AWS Cloud Practitioner Essentials* ([skillbuilder.aws](https://skillbuilder.aws/)) | Khóa nền tảng miễn phí, học song song tuần 11 (xem [khảo sát nguồn](../00-ROADMAP/source-survey.md)) | 2026-10-31 |
