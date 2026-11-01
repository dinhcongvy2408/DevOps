# Bước 2 — Lộ trình học DevOps / Cloud Engineer

> Đối tượng: người đã biết Java/SQL cơ bản, dùng qua Git, Docker, WSL, chưa vững Linux, Networking, AWS và debug.
> Mục tiêu: ứng tuyển **Junior DevOps / Cloud Engineer** sau 3–6 tháng, 15–18 giờ/tuần.

## Mục lục

- [1. Đánh giá khoảng trống kiến thức](#1-đánh-giá-khoảng-trống-kiến-thức)
- [2. Nguyên tắc thiết kế lộ trình](#2-nguyên-tắc-thiết-kế-lộ-trình)
- [3. Tổng quan các giai đoạn](#3-tổng-quan-các-giai-đoạn)
- [4. Thứ tự học và lý do](#4-thứ-tự-học-và-lý-do)
- [5. Các quyết định thiết kế quan trọng](#5-các-quyết-định-thiết-kế-quan-trọng)
- [6. Dự án xuyên suốt phát triển qua từng giai đoạn](#6-dự-án-xuyên-suốt-phát-triển-qua-từng-giai-đoạn)
- [7. Chiến lược kiểm soát chi phí AWS](#7-chiến-lược-kiểm-soát-chi-phí-aws)
- [8. Mốc 3 tháng và 6 tháng](#8-mốc-3-tháng-và-6-tháng)

Tài liệu liên quan: [Ma trận kỹ năng](skill-matrix.md) · [Kế hoạch theo tuần](weekly-study-plan.md) · [Cấu trúc giáo trình](curriculum-structure.md) · [Khảo sát nguồn](source-survey.md)

---

## 1. Đánh giá khoảng trống kiến thức

| Lĩnh vực | Hiện tại (tự đánh giá) | Khoảng trống chính | Mức ưu tiên |
|---|---|---|---|
| Linux | Dùng Ubuntu qua WSL, chưa vững quản trị | Permissions, process, systemd, log, troubleshooting | 🔴 Rất cao — nền của mọi thứ |
| Debug / đọc log | Yếu | Không có quy trình phân tích lỗi | 🔴 Rất cao — luyện **xuyên suốt**, không học riêng một lần |
| Networking | Cần học lại | IP/CIDR, DNS, TCP, HTTP/TLS, NAT, firewall | 🔴 Rất cao — thiếu phần này sẽ không hiểu VPC và Kubernetes |
| Git | Đã dùng | Branching chiến lược, PR, conflict, tag/release | 🟡 Trung bình — ôn nhanh, học thêm workflow nhóm |
| Docker | Có cài, chưa thạo | Image layers, network, volume, multi-stage, debug | 🔴 Cao |
| Java / Spring Boot | Cơ bản / mới bắt đầu | Chỉ cần đủ để build, cấu hình, đọc stack trace | 🟢 Thấp — DevOps không cần code Spring sâu |
| SQL / PostgreSQL | Cơ bản | Backup/restore, kết nối, user/quyền | 🟡 Trung bình |
| AWS | Chưa có nền thực hành | Toàn bộ | 🔴 Rất cao |
| CI/CD, Terraform, Monitoring, K8s | Chưa có | Toàn bộ | 🔴 Cao (theo thứ tự) |

**Kết luận:** điểm yếu lớn nhất không nằm ở công cụ nào cụ thể, mà ở **nền tảng (Linux + Networking) và khả năng tự debug**. Vì vậy lộ trình dành 5 tuần đầu cho nền tảng và đưa bài tập "sửa lỗi" (break-fix) vào **mọi** module.

---

## 2. Nguyên tắc thiết kế lộ trình

1. **Bản chất trước, công cụ sau.** Hiểu process, port, DNS trước rồi mới học Docker networking và Kubernetes Service.
2. **Mỗi tuần đều chạm vào dự án.** Không học lý thuyết suông nhiều tuần liền.
3. **Một công cụ chính cho mỗi loại việc.** GitHub Actions (CI/CD), Terraform (IaC), Prometheus + Grafana (metrics), Loki + Alloy (logs). Công cụ khác chỉ học ở mức nhận biết.
4. **Debug là kỹ năng chính, không phải phụ.** Mỗi module có phần "Đọc log và xử lý lỗi" và ít nhất một bài break-fix.
5. **Bảo mật lồng vào từng giai đoạn** (SSH key ở Linux, secrets ở CI/CD, IAM ở AWS…). Giai đoạn 10 chỉ tổng hợp và bổ sung.
6. **Phân tầng kiến thức:** 🟥 Bắt buộc · 🟨 Nên biết · 🟦 Nâng cao (học sau khi đi làm).
7. **Không học Kubernetes trước khi vững Linux, Networking, Docker, CI/CD** — đúng yêu cầu của bạn.

---

## 3. Tổng quan các giai đoạn

| GĐ | Chủ đề | Tuần | Giờ ước tính | Đóng góp vào dự án |
|---|---|---|---|---|
| 1 | Linux & System Administration | 1–3 | ~48h | Script vận hành, quản lý service, đọc log |
| 2 | Networking Fundamentals | 4–5 | ~32h | Hiểu luồng request; cấu hình Nginx reverse proxy thử nghiệm |
| 3 | Git & Workflow | 6 | ~16h | Repo dự án, branch protection, PR, quy ước commit; tạo ứng dụng Spring Boot mẫu |
| 4 | Docker & Container | 7–8 | ~32h | **v0:** Spring Boot + PostgreSQL + Nginx chạy bằng Docker Compose |
| 5 | CI/CD (GitHub Actions) | 9–10 | ~32h | **v1:** Pipeline build → test → scan → đẩy image lên registry |
| 6a | AWS nền tảng | 11–12 | ~34h | **v2:** Triển khai lên EC2 thủ công (VPC, SG, IAM role) |
| 6b | AWS mở rộng | 13–14 | ~34h | **v3:** CD tự động lên EC2; lab ngắn RDS/ALB/ASG; CloudWatch |
| 7 | Terraform (+ Ansible cơ bản) | 15–16 | ~34h | **v4:** Toàn bộ hạ tầng AWS bằng Terraform, state trên S3 |
| 8 | Monitoring, Logging, Observability | 17–18 | ~34h | **v5:** Prometheus, Grafana, Loki, Alloy, alert; backup/restore DB |
| 9 | Kubernetes (mức Junior) | 19–20 | ~34h | **v6:** Chạy ứng dụng trên Kubernetes local bằng Helm chart |
| 10 | Security & DevSecOps | 21 | ~17h | Rà soát bảo mật toàn dự án, quét image/dependency trong CI |
| 11 | Hybrid Cloud, VMware, On-Premises | 22 (một phần) | ~6h | Một mục trong README: dự án sẽ thay đổi thế nào nếu chạy on-premises |
| — | Ôn tập, Jenkins nhận biết, sự cố mô phỏng | 22 | ~11h | Bản ghi incident (postmortem) |
| — | Hoàn thiện dự án + phỏng vấn | 23–24 | ~34h | **v1.0:** README, sơ đồ kiến trúc, demo, CV, mock interview |

Tổng ≈ 400 giờ trong 24 tuần (~16,5 giờ/tuần). Mỗi tuần để **1–2 giờ dự phòng** cho phần chưa xong.

---

## 4. Thứ tự học và lý do

```text
Linux ──► Networking ──► Git ──► Docker ──► CI/CD ──► AWS ──► Terraform ──► Monitoring ──► Kubernetes ──► Security (tổng hợp)
  │           │                    │                    │                       │
  └── Bash, log, debug ────────────┴── luyện xuyên suốt ┴───────────────────────┘
```

| Đổi so với yêu cầu gốc? | Quyết định | Lý do |
|---|---|---|
| Không | Linux trước Networking | Các lệnh mạng (`ss`, `ip`, `dig`, `curl`) chạy trên Linux; cần thạo terminal trước |
| Có — điều chỉnh nhỏ | Git ôn **2 giờ ở tuần 1**, học đầy đủ ở tuần 6 | Ngay từ tuần 1 bạn cần commit script và ghi chú vào repo. Workflow nhóm (PR, review, release) để tuần 6 khi đã có thứ để quản lý |
| Không | Docker trước CI/CD | Pipeline sẽ build Docker image, cần hiểu image trước |
| Không | CI/CD trước AWS | Phần CI chạy được hoàn toàn miễn phí trên GitHub, không phụ thuộc AWS. Phần CD lên AWS làm ở tuần 13–14 |
| Có — điều chỉnh nhỏ | Monitoring học **sau** Terraform nhưng đưa CloudWatch cơ bản vào phần AWS | Cần hạ tầng ổn định (dựng lại được bằng Terraform) trước khi gắn monitoring stack |
| Có | Bảo mật lồng vào từng giai đoạn, GĐ 10 tổng hợp | Bảo mật học tách riêng ở cuối thường bị coi là "phần thêm". Thực tế mỗi bước đều có rủi ro riêng |

---

## 5. Các quyết định thiết kế quan trọng

### 5.1. CI/CD chính: GitHub Actions (Jenkins ở mức nhận biết)

| Tiêu chí | GitHub Actions | Jenkins |
|---|---|---|
| Chi phí khi học | Miễn phí cho repo public | Phải tự chạy server (local hoặc EC2) |
| Gắn với nơi lưu code | Có sẵn trong GitHub | Phải tích hợp thêm |
| Khả năng xác thực AWS không cần access key | Có OIDC, cấp quyền tạm thời | Cần cấu hình thêm |
| Phổ biến trong JD Việt Nam | Có | **Rất phổ biến**, nhất là công ty outsource/doanh nghiệp lâu năm |

**Kết luận:** học sâu GitHub Actions để tập trung vào **khái niệm** pipeline (stage, artifact, secret, environment, rollback). Tuần 22 có 1 lab Jenkins (chạy bằng Docker theo tutorial chính thức) để bạn đọc hiểu được `Jenkinsfile` khi phỏng vấn. Khái niệm giống nhau, chuyển công cụ sau này không khó.

### 5.2. Logging: Loki + Grafana Alloy cho dự án, ELK/OpenSearch ở mức hiểu

Elasticsearch/OpenSearch cần nhiều RAM, không chạy nổi trên EC2 nhỏ mà không tốn chi phí. Loki nhẹ hơn và cùng hệ sinh thái Grafana với Prometheus. **Không dùng Promtail** vì đã hết vòng đời từ 02/03/2026. ELK/OpenSearch sẽ có 1 lab chạy trên laptop của bạn để hiểu kiến trúc, vì JD vẫn hay nhắc đến.

### 5.3. Kubernetes: chạy local, không dùng EKS

EKS tính phí theo giờ cho control plane cộng thêm phí worker node — không phù hợp để học. Dùng **kind** hoặc **minikube** trên Docker Desktop: miễn phí, đủ để học mọi khái niệm Junior cần. EKS chỉ giới thiệu bằng sơ đồ.

### 5.4. Môi trường thực hành

| Việc | Ở đâu | Ghi chú |
|---|---|---|
| Linux, Bash, Networking cơ bản | WSL Ubuntu 24.04 | Một số thứ khác máy thật (systemd có thể chưa bật, mạng WSL qua NAT, không có firewall thật) — bài học sẽ ghi rõ điểm khác |
| Linux "như server thật" | EC2 Ubuntu 24.04 (từ tuần 11) | Bài tập SSH hardening, firewall, systemd thật |
| Docker, Compose, Kubernetes local | Docker Desktop + WSL | |
| Code Spring Boot | IntelliJ IDEA + Java 21 | |
| Viết tài liệu, YAML, Terraform | VS Code | |

### 5.5. Region AWS

Mặc định đề xuất **ap-southeast-1 (Singapore)** vì gần Việt Nam. Giá ở Singapore thường cao hơn một chút so với us-east-1. Tôi sẽ kiểm tra giá thật khi bắt đầu phần AWS và để bạn quyết định.

---

## 6. Dự án xuyên suốt phát triển qua từng giai đoạn

**Tên tạm:** `taskhub` — ứng dụng quản lý công việc (REST API CRUD) viết bằng Spring Boot, dùng PostgreSQL. Ứng dụng cố ý đơn giản để bạn tập trung vào phần DevOps.

| Phiên bản | Tuần | Bạn làm được gì | Kiến trúc |
|---|---|---|---|
| v-pre | 1–6 | Repo GitHub, script vận hành, ứng dụng chạy trên máy (`./mvnw spring-boot:run`) với PostgreSQL | Laptop |
| **v0** | 7–8 | Dockerfile multi-stage, `compose.yaml` gồm app + postgres + nginx, healthcheck, volume, `.env` | Laptop / Docker Compose |
| **v1** | 9–10 | GitHub Actions: build, test, quét lỗ hổng, đẩy image (gắn tag theo commit SHA) lên GHCR | GitHub |
| **v2** | 11–12 | EC2 trong VPC tự tạo, SG chỉ mở 80/443, đăng nhập bằng SSM hoặc SSH key, IAM role cho EC2, chạy Compose | AWS — 1 EC2 |
| **v3** | 13–14 | CD tự động lên EC2 qua OIDC (không lưu access key); lab ngắn: RDS, ALB + ASG, Route 53 (nếu có domain) | AWS |
| **v4** | 15–16 | Viết lại toàn bộ hạ tầng bằng Terraform (module, variable, output, remote state); Ansible cài đặt server | Terraform |
| **v5** | 17–18 | Actuator + Prometheus + Grafana + Loki + Alloy, dashboard, alert; backup `pg_dump` lên S3 bằng cron + bài diễn tập restore; quy trình rollback bằng image tag | Observability |
| **v6** | 19–20 | Manifest Kubernetes → Helm chart, chạy trên kind/minikube | Kubernetes local |
| **v1.0** | 21–24 | Rà soát bảo mật, README, sơ đồ kiến trúc, runbook, postmortem, video demo | Hoàn chỉnh |

Sơ đồ kiến trúc mục tiêu (v5) — sẽ vẽ chi tiết trong 12-PRACTICAL-PROJECT:

```text
Developer ──push──► GitHub ──► GitHub Actions ──build/test/scan──► GHCR (image)
                                     │ OIDC (quyền tạm thời)
                                     ▼
Internet ──► [Security Group 80/443] ──► EC2 (public subnet, VPC tự tạo)
                                           ├─ nginx (reverse proxy, TLS)
                                           ├─ taskhub (Spring Boot)
                                           ├─ postgres (volume)  ──cron pg_dump──► S3 (backup)
                                           ├─ prometheus / grafana / loki / alloy
                                           └─ IAM role (S3, CloudWatch) — không lưu access key trên máy
```

---

## 7. Chiến lược kiểm soát chi phí AWS

Bạn chưa có tài khoản AWS. Điều này có lợi: có thể căn thời điểm tạo tài khoản cho hợp lý.

1. **Tạo tài khoản ở tuần 11**, chọn **Free plan**. Cửa sổ 6 tháng sẽ kéo dài đến khoảng tuần 37 — đủ cho phần AWS, dự án và thời gian đi phỏng vấn (để demo).
2. Ngay buổi đầu tiên: bật MFA cho root, tạo IAM user/Identity Center cho việc hằng ngày, tạo **AWS Budget** với cảnh báo qua email.
3. **Không dùng NAT Gateway** trong dự án chính (~32 USD/tháng). Kiến trúc có NAT chỉ dựng trong lab ngắn rồi xóa ngay.
4. Hạn chế Public IPv4 (0,005 USD/giờ mỗi địa chỉ). Dự án chính chỉ dùng **1** địa chỉ.
5. RDS, ALB, ASG học bằng **lab ngắn có checklist xóa tài nguyên** ở cuối.
6. Mỗi bài lab AWS kết thúc bằng mục **"Dọn dẹp tài nguyên"** + lệnh AWS CLI để kiểm tra không còn tài nguyên sót.
7. Từ tuần 15 dùng `terraform destroy` để tắt toàn bộ hạ tầng khi không học, `terraform apply` để dựng lại.
8. **Tôi sẽ không bao giờ tự chạy lệnh tạo tài nguyên AWS.** Giáo trình chỉ hướng dẫn, bạn tự chạy.

> ⚠️ Free plan tự đóng tài khoản khi hết 6 tháng hoặc hết credit. Nếu muốn giữ dự án chạy lâu hơn để demo, phải nâng cấp lên Paid plan — khi đó các bước trên càng quan trọng.

---

## 8. Mốc 3 tháng và 6 tháng

### Mốc 3 tháng (cuối tuần 12) — "Triển khai được cơ bản"

Bạn phải tự làm được, **không cần AI tạo lệnh**:

- Quản trị một server Ubuntu: user, quyền, service, log, SSH key, cron, đọc tình trạng CPU/RAM/disk.
- Giải thích được điều gì xảy ra khi gõ một URL vào trình duyệt (DNS → TCP → TLS → HTTP → reverse proxy → app).
- Viết Dockerfile multi-stage và `compose.yaml` cho Spring Boot + PostgreSQL + Nginx; debug được container không khởi động.
- Viết pipeline GitHub Actions build/test/đẩy image.
- Triển khai ứng dụng lên EC2 trong VPC tự tạo với Security Group và IAM role đúng.

➡️ Đủ để **bắt đầu nộp CV** cho vị trí intern/fresher DevOps, hoặc System/Cloud Support.

### Mốc 6 tháng (cuối tuần 24) — "Junior DevOps / Cloud Engineer"

Thêm vào mốc 3 tháng:

- Hạ tầng hoàn toàn bằng Terraform, dựng lại/xóa trong vài phút.
- CD tự động, có quy trình rollback đã diễn tập.
- Monitoring + logging + alert; đã diễn tập ít nhất 2 sự cố và viết postmortem.
- Backup/restore database đã diễn tập thành công.
- Chạy ứng dụng trên Kubernetes bằng Helm; debug được Pod lỗi (`CrashLoopBackOff`, `ImagePullBackOff`, Service không kết nối).
- Dự án có README, sơ đồ kiến trúc, trình bày được trong 10 phút phỏng vấn.

➡️ Đủ để ứng tuyển **Junior DevOps / Cloud Engineer**.
