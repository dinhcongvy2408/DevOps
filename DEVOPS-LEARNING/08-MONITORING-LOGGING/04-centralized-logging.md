# 04. Log tập trung — Loki + Grafana Alloy

> ⏱️ ~4 giờ (+ 2 giờ lab OpenSearch tùy chọn) · Mức độ: 🟥 Bắt buộc (phần OpenSearch 🟨) · Kiến thức cần có trước: [01. Monitoring, logging, observability](01-monitoring-logging-observability.md), [03. Grafana](03-grafana-dashboards-alerting.md), [Docker 08 — Xử lý sự cố container](../04-DOCKER/08-container-troubleshooting.md), [Linux 07 — Log và xử lý sự cố](../01-LINUX/07-logs-monitoring-troubleshooting.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL integration) · `[Container]` · `[Browser]` · Phiên bản khi viết: Loki 3.7.9, Grafana Alloy 1.21.3, Grafana 13.3.0, Spring Boot 4.1.2; lab tùy chọn: OpenSearch 3.9.0, Fluent Bit 5.1.5 (kiểm tra 2026-10-31)

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

- Giải thích vì sao `docker logs` trên từng máy **không đủ** khi hệ thống có nhiều container, nhiều máy, hoặc container đã bị xóa.
- Bật **log có cấu trúc** (JSON) cho Spring Boot 4 bằng `logging.structured.format.console`, đọc được một dòng log ECS.
- Biết nên log gì, không được log gì (secret, dữ liệu cá nhân), dùng đúng các mức `ERROR/WARN/INFO/DEBUG`.
- Giải thích kiến trúc **Loki**: nhãn (label) khác nội dung log thế nào, vì sao **cardinality** cao làm Loki chậm và tốn tiền, retention hoạt động ra sao.
- Viết truy vấn **LogQL**: chọn stream, lọc dòng, `| json`, lọc theo nhãn, và truy vấn **metric từ log** (`count_over_time`, `rate`).
- Đọc và viết một pipeline **Grafana Alloy**: `discovery.docker` → `discovery.relabel` → `loki.source.docker` → `loki.process` → `loki.write`; biết rủi ro của Docker socket.
- Biết **Promtail đã hết vòng đời** (EOL 02/03/2026) và nhận ra nó trong tutorial cũ.
- So sánh kiến trúc **ELK/OpenSearch** với Loki: index toàn văn khác index theo nhãn, đánh đổi RAM và chi phí.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống khi đi làm | Bạn cần gì từ bài này |
|---|---|
| "API trả 500 lúc 2 giờ sáng, giờ đã bình thường" — container đã restart, `docker logs` chỉ còn log mới | Log được **gửi đi** nơi khác trước khi container mất |
| 3 server chạy cùng app sau load balancer, lỗi xảy ra ở "một máy nào đó" | Một chỗ duy nhất để tìm, lọc theo `host`/`container` |
| Alert "tỉ lệ 5xx cao" kêu, cần biết **lỗi gì** | Từ dashboard metric nhảy sang log cùng khoảng thời gian (Grafana Explore) |
| Sếp hỏi "tháng này log tốn bao nhiêu?" | Hiểu chi phí phụ thuộc **dung lượng ghi vào** và **số stream/cardinality** |
| Đọc tutorial dùng Promtail hoặc ELK | Nhận ra công cụ cũ / kiến trúc khác, biết chuyển đổi |
| Phỏng vấn: "Log và metric khác nhau thế nào? Khi nào dùng cái nào?" | Trả lời bằng ví dụ thật từ `taskhub` |

Ở v3 bạn đã gửi log lên **CloudWatch Logs** bằng driver `awslogs` ([AWS bài 10](../06-AWS/10-cloudwatch.md)). Bài này dựng một hệ thống log tự vận hành, dùng chung Grafana với metric — đó là thứ `taskhub` v5 sẽ dùng.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Log là gì, đi đâu?

Một app container in log ra **stdout/stderr**. Docker (driver mặc định `json-file`) ghi mỗi dòng vào một file JSON trên host — đó là thứ `docker logs` đọc ([Docker bài 08](../04-DOCKER/08-container-troubleshooting.md)). Vấn đề:

- File nằm **trên từng máy**; container bị xóa (`docker compose down`) là file mất theo.
- Mặc định **không giới hạn dung lượng** (`max-size` mặc định là `-1`, tức không giới hạn — theo tài liệu Docker). Log nhiều có thể làm đầy ổ đĩa.
- Muốn tìm "mọi dòng ERROR của taskhub trong 6 giờ qua trên 3 máy" thì phải SSH từng máy và `grep`.

**Log tập trung** (centralized logging) = một **agent** trên mỗi máy đọc log, gắn nhãn, **gửi** về một **kho log** chung; người dùng tìm kiếm qua một giao diện (Grafana, Kibana…).

```text
 máy 1: container → stdout → [agent] ─┐
 máy 2: container → stdout → [agent] ─┼──► kho log (Loki / OpenSearch) ◄── Grafana / Dashboards
 máy 3: container → stdout → [agent] ─┘
```

### 3.2. Log có cấu trúc (structured logging)

Log dạng chữ tự do:

```text
2026-11-08T03:12:45.123Z ERROR 1 --- [nio-8080-exec-3] o.a.c.c.C.[.[.[/].[dispatcherServlet] : Servlet.service() ... threw exception
```

Máy muốn biết "mức là gì, logger nào" thì phải **đoán** bằng regex — hễ format đổi là gãy. Log **có cấu trúc** in mỗi dòng là một object JSON với các trường có tên:

```json
{"@timestamp":"2026-11-08T03:12:45.123Z","log":{"level":"ERROR","logger":"org.apache.catalina..."},"process":{"pid":1,"thread":{"name":"http-nio-8080-exec-3"}},"service":{"name":"taskhub"},"message":"Servlet.service() ... threw exception","ecs":{"version":"8.11"}}
```

Agent chỉ cần **parse JSON**, không cần regex. Spring Boot (từ 3.4, có trong Boot 4) hỗ trợ sẵn 3 định dạng JSON. Theo tài liệu Spring Boot 4.1.2:

| Giá trị của `logging.structured.format.console` | Định dạng | Trường mức log |
|---|---|---|
| `ecs` | Elastic Common Schema | lồng: `log.level` |
| `logstash` | Logstash JSON | phẳng: `level` |
| `gelf` | Graylog Extended Log Format | `level` dạng số syslog (hiểu theo chuẩn GELF) |

Dự án `taskhub` dùng **`ecs`** (xem [bản tham khảo v5](labs/reference/README.md)). Nhớ trường mức log nằm **lồng** trong `log.level` — đây là chi tiết sẽ gặp lại khi viết Alloy và LogQL.

Theo tài liệu Spring Boot, định dạng ECS còn **thêm mọi cặp key-value trong MDC** vào JSON. MDC (Mapped Diagnostic Context) là "túi" key-value gắn với luồng xử lý hiện tại; khi bật tracing ([bài 05](05-tracing-overview.md)), Micrometer Tracing đặt `traceId` và `spanId` vào MDC → mỗi dòng log có ID để nối sang trace.

### 3.3. Mức log và nên log gì

| Mức | Dùng khi | Ví dụ trong `taskhub` |
|---|---|---|
| `ERROR` | Có thứ **hỏng**, cần người xem; thường kèm stack trace | Không kết nối được PostgreSQL, exception không xử lý |
| `WARN` | Bất thường nhưng app tự xử lý được | Health check database thất bại, retry lần 2 |
| `INFO` | Sự kiện vận hành quan trọng, **ít** | App khởi động xong, Flyway migrate, task được tạo (không kèm nội dung nhạy cảm) |
| `DEBUG` | Chi tiết để gỡ lỗi; **tắt** ở production | Câu SQL, giá trị biến |

