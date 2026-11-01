# 02. Metrics với Prometheus

> ⏱️ ~5 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Monitoring, Logging, Observability](01-monitoring-logging-observability.md), [Docker 05 — Compose](../04-DOCKER/05-docker-compose.md), [App taskhub tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL Integration) · `[Browser]` giao diện Prometheus · Phiên bản khi viết: Prometheus **3.15.1**, node_exporter **1.12.1**, Spring Boot **4.1.x** + Micrometer (kiểm tra 2026-10-31)

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ luồng hoạt động](#6-sơ-đồ-luồng-hoạt-động)
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

- Giải thích kiến trúc **Prometheus**: scrape theo chu kỳ, lưu vào TSDB, exporter, service discovery, khi nào cần Pushgateway.
- Đọc một dòng metric dạng text và chỉ ra **tên metric**, **label**, **giá trị**; phân biệt 4 loại **counter, gauge, histogram, summary** và loại tương ứng trong Micrometer.
- Bật endpoint `/actuator/prometheus` cho `taskhub` (Spring Boot 4 + Micrometer) và bật histogram cho request HTTP.
- Chạy **node_exporter** để lấy metric CPU, RAM, disk của máy.
- Viết `prometheus.yml`: `global`, `scrape_configs`, `static_configs`, relabeling cơ bản.
- Viết **PromQL** trả lời câu hỏi vận hành thật: tốc độ request, tỷ lệ lỗi 5xx, latency p95, `up`, phần trăm disk và RAM.
- Nhận ra **bẫy cardinality**, hiểu **staleness**, ước lượng dung lượng lưu trữ, kiểm tra cấu hình bằng `promtool`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần |
|---|---|
| "API chậm từ sáng" — chậm bao nhiêu, từ lúc nào, endpoint nào? | Histogram latency + `histogram_quantile` theo `uri` |
| Sau deploy v0.7.0, khách báo lỗi lẻ tẻ | Tỷ lệ 5xx trước/sau deploy trên cùng một đồ thị |
| Disk EC2 đầy lúc 3 giờ sáng làm PostgreSQL dừng | Metric `node_filesystem_*` + alert **trước** khi đầy (bài 03) |
| Phỏng vấn: "Counter khác gauge thế nào? Vì sao phải `rate()`?" | Hiểu bản chất dữ liệu, không chỉ copy query |
| Grafana hiện "No data" | Biết kiểm tra theo thứ tự: target có `UP` không → tên metric đúng chưa → label đúng chưa |

Ở v3 bạn đã có CloudWatch đo CPU của EC2 mỗi 5 phút. Nhưng CloudWatch **không biết** app của bạn trả bao nhiêu lỗi 500 hay request nào chậm. Metric của **ứng dụng** phải do chính ứng dụng xuất ra — đó là việc của Micrometer + Prometheus.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Metric là gì

**Metric** (số đo) là một con số được đo lặp đi lặp lại theo thời gian. Chuỗi các cặp (thời điểm, giá trị) của cùng một thứ được gọi là **time series** (chuỗi thời gian).

Ví dụ: "số request đã xử lý của `taskhub`, đo mỗi 15 giây" là một time series. Nhưng "số request" của `GET /api/tasks` và của `POST /api/tasks` là **hai** time series khác nhau — phân biệt bằng **label** (nhãn).

### 3.2. Mô hình dữ liệu của Prometheus

Mỗi time series được định danh bởi **tên metric + tập label**:

```text
http_server_requests_seconds_count{method="GET", status="200", uri="/api/tasks"}  1532
└────────────── tên metric ───────┘└──────────────── label ─────────────────┘   └ giá trị
```

| Thành phần | Nghĩa |
|---|---|
| **Tên metric** | Đo cái gì. Quy ước: chữ thường, gạch dưới, có đơn vị cơ bản (`_seconds`, `_bytes`), counter kết thúc bằng `_total` |
| **Label** | Chiều để lọc/gộp: `method`, `status`, `uri`, `instance`, `job` |
| **Sample** | Một cặp (timestamp, giá trị float64) |

Mỗi tổ hợp label **khác nhau** = một time series **riêng** trong bộ nhớ và trên đĩa. Đây là gốc rễ của bẫy cardinality ở [mục 4.10](#410--cardinality--bẫy-tốn-ram-nhất).

### 3.3. Pull thay vì push

Prometheus **chủ động kéo** (pull/scrape) metric: cứ mỗi `scrape_interval` (ví dụ 15 giây) nó gọi HTTP `GET` tới một URL của target (ví dụ `http://taskhub:8080/actuator/prometheus`) và đọc văn bản trả về.

| Pull (Prometheus) | Push (StatsD, CloudWatch agent…) |
|---|---|
| Prometheus biết target **chết** (scrape thất bại → `up = 0`) | Không nhận được dữ liệu: target chết hay mạng lỗi? Khó phân biệt |
| Target chỉ cần mở một endpoint HTTP | Target phải biết địa chỉ server nhận |
| Cần đường mạng **từ Prometheus tới target** | Cần đường mạng từ target tới server |

### 3.4. Ôn lại: nối với kiến thức cũ

| Kiến thức cũ | Dùng ở bài này |
|---|---|
| HTTP status 2xx/4xx/5xx ([Network 06](../02-NETWORKING/06-http-https-tls.md)) | Label `status`, `outcome` và tỷ lệ lỗi 5xx |
| Actuator `/actuator/health` ([tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)) | Thêm endpoint `/actuator/prometheus` cùng cơ chế |
| Docker network, DNS theo tên service ([Docker 04](../04-DOCKER/04-volumes-networks-env.md)) | Prometheus gọi `taskhub:8080`, `node-exporter:9100` qua DNS nội bộ |
| `free -m`, `df -h` ([Linux 07](../01-LINUX/07-logs-monitoring-troubleshooting.md)) | Cùng số liệu, nhưng thu liên tục bằng node_exporter |
| CloudWatch metric, namespace, dimension ([AWS 10](../06-AWS/10-cloudwatch.md)) | Dimension ≈ label; namespace ≈ tiền tố tên metric |

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Kiến trúc Prometheus

```text
   ┌─────────────── Prometheus server ───────────────┐
   │  Service discovery ─► Scrape loop (mỗi 15s)     │
   │        │                    │                   │
   │        ▼                    ▼                   │
   │  danh sách target      TSDB (đĩa, nén)  ◄── PromQL ◄── Grafana, UI, API
   │                             │                   │
   │                     Rule evaluation ──► alert ──┼──► Alertmanager (bài 03)
   └─────────────────────────────────────────────────┘
          ▲ HTTP GET /metrics          ▲ HTTP GET /actuator/prometheus
   ┌──────┴───────┐             ┌──────┴───────┐
   │ node_exporter│             │   taskhub    │  (Micrometer)
   └──────────────┘             └──────────────┘
```

| Thành phần | Vai trò |
|---|---|
| **Scrape** | Gọi HTTP tới target theo chu kỳ, đọc định dạng text |
| **TSDB** (time series database) | Lưu sample trên đĩa, nén mạnh — tài liệu Prometheus nói trung bình chỉ **1–2 byte mỗi sample** |
| **Service discovery** | Tìm target tự động (Kubernetes, EC2, Docker, file…). Bài này dùng `static_configs` — liệt kê tay |
| **Exporter** | Chương trình phụ "dịch" số liệu của hệ thống khác sang định dạng Prometheus: node_exporter (máy), postgres_exporter (database), blackbox_exporter (thăm dò HTTP từ bên ngoài) |
| **Rule evaluation** | Định kỳ tính **recording rule** (lưu kết quả query) và **alerting rule** (bài 03) |
| 🟦 **Pushgateway** | Nơi để job **ngắn hạn** (cron backup chạy 30 giây rồi thoát) đẩy metric lên, Prometheus scrape lại từ đó. Không dùng cho service chạy liên tục |

> Với job backup của v5 dự án dùng cách nhẹ hơn Pushgateway: ghi file cho **textfile collector** của node_exporter (xem [bài 06](06-incident-response.md) và bộ tham khảo).

### 4.2. 🟥 Bốn loại metric

| Loại | Ý nghĩa | Ví dụ taskhub | Đọc đúng cách | Micrometer |
|---|---|---|---|---|
| **Counter** | Chỉ **tăng** (hoặc về 0 khi process khởi động lại) | Tổng số request, tổng số lỗi | **Không** nhìn giá trị tuyệt đối. Dùng `rate()`/`increase()` | `Counter` |
| **Gauge** | Lên xuống tùy ý | Heap đang dùng, số kết nối DB đang mở, % CPU | Đọc trực tiếp, `avg_over_time`, `max_over_time` | `Gauge` |
| **Histogram** | Đếm quan sát theo **bucket** (`le` = less or equal) + tổng + đếm | Thời gian xử lý request | `histogram_quantile()` trên `rate(..._bucket)` — **gộp được** giữa nhiều instance | `Timer`/`DistributionSummary` có bật `percentiles-histogram` |
| **Summary** | App tự tính sẵn phân vị (p95) | — | Đọc trực tiếp, nhưng **không gộp được** p95 của nhiều instance | `Timer` có `percentiles` |

Tài liệu "Histograms and summaries" của Prometheus nói thẳng: summary **không gộp được** giữa nhiều instance; chỉ nghĩ tới summary khi không cần gộp. Thứ tự khuyến nghị: native histogram 🟦 → classic histogram → summary. Bài này dùng **classic histogram** (cách Spring Boot bật mặc định qua `percentiles-histogram`).

**Vì sao counter phải dùng `rate()`?** Giá trị `http_server_requests_seconds_count = 1532` chỉ nói "từ lúc app khởi động đã xử lý 1532 request". Câu hỏi vận hành là "**bây giờ** mỗi giây bao nhiêu request?". `rate(x[5m])` tính độ dốc trung bình trong 5 phút, và **tự xử lý** việc counter về 0 khi app restart.

**Một Timer của Micrometer sinh ra những gì** (theo tài liệu Micrometer cho Prometheus):

| Series | Ý nghĩa |
|---|---|
| `http_server_requests_seconds_count` | Số lần gọi (counter) |
| `http_server_requests_seconds_sum` | Tổng thời gian (counter, giây) |
| `http_server_requests_seconds_max` | Thời gian lớn nhất trong cửa sổ gần đây (gauge) |
| `http_server_requests_seconds_bucket{le="..."}` | **Chỉ có khi bật** `percentiles-histogram` |

Tên trong code Java là `http.server.requests` (dấu chấm). Micrometer đổi sang quy ước Prometheus: chấm → gạch dưới, thêm đơn vị `_seconds`. Khi tìm trong tài liệu Spring, dùng tên có dấu chấm; khi viết PromQL, dùng tên có gạch dưới.

### 4.3. 🟥 Bật metric Prometheus cho `taskhub`

Theo tài liệu Spring Boot: chỉ cần có `micrometer-registry-{system}` trên classpath là Spring Boot tự cấu hình registry; endpoint `/actuator/prometheus` **không** được mở qua HTTP cho tới khi bạn tự expose.

**1) Thêm dependency** vào `app/pom.xml` (phiên bản do Spring Boot quản lý, không ghi `<version>`):

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
    <scope>runtime</scope>
</dependency>
```

> Micrometer hiện có hai module: `micrometer-registry-prometheus` (dùng Prometheus Java client 1.x — chọn cái này) và `micrometer-registry-prometheus-simpleclient` (client cũ, chỉ để tương thích). Tutorial cũ có thể dùng tên khác — kiểm tra trước khi chép.

**2) Sửa `app/src/main/resources/application.yml`** (phần `management`):

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  metrics:
    tags:
      application: taskhub
    distribution:
      percentiles-histogram:
        http.server.requests: true
```

| Dòng | Ý nghĩa |
|---|---|
| `include: health,info,prometheus` | Mở thêm endpoint `prometheus` (tuần 6 chỉ có `health,info`) |
| `metrics.tags.application: taskhub` | **Common tag**: gắn label `application="taskhub"` cho **mọi** metric — hữu ích khi nhiều app cùng gửi về một Prometheus |
| `percentiles-histogram` | Bật bucket histogram cho meter `http.server.requests` → có `_bucket` để tính p95 ở phía Prometheus |
| `http.server.requests: true` | Tên meter chứa dấu chấm, dùng làm **key của Map**. Theo tài liệu Spring Boot, key không có ngoặc vuông chỉ bị bỏ các ký tự **khác** chữ/số, `-` và `.` — dấu chấm được giữ nguyên, nên viết thẳng như trên là đủ (đã chạy thật với Boot 4.1.2: có series `http_server_requests_seconds_bucket`; giống `app-changes/application-monitoring.yml` trong [bộ tham khảo](labs/reference/README.md)). Ký hiệu `"[http.server.requests]"` (ngoặc vuông trong nháy kép) cũng đúng — bạn sẽ gặp nó trong nhiều tài liệu; cần thiết khi key chứa ký tự khác như `/` |

Các thuộc tính khác của nhóm `management.metrics.distribution.*` (theo bảng "Per-meter customizations" trong tài liệu Spring Boot): `percentiles` (app tự tính phân vị — kiểu summary), `slo` (bucket theo mục tiêu dịch vụ), `minimum-expected-value`/`maximum-expected-value` (giới hạn dải bucket để bớt series).

**3) Kiểm tra trên máy** (app chạy bằng `./mvnw spring-boot:run` như tuần 6):

