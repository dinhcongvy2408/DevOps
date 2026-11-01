# Checkpoint Giai đoạn 8 — Monitoring, Logging, Backup & Incident

> ⏱️ Tổng ~4,5 giờ (nên chia 2 buổi: A + B một buổi, C một buổi) · Làm vào cuối tuần 18
> Bao phủ: Module 08, bài [01](01-monitoring-logging-observability.md) → [06](06-incident-response.md), [Break-fix Observability #1](labs/break-fix-01/README.md)
> Lời giải: [solutions/checkpoint-solutions.md](solutions/checkpoint-solutions.md) — **chỉ mở sau khi đã nộp bài cho chính mình** (commit vào repo).

> 💰 **Chi phí: 0 USD.** Cả ba phần chạy trên Docker trong máy bạn. Dự án v5 đã cho bạn thực hành trên EC2; checkpoint đo **hiểu biết** và kỹ năng debug, và những thứ đó kiểm tra được hoàn toàn trên máy.

## Mục lục

- [Quy tắc](#quy-tắc)
- [Chuẩn bị](#chuẩn-bị)
- [Phần A — Lý thuyết (45 phút)](#phần-a--lý-thuyết-45-phút)
- [Phần B — Thực hành (120 phút)](#phần-b--thực-hành-120-phút)
- [Phần C — Break-fix (90 phút)](#phần-c--break-fix-90-phút)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [Nếu chưa đạt](#nếu-chưa-đạt)

---

## Quy tắc

1. **Không dùng AI và không xem lời giải** trong lúc làm.
2. **Được phép:** tài liệu chính thức (prometheus.io, grafana.com/docs, docs Loki/Alloy, `promtool --help`, `amtool --help`), các bài trong Module 08, ghi chú của chính bạn.
3. Tự bấm giờ cho từng phần. Hết giờ thì dừng, ghi lại mình đang ở đâu.
4. Nộp bài: thư mục `~/devops-journey/week18/checkpoint/` gồm `part-a.md`, `part-b/` (code + output các lần chạy), `part-c.md` (nhật ký debug). Commit **trước** khi mở lời giải.

## Chuẩn bị

`[WSL]` — phải chạy được:

```bash
docker ps                      # Docker Desktop đã bật WSL integration
docker compose version         # Compose v2
python3 --version              # 3.12 trên Ubuntu 24.04 (verify.sh dùng)
```

Phần B dùng lại hệ thống `bf08` **đã sửa xong** ở [Break-fix Observability #1](labs/break-fix-01/README.md). Nếu đã dọn nó: chạy lại `setup.sh` rồi áp lại các bản sửa **từ nhật ký của bạn** (không mở lời giải) — đó cũng là bài kiểm tra nhật ký có đủ chi tiết hay không. `verify.sh` của bf08 phải đạt 7/7 trước khi bắt đầu phần B.

---

## Phần A — Lý thuyết (45 phút)

Trả lời bằng lời của bạn, 3–8 câu mỗi câu. Giải thích **bản chất** và **vì sao**, không chép định nghĩa.

### Khái niệm và metrics

1. **Monitoring**, **logging** và **observability** khác nhau thế nào? Với mỗi cái, nêu một câu hỏi về taskhub mà nó trả lời được còn hai cái kia thì khó.
2. **Bốn tín hiệu vàng** (golden signals) là gì? Với mỗi tín hiệu, viết tên metric hoặc biểu thức PromQL cụ thể cho taskhub (Spring Boot + Micrometer, hoặc node_exporter).
3. **Counter**, **gauge**, **histogram** khác nhau thế nào? Vì sao `rate()` chỉ dùng cho counter? Điều gì xảy ra với counter khi app khởi động lại, và `rate()` xử lý nó ra sao?
4. `rate()`, `irate()` và `increase()` khác nhau thế nào? Với `scrape_interval: 15s`, vì sao `rate(x[10s])` gần như luôn trả về **rỗng**? Quy tắc chọn độ dài cửa sổ là gì? *(bắt buộc đúng)*
5. Vì sao đo độ trễ bằng **trung bình** dễ đánh lừa? Viết biểu thức p95 độ trễ HTTP từ histogram, và giải thích vì sao bắt buộc phải có `by (le)` trong `sum(...)`.
6. **Cardinality** là gì? Vì sao đưa `user_id` hay `request_id` vào **label** là sai ở cả Prometheus và Loki? Trong Loki, phân biệt **label** và **nội dung log**; muốn tìm log của một `request_id` cụ thể thì viết LogQL thế nào? *(bắt buộc đúng)*
7. Prometheus dùng mô hình **pull**. Metric `up` từ đâu ra, bằng 0 nghĩa là gì? Nêu 3 nguyên nhân khác nhau khiến một target ở trạng thái DOWN và cách phân biệt chúng từ cột *Error*.

### Cảnh báo

8. Một alert tốt cần những gì? So sánh alert theo **triệu chứng** (symptom) và theo **nguyên nhân** (cause). Vai trò của `for:`, nhãn `severity`, annotation `runbook_url`. Thế nào là "alert fatigue" và làm sao tránh?
9. Trong Alertmanager, **grouping**, **routing**, **inhibition** và **silence** giải quyết vấn đề gì? Cho ví dụ một inhibit rule **đúng** cho taskhub, và giải thích vì sao một inhibit rule viết quá rộng còn nguy hiểm hơn không có alert.
10. Ở v5, bộ giám sát chạy **cùng máy** với app. Nếu EC2 chết, ai báo cho bạn? "Who watches the watcher" được giải quyết thế nào trong thiết kế v5, và Watchdog/dead man's switch giúp gì?

### Backup, sự cố

11. Định nghĩa **RPO** và **RTO**. taskhub backup `pg_dump` lúc 02:00 hằng ngày; ổ dữ liệu hỏng lúc 18:00. Mất tối đa bao nhiêu dữ liệu? Khôi phục mất bao lâu (liệt kê các bước tốn thời gian)? Muốn giảm RPO xuống 15 phút thì có những lựa chọn nào? *(bắt buộc đúng)*
12. "Backup chưa từng restore thử thì coi như không có backup" — vì sao? Liệt kê các bước của một buổi **diễn tập restore** cho taskhub. Vì sao restore vào database **mới** trước, không ghi đè database đang chạy? `pg_dump -Fc` khác dạng SQL thường ở điểm nào khi restore?
13. Trong một sự cố, vì sao ưu tiên **giảm thiểu tác động** (mitigate: rollback, tắt tính năng) trước khi tìm nguyên nhân gốc? Các vai trò trong một sự cố (incident commander, người liên lạc…) để làm gì, kể cả khi team chỉ có 2–3 người?
14. Một **postmortem không đổ lỗi** (blameless) gồm những phần nào? Vì sao "không đổ lỗi" lại giúp hệ thống an toàn hơn? Viết một ví dụ action item **tốt** và một ví dụ **tồi** cho sự cố "dừng dịch vụ 20 phút mà không ai được báo" ở bf08.

---

## Phần B — Thực hành (120 phút)

### Nhiệm vụ: đo một chỉ số kinh doanh từ đầu đến cuối

Nhiệm vụ này **mới**: các bài trước chỉ đo metric kỹ thuật có sẵn; ở đây bạn tự **thêm** một metric nghiệp vụ, viết **recording rule**, viết **unit test cho rule** bằng `promtool test rules`, và **provision dashboard từ file** — bốn việc chưa lab nào bắt làm. Vì sao chọn bài này: ở công ty, câu hỏi thường gặp nhất không phải "CPU bao nhiêu" mà là "tỷ lệ đơn hàng lỗi có đang tăng không" — và rule không có test sẽ im lặng hỏng như bạn đã thấy ở bf08.

Làm trên hệ thống `bf08` đã sửa (thư mục `~/devops-lab/08-monitoring/bf08`). Ở phần này **được phép** sửa `app/app.py`.

| # | Yêu cầu |
|---|---|
| R1 | App có endpoint `/order`: thành công với xác suất `1 - ORDER_FAIL_RATIO` (biến môi trường, mặc định `0.05`), thất bại thì trả HTTP 502. Counter `demo_orders_total{result="success"\|"failed"}`. Cả hai giá trị `result` phải **có series ngay khi app khởi động** (giá trị 0), không đợi đơn đầu tiên |
| R2 | Gauge `demo_inflight_requests`: số request đang được xử lý |
| R3 | Service `loadgen` mới trong `compose.yaml` gọi `/order` khoảng 2 lần/giây (tự viết, image nhỏ, có `mem_limit`) |
| R4 | Recording rule `job:demo_order_failure_ratio:rate5m` = tỷ lệ đơn thất bại trong 5 phút, **giữ nhãn `job`** |
| R5 | Alert `OrderFailureRatioHigh`: dùng recording rule ở R4, ngưỡng `> 0.10` trong 5 phút, `severity: warning`, có annotation `summary` và `runbook_url` |
| R6 | File `prometheus/tests.yml` với **ít nhất 2 ca**: (a) tỷ lệ lỗi 20% → alert firing với đúng nhãn; (b) tỷ lệ lỗi 5% → không có alert. Chạy được bằng `promtool test rules` (qua image `prom/prometheus:v3.15.1`, entrypoint `promtool`) |
| R7 | Dashboard Grafana **provision từ file** (provider YAML + file JSON trong repo, không tạo bằng tay trên UI): panel tốc độ đơn hàng theo `result`, panel tỷ lệ lỗi (dùng recording rule) có ngưỡng 0,1, panel `demo_inflight_requests` |
| R8 | Thêm vào dashboard một panel log (Loki) chỉ hiện log đơn **thất bại** — lọc bằng nội dung JSON, không thêm label mới |
| R9 | Chứng minh end-to-end: đặt `ORDER_FAIL_RATIO=0.3`, alert tới `webhook-debug`; trả về `0.05`, webhook nhận `resolved` |
| R10 | `promtool check config`, `promtool check rules`, `amtool check-config` đều qua; `verify.sh` của bf08 vẫn 7/7 |

**Kiểm thử phải ghi vào `part-b.md`** (dán output thật):

1. `curl -s 127.0.0.1:<cổng-app>/order` vài lần + `curl -s` endpoint metrics của app (qua `docker compose exec prometheus wget -qO- http://app:8000/metrics`) cho thấy `demo_orders_total` có **cả hai** giá trị `result`.
2. Output `promtool test rules tests.yml` báo `SUCCESS`. Sửa ngưỡng trong rule thành `0.5`, chạy lại → test (a) **FAILED**; trả lại `0.10`.
3. Ảnh chụp dashboard với 4 panel có dữ liệu.
4. Danh sách webhook đã nhận (`curl -s 127.0.0.1:<cổng-webhook>/`) có `OrderFailureRatioHigh` cả `firing` lẫn `resolved`, kèm mốc thời gian bạn đổi `ORDER_FAIL_RATIO`.
5. Giải thích ngắn: vì sao R1 yêu cầu khởi tạo series bằng 0? Chuyện gì xảy ra với biểu thức tỷ lệ nếu series `failed` chưa tồn tại?

---

## Phần C — Break-fix (90 phút)

### Khởi tạo

```bash
mkdir -p ~/devops-lab/08-monitoring/tools-ck && cd ~/devops-lab/08-monitoring/tools-ck
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/08-MONITORING-LOGGING/labs/checkpoint/setup.sh .
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/08-MONITORING-LOGGING/labs/checkpoint/verify.sh .
sed -i 's/\r$//' setup.sh verify.sh
bash setup.sh      # cổng bị chiếm → ví dụ CK08_GRAFANA_PORT=23010 CK08_PROM_PORT=29190 bash setup.sh
```

Script dựng hệ thống `ck08` (app demo + loadgen ~5 request/giây với khoảng 20% lỗi 500 và 10% request chậm ~0,5 giây, cùng bộ Prometheus/Alertmanager/Loki/Alloy/Grafana). Cổng mặc định: Prometheus 19190, Alertmanager 19193, webhook-debug 15101, Loki 13110, Grafana 13010 (admin / `ck08-admin`). **Không đọc `setup.sh` và `verify.sh` trước khi nộp bài.** Chạy `bf08` và `ck08` cùng lúc được (khác cổng), nhưng nên dừng bf08 để đỡ RAM: `cd ~/devops-lab/08-monitoring/bf08 && docker compose stop`.

### Bối cảnh

Đồng nghiệp bàn giao: *"Mình vừa 'tối ưu' bộ giám sát: alert lỗi phản hồi nhanh hơn, thêm alert độ trễ, thêm inhibit rule cho đỡ spam, và gắn `request_id` làm label Loki cho dễ tìm. Loadgen đang bắn lỗi 20% đấy, chắc chắn phải có cảnh báo."*

Nhưng `webhook-debug` chỉ nhận đúng một thứ: `Watchdog`.

### Các ticket

| Ticket | Triệu chứng được báo | Kết quả mong đợi |
|---|---|---|
| 🎫 #8101 | 20% request lỗi mà `HighErrorRate` không bao giờ chuyển pending | `HighErrorRate` firing trên Prometheus. **Không** được hạ ngưỡng 5% hay bỏ `for` |
| 🎫 #8102 | Panel/alert độ trễ p95 trống trơn, dù 10% request chậm 0,5 giây | `HighLatencyP95` firing; biểu thức trả về giá trị p95 hợp lý (khoảng 0,5–0,75 giây) khi dán vào Query |
| 🎫 #8103 | (sau #8101, #8102) Hai alert đỏ trên Prometheus, **có** trong Alertmanager, nhưng webhook vẫn chỉ nhận Watchdog | Cả hai tới `webhook-debug`. Inhibit rule vẫn còn và làm **đúng** ý định ban đầu của đồng nghiệp |
| 🎫 #8104 | Grafana Explore → Loki chậm dần; label browser có hàng nghìn giá trị `request_id`; để lâu, log của Alloy bắt đầu có lỗi từ Loki | `request_id` không còn là label; vẫn tìm được log của một request cụ thể bằng LogQL |

### Luật chơi

- Không sửa `app/`, `loadgen/`, `verify.sh`. Không tắt loadgen.
- Không hạ ngưỡng, không bỏ `for`, không xóa alert hay inhibit rule để "cho xanh" — sửa **đúng chỗ sai**.
- Nhật ký cho **từng** ticket theo mẫu ở [Break-fix Observability #1](labs/break-fix-01/README.md#8-sản-phẩm-phải-nộp) vào `part-c.md`, đặc biệt: **bạn chứng minh nguyên nhân bằng cách nào** (truy vấn nào, API nào).

### Kiểm tra

```bash
bash ~/devops-lab/08-monitoring/tools-ck/verify.sh     # 7 mục; alert có for: 2m → sửa xong chờ ~3 phút
```

### Dọn dẹp (bắt buộc)

```bash
cd ~/devops-lab/08-monitoring/ck08
docker compose down -v                                        # ⚠️ chỉ project ck08
docker rmi ck08-app:local ck08-loadgen:local ck08-webhook:local
cd .. && rm -rf ck08
```

---

## Tiêu chí đạt

| Phần | Đạt khi | Trọng số |
|---|---|---|
| A | ≥ 11/14 câu đúng **bản chất** (tự chấm theo lời giải, trung thực). Câu **4, 6 và 11 bắt buộc đúng** | 30% |
| B | Đạt R1–R10 và đủ 5 kiểm thử có output thật, trong 120 phút | 35% |
| C | `verify.sh` đạt **7/7** trong 90 phút, nhật ký nêu **cách chứng minh** từng nguyên nhân và vì sao cách sửa không làm hỏng ý định ban đầu | 35% |

**Đạt Checkpoint** khi đạt cả 3 phần → tick vào checklist [Module 08](README.md) và cập nhật [ma trận kỹ năng](../00-ROADMAP/skill-matrix.md).

---

## Nếu chưa đạt

Không chuyển sang Module 09 ngay (xem [quy tắc khi chậm tiến độ](../00-ROADMAP/weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ)):

| Sai ở | Ôn lại |
|---|---|
| Câu A1, A2 | [Bài 01 — Monitoring, logging, observability](01-monitoring-logging-observability.md) |
| Câu A3–A5, A7, R1–R4, R6, ticket #8101, #8102 | [Bài 02 — Metrics & Prometheus](02-metrics-prometheus.md), làm lại [Break-fix Observability #1](labs/break-fix-01/README.md) |
| Câu A8, A9, R5, R7, R9, ticket #8103 | [Bài 03 — Grafana, dashboard & alerting](03-grafana-dashboards-alerting.md) |
| Câu A6, R8, ticket #8104 | [Bài 04 — Log tập trung](04-centralized-logging.md) |
| Câu A10 | [Bài 03](03-grafana-dashboards-alerting.md), [Bài 06](06-incident-response.md) |
| Câu A11–A14 | [Bài 06 — Ứng phó sự cố, backup/restore, rollback](06-incident-response.md) |

Ôn xong 2–3 ngày rồi làm lại phần chưa đạt. Phần C: dọn dẹp rồi chạy lại `setup.sh` — lỗi được cài lại y hệt.
