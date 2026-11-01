# Milestone v5 — Observability, alert, backup và diễn tập khôi phục (tuần 17–18)

> Mức độ: 🟥 Bắt buộc (cAdvisor, postgres_exporter, probe ngoài bằng GitHub Actions là 🟨) · Kiến thức cần có trước: milestone [v4 — Terraform + Ansible](v4-terraform.md) (release `v0.6.0`), [Module 08 — Monitoring & Logging](../../08-MONITORING-LOGGING/README.md)
> Môi trường: `[WSL]` (terraform, ansible, aws, session-manager-plugin), `[EC2]` (qua Session Manager), `[Browser]` (Grafana qua SSM port forwarding), `[AWS Console]`, `[GitHub]`
> Đây là **việc cần nộp + tiêu chí chấp nhận**. Kiến thức nền: [bài 01 — Monitoring, logging, observability](../../08-MONITORING-LOGGING/01-monitoring-logging-observability.md), [bài 02 — Prometheus](../../08-MONITORING-LOGGING/02-metrics-prometheus.md), [bài 03 — Grafana & alert](../../08-MONITORING-LOGGING/03-grafana-dashboards-alerting.md), [bài 04 — Log tập trung](../../08-MONITORING-LOGGING/04-centralized-logging.md), [bài 05 — Tracing](../../08-MONITORING-LOGGING/05-tracing-overview.md), [bài 06 — Ứng phó sự cố](../../08-MONITORING-LOGGING/06-incident-response.md). Các bước làm chi tiết **trên laptop trước**: [Lab 01 — Dashboard + alert](../../08-MONITORING-LOGGING/labs/lab-01-dashboard-alerts.md), [Lab 02 — Backup & restore](../../08-MONITORING-LOGGING/labs/lab-02-backup-restore.md), [Incident drill #1](../../08-MONITORING-LOGGING/labs/incident-drill-01/README.md).

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc v5](#2-kiến-trúc-v5)
- [3. Chi phí — vì sao đổi sang c7i-flex.large](#3-chi-phí--vì-sao-đổi-sang-c7i-flexlarge)
- [4. Danh sách thay đổi](#4-danh-sách-thay-đổi)
- [5. File phải có trong repo](#5-file-phải-có-trong-repo)
- [6. Yêu cầu chất lượng](#6-yêu-cầu-chất-lượng)
- [7. Thử nghiệm bắt buộc](#7-thử-nghiệm-bắt-buộc)
- [8. Xử lý sự cố thường gặp](#8-xử-lý-sự-cố-thường-gặp)
- [9. Câu hỏi tự kiểm](#9-câu-hỏi-tự-kiểm)
- [10. Definition of Done và release v0.7.0](#10-definition-of-done-và-release-v070)
- [11. Dọn dẹp](#11-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu

Tới v4, bạn **dựng** được hệ thống bằng một lệnh — nhưng khi nó hỏng lúc 3 giờ sáng, bạn chỉ biết khi có người kêu. Và `terraform destroy` cuối buổi xóa luôn dữ liệu database. v5 trả lời ba câu hỏi phỏng vấn kinh điển bằng số đo thật:

| Câu hỏi | v5 trả lời bằng |
|---|---|
| "Làm sao bạn biết hệ thống đang hỏng — trước người dùng?" | Prometheus + Alertmanager → **tin nhắn Telegram** khi app chết, ổ đĩa > 80%, lỗi 5xx tăng; dashboard Grafana; log tập trung trong Loki |
| "Mất database thì sao?" | `pg_dump` hằng ngày lên S3 + **diễn tập restore có bấm giờ** (RPO/RTO đo được) + alert khi backup quá cũ |
| "Bản mới lỗi thì sao?" | **Rollback < 5 phút** bằng workflow Deploy (v3) — lần này bạn **thấy** nó trên dashboard |

Cụ thể:

1. App xuất metric qua `/actuator/prometheus` (Micrometer) và log **JSON có cấu trúc**; endpoint metric **không** lộ ra Internet qua nginx.
2. Thư mục `monitoring/` trong repo: Prometheus, Alertmanager, Loki, Alloy, Grafana (datasource + dashboard **provisioning** bằng code), node_exporter — chạy thành Compose project **riêng** `taskhub-mon`, vòng đời tách khỏi app.
3. **Không cổng giám sát nào mở ra Internet.** Grafana chỉ vào được qua **SSM port forwarding**; Security Group vẫn chỉ TCP 80 như v4.
4. Hai alert bắt buộc chạy thật end-to-end: `TaskhubDown`, `HostDiskUsageHigh` → Telegram.
5. Backup hằng ngày, restore đã diễn tập, có runbook và alert "backup quá cũ".
6. Một **người canh độc lập** ngoài máy: CloudWatch alarm `taskhub-status-check` (từ v3/v4) vẫn giữ — vì bộ giám sát chạy chung máy sẽ chết cùng máy.
7. Mọi thứ vẫn qua Terraform + Ansible: `plan` → *No changes*, Ansible lần 2 → `changed=0`.

---

## 2. Kiến trúc v5

```text
 Internet ──TCP 80──► SG taskhub-web-sg (chỉ 80) ──► EC2 taskhub-app  c7i-flex.large (2 vCPU, 4 GiB) · Ubuntu 24.04 · IMDSv2 hop 1
                                                        │
   ┌─ Compose project "taskhub" (network taskhub_default) ──────────────────────────────┐
   │  nginx :80 ──► taskhub :8080  (/actuator/* bị nginx chặn, trừ /actuator/health)     │
   │                   │  log JSON ra stdout                                            │
   │                   └──► postgres :5432 (volume pgdata)                              │
   └───────────▲───────────────────────────────────────────────▲────────────────────────┘
               │ scrape taskhub:8080/actuator/prometheus        │ docker logs API
   ┌─ Compose project "taskhub-mon" (nối vào taskhub_default + network riêng) ──────────┐
   │  prometheus (7d) ──rules──► alertmanager ──► Telegram (bot token từ file 0400)     │
   │      └─ scrape: taskhub, node-exporter, prometheus, alertmanager, alloy            │
   │  alloy ── docker.sock (read-only) ──► loki (7d, compactor)                          │
   │  grafana ── datasource Prometheus + Loki · dashboard taskhub-overview (provisioned) │
   │  node-exporter (/proc, /sys, / read-only) + textfile: taskhub_backup_last_success… │
   │  Mọi cổng: 127.0.0.1 — KHÔNG publish ra 0.0.0.0                                     │
   └────────────────────────────────────────────────────────────────────────────────────┘
   systemd timer (trên HOST, không trong container): scripts/backup.sh 18:00 UTC (01:00 giờ VN) hằng ngày, Persistent=true
        docker exec postgres pg_dump -Fc ──► aws s3 cp - s3://taskhub-backups-<acct>/pg-dumps/<ngày>.dump
        (AWS CLI snap trên host dùng instance role — container không có quyền AWS vì hop limit 1)

 [WSL] laptop ── aws ssm start-session … AWS-StartPortForwardingSession (3000 → localhost:13000) ──► [Browser] Grafana
 [AWS]  CloudWatch alarm taskhub-status-check + taskhub-cpu-high ──► SNS taskhub-alerts ──► email   ← người canh ĐỘC LẬP
 [AWS]  S3 taskhub-backups-<acct> (lớp bền bootstrap — sống qua mọi lần destroy)
 [AWS]  Parameter Store: /taskhub/dev/postgres-password · /taskhub/dev/grafana-admin-password · /taskhub/dev/telegram-bot-token
```

**Vì sao bộ giám sát là project Compose riêng?** Workflow Deploy chạy `deploy.sh` mỗi lần merge — nó chỉ được đụng tới app. Nếu Prometheus nằm chung project, mỗi lần deploy có nguy cơ khởi động lại luôn bộ giám sát, đúng lúc bạn cần nó nhất để xem bản mới có lỗi không.

**Vì sao vẫn giữ CloudWatch alarm?** Prometheus, Alertmanager và app chạy **trên cùng một máy**. Máy treo → không ai gửi alert. `taskhub-status-check` do AWS đo từ **bên ngoài** máy — đây là câu trả lời cho "who watches the watcher". Nó có điểm mù (máy bị *stop* thì không có dữ liệu, alarm không kêu — xem T7), và bạn phải ghi điểm mù đó vào ADR-0010.

---

## 3. Chi phí — vì sao đổi sang c7i-flex.large

**Bài toán bộ nhớ.** Lấy số `docker stats` thật trong [README bản tham khảo](../../08-MONITORING-LOGGING/labs/reference/README.md) và giới hạn `mem_limit` của bạn, cộng lại:

```text
taskhub (mem_limit 768m) + postgres + nginx            ≈ 1,0–1,2 GiB
prometheus + loki + alloy + grafana + alertmanager + node-exporter  ≈ 0,8–1,2 GiB (tùy mem_limit, retention)
Ubuntu + dockerd + snapd + SSM Agent                    ≈ 0,3–0,5 GiB
────────────────────────────────────────────────────────
Tổng ≈ 2,1–2,9 GiB  >  2 GiB của t3.small  →  OOM killer sẽ chọn "nạn nhân" (thường là JVM hoặc Prometheus)
```

Gói **Free plan chỉ cho chạy các loại máy đủ điều kiện free tier** (`t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`, `m7i-flex.large` — kiểm tra bằng `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true`). `t3.medium` (4 GiB) **không** có trong danh sách. Loại nhỏ nhất có 4 GiB trong danh sách là **`c7i-flex.large`**.

Giá on-demand Linux ở ap-southeast-1 (dữ liệu giá công khai của AWS, kiểm tra 2026-10-31):

| Khoản | Đơn giá | 24/7 (730 giờ/tháng) | Chỉ khi học (~78 giờ/tháng) | Ghi chú |
|---|---|---|---|---|
| EC2 `t3.small` (v2–v4) | 0,0264 USD/giờ | ≈ 19,3 USD | ≈ 2,1 USD | Để so sánh |
| EC2 **`c7i-flex.large`** (v5) | **0,09778 USD/giờ** | **≈ 71,4 USD** | **≈ 7,6 USD** | ≈ 3,7 lần `t3.small` |
| Public IPv4 | 0,005 USD/giờ | ≈ 3,7 USD | ≈ 0,4 USD | |
| EBS gp3 20 GiB | ≈ 0,096 USD/GB-tháng | ≈ 1,9 USD | ≈ 0–1,9 USD | Destroy cuối buổi (v4) → chỉ tính lúc tồn tại |
| S3 backup | ≈ 0,025 USD/GB-tháng + request | ≈ 0 | ≈ 0 | Một bản dump của taskhub chỉ vài trăm KB–vài MB |
| CloudWatch: 2 alarm, SNS email | Như [v3 §3](v3-cd.md#3-chi-phí) | ≈ 0 | ≈ 0 | Kiểm tra hạn mức miễn phí trên trang giá CloudWatch |
| CloudWatch Logs | **0** từ v5 | — | — | Bỏ driver `awslogs` (mục 4.6) — tiết kiệm phí ingest 0,70 USD/GB |
| Parameter Store Standard, IAM, VPC | 0 | | | |

**Kết luận phải ghi vào `docs/cost.md`:** chạy 24/7 ≈ 77 USD/tháng → 100 USD credit hết trong ~5 tuần và tài khoản Free plan bị đóng. Với `make down` cuối mỗi buổi (backup → destroy), ≈ 8–10 USD/tháng. **Từ v5, "destroy cuối buổi" không còn mất dữ liệu** vì đã có backup + restore (T10).

> Muốn tiết kiệm hơn? 🟦 Giữ `t3.small` cho các tuần không học giám sát, chỉ đổi `instance_type` khi làm v5 — một dòng trong `terraform.tfvars`, sửa tại chỗ (stop/start) như [v4 T6](v4-terraform.md#7-thử-nghiệm-bắt-buộc).

---

## 4. Danh sách thay đổi

### 4.1. Terraform (`infra/terraform/envs/dev`)

| Thay đổi | Chi tiết | Plan mong đợi |
|---|---|---|
| `instance_type = "c7i-flex.large"` trong `terraform.tfvars` | Biến đã có từ v4 | `~ update in-place` (stop/start, IP public đổi → cập nhật `APP_URL`) |
| Tham số `/taskhub/dev/grafana-admin-password` | Giống mật khẩu PostgreSQL: `ephemeral "random_password"` → `value_wo` + `value_wo_version` | `+ create` — giá trị không vào state |
| Bỏ `aws_cloudwatch_log_group.app` và quyền `logs:*` trong `taskhub-ec2-app` | Không còn driver `awslogs` (4.6) | `- destroy` log group (log cũ mất — đã quyết định trong ADR-0010) |
| Giữ alarm `taskhub-status-check`, `taskhub-cpu-high`, SNS `taskhub-alerts` | Người canh độc lập | Không đổi |
| **Không** thêm rule SG nào | Grafana qua SSM port forwarding | Không đổi |
| (Tùy chọn) `root_volume_size` | 20 GiB đủ với retention 7 ngày; image giám sát thêm ~2–3 GB — đo `df -h` trước khi quyết | — |

**Telegram bot token: tạo bằng tay, ngoài Terraform.** Token do bạn lấy từ BotFather — Terraform không "sinh" được nó. Hai cách:

| Cách | Ưu | Nhược |
|---|---|---|
| **`aws ssm put-parameter` một lần bằng tay** (chọn) | Đơn giản; token không bao giờ đi qua file `.tf`, `.tfvars` hay state; tham số sống qua mọi lần `destroy` | Một tài nguyên `ManagedBy=manual` — ghi ngoại lệ vào ADR-0010 như Budget, user admin |
| 🟦 Biến `ephemeral = true` → `value_wo` | Mọi thứ trong code | Tài liệu Terraform nói write-only argument nhận được giá trị ephemeral, nhưng **không** mô tả hành vi khi lần `apply` sau bạn không truyền biến — phải tự thử và ghi kết quả trước khi dùng |

```bash
# [WSL] một lần — gõ token vào biến từ bàn phím, KHÔNG để token trong lịch sử shell
read -rs TG_TOKEN
aws ssm put-parameter --name /taskhub/dev/telegram-bot-token --type SecureString \
  --value "$TG_TOKEN" --tags Key=Project,Value=taskhub Key=ManagedBy,Value=manual
unset TG_TOKEN
```

Quyền đọc: policy `taskhub-ec2-app` (v4) đã cho `ssm:GetParameter` trên `/taskhub/dev/*` → EC2 đọc được cả ba tham số, không sửa IAM.

### 4.2. App (`app/`, `docker/nginx/`)

Theo `app-changes/` trong [bản tham khảo](../../08-MONITORING-LOGGING/labs/reference/README.md) và [bài 02](../../08-MONITORING-LOGGING/02-metrics-prometheus.md), [bài 04](../../08-MONITORING-LOGGING/04-centralized-logging.md):

- `pom.xml`: `io.micrometer:micrometer-registry-prometheus` (phiên bản do Spring Boot quản lý — không ghi version).
- `application.yml`: mở `health,info,prometheus`; histogram cho `http.server.requests` (để tính p95); log JSON ra console (`logging.structured.format.console`).
- `docker/nginx/default.conf`: chặn `/actuator/` từ ngoài, **trừ** `/actuator/health` (load balancer, smoke test của Deploy vẫn dùng).
- Đây là thay đổi code → đi qua PR, CI build image mới; triển khai bằng workflow Deploy như mọi bản khác.

### 4.3. Thư mục `monitoring/`

Chép cấu trúc từ [08-MONITORING-LOGGING/labs/reference/](../../08-MONITORING-LOGGING/labs/reference/README.md) **sau khi** đã tự làm [Lab 01](../../08-MONITORING-LOGGING/labs/lab-01-dashboard-alerts.md) trên laptop. Chạy được trên laptop **và** EC2 bằng cùng file, khác nhau qua biến môi trường (cổng, receiver).

### 4.4. Ansible — role mới `monitoring`, mở rộng role `taskhub`

| Role | Việc | Ghi chú |
|---|---|---|
| `monitoring` (MỚI) | Copy `monitoring/` → `/opt/taskhub/monitoring`; lấy token Telegram và mật khẩu Grafana **trên EC2** bằng `aws ssm get-parameter --with-decryption` (instance role — như `deploy.sh`), ghi file quyền `0400`/`0440`, chủ sở hữu khớp UID của container đọc nó; `docker compose -p taskhub-mon up -d`; handler restart đúng service khi config đổi | Task chạm secret có `no_log: true`; secret không đi qua laptop. Idempotent: chỉ ghi file khi nội dung đổi |
| `taskhub` (mở rộng) | Copy `scripts/backup.sh`, `scripts/restore.sh`; systemd service + timer `taskhub-backup` (`OnCalendar=*-*-* 18:00:00 UTC`, `Persistent=true`, `Environment=PATH=...:/snap/bin`) bằng `ansible.builtin.template` + `ansible.builtin.systemd_service`; thư mục textfile cho node_exporter | Vì sao timer thay vì cron: EC2 bị **stop** khi không học — `Persistent=true` chạy bù lần backup bị lỡ khi máy bật lại, cron thì bỏ qua luôn; log nằm trong `journalctl -u taskhub-backup`. Giải thích trong ADR-0011 ([Lab 02](../../08-MONITORING-LOGGING/labs/lab-02-backup-restore.md)) |

### 4.5. Backup và restore (`scripts/`)

- `backup.sh` chạy **trên host**: `pg_dump -Fc` (đã nén — không gzip thêm) → stream thẳng lên `s3://taskhub-backups-<account-id>/pg-dumps/` (prefix mà inline policy `taskhub-ec2-s3-backup` cho phép); `set -euo pipefail`; chỉ ghi metric `taskhub_backup_last_success_timestamp_seconds` khi **thành công**; thoát khác 0 khi lỗi.
- `restore.sh`: tải bản dump chỉ định (hoặc mới nhất) → restore vào database **mới** `taskhub_restore` → so số dòng với bản gốc → in hướng dẫn "đổi chỗ" (swap) — không bao giờ ghi đè database đang chạy trong một bước.
- Lifecycle của bucket (lớp `bootstrap`, v4) quyết định giữ bao nhiêu ngày — ghi con số vào ADR-0011.
- **RPO** (tối đa mất bao nhiêu dữ liệu) = khoảng giữa hai lần backup = 24 giờ; **RTO** (bao lâu để chạy lại) = số đo của T4.

### 4.6. Quyết định về log: bỏ `awslogs`, Loki là nơi chứa log

| Lựa chọn | Ưu | Nhược |
|---|---|---|
| Giữ `awslogs` (v3) + thêm Loki | Log nằm ngoài máy, còn khi máy chết | Phí ingest 0,70 USD/GB; hai nơi tra cứu; phải kiểm chứng `loki.source.docker` đọc được log khi driver là `awslogs` (cơ chế dual logging của Docker) |
| **Chỉ Loki (chọn)** | Một nơi tra cứu, cùng Grafana với metric; 0 phí CloudWatch Logs | Máy chết → log 7 ngày gần nhất nằm trên EBS của máy đó (destroy là mất) |

Việc phải làm: xóa khối `logging:` trong `compose.aws.yaml` (hoặc xóa file nếu không còn gì), bỏ log group + quyền `logs:*` trong Terraform (4.1). Ghi rõ nhược điểm vào ADR-0010 — "log quan trọng nhất là log lúc máy chết" là phản biện bạn phải trả lời được.

### 4.7. Truy cập Grafana

```bash
# [WSL] — giữ terminal này mở; trên laptop dùng 13000 để khỏi đụng cổng 3000 đang bận
ID=$(terraform -chdir=infra/terraform/envs/dev output -raw instance_id)
aws ssm start-session --target "$ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["13000"]}'
# [Browser] http://localhost:13000 — user admin, mật khẩu:
aws ssm get-parameter --name /taskhub/dev/grafana-admin-password --with-decryption --query Parameter.Value --output text
```

Vì Grafana chỉ bind `127.0.0.1:3000` **trên EC2**, port forwarding của Session Manager nối tới đúng cổng đó từ bên trong máy — không cần mở SG, không cần public IP cho Grafana.

### 4.8. Tài liệu

- ADR-0010 — Prometheus + Grafana + Loki/Alloy tự chạy (so với chỉ CloudWatch, Grafana Cloud, ELK/OpenSearch): chi phí, RAM (lý do đổi `c7i-flex.large`), điểm mù chạy chung máy, người canh độc lập, bỏ `awslogs`, ngoại lệ tham số Telegram tạo tay.
- ADR-0011 — Backup `pg_dump` → S3 + diễn tập restore (so với snapshot EBS, RDS automated backup/PITR): RPO/RTO, lifecycle, vì sao chọn systemd timer (`Persistent=true`) thay vì cron, vì sao backup chạy trên host.
- `docs/runbooks/backup-restore.md` (MỚI), `docs/runbooks/rollback.md` (CẬP NHẬT từ v3: thêm "nhìn dashboard nào để quyết định rollback"), `docs/runbooks/incident-response.md` (MỚI — mức độ nghiêm trọng, vai trò, kênh liên lạc).
- `docs/slo.md` (MỚI) — SLI/SLO cho taskhub (ví dụ: tỷ lệ request không 5xx ≥ 99% trong 7 ngày; p95 < 500 ms), error budget, câu PromQL tính từng SLI.
- `docs/postmortems/` (MỚI) — postmortem của [Incident drill #1](../../08-MONITORING-LOGGING/labs/incident-drill-01/README.md) và của ít nhất một thử nghiệm ở mục 7.

---

## 5. File phải có trong repo

```text
taskhub/
├── app/pom.xml, app/src/main/resources/application.yml   # CẬP NHẬT — Micrometer Prometheus, exposure, histogram, log JSON
├── docker/nginx/default.conf                             # CẬP NHẬT — chặn /actuator/* trừ /actuator/health
├── compose.aws.yaml                                      # CẬP NHẬT/XÓA — bỏ driver awslogs
├── monitoring/                                           # MỚI
│   ├── compose.yaml                                      #   name: taskhub-mon · network ngoài taskhub_default · mem_limit · 127.0.0.1
│   ├── prometheus/prometheus.yml, prometheus/rules/alerts.yml
│   ├── alertmanager/alertmanager.yml                     #   receiver telegram (bot_token_file) + webhook-debug
│   ├── loki/config.yaml, alloy/config.alloy
│   └── grafana/provisioning/{datasources,dashboards}/, grafana/dashboards/taskhub-overview.json
├── scripts/backup.sh, scripts/restore.sh                 # MỚI
├── infra/terraform/envs/dev/                             # CẬP NHẬT — tfvars instance_type, tham số grafana, bỏ log group
├── infra/ansible/roles/monitoring/                       # MỚI
├── infra/ansible/roles/taskhub/                          # CẬP NHẬT — backup/restore + systemd timer
├── .github/workflows/infra.yml                           # CẬP NHẬT — thêm job kiểm tra monitoring/** (promtool, amtool) 🟨
├── Makefile                                              # CẬP NHẬT 🟨 — `make backup`, `make restore`, `make down` = backup rồi destroy
└── docs/
    ├── architecture.md                                   # CẬP NHẬT — sơ đồ v5
    ├── slo.md                                            # MỚI
    ├── runbooks/{backup-restore,incident-response}.md    # MỚI · rollback.md CẬP NHẬT
    ├── postmortems/                                      # MỚI
    ├── adr/0010-self-hosted-observability.md             # MỚI
    ├── adr/0011-pg-dump-s3-restore-drill.md              # MỚI
    ├── cost.md                                           # CẬP NHẬT — c7i-flex.large, 24/7 vs khi học
    └── experiments/v5-tests.md                           # MỚI — kết quả T1–T10
```

**Bản tham khảo:** [08-MONITORING-LOGGING/labs/reference/](../../08-MONITORING-LOGGING/labs/reference/README.md). ⚠️ Chỉ mở sau khi đã tự viết config của bạn ở Lab 01 — một file `prometheus.yml` chép về mà không giải thích được từng job là thứ người phỏng vấn hỏi đầu tiên.

---

## 6. Yêu cầu chất lượng

| # | Yêu cầu | Vì sao | Học ở |
|---|---|---|---|
| Q1 | **Không cổng giám sát nào ra Internet**: SG chỉ TCP 80; mọi cổng của `taskhub-mon` bind `127.0.0.1`; từ laptop `curl --max-time 5 http://<public-ip>:3000` và `:9090` đều **thất bại**; Grafana chỉ qua SSM port forwarding | Grafana/Prometheus lộ ra Internet là lỗ hổng phổ biến (lộ hạ tầng, tài khoản admin mặc định) | [Bài 03](../../08-MONITORING-LOGGING/03-grafana-dashboards-alerting.md), [AWS bài 03](../../06-AWS/03-vpc-networking.md) |
| Q2 | `curl $APP_URL/actuator/prometheus` → **403/404** qua nginx; đồng thời target `taskhub` trong Prometheus **UP** (scrape nội bộ `taskhub:8080`) | Metric chứa thông tin nội bộ (phiên bản, đường dẫn, số request) — chỉ dành cho hệ thống giám sát | [Bài 02](../../08-MONITORING-LOGGING/02-metrics-prometheus.md) |
| Q3 | **Secret**: mật khẩu Grafana và token Telegram chỉ ở Parameter Store (SecureString) và file `0400`/`0440` trên EC2; **không** trong Git, `.tfvars`, state, output Ansible (`no_log`), biến môi trường dạng chữ trong `compose.yaml`; Alertmanager dùng `bot_token_file`, Grafana đọc mật khẩu từ file | Như mật khẩu PostgreSQL từ v2 | [CI/CD bài 04](../../05-CICD/04-secrets-environments.md) |
| Q4 | Mọi container giám sát có `mem_limit`; `docker stats --no-stream` trên EC2 cho thấy tổng < 80% của 4 GiB; không container nào bị `OOMKilled` (`docker inspect … .State.OOMKilled`) | Bộ giám sát không được là thứ giết app | [Docker bài 01](../../04-DOCKER/01-vm-vs-container-architecture.md) |
| Q5 | **Retention**: Prometheus `--storage.tsdb.retention.time=7d` (và/hoặc theo dung lượng); Loki retention 7 ngày với compactor bật | Không có retention = ổ đĩa đầy dần — chính là alert Q7 sẽ bắn | [Bài 02](../../08-MONITORING-LOGGING/02-metrics-prometheus.md), [bài 04](../../08-MONITORING-LOGGING/04-centralized-logging.md) |
| Q6 | Mọi image giám sát ghim tag cụ thể (không `latest`), giống bản tham khảo đã chạy thử | Giống quy tắc image app từ v0 | [Docker bài 06](../../04-DOCKER/06-registry.md) |
| Q7 | Rule alert có `for:`, nhãn `severity`, annotation `summary`, `description` và `runbook_url` trỏ tới `docs/runbooks/…`; `promtool check config`/`check rules` và `amtool check-config` sạch | Alert không có runbook = người trực lúc 3 giờ sáng phải tự đoán | [Bài 03](../../08-MONITORING-LOGGING/03-grafana-dashboards-alerting.md), [bài 06](../../08-MONITORING-LOGGING/06-incident-response.md) |
| Q8 | **Cardinality thấp**: nhãn Loki chỉ `container`, `compose_service`, `compose_project`, `level`; không nhãn chứa giá trị không giới hạn (request id, user id, URL đầy đủ); tag `uri` của metric HTTP là **mẫu** (`/api/tasks/{id}`), không phải đường dẫn thật | Cardinality cao làm Loki/Prometheus phình RAM và chậm — trên máy 4 GiB là sự cố thật | [Bài 02](../../08-MONITORING-LOGGING/02-metrics-prometheus.md), [bài 04](../../08-MONITORING-LOGGING/04-centralized-logging.md) |
| Q9 | **Backup**: systemd timer hằng ngày (`Persistent=true`); `pg_dump -Fc`; tên file có ngày giờ UTC; lên đúng prefix `pg-dumps/`; script dừng và trả mã lỗi khi bất kỳ bước nào hỏng (kể cả lỗi giữa pipe); metric thành công chỉ ghi khi thành công; có alert backup quá cũ (> 26 giờ) | Backup "chạy" nhưng âm thầm ghi file rỗng là kiểu sự cố chỉ phát hiện lúc cần restore | [Lab 02](../../08-MONITORING-LOGGING/labs/lab-02-backup-restore.md), [Linux bài 06](../../01-LINUX/06-bash-scripting.md) |
| Q10 | **Restore đã diễn tập**: `restore.sh` khôi phục vào `taskhub_restore`, so số dòng; T4 có RTO đo thật; runbook làm theo được | "Backup chưa restore thử thì chưa phải backup" | [Bài 06](../../08-MONITORING-LOGGING/06-incident-response.md) |
| Q11 | **Log**: không còn driver `awslogs`; Terraform không còn log group/quyền `logs:*` (hoặc còn với lý do trong ADR); alarm `taskhub-status-check` vẫn còn và đã thử đường gửi SNS (T7) | Nhất quán giữa code và quyết định trong ADR-0010 | Mục 4.6 |
| Q12 | Mỗi alert có runbook; `docs/slo.md` có SLI tính bằng PromQL thật; ít nhất **một postmortem** blameless | Alert → runbook → postmortem là vòng khép kín của vận hành | [Bài 06](../../08-MONITORING-LOGGING/06-incident-response.md) |
| Q13 | Idempotency giữ nguyên: sau `apply`, `terraform plan -detailed-exitcode` = 0; Ansible lần 2 `changed=0` **kể cả role `monitoring`** | Như Q5 của v4 | [v4 §6](v4-terraform.md#6-yêu-cầu-chất-lượng) |

**Kiểm tra nhanh** `[WSL]`:

```bash
IP=$(terraform -chdir=infra/terraform/envs/dev output -raw public_ip)
for p in 3000 3100 9090 9093 9100 12345; do curl -s --max-time 5 -o /dev/null "http://$IP:$p" && echo "⚠️ $p MỞ" || echo "ok $p đóng"; done
curl -s -o /dev/null -w '%{http_code}\n' "http://$IP/actuator/prometheus"     # 403 hoặc 404
curl -s -o /dev/null -w '%{http_code}\n' "http://$IP/actuator/health"         # 200
grep -rnE 'image: [^ ]+:latest|image: [^:]+$' monitoring/compose.yaml ; echo "↑ phải rỗng"
grep -rn 'awslogs' compose*.yaml ; echo "↑ phải rỗng"
```

---

## 7. Thử nghiệm bắt buộc

Ghi **thao tác → quan sát (lệnh + output rút gọn, ảnh chụp dashboard/tin nhắn) → giải thích** vào `docs/experiments/v5-tests.md`. Làm trên laptop trước ([Lab 01](../../08-MONITORING-LOGGING/labs/lab-01-dashboard-alerts.md), [Lab 02](../../08-MONITORING-LOGGING/labs/lab-02-backup-restore.md)), rồi trên EC2.

| # | Thử nghiệm | Cách làm | Kết quả mong đợi — bạn phải giải thích được |
|---|---|---|---|
| T1 | **Alert end-to-end: app chết** | `[EC2]` bấm giờ → `docker compose -p taskhub stop taskhub` → chờ Telegram → `start` → chờ tin *resolved* | Tin `TaskhubDown` tới sau khoảng (chu kỳ scrape) + `for: 1m` + `group_wait` của Alertmanager — tính ra con số lý thuyết rồi so với số đo. Alert đi qua các trạng thái *inactive → pending → firing* (xem trang Alerts của Prometheus). Vì sao không đặt `for: 0`? |
| T2 | **Alert ổ đĩa** | `[EC2]` `df -h /` → tính kích thước cần để vượt 85% → ⚠️ `sudo fallocate -l <N>G /var/tmp/fill.img` → chờ `HostDiskUsageHigh` → **xóa ngay** `sudo rm /var/tmp/fill.img` → *resolved*. (Trên laptop: dùng cách hạ ngưỡng tạm thời của Lab 01, không làm đầy ổ thật.) | Tính đúng `N` trước khi chạy; không để vượt 95% (PostgreSQL ngừng ghi khi đầy đĩa). Biểu thức PromQL của rule loại bỏ filesystem nào (tmpfs, overlay) và vì sao? |
| T3 | **Backup lên S3** | Chạy tay `sudo /opt/taskhub/scripts/backup.sh` → `aws s3 ls s3://taskhub-backups-<account-id>/pg-dumps/` → kiểm tra metric `taskhub_backup_last_success_timestamp_seconds` trong Prometheus; rồi `sudo systemctl start taskhub-backup.service` (chạy như timer sẽ chạy) và đọc `journalctl -u taskhub-backup`; `systemctl list-timers taskhub-backup.timer` xem lần chạy kế tiếp | File có kích thước > 0, tên đúng quy ước; metric cập nhật. Service chạy với `PATH` nào — vì sao `aws` (snap) có thể "không tìm thấy" trong service dù chạy tay được? Stop EC2 qua giờ 18:00 UTC rồi start lại: lần backup bị lỡ có chạy bù không? |
| T4 | **Diễn tập restore — đo RTO** | Tạo vài task → backup → ghi số dòng → `make down` (backup + destroy) → `make up` → bấm giờ từ lúc bắt đầu restore → `restore.sh` vào `taskhub_restore` → so số dòng → swap theo runbook → `curl $APP_URL/api/tasks` thấy dữ liệu cũ | RTO (phút, đo thật) và RPO (thời điểm bản dump so với lúc "sự cố"). Mật khẩu PostgreSQL đã **đổi** sau rebuild (sinh lại bởi Terraform) — vì sao restore vẫn chạy được (gợi ý: `pg_restore --no-owner`, role do `POSTGRES_USER` tạo)? Ghi vào `backup-restore.md` |
| T5 | **Alert backup quá cũ** | Ghi tạm metric textfile với timestamp 2 ngày trước (hoặc `systemctl stop taskhub-backup.timer`) → chờ alert → khôi phục | Alert bắn, có runbook. Vì sao giám sát **thời điểm thành công cuối cùng** tốt hơn giám sát "script có chạy không"? |
| T6 | **Rollback < 5 phút, nhìn trên dashboard** | Merge một bản cố ý trả 500 cho một endpoint (trên nhánh, có PR) → Deploy → quan sát panel 5xx + alert `HighErrorRate` (nếu có) → Run workflow Deploy với tag trước → Approve | Thời gian từ lúc alert/biểu đồ báo lỗi đến lúc 5xx về 0. So với [v3 T5](v3-cd.md#7-thử-nghiệm-bắt-buộc): giờ bạn có **bằng chứng** (biểu đồ) cho quyết định rollback. Cập nhật `rollback.md` |
| T7 | **Bộ giám sát chết — ai báo?** | `[EC2]` `docker compose -p taskhub-mon stop` rồi `docker compose -p taskhub stop taskhub` → không có Telegram nào. Sau đó thử đường độc lập: `aws cloudwatch set-alarm-state --alarm-name taskhub-status-check --state-value ALARM --state-reason "v5 T7 test"` → email SNS tới. Khôi phục mọi thứ | Điểm mù của giám sát chạy chung máy. `set-alarm-state` chỉ thử **đường gửi**, alarm tự trở về trạng thái thật trong vài giây. `StatusCheckFailed` **không** kêu khi máy bị *stop* (không có dữ liệu, `treat_missing_data = notBreaching`) và không biết app có trả lời không. 🟨 Probe ngoài miễn phí: workflow GitHub Actions `schedule` gọi `$APP_URL/actuator/health` (nhớ: lịch bị tắt sau 60 ngày repo không hoạt động — [CI/CD bài 02](../../05-CICD/02-github-actions-basics.md)). Ghi vào ADR-0010 |
| T8 | **Kiểm tra cardinality** | Prometheus: top metric theo số series (`topk(10, count by (__name__)({__name__=~".+"}))`); Loki: liệt kê nhãn và số giá trị của từng nhãn (Grafana Explore hoặc API `/loki/api/v1/labels`, `/label/<name>/values`) | Không nhãn nào có hàng trăm giá trị thay đổi theo request. Tag `uri` là mẫu đường dẫn. Điều gì xảy ra nếu bạn lỡ đưa `trace_id` thành nhãn Loki? |
| T9 | **Từ alert tới log** | Gây lỗi thật (ví dụ dừng `postgres` 2 phút) → alert/biểu đồ → Grafana Explore: LogQL lọc `compose_service="taskhub"` và `level="ERROR"` cùng khung giờ → tìm dòng `Caused by` | Luồng điều tra metric → log mà [Incident drill #1](../../08-MONITORING-LOGGING/labs/incident-drill-01/README.md) đã luyện. Viết postmortem ngắn vào `docs/postmortems/` |
| T10 | **Chu trình dựng lại CÓ dữ liệu** | Từ trạng thái đang chạy có dữ liệu: `make down` (backup **trước**, rồi destroy) → `make up` → restore → app có dữ liệu cũ, dashboard có số liệu mới, alert hoạt động; bấm giờ | Mục tiêu < 40 phút (v4 T1 + restore). Mở rộng `rebuild-from-scratch.md`. Metric/log cũ có còn không, và có cần không? |

---

## 8. Xử lý sự cố thường gặp

Thông báo dưới đây là minh họa — tìm **ý chính** in đậm. Bảng lỗi chi tiết ở các bài và lab của [Module 08](../../08-MONITORING-LOGGING/README.md), và trong [Break-fix #1](../../08-MONITORING-LOGGING/labs/break-fix-01/README.md).

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra | Cách sửa |
|---|---|---|---|
| Target `taskhub` **DOWN**: *no such host* / *connection refused* | `taskhub-mon` không nối vào network `taskhub_default`; project app không tên `taskhub` | `docker network inspect taskhub_default` — có container prometheus không? | Sửa `networks:` (external) trong `monitoring/compose.yaml`; kiểm tra `name:` của project app |
| Target `taskhub` **DOWN**: HTTP **404** | Chưa mở `prometheus` trong `exposure.include`, hoặc thiếu dependency Micrometer Prometheus | `docker exec … curl -s localhost:8080/actuator` từ trong network | Sửa `application.yml`/`pom.xml` → build image mới → Deploy |
| Alert kẹt **Pending** mãi | Chưa đủ thời gian `for:`; biểu thức dao động quanh ngưỡng | Trang Alerts của Prometheus | Chờ đúng `for:`; xem lại biểu thức |
| Alert **Firing** trong Prometheus nhưng không có tin | Prometheus không trỏ tới Alertmanager; route/receiver sai | Trang Status → *Alertmanagers*; UI Alertmanager (qua port forwarding) | Sửa `alerting:` trong `prometheus.yml`; `amtool check-config` |
| Telegram: **401 Unauthorized** / **chat not found** | Token sai; `chat_id` sai kiểu hoặc sai số; bạn chưa gửi `/start` cho bot | Log container alertmanager | Kiểm tra token trong Parameter Store; `chat_id` là **số nguyên**; nhắn `/start` cho bot trước |
| Alertmanager/Grafana: **permission denied** khi đọc file secret | File `0400` của root nhưng container chạy bằng user khác | `ls -ln` file + `docker inspect … .Config.User` | Đặt chủ sở hữu/quyền theo UID của container (role `monitoring`) |
| Đổi mật khẩu Grafana trong Parameter Store nhưng **đăng nhập vẫn mật khẩu cũ** | Grafana chỉ dùng `admin_password` ở **lần chạy đầu**, sau đó lưu trong database của nó (volume) | — | `grafana cli admin reset-admin-password` trong container, hoặc xóa volume Grafana khi dữ liệu dashboard đã nằm trong provisioning |
| Loki **không có log** của taskhub | Alloy không đọc được `docker.sock`; vẫn còn driver `awslogs`; nhãn lọc sai | UI Alloy (127.0.0.1); `docker logs alloy` | Mount socket read-only đúng đường dẫn; bỏ `awslogs` (4.6) |
| Container **OOMKilled** / máy chậm, swap | Vẫn chạy `t3.small`; `mem_limit` quá thấp cho JVM/Prometheus | `docker inspect … .State.OOMKilled`; `free -m`; `docker stats` | Đổi `c7i-flex.large` (mục 3); chỉnh `mem_limit` theo số đo |
| `start-session` port forwarding lỗi: **address already in use** | Cổng local (3000/13000) đang bận trên laptop | `ss -ltnp` trên WSL | Đổi `localPortNumber` |
| `taskhub-backup.service`: **aws: command not found** | `PATH` mặc định của systemd không có `/snap/bin` | `journalctl -u taskhub-backup` | `Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin` trong unit, hoặc gọi đường dẫn đầy đủ |
| `backup.sh`: **AccessDenied** khi `s3 cp` | Ghi ngoài prefix `pg-dumps/`; tên bucket sai | `aws sts get-caller-identity` trên EC2; policy `taskhub-ec2-s3-backup` | Đúng prefix và bucket |
| `pg_restore`: **role "…" does not exist** / lỗi owner | Dump mang thông tin chủ sở hữu của môi trường cũ | Output `pg_restore` | `--no-owner` (và `--no-privileges` nếu cần) — xem Lab 02 |
| Ổ đĩa đầy dần | Retention chưa đặt; image cũ tích tụ | `du -sh /var/lib/docker/volumes/*`; `docker system df` | Q5; xóa image không dùng **có chủ đích** (không `prune -a` mù quáng trên máy có dữ liệu) |

Ghi mọi lỗi vào `troubleshooting-journal.md` theo [mẫu](../../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 9. Câu hỏi tự kiểm

1. Monitoring, logging và observability khác nhau thế nào? Với taskhub, mỗi thứ trả lời câu hỏi gì?
2. Vì sao Prometheus **kéo** (scrape) metric thay vì app **đẩy**? Khi nào phải dùng Pushgateway hoặc textfile collector (như metric backup)?
3. Từ lúc app chết tới lúc Telegram rung mất bao lâu, gồm những khoảng chờ nào? Rút ngắn được không, và đánh đổi gì?
4. Vì sao bộ giám sát chạy trên chính máy nó giám sát là một điểm yếu? Bạn đã bù đắp thế nào, và còn điểm mù nào?
5. RPO và RTO của taskhub hiện là bao nhiêu (số đo thật)? Muốn RPO 5 phút thì phải thay đổi gì (gợi ý: WAL archiving, RDS PITR)?
6. Vì sao `restore.sh` không ghi thẳng vào database đang chạy?
7. Cardinality là gì? Cho một ví dụ nhãn làm Loki/Prometheus "nổ" bộ nhớ.
8. Vì sao Grafana không mở ra Internet mà vẫn dùng được từ laptop? So SSM port forwarding với mở cổng 3000 cho IP của bạn.
9. Bạn bỏ CloudWatch Logs ở v5. Phản biện mạnh nhất cho quyết định đó là gì, và bạn trả lời thế nào?

---

## 10. Definition of Done và release v0.7.0

- [ ] EC2 chạy `c7i-flex.large` qua Terraform (sửa tại chỗ); `docs/cost.md` có bảng 24/7 vs khi học với giá mục 3.
- [ ] App xuất `/actuator/prometheus` (nội bộ), log JSON; nginx chặn `/actuator/*` trừ `health` (Q2).
- [ ] `monitoring/` chạy thành project `taskhub-mon` qua role Ansible `monitoring`; mọi target **UP**; dashboard `taskhub-overview` có dữ liệu thật (ảnh chụp trong `docs/experiments/v5-tests.md`).
- [ ] `TaskhubDown` và `HostDiskUsageHigh` gửi được Telegram và *resolved* (T1, T2).
- [ ] Backup hằng ngày lên S3; restore đã diễn tập với RTO đo thật (T3, T4); alert backup quá cũ hoạt động (T5).
- [ ] Rollback < 5 phút với bằng chứng trên dashboard (T6); thử đường cảnh báo độc lập bằng `set-alarm-state` (T7).
- [ ] Đạt Q1–Q13; lệnh kiểm tra nhanh mục 6 ra đúng kết quả.
- [ ] Hoàn thành T1–T10 trong `docs/experiments/v5-tests.md`.
- [ ] ADR-0010, ADR-0011; `docs/slo.md`; runbook `backup-restore.md`, `incident-response.md`, `rollback.md` (cập nhật); ít nhất một postmortem trong `docs/postmortems/`; `docs/architecture.md` có sơ đồ v5.
- [ ] Code vào `main` qua PR (ví dụ `feat/observability-backup`), CI + `infra.yml` xanh.
- [ ] **Release `v0.7.0`**: sau khi CI trên `main` xanh, `git tag -a v0.7.0 -m "v5: observability, alert, backup/restore"` → `git push origin v0.7.0` (workflow `Release` gắn `:v0.7.0`) → Deploy `workflow_dispatch` với `v0.7.0` → `curl $APP_URL/actuator/health` = `UP` → dashboard thấy phiên bản mới chạy.
- [ ] Cuối buổi: `make down` (backup rồi destroy) — mục 11.
- [ ] Kiểm tra bản thân: [Checkpoint Module 08](../../08-MONITORING-LOGGING/checkpoint.md) (tuần 18).

➡️ Tiếp theo: **v6 — Kubernetes local** (tuần 19–20): đưa taskhub lên Kubernetes chạy trên laptop (kind/minikube) bằng manifest rồi Helm chart — không tốn tiền EKS. Tài liệu sẽ được viết cùng Module 09.

---

## 11. Dọn dẹp

| Khi nào | Làm gì | Kiểm tra |
|---|---|---|
| **Cuối mỗi buổi** | Chạy backup (`make backup` hoặc `backup.sh` qua Session Manager/Ansible) → kiểm tra file mới trên S3 → ⚠️ `terraform -chdir=infra/terraform/envs/dev destroy` | `aws s3 ls …/pg-dumps/` có bản của hôm nay; `find-leftovers.sh` chỉ còn lớp bền |
| Đầu buổi sau | `make up` → restore bản mới nhất (T4) → cập nhật `APP_URL`, `AWS_DEPLOY_ROLE_ARN` nếu đổi | `curl $APP_URL/api/tasks` có dữ liệu cũ |
| Giữa chừng, không muốn destroy | Stop EC2 — `c7i-flex.large` đắt gấp ~3,7 lần, đừng để chạy qua đêm | Billing → credit còn lại |
| Hết tuần 18 | Có thể đổi `instance_type` về `t3.small` nếu tuần sau chưa cần bộ giám sát trên AWS (v6 chạy trên laptop) | `terraform plan` → `~ update in-place` |
| Dừng hẳn dự án | Như [v4 §11](v4-terraform.md#11-dọn-dẹp); thêm: xóa tham số tạo tay `/taskhub/dev/telegram-bot-token`; thu hồi bot qua BotFather nếu không dùng nữa | `aws ssm describe-parameters --parameter-filters Key=Name,Option=BeginsWith,Values=/taskhub/` |

Không xóa bucket backup — đó là dữ liệu duy nhất sống qua mọi lần destroy.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS — Track Free Tier usage for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | Danh sách loại máy free-tier-eligible (tài khoản tạo từ 15/7/2025), lệnh lọc `free-tier-eligible` | 2026-10-31 |
| [Amazon EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) | Giá `c7i-flex.large`, `t3.small` ap-southeast-1 (đối chiếu dữ liệu giá công khai của AWS) | 2026-10-31 |
| [Prometheus — Alertmanager configuration](https://prometheus.io/docs/alerting/latest/configuration/) | `telegram_config` (`bot_token_file`, `chat_id` kiểu int), mặc định `group_wait` 30s / `group_interval` 5m / `repeat_interval` 4h | 2026-10-31 |
| [Prometheus — Alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/) | `for`, nhãn, annotation, trạng thái pending/firing | 2026-10-31 |
| [Prometheus — Storage](https://prometheus.io/docs/prometheus/latest/storage/) | Retention theo thời gian/dung lượng | 2026-10-31 |
| [node_exporter — Textfile collector](https://github.com/prometheus/node_exporter#textfile-collector) | Metric thời điểm backup thành công | 2026-10-31 |
| [Grafana — Configure Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/) | `admin_password` chỉ đặt ở lần chạy đầu; đọc giá trị từ file (`$__file{}`) | 2026-10-31 |
| [Grafana — Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) | Datasource và dashboard bằng file | 2026-10-31 |
| [Grafana Loki — Retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) | Retention với compactor | 2026-10-31 |
| [Grafana Alloy — `loki.source.docker`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/) | Thu log container qua Docker API | 2026-10-31 |
| [Spring Boot — Metrics (Prometheus)](https://docs.spring.io/spring-boot/reference/actuator/metrics.html) | `micrometer-registry-prometheus`, `/actuator/prometheus` | 2026-10-31 |
| [PostgreSQL 17 — `pg_dump`](https://www.postgresql.org/docs/17/app-pgdump.html) · [`pg_restore`](https://www.postgresql.org/docs/17/app-pgrestore.html) | Định dạng custom `-Fc`, `--no-owner` | 2026-10-31 |
| [AWS Systems Manager — Start a session (port forwarding)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html) | `AWS-StartPortForwardingSession`, `portNumber`, `localPortNumber` | 2026-10-31 |
| [AWS CLI — `cloudwatch set-alarm-state`](https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/set-alarm-state.html) | Thử đường gửi alarm; alarm trở về trạng thái thật sau vài giây | 2026-10-31 |
| [Terraform — Write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only) | `value_wo` nhận cả giá trị ephemeral và không ephemeral | 2026-10-31 |
| [AWS provider — `aws_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | Đổi `instance_type` → stop/start (sửa tại chỗ) | 2026-10-31 |