```bash
curl -s localhost:8080/actuator/prometheus | grep -E '^(# TYPE|http_server_requests_seconds_count)' | head
```

```text
# TYPE http_server_requests_seconds counter
http_server_requests_seconds_count{application="taskhub",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/actuator/health"} 3
...
```

*(minh họa — tập label chính xác phụ thuộc phiên bản Spring/Micrometer; hãy đọc output thật của bạn và ghi lại)*

> ⚠️ **Bảo mật:** `/actuator/prometheus` để lộ tên endpoint, phiên bản JVM, số lượng request… Ở v5, Nginx **chặn** `/actuator/*` từ Internet (trừ `/actuator/health`), Prometheus scrape thẳng `taskhub:8080` trong Docker network. Xem `app-changes/` trong [bộ tham khảo](labs/reference/README.md).

### 4.4. 🟥 Metric có sẵn đáng chú ý của Spring Boot

| Metric (tên Prometheus) | Loại | Dùng để |
|---|---|---|
| `http_server_requests_seconds_*` | Timer | Traffic, lỗi, latency theo `uri`, `method`, `status`, `outcome` |
| `jvm_memory_used_bytes{area="heap"}` / `jvm_memory_max_bytes` | Gauge | Heap có sắp đầy không (liên hệ `mem_limit` và `MaxRAMPercentage` ở [AWS 04](../06-AWS/04-ec2.md)) |
| `jvm_gc_pause_seconds_*` | Timer | GC dừng app bao lâu |
| `process_cpu_usage` | Gauge (0–1) | CPU của process Java |
| `hikaricp_connections_active` / `_pending` | Gauge | Pool kết nối PostgreSQL có cạn không |
| `process_uptime_seconds` | Gauge | App vừa restart? |

