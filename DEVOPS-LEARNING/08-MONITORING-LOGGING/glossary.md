# Thuật ngữ Module 08 — Monitoring, Logging, Observability

> Mỗi nhóm ghi bài học giải thích kỹ thuật ngữ đó. CloudWatch, alarm, SNS ở [glossary AWS](../06-AWS/glossary.md); rollback, smoke test ở [glossary CI/CD](../05-CICD/glossary.md).

## Mục lục

- [Khái niệm (bài 01)](#khái-niệm-bài-01)
- [Metrics và Prometheus (bài 02)](#metrics-và-prometheus-bài-02)
- [Grafana và alerting (bài 03)](#grafana-và-alerting-bài-03)
- [Log tập trung (bài 04)](#log-tập-trung-bài-04)
- [Tracing (bài 05)](#tracing-bài-05)
- [Sự cố, backup, restore (bài 06)](#sự-cố-backup-restore-bài-06)

---

## Khái niệm (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Monitoring | Giám sát | Theo dõi các chỉ số đã biết trước để phát hiện vấn đề đã biết. |
| Observability | Khả năng quan sát | Hiểu được trạng thái bên trong hệ thống từ dữ liệu nó phát ra, kể cả với vấn đề chưa lường trước. |
| Metrics / logs / traces | Chỉ số / nhật ký / dấu vết | Ba "trụ cột": số theo thời gian / sự kiện dạng văn bản / đường đi của một request. |
| White-box / black-box monitoring | Giám sát hộp trắng / hộp đen | Đo từ bên trong app / đo từ bên ngoài như người dùng. |
| Push / pull | Đẩy / kéo | App gửi dữ liệu đi / hệ thống giám sát đến lấy (Prometheus kéo). |
| Golden Signals | Bốn tín hiệu vàng | Latency, traffic, errors, saturation (Google SRE). |
| USE / RED | Hai phương pháp | Utilization-Saturation-Errors cho tài nguyên; Rate-Errors-Duration cho dịch vụ. |
| SLI / SLO / SLA | Chỉ số / mục tiêu / cam kết mức dịch vụ | Đo gì / đạt bao nhiêu / hứa với khách hàng kèm hậu quả. |
| Error budget | Ngân sách lỗi | Phần không đạt cho phép (ví dụ 99,9% → 43,2 phút/tháng). |
| Cardinality | Số chuỗi | Số tổ hợp nhãn khác nhau — nhãn có quá nhiều giá trị làm hệ thống quá tải. |
| Alert fatigue | Mệt mỏi cảnh báo | Quá nhiều cảnh báo vô nghĩa khiến người trực bỏ qua cả cảnh báo thật. |

## Metrics và Prometheus (bài 02)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Scrape / target / job | Lấy dữ liệu / đích / nhóm đích | Prometheus gọi HTTP tới `/metrics` của từng target theo chu kỳ. |
| Exporter | Bộ xuất chỉ số | Chương trình chuyển chỉ số của hệ thống khác sang định dạng Prometheus (`node_exporter`). |
| TSDB | Cơ sở dữ liệu chuỗi thời gian | Nơi Prometheus lưu mẫu (sample) theo thời gian; có retention. |
| Label | Nhãn | Cặp khóa–giá trị phân biệt các chuỗi của cùng một metric. |
| Counter / gauge | Bộ đếm / đồng hồ đo | Chỉ tăng (reset khi khởi động lại) / lên xuống tự do. |
| Histogram / summary | Biểu đồ tần suất / tóm tắt | Đếm theo bucket (`_bucket`, gộp được) / tính phân vị phía client (không gộp được). |
| Micrometer | Thư viện metric Java | Lớp trung gian Spring Boot dùng để xuất metric (`http.server.requests`). |
| PromQL | Ngôn ngữ truy vấn | `rate()`, `sum by`, `histogram_quantile()`… |
| `rate` / `irate` / `increase` | Tốc độ / tốc độ tức thời / mức tăng | Trên counter, trong một cửa sổ thời gian. |
| `up` | Chỉ số sống | 1 nếu scrape thành công, 0 nếu thất bại. |
| Recording rule | Luật ghi sẵn | Tính trước biểu thức tốn kém, lưu thành metric mới. |
| Staleness | Hết hạn | Chuỗi không còn được scrape bị coi là biến mất sau 5 phút. |
| Textfile collector | Bộ thu file văn bản | `node_exporter` đọc metric từ file `.prom` — dùng cho job như backup. |

## Grafana và alerting (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Datasource | Nguồn dữ liệu | Kết nối từ Grafana tới Prometheus, Loki… |
| Dashboard / panel | Bảng điều khiển / ô biểu đồ | Tập các panel; mỗi panel là một truy vấn + cách hiển thị. |
| Provisioning | Cấp phát bằng file | Datasource và dashboard định nghĩa bằng file trong repo, không click tay. |
| Alerting rule | Luật cảnh báo | `expr` + `for` + `labels` + `annotations`. |
| Pending / firing / resolved | Chờ / đang báo / đã hết | Trạng thái của một alert. |
| Alertmanager | Trình quản lý cảnh báo | Gom nhóm, khử trùng, định tuyến, im lặng, gửi thông báo. |
| Route / receiver | Tuyến / nơi nhận | Cây định tuyến chọn receiver (Telegram, webhook…). |
| `group_wait` / `group_interval` / `repeat_interval` | Thời gian chờ nhóm / giữa các lần nhóm / nhắc lại | Điều khiển nhịp gửi thông báo. |
| Inhibition / silence | Ức chế / tắt tiếng | Một alert chặn alert khác / tắt tạm theo bộ lọc. |
| Runbook | Sổ tay xử lý | Tài liệu từng bước cho một cảnh báo cụ thể. |
| `promtool test rules` | Kiểm thử luật | Unit test cho alerting/recording rules. |

## Log tập trung (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Structured logging | Log có cấu trúc | Log dạng JSON (ECS, Logstash, GELF) thay vì văn bản tự do. |
| Log level | Mức log | TRACE/DEBUG/INFO/WARN/ERROR. |
| Loki | Hệ thống log | Chỉ đánh chỉ mục **nhãn**, không đánh chỉ mục nội dung — rẻ hơn ELK. |
| Stream | Luồng | Tập log có cùng bộ nhãn. |
| LogQL | Ngôn ngữ truy vấn log | `{service="taskhub"} \|= "ERROR" \| json`, `rate()`, `count_over_time()`. |
| Structured metadata | Siêu dữ liệu có cấu trúc | Trường đính kèm dòng log nhưng không phải nhãn (dùng cho ID nhiều giá trị). |
| Grafana Alloy | Tác tử thu thập | Thu log/metric/trace và gửi đi; thay Promtail (EOL 2/3/2026). |
| Pipeline (Alloy) | Đường ống | `discovery.docker` → `discovery.relabel` → `loki.source.docker` → `loki.process` → `loki.write`. |
| ELK / OpenSearch | Bộ log toàn văn | Elasticsearch/OpenSearch + Logstash/Fluent Bit + Kibana/Dashboards — tìm kiếm mạnh, tốn RAM. |
| Log rotation | Xoay vòng log | Giới hạn dung lượng file log (`max-size`, `max-file`). |

## Tracing (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Trace / span | Dấu vết / đoạn | Toàn bộ hành trình một request / một bước trong đó (HTTP, SQL…). |
| Context propagation | Truyền ngữ cảnh | Chuyển trace ID qua các dịch vụ (header W3C `traceparent`). |
| Sampling | Lấy mẫu | Chỉ giữ một phần trace để giảm chi phí. |
| OpenTelemetry (OTel) | Chuẩn quan sát mở | API/SDK/Collector/giao thức OTLP cho metric, log, trace. |
| Java agent | Tác tử Java | Tự gắn instrumentation vào app không cần sửa code. |
| Jaeger / Tempo | Hệ thống lưu trace | Nơi lưu và xem trace. |
| Exemplar | Mẫu tiêu biểu | Trace ID gắn vào một điểm metric để nhảy từ biểu đồ sang trace. |

## Sự cố, backup, restore (bài 06)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Incident | Sự cố | Sự kiện làm suy giảm dịch vụ, cần phản ứng. |
| Severity (SEV1–SEV4) | Mức nghiêm trọng | Quyết định tốc độ và quy mô phản ứng. |
| Incident commander | Người chỉ huy sự cố | Điều phối, ra quyết định; không tự tay sửa. |
| Mitigate / resolve | Giảm thiểu / giải quyết | Cầm máu trước (rollback) / sửa nguyên nhân sau. |
| Postmortem (blameless) | Bản phân tích sau sự cố (không đổ lỗi) | Timeline, ảnh hưởng, nguyên nhân, bài học, việc cần làm có người chịu trách nhiệm. |
| MTTD / MTTR | Thời gian phát hiện / khôi phục trung bình | Đo hiệu quả phản ứng sự cố. |
| Logical / physical backup | Sao lưu logic / vật lý | `pg_dump` (SQL/định dạng riêng) / sao chép file dữ liệu + WAL. |
| `pg_dump -Fc` / `pg_restore` | Dump định dạng custom / khôi phục | Định dạng nén sẵn, khôi phục chọn lọc được. |
| PITR | Khôi phục theo thời điểm | Cần backup vật lý + WAL (RDS có sẵn). |
| RPO / RTO | Mục tiêu điểm khôi phục / thời gian khôi phục | Mất tối đa bao nhiêu dữ liệu / mất bao lâu để chạy lại. |
| 3-2-1 rule | Quy tắc 3-2-1 | 3 bản, 2 loại phương tiện, 1 bản ở nơi khác. |
| Restore drill | Diễn tập khôi phục | Định kỳ khôi phục thật để chứng minh backup dùng được. |
