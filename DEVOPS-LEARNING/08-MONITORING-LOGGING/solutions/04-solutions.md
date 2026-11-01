# Lời giải — Bài 04: Log tập trung (Loki + Alloy)

> Chỉ mở sau khi đã tự làm. Quay lại bài: [04-centralized-logging.md](../04-centralized-logging.md)

## Câu hỏi trong lab

**Bước 1.** Mỗi dòng là một object JSON. Mức log nằm **lồng** trong `log`: `{"log":{"level":"INFO","logger":"..."}}`.

**Bước 2.** `path_prefix: /tmp/loki` — nằm **trong** container, mất khi container bị xóa (`down`). File mẫu chưa bật retention (không có `retention_enabled`) → dữ liệu không tự xóa; với lab chấp nhận được.

**Bước 3.** `loki.source.docker` cần nhãn meta (`__meta_docker_container_id`…) để biết đọc log của container nào. Nếu đưa target đã relabel (nhãn `__` đã bị bỏ) vào thì nó không còn thông tin đó. Vì vậy `discovery.relabel` chỉ dùng để **chứa luật** (`targets = []`), luật được áp **bên trong** `loki.source.docker` qua `relabel_rules`.

**Bước 8.** Trường parse được tên `log_level` (JSON lồng `log.level` được làm phẳng bằng `_`). `| json | level="ERROR"` vẫn ra kết quả vì bộ lọc sau `| json` áp lên **cả nhãn stream lẫn trường vừa parse** — và stream đã có nhãn `level` do Alloy gắn. Nếu Alloy không gắn nhãn đó, câu này trả **rỗng**. Bài học: biết rõ một tên là **nhãn của stream** hay **trường vừa parse**. Cách chắc chắn với ECS khi không có nhãn: `| json | log_level="ERROR"`; khi đã có nhãn: đưa vào selector `{compose_service="taskhub", level="ERROR"}`.

**Bước 10.** Mỗi tổ hợp nhãn khác nhau = một stream. Với `container` × `level` chỉ vài stream. Thêm nhãn `thread` (pool Tomcat mặc định tới 200 thread `http-nio-8080-exec-N`) nhân số stream của taskhub lên tới hàng trăm — mỗi stream rất ít dữ liệu, index phình to, đúng kiểu cardinality cao.

## Câu hỏi kiểm tra kiến thức

1. (a) Log nằm trên từng máy, phải vào từng máy để xem; (b) container bị xóa/tạo lại là log cũ mất; (c) không tìm/lọc/thống kê được trên nhiều máy, không nối được với metric; thêm: không giới hạn dung lượng mặc định.
2. Log có cấu trúc là JSON với trường có tên → agent chỉ cần parse JSON, không phải viết regex đoán format; đổi format chữ không làm gãy pipeline; lọc theo trường chính xác.
3. `ecs`, `logstash`, `gelf`. Với `ecs`: `log.level` (lồng).
4. Mật khẩu/secret/token, header `Authorization`, dữ liệu cá nhân (CCCD, số điện thoại…), body request/response đầy đủ, chuỗi kết nối có mật khẩu. Việc đầu tiên: **đổi (rotate) secret đó** — coi như đã lộ — rồi mới sửa code và xử lý dữ liệu log.
5. Stream = tập dòng log có **cùng bộ nhãn**. `user_id` có rất nhiều giá trị → mỗi giá trị một stream → hàng nghìn/triệu stream nhỏ → index lớn, ingester tốn RAM, truy vấn chậm. Để `user_id` trong nội dung (lọc bằng `| json`) hoặc structured metadata.
6. Loki chỉ index nhãn, quét nội dung khi truy vấn → rẻ, mạnh với truy vấn đã thu hẹp bằng nhãn và log vận hành. Elasticsearch/OpenSearch index toàn văn → tìm từ bất kỳ rất nhanh, aggregation mạnh, nhưng tốn dung lượng/RAM và vận hành phức tạp hơn.
7. `{compose_service="taskhub"} |= "timeout" != "actuator"`
8. ECS lồng → sau `| json` trường là `log_level`, không có `level`. Sửa: `| json | log_level="ERROR"`, hoặc gắn nhãn `level` ở Alloy rồi dùng `{compose_service="taskhub", level="ERROR"}`. Trong lab câu đó vẫn ra kết quả vì bộ lọc sau `| json` cũng xét nhãn stream — nhãn `level` đã có sẵn.
9. `sum by (compose_service) (count_over_time({compose_project="taskhub", level="ERROR"}[1m]))`
10. Metric từ log: khi app không xuất metric cho điều bạn cần đếm (số lần một thông báo lỗi cụ thể xuất hiện), truy vấn thỉnh thoảng. Prometheus: thứ đo thường xuyên, cần rẻ và nhanh (request rate, latency, tỉ lệ lỗi HTTP) — app đã xuất qua `/actuator/prometheus`.
11. `discovery.docker` (liệt kê container + nhãn meta), `discovery.relabel` (luật đổi nhãn), `loki.source.docker` (đọc log qua Docker API), `loki.process` (parse JSON, gắn nhãn `level`), `loki.write` (đẩy về Loki).
12. Xem câu hỏi bước 3 ở trên.
13. Không. `:ro` chỉ chặn ghi vào **file** socket trên filesystem; gọi API Docker qua socket vẫn hoạt động đầy đủ (tạo container privileged, mount `/`…) → vẫn tương đương root. Giảm rủi ro bằng cách giữ Alloy cập nhật, không publish UI, hoặc đọc file log thay vì dùng socket.
14. Không — EOL từ 02/03/2026 (trừ `lambda-promtail`). Hiểu ý tưởng, viết lại bằng Alloy; với hệ thống có sẵn dùng `alloy convert --source-format=promtail` (hoặc tạm chạy `--config.format=promtail`) rồi kiểm tra lại dashboard/alert dựa trên metric của Promtail.
15. `compactor.retention_enabled: true`, `compactor.delete_request_store`, `limits_config.retention_period: 168h`, index period 24h. Không cấu hình → giữ mãi → đầy ổ đĩa.