Label `uri` dùng **template** (`/api/tasks/{id}`), không phải đường dẫn thật (`/api/tasks/17`) — Spring cố ý làm vậy để không nổ cardinality.

### 4.5. 🟥 node_exporter — metric của máy

**node_exporter** đọc `/proc`, `/sys` và bảng mount của Linux rồi xuất ra cổng **9100**. README chính thức nhấn mạnh: nó được thiết kế để giám sát **máy host**; chạy trong container cần cẩn thận để không vô tình đo chính cái container. Cấu hình container theo README:

```yaml
node-exporter:
  image: prom/node-exporter:v1.12.1
  command: ["--path.rootfs=/host"]
  pid: host
  volumes:
    - "/:/host:ro,rslave"
```

| Tùy chọn | Vì sao |
|---|---|
| `/:/host:ro` | Thấy filesystem của **host**, chỉ đọc |
| `--path.rootfs=/host` | Báo node_exporter đọc mọi đường dẫn với tiền tố `/host` |
| `pid: host` | Thấy process của host (một số collector cần) |
| `rslave` | Mount con của host (ví dụ ổ mới gắn) cũng hiện trong container |

> **Trên Docker Desktop**, "host" là máy ảo Linux của Docker Desktop, **không phải** Ubuntu WSL của bạn — số RAM/disk sẽ là của máy ảo đó. Trên EC2 ở v5 thì đúng là máy thật. **Docker Desktop từ chối `rslave`** (đã chạy thử: `Error response from daemon: path / is mounted on / but it is not a shared or slave mount`), nên lab trên laptop dùng `"/:/host:ro"`. Trên EC2 (Linux thật) giữ `rslave` như README chính thức.

Metric hay dùng:

| Metric | Ý nghĩa |
|---|---|
| `node_cpu_seconds_total{mode="idle"}` | Counter thời gian CPU theo mode |
| `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes` | RAM còn dùng được / tổng |
| `node_filesystem_avail_bytes`, `node_filesystem_size_bytes` | Dung lượng trống (cho user thường) / tổng, theo `mountpoint`, `fstype` |
| `node_load1` | Load average 1 phút |
| 🟨 `node_textfile_*` | Metric do script tự ghi vào file (dùng cho backup ở v5) |

### 4.6. 🟥 `prometheus.yml`

```yaml
global:
  scrape_interval: 15s       # bao lâu scrape một lần
  evaluation_interval: 15s   # bao lâu tính rule một lần
  external_labels:
    env: lab

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: taskhub
    metrics_path: /actuator/prometheus   # mặc định là /metrics
    static_configs:
      - targets: ["taskhub:8080"]

  - job_name: node
    static_configs:
      - targets: ["node-exporter:9100"]
```

| Khóa | Ý nghĩa |
|---|---|
| `job_name` | Thành label `job` trên mọi series của target |
| `targets` | `host:port`; thành label `instance` |
| `metrics_path` | Đường dẫn scrape (Spring Boot không dùng `/metrics` mặc định) |
| `external_labels` | Gắn thêm khi gửi ra ngoài (Alertmanager, remote write) |
| `rule_files` | Nơi đọc recording/alerting rule |

Prometheus tự sinh vài series cho **mỗi target**: `up` (1 = scrape thành công, 0 = thất bại), `scrape_duration_seconds`, `scrape_samples_scraped`. `up` là metric quan trọng nhất của mọi hệ thống giám sát.

### 4.7. 🟨 Relabeling cơ bản

| Khối | Chạy lúc nào | Dùng để |
|---|---|---|
| `relabel_configs` | **Trước** khi scrape, trên label của target | Chọn/bỏ target từ service discovery, đổi `instance` cho dễ đọc |
| `metric_relabel_configs` | **Sau** khi scrape, trên từng series | Bỏ metric không cần (tiết kiệm lưu trữ), bỏ label nổ cardinality |

```yaml
  - job_name: taskhub
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ["taskhub:8080"]
    relabel_configs:
      - target_label: instance        # instance="taskhub-lab" thay vì "taskhub:8080"
        replacement: taskhub-lab
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: "jvm_buffer_.*"        # bỏ nhóm metric không dùng
        action: drop
```

### 4.8. 🟥 PromQL — từ cơ bản tới câu hỏi vận hành

**Hai kiểu dữ liệu cần phân biệt:**

| Kiểu | Ví dụ | Là gì |
|---|---|---|
| **Instant vector** | `up` | Giá trị **mới nhất** của mỗi series |
| **Range vector** | `up[5m]` | **Tất cả** sample trong 5 phút của mỗi series — chỉ đưa vào hàm (`rate`, `avg_over_time`…), không vẽ trực tiếp được |

**Bộ chọn label:** `=`, `!=`, `=~` (regex), `!~`. Ví dụ `http_server_requests_seconds_count{job="taskhub", status=~"5.."}`.

**Các truy vấn taskhub cần thuộc:**

```promql
# Q1. Target nào đang chết?
up == 0

# Q2. Tốc độ request (req/s) của toàn app, bỏ request của actuator
sum(rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[5m]))

# Q3. Tốc độ request theo endpoint và method
sum by (method, uri) (rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[5m]))

# Q4. Tỷ lệ lỗi 5xx (0..1)
  sum(rate(http_server_requests_seconds_count{job="taskhub", status=~"5.."}[5m]))
/
  sum(rate(http_server_requests_seconds_count{job="taskhub"}[5m]))

# Q5. Latency p95 (giây) của toàn app
histogram_quantile(0.95,
  sum by (le) (rate(http_server_requests_seconds_bucket{job="taskhub", uri!~"/actuator.*"}[5m])))

# Q6. Latency p95 theo endpoint
histogram_quantile(0.95,
  sum by (le, uri) (rate(http_server_requests_seconds_bucket{job="taskhub", uri!~"/actuator.*"}[5m])))

# Q7. Số request 404 trong 1 giờ qua
sum(increase(http_server_requests_seconds_count{job="taskhub", status="404"}[1h]))

# Q8. Disk đã dùng bao nhiêu % (EC2: mountpoint "/"; Docker Desktop: VM không báo "/", dữ liệu nằm ở "/var/lib")
100 * (1 -
  node_filesystem_avail_bytes{mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|squashfs|9p"}
/
  node_filesystem_size_bytes{mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|squashfs|9p"})

# Q9. RAM còn dùng được bao nhiêu %
100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Q10. CPU của máy đang bận bao nhiêu %
100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))

# Q11. Heap JVM đang dùng bao nhiêu % so với tối đa
100 * sum(jvm_memory_used_bytes{job="taskhub", area="heap"})
    / sum(jvm_memory_max_bytes{job="taskhub", area="heap"})
```

