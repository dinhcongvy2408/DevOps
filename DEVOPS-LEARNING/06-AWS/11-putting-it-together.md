# 11. Ghép các dịch vụ thành hệ thống thật — kiến trúc taskhub v2/v3

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc (luồng request, luồng deploy, chuỗi tin cậy, phân tích sự cố, chi phí) · 🟨 Nên biết (khi hệ thống lớn lên) · 🟦 Nâng cao (ECS/EKS)
> Kiến thức cần có trước: toàn bộ bài 00–10 của module, đặc biệt [02. IAM](02-iam.md), [03. VPC](03-vpc-networking.md), [04. EC2](04-ec2.md), [10. CloudWatch](10-cloudwatch.md); [Module 05 bài 04 — Secrets & OIDC](../05-CICD/04-secrets-environments.md); dự án [v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) đã xong, [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md) đang làm hoặc đã xong
> Môi trường: `[WSL]` AWS CLI v2 (`export AWS_PROFILE=taskhub`) — **chỉ lệnh đọc** · `[AWS Console]` (Billing) · `[EC2]` qua SSM cho một bài diễn tập an toàn
> 💰 **Chi phí:** bài này **không tạo tài nguyên mới**. Mọi lệnh ở mục 7–9 là lệnh đọc (miễn phí). Bài diễn tập ở bước 4 chỉ dừng/khởi động lại một container.

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

- Vẽ và **kể lại bằng lời** kiến trúc taskhub v3 trên AWS: mạng, danh tính, máy chủ, dữ liệu, giám sát, triển khai.
- Đi theo **một request** từ trình duyệt tới PostgreSQL và ngược lại, nói được mỗi bước do dịch vụ nào, cấu hình nào quyết định.
- Đi theo **một lần deploy** từ lúc merge Pull Request tới lúc container mới chạy, và giải thích **chuỗi tin cậy**: GitHub OIDC → STS → IAM role → SSM → instance role → Parameter Store.
- Lập bảng **"nếu X chết thì sao"** cho từng thành phần: ảnh hưởng gì, phát hiện bằng gì, khôi phục thế nào — và chỉ ra **khoảng mù** của v3.
- Tính **chi phí tháng** của v3 từ đơn giá đã kiểm chứng, và ước lượng credit Free plan đủ dùng bao lâu.
- Rà soát bảo mật theo checklist, và giải thích kiến trúc sẽ thay đổi thế nào khi hệ thống lớn lên.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Học từng dịch vụ riêng lẻ (VPC, IAM, EC2…) giống học từng chi tiết của một chiếc xe. Đi làm, bạn phải **lái cả chiếc xe** và **biết nó hỏng ở đâu khi có tiếng kêu lạ**.

| Tình huống thật | Kiến thức trong bài |
|---|---|
| Phỏng vấn: "Hãy trình bày kiến trúc dự án của bạn" (gần như chắc chắn gặp) | Mục 4.1–4.5, mục 5 |
| Phỏng vấn: "Nếu database chết thì sao? Bạn phát hiện thế nào?" | Mục 4.7 |
| "Deploy lỗi AccessDenied" — lỗi nằm ở mắt xích nào trong 5 mắt xích quyền? | Mục 4.4 |
| Sếp hỏi: "Hệ thống này tốn bao nhiêu mỗi tháng?" | Mục 4.8 |
| "Lên production được chưa?" | Checklist bảo mật mục 4.9 |
| "Khi có 10.000 người dùng thì sao?" | Mục 4.10 |

Đây cũng là bài chuẩn bị trực tiếp cho [Checkpoint GĐ 6](checkpoint.md) và **Bài thi mốc 3 tháng**.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Sáu "lớp" của một hệ thống trên cloud

| Lớp | Câu hỏi | Dịch vụ trong taskhub |
|---|---|---|
| **Mạng** | Gói tin đi đường nào, ai được vào? | VPC, subnet, route table, IGW, security group |
| **Danh tính** | Ai/cái gì được làm gì? | IAM user (bạn), instance role, deploy role (OIDC) |
| **Tính toán** | Code chạy ở đâu? | EC2 `t3.small` + Docker Compose |
| **Dữ liệu** | Dữ liệu nằm đâu, sống sót qua sự cố nào? | PostgreSQL container + volume trên EBS; S3 (backup ở v5); Parameter Store (secret) |
| **Quan sát** | Biết hệ thống khỏe không bằng cách nào? | CloudWatch metrics, Logs, alarm, SNS; CloudTrail |
| **Phân phối** | Code mới đến server thế nào? | GitHub Actions → GHCR → SSM Run Command |

Khi gặp sự cố, việc đầu tiên là **xác định lớp**: "không vào được" thường là mạng hoặc tính toán; "AccessDenied" là danh tính; "dữ liệu mất" là dữ liệu.

### 3.2. Control plane và data plane

- **Data plane** (mặt phẳng dữ liệu): đường đi của **traffic người dùng** — request HTTP tới nginx, truy vấn SQL tới PostgreSQL.
- **Control plane** (mặt phẳng điều khiển): đường đi của **thao tác quản trị** — gọi API AWS, deploy, đổi cấu hình.

Hai mặt phẳng hỏng **độc lập** với nhau. GitHub Actions sập (control plane) → bạn không deploy được, nhưng **app vẫn phục vụ người dùng** bình thường (data plane). Ngược lại, security group bị sửa sai (data plane) → người dùng không vào được, nhưng bạn vẫn vào máy được qua SSM (control plane đi đường khác). Phân biệt được hai mặt phẳng giúp bạn khoanh vùng sự cố rất nhanh.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Kiến trúc tổng thể v3

```text
                                    ┌──────────────── GitHub ────────────────┐
  Developer ──git push / PR──────►  │ repo taskhub (public)                  │
                                    │  CI ─► GHCR ghcr.io/<user>/taskhub:sha7│
                                    │  Deploy (environment production)       │
                                    └───────┬────────────────────────────────┘
                                            │ ① OIDC token (JWT)
                                            ▼
 ┌─────────────────────────────── AWS account (Free plan) — ap-southeast-1 ───────────────────────────────┐
 │  IAM: OIDC provider token.actions.githubusercontent.com                                                │
 │       role taskhub-github-deploy ──② STS AssumeRoleWithWebIdentity → credential tạm thời               │
 │                                    ③ ssm:SendCommand (chỉ AWS-RunShellScript, chỉ instance tag taskhub)│
 │                                                                                                        │
 │  ┌──────────────────────── VPC taskhub-vpc 10.20.0.0/16 ─────────────────────────────┐                 │
 │  │ IGW taskhub-igw ◄──► route table taskhub-public-rt (0.0.0.0/0 → IGW)              │                 │
 │  │  ┌─ public-a 10.20.1.0/24 (1a) ─────────────────────────────────────────┐          │                 │
 │  │  │ SG taskhub-web-sg: vào 80/443 từ 0.0.0.0/0, KHÔNG có 22              │          │                 │
 │  │  │ EC2 taskhub-app t3.small, Ubuntu 24.04, gp3 20 GiB, IMDSv2           │          │                 │
 │  │  │   instance role taskhub-ec2-role ── ⑤ đọc /taskhub/dev/* (SSM PS)    │          │                 │
 │  │  │   SSM agent ◄─④ lệnh deploy (agent chủ động kết nối ra ngoài)        │          │                 │
 │  │  │   /opt/taskhub: docker compose                                       │          │                 │
 │  │  │     nginx :80 ──► taskhub :8080 ──► postgres :5432 (volume pgdata)   │          │                 │
 │  │  │                    └─ log driver awslogs ─► CloudWatch Logs           │          │                 │
 │  │  └──────────────────────────────────────────────────────────────────────┘          │                 │
 │  │  public-b, private-a, private-b: dự phòng cho lab tuần 14 (không có NAT Gateway)   │                 │
 │  └───────────────────────────────────────────────────────────────────────────────────┘                 │
 │  SSM Parameter Store /taskhub/dev/postgres-password (SecureString, standard tier)                      │
 │  S3 taskhub-backups-<account-id> (versioning, chặn public — dùng cho backup ở v5)                      │
 │  CloudWatch: /taskhub/dev/app (7 ngày) · alarm CPU + status check ─► SNS taskhub-alerts ─► email       │
 │  CloudTrail event history (90 ngày)                                                                    │
 └────────────────────────────────────────────────────────────────────────────────────────────────────────┘
        ▲
 Người dùng ── http://<public IP> (hoặc tên miền ở bài 09)
```

