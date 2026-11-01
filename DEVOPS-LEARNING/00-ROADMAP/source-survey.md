# Bước 1 — Khảo sát và kiểm chứng nguồn tài liệu

> Ngày khảo sát: **2026-10-31**. Tài liệu công nghệ thay đổi nhanh — mỗi nguồn đều ghi trạng thái kiểm chứng để bạn biết mức độ tin cậy.

## Mục lục

- [1. Cách đọc bảng](#1-cách-đọc-bảng)
- [2. Những phát hiện quan trọng khi khảo sát](#2-những-phát-hiện-quan-trọng-khi-khảo-sát)
- [3. Nguồn theo từng giai đoạn](#3-nguồn-theo-từng-giai-đoạn)
- [4. Nguồn tổng quan / định hướng](#4-nguồn-tổng-quan--định-hướng)
- [5. Khảo sát JD Junior DevOps tại Việt Nam](#5-khảo-sát-jd-junior-devops-tại-việt-nam)
- [6. Giới hạn của lần khảo sát này](#6-giới-hạn-của-lần-khảo-sát-này)

---

## 1. Cách đọc bảng

| Ký hiệu | Ý nghĩa |
|---|---|
| ✅ | Đã mở trang và đọc nội dung ngày 2026-10-31 |
| 🔎 | Xác nhận qua kết quả tìm kiếm, chưa mở trực tiếp trang (thường do trang render bằng JavaScript hoặc chặn truy cập tự động) |
| ⚠️ | Chưa kiểm chứng được — sẽ kiểm tra lại khi biên soạn module tương ứng |
| **[Chính]** | Nguồn học chính của chủ đề |
| [Bổ sung] | Nguồn phụ, dùng khi nguồn chính chưa đủ |
| Mới / Có nền | Dành cho người mới bắt đầu / người đã có nền tảng |
| EN / VI | Ngôn ngữ |

**Nguyên tắc chung:** giáo trình này tự giải thích kiến thức bằng tiếng Việt. Nguồn bên dưới là nơi bạn **kiểm tra lại, đọc sâu hơn và tra cứu khi đi làm**, không phải nơi bạn phải đọc hết.

---

## 2. Những phát hiện quan trọng khi khảo sát

Những điểm này ảnh hưởng trực tiếp đến thiết kế giáo trình. Nhiều tutorial cũ trên mạng **chưa cập nhật** các thay đổi này.

| # | Phát hiện | Ảnh hưởng đến giáo trình |
|---|---|---|
| 1 | **AWS Free Tier đã đổi mô hình** (tài khoản tạo sau 15/07/2025): nhận 100 USD credit khi đăng ký + tối đa 100 USD nếu hoàn thành hoạt động. Chọn **Free plan** thì không bị tính phí, nhưng tài khoản **tự đóng sau 6 tháng hoặc khi hết credit** (dữ liệu giữ 90 ngày để nâng cấp). Free plan chỉ cho dùng một số dịch vụ. Nguồn: [AWS Free Tier](https://aws.amazon.com/free/) ✅, [Choosing a plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) ✅ | Không tạo tài khoản AWS quá sớm. Tạo ở **tuần 11** để cửa sổ 6 tháng bao trùm toàn bộ phần AWS, Terraform, Monitoring và dự án. Các tutorial nói "EC2 t2.micro miễn phí 12 tháng" là **đã lỗi thời**. |
| 2 | **NAT Gateway và Public IPv4 tính phí theo giờ**: NAT Gateway 0,045 USD/giờ (US East Ohio) ≈ 32 USD/tháng chưa tính phí dữ liệu; mỗi Public IPv4 0,005 USD/giờ ≈ 3,6 USD/tháng, kể cả khi không dùng. Nguồn: [VPC Pricing](https://aws.amazon.com/vpc/pricing/) ✅ | Dự án chính **không dùng NAT Gateway**. Kiến trúc chuẩn có NAT (theo [AWS VPC example](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-example-private-subnets-nat.html) ✅) chỉ dựng trong lab ngắn (vài giờ) rồi xóa ngay. |
| 3 | **Promtail đã hết vòng đời (EOL) ngày 02/03/2026**, thay bằng **Grafana Alloy**. Nguồn: [Loki docs – Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) 🔎 | Phần Logging dùng **Grafana Alloy** để thu thập log, không dùng Promtail như các tutorial cũ. |
| 4 | **Terraform S3 backend có khóa state bằng file trên S3 (`use_lockfile = true`)**; khóa bằng DynamoDB (`dynamodb_table`) đã bị **deprecated**. Nguồn: [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) ✅ | Bài Remote Backend dùng `use_lockfile`, không tạo bảng DynamoDB như tutorial cũ. |
| 5 | **Spring Boot đã lên 4.x** (guide chính thức chạy Spring Boot 4.1.1, yêu cầu Java 17+). Nguồn: [Spring Boot with Docker](https://spring.io/guides/gs/spring-boot-docker) ✅ | Dự án dùng phiên bản Spring Boot ổn định hiện tại trên start.spring.io + Java 21. Lưu ý: nhiều tutorial trên mạng vẫn dùng 3.x, một số cấu hình có thể khác. |
| 6 | WSL của bạn là **Ubuntu 24.04 LTS** (kiểm tra bằng `lsb_release -a` ngày 2026-10-31: 24.04.1), hỗ trợ tiêu chuẩn đến **tháng 6/2029**. Ubuntu 22.04 LTS hết hỗ trợ tiêu chuẩn tháng 6/2027; Ubuntu **26.04 LTS** đã phát hành 23/04/2026. Nguồn: [Ubuntu list of releases](https://ubuntu.com/project/docs/release-team/list-of-releases/) 🔎 | WSL và máy chủ EC2 cùng chạy **Ubuntu 24.04 LTS** → lệnh và đường dẫn giống nhau. Không cần nâng cấp WSL trong suốt khóa học. Container sandbox ở Module 01 vẫn dùng image `ubuntu:22.04` (đã chạy thử) — khác phiên bản với WSL là chuyện bình thường. |
| 7 | **systemd trên WSL**: chỉ bật mặc định với bản Ubuntu cài bằng `wsl --install` gần đây; bản cũ phải bật trong `/etc/wsl.conf`. Nguồn: [Microsoft Learn – systemd in WSL](https://learn.microsoft.com/en-us/windows/wsl/systemd) ✅ | Bài systemd sẽ có bước **kiểm tra** trước (`ps -p 1 -o comm=`). Nếu cần bật, bạn tự làm theo hướng dẫn — tôi không tự sửa cấu hình máy bạn. |
| 8 | **Linux Journey** đã chuyển về `labex.io/linuxjourney`, vẫn miễn phí, không cần đăng ký. ✅ | Vẫn dùng làm nguồn bổ sung cho Linux. |
| 9 | Spring guide chính thức **không** dạy multi-stage build. ✅ | Bài Multi-stage build sẽ dựa vào Docker docs, tự viết Dockerfile cho dự án. |

---

## 3. Nguồn theo từng giai đoạn

### Giai đoạn 1 — Linux & System Administration

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | Giáo trình này (01-LINUX) + [Ubuntu Server docs](https://ubuntu.com/server/docs) | Mới → Có nền | EN | ✅ | Ubuntu docs luôn bám bản LTS mới nhất, có ghi chú khác biệt cho bản cũ |
| [Bổ sung] | [Linux Journey](https://labex.io/linuxjourney) | Mới | EN | ✅ | Miễn phí, không cần đăng ký. Các lab LabEx đi kèm có thể yêu cầu tài khoản/trả phí |
| [Bổ sung] | [MIT Missing Semester (2026)](https://missing.csail.mit.edu/) | Mới → Có nền | EN | ✅ | Bài Shell, Command-line Environment, Debugging rất hợp để luyện terminal |
| [Bổ sung] | [Red Hat Enterprise Linux docs](https://docs.redhat.com/) | Có nền | EN | ⚠️ | Tham khảo khi học sâu systemd, SELinux, quản trị hệ thống doanh nghiệp |

### Giai đoạn 2 — Networking Fundamentals

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | Giáo trình này (02-NETWORKING) — chỉ dạy phần DevOps cần | Mới | VI | — | Tập trung vào TCP/IP, CIDR, DNS, HTTP/TLS, NAT, firewall và cách debug |
| [Bổ sung] | [Cisco Networking Academy — Networking Essentials](https://www.netacad.com/courses/networking/networking-essentials) | Mới | EN | 🔎 | Miễn phí, tự học, ~70 giờ, có Packet Tracer. **Không cần học hết** — chỉ chọn module về IP, subnet, DNS, TCP/UDP |
| [Bổ sung] | Linux Journey — phần *Networking Nomad* | Mới | EN | ✅ | Ngắn, gắn với lệnh Linux |
| [Bổ sung] | NetworkChuck — loạt *"FREE CCNA"* và khóa subnetting trên YouTube/academy | Mới | EN | 🔎 | Dễ hiểu, giải trí. Chưa xác nhận được link playlist chính thức → sẽ ghi link cụ thể khi viết module |

### Giai đoạn 3 — Git & Workflow

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | [Pro Git (2nd Edition)](https://git-scm.com/book/en/v2) | Mới → Có nền | EN | ✅ | Miễn phí (CC BY-NC-SA 3.0). Chưa có bản tiếng Việt. Đọc chương 1–3, 5, 6 |
| [Bổ sung] | [GitHub Docs](https://docs.github.com/) — Pull requests, branch protection, releases | Mới | EN | ⚠️ | Kiểm tra từng trang khi viết module |
| [Bổ sung] | MIT Missing Semester — *Version Control and Git* | Có nền | EN | ✅ | Giải thích mô hình dữ liệu của Git |

### Giai đoạn 4 — Docker & Container

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | [Docker docs — Get started workshop](https://docs.docker.com/get-started/workshop/) | Mới | EN | ✅ | Run container → app stack → build image → share image |
| **[Chính]** | [Docker Compose quickstart](https://docs.docker.com/compose/gettingstarted/) | Mới | EN | ✅ | Dùng `compose.yaml`, có healthcheck, volume, `docker compose config`, `logs`, `exec` |
| [Bổ sung] | [Spring Boot with Docker](https://spring.io/guides/gs/spring-boot-docker) | Có nền | EN | ✅ | Non-root user, layering, Buildpacks. Không dạy multi-stage |
| [Bổ sung] | TechWorld with Nana — *Docker Tutorial for Beginners* (YouTube) | Mới | EN | 🔎 | Chưa xác nhận tên chính xác & link → bổ sung khi viết module |
| [Bổ sung] | [iximiuz Labs](https://labs.iximiuz.com/) | Có nền | EN | ✅ | Lab thật trên trình duyệt về container internals, networking. Có gói miễn phí + gói trả phí |

### Giai đoạn 5 — CI/CD

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | [GitHub Actions docs — Quickstart](https://docs.github.com/en/actions/get-started/quickstart) | Mới | EN | ✅ | Công cụ chính (lý do ở [learning-roadmap.md](learning-roadmap.md#5-các-quyết-định-thiết-kế-quan-trọng)) |
| [Bổ sung] | [Jenkins — Build a Java app with Maven](https://www.jenkins.io/doc/tutorials/build-a-java-app-with-maven/) | Mới | EN | ✅ | Chạy Jenkins bằng Docker Compose, Jenkinsfile Build/Test/Deliver. Dùng cho 1 lab nhận biết |
| [Bổ sung] | GitLab CI docs | Mới | EN | ⚠️ | Chỉ ở mức nhận biết cú pháp `.gitlab-ci.yml` |

### Giai đoạn 6 — AWS Cloud

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | AWS Documentation (VPC, EC2, IAM, S3, RDS, ELB, CloudWatch…) + giáo trình này | Mới → Có nền | EN | ✅ (VPC) | Giáo trình giải thích cách các dịch vụ **nối với nhau**, docs dùng để tra cứu |
| **[Chính]** | AWS Skill Builder — *AWS Cloud Practitioner Essentials* | Mới | EN | 🔎 | Miễn phí, tự học, cần AWS Builder ID. Bản Second Edition đã ngừng, dùng bản hiện tại |
| [Bổ sung] | [AWS VPC example: private subnets + NAT](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-example-private-subnets-nat.html) | Có nền | EN | ✅ | Kiến trúc tham chiếu ALB + ASG + 2 AZ. Dùng cho lab ngắn rồi xóa |
| [Bổ sung] | [AWS Free Tier](https://aws.amazon.com/free/) + [Choosing a plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) | Mới | EN | ✅ | Đọc **trước** khi tạo tài khoản |

### Giai đoạn 7 — Terraform & Ansible

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | [Terraform — Get Started AWS](https://developer.hashicorp.com/terraform/tutorials/aws-get-started) | Mới | EN | ✅ | 6 bài: IaC là gì → Install → Create → Manage → Destroy → HCP Terraform |
| **[Chính]** | [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) | Có nền | EN | ✅ | Dùng `use_lockfile`, không dùng DynamoDB |
| [Bổ sung] | TechWorld with Nana — Terraform course (~3 giờ, YouTube) | Mới | EN | 🔎 | Kiểm tra năm phát hành — có thể dùng cú pháp backend cũ |
| [Bổ sung] | [Ansible — Getting started](https://docs.ansible.com/ansible/latest/getting_started/index.html) | Mới | EN | ⚠️ | Trang trả về lỗi 429 khi kiểm tra → kiểm tra lại khi viết module |

### Giai đoạn 8 — Monitoring, Logging & Observability

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | [Prometheus — Overview](https://prometheus.io/docs/introduction/overview/) | Mới | EN | ✅ | Kiến trúc pull, exporter, PromQL, Alertmanager |
| **[Chính]** | [Grafana — Get started with Grafana and Prometheus](https://grafana.com/docs/grafana/latest/getting-started/get-started-grafana-prometheus/) | Mới | EN | ✅ | Hướng dẫn dùng Grafana Cloud; giáo trình sẽ chuyển sang Grafana chạy local bằng Docker |
| [Bổ sung] | Grafana Loki + Alloy docs | Có nền | EN | 🔎 | Thay cho Promtail (EOL) |
| [Bổ sung] | [OpenSearch docs](https://docs.opensearch.org/latest/getting-started/) | Có nền | EN | ⚠️ | Đã chuyển sang domain `docs.opensearch.org`. Chỉ dùng cho lab ELK/OpenSearch trên laptop |

### Giai đoạn 9 — Kubernetes

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | [Kubernetes Basics tutorial](https://kubernetes.io/docs/tutorials/kubernetes-basics/) | Mới | EN | ✅ | 6 module: tạo cluster → deploy → explore → expose → scale → rolling update |
| [Bổ sung] | TechWorld with Nana — Kubernetes ~4 giờ (YouTube) | Mới | EN | 🔎 | Các nguồn ghi tên video khác nhau → xác nhận khi viết module |
| [Bổ sung] | iximiuz Labs — Kubernetes | Có nền | EN | ✅ | Thực hành troubleshooting |

### Giai đoạn 10 — Security & DevSecOps

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | Giáo trình này + docs từng công cụ | Mới | VI | — | Bảo mật được lồng vào từng giai đoạn, giai đoạn 10 tổng hợp và bổ sung |
| [Bổ sung] | Trivy (quét image, dependency, IaC) | Mới | EN | ⚠️ | Link docs cũ trả 404 → tìm link đúng khi viết module |
| [Bổ sung] | Spring guide — chạy container bằng non-root user | Mới | EN | ✅ | |

### Giai đoạn 11 — VMware, Hybrid Cloud, On-Premises

| Vai trò | Nguồn | Trình độ | Ngôn ngữ | Trạng thái | Ghi chú |
|---|---|---|---|---|---|
| **[Chính]** | Giáo trình này — 1 bài tổng quan | Mới | VI | — | Chỉ cần mức hiểu khái niệm cho Junior |
| [Bổ sung] | Ubuntu Server docs — phần Virtualisation | Có nền | EN | ✅ | |

---

## 4. Nguồn tổng quan / định hướng

| Nguồn | Trạng thái | Đánh giá |
|---|---|---|
| [roadmap.sh/devops](https://roadmap.sh/devops) | ✅ | Bản đồ kỹ năng tổng thể. **Dùng để tra cứu, không dùng làm lộ trình học** — quá rộng cho người mới, không phân biệt Junior/Senior |
| Video trong thư mục của bạn: *"DevOps Roadmap - How to become a DevOps Engineer? What is DevOps?"* — TechWorld with Nana, [YouTube 9pZ2xmsSDdo](https://www.youtube.com/watch?v=9pZ2xmsSDdo) | ✅ tiêu đề / 🔎 kênh & năm | Phát hành khoảng **năm 2022**. Phần "DevOps là gì" và thứ tự học tổng quát vẫn đúng. Phần công cụ cụ thể có thể đã cũ. Tôi không xem được nội dung video, chỉ xác minh tiêu đề |
| freeCodeCamp (YouTube/News) | ⚠️ | Có nhiều khóa dài miễn phí. Chỉ đưa vào khi tìm được bài cụ thể đáng học |

---

## 5. Khảo sát JD Junior DevOps tại Việt Nam

Tổng hợp sơ bộ từ các tin tuyển dụng trên ITviec, TopDev, TopCV và trang tuyển dụng của Saigon Technology, VTI, Pixelz, AvePoint, Endava (kết quả tìm kiếm 🔎, nhiều tin đã hết hạn — chỉ dùng để thấy xu hướng):

- **Gần như luôn có:** Linux, Git, CI/CD (khái niệm + ít nhất 1 công cụ), Docker, AWS cơ bản (EC2, S3, VPC), Bash hoặc Python cơ bản.
- **Thường gặp:** Jenkins / GitLab CI / GitHub Actions (chỉ cần thạo 1), Terraform cơ bản, hiểu kiến trúc Kubernetes.
- **Điểm cộng:** Kubernetes thực chiến, chứng chỉ (AWS, RHCSA, LPIC), Azure/GCP, tiếng Anh tốt.
- **Bẫy cần lưu ý:** một số tin ghi "Junior" nhưng yêu cầu 2+ năm kinh nghiệm — thực chất là Middle. Phần 13-INTERVIEW-PREPARATION sẽ phân tích kỹ hơn.

---

## 6. Giới hạn của lần khảo sát này

Tôi ghi rõ để bạn không hiểu nhầm là mọi thứ đã được kiểm chứng:

1. Một số trang render bằng JavaScript (AWS Skill Builder, Cisco NetAcad) hoặc chặn truy cập tự động (Ansible docs trả 429) → chỉ xác nhận qua kết quả tìm kiếm.
2. **Chưa xác nhận được link chính xác** của từng video YouTube (TechWorld with Nana, NetworkChuck). Tôi sẽ không ghi link video cho đến khi xác minh được.
3. **Chưa tìm được nguồn tiếng Việt chất lượng đã kiểm chứng.** Kết quả tìm Viblo chỉ trả về trang hồ sơ trống. Vì vậy giáo trình tự viết bằng tiếng Việt là nguồn chính, nguồn bổ sung chủ yếu là tiếng Anh.
4. Giá AWS chỉ kiểm tra cho một số region. Khi bắt đầu phần AWS sẽ kiểm tra lại giá ở region bạn chọn.
5. Mỗi module sẽ **kiểm tra lại link** ngay lúc biên soạn (Bước 6).