**Không bao giờ log:**

- Mật khẩu, token, API key, header `Authorization`, chuỗi kết nối có mật khẩu.
- Dữ liệu cá nhân (số CCCD, số điện thoại, email người dùng…) — vừa rủi ro bảo mật, vừa có thể vi phạm quy định bảo vệ dữ liệu cá nhân.
- Toàn bộ body request/response "cho tiện".

Log là **dữ liệu được sao chép đi khắp nơi** (agent, kho log, backup, người xem dashboard). Một secret lọt vào log = secret đã lộ cho tất cả những nơi đó.

### 3.4. Nhãn (label) khác nội dung (content) — ý tưởng cốt lõi của Loki

Loki **không** đánh index toàn bộ nội dung log. Nó chỉ index một **tập nhãn nhỏ** gắn với mỗi **stream**:

```text
stream = tập log có CÙNG một bộ nhãn
{compose_project="taskhub", compose_service="taskhub", container="taskhub-taskhub-1", level="ERROR"}
   ├── 03:12:45 {"@timestamp":...,"log":{"level":"ERROR",...},"message":"..."}
   ├── 03:12:46 ...
```

Truy vấn luôn bắt đầu bằng **chọn stream qua nhãn** (nhanh, dùng index), rồi mới **quét nội dung** các stream đó (song song, dùng sức CPU). Hệ quả:

- Ít nhãn, giá trị ổn định → ít stream → index nhỏ, rẻ.
- Nhãn có **nhiều giá trị** (cardinality cao: `user_id`, `ip`, `trace_id`, `request_path` có ID trong URL) → **mỗi giá trị một stream** → hàng triệu stream nhỏ → Loki chậm, tốn bộ nhớ.

Tài liệu Loki khuyên: tối đa khoảng **10–15 nhãn**, chỉ tạo nhãn cho giá trị **sống lâu, hữu hạn**; dữ liệu cardinality cao mà hay tìm thì dùng **structured metadata** (siêu dữ liệu có cấu trúc — gắn kèm từng dòng, không tạo stream mới) hoặc đơn giản là để trong nội dung rồi lọc bằng `| json`.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Bật log JSON cho taskhub

Hai cách, kết quả như nhau:

**Cách 1 — trong `application.yml`** (cách dự án dùng ở v5, xem `app-changes/` trong [bản tham khảo](labs/reference/README.md)):

```yaml
logging:
  structured:
    format:
      console: ecs
```

**Cách 2 — biến môi trường** (không sửa code, hợp để thử): theo quy tắc *relaxed binding* bạn đã học ở [tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md), `logging.structured.format.console` ↔ `LOGGING_STRUCTURED_FORMAT_CONSOLE`.

```yaml
# trong service taskhub của compose
    environment:
      LOGGING_STRUCTURED_FORMAT_CONSOLE: ecs
```

Sau khi bật, `docker compose logs taskhub` không còn "đẹp" cho mắt người — đó là đánh đổi có chủ đích: log giờ viết cho **máy** đọc; người đọc qua Grafana (hoặc `| jq`).

### 4.2. 🟥 Kiến trúc Loki

Loki chạy được ở chế độ **single binary** (một process làm mọi việc) — đủ cho `taskhub` — hoặc tách thành nhiều thành phần khi lớn. Các khái niệm cần biết:

| Thành phần / khái niệm | Vai trò |
|---|---|
| **Distributor** | Nhận log đẩy vào (`POST /loki/api/v1/push`), kiểm tra giới hạn |
| **Ingester** | Gom log của mỗi stream thành **chunk** trong RAM, định kỳ ghi xuống storage |
| **Chunk** | Khối log đã nén của một stream trong một khoảng thời gian |
| **Index** | Ánh xạ *bộ nhãn + thời gian* → các chunk. Loki 3 dùng định dạng `tsdb`, schema `v13` |
| **Querier** | Chạy LogQL: tra index → tải chunk → quét nội dung |
| **Compactor** | Gộp index; khi bật **retention** thì xóa dữ liệu quá hạn |
| **Storage** | `filesystem` (một máy, như lab) hoặc object storage (S3, GCS) khi chạy thật ở quy mô lớn |

**Retention** (thời gian giữ log) — theo tài liệu Loki, cần **cả ba**: `compactor.retention_enabled: true`, `compactor.delete_request_store` (nơi lưu yêu cầu xóa), và `limits_config.retention_period`; retention chỉ hoạt động khi index period là `24h`. Không cấu hình → log giữ **mãi** → ổ đĩa đầy dần. Bản tham khảo v5 giữ 7 ngày.

```yaml
# Trích đoạn minh họa — cấu hình đầy đủ nằm trong labs/reference/loki/
compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
limits_config:
  retention_period: 168h   # 7 ngày
```

### 4.3. 🟥 LogQL — ngôn ngữ truy vấn của Loki

Cấu trúc: `{chọn stream} | pipeline`. Phần `{...}` **bắt buộc**.

**a) Chọn stream** — toán tử `=`, `!=`, `=~` (regex khớp), `!~` (regex không khớp):

```logql
{compose_service="taskhub"}
{compose_project="taskhub", compose_service=~"taskhub|nginx"}
```

**b) Lọc dòng** (trên nội dung, trước khi parse — nhanh nhất):

| Toán tử | Nghĩa | Ví dụ |
|---|---|---|
| `\|=` | Dòng **chứa** chuỗi | `{compose_service="taskhub"} \|= "Connection refused"` |
| `!=` | Dòng **không chứa** | `... != "actuator/health"` |
| `\|~` | Khớp regex (RE2) | `... \|~ "status=5[0-9]{2}"` |
| `!~` | Không khớp regex | `... !~ "DEBUG\|TRACE"` |

**c) Parse JSON rồi lọc theo trường:**

```logql
{compose_service="taskhub"} | json | log_level="ERROR"
```

`| json` **làm phẳng** JSON lồng nhau bằng dấu gạch dưới: `log.level` → `log_level`, `process.thread.name` → `process_thread_name`. Đây là lỗi hay gặp số 1 với ECS: trên một stream **không có** nhãn `level`, viết `| json | level="ERROR"` thì không ra gì (vì trường vừa parse tên là `log_level`).

Bộ lọc sau `| json` áp lên **cả** nhãn của stream **lẫn** trường vừa parse. Ở lab, Alloy đã **gắn sẵn** nhãn `level` khi thu log → `| json | level="ERROR"` *trông như* chạy đúng, nhưng thực ra nó đang lọc theo **nhãn**, không phải theo JSON. Hiểu rõ một tên là nhãn hay trường giúp bạn không bị "đúng do may mắn". Khi đã có nhãn, viết gọn nhất là đưa vào selector: `{compose_service="taskhub", level="ERROR"}` — vừa nhanh (dùng index) vừa rõ ý.

**d) Truy vấn metric từ log** — biến log thành chuỗi số theo thời gian (vẽ biểu đồ, cảnh báo):

| Hàm | Trả về |
|---|---|
| `count_over_time({...}[5m])` | Số dòng trong mỗi cửa sổ 5 phút, theo từng stream |
| `rate({...}[1m])` | Số dòng **mỗi giây** (trung bình trong cửa sổ) |
| `bytes_over_time`, `bytes_rate` | Tính theo dung lượng — dùng để soi "ai log nhiều nhất" |
| `absent_over_time({...}[10m])` | Trả 1 khi **không có** log — cảnh báo "app im lặng bất thường" |

Gộp theo nhãn bằng `sum by (...)`, giống PromQL ([bài 02](02-metrics-prometheus.md)):