Đặc điểm cần nói được khi trình bày:

- **Một** EC2, **một** public IPv4, **không** NAT Gateway, **không** load balancer → rẻ, đơn giản, nhưng **không có dự phòng** (mục 4.7).
- **Không mở cổng 22.** Quản trị và deploy đều qua **SSM**: agent trên máy **chủ động kết nối ra** dịch vụ SSM qua HTTPS, nên không cần cổng vào nào.
- **Không có access key dài hạn ở đâu cả**: laptop dùng `aws login`, GitHub dùng OIDC, EC2 dùng instance role. Mọi credential đều **tạm thời**.
- **Secret duy nhất** (mật khẩu PostgreSQL) nằm ở Parameter Store, không nằm trong repo, image, user data hay GitHub.

### 4.2. 🟥 Luồng request (data plane)

Người dùng gọi `GET http://<public-ip>/api/tasks`:

| # | Chặng | Ai quyết định | Cấu hình liên quan | Học ở |
|---|---|---|---|---|
| 1 | (Nếu dùng tên miền) phân giải DNS | Route 53 / DNS provider | Record A → public IP | [Bài 09](09-route53.md) |
| 2 | Gói tin tới public IP của AWS | Internet → AWS edge | — | — |
| 3 | IGW dịch public IP → private IP `10.20.1.x` (NAT 1:1) | Internet Gateway | Instance có public IPv4 | [Bài 03](03-vpc-networking.md), [Networking 04](../02-NETWORKING/04-routing-nat-switching.md) |
| 4 | Vào subnet public-a | Route table | `0.0.0.0/0 → igw` gắn với subnet | Bài 03 |
| 5 | Qua **NACL** (mặc định cho phép hết) | NACL của subnet | Mặc định | Bài 03 |
| 6 | Qua **security group** — có rule cho cổng 80? | SG `taskhub-web-sg` | Inbound TCP 80 từ `0.0.0.0/0` | Bài 03, 04 |
| 7 | Tới ENI của instance, kernel chuyển vào Docker (DNAT cổng 80 → container nginx) | Linux + Docker | `ports: "80:80"` của nginx | [Docker 04](../04-DOCKER/04-volumes-networks-env.md) |
| 8 | nginx `proxy_pass` tới `taskhub:8080` qua DNS nội bộ Docker | nginx, Docker DNS | `default.conf`, network Compose | [Networking 07](../02-NETWORKING/07-load-balancing-reverse-proxy.md) |
| 9 | Spring Boot truy vấn `postgres:5432` | JDBC, Docker DNS | `SPRING_DATASOURCE_URL` | [v-pre tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md) |
| 10 | PostgreSQL đọc dữ liệu từ volume `pgdata` (nằm trên EBS gp3) | PostgreSQL, EBS | Named volume | [Docker 04](../04-DOCKER/04-volumes-networks-env.md) |

**Đường về:** security group là **stateful** — phản hồi của một kết nối đã được cho phép thì tự động được ra, không cần rule outbound riêng cho nó. NACL là **stateless** — nếu bạn từng sửa NACL, phải mở cả dải cổng tạm (ephemeral ports) chiều ra. Đây là câu hỏi phỏng vấn kinh điển.

### 4.3. 🟥 Luồng deploy (control plane, v3)

| # | Bước | Ai làm | Credential | Thất bại thì |
|---|---|---|---|---|
| 1 | Merge PR vào `main` | Bạn | GitHub account | — |
| 2 | Workflow `CI` build, test, quét, push `ghcr.io/<user>/taskhub:<sha7>` | GitHub Actions | `GITHUB_TOKEN` (`packages: write`) | Không có image → không deploy |
| 3 | Workflow `Deploy` chạy (`workflow_run` khi CI xanh), dừng chờ duyệt environment `production` | GitHub | — | Không ai duyệt → không deploy |
| 4 | Job xin **OIDC token** (JWT) từ GitHub, trong đó có `sub = repo:<user>/taskhub:environment:production` | Runner | `permissions: id-token: write` | Thiếu permission → không có token |
| 5 | `configure-aws-credentials` gọi **STS `AssumeRoleWithWebIdentity`** với token đó | AWS STS | Trust policy của `taskhub-github-deploy` kiểm tra `aud` và `sub` | `sub` không khớp → `AccessDenied` |
| 6 | `aws ssm send-command` chạy `AWS-RunShellScript` trên instance có tag `Project=taskhub` | AWS SSM | Credential tạm thời (1 giờ) của deploy role | Policy không cho → `AccessDenied` |
| 7 | **SSM agent** trên EC2 (đang giữ kết nối ra SSM) nhận lệnh, chạy `/opt/taskhub/scripts/deploy.sh <tag>` bằng root | EC2 | Instance role (để agent nói chuyện với SSM) | Agent offline → lệnh `Undeliverable`/hết hạn |
| 8 | `deploy.sh` đọc `/taskhub/dev/postgres-password` từ **Parameter Store** | EC2 | Instance role `taskhub-ec2-role` (`ssm:GetParameter`, `kms:Decrypt`) | `AccessDenied` → script dừng, giữ bản cũ |
| 9 | Sửa dòng `TASKHUB_IMAGE_TAG` trong `.env`, `docker compose pull taskhub && up -d --wait` | Docker trên EC2 | GHCR public → không cần token | Pull lỗi / health lỗi → script tự rollback về tag trước |
| 10 | Runner chờ kết quả lệnh SSM, rồi **smoke test** `curl -fsS --retry ... $APP_URL/actuator/health` | Runner | — | Smoke test đỏ → workflow đỏ, có người biết |

Lưu ý quan trọng về giới hạn của v3: `deploy.sh` **chỉ đổi image tag**. Nếu bạn sửa `compose.yaml` hay cấu hình nginx trong repo, EC2 **không tự cập nhật** — phải đồng bộ tay (ghi rõ trong runbook). Module 07 (Ansible, v4) giải quyết điểm này.

### 4.4. 🟥 Chuỗi tin cậy — "ai tin ai"

