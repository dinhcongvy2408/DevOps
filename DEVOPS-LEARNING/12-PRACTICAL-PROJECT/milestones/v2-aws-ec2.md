# Milestone v2 — Triển khai thủ công lên AWS EC2 (tuần 11–12)

> Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 06 — AWS](../../06-AWS/README.md) (bài 00–06), milestone [v1 — CI](v1-ci.md) (release `v0.3.0`, image public trên GHCR)
> Môi trường: `[WSL]` (AWS CLI, git), `[AWS Console]`, `[EC2]` (shell qua Session Manager), `[GitHub]`
> Đây là **việc cần nộp + tiêu chí chấp nhận**. Các bước làm chi tiết nằm ở [Lab 01 — Tạo VPC bằng tay](../../06-AWS/labs/lab-01-vpc-by-hand.md) (tuần 11) và [Lab 02 — Triển khai taskhub lên EC2](../../06-AWS/labs/lab-02-ec2-deploy-taskhub.md) (tuần 12). Làm lab trước, rồi đưa kết quả vào repo `taskhub`.

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc v2](#2-kiến-trúc-v2)
- [3. Chi phí và nguyên tắc tiết kiệm](#3-chi-phí-và-nguyên-tắc-tiết-kiệm)
- [4. File phải có trong repo](#4-file-phải-có-trong-repo)
- [5. Tài nguyên AWS phải có](#5-tài-nguyên-aws-phải-có)
- [6. Yêu cầu chất lượng](#6-yêu-cầu-chất-lượng)
- [7. Thử nghiệm bắt buộc](#7-thử-nghiệm-bắt-buộc)
- [8. Xử lý sự cố thường gặp](#8-xử-lý-sự-cố-thường-gặp)
- [9. Câu hỏi tự kiểm](#9-câu-hỏi-tự-kiểm)
- [10. Definition of Done và release v0.4.0](#10-definition-of-done-và-release-v040)
- [11. Dọn dẹp](#11-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu

Lần đầu tiên `taskhub` chạy trên **hạ tầng thật, trên Internet**, do chính bạn dựng từng mảnh:

1. **Tài khoản AWS an toàn**: Free plan, MFA cho root, user `phuong-admin` có MFA, CLI đăng nhập bằng `aws login` (không có access key dài hạn trên laptop), AWS Budget gửi email cảnh báo ([bài 00](../../06-AWS/00-aws-account-setup-cost-safety.md)).
2. **VPC tự tạo** đúng bảng `docs/network-plan.md` bạn viết từ tuần 4: 2 subnet public + 2 subnet private, IGW, route table — **không** NAT Gateway.
3. **Một EC2** `t3.small` Ubuntu 24.04 trong subnet public chạy `docker compose` (nginx · taskhub · postgres). Image lấy từ GHCR theo tag bất biến — server **không build** gì.
4. **Không có port 22**: quản trị qua SSM Session Manager. Security Group chỉ mở 80.
5. **Mật khẩu database** nằm ở Parameter Store (SecureString), không trong Git, user data hay GitHub.
6. Bạn giải thích được **mỗi gói tin** đi từ trình duyệt tới PostgreSQL qua những lớp nào, và mỗi quyền IAM tồn tại để làm gì.

Vì sao làm **tay** trước khi tự động hóa: v3 (CD) và v4 (Terraform) chỉ là tự động hóa đúng những bước này. Không tự làm tay được thì không debug được khi tự động hóa hỏng — câu "Bạn đã từng dựng nó bằng tay chưa?" rất hay gặp trong phỏng vấn.

---

## 2. Kiến trúc v2

```text
 Người dùng ──HTTP :80──► Internet ──► IGW taskhub-igw
                                          │
┌──────────────────── VPC taskhub-vpc (vd 10.20.0.0/16 — theo network-plan.md của bạn) ─────────────┐
│ public-a 10.20.1.0/24 (1a)                     │ public-b 10.20.2.0/24 (1b)  — dự phòng (ALB tuần 14)│
│  ┌ SG taskhub-web-sg: in 80/0.0.0.0/0, KHÔNG 22 ┐                                                  │
│  │ EC2 taskhub-app  t3.small · Ubuntu 24.04      │ private-a 10.20.11.0/24 · private-b 10.20.12.0/24 │
│  │  IMDSv2 bắt buộc, hop limit 1, EBS mã hóa     │   (không route ra Internet — RDS ở lab tuần 14)   │
│  │  instance profile taskhub-ec2-role            │                                                   │
│  │  /opt/taskhub @ tag v0.4.0                    │                                                   │
│  │   nginx:80 → taskhub:8080 → postgres (pgdata) │                                                   │
│  └───────────────────────────────────────────────┘                                                   │
└──────────────────────────────────────────────────────────────────────────────────────────────────────┘
  EC2 ──443 ra ngoài──► ghcr.io (pull) · SSM (Agent) · Parameter Store (mật khẩu)
  Bạn  ──aws ssm start-session──► SSM ──► EC2          Bạn ──sudo deploy.sh <tag>──► compose pull + up --wait
```

| Thành phần | Quyết định | Phương án khác và vì sao không chọn (ghi vào ADR) |
|---|---|---|
| Nơi chạy | 1 EC2 + Docker Compose | ECS/EKS: thêm khái niệm và chi phí, chưa cần cho 1 service; học Kubernetes ở v6 (local) |
| Database | PostgreSQL trong container, volume trên EBS | RDS: có backup/Multi-AZ tự động nhưng tốn thêm; học bằng lab ngắn tuần 14 |
| Mạng ra ngoài | EC2 ở subnet public có IP public | NAT Gateway ≈ 0,045 USD/giờ + phí dữ liệu — đắt hơn cả EC2 |
| Quản trị | Session Manager | SSH: phải mở port 22, quản lý key, lộ bề mặt tấn công |
| Secret | Parameter Store SecureString (Standard) | Secrets Manager: có xoay vòng tự động nhưng tính phí theo secret/tháng |

---

## 3. Chi phí và nguyên tắc tiết kiệm

| Khoản | Đơn giá | Khi nào tính | Cách giảm |
|---|---|---|---|
| EC2 `t3.small` | Tra [AWS Pricing Calculator](https://calculator.aws/) cho ap-southeast-1 | Khi instance **running** | Stop sau mỗi buổi học |
| EBS gp3 20 GiB | Tra Calculator (GB-tháng) | Luôn luôn, kể cả khi stop | Terminate khi không còn cần (sau v3 / trước v4) |
| Public IPv4 tự cấp | 0,005 USD/giờ ([VPC pricing](https://aws.amazon.com/vpc/pricing/)) | Khi instance running | Stop → IP được trả lại |
| Elastic IP (nếu dùng) | 0,005 USD/giờ | **Luôn luôn**, kể cả khi instance stop | Không dùng ở v2 trừ khi có lý do (ghi vào ADR) |
| VPC, subnet, IGW, route table, SG, IAM | 0 | — | — |
| Parameter Store Standard, Session Manager | 0 | — | — |

**Bảng chi phí thực tế** (`docs/cost.md`, bắt buộc): mỗi buổi học ghi số giờ instance chạy và số dư credit trước/sau (Billing → Credits). Cuối tuần 12 tính: "nếu chạy 24/7 thì credit đủ bao nhiêu tháng?" — câu trả lời quyết định bạn stop thường xuyên đến mức nào.

> ⚠️ Free plan: tài khoản **tự đóng** khi hết 6 tháng **hoặc** hết credit. Credit đốt vào một instance quên tắt là credit không còn cho Terraform (tuần 15–16) và Monitoring (17–18). Đặt nhắc nhở "stop EC2" cuối mỗi buổi.

---

## 4. File phải có trong repo

```text
taskhub/
├── compose.yaml                 # CẬP NHẬT — bản TRIỂN KHAI: image ghcr.io/<user>/taskhub:${TASKHUB_IMAGE_TAG}, không build
├── compose.override.yaml        # MỚI — chỉ laptop: build: + image: taskhub:local
├── .env.example                 # CẬP NHẬT — thêm TASKHUB_IMAGE_TAG=dev, NGINX_HOST_PORT
├── scripts/deploy.sh            # MỚI — (mode 100755) Parameter Store → .env, pull, up --wait, smoke test, rollback
├── infra/aws-manual/            # MỚI — những gì bạn đã dùng để dựng tay (để v4 đối chiếu)
│   ├── user-data.sh
│   ├── ec2-trust.json
│   ├── ec2-app-policy.json
│   └── commands.md              # các lệnh AWS CLI đã chạy, theo thứ tự, ID đã thay bằng <...>
├── docs/
│   ├── network-plan.md          # CẬP NHẬT — điền ID thật (vpc-…, subnet-…) bên cạnh CIDR
│   ├── architecture.md          # CẬP NHẬT — sơ đồ v2
│   ├── cost.md                  # MỚI — bảng chi phí thực tế
│   ├── runbooks/deploy-manual.md    # MỚI — triển khai/rollback tay trên EC2 (≤ 10 bước)
│   ├── adr/0004-single-ec2-docker-compose.md   # MỚI
│   └── experiments/v2-tests.md  # MỚI — kết quả T1–T8
└── README.md                    # CẬP NHẬT — mục "Triển khai lên AWS (v2)" + cách dọn dẹp
```

**Bản tham khảo:** [06-AWS/labs/reference-v3/](../../06-AWS/labs/reference-v3/README.md) có `compose.yaml`, `compose.override.yaml`, `scripts/deploy.sh`, `user-data.sh`, các file IAM. ⚠️ Chỉ mở sau khi bạn đã tự viết và chạy được (hoặc đã kẹt quá 30 phút ở một lỗi cụ thể). Không commit account id thật hay ID tài nguyên vào chỗ công khai nếu bạn không muốn — dùng `<account-id>` trong tài liệu.

### 4.1. ADR-0004 — một EC2 + Docker Compose

Ghi: bối cảnh (dự án cá nhân, Free plan, 1 service), các lựa chọn (EC2 + Compose · ECS Fargate · EKS · Lightsail), quyết định, **hệ quả** — phải có: một điểm hỏng duy nhất (EC2 chết = sập), không tự mở rộng, database và app chung máy, IP đổi khi stop/start, mật khẩu vẫn thấy được trong `docker inspect` trên host (thử nghiệm T5). Viết luôn lý do chọn `t3.small` thay vì `t3.micro`.

ADR "không dùng NAT Gateway" được gợi ý ở [README dự án §7](../README.md#7-ghi-lại-quyết-định-adr) — nếu chưa có, viết ADR-0005 cùng lúc.

### 4.2. Runbook `deploy-manual.md`

Một người khác (hoặc bạn 3 tháng sau) phải triển khai được chỉ bằng runbook: vào máy thế nào, kiểm tra phiên bản đang chạy, chạy `deploy.sh`, kiểm tra kết quả, rollback, khi nào **không** rollback được (migration không tương thích ngược — [CI/CD bài 05](../../05-CICD/05-deployment-strategies-rollback.md)).

---

## 5. Tài nguyên AWS phải có

| Tài nguyên | Tên | Yêu cầu |
|---|---|---|
| VPC | `taskhub-vpc` | CIDR theo `network-plan.md`; DNS hostnames bật |
| Subnet | `taskhub-public-a/b`, `taskhub-private-a/b` | Đúng AZ và CIDR trong plan; private **không** route ra Internet |
| IGW + route table | `taskhub-igw`, `taskhub-public-rt`, `taskhub-private-rt` | Public RT có `0.0.0.0/0 → igw`; private RT chỉ có `local` |
| Security Group | `taskhub-web-sg` | Vào: chỉ TCP 80 từ `0.0.0.0/0` |
| IAM role + instance profile | `taskhub-ec2-role` | `AmazonSSMManagedInstanceCore` + inline `taskhub-ec2-app` (chỉ đọc `/taskhub/dev/*`) |
| Parameter Store | `/taskhub/dev/postgres-password` | SecureString, Standard |
| EC2 | `taskhub-app` | `t3.small`, Ubuntu 24.04 từ tham số SSM của Canonical, IMDSv2 required + hop limit 1, gp3 20 GiB mã hóa, DeleteOnTermination |
| Budget | (tên tùy bạn) | Cảnh báo email theo [bài 00](../../06-AWS/00-aws-account-setup-cost-safety.md) |

Mọi tài nguyên có đủ 4 tag: `Project=taskhub`, `Env=dev`, `Owner=<tên>`, `ManagedBy=manual`. Kiểm tra bằng **Tag Editor** (`[AWS Console]` Resource Groups & Tag Editor → Tag Editor → Region ap-southeast-1, tag `Project=taskhub`): danh sách phải khớp bảng trên.

---

## 6. Yêu cầu chất lượng

| # | Yêu cầu | Vì sao | Học ở |
|---|---|---|---|
| Q1 | Root có MFA, không có access key; việc hằng ngày dùng `phuong-admin` có MFA; laptop **không** có `~/.aws/credentials` chứa access key | Root bị lộ = mất toàn bộ tài khoản, không giới hạn được bằng IAM | [Bài 00](../../06-AWS/00-aws-account-setup-cost-safety.md), [bài 02](../../06-AWS/02-iam.md) |
| Q2 | Security Group **không** có rule cổng 22 (cũng không có rule "All traffic") | Bề mặt tấn công nhỏ nhất; Session Manager thay SSH | [Bài 03](../../06-AWS/03-vpc-networking.md), [bài 04](../../06-AWS/04-ec2.md) |
| Q3 | IMDSv2 `required`, hop limit `1`; EBS gốc `Encrypted` | Chặn đánh cắp quyền qua SSRF/IMDSv1 và từ container | Bài 04, Lab 02 |
| Q4 | Policy `taskhub-ec2-app` chỉ có `ssm:GetParameter(s)` trên `parameter/taskhub/dev/*` — không `*` ở Action hay Resource | Quyền tối thiểu: máy bị chiếm cũng chỉ đọc được tham số của dự án | Bài 02 |
| Q5 | Mật khẩu database chỉ có ở Parameter Store; `git grep -i password` chỉ thấy tên biến/placeholder; user data không chứa secret; `.env` trên server quyền `600` | Không lộ qua Git, user data, AMI | Lab 02 (E4, E5) |
| Q6 | Server **không build**: `compose.yaml` không có `build:`; `deploy.sh` luôn dùng `-f compose.yaml`. Service `taskhub` có `mem_limit` (vd `768m`) | Chỉ chạy image đã qua CI + Trivy ([v1](v1-ci.md)). Không có giới hạn, JVM (`MaxRAMPercentage=75`) tính theo cả 2 GiB của máy và giành RAM của PostgreSQL | [CI/CD bài 05](../../05-CICD/05-deployment-strategies-rollback.md), [bài 04](../../06-AWS/04-ec2.md) |
| Q7 | Triển khai bằng tag bất biến (`:vX.Y.Z` hoặc `:<sha7>`), không `latest`; `deploy.sh` từ chối tag sai định dạng | Biết chính xác code nào đang chạy; rollback được | [Docker bài 06](../../04-DOCKER/06-registry.md) |
| Q8 | `deploy.sh`: `set -euo pipefail`, `--wait`, smoke test kiểm tra **cả** `/actuator/health` **và** image đang chạy đúng tag, tự rollback khi lỗi | Triển khai hỏng không được để app chết | CI/CD bài 05 |
| Q9 | AMI lấy từ tham số SSM của Canonical, không chép ID cứng; ghi lại AMI ID đã dùng vào `infra/aws-manual/commands.md` | AMI ID khác nhau theo Region và thời gian | Bài 04 |
| Q10 | Mọi tài nguyên có đủ tag; không có tài nguyên `Project=taskhub` ở Region khác | Tìm được, tính được chi phí, dọn được | [Bài 01](../../06-AWS/01-cloud-fundamentals.md) |
| Q11 | `docs/cost.md` có số liệu thật; Budget đã nhận ít nhất 1 email (thử bằng ngưỡng thấp hoặc chờ báo cáo) | Kiểm soát chi phí là kỹ năng được hỏi trong phỏng vấn Cloud | Bài 00 |

**Kiểm tra nhanh** `[WSL]`:

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=taskhub-web-sg \
  --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort]' --output text   # chỉ: tcp 80 80
aws ec2 describe-instances --filters Name=tag:Name,Values=taskhub-app Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].MetadataOptions.[HttpTokens,HttpPutResponseHopLimit]' --output text  # required 1
grep -n 'build:' compose.yaml                     # KHÔNG in gì
git ls-files -s scripts/deploy.sh                 # 100755
ls ~/.aws/credentials 2>/dev/null && echo "CẢNH BÁO: còn file credentials"
```

---

## 7. Thử nghiệm bắt buộc

Ghi **thao tác → quan sát → giải thích** vào `docs/experiments/v2-tests.md`. T1–T6 tương ứng các thí nghiệm ở [Lab 02 mục 11](../../06-AWS/labs/lab-02-ec2-deploy-taskhub.md); T7–T8 là của milestone.

| # | Thử nghiệm | Kết quả mong đợi — bạn phải giải thích được |
|---|---|---|
| T1 | **Stop/start** (Lab 02 E1) | IP public đổi, IP private giữ; app tự lên lại; dữ liệu còn. Hệ quả với người dùng |
| T2 | **Process app bị kill** (E3) | Container tự khởi động lại (`RestartCount` tăng); `docker stop` thì không — vì sao |
| T3 | **Đường đi của gói tin** | Vẽ (bằng chữ) đường đi của `curl http://<IP>/api/tasks`: IP public → IGW (dịch sang IP private) → route table → SG (stateful) → ENI → nginx:80 → mạng Docker → taskhub:8080 → postgres:5432; và đường **ra** của `docker pull`. Nối với [Networking bài 04](../../02-NETWORKING/04-routing-nat-switching.md) |
| T4 | **Gỡ route Internet** | ⚠️ Tạm xóa route `0.0.0.0/0` khỏi `taskhub-public-rt` (ghi lại ID IGW trước!) → thử `curl` từ laptop và mở Session Manager → **thêm lại route ngay** | Cả hai đều hỏng: người dùng không vào được, **và** SSM Agent mất đường ra → mất luôn đường quản trị. Bài học: Session Manager cũng phụ thuộc mạng. Khôi phục mất bao lâu? |
| T5 | **Mật khẩu lộ ở đâu** (E4) | Không ở Git/user data; **có** trong `docker inspect` trên host. Ghi mô hình đe dọa vào ADR-0004 |
| T6 | **Container không mượn được quyền EC2** (E6) | Token IMDSv2 lấy được trên host, không lấy được trong container (hop limit 1) |
| T7 | **Dựng lại từ đầu theo runbook** | Terminate EC2 → dựng lại chỉ bằng `infra/aws-manual/commands.md` + runbook, **không xem lab**. Đo thời gian. Dữ liệu cũ mất (volume bị xóa theo) — ghi điều đó làm động lực cho backup ở v5. Đây cũng là bài luyện cho [bài thi mốc 3 tháng](../../00-ROADMAP/exam-month-3.md) |
| T8 | **Rollback tay** | `deploy.sh v0.3.0` rồi `deploy.sh v0.4.0`; tag không tồn tại (`v9.9.9`) → script tự giữ bản đang chạy. Đo thời gian từng lần — số liệu nền cho mục tiêu "rollback < 5 phút" ở v3 |

---

## 8. Xử lý sự cố thường gặp

Bảng lỗi chi tiết ở [Lab 02 mục 13](../../06-AWS/labs/lab-02-ec2-deploy-taskhub.md). Thứ tự kiểm tra khi "từ laptop không vào được":

```text
1. Instance running? IP public hiện tại là gì?          aws ec2 describe-instances ...
2. App trên máy có trả lời không?                         [EC2] curl -s localhost/actuator/health
   ├─ Không → vấn đề trong máy: docker compose ps, logs taskhub, free -m
   └─ Có  → vấn đề mạng giữa Internet và máy:
3. SG có TCP 80 từ 0.0.0.0/0?                             describe-security-groups
4. Subnet có route 0.0.0.0/0 → igw? IGW gắn vào VPC?      describe-route-tables, describe-internet-gateways
5. NACL có chặn không? (mặc định cho phép hết)            describe-network-acls
6. nginx có publish đúng cổng 80 trên host?               [EC2] sudo ss -ltnp | grep ':80 '
```

Đi từ **trong ra ngoài**: chứng minh app chạy trước, rồi mới nghi mạng. Ghi mọi lỗi vào `troubleshooting-journal.md` theo [mẫu](../../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 9. Câu hỏi tự kiểm

1. Một gói tin từ trình duyệt tới EC2: IP đích là IP public, nhưng card mạng của EC2 chỉ có IP private. Ai dịch, ở đâu?
2. Security Group và NACL khác nhau thế nào (stateful/stateless, cấp áp dụng, allow/deny)? Vì sao v2 không cần sửa NACL?
3. EC2 trong subnet public nhưng **không** có IP public: điều gì xảy ra với `docker pull` và với Session Manager?
4. Instance role lấy quyền tạm thời thế nào? Quyền đó hết hạn khi nào và ai làm mới?
5. Vì sao `deploy.sh` cần `sudo`, và vì sao không thêm `ssm-user` vào nhóm `docker` cho tiện?
6. Bạn stop EC2 mỗi tối. Liệt kê các khoản **vẫn** bị tính tiền qua đêm.
7. Vì sao `compose.yaml` dùng `${TASKHUB_IMAGE_TAG:?...}` thay vì `${TASKHUB_IMAGE_TAG:-latest}`?
8. Kiến trúc v2 có những điểm hỏng duy nhất nào? Với mỗi điểm, bạn phát hiện bằng cách nào (hiện tại: **chưa** có monitoring — v3 bổ sung CloudWatch)?

---

## 10. Definition of Done và release v0.4.0

- [ ] Tài khoản: root MFA, user admin có MFA, `aws login` hoạt động, Budget đã tạo (Q1, Q11).
- [ ] VPC + 4 subnet + IGW + route table đúng `network-plan.md`; ID thật đã điền vào plan.
- [ ] `http://<IP-public>/actuator/health` trả `{"status":"UP"}` từ máy khác (điện thoại dùng 4G cũng được); tạo/đọc task được.
- [ ] Đạt Q1–Q11; các lệnh kiểm tra nhanh ở mục 6 ra đúng kết quả.
- [ ] Hoàn thành T1–T8, ghi trong `docs/experiments/v2-tests.md`; T7 có số phút thực tế.
- [ ] `docs/architecture.md` (sơ đồ v2), `docs/cost.md`, `docs/runbooks/deploy-manual.md`, ADR-0004 đã merge.
- [ ] README có mục **"Triển khai lên AWS (v2)"**: sơ đồ rút gọn, điều kiện tiên quyết, lệnh triển khai, **cách dọn dẹp**, và câu cảnh báo chi phí.
- [ ] Code vào `main` qua PR (ví dụ `feat/aws-ec2-deploy`), CI xanh.
- [ ] **Release `v0.4.0`** do workflow `Release` (v1) tạo sau khi CI trên `main` xanh: `git tag -a v0.4.0 -m "v2: triển khai thủ công lên AWS EC2"` → `git push origin v0.4.0`. EC2 đang chạy đúng `:v0.4.0` (`sudo grep TASKHUB_IMAGE_TAG /opt/taskhub/.env`).
- [ ] Ít nhất một lỗi gặp phải đã được ghi vào nhật ký debug.
- [ ] Kiểm tra bản thân: [Bài thi mốc 3 tháng](../../00-ROADMAP/exam-month-3.md) (tuần 12).

➡️ Tiếp theo: [**v3 — CD tự động qua OIDC + SSM**](v3-cd.md) (tuần 13–14): chính `deploy.sh` này sẽ được GitHub Actions gọi qua SSM Run Command sau mỗi lần CI xanh trên `main` — không SSH, không access key.

---

## 11. Dọn dẹp

EC2 được dùng tiếp ở v3 → **stop** sau mỗi buổi, đừng terminate. Khi kết thúc v3 (hoặc nếu dừng dự án), làm đúng thứ tự trong [Lab 02 mục 14](../../06-AWS/labs/lab-02-ec2-deploy-taskhub.md) và chạy các lệnh kiểm tra "không còn gì sót" ở đó. Trước v4: toàn bộ tài nguyên `ManagedBy=manual` phải được xóa — Terraform sẽ dựng lại từ đầu, và hai bản cùng tồn tại sẽ gây nhầm lẫn (và tốn gấp đôi).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS Billing — Free plan vs Paid plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) | Credit, 6 tháng, tự đóng tài khoản | 2026-10-31 |
| [Amazon EC2 — Free Tier usage](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | Loại instance free-tier-eligible | 2026-10-31 |
| [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Public IPv4, NAT Gateway | 2026-10-31 |
| [AWS Pricing Calculator](https://calculator.aws/) | Ước tính EC2/EBS theo Region | 2026-10-31 |
| [Systems Manager — AMIs with SSM Agent preinstalled](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html) | Ubuntu 24.04 có SSM Agent | 2026-10-31 |
| [AWS KMS — Parameter Store SecureString](https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html) | SecureString và key `aws/ssm` | 2026-10-31 |
| [Ubuntu on AWS — Find Ubuntu images](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/) | Tham số SSM của Canonical | 2026-10-31 |