**Giải thích các điểm khó:**

| Điểm | Giải thích |
|---|---|
| `rate(x[5m])` | Độ dốc trung bình **mỗi giây** trong 5 phút; tài liệu ghi rõ `rate` **chỉ dùng cho counter**. Kinh nghiệm phổ biến (không phải quy định trong tài liệu): cửa sổ nên dài gấp vài lần `scrape_interval` để luôn có ít nhất vài sample |
| `sum(...)` trước khi chia (Q4) | Chia hai **tổng**, không chia từng series rồi trung bình — trung bình của tỷ lệ là sai về toán |
| Q4 trả **rỗng** khi chưa có lỗi 5xx nào | Chưa từng có request 5xx thì **không tồn tại** series `status=~"5.."` → tử số rỗng → cả phép chia rỗng ("Empty query result"), không phải 0 (đã chạy thử). Muốn panel/alert luôn có số: `(sum(rate(...{status=~"5.."}[5m])) or vector(0)) / sum(rate(...[5m]))` |
| `mountpoint=~"/\|/var/lib"` và loại `9p` (Q8) | Trên EC2 disk gốc là `/`. Trên Docker Desktop node_exporter thấy máy ảo của Docker Desktop: **không** có series `mountpoint="/"`, dữ liệu Docker nằm ở `/var/lib` (ext4); các thư mục Windows chia sẻ vào là `9p` (đã chạy thử). Chỉ lọc `"/"` thì query — và alert disk — **im lặng** trên laptop |
| `sum by (le)` trong `histogram_quantile` | Phải **giữ** label `le`; bỏ `le` thì hàm không còn bucket để tính |
| `increase(x[1h])` | ≈ `rate(x[1h]) * 3600` — tổng số tăng trong cửa sổ; có thể ra số lẻ vì nội suy |
| `fstype!~"tmpfs|overlay|squashfs"` | Loại filesystem ảo/RAM — chúng không phải "disk đầy" thật |
| `node_filesystem_avail_bytes` vs `free_bytes` | `avail` là chỗ user thường dùng được; `free` gồm cả phần ext4 giữ riêng cho root. Alert theo `avail` — đó là thứ app thực sự còn |

> **Prometheus 3 khác tutorial 2.x ở đâu** (theo hướng dẫn migration chính thức): range selector giờ là khoảng **mở bên trái** (sample đúng ở biên trái bị loại); giá trị label `le`/`quantile` được chuẩn hóa dạng số thực (`le="1"` thành `le="1.0"`) — query hay dashboard so khớp `le="1"` sẽ không còn khớp; target trả `Content-Type` sai bị **từ chối scrape**; giao diện web mới. Đọc tutorial cũ nhớ đối chiếu.

### 4.9. 🟨 Recording rule

Query p95 ở Q5 phải đọc mọi bucket của mọi series mỗi lần dashboard tải lại. **Recording rule** tính sẵn và lưu kết quả thành series mới:

```yaml
groups:
  - name: taskhub-recording
    interval: 30s
    rules:
      - record: job:http_server_requests:rate5m
        expr: sum by (job) (rate(http_server_requests_seconds_count{uri!~"/actuator.*"}[5m]))

      - record: job:http_server_requests_errors:ratio_rate5m
        expr: |
          sum by (job) (rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
          /
          sum by (job) (rate(http_server_requests_seconds_count[5m]))
```

Quy ước đặt tên `level:metric:operations` (mức gộp : metric gốc : phép tính) giúp người đọc biết series đến từ đâu. Bài 03 dùng các rule kiểu này cho alert.

### 4.10. 🟥 Cardinality — bẫy tốn RAM nhất

**Cardinality** = số time series. Mỗi tổ hợp label mới = một series mới, chiếm RAM trong "head block" của Prometheus.

| Thiết kế | Số series |
|---|---|
| Label `method` (4 giá trị) × `status` (8) × `uri` template (6) | ≈ 192 — ổn |
| Thêm label `userId` với 50.000 user | ≈ 9,6 triệu — Prometheus hết RAM |
| Label `uri` là đường dẫn thật (`/api/tasks/1`, `/api/tasks/2`…) | Tăng **không giới hạn** theo số task |

**Quy tắc:** label chỉ chứa giá trị có tập **nhỏ và hữu hạn** (method, status, môi trường, tên service). ID người dùng, email, request ID, timestamp thuộc về **log** hoặc **trace** (bài 04, 05), không thuộc về metric.

Kiểm tra metric nào nhiều series nhất:

```promql
topk(10, count by (__name__) ({__name__=~".+"}))
```

> Trang **Status → TSDB Status** trên UI Prometheus cũng hiện top metric theo số series.

### 4.11. 🟥 Staleness — vì sao series "biến mất" sau 5 phút

Theo tài liệu PromQL: khi một instant query không tìm thấy sample mới, Prometheus **nhìn lùi tối đa 5 phút** (`--query.lookback-delta`). Khi một target biến mất khỏi kết quả scrape, series của nó được gắn **stale marker** và ngừng hiện ngay.

Hệ quả thực tế:

- Container `taskhub` chết → `up{job="taskhub"}` **vẫn còn** và bằng 0 (vì Prometheus vẫn cố scrape target đó). Đây là lý do alert "app chết" dùng `up == 0`, không dùng "không có metric".
- Nhưng `http_server_requests_seconds_count` của app chết thì **biến mất** khỏi instant query ngay (stale marker).
- **Hàm trên range vector thì khác:** `rate(x[5m])` vẫn dùng các sample *trước* stale marker, nên Q2/Q4 **vẫn ra số** trong khoảng 5 phút sau khi app chết (chạy thử: ngay khi `up{job="taskhub"}` = 0, Q2 và Q4 vẫn có giá trị). Chỉ khi cửa sổ không còn đủ 2 sample thì chúng mới thành "no data" — không bao giờ là 0.
- Hệ quả: alert dựa trên tỷ lệ lỗi **không** phát hiện được app chết (lúc đầu nó báo số cũ, sau đó im lặng) — cần cả alert `up == 0`.

### 4.12. 🟨 Lưu trữ và dung lượng

| Cờ | Ý nghĩa |
|---|---|
| `--storage.tsdb.retention.time` | Giữ dữ liệu bao lâu. Không đặt cờ nào thì mặc định **15 ngày** |
| `--storage.tsdb.retention.size` | Giới hạn dung lượng block; đặt cả hai thì cái nào chạm trước được áp dụng |

Công thức ước lượng trong tài liệu Prometheus:

```text
needed_disk_space = retention_time_seconds × ingested_samples_per_second × bytes_per_sample
```

Ví dụ taskhub: khoảng 1.500 series, scrape mỗi 15 s → 100 sample/s. Giữ 7 ngày (604.800 s), 2 byte/sample → 604.800 × 100 × 2 ≈ **121 MB**. Cộng thêm WAL (Prometheus giữ tối thiểu 3 file WAL, mỗi segment 128 MB). Con số này là cơ sở để chọn `retention.time=7d` cho EC2 ở v5.

### 4.13. 🟨 `promtool`