```logql
sum by (level) (count_over_time({compose_service="taskhub"}[5m]))
sum(rate({compose_service="taskhub", level="ERROR"}[1m]))
topk(3, sum by (compose_service) (bytes_over_time({compose_project="taskhub"}[1h])))
```

> Metric từ log **đắt hơn** metric thật: Loki phải quét nội dung mỗi lần truy vấn. Thứ bạn cần đo thường xuyên (số request, tỉ lệ lỗi HTTP) hãy lấy từ **Prometheus** (`http_server_requests_seconds_count`). Metric từ log hợp cho thứ app **không** xuất metric: "số lần xuất hiện chữ `Connection refused`".

### 4.4. 🟥 Grafana Alloy — agent thu log

**Alloy** là agent của Grafana (bản phân phối OpenTelemetry Collector của Grafana), thay thế Promtail và Grafana Agent. Cấu hình viết bằng **ngôn ngữ cấu hình Alloy** (file `.alloy`): các **component** có nhãn, nối với nhau bằng cách tham chiếu **export** của component khác.

```text
discovery.docker ──targets──► loki.source.docker ──entries──► loki.process ──► loki.write ──HTTP──► Loki
        │                              ▲
        └── (meta labels) ── discovery.relabel ──rules──┘
```

| Component | Việc làm |
|---|---|
| `discovery.docker` | Hỏi Docker API qua socket: "đang có container nào?" → danh sách target kèm nhãn `__meta_docker_*` (tên container, nhãn Docker, network…) |
| `discovery.relabel` | Viết **luật** đổi nhãn meta (bắt đầu bằng `__`, sẽ bị bỏ) thành nhãn thật: `__meta_docker_container_name="/taskhub-taskhub-1"` → `container="taskhub-taskhub-1"` |
| `loki.source.docker` | Đọc log của từng container qua Docker API, áp luật relabel, gửi tiếp |
| `loki.process` | Xử lý từng dòng: parse JSON, gắn nhãn `level`, bỏ dòng rác… (các `stage.*`) |
| `loki.write` | Đẩy về Loki (`/loki/api/v1/push`), có buffer và retry |

Nhãn meta hữu ích do `discovery.docker` cung cấp (theo tài liệu Alloy): `__meta_docker_container_name`, `__meta_docker_container_id`, `__meta_docker_container_label_<tên nhãn>` (dấu `.` trong tên nhãn Docker đổi thành `_`). Docker Compose tự gắn nhãn `com.docker.compose.project` và `com.docker.compose.service` cho container → trong Alloy chúng là `__meta_docker_container_label_com_docker_compose_project` và `..._service`.

> **Mẫu chính thức** trong tài liệu Alloy ("Monitor Docker containers"): `discovery.relabel` khai báo `targets = []` và chỉ dùng để **chứa luật**; `loki.source.docker` nhận luật qua `relabel_rules = discovery.relabel.<tên>.rules`. Lý do: `loki.source.docker` cần nhãn meta (ID container) để biết đọc log của ai — nếu relabel trước rồi mới đưa target vào, nhãn `__meta_*` đã bị bỏ.

⚠️ **Docker socket = quyền root.** Để đọc log qua Docker API, Alloy phải mount `/var/run/docker.sock`. Ai điều khiển được socket thì tạo được container `--privileged` mount `/` của host — tức là root trên máy ([Docker bài 07](../04-DOCKER/07-docker-security.md)). Giảm rủi ro:

- Mount **read-only** (`:ro`) — chặn ghi vào file socket, nhưng **không** chặn gọi API (socket là kênh giao tiếp, không phải file dữ liệu). Đừng nghĩ `:ro` là đủ.
- Giữ image Alloy cập nhật, không publish UI của Alloy ra ngoài, không cho container khác dùng chung.
- Cách thay thế 🟨: đọc thẳng file `/var/lib/docker/containers/*/*-json.log` (component `local.file_match` + `loki.source.file`) — không cần socket, nhưng mất nhãn Compose tiện lợi và phụ thuộc driver `json-file`.

### 4.5. 🟥 Promtail đã hết vòng đời

Tài liệu Loki ghi rõ: **Promtail EOL từ ngày 02/03/2026**, mọi phát triển mới diễn ra ở Grafana Alloy (riêng client `lambda-promtail` không nằm trong đợt deprecation). Bạn vẫn sẽ thấy Promtail trong rất nhiều tutorial và repo cũ (file `promtail-config.yaml`, `scrape_configs` kiểu Prometheus).

| Khi gặp | Làm gì |
|---|---|
| Tutorial dùng Promtail | Hiểu ý tưởng (nhãn, pipeline stages), viết lại bằng Alloy |
| Hệ thống có sẵn Promtail | Theo hướng dẫn migrate chính thức: `alloy convert --source-format=promtail` chuyển config; hoặc chạy tạm config cũ bằng cờ `--config.format=promtail`. Lưu ý dashboard/alert dựa trên **metric của Promtail** phải sửa |

### 4.6. 🟨 Kiến trúc ELK / OpenSearch — để so sánh

**ELK** = Elasticsearch (lưu + tìm) + Logstash (xử lý) + Kibana (giao diện). Ngày nay thường thay Logstash bằng agent nhẹ (Beats, **Fluent Bit**). **OpenSearch** là bản fork mã nguồn mở của Elasticsearch/Kibana (từ 2021), AWS có dịch vụ quản lý *Amazon OpenSearch Service*.

| Tiêu chí | Loki | Elasticsearch / OpenSearch |
|---|---|---|
| Index | Chỉ **nhãn** | **Toàn văn** (inverted index trên mọi từ) |
| Tìm "chuỗi bất kỳ trong 30 ngày" | Quét nội dung các stream được chọn — chậm nếu không thu hẹp bằng nhãn | Rất nhanh nhờ index |
| Dung lượng / RAM | Thấp; chunk nén, rẻ khi để trên object storage | Index có thể **lớn ngang hoặc hơn** dữ liệu gốc; JVM cần nhiều heap |
| Vận hành | Đơn giản (single binary cho quy mô nhỏ) | Cần quản lý shard, replica, mapping, heap |
| Phân tích phức tạp (aggregation trên trường, full-text relevance) | Hạn chế | Mạnh |
| Hợp với | Đội nhỏ, đã dùng Grafana/Prometheus, log vận hành | Tìm kiếm phức tạp, security analytics (SIEM), yêu cầu truy vấn tùy ý |

Dự án chọn Loki vì: một EC2, ngân sách thấp, đã có Grafana — ghi vào ADR-0010 ở v5. Nhưng nhiều công ty Việt Nam dùng ELK/OpenSearch, nên bạn cần **đọc hiểu** được kiến trúc này; lab tùy chọn ở mục 9 phần B cho bạn chạm tay vào.

### 4.7. 🟨 Xoay vòng log trên Docker

Dù đã gửi log về Loki, file `json-file` trên host **vẫn được ghi** (đó là chỗ `loki.source.docker` đọc qua API). Luôn giới hạn nó như ở [Docker bài 08](../04-DOCKER/08-container-troubleshooting.md):

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"   # mỗi file tối đa 10 MB
        max-file: "3"     # giữ 3 file → tối đa 30 MB/container