| Mắt xích | Bên chứng minh | Bên kiểm tra | Bằng chứng | Sống bao lâu | Phạm vi |
|---|---|---|---|---|---|
| Bạn → AWS (laptop) | IAM user `phuong-admin` + MFA | AWS Sign-in | `aws login` → credential tạm thời | Tự xoay vòng, phiên tối đa 12 giờ | Admin (chỉ bạn) |
| GitHub job → AWS | Job trong environment `production` | IAM OIDC provider + trust policy | JWT do GitHub ký (`aud`, `sub`) | Một lần dùng | Chỉ được assume `taskhub-github-deploy` |
| Deploy role → SSM | Credential tạm thời của role | IAM policy | Chữ ký request (SigV4) | ≤ 1 giờ | `SendCommand` một document, instance có tag |
| SSM → EC2 | Dịch vụ SSM | SSM agent (đã đăng ký bằng instance role) | Kênh do agent mở ra | Theo lệnh | Chạy lệnh bằng root trên máy |
| EC2 → Parameter Store, Logs, S3 | Instance role `taskhub-ec2-role` | IAM policy | Credential từ IMDSv2 (tự xoay vòng) | Vài giờ, tự làm mới | Chỉ `/taskhub/dev/*`, log group `/taskhub/dev/*`, bucket backup |

**Nhận xét quan trọng:**

1. Mắt xích **SSM → EC2** rất mạnh: ai gửi được `SendCommand` tới instance là có **root** trên máy. Vì vậy policy của deploy role phải giới hạn **cả document** (`AWS-RunShellScript`) **lẫn instance** (tag `Project=taskhub`), và trust policy phải ràng buộc `sub` tới **environment** `production` — không phải mọi nhánh, mọi workflow.
2. Lỗi `AccessDenied` khi deploy: đọc thông báo để biết **ai** bị từ chối (`assumed-role/taskhub-github-deploy/...` hay `assumed-role/taskhub-ec2-role/...`) → biết mắt xích nào hỏng (mục 12).
3. Không có mắt xích nào dùng **mật khẩu hay key dài hạn**. Đây là câu trả lời mạnh nhất cho câu hỏi phỏng vấn "bạn quản lý credential thế nào".

### 4.5. 🟥 Luồng quan sát

```text
Hypervisor ─► AWS/EC2 metrics (CPU 5 phút, status check 1 phút) ─► alarm ─► SNS ─► email
Container taskhub stdout ─► Docker daemon (awslogs, non-blocking) ─► /taskhub/dev/app (7 ngày)
Mọi lệnh gọi API AWS ─► CloudTrail event history (90 ngày)
Runner GitHub ─► smoke test /actuator/health sau mỗi deploy (chỉ lúc deploy)
```

Điều v3 **không** quan sát được (khoảng mù — ghi vào README): RAM, dung lượng đĩa, nginx/postgres log, **ứng dụng có trả lời người dùng không** giữa hai lần deploy (không có kiểm tra từ bên ngoài định kỳ), độ trễ request. Module 08 (v5) lấp các khoảng mù này.

### 4.6. 🟥 Dữ liệu sống sót qua những gì

| Sự kiện | Container tạo lại | Reboot | Stop → Start | Simplified auto recovery | **Terminate** | AZ gặp sự cố |
|---|---|---|---|---|---|---|
| Dữ liệu PostgreSQL (`pgdata` trên EBS root) | ✅ | ✅ | ✅ | ✅ | ❌ **mất** (root volume mặc định bị xóa khi terminate) | ❌ không truy cập được |
| `.env`, `/opt/taskhub` | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Public IPv4 tự gán | ✅ | ✅ | ❌ **đổi** | ✅ giữ | ❌ | — |
| Log trên CloudWatch | ✅ | ✅ | ✅ | ✅ | ✅ (theo retention) | ✅ |
| Secret ở Parameter Store | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Kết luận phải nói ra được:** ở v3, dữ liệu chỉ có **một bản** nằm trên **một ổ EBS** trong **một AZ**. Terminate nhầm instance = mất toàn bộ dữ liệu. Đó là lý do v5 có **backup `pg_dump` lên S3** và **diễn tập restore**, và vì sao trong lab tuần 14 bạn so sánh với **RDS** (backup tự động, Multi-AZ).

### 4.7. 🟥 Phân tích sự cố từng thành phần — "nếu X chết thì sao"

| Thành phần hỏng | Người dùng thấy gì | v3 phát hiện bằng gì | Khôi phục | Khoảng mù? |
|---|---|---|---|---|
| Container **nginx** chết | Không kết nối được cổng 80 | ❌ Không có gì tự động (EC2 vẫn khỏe) | `restart: unless-stopped` tự khởi động lại; nếu crash lặp → vào SSM xem log | **Có** — cần kiểm tra từ bên ngoài |
| Container **taskhub** chết/treo | `502`/`504` từ nginx | Log `ERROR` trên CloudWatch (nếu bạn đang xem); healthcheck Docker đánh dấu unhealthy | `restart` policy; rollback image | **Có** — chưa có alarm theo lỗi (bài tập bài 10) |
| **PostgreSQL** chết | `500`, health `DOWN` | Log `ERROR` của taskhub | `restart` policy; nếu dữ liệu hỏng → restore (v5) | **Có** |
| **Đĩa đầy** (image cũ, log, `pgdata`) | PostgreSQL ngừng ghi → `500` | ❌ Không có metric đĩa mặc định | Xóa image cũ (`docker image prune`), tăng EBS | **Có** — cần CloudWatch agent / node-exporter |
| **EC2 treo** (kernel, hết RAM) | Mất kết nối | Alarm `taskhub-status-check` (instance check) → email | Reboot/stop-start bằng tay (stop-start đổi IP!) | Không |
| **Host AWS hỏng** | Mất kết nối vài phút | System status check → alarm + simplified auto recovery | Tự động, giữ IP | Không |
| **AZ ap-southeast-1a** sự cố | Mất dịch vụ | Status check / AWS Health Dashboard | Chờ AWS; hoặc dựng lại ở AZ khác (cần backup + IaC ở v4/v5) | Không phát hiện được gì hơn — vấn đề là **không có dự phòng** |
| **Security group bị sửa** (mất rule 80) | Timeout | ❌ EC2 vẫn khỏe; CloudTrail ghi `RevokeSecurityGroupIngress` | Thêm lại rule; tìm ai sửa qua CloudTrail | **Có** |
| **Instance role bị gỡ / thiếu quyền** | Ban đầu không thấy gì; deploy sau thất bại; **container không start được** vì log driver lỗi | Deploy đỏ; `AccessDenied` trong log | Gắn lại role / sửa policy | Một phần |
| **SSM agent** ngừng | Người dùng không thấy gì | Deploy đỏ (`Undeliverable`); không vào được Session Manager | Reboot instance (agent tự khởi động) | Không — deploy báo ngay |
| **GitHub Actions / GHCR** sập | **Không thấy gì** — app vẫn chạy | Workflow đỏ | Chờ; `deploy.sh` giữ bản cũ nếu pull lỗi | Không (control plane) |
| **Parameter Store** không đọc được | Không thấy gì (container đang chạy đã có mật khẩu) | Deploy đỏ | Sửa quyền/region | Không |
| **Credit Free plan cạn / hết 6 tháng** | **Tài khoản bị đóng, mọi thứ dừng** | Billing console, AWS Budget alert (bài 00) | Nâng lên Paid plan trong 90 ngày | Theo dõi định kỳ là bắt buộc |

Tổng kết: v3 có **nhiều khoảng mù ở tầng ứng dụng** (nginx, taskhub, postgres, đĩa) vì chỉ giám sát tầng **máy ảo**. Nói thẳng điều này khi phỏng vấn — nhận ra giới hạn của hệ thống mình là dấu hiệu hiểu bài, không phải điểm trừ.

### 4.8. 🟥 Chi phí v3

**Đơn giá** (Singapore, On-Demand Linux, kiểm tra 2026-10-31 từ dữ liệu giá công khai của AWS — xem Nguồn tham khảo):

