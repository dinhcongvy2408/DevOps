# 03. Grafana, dashboard và cảnh báo (Alertmanager)

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Monitoring, logging, observability](01-monitoring-logging-observability.md), [02. Metrics và Prometheus](02-metrics-prometheus.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL integration), `[Browser]` trình duyệt trên Windows
> Phiên bản khi viết: Grafana 13.3.0, Prometheus 3.15.1, Alertmanager 0.34.2, node_exporter 1.12.1

> 💰 **Chi phí của bài này: 0 USD.** Mọi thứ chạy trên laptop. Trên EC2 (v5), Grafana **không** mở ra Internet — bạn vào bằng SSM port forwarding.
> ⚙️ **Điều kiện:** app stack `taskhub` đang chạy với endpoint `/actuator/prometheus` (bài 02), Prometheus + node-exporter của bài 02 đang chạy trong project `taskhub-mon`. Máy bạn có nhiều container khác: mọi port trong bài đều đổi được bằng biến môi trường (`GRAFANA_HOST_PORT`, `PROMETHEUS_HOST_PORT`, `ALERTMANAGER_HOST_PORT`).

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc](#6-sơ-đồ-kiến-trúc)
7. [Các câu lệnh cần biết](#7-các-câu-lệnh-cần-biết)
8. [Giải thích câu lệnh và tham số](#8-giải-thích-câu-lệnh-và-tham-số)
9. [Bài thực hành từng bước](#9-bài-thực-hành-từng-bước)
10. [Kết quả mong đợi](#10-kết-quả-mong-đợi)
11. [Các lỗi thường gặp](#11-các-lỗi-thường-gặp)
12. [Đọc log và xử lý lỗi](#12-đọc-log-và-xử-lý-lỗi)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Giải thích **Grafana** làm gì và **không** làm gì (không lưu metric — chỉ hỏi Prometheus/Loki rồi vẽ).
- Tạo **datasource**, **dashboard**, **panel**; chọn đúng loại biểu đồ, đơn vị (unit), ngưỡng (threshold).
- Dùng biến dashboard và `$__rate_interval` đúng cách.
- **Provision** Grafana bằng file (datasource + dashboard nằm trong Git) thay vì bấm tay.
- Thiết kế dashboard theo **RED** (cho service) và **USE** (cho tài nguyên máy).
- Viết **alerting rule** của Prometheus: `expr`, `for`, `labels.severity`, `annotations`.
- Cấu hình **Alertmanager**: cây route, `group_by`, `group_wait`, `group_interval`, `repeat_interval`, **inhibition**, **silence**, receiver **Telegram** và **webhook**.
- Kiểm thử cảnh báo **trước khi** có sự cố thật: `promtool test rules`, `amtool check-config`, `amtool config routes test`.
- Nhận ra **alert fatigue** (mệt mỏi vì cảnh báo) và viết cảnh báo có **runbook**.

## 2. Tại sao DevOps Engineer cần kiến thức này?

Ở bài 02 bạn đã có Prometheus thu metric. Nhưng chưa ai **nhìn** vào nó, và khi app chết lúc 2 giờ sáng thì cũng chưa ai **biết**.

| Tình huống thật | Thứ giải quyết |
|---|---|
| Sếp hỏi "hệ thống hôm nay thế nào?" | **Dashboard** — trả lời trong 10 giây bằng một màn hình |
| Người dùng báo "web chậm" lúc 14:05 | Dashboard có **p95 latency** + **logs** cùng khung giờ → khoanh vùng nhanh |
| App chết lúc 2 giờ sáng | **Alert** → Telegram rung điện thoại, kèm link runbook |
| Disk đầy dần trong 3 tuần | Alert **disk > 80%** báo trước khi database ngừng ghi |
| Một sự cố gây 40 cảnh báo cùng lúc | Alertmanager **gom nhóm** + **inhibition** → 1–2 tin nhắn có nghĩa |

Câu hỏi phỏng vấn Junior DevOps rất hay gặp: *"Bạn giám sát dự án thế nào? Alert nào bạn đặt, vì sao, khi nó kêu thì bạn làm gì?"* Bài này và [Lab 01](labs/lab-01-dashboard-alerts.md) cho bạn câu trả lời bằng chính hệ thống của mình.

## 3. Kiến thức nền tảng cần hiểu

| Khái niệm | Ý nghĩa ngắn | Đã gặp ở |
|---|---|---|
| Metric, label, time series | Chuỗi số theo thời gian, định danh bằng tên + nhãn | [Bài 02](02-metrics-prometheus.md) |
| PromQL `rate()`, `sum by`, `histogram_quantile()` | Tính tốc độ, gộp nhóm, tính phân vị | [Bài 02](02-metrics-prometheus.md) |
| Four golden signals | Latency, traffic, errors, saturation | [Bài 01](01-monitoring-logging-observability.md) |
| Symptom vs cause | Cảnh báo theo **triệu chứng** người dùng thấy, không theo nguyên nhân | [Bài 01](01-monitoring-logging-observability.md) |
| Docker Compose project, network, volume | Bộ giám sát là project riêng `taskhub-mon` | [Docker 05](../04-DOCKER/05-docker-compose.md) |
| Secret không nằm trong Git | Token bot, mật khẩu admin đọc từ file | [CI/CD 04](../05-CICD/04-secrets-environments.md) |
| SSM port forwarding | Vào Grafana trên EC2 mà không mở Security Group | [AWS 04](../06-AWS/04-ec2.md) |

## 4. Giải thích chi tiết

### 4.1. 🟥 Grafana là gì — và không phải là gì

**Grafana** là công cụ **trực quan hóa** (visualization): bạn viết câu truy vấn, Grafana gửi tới nguồn dữ liệu, nhận kết quả và vẽ.

- Grafana **không lưu** metric hay log. Metric nằm trong **Prometheus**, log nằm trong **Loki** ([bài 04](04-centralized-logging.md)).
- Grafana tự có database nhỏ (SQLite trong `/var/lib/grafana`) để lưu **cấu hình**: user, dashboard tạo bằng tay, datasource tạo bằng tay.
- Hệ quả: xóa volume `grafana-data` thì mất dashboard **bấm tay**, nhưng **không** mất metric. Dashboard provision từ file thì không mất gì — đó là lý do mục 4.5 tồn tại.

### 4.2. 🟥 Datasource

**Datasource** (nguồn dữ liệu) là cấu hình "Grafana hỏi ai, ở địa chỉ nào".

| Trường | Giá trị trong taskhub | Giải thích |
|---|---|---|
| `type` | `prometheus` / `loki` | Loại plugin |
| `url` | `http://prometheus:9090` | Địa chỉ **từ bên trong container Grafana** — dùng tên service trong network `mon`, **không phải** `localhost` |
| `access` | `proxy` | Server Grafana đi hỏi (trình duyệt của bạn không gọi thẳng Prometheus) |
| `uid` | ví dụ `prometheus` | Định danh **cố định**. Panel trong dashboard JSON tham chiếu datasource bằng `uid` — uid đổi là panel "No data" |

> ⚠️ Lỗi phổ biến nhất của người mới: đặt `url: http://localhost:9090`. Trong container Grafana, `localhost` là **chính container Grafana**, không phải Prometheus. Đây đúng là bài học network namespace ở [Docker 04](../04-DOCKER/04-volumes-networks-env.md).

### 4.3. 🟥 Dashboard, panel, đơn vị, ngưỡng

Một **dashboard** gồm nhiều **panel**. Mỗi panel = một (hoặc vài) câu truy vấn + một kiểu hiển thị.

| Kiểu panel | Dùng khi | Ví dụ taskhub |
|---|---|---|
| **Time series** | Xem xu hướng theo thời gian | Request/giây, p95 latency, CPU |
| **Stat** | Một con số hiện tại, to, dễ đọc | `up` của app (UP/DOWN), tỷ lệ lỗi hiện tại |
| **Gauge / Bar gauge** | Mức đầy của tài nguyên có giới hạn | Disk 63% |
| **Table** | So sánh nhiều thực thể | Top 5 endpoint chậm nhất |
| **Logs** | Dòng log từ Loki ngay cạnh biểu đồ | Log `level=ERROR` của taskhub |

Ba thiết lập quyết định panel **đọc được** hay **đánh đố**:

- **Unit** (đơn vị): `seconds (s)`, `bytes(IEC)`, `percent (0-100)`, `percentunit (0.0-1.0)`, `requests/sec`. Không đặt unit → người đọc thấy `0.0423` và không biết là giây, phần trăm hay gì.
- **Threshold** (ngưỡng màu): xanh < 70%, vàng < 80%, đỏ ≥ 80% — **khớp với ngưỡng alert** để dashboard và cảnh báo nói cùng một ngôn ngữ.
- **Value mapping**: `1 → UP` (xanh), `0 → DOWN` (đỏ) cho panel `up`.

### 4.4. 🟨 Biến dashboard và `$__rate_interval`

**Variable** (biến) cho phép một dashboard dùng cho nhiều đối tượng: biến `instance` lấy danh sách bằng `label_values(up{job="taskhub"}, instance)`, rồi query viết `up{instance="$instance"}`. taskhub hiện chỉ có một instance, nên biến là 🟨 — nhưng bạn sẽ gặp ở mọi dashboard công ty.

Biến **có sẵn** quan trọng nhất với Prometheus là **`$__rate_interval`**. Tài liệu Grafana: đây là biến "thiết kế để dùng với `rate()` và `increase()`", bảo đảm cửa sổ đủ rộng để chứa **ít nhất 4 mẫu scrape**, và khuyên *"luôn dùng `$__rate_interval` thay vì khoảng cố định hoặc `$__interval`"*.

```promql
# Trong panel Grafana:
sum(rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[$__rate_interval]))

# Trong file rule của Prometheus (không có Grafana) → dùng khoảng cố định:
sum(rate(http_server_requests_seconds_count{job="taskhub"}[5m]))
```

Vì sao `uri!~"/actuator.*"`? Chính Prometheus gọi `/actuator/prometheus` mỗi 15 giây — request đó cũng được đếm. Không lọc thì dashboard luôn có "traffic" dù không ai dùng app, và p95 bị kéo về phía các request scrape.

### 4.5. 🟥 Provisioning — Grafana dạng code

**Provisioning** là để Grafana đọc cấu hình từ **file** lúc khởi động. Trong image Docker, thư mục mặc định là `GF_PATHS_PROVISIONING=/etc/grafana/provisioning` (tài liệu Grafana — bảng đường dẫn mặc định của image Docker).

```text
monitoring/grafana/
├── provisioning/
│   ├── datasources/datasources.yaml     ← Prometheus, Loki (uid cố định)
│   └── dashboards/dashboards.yaml       ← "provider": đọc JSON từ thư mục nào
└── dashboards/
    └── taskhub-overview.json            ← dashboard, export từ UI rồi commit
```

Datasource provisioning:

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus          # panel trong JSON tham chiếu uid này
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

Dashboard provider (cấu trúc theo ví dụ trong tài liệu Grafana):

```yaml
apiVersion: 1
providers:
  - name: taskhub
    orgId: 1
    folder: taskhub            # thư mục hiển thị trong Grafana
    type: file
    disableDeletion: true      # không cho xóa dashboard provisioned từ UI
    allowUiUpdates: false      # sửa trên UI không lưu được → buộc sửa qua Git
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
```

| Cách | Ưu | Nhược |
|---|---|---|
| Bấm tay trên UI | Nhanh lúc thử | Mất khi xóa volume; không review được; dựng lại server = vẽ lại từ đầu |
| **Provisioning từ Git** | Dựng lại server → dashboard có ngay; thay đổi đi qua PR | Phải export JSON và commit mỗi lần đổi |

Quy trình chuẩn: **thử trên UI → Export → commit JSON → Grafana đọc lại từ file**. Grafana 13: Export → *Export as code* → mục *Advanced options* chọn **Model: Classic**, định dạng JSON. Công tắc *Share dashboard with another instance* để **tắt** khi file dùng cho provisioning của chính bạn (bật thì Grafana thay uid datasource bằng biến đầu vào, file không provision thẳng được).

Mật khẩu admin: tài liệu Grafana mô tả hậu tố **`__FILE`** — `GF_SECURITY_ADMIN_PASSWORD__FILE=/đường/dẫn/file` — Grafana đọc giá trị từ file. Mật khẩu không nằm trong `compose.yaml` hay `env`.

### 4.6. 🟥 Thiết kế dashboard: RED cho service, USE cho tài nguyên

| Phương pháp | Áp cho | Ba câu hỏi | Panel taskhub |
|---|---|---|---|
| **RED** (Tom Wilkie, 2015) | **Service** (taskhub) | **R**ate — bao nhiêu request/giây? **E**rrors — bao nhiêu thất bại? **D**uration — mất bao lâu? | Request rate · Tỷ lệ 5xx · p95 latency |
| **USE** (Brendan Gregg) | **Tài nguyên** (CPU, RAM, disk) | **U**tilization — dùng bao nhiêu %? **S**aturation — có hàng đợi/nghẽn không? **E**rrors — có lỗi phần cứng/IO không? | CPU % · RAM % · Disk % · (🟨 load average, swap) |

Câu gốc của USE: *"For every resource, check utilization, saturation, and errors."* RED chính là "golden signals" áp cho từng service (Saturation chuyển sang phía USE).

Bố cục dashboard `taskhub-overview`:

```text
┌──────────────── Hàng 1: "Có đang ổn không?" (Stat, nhìn 3 giây) ────────────────┐
│  App UP/DOWN   │  Request/s   │  Tỷ lệ 5xx (%)  │  p95 latency (s)               │
├──────────────── Hàng 2: RED theo thời gian (Time series) ────────────────────────┤
│  Request rate theo status   │  Tỷ lệ lỗi        │  p95 / p99 latency             │
├──────────────── Hàng 3: USE của host + JVM ──────────────────────────────────────┤
│  CPU %   │  RAM %   │  Disk / (%) — ngưỡng 80% đỏ  │  JVM heap used / max        │
├──────────────── Hàng 4: Logs (Loki — bài 04) ────────────────────────────────────┤
│  {compose_service="taskhub", level="ERROR"}                                      │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Nguyên tắc:

1. **Quan trọng nhất ở góc trên bên trái** — mắt người đọc bắt đầu từ đó.
2. **Mỗi panel trả lời một câu hỏi.** Không trả lời được "panel này để làm gì khi có sự cố?" → bỏ.
3. **Tránh panel "cho đẹp"** (vanity panel): uptime 9999 ngày, tổng request từ đầu năm, đồng hồ CPU từng core của 16 core. Đẹp nhưng không giúp ra quyết định.
4. **Cùng trục thời gian, cùng ngưỡng với alert.**

### 4.7. 🟥 Đường đi của một cảnh báo

```text
 Prometheus                                  Alertmanager                        Con người
 ┌──────────────────────────────┐            ┌────────────────────────────┐
 │ mỗi evaluation_interval (15s)│            │ 1. nhận alert              │
 │ tính expr của mỗi rule       │  firing    │ 2. route: chọn receiver    │      Telegram
 │  ─ false → inactive          │ ─────────► │ 3. group: gom theo group_by│ ───► (điện thoại)
 │  ─ true lần đầu → pending    │  (HTTP)    │ 4. inhibit / silence?      │      webhook
 │  ─ true liên tục ≥ for → FIRING│          │ 5. chờ group_wait → gửi     │ ───► (log)
 └──────────────────────────────┘            └────────────────────────────┘
```

Chia việc rõ ràng: **Prometheus quyết định "có vấn đề không"**, **Alertmanager quyết định "báo cho ai, khi nào, gộp thế nào"**.

### 4.8. 🟥 Alerting rule của Prometheus

```yaml
groups:
  - name: taskhub
    rules:
      - alert: TaskhubDown
        expr: up{job="taskhub"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "taskhub không trả lời Prometheus"
          description: "Scrape {{ $labels.instance }} thất bại hơn 1 phút."
          runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/taskhub-down.md"
```

| Trường | Ý nghĩa (theo tài liệu Prometheus) | Chọn thế nào |
|---|---|---|
| `alert` | Tên cảnh báo | Danh từ + tình trạng, CamelCase: `TaskhubDown`, `HostDiskUsageHigh` |
| `expr` | Biểu thức PromQL; **mỗi series trả về** là một alert | Viết sao cho kết quả rỗng khi bình thường |
| `for` | Chờ điều kiện đúng **liên tục** bấy lâu rồi mới firing (trong lúc chờ: **pending**) | Đủ dài để bỏ qua dao động (deploy, GC), đủ ngắn để kịp phản ứng |
| `keep_firing_for` 🟨 | Giữ trạng thái firing thêm một lúc sau khi điều kiện hết đúng | Chống "nhấp nháy" firing/resolved |
| `labels` | Nhãn **thêm** vào alert — dùng để **route** | `severity: critical` / `warning` |
| `annotations` | Thông tin cho **người đọc**, không dùng để route | `summary`, `description`, `runbook_url` |
| `{{ $labels.x }}`, `{{ $value }}` | Template: nhãn và giá trị của alert | Cho người nhận biết **ở đâu** và **bao nhiêu** |

Ba trạng thái: **inactive** (điều kiện sai) → **pending** (đúng nhưng chưa đủ `for`) → **firing** (gửi sang Alertmanager). Khi điều kiện hết đúng, alert **resolved** và Alertmanager gửi thông báo "đã hết" nếu `send_resolved: true`.

Hai alert bắt buộc của taskhub:

```yaml
      - alert: HostDiskUsageHigh
        expr: |
          (1 - node_filesystem_avail_bytes{job="node", mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|9p"}
             / node_filesystem_size_bytes{job="node", mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|9p"}) * 100
          > 80
        for: 5m
        labels:
          severity: warning
```

- `avail` (còn dùng được bởi user thường), không phải `free` (gồm cả phần dành riêng cho root) — "đầy với ứng dụng" là theo `avail`.
- `fstype!~"tmpfs|overlay"`: bỏ filesystem trong RAM và lớp overlay của container — chúng không phải "disk của máy".
- 🟥 Trên laptop, node-exporter chạy trong Docker Desktop → "host" là **máy ảo Linux của Docker Desktop**, không phải ổ C: của Windows hay filesystem WSL. Trên EC2 thì đúng là ổ EBS gốc. Đọc số trên laptop với hiểu biết đó.

### 4.9. 🟥 Alertmanager: route, nhóm, nhịp gửi, inhibition, silence

Ba khái niệm theo tài liệu Alertmanager:

- **Grouping**: *"gom các cảnh báo cùng bản chất thành một thông báo"*.
- **Inhibition**: *"chặn thông báo của một số cảnh báo nếu một số cảnh báo khác đang firing"*.
- **Silences**: *"cách đơn giản để tắt tiếng cảnh báo trong một khoảng thời gian"*.

```yaml
route:
  receiver: telegram              # receiver mặc định (gốc của cây)
  group_by: [alertname, severity]
  group_wait: 30s                 # mặc định 30s: chờ gom alert cùng nhóm trước lần gửi đầu
  group_interval: 5m              # mặc định 5m: nhóm đã gửi, có alert MỚI → gửi lại sau ≥ 5m
  repeat_interval: 4h             # mặc định 4h: alert vẫn cháy → nhắc lại mỗi 4h
  routes:                         # 🟨 nhánh con: khớp matchers → receiver khác
    - matchers: [severity="warning"]
      receiver: telegram-warning
      repeat_interval: 12h

inhibit_rules:
  - source_matchers: [alertname="TaskhubDown"]
    target_matchers: [alertname=~"TaskhubHighErrorRate|TaskhubHighLatencyP95"]
```

| Thiết lập | Đặt sai thì sao |
|---|---|
| `group_by: []` hoặc thiếu | 30 alert disk của 30 máy → **30 tin nhắn** |
| `group_wait` quá dài | Sự cố nghiêm trọng bị báo muộn |
| `repeat_interval` quá ngắn (5m) | Điện thoại rung liên tục suốt sự cố → người trực tắt thông báo → bỏ lỡ alert thật |
| Không inhibition | App chết → nhận cả `TaskhubDown` lẫn "tỷ lệ lỗi cao", "latency cao" — 3 tin cho 1 nguyên nhân |

**Silence** dùng khi **biết trước**: bảo trì, deploy lớn, hoặc đang xử lý sự cố đã rõ. Silence có thời hạn và có người tạo, lý do — khác hẳn việc xóa rule.

**Receiver** là "gửi đi đâu". Taskhub dùng hai loại (trường lấy từ tài liệu cấu hình Alertmanager):

| Receiver | Trường chính | Dùng khi |
|---|---|---|
| `telegram_configs` | `bot_token` **hoặc** `bot_token_file` (loại trừ nhau), `chat_id` **hoặc** `chat_id_file`, `parse_mode` (mặc định `HTML`), `send_resolved` (mặc định `true`) | Thật: laptop khi đã có bot, EC2 |
| `webhook_configs` | `url` **hoặc** `url_file`, `send_resolved`, `max_alerts` (0 = tất cả) | Lab: gửi vào container `webhook-debug` in payload ra log; ở công ty: tích hợp hệ thống ticket/on-call |

Dùng `*_file` thay vì ghi token thẳng vào YAML: file cấu hình commit lên Git được, token nằm ở file khác không commit (trên EC2 do Ansible ghi từ Parameter Store).

### 4.10. 🟥 Tạo bot Telegram và lấy chat id

1. Mở Telegram, chat với **@BotFather** (tài khoản chính thức, có dấu tích xanh), gửi `/newbot`, làm theo hướng dẫn đặt tên → BotFather trả về **token** dạng `123456789:AA...`.
   Tài liệu Telegram: hãy *"coi token như mật khẩu và đừng chia sẻ với ai"*. Ai có token là điều khiển được bot.
2. Mở chat với bot vừa tạo và gửi một tin bất kỳ (ví dụ `/start`). **Bot không tự nhắn cho bạn trước được** — bạn phải mở cuộc trò chuyện.
3. Lấy chat id bằng Bot API `getUpdates` (dạng URL `https://api.telegram.org/bot<token>/getUpdates`):

   ```bash
   read -rs TG_TOKEN            # dán token, không hiện ra màn hình, không vào history
   curl -s "https://api.telegram.org/bot${TG_TOKEN}/getUpdates" | jq '.result[].message.chat | {id, type}'
   ```

   ```text
   { "id": 987654321, "type": "private" }      ← minh họa
   ```

   Chat nhóm có id **âm** (ví dụ `-1001234567890`). Theo tài liệu Bot API, `getUpdates` **không** chạy khi bot đã đặt webhook — bot mới tạo chưa có webhook nên không gặp vấn đề này.
4. Lưu vào thư mục secret **không commit**:

   ```bash
   printf '%s' "$TG_TOKEN" > monitoring/secrets/telegram_bot_token     # printf: không thêm xuống dòng
   printf '%s' 987654321  > monitoring/secrets/telegram_chat_id
   chmod 600 monitoring/secrets/*
   unset TG_TOKEN
   ```

> ⚠️ Lỡ commit token hoặc dán vào ảnh chụp màn hình → vào @BotFather `/revoke` để thu hồi và tạo token mới. Xóa commit **không** đủ (bài học ở [Git 00](../03-GIT/00-git-quick-review.md)).

### 4.11. 🟨 Grafana-managed alerting — biết để chọn

Grafana 13 có hệ thống cảnh báo riêng (*Alerting* trong menu): rule viết trên UI, đánh giá trên Grafana, gửi qua *contact point* (có cả Telegram).

| Tiêu chí | Prometheus rule + Alertmanager (taskhub chọn) | Grafana-managed alerting |
|---|---|---|
| Rule ở đâu | File YAML trong Git, review qua PR | Database Grafana (có thể provision, phức tạp hơn) |
| Kiểm thử tự động | `promtool test rules` — chạy được trong CI | Hạn chế |
| Grafana chết | Cảnh báo **vẫn chạy** | Cảnh báo chết theo |
| Query nhiều nguồn (Loki, SQL…) | Chỉ PromQL | Mạnh hơn |

Ở công ty bạn sẽ gặp cả hai. Nguyên tắc: **cảnh báo phải sống lâu hơn công cụ vẽ biểu đồ**.

### 4.12. 🟥 Kiểm thử cảnh báo trước khi cần

Một alert chưa từng kêu là một alert **chưa chắc chạy**. Ba lớp kiểm tra:

| Công cụ | Kiểm tra gì | Có trong image |
|---|---|---|
| `promtool check rules` | Cú pháp file rule, PromQL hợp lệ | `prom/prometheus` |
| `promtool test rules` | **Logic**: với dữ liệu giả lập X, alert Y có firing ở phút Z với đúng nhãn không | `prom/prometheus` |
| `amtool check-config` | Cú pháp `alertmanager.yml` | `prom/alertmanager` |
| `amtool config routes test` | Alert có nhãn X đi tới receiver nào | `prom/alertmanager` |

File test của `promtool` (cấu trúc theo tài liệu "Unit testing for rules"):

```yaml
rule_files:
  - ../rules/alerts.yml          # đường dẫn tính từ vị trí file test

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      # '1x2 0x6' = 1,1,1 rồi 0 ×7 (phút 0..9). Ký hiệu: 'a+bxn', 'axn', '_' (thiếu mẫu), 'stale'
      - series: 'up{job="taskhub", instance="taskhub:8080"}'
        values: '1x2 0x6'
    alert_rule_test:
      - eval_time: 3m             # mới down 0 phút → chưa có gì (đang pending)
        alertname: TaskhubDown
        exp_alerts: []
      - eval_time: 5m             # down từ phút 3, for: 1m → firing
        alertname: TaskhubDown
        exp_alerts:
          - exp_labels:
              severity: critical
              job: taskhub
              instance: taskhub:8080
            exp_annotations:
              summary: "taskhub không trả lời Prometheus"
              description: "Scrape taskhub:8080 thất bại hơn 1 phút."
```

- `exp_alerts: []` = khẳng định **không** có alert nào — quan trọng ngang khẳng định có.
- `exp_labels` phải khớp **toàn bộ** nhãn của alert (nhãn series + nhãn rule). `exp_annotations` là annotation **sau khi** điền template — rule có `runbook_url` thì `exp_annotations` cũng phải có `runbook_url`.
- Chạy: `promtool test rules tests/alerts_test.yml`.

### 4.13. 🟥 Alert fatigue và runbook

**Alert fatigue**: cảnh báo kêu quá nhiều, phần lớn không cần làm gì → người trực quen bỏ qua → bỏ lỡ alert thật. Đây là lỗi vận hành rất phổ biến.

Sách SRE của Google: hãy dồn công sức bắt **triệu chứng** hơn là nguyên nhân, và *"mọi page phải hành động được"* (every page should be actionable) — nếu phản ứng chỉ là thao tác máy móc thì hãy tự động hóa nó thay vì gọi người dậy.

| Alert tệ | Vì sao tệ | Alert tốt hơn |
|---|---|---|
| `CPU > 70%` trong 1 phút | Nguyên nhân, dao động bình thường, không ai làm gì | p95 latency > 500ms trong 10 phút (triệu chứng) |
| Không có `for` | Mỗi lần deploy (app down 20s) là một alert | `for: 1m` |
| `summary: "Alert!"` | Người nhận không biết gì | "Disk / của host đã dùng 85%" + runbook |
| Mọi thứ đều `critical` | Không phân biệt "dậy ngay" với "sáng mai xem" | `critical` = xử lý ngay; `warning` = trong giờ làm việc |

**Runbook**: trang ngắn trả lời "alert này kêu thì làm gì". Mỗi alert một runbook trong `docs/runbooks/`, link bằng `runbook_url`:

```markdown
# Runbook: TaskhubDown
- Ý nghĩa: Prometheus không scrape được taskhub:8080 trong hơn 1 phút.
- Ảnh hưởng: người dùng không gọi được API (nginx trả 502).
- Kiểm tra: docker compose -p taskhub ps · docker logs --tail 100 taskhub · dashboard taskhub-overview
- Xử lý nhanh: docker compose -p taskhub up -d · nếu do bản mới → rollback (CI/CD bài 05)
- Leo thang: sau 15 phút chưa xong → ghi incident (bài 06).
```

### 4.14. Gặp lại ở đâu

| Kiến thức bài này | Gặp lại ở |
|---|---|
| Dashboard RED/USE, provisioning | [Lab 01](labs/lab-01-dashboard-alerts.md), dự án [v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md) |
| Logs panel trong dashboard | [Bài 04 — Loki + Alloy](04-centralized-logging.md) |
| Alert → runbook → xử lý → postmortem | [Bài 06 — Incident response](06-incident-response.md), incident drill |
| `promtool test rules` trong CI | Bài tập 4 (thêm vào workflow), [CI/CD 02](../05-CICD/02-github-actions-basics.md) |
| Alert backup quá cũ | Bài 06, script backup v5 |
| Kubernetes: PrometheusRule, Grafana dashboards | Module 09 — Kubernetes (🟦) |

## 5. Ví dụ thực tế

**Tình huống:** 23:40 thứ Sáu, Telegram rung:

```text
🔥 [FIRING:1] TaskhubDown (critical)
summary: taskhub không trả lời Prometheus
description: Scrape taskhub:8080 thất bại hơn 1 phút.
runbook: https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/taskhub-down.md
```

(minh họa — định dạng thật tùy template)

Người trực làm theo runbook:

1. Mở Grafana qua SSM port forwarding → hàng 1: App **DOWN** từ 23:38. Hàng 3: RAM host 97% từ 23:30, JVM heap đi ngang.
2. Logs panel: không có log mới từ 23:38. `docker ps -a` trên EC2: `taskhub` `Exited (137)` → **OOMKilled** ([Docker 08](../04-DOCKER/08-container-troubleshooting.md)).
3. Không nhận thêm tin "tỷ lệ lỗi cao" — **inhibition** đã chặn vì cùng nguyên nhân.
4. Khởi động lại (`restart: unless-stopped` đã tự làm, nhưng bị giết lại) → giảm tải tạm thời, rồi mở ticket điều tra memory.
5. 23:52: Telegram `✅ [RESOLVED] TaskhubDown`. Thứ Hai viết postmortem (bài 06).

Không có dashboard và alert: người dùng phát hiện sáng thứ Bảy, không ai biết sự cố bắt đầu từ lúc nào và vì sao.

## 6. Sơ đồ kiến trúc

```text
 [Browser] http://localhost:3000 (laptop) / SSM port forwarding (EC2)
     │
     ▼
 ┌──────────────────────── project taskhub-mon (network "mon") ─────────────────────────┐
 │  grafana:3000 ── query ──► prometheus:9090 ── scrape ──► node-exporter:9100          │
 │     │  (provisioning:              │  │                                               │
 │     │   datasource + dashboard     │  └── scrape ──► taskhub:8080/actuator/prometheus │
 │     │   từ Git)                    │        (qua network external taskhub_default)    │
 │     └── query ──► loki:3100        │                                                  │
 │                                    │ rule firing                                      │
 │                                    ▼                                                  │
 │                         alertmanager:9093 ──► telegram (EC2, laptop khi có bot)       │
 │                                    └────────► webhook-debug:8080 (laptop, profile debug)│
 └───────────────────────────────────────────────────────────────────────────────────────┘
 Port publish: chỉ 127.0.0.1 (Grafana, Prometheus, Alertmanager). Loki không publish.
```

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích |
|---|---|
| `docker compose -p taskhub-mon -f monitoring/compose.yaml up -d grafana` | Chạy/khởi động lại Grafana |
| `curl -s -u admin:"$GF_PASS" localhost:3000/api/health` | Grafana sống chưa |
| `curl -s -u admin:"$GF_PASS" localhost:3000/api/datasources/uid/prometheus/health` | Datasource kết nối được không |
| `curl -s localhost:9090/api/v1/rules \| jq` | Rule đã nạp, trạng thái |
| `curl -s localhost:9090/api/v1/alerts \| jq` | Alert đang pending/firing |
| `curl -X POST localhost:9090/-/reload` | Nạp lại cấu hình Prometheus (cần cờ `--web.enable-lifecycle`) |
| `promtool check rules <file>` / `promtool test rules <file>` | Kiểm tra cú pháp / kiểm thử logic rule |
| `amtool check-config alertmanager.yml` | Kiểm tra cấu hình Alertmanager |
| `amtool config routes test --config.file=... severity=critical` | Alert này đi tới receiver nào |
| `amtool --alertmanager.url=http://localhost:9093 alert query` | Alert Alertmanager đang giữ |
| `amtool ... silence add alertname=X --duration=1h --comment="..."` | Tắt tiếng có thời hạn |

## 8. Giải thích câu lệnh và tham số

`promtool` và `amtool` có sẵn trong image chính thức — không cần cài lên WSL:

```bash
cd ~/projects/taskhub
docker run --rm -v "$PWD/monitoring/prometheus:/p:ro" --entrypoint promtool \
  prom/prometheus:v3.15.1 check rules /p/rules/alerts.yml
```

| Phần | Ý nghĩa |
|---|---|
| `--rm` | Xóa container sau khi chạy xong |
| `-v "$PWD/monitoring/prometheus:/p:ro"` | Gắn thư mục cấu hình vào `/p`, chỉ đọc |
| `--entrypoint promtool` | Image mặc định chạy `prometheus`; ta đổi sang công cụ `promtool` có trong cùng image |
| `check rules /p/rules/alerts.yml` | Kiểm tra cú pháp + PromQL |

```text
Checking /p/rules/alerts.yml
  SUCCESS: 2 rules found
```

(minh họa)

```bash
docker run --rm -v "$PWD/monitoring/alertmanager:/a:ro" --entrypoint amtool \
  prom/alertmanager:v0.34.2 config routes test --config.file=/a/alertmanager.yml \
  --tree severity=warning alertname=HostDiskUsageHigh
```

| Phần | Ý nghĩa |
|---|---|
| `config routes test` | Mô phỏng một alert có các nhãn cho sau đó, in receiver mà cây route chọn |
| `--tree` | In cả cây route để thấy alert đi qua nhánh nào |
| `severity=warning alertname=...` | Nhãn của alert giả |

```bash
curl -s localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state, activeAt}'
```

```json
{ "name": "TaskhubDown", "state": "pending", "activeAt": "2026-11-20T15:02:15Z" }
```

(minh họa) — `state` đi `pending` → `firing`. `activeAt` là lúc điều kiện bắt đầu đúng: từ đó cộng `for` là lúc firing.

```bash
docker exec taskhub-mon-alertmanager-1 amtool --alertmanager.url=http://localhost:9093 \
  silence add alertname=TaskhubDown --duration=30m --comment="bảo trì database"
```

| Phần | Ý nghĩa |
|---|---|
| `docker exec taskhub-mon-alertmanager-1` | Chạy amtool **bên trong** container Alertmanager (tên container = `<project>-<service>-1`) |
| `--alertmanager.url` | Alertmanager nào; trong container thì là chính nó |
| `alertname=TaskhubDown` | Matcher: silence những alert có nhãn này |
| `--duration=30m`, `--comment` | Thời hạn và lý do — người khác nhìn vào biết ai tắt, vì sao |

Lệnh in ra **ID** của silence; hủy sớm bằng `amtool silence expire <ID>`.

## 9. Bài thực hành từng bước

> Bài thực hành **đầy đủ** (dashboard thật, 2 alert, Telegram) là [Lab 01](labs/lab-01-dashboard-alerts.md). Phần này luyện riêng từng kỹ năng, **không cần** app chạy cho Bước B và C.

### Bước A — Grafana + datasource bằng provisioning `[WSL]` `[Browser]`

1. Tạo thư mục secret và mật khẩu admin:

   ```bash
   cd ~/projects/taskhub
   mkdir -p monitoring/secrets monitoring/grafana/provisioning/{datasources,dashboards} monitoring/grafana/dashboards
   grep -qx 'monitoring/secrets/' .gitignore || echo 'monitoring/secrets/' >> .gitignore
   openssl rand -base64 18 | tr -d '\n' > monitoring/secrets/grafana_admin_password
   chmod 600 monitoring/secrets/grafana_admin_password
   ```

2. Viết `monitoring/grafana/provisioning/datasources/datasources.yaml` theo mục 4.5 (uid `prometheus`).
3. Thêm service `grafana` vào `monitoring/compose.yaml`: image `grafana/grafana:13.3.0`, network `mon`, port `127.0.0.1:${GRAFANA_HOST_PORT:-3000}:3000`, mount `./grafana/provisioning:/etc/grafana/provisioning:ro`, `./grafana/dashboards:/var/lib/grafana/dashboards:ro`, thư mục secret, volume `grafana-data:/var/lib/grafana`, biến `GF_SECURITY_ADMIN_PASSWORD__FILE`, `mem_limit: 256m`. Tự viết trước, sau đó mới so với [bản tham khảo](labs/reference/compose.yaml).
4. Chạy và kiểm tra:

   ```bash
   docker compose -p taskhub-mon -f monitoring/compose.yaml up -d grafana
   GF_PASS="$(cat monitoring/secrets/grafana_admin_password)"
   curl -s -u admin:"$GF_PASS" "localhost:${GRAFANA_HOST_PORT:-3000}/api/datasources/uid/prometheus/health" | jq
   ```

   ❓ Đổi `url` của datasource thành `http://localhost:9090`, restart Grafana, gọi lại lệnh trên. Thông báo lỗi là gì, vì sao? Sửa lại.

5. Mở `http://localhost:3000` (đăng nhập `admin`), vào **Explore**, chạy:

   ```promql
   sum(rate(http_server_requests_seconds_count{job="taskhub"}[$__rate_interval]))
   sum(rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[$__rate_interval]))
   ```

   Tạo traffic ở terminal khác: `for i in $(seq 200); do curl -s -o /dev/null localhost:8000/api/tasks; done` (đổi `8000` nếu bạn đã đổi `NGINX_HOST_PORT`).
   ❓ Khi **không** chạy vòng lặp, câu 1 và câu 2 khác nhau thế nào? Giải thích.

### Bước B — Kiểm thử một rule bằng `promtool` (không cần stack chạy) `[WSL]`

1. Tạo `~/devops-lab/08-monitoring/promtool/alerts.yml` chứa đúng rule `TaskhubDown` của mục 4.8 (không có `runbook_url`), và `alerts_test.yml` như mục 4.12 nhưng `rule_files: [alerts.yml]`.
2. Chạy:

   ```bash
   cd ~/devops-lab/08-monitoring/promtool
   docker run --rm -v "$PWD:/t:ro" -w /t --entrypoint promtool prom/prometheus:v3.15.1 test rules alerts_test.yml
   ```

3. Phá có chủ đích, mỗi lần một thay đổi, ghi lại thông báo lỗi:
   - Đổi `for: 1m` thành `for: 3m`.
   - Xóa dòng `instance: taskhub:8080` trong `exp_labels`.
   - Thêm một test `eval_time: 2m` khẳng định **có** alert.
4. Khôi phục để test xanh.

### Bước C — Mô phỏng cây route Alertmanager `[WSL]`

1. Tạo `~/devops-lab/08-monitoring/am/alertmanager.yml` với route mục 4.9 (có nhánh `severity="warning"` → `telegram-warning`) và hai receiver dạng webhook giả (`url: http://example.invalid/a`, `.../b`) — chỉ để thử route, không gửi thật.
2. Kiểm tra cú pháp và mô phỏng:

   ```bash
   cd ~/devops-lab/08-monitoring/am
   docker run --rm -v "$PWD:/a:ro" --entrypoint amtool prom/alertmanager:v0.34.2 check-config /a/alertmanager.yml
   for sev in critical warning info; do
     echo "== severity=$sev"
     docker run --rm -v "$PWD:/a:ro" --entrypoint amtool prom/alertmanager:v0.34.2 \
       config routes test --config.file=/a/alertmanager.yml alertname=Demo severity="$sev"
   done
   ```

   ❓ `severity=info` đi đâu? Vì sao?

## 10. Kết quả mong đợi

- Bước A: lệnh health trả `"status": "OK"` (hoặc thông báo thành công tương đương). Với `localhost`, lỗi kiểu `connection refused` — vì trong container Grafana không có gì nghe ở 9090. Không có traffic, câu 1 vẫn > 0 (request scrape của Prometheus), câu 2 về 0.
- Bước B: `SUCCESS` ban đầu; đổi `for: 3m` → test ở `eval_time: 5m` **fail** (alert mới pending); thiếu nhãn → fail vì `exp_labels` phải khớp toàn bộ; test ở 2m khẳng định có alert → fail.
- Bước C: `check-config` báo `SUCCESS`; `critical` → receiver gốc, `warning` → `telegram-warning`, `info` → receiver gốc (không nhánh con nào khớp thì dùng receiver của route cha).

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Kiểm tra | Cách sửa |
|---|---|---|---|
| Datasource: `connection refused` / `no such host` | `url` dùng `localhost`, hoặc Grafana không cùng network với Prometheus | `docker inspect taskhub-mon-grafana-1 --format '{{json .NetworkSettings.Networks}}'` | `http://prometheus:9090`, cùng network `mon` |
| Panel "No data" dù Explore có dữ liệu | Panel trong JSON tham chiếu **uid datasource khác** (export bật "share with another instance", hoặc uid đổi) | Mở JSON panel, tìm `"datasource": {"uid": ...}` | uid cố định trong provisioning, export ở chế độ Classic, tắt công tắc chia sẻ |
| p95 "No data" | Chưa bật histogram → không có series `_bucket` | `curl -s localhost:9090/api/v1/label/__name__/values \| jq -r '.data[]' \| grep http_server_requests` | Bật `percentiles-histogram` cho `http.server.requests` (bài 02) |
| Sửa dashboard trên UI báo không lưu được | Dashboard provisioned, `allowUiUpdates: false` — **đúng thiết kế** | — | Export JSON → sửa file trong Git → Grafana tự nạp lại |
| Grafana không khởi động, log `permission denied` ở `/var/lib/grafana` | Bind mount thư mục host thuộc user khác (Grafana chạy bằng user không phải root) | `docker logs taskhub-mon-grafana-1` | Dùng **named volume** `grafana-data` như bản tham khảo |
| Alert mãi **pending** rồi biến mất | Sự cố ngắn hơn `for` — **đúng thiết kế** | `/api/v1/alerts` | Không cần sửa; nếu `for` quá dài so với yêu cầu thì giảm |
| Alert không bao giờ kêu khi target biến mất khỏi cấu hình | Series không còn → `== 0` không trả gì | Query `up{job="taskhub"}` | Target tĩnh vẫn sinh `up=0` khi scrape lỗi; với series tự biến mất dùng `absent()` 🟨 |
| Rule mới không có hiệu lực | Chưa reload Prometheus; hoặc không có cờ `--web.enable-lifecycle` nên `/-/reload` trả lỗi | `curl -s localhost:9090/api/v1/rules` | `curl -X POST localhost:9090/-/reload` hoặc restart container |
| Alertmanager không khởi động | Cấu hình sai cú pháp | `docker logs taskhub-mon-alertmanager-1` | `amtool check-config` trước khi restart |
| Telegram: `401 Unauthorized` | Token sai/đã thu hồi, hoặc file token có ký tự thừa | Thử `curl .../bot<token>/getMe` | Ghi lại token bằng `printf '%s'` |
| Telegram: `400 Bad Request: chat not found` | Chưa gửi `/start` cho bot, sai chat id, thiếu dấu `-` với chat nhóm | `getUpdates` | Gửi tin cho bot, lấy lại id |
| Điện thoại rung liên tục cho một sự cố | `repeat_interval` / `group_interval` quá ngắn, thiếu `group_by` | Đọc `route:` | Theo mục 4.9 |

## 12. Đọc log và xử lý lỗi

Ba nguồn log, đọc theo thứ tự đường đi của alert:

```bash
docker logs --since 10m taskhub-mon-prometheus-1   2>&1 | grep -iE 'rule|error|notif'
docker logs --since 10m taskhub-mon-alertmanager-1 2>&1 | grep -iE 'level=(warn|error)|notify'
docker logs --since 10m taskhub-mon-grafana-1      2>&1 | grep -iE 'level=error|provisioning'
```

Ví dụ (minh họa — chữ thật có thể khác theo phiên bản):

```text
ts=... level=ERROR source=... msg="Notify for alerts failed" num_alerts=1 err="telegram/telegram[0]: notify retry canceled ... 401 Unauthorized"
```

Cách đọc: `msg` cho biết **bước** hỏng (gửi thông báo), `err` cho biết **receiver** (`telegram[0]` = mục đầu tiên trong `telegram_configs`) và **mã lỗi từ phía Telegram** (401 = token). Không phải lỗi của rule hay Prometheus.

Quy trình khi "alert không đến":

1. Prometheus có thấy alert firing không? → `/api/v1/alerts`. Không → lỗi ở **rule/metric** (sai nhãn `job`, sai tên metric, chưa reload).
2. Alertmanager có nhận không? → `amtool alert query` trong container. Không → Prometheus không gửi được (`alerting:` sai địa chỉ, khác network).
3. Alertmanager có gửi không? → log `Notify` + `amtool silence query` (đang bị silence?) + inhibition.
4. Receiver có nhận không? → log `webhook-debug`, hoặc thử token Telegram bằng `getMe`.

Ghi mỗi lần gỡ lỗi vào `troubleshooting-journal.md` ([mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md)).

## 13. Câu hỏi kiểm tra kiến thức

1. Grafana có lưu metric không? Xóa volume `grafana-data` thì mất gì, không mất gì?
2. Vì sao datasource trong container Grafana không được dùng `http://localhost:9090`?
3. `uid` của datasource quan trọng thế nào với dashboard provisioned?
4. RED và USE khác nhau ở đối tượng áp dụng thế nào? Cho mỗi loại 3 panel của taskhub.
5. Vì sao panel request rate nên lọc `uri!~"/actuator.*"`?
6. `$__rate_interval` giải quyết vấn đề gì? Vì sao trong file rule lại dùng `[5m]`?
7. Giải thích ba trạng thái inactive / pending / firing. `for: 1m` ảnh hưởng thế nào?
8. `labels` và `annotations` của rule khác nhau về mục đích thế nào?
9. Với `group_wait: 30s`, `group_interval: 5m`, `repeat_interval: 4h`: app chết lúc 10:00:00 và chưa sửa, bạn nhận tin nhắn khoảng lúc nào? Một alert mới cùng nhóm xuất hiện lúc 10:02 thì sao?
10. Inhibition và silence khác nhau thế nào? Mỗi cái dùng khi nào?
11. Vì sao dùng `bot_token_file` thay vì `bot_token`?
12. Vì sao bot Telegram chưa nhắn được cho bạn nếu bạn chưa gửi `/start`?
13. Trên laptop, alert disk đo disk nào? Trên EC2 thì sao?
14. `exp_alerts: []` trong test có ý nghĩa gì? Vì sao cần test cả trường hợp "không có alert"?
15. Nêu 3 dấu hiệu của alert fatigue và cách sửa.

## 14. Bài tập tự làm

> Lời giải: [solutions/03-solutions.md](solutions/03-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Alert tỷ lệ lỗi.** Viết rule `TaskhubHighErrorRate`: tỷ lệ request 5xx > 5% trong 5 phút, `for: 5m`, `severity: critical`, annotation có giá trị phần trăm. Viết test promtool cho 3 trường hợp: không traffic (không alert), traffic có 2% lỗi (không alert), 10% lỗi (alert). Gợi ý: counter tăng đều dùng ký hiệu `0+10x20`.

**Bài 2 — Route theo severity.** Sửa `alertmanager.yml` để `warning` chỉ nhắc lại mỗi 12 giờ và đi tới receiver riêng, còn `critical` nhắc lại mỗi 1 giờ. Chứng minh bằng `amtool config routes test --tree`.

**Bài 3 — Dashboard có biến.** Thêm biến `instance` (lấy từ `label_values(up{job="taskhub"}, instance)`) và dùng nó trong mọi panel app. Export Classic JSON, commit, kiểm tra Grafana nạp lại từ file sau khi xóa volume `grafana-data` (⚠️ chỉ volume Grafana — không xóa volume Prometheus/Loki).

**Bài 4 — Kiểm thử rule trong CI.** Thêm một job vào workflow (hoặc `infra.yml` của v4) chạy `promtool check rules` và `promtool test rules` bằng image `prom/prometheus:v3.15.1` khi PR thay đổi `monitoring/prometheus/**`. Không cần quyền AWS.

**Bài 5 — Runbook.** Viết `docs/runbooks/host-disk-usage-high.md`: ý nghĩa, ảnh hưởng, lệnh kiểm tra (`df -h`, `docker system df`, `du -xh --max-depth=1 /var/lib/docker`), xử lý an toàn (cái gì xóa được, cái gì tuyệt đối không), khi nào leo thang. Gắn `runbook_url` vào rule.

**Bài 6 — Đánh giá alert.** Cho danh sách: `CPU > 80% 1m`, `up == 0 0s`, `disk > 95% 30m`, `p95 > 2s 10m`, `JVM heap > 90% 1m`. Với mỗi alert: tốt/tệ, vì sao, sửa thế nào (triệu chứng hay nguyên nhân, `for` hợp lý, severity).

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được Grafana không lưu dữ liệu và datasource dùng tên service, không dùng `localhost`.
- [ ] Tự provision được datasource + một dashboard từ file, dựng lại được sau khi xóa volume Grafana.
- [ ] Vẽ được dashboard RED + USE cho taskhub, có unit và threshold khớp alert.
- [ ] Viết được rule có `for`, `severity`, `summary`, `description`, `runbook_url` và giải thích từng trường.
- [ ] Giải thích được `group_by`, `group_wait`, `group_interval`, `repeat_interval`, inhibition, silence bằng ví dụ thời gian cụ thể.
- [ ] Viết được test promtool có cả trường hợp "có alert" và "không có alert", đọc được thông báo khi test fail.
- [ ] Gỡ lỗi "alert không đến" theo đúng 4 bước của mục 12.
- [ ] Phân biệt được alert tốt và alert gây mệt mỏi.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Prometheus — Alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/) | `for`, `keep_firing_for`, `labels`, `annotations`, `$labels`/`$value`, pending/firing | 2026-10-31 |
| [Prometheus — Unit testing for rules](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/) | Cấu trúc file test, ký hiệu `a+bxn`, `_`, `stale`, `exp_alerts` | 2026-10-31 |
| [Alertmanager — Configuration](https://prometheus.io/docs/alerting/latest/configuration/) | Route, giá trị mặc định 30s/5m/4h, `inhibit_rules`, `telegram_config`, `webhook_config` | 2026-10-31 |
| [Alertmanager — Overview](https://prometheus.io/docs/alerting/latest/alertmanager/) | Định nghĩa grouping, inhibition, silences | 2026-10-31 |
| [Alertmanager README (amtool)](https://github.com/prometheus/alertmanager/blob/main/README.md) | `amtool alert query`, `silence add`, `config routes test` | 2026-10-31 |
| [Grafana — Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) | Datasource và dashboard provider bằng file | 2026-10-31 |
| [Grafana — Configure a Grafana Docker image](https://grafana.com/docs/grafana/latest/setup-grafana/configure-docker/) | `GF_PATHS_PROVISIONING`, hậu tố `__FILE` cho secret | 2026-10-31 |
| [Grafana — Share dashboards and panels](https://grafana.com/docs/grafana/latest/dashboards/share-dashboards-panels/) | Export as code, Classic vs V2 Resource | 2026-10-31 |
| [Grafana — Prometheus template variables](https://grafana.com/docs/grafana/latest/datasources/prometheus/template-variables/) | `$__rate_interval` | 2026-10-31 |
| [Telegram — From BotFather to "Hello World"](https://core.telegram.org/bots/tutorial) | `/newbot`, giữ token như mật khẩu | 2026-10-31 |
| [Telegram Bot API](https://core.telegram.org/bots/api) | `getUpdates`, dạng URL, không chạy khi có webhook | 2026-10-31 |
| [Google SRE Book — Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) | Four golden signals, symptom vs cause, "every page should be actionable" | 2026-10-31 |
| [The RED Method (Grafana Labs blog)](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/) | Rate, Errors, Duration — Tom Wilkie | 2026-10-31 |
| [The USE Method — Brendan Gregg](https://www.brendangregg.com/usemethod.html) | Utilization, Saturation, Errors | 2026-10-31 |
| [node_exporter README](https://github.com/prometheus/node_exporter) | `--path.rootfs`, mount host, textfile collector | 2026-10-31 |