```

Theo tài liệu Docker, `max-file` chỉ có tác dụng khi đã đặt `max-size`, và giá trị trong `log-opts` phải là **chuỗi** (có nháy). Đặt cho mọi container trong `daemon.json` thì chỉ áp dụng cho container **tạo mới** sau khi restart Docker.

### 4.8. Gặp lại ở đâu

| Kiến thức | Dùng ở |
|---|---|
| Log JSON ECS, nhãn `level` | Bản tham khảo v5, dashboard `taskhub-overview` (panel log) |
| LogQL metric query, `absent_over_time` | [Bài 03](03-grafana-dashboards-alerting.md) — alert dựa trên log; incident drill ([bài 06](06-incident-response.md)) |
| Alloy + Docker socket | v5 trên EC2; Module 10 — Security (rà soát quyền) |
| `traceId` trong log | [Bài 05](05-tracing-overview.md) — nối log với trace |
| So sánh Loki vs ELK | ADR-0010 ([milestone v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md)), phỏng vấn |
| Log trong Kubernetes | Module 09 — Kubernetes: `kubectl logs`, Alloy chạy dạng DaemonSet |

---

## 5. Ví dụ thực tế

**Ví dụ 1 — "500 lúc 2 giờ sáng".** Sáng ra, đồng nghiệp báo người dùng gặp lỗi 500 trong đêm. `docker logs` chỉ còn log từ lúc container restart 4 giờ sáng. Với Loki: Grafana Explore, chọn 01:30–02:30, truy vấn `{compose_service="taskhub", level="ERROR"}` → thấy `HikariPool-1 - Connection is not available, request timed out` lặp lại → nhảy sang dashboard metric cùng giờ: PostgreSQL hết kết nối vì một job batch giữ kết nối quá lâu. Không có log tập trung, câu chuyện dừng ở "không biết".

**Ví dụ 2 — Nhãn `user_id` làm sập Loki.** Một bạn thêm nhãn `user_id` trong Alloy "cho dễ lọc". Ứng dụng có 200.000 người dùng → 200.000 stream mỗi service → ingester hết RAM, truy vấn timeout. Sửa: bỏ nhãn, để `user_id` trong nội dung JSON và lọc bằng `| json | user_id="123"` (hoặc đưa vào structured metadata).

**Ví dụ 3 — Mật khẩu trong log.** Log `DEBUG` in toàn bộ cấu hình datasource khi khởi động, có cả mật khẩu. Log đã chảy vào Loki, được giữ 30 ngày và nằm trong backup. Xử lý đúng: **đổi mật khẩu ngay** (coi như đã lộ), sửa mức log, rồi mới tính chuyện xóa dữ liệu log (Loki hỗ trợ delete request khi đã cấu hình `delete_request_store`). Bài học: tắt `DEBUG` ở production và review những gì app in ra.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Luồng log trong lab (laptop)

```text
┌──────────── project "taskhub" (network taskhub_default) ────────────┐
│ nginx ─► taskhub (log JSON ECS ra stdout) ─► postgres               │
└───────────────┬─────────────────────────────────────────────────────┘
                │ stdout/stderr ─► Docker daemon (json-file trên host)
                │
   /var/run/docker.sock (ro) ── Docker API: liệt kê container + đọc log
                │
┌──────────── project "log08" ────────────────────────────────────────┐
│ alloy                                                                │
│  discovery.docker (lọc label com.docker.compose.project=taskhub)     │
│  discovery.relabel (rules: container, compose_service, ...)          │
│  loki.source.docker ─► loki.process (match taskhub: json → level)    │
│                         └─► loki.write ──HTTP push──► loki:3100      │
│ loki (single binary, filesystem) ◄──LogQL── grafana (Explore)        │
└──────────────────────────────────────────────────────────────────────┘
   127.0.0.1:3101 → Loki API (curl)   127.0.0.1:3001 → Grafana   127.0.0.1:12346 → Alloy UI
```

### 6.2. Một truy vấn LogQL đi qua Loki thế nào

```text
{compose_service="taskhub", level="ERROR"} |= "Connection" 
   │
   ├─1─► index (tsdb): bộ nhãn này + khoảng thời gian → danh sách chunk   (nhanh, nhỏ)
   ├─2─► tải các chunk đó từ storage
   └─3─► giải nén + quét từng dòng tìm "Connection"                      (tốn CPU, song song)
Nhãn càng chọn lọc ở bước 1 → bước 3 càng ít việc.
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `curl -s http://127.0.0.1:3101/ready` | Loki đã sẵn sàng chưa | 🟥 |
| `curl -s http://127.0.0.1:3101/loki/api/v1/labels` | Liệt kê tên nhãn Loki đang có | 🟥 |
| `curl -s http://127.0.0.1:3101/loki/api/v1/label/<tên>/values` | Liệt kê giá trị của một nhãn | 🟥 |
| `curl -G .../loki/api/v1/query_range --data-urlencode 'query=...'` | Chạy LogQL trên một khoảng thời gian | 🟥 |
| `curl -G .../loki/api/v1/query --data-urlencode 'query=...'` | Truy vấn metric tức thời (một thời điểm) | 🟨 |
| `docker compose -p log08 logs alloy` | Log của chính agent — chỗ đầu tiên xem khi không có log | 🟥 |
| `docker run --rm -v ...:/c grafana/alloy:v1.21.3 fmt /c/config.alloy` | Kiểm tra cú pháp file `.alloy` | 🟨 |
| `jq -r '.data.result[].values[][1]'` | Rút nội dung log từ JSON trả về của Loki | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

### `curl -G … /loki/api/v1/query_range`

```bash
curl -sG http://127.0.0.1:3101/loki/api/v1/query_range \
  --data-urlencode 'query={compose_service="taskhub", level="ERROR"}' \
  --data-urlencode 'since=15m' \
  --data-urlencode 'limit=5' | jq -r '.data.result[].values[][1]'
```

| Tham số | Ý nghĩa |
|---|---|
| `-G` | Gửi các `--data-urlencode` thành **query string** của request GET (không có `-G`, curl gửi POST body) |
| `--data-urlencode 'query=...'` | Mã hóa `{`, `"`, dấu cách cho URL — gõ tay vào URL rất dễ sai |
| `since=15m` | Tìm trong 15 phút gần nhất (thay cho `start`/`end` dạng timestamp) |
| `limit=5` | Tối đa 5 dòng — luôn giới hạn khi thử để không kéo về hàng nghìn dòng |
| `jq -r '.data.result[].values[][1]'` | Kết quả có dạng `result[] → {stream:{nhãn}, values:[[timestamp_ns, "dòng log"], ...]}`; lấy phần tử thứ 2 của mỗi cặp = nội dung |

Đầu ra mẫu (**minh họa** — nội dung trên máy bạn sẽ khác):

```text
{"@timestamp":"2026-11-08T03:12:45.123Z","log":{"level":"ERROR","logger":"org.apache.catalina.core.ContainerBase.[Tomcat].[localhost].[/].[dispatcherServlet]"},...,"message":"Servlet.service() for servlet [dispatcherServlet] in context with path [] threw exception ..."}
```

### Khối Alloy `loki.process` với `stage.match`

```alloy
loki.process "taskhub" {
  forward_to = [loki.write.local.receiver]

  stage.match {
    selector = "{compose_service=\"taskhub\"}"

    stage.json {
      expressions = { level = "log.level" }
    }

    stage.labels {
      values = { level = "" }
    }
  }
}
```

| Phần | Ý nghĩa |
|---|---|
| `forward_to` | Danh sách nơi nhận kết quả — ở đây là `receiver` (export) của `loki.write "local"` |
| `stage.match { selector = ... }` | Chỉ áp các stage bên trong cho stream khớp selector (cú pháp như LogQL). Log của nginx, postgres **không phải JSON** nên không parse |
| `stage.json { expressions = { level = "log.level" } }` | Biểu thức **JMESPath**: `log.level` = trường `level` nằm trong object `log`. Kết quả lưu vào **giá trị trích xuất** tên `level` (chưa phải nhãn) |
| `stage.labels { values = { level = "" } }` | Biến giá trị trích xuất `level` thành **nhãn** `level`. Chuỗi rỗng = lấy theo đúng tên khóa |

