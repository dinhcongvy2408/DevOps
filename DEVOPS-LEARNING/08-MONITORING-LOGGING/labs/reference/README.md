# Bản tham khảo giám sát `taskhub` v5 — Prometheus · Alertmanager · Grafana · Loki · Alloy

> ⚠️ **Chỉ mở sau khi đã tự viết.** File ở đây để **so sánh** với cấu hình của bạn, không phải để chép. Phỏng vấn viên sẽ hỏi "vì sao dòng này viết như vậy?".
>
> ✅ Toàn bộ thư mục này đã **chạy thật** ngày 2026-10-31 trên Docker Desktop 27.3.1, cùng app taskhub Spring Boot 4.1.2 dựng lại từ [hướng dẫn tuần 6](../../../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md): mọi target UP, alert đi tới receiver rồi resolved, log có nhãn `level`, dashboard có dữ liệu, backup → S3 (giả lập) → restore → swap chạy đúng. Kết quả ở [mục 6](#6-đã-kiểm-chứng-những-gì).

## Mục lục

1. [Chép vào đâu](#1-chép-vào-đâu)
2. [Từng file làm gì](#2-từng-file-làm-gì)
3. [Chạy trên laptop](#3-chạy-trên-laptop)
4. [Chạy trên EC2 (v5)](#4-chạy-trên-ec2-v5)
5. [RAM thực tế — vì sao v5 đổi sang c7i-flex.large](#5-ram-thực-tế--vì-sao-v5-đổi-sang-c7i-flexlarge)
6. [Đã kiểm chứng những gì](#6-đã-kiểm-chứng-những-gì)
7. [Những chỗ tài liệu/tutorial khác sẽ làm bạn sai](#7-những-chỗ-tài-liệututorial-khác-sẽ-làm-bạn-sai)

---

## 1. Chép vào đâu

| Ở đây | Trong repo `taskhub` | Ghi chú |
|---|---|---|
| `compose.yaml`, `prometheus/`, `alertmanager/`, `loki/`, `alloy/`, `grafana/`, `webhook-debug/` | `monitoring/` | Compose project **riêng** `taskhub-mon` |
| `scripts/backup.sh`, `scripts/restore.sh` | `scripts/` | Chạy trên **host**, không trong container |
| `app-changes/pom-dependency.xml` | gộp vào `app/pom.xml` | Thêm `micrometer-registry-prometheus` |
| `app-changes/application-monitoring.yml` | gộp vào `app/src/main/resources/application.yml` | Expose `prometheus`, histogram, log JSON |
| `app-changes/nginx-default.conf` | thay `docker/nginx/default.conf` | Chặn `/actuator/*` từ ngoài, trừ `/actuator/health` |
| — | `monitoring/secrets/` (**không commit**, thêm vào `.gitignore`) | `grafana_admin_password`, `telegram_bot_token`, `telegram_chat_id` |

```text
                     project "taskhub" (app)                    project "taskhub-mon" (giám sát)
   Internet ──► nginx:80 ──► taskhub:8080 ──► postgres:5432
                 │ chặn /actuator/*       ▲                          ┌──────────────► Alertmanager ──► Telegram
                 │ (trừ /health)          │ scrape /actuator/prometheus  │ rule cháy       (laptop: webhook-debug)
                 │                        │ (đi thẳng trong network      │
                 ▼                        │  taskhub_default)        Prometheus ◄── node-exporter (host: CPU, RAM, disk,
        stdout/stderr các container ──────┼──────────────────────────► Alloy ──► Loki           + metric backup)
                                          │                               ▲          ▲
                                          └──────────── Grafana ──────────┴──────────┘  (chỉ 127.0.0.1)
```

---

## 2. Từng file làm gì

| File | Vai trò | Điểm cần hiểu |
|---|---|---|
| `compose.yaml` | 7 service giám sát | Tham gia network **external** `taskhub_default` (app phải chạy trước). Mọi port chỉ bind `127.0.0.1`, đổi được bằng biến. Mọi service có `mem_limit` |
| `prometheus/prometheus.yml` | Scrape 6 job: `taskhub`, `node`, `prometheus`, `alertmanager`, `alloy`, `loki` | `taskhub:8080/actuator/prometheus` gọi thẳng, không qua nginx. Retention 7 ngày **hoặc** 2 GB |
| `prometheus/rules/alerts.yml` | 8 rule, 3 nhóm | Bắt buộc: `TaskhubDown`, `HostDiskUsageHigh`. Thêm: `TaskhubHighErrorRate`, `TaskhubHighLatencyP95`, `HostMemoryHigh`, `NodeExporterDown`, `TaskhubBackupStale`, `TaskhubBackupMetricMissing` |
| `alertmanager/alertmanager.yml` | EC2: gửi **Telegram** | `bot_token_file` + `chat_id_file` → không secret nào trong Git. `inhibit_rules`: đang `TaskhubDown` thì không gửi thêm lỗi 5xx/latency |
| `alertmanager/alertmanager.laptop.yml` | Laptop: gửi **webhook-debug** | Chọn bằng biến `ALERTMANAGER_CONFIG` |
| `webhook-debug/receiver.py` | 25 dòng Python, in alert ra log | Chỉ chạy khi `COMPOSE_PROFILES=debug` |
| `loki/config.yaml` | Loki single binary, filesystem, TSDB v13 | `retention_period: 168h` **chỉ có tác dụng** khi `compactor.retention_enabled: true` |
| `alloy/config.alloy` | Docker socket → lọc 2 project → nhãn → JSON `log.level` → Loki | Nhãn ít giá trị: `container`, `compose_service`, `compose_project`, `level`. Đã chạy qua `alloy fmt` (thụt lề bằng tab) |
| `grafana/provisioning/datasources/datasources.yaml` | Prometheus (mặc định), Loki, Alertmanager | `uid` cố định để dashboard tham chiếu |
| `grafana/provisioning/dashboards/dashboards.yaml` + `grafana/dashboards/taskhub-overview.json` | Dashboard 12 panel | UP, request rate, tỷ lệ 5xx, p95, disk · rate theo status, p50/p95/p99 · JVM heap, CPU, RAM · đếm log ERROR, log taskhub. Sửa trong Git, UI không ghi đè được |
| `scripts/backup.sh` | `pg_dump -Fc` → file tạm → kiểm tra `pg_restore --list` → `aws s3 cp` → ghi metric textfile | Lỗi ở **bất kỳ** bước nào → thoát ≠ 0 và **không** ghi metric → alert `TaskhubBackupStale` sẽ kêu |
| `scripts/restore.sh` | Tải bản mới nhất (hoặc theo tên) → restore vào `taskhub_restore` (`pg_restore --no-owner --exit-on-error`) → so số dòng | Từ chối restore đè lên database đang chạy. In 4 bước swap để làm **có chủ đích** |

Nhãn tự động: Loki 3.x tự thêm `service_name` và `detected_level` vào mỗi stream. Bạn sẽ thấy chúng cạnh các nhãn do Alloy đặt; không phải lỗi.

---

## 3. Chạy trên laptop

```bash
# [WSL] — từ gốc repo taskhub, SAU KHI app stack (project taskhub) đang chạy
mkdir -p monitoring/secrets monitoring/textfile
openssl rand -base64 24 > monitoring/secrets/grafana_admin_password
printf 'unused' > monitoring/secrets/telegram_bot_token     # laptop dùng webhook-debug, file vẫn phải tồn tại
printf '0'      > monitoring/secrets/telegram_chat_id

export ALERTMANAGER_CONFIG=alertmanager.laptop.yml   # gửi alert vào webhook-debug
export COMPOSE_PROFILES=debug                       # bật service webhook-debug
export NODE_EXPORTER_TEXTFILE_DIR=./textfile        # laptop: thư mục trong repo (EC2: mặc định /var/lib/node_exporter/textfile_collector)
docker compose -p taskhub-mon -f monitoring/compose.yaml up -d
```

| Mở | Địa chỉ mặc định | Đổi port bằng |
|---|---|---|
| Grafana (user `admin`, mật khẩu trong file secret) | http://localhost:3000 → dashboard **taskhub / taskhub overview** | `GRAFANA_HOST_PORT` |
| Prometheus — Status → Targets, Alerts | http://localhost:9090 | `PROMETHEUS_HOST_PORT` |
| Alertmanager | http://localhost:9093 | `ALERTMANAGER_HOST_PORT` |
| Alloy UI (đồ thị pipeline) | http://localhost:12345 | `ALLOY_HOST_PORT` |
| Alert nhận được | `docker logs -f taskhub-mon-webhook-debug-1` | — |

Port bị chiếm (máy có nhiều project khác)? `export GRAFANA_HOST_PORT=13000` rồi chạy lại `up -d`.

Kiểm tra nhanh:

```bash
docker run --rm -v "$PWD/monitoring/prometheus:/p:ro" --entrypoint promtool prom/prometheus:v3.15.1 check config /p/prometheus.yml
docker run --rm -v "$PWD/monitoring/prometheus:/p:ro" --entrypoint promtool prom/prometheus:v3.15.1 check rules /p/rules/alerts.yml
docker run --rm -v "$PWD/monitoring/alertmanager:/a:ro" --entrypoint amtool prom/alertmanager:v0.34.2 check-config /a/alertmanager.yml
docker run --rm -v "$PWD/monitoring/alloy:/a:ro" grafana/alloy:v1.21.3 fmt /a/config.alloy
curl -s localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c   # 6 × "up"
curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/actuator/prometheus            # 404 — bị nginx chặn
```

**Demo alert disk an toàn** (không làm đầy ổ thật): trong một **bản sao** rule, đổi ngưỡng `> 80` thành `> 5` và `for: 5m` thành `for: 30s`, rồi `curl -X POST localhost:9090/-/reload`. Khoảng 1 phút sau, webhook-debug in `[firing] HostDiskUsageHigh`. Trả lại rule gốc và reload. Đừng dùng `fallocate` làm đầy ổ của Docker Desktop: đó là ổ chung của **mọi** container trên máy.

Dọn: `docker compose -p taskhub-mon -f monitoring/compose.yaml down` (thêm `-v` ⚠️ nếu muốn xóa luôn dữ liệu metric/log/dashboard).

---

## 4. Chạy trên EC2 (v5)

- Ansible role `monitoring` chép thư mục này vào `/opt/taskhub/monitoring`, ghi các file secret (từ Parameter Store, ví dụ `/taskhub/dev/telegram-bot-token`, quyền chỉ root đọc) rồi chạy `docker compose -p taskhub-mon up -d`. Mặc định dùng `alertmanager.yml` (Telegram), không bật profile `debug`.
- **Không** mở thêm port nào trong Security Group. Vào Grafana từ laptop bằng SSM port forwarding: cổng 3000 trên EC2 (chỉ bind 127.0.0.1) → cổng **13000** trên laptop:

  ```bash
  aws ssm start-session --target <instance-id> \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["3000"],"localPortNumber":["13000"]}'
  # rồi mở http://localhost:13000
  ```

- Backup: systemd timer `taskhub-backup.timer` (`OnCalendar=*-*-* 18:00:00 UTC`, `Persistent=true`) chạy `scripts/backup.sh` với `BACKUP_BUCKET=taskhub-backups-<account-id>`. AWS CLI trên **host** dùng instance role. Container không có quyền AWS vì IMDS hop limit 1.
- CloudWatch alarm `StatusCheckFailed` (v3) vẫn giữ: bộ giám sát chạy **cùng máy** với app, nên máy chết thì nó chết theo. Cần một "người canh" độc lập bên ngoài.

---

## 5. RAM thực tế — vì sao v5 đổi sang c7i-flex.large

Đo bằng `docker stats --no-stream` sau ~200 request, máy rảnh (2026-10-31, Docker Desktop; trên laptop app **chưa** có `mem_limit`):

| Container | RAM dùng | `mem_limit` trong file | Ghi chú |
|---|---|---|---|
| taskhub (JVM) | 321 MiB | 768m (EC2, `compose.aws.yaml`/v2) | Heap còn lớn dần theo tải, tới ~75% của limit |
| postgres | 71 MiB | — | Tăng theo dữ liệu và kết nối |
| nginx | 12 MiB | — | |
| **Cộng app** | **~404 MiB** | | |
| grafana | 233 MiB | 384m | Ban đầu đặt 256m — quá sát, đã nâng |
| prometheus | 88 MiB | 512m | Tăng theo số series và thời gian giữ (7 ngày) |
| alloy | 104 MiB | 256m | |
| loki | 92 MiB | 384m | Tăng theo lượng log |
| alertmanager | 30 MiB | 128m | |
| node-exporter | 20 MiB | 64m | |
| webhook-debug (chỉ laptop) | 13 MiB | 64m | |
| **Cộng giám sát (EC2, không webhook)** | **~567 MiB** | **1,7 GiB** | |

- **Lúc rảnh:** app + giám sát ≈ **1,0 GiB**, cộng OS + dockerd + snap (SSM agent, AWS CLI) khoảng 300–400 MiB, ≈ **1,3–1,4 GiB**. Trên `t3.small` (2 GiB) nghĩa là còn vài trăm MiB.
- **Khi có tải:** heap JVM lớn lên (tới ~576 MiB với limit 768m), Prometheus tích series trong 7 ngày, Loki nhận log. Tổng `mem_limit` của mọi container ≈ **2,5 GiB** > 2 GiB vật lý, nên chỉ cần vài container cùng lớn là OOM killer chọn giết một process, thường là JVM.
- Gói Free chỉ cho chạy loại máy trong danh sách free-tier (`t3.medium` **không** có trong danh sách). Loại 4 GiB rẻ nhất trong danh sách là **`c7i-flex.large`** (2 vCPU, 4 GiB, 0,09778 USD/giờ ở ap-southeast-1, khoảng 3,7× `t3.small`). Đổi bằng một biến Terraform (`instance_type`), là cập nhật tại chỗ (stop/start), và nhớ **stop khi không học**.

---

## 6. Đã kiểm chứng những gì

Chạy ngày 2026-10-31 bằng Docker CLI 27.3.1 (Windows) với app taskhub dựng từ start.spring.io (Spring Boot 4.1.2, Java 21).

| Kiểm tra | Kết quả |
|---|---|
| `promtool check config` / `check rules` | SUCCESS · 8 rules |
| `amtool check-config` cả 2 file | SUCCESS (1 receiver, 1 inhibit rule) |
| `alloy fmt` | Không còn khác biệt |
| `docker compose config -q` | Hợp lệ |
| Prometheus targets | 6/6 `up` |
| `/actuator/prometheus` qua nginx | 404; `/actuator/health` 200; Prometheus vẫn scrape được trực tiếp |
| `http_server_requests_seconds_bucket` | Có (histogram bật đúng với tên thuộc tính Boot 4.1.2) |
| Log JSON (ECS) | Dạng lồng `{"log":{"level":"INFO",...}}` → biểu thức `log.level` |
| Loki | Nhận log 9 service; nhãn `level` có `INFO`, `WARN`, `ERROR` (sau khi dừng PostgreSQL để tạo lỗi) |
| Grafana `GF_SECURITY_ADMIN_PASSWORD__FILE` | Hoạt động ở 13.3.0: mật khẩu trong file → 200; `admin:admin` → 401 |
| Datasource health | Prometheus OK, Loki OK. Alertmanager: nút *Test* báo "Plugin unavailable" (datasource này không có health check), nhưng API alerting của Grafana đọc được Alertmanager (HTTP 200) |
| Dashboard | Provisioned trong folder `taskhub`, 12 panel; query Prometheus và Loki đều trả dữ liệu |
| `TaskhubDown` | Dừng app → sau ~1 phút webhook-debug nhận `[firing]`; bật lại → `[resolved]` |
| `HostDiskUsageHigh` | Bản sao rule ngưỡng 5%, `for: 30s` → `[firing]` trên mountpoint `/var/lib` |
| Lỗi thật | Dừng PostgreSQL: nginx trả **504** cho request đầu (chờ HikariCP ~30s đúng bằng `proxy_read_timeout`), sau đó **500**; metric `status="500"` tăng, Loki có `level="ERROR"` |
| `backup.sh` lỗi upload | Thoát 1, **không** ghi metric (đúng thiết kế) |
| `backup.sh` thành công | Dump 4,8 KB trong 2s → S3; metric textfile tới Prometheus; `TaskhubBackupMetricMissing` hết pending |
| `restore.sh` | 3s; `taskhub` 5 dòng vs `taskhub_restore` 4 dòng (1 dòng tạo sau backup = RPO); chặn `TARGET_DB=taskhub` |
| 4 bước swap in ra | Chạy đúng: app khỏe lại với dữ liệu đã restore |

S3 trong bài test là **giả lập** (`adobe/s3mock:5.2.3`) gọi bằng AWS CLI 2.39.3 qua `AWS_ENDPOINT_URL`. Bước upload lên S3 thật chưa chạy (không gọi AWS).

---

## 7. Những chỗ tài liệu/tutorial khác sẽ làm bạn sai

| Bạn sẽ thấy ở nơi khác | Thực tế (đã gặp khi chạy) |
|---|---|
| node-exporter mount `/:/host:ro,rslave` | Docker Desktop báo `path / is mounted on / but it is not a shared or slave mount` → file này dùng `/:/host:ro` |
| Alert disk dùng `mountpoint="/"` | Trên Docker Desktop, VM **không** báo `/`; dữ liệu Docker nằm ở `/var/lib`. Chỉ khớp `/` thì alert **im lặng mãi** → rule dùng `mountpoint=~"/|/var/lib"` |
| Promtail | Hết hỗ trợ từ 2026-03-02 — dùng Alloy |
| Biểu thức `"log.level"` (khóa phẳng) | ECS của Spring Boot là JSON **lồng** → `log.level` không ngoặc kép |
| Image `minio/minio` để giả lập S3 | Không còn trên Docker Hub (pull báo `repository does not exist`) |
| `pg_dump ... \| aws s3 cp - s3://...` | Gọn nhưng nếu `pg_dump` lỗi giữa chừng, S3 vẫn nhận một file dở trông như backup thật → script dump ra file tạm và kiểm tra trước |
