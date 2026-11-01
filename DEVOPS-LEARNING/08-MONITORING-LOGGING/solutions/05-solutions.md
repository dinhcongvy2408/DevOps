# Lời giải — Bài 05: Distributed tracing

> Chỉ mở sau khi đã tự làm. Quay lại bài: [05-tracing-overview.md](../05-tracing-overview.md)

## Câu hỏi trong lab

**Bước 1.** `latest` là tag **di động**: cùng một lệnh hôm nay và tháng sau tải về hai phiên bản khác nhau → lab không lặp lại được, và nếu bản mới có lỗi/không tương thích với Spring Boot của bạn thì khó biết vì sao. Ghim `v2.33.1` = biết chính xác mình đang chạy gì (cùng lý do với ghim SHA action ở Module 05).

**Bước 5 (gợi ý chấm).** Thường thấy: span gốc `POST /api/tasks` (kind SERVER), các span con của Spring MVC/controller, một span JDBC có thuộc tính `db.system=postgresql` và câu `INSERT`; span gốc có `http.response.status_code=201`. Tỉ lệ % = thời lượng span JDBC ÷ thời lượng span gốc. Con số cụ thể phụ thuộc máy bạn — chấm theo cách đọc, không theo con số.

**Bước 6.** Span gốc (và/hoặc span JDBC/lấy kết nối) được đánh dấu lỗi, thời lượng khoảng 30 giây — đúng bằng thời gian HikariCP chờ kết nối trước khi ném exception.

## Câu hỏi kiểm tra kiến thức

1. Span: một đơn vị công việc có tên, thời điểm bắt đầu, thời lượng, thuộc tính, trạng thái (lỗi/không), span ID, parent span ID. Trace: tập các span cùng trace ID của một request, nối thành cây.
2. `00` version; `4bf9…4736` trace-id (32 hex chữ thường, định danh cả trace); `00f0…02b7` parent-id (16 hex, span ID của bên gọi); `01` trace-flags — bit "sampled" bật.
3. Bên nhận không thấy context → tạo **trace mới** → một request hiện thành hai (hoặc nhiều) trace rời nhau, mất quan hệ cha–con.
4. Head-based: quyết định ở đầu request (rẻ, đơn giản, có thể bỏ sót request lỗi). Tail-based: quyết định sau khi có đủ span (giữ được mọi trace lỗi/chậm, nhưng phải đệm span — phức tạp, thường làm ở Collector). Spring Boot mặc định 10% (`management.tracing.sampling.probability=0.1`).
5. API (interface), SDK (triển khai: sampling, batch, export), instrumentation (tự tạo span cho thư viện), Collector (nhận/xử lý/chuyển tiếp), backend (Jaeger/Tempo). OTLP: gRPC 4317, HTTP/protobuf 4318.
6. Agent: không sửa code/build, instrument rộng, nhưng phải khớp phiên bản thư viện, khó chẩn đoán khi lệch, thêm việc với native image. Starter của Spring: tích hợp với Micrometer, cấu hình bằng `management.*`, log tự có traceId. Dùng cả hai → instrument hai lần → span trùng, xung đột.
7. Không phải sửa và build lại image; bật/tắt bằng một biến môi trường; image vẫn giữ nguyên cho môi trường không cần tracing. JVM tự đọc `JAVA_TOOL_OPTIONS`.
8. Jaeger: UI riêng, all-in-one một container, nhiều lựa chọn lưu trữ. Tempo: xem trong Grafana, lưu object storage, index tối thiểu (giống Loki). Với taskhub (đã có Grafana + Loki + Prometheus) Tempo hợp hơn về lâu dài — một giao diện, nối log↔trace↔metric dễ.
9. Bật tracing để `traceId` vào MDC → log JSON có trường `traceId` → trong Grafana cấu hình derived field của datasource Loki biến `traceId` thành link tới Tempo/Jaeger (hoặc copy trace ID dán vào Jaeger).
10. taskhub chỉ có một service + một database: metric và log đủ để định vị lỗi; tracing tốn thêm RAM/công vận hành. Bắt buộc khi có nhiều service gọi nhau (microservice), khi cần biết thời gian nằm ở service/lời gọi nào.

## Bài tập tự làm

### Bài 1 — Cây span

```text
trace 0af7651916cd43dd8448eb211c80319c
└─ GET /api/tasks          span b7ad6b7169203331  parent: (không — span gốc)   50 ms  [taskhub]
   └─ SELECT taskhub.tasks span 00f067aa0ba902b7  parent: b7ad6b7169203331     30 ms  [taskhub]
```

