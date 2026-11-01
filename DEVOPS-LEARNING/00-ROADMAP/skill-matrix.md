# Ma trận kỹ năng Junior DevOps / Cloud Engineer

> Dùng file này để **tự chấm điểm** sau mỗi giai đoạn. Đánh giá bằng bằng chứng cụ thể, không đánh giá bằng cảm giác.

## Mục lục

- [1. Thang điểm](#1-thang-điểm)
- [2. Phân loại Must / Should / Nice](#2-phân-loại-must--should--nice)
- [3. Ma trận chi tiết](#3-ma-trận-chi-tiết)
- [4. Kỹ năng xuyên suốt](#4-kỹ-năng-xuyên-suốt)
- [5. Nhật ký tự đánh giá](#5-nhật-ký-tự-đánh-giá)

Liên quan: [Lộ trình](learning-roadmap.md) · [Kế hoạch tuần](weekly-study-plan.md)

---

## 1. Thang điểm

| Điểm | Mức | Mô tả | Ví dụ với Docker |
|---|---|---|---|
| 0 | Chưa biết | Chưa từng nghe hoặc chỉ biết tên | — |
| 1 | Nhận biết | Giải thích được khái niệm, làm theo hướng dẫn được | Chạy `docker run` theo tutorial |
| 2 | Làm được có tra cứu | Tự làm việc thông thường, cần tra docs | Viết Dockerfile cho app mới, có xem docs |
| 3 | Tự xử lý | Làm và **debug** được mà không cần làm theo hướng dẫn từng bước | Container chết khi khởi động → tự tìm ra nguyên nhân từ log |
| 4 | Hướng dẫn người khác | Giải thích được bản chất, đánh giá được giải pháp | Giải thích vì sao image to, tối ưu và giải thích từng bước |

**Mục tiêu Junior:** 🟥 Must Have đạt **3**, 🟨 Should Have đạt **2**, 🟦 Nice to Have đạt **1**.

---

## 2. Phân loại Must / Should / Nice

Phân loại dựa trên khảo sát JD Junior tại Việt Nam (xem [source-survey.md §5](source-survey.md#5-khảo-sát-jd-junior-devops-tại-việt-nam)). Yêu cầu của Middle/Senior **không** được tính vào Must Have.

- 🟥 **Must Have** — thiếu là trượt phỏng vấn Junior.
- 🟨 **Should Have** — có thì nổi bật hơn hẳn, nhà tuyển dụng thường hỏi.
- 🟦 **Nice to Have** — điểm cộng, học dần sau khi đi làm.

---

## 3. Ma trận chi tiết

Cột **Hiện tại** là ước tính từ thông tin bạn cung cấp — hãy tự sửa lại cho đúng.

### Linux

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng đã đạt |
|---|---|---|---|---|---|
| Filesystem, lệnh cơ bản, xử lý văn bản (`grep`, `awk`, `sed`, pipe) | 🟥 | 1 | 3 | 3 | Tìm 10 IP truy cập nhiều nhất từ access log bằng 1 pipeline |
| Permissions, ownership, users/groups | 🟥 | 1 | 3 | 3 | Giải thích và sửa lỗi `Permission denied` trong 3 tình huống khác nhau |
| Process, signals, systemd service | 🟥 | 0–1 | 3 | 3 | Viết unit file chạy app Java như service, tự khởi động lại khi chết |
| Package management (apt) | 🟥 | 1 | 3 | 3 | |
| SSH (key, config, port forwarding) | 🟥 | 1 | 3 | 3 | SSH bằng key, tắt đăng nhập mật khẩu trên EC2 |
| Bash scripting | 🟥 | 0–1 | 2 | 3 | Script backup có kiểm tra lỗi, log, exit code |
| Logs & troubleshooting (`journalctl`, `/var/log`) | 🟥 | 0–1 | 3 | 3 | Hoàn thành bài break-fix Linux không xem gợi ý |
| Giám sát tài nguyên (`top`, `free`, `df`, `du`, `iostat`) | 🟥 | 0–1 | 3 | 3 | |
| Cron, systemd timer | 🟨 | 0 | 2 | 3 | |
| LVM, mount, fstab | 🟨 | 0 | 1 | 2 | |
| SELinux / AppArmor | 🟦 | 0 | 0 | 1 | |

### Networking

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng đã đạt |
|---|---|---|---|---|---|
| Mô hình TCP/IP (OSI ở mức hiểu) | 🟥 | 0–1 | 3 | 3 | Xếp được lỗi vào đúng tầng (DNS? TCP? HTTP?) |
| IPv4, CIDR, subnet, public/private IP | 🟥 | 0–1 | 3 | 3 | Chia `10.0.0.0/16` thành 4 subnet đúng, không cần công cụ |
| DNS (record A, CNAME, TTL, resolve) | 🟥 | 0–1 | 3 | 3 | Dùng `dig` truy vết một domain |
| TCP/UDP, port, `ss` | 🟥 | 0–1 | 3 | 3 | Tìm process đang chiếm port 8080 |
| HTTP/HTTPS, status code, TLS cơ bản | 🟥 | 1 | 3 | 3 | Debug bằng `curl -v`, đọc được TLS handshake |
| NAT, routing, gateway | 🟥 | 0 | 2 | 3 | Giải thích vì sao instance trong private subnet cần NAT để ra Internet |
| Firewall (ufw/iptables khái niệm, Security Group) | 🟥 | 0 | 2 | 3 | |
| Reverse proxy, load balancing | 🟥 | 0 | 2 | 3 | Cấu hình Nginx reverse proxy cho Spring Boot |
| `tcpdump` | 🟨 | 0 | 1 | 2 | |
| DHCP, switching, VLAN | 🟦 | 0 | 1 | 1 | |

### Git

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| Commit, branch, merge, rebase cơ bản | 🟥 | 1–2 | 3 | 3 | |
| Giải quyết merge conflict | 🟥 | 1 | 3 | 3 | |
| Pull Request, code review, branch protection | 🟥 | 1 | 3 | 3 | Repo dự án bắt buộc PR + CI xanh mới được merge |
| Tag, release, semantic versioning | 🟨 | 0 | 2 | 3 | |
| Git internals, reflog, cứu commit bị mất | 🟦 | 0 | 1 | 2 | |

### Docker

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| VM vs container, image vs container | 🟥 | 1 | 3 | 3 | |
| Dockerfile, multi-stage build | 🟥 | 1 | 3 | 3 | Image runtime dùng JRE (không phải JDK), < 400MB, chạy bằng non-root user; giải thích được từng layer |
| Docker Compose | 🟥 | 1 | 3 | 3 | Dự án v0 |
| Volume, network, biến môi trường | 🟥 | 0–1 | 3 | 3 | Giải thích vì sao app gọi `postgres:5432` chứ không phải `localhost:5432` |
| Registry (GHCR / ECR) | 🟥 | 0 | 2 | 3 | |
| Debug container (`logs`, `exec`, `inspect`) | 🟥 | 0–1 | 3 | 3 | Hoàn thành break-fix Docker |
| Docker security cơ bản | 🟨 | 0 | 2 | 3 | |

### CI/CD

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| Khái niệm CI/CD, pipeline, artifact | 🟥 | 0 | 3 | 3 | |
| GitHub Actions (workflow, job, cache, secret, environment) | 🟥 | 0 | 2 | 3 | Dự án v1 |
| Triển khai tự động + rollback | 🟥 | 0 | 1 | 3 | Diễn tập rollback trong < 5 phút |
| Chiến lược triển khai (rolling, blue-green, canary) | 🟨 | 0 | 1 | 2 | |
| Jenkins (đọc hiểu Jenkinsfile) | 🟨 | 0 | 0 | 2 | |
| GitLab CI | 🟦 | 0 | 0 | 1 | |

### AWS

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| Cloud fundamentals, Shared Responsibility, Global Infrastructure | 🟥 | 0 | 2 | 3 | |
| IAM (user, role, policy, least privilege) | 🟥 | 0 | 2 | 3 | Viết policy chỉ cho phép đọc/ghi 1 bucket S3 |
| EC2 | 🟥 | 0 | 2 | 3 | |
| VPC, subnet, route table, IGW, NAT, SG, NACL | 🟥 | 0 | 2 | 3 | Vẽ và giải thích VPC của dự án |
| S3 | 🟥 | 0 | 2 | 3 | |
| AWS CLI | 🟥 | 0 | 2 | 3 | |
| Quản lý chi phí (Budget, Cost Explorer) | 🟥 | 0 | 2 | 3 | Không có hóa đơn ngoài dự kiến |
| RDS | 🟨 | 0 | 1 | 2 | |
| ELB, Auto Scaling | 🟨 | 0 | 1 | 2 | |
| Route 53 | 🟨 | 0 | 1 | 2 | |
| CloudWatch | 🟨 | 0 | 1 | 2 | |
| ECS / EKS / Lambda | 🟦 | 0 | 0 | 1 | |

### IaC

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| Terraform (provider, resource, variable, output, state, workflow) | 🟨→🟥 | 0 | 0 | 3 | Dự án v4 |
| Terraform module, remote backend | 🟨 | 0 | 0 | 2 | |
| Ansible cơ bản (inventory, playbook) | 🟨 | 0 | 0 | 2 | |

> Terraform ghi 🟨→🟥 vì JD Việt Nam thường yêu cầu ở mức cơ bản, nhưng ngày càng phổ biến. Với dự án có Terraform, bạn sẽ nổi bật.

### Monitoring & Logging

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| Phân biệt monitoring, logging, observability | 🟥 | 0 | 1 | 3 | |
| Prometheus + Grafana | 🟨 | 0 | 0 | 2 | Dashboard + 2 alert cho dự án |
| Loki / ELK / OpenSearch | 🟨 | 0 | 0 | 2 | |
| Incident response, postmortem | 🟨 | 0 | 0 | 2 | 2 bản postmortem |
| Tracing (OpenTelemetry) | 🟦 | 0 | 0 | 1 | |

### Kubernetes

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| Kiến trúc, Pod, Deployment, Service | 🟨 | 0 | 0 | 2 | |
| ConfigMap, Secret, Namespace | 🟨 | 0 | 0 | 2 | |
| Ingress, PV/PVC | 🟨 | 0 | 0 | 2 | |
| Helm | 🟨 | 0 | 0 | 2 | Dự án v6 |
| Debug Pod (`describe`, `logs`, events) | 🟨 | 0 | 0 | 2 | |
| RBAC, NetworkPolicy, HPA, Operator, service mesh | 🟦 | 0 | 0 | 1 | |

### Security

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| SSH hardening, least privilege | 🟥 | 0 | 2 | 3 | |
| Quản lý secrets (không commit secret, GitHub Secrets, OIDC) | 🟥 | 0 | 2 | 3 | Repo không chứa secret (kiểm tra bằng công cụ quét) |
| Quét image / dependency | 🟨 | 0 | 1 | 2 | |
| AWS security fundamentals | 🟨 | 0 | 1 | 2 | |

### Hybrid Cloud / VMware

| Kỹ năng | Loại | Hiện tại | Mục tiêu 3T | Mục tiêu 6T | Bằng chứng |
|---|---|---|---|---|---|
| On-premises, virtualization, hybrid cloud — khái niệm | 🟦 | 0 | 0 | 1 | |

---

## 4. Kỹ năng xuyên suốt

Những kỹ năng không thuộc một module nào nhưng quyết định bạn có làm được việc hay không:

| Kỹ năng | Loại | Cách luyện trong giáo trình |
|---|---|---|
| Quy trình debug có hệ thống (triệu chứng → giả thuyết → kiểm chứng → sửa → ghi lại) | 🟥 | Mỗi module có bài break-fix; bạn ghi lại vào `troubleshooting-journal.md` |
| Đọc log và stack trace Java | 🟥 | Phần "Đọc log và xử lý lỗi" trong mỗi bài |
| Đọc tài liệu chính thức | 🟥 | Bài tập yêu cầu tìm câu trả lời trong docs, ghi link nguồn |
| Viết tài liệu (README, runbook, postmortem) | 🟥 | Dự án xuyên suốt |
| Dùng AI đúng cách: hỏi để hiểu, tự kiểm chứng câu trả lời | 🟨 | Quy tắc: chỉ dùng lệnh AI gợi ý khi giải thích được từng tham số |
| Đọc tài liệu kỹ thuật tiếng Anh | 🟨 | Nguồn bổ sung chủ yếu bằng tiếng Anh |

---

## 5. Nhật ký tự đánh giá

Cập nhật sau mỗi giai đoạn. Chấm điểm trung bình các kỹ năng 🟥 của từng nhóm.

| Ngày | Giai đoạn vừa xong | Linux | Network | Git | Docker | CI/CD | AWS | IaC | Monitor | K8s | Security | Ghi chú |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | Bắt đầu | | | | | | | | | | | |
