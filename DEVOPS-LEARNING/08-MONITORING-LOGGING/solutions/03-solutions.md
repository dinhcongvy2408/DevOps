# Lời giải — Bài 03: Grafana, dashboard và cảnh báo

> Chỉ mở sau khi đã tự làm. Quay lại bài: [03-grafana-dashboards-alerting.md](../03-grafana-dashboards-alerting.md)

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Không. Grafana chỉ gửi truy vấn tới datasource (Prometheus, Loki) rồi vẽ. Xóa volume `grafana-data` mất: user, mật khẩu đổi trên UI, dashboard/datasource **tạo bằng tay**, cài đặt cá nhân. Không mất: metric (ở Prometheus), log (ở Loki), dashboard và datasource **provisioned từ file** (Grafana tạo lại lúc khởi động).

**2.** Grafana chạy trong container có network namespace riêng; `localhost` là chính container Grafana, trong đó không có gì nghe ở 9090. Phải dùng tên service `prometheus` — DNS nội bộ của Docker network `mon` phân giải ra IP container Prometheus.

**3.** Panel trong JSON lưu `"datasource": {"type": "prometheus", "uid": "..."}`. Grafana tìm datasource theo uid. uid trong provisioning khác uid trong JSON (hoặc uid tự sinh ngẫu nhiên khi tạo bằng tay) → panel "No data"/lỗi datasource not found. Đặt uid cố định trong file provisioning và export dashboard ở chế độ không thay uid bằng biến.

**4.** RED cho **service** (thứ nhận request): Request/s, tỷ lệ 5xx, p95 latency. USE cho **tài nguyên** (thứ có giới hạn): CPU %, RAM %, Disk % (saturation: load average, swap, hàng đợi IO 🟨).

**5.** Prometheus gọi `/actuator/prometheus` mỗi 15 giây; request đó được Spring đếm vào `http.server.requests`. Không lọc → luôn có "traffic" giả, tỷ lệ lỗi và p95 bị pha loãng bởi request scrape (nhanh, luôn 200).

**6.** `rate()` cần ít nhất 2 mẫu trong cửa sổ; cửa sổ cố định quá nhỏ so với bước vẽ của Grafana (khi zoom) sẽ cho lỗ hổng hoặc số sai. `$__rate_interval` do Grafana tính theo scrape interval và bước vẽ, bảo đảm đủ ≥ 4 mẫu. File rule chạy trong Prometheus, không có Grafana → không có biến này → dùng khoảng cố định đủ lớn so với scrape interval (5m với scrape 15s).

**7.** inactive: `expr` không trả series. pending: trả series nhưng chưa liên tục đủ `for`. firing: liên tục ≥ `for` → gửi Alertmanager. `for: 1m` bỏ qua các lần down ngắn hơn 1 phút (restart, deploy), đổi lại báo chậm thêm 1 phút.

**8.** `labels` là một phần **định danh** của alert, dùng để route, group, inhibit, silence (`severity`, `team`). `annotations` là thông tin cho **người đọc** (`summary`, `description`, `runbook_url`), không dùng để route.

**9.** App chết 10:00:00. Lần scrape lỗi đầu tiên trong vòng 15s (≤ 10:00:15); lần evaluation kế tiếp (≤ 15s) thấy `up == 0` → pending. Đủ `for: 1m` → firing khoảng 10:01:15–10:01:45. Alertmanager chờ `group_wait: 30s` → tin đầu tiên khoảng **10:01:45–10:02:15**. Chưa sửa → nhắc lại mỗi `repeat_interval` 4h (≈ 14:02). Alert mới **cùng nhóm** (cùng `alertname` và `severity`, ví dụ cùng alert ở instance khác) xuất hiện lúc 10:02: nhóm đã gửi rồi → gửi bản cập nhật sau `group_interval` 5m kể từ lần gửi trước, khoảng 10:07. Alert khác tên → nhóm khác → có `group_wait` riêng.

**10.** Inhibition: **tự động**, theo quy tắc cấu hình sẵn — alert A đang firing thì tắt tiếng alert B (thường là hệ quả của A). Silence: **thủ công**, có thời hạn, người tạo, lý do — dùng khi biết trước (bảo trì) hoặc đang xử lý sự cố đã rõ. Cả hai chỉ tắt **thông báo**; Prometheus vẫn đánh giá và hiển thị alert.

**11.** File cấu hình `alertmanager.yml` nằm trong Git. Token trong file đó = lộ token cho mọi người đọc repo (repo public). `bot_token_file` trỏ tới file nằm ngoài Git (thư mục secret, trên EC2 do Ansible ghi từ Parameter Store).

**12.** Telegram không cho bot chủ động bắt đầu trò chuyện với người dùng chưa từng nhắn cho nó (chống spam). Phải mở chat và gửi tin trước; khi đó `getUpdates` cũng mới có bản ghi chứa chat id.