| Hạng mục | Đơn giá |
|---|---|
| EC2 `t3.small` | 0,0264 USD/giờ |
| EBS gp3 | 0,096 USD/GB-tháng |
| Public IPv4 (đang dùng hoặc idle) | 0,005 USD/giờ |
| S3 Standard (50 TB đầu) | 0,025 USD/GB-tháng |
| CloudWatch, SNS | Trong mức miễn phí (bài 10) |
| SSM Session Manager, Run Command trên EC2, Parameter Store standard | Không tính thêm phí |
| Dữ liệu ra Internet | 100 GB đầu mỗi tháng miễn phí (gộp mọi dịch vụ, mọi region) |
| Route 53 (tùy chọn) | 0,50 USD/hosted zone/tháng |

**Kịch bản A — chạy 24/7 (730 giờ/tháng):**

| Hạng mục | Tính | USD/tháng |
|---|---|---|
| `t3.small` | 0,0264 × 730 | 19,27 |
| Public IPv4 | 0,005 × 730 | 3,65 |
| EBS gp3 20 GiB | 0,096 × 20 | 1,92 |
| S3 (~1 GB backup ở v5) | 0,025 × 1 | 0,03 |
| CloudWatch, SNS, SSM, data transfer | Miễn phí trong hạn mức | 0,00 |
| **Tổng** | | **≈ 24,87** |

**Kịch bản B — chỉ bật khi học** (~18 giờ/tuần ≈ 78 giờ/tháng; stop khi không học):

| Hạng mục | Tính | USD/tháng |
|---|---|---|
| `t3.small` | 0,0264 × 78 | 2,06 |
| Public IPv4 tự gán (được trả lại khi stop → không tính lúc stop) | 0,005 × 78 | 0,39 |
| EBS gp3 20 GiB (**tính cả khi stop**) | 0,096 × 20 | 1,92 |
| S3 | | 0,03 |
| **Tổng** | | **≈ 4,40** |

**Credit Free plan đủ bao lâu?** (100 USD credit đăng ký; có thể thêm tới 100 USD khi hoàn thành hoạt động)

| | Chỉ 100 USD | Đủ 200 USD |
|---|---|---|
| Kịch bản A (24/7) | ≈ 4 tháng → **tài khoản đóng trước hạn 6 tháng** | ≈ 8 tháng → bị giới hạn bởi mốc **6 tháng** |
| Kịch bản B (khi học) | ≈ 22 tháng → giới hạn bởi mốc 6 tháng (tổng tiêu ≈ 26 USD) | Như trên |

Tức là: **chạy 24/7 với chỉ 100 USD credit có thể làm tài khoản bị đóng trước khi bạn kịp phỏng vấn**. Đó là lý do lộ trình chọn kịch bản B, và từ v4 dùng `terraform destroy`/`apply` để tắt/bật toàn bộ.

**Chi phí ẩn hay gặp** (đối chiếu lại hằng tuần trong Billing):

- Elastic IP để **idle** (instance stop) vẫn tính 0,005 USD/giờ.
- Log group "Never expire" ([bài 10](10-cloudwatch.md)).
- NAT Gateway quên xóa sau lab tuần 14 (≈ 0,045 USD/giờ + dữ liệu).
- Hosted zone thử nghiệm quên xóa (0,50 USD/tháng).
- Snapshot EBS, AMI tự tạo không dùng nữa.
- `t3` unlimited chạy tải cao kéo dài (surplus credit).
- ALB, RDS của lab tuần 14 không xóa ([bài 07](07-rds.md), [bài 08](08-elb-autoscaling.md)).

### 4.9. 🟥 Checklist rà soát bảo mật v3

| Nhóm | Kiểm tra | Cách kiểm chứng |
|---|---|---|
| Tài khoản | Root có MFA, không có access key; Budget alert đã bật | IAM console → Security recommendations; Billing → Budgets |
| IAM | Không có access key dài hạn cho người; user admin có MFA | `aws iam list-access-keys --user-name phuong-admin` trả rỗng |
| IAM | Instance role chỉ có `AmazonSSMManagedInstanceCore` + `taskhub-ec2-app` (giới hạn theo ARN) | `aws iam list-attached-role-policies`, `get-role-policy` |
| IAM | Trust policy deploy role ràng buộc `aud` **và** `sub` tới environment `production` | `aws iam get-role --role-name taskhub-github-deploy --query Role.AssumeRolePolicyDocument` |
| Mạng | SG chỉ mở 80 (443 nếu dùng TLS); **không** có 22; không có rule `0.0.0.0/0` cho cổng khác | `aws ec2 describe-security-groups` |
| Mạng | PostgreSQL **không** publish cổng ra host | `docker compose ps` trên EC2: chỉ nginx có `0.0.0.0:80->80` |
| Máy chủ | IMDSv2 bắt buộc (`HttpTokens=required`); EBS mã hóa | `describe-instances --query '...MetadataOptions'`, `describe-volumes --query '...Encrypted'` |
| Máy chủ | Hệ điều hành được cập nhật bảo mật | `[EC2] apt list --upgradable` |
| Container | App chạy non-root; image được quét trong CI | [Docker 07](../04-DOCKER/07-docker-security.md), [Module 05](../05-CICD/README.md) |
| Secret | Mật khẩu DB ở Parameter Store SecureString; không có trong repo/image/user data/GitHub | `git grep`, `aws ec2 describe-instance-attribute --attribute userData` |
| S3 | Block Public Access bật; versioning bật; mã hóa mặc định | `aws s3api get-public-access-block`, `get-bucket-versioning` |
| Pipeline | Action ghim SHA; environment `production` có người duyệt; `permissions` tối thiểu | [Module 05 bài 04](../05-CICD/04-secrets-environments.md) |
| Quan sát | Log group có retention; alarm có SNS đã xác nhận; biết xem CloudTrail | Bài 10 |

### 4.10. 🟨 Khi hệ thống lớn lên — kiến trúc sẽ đổi thế nào

| Vấn đề của v3 | Giải pháp ở quy mô lớn hơn | Đổi lại | Gặp ở |
|---|---|---|---|
| Một EC2 = một điểm chết | **ALB + Auto Scaling Group** trải trên 2 AZ | ALB tính theo giờ + LCU; app phải **stateless** | Lab tuần 14 ([bài 08](08-elb-autoscaling.md)) |
| PostgreSQL tự chạy, một bản | **RDS** (backup tự động, Multi-AZ, vá tự động) | Đắt hơn nhiều so với container; ít quyền kiểm soát | Lab tuần 14 ([bài 07](07-rds.md)) |
| App ở subnet public | App + DB ở **private subnet**, chỉ ALB ở public; ra Internet qua **NAT Gateway** hoặc **VPC endpoint** | NAT ≈ 0,045 USD/giờ mỗi AZ + phí dữ liệu | Bài 03 (lý thuyết), lab tuần 14 |
| Deploy bằng SSM + Compose, cấu hình đồng bộ tay | **ECS** (Fargate) chạy container, tự rolling update | Học thêm khái niệm task/service; phí Fargate theo vCPU/GB | 🟦 Sau khi đi làm |
| Nhiều service, nhiều team | **EKS** (Kubernetes) | Phí control plane, độ phức tạp cao | Module 09 dùng Kubernetes **local** (v6), không dùng EKS vì chi phí |
| Hạ tầng tạo bằng tay | **Terraform** | Phải học IaC | Module 07 (v4) |
| Giám sát tầng máy ảo | Prometheus, Grafana, Loki, alert theo ứng dụng | Thêm thành phần phải vận hành | Module 08 (v5) |