nginx không instrument → không có span cho nginx; header `traceparent` (nếu client gửi) đi xuyên qua.

Thêm `notifier` (gọi sau khi tạo task, trong `POST /api/tasks`):

```text
└─ POST /api/tasks                    [taskhub]   span A (gốc)
   ├─ INSERT taskhub.tasks            [taskhub]   span B, parent A
   └─ POST http://notifier/notify     [taskhub]   span C (CLIENT), parent A
      └─ POST /notify                 [notifier]  span D (SERVER), parent C — CÙNG trace ID, nhờ traceparent
```

### Bài 2 — Chi phí sampling

20 req/s × 86.400 s = 1.728.000 trace/ngày × 5 span × 1 KB ≈ 8,64 GB/ngày ở 100%.

| Sampling | Dung lượng/ngày | 7 ngày |
|---|---|---|
| 100% | ≈ 8,6 GB | ≈ 60 GB |
| 10% | ≈ 0,86 GB | ≈ 6 GB |
| 1% | ≈ 86 MB | ≈ 0,6 GB |

Đề xuất: 10% head-based (mặc định Spring Boot) — đủ thống kê độ trễ; nếu cần chắc chắn giữ mọi trace lỗi thì thêm tail-based ở Collector (giữ 100% trace lỗi + trace chậm hơn ngưỡng). Với EC2 4 GiB của v5, ngay cả 10% cũng là thêm tải đáng kể — lý do tracing không bắt buộc ở dự án.

### Bài 3 — `spring-boot-starter-opentelemetry`

`pom.xml`:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-opentelemetry</artifactId>
</dependency>
```

`application.yml`:

```yaml
management:
  tracing:
    sampling:
      probability: ${TRACING_SAMPLING_PROBABILITY:0.1}   # prod mặc định 10%
  opentelemetry:
    tracing:
      export:
        otlp:
          endpoint: ${OTEL_TRACES_ENDPOINT:http://jaeger:4318/v1/traces}
```

Dev: đặt `TRACING_SAMPLING_PROBABILITY=1.0` trong compose của laptop (hoặc profile `dev` với `application-dev.yml`). Lưu ý: endpoint ở đây là **đường dẫn đầy đủ** `/v1/traces` (theo ví dụ của bài viết Spring), khác biến `OTEL_EXPORTER_OTLP_ENDPOINT` chung của Java agent (agent tự thêm `/v1/traces`). Tên nhóm thuộc tính `management.opentelemetry.tracing.export.otlp.*` theo tài liệu Spring Boot 4.1.2 — đối chiếu lại trong "Common Application Properties" trước khi dùng. Không dùng chung với Java agent.

### Bài 4 — `traceId` trong log

Micrometer Tracing đặt `traceId` và `spanId` vào MDC; định dạng ECS thêm mọi cặp MDC vào JSON → dòng log có thêm trường `traceId`, `spanId` (đúng tên trường kiểm tra bằng `| json` trên log thật của bạn).

```logql
{compose_service="taskhub"} | json | traceId="4bf92f3577b34da6a3ce929d0e0e4736"
```

Hoặc nhanh hơn (lọc dòng trước khi parse): `{compose_service="taskhub"} |= "4bf92f3577b34da6a3ce929d0e0e4736"`. Không dùng nhãn cho trace ID: mỗi request một giá trị → cardinality cực cao → mỗi trace một stream (bài 04, mục 3.4).

### Bài 5 — Kế hoạch thêm Tempo (đáp án tham khảo)

- Service `tempo` (image `grafana/tempo`, ghim tag), lưu filesystem trong volume, retention ngắn (ví dụ 48h), `mem_limit` ~256–512 MB; không publish ra host.
- Alloy: thêm `otelcol.receiver.otlp` (nhận OTLP 4317/4318 từ taskhub trong network) → `otelcol.exporter.otlp` tới Tempo (đọc tài liệu Alloy để lấy đúng tên component/tham số).
- App: starter của Spring (bài 3) hoặc Java agent, endpoint trỏ tới Alloy (không trỏ thẳng Tempo — để còn đổi backend/thêm tail sampling).
- Grafana: datasource Tempo; trong datasource Loki thêm derived field `traceId` → link Tempo.
- RAM: cộng thêm vài trăm MB → kiểm tra lại bảng bộ nhớ trên `c7i-flex.large` (4 GiB) trước khi bật.
- Chấm đạt khi kế hoạch có đủ: thành phần, đường đi dữ liệu, cấu hình app, Grafana, ước tính tài nguyên, và nguồn tài liệu đã đọc.