Vì sao chỉ đưa `level` lên nhãn mà không đưa `logger`, `thread`? `level` có **4–5 giá trị** cố định (cardinality thấp) và là thứ bạn lọc nhiều nhất. `logger` có hàng trăm giá trị, `thread` đổi liên tục → để trong nội dung.

---

## 9. Bài thực hành từng bước

**Mục tiêu:** dựng Loki + Alloy + Grafana cạnh stack `taskhub` trên laptop, tìm log `ERROR` khi database chết, tạo một metric từ log.

**Chi phí:** 0 USD. RAM thêm khoảng vài trăm MB. Thời gian ~90 phút.

**Chuẩn bị:** stack `taskhub` của bạn chạy được trên laptop (v0 — [Docker lab](../04-DOCKER/labs/lab-springboot-postgres-compose/README.md)), project tên `taskhub` → network `taskhub_default`. Kiểm tra:

```bash
# [WSL]
docker network ls --filter name=taskhub_default
docker compose -p taskhub ps
```

> Máy bạn có cổng 8000 đã bị chiếm? Chạy stack taskhub với `NGINX_HOST_PORT=8080` và thay `8000` thành `8080` trong các lệnh bên dưới. Lab này dùng cổng **3001 / 3101 / 12346** (đều bind `127.0.0.1`) để không đụng bộ giám sát chính của dự án (3000…); bị chiếm thì đổi qua biến `LOG08_*_PORT`.

### Phần A — bắt buộc

**Bước 1 — Bật log JSON cho taskhub `[WSL]`**

Nếu `application.yml` của bạn chưa có `logging.structured.format.console: ecs`, tạo file ghi đè tạm (không sửa repo):

```bash
mkdir -p ~/devops-lab/08-monitoring/log08
cat > ~/devops-lab/08-monitoring/log08/taskhub-ecs.yaml <<'EOF'
services:
  taskhub:
    environment:
      LOGGING_STRUCTURED_FORMAT_CONSOLE: ecs
EOF
```

Áp dụng: trong thư mục repo `taskhub`, liệt kê **tất cả** file compose bạn đang dùng **cộng thêm** file trên. (Khi đã dùng `-f`, Compose **không** tự nạp `compose.override.yaml` nữa — phải ghi rõ.)

```bash
cd ~/projects/taskhub
docker compose -p taskhub -f compose.yaml -f compose.override.yaml \
  -f ~/devops-lab/08-monitoring/log08/taskhub-ecs.yaml up -d
docker compose -p taskhub logs --tail 3 taskhub
```

❓ Dòng log giờ trông thế nào? Tìm trường mức log — nó nằm ở đâu trong JSON?

**Bước 2 — Cấu hình Loki `[WSL]`**

Dùng file cấu hình mẫu **local** do chính dự án Loki cung cấp, đúng phiên bản image:

```bash
cd ~/devops-lab/08-monitoring/log08
curl -fsSL -o loki-config.yaml \
  https://raw.githubusercontent.com/grafana/loki/v3.7.9/cmd/loki/loki-local-config.yaml
grep -n "store: tsdb\|schema: v13\|period: 24h\|path_prefix" loki-config.yaml
```

❓ File lưu dữ liệu ở đâu (`path_prefix`)? Có cấu hình retention chưa? (Đối chiếu mục 4.2 — với lab, dữ liệu mất khi xóa container là chấp nhận được.)

**Bước 3 — Cấu hình Alloy `[WSL]`**

```bash
cat > config.alloy <<'EOF'
// 1. Hỏi Docker: container nào thuộc project "taskhub"?
discovery.docker "taskhub" {
  host = "unix:///var/run/docker.sock"

  filter {
    name   = "label"
    values = ["com.docker.compose.project=taskhub"]
  }
}

// 2. Luật đổi nhãn meta → nhãn thật (chỉ chứa luật, targets rỗng — theo mẫu chính thức)
discovery.relabel "taskhub" {
  targets = []

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }

  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_service"]
    target_label  = "compose_service"
  }

  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_project"]
    target_label  = "compose_project"
  }
}

// 3. Đọc log của các container đó qua Docker API
loki.source.docker "taskhub" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.docker.taskhub.targets
  relabel_rules = discovery.relabel.taskhub.rules
  forward_to    = [loki.process.taskhub.receiver]
}

// 4. Với log của service taskhub (JSON ECS): rút log.level thành nhãn "level"
loki.process "taskhub" {
  forward_to = [loki.write.local.receiver]

  stage.match {
    selector = "{compose_service=\"taskhub\"}"

    stage.json {
      expressions = { level = "log.level" }
    }

    stage.labels {
      values = { level = "" }
    }
  }
}

// 5. Đẩy về Loki
loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
EOF
```

Kiểm tra cú pháp trước khi chạy:

```bash
docker run --rm -v "$PWD":/c grafana/alloy:v1.21.3 fmt /c/config.alloy > /dev/null && echo "cú pháp OK"
```

❓ Vì sao `discovery.relabel` có `targets = []`? (mục 4.4)

**Bước 4 — Grafana datasource `[WSL]`**

```bash
mkdir -p grafana/provisioning/datasources
cat > grafana/provisioning/datasources/loki.yaml <<'EOF'
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true
EOF
```

**Bước 5 — Compose của project `log08` `[WSL]`**

```bash
cat > compose.yaml <<'EOF'
name: log08

services:
  loki:
    image: grafana/loki:3.7.9
    command: ["-config.file=/etc/loki/config.yaml"]
    volumes:
      - ./loki-config.yaml:/etc/loki/config.yaml:ro
    ports:
      - "127.0.0.1:${LOG08_LOKI_PORT:-3101}:3100"
    mem_limit: 512m

  alloy:
    image: grafana/alloy:v1.21.3
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
      - /etc/alloy/config.alloy
    volumes:
      - ./config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro   # ⚠️ quyền tương đương root — mục 4.4
    ports:
      - "127.0.0.1:${LOG08_ALLOY_PORT:-12346}:12345"
    depends_on:
      - loki
    mem_limit: 256m

  grafana:
    image: grafana/grafana:13.3.0
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${LOG08_GRAFANA_PASSWORD:?đặt LOG08_GRAFANA_PASSWORD}
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "127.0.0.1:${LOG08_GRAFANA_PORT:-3001}:3000"
    depends_on:
      - loki
    mem_limit: 384m        # Grafana 13 rảnh đã ~230 MiB (đo thật) — 256m quá sát
EOF

read -rsp "Mật khẩu admin Grafana cho lab: " LOG08_GRAFANA_PASSWORD; echo
export LOG08_GRAFANA_PASSWORD
docker compose up -d
docker compose ps
```

> Alloy **không** cần chung network với `taskhub`: nó đọc log qua Docker **API** (socket), không gọi container qua mạng. Nó chỉ cần nói chuyện với `loki` — cùng network mặc định của project `log08`.

**Bước 6 — Kiểm tra từng tầng `[WSL]`**

```bash
curl -s http://127.0.0.1:3101/ready; echo                     # tầng kho
curl -s http://127.0.0.1:3101/loki/api/v1/labels | jq         # Loki đã thấy nhãn nào?
curl -s http://127.0.0.1:3101/loki/api/v1/label/compose_service/values | jq
```

Mở `http://127.0.0.1:12346` (Alloy UI) → xem graph các component, component nào **không** "Healthy"? Bấm `loki.source.docker.taskhub` → mục debug liệt kê các container đang đọc.

**Bước 7 — Tạo traffic, đọc log `[WSL]`**