**Vì sao taskhub vẫn dùng kiến trúc đơn giản?** Vì mục tiêu là **học được nền tảng với chi phí gần 0**, và v3 đã thể hiện đủ các nguyên tắc quan trọng: quyền tối thiểu, không key dài hạn, không cổng SSH, secret ngoài code, deploy tự động có duyệt, giám sát và cảnh báo cơ bản. Biết **khi nào** cần ALB/RDS/ECS và **tại sao chưa cần** là câu trả lời của một người hiểu kiến trúc, không phải người chỉ chép mẫu.

### 4.11. Gặp lại ở đâu

| Kiến thức | Gặp lại |
|---|---|
| Sơ đồ kiến trúc v3 | `docs/architecture.md` của repo; README dự án ([Module 12](../12-PRACTICAL-PROJECT/README.md)) |
| Bảng "nếu X chết thì sao" | Checkpoint GĐ 6; Module 08 (alert lấp khoảng mù); diễn tập sự cố tuần 18, 22 |
| Bảng chi phí | `cost-control.md` của dự án; Module 07 (`terraform destroy` để về kịch bản B) |
| Checklist bảo mật | Module 10 (rà soát toàn dự án ở v1.0) |
| ADR | Module 12 — tối thiểu 3 ADR cho CV |

---

## 5. Ví dụ thực tế

**Câu trả lời mẫu cho "Hãy trình bày kiến trúc dự án của bạn" (khoảng 2 phút):**

> "taskhub là REST API Spring Boot với PostgreSQL. Trên AWS, nó chạy trên một EC2 `t3.small` trong VPC em tự thiết kế, ở subnet public, chỉ mở cổng 80 — không mở SSH; em quản trị qua SSM Session Manager. Trong máy, Docker Compose chạy ba container: nginx làm reverse proxy, ứng dụng, và PostgreSQL với volume trên EBS.
>
> Khi em merge Pull Request, GitHub Actions build, test, quét image bằng Trivy rồi đẩy lên GHCR với tag là SHA commit. Workflow deploy chờ em duyệt, rồi lấy quyền AWS **tạm thời** qua OIDC — không lưu access key nào — và gửi lệnh qua SSM Run Command để máy chủ kéo image mới. Script deploy lấy mật khẩu database từ Parameter Store, kiểm tra health, và tự quay về bản cũ nếu bản mới lỗi.
>
> Log ứng dụng đi lên CloudWatch Logs, giữ 7 ngày; có alarm CPU và status check gửi email qua SNS. Chi phí khoảng 25 USD/tháng nếu chạy liên tục, em chỉ bật khi cần nên khoảng 4–5 USD.
>
> Hạn chế em biết: chỉ một instance nên không có dự phòng; dữ liệu chỉ một bản trên một ổ EBS — v5 em thêm backup lên S3 và đã diễn tập restore; và em chưa giám sát được tầng ứng dụng, phần đó em làm với Prometheus và Grafana ở bản sau. Nếu cần chịu tải lớn hơn, em sẽ chuyển sang ALB với Auto Scaling trên hai AZ và RDS Multi-AZ."

Chú ý cấu trúc: **cái gì → chạy thế nào → deploy thế nào → giám sát thế nào → tốn bao nhiêu → hạn chế và hướng mở rộng**. Phần "hạn chế" thường là thứ để lại ấn tượng tốt nhất.

---

## 6. Sơ đồ kiến trúc

Sơ đồ tổng thể ở mục 4.1. Dưới đây là hai sơ đồ bổ sung thường được hỏi.

### 6.1. Chuỗi tin cậy của một lần deploy

```text
 GitHub job (environment: production)
   │  JWT: iss=token.actions.githubusercontent.com
   │       aud=sts.amazonaws.com
   │       sub=repo:<user>/taskhub:environment:production
   ▼
 AWS STS ── kiểm tra trust policy của taskhub-github-deploy ──► credential tạm thời (≤ 1 giờ)
   ▼
 SSM SendCommand (document AWS-RunShellScript, target tag Project=taskhub)
   ▼
 SSM agent trên EC2 (kết nối RA ngoài, xác thực bằng instance role)
   ▼
 deploy.sh (root) ── instance role taskhub-ec2-role ──► Parameter Store /taskhub/dev/postgres-password
   ▼
 docker compose pull/up ── GHCR (public, không cần token) ──► health OK → xong / lỗi → rollback
```

### 6.2. Hai mặt phẳng

```text
 DATA PLANE  (người dùng)                       CONTROL PLANE  (quản trị, deploy)
 ───────────────────────                        ────────────────────────────────
 Browser → IGW → SG:80 → nginx → app → DB       Laptop (aws login) ─┐
                                                GitHub (OIDC) ──────┼─► AWS API (IAM, EC2, SSM…)
 Hỏng ở đây: người dùng thấy ngay               SSM agent ◄─────────┘   Hỏng ở đây: không deploy/
                                                                        không quản trị được, app vẫn chạy
```

---

## 7. Các câu lệnh cần biết

Toàn bộ là lệnh **đọc** (miễn phí), dùng để **kiểm kê** hệ thống đang chạy:

| Lệnh | Trả lời câu hỏi |
|---|---|
| `aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=taskhub` | Tôi đang có những tài nguyên nào gắn tag dự án? |
| `aws ec2 describe-instances --filters Name=tag:Project,Values=taskhub` | Instance nào, trạng thái, IP, role, IMDS? |
| `aws ec2 describe-security-groups --group-names taskhub-web-sg` | Đang mở cổng nào cho ai? |
| `aws ec2 describe-route-tables --filters Name=tag:Project,Values=taskhub` | Subnet nào ra được Internet? |
| `aws ec2 describe-addresses` | Có Elastic IP nào (đang tính tiền) không? |
| `aws ssm describe-instance-information` | SSM agent có online không? |
| `aws ssm list-command-invocations --details --max-items 5` | Mấy lần deploy gần nhất thành công không? |
| `aws iam get-role --role-name <role>` | Trust policy là gì? |
| `aws logs describe-log-groups` | Log group nào, retention bao nhiêu? |
| `aws cloudwatch describe-alarms` | Alarm nào, trạng thái gì? |
| `aws s3api get-public-access-block --bucket <bucket>` | Bucket có bị lộ public không? |
| `aws cloudtrail lookup-events` | Ai đã thay đổi gì gần đây? |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. Kiểm kê theo tag

```bash
export AWS_PROFILE=taskhub
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=taskhub \
  --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n'
```

Đầu ra minh họa (rút gọn):

```text
arn:aws:ec2:ap-southeast-1:111122223333:instance/i-0abc1234def567890
arn:aws:ec2:ap-southeast-1:111122223333:vpc/vpc-0123456789abcdef0
arn:aws:ec2:ap-southeast-1:111122223333:security-group/sg-0123456789abcdef0
arn:aws:ec2:ap-southeast-1:111122223333:subnet/subnet-0aaa...
arn:aws:logs:ap-southeast-1:111122223333:log-group:/taskhub/dev/app
arn:aws:sns:ap-southeast-1:111122223333:taskhub-alerts
arn:aws:cloudwatch:ap-southeast-1:111122223333:alarm:taskhub-cpu-high
```

- Lệnh này chỉ thấy tài nguyên **có tag** và **trong region hiện tại**. Tài nguyên quên gắn tag sẽ "vô hình" — đó là lý do quy ước gắn tag ở mọi thứ.
- IAM role là tài nguyên toàn cầu, có thể không hiện ở đây; kiểm tra riêng bằng `aws iam`.

