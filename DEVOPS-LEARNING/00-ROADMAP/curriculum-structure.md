# Bước 3 — Cấu trúc giáo trình

> File này là **bản thiết kế** trước khi biên soạn. Sau khi bạn duyệt, mỗi module sẽ được viết theo đúng cấu trúc này.

## Mục lục

- [1. Mẫu cấu trúc một bài học](#1-mẫu-cấu-trúc-một-bài-học)
- [2. Quy ước chung](#2-quy-ước-chung)
- [3. Danh sách bài học theo module](#3-danh-sách-bài-học-theo-module)
- [4. Cấu trúc repo dự án taskhub](#4-cấu-trúc-repo-dự-án-taskhub)
- [5. Thứ tự biên soạn đề xuất](#5-thứ-tự-biên-soạn-đề-xuất)

---

## 1. Mẫu cấu trúc một bài học

Mỗi file bài học có đúng 15 phần theo yêu cầu, cộng mục lục và nguồn tham khảo:

```markdown
# <Số>. <Tên bài>

> Thời lượng ước tính · Mức độ: 🟥/🟨/🟦 · Kiến thức cần có trước: <link bài trước>

## Mục lục

1. Mục tiêu bài học
2. Tại sao DevOps Engineer cần kiến thức này?
3. Kiến thức nền tảng cần hiểu
4. Giải thích chi tiết (từ dễ đến khó)
5. Ví dụ thực tế
6. Sơ đồ kiến trúc / luồng hoạt động
7. Các câu lệnh cần biết
8. Giải thích câu lệnh và tham số (có đầu vào + đầu ra mẫu)
9. Bài thực hành từng bước
10. Kết quả mong đợi
11. Các lỗi thường gặp
12. Đọc log và xử lý lỗi
13. Câu hỏi kiểm tra kiến thức
14. Bài tập tự làm (không có lời giải ngay)
15. Tiêu chí đánh giá đã hiểu bài
— Nguồn tham khảo (nguồn chính + bổ sung, ngày kiểm tra link)
```

**Lưu ý về mục 14:** lời giải nằm trong file riêng `solutions/` của mỗi module, chỉ mở sau khi bạn đã tự làm.

---

## 2. Quy ước chung

| Quy ước | Cách áp dụng |
|---|---|
| Thuật ngữ | Lần đầu xuất hiện: **Container** (vùng chứa — tiến trình bị cô lập…). Mỗi module có `glossary.md` |
| Phân tầng | 🟥 Bắt buộc · 🟨 Nên biết · 🟦 Nâng cao — gắn ở đầu mỗi mục |
| Câu lệnh | Luôn có: lệnh → đầu ra mẫu → giải thích từng tham số. Đánh dấu ⚠️ cho lệnh nguy hiểm (xóa dữ liệu, tạo tài nguyên tính phí) |
| Môi trường | Ghi rõ lệnh chạy ở đâu: `[WSL]`, `[PowerShell]`, `[EC2]`, `[Container]` |
| Lab AWS | Bắt đầu bằng **ước tính chi phí**, kết thúc bằng **dọn dẹp tài nguyên + lệnh kiểm tra** |
| Phiên bản | Ghi phiên bản công nghệ đã dùng khi viết (ví dụ: Docker Engine x.y, Terraform x.y) |
| Liên kết | Liên kết nội bộ dạng tương đối; link ngoài ghi ngày kiểm tra |
| Break-fix | Mỗi module có ít nhất 1 bài: môi trường có lỗi cài sẵn + script tạo lỗi + gợi ý theo cấp độ |

---

## 3. Danh sách bài học theo module

Số bài được giữ ở mức vừa đủ: mỗi bài ~2–4 giờ học. Gộp những chủ đề nhỏ liên quan, không tách thành file sơ sài.

### 01-LINUX (tuần 1–3)

```text
01-LINUX/
├── README.md                           # Tổng quan module, thứ tự học, checklist
├── 01-linux-architecture-filesystem.md # Kernel, shell, FHS, đường dẫn, WSL khác server thật thế nào
├── 02-essential-commands-text.md       # Lệnh file, xem/tìm/lọc văn bản, pipe, redirect
├── 03-permissions-users-groups.md      # rwx, chmod, chown, umask, sudo, user/group
├── 04-processes-systemd.md             # Process, signal, systemd unit, systemctl, journalctl
├── 05-packages-ssh.md                  # apt, repository, SSH key, ssh config, scp/rsync
├── 06-bash-scripting.md                # Biến, điều kiện, vòng lặp, hàm, exit code, env vars
├── 07-logs-monitoring-troubleshooting.md # /var/log, journalctl, CPU/RAM/disk/network, quy trình debug
├── 08-cron-scheduling.md               # cron, systemd timer
├── labs/                               # Lab bắt buộc + break-fix
├── solutions/
├── glossary.md
└── checkpoint.md
```

### 02-NETWORKING (tuần 4–5)

```text
02-NETWORKING/
├── README.md                     # Gồm bảng "DevOps cần biết mạng đến mức nào"
├── 01-osi-tcpip-model.md
├── 02-ipv4-subnet-cidr.md        # Public/private IP, chia subnet bằng tay
├── 03-dns-dhcp.md
├── 04-routing-nat-switching.md   # Mức nền tảng
├── 05-tcp-udp-ports-firewall.md
├── 06-http-https-tls.md
├── 07-load-balancing-reverse-proxy.md  # Có lab Nginx
├── 08-network-troubleshooting-tools.md # ping, traceroute, nslookup, dig, curl, ss, netstat, tcpdump
├── labs/ · solutions/ · glossary.md · checkpoint.md
```

### 03-GIT (tuần 1 ôn + tuần 6)

```text
03-GIT/
├── README.md
├── 01-git-fundamentals-internals.md
├── 02-branching-merging-conflicts.md
├── 03-github-pull-request-code-review.md # Branch protection, repository management
├── 04-team-workflows.md                  # GitHub Flow, Git Flow, trunk-based
├── 05-tags-releases-versioning.md
├── labs/ · solutions/ · checkpoint.md
```

### 04-DOCKER (tuần 7–8)

```text
04-DOCKER/
├── README.md
├── 01-vm-vs-container-architecture.md  # namespace, cgroup, container runtime
├── 02-images-containers.md
├── 03-dockerfile-multistage.md
├── 04-volumes-networks-env.md
├── 05-docker-compose.md
├── 06-registry.md
├── 07-docker-security.md
├── 08-container-troubleshooting.md
├── labs/
│   └── lab-springboot-postgres-compose/ # Lab bắt buộc theo yêu cầu
├── solutions/ · checkpoint.md
```

### 05-CICD (tuần 9–10, Jenkins tuần 22)

```text
05-CICD/
├── README.md                    # Gồm lý do chọn GitHub Actions
├── 01-cicd-concepts.md          # Build, test, package, deploy, pipeline, artifact
├── 02-github-actions-basics.md
├── 03-github-actions-docker-registry.md
├── 04-secrets-environments.md
├── 05-deployment-strategies-rollback.md
├── 06-jenkins-gitlab-overview.md # Mức nhận biết
├── labs/ · solutions/ · checkpoint.md
```

### 06-AWS (tuần 11–14)

```text
06-AWS/
├── README.md
├── 00-aws-account-setup-cost-safety.md # Free plan, MFA, Budget — làm TRƯỚC mọi thứ
├── 01-cloud-fundamentals.md            # Global Infrastructure, Shared Responsibility
├── 02-iam.md
├── 03-vpc-networking.md                # VPC, subnet, route table, IGW, NAT, SG, NACL — nối với GĐ 2
├── 04-ec2.md
├── 05-s3.md
├── 06-aws-cli.md
├── 07-rds.md
├── 08-elb-autoscaling.md
├── 09-route53.md
├── 10-cloudwatch.md
├── 11-putting-it-together.md           # Các dịch vụ kết nối thành hệ thống thật thế nào
├── labs/ · solutions/ · checkpoint.md
```

### 07-TERRAFORM-ANSIBLE (tuần 15–16)

```text
07-TERRAFORM-ANSIBLE/
├── README.md
├── 01-iac-concepts.md
├── 02-terraform-basics.md      # Provider, resource, variable, output, workflow
├── 03-terraform-state-backend.md
├── 04-terraform-modules-environments.md
├── 05-ansible-fundamentals.md
├── labs/ · solutions/ · checkpoint.md
```

### 08-MONITORING-LOGGING (tuần 17–18)

```text
08-MONITORING-LOGGING/
├── README.md
├── 01-monitoring-logging-observability.md # Phân biệt 3 khái niệm
├── 02-metrics-prometheus.md
├── 03-grafana-dashboards-alerting.md
├── 04-centralized-logging.md              # Loki + Alloy; kiến trúc ELK/OpenSearch
├── 05-tracing-overview.md
├── 06-incident-response.md                # Quy trình, postmortem, backup/restore, rollback
├── labs/ · solutions/ · checkpoint.md
```

### 09-KUBERNETES (tuần 19–20)

```text
09-KUBERNETES/
├── README.md                   # Gồm bảng "Junior cần gì / học sau"
├── 01-architecture.md
├── 02-pods-deployments.md      # Pod, ReplicaSet, Deployment
├── 03-services-ingress.md
├── 04-config-secrets-namespaces.md
├── 05-storage.md
├── 06-helm.md
├── 07-troubleshooting.md
├── labs/ · solutions/ · checkpoint.md
```

### 10-SECURITY (tuần 21)

```text
10-SECURITY/
├── README.md
├── 01-security-mindset-checklist.md # Tổng hợp những gì đã học ở các GĐ trước
├── 02-secrets-management.md
├── 03-supply-chain-scanning.md      # Dependency, image, IaC scanning
├── 04-aws-security-fundamentals.md
├── labs/ · checkpoint.md
```

### 11-HYBRID-CLOUD-VMWARE (tuần 22)

```text
11-HYBRID-CLOUD-VMWARE/
└── README.md   # Một bài duy nhất: on-premises, virtualization, VMware, hybrid, khi nào dùng, Junior cần biết gì
```

### 12-PRACTICAL-PROJECT (xuyên suốt)

```text
12-PRACTICAL-PROJECT/
├── README.md                 # Mục tiêu, yêu cầu, tiêu chí đánh giá
├── architecture.md           # Sơ đồ kiến trúc từng phiên bản v0 → v1.0
├── milestones/
│   ├── v0-docker-compose.md
│   ├── v1-ci.md
│   ├── v2-aws-ec2.md
│   ├── v3-cd.md
│   ├── v4-terraform.md
│   ├── v5-observability-backup.md
│   ├── v6-kubernetes.md
│   └── v1.0-release.md
├── runbooks/                 # Deploy, rollback, backup/restore, xử lý sự cố
└── cost-control.md
```

### 13-INTERVIEW-PREPARATION

```text
13-INTERVIEW-PREPARATION/
├── README.md
├── jd-analysis.md            # Must/Should/Nice, Junior vs Senior
├── linux-questions.md
├── networking-questions.md
├── docker-cicd-questions.md
├── aws-questions.md
├── practical-tasks.md        # Bài tập thực hành tuyển dụng mẫu
└── project-presentation.md   # Cách trình bày taskhub trong 10 phút
```

### 14-RESOURCE-LIBRARY

Năm file theo yêu cầu (`official-docs.md`, `youtube-channels.md`, `free-courses.md`, `github-labs.md`, `reference-links.md`), tạo từ [source-survey.md](source-survey.md) và bổ sung dần khi biên soạn từng module.

---

## 4. Cấu trúc repo dự án taskhub

Repo dự án **tách riêng** khỏi thư mục giáo trình (đây là repo bạn đưa vào CV):

```text
taskhub/
├── README.md               # Giới thiệu, kiến trúc, cách chạy, cách deploy
├── app/                    # Spring Boot (Java 21, Maven)
├── docker/
│   ├── Dockerfile
│   └── nginx/
├── compose.yaml
├── .github/workflows/      # ci.yml, release.yml, deploy.yml
├── infra/
│   ├── terraform/          # modules/, envs/dev/
│   └── ansible/
├── monitoring/             # prometheus/, grafana/, loki/, alloy/
├── k8s/helm/taskhub/
├── scripts/                # backup.sh, restore.sh, healthcheck.sh
└── docs/                   # architecture, runbooks, postmortems, ADR
```

---

## 5. Thứ tự biên soạn đề xuất

Biên soạn theo thứ tự học, mỗi lần 1 module. Sau mỗi module, bạn học thử và góp ý trước khi tôi viết module tiếp theo.

| Lượt | Nội dung | Lý do |
|---|---|---|
| 1 | `README.md` gốc + 00-ROADMAP | ✅ Đã xong (lượt này) |
| 2 | 01-LINUX đầy đủ + 03-GIT phần ôn tập + khung 12-PRACTICAL-PROJECT | Bạn bắt đầu học được ngay tuần 1 |
| 3 | 02-NETWORKING | Tuần 4 |
| 4 | 03-GIT phần còn lại + 04-DOCKER + project v0 | Tuần 6–8 |
| 5 | 05-CICD + project v1 | Tuần 9–10 |
| 6 | 06-AWS + project v2, v3 | Tuần 11–14 |
| 7 | 07-TERRAFORM-ANSIBLE + v4 | |
| 8 | 08-MONITORING-LOGGING + v5 | |
| 9 | 09-KUBERNETES + v6 | |
| 10 | 10-SECURITY + 11-HYBRID + 13-INTERVIEW + 14-RESOURCE-LIBRARY hoàn chỉnh | |
| 11 | Bước 6–7: kiểm tra link/lệnh/phiên bản toàn bộ + báo cáo | |

Viết trước 1–2 module so với tiến độ học là đủ — tránh viết quá xa khi công cụ còn có thể thay đổi.
