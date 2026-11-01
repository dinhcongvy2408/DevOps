# Kế hoạch học theo tuần (24 tuần · 15–18 giờ/tuần)

## Mục lục

- [1. Nhịp học mỗi tuần](#1-nhịp-học-mỗi-tuần)
- [2. Giai đoạn 3 tháng đầu (tuần 1–12)](#2-giai-đoạn-3-tháng-đầu-tuần-112)
- [3. Giai đoạn tháng 4–6 (tuần 13–24)](#3-giai-đoạn-tháng-46-tuần-1324)
- [4. Lịch kiểm tra định kỳ](#4-lịch-kiểm-tra-định-kỳ)
- [5. Quy tắc khi bị chậm tiến độ](#5-quy-tắc-khi-bị-chậm-tiến-độ)

Liên quan: [Lộ trình](learning-roadmap.md) · [Ma trận kỹ năng](skill-matrix.md) · [Cấu trúc giáo trình](curriculum-structure.md)

---

## 1. Nhịp học mỗi tuần

Gợi ý phân bổ ~16 giờ. Bạn có thể đổi ngày, nhưng giữ **tỉ lệ**: khoảng 35% đọc/hiểu, 50% thực hành, 15% ôn tập và ghi chép.

| Buổi | Thời lượng | Nội dung |
|---|---|---|
| Thứ 2–5 (tối) | 4 × 2h = 8h | Học bài mới: đọc phần giải thích → làm ví dụ → trả lời câu hỏi kiểm tra |
| Thứ 7 | 4–5h | Lab bắt buộc + bài tập tự làm |
| Chủ nhật | 3–4h | Làm phần dự án của tuần (2–3h) + ôn tập, cập nhật nhật ký debug (1h) |
| Dự phòng | 1–2h | Bù phần chưa xong |

**Thói quen bắt buộc:**

- Mỗi lỗi gặp phải → ghi vào `troubleshooting-journal.md`: *triệu chứng / nguyên nhân / cách tìm ra / cách sửa*.
- Mỗi tuần commit ít nhất 1 lần vào repo dự án.
- Đầu mỗi tuần dành 20 phút ôn lại câu hỏi kiểm tra của tuần trước (ôn tập ngắt quãng).

---

## 2. Giai đoạn 3 tháng đầu (tuần 1–12)

### Tuần 1 — Linux: kiến trúc, filesystem, lệnh cơ bản (+ ôn Git)

| Mục | Nội dung |
|---|---|
| Bài học | Kernel/shell/userspace · Cây thư mục FHS · Đường dẫn tuyệt đối/tương đối · Lệnh file & thư mục · `less`, `head`, `tail`, `grep`, pipe, redirect · Git ôn tập (2h): clone, commit, push, `.gitignore` |
| Đầu ra | Tự di chuyển, tìm file, đọc log bằng terminal, không dùng File Explorer |
| Lab bắt buộc | Tạo repo `devops-journey` trên GitHub, commit ghi chú học tập; lab "Thám hiểm `/etc`, `/var/log`, `/proc`" |
| Dự án | Tạo repo `taskhub` (rỗng + README) |

### Tuần 2 — Linux: permissions, users, process, systemd

| Mục | Nội dung |
|---|---|
| Bài học | rwx, chmod (số & ký hiệu), chown, umask · user/group, sudo · process, PID, signal, `ps`, `top`, `kill` · systemd: unit, `systemctl`, `journalctl` · Kiểm tra systemd trên WSL |
| Đầu ra | Giải thích được mọi lỗi `Permission denied` gặp phải; quản lý được một service |
| Lab bắt buộc | Chạy một ứng dụng Java (jar mẫu) thành systemd service với user riêng, tự restart khi bị kill |
| Dự án | Ghi lại trong `docs/` quyền và user mà ứng dụng sẽ chạy |

### Tuần 3 — Linux: package, SSH, Bash, log, monitoring, cron

| Mục | Nội dung |
|---|---|
| Bài học | apt, repository · SSH key, `~/.ssh/config` · Bash: biến, điều kiện, vòng lặp, hàm, exit code, `set -euo pipefail` · Biến môi trường · Log & troubleshooting · `free`, `df`, `du`, `vmstat`, `iostat` · cron |
| Đầu ra | Viết script Bash có xử lý lỗi; quy trình 5 bước khi server "chậm" |
| Lab bắt buộc | Script `healthcheck.sh` ghi log tài nguyên chạy bằng cron mỗi 5 phút · **Break-fix Linux #1** |
| Dự án | Thêm `scripts/` vào repo `taskhub` |
| Kiểm tra | ✅ **Checkpoint GĐ 1** (xem §4) |

### Tuần 4 — Networking: TCP/IP, IP, CIDR, DNS

| Mục | Nội dung |
|---|---|
| Bài học | Mô hình OSI vs TCP/IP (mức DevOps cần) · IPv4, subnet mask, CIDR, chia subnet · Public/private IP · DHCP · DNS: phân giải, record, TTL · `ip`, `ping`, `traceroute`, `nslookup`, `dig` |
| Đầu ra | Chia subnet bằng tay; truy vết DNS của một domain |
| Lab bắt buộc | Thiết kế bảng IP cho một VPC giả định (sẽ dùng lại ở tuần 11) · Truy vết DNS với `dig +trace` |
| Dự án | `docs/network-plan.md` cho dự án |

### Tuần 5 — Networking: TCP/UDP, HTTP/TLS, NAT, firewall, proxy

| Mục | Nội dung |
|---|---|
| Bài học | TCP handshake, UDP · Port, `ss` · HTTP method/status/header · HTTPS & TLS, chứng chỉ · NAT, routing, gateway · Firewall · Load balancer, reverse proxy · `curl -v`, `tcpdump` |
| Đầu ra | Giải thích chi tiết "gõ URL vào trình duyệt thì chuyện gì xảy ra" |
| Lab bắt buộc | Cài Nginx trên WSL làm reverse proxy trước một app đơn giản · Bắt gói tin HTTP bằng `tcpdump` · **Break-fix Network #1** |
| Kiểm tra | ✅ **Checkpoint GĐ 2** |

### Tuần 6 — Git workflow nhóm + ứng dụng mẫu

| Mục | Nội dung |
|---|---|
| Bài học | Git internals (commit, tree, HEAD) · Branching, merge vs rebase · Conflict · PR, code review · Branch protection · GitHub Flow vs Git Flow · Tag, release, SemVer · Conventional Commits |
| Đầu ra | Làm việc trên repo theo quy trình PR |
| Lab bắt buộc | Tự tạo và giải quyết 3 loại conflict · Mô phỏng làm việc nhóm 2 người (2 thư mục clone) |
| Dự án | Tạo ứng dụng `taskhub` bằng Spring Boot (start.spring.io, Java 21): REST CRUD, Actuator, PostgreSQL, Flyway; chạy trên máy; bật branch protection cho `main`. Release `v0.1.0` |

### Tuần 7 — Docker: nền tảng

| Mục | Nội dung |
|---|---|
| Bài học | VM vs container (namespace, cgroup) · Image, layer, container · Dockerfile · Volume, bind mount · Network (bridge, DNS nội bộ) · Biến môi trường |
| Đầu ra | Giải thích được image layer và cache |
| Lab bắt buộc | Docker workshop chính thức · Chạy PostgreSQL bằng container với volume, kết nối từ app chạy trên máy |
| Dự án | Dockerfile đầu tiên cho `taskhub` |

### Tuần 8 — Docker: Compose, multi-stage, registry, security, debug

| Mục | Nội dung |
|---|---|
| Bài học | Multi-stage build cho Spring Boot · `compose.yaml`: service, healthcheck, `depends_on`, volume, network, `.env` · Registry (GHCR) · Non-root user, image nhỏ · Debug: `logs`, `exec`, `inspect`, `docker compose config` |
| Lab bắt buộc | **Spring Boot + PostgreSQL + Nginx bằng Docker Compose** · **Break-fix Docker #1** (5 lỗi cài sẵn) |
| Dự án | ✅ **taskhub v0** |
| Kiểm tra | ✅ **Checkpoint GĐ 3–4** |

### Tuần 9 — CI: GitHub Actions

| Mục | Nội dung |
|---|---|
| Bài học | CI/CD là gì · Build → Test → Package → Deploy · Workflow, event, job, step, runner · Cache Maven · Artifact · Matrix (nhận biết) |
| Lab bắt buộc | Pipeline build + test chạy mỗi PR; PR chỉ được merge khi CI xanh |
| Dự án | `.github/workflows/ci.yml` |

### Tuần 10 — CI: image, registry, secrets, môi trường

| Mục | Nội dung |
|---|---|
| Bài học | Build & push image lên GHCR · Tag image (SHA, SemVer) · Secrets & variables · Environments · Deployment strategies (khái niệm) · Rollback (khái niệm) · GitLab CI (đọc hiểu) |
| Lab bắt buộc | Pipeline release: tạo tag `v*` → build image → push GHCR · **Break-fix CI #1** |
| Dự án | ✅ **taskhub v1** |
| Kiểm tra | ✅ **Checkpoint GĐ 5** |

### Tuần 11 — AWS: tài khoản, IAM, chi phí, VPC

| Mục | Nội dung |
|---|---|
| Bài học | Cloud fundamentals · Shared Responsibility · Region/AZ · **Tạo tài khoản (Free plan), MFA, Budget** · IAM: user, group, role, policy · AWS CLI · VPC, subnet, route table, IGW, NAT (lý thuyết), SG vs NACL |
| Đầu ra | Vẽ được VPC và giải thích luồng gói tin vào/ra |
| Lab bắt buộc | Thiết lập tài khoản an toàn · Tạo VPC bằng tay theo bảng IP tuần 4 · AWS Cloud Practitioner Essentials (học song song, ~6h) |
| ⚠️ Chi phí | Kiểm tra Billing sau mỗi buổi |

### Tuần 12 — AWS: EC2, S3, triển khai thủ công

| Mục | Nội dung |
|---|---|
| Bài học | EC2: AMI, instance type, key pair, user data, EBS · IAM role cho EC2 · SSM Session Manager · S3: bucket, policy, versioning · CloudWatch cơ bản |
| Lab bắt buộc | Triển khai `taskhub` (Compose) lên EC2 Ubuntu 24.04; SG chỉ mở 80/443; SSH hardening · Dọn dẹp tài nguyên đúng checklist |
| Dự án | ✅ **taskhub v2** |
| Kiểm tra | 🎯 **Bài thi mốc 3 tháng** (xem §4) |

---

## 3. Giai đoạn tháng 4–6 (tuần 13–24)

### Tuần 13 — AWS: CD tự động, Route 53, CloudWatch

| Bài học | OIDC giữa GitHub Actions và AWS · Triển khai qua SSM hoặc SSH · Route 53 · CloudWatch logs/metrics/alarm |
|---|---|
| Lab bắt buộc | Pipeline tự động deploy lên EC2 khi merge vào `main` |
| Dự án | ✅ **taskhub v3** (phần CD) |

### Tuần 14 — AWS: RDS, ALB, Auto Scaling (lab ngắn)

| Bài học | RDS: Multi-AZ, backup, so sánh với PostgreSQL tự chạy · ELB/ALB, target group, health check · Auto Scaling group, launch template · Kiến trúc tham chiếu 2 AZ có NAT |
|---|---|
| Lab bắt buộc | Dựng kiến trúc ALB + ASG + RDS trong **một buổi** → kiểm tra → **xóa toàn bộ** · Viết so sánh "EC2 + Compose" và "ALB + ASG + RDS" |
| Kiểm tra | ✅ **Checkpoint GĐ 6** |

### Tuần 15 — Terraform nền tảng

| Bài học | IaC là gì · Provider, resource, data source · Variable, output, locals · State · Workflow `init/plan/apply/destroy` |
|---|---|
| Lab bắt buộc | Terraform Get Started AWS · Viết lại VPC + SG + EC2 của dự án bằng Terraform |

### Tuần 16 — Terraform nâng cao + Ansible

| Bài học | Module · Remote backend S3 (`use_lockfile`) · Môi trường dev/prod · Ansible: inventory, playbook, idempotency |
|---|---|
| Lab bắt buộc | Dựng/xóa toàn bộ hạ tầng bằng 1 lệnh · Playbook Ansible cài Docker lên EC2 · **Break-fix Terraform #1** (state drift) |
| Dự án | ✅ **taskhub v4** |
| Kiểm tra | ✅ **Checkpoint GĐ 7** |

### Tuần 17 — Monitoring & Metrics

| Bài học | Monitoring vs Logging vs Observability · Metrics, Golden Signals · Prometheus, exporter, PromQL · Grafana dashboard · Alertmanager · Spring Boot Actuator + Micrometer |
|---|---|
| Lab bắt buộc | Dashboard cho app + server, 2 alert (app down, disk > 80%) |

### Tuần 18 — Logging, backup, rollback, incident

| Bài học | Log tập trung: Loki + Alloy · Kiến trúc ELK/OpenSearch (lab trên laptop) · Tracing (khái niệm) · Incident response, postmortem · Backup/restore PostgreSQL · Rollback |
|---|---|
| Lab bắt buộc | Backup `pg_dump` → S3 bằng cron, **diễn tập restore** · Diễn tập rollback · **Incident drill #1** + postmortem |
| Dự án | ✅ **taskhub v5** |
| Kiểm tra | ✅ **Checkpoint GĐ 8** |

### Tuần 19 — Kubernetes nền tảng

| Bài học | Kiến trúc: control plane, worker node · Pod, ReplicaSet, Deployment · Service · ConfigMap, Secret · Namespace · kubectl |
|---|---|
| Lab bắt buộc | Kubernetes Basics (chạy trên kind/minikube) · Deploy `taskhub` + PostgreSQL bằng manifest |

### Tuần 20 — Kubernetes: Ingress, storage, Helm, troubleshooting

| Bài học | Ingress · PV, PVC, StorageClass · Helm chart · Probes · Troubleshooting: `describe`, `logs`, events |
|---|---|
| Lab bắt buộc | Đóng gói `taskhub` thành Helm chart · **Break-fix K8s #1** (CrashLoopBackOff, ImagePullBackOff, Service selector sai) |
| Dự án | ✅ **taskhub v6** |
| Kiểm tra | ✅ **Checkpoint GĐ 9** |

### Tuần 21 — Security & DevSecOps

| Bài học | Linux & SSH security (tổng hợp) · IAM least privilege · Secrets management · Network security · Container security · Quét dependency, image, IaC · Bảo mật trong pipeline · AWS security fundamentals |
|---|---|
| Lab bắt buộc | Thêm bước quét bảo mật vào CI (fail khi có lỗ hổng CRITICAL) · Rà soát IAM của dự án · Quét repo tìm secret bị lộ |
| Kiểm tra | ✅ **Checkpoint GĐ 10** |

### Tuần 22 — Hybrid Cloud, Jenkins, ôn tập sự cố

| Bài học | On-premises, virtualization, VMware, hybrid cloud (~6h) · Jenkins: chạy bằng Docker, đọc Jenkinsfile (~4h) |
|---|---|
| Lab bắt buộc | Jenkins tutorial chính thức · **Incident drill #2** (tổng hợp nhiều tầng) + postmortem |

### Tuần 23 — Hoàn thiện dự án

| Việc | README đầy đủ · Sơ đồ kiến trúc · Runbook vận hành · Dọn code, đánh giá chi phí thực tế · Video demo 5 phút |
|---|---|
| Dự án | ✅ **taskhub v1.0** |

### Tuần 24 — Chuẩn bị phỏng vấn

| Việc | CV · Luyện trình bày dự án 10 phút · Bộ câu hỏi Linux/Network/Docker/CI-CD/AWS · Mock interview (có thể nhờ tôi đóng vai người phỏng vấn) · Bài tập thực hành tuyển dụng mẫu |
|---|---|
| Kiểm tra | 🎯 **Bài thi mốc 6 tháng** |

---

## 4. Lịch kiểm tra định kỳ

Mỗi checkpoint gồm 3 phần, làm **không dùng AI và không xem lời giải**. Được phép xem docs chính thức và `man`.

| Phần | Hình thức | Đạt khi |
|---|---|---|
| A. Lý thuyết | 10–15 câu hỏi tự luận ngắn | ≥ 80% trả lời đúng bản chất |
| B. Thực hành | Làm một task mới (không có trong bài lab) | Hoàn thành trong thời gian quy định |
| C. Break-fix | Hệ thống có lỗi cài sẵn, tìm và sửa | Tìm ra nguyên nhân gốc và giải thích được cách tìm ra |

| Tuần | Checkpoint | Trọng tâm |
|---|---|---|
| 3 | GĐ 1 | Linux |
| 5 | GĐ 2 | Networking |
| 8 | GĐ 3–4 | Git + Docker |
| 10 | GĐ 5 | CI |
| **12** | 🎯 **Mốc 3 tháng** | Tổng hợp: dựng server mới từ đầu, triển khai `taskhub` trong 3 giờ |
| 14 | GĐ 6 | AWS |
| 16 | GĐ 7 | Terraform |
| 18 | GĐ 8 | Observability + incident |
| 20 | GĐ 9 | Kubernetes |
| 21 | GĐ 10 | Security |
| **24** | 🎯 **Mốc 6 tháng** | Phỏng vấn mô phỏng + sự cố mô phỏng trên dự án |

**Không đạt checkpoint?** Dùng tuần dự phòng (xem §5) — **không** chuyển sang giai đoạn sau khi phần nền còn hổng, đặc biệt với Linux và Networking.

---

## 5. Quy tắc khi bị chậm tiến độ

1. Kế hoạch có sẵn ~1–2 giờ dự phòng mỗi tuần. Chậm dưới 1 tuần → dùng giờ dự phòng.
2. Chậm hơn 1 tuần → cắt theo thứ tự ưu tiên (cắt phần trên trước):
   - 🟦 Nâng cao trong mọi module.
   - Ansible (giữ khái niệm, bỏ lab).
   - Lab ELK/OpenSearch (giữ Loki).
   - Jenkins lab (giữ phần đọc Jenkinsfile).
   - Hybrid/VMware rút còn 2 giờ.
3. **Không bao giờ cắt:** Linux, Networking, Docker, CI, AWS VPC/EC2/IAM, break-fix, dự án.
4. Nếu toàn bộ lộ trình kéo dài thành 7–8 tháng nhưng nền tảng vững, vẫn tốt hơn hoàn thành 6 tháng mà hiểu nông.
