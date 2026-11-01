# Lab 01 — Dashboard cho app + server và 2 cảnh báo bắt buộc

> ⏱️ ~4–5 giờ · Tuần 17 · 🟥 Lab bắt buộc · Kiến thức: [02. Prometheus](../02-metrics-prometheus.md), [03. Grafana & alerting](../03-grafana-dashboards-alerting.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (WSL integration **bật**), `[Browser]`, điện thoại có Telegram (Phần E)
> 💰 Chi phí: **0 USD** — chạy hoàn toàn trên laptop.

## Mục lục

- [Mục tiêu và sản phẩm nộp](#mục-tiêu-và-sản-phẩm-nộp)
- [Điều kiện trước khi bắt đầu](#điều-kiện-trước-khi-bắt-đầu)
- [Phần A — Grafana provisioned](#phần-a--grafana-provisioned)
- [Phần B — Dashboard taskhub-overview](#phần-b--dashboard-taskhub-overview)
- [Phần C — Hai alert và Alertmanager gửi vào webhook-debug](#phần-c--hai-alert-và-alertmanager-gửi-vào-webhook-debug)
- [Phần D — Kiểm thử rule bằng promtool](#phần-d--kiểm-thử-rule-bằng-promtool)
- [Phần E — Chuyển sang Telegram, thử silence](#phần-e--chuyển-sang-telegram-thử-silence)
- [Phần F — Commit qua Pull Request](#phần-f--commit-qua-pull-request)
- [Lỗi thường gặp](#lỗi-thường-gặp)
- [Checklist hoàn thành](#checklist-hoàn-thành)
- [Dọn dẹp](#dọn-dẹp)

---

## Mục tiêu và sản phẩm nộp

Kết thúc lab, repo `taskhub` có thêm (trên nhánh `feat/monitoring-dashboard-alerts`):

| File | Nội dung |
|---|---|
| `monitoring/compose.yaml` | Thêm `grafana`, `alertmanager`, `webhook-debug` (profile `debug`) vào project `taskhub-mon` |
| `monitoring/grafana/provisioning/datasources/datasources.yaml` | Datasource Prometheus, uid cố định |
| `monitoring/grafana/provisioning/dashboards/dashboards.yaml` | Provider đọc JSON từ `/var/lib/grafana/dashboards` |
| `monitoring/grafana/dashboards/taskhub-overview.json` | Dashboard app + server, export Classic JSON |
| `monitoring/prometheus/rules/alerts.yml` | `TaskhubDown`, `HostDiskUsageHigh` |
| `monitoring/prometheus/tests/alerts_test.yml` | Unit test promtool cho 2 alert |
| `monitoring/alertmanager/alertmanager.laptop.yml` | Route vào `webhook-debug` |
| `monitoring/alertmanager/alertmanager.yml` | Route vào Telegram (token/chat id đọc từ file) |
| `monitoring/webhook-debug/receiver.py` | Bộ nhận webhook in payload ra log |
| `docs/runbooks/taskhub-down.md`, `docs/runbooks/host-disk-usage-high.md` | Runbook cho 2 alert |
| `.gitignore` | Có dòng `monitoring/secrets/` |

> Bản tham khảo để **so sánh sau khi tự làm**: [labs/reference/](reference/README.md) — đặc biệt [compose.yaml](reference/compose.yaml), [prometheus/rules/alerts.yml](reference/prometheus/rules/alerts.yml), [alertmanager/alertmanager.yml](reference/alertmanager/alertmanager.yml), [grafana/dashboards/taskhub-overview.json](reference/grafana/dashboards/taskhub-overview.json). Bản tham khảo có thêm vài alert và service (Loki, Alloy) của các bài sau — lab này chỉ yêu cầu 2 alert.

## Điều kiện trước khi bắt đầu

`[WSL]`:

```bash
cd ~/projects/taskhub
git switch main && git pull
git switch -c feat/monitoring-dashboard-alerts

# 1. Docker chạy được trong WSL
docker info --format '{{.ServerVersion}}'

# 2. App stack chạy, project tên "taskhub" (network phải là taskhub_default)
docker compose -p taskhub ps
docker network ls --filter name=taskhub_default --format '{{.Name}}'

# 3. App đã bật /actuator/prometheus (bài 02) — gọi THẲNG container, không qua nginx
docker compose -p taskhub exec taskhub curl -s localhost:8080/actuator/prometheus | head -3

# 4. Prometheus + node-exporter của bài 02 đang chạy, mọi target UP
curl -s "localhost:${PROMETHEUS_HOST_PORT:-9090}/api/v1/targets" \
  | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)"'
```

Kết quả cần có: Docker trả về phiên bản; `taskhub_default` tồn tại; dòng `# HELP ...` của metric; các job `taskhub`, `node`, `prometheus` đều `up`.

**Port trên máy bạn.** Máy có nhiều container khác. Kiểm tra trước, đổi bằng biến môi trường nếu bị chiếm:

```bash
for p in 3000 9090 9093 8000; do
  docker ps --format '{{.Names}} {{.Ports}}' | grep -q ":$p->" && echo "Port $p đang bị container khác dùng"
done
# Ví dụ đổi: thêm vào monitoring/.env (file này KHÔNG commit nếu chứa gì riêng tư)
#   GRAFANA_HOST_PORT=3300
#   ALERTMANAGER_HOST_PORT=9393
export APP="http://localhost:${NGINX_HOST_PORT:-8000}"     # địa chỉ app qua nginx
```

> Compose đọc `.env` ở **project directory**. Theo tài liệu Docker, khi dùng `-f`, project directory là **thư mục của file compose đầu tiên** (trừ khi đặt `--project-directory`). Chạy từ gốc repo với `-f monitoring/compose.yaml` → Compose đọc `monitoring/.env`, **không** đọc `.env` ở gốc repo (file đó là của app stack). Biến `export` trong shell luôn thắng `.env`. Kiểm tra thay vì đoán: `docker compose -p taskhub-mon -f monitoring/compose.yaml config | grep published` ([Docker 05](../../04-DOCKER/05-docker-compose.md)).

---

## Phần A — Grafana provisioned

**A1. Secret và cấu trúc thư mục.**

```bash
mkdir -p monitoring/secrets monitoring/grafana/provisioning/{datasources,dashboards} \
         monitoring/grafana/dashboards monitoring/prometheus/{rules,tests} \
         monitoring/alertmanager monitoring/webhook-debug docs/runbooks
grep -qx 'monitoring/secrets/' .gitignore || echo 'monitoring/secrets/' >> .gitignore
openssl rand -base64 18 | tr -d '\n' > monitoring/secrets/grafana_admin_password
chmod 600 monitoring/secrets/*
git status --short monitoring/secrets/        # phải KHÔNG in gì (đã bị ignore)
```

**A2. Datasource và dashboard provider.** Viết 2 file theo [bài 03 mục 4.5](../03-grafana-dashboards-alerting.md#45--provisioning--grafana-dạng-code): datasource Prometheus `uid: prometheus`, `url: http://prometheus:9090`; provider `folder: taskhub`, `allowUiUpdates: false`, `path: /var/lib/grafana/dashboards`.

**A3. Service `grafana`.** Thêm vào `monitoring/compose.yaml` (tự viết, chưa mở bản tham khảo):

- image `grafana/grafana:13.3.0`, `restart: unless-stopped`, network `mon`, `mem_limit: 256m`;
- port `127.0.0.1:${GRAFANA_HOST_PORT:-3000}:3000`;
- mount provisioning, dashboards (đều `:ro`), thư mục secret `./secrets:/etc/monitoring-secrets:ro`, named volume `grafana-data:/var/lib/grafana`;
- `GF_SECURITY_ADMIN_PASSWORD__FILE=/etc/monitoring-secrets/grafana_admin_password`, `GF_USERS_ALLOW_SIGN_UP=false`.

```bash
docker compose -p taskhub-mon -f monitoring/compose.yaml config --quiet && echo "compose OK"
docker compose -p taskhub-mon -f monitoring/compose.yaml up -d grafana
GF="http://localhost:${GRAFANA_HOST_PORT:-3000}"
GF_PASS="$(cat monitoring/secrets/grafana_admin_password)"
curl -s "$GF/api/health" | jq
curl -s -u admin:"$GF_PASS" "$GF/api/datasources/uid/prometheus/health" | jq
```

✅ `api/health` có `"database": "ok"`; datasource health báo thành công. Mở `$GF` trên trình duyệt Windows (WSL chuyển tiếp `localhost`), đăng nhập `admin`.

---

## Phần B — Dashboard taskhub-overview

**B1. Tạo traffic** ở một terminal riêng (để biểu đồ có dữ liệu), gồm cả request thành công lẫn lỗi 4xx:

```bash
while true; do
  curl -s -o /dev/null "$APP/api/tasks"
  curl -s -o /dev/null "$APP/api/tasks/999999"                                  # 404
  curl -s -o /dev/null -X POST "$APP/api/tasks" -H 'Content-Type: application/json' -d '{"title":""}'  # 400
  sleep 0.5
done
```

**B2. Tạo dashboard trên UI** (Dashboards → New → New dashboard). Đặt tên `taskhub-overview`. Tạo các panel dưới đây. Mỗi panel: đặt **title**, **unit**, **threshold** đúng như bảng.

| Hàng | Panel | Kiểu | PromQL | Unit / threshold |
|---|---|---|---|---|
| 1 | App | Stat | `up{job="taskhub"}` | Value mapping 1→UP (xanh), 0→DOWN (đỏ) |
| 1 | Request/s | Stat | `sum(rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[$__rate_interval]))` | `requests/sec` |
| 1 | Tỷ lệ 5xx | Stat | `sum(rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*", status=~"5.."}[$__rate_interval])) / sum(rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[$__rate_interval]))` | `percentunit`, vàng 0.01, đỏ 0.05 |
| 1 | p95 latency | Stat | `histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{job="taskhub", uri!~"/actuator.*"}[$__rate_interval])))` | `seconds`, vàng 0.3, đỏ 0.5 |
| 2 | Request theo status | Time series | `sum by (status) (rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[$__rate_interval]))` | `requests/sec`, legend `{{status}}` |
| 2 | Latency p50/p95/p99 | Time series | 3 query `histogram_quantile(0.5 / 0.95 / 0.99, …)` | `seconds` |
| 3 | CPU host | Time series | `100 * (1 - avg(rate(node_cpu_seconds_total{job="node", mode="idle"}[$__rate_interval])))` | `percent (0-100)` |
| 3 | RAM host | Time series | `100 * (1 - node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"})` | `percent (0-100)`, đỏ 90 |
| 3 | Disk | Gauge | `100 * (1 - node_filesystem_avail_bytes{job="node", mountpoint=~"/\|/var/lib", fstype!~"tmpfs\|overlay\|9p"} / node_filesystem_size_bytes{job="node", mountpoint=~"/\|/var/lib", fstype!~"tmpfs\|overlay\|9p"})` | `percent (0-100)`, vàng 70, **đỏ 80** (= ngưỡng alert). EC2 khớp `/`; Docker Desktop khớp `/var/lib` (không có `/`) |
| 3 | JVM heap | Time series | `sum(jvm_memory_used_bytes{job="taskhub", area="heap"})` và `sum(jvm_memory_max_bytes{job="taskhub", area="heap"})` | `bytes(IEC)` |

> Trong ô query của Grafana, viết `fstype!~"tmpfs|overlay"` bình thường — dấu `\|` trong bảng chỉ là ký tự thoát của Markdown.

❓ Panel "Tỷ lệ 5xx" hiện gì khi không có lỗi 5xx nào? Còn khi **không có traffic**? (Gợi ý: 0 chia 0.)

**B3. Thử tạo lỗi 5xx (tùy chọn).** Dừng database rồi gọi API: `docker compose -p taskhub stop postgres`, gọi `$APP/api/tasks` vài lần, rồi `docker compose -p taskhub start postgres`. Request sẽ treo khoảng 30 giây mỗi lần trước khi lỗi (timeout kết nối mặc định của HikariCP — đã gặp ở [v0](../../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md)), và nginx có thể trả **504** thay vì để app trả 500. Quan sát panel "Request theo status" phân biệt được ai trả lỗi.

**B4. Export và provision.** Dashboard → **Export** → **Export as code** → *Advanced options*: **Model = Classic**, định dạng JSON, công tắc *Share dashboard with another instance* = **tắt** → *Copy to clipboard*. Dán vào `monitoring/grafana/dashboards/taskhub-overview.json`. Sửa trong file:

- `"uid": "taskhub-overview"` (cố định, để link/alert trỏ tới được lâu dài);
- `"id": null` (id là số nội bộ của database Grafana, không nên mang theo).

```bash
jq -e '.uid == "taskhub-overview"' monitoring/grafana/dashboards/taskhub-overview.json
jq -r '[.. | objects | select(has("datasource")) | .datasource.uid? // empty] | unique' \
  monitoring/grafana/dashboards/taskhub-overview.json      # phải chỉ có "prometheus"
docker compose -p taskhub-mon -f monitoring/compose.yaml restart grafana
```

Xóa dashboard bấm tay trên UI (bản provisioned nằm trong folder `taskhub`). Thử sửa một panel trên bản provisioned rồi bấm Save — ghi lại thông báo. Đó là hành vi đúng của `allowUiUpdates: false`.

**B5. Chứng minh "dashboard là code".** ⚠️ Lệnh dưới xóa **chỉ** volume của Grafana (mất user/dashboard bấm tay — dashboard provisioned không mất):

```bash
docker compose -p taskhub-mon -f monitoring/compose.yaml rm -sf grafana
docker volume rm taskhub-mon_grafana-data
docker compose -p taskhub-mon -f monitoring/compose.yaml up -d grafana
```

✅ Đăng nhập lại (mật khẩu vẫn từ file) → dashboard `taskhub-overview` có ngay, có dữ liệu (metric nằm ở Prometheus, không ở Grafana).

---

## Phần C — Hai alert và Alertmanager gửi vào webhook-debug

**C1. Rule.** Viết `monitoring/prometheus/rules/alerts.yml` với 2 alert theo [bài 03 mục 4.8](../03-grafana-dashboards-alerting.md#48--alerting-rule-của-prometheus):

| Alert | `expr` | `for` | `severity` |
|---|---|---|---|
| `TaskhubDown` | `up{job="taskhub"} == 0` | `1m` | `critical` |
| `HostDiskUsageHigh` | Tỷ lệ dùng disk `/` (bỏ `tmpfs`, `overlay`) `> 80` | `5m` | `warning` |

Mỗi alert có `summary`, `description` (dùng `{{ $labels.instance }}` hoặc giá trị) và `runbook_url` trỏ tới `docs/runbooks/*.md` trong repo của bạn.

**C2. Nạp rule vào Prometheus.** Trong `prometheus.yml`: `rule_files: [/etc/prometheus/rules/*.yml]` và khối `alerting` trỏ `alertmanager:9093`. Prometheus cần cờ `--web.enable-lifecycle` để reload qua HTTP.

```bash
docker run --rm -v "$PWD/monitoring/prometheus:/etc/prometheus:ro" --entrypoint promtool \
  prom/prometheus:v3.15.1 check config /etc/prometheus/prometheus.yml
PROM="http://localhost:${PROMETHEUS_HOST_PORT:-9090}"
curl -s -X POST "$PROM/-/reload" && echo reloaded
curl -s "$PROM/api/v1/rules" | jq -r '.data.groups[].rules[] | "\(.name)\t\(.state)\t\(.health)"'
```

✅ Hai dòng `TaskhubDown inactive ok`, `HostDiskUsageHigh inactive ok`.

**C3. Bộ nhận webhook-debug.** Viết `monitoring/webhook-debug/receiver.py` (Python thuần, ~20 dòng): `http.server` nghe `0.0.0.0:8080`, với mỗi POST đọc JSON, in `status`, `labels.alertname`, `labels.severity`, `annotations.summary` của từng alert, trả 200. Thêm service `webhook-debug` (image `python:3.12-slim`, `profiles: [debug]`, mount thư mục `:ro`, network `mon`, `mem_limit: 64m`).

**C4. Alertmanager cho laptop.** Viết `monitoring/alertmanager/alertmanager.laptop.yml`: receiver `webhook-debug` (`url: http://webhook-debug:8080/alerts`, `send_resolved: true`), `group_by: [alertname, severity]`, `group_wait: 10s`, `group_interval: 1m`, `repeat_interval: 1h` (ngắn để thí nghiệm nhanh). Thêm service `alertmanager` (image `prom/alertmanager:v0.34.2`, `--config.file=/etc/alertmanager/${ALERTMANAGER_CONFIG:-alertmanager.yml}`, port `127.0.0.1:${ALERTMANAGER_HOST_PORT:-9093}:9093`, mount thư mục cấu hình + thư mục secret, named volume, `mem_limit: 128m`).

```bash
docker run --rm -v "$PWD/monitoring/alertmanager:/a:ro" --entrypoint amtool \
  prom/alertmanager:v0.34.2 check-config /a/alertmanager.laptop.yml
export ALERTMANAGER_CONFIG=alertmanager.laptop.yml COMPOSE_PROFILES=debug
docker compose -p taskhub-mon -f monitoring/compose.yaml up -d alertmanager webhook-debug
curl -s "$PROM/api/v1/alertmanagers" | jq '.data.activeAlertmanagers'
```

✅ `check-config` báo `SUCCESS`; Prometheus liệt kê một Alertmanager active.

**C5. Thí nghiệm TaskhubDown.** Mở terminal theo dõi:

```bash
docker logs -f taskhub-mon-webhook-debug-1
```

Terminal khác — ghi lại **giờ** mỗi mốc:

```bash
date +%T; docker compose -p taskhub stop taskhub          # T0: app dừng
watch -n 5 "curl -s $PROM/api/v1/alerts | jq -r '.data.alerts[] | \"\(.labels.alertname) \(.state) \(.activeAt)\"'"
```

Khi webhook-debug in `[firing] TaskhubDown`, ghi giờ (T1). Rồi:

```bash
date +%T; docker compose -p taskhub start taskhub         # T2
```

Đợi dòng `[resolved] TaskhubDown` (T3).

❓ Tính T1 − T0 và giải thích bằng 4 con số: `scrape_interval`, `evaluation_interval`, `for`, `group_wait`. Vì sao không bao giờ là đúng 1 phút?

**C6. Thí nghiệm HostDiskUsageHigh — cách an toàn.** ⚠️ **Không** làm đầy disk thật (`fallocate`, `dd` một file lớn) để thử: database và Docker có thể hỏng khi disk đầy, và disk trên laptop là disk của máy ảo Docker Desktop dùng chung với mọi container khác của bạn.

Cách an toàn: một rule **diễn tập** riêng, ngưỡng thấp, tên khác, xóa ngay sau khi thử.

```bash
cat > monitoring/prometheus/rules/zz-disk-drill.yml <<'EOF'
# FILE TẠM — xóa sau thí nghiệm. Không commit.
groups:
  - name: drill
    rules:
      - alert: HostDiskUsageDrill
        expr: |
          (1 - node_filesystem_avail_bytes{job="node", mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|9p"}
             / node_filesystem_size_bytes{job="node", mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|9p"}) * 100
          > 1
        for: 30s
        labels:
          severity: warning
          drill: "true"
        annotations:
          summary: "DIỄN TẬP: disk / đang dùng {{ printf \"%.1f\" $value }}%"
EOF
curl -s -X POST "$PROM/-/reload"
```

Quan sát webhook-debug nhận `[firing] HostDiskUsageDrill`, rồi:

```bash
rm monitoring/prometheus/rules/zz-disk-drill.yml
curl -s -X POST "$PROM/-/reload"
```

✅ Sau khi xóa rule, Prometheus **ngừng gửi** alert đó. Mỗi lần gửi, Prometheus kèm thời hạn `endsAt` ngắn; quá hạn mà không được gửi lại, Alertmanager coi alert là đã hết và gửi `[resolved] HostDiskUsageDrill` ở chu kỳ `group_interval` kế tiếp — nên có thể mất vài phút (ghi lại thời gian bạn đo được). Biểu thức giống hệt alert thật — chỉ khác ngưỡng — nên bạn đã kiểm chứng **đường gửi** và **biểu thức**. **Logic ngưỡng 80% + `for: 5m`** sẽ được kiểm chứng bằng unit test ở Phần D.

❓ Disk `/` mà node-exporter thấy trên laptop là disk nào? Con số có khớp `df -h /` trong WSL không? Vì sao?

---

## Phần D — Kiểm thử rule bằng promtool

**D1.** Viết `monitoring/prometheus/tests/alerts_test.yml` (`rule_files: [../rules/alerts.yml]`) với **ít nhất 4** trường hợp:

| # | Alert | Dữ liệu giả lập | Khẳng định |
|---|---|---|---|
| 1 | `TaskhubDown` | `up` = 1 ba phút rồi 0 | Ở phút vừa down: **không** alert (pending) |
| 2 | `TaskhubDown` | như trên | Sau ≥ `for`: alert firing, đủ nhãn `job`, `instance`, `severity` và annotation đã điền |
| 3 | `HostDiskUsageHigh` | size = 100, avail = 50 → 15 (dùng 85%) | Chưa đủ 5 phút: **không** alert |
| 4 | `HostDiskUsageHigh` | như trên | Sau ≥ 5 phút: alert firing với nhãn `device`, `fstype`, `instance`, `job`, `mountpoint`, `severity` |

Gợi ý series cho disk: `node_filesystem_size_bytes{job="node", instance="node-exporter:9100", device="/dev/sda1", fstype="ext4", mountpoint="/"}` với `values: '100x15'`, và series `avail` cùng nhãn `values: '50x4 15x10'`.

```bash
docker run --rm -v "$PWD/monitoring/prometheus:/p:ro" -w /p/tests --entrypoint promtool \
  prom/prometheus:v3.15.1 test rules alerts_test.yml
```

**D2. Chứng minh test bắt được lỗi.** Tạm đổi ngưỡng trong `alerts.yml` thành `> 90`, chạy lại test → phải **FAIL** ở trường hợp 4. Đọc thông báo (alert mong đợi vs alert thật). Hoàn tác.

✅ Bản cuối: `SUCCESS`.

> Annotation có `{{ $value }}` thì `exp_annotations` phải khớp **chuỗi sau khi điền** — số thực như `85.00000000000001` rất khó khớp. Dùng `{{ printf "%.0f" $value }}` hoặc `printf "%.1f"` trong annotation để test ổn định (và người đọc cũng dễ đọc hơn).

---

## Phần E — Chuyển sang Telegram, thử silence

**E1.** Tạo bot và lấy chat id theo [bài 03 mục 4.10](../03-grafana-dashboards-alerting.md#410--tạo-bot-telegram-và-lấy-chat-id). Lưu `monitoring/secrets/telegram_bot_token` và `monitoring/secrets/telegram_chat_id` bằng `printf '%s'`, `chmod 600`.

**E2.** Viết `monitoring/alertmanager/alertmanager.yml`: receiver `telegram` với `bot_token_file: /etc/monitoring-secrets/telegram_bot_token`, `chat_id_file: /etc/monitoring-secrets/telegram_chat_id`, `send_resolved: true`; `group_wait: 30s`, `group_interval: 5m`, `repeat_interval: 4h`.

```bash
docker run --rm -v "$PWD/monitoring/alertmanager:/a:ro" --entrypoint amtool \
  prom/alertmanager:v0.34.2 check-config /a/alertmanager.yml
unset ALERTMANAGER_CONFIG                         # quay về mặc định alertmanager.yml
docker compose -p taskhub-mon -f monitoring/compose.yaml up -d --force-recreate alertmanager
```

> `check-config` chạy trong container dùng một lần **không** gắn thư mục secret. Nó kiểm tra cú pháp; việc Alertmanager thật đọc được file token/chat id chỉ được chứng minh ở bước gửi thử E3. Nếu phiên bản của bạn báo lỗi vì không thấy file, gắn thêm `-v "$PWD/monitoring/secrets:/etc/monitoring-secrets:ro"` vào lệnh.

**E3. Gửi thử** một alert giả trực tiếp vào Alertmanager (không cần làm hỏng gì):

```bash
docker exec taskhub-mon-alertmanager-1 amtool --alertmanager.url=http://localhost:9093 \
  alert add alertname=TelegramTest severity=warning --annotation='summary="Thử kênh Telegram từ laptop"'
```

✅ Khoảng 30 giây sau (`group_wait`), điện thoại nhận tin. Không nhận được → mục 12 bài 03 (log `Notify for alerts failed`). Bọc **cả** `summary="..."` trong nháy đơn như trên: viết `--annotation=summary="... có dấu cách"` thì shell bỏ mất nháy kép, amtool 0.34 vẫn chạy nhưng in cảnh báo `Alertmanager is moving to a new parser for labels and matchers` (đã chạy thử). Cú pháp khác trên phiên bản của bạn → `amtool alert add --help`.

**E4.** Lặp lại thí nghiệm C5 (dừng app) — lần này nhận trên Telegram cả `FIRING` lẫn `RESOLVED`.

**E5. Silence.** Trước khi dừng app lần nữa, tạo silence 10 phút:

```bash
docker exec taskhub-mon-alertmanager-1 amtool --alertmanager.url=http://localhost:9093 \
  silence add alertname=TaskhubDown --duration=10m --comment="Lab 01: thử silence"
docker exec taskhub-mon-alertmanager-1 amtool --alertmanager.url=http://localhost:9093 silence query
```

Dừng app 2 phút rồi bật lại. ✅ Prometheus vẫn báo `firing` (`/api/v1/alerts`), nhưng **không** có tin Telegram. Hủy silence sớm: `silence expire <ID>`.

❓ Vì sao silence đặt ở Alertmanager chứ không "tắt rule" ở Prometheus?

---

## Phần F — Commit qua Pull Request

1. Viết 2 runbook ngắn trong `docs/runbooks/` (mẫu ở [bài 03 mục 4.13](../03-grafana-dashboards-alerting.md#413--alert-fatigue-và-runbook)).
2. Kiểm tra không lộ secret:

   ```bash
   git status --short
   git diff --cached --name-only | grep -E 'secrets/|\.env$' && echo "⚠️ DỪNG: có file secret trong staging"
   git grep -nE '[0-9]{8,10}:[A-Za-z0-9_-]{30,}' -- . ':!*.md' || echo "Không thấy chuỗi giống token Telegram"
   ```

3. Commit theo Conventional Commits (`feat(monitoring): dashboard taskhub-overview và alert TaskhubDown, HostDiskUsageHigh`), push, mở PR. CI hiện tại không đụng `monitoring/` — đó là lý do bài tập 4 của bài 03 đề nghị thêm job `promtool`.

---

## Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `network taskhub_default declared as external, but could not be found` | App stack chưa chạy, hoặc chạy với tên project khác | `docker compose -p taskhub up -d` trước |
| Target `taskhub` DOWN: `no such host` | Prometheus không nằm trong network `taskhub_default` | Service `prometheus` phải có cả network `mon` và `app` (external) |
| Grafana `Bind for 127.0.0.1:3000 failed: port is already allocated` | Container khác dùng 3000 | `GRAFANA_HOST_PORT=3300`, kiểm tra bằng `compose config` |
| Panel p95 "No data" | Chưa bật histogram trong app | `management.metrics.distribution.percentiles-histogram.http.server.requests: true` (bài 02) |
| `/-/reload` trả `Lifecycle API is not enabled` | Thiếu cờ `--web.enable-lifecycle` | Thêm vào `command:` của Prometheus, recreate |
| Rule không xuất hiện | Sai đường dẫn `rule_files`, hoặc file rule lỗi cú pháp (Prometheus giữ cấu hình cũ) | `promtool check config`, xem log Prometheus sau reload |
| webhook-debug không nhận gì | Thiếu `COMPOSE_PROFILES=debug` nên service không chạy; hoặc Alertmanager đang dùng `alertmanager.yml` (Telegram) | `docker compose ... ps`; kiểm tra `ALERTMANAGER_CONFIG` |
| Test promtool fail vì annotation | Annotation chứa số thực chưa định dạng | `printf "%.1f"` trong annotation |
| Telegram không nhận dù alert firing | Token/chat id sai, chưa `/start`, đang có silence | Log Alertmanager; `amtool silence query`; `getMe` |

## Checklist hoàn thành

- [ ] Dashboard `taskhub-overview` provisioned từ file, sống sót sau khi xóa volume Grafana (B5).
- [ ] Mọi panel có unit; panel disk đỏ ở 80% đúng bằng ngưỡng alert.
- [ ] `TaskhubDown` firing và resolved đến webhook-debug, đã giải thích được T1 − T0.
- [ ] Diễn tập disk an toàn bằng rule tạm, đã xóa file tạm.
- [ ] `promtool test rules` xanh với ≥ 4 trường hợp; đã chứng minh test bắt được ngưỡng sai.
- [ ] Nhận được alert thật trên Telegram; silence hoạt động.
- [ ] Không file secret nào trong Git; PR đã mở.

Lời giải tham khảo: [solutions/lab-01-solutions.md](../solutions/lab-01-solutions.md) — chỉ mở sau khi đã tự làm.

## Dọn dẹp

```bash
# Dừng bộ giám sát nhưng GIỮ dữ liệu (dùng tiếp ở bài 04–06):
docker compose -p taskhub-mon -f monitoring/compose.yaml stop
# Vòng lặp traffic ở terminal B1: Ctrl+C
```

⚠️ `docker compose -p taskhub-mon -f monitoring/compose.yaml down -v` xóa **toàn bộ** metric Prometheus, dữ liệu Grafana/Alertmanager của lab — chỉ chạy khi chắc chắn không cần nữa. Lệnh này **không** đụng app stack `taskhub` hay database của app (project khác).
