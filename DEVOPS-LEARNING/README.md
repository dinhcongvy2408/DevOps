# DEVOPS-LEARNING — Giáo trình DevOps & Cloud Engineer từ nền tảng đến đi làm

> Giáo trình cá nhân hóa cho người đã biết Java/SQL cơ bản, đang dùng Windows 11 + WSL Ubuntu 24.04 + Docker Desktop.
> Mục tiêu: **Junior DevOps / Cloud Engineer trong 3–6 tháng**, học 15–18 giờ/tuần.

## 📚 Học ngay

> Mở file này ở chế độ xem trước (**Ctrl+Shift+V**) một lần, sau đó chỉ cần bấm link. Quay lại trang trước: **Alt+←**.

| Tuần | Bài học | Lab / kiểm tra |
|---|---|---|
| **1** | [Linux 01 — Kiến trúc & Filesystem](01-LINUX/01-linux-architecture-filesystem.md) · [Linux 02 — Lệnh & xử lý văn bản](01-LINUX/02-essential-commands-text.md) · [Ôn tập Git nhanh](03-GIT/00-git-quick-review.md) | Lab trong mục 9 của mỗi bài |
| **2** | [Linux 03 — Permissions, Users & Groups](01-LINUX/03-permissions-users-groups.md) · [Linux 04 — Processes & systemd](01-LINUX/04-processes-systemd.md) | [Lab 02 — Java systemd service](01-LINUX/labs/lab-02-java-systemd-service.md) |
| **3** | [Linux 05 — Packages & SSH](01-LINUX/05-packages-ssh.md) · [Linux 06 — Bash scripting](01-LINUX/06-bash-scripting.md) · [Linux 07 — Logs & troubleshooting](01-LINUX/07-logs-monitoring-troubleshooting.md) · [Linux 08 — Cron](01-LINUX/08-cron-scheduling.md) | [Lab 03 — Healthcheck cron](01-LINUX/labs/lab-03-healthcheck-cron.md) · [Break-fix #1](01-LINUX/labs/break-fix-01/README.md) · [Checkpoint](01-LINUX/checkpoint.md) |
| **4** | [Network 01 — OSI & TCP/IP](02-NETWORKING/01-osi-tcpip-model.md) · [Network 02 — IPv4 & CIDR](02-NETWORKING/02-ipv4-subnet-cidr.md) · [Network 03 — DNS & DHCP](02-NETWORKING/03-dns-dhcp.md) · [Network 04 — Routing & NAT](02-NETWORKING/04-routing-nat-switching.md) | Lab trong mục 9 của mỗi bài |
| **5** | [Network 05 — TCP/UDP & firewall](02-NETWORKING/05-tcp-udp-ports-firewall.md) · [Network 06 — HTTP & TLS](02-NETWORKING/06-http-https-tls.md) · [Network 07 — Reverse proxy & LB](02-NETWORKING/07-load-balancing-reverse-proxy.md) · [Network 08 — Công cụ chẩn đoán](02-NETWORKING/08-network-troubleshooting-tools.md) | [Break-fix #1](02-NETWORKING/labs/break-fix-01/README.md) · [Checkpoint](02-NETWORKING/checkpoint.md) |
| **6** | [Git 01 — Bên trong Git](03-GIT/01-git-fundamentals-internals.md) · [Git 02 — Branch, merge, conflict](03-GIT/02-branching-merging-conflicts.md) · [Git 03 — Pull Request & review](03-GIT/03-github-pull-request-code-review.md) · [Git 04 — Quy trình nhóm](03-GIT/04-team-workflows.md) · [Git 05 — Tag & release](03-GIT/05-tags-releases-versioning.md) | [Lab conflict & làm việc nhóm](03-GIT/labs/lab-01-conflicts-team-simulation.md) · **Dự án:** [Tạo app Spring Boot taskhub](12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md) |
| **7** | [Docker 01 — VM vs container](04-DOCKER/01-vm-vs-container-architecture.md) · [Docker 02 — Image & container](04-DOCKER/02-images-containers.md) · [Docker 03 — Dockerfile & multi-stage](04-DOCKER/03-dockerfile-multistage.md) · [Docker 04 — Volume, network, env](04-DOCKER/04-volumes-networks-env.md) | Lab trong mục 9 của mỗi bài |
| **8** | [Docker 05 — Compose](04-DOCKER/05-docker-compose.md) · [Docker 06 — Registry](04-DOCKER/06-registry.md) · [Docker 07 — Bảo mật](04-DOCKER/07-docker-security.md) · [Docker 08 — Xử lý sự cố](04-DOCKER/08-container-troubleshooting.md) | [**Lab Spring Boot + PostgreSQL + Nginx**](04-DOCKER/labs/lab-springboot-postgres-compose/README.md) · [Break-fix #1](04-DOCKER/labs/break-fix-01/README.md) · [Checkpoint Git + Docker](04-DOCKER/checkpoint.md) · **Dự án:** [v0 — Docker Compose](12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md) |
| **9** | [CI/CD 01 — Khái niệm CI/CD](05-CICD/01-cicd-concepts.md) · [CI/CD 02 — GitHub Actions cơ bản](05-CICD/02-github-actions-basics.md) | [Lab 01 — CI chặn PR đỏ](05-CICD/labs/lab-01-ci-pr-gate.md) |
| **10** | [CI/CD 03 — Build & push image lên GHCR](05-CICD/03-github-actions-docker-registry.md) · [CI/CD 04 — Secrets, quyền, môi trường](05-CICD/04-secrets-environments.md) · [CI/CD 05 — Chiến lược triển khai & rollback](05-CICD/05-deployment-strategies-rollback.md) · [CI/CD 06 — GitLab CI (đọc hiểu)](05-CICD/06-jenkins-gitlab-overview.md) | [Lab 02 — Release lên GHCR](05-CICD/labs/lab-02-release-ghcr.md) · [Break-fix CI #1](05-CICD/labs/break-fix-01/README.md) · [Checkpoint CI](05-CICD/checkpoint.md) · **Dự án:** [v1 — CI](12-PRACTICAL-PROJECT/milestones/v1-ci.md) |
| **11** | [AWS 00 — Tạo tài khoản an toàn & kiểm soát chi phí](06-AWS/00-aws-account-setup-cost-safety.md) (làm **trước**) · [AWS 01 — Cloud fundamentals](06-AWS/01-cloud-fundamentals.md) · [AWS 02 — IAM](06-AWS/02-iam.md) · [AWS 03 — VPC](06-AWS/03-vpc-networking.md) · [AWS 06 — AWS CLI](06-AWS/06-aws-cli.md) | [Lab 01 — Dựng VPC bằng tay](06-AWS/labs/lab-01-vpc-by-hand.md) |
| **12** | [AWS 04 — EC2](06-AWS/04-ec2.md) · [AWS 05 — S3](06-AWS/05-s3.md) | [Lab 02 — Triển khai taskhub lên EC2](06-AWS/labs/lab-02-ec2-deploy-taskhub.md) · **Dự án:** [v2 — AWS EC2](12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) · 🎯 [Bài thi mốc 3 tháng](00-ROADMAP/exam-month-3.md) |
| **13** | [AWS 09 — Route 53](06-AWS/09-route53.md) · [AWS 10 — CloudWatch](06-AWS/10-cloudwatch.md) · [AWS 11 — Ghép thành hệ thống](06-AWS/11-putting-it-together.md) | **Dự án:** [v3 — CD tự động](12-PRACTICAL-PROJECT/milestones/v3-cd.md) |
| **14** | [AWS 07 — RDS](06-AWS/07-rds.md) · [AWS 08 — ELB & Auto Scaling](06-AWS/08-elb-autoscaling.md) | [Lab 03 — ALB + ASG + RDS (một buổi, xóa ngay)](06-AWS/labs/lab-03-alb-asg-rds-short.md) · [Break-fix AWS #1](06-AWS/labs/break-fix-01/README.md) · [Checkpoint AWS](06-AWS/checkpoint.md) |
| **15** | [IaC 01 — Khái niệm IaC](07-TERRAFORM-ANSIBLE/01-iac-concepts.md) · [IaC 02 — Terraform cơ bản](07-TERRAFORM-ANSIBLE/02-terraform-basics.md) | [Lab 01 — Terraform với Docker (0 USD)](07-TERRAFORM-ANSIBLE/labs/lab-01-terraform-local-docker.md) · [Lab 02 — Hạ tầng taskhub bằng Terraform](07-TERRAFORM-ANSIBLE/labs/lab-02-taskhub-infra-terraform.md) (bắt đầu) |
| **16** | [IaC 03 — State & remote backend](07-TERRAFORM-ANSIBLE/03-terraform-state-backend.md) · [IaC 04 — Module & môi trường](07-TERRAFORM-ANSIBLE/04-terraform-modules-environments.md) · [IaC 05 — Ansible](07-TERRAFORM-ANSIBLE/05-ansible-fundamentals.md) | [Lab 03 — Ansible qua SSM](07-TERRAFORM-ANSIBLE/labs/lab-03-ansible-ssm.md) · [Break-fix Terraform #1 (state drift)](07-TERRAFORM-ANSIBLE/labs/break-fix-01/README.md) · [Checkpoint IaC](07-TERRAFORM-ANSIBLE/checkpoint.md) · **Dự án:** [v4 — Terraform + Ansible](12-PRACTICAL-PROJECT/milestones/v4-terraform.md) |
| **17** | [Obs 01 — Monitoring, logging, observability](08-MONITORING-LOGGING/01-monitoring-logging-observability.md) · [Obs 02 — Prometheus & PromQL](08-MONITORING-LOGGING/02-metrics-prometheus.md) · [Obs 03 — Grafana & alerting](08-MONITORING-LOGGING/03-grafana-dashboards-alerting.md) | [Lab 01 — Dashboard + 2 alert](08-MONITORING-LOGGING/labs/lab-01-dashboard-alerts.md) |
| **18** | [Obs 04 — Log tập trung (Loki + Alloy)](08-MONITORING-LOGGING/04-centralized-logging.md) · [Obs 05 — Tracing](08-MONITORING-LOGGING/05-tracing-overview.md) · [Obs 06 — Xử lý sự cố, backup/restore](08-MONITORING-LOGGING/06-incident-response.md) | [Lab 02 — Backup & diễn tập restore](08-MONITORING-LOGGING/labs/lab-02-backup-restore.md) · [Incident drill #1](08-MONITORING-LOGGING/labs/incident-drill-01/README.md) · [Break-fix Observability #1](08-MONITORING-LOGGING/labs/break-fix-01/README.md) · [Checkpoint Observability](08-MONITORING-LOGGING/checkpoint.md) · **Dự án:** [v5 — Observability + backup](12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md) |

Song song mỗi tuần: [Dự án taskhub — việc tuần 1–6](12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md) · [Mẫu nhật ký debug](00-ROADMAP/templates/troubleshooting-journal-template.md)

## Mục lục

- [Học ngay](#-học-ngay)
- [Bắt đầu từ đâu?](#bắt-đầu-từ-đâu)
- [Trạng thái biên soạn](#trạng-thái-biên-soạn)
- [Bản đồ thư mục](#bản-đồ-thư-mục)
- [Cách học hiệu quả với giáo trình này](#cách-học-hiệu-quả-với-giáo-trình-này)
- [Nguyên tắc an toàn](#nguyên-tắc-an-toàn)

---

## Bắt đầu từ đâu?

1. Đọc [Lộ trình học](00-ROADMAP/learning-roadmap.md) — hiểu vì sao học theo thứ tự này.
2. Tự chấm điểm hiện tại trong [Ma trận kỹ năng](00-ROADMAP/skill-matrix.md).
3. Mở [Kế hoạch theo tuần](00-ROADMAP/weekly-study-plan.md) và bắt đầu **Tuần 1**.
4. Khi cần tìm tài liệu gốc: [Khảo sát nguồn](00-ROADMAP/source-survey.md).

## Trạng thái biên soạn

| Phần | Trạng thái |
|---|---|
| 00-ROADMAP (khảo sát nguồn, lộ trình, ma trận kỹ năng, kế hoạch tuần, cấu trúc giáo trình) | ✅ Đã duyệt — 2026-10-31 |
| [01-LINUX](01-LINUX/README.md) — 8 bài, 2 lab, break-fix, checkpoint, lời giải, glossary | ✅ Đã biên soạn — 2026-10-31 · break-fix + checkpoint đã chạy thử trong container |
| [02-NETWORKING](02-NETWORKING/README.md) — 8 bài, break-fix (Docker Compose), checkpoint, lời giải, glossary | ✅ Đã biên soạn — 2026-10-31 · lab Compose đã chạy thử |
| [03-GIT](03-GIT/README.md) — 6 bài, lab conflict & làm việc nhóm, lời giải, glossary | ✅ Đã biên soạn — 2026-10-31 |
| [04-DOCKER](04-DOCKER/README.md) — 8 bài, lab Spring Boot + PostgreSQL + Nginx, break-fix, checkpoint Git + Docker, lời giải, glossary | ✅ Đã biên soạn — 2026-10-31 · lab, break-fix, checkpoint, app Spring Boot đã chạy thử |
| [05-CICD](05-CICD/README.md) — 6 bài, 2 lab, workflow tham khảo (đã pin SHA), break-fix, checkpoint, lời giải, glossary | ✅ Đã biên soạn — 2026-10-31 · actionlint sạch, lab bg05 đã chạy thử; workflow chưa chạy trên GitHub |
| [06-AWS](06-AWS/README.md) — 12 bài, 3 lab, workflow CD tham khảo, break-fix (CloudFormation), checkpoint, lời giải, glossary | ✅ Đã biên soạn — 2026-10-31 (chưa chạy trên AWS thật; template đã qua cfn-lint) |
| [07-TERRAFORM-ANSIBLE](07-TERRAFORM-ANSIBLE/README.md) — 5 bài, 3 lab, code Terraform + Ansible tham khảo, break-fix state drift, checkpoint, lời giải, glossary | ✅ Đã biên soạn — 2026-10-31 · lab local, break-fix, checkpoint đã chạy thử; code tham khảo qua validate, tflint, trivy, ansible-lint; phần AWS chưa chạy trên AWS thật |
| [12-PRACTICAL-PROJECT](12-PRACTICAL-PROJECT/README.md) — khung dự án, v-pre (tuần 1–6), hướng dẫn tạo app, v0, v1, v2, v3, v4 | ✅ Đã biên soạn |
| [🎯 Bài thi mốc 3 tháng](00-ROADMAP/exam-month-3.md) | ✅ Đã biên soạn |
| [Mẫu nhật ký debug](00-ROADMAP/templates/troubleshooting-journal-template.md) | ✅ |
| Các module còn lại | ⏳ Theo thứ tự trong [curriculum-structure.md §5](00-ROADMAP/curriculum-structure.md#5-thứ-tự-biên-soạn-đề-xuất) |

## Bản đồ thư mục

| Thư mục | Nội dung | Tuần |
|---|---|---|
| [00-ROADMAP](00-ROADMAP/learning-roadmap.md) | Lộ trình, ma trận kỹ năng, kế hoạch tuần, khảo sát nguồn | — |
| [01-LINUX](01-LINUX/README.md) | Linux & System Administration | 1–3 |
| [02-NETWORKING](02-NETWORKING/README.md) | Networking Fundamentals | 4–5 |
| [03-GIT](03-GIT/README.md) | Git & Workflow | 1 (ôn), 6 |
| [04-DOCKER](04-DOCKER/README.md) | Docker & Container | 7–8 |
| [05-CICD](05-CICD/README.md) | CI/CD với GitHub Actions (+ Jenkins nhận biết) | 9–10, 22 |
| [06-AWS](06-AWS/README.md) | AWS Cloud | 11–14 |
| [07-TERRAFORM-ANSIBLE](07-TERRAFORM-ANSIBLE/README.md) | Infrastructure as Code | 15–16 |
| [08-MONITORING-LOGGING](08-MONITORING-LOGGING/README.md) | Monitoring, Logging, Observability | 17–18 |
| 09-KUBERNETES | Kubernetes mức Junior | 19–20 |
| 10-SECURITY | Security & DevSecOps | 21 (+ lồng trong mọi GĐ) |
| 11-HYBRID-CLOUD-VMWARE | On-premises, VMware, Hybrid Cloud | 22 |
| [12-PRACTICAL-PROJECT](12-PRACTICAL-PROJECT/README.md) | Dự án xuyên suốt `taskhub` | Xuyên suốt |
| 13-INTERVIEW-PREPARATION | Chuẩn bị phỏng vấn | 23–24 |
| 14-RESOURCE-LIBRARY | Thư viện tài liệu đã kiểm chứng | — |

## Cách học hiệu quả với giáo trình này

- **Hiểu trước, gõ lệnh sau.** Nếu không giải thích được một tham số, đừng chạy lệnh đó.
- **Ghi nhật ký debug** (`troubleshooting-journal.md`) cho mọi lỗi gặp phải. Đây sẽ là tài liệu quý nhất khi đi phỏng vấn.
- **Dùng AI như người hướng dẫn, không phải người làm thay.** Hỏi "tại sao", tự kiểm chứng câu trả lời bằng docs chính thức.
- **Làm bài tập tự làm trước khi xem lời giải.** Bị kẹt 30 phút → xem gợi ý cấp 1, chưa xem lời giải.

## Nguyên tắc an toàn

- ⚠️ Lệnh có thể xóa dữ liệu hoặc tạo tài nguyên AWS tính phí đều được đánh dấu rõ. Đọc kỹ trước khi chạy.
- Mỗi lab AWS có phần **ước tính chi phí** ở đầu và **dọn dẹp tài nguyên** ở cuối.
- Không commit secret (mật khẩu, access key, file `.env`) lên GitHub.