**13.** Laptop: node-exporter chạy trong Docker Desktop, `--path.rootfs=/host` gắn `/` của **máy ảo Linux của Docker Desktop** → đo disk của máy ảo đó (nơi chứa image/volume của mọi container). Không phải ổ C: của Windows, không phải filesystem WSL Ubuntu. EC2: đo đúng ổ EBS gốc của instance.

**14.** Khẳng định tại thời điểm đó **không** có alert nào firing. Cần vì một rule sai có thể firing quá sớm hoặc luôn firing (ngưỡng ngược dấu, thiếu `for`) — chỉ test "có alert" không bắt được lỗi này.

**15.** Dấu hiệu: (a) phần lớn alert không ai làm gì; (b) người trực tắt thông báo/mute nhóm chat; (c) cùng một sự cố sinh hàng chục tin. Sửa: cảnh báo theo triệu chứng, có `for` hợp lý, phân `critical`/`warning`, `group_by` + inhibition, `repeat_interval` dài, mỗi alert có runbook, xóa alert không hành động được.

## Bài tập tự làm (mục 14)

### Bài 1 — Alert tỷ lệ lỗi

`alerts.yml` (thêm vào nhóm `taskhub`):

```yaml
      - alert: TaskhubHighErrorRate
        expr: |
          sum(rate(http_server_requests_seconds_count{job="taskhub", status=~"5.."}[5m]))
            /
          sum(rate(http_server_requests_seconds_count{job="taskhub"}[5m]))
          > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "taskhub trả lỗi 5xx cho hơn 5% request"
          description: "Tỷ lệ lỗi {{ $value | humanizePercentage }}."
```

`error_rate_test.yml`:

```yaml
rule_files:
  - alerts.yml

evaluation_interval: 1m

tests:
  # 1. Không traffic: 0/0 = NaN, so sánh NaN > 0.05 là false → không alert
  - interval: 1m
    input_series:
      - series: 'http_server_requests_seconds_count{job="taskhub", status="200", uri="/api/tasks"}'
        values: '0x20'
      - series: 'http_server_requests_seconds_count{job="taskhub", status="500", uri="/api/tasks"}'
        values: '0x20'
    alert_rule_test:
      - eval_time: 15m
        alertname: TaskhubHighErrorRate
        exp_alerts: []

  # 2. 2% lỗi: mỗi phút +98 request 200, +2 request 500 → không alert
  - interval: 1m
    input_series:
      - series: 'http_server_requests_seconds_count{job="taskhub", status="200", uri="/api/tasks"}'
        values: '0+98x20'
      - series: 'http_server_requests_seconds_count{job="taskhub", status="500", uri="/api/tasks"}'
        values: '0+2x20'
    alert_rule_test:
      - eval_time: 15m
        alertname: TaskhubHighErrorRate
        exp_alerts: []

  # 3. 10% lỗi → alert
  - interval: 1m
    input_series:
      - series: 'http_server_requests_seconds_count{job="taskhub", status="200", uri="/api/tasks"}'
        values: '0+90x20'
      - series: 'http_server_requests_seconds_count{job="taskhub", status="500", uri="/api/tasks"}'
        values: '0+10x20'
    alert_rule_test:
      - eval_time: 15m
        alertname: TaskhubHighErrorRate
        exp_alerts:
          - exp_labels:
              severity: critical
            exp_annotations:
              summary: "taskhub trả lỗi 5xx cho hơn 5% request"
              description: "Tỷ lệ lỗi 10%."
```

- `sum(...)` không có `by` → kết quả **không còn nhãn nào** của series gốc → `exp_labels` chỉ có nhãn của rule.
- Nếu test 3 fail ở `description` (ví dụ ra `9.999%` thay vì `10%`), đó là sai số dấu phẩy động khi chia hai `rate()`. Cách ổn định: viết rule với `* 100 > 5` và annotation `{{ printf "%.1f" $value }}%`, rồi sửa `exp_annotations` thành `"Tỷ lệ lỗi 10.0%."`. Ghi lại quan sát của bạn vào nhật ký.

### Bài 2 — Route theo severity

```yaml
route:
  receiver: telegram-critical
  group_by: [alertname, severity]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  routes:
    - matchers: [severity="warning"]
      receiver: telegram-warning
      repeat_interval: 12h

receivers:
  - name: telegram-critical
    telegram_configs:
      - bot_token_file: /etc/monitoring-secrets/telegram_bot_token
        chat_id_file: /etc/monitoring-secrets/telegram_chat_id
  - name: telegram-warning
    telegram_configs:
      - bot_token_file: /etc/monitoring-secrets/telegram_bot_token
        chat_id_file: /etc/monitoring-secrets/telegram_chat_id_warning   # ví dụ: một nhóm chat khác
```