## Bài tập tự làm

### Bài 1 — Bỏ log healthcheck

Thêm vào **trong** `stage.match` của taskhub (trước `stage.json`):

```alloy
    stage.drop {
      expression          = ".*/actuator/health.*"
      drop_counter_reason = "healthcheck"
    }
```

Đo trước/sau (chạy trong 30 phút trước và 30 phút sau thay đổi):

```logql
sum(bytes_over_time({compose_service="taskhub"}[30m]))
```

Lưu ý: Spring Boot mặc định **không** log mỗi request; dòng chứa `/actuator/health` thường đến từ log WARN của health check hoặc từ access log nếu bạn bật. Nếu không có dòng nào khớp, kết quả không đổi — đó cũng là một quan sát đáng ghi (đừng tối ưu thứ không tồn tại). Log truy cập của **nginx** thì chắc chắn có — áp dụng tương tự cho service `nginx` bằng một `stage.match` khác.

### Bài 2 — App im lặng

```logql
absent_over_time({compose_service="taskhub"}[10m])
```

Trả 1 khi không có dòng nào trong 10 phút: app treo (deadlock), agent ngừng thu, hoặc container không còn. Không thay được `up == 0` vì: app có thể **chết nhưng vẫn in log lỗi** (không im lặng), hoặc **sống bình thường nhưng ít log** (đêm khuya, không có request → báo động giả). Hai tín hiệu bổ sung cho nhau; `up` đo trực tiếp "scrape được không".

### Bài 3 — Status của nginx

```alloy
  stage.match {
    selector = "{compose_service=\"nginx\"}"

    stage.regex {
      expression = "\" (?P<status>\\d{3}) "
    }
  }
```

Không thêm `stage.labels` → `status` chỉ là giá trị trích xuất trong pipeline (không thành nhãn). Truy vấn phía Loki tự parse:

```logql
sum(count_over_time({compose_service="nginx"} | regexp "\" (?P<status>\\d{3}) " | status=~"5.." [1m]))
```

Lý do không làm nhãn: `status` có khoảng vài chục giá trị — không quá tệ, nhưng nhân với mọi nhãn khác vẫn tăng số stream; và bạn đã có tỉ lệ 5xx từ Prometheus. Nếu nhóm lọc theo status rất thường xuyên, có thể chấp nhận nhãn **đã gom** (`status_class="5xx"`) — 5 giá trị.

### Bài 4 — Retention 3 ngày

Thêm vào `loki-config.yaml` (giữ nguyên `schema_config` có `period: 24h`):

```yaml
compactor:
  working_directory: /tmp/loki/compactor
  retention_enabled: true
  delete_request_store: filesystem

limits_config:
  retention_period: 72h
```

Lưu ý `limits_config` đã có sẵn trong file mẫu (`metric_aggregation_enabled`…) — **thêm khóa vào khối có sẵn**, đừng tạo khối `limits_config` thứ hai (YAML trùng khóa: khối sau ghi đè khối trước). Kiểm tra: `docker compose -p log08 restart loki && docker compose -p log08 logs --tail 30 loki` không có lỗi cấu hình. Điều kiện: index period phải là 24h.

### Bài 5 — Promtail → Alloy

Chạy công cụ chuyển đổi trong container (không cài lên máy):

```bash
docker run --rm -v "$PWD":/c grafana/alloy:v1.21.3 convert \
  --source-format=promtail --output=/c/converted.alloy /c/promtail-config.yaml
```

Điểm khác thường gặp: (1) `docker_sd_configs` thành `discovery.docker` + `discovery.relabel` + `loki.source.docker` với `relabel_rules`; (2) `pipeline_stages` thành các `stage.*` trong `loki.process`; tên component được sinh tự động khá dài — nên đổi tên cho dễ đọc. Chấm đạt khi bạn tự viết được bản tương đương và giải thích từng khác biệt.

### Bài 6 — Báo cáo

Không có đáp án duy nhất. Đạt khi: kết luận ở đầu ("chọn Loki"); số liệu RAM (Loki single-binary vài trăm MB so với OpenSearch tối thiểu ~1 GB heap + Dashboards), dung lượng (Loki nén chunk, OpenSearch thêm index); loại truy vấn chính của nhóm (theo service/thời gian/mức lỗi — hợp Loki); nêu rủi ro (tìm chuỗi tùy ý trên khoảng dài sẽ chậm) và khi nào xem lại quyết định (yêu cầu SIEM, tìm kiếm toàn văn thường xuyên).