### 8.2. Một dòng mô tả instance

```bash
aws ec2 describe-instances --filters Name=tag:Project,Values=taskhub \
  --query 'Reservations[].Instances[].{id:InstanceId,state:State.Name,type:InstanceType,ip:PublicIpAddress,az:Placement.AvailabilityZone,role:IamInstanceProfile.Arn,imds:MetadataOptions.HttpTokens}' \
  --output table
```

```text
--------------------------------------------------------------------------------------------------------------
|                                              DescribeInstances                                             |
+-----------------+------------------------+-----------+--------------+-----------+----------+---------------+
|       az        |          id            |   imds    |     ip       |  role     |  state   |     type      |
+-----------------+------------------------+-----------+--------------+-----------+----------+---------------+
|  ap-southeast-1a|  i-0abc1234def567890   |  required |  203.0.113.10|  arn:...  |  running |  t3.small     |
+-----------------+------------------------+-----------+--------------+-----------+----------+---------------+
```

`imds = required` nghĩa là IMDSv2 bắt buộc. `role` rỗng → không có instance role → SSM, log, Parameter Store đều hỏng.

### 8.3. SSM agent và lịch sử deploy

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].[InstanceId,PingStatus,AgentVersion,PlatformName]' --output table
aws ssm list-command-invocations --details --max-items 5 \
  --query 'CommandInvocations[].[RequestedDateTime,Status,CommandPlugins[0].ResponseCode]' --output table
```

- `PingStatus = Online` → agent đang kết nối. `ConnectionLost` → deploy sẽ thất bại.
- `Status = Success` và `ResponseCode = 0` → `deploy.sh` thoát mã 0. Mã khác 0 → đọc `StandardOutputContent` của lần đó (bằng `get-command-invocation`).

### 8.4. Rule security group dạng dễ đọc

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=taskhub-web-sg \
  --query 'SecurityGroups[].IpPermissions[].{proto:IpProtocol,from:FromPort,to:ToPort,cidr:IpRanges[].CidrIp}' --output json
```

Mong đợi: chỉ cổng 80 (và 443 nếu đã bật TLS) với `0.0.0.0/0`. Thấy cổng 22 → đó là rule tạm từ bài 04 bạn **quên xóa**.

---

## 9. Bài thực hành từng bước

> 💰 Không tạo tài nguyên. Lệnh đọc miễn phí. Bước 4 chỉ dừng một container vài phút.
> **Điều kiện:** v2 đang chạy; v3 đã có hoặc đang làm (nếu chưa có v3, bỏ qua các dòng liên quan tới deploy role/OIDC và đánh dấu "chưa có").
> Đầu ra của bài: thư mục `docs/` trong repo `taskhub` được cập nhật qua một Pull Request (`docs/aws-architecture-review`).

### Bước 1 — Script kiểm kê `[WSL]`

Tạo `scripts/aws-inventory.sh` trong repo `taskhub`:

```bash
#!/usr/bin/env bash
# Kiểm kê tài nguyên AWS của taskhub. Chỉ dùng lệnh đọc.
set -euo pipefail

: "${AWS_PROFILE:?Đặt AWS_PROFILE (ví dụ: export AWS_PROFILE=taskhub)}"
region="$(aws configure get region)"

echo "# Kiểm kê taskhub — $(date -u +%Y-%m-%dT%H:%MZ) — region ${region}"
echo
echo "## Tài khoản"
aws sts get-caller-identity --query '[Account,Arn]' --output text
echo
echo "## Tài nguyên có tag Project=taskhub"
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=taskhub \
  --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n'
echo
echo "## EC2"
aws ec2 describe-instances --filters Name=tag:Project,Values=taskhub \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,PublicIpAddress,MetadataOptions.HttpTokens]' \
  --output text
echo
echo "## Security group taskhub-web-sg (inbound)"
aws ec2 describe-security-groups --filters Name=group-name,Values=taskhub-web-sg \
  --query 'SecurityGroups[].IpPermissions[].[IpProtocol,FromPort,ToPort,join(`,`,IpRanges[].CidrIp)]' \
  --output text
echo
echo "## Elastic IP (tính tiền cả khi idle)"
aws ec2 describe-addresses --query 'Addresses[].[PublicIp,InstanceId]' --output text
echo
echo "## SSM agent"
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].[InstanceId,PingStatus,AgentVersion]' --output text
echo
echo "## Log group (retention trống = Never expire)"
aws logs describe-log-groups --query 'logGroups[].[logGroupName,retentionInDays]' --output text
echo
echo "## Alarm"
aws cloudwatch describe-alarms --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
```

Chạy và lưu kết quả **ngoài repo** (có thể chứa ID tài khoản, IP):

```bash
chmod +x scripts/aws-inventory.sh
./scripts/aws-inventory.sh > ~/devops-lab/06-aws/inventory-$(date +%F).md
less ~/devops-lab/06-aws/inventory-$(date +%F).md
```

❓ Có tài nguyên nào bạn **không ngờ** là còn tồn tại? Có tài nguyên nào **thiếu tag**? (So danh sách với những gì bạn nhớ đã tạo ở bài 03–10.)

### Bước 2 — Vẽ sơ đồ khớp với hệ thống thật

Trong repo, cập nhật `docs/architecture.md` thêm mục "v2/v3 — AWS". Sơ đồ phải:

- Dùng **giá trị thật** của bạn: CIDR VPC/subnet theo `docs/network-plan.md`, AZ, loại instance, tên log group. (Không đưa account ID, IP public vào repo public — dùng `<account-id>`, `<public-ip>`.)
- Có cả **luồng request** và **luồng deploy**.
- Ghi rõ **khoảng mù** (mục 4.5).

Đối chiếu từng hộp trong sơ đồ với một dòng trong file kiểm kê. Hộp nào không có dòng tương ứng = sơ đồ đang vẽ thứ không tồn tại → sửa sơ đồ hoặc tạo tài nguyên còn thiếu (theo milestone).

### Bước 3 — Bảng "nếu X chết thì sao" của riêng bạn

Tạo `docs/failure-analysis.md`: chép bảng mục 4.7, rồi **điều chỉnh theo hệ thống thật của bạn** (ví dụ: bạn đã làm bài tập metric filter ở bài 10 → taskhub chết đã có alarm → bỏ "khoảng mù" ở dòng đó). Thêm cột "Đã diễn tập?".

### Bước 4 — Diễn tập an toàn: container taskhub chết `[EC2]` + `[WSL]`

1. Ở `[WSL]`, mở một cửa sổ đo:

   ```bash
   APP_URL="http://<public-ip>"
   while true; do printf '%s ' "$(date +%T)"; curl -s -o /dev/null -m 3 -w '%{http_code}\n' "$APP_URL/actuator/health"; sleep 2; done
   ```

2. Ở `[EC2]` (phiên SSM), dừng hẳn container (dừng thủ công thì restart policy **không** tự bật lại — [Docker 02](../04-DOCKER/02-images-containers.md)):

   ```bash
   cd /opt/taskhub && sudo docker compose stop taskhub
   ```

3. Quan sát: cửa sổ đo chuyển sang `502` (nginx còn sống, upstream chết). Mở CloudWatch → alarm nào đổi trạng thái? (Đáp án mong đợi: **không alarm nào** — chứng minh khoảng mù.) Log group có dòng gì?
4. Khôi phục: `sudo docker compose start taskhub`, đo thời gian tới khi lại `200`.
5. Ghi vào `docs/failure-analysis.md`: thời gian phát hiện (nếu bạn không nhìn màn hình thì là **vô hạn**), thời gian khôi phục, bài học.

