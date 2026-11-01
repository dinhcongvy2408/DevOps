# Module 08 — Monitoring, Logging, Observability

> Tuần 17–18 · ~34 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 07 — Terraform + Ansible](../07-TERRAFORM-ANSIBLE/README.md), dự án [taskhub v4](../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) đã xong (dựng/xóa được toàn bộ hạ tầng bằng một lệnh)

## Mục lục

- [1. Vì sao DevOps phải biết observability?](#1-vì-sao-devops-phải-biết-observability)
- [2. Junior cần biết đến mức nào?](#2-junior-cần-biết-đến-mức-nào)
- [3. Bộ công cụ của module và vì sao chọn nó](#3-bộ-công-cụ-của-module-và-vì-sao-chọn-nó)
- [4. Chuẩn bị môi trường và cổng trên laptop](#4-chuẩn-bị-môi-trường-và-cổng-trên-laptop)
- [5. Chi phí khi lên AWS (v5)](#5-chi-phí-khi-lên-aws-v5)
- [6. Thứ tự bài học](#6-thứ-tự-bài-học)
- [7. Lab, diễn tập, break-fix, checkpoint và dự án](#7-lab-diễn-tập-break-fix-checkpoint-và-dự-án)
- [8. Quy ước dùng chung trong module](#8-quy-ước-dùng-chung-trong-module)
- [9. Gặp lại ở đâu](#9-gặp-lại-ở-đâu)
- [10. Checklist hoàn thành module](#10-checklist-hoàn-thành-module)
- [11. Nguồn học](#11-nguồn-học)

---

## 1. Vì sao DevOps phải biết observability?

Đến v4, `taskhub` đã có CI/CD, chạy trên AWS, dựng lại được bằng một lệnh. Nhưng hãy trả lời thật lòng mấy câu sau:

- Ngay lúc này, app có đang chạy không? Bạn biết bằng cách nào — mở trình duyệt thử?
- Hôm qua có bao nhiêu request lỗi 5xx? Chậm nhất là bao lâu?
- 3 giờ sáng ổ đĩa EC2 đầy 95% — **ai** biết, và biết **khi nào**?
- Người dùng báo "lúc 14h20 tạo task không được". Bạn tìm log của đúng lúc đó ở đâu, khi container đã bị tạo lại hai lần?
- Database bị xóa nhầm. Bản backup gần nhất ở đâu, và **đã ai từng thử restore nó chưa**?

Nếu câu trả lời là "không biết" hoặc "phải SSH vào xem", hệ thống của bạn đang **chạy mù**. Module này cho bạn đôi mắt.

| Bạn sẽ làm ở công việc thật | Cần kiến thức của module này |
|---|---|
| Trực sự cố (on-call): nhận cảnh báo lúc nửa đêm, phải biết nó có thật không | Alert có ý nghĩa, dashboard, runbook (bài [01](01-monitoring-logging-observability.md), [03](03-grafana-dashboards-alerting.md)) |
| "Dịch vụ chậm từ sáng, xem giúp" | Golden Signals, PromQL `rate`, `histogram_quantile` (bài [02](02-metrics-prometheus.md)) |
| "Lỗi này xảy ra lúc mấy giờ, với request nào?" | Log tập trung, truy vấn LogQL (bài [04](04-centralized-logging.md)) |
| "Request đi qua 5 service, chậm ở đâu?" | Tracing (bài [05](05-tracing-overview.md)) |
| Sự cố xong: viết postmortem, không đổ lỗi | Quy trình incident response (bài [06](06-incident-response.md)) |
| "Khôi phục database về sáng nay" | Backup/restore đã **diễn tập** ([Lab 02](labs/lab-02-backup-restore.md)) |
| Phỏng vấn: "Làm sao bạn biết hệ thống của bạn đang chạy tốt?" | Toàn bộ module — câu hỏi gần như chắc chắn gặp |

> **Câu trả lời phỏng vấn tốt nhất** không phải "em dùng Prometheus và Grafana", mà là: "Em định nghĩa SLO cho `taskhub` là 99,5% request thành công trong 30 ngày. Prometheus đo tỷ lệ lỗi; nếu vượt ngưỡng 5 phút thì Alertmanager gửi Telegram kèm link runbook. Log tập trung ở Loki nên em lọc được theo thời điểm và mức lỗi. Backup chạy mỗi đêm, và em đã diễn tập restore — mất 6 phút."

---

## 2. Junior cần biết đến mức nào?

| Chủ đề | Mức cần cho Junior | Có thể học sau |
|---|---|---|
| Monitoring vs logging vs observability, ba trụ cột | 🟥 Giải thích bằng ví dụ của `taskhub` | Profiling liên tục |
| Golden Signals, RED, USE, SLI/SLO/error budget | 🟥 Đặt được SLO đơn giản cho dự án và tính error budget | Alert theo burn rate nhiều cửa sổ |
| Prometheus: scrape, exporter, metric type, PromQL cơ bản | 🟥 Tự viết `rate`, `sum by`, `histogram_quantile` | Recording rule phức tạp, federation, Thanos/Mimir |
| Alert rule + Alertmanager (route, receiver, silence) | 🟥 Viết 2 alert có ý nghĩa, gửi được tới Telegram | Inhibition phức tạp, nhiều team |
| Grafana: datasource, dashboard, biến | 🟥 Dựng dashboard cho app + server | Grafana alerting nâng cao, plugin |
| Spring Boot Actuator + Micrometer | 🟥 Mở endpoint `prometheus`, đọc metric `http_server_requests` | Custom metric với `MeterRegistry` |
| Log tập trung: Loki + Alloy, LogQL | 🟥 Gom log container, lọc theo service và mức lỗi | Pipeline log phức tạp |
| Kiến trúc ELK/OpenSearch | 🟨 Biết thành phần và khác Loki thế nào; chạy thử trên laptop | Vận hành cluster OpenSearch |
| Tracing (OpenTelemetry, Tempo) | 🟨 Khái niệm: trace, span, context propagation | Instrument thật nhiều service |
| Incident response, postmortem | 🟥 Theo được quy trình, viết postmortem không đổ lỗi | Chỉ huy sự cố lớn |
| Backup/restore PostgreSQL | 🟥 Backup tự động lên S3 **và đã diễn tập restore** | Point-in-time recovery với WAL |

**Quy tắc vàng của module:** một hệ thống chưa từng được **diễn tập** khôi phục thì coi như **chưa có backup**; một alert không ai biết phải làm gì khi nhận được thì coi như **chưa có alert**.

---

## 3. Bộ công cụ của module và vì sao chọn nó

```text
                        ┌────────────── Grafana (xem: dashboard, truy vấn) ──────────────┐
                        │                                                                 │
                 truy vấn PromQL                                                  truy vấn LogQL
                        │                                                                 │
                        ▼                                                                 ▼
 taskhub /actuator/prometheus ◄── scrape ── Prometheus ── alert ──► Alertmanager ──► Telegram
 node_exporter (CPU, RAM, disk) ◄── scrape ──┘                                  (webhook-debug trên laptop)

 log stdout của mọi container ──► Alloy (đọc qua Docker API) ──► Loki (lưu log, giữ 7 ngày)
```

| Công cụ | Vai trò | Vì sao chọn |
|---|---|---|
| **Prometheus** | Thu (scrape) và lưu metric dạng time series; đánh giá alert rule | Chuẩn de facto cho metric trong cloud native; Spring Boot hỗ trợ sẵn qua Micrometer |
| **Alertmanager** | Nhận alert từ Prometheus, gom nhóm, chặn trùng, gửi đi (Telegram, email, webhook) | Đi kèm Prometheus; tách "phát hiện" khỏi "thông báo" |
| **Grafana** | Dashboard, truy vấn metric và log ở cùng một nơi | Phổ biến nhất; đọc được cả Prometheus lẫn Loki |
| **Loki** | Lưu log, chỉ đánh chỉ mục (index) theo label | Nhẹ hơn nhiều so với Elasticsearch/OpenSearch — vừa với một máy EC2 |
| **Grafana Alloy** | Thu log (và metric, trace) rồi gửi đi | **Promtail đã hết vòng đời (EOL) ngày 2/3/2026** theo tài liệu Loki; Alloy là công cụ thay thế chính thức |
| **node_exporter** | Xuất metric của máy chủ (CPU, RAM, disk, network) | Exporter chuẩn của Prometheus |

> ⚠️ Tutorial cũ trên mạng (trước 2026) thường dùng **Promtail** để gửi log vào Loki. Bạn sẽ gặp nó khi đọc tài liệu cũ — hiểu nó làm gì, nhưng **không** dùng cho dự án mới.

**Vì sao tự chạy (self-hosted) thay vì chỉ dùng CloudWatch?** Bài [01](01-monitoring-logging-observability.md) so sánh kỹ ba hướng: CloudWatch (đã học ở [AWS bài 10](../06-AWS/10-cloudwatch.md)), tự chạy, và dịch vụ SaaS. Tóm tắt: tự chạy cho bạn **hiểu từng mảnh** và là bộ công cụ xuất hiện nhiều nhất trong tin tuyển dụng; đổi lại bạn phải tự vận hành nó. Quyết định này được ghi thành ADR-0010 ở [v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md).

---

## 4. Chuẩn bị môi trường và cổng trên laptop

**Kiểm tra trước khi học:**

| Cần có | Kiểm tra | Nếu chưa có |
|---|---|---|
| Docker chạy được **trong WSL** | `docker info` trong WSL không báo `Cannot connect to the Docker daemon` | Bật WSL integration — bảng lỗi ở [Docker bài 01](../04-DOCKER/01-vm-vs-container-architecture.md) |
| Stack `taskhub` chạy được trên laptop | `docker compose ps` trong `~/projects/taskhub` thấy `nginx`, `taskhub`, `postgres` đều healthy | [Lab Spring Boot + PostgreSQL + Nginx](../04-DOCKER/labs/lab-springboot-postgres-compose/README.md) |
| RAM trống cho Docker Desktop | Thêm khoảng 1–1,5 GB cho bộ giám sát (số đo thật ở [labs/reference/README.md](labs/reference/README.md)) | Tắt bớt container không dùng; tăng RAM cho WSL nếu cần |
| AWS CLI + Terraform + Ansible từ Module 06–07 | `aws sts get-caller-identity --profile taskhub` | Chỉ cần ở tuần 18 khi làm v5 |

> **Môi trường của bạn:** WSL **Ubuntu 24.04**. Máy bạn đang chạy nhiều container của dự án khác, và cổng `8000`, `18000`, `55432` đã bị chiếm. **Mọi cổng** của module đều đổi được bằng biến môi trường — đừng tắt container của dự án khác để lấy cổng.

**Cổng trên laptop** (tất cả chỉ bind `127.0.0.1` — không ai trong mạng LAN truy cập được):

| Dịch vụ | Cổng mặc định | Đổi bằng biến | Publish ra host? |
|---|---|---|---|
| nginx của `taskhub` | `8000` (máy bạn đã bị chiếm) | `NGINX_HOST_PORT` (ví dụ `8080`) | Có |
| Grafana | `3000` | `GRAFANA_HOST_PORT` | Có, `127.0.0.1` |
| Prometheus | `9090` | `PROMETHEUS_HOST_PORT` | Có, `127.0.0.1` |
| Alertmanager | `9093` | `ALERTMANAGER_HOST_PORT` | Có, `127.0.0.1` |
| Loki | `3100` | — | **Không** (chỉ trong mạng Docker) |
| Alloy | `12345` (giao diện debug) | — | Không (tùy chọn `127.0.0.1`) |
| node_exporter | `9100` | — | Không |

Kiểm tra một cổng có trống không trước khi dùng:

```bash
# [WSL] không in gì = cổng trống
ss -ltn | grep -E ':(3000|9090|9093)\b'
docker ps --format '{{.Names}}\t{{.Ports}}' | grep -E ':(3000|9090|9093)->'
```

> Docker Desktop publish cổng ở phía Windows. Nếu `ss` trong WSL không thấy gì nhưng `docker compose up` vẫn báo `port is already allocated`, kiểm tra thêm bằng lệnh `docker ps` ở trên.

**Bộ giám sát là một Compose project riêng** (`taskhub-mon`), nối vào network `taskhub_default` của app. Vì vậy deploy lại app không làm mất dashboard và lịch sử metric — chi tiết ở [labs/reference/README.md](labs/reference/README.md).

**Nhãn môi trường dùng trong module:**

| Nhãn | Nghĩa |
|---|---|
| `[WSL]` | Terminal Ubuntu trên laptop |
| `[Container]` | Bên trong một container (`docker compose exec ...`) |
| `[Browser]` | Trình duyệt trên Windows (Grafana, Prometheus UI) |
| `[EC2]` | Bên trong máy EC2 (qua SSM Session Manager) |
| `[AWS Console]` | Giao diện web console.aws.amazon.com |
| `[GitHub]` | Giao diện web github.com |

---

## 5. Chi phí khi lên AWS (v5)

Tuần 17 và phần lớn tuần 18 học **hoàn toàn trên laptop — 0 USD**. Chỉ khi làm [v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md) bạn mới đưa bộ giám sát lên EC2.

**Vấn đề:** `t3.small` (2 GiB RAM) đang chạy app (giới hạn 768 MiB) + PostgreSQL + nginx đã gần đầy. Thêm Prometheus, Grafana, Loki, Alloy, Alertmanager, node_exporter thì **không vừa**. Số đo RAM thật của từng container nằm ở [labs/reference/README.md](labs/reference/README.md).

**Vì sao không chọn `t3.medium` (4 GiB)?** Tài khoản **Free plan** chỉ chạy được các loại instance nằm trong danh sách free-tier: `t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`, `m7i-flex.large` (theo [tài liệu EC2 về Free Tier](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) cho tài khoản tạo từ 15/7/2025). `t3.medium` không có trong danh sách.

**Lựa chọn của dự án:** đổi biến Terraform `instance_type` sang **`c7i-flex.large`** (2 vCPU, 4 GiB) — một thay đổi tại chỗ (stop/start), đúng như bạn đã thử ở v4.

| Loại | RAM | Giá on-demand Singapore (USD/giờ) | Chạy 24/7 (~730 giờ) | Chỉ bật khi học (~78 giờ/tháng) |
|---|---|---|---|---|
| `t3.small` (v2–v4) | 2 GiB | 0,0264 | ≈ 19,3 | ≈ 2,1 |
| `c7i-flex.large` (v5) | 4 GiB | 0,09778 | ≈ 71,4 | ≈ 7,6 |

Giá lấy từ dữ liệu giá công khai của AWS ngày 2026-10-31; chỉ tính phần compute. Cộng thêm EBS gp3 20 GiB và Public IPv4 như [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md) — bảng đầy đủ ở milestone v5.

> ⚠️ Chạy `c7i-flex.large` 24/7 sẽ tiêu hết **100 USD credit trong khoảng 1,3 tháng**, và tài khoản Free plan tự đóng khi hết credit. Quy tắc: `terraform destroy` (hoặc ít nhất stop) **mỗi khi dừng học**. Từ v4 bạn đã dựng lại được trong 10–30 phút — hãy tận dụng.

---

## 6. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 01 | [Monitoring, logging, observability](01-monitoring-logging-observability.md) — ba trụ cột, Golden Signals, RED/USE, SLI/SLO, triết lý alert | 17 | 3h | 🟥 |
| 02 | [Metrics với Prometheus](02-metrics-prometheus.md) — scrape, exporter, kiểu metric, PromQL, Actuator + Micrometer | 17 | 5h | 🟥 |
| 03 | [Grafana dashboard và alerting](03-grafana-dashboards-alerting.md) — datasource, panel, biến, alert rule, Alertmanager | 17 | 4h | 🟥 |
| — | [Lab 01 — Dashboard và 2 alert cho taskhub](labs/lab-01-dashboard-alerts.md) | 17 | 4h | 🟥 |
| 04 | [Log tập trung](04-centralized-logging.md) — Loki + Alloy, LogQL, log có cấu trúc; kiến trúc ELK/OpenSearch | 18 | 4h | 🟥 |
| 05 | [Tracing — tổng quan](05-tracing-overview.md) — trace, span, OpenTelemetry | 18 | 2h | 🟨 |
| 06 | [Incident response](06-incident-response.md) — quy trình sự cố, postmortem, backup/restore, rollback | 18 | 3h | 🟥 |
| — | [Lab 02 — Backup và diễn tập restore PostgreSQL](labs/lab-02-backup-restore.md) | 18 | 3h | 🟥 |
| — | [Incident drill #1](labs/incident-drill-01/README.md) + postmortem | 18 | 3h | 🟥 |

Lời giải câu hỏi và bài tập: thư mục [solutions/](solutions/) — **chỉ mở sau khi đã tự làm**. Thuật ngữ: [glossary.md](glossary.md). Bộ giám sát tham khảo hoàn chỉnh (thư mục `monitoring/` của `taskhub`): [labs/reference/](labs/reference/README.md) — ⚠️ chỉ mở sau khi đã tự viết.

---

## 7. Lab, diễn tập, break-fix, checkpoint và dự án

| Hạng mục | Tuần | Mô tả |
|---|---|---|
| [Lab 01 — Dashboard và alert](labs/lab-01-dashboard-alerts.md) | 17 | **Lab bắt buộc, 0 USD:** dashboard cho app + server; 2 alert: app down, disk > 80% |
| [Lab 02 — Backup và restore](labs/lab-02-backup-restore.md) | 18 | **Lab bắt buộc:** `pg_dump` tự động, restore vào database mới, đo thời gian khôi phục |
| [Incident drill #1](labs/incident-drill-01/README.md) | 18 | **Bắt buộc:** sự cố được dàn dựng trên laptop — phát hiện bằng alert → dashboard → log → khắc phục → viết postmortem |
| [Break-fix Monitoring #1](labs/break-fix-01/README.md) | 18 | Bộ giám sát bị cài lỗi: target không lên, alert không bao giờ bắn, log không về — tìm và sửa. Chạy local, **0 USD** |
| [Checkpoint Giai đoạn 8](checkpoint.md) | 18 | Lý thuyết + thực hành mới + break-fix, không dùng AI |
| [Dự án: taskhub v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md) | 17–18 | Giám sát + log + alert trên EC2, backup tự động lên S3, diễn tập restore và rollback; release `v0.7.0` |

---

## 8. Quy ước dùng chung trong module

| Thành phần | Giá trị |
|---|---|
| Phiên bản (bản ổn định mới nhất khi viết, 2026-10-31) | Prometheus 3.15.1 · Grafana 13.3.0 · Loki 3.7.9 · Grafana Alloy 1.21.3. Tag image chính xác (đã kiểm chứng bằng cách pull) ở [labs/reference/README.md](labs/reference/README.md) |
| Thư mục trong repo `taskhub` | `monitoring/` — `compose.yaml`, `prometheus/`, `alertmanager/`, `loki/`, `alloy/`, `grafana/` |
| Compose project | App: `taskhub` (network `taskhub_default`) · Giám sát: `taskhub-mon` (nối vào `taskhub_default`) |
| Job Prometheus | `taskhub` (`taskhub:8080/actuator/prometheus`), `node`, `prometheus`, `alertmanager`, `alloy` |
| Alert bắt buộc | `TaskhubDown` (app không scrape được 1 phút) · `HostDiskUsageHigh` (ổ gốc > 80% trong 5 phút) |
| Receiver | `telegram` (EC2 và laptop nếu bạn có bot) · `webhook-debug` (laptop, không cần Telegram) |
| Label log trong Loki | Ít giá trị (low cardinality): `container`, `compose_service`, `compose_project`, `level` |
| Thời gian giữ dữ liệu | Prometheus 7 ngày · Loki 7 ngày |
| Endpoint app | `/actuator/health` (public qua nginx) · `/actuator/prometheus` (**chỉ** trong mạng Docker — nginx chặn `/actuator/*` trừ `health`) |
| Bảo mật | Không cổng giám sát nào mở ra Internet. Trên EC2 vào Grafana qua **SSM port forwarding**; Security Group vẫn chỉ 80/443 |
| Secret | Mật khẩu admin Grafana, token bot Telegram: Parameter Store trên EC2, file `.env` không commit trên laptop |
| Backup | `pg_dump -Fc` chạy trên **host** EC2 (container không có quyền AWS vì hop limit 1) → `s3://taskhub-backups-<account-id>/pg-dumps/` |
| Phát hành | v5 → `v0.7.0` |
| Số tài khoản trong ví dụ | `111122223333` · GitHub user mẫu `phuong-dev` |

---

## 9. Gặp lại ở đâu

| Kiến thức ở đây | Gặp lại ở |
|---|---|
| Health check `/actuator/health`, mã 503 | Đã dùng cho Docker healthcheck, ALB; Kubernetes liveness/readiness probe (Module 09) |
| Metric và alert | Kubernetes: Prometheus scrape pod qua service discovery (Module 09) |
| Log stdout của container | Kubernetes: `kubectl logs`, log của pod thu bằng cùng Alloy (Module 09) |
| Postmortem, incident drill | Incident drill #2 tổng hợp nhiều tầng (tuần 22), câu chuyện phỏng vấn (Module 13) |
| Backup đã diễn tập restore | Rà soát bảo mật và vận hành v1.0 (Module 10, tuần 23) |
| SLO, error budget | Quyết định tốc độ phát hành, câu hỏi phỏng vấn SRE |

---

## 10. Checklist hoàn thành module

- [ ] 🟥 Phân biệt được monitoring, logging, observability; giải thích ba trụ cột bằng ví dụ của `taskhub`.
- [ ] 🟥 Nêu được 4 Golden Signals và đo được từng tín hiệu cho `taskhub`.
- [ ] 🟥 Đặt được SLO cho `taskhub` và tính error budget theo phút.
- [ ] 🟥 Viết được PromQL: tỷ lệ request, tỷ lệ lỗi 5xx, độ trễ p95, % ổ đĩa đã dùng.
- [ ] 🟥 Dashboard cho app + server, provisioning bằng file (không bấm tay).
- [ ] 🟥 Hai alert `TaskhubDown` và `HostDiskUsageHigh` bắn thật và tự hết (resolved) khi lỗi được sửa.
- [ ] 🟥 Log của mọi container vào Loki; lọc được log lỗi của `taskhub` trong một khoảng thời gian.
- [ ] 🟨 Giải thích được trace, span, context propagation; khi nào cần tracing.
- [ ] 🟥 Backup tự động lên S3 và **đã diễn tập restore**, có số đo thời gian khôi phục.
- [ ] 🟥 Hoàn thành incident drill #1 và viết postmortem không đổ lỗi.
- [ ] 🟥 Đạt [Checkpoint Giai đoạn 8](checkpoint.md) và hoàn thành [taskhub v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md).
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md).

---

## 11. Nguồn học

| Vai trò | Nguồn | Ghi chú | Kiểm tra ngày |
|---|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt, gắn với dự án `taskhub` | — |
| Chính | [Google SRE book — Chapter 6: Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) | Golden Signals, white-box/black-box, alert phải hành động được | 2026-10-31 |
| Chính | [Google SRE book — Chapter 4: Service Level Objectives](https://sre.google/sre-book/service-level-objectives/) | SLI, SLO, SLA | 2026-10-31 |
| Chính | [Prometheus — Overview](https://prometheus.io/docs/introduction/overview/) | Mô hình pull, thành phần | 2026-10-31 |
| Chính | [Grafana Alloy — Introduction](https://grafana.com/docs/alloy/latest/introduction/) | Alloy là gì | 2026-10-31 |
| Chính | [Grafana Loki — Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Promtail EOL 2/3/2026, chuyển sang Alloy | 2026-10-31 |
| Chính | [Spring Boot — Metrics](https://docs.spring.io/spring-boot/reference/actuator/metrics.html) | `/actuator/metrics`, `micrometer-registry-prometheus` | 2026-10-31 |
| Bổ sung | [Google SRE workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) | Error budget, burn rate (🟦) | 2026-10-31 |
| Bổ sung | [Brendan Gregg — The USE Method](https://www.brendangregg.com/usemethod.html) | Phương pháp USE | 2026-10-31 |
| Bổ sung | [Grafana blog — The RED Method](https://grafana.com/blog/the-red-method-how-to-instrument-your-services/) | Phương pháp RED (Tom Wilkie) | 2026-10-31 |
| Chi phí | [Amazon EC2 — Track your Free Tier usage](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | Loại instance được phép trên Free plan | 2026-10-31 |

Thuật ngữ của module: [glossary.md](glossary.md).
