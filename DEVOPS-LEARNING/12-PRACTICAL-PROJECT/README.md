# Module 12 — Dự án xuyên suốt: `taskhub`

> Triển khai một hệ thống web **Java Spring Boot + PostgreSQL** lên **AWS** bằng quy trình DevOps hoàn chỉnh.
> Xuyên suốt 24 tuần · Mỗi giai đoạn học đóng góp một phần · Kết quả cuối: một dự án đưa vào CV và trình bày được trong phỏng vấn.

## Mục lục

- [1. Dự án này là gì và vì sao quan trọng](#1-dự-án-này-là-gì-và-vì-sao-quan-trọng)
- [2. Ánh xạ 15 yêu cầu → phiên bản → tuần](#2-ánh-xạ-15-yêu-cầu--phiên-bản--tuần)
- [3. Tiến hóa kiến trúc](#3-tiến-hóa-kiến-trúc)
- [4. Cấu trúc repo taskhub](#4-cấu-trúc-repo-taskhub)
- [5. Danh sách milestones](#5-danh-sách-milestones)
- [6. Nguyên tắc chi phí AWS](#6-nguyên-tắc-chi-phí-aws)
- [7. Ghi lại quyết định: ADR](#7-ghi-lại-quyết-định-adr)
- [8. Tiêu chí "đủ tốt để đưa vào CV"](#8-tiêu-chí-đủ-tốt-để-đưa-vào-cv)
- [Nguồn tham khảo](#nguồn-tham-khảo)

Liên quan: [Lộ trình §6](../00-ROADMAP/learning-roadmap.md#6-dự-án-xuyên-suốt-phát-triển-qua-từng-giai-đoạn) · [Kế hoạch tuần](../00-ROADMAP/weekly-study-plan.md) · [Cấu trúc giáo trình §4](../00-ROADMAP/curriculum-structure.md#4-cấu-trúc-repo-dự-án-taskhub)

---

## 1. Dự án này là gì và vì sao quan trọng

`taskhub` là một REST API quản lý công việc (task): tạo, xem, sửa, xóa task. Ứng dụng **cố ý đơn giản** — giá trị của dự án nằm ở phần **vận hành**: đóng gói, tự động hóa, hạ tầng, giám sát, bảo mật, sao lưu, khôi phục.

Vì sao một dự án xuyên suốt tốt hơn nhiều bài lab rời rạc:

- **Kiến thức được nối với nhau.** Dockerfile ở tuần 8 được pipeline build ở tuần 10, chạy trên EC2 ở tuần 12, được Terraform dựng lại ở tuần 16, được Prometheus giám sát ở tuần 17.
- **Gặp lỗi thật.** Lỗi khi ghép nhiều thành phần mới là lỗi bạn sẽ gặp khi đi làm.
- **Câu chuyện phỏng vấn.** Nhà tuyển dụng Junior hỏi rất nhiều về dự án: "Tại sao chọn X?", "Nếu Y chết thì sao?", "Gặp lỗi khó nhất là gì?". Dự án do bạn tự làm từ đầu cho bạn câu trả lời thật.

> **Quy tắc vàng:** bạn phải **giải thích được mọi dòng** trong repo. Thứ gì không giải thích được, hãy xóa hoặc học cho hiểu.

---

## 2. Ánh xạ 15 yêu cầu → phiên bản → tuần

| # | Yêu cầu (từ đề bài gốc) | Phiên bản | Tuần | Module liên quan |
|---|---|---|---|---|
| 1 | Quản lý source code bằng GitHub | v-pre | 1, 6 | [03-GIT](../03-GIT/) |
| 2 | Đóng gói ứng dụng bằng Docker | v0 | 7–8 | 04-DOCKER |
| 3 | Chạy ứng dụng và PostgreSQL bằng Docker Compose | v0 | 8 | 04-DOCKER |
| 4 | Nginx làm Reverse Proxy | v-pre (thử nghiệm) → v0 | 5, 8 | 02-NETWORKING, 04-DOCKER |
| 5 | Thiết lập môi trường AWS | v2 | 11 | 06-AWS |
| 6 | Triển khai lên EC2 | v2 | 12 | 06-AWS |
| 7 | Cấu hình VPC, Security Group, IAM phù hợp | v2 → v4 | 11–12, 15–16 | 06-AWS, 07-TERRAFORM |
| 8 | CI/CD tự động | v1 (CI) → v3 (CD) | 9–10, 13 | 05-CICD |
| 9 | Terraform quản lý hạ tầng | v4 | 15–16 | 07-TERRAFORM-ANSIBLE |
| 10 | Logging và Monitoring | v3 (CloudWatch cơ bản) → v5 | 13, 17–18 | 06-AWS, 08-MONITORING |
| 11 | Backup và restore database | v5 | 18 | 08-MONITORING |
| 12 | Rollback khi deployment lỗi | v1 (tag image) → v5 (diễn tập) | 10, 18 | 05-CICD, 08-MONITORING |
| 13 | Bảo mật cơ bản | Mọi phiên bản → rà soát ở v1.0 | Xuyên suốt, 21 | 10-SECURITY |
| 14 | README hướng dẫn triển khai | Cập nhật mỗi phiên bản → hoàn chỉnh ở v1.0 | Xuyên suốt, 23 | — |
| 15 | Sơ đồ kiến trúc hệ thống | Cập nhật mỗi phiên bản → hoàn chỉnh ở v1.0 | Xuyên suốt, 23 | — |

Thêm (ngoài 15 yêu cầu): **v6 — chạy trên Kubernetes local bằng Helm** (tuần 19–20), để có kinh nghiệm Kubernetes thực tế mà không tốn chi phí EKS.

---

## 3. Tiến hóa kiến trúc

Bảng tổng quan các phiên bản nằm ở [Lộ trình §6](../00-ROADMAP/learning-roadmap.md#6-dự-án-xuyên-suốt-phát-triển-qua-từng-giai-đoạn). Dưới đây là kiến trúc ở 3 mốc quan trọng, để bạn thấy hệ thống lớn dần thế nào.

### 3.1. v0 — Laptop, Docker Compose (tuần 8)

```text
Trình duyệt / curl
      │ http://localhost:80
      ▼
┌──────────────── Docker network "taskhub" (trên WSL) ────────────────┐
│  nginx:80 ──proxy_pass──► taskhub:8080 ──JDBC──► postgres:5432      │
│                                                    │                │
│                                              volume "pgdata"        │
└─────────────────────────────────────────────────────────────────────┘
Chỉ nginx mở port ra ngoài. App và database chỉ nói chuyện trong network nội bộ.
```

### 3.2. v2/v3 — AWS, 1 EC2 (tuần 12–13)

```text
GitHub ──push/merge──► GitHub Actions ──build/test/scan──► GHCR (image: sha, v1.2.0)
                              │ OIDC → IAM role tạm thời (không lưu access key)
                              ▼ deploy (SSM)
Internet ──► Security Group (80/443) ──► EC2 Ubuntu 24.04 (public subnet, VPC tự tạo)
                                          └─ docker compose: nginx · taskhub · postgres
                                          └─ IAM instance role: đọc/ghi S3 backup, gửi log CloudWatch
Không có NAT Gateway (tiết kiệm chi phí). Quản trị qua SSM Session Manager, không mở port 22 ra Internet.
```

### 3.3. v5 — Có Terraform, observability, backup (tuần 18)

```text
                    Terraform (state trên S3, khóa bằng use_lockfile)
                              │ dựng / xóa toàn bộ
                              ▼
EC2 ─┬─ nginx ─► taskhub (/actuator/prometheus) ─► postgres
     ├─ prometheus ──scrape──► taskhub, node-exporter
     ├─ grafana (dashboard, alert) ◄── loki ◄── alloy (thu log container)
     └─ cron: pg_dump ──► S3 (versioning, lifecycle xóa bản cũ)
Rollback: deploy lại image tag trước đó. Restore: tải bản backup từ S3 → psql.
```

Sơ đồ chi tiết từng phiên bản sẽ được viết trong `architecture.md` khi biên soạn các milestone tương ứng.

---

## 4. Cấu trúc repo taskhub

Repo `taskhub` **tách riêng** khỏi repo nhật ký `devops-journey` và khỏi thư mục giáo trình này. Đây là repo bạn đưa vào CV.

```text
taskhub/
├── README.md               # Giới thiệu, sơ đồ, cách chạy local, cách deploy
├── app/                    # Spring Boot (Java 21, Maven)
├── docker/
│   ├── Dockerfile          # multi-stage, non-root (v0)
│   └── nginx/              # cấu hình reverse proxy (v0)
├── compose.yaml            # (v0)
├── .github/workflows/      # ci.yml, release.yml (v1), deploy.yml (v3)
├── infra/
│   ├── terraform/          # modules/, envs/dev/ (v4)
│   └── ansible/            # (v4)
├── monitoring/             # prometheus/, grafana/, loki/, alloy/ (v5)
├── k8s/helm/taskhub/       # (v6)
├── scripts/                # healthcheck.sh (v-pre), backup.sh, restore.sh (v5)
└── docs/
    ├── architecture.md
    ├── network-plan.md     # (v-pre)
    ├── runbooks/           # deploy, rollback, backup/restore, xử lý sự cố
    ├── postmortems/
    └── adr/                # Architecture Decision Records
```

Thư mục chỉ được tạo **khi đến phiên bản cần nó** — không tạo sẵn thư mục rỗng.

---

## 5. Danh sách milestones

| Phiên bản | Tuần | Nội dung chính | Tài liệu hướng dẫn |
|---|---|---|---|
| **v-pre** | 1–6 | Repo, script vận hành, network plan, Nginx thử nghiệm, ứng dụng Spring Boot chạy trên máy | [milestones/v-pre-foundation.md](milestones/v-pre-foundation.md) · Tuần 6 chi tiết: [v-pre-week6-springboot-app.md](milestones/v-pre-week6-springboot-app.md) |
| **v0** | 7–8 | Dockerfile multi-stage, Docker Compose (app + postgres + nginx) | [milestones/v0-docker-compose.md](milestones/v0-docker-compose.md) |
| **v1** | 9–10 | CI GitHub Actions: build, test, scan, push image lên GHCR | [milestones/v1-ci.md](milestones/v1-ci.md) |
| **v2** | 11–12 | Triển khai thủ công lên EC2 trong VPC tự tạo | [milestones/v2-aws-ec2.md](milestones/v2-aws-ec2.md) |
| **v3** | 13–14 | CD tự động qua OIDC, CloudWatch cơ bản | [milestones/v3-cd.md](milestones/v3-cd.md) |
| **v4** | 15–16 | Hạ tầng bằng Terraform, Ansible cài đặt server | [milestones/v4-terraform.md](milestones/v4-terraform.md) |
| **v5** | 17–18 | Monitoring, logging, alert, backup/restore, diễn tập rollback | [milestones/v5-observability-backup.md](milestones/v5-observability-backup.md) |
| v6 | 19–20 | Kubernetes local + Helm chart | Sẽ viết ở lượt 9 |
| v1.0 | 21–24 | Rà soát bảo mật, README, sơ đồ, runbook, postmortem, demo | Sẽ viết ở lượt 10 |

Thứ tự các lượt biên soạn: [curriculum-structure.md §5](../00-ROADMAP/curriculum-structure.md#5-thứ-tự-biên-soạn-đề-xuất).

Mỗi phiên bản kết thúc bằng một **Git tag** (`v0.1.0`, `v0.2.0`…) và một mục trong `CHANGELOG` hoặc GitHub Release — bạn sẽ học cách làm ở tuần 6.

---

## 6. Nguyên tắc chi phí AWS

Chi tiết đầy đủ: [Lộ trình §7](../00-ROADMAP/learning-roadmap.md#7-chiến-lược-kiểm-soát-chi-phí-aws). Tóm tắt các nguyên tắc áp dụng cho dự án:

1. Tạo tài khoản AWS ở **tuần 11**, chọn **Free plan**, bật MFA, tạo **AWS Budget** ngay buổi đầu.
2. Dự án chính: **1 EC2, không NAT Gateway, 1 Public IPv4**.
3. RDS, ALB, Auto Scaling chỉ dựng trong **lab ngắn**, xóa ngay sau buổi học.
4. Từ v4: `terraform destroy` khi không học, `terraform apply` khi cần.
5. ⚠️ Mọi lệnh tạo tài nguyên AWS **do bạn tự chạy** sau khi đọc phần ước tính chi phí của bài.

Mỗi milestone có phần AWS sẽ có bảng **ước tính chi phí** và **checklist dọn dẹp**.

---

## 7. Ghi lại quyết định: ADR

**ADR** (Architecture Decision Record — bản ghi quyết định kiến trúc) là một file ngắn ghi lại **một** quyết định quan trọng: bối cảnh, lựa chọn, lý do, hệ quả. Khái niệm được phổ biến bởi bài viết *Documenting Architecture Decisions* của Michael Nygard (2011).

Vì sao cần với một dự án cá nhân:

- 3 tháng sau bạn sẽ quên vì sao mình chọn X.
- Trong phỏng vấn, câu hỏi "Tại sao chọn X mà không phải Y?" gần như chắc chắn xuất hiện. ADR là câu trả lời đã chuẩn bị sẵn.
- Ở công ty, ADR giúp người mới hiểu hệ thống mà không phải hỏi lại.

**Quy ước:** lưu ở `docs/adr/NNNN-ten-quyet-dinh.md`, đánh số tăng dần, không sửa ADR cũ — nếu đổi quyết định thì viết ADR mới đánh dấu thay thế ADR cũ.

**Mẫu:**

```markdown
# ADR-NNNN: <Tên quyết định>

- Trạng thái: Đề xuất | Đã chấp nhận | Bị thay thế bởi ADR-XXXX
- Ngày: YYYY-MM-DD

## Bối cảnh
Vấn đề cần giải quyết là gì? Có ràng buộc gì (chi phí, thời gian, kỹ năng)?

## Các lựa chọn đã cân nhắc
1. ...
2. ...

## Quyết định
Chọn ... vì ...

## Hệ quả
- Tích cực: ...
- Tiêu cực / đánh đổi: ...
- Việc cần làm thêm: ...
```

**Ví dụ:**

```markdown
# ADR-0001: Dùng GitHub Actions thay vì Jenkins cho CI/CD

- Trạng thái: Đã chấp nhận
- Ngày: 2027-01-04

## Bối cảnh
taskhub cần pipeline build, test, quét bảo mật, đẩy image và deploy lên EC2.
Ràng buộc: dự án cá nhân, ngân sách gần 0, một người vận hành, code đã nằm trên GitHub.

## Các lựa chọn đã cân nhắc
1. Jenkins tự chạy (trên laptop hoặc EC2).
2. GitHub Actions.
3. GitLab CI (phải chuyển repo sang GitLab).

## Quyết định
Chọn GitHub Actions vì:
- Miễn phí cho repo public, không phải duy trì server CI.
- Tích hợp sẵn với repo, Pull Request, branch protection.
- Hỗ trợ OIDC để lấy quyền AWS tạm thời → không lưu access key dài hạn.

## Hệ quả
- Tích cực: không tốn chi phí và công vận hành server CI; cấu hình nằm trong repo.
- Tiêu cực: phụ thuộc vào GitHub; nhiều công ty Việt Nam dùng Jenkins nên cần
  bổ sung kiến thức Jenkins ở mức đọc hiểu Jenkinsfile (tuần 22).
- Việc cần làm thêm: thiết lập IAM role cho OIDC ở v3.
```

Gợi ý các ADR nên viết trong dự án: chọn Docker Compose trên EC2 thay vì ECS/EKS · không dùng NAT Gateway · PostgreSQL tự chạy thay vì RDS · Loki + Alloy thay vì ELK · S3 backend với `use_lockfile`.

---

## 8. Tiêu chí "đủ tốt để đưa vào CV"

Dự án đạt chuẩn khi tick được toàn bộ danh sách dưới đây. Đây cũng là checklist cho bài thi mốc 6 tháng.

**Tài liệu**
- [ ] `README.md`: dự án làm gì, sơ đồ kiến trúc, công nghệ, cách chạy local trong ≤ 5 lệnh, cách deploy, cách dọn dẹp.
- [ ] Sơ đồ kiến trúc khớp với hệ thống **đang chạy thật** (không vẽ thứ không có).
- [ ] Ít nhất 3 ADR giải thích các quyết định quan trọng.
- [ ] Runbook: deploy, rollback, backup/restore, xử lý sự cố thường gặp.
- [ ] Ít nhất 2 postmortem từ các buổi diễn tập sự cố.

**Kỹ thuật**
- [ ] CI xanh trên nhánh `main`; `main` được bảo vệ, chỉ merge qua Pull Request.
- [ ] Image được tag theo commit SHA và phiên bản; rollback đã diễn tập thành công trong < 5 phút.
- [ ] Toàn bộ hạ tầng AWS dựng được bằng `terraform apply` và xóa được bằng `terraform destroy`.
- [ ] Có dashboard, ít nhất 2 alert, log tập trung tìm kiếm được.
- [ ] Backup tự động và **đã diễn tập restore** thành công.
- [ ] Chạy được trên Kubernetes local bằng Helm (v6).

**Bảo mật & chi phí**
- [ ] Không có secret trong repo và lịch sử Git (đã quét bằng công cụ).
- [ ] Không có access key AWS dài hạn trong pipeline (dùng OIDC); IAM theo nguyên tắc quyền tối thiểu.
- [ ] Container chạy bằng user không phải root; image được quét lỗ hổng trong CI.
- [ ] Security Group chỉ mở port cần thiết; không mở SSH ra `0.0.0.0/0`.
- [ ] Có bảng chi phí thực tế đã phát sinh và cách bạn kiểm soát nó.

**Khả năng trình bày**
- [ ] Trình bày dự án trong 10 phút: vấn đề → kiến trúc → quy trình → sự cố đã gặp → bài học.
- [ ] Trả lời được "nếu thành phần X chết thì chuyện gì xảy ra và bạn phát hiện thế nào" cho mọi thành phần.
- [ ] Giải thích được mọi file trong repo.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [ADR GitHub organization](https://adr.github.io/) | Khái niệm ADR, mẫu của Michael Nygard | 2026-10-31 |
| [AWS Free Tier](https://aws.amazon.com/free/) | Chính sách Free plan | 2026-10-31 |
| [AWS VPC Pricing](https://aws.amazon.com/vpc/pricing/) | Giá NAT Gateway, Public IPv4 | 2026-10-31 |
| [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) | `use_lockfile` | 2026-10-31 |
