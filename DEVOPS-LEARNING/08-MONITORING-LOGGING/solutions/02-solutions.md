# Lời giải — 02. Metrics với Prometheus

> Chỉ mở sau khi đã tự làm. Bài: [02-metrics-prometheus.md](../02-metrics-prometheus.md)

## Mục lục

- [Thực hành mục 9](#thực-hành-mục-9)
- [Câu hỏi kiểm tra kiến thức (mục 13)](#câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Bài tập tự làm (mục 14)](#bài-tập-tự-làm-mục-14)

---

## Thực hành mục 9

**Bước 5.**

1. Mỗi vòng lặp gửi 4 request rồi ngủ 0,2 s. Mỗi `curl` tới app trên máy mất vài ms đến vài chục ms, nên một vòng mất khoảng 0,25–0,35 s → khoảng **11–16 req/s** cho `/api/**`. Q2 sẽ ra một con số trong khoảng đó, thấp hơn một chút ở đầu và cuối cửa sổ 5 phút (vì `rate` lấy trung bình cả khoảng thời gian có lẫn lúc chưa có traffic).
2. Thường là `POST /api/tasks` (có ghi database, chạy Flyway/JPA lần đầu chậm). Request 400 dừng ở bước validation nên rất nhanh; 404 chỉ một truy vấn theo khóa chính. Kết quả cụ thể phụ thuộc máy — quan trọng là bạn đọc được nhãn `uri`, `method`.
3. Dùng `sum by (status) (increase(http_server_requests_seconds_count{job="taskhub", status=~"4.."}[15m]))`. Chúng không làm tăng Q4 vì Q4 chỉ đếm `status=~"5.."`. 4xx là lỗi **của client** (gửi sai), không phải lỗi hệ thống — nhưng 4xx tăng đột biến vẫn đáng theo dõi riêng (client hỏng, bị dò quét).
4. Khi vòng lặp dừng, đồ thị **không** rơi thẳng xuống 0 mà dốc dần trong khoảng 5 phút, vì mỗi điểm là trung bình của 5 phút trước đó.
5. Giá trị counter chỉ tăng dần từ lúc app khởi động; nó trả lời "tổng từ trước tới nay", phụ thuộc thời điểm restart. Không đọc được "bây giờ nhanh hay chậm" từ đó, và khi app restart đồ thị rơi về 0 trông như sự cố.

**Bước 6.** `up{job="taskhub"} = 1` vì Prometheus vẫn scrape `/actuator/prometheus` thành công — endpoint này không cần database. Mọi request `/api/tasks` trả **500** sau khoảng 3 s (nhờ `HIKARI_CONNECTION_TIMEOUT=3000`), nên Q4 **tăng** — nhưng với cửa sổ `[5m]` và chỉ 30 request lỗi, Q4 chỉ khoảng vài % (chạy thử: ≈ 0,05) vì trong 5 phút đó còn hàng trăm request thành công của bước 4. Lặp vòng lâu hơn hoặc dùng `[1m]` thì Q4 mới tiến dần về 1. Vòng 30 request mất ~90 giây (mỗi request chờ 3 s). Kết luận: alert theo `up` **không** phát hiện được database chết; alert theo tỷ lệ 5xx thì có. (Health check `/actuator/health` cũng báo `DOWN` — Docker healthcheck và blackbox probe bắt được.)

**Bước 7.** `up{job="taskhub"} = 0` — target vẫn có trong cấu hình, scrape thất bại. Instant query `http_server_requests_seconds_count` **rỗng ngay**: series đã bị gắn stale marker khi scrape thất bại. Nhưng Q2 và Q4 **vẫn ra số** trong ~5 phút đầu (chạy thử xác nhận): `rate(...[5m])` là hàm trên range vector, vẫn dùng các sample *trước* stale marker. Khi cửa sổ không còn đủ 2 sample (~5 phút), Q2/Q4 thành **"no data"** — không bao giờ là 0. Hệ quả: alert theo tỷ lệ lỗi **im lặng** khi app chết hẳn → bắt buộc phải có alert `up == 0` (bài 03 `TaskhubDown`).

**Bước 8.** Thường thấy `http_server_requests_seconds_bucket` đứng đầu (mỗi tổ hợp method/uri/status × khoảng vài chục bucket `le`), tiếp theo là nhóm `jvm_*` và `node_*`. Một app nhỏ thường ra vài trăm tới vài nghìn series. Ví dụ 1.500 series, scrape 15 s → 100 sample/s → 7 ngày ≈ 604.800 × 100 × 2 B ≈ 121 MB (+ WAL).

**Bước 9.** `promtool` in `SUCCESS: ... is valid prometheus config file syntax` và kiểm tra cả `rules/recording.yml`. Sau reload, `count({__name__=~"jvm_buffer_.*"})` trả **rỗng chỉ sau một lần scrape** (chạy thử: ~15 giây): series có ở lần scrape trước mà vắng ở lần sau được Prometheus gắn **stale marker** ngay, nên instant query không còn thấy chúng (không phải chờ hết lookback 5 phút). Dữ liệu cũ vẫn nằm trong TSDB — query trên range (ví dụ `count_over_time(jvm_buffer_count_buffers[10m])`) vẫn thấy — điều này chứng minh `metric_relabel_configs` chặn **trước khi lưu**, không xóa dữ liệu cũ.

---

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Pull: server chủ động gọi target theo chu kỳ. Push: target tự gửi về server. Ưu điểm lớn nhất của pull: scrape thất bại là một **tín hiệu** rõ ràng (`up = 0`) — biết target chết hay không truy cập được. Với push, "không nhận được dữ liệu" có thể là target chết, mạng hỏng hoặc chỉ là không có gì để gửi.

**2.** Counter: tổng request (`http_server_requests_seconds_count`). Gauge: heap đang dùng (`jvm_memory_used_bytes`), số kết nối DB đang mở. Histogram: thời gian xử lý request có bucket (`..._bucket`). Summary: phân vị app tự tính khi cấu hình `management.metrics.distribution.percentiles` — dự án không dùng.

**3.** Giá trị tuyệt đối của counter phụ thuộc lúc app khởi động, không nói lên tốc độ hiện tại. `rate()` tính độ dốc mỗi giây; khi gặp giá trị giảm (counter về 0 lúc restart), nó coi như reset và cộng dồn tiếp, nên kết quả không bị âm hay sụt sai.

**4.** `_count` (số lần), `_sum` (tổng giây), `_max` (lớn nhất gần đây). `_bucket{le=...}` chỉ có khi bật `percentiles-histogram` (hoặc `slo`).

**5.** Histogram xuất **số đếm theo bucket** — cộng được giữa các instance rồi mới tính phân vị. Summary xuất **phân vị đã tính sẵn** trên từng instance; trung bình p95 của 3 instance không phải p95 của tổng thể. Tài liệu Prometheus ghi summary "Not aggregatable".

**6.**

```promql
  sum(rate(http_server_requests_seconds_count{job="taskhub", status=~"5.."}[5m]))
/
  sum(rate(http_server_requests_seconds_count{job="taskhub"}[5m]))
```

Phải `sum` trước để chia **tổng lỗi / tổng request**. Chia từng series (theo từng `uri`) rồi lấy trung bình sẽ cho endpoint ít traffic trọng số ngang endpoint nhiều traffic — sai về toán.

**7.** `histogram_quantile` dựa vào label `le` (cận trên của bucket) để nội suy. Gộp mà bỏ `le` thì mọi bucket bị cộng thành một số, không còn phân phối để tính. Tài liệu: phải giữ `le` trong mệnh đề `by` khi gộp classic histogram.

**8.** `avail` = chỗ user thường còn ghi được; `free` gồm cả phần dành riêng cho root (ext4 mặc định khoảng 5%). App chạy bằng user thường → alert theo `avail_bytes`.

**9.** `up = 1` (scrape không cần database). Phát hiện bằng tỷ lệ 5xx (Q4), `hikaricp_connections_pending` tăng, health check `/actuator/health` = DOWN (blackbox probe hoặc Docker healthcheck), hoặc exporter của PostgreSQL (`pg_up`).

**10.** Series của app đã stale, không còn sample → phép chia không có dữ liệu → kết quả rỗng, không phải 0. Alert dựa trên biểu thức rỗng thì **không bao giờ** kích hoạt. Thiết kế: luôn có alert `up == 0` (hoặc `absent(...)`) bên cạnh alert tỷ lệ lỗi.

**11.** Cardinality là số time series khác nhau. Không dùng `userId`, `email`, `requestId`, đường dẫn thật chứa ID — tập giá trị không giới hạn, mỗi giá trị tạo series mới chiếm RAM vĩnh viễn trong cửa sổ head block; Prometheus có thể bị OOMKilled.

**12.** Để số giá trị của `uri` hữu hạn (bằng số endpoint), tránh nổ cardinality, và để gộp được mọi request cùng loại.

**13.** `--config.file` và `--storage.tsdb.path`. `command:` thay toàn bộ CMD mặc định của image; thiếu `--storage.tsdb.path=/prometheus` thì Prometheus ghi vào thư mục mặc định khác — có thể không trùng chỗ volume được gắn.

**14.** Lifecycle API cho phép **bất kỳ ai gọi được cổng 9090** nạp lại cấu hình hoặc tắt Prometheus (`/-/quit`) mà không cần xác thực.

**15.** 2.000 series / 15 s ≈ 133 sample/s. 7 ngày = 604.800 s. 604.800 × 133 × 2 B ≈ 161 MB (cận trên ≈ 1–2 byte/sample → 80–160 MB), cộng WAL (tối thiểu 3 segment, tối đa 128 MB mỗi segment).

---

## Bài tập tự làm (mục 14)

**Bài 1.**

```promql
# Trung bình
  sum(rate(http_server_requests_seconds_sum{job="taskhub", uri!~"/actuator.*"}[5m]))
/
  sum(rate(http_server_requests_seconds_count{job="taskhub", uri!~"/actuator.*"}[5m]))

# p99
histogram_quantile(0.99,
  sum by (le) (rate(http_server_requests_seconds_bucket{job="taskhub", uri!~"/actuator.*"}[5m])))
```

Với vài phần trăm request chậm, trung bình gần như không đổi còn p99 nhảy vọt. Trung bình bị số đông request nhanh kéo xuống. Nhớ **xóa** đoạn `Thread.sleep` — không merge vào `main`.

**Bài 2.**

```yaml
management:
  metrics:
    distribution:
      slo:
        http.server.requests: 100ms,300ms,1s
```

(Bỏ `percentiles-histogram` để so sánh.) Số series `_bucket` giảm mạnh: mỗi tổ hợp label chỉ còn vài bucket (3 mốc + `+Inf`) thay vì vài chục. Tỷ lệ request dưới 300 ms:

```promql
  sum(rate(http_server_requests_seconds_bucket{job="taskhub", le="0.3"}[5m]))
/
  sum(rate(http_server_requests_seconds_count{job="taskhub"}[5m]))
```

Kiểm tra giá trị `le` **thật** trong UI trước khi viết matcher (Prometheus 3 chuẩn hóa dạng số thực; Micrometer xuất giây).

**Bài 3.**

```yaml
groups:
  - name: taskhub-latency
    rules:
      - record: job:http_server_requests:p95_5m
        expr: |
          histogram_quantile(0.95,
            sum by (job, le) (rate(http_server_requests_seconds_bucket{uri!~"/actuator.*"}[5m])))
```

Giữ `job` trong `by` để tên rule (mức `job`) đúng với nội dung. `promtool check rules rules/latency.yml` → `SUCCESS: 1 rules found`.

**Bài 4.** Cần: image exporter đã ghim tag thật, biến môi trường chuỗi kết nối tới `postgres:5432` với user chỉ đọc (lý tưởng là user riêng có quyền `pg_monitor`), job `scrape_configs` trỏ tới cổng của exporter. Metric thường gặp: `pg_up`, nhóm `pg_stat_database_*` (số backend), kích thước database (tên metric tùy phiên bản exporter — đọc `/metrics` của chính nó). Đạt khi giải thích được vì sao không dùng user `taskhub` của app.

**Bài 5.** `up{job="taskhub"}` đi từ **bên trong** Docker network, bỏ qua Nginx, Security Group, DNS, TLS. Probe từ bên ngoài đi đúng đường người dùng: Nginx chết, cấu hình proxy sai, SG chặn 80 hay chứng chỉ hết hạn đều làm probe thất bại trong khi `up` vẫn bằng 1.

**Bài 6.** Khác biệt chính: `external_labels: {env: dev}`, `--storage.tsdb.retention.time=7d` (có thể thêm `retention.size`), job `node` giữ `rslave`. Trên EC2, container node_exporter chạy trực tiếp trên kernel của máy thật, `/` của host là đĩa EBS → số đo đúng máy. Trên laptop, Docker Desktop chạy container trong một máy ảo Linux riêng → node_exporter đo máy ảo đó, không phải Windows hay WSL.