```bash
for i in $(seq 1 5); do
  curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8000/api/tasks \
    -H 'Content-Type: application/json' -d "{\"title\":\"log lab $i\"}"
done

curl -sG http://127.0.0.1:3101/loki/api/v1/query_range \
  --data-urlencode 'query={compose_service="taskhub"}' \
  --data-urlencode 'since=10m' --data-urlencode 'limit=3' | jq -r '.data.result[].values[][1]'
```

**Bước 8 — Sự cố: database chết `[WSL]`**

```bash
docker compose -p taskhub stop postgres
for i in $(seq 1 5); do curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/api/tasks; done
```

(Mỗi request mất ~30 giây rồi trả **504** — HikariCP chờ kết nối 30 giây, và Nginx cũng hết `proxy_read_timeout` 30 giây nên trả 504 trước khi app kịp trả 500, như bạn đã thấy ở [Docker lab](../04-DOCKER/labs/lab-springboot-postgres-compose/README.md). Log `ERROR` vẫn được app ghi khi nó tự hết chờ.)

Tìm log lỗi bằng **ba cách** và so sánh:

```bash
# (a) nhãn level do Alloy gắn
curl -sG http://127.0.0.1:3101/loki/api/v1/query_range \
  --data-urlencode 'query={compose_service="taskhub", level=~"ERROR|WARN"}' \
  --data-urlencode 'since=10m' --data-urlencode 'limit=5' | jq -r '.data.result[].values[][1]' | cut -c1-200

# (b) parse JSON lúc truy vấn (không cần nhãn)
curl -sG http://127.0.0.1:3101/loki/api/v1/query_range \
  --data-urlencode 'query={compose_service="taskhub"} | json | log_level="ERROR"' \
  --data-urlencode 'since=10m' --data-urlencode 'limit=5' | jq -r '.data.result[].values[][1]' | cut -c1-200

# (c) lọc dòng theo chuỗi
curl -sG http://127.0.0.1:3101/loki/api/v1/query_range \
  --data-urlencode 'query={compose_service="taskhub"} |= "Connection"' \
  --data-urlencode 'since=10m' --data-urlencode 'limit=5' | jq -r '.data.result[].values[][1]' | cut -c1-200
```

❓ Chạy `{compose_service="taskhub"} | json` (không lọc) trong Grafana Explore, mở một dòng → xem danh sách trường: mức log tên là gì? Rồi thử `{compose_service="taskhub"} | json | level="ERROR"` — vẫn ra kết quả. Vì sao, khi JSON không có trường `level` ở cấp ngoài cùng? Nếu Alloy **không** gắn nhãn `level`, câu này sẽ ra gì? Ghi vào nhật ký debug.

Bật lại database: `docker compose -p taskhub start postgres`.

**Bước 9 — Metric từ log `[WSL]` `[Browser]`**

```bash
curl -sG http://127.0.0.1:3101/loki/api/v1/query \
  --data-urlencode 'query=sum by (level) (count_over_time({compose_service="taskhub"}[15m]))' | jq '.data.result'
```

Mở Grafana `http://127.0.0.1:3001` (user `admin`, mật khẩu bạn vừa đặt) → **Explore** → datasource **Loki** → chuyển sang chế độ **Code** → nhập:

```logql
sum by (level) (count_over_time({compose_service="taskhub"}[1m]))
```

Chọn khoảng **Last 30 minutes** → bạn thấy một đỉnh `ERROR`/`WARN` đúng lúc database chết.

**Bước 10 — Thí nghiệm cardinality (chỉ quan sát, không làm thật ở production) `[WSL]`**

```bash
curl -s http://127.0.0.1:3101/loki/api/v1/label/container/values | jq
curl -sG http://127.0.0.1:3101/loki/api/v1/series \
  --data-urlencode 'match[]={compose_project="taskhub"}' | jq '.data | length'
```

❓ Có bao nhiêu stream? Nếu thêm nhãn `thread` (mỗi request một thread khác nhau trong pool), con số này thay đổi thế nào? Viết dự đoán, **không** cần làm.

**Bước 11 — Dọn dẹp `[WSL]`**

```bash
cd ~/devops-lab/08-monitoring/log08
docker compose down -v          # ⚠️ xóa dữ liệu Loki/Grafana của lab (chỉ project log08)
cd ~/projects/taskhub
docker compose -p taskhub -f compose.yaml -f compose.override.yaml up -d   # trả taskhub về cấu hình cũ (nếu bước 1 dùng file tạm)
```

### Phần B — 🟨 Tùy chọn: OpenSearch + Fluent Bit (laptop)

> ⚠️ **RAM:** OpenSearch là JVM, cần ít nhất ~1 GB heap; cả bộ (OpenSearch + Dashboards + Fluent Bit) có thể chiếm **2–3 GB**. Máy bạn đang chạy nhiều container khác — kiểm tra `docker stats --no-stream` trước. Phần này **chưa được chạy thử** khi viết; tham số đã đối chiếu tài liệu chính thức nhưng có thể cần điều chỉnh.

Theo tài liệu OpenSearch:

- **OpenSearch 2.12 trở lên bắt buộc** đặt mật khẩu admin tùy chỉnh khi khởi động (`OPENSEARCH_INITIAL_ADMIN_PASSWORD`), mật khẩu phải đủ dài, nhiều loại ký tự và qua kiểm tra độ mạnh.
- Host cần `vm.max_map_count=262144`. Với Docker Desktop trên Windows: `wsl -d docker-desktop sysctl -w vm.max_map_count=262144` `[PowerShell]` (giá trị mất khi Docker Desktop khởi động lại).

```bash
# [WSL]
mkdir -p ~/devops-lab/08-monitoring/os08 && cd ~/devops-lab/08-monitoring/os08

cat > fluent-bit.yaml <<'EOF'
pipeline:
  inputs:
    - name: forward
      listen: 0.0.0.0
      port: 24224
  outputs:
    - name: opensearch
      match: '*'
      host: opensearch
      port: 9200
      http_user: admin
      http_passwd: ${OPENSEARCH_INITIAL_ADMIN_PASSWORD}
      logstash_format: on
      logstash_prefix: os08
      suppress_type_name: on
      tls: on
      tls.verify: off
EOF

cat > compose.yaml <<'EOF'
name: os08
services:
  opensearch:
    image: opensearchproject/opensearch:3.9.0
    environment:
      discovery.type: single-node
      OPENSEARCH_JAVA_OPTS: "-Xms1g -Xmx1g"
      OPENSEARCH_INITIAL_ADMIN_PASSWORD: ${OPENSEARCH_INITIAL_ADMIN_PASSWORD:?đặt mật khẩu mạnh}
    mem_limit: 2g
  dashboards:
    image: opensearchproject/opensearch-dashboards:3.9.0
    environment:
      OPENSEARCH_HOSTS: '["https://opensearch:9200"]'
    ports:
      - "127.0.0.1:${OS08_DASHBOARDS_PORT:-5601}:5601"
    depends_on: [opensearch]
  fluent-bit:
    image: fluent/fluent-bit:5.1.5
    command: ["-c", "/fluent-bit/etc/fluent-bit.yaml"]
    environment:
      OPENSEARCH_INITIAL_ADMIN_PASSWORD: ${OPENSEARCH_INITIAL_ADMIN_PASSWORD}
    volumes:
      - ./fluent-bit.yaml:/fluent-bit/etc/fluent-bit.yaml:ro
    ports:
      - "127.0.0.1:24224:24224"
    depends_on: [opensearch]
EOF

read -rsp "Mật khẩu admin OpenSearch (mạnh): " OPENSEARCH_INITIAL_ADMIN_PASSWORD; echo
export OPENSEARCH_INITIAL_ADMIN_PASSWORD
docker compose up -d

# Một container sinh log, gửi thẳng tới Fluent Bit bằng log driver fluentd
docker run -d --name os08-gen --log-driver fluentd \
  --log-opt fluentd-address=127.0.0.1:24224 --log-opt tag=os08.gen \
  alpine:3.20 sh -c 'i=0; while true; do i=$((i+1)); echo "{\"level\":\"INFO\",\"msg\":\"hello $i\"}"; sleep 2; done'
```