`promtool` đi kèm image Prometheus, kiểm tra cấu hình **trước** khi nạp:

```bash
docker run --rm --entrypoint promtool \
  -v "$PWD":/etc/prometheus:ro prom/prometheus:v3.15.1 \
  check config /etc/prometheus/prometheus.yml
```

Nó kiểm tra cú pháp YAML, khóa không tồn tại và **cả các file rule** được tham chiếu. Đưa lệnh này vào CI (giống actionlint ở [Module 05](../05-CICD/02-github-actions-basics.md)) để không bao giờ deploy cấu hình hỏng.

### 4.14. Gặp lại ở đâu

| Kiến thức | Dùng ở |
|---|---|
| PromQL tỷ lệ lỗi, p95, disk % | Dashboard và alert ([bài 03](03-grafana-dashboards-alerting.md)) |
| `up`, staleness | Alert `TaskhubDown`; break-fix "target down" ([break-fix](labs/break-fix-01/README.md)) |
| node_exporter textfile | Metric "lần backup thành công gần nhất" ([bài 06](06-incident-response.md), v5) |
| Cardinality | Label của Loki cũng phải ít giá trị ([bài 04](04-centralized-logging.md)) |
| Scrape theo Service/annotation | Prometheus trên Kubernetes (Module 09) |
| Golden Signals ([bài 01](01-monitoring-logging-observability.md)) | Traffic = Q2, Errors = Q4, Latency = Q5, Saturation = Q8–Q11 |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Latency trung bình vẫn đẹp mà khách kêu chậm"

Một team vẽ `rate(_sum[5m]) / rate(_count[5m])` — latency **trung bình** — thấy 80 ms, rất ổn. Thực tế 3% request mất 4 giây vì truy vấn thiếu index. Trung bình che mất đuôi phân phối. Chuyển sang p95 và p99 bằng `histogram_quantile` thì thấy ngay p99 = 4 s. Bài học: luôn nhìn **phân vị**, không chỉ trung bình.

### Ví dụ 2: Prometheus hết RAM sau một tính năng mới

Một dev thêm `Counter.builder("orders").tag("customerId", id)`. Sau một tuần, Prometheus bị OOMKilled liên tục. Trang TSDB Status cho thấy metric `orders_total` có 400.000 series. Sửa: bỏ tag `customerId`, ghi thông tin đó vào log có cấu trúc.

### Ví dụ 3: Alert disk không bao giờ kêu

Rule viết `node_filesystem_free_bytes / node_filesystem_size_bytes < 0.2` và không lọc gì. Hai vấn đề cộng lại:

- Kết quả có cả hàng chục filesystem `tmpfs`/`overlay` gần như trống, làm bảng alert nhiễu, ai cũng bỏ qua.
- Với đĩa root ext4, khoảng 5% dung lượng được giữ riêng cho root. `free_bytes` tính cả phần đó, nên khi app (chạy bằng user thường) đã **không ghi được nữa**, rule vẫn thấy "còn 5%" — sát ngưỡng nhưng không kêu kịp.

Sửa: dùng `avail_bytes`, lọc mountpoint của disk thật (`/` trên EC2, `/var/lib` trên Docker Desktop) và loại `fstype` ảo — đúng như Q8.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Lab của bài này

```text
WSL (trình duyệt Windows mở 127.0.0.1)
  │ curl loop → 127.0.0.1:${APP_HOST_PORT:-8088}        127.0.0.1:${PROMETHEUS_HOST_PORT:-9090} ← bạn dùng UI/PromQL
  ▼                                                        │
┌──────────────────────── Docker network prom08_default ──┼───────────────────┐
│  taskhub:8080  ◄── scrape /actuator/prometheus ─── prometheus:9090           │
│     │ JDBC                                              │                    │
│  postgres:5432        node-exporter:9100 ◄── scrape /metrics ┘               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 6.2. Một chu kỳ scrape

```text
t=0s   Prometheus: GET http://taskhub:8080/actuator/prometheus  (timeout = scrape_timeout)
        ├─ thành công → parse text → gắn job, instance → ghi vào TSDB → up=1
        └─ lỗi (refused/timeout/sai Content-Type) → up=0, ghi lý do ở trang Targets
t=15s  lặp lại
t=15s  (evaluation_interval) tính recording/alerting rule trên dữ liệu vừa ghi
```

---

## 7. Các câu lệnh cần biết

| Lệnh / thao tác | Mục đích |
|---|---|
| `curl -s localhost:8080/actuator/prometheus` | Xem metric app xuất ra (định dạng text) |
| UI `http://127.0.0.1:9090` → **Query** | Chạy PromQL, xem bảng/đồ thị |
| UI → **Status → Target health** | Target nào UP/DOWN, lỗi gì |
| `curl -s 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=up'` | Gọi PromQL qua HTTP API (dùng trong script) |
| `curl -s http://127.0.0.1:9090/api/v1/targets` | Trạng thái target dạng JSON |
| `curl -X POST http://127.0.0.1:9090/-/reload` | Nạp lại cấu hình (cần `--web.enable-lifecycle`) |
| `docker run --rm --entrypoint promtool ... check config` | Kiểm tra cấu hình |
| `docker run --rm --entrypoint promtool ... check rules rules/*.yml` | Kiểm tra file rule |

---

## 8. Giải thích câu lệnh và tham số

