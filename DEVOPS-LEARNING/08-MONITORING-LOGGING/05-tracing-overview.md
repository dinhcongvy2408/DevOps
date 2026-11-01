# 05. Distributed tracing — tổng quan

> ⏱️ ~2 giờ (+ 1,5 giờ lab tùy chọn) · Mức độ: 🟨 Nên biết (mức nhận biết; lab 🟦) · Kiến thức cần có trước: [01. Monitoring, logging, observability](01-monitoring-logging-observability.md), [02. Prometheus](02-metrics-prometheus.md), [04. Log tập trung](04-centralized-logging.md), [Networking 06 — HTTP](../02-NETWORKING/06-http-https-tls.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop · `[Container]` · `[Browser]` · Phiên bản khi viết: Spring Boot 4.1.2, OpenTelemetry Java agent 2.33.1, Jaeger 2.22.0, Grafana Tempo 2.9.0 (chỉ nhắc tới) (kiểm tra 2026-10-31)

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

> **Vì sao bài này ở mức "nhận biết"?** `taskhub` chỉ có **một** service gọi **một** database — metric (bài 02) và log (bài 04) đã đủ để tìm lỗi. Tracing tỏa sáng khi có **nhiều service gọi nhau**. Junior cần hiểu khái niệm, đọc được một trace và biết các thành phần; dựng hệ thống tracing hoàn chỉnh là việc bạn sẽ làm khi đi làm. Dự án v5 **không bắt buộc** tracing.

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Giải thích **trace**, **span**, quan hệ cha–con, thời lượng, thuộc tính (attribute) của span.
- Giải thích **context propagation**: làm sao ID của trace đi từ service này sang service khác, đọc được header W3C `traceparent`.
- Hiểu **sampling** là gì, vì sao không lưu 100% trace ở production, và mặc định của Spring Boot.
- Phân biệt các thành phần **OpenTelemetry**: API, SDK, instrumentation, Collector, giao thức **OTLP**.
- So sánh 3 cách thêm tracing vào Spring Boot 4: **OpenTelemetry Java agent**, starter của dự án OpenTelemetry, và **`spring-boot-starter-opentelemetry`** của Spring.
- Biết **Jaeger** và **Grafana Tempo** là backend lưu trace; biết cách nối log ↔ trace ↔ metric (`traceId` trong log, exemplar 🟦).
- (Lab tùy chọn) Chạy taskhub với Java agent, xem trace của `POST /api/tasks` có span JDBC trong Jaeger.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống | Metric/log trả lời được | Tracing trả lời thêm |
|---|---|---|
| "API checkout chậm, p95 = 3 giây" | Có chậm, chậm từ lúc nào | Chậm **ở đâu**: 2,6 giây nằm trong lời gọi service thanh toán → trong đó 2,5 giây là một câu SQL |
| Một request đi qua gateway → order → inventory → payment → DB | Mỗi service có log riêng, giờ lệch nhau | **Một** cây thời gian cho cả request, theo đúng thứ tự |
| Lỗi chỉ xảy ra với một số request | Tỉ lệ lỗi 2% | Trace của chính request lỗi, có thuộc tính (đầu vào, service con trả gì) |
| Phỏng vấn: "Ba trụ cột observability là gì?" | — | Metric, log, **trace** — và khi nào dùng cái nào |

Với hệ thống microservice (và Kubernetes ở [Module 09](../00-ROADMAP/curriculum-structure.md)), tracing gần như bắt buộc. Nhiều công ty tuyển DevOps hỏi về OpenTelemetry vì nó đã thành chuẩn chung cho cả ba loại tín hiệu.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Trace và span

- **Span** = một đơn vị công việc có **thời điểm bắt đầu, thời lượng, tên** và **thuộc tính**. Ví dụ: "xử lý `POST /api/tasks`", "câu `INSERT INTO tasks`", "gọi HTTP tới service khác".
- **Trace** = tập các span của **cùng một request**, nối với nhau thành cây nhờ quan hệ **cha–con**. Mỗi trace có một **trace ID** (16 byte = 32 ký tự hex), mỗi span có **span ID** (8 byte = 16 ký tự hex) và trỏ tới **parent span ID**.

```text
trace 4bf92f3577b34da6a3ce929d0e0e4736
└─ POST /api/tasks                      [taskhub]   45 ms   (span gốc — root span)
   ├─ TaskController.create             [taskhub]    40 ms
   │  └─ INSERT taskhub.tasks           [taskhub]    12 ms   db.system=postgresql
   └─ (nếu gọi service khác) POST /notify [notifier] 20 ms   ← span ở SERVICE KHÁC, cùng trace ID
```

Đọc một trace như đọc biểu đồ Gantt: thanh dài nhất, nằm sâu nhất thường là chỗ chậm.

### 3.2. Context propagation — trace ID đi qua mạng thế nào

Service A gọi service B qua HTTP. Để span ở B gắn vào **đúng** trace của A, A phải **gửi kèm** trace ID và span ID hiện tại. Chuẩn **W3C Trace Context** định nghĩa header:

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             │  │                                │                └─ trace-flags (01 = đã được sample)
             │  │                                └─ parent-id: span ID của bên gọi (16 hex)
             │  └─ trace-id (32 hex)
             └─ version (00)
```

B đọc header → tạo span mới với **cùng trace-id**, parent là `00f067aa0ba902b7`. Thư viện instrumentation làm việc này tự động cho HTTP client/server phổ biến. Nếu một tầng ở giữa (proxy, message queue) **làm rơi** header, trace bị **đứt làm hai**.

> Nginx làm reverse proxy mặc định **chuyển tiếp** các header request của client (trừ một số header đặc biệt), nên `traceparent` đi qua nginx của `taskhub` mà không cần cấu hình thêm. Bản thân nginx không tạo span trừ khi bạn cài module OpenTelemetry cho nginx 🟦.

### 3.3. Sampling — không lưu mọi trace

Một API 1.000 request/giây → 86 triệu trace/ngày. Lưu hết rất tốn. **Sampling** = chỉ giữ một phần:

| Kiểu | Quyết định lúc | Ưu | Nhược |
|---|---|---|---|
| **Head-based** (ví dụ giữ 10%) | Bắt đầu request (span gốc) | Đơn giản, rẻ; quyết định truyền theo `trace-flags` nên cả trace nhất quán | Có thể bỏ sót đúng request lỗi/chậm |
| **Tail-based** | Sau khi request kết thúc (ở Collector) | Giữ được **mọi** trace lỗi/chậm | Phải đệm toàn bộ span trong bộ nhớ — phức tạp |

Theo tài liệu Spring Boot 4.1.2: mặc định Spring Boot **chỉ sample 10%** request (`management.tracing.sampling.probability`, mặc định `0.1`); với OpenTelemetry, sampler mặc định là `parent-based-trace-id-ratio` — tôn trọng quyết định của bên gọi, nếu là span gốc thì dùng tỉ lệ trên. Khi học, đặt `1.0` để thấy mọi request.

---

## 4. Giải thích chi tiết

### 4.1. 🟨 OpenTelemetry là gì

**OpenTelemetry (OTel)** là dự án mã nguồn mở (thuộc CNCF) chuẩn hóa cách **tạo, thu thập và gửi** dữ liệu observability — trace, metric, log — không phụ thuộc nhà cung cấp.

| Thành phần | Vai trò |
|---|---|
| **API** | Interface để code tạo span/metric. Thư viện dùng API mà không ràng buộc vào triển khai cụ thể |
| **SDK** | Triển khai của API: sampling, gom batch, export |
| **Instrumentation** | Code tự động tạo span cho framework phổ biến (Spring MVC, JDBC, HTTP client…) |
| **OTLP** | Giao thức gửi dữ liệu (OpenTelemetry Protocol) qua **gRPC (cổng 4317)** hoặc **HTTP/protobuf (cổng 4318)** |
| **Collector** | Tiến trình trung gian nhận OTLP, xử lý (lọc, tail sampling, thêm thuộc tính), rồi gửi tới một hoặc nhiều backend. **Grafana Alloy** chính là một bản phân phối của Collector |
| **Backend** | Nơi lưu và xem trace: **Jaeger**, **Grafana Tempo**, hoặc dịch vụ thương mại |

Lợi ích lớn nhất: **đổi backend không phải sửa code** — app chỉ nói OTLP.

### 4.2. 🟨 Ba cách thêm tracing vào Spring Boot 4

| Cách | Cách làm | Ưu | Nhược |
|---|---|---|---|
| **1. OpenTelemetry Java agent** | Gắn `-javaagent:opentelemetry-javaagent.jar` lúc chạy JVM, cấu hình bằng biến `OTEL_*` | **Không sửa code, không sửa build**; instrument rất nhiều thư viện | Theo bài viết của Spring: agent phải **khớp phiên bản thư viện** của bạn, lỗi lệch phiên bản khó chẩn đoán; thêm việc với GraalVM native; có thể xung đột với agent khác |
| **2. OpenTelemetry Spring Boot starter** (của dự án OTel) | Thêm dependency | Không cần agent | Chính dự án OTel khuyên chỉ dùng khi **không** dùng được agent; kéo theo dependency bản alpha |
| **3. `spring-boot-starter-opentelemetry`** (của Spring, từ Boot 4.0) | Thêm dependency, cấu hình `management.*` | Tích hợp chuẩn với **Micrometer** (cùng hệ với metric bạn đã dùng ở bài 02); log tự có `traceId`/`spanId` | Starter đã stable nhưng kéo theo vài dependency có hậu tố alpha (theo bài viết của Spring) |

Theo tài liệu Spring Boot 4.1.2, tracing được hỗ trợ qua **Micrometer Tracing** với hai lựa chọn: OpenTelemetry + OTLP (cần `spring-boot-starter-opentelemetry`) hoặc Brave + Zipkin (`spring-boot-starter-zipkin`). Cấu hình xuất OTLP dùng nhóm thuộc tính `management.opentelemetry.tracing.export.otlp.*`. Ví dụ trong bài viết của Spring:

```yaml
management:
  tracing:
    sampling:
      probability: 1.0        # mặc định 0.1 — chỉ dùng 1.0 khi học/thử
  opentelemetry:
    tracing:
      export:
        otlp:
          endpoint: http://jaeger:4318/v1/traces
```

> ⚠️ **Không dùng đồng thời** Java agent và starter — hai bên cùng instrument, bạn sẽ được span trùng lặp hoặc lỗi khó hiểu. Chọn một.

Lab của bài dùng **cách 1 (agent)** vì không phải sửa code hay build lại image — hợp để thử nhanh. Khi muốn tracing là một phần cố định của dự án, cách 3 nhất quán hơn với Micrometer.

### 4.3. 🟨 Biến cấu hình quan trọng của Java agent

| Biến | Ý nghĩa | Lab dùng |
|---|---|---|
| `OTEL_SERVICE_NAME` | Tên service hiển thị trong backend | `taskhub` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Địa chỉ nhận OTLP | `http://jaeger:4318` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` hoặc `grpc`. Từ agent **2.0**, mặc định đổi từ gRPC sang `http/protobuf` (ghi trong release 2.0.0) | để mặc định → dùng cổng **4318** |
| `OTEL_TRACES_EXPORTER` | Exporter cho trace | mặc định `otlp` |
| `OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER` | Exporter cho metric, log | `none` — metric đã có Prometheus, log đã có Loki |
| `OTEL_TRACES_SAMPLER`, `OTEL_TRACES_SAMPLER_ARG` | Sampler và tham số | để mặc định khi học |

Gắn agent vào JVM trong container mà **không sửa Dockerfile**: biến môi trường `JAVA_TOOL_OPTIONS` được JVM tự đọc lúc khởi động.

### 4.4. 🟨 Jaeger và Grafana Tempo

| | Jaeger | Grafana Tempo |
|---|---|---|
| Nguồn gốc | Uber, nay là dự án CNCF | Grafana Labs |
| Giao diện | UI riêng (cổng 16686) | Xem trong **Grafana** (cùng chỗ với metric, log) |
| Lưu trữ | Bộ nhớ (all-in-one), hoặc Cassandra/Elasticsearch/OpenSearch… | Object storage (S3…), index tối thiểu — giống triết lý Loki |
| Hợp với | Học, thử nhanh: một container là đủ | Hệ thống đã dùng Grafana/Loki/Prometheus |

Lab dùng **Jaeger all-in-one** (lưu trong bộ nhớ, mất khi xóa container) vì chỉ cần một lệnh. Nếu đi tiếp, Tempo là lựa chọn tự nhiên cho stack Grafana của `taskhub`.

### 4.5. 🟦 Nối log ↔ trace ↔ metric

- **Log → trace:** khi tracing bật, Micrometer Tracing đặt `traceId`, `spanId` vào MDC; theo tài liệu Spring Boot, định dạng log JSON ECS thêm mọi cặp trong MDC vào dòng log ([bài 04](04-centralized-logging.md)). Trong Grafana, cấu hình *derived fields* của datasource Loki để biến `traceId` thành link mở trace trong Tempo/Jaeger.
- **Trace → log:** từ một span, mở log cùng `traceId` trong Loki.
- **Metric → trace (exemplar):** Prometheus có thể lưu kèm một vài **exemplar** — mẫu `traceId` của request cụ thể — cạnh điểm dữ liệu histogram. Trên biểu đồ p95 latency, bấm vào điểm cao bất thường → mở đúng trace chậm đó. Cần bật exemplar ở cả app, Prometheus và Grafana — để sau khi đi làm.

### 4.6. Gặp lại ở đâu

| Kiến thức | Dùng ở |
|---|---|
| `traceparent`, propagation | Microservice trên Kubernetes (Module 09), service mesh 🟦 |
| OTLP, Collector, Alloy | Alloy trong [bản tham khảo v5](labs/reference/README.md) có thể nhận thêm OTLP khi bạn mở rộng |
| Sampling | Kiểm soát chi phí observability khi đi làm |
| `traceId` trong log | Incident response ([bài 06](06-incident-response.md)) — tìm mọi log của một request lỗi |

---

## 5. Ví dụ thực tế

**Ví dụ 1 — "Chậm ở đâu?"** Dashboard báo p95 của `POST /orders` tăng từ 200 ms lên 2 giây. Log không có lỗi. Mở một trace chậm: span `POST /orders` 2,1 s → con `GET inventory/check` 1,9 s → trong service inventory, span `SELECT ... FROM stock` 1,8 s. Kết luận trong 5 phút: thiếu index sau đợt migration hôm qua. Không có trace, nhóm order và nhóm inventory sẽ tranh cãi "lỗi bên anh".

**Ví dụ 2 — Trace bị đứt.** Trong Jaeger, request đi qua API gateway hiện thành **hai** trace riêng. Nguyên nhân: gateway cấu hình lại header và bỏ mất `traceparent`. Sửa: cho phép chuyển tiếp header W3C, hoặc bật instrumentation ở gateway.

**Ví dụ 3 — Hóa đơn tracing tăng vọt.** Một đội bật sampling 100% ở production "cho chắc". Lượng span gấp 10 lần dự kiến, chi phí lưu trữ tăng tương ứng. Sửa: head-based 10% + tail-based ở Collector để **luôn** giữ trace lỗi và trace chậm.

---

## 6. Sơ đồ luồng hoạt động

```text
                            (lab tùy chọn trên laptop)
 curl ──HTTP──► nginx ──(traceparent được chuyển tiếp)──► taskhub (JVM + OTel Java agent)
                                                           │  tạo span: HTTP server, Spring MVC, JDBC
                                                           │  gom batch trong SDK
                                                           ▼ OTLP HTTP/protobuf → jaeger:4318
                                              ┌──────────── jaeger (all-in-one, bộ nhớ) ─────────┐
                                              │ nhận OTLP (4317/4318) · lưu · UI 16686           │
                                              └──────────────────────────┬───────────────────────┘
                                                                         ▼
                                                     Trình duyệt: 127.0.0.1:16686 → tìm service "taskhub"

Ở quy mô lớn:  app ──OTLP──► Collector/Alloy (lọc, tail sampling) ──► Tempo (S3) ──► Grafana
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `curl -fL -o opentelemetry-javaagent.jar https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.33.1/opentelemetry-javaagent.jar` | Tải agent **ghim phiên bản** | 🟨 |
| `docker run ... -e JAVA_TOOL_OPTIONS=-javaagent:/otel/opentelemetry-javaagent.jar` | Gắn agent vào JVM trong container | 🟨 |
| `curl -H 'traceparent: 00-<32hex>-<16hex>-01' ...` | Gửi request có sẵn trace context, rồi tìm đúng trace ID đó | 🟨 |
| `curl -s 'http://127.0.0.1:16686/api/services'` | Hỏi Jaeger: đã nhận service nào | 🟦 |
| `docker compose -p trace08 logs jaeger` | Log của backend khi không thấy trace | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

### Gắn agent vào taskhub bằng biến môi trường

```yaml
  taskhub:
    environment:
      JAVA_TOOL_OPTIONS: "-javaagent:/otel/opentelemetry-javaagent.jar"
      OTEL_SERVICE_NAME: taskhub
      OTEL_EXPORTER_OTLP_ENDPOINT: http://jaeger:4318
      OTEL_METRICS_EXPORTER: none
      OTEL_LOGS_EXPORTER: none
    volumes:
      - ./opentelemetry-javaagent.jar:/otel/opentelemetry-javaagent.jar:ro
```

| Dòng | Ý nghĩa |
|---|---|
| `JAVA_TOOL_OPTIONS` | JVM đọc biến này lúc khởi động và coi như tham số dòng lệnh. Không phải sửa `ENTRYPOINT` của Dockerfile ([Docker bài 03](../04-DOCKER/03-dockerfile-multistage.md)). Log khởi động sẽ có dòng `Picked up JAVA_TOOL_OPTIONS: ...` |
| `OTEL_EXPORTER_OTLP_ENDPOINT: http://jaeger:4318` | Tên service `jaeger` phân giải qua DNS của Docker network — vì vậy Jaeger phải chung network `taskhub_default`. Agent tự thêm đường dẫn `/v1/traces` khi dùng biến endpoint chung này (theo đặc tả cấu hình OTLP) |
| `OTEL_METRICS_EXPORTER: none` | Tắt gửi metric qua OTLP — tránh agent báo lỗi vì Jaeger không nhận metric |
| Mount `:ro` | App chạy bằng user không phải root (`taskhub`, [Docker bài 03](../04-DOCKER/03-dockerfile-multistage.md)) → file jar phải **đọc được** bởi mọi user (`chmod 644`) |

### Header `traceparent` tự tạo

```bash
TRACE_ID=$(openssl rand -hex 16)      # 32 ký tự hex
PARENT_ID=$(openssl rand -hex 8)      # 16 ký tự hex
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8000/api/tasks \
  -H 'Content-Type: application/json' \
  -H "traceparent: 00-${TRACE_ID}-${PARENT_ID}-01" \
  -d '{"title":"trace me"}'
echo "Tìm trace: $TRACE_ID"
```

| Phần | Ý nghĩa |
|---|---|
| `openssl rand -hex 16` | 16 byte ngẫu nhiên in dạng hex = đúng độ dài trace-id W3C |
| `-01` | trace-flags "sampled" — bên nhận (sampler `parent-based`) sẽ **giữ** trace này |
| Kết quả | Span trong taskhub dùng chính `TRACE_ID` của bạn → dán vào ô tìm kiếm của Jaeger để mở |

---

## 9. Bài thực hành từng bước

> 🟦 **Tùy chọn.** Làm khi đã xong lab bắt buộc của bài 02–04 và còn thời gian. Chi phí 0 USD. RAM thêm ~200–300 MB (Jaeger + agent).
> **Chưa chạy thử khi viết bài:** agent phải tương thích với Spring Boot 4.1 / Spring Framework 7 — tài liệu Spring cảnh báo agent cần khớp phiên bản thư viện. Nếu không thấy span Spring MVC/JDBC, xem mục 11 và phương án dùng `spring-boot-starter-opentelemetry` ở bài tập 3.

**Chuẩn bị:** stack `taskhub` (v0) đang chạy với project `taskhub`, network `taskhub_default`.

**Bước 1 — Tải agent (ghim phiên bản) `[WSL]`**

```bash
mkdir -p ~/devops-lab/08-monitoring/trace08 && cd ~/devops-lab/08-monitoring/trace08
curl -fL -o opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.33.1/opentelemetry-javaagent.jar
chmod 644 opentelemetry-javaagent.jar
ls -lh opentelemetry-javaagent.jar          # khoảng 25 MB
```

❓ Vì sao không dùng link `.../releases/latest/download/...` dù tài liệu "Getting started" dùng nó? (Gợi ý: [Module 05 bài 04](../05-CICD/04-secrets-environments.md) — ghim phiên bản.)

**Bước 2 — Chạy Jaeger trong network của taskhub `[WSL]`**

```bash
cat > compose.yaml <<'EOF'
name: trace08

services:
  jaeger:
    image: jaegertracing/jaeger:2.22.0
    ports:
      - "127.0.0.1:${TRACE08_JAEGER_PORT:-16686}:16686"   # UI
    networks: [taskhub_default]
    mem_limit: 512m

networks:
  taskhub_default:
    external: true
EOF

docker compose up -d
docker compose logs --tail 20 jaeger
```

Không publish 4317/4318 ra host: taskhub gửi tới Jaeger **trong** network Docker.

**Bước 3 — Gắn agent vào taskhub `[WSL]`**

```bash
cat > taskhub-otel.yaml <<'EOF'
services:
  taskhub:
    environment:
      JAVA_TOOL_OPTIONS: "-javaagent:/otel/opentelemetry-javaagent.jar"
      OTEL_SERVICE_NAME: taskhub
      OTEL_EXPORTER_OTLP_ENDPOINT: http://jaeger:4318
      OTEL_METRICS_EXPORTER: none
      OTEL_LOGS_EXPORTER: none
    volumes:
      - ${HOME}/devops-lab/08-monitoring/trace08/opentelemetry-javaagent.jar:/otel/opentelemetry-javaagent.jar:ro
EOF

cd ~/projects/taskhub
docker compose -p taskhub -f compose.yaml -f compose.override.yaml \
  -f ~/devops-lab/08-monitoring/trace08/taskhub-otel.yaml up -d
docker compose -p taskhub logs taskhub | grep -m3 -i "JAVA_TOOL_OPTIONS\|opentelemetry"
```

(Như bài 04: đã dùng `-f` thì phải ghi đủ mọi file compose bạn đang dùng.)

App khởi động **chậm hơn** vài giây — agent đang instrument các class.

**Bước 4 — Tạo request có trace ID biết trước `[WSL]`**

Chạy đoạn lệnh ở mục 8 ("Header `traceparent` tự tạo") 1 lần, rồi thêm vài request thường:

```bash
for i in 1 2 3; do curl -s -o /dev/null localhost:8000/api/tasks; done
curl -s http://127.0.0.1:16686/api/services | jq
```

**Bước 5 — Đọc trace trong Jaeger `[Browser]`**

1. Mở `http://127.0.0.1:16686` → **Service** = `taskhub` → **Find Traces**.
2. Dán `TRACE_ID` của bước 4 vào ô tìm theo Trace ID → mở trace `POST /api/tasks`.
3. Trả lời vào `week18/tracing.md`:
   - Có bao nhiêu span? Span nào là gốc? Span nào là con của span nào?
   - Có span nào chứa câu SQL (`INSERT ...`, thuộc tính `db.system`)? Nó chiếm bao nhiêu % thời gian request?
   - Span gốc có thuộc tính `http.response.status_code` không? Giá trị?

**Bước 6 — So sánh khi database chết `[WSL]` `[Browser]`**

```bash
docker compose -p taskhub stop postgres
curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/api/tasks
docker compose -p taskhub start postgres
```

Tìm trace mới nhất → span nào được đánh dấu lỗi? Thời lượng bao nhiêu (liên hệ ~30 giây chờ kết nối ở [Docker lab](../04-DOCKER/labs/lab-springboot-postgres-compose/README.md))?

**Bước 7 — Dọn dẹp `[WSL]`**

```bash
cd ~/projects/taskhub
docker compose -p taskhub -f compose.yaml -f compose.override.yaml up -d   # bỏ agent
cd ~/devops-lab/08-monitoring/trace08 && docker compose down                # Jaeger (dữ liệu trong bộ nhớ, mất theo)
```

---

## 10. Kết quả mong đợi

| Bước | Kết quả (minh họa) |
|---|---|
| 1 | File jar khoảng 25 MB |
| 2 | Jaeger chạy, log không có lỗi |
| 3 | Log taskhub có `Picked up JAVA_TOOL_OPTIONS: -javaagent:/otel/opentelemetry-javaagent.jar` và dòng khởi động của OpenTelemetry agent |
| 4 | `/api/services` liệt kê `taskhub` |
| 5 | Trace `POST /api/tasks` có span gốc HTTP server, các span con, ít nhất một span JDBC với câu `INSERT` |
| 6 | Trace lỗi có span đánh dấu error, thời lượng dài (hàng chục giây) |
| 7 | taskhub chạy lại không có agent; `docker compose -p trace08 ps` rỗng |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Kiểm tra | Cách sửa |
|---|---|---|---|
| Container taskhub thoát ngay, log `Error opening zip file or JAR manifest missing` | Đường dẫn jar sai hoặc mount nhầm thành thư mục | `docker compose -p taskhub logs taskhub \| head` | Sửa đường dẫn bind mount (đường dẫn tuyệt đối trên host) |
| `Permission denied` khi đọc jar | File không đọc được bởi user `taskhub` trong container | `ls -l opentelemetry-javaagent.jar` | `chmod 644` |
| Jaeger không có service `taskhub` | Sai endpoint hoặc Jaeger khác network | `docker network inspect taskhub_default` — có `jaeger` không? | Thêm Jaeger vào `taskhub_default` (bước 2) |
| Log agent báo lỗi export tới cổng 4317 | Dùng `grpc` với endpoint 4318 (hoặc ngược lại) | Biến `OTEL_EXPORTER_OTLP_PROTOCOL` | Để mặc định `http/protobuf` + 4318, hoặc đặt `grpc` + 4317 |
| Có trace nhưng chỉ có span HTTP, không có span Spring MVC/JDBC | Agent chưa hỗ trợ đầy đủ phiên bản thư viện (Spring Framework 7 / Boot 4) | Log khởi động agent; changelog agent | Nâng agent lên bản mới hơn, hoặc dùng `spring-boot-starter-opentelemetry` (bài tập 3) |
| Trace bị nhân đôi span | Dùng **cả** agent và starter | `pom.xml` có starter OpenTelemetry không? | Chỉ dùng một cách |
| Không tìm thấy trace theo `TRACE_ID` | Header sai định dạng (sai độ dài, sai version) → bị bỏ qua, trace mới được tạo | `echo -n $TRACE_ID \| wc -c` phải là 32 | Tạo lại theo mục 8 |

---

## 12. Đọc log và xử lý lỗi

Đi theo đường dữ liệu: **app → exporter → backend → UI**.

1. **App có agent không?** `docker compose -p taskhub logs taskhub | grep -i javaagent` — không có dòng `Picked up JAVA_TOOL_OPTIONS` nghĩa là biến môi trường chưa vào container (`docker inspect taskhub-taskhub-1 --format '{{json .Config.Env}}' | jq`).
2. **Exporter có gửi được không?** Agent ghi lỗi export ra log của app (ví dụ minh họa: `Failed to export spans. ... Connection refused`). Kiểm tra DNS và cổng từ trong network: `docker run --rm --network taskhub_default curlimages/curl:8.10.1 -s -o /dev/null -w '%{http_code}\n' http://jaeger:4318/v1/traces` — mã khác `000` (ví dụ 405 vì GET) nghĩa là cổng có người nghe.
3. **Backend có nhận không?** `docker compose -p trace08 logs jaeger | tail`; `curl -s http://127.0.0.1:16686/api/services`.
4. **UI:** đúng service, đúng khoảng thời gian, đúng định dạng trace ID.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Trace và span khác nhau thế nào? Một span có những thông tin gì?
2. Giải thích từng phần của `traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`.
3. Điều gì xảy ra với trace nếu một proxy ở giữa làm rơi header `traceparent`?
4. Head-based và tail-based sampling khác nhau thế nào? Mặc định Spring Boot sample bao nhiêu phần trăm?
5. Kể 5 thành phần của OpenTelemetry và vai trò. OTLP dùng những cổng nào?
6. So sánh Java agent với `spring-boot-starter-opentelemetry`. Vì sao không dùng cả hai?
7. Vì sao lab dùng `JAVA_TOOL_OPTIONS` thay vì sửa `ENTRYPOINT` của Dockerfile?
8. Jaeger khác Grafana Tempo ở đâu? Với stack của `taskhub`, cái nào hợp hơn về lâu dài? Vì sao?
9. Làm sao đi từ một dòng log lỗi trong Loki tới trace tương ứng?
10. Vì sao `taskhub` v5 không bắt buộc tracing? Khi nào thì tracing trở thành bắt buộc?

---

## 14. Bài tập tự làm

> Lời giải ở [solutions/05-solutions.md](solutions/05-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Vẽ trace bằng tay.** Một request đi qua: nginx (không instrument) → taskhub `GET /api/tasks` (50 ms) → JDBC `SELECT` (30 ms). Vẽ cây span (dạng chữ), ghi trace ID giả, span ID, parent ID. Nếu thêm service `notifier` được taskhub gọi qua HTTP sau khi tạo task, cây thay đổi thế nào?

**Bài 2 — Chi phí sampling.** taskhub nhận trung bình 20 request/giây, mỗi trace ~5 span, mỗi span ~1 KB khi lưu. Tính dung lượng/ngày với sampling 100%, 10%, 1%. Đề xuất mức cho production kèm lý do.

**Bài 3 — Cách của Spring.** Viết (không cần chạy) thay đổi `pom.xml` và `application.yml` để taskhub dùng `spring-boot-starter-opentelemetry` gửi trace tới Jaeger, sample 100% khi dev và 10% khi prod (gợi ý: profile Spring hoặc biến môi trường). Đối chiếu tên thuộc tính với tài liệu Spring Boot.

**Bài 4 — `traceId` trong log.** Khi dùng Micrometer Tracing (bài 3), log JSON ECS của taskhub sẽ có thêm trường gì? Viết LogQL lấy mọi dòng log của **một** trace ID cụ thể (không dùng nhãn cho trace ID — vì sao?).

**Bài 5 — Tìm hiểu Tempo.** Đọc tài liệu Grafana Tempo, liệt kê những gì cần thêm vào [bản tham khảo v5](labs/reference/README.md) để có tracing: service nào, Alloy nhận OTLP ra sao, datasource Grafana, RAM ước tính. Chỉ viết kế hoạch, không triển khai.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích trace/span/parent bằng một ví dụ của taskhub mà không nhìn bài.
- [ ] Đọc và tự tạo được header `traceparent` đúng định dạng.
- [ ] Nói được sampling là gì, mặc định của Spring Boot, khi nào cần tail-based.
- [ ] Phân biệt API/SDK/instrumentation/Collector/backend và giao thức OTLP.
- [ ] So sánh được 3 cách thêm tracing vào Spring Boot 4 và chọn có lý do.
- [ ] Nêu được cách nối log ↔ trace ↔ metric.
- [ ] (Nếu làm lab) Mở được trace `POST /api/tasks`, chỉ ra span JDBC và % thời gian của nó.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Spring Boot — Tracing](https://docs.spring.io/spring-boot/reference/actuator/tracing.html) | `spring-boot-starter-opentelemetry`, `management.tracing.sampling.probability` (mặc định 10%), sampler OTel, `traceId`/`spanId` trong MDC, `logging.pattern.correlation` | 2026-10-31 |
| [Spring blog — OpenTelemetry with Spring Boot (18/11/2025)](https://spring.io/blog/2025/11/18/opentelemetry-with-spring-boot/) | So sánh 3 cách, thuộc tính `management.opentelemetry.tracing.export.otlp.endpoint`, cảnh báo về agent | 2026-10-31 |
| [Spring Boot — Logging](https://docs.spring.io/spring-boot/reference/features/logging.html) | ECS thêm MDC vào JSON | 2026-10-31 |
| [W3C Trace Context](https://www.w3.org/TR/trace-context/) | Định dạng `traceparent` | 2026-10-31 |
| [OpenTelemetry — Java agent: Getting started](https://opentelemetry.io/docs/zero-code/java/agent/getting-started/) | `-javaagent`, `OTEL_SERVICE_NAME`, link tải agent | 2026-10-31 |
| [opentelemetry-java-instrumentation — Releases](https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases) | Phiên bản 2.33.1; release 2.0.0: mặc định `http/protobuf` | 2026-10-31 |
| [Jaeger — Getting started](https://www.jaegertracing.io/docs/latest/getting-started/) | All-in-one 2.22.0, cổng 16686/4317/4318 | 2026-10-31 |
| [Grafana Tempo — Documentation](https://grafana.com/docs/tempo/latest/) | Tempo là backend trace của Grafana | 2026-10-31 |