Mở `http://127.0.0.1:5601`, đăng nhập `admin` → **Dashboards Management** → tạo index pattern `os08-*` → **Discover** → tìm `hello`. So sánh với Loki: bạn tìm **bất kỳ từ nào** mà không cần nhãn.

Dọn dẹp: `docker rm -f os08-gen && docker compose down -v` (⚠️ xóa toàn bộ dữ liệu của lab `os08`).

---

## 10. Kết quả mong đợi

| Bước | Kết quả |
|---|---|
| 1 | `docker compose logs taskhub` in JSON; mức log nằm ở `log.level` (lồng trong `log`) |
| 3 | `alloy fmt` không báo lỗi |
| 6 | `/ready` trả `ready`; danh sách nhãn có `compose_service`, `compose_project`, `container`, `level` **và `service_name`** — nhãn này Loki 3.x **tự thêm** (`discover_service_name` trong `limits_config`, lấy từ một nhãn sẵn có, không phải do Alloy); giá trị `compose_service` gồm `taskhub`, `nginx`, `postgres` |
| 6 | Alloy UI: mọi component Healthy; `loki.source.docker.taskhub` liệt kê 3 container |
| 7 | Có dòng JSON của taskhub, ví dụ log khởi động hoặc log request |
| 8 | (a), (b), (c) đều trả về các dòng `ERROR`/`WARN` liên quan kết nối database; trường parse được tên `log_level`; `| json | level="ERROR"` vẫn ra kết quả vì lọc theo **nhãn** `level` do Alloy gắn (không có nhãn đó thì rỗng) |
| 9 | Có các series `level="INFO"`, `level="ERROR"`/`WARN` (tùy app in gì); biểu đồ có đỉnh lúc database tắt |
| 10 | Số stream nhỏ (cỡ vài đến hơn chục — mỗi tổ hợp container × level một stream) |
| 11 | `docker compose -p log08 ps` rỗng; taskhub chạy lại bình thường |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Kiểm tra | Cách sửa |
|---|---|---|---|
| `/loki/api/v1/labels` trả rỗng | Alloy chưa gửi gì | `docker compose -p log08 logs alloy` | Đọc lỗi của Alloy (thường là socket hoặc URL Loki) |
| Alloy log `permission denied` / `Cannot connect to the Docker daemon` | Không mount socket, hoặc Docker trong WSL chưa bật integration | `docker inspect log08-alloy-1 --format '{{json .Mounts}}'` | Mount `/var/run/docker.sock`; bật WSL integration ([Docker bài 01](../04-DOCKER/01-vm-vs-container-architecture.md)) |
| Có nhãn `container` nhưng **không** có `compose_service` | Tên nhãn meta sai (`.` chưa đổi thành `_`) | Alloy UI → `discovery.docker` → debug info | Dùng `__meta_docker_container_label_com_docker_compose_service` |
| Không có log nào dù component Healthy | `filter` lọc sai project (project của bạn không tên `taskhub`) | `docker inspect <container> --format '{{index .Config.Labels "com.docker.compose.project"}}'` | Sửa giá trị trong `filter` |
| Nhãn `level` không xuất hiện | Log chưa phải JSON (chưa bật ECS), hoặc selector của `stage.match` không khớp | Bước 1; `docker compose -p taskhub logs --tail 1 taskhub` | Bật ECS; kiểm tra tên service trong selector |
| LogQL lỗi `parse error ... queries require at least one regexp or equality matcher that does not have an empty-compatible value` | Selector chỉ có matcher có thể khớp rỗng, ví dụ `{level=~".*"}` | Đọc thông báo | Thêm một matcher cụ thể, ví dụ `compose_service="taskhub"` |
| `\| json \| level="ERROR"` rỗng (trên stream không có nhãn `level`) | ECS lồng → trường là `log_level` | Chạy `\| json` không lọc, xem tên trường | Dùng `log_level`, hoặc gắn nhãn `level` ở Alloy |
| Grafana "Data source connected, but no labels found" | Chưa có log trong khoảng thời gian | Đổi time range | Tạo traffic (bước 7) |
| Port 3001/3101/12346 đã bị chiếm | Máy có container khác | `docker ps --format '{{.Ports}}' \| grep 3001` | `LOG08_GRAFANA_PORT=3002 docker compose up -d` |
| (Phần B) OpenSearch thoát ngay, log `max virtual memory areas vm.max_map_count [65530] is too low` | Chưa đặt `vm.max_map_count` | `wsl -d docker-desktop cat /proc/sys/vm/max_map_count` | Lệnh ở phần B |
| (Phần B) OpenSearch báo thiếu/yếu admin password | 2.12+ bắt buộc mật khẩu mạnh | `docker compose -p os08 logs opensearch \| tail` | Đặt `OPENSEARCH_INITIAL_ADMIN_PASSWORD` mạnh hơn |

---

## 12. Đọc log và xử lý lỗi

Hệ thống log có **ba tầng**, lỗi ở tầng nào thì xem log của tầng đó — đi từ nguồn tới đích:

```text
1. Nguồn     docker compose -p taskhub logs --tail 5 taskhub     → app có in log không? có phải JSON không?
2. Agent     docker compose -p log08 logs alloy | tail -30        → đọc được container nào? đẩy về Loki có lỗi không?
             Alloy UI (127.0.0.1:12346): component đỏ / debug info
3. Kho       docker compose -p log08 logs loki | tail -30         → có nhận push không? có từ chối (rate limit, label quá nhiều)?
4. Hiển thị  Grafana Explore → Query inspector                    → câu truy vấn thực sự gửi đi, lỗi parse
```

Một vài dòng log điển hình (**minh họa** — chữ chính xác tùy phiên bản):

| Dòng log | Tầng | Nghĩa |
|---|---|---|
| Alloy: `error="... connect: no such file or directory" ... docker.sock` | Agent | Socket không có trong container |
| Alloy: `... final error sending batch ... connection refused` tới `loki:3100` | Agent → Kho | Loki chưa chạy hoặc sai tên/port |
| Loki: `... stream limit exceeded` hoặc `maximum active stream limit exceeded` | Kho | Quá nhiều stream — **cardinality** cao, xem lại nhãn |
| Loki: `entry too far behind` / `out of order` | Kho | Dòng log có timestamp cũ hơn cho phép (thường gặp khi gửi lại log cũ) |