### Bước 5 — Đối chiếu chi phí `[AWS Console]`

1. **Billing and Cost Management** → xem chi phí tháng này theo dịch vụ và số **credit** còn lại của Free plan.
2. So với bảng mục 4.8 theo số giờ instance **thực tế** đã chạy (`describe-instances` không cho số giờ — dùng trang Billing/Cost Explorer trong console).
3. Ghi chênh lệch và lý do vào `docs/cost.md` (hoặc `cost-control.md` theo cấu trúc dự án). Dịch vụ nào xuất hiện mà bạn không dự tính?

### Bước 6 — Rà soát bảo mật

Đi hết checklist mục 4.9, mỗi dòng ghi ✅/❌ kèm lệnh đã dùng để kiểm chứng. Dòng ❌ → tạo issue GitHub để sửa (ví dụ "Xóa rule tạm cổng 22").

### Bước 7 — Viết ADR

Repo đã có (hoặc sẽ có) ADR-0001 (chọn GitHub Actions — ví dụ ở [Module 12 §7](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr)), ADR-0002 (quy trình Git), ADR-0003 (scan-before-push, v1). Viết **ít nhất hai** trong ba ADR sau, theo mẫu ở Module 12:

- `docs/adr/0004-single-ec2-docker-compose.md` (đã viết ở v2 — bổ sung phần so sánh với ECS)
- `docs/adr/0005-no-nat-gateway.md`
- `docs/adr/0006-postgresql-container-instead-of-rds.md`

Mỗi ADR phải có **con số** (chi phí, thời gian) và **hệ quả tiêu cực** trung thực (ví dụ ADR-0006: "dữ liệu chỉ một bản cho tới v5").

### Bước 8 — Luyện trình bày

Tự ghi âm (điện thoại) phần trình bày kiến trúc **dưới 3 phút** theo cấu trúc ở mục 5, bằng lời của bạn và số liệu của bạn. Nghe lại: có chỗ nào bạn nói "hình như", "chắc là"? Đó là chỗ cần học lại.

### Bước 9 — Mở Pull Request

Nhánh `docs/aws-architecture-review` gồm: `scripts/aws-inventory.sh`, `docs/architecture.md`, `docs/failure-analysis.md`, file chi phí, các ADR. **Không** commit file kết quả kiểm kê. Merge qua PR như mọi thay đổi khác.

---

## 10. Kết quả mong đợi

- `scripts/aws-inventory.sh` chạy được, chỉ dùng lệnh đọc, in đủ các mục.
- `docs/architecture.md` có sơ đồ v2/v3 khớp **từng hộp** với kết quả kiểm kê; có luồng request, luồng deploy, khoảng mù.
- `docs/failure-analysis.md` có ít nhất 10 dòng và kết quả diễn tập bước 4 (thời gian khôi phục, không có alarm nào kêu).
- Chi phí thực tế được ghi lại, chênh lệch so với ước tính được giải thích.
- Checklist bảo mật đi hết; mọi dòng ❌ có issue.
- Ít nhất 2 ADR mới (0004+), có số liệu và hệ quả tiêu cực.
- Trình bày được kiến trúc trong 3 phút không cần nhìn tài liệu.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách kiểm tra | Cách sửa |
|---|---|---|---|
| `get-resources` trả về ít hơn thực tế | Tài nguyên thiếu tag, hoặc ở region khác | Console → **Tag Editor** tìm theo mọi region; EC2 Global View | Gắn tag; xóa tài nguyên lạc region |
| Script kiểm kê lỗi `ExpiredToken` | Phiên `aws login` hết hạn | `aws sts get-caller-identity` | `aws login --profile taskhub` lại |
| Sơ đồ có hộp không tồn tại trong kiểm kê | Vẽ theo "dự định" thay vì "thực tế" | Đối chiếu bước 2 | Sửa sơ đồ — quy tắc vàng của Module 12: không vẽ thứ không có |
| Billing có chi phí lạ ở region khác | Tạo nhầm tài nguyên khi console đang ở region khác | Billing → theo region; EC2 Global View | Xóa; luôn kiểm tra góc trên phải console |
| Diễn tập bước 4: container tự bật lại ngay | Dùng `docker kill`/process crash thay vì `stop` → restart policy kích hoạt | `docker inspect ... RestartCount` | Đúng — đó là restart policy hoạt động; muốn mô phỏng "chết hẳn" thì dùng `stop` |
| Trình bày bị lẫn lộn chi tiết | Nhảy giữa các lớp | — | Dùng cấu trúc cố định ở mục 5 |
| Lỡ commit file kiểm kê có account ID / IP | Không thêm vào `.gitignore` | `git log --stat` | Gỡ file, coi như thông tin đã công khai; account ID không phải secret nhưng không nên phô ra |

---

## 12. Đọc log và xử lý lỗi

Bài này là nơi gộp các kỹ năng đọc lỗi của cả module. Với một lỗi bất kỳ của taskhub trên AWS, quy trình là:

```text
1. Lớp nào?        Người dùng thấy gì (timeout / 502 / 500 / AccessDenied)? → mục 3.1
2. Mặt phẳng nào?  Người dùng bị ảnh hưởng (data) hay chỉ deploy/quản trị (control)? → mục 3.2
3. Mắt xích nào?   Với AccessDenied: đọc ARN "User: arn:aws:sts::...:assumed-role/<ROLE>/..." → mục 4.4
4. Bằng chứng:     CloudWatch Logs (app), describe-alarm-history (khi nào), CloudTrail (ai đổi gì),
                   SSM get-command-invocation (deploy in gì), docker compose logs (trong máy)
5. Ghi lại:        nhật ký debug + cập nhật docs/failure-analysis.md nếu là loại lỗi mới
```

**Bảng tra nhanh theo triệu chứng:**

| Triệu chứng | Lớp | Xem đầu tiên |
|---|---|---|
| `curl` timeout tới public IP | Mạng / máy | Instance running? Public IP còn đúng? SG có cổng 80? Route table có IGW? |
| `502 Bad Gateway` | Ứng dụng (nginx sống, app chết) | `docker compose ps`, log `/taskhub/dev/app` |
| `500` từ API | Ứng dụng / dữ liệu | Log `ERROR`, health `/actuator/health` (DB `DOWN`?) |
| Deploy: `AccessDenied` với `taskhub-github-deploy` | Danh tính (GitHub → AWS) | Trust policy `sub`, policy `ssm:SendCommand` |
| Deploy: `AccessDenied` với `taskhub-ec2-role` | Danh tính (EC2 → dịch vụ) | Policy `taskhub-ec2-app` |
| Deploy: lệnh SSM `Undeliverable` / `TimedOut` | Control plane | `describe-instance-information` (agent Online?) |
| Không nhận email cảnh báo | Quan sát | Subscription đã xác nhận? Alarm có action? |

Ví dụ đọc lỗi trong log deploy của GitHub Actions (minh họa):

```text
An error occurred (AccessDeniedException) when calling the SendCommand operation:
User: arn:aws:sts::111122223333:assumed-role/taskhub-github-deploy/GitHubActions
is not authorized to perform: ssm:SendCommand on resource:
arn:aws:ec2:ap-southeast-1:111122223333:instance/i-0abc1234def567890
because no identity-based policy allows the ssm:SendCommand action
```

