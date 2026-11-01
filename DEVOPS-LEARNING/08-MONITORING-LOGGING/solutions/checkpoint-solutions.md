# Lời giải — Checkpoint Giai đoạn 8

> ⚠️ Chỉ mở sau khi đã **commit bài làm** của bạn. Đề bài: [checkpoint.md](../checkpoint.md)
> Output là **minh họa** — chữ chính xác có thể khác theo phiên bản.

## Mục lục

- [Phần A — Đáp án gợi ý](#phần-a--đáp-án-gợi-ý)
- [Phần B — Bản tham khảo](#phần-b--bản-tham-khảo)
- [Phần C — Từng ticket](#phần-c--từng-ticket)

---

## Phần A — Đáp án gợi ý

Chấm theo **bản chất**, không theo câu chữ.

**1. Monitoring / logging / observability.** Monitoring = theo dõi những chỉ số **biết trước** là quan trọng và cảnh báo khi vượt ngưỡng ("taskhub có đang trả lời không, tỷ lệ 5xx bao nhiêu?"). Logging = bản ghi chi tiết **từng sự kiện** ("request `abc123` lúc 10:03 lỗi vì sao, stack trace là gì?"). Observability = khả năng trả lời cả những câu hỏi **chưa lường trước** bằng cách kết hợp metrics, logs, traces ("vì sao chỉ người dùng gọi `PUT /api/tasks` sau 18h mới chậm?"). Monitoring là thứ bạn làm; observability là tính chất của hệ thống.

**2. Golden signals.** Latency: `histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket[5m])))`. Traffic: `sum(rate(http_server_requests_seconds_count[5m]))`. Errors: tỷ lệ `status=~"5.."` trên tổng `http_server_requests_seconds_count`. Saturation: CPU/RAM/disk từ node_exporter (`node_filesystem_avail_bytes`, `node_memory_MemAvailable_bytes`), heap JVM (`jvm_memory_used_bytes{area="heap"}`), connection pool (`hikaricp_connections_active`). (Tên metric Micrometer chính xác xem `/actuator/prometheus` của bạn.)

**3. Counter/gauge/histogram.** Counter chỉ tăng (hoặc về 0 khi restart): số request, số lỗi. Gauge lên xuống tự do: RAM, request đang xử lý. Histogram đếm quan sát vào các **bucket** (`_bucket{le=...}`, `_sum`, `_count`) để tính phân vị phía server. `rate()` tính tốc độ tăng mỗi giây của counter; với gauge thì "tốc độ tăng" vô nghĩa (dùng `deriv()`/`delta()` nếu cần). Counter về 0 khi app restart; `rate()` nhận ra giá trị giảm là **reset** và cộng bù nên kết quả không bị âm.

**4. rate/irate/increase và cửa sổ.** `rate` = tốc độ trung bình mỗi giây trên cả cửa sổ (mượt, dùng cho alert và dashboard). `irate` = chỉ dùng **2 mẫu cuối** (nhạy, dùng cho đồ thị zoom ngắn, không dùng cho alert). `increase` = `rate × độ dài cửa sổ` (tổng tăng trong cửa sổ). Cần **ít nhất 2 mẫu** trong cửa sổ mới tính được; scrape 15s thì cửa sổ 10s chứa tối đa 1 mẫu → rỗng. Quy tắc thường dùng: cửa sổ **≥ 4 lần** `scrape_interval` (15s → tối thiểu 1m) để chịu được một lần scrape lỡ. *(bắt buộc: phải nêu được "cần ≥ 2 mẫu" và hệ quả rỗng)*

**5. Phân vị.** Trung bình che mất đuôi: 95% request 50ms + 5% request 5s vẫn cho trung bình ~0,3s "trông ổn", trong khi 1/20 người dùng chờ 5 giây. p95: `histogram_quantile(0.95, sum by (le) (rate(x_bucket[5m])))`. `histogram_quantile` cần nhãn `le` để biết bucket nào là bucket nào; `sum(...)` không có `by (le)` **xóa** nhãn `le` → không còn histogram → kết quả rỗng. Không được lấy trung bình các p95 của từng instance; phải cộng bucket rồi mới tính phân vị.

**6. Cardinality.** Số chuỗi thời gian (Prometheus) hay số stream (Loki) khác nhau = tích số giá trị của mọi label. `user_id`/`request_id` có số giá trị không giới hạn → mỗi giá trị một series/stream → tốn RAM, index phình, truy vấn chậm, chạm giới hạn và bị từ chối ghi. Loki chỉ **đánh index label**; nội dung log được lưu nén và quét khi truy vấn. Label = vài chiều ít giá trị dùng để chọn stream (`compose_service`, `level`); thứ chi tiết để trong nội dung. Tìm một request: `{compose_service="app"} |= "abc123"` (lọc chuỗi, nhanh) hoặc `{compose_service="app"} | json | request_id="abc123"`. *(bắt buộc: phân biệt label/nội dung và viết được LogQL lọc theo nội dung)*

**7. Pull và `up`.** Prometheus chủ động gọi `/metrics` của từng target theo chu kỳ. Mỗi lần scrape nó tự ghi `up{job,instance}` = 1 nếu scrape thành công, 0 nếu thất bại. Ba nguyên nhân DOWN: `connection refused` (không có gì nghe cổng đó: sai cổng, app chết), `context deadline exceeded` (timeout: firewall/SG chặn, app treo), `server returned HTTP status 404` (có server nhưng sai đường dẫn/cổng metrics), ngoài ra lỗi DNS `no such host` (sai tên service).

**8. Alert tốt.** Cảnh báo **người dùng đang bị ảnh hưởng** (triệu chứng: tỷ lệ lỗi, độ trễ, dịch vụ không trả lời) thay vì mọi nguyên nhân có thể (CPU 90% chưa chắc ai bị ảnh hưởng). `for:` lọc nhiễu thoáng qua. `severity` quyết định đường đi (đánh thức người trực hay chỉ ghi kênh). `runbook_url` cho người nhận biết làm gì tiếp. Alert fatigue: quá nhiều cảnh báo không cần hành động → con người bỏ qua cả cảnh báo thật. Tránh: mỗi alert phải **cần hành động**, xóa alert không ai xử lý, nhóm/ức chế cảnh báo hệ quả.

**9. Alertmanager.** Grouping gom nhiều alert liên quan vào một thông báo. Routing chọn receiver theo nhãn. Inhibition: khi alert A firing thì tắt alert B (hệ quả của A). Silence: tắt tạm thời có thời hạn (bảo trì). Inhibit rule đúng cho taskhub: `source_matchers: [alertname="TaskhubDown"]`, `target_matchers: [alertname=~"HighErrorRate|HighLatencyP95"]`, `equal: [job]` (nếu cả hai có nhãn `job`). Inhibit quá rộng (như ở ck08: Watchdog luôn firing ức chế mọi severity) **âm thầm** nuốt mọi cảnh báo, trong khi bạn vẫn tin "hệ thống có alert" — tệ hơn không có alert vì tạo cảm giác an toàn giả.

**10. Who watches the watcher.** EC2 chết thì Prometheus/Alertmanager chết theo — không ai gửi cảnh báo. v5 giữ CloudWatch alarm `StatusCheckFailed` (+ email SNS) chạy **ngoài** máy như người canh độc lập. Watchdog chứng minh đường ống cảnh báo thông; nếu gửi Watchdog tới một dịch vụ bên ngoài biết báo động khi **ngừng** nhận (dead man's switch), thì cả trường hợp "bộ giám sát chết" cũng được phát hiện.

**11. RPO/RTO.** RPO = lượng dữ liệu tối đa chấp nhận mất (đo bằng thời gian). RTO = thời gian tối đa chấp nhận để khôi phục dịch vụ. Backup 02:00, hỏng 18:00 → mất tối đa **16 giờ** dữ liệu (RPO thực tế ≈ 24h vì có thể hỏng ngay trước 02:00 hôm sau). RTO gồm: phát hiện, quyết định restore, dựng máy/volume mới, tải file dump từ S3, `pg_restore`, kiểm tra, chuyển app sang dữ liệu mới, smoke test. Giảm RPO xuống 15 phút: backup thường xuyên hơn (pg_dump mỗi 15 phút — chỉ hợp với DB nhỏ), **WAL archiving + PITR** (pgBackRest, WAL-G), hoặc RDS với automated backup (PITR tới vài phút gần nhất). *(bắt buộc: định nghĩa đúng và tính đúng 16h)*

**12. Diễn tập restore.** Backup có thể hỏng âm thầm (file rỗng, sai database, thiếu quyền, phiên bản không tương thích) — chỉ restore thật mới chứng minh được. Các bước: chọn bản backup → tải về → `pg_restore` vào database **mới** (`taskhub_restore`) → kiểm tra số dòng/bản ghi mới nhất → đo thời gian (RTO thật) → ghi kết quả → xóa database tạm. Restore vào DB mới để không phá dữ liệu hiện tại nếu backup hỏng, và để so sánh. `-Fc` (custom format) đã nén, `pg_restore` chọn được đối tượng, chạy song song (`-j`), `--clean`; dạng SQL thường chỉ chạy lại bằng `psql`, khó chọn lọc.

**13. Mitigate trước.** Người dùng đang bị ảnh hưởng từng phút; nguyên nhân gốc có thể mất hàng giờ. Rollback/tắt tính năng khôi phục dịch vụ trước, điều tra sau (dữ liệu vẫn còn trong log/metrics). Vai trò: incident commander điều phối, quyết định, giữ mọi người khỏi cùng sửa một chỗ; người liên lạc cập nhật cho người dùng/sếp để người sửa không bị ngắt quãng. Team 2–3 người vẫn cần tách "người quyết" và "người làm" để tránh hỗn loạn.

**14. Postmortem blameless.** Gồm: tóm tắt, tác động (bao lâu, ai bị ảnh hưởng), dòng thời gian, nguyên nhân gốc (5 whys), điều gì làm tốt / chưa tốt, action items có người phụ trách và hạn. Không đổ lỗi → mọi người khai thật → tìm ra lỗ hổng **hệ thống** (con người luôn mắc lỗi; hệ thống tốt phải chịu được lỗi). Action item tốt: "Thêm unit test `promtool test rules` cho mọi alert, chạy trong CI — phụ trách: Phương — hạn 15/2". Tồi: "Cẩn thận hơn khi viết rule" (không đo được, không ai phụ trách).

---

## Phần B — Bản tham khảo

Một cách làm; cách khác vẫn đạt nếu thỏa R1–R10.

### `app/app.py` (phần thay đổi)

```python
import os
from prometheus_client import Counter, Gauge, Histogram, start_http_server

KNOWN_PATHS = {"/", "/fail", "/slow", "/order"}
ORDERS = Counter("demo_orders_total", "So don hang theo ket qua", ["result"])
INFLIGHT = Gauge("demo_inflight_requests", "So request dang duoc xu ly")
FAIL_RATIO = float(os.environ.get("ORDER_FAIL_RATIO", "0.05"))

for result in ("success", "failed"):   # R1: tạo series = 0 ngay khi khởi động
    ORDERS.labels(result=result)


class Handler(BaseHTTPRequestHandler):
    @INFLIGHT.track_inprogress()         # R2: +1 khi vào, -1 khi ra (kể cả khi lỗi)
    def do_GET(self):
        ...
        elif path == "/order":
            result = "failed" if random.random() < FAIL_RATIO else "success"
            status = 502 if result == "failed" else 200
            body = b"order failed\n" if result == "failed" else b"order ok\n"
            ORDERS.labels(result=result).inc()
            log("error" if result == "failed" else "info", "order", result=result)
        ...
```

### `compose.yaml` (phần thêm)

```yaml
  app:
    # ... giữ nguyên, thêm:
    environment:
      ORDER_FAIL_RATIO: ${ORDER_FAIL_RATIO:-0.05}

  loadgen:
    build: ./loadgen
    image: bf08-loadgen:local
    depends_on:
      - app
    mem_limit: 64m
    restart: unless-stopped
```

`loadgen/loadgen.py`: vòng lặp `urllib.request.urlopen("http://app:8080/order")` bắt `HTTPError` (502 là cố ý), `time.sleep(0.5)`; Dockerfile `python:3.12-slim`, `USER nobody`.

Đổi tỷ lệ lỗi (R9): `ORDER_FAIL_RATIO=0.3 docker compose up -d app` → chờ ~6–7 phút (rate 5m + `for` 5m) → trả về `docker compose up -d app` (không đặt biến → 0,05).

### `prometheus/rules.yml` (nhóm thêm)

```yaml
  - name: bf08-orders
    rules:
      - record: job:demo_order_failure_ratio:rate5m
        expr: |
          sum by (job) (rate(demo_orders_total{result="failed"}[5m]))
            / sum by (job) (rate(demo_orders_total[5m]))

      - alert: OrderFailureRatioHigh
        expr: job:demo_order_failure_ratio:rate5m > 0.10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Tỷ lệ đơn hàng thất bại trên 10% trong 5 phút"
          runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/order-failures.md"
```

Tên recording rule theo quy ước `level:metric:operations`: `job` = nhãn còn giữ, `demo_order_failure_ratio` = ý nghĩa, `rate5m` = phép tính.

### `prometheus/tests.yml`

```yaml
rule_files:
  - rules.yml

evaluation_interval: 1m

tests:
  # (a) 20 lỗi / 100 đơn mỗi phút → tỷ lệ 0,2 → phải cảnh báo
  - interval: 1m
    input_series:
      - series: 'demo_orders_total{job="app", instance="app:8000", result="success"}'
        values: '0+80x20'
      - series: 'demo_orders_total{job="app", instance="app:8000", result="failed"}'
        values: '0+20x20'
    promql_expr_test:
      - expr: job:demo_order_failure_ratio:rate5m
        eval_time: 15m
        exp_samples:
          - labels: 'job:demo_order_failure_ratio:rate5m{job="app"}'
            value: 0.2
    alert_rule_test:
      - eval_time: 15m
        alertname: OrderFailureRatioHigh
        exp_alerts:
          - exp_labels:
              severity: warning
              job: app
            exp_annotations:
              summary: "Tỷ lệ đơn hàng thất bại trên 10% trong 5 phút"
              runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/order-failures.md"

  # (b) 5 lỗi / 100 đơn → tỷ lệ 0,05 → im lặng
  - interval: 1m
    input_series:
      - series: 'demo_orders_total{job="app", instance="app:8000", result="success"}'
        values: '0+95x20'
      - series: 'demo_orders_total{job="app", instance="app:8000", result="failed"}'
        values: '0+5x20'
    alert_rule_test:
      - eval_time: 15m
        alertname: OrderFailureRatioHigh
        exp_alerts: []
```

```bash
cd ~/devops-lab/08-monitoring/bf08/prometheus
docker run --rm -v "$PWD:/w:ro" -w /w --entrypoint promtool prom/prometheus:v3.15.1 test rules tests.yml
# Unit Testing:  tests.yml
#   SUCCESS
```

Ghi chú: `values: '0+80x20'` = bắt đầu 0, tăng 80 mỗi bước, 20 bước. `exp_annotations` phải khớp **toàn bộ** annotation của alert, nên annotation có template (`{{ $value }}`) sẽ khó test hơn — một lý do để `summary` ngắn và tĩnh.

### Dashboard provision từ file (R7, R8)

`grafana/provisioning/dashboards/provider.yaml`:

```yaml
apiVersion: 1

providers:
  - name: bf08
    folder: bf08
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards/json
```

`grafana/provisioning/dashboards/json/orders.json` (rút gọn — mỗi panel cần `type`, `title`, `datasource`, `targets`, `gridPos`):

```json
{
  "uid": "bf08-orders",
  "title": "bf08 — Đơn hàng",
  "schemaVersion": 39,
  "time": { "from": "now-30m", "to": "now" },
  "panels": [
    {
      "type": "timeseries", "title": "Đơn hàng/giây theo kết quả",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
      "targets": [{ "refId": "A", "expr": "sum by (result) (rate(demo_orders_total[1m]))", "legendFormat": "{{result}}" }]
    },
    {
      "type": "timeseries", "title": "Tỷ lệ đơn thất bại (5 phút)",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "x": 12, "y": 0, "w": 12, "h": 8 },
      "fieldConfig": {
        "defaults": {
          "unit": "percentunit",
          "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }, { "color": "red", "value": 0.1 }] },
          "custom": { "thresholdsStyle": { "mode": "line" } }
        },
        "overrides": []
      },
      "targets": [{ "refId": "A", "expr": "job:demo_order_failure_ratio:rate5m" }]
    },
    {
      "type": "stat", "title": "Request đang xử lý",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "x": 0, "y": 8, "w": 6, "h": 6 },
      "targets": [{ "refId": "A", "expr": "sum(demo_inflight_requests)" }]
    },
    {
      "type": "logs", "title": "Đơn thất bại",
      "datasource": { "type": "loki", "uid": "loki" },
      "gridPos": { "x": 6, "y": 8, "w": 18, "h": 10 },
      "targets": [{ "refId": "A", "expr": "{compose_service=\"app\"} | json | msg=\"order\" | result=\"failed\"" }]
    }
  ]
}
```

`docker compose restart grafana`. Grafana tự nâng `schemaVersion` khi mở dashboard — bình thường.

**Kiểm thử 5 (vì sao khởi tạo series bằng 0):** nếu chưa có đơn lỗi nào, series `result="failed"` **không tồn tại**. `rate(demo_orders_total{result="failed"}[5m])` trả rỗng → phép chia trả rỗng → panel trống và alert không đánh giá được, thay vì hiện tỷ lệ 0. Tệ hơn: khi đơn lỗi đầu tiên xuất hiện, series mới bắt đầu từ 1 và `rate()` không thấy bước tăng từ 0 lên 1 → đếm thiếu. Khởi tạo bằng 0 giúp mọi biểu thức luôn có dữ liệu.

**Lưu ý phụ:** `/order` trả 502 nên `HighErrorRate` (tính mọi 5xx) cũng có thể firing khi `ORDER_FAIL_RATIO=0.3`. Ghi vào nhật ký: đây là ví dụ hai alert chồng nhau — ứng viên cho một inhibit rule, hoặc cho việc định nghĩa lại `HighErrorRate` chỉ tính lỗi hệ thống.

---

## Phần C — Từng ticket

### 🎫 #8101 — Cửa sổ `rate` ngắn hơn chu kỳ scrape

**Chứng minh:**

```text
rate(demo_requests_total[10s])               → Empty query result
count_over_time(demo_requests_total[10s])    → mỗi series 0 hoặc 1 mẫu
rate(demo_requests_total[1m])                → có giá trị
```

`scrape_interval: 15s` → cửa sổ 10 giây chứa tối đa **1** mẫu; `rate()` cần ít nhất 2 → rỗng → phép chia rỗng → rule không bao giờ pending. Không có lỗi nào được ghi: rỗng là hợp lệ.

**Sửa** (giữ ngưỡng 5% và `for: 2m`):

```diff
-          sum(rate(demo_requests_total{status=~"5.."}[10s]))
-            / sum(rate(demo_requests_total[10s])) > 0.05
+          sum(rate(demo_requests_total{status=~"5.."}[1m]))
+            / sum(rate(demo_requests_total[1m])) > 0.05
```

`curl -X POST 127.0.0.1:19190/-/reload`. "Phản hồi nhanh" đúng nghĩa đến từ cửa sổ hợp lý (1m = 4× scrape) và `for` ngắn, không phải từ cửa sổ nhỏ hơn dữ liệu.

### 🎫 #8102 — `histogram_quantile` thiếu `by (le)`

**Chứng minh:**

```text
sum(rate(demo_request_duration_seconds_bucket[1m]))            → 1 series, KHÔNG có nhãn le
sum by (le) (rate(demo_request_duration_seconds_bucket[1m]))   → nhiều series, mỗi le một series
```

`histogram_quantile` cần nhãn `le` để biết ranh giới các bucket. `sum` không `by (le)` cộng mọi bucket lại thành một con số vô nghĩa → kết quả rỗng. (Prometheus UI có thể hiện thêm một annotation cảnh báo thiếu `le`.)

**Sửa:**

```diff
           histogram_quantile(0.95,
-            sum(rate(demo_request_duration_seconds_bucket[1m]))
+            sum by (le) (rate(demo_request_duration_seconds_bucket[1m]))
           ) > 0.3
```

Dán phần trong (bỏ `> 0.3`) vào Query → khoảng 0,5–0,75 (10% request chậm 0,4–0,7s rơi vào bucket `le="0.75"`; nội suy tuyến tính trong bucket nên con số chỉ là ước lượng — đặc điểm của histogram cổ điển).

### 🎫 #8103 — Inhibit rule nuốt mọi cảnh báo

**Chứng minh:**

- Alertmanager UI → tích ô **Inhibited** → thấy `HighErrorRate`, `HighLatencyP95` (và cả `AppDown` nếu có) ở trạng thái bị ức chế.
- `docker compose exec alertmanager amtool alert query --inhibited --alertmanager.url=http://localhost:9093` liệt kê các alert bị ức chế.
- Đọc `inhibit_rules`: nguồn là `Watchdog` — alert **luôn** firing; đích là `severity =~ ".+"` — mọi alert; không có `equal` → tài liệu Alertmanager coi nhãn thiếu bằng nhãn rỗng, nên điều kiện "bằng nhau" luôn đúng. Kết quả: mọi alert có severity đều bị ức chế, **trừ chính Watchdog** (Alertmanager không cho một alert khớp cả hai phía tự ức chế mình) → webhook chỉ nhận Watchdog, tạo ảo giác "đường ống ổn".

**Sửa** — giữ ý định ban đầu "app chết thì đừng báo thêm hệ quả":

```diff
 inhibit_rules:
   - source_matchers:
-      - alertname = Watchdog
+      - alertname = AppDown
     target_matchers:
-      - severity =~ ".+"
+      - alertname =~ "HighErrorRate|HighLatencyP95"
```

`docker compose restart alertmanager` (hoặc `curl -X POST 127.0.0.1:19193/-/reload`). Trong vài phút webhook nhận cả hai alert. Nếu các alert có chung nhãn định danh (ví dụ `job`), thêm `equal: [job]` để chỉ ức chế đúng dịch vụ đang chết — ở đây các rule đã `sum()` mất nhãn `job` nên không dùng được; ghi nhận xét này vào nhật ký.

### 🎫 #8104 — `request_id` làm label Loki

**Chứng minh:**

```bash
curl -s 127.0.0.1:13110/loki/api/v1/label/request_id/values | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'
# vài nghìn giá trị và tăng ~5 mỗi giây
curl -s 127.0.0.1:13110/loki/api/v1/labels
# {"status":"success","data":["compose_project","compose_service","container","level","request_id",...]}
docker compose logs --tail 20 alloy      # chỉ thấy lỗi 429 khi đã chạm giới hạn 5000 stream (~15–20 phút)
```

Mỗi giá trị label mới = một **stream** mới trong Loki, với index và chunk riêng. Loadgen ~5 request/giây → ~300 stream mới mỗi phút → index phình, truy vấn chậm, và khi chạm giới hạn số stream đang hoạt động của tenant, Loki **từ chối ghi** (HTTP 429) — log bị mất. Với Loki 3.7.9, `curl -s 127.0.0.1:13110/config | grep max_global_streams_per_user` cho `5000` (giới hạn stream đang hoạt động mặc định của một tenant). Ở ~5 stream mới/giây, mất khoảng 15–20 phút mới chạm giới hạn — nên trong 5 phút đầu bạn **chưa** thấy 429 (đã chạy thử: sau ~5 phút có ~1.400 giá trị `request_id`, chưa có 429). Bằng chứng chính vì vậy là số giá trị của label, không phải lỗi 429.

**Sửa:**

```diff
   stage.json {
-    expressions = { level = "level", request_id = "request_id" }
+    expressions = { level = "level" }
   }

   stage.labels {
-    values = { level = "", request_id = "" }
+    values = { level = "" }
   }
```

`docker compose restart alloy`. Tìm một request:

```logql
{compose_service="app"} |= "3f9a1c2b7d4e"                          # lọc chuỗi — nhanh nhất
{compose_service="app"} | json | request_id="3f9a1c2b7d4e"          # lọc theo trường JSON — chính xác
```

Stream cũ (đã có `request_id`) vẫn còn trong khoảng giữ dữ liệu, và `/loki/api/v1/labels` vẫn liệt kê `request_id` khoảng **30 phút** sau khi sửa (đã chạy thử: API này trả nhãn của mọi stream còn trong bộ nhớ ingester cho tới khi flush theo `chunk_idle_period`, dù đã truyền `start`). Vì vậy `verify.sh` mục 6 không dùng API `labels` mà lấy log **60 giây gần nhất** bằng `query_range` và xem nhãn của các stream có dòng mới — chờ khoảng 1 phút sau khi restart Alloy rồi chạy lại.

**Bài học chung của phần C:** cả 4 lỗi đều **qua mọi kiểm tra cú pháp** (`promtool check`, `amtool check-config`, Alloy khởi động bình thường). Chỉ có kiểm thử hành vi — unit test rule, xem trạng thái Inhibited, đo cardinality — mới bắt được chúng.
