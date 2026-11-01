# Lời giải — Break-fix Observability #1 (bf08)

> ⚠️ Chỉ đọc sau khi đã làm xong, hoặc đã kẹt quá 30 phút sau khi xem hết gợi ý. Bài: [labs/break-fix-01/README.md](../labs/break-fix-01/README.md)
> Mọi output bên dưới là **minh họa** — chữ chính xác có thể khác theo phiên bản. Hãy tìm **ý chính**.

## Mục lục

- [Tổng quan: 6 lỗi theo thứ tự lộ ra](#tổng-quan-6-lỗi-theo-thứ-tự-lộ-ra)
- [Ticket #8001](#ticket-8001)
- [Ticket #8002](#ticket-8002)
- [Ticket #8003](#ticket-8003)
- [Câu hỏi cuối bài](#câu-hỏi-cuối-bài)
- [Phương pháp chung](#phương-pháp-chung)

---

## Tổng quan: 6 lỗi theo thứ tự lộ ra

| # | Ticket | Khâu bị đứt | Lỗi | Vì sao im lặng |
|---|---|---|---|---|
| 1 | #8001 | Grafana → Prometheus | Data source dùng `http://localhost:9090` | Grafana vẫn chạy, chỉ báo lỗi khi có người mở |
| 2 | #8001 | Prometheus → app | Scrape `app:8080` (cổng HTTP) thay vì `app:8000` (cổng metrics) → `404` | `up == 0` đúng là tín hiệu, nhưng lỗi 3 khiến không rule nào bắt được nó |
| 3 | #8002 | Rule | `AppDown` lọc `up{job="demo-app"}` nhưng job thật tên `app` → biểu thức rỗng | Biểu thức rỗng là hợp lệ: không lỗi, không pending, không gì cả |
| 4 | #8002 | Alertmanager route | `severity: crit` không khớp route `critical\|warning` → rơi vào `blackhole` | Alert **có** trong Alertmanager, chỉ không đi đâu cả |
| 5 | #8003 | Docker → Alloy | Thiếu mount `/var/run/docker.sock` | Alloy vẫn "sống", chỉ ghi lỗi vào log của chính nó |
| 6 | #8003 | Alloy → Loki | URL push `/api/v1/push` thiếu tiền tố `/loki` → `404` | Bị lỗi 5 che: chưa có log nào để đẩy thì chưa thấy lỗi đẩy |

---

## Ticket #8001

### Lỗi 1 — Data source Grafana trỏ `localhost`

**Triệu chứng:** Connections → Data sources → Prometheus → **Save & test**:

```text
Post "http://localhost:9090/api/v1/query": dial tcp [::1]:9090: connect: connection refused
```

**Bằng chứng:** `cat grafana/provisioning/datasources/datasources.yaml` → `url: http://localhost:9090`. Trong container `grafana`, `localhost` là chính Grafana — không có gì nghe cổng 9090. Kiểm chứng từ trong container: `docker compose exec grafana wget -qO- http://prometheus:9090/-/healthy` trả `Prometheus Server is Healthy.`

**Sửa:**

```diff
   - name: Prometheus
     uid: prometheus
     type: prometheus
     access: proxy
-    url: http://localhost:9090
+    url: http://prometheus:9090
```

```bash
docker compose restart grafana     # provisioning chỉ được đọc khi Grafana khởi động
```

**Phòng tránh:** quy ước "trong mạng Compose luôn dùng **tên service**"; checklist review provisioning; có thể thêm bước smoke test gọi `/api/datasources/uid/<uid>/health` sau mỗi lần triển khai (chính là mục 2 của `verify.sh`).

### Lỗi 2 — Scrape nhầm cổng

**Triệu chứng:** Status → Targets, job `app`:

```text
State: DOWN   Error: server returned HTTP status 404 Not Found
```

**Bằng chứng:**

```bash
docker compose exec prometheus wget -qO- http://app:8080/metrics      # wget: server returned error: HTTP/1.0 404 Not Found
docker compose exec prometheus wget -qO- http://app:8000/metrics | head -3
# # HELP python_gc_objects_collected_total Objects collected during gc
# # TYPE python_gc_objects_collected_total counter
# ...
```

`404` (không phải `connection refused`) nghĩa là **có** server trả lời ở 8080 — đó là cổng HTTP của app, nó không biết `/metrics`. Thư viện `prometheus_client` mở metrics ở cổng **riêng** (`start_http_server(8000)`).

**Sửa:**

```diff
   - job_name: app
     static_configs:
-      - targets: ["app:8080"]
+      - targets: ["app:8000"]
```

```bash
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
curl -X POST 127.0.0.1:19090/-/reload
```

Sau ≤ 15 giây target `app` chuyển **UP**. `verify.sh`: mục 1 và 2 đạt.

---

## Ticket #8002

### Lỗi 3 — Rule lọc theo job không tồn tại

**Triệu chứng:** dừng app 5 phút, trang **Alerts** không có `AppDown` ở trạng thái pending hay firing; Status → Rules hiện rule với trạng thái `OK`, không lỗi.

**Bằng chứng:** dán từng phần biểu thức vào Query:

```text
up{job="demo-app"}     → Empty query result
up                     → up{instance="app:8000", job="app"} 1 ...
```

Nhãn `job` lấy từ `job_name` trong `scrape_configs` — ở đây là `app`. Biểu thức rỗng không phải lỗi cú pháp nên `promtool check rules` **vẫn qua**. Đây là lý do cần unit test cho rule (`promtool test rules`, phần B của checkpoint).

**Sửa:**

```diff
       - alert: AppDown
-        expr: up{job="demo-app"} == 0
+        expr: up{job="app"} == 0
```

Reload Prometheus. Thử lại: `docker compose stop app` → sau ~15–30 giây `AppDown` **pending**, sau 1 phút **firing** (đỏ). `verify.sh` mục 4 đạt.

> Cẩn thận hơn nữa: `up{job="app"} == 0` không bắt được trường hợp target **biến mất** hẳn khỏi cấu hình (không còn series `up`). Bổ sung `absent(up{job="app"})` nếu muốn bắt cả trường hợp đó.

### Lỗi 4 — Nhãn `severity` sai quy ước

**Triệu chứng:** `AppDown` đỏ trên Prometheus, **có** trong Alertmanager UI, nhưng `curl -s 127.0.0.1:15001/` chỉ có `Watchdog`.

**Bằng chứng:**

```bash
docker compose exec alertmanager amtool config routes test \
  --config.file=/etc/alertmanager/alertmanager.yml alertname=AppDown severity=crit
# blackhole
docker compose exec alertmanager amtool config routes test \
  --config.file=/etc/alertmanager/alertmanager.yml alertname=Watchdog severity=warning
# webhook-debug
```

Route con chỉ khớp `severity =~ "critical|warning"`; `crit` không khớp → về receiver gốc `blackhole` — receiver **không có** cấu hình gửi đi, Alertmanager nhận rồi "nuốt" mất.

**Sửa (sửa rule, không sửa route):**

```diff
         for: 1m
         labels:
-          severity: crit
+          severity: critical
```

Vì sao không nới route (`severity =~ ".+"`)? Route là **hợp đồng** về mức độ nghiêm trọng của cả team. Nới route để "hứng" giá trị sai sẽ khiến lỗi chính tả tiếp theo cũng lọt qua. Cách phòng tránh tốt hơn: unit test rule kiểm tra `exp_labels` có `severity: critical`, và dùng receiver mặc định là một kênh **có người đọc** (ví dụ kênh "unrouted") thay vì `blackhole` để cảnh báo lạc đường vẫn được nhìn thấy.

Reload Prometheus, rồi `bash verify.sh --e2e` → 8/8. Bật app lại, webhook nhận thêm bản tin `"status": "resolved"` (do `send_resolved: true`).

---

## Ticket #8003

### Lỗi 5 — Alloy không thấy Docker socket

**Triệu chứng:** `docker compose logs --tail 30 alloy`:

```text
level=error msg="Unable to refresh target groups" component_path=/ component_id=discovery.docker.bf08
  err="error while listing containers: failed to connect to the docker API at unix:///var/run/docker.sock; check if the path is correct and if the daemon is running: dial unix /var/run/docker.sock: connect: no such file or directory"
```

**Bằng chứng:** `docker compose exec alloy ls -l /var/run/docker.sock` → `No such file or directory`. Socket là file **của host**; container chỉ thấy nó khi được mount.

**Sửa:**

```diff
   alloy:
     ...
     volumes:
       - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
+      - /var/run/docker.sock:/var/run/docker.sock:ro
```

```bash
docker compose up -d alloy        # đổi compose.yaml → up -d để tạo lại container (restart không đủ)
```

**Đánh đổi bảo mật:** ai điều khiển được socket Docker thì điều khiển được cả host (tạo container mount `/`). `:ro` chỉ chặn **ghi file socket**, không chặn gọi API. Chấp nhận được ở đây vì Alloy là image chính thức, ghim phiên bản, không mở cổng ra ngoài. Cách thay thế: mount `/var/lib/docker/containers` (chỉ đọc) và dùng `loki.source.file` đọc file log JSON của Docker — không cần socket nhưng mất nhãn Compose (phải tự suy từ đường dẫn).

### Lỗi 6 — URL push của Loki sai

**Triệu chứng:** sau khi sửa lỗi 5, log Alloy đổi sang:

```text
level=error msg="final error sending batch, no retries left, dropping data" component_id=loki.write.local component=endpoint host=loki:3100 status=404 error="server returned HTTP status 404 Not Found (404): 404 page not found"
```

**Bằng chứng:** API push của Loki là `POST /loki/api/v1/push`. Thử nhanh từ máy bạn:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST 127.0.0.1:13100/api/v1/push        # 404
curl -s -o /dev/null -w '%{http_code}\n' -X POST 127.0.0.1:13100/loki/api/v1/push   # 4xx khác (thân request rỗng) — tức là đường dẫn đúng
```

**Sửa:**

```diff
 loki.write "local" {
   endpoint {
-    url = "http://loki:3100/api/v1/push"
+    url = "http://loki:3100/loki/api/v1/push"
   }
 }
```

```bash
docker compose restart alloy
curl -sG 127.0.0.1:13100/loki/api/v1/query_range --data-urlencode 'query={compose_service="app"}' --data-urlencode limit=3
curl -s 127.0.0.1:18088/fail >/dev/null
# Grafana Explore: {compose_service="app", level="error"}  → dòng "request" có status 500
```

**Phòng tránh:** Prometheus đã scrape Alloy — thêm alert dựa trên metric lỗi gửi của `loki.write` (xem các metric `loki_write_*` ở `http://alloy:12345/metrics`), và alert "không có log từ app trong 10 phút" bằng Loki ruler/Grafana alerting.

---

## Câu hỏi cuối bài

*"Chỉ được thêm một alert để phát hiện 'hệ thống giám sát hỏng mà không ai biết'?"* — Đáp án tốt: **Watchdog / dead man's switch** gửi tới một dịch vụ **bên ngoài** hệ thống giám sát, và dịch vụ đó báo động khi **ngừng nhận** tín hiệu (ví dụ một dịch vụ heartbeat, hoặc CloudWatch alarm trên metric tự gửi). Watchdog gửi vào chính kênh của bạn chỉ chứng minh "đường ống còn thông khi bạn nhìn"; giá trị thật nằm ở chỗ **sự im lặng** của nó được phát hiện tự động. Lưu ý: Watchdog không bắt được lỗi 3 và 4 (rule riêng hỏng) — những lỗi đó cần unit test rule và diễn tập dừng dịch vụ có kiểm soát.

## Phương pháp chung

1. **Vẽ đường đi của dữ liệu** trước khi sửa: metrics (app → Prometheus → rule → Alertmanager → receiver) và logs (app → Docker → Alloy → Loki → Grafana).
2. **Chứng minh từng khâu** bằng công cụ của chính khâu đó: Targets, Query từng phần biểu thức, `amtool config routes test`, log của Alloy, API của Loki.
3. **Lỗi im lặng thường che lỗi sau** (lỗi 5 che lỗi 6, lỗi 3 che lỗi 4). Sửa xong một lỗi, **quay lại bước 2**, đừng giả định là xong.
4. **Kiểm tra tĩnh không đủ:** `promtool check` và `amtool check-config` qua hết mà hệ thống vẫn hỏng. Cần kiểm thử **hành vi**: unit test rule, và diễn tập thật (`verify.sh --e2e`).