```bash
docker run --rm -v "$PWD/monitoring/alertmanager:/a:ro" --entrypoint amtool prom/alertmanager:v0.34.2 \
  config routes test --config.file=/a/alertmanager.yml --tree severity=warning alertname=HostDiskUsageHigh
# → telegram-warning
docker run --rm -v "$PWD/monitoring/alertmanager:/a:ro" --entrypoint amtool prom/alertmanager:v0.34.2 \
  config routes test --config.file=/a/alertmanager.yml --tree severity=critical alertname=TaskhubDown
# → telegram-critical
```

Nhánh con kế thừa `group_by`, `group_wait`… của cha, chỉ ghi đè `repeat_interval`.

### Bài 3 — Dashboard có biến

- Dashboard settings → Variables → New: Type `Query`, Name `instance`, datasource Prometheus, Query `label_values(up{job="taskhub"}, instance)`, bật *Include All* nếu muốn.
- Sửa query panel: `{job="taskhub", instance=~"$instance", ...}` — dùng `=~` vì giá trị "All" là regex.
- Export Classic JSON → file → restart Grafana → xóa volume `grafana-data` như Lab 01 B5 → biến vẫn còn (nằm trong JSON, mục `templating`).

### Bài 4 — Kiểm thử rule trong CI

```yaml
name: Monitoring rules

on:
  pull_request:
    paths: ['monitoring/prometheus/**']

permissions:
  contents: read

jobs:
  promtool:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Check and test alert rules
        run: |
          docker run --rm -v "$PWD/monitoring/prometheus:/p:ro" --entrypoint promtool \
            prom/prometheus:v3.15.1 check rules /p/rules/alerts.yml
          docker run --rm -v "$PWD/monitoring/prometheus:/p:ro" -w /p/tests --entrypoint promtool \
            prom/prometheus:v3.15.1 test rules alerts_test.yml
```

- Không đặt job này làm **required status check**: có `paths:` → PR không đụng `monitoring/prometheus/` thì workflow không chạy → check treo "Expected" ([CI/CD 02](../../05-CICD/02-github-actions-basics.md)).
- Không cần secret hay quyền AWS.

### Bài 5 — Runbook disk

```markdown
# Runbook: HostDiskUsageHigh

**Ý nghĩa:** filesystem `/` của host dùng > 80% liên tục 5 phút.
**Ảnh hưởng:** chưa có. Tới ~100%: PostgreSQL ngừng ghi, Docker không pull được image, log mất.

## Kiểm tra (trên EC2, qua Session Manager)
- `df -h /` — xác nhận con số.
- `docker system df` — image, container, volume, build cache chiếm bao nhiêu.
- `sudo du -xh --max-depth=1 /var/lib/docker | sort -h | tail` — thư mục nào lớn.
- `sudo du -xh --max-depth=1 /var/log | sort -h | tail`.

## Xử lý an toàn
- ✅ `docker image prune` (chỉ image dangling) — xem danh sách trước.
- ✅ Xóa file backup tạm đã upload S3 thành công (kiểm tra trên S3 trước).
- ⚠️ `docker image prune -a` — chỉ khi chắc chắn không cần rollback về image cũ trên máy (pull lại từ GHCR được nhưng mất thời gian).
- ❌ KHÔNG `docker volume prune` / xóa volume `pgdata` — mất database.
- ❌ KHÔNG xóa file trong `/var/lib/docker` bằng tay.

## Leo thang
- > 90% hoặc tăng nhanh (> 5%/giờ): tăng kích thước EBS (Terraform `root_volume_size`) và ghi incident.
```

Thêm vào rule: `runbook_url: "https://github.com/<user>/taskhub/blob/main/docs/runbooks/host-disk-usage-high.md"`.

### Bài 6 — Đánh giá alert

| Alert | Đánh giá | Sửa |
|---|---|---|
| `CPU > 80%` `for: 1m` | Tệ: nguyên nhân, dao động bình thường (build, GC), không ai làm gì | Bỏ, hoặc `warning` với `for: 15m`; cảnh báo chính dựa vào latency/error rate |
| `up == 0` `for: 0s` | Tệ: mỗi lần deploy/restart là một alert | `for: 1m`, `critical` |
| `disk > 95%` `for: 30m` | Tệ: quá muộn — 95% rồi chờ thêm 30 phút, có thể đầy trước khi báo | `> 80%` `for: 5m` `warning`; 🟨 thêm alert dự báo `predict_linear()` |
| `p95 > 2s` `for: 10m` | Tốt (triệu chứng người dùng thấy). Ngưỡng tùy SLO | Giữ; ngưỡng theo yêu cầu (taskhub dùng 500ms) |
| `JVM heap > 90%` `for: 1m` | Tệ: JVM bình thường dùng heap cao rồi GC; dao động liên tục | Bỏ; nếu cần, cảnh báo theo **thời gian GC** hoặc OOMKilled/restart |