### Gọi PromQL qua API

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=up' | jq '.data.result[] | {job: .metric.job, value: .value[1]}'
```

```json
{ "job": "prometheus", "value": "1" }
{ "job": "taskhub", "value": "1" }
{ "job": "node", "value": "1" }
```

*(minh họa)*

| Phần | Ý nghĩa |
|---|---|
| `/api/v1/query` | Instant query tại thời điểm hiện tại (thêm `time=` để hỏi quá khứ) |
| `--data-urlencode 'query=...'` | Mã hóa URL cho PromQL (có `{`, `"`, khoảng trắng) |
| `.value[1]` | Mảng `[timestamp, "giá trị dạng chuỗi"]` |
| `jq` | Lọc JSON; Ubuntu 24.04 chưa có sẵn → `sudo apt install jq` |

Truy vấn theo khoảng thời gian (để vẽ đồ thị): `/api/v1/query_range?query=...&start=...&end=...&step=15s`.

### Cờ khởi động Prometheus trong lab

| Cờ | Ý nghĩa |
|---|---|
| `--config.file=/etc/prometheus/prometheus.yml` | Đường dẫn cấu hình |
| `--storage.tsdb.path=/prometheus` | Thư mục TSDB — gắn volume vào đây để dữ liệu sống qua lần tạo lại container |
| `--storage.tsdb.retention.time=2d` | Lab chỉ giữ 2 ngày |
| `--web.enable-lifecycle` | Cho phép `POST /-/reload` và `/-/quit`. ⚠️ Chỉ bật khi cổng 9090 **không** lộ ra ngoài (lab bind `127.0.0.1`) |

> Khai báo `command:` trong Compose **thay thế toàn bộ** cờ mặc định của image — vì vậy phải ghi lại cả `--config.file` và `--storage.tsdb.path`.

---

## 9. Bài thực hành từng bước

> Chi phí: 0 USD (chạy trên laptop). Thời gian: ~2 giờ. Thư mục: `~/devops-lab/08-monitoring/prom08/`.
> Máy bạn đã có cổng 8000 bị chiếm. Lab dùng `APP_HOST_PORT` (mặc định 8088) và `PROMETHEUS_HOST_PORT` (mặc định 9090) — đổi trong `.env` nếu trùng. Kiểm tra trước: `docker ps --format '{{.Ports}}' | grep -E '8088|9090'`.

### Bước 1 — Bật metric cho taskhub `[WSL]`

Trong repo `~/projects/taskhub`, tạo nhánh `feat/prometheus-metrics`, làm đúng [mục 4.3](#43--bật-metric-prometheus-cho-taskhub) (dependency + `application.yml`). Chạy test:

```bash
cd ~/projects/taskhub/app
./mvnw -B -ntp verify        # cần PostgreSQL dev đang chạy như tuần 6
```

Build image cục bộ để lab dùng:

```bash
cd ~/projects/taskhub
docker build -f docker/Dockerfile -t taskhub:metrics .
```

### Bước 2 — Tạo các file của lab `[WSL]`

```bash
mkdir -p ~/devops-lab/08-monitoring/prom08/rules
cd ~/devops-lab/08-monitoring/prom08
printf 'POSTGRES_PASSWORD=lab-only-%s\nAPP_HOST_PORT=8088\nPROMETHEUS_HOST_PORT=9090\n' "$(openssl rand -hex 6)" > .env
```

`compose.yaml`:

```yaml
name: prom08

services:
  postgres:
    image: postgres:17
    environment:
      POSTGRES_DB: taskhub
      POSTGRES_USER: taskhub
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U taskhub -d taskhub"]
      interval: 5s
      timeout: 3s
      retries: 10

  taskhub:
    image: ${TASKHUB_LOCAL_IMAGE:-taskhub:metrics}
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/taskhub
      SPRING_DATASOURCE_USERNAME: taskhub
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD}
      SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT: "3000"   # DB chết → lỗi sau 3s thay vì 30s
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "127.0.0.1:${APP_HOST_PORT:-8088}:8080"

  prometheus:
    image: prom/prometheus:v3.15.1
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=2d
      - --web.enable-lifecycle
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./rules:/etc/prometheus/rules:ro
      - promdata:/prometheus
    ports:
      - "127.0.0.1:${PROMETHEUS_HOST_PORT:-9090}:9090"

  node-exporter:
    image: prom/node-exporter:v1.12.1
    command: ["--path.rootfs=/host"]
    pid: host
    volumes:
      - "/:/host:ro"          # laptop: Docker Desktop từ chối ",rslave" (mục 4.5); EC2 giữ ",rslave"

volumes:
  pgdata:
  promdata:
```

`prometheus.yml`: dùng đúng nội dung ở [mục 4.6](#46--prometheusyml) (đổi `external_labels.env` thành `lab`).

`rules/recording.yml`: dùng đúng nội dung ở [mục 4.9](#49--recording-rule).

Kiểm tra trước khi chạy:

```bash
docker run --rm --entrypoint promtool -v "$PWD":/etc/prometheus:ro prom/prometheus:v3.15.1 \
  check config /etc/prometheus/prometheus.yml
docker compose config --quiet && echo "compose OK"
```

### Bước 3 — Chạy và kiểm tra target `[WSL]` `[Browser]`

```bash
docker compose up -d
docker compose ps
```

Mở `http://127.0.0.1:9090` → **Status → Target health**. Cả 3 job phải **UP**. Nếu `taskhub` DOWN, đọc cột "Error" và [mục 12](#12-đọc-log-và-xử-lý-lỗi).

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=up' | jq -r '.data.result[] | "\(.metric.job) \(.value[1])"'
```

### Bước 4 — Tạo traffic `[WSL]`

```bash
APP="http://127.0.0.1:${APP_HOST_PORT:-8088}"
for i in $(seq 1 300); do
  curl -s -o /dev/null -X POST "$APP/api/tasks" -H 'Content-Type: application/json' -d "{\"title\":\"task $i\"}"
  curl -s -o /dev/null "$APP/api/tasks"
  curl -s -o /dev/null "$APP/api/tasks/999999"                                                       # 404
  curl -s -o /dev/null -X POST "$APP/api/tasks" -H 'Content-Type: application/json' -d '{"title":""}' # 400
  sleep 0.2
done
```

Để vòng lặp chạy trong một terminal khác (khoảng 1–2 phút), làm tiếp bước 5.

### Bước 5 — Trả lời bằng PromQL `[Browser]`

Chạy từng query Q1–Q11 ở [mục 4.8](#48--promql--từ-cơ-bản-tới-câu-hỏi-vận-hành) trong tab **Query** và ghi câu trả lời vào `~/devops-lab/08-monitoring/prom08/answers.md`:

1. Tốc độ request toàn app lúc vòng lặp đang chạy là bao nhiêu req/s? Khớp với ước tính của bạn từ vòng lặp không (4 request mỗi ~0,2 s + thời gian curl)?
2. Endpoint nào có p95 cao nhất?
3. Có bao nhiêu request 404 và 400 trong 15 phút qua? Vì sao chúng **không** làm tăng Q4?
4. Chuyển tab **Graph** cho Q2: đồ thị trông thế nào khi vòng lặp dừng?
5. Chạy `http_server_requests_seconds_count` **không** có `rate()`. Vì sao đồ thị này gần như vô dụng cho vận hành?

### Bước 6 — Lỗi 5xx và `up` không đủ `[WSL]`

```bash
docker compose stop postgres
for i in $(seq 1 30); do curl -s -o /dev/null -w '%{http_code}\n' "$APP/api/tasks"; done | sort | uniq -c
```

Sau ~1 phút, chạy lại Q1 và Q4.

- `up{job="taskhub"}` bằng bao nhiêu? Vì sao?
- Q4 bằng bao nhiêu?
- Kết luận: alert nào phát hiện được sự cố "database chết", alert nào không?

```bash
docker compose start postgres
```

### Bước 7 — App chết và staleness `[WSL]`

```bash
docker compose stop taskhub
```

Đợi 30 giây rồi chạy: `up{job="taskhub"}`, Q2, Q4 và `http_server_requests_seconds_count`. Ghi lại kết quả **của từng query** — vì sao Q2 vẫn ra số trong khi query cuối đã rỗng? Đợi thêm 5 phút rồi chạy lại Q2 và Q4 — giờ ra gì? Giải thích bằng [mục 4.11](#411--staleness--vì-sao-series-biến-mất-sau-5-phút).

```bash
docker compose start taskhub
```

### Bước 8 — Cardinality và lưu trữ `[Browser]`

1. Chạy query `topk` ở [mục 4.10](#410--cardinality--bẫy-tốn-ram-nhất). Ba metric nhiều series nhất là gì?
2. `count({job="taskhub"})` — app của bạn đang sinh bao nhiêu series?
3. Mở **Status → TSDB Status**, so sánh.
4. Với số series vừa đếm và `scrape_interval: 15s`, ước lượng dung lượng cho 7 ngày theo công thức [mục 4.12](#412--lưu-trữ-và-dung-lượng).

### Bước 9 — Thay đổi cấu hình nóng `[WSL]`

Thêm khối `metric_relabel_configs` bỏ `jvm_buffer_.*` (mục 4.7) vào job `taskhub`, rồi:

```bash
docker run --rm --entrypoint promtool -v "$PWD":/etc/prometheus:ro prom/prometheus:v3.15.1 \
  check config /etc/prometheus/prometheus.yml
curl -s -X POST "http://127.0.0.1:${PROMETHEUS_HOST_PORT:-9090}/-/reload" && echo reloaded
```

Kiểm tra trên **Status → Configuration** rằng cấu hình mới đã nạp. Sau 1 phút, `count({__name__=~"jvm_buffer_.*"})` trả gì?

### Bước 10 — Dọn dẹp `[WSL]`

```bash
docker compose down -v      # ⚠️ -v xóa luôn volume pgdata và promdata của lab
docker image rm taskhub:metrics   # nếu không cần nữa
```

Giữ lại thư mục `prom08/` và `answers.md` để so với bộ tham khảo ở bài 03.

So sánh với bộ đầy đủ của dự án: [labs/reference/README.md](labs/reference/README.md) (có Grafana, Loki, Alloy, Alertmanager).

---

## 10. Kết quả mong đợi

| Bước | Kết quả |
|---|---|
| 1 | `curl localhost:8080/actuator/prometheus` có `http_server_requests_seconds_bucket` |
| 3 | 3 target UP; `up` trả 3 dòng giá trị 1 |
| 5 | Q2 > 0 khi có traffic; Q4 trả **rỗng** (chưa có series 5xx nào — xem bảng giải thích ở mục 4.8), không phải lỗi; có p95 theo `uri` dạng template `/api/tasks/{id}` |
| 6 | `up{job="taskhub"} = 1` dù mọi request trả 500 và `/actuator/health` là `DOWN`; Q4 **> 0** nhưng chỉ vài % (chạy thử: 30 request lỗi → Q4 ≈ 0,05), vì cửa sổ `[5m]` vẫn chứa hàng trăm request thành công của bước 4. Vòng 30 request mất ~90 giây: mỗi request chờ Hikari hết 3 giây. Lặp vòng lâu hơn (hoặc đổi `[5m]` thành `[1m]`) thì Q4 mới tiến dần về 1 |
| 7 | `up{job="taskhub"} = 0` sau ~1 lần scrape; ngay lúc đó Q2/Q4 **vẫn có số** (rate trên cửa sổ 5 phút dùng sample cũ); `http_server_requests_seconds_count` (instant) biến mất ngay; sau ~5 phút Q2/Q4 thành "no data" (không bao giờ là 0) |
| 8 | Có con số series cụ thể và ước lượng dung lượng hợp lý (cỡ chục–trăm MB cho 7 ngày) |
| 9 | `promtool` báo `SUCCESS`; sau reload, `jvm_buffer_*` không còn series mới |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách kiểm tra | Cách sửa |
|---|---|---|---|
| Target `taskhub` DOWN, lỗi `404 Not Found` | Chưa expose `prometheus` hoặc chưa có dependency | `curl localhost:8080/actuator/prometheus` trên máy | Làm lại mục 4.3; build lại image |
| Target DOWN, `connection refused` | Sai cổng (8088 là cổng **host**; trong network phải là `taskhub:8080`) | `docker compose exec prometheus wget -qO- http://taskhub:8080/actuator/health` | Sửa `targets` |
| Target DOWN, `no such host` | Sai tên service, hoặc Prometheus ở network khác | `docker network inspect prom08_default` | Cùng project/network; đúng tên service |
| Không có `_bucket` | Chưa bật `percentiles-histogram`, hoặc key YAML thiếu ngoặc vuông/nháy | `curl .../actuator/prometheus \| grep _bucket` | Sửa `application.yml` như mục 4.3 |
| `histogram_quantile` trả `NaN` | Không có request trong cửa sổ (chia 0/0) | Q2 có > 0 không? | Tạo traffic; dùng cửa sổ lớn hơn |
| `docker compose up` báo `path / is mounted on / but it is not a shared or slave mount` (container node-exporter ở trạng thái Created, không khởi động được) | Docker Desktop không hỗ trợ propagation `rslave` | Đọc lỗi ngay ở output của `docker compose up` (container chưa từng chạy nên không có log) | Trên laptop đổi thành `"/:/host:ro"` (bỏ `,rslave`); trên EC2 giữ nguyên |
| `permission denied` khi Prometheus đọc `prometheus.yml` | Image chạy bằng user `nobody`, file chỉ đọc được bởi bạn | `ls -l prometheus.yml` | `chmod 644 prometheus.yml` |
| `Bind for 127.0.0.1:9090 failed: port is already allocated` | Cổng đã có container khác dùng | `docker ps --format '{{.Names}} {{.Ports}}' \| grep 9090` | Đổi `PROMETHEUS_HOST_PORT` trong `.env` |
| `POST /-/reload` trả `Lifecycle API is not enabled` | Thiếu `--web.enable-lifecycle` | Xem `command:` | Thêm cờ, hoặc `docker compose restart prometheus` |
| Dashboard cũ hiện "No data" với `le="1"` | Prometheus 3 chuẩn hóa `le` thành `"1.0"` | Xem giá trị `le` thật trong UI | Sửa matcher |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Thứ tự kiểm tra khi "không có dữ liệu"

```text
1. Target có UP không?          Status → Target health (cột Error ghi lý do)
2. App có xuất metric đó không?  curl …/actuator/prometheus | grep <tên>
3. Tên metric đúng chưa?         Trong UI gõ vài chữ đầu → gợi ý tên có thật
4. Label đúng chưa?              Bỏ bớt bộ lọc {…} cho tới khi có dữ liệu, rồi thêm lại từng cái
5. Cửa sổ thời gian đủ chưa?     rate(x[1m]) với scrape 30s chỉ có 2 sample → dễ rỗng
```

### 12.2. Log của Prometheus

```bash
docker compose logs prometheus --tail 50
```

```text
time=... level=INFO source=main.go msg="Loading configuration file" filename=/etc/prometheus/prometheus.yml
time=... level=INFO source=main.go msg="Completed loading of configuration file" ...
time=... level=ERROR source=main.go msg="Error loading config (--config.file=...)" err="parsing YAML file ...: yaml: line 12: did not find expected key"
```

*(minh họa — Prometheus 3 dùng định dạng log key=value; đọc trường `msg` và `err`)*

| Dòng log | Ý nghĩa |
|---|---|
| `Error loading config` + `yaml: line N` | YAML sai ở dòng N (thường là thụt lề) — container có thể dừng ngay |
| `Error reloading config` sau `/-/reload` | Cấu hình mới hỏng, Prometheus **giữ cấu hình cũ** — không sập nhưng thay đổi không có hiệu lực |
| `Server is ready to receive web requests` | Khởi động xong |

### 12.3. Lỗi scrape cụ thể

Trên trang Target health, cột Error cho biết nguyên nhân: `context deadline exceeded` (quá `scrape_timeout` — app quá chậm hoặc mạng), `server returned HTTP status 401/403/404`, `received unsupported Content-Type` (Prometheus 3 từ chối định dạng lạ — xem `fallback_scrape_protocol` trong tài liệu migration).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Pull khác push thế nào? Ưu điểm lớn nhất của pull đối với việc phát hiện target chết là gì?
2. Phân biệt counter, gauge, histogram, summary. Mỗi loại cho một ví dụ trong `taskhub`.
3. Vì sao không vẽ thẳng giá trị của counter? `rate()` xử lý chuyện app restart thế nào?
4. Một Timer của Micrometer sinh ra những series nào? Series nào chỉ xuất hiện khi bật `percentiles-histogram`?
5. Vì sao p95 tính từ histogram gộp được giữa 3 instance còn p95 từ summary thì không?
6. Viết PromQL tỷ lệ lỗi 5xx. Vì sao phải `sum` trước khi chia?
7. Vì sao `histogram_quantile` phải giữ label `le` trong `sum by`?
8. `node_filesystem_avail_bytes` khác `node_filesystem_free_bytes` thế nào? Alert disk nên dùng cái nào?
9. Database chết, app vẫn chạy: `up{job="taskhub"}` bằng bao nhiêu? Cần metric nào để phát hiện?
10. App chết: vì sao query tỷ lệ lỗi trả "no data" thay vì 0? Điều này ảnh hưởng thế nào đến thiết kế alert?
11. Cardinality là gì? Cho một ví dụ label **không** được dùng và giải thích vì sao.
12. Vì sao label `uri` của Spring dùng template `/api/tasks/{id}`?
13. Khai báo `command:` trong Compose cho Prometheus thì phải nhớ ghi lại những cờ nào? Vì sao?
14. Vì sao chỉ bật `--web.enable-lifecycle` khi cổng 9090 không lộ ra Internet?
15. Ước lượng dung lượng TSDB cho 2.000 series, scrape 15 s, giữ 7 ngày.

---

## 14. Bài tập tự làm

**Bài 1 — p99 và latency trung bình.** Viết query latency **trung bình** từ `_sum` và `_count`, và query **p99**. Tạo một endpoint chậm giả lập (ví dụ gọi `GET /api/tasks?status=TODO` nhiều lần khi có nhiều dữ liệu, hoặc thêm `Thread.sleep` ngẫu nhiên vào một nhánh **chỉ trên nhánh thử nghiệm**). So sánh hai đường, giải thích vì sao trung bình đánh lừa.

**Bài 2 — SLO bucket.** Thay vì `percentiles-histogram`, cấu hình `management.metrics.distribution.slo` cho `http.server.requests` với các mốc 100ms, 300ms, 1s. Đếm số series `_bucket` trước/sau. Viết query "tỷ lệ request dưới 300 ms trong 5 phút".

**Bài 3 — Recording rule cho p95.** Viết recording rule `job:http_server_requests:p95_5m`. Kiểm tra bằng `promtool check rules`, nạp lại, xác minh series mới có dữ liệu.

**Bài 4 — Exporter cho PostgreSQL** 🟨. Thêm `postgres_exporter` (image chính thức của cộng đồng Prometheus — tự tìm, kiểm tra tag có thật trên Docker Hub trước khi ghim) vào lab, cấu hình kết nối bằng biến môi trường, thêm job scrape. Tìm metric cho biết số kết nối hiện tại và kích thước database.

**Bài 5 — Blackbox từ bên ngoài** 🟨. Đọc tài liệu blackbox_exporter. Giải thích vì sao probe `/actuator/health` từ **bên ngoài** bắt được lỗi mà `up{job="taskhub"}` không bắt được (gợi ý: Nginx chết, Security Group sai).

**Bài 6 — Viết lại cho EC2.** Không chạy: viết `prometheus.yml` cho EC2 v5 với `external_labels` `env: dev`, `retention.time=7d`, và giải thích vì sao trên EC2 node_exporter đo đúng máy thật còn trên laptop thì không.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Đọc một dòng `/actuator/prometheus` và chỉ ra tên metric, label, giá trị, loại metric.
- [ ] Bật được metric Prometheus cho taskhub, giải thích từng dòng `application.yml` (kể cả ngoặc vuông).
- [ ] Viết `prometheus.yml` từ trí nhớ cho 3 job: prometheus, taskhub, node.
- [ ] Viết không cần nhìn: tốc độ request, tỷ lệ 5xx, p95, disk %, RAM %.
- [ ] Giải thích vì sao `up` không phát hiện database chết, và vì sao tỷ lệ lỗi không phát hiện app chết.
- [ ] Nhận ra một label gây nổ cardinality trong code review.
- [ ] Ước lượng dung lượng TSDB và chọn `retention` có lý do.
- [ ] Kiểm tra cấu hình bằng `promtool` trước khi nạp.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Spring Boot — Metrics](https://docs.spring.io/spring-boot/reference/actuator/metrics.html) | `micrometer-registry-{system}`, endpoint `/actuator/prometheus` phải expose, `management.metrics.distribution.*`, common tags, `http.server.requests` | 2026-10-31 |
| [Spring Boot — Externalized configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html) | Ký hiệu ngoặc vuông khi bind key có dấu chấm vào Map | 2026-10-31 |
| [Micrometer — Prometheus](https://docs.micrometer.io/micrometer/reference/implementations/prometheus.html) | Tên series `_seconds_count/_sum/_max/_bucket`, module client 1.x vs simpleclient | 2026-10-31 |
| [Prometheus — Overview](https://prometheus.io/docs/introduction/overview/) | Kiến trúc, pull model, Pushgateway cho job ngắn hạn | 2026-10-31 |
| [Prometheus — Metric types](https://prometheus.io/docs/concepts/metric_types/) | Counter, gauge, histogram, summary | 2026-10-31 |
| [Prometheus — Querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/) | Instant/range vector, range mở bên trái, staleness 5 phút | 2026-10-31 |
| [Prometheus — Query functions](https://prometheus.io/docs/prometheus/latest/querying/functions/) | `rate`, `increase`, `histogram_quantile` | 2026-10-31 |
| [Prometheus — Storage](https://prometheus.io/docs/prometheus/latest/storage/) | Retention mặc định 15d, `retention.size`, công thức dung lượng, 1–2 byte/sample, WAL | 2026-10-31 |
| [Prometheus — Migration to 3.0](https://prometheus.io/docs/prometheus/latest/migration/) | Range mở trái, chuẩn hóa `le`, Content-Type nghiêm ngặt, UTF-8 | 2026-10-31 |
| [Prometheus — Recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) | Cú pháp rule, `promtool check rules` | 2026-10-31 |
| [Prometheus — Recording rule best practices](https://prometheus.io/docs/practices/rules/) | Quy ước `level:metric:operations` | 2026-10-31 |
| [Prometheus — Histograms and summaries](https://prometheus.io/docs/practices/histograms/) | Summary không gộp được; thứ tự native → classic histogram → summary | 2026-10-31 |
| [Prometheus — Naming conventions](https://prometheus.io/docs/practices/naming/) | Tên metric, đơn vị cơ bản, `_total` | 2026-10-31 |
| [node_exporter (GitHub)](https://github.com/prometheus/node_exporter) | Cổng 9100, chạy trong container: `--path.rootfs=/host`, `/:/host:ro,rslave`, `pid: host`; bản 1.12.1 | 2026-10-31 |
| [Prometheus releases (GitHub)](https://github.com/prometheus/prometheus/releases) | Phiên bản 3.15.1 | 2026-10-31 |