Quy trình khi "không thấy log trong Grafana": (1) app có in không → (2) Alloy có đọc container đó không (UI debug) → (3) Loki có nhãn không (`/labels`) → (4) time range và selector trong Grafana có đúng không. Đừng nhảy thẳng vào sửa cấu hình Grafana.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Nêu 3 lý do `docker logs` không đủ cho một hệ thống chạy thật.
2. Log có cấu trúc khác log chữ tự do thế nào? Lợi ích cụ thể cho agent thu log?
3. Ba giá trị Spring Boot 4 hỗ trợ cho `logging.structured.format.console` là gì? Với `ecs`, mức log nằm ở trường nào?
4. Kể 4 loại thông tin **không bao giờ** được ghi vào log. Nếu lỡ ghi mật khẩu vào log đã gửi lên Loki, việc **đầu tiên** cần làm là gì?
5. Trong Loki, "stream" là gì? Vì sao nhãn `user_id` là ý tưởng tồi?
6. Loki khác Elasticsearch/OpenSearch ở cách đánh index thế nào? Mỗi bên mạnh ở loại truy vấn nào?
7. Viết LogQL: mọi dòng của service `taskhub` chứa chuỗi `timeout` nhưng không chứa `actuator`.
8. Trên một stream **không có** nhãn `level`, vì sao `{compose_service="taskhub"} | json | level="ERROR"` trả rỗng với log ECS? Sửa thế nào (2 cách)? Vì sao trong lab (Alloy đã gắn nhãn `level`) câu đó lại ra kết quả?
9. Viết LogQL đếm số dòng ERROR mỗi phút, gộp theo `compose_service`.
10. Khi nào nên dùng metric từ log, khi nào nên dùng metric Prometheus?
11. Kể tên 5 component Alloy trong pipeline của lab và việc của từng cái.
12. Vì sao trong mẫu chính thức, `discovery.relabel` có `targets = []` và luật được đưa vào `loki.source.docker` qua `relabel_rules`?
13. Mount Docker socket `:ro` có làm Alloy "an toàn" không? Giải thích.
14. Promtail có còn được hỗ trợ không? Gặp một repo dùng Promtail bạn làm gì?
15. Cần cấu hình gì để Loki tự xóa log cũ hơn 7 ngày? Không cấu hình thì sao?

---

## 14. Bài tập tự làm

> Lời giải ở [solutions/04-solutions.md](solutions/04-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Bỏ log healthcheck.** Request `/actuator/health` (từ healthcheck Docker, từ nginx) có thể tạo nhiều dòng log rác. Thêm một `stage.drop` vào `loki.process` để bỏ các dòng của taskhub có chứa `/actuator/health`. Chứng minh trước/sau bằng `bytes_over_time`.

**Bài 2 — Alert "app im lặng".** Viết biểu thức LogQL trả về 1 khi service `taskhub` **không có dòng log nào** trong 10 phút. Giải thích vì sao đây là tín hiệu đáng cảnh báo, và vì sao nó **không** thay được alert `up == 0` của Prometheus.

**Bài 3 — Nhãn cho nginx.** Log truy cập của nginx là chữ (định dạng `combined`). Không parse JSON được. Dùng `stage.regex` (đọc tài liệu Alloy) để rút mã HTTP `status`, rồi viết LogQL đếm số response 5xx của nginx mỗi phút **mà không** biến `status` thành nhãn. Giải thích lựa chọn của bạn về cardinality.

**Bài 4 — Retention.** Viết thêm cấu hình retention 3 ngày vào `loki-config.yaml` của lab (dựa trên tài liệu Loki về retention). Khởi động lại Loki, kiểm tra log của Loki không báo lỗi cấu hình. Nêu điều kiện về index period.

**Bài 5 — Chuyển đổi từ Promtail.** Một repo cũ có file `promtail-config.yaml` với `docker_sd_configs` và một `pipeline_stages` dùng `json`. Viết lại bằng Alloy (tự viết, rồi đối chiếu với kết quả của lệnh `alloy convert` chạy trong container). Liệt kê 2 điểm khác nhau.

**Bài 6 — Báo cáo so sánh.** Viết nửa trang (cho trưởng nhóm đọc): dự án `taskhub` nên dùng Loki hay OpenSearch? Có số liệu: RAM ước tính, dung lượng, loại truy vấn chính của nhóm. Kết luận trước, chi tiết sau.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Bật được log JSON ECS cho taskhub bằng cả hai cách (file cấu hình, biến môi trường) và chỉ ra trường `log.level`.
- [ ] Dựng được Loki + Alloy + Grafana, giải thích từng khối trong `config.alloy` mà không nhìn bài.
- [ ] Viết được LogQL: chọn stream, lọc dòng, `| json`, lọc trường, `count_over_time`/`rate` với `sum by`.
- [ ] Giải thích được cardinality và chỉ ra một nhãn tồi + cách xử lý thay thế.
- [ ] Khi "không thấy log", đi theo đúng thứ tự nguồn → agent → kho → hiển thị.
- [ ] Nêu được rủi ro Docker socket và ít nhất một cách thay thế.
- [ ] So sánh được Loki với ELK/OpenSearch bằng ít nhất 3 tiêu chí, nói được vì sao dự án chọn Loki.
- [ ] Biết Promtail đã EOL và hướng chuyển sang Alloy.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Spring Boot — Logging (Structured logging)](https://docs.spring.io/spring-boot/reference/features/logging.html) | `logging.structured.format.console`, định dạng `ecs`/`gelf`/`logstash`, MDC vào JSON | 2026-10-31 |
| [Grafana Loki — Labels](https://grafana.com/docs/loki/latest/get-started/labels/) | 10–15 nhãn, cardinality, structured metadata | 2026-10-31 |
| [Grafana Loki — Query (LogQL)](https://grafana.com/docs/loki/latest/query/) | Stream selector, line filter, parser, label filter | 2026-10-31 |
| [Grafana Loki — Metric queries](https://grafana.com/docs/loki/latest/query/metric_queries/) | `rate`, `count_over_time`, `absent_over_time`, `sum by` | 2026-10-31 |
| [Grafana Loki — Retention](https://grafana.com/docs/loki/latest/operations/storage/retention/) | `retention_enabled`, `delete_request_store`, `retention_period`, index 24h | 2026-10-31 |
| [Grafana Loki — Install with Docker](https://grafana.com/docs/loki/latest/setup/install/docker/) | Chạy Loki bằng Docker, `/ready`, file cấu hình local | 2026-10-31 |
| [Grafana Loki — Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Promtail EOL 02/03/2026 | 2026-10-31 |
| [Grafana Cloud — Migrate from Promtail to Alloy](https://grafana.com/docs/grafana-cloud/observe-and-act/send-data/alloy/set-up/migrate/from-promtail/) | `alloy convert`, `--config.format=promtail` | 2026-10-31 |
| [Grafana Alloy — Install on Docker](https://grafana.com/docs/alloy/latest/set-up/install/docker/) | Lệnh `run`, cổng UI 12345 | 2026-10-31 |
| [Grafana Alloy — Monitor Docker containers](https://grafana.com/docs/alloy/latest/monitor/monitor-docker-containers/) | Mẫu `discovery.relabel` + `relabel_rules` | 2026-10-31 |
| [Grafana Alloy — discovery.docker](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.docker/) | Nhãn `__meta_docker_*`, khối `filter` | 2026-10-31 |
| [Grafana Alloy — loki.source.docker](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/) | Tham số `host`, `targets`, `relabel_rules` | 2026-10-31 |
| [Grafana Alloy — loki.process](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.process/) | `stage.json`, `stage.labels`, `stage.drop`, `stage.structured_metadata` | 2026-10-31 |
| [Docker — JSON File logging driver](https://docs.docker.com/engine/logging/drivers/json-file/) | `max-size` mặc định không giới hạn, `max-file` | 2026-10-31 |
| [OpenSearch — Installing OpenSearch using Docker](https://docs.opensearch.org/latest/install-and-configure/install-opensearch/docker/) | Mật khẩu admin từ 2.12, `vm.max_map_count`, image | 2026-10-31 |
| [Fluent Bit — OpenSearch output](https://docs.fluentbit.io/manual/pipeline/outputs/opensearch) | `suppress_type_name`, `logstash_format`, TLS | 2026-10-31 |
| [Fluent Bit — Forward input](https://docs.fluentbit.io/manual/pipeline/inputs/forward) | Cổng 24224 | 2026-10-31 |