Đọc: OIDC + STS đã **thành công** (đã có `assumed-role/taskhub-github-deploy`) → mắt xích 1–2 ổn. Thiếu quyền ở mắt xích 3, trên **resource là instance** → kiểm tra điều kiện tag của policy (instance có tag `Project=taskhub` không? policy có `Condition` đúng khóa `ssm:resourceTag/Project` không?).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Kể 6 lớp của hệ thống taskhub trên AWS và dịch vụ tương ứng với mỗi lớp.
2. Data plane và control plane khác nhau thế nào? Cho một sự cố chỉ ảnh hưởng control plane.
3. Đi theo một request `GET /api/tasks` từ trình duyệt tới PostgreSQL: liệt kê ít nhất 8 chặng và cấu hình quyết định mỗi chặng.
4. Vì sao phản hồi HTTP đi ra được dù security group không có rule outbound riêng cho nó? NACL khác gì?
5. Vì sao taskhub không cần mở cổng 22 mà vẫn quản trị và deploy được?
6. Mô tả chuỗi tin cậy của một lần deploy v3. Mắt xích nào mạnh nhất và được giới hạn bằng gì?
7. Trust policy của deploy role kiểm tra những gì trong OIDC token? Nếu chỉ kiểm tra `aud` mà không kiểm tra `sub` thì nguy hiểm thế nào?
8. Deploy báo `AccessDenied`. Làm sao biết lỗi ở mắt xích GitHub → AWS hay EC2 → Parameter Store?
9. Dữ liệu PostgreSQL sống sót qua những sự kiện nào? Sự kiện nào làm mất dữ liệu ở v3?
10. Nêu 4 khoảng mù giám sát của v3 và thành phần nào trong lộ trình sẽ lấp chúng.
11. GitHub Actions sập trong 2 giờ. Người dùng taskhub bị ảnh hưởng gì?
12. Tính chi phí tháng của v3 khi chạy 24/7. Thành phần nào chiếm nhiều nhất?
13. Vì sao chạy 24/7 có thể làm tài khoản Free plan bị đóng trước mốc 6 tháng?
14. Nêu 5 chi phí ẩn hay gặp trên AWS.
15. Khi taskhub cần chịu tải gấp 100 lần và không được ngừng khi một AZ sự cố, kiến trúc cần thay đổi những gì? Mỗi thay đổi tốn thêm gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/11-solutions.md](solutions/11-solutions.md). Chỉ mở sau khi tự làm.

**Bài 1 — Sự cố giả định.** 9 giờ sáng, người dùng báo "không vào được taskhub". Instance `running`, alarm status check `OK`. Viết **runbook** từng bước (lệnh cụ thể) để khoanh vùng: DNS/IP → mạng → nginx → app → DB. Mỗi bước ghi "kết quả nào thì chuyển bước nào".

**Bài 2 — Lấp một khoảng mù rẻ nhất.** Chọn **một** khoảng mù ở mục 4.5 và đề xuất cách lấp **trong mức miễn phí** (gợi ý: health check Route 53 nếu có tên miền; metric filter đếm lỗi; GitHub Actions `schedule` gọi `/actuator/health` mỗi 15 phút — nhớ giới hạn của schedule ở [Module 05 bài 02](../05-CICD/02-github-actions-basics.md)). So sánh ưu nhược. Làm thật nếu được.

**Bài 3 — Tính lại chi phí.** Tính chi phí tháng (kịch bản 24/7) nếu: (a) đổi sang `t3.micro` (0,0132 USD/giờ, 1 GiB RAM); (b) thêm Elastic IP và stop instance 2/3 thời gian; (c) thêm một ALB (tra giá ALB Singapore tại trang giá ELB, ghi ngày kiểm tra). Với mỗi phương án, nói rõ đánh đổi kỹ thuật (ví dụ (a): Spring Boot + PostgreSQL + nginx trong 1 GiB).

**Bài 4 — Thiết kế "v3 cho 2 AZ" trên giấy.** Vẽ kiến trúc taskhub chịu được mất một AZ: ALB, ASG tối thiểu 2 instance, RDS Multi-AZ, subnet nào public/private, đường ra Internet của instance ở private subnet (NAT hay VPC endpoint — cho SSM, GHCR thì sao?). Liệt kê thay đổi cần có ở ứng dụng (session, file upload, migration Flyway chạy ở đâu khi có 2 instance).

**Bài 5 — Kiểm tra trust policy.** In trust policy của `taskhub-github-deploy`. Viết 3 tình huống token (khác nhánh, khác repo, không dùng environment) và với mỗi tình huống, giải thích STS sẽ chấp nhận hay từ chối, vì sao.

**Bài 6 — ADR thứ ba.** Viết ADR còn lại trong ba ADR ở bước 7 mà bạn chưa viết.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ được kiến trúc v3 từ trí nhớ, đúng các thành phần và tên.
- [ ] Đi được luồng request (≥ 8 chặng) và luồng deploy (≥ 8 bước) bằng lời.
- [ ] Giải thích được chuỗi tin cậy và đọc được lỗi `AccessDenied` để khoanh vùng mắt xích.
- [ ] Lập được bảng "nếu X chết thì sao" và chỉ ra ít nhất 4 khoảng mù.
- [ ] Tính được chi phí tháng của v3 theo hai kịch bản và giải thích rủi ro đóng tài khoản Free plan.
- [ ] Đi hết checklist bảo mật với bằng chứng cho từng dòng.
- [ ] Giải thích được khi nào cần ALB/ASG/RDS/NAT/ECS/EKS và vì sao taskhub chưa cần.
- [ ] Trình bày kiến trúc trong 3 phút, có phần hạn chế và hướng mở rộng.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS public price data — EC2 On-Demand, Asia Pacific (Singapore), Linux](https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/Asia%20Pacific%20(Singapore)/Linux/index.json) | `t3.small` 0,0264 USD/giờ, `t3.micro` 0,0132 USD/giờ | 2026-10-31 |
| [AWS Price List — AmazonEC2 (ap-southeast-1)](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/ap-southeast-1/index.json) (file rất lớn, ~350 MB) | EBS gp3 0,096 USD/GB-tháng | 2026-10-31 |
| [AWS Price List — AmazonVPC (ap-southeast-1)](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/ap-southeast-1/index.json) | Public IPv4 0,005 USD/giờ (in-use và idle) | 2026-10-31 |
| [AWS Price List — AmazonS3 (ap-southeast-1)](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonS3/current/ap-southeast-1/index.json) | S3 Standard 0,025 USD/GB-tháng | 2026-10-31 |
| [Amazon EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) | 100 GB dữ liệu ra Internet miễn phí/tháng; Elastic IP tính cả khi idle | 2026-10-31 |
| [AWS Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/) | Session Manager, Run Command trên EC2 và Parameter Store standard không tính thêm phí | 2026-10-31 |
| [AWS Billing — Choosing a plan (Free/Paid)](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) | Credit, 6 tháng, đóng tài khoản, 90 ngày nâng cấp | 2026-10-31 |
| [EC2 — Track your Free Tier usage](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | Loại instance đủ điều kiện, dùng credit | 2026-10-31 |
| [EC2 — Automatic instance recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html) | Giữ IP khi recovery; stop/start đổi IP | 2026-10-31 |
| [GitHub Docs — Configuring OpenID Connect in AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) | Provider URL, `aud`, `sub` theo environment | 2026-10-31 |
| [Amazon CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) | Hạn mức miễn phí dùng trong bảng chi phí | 2026-10-31 |
