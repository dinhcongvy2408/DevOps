# 01. Monitoring, logging, observability — biết hệ thống đang ra sao mà không cần đoán

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Lab Spring Boot + PostgreSQL + Nginx](../04-DOCKER/labs/lab-springboot-postgres-compose/README.md), [Network 06 — HTTP và `curl -w`](../02-NETWORKING/06-http-https-tls.md), [AWS 10 — CloudWatch](../06-AWS/10-cloudwatch.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL integration), stack `taskhub` chạy trên laptop. **0 USD**, không tạo tài nguyên AWS nào.

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc](#6-sơ-đồ-kiến-trúc)
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

- Phân biệt **monitoring** (giám sát), **logging** (ghi log) và **observability** (khả năng quan sát) — và giải thích vì sao chúng không phải ba tên gọi của cùng một thứ.
- Kể ra **ba trụ cột** của observability (metrics, logs, traces), mỗi loại trả lời câu hỏi gì và tốn kém ra sao.
- Phân biệt **push** và **pull**, **white-box** và **black-box**, rồi tự làm cả hai kiểu kiểm tra trên `taskhub`.
- Nêu **4 Golden Signals**, phương pháp **RED** và **USE**, và ánh xạ chúng vào metric thật của `taskhub`.
- Định nghĩa **SLI**, **SLO**, **SLA**, tính **error budget** (ngân sách lỗi) theo phút, và viết `docs/slo.md` cho dự án.
- Giải thích triết lý alert: cảnh báo theo **triệu chứng**, phải **hành động được**, có **runbook**, tránh **alert fatigue** (mệt mỏi vì cảnh báo).
- Giải thích **cardinality** (số lượng chuỗi dữ liệu) và vì sao một label sai có thể làm sập Prometheus.
- Mô tả vai trò của từng công cụ trong bộ giám sát của module, và trả lời được câu hỏi "**ai giám sát hệ thống giám sát?**".

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống ở công việc thật | Khái niệm của bài này giúp gì |
|---|---|
| Nhận cảnh báo "CPU 85%" lúc 2 giờ sáng — có phải dậy không? | Alert theo **triệu chứng** người dùng thấy, không theo nguyên nhân; CPU cao mà người dùng không bị ảnh hưởng thì không đáng đánh thức ai |
| "Hệ thống của em có ổn không?" | SLO: trả lời bằng **con số** ("99,7% request thành công trong 30 ngày, mục tiêu 99,5%") thay vì cảm giác |
| "Có nên phát hành bản mới tối thứ Sáu không?" | Error budget: còn ngân sách lỗi thì phát hành, hết thì ưu tiên sửa độ ổn định |
| Dashboard xanh hết mà người dùng vẫn kêu không vào được | White-box chỉ thấy **bên trong**; cần black-box đo **từ phía người dùng** |
| Prometheus bỗng dùng 6 GB RAM sau khi thêm một metric | Cardinality: ai đó gắn `user_id` làm label |
| Phỏng vấn: "Monitoring khác observability thế nào?", "Golden Signals là gì?", "SLO khác SLA?" | Ba câu hỏi lý thuyết hay gặp nhất về giám sát |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Thực ra bạn đã "giám sát" từ lâu

Nhìn lại các module trước, bạn đã làm rất nhiều việc giám sát — chỉ là rời rạc:

| Ở đâu | Bạn đã làm gì | Thiếu gì |
|---|---|---|
| [Linux lab 03](../01-LINUX/labs/lab-03-healthcheck-cron.md) | Script `healthcheck.sh` chạy bằng cron, gọi `curl` rồi ghi log | Không ai được báo khi lỗi; không có lịch sử để vẽ biểu đồ |
| [Docker](../04-DOCKER/03-dockerfile-multistage.md) | `HEALTHCHECK` gọi `/actuator/health` | Chỉ biết **sống/chết**, không biết chậm hay nhanh, lỗi bao nhiêu % |
| [CI/CD bài 05](../05-CICD/05-deployment-strategies-rollback.md) | Smoke test sau deploy | Chỉ kiểm tra **một lần** sau deploy, không liên tục |
| [AWS bài 10](../06-AWS/10-cloudwatch.md) | Alarm CPU và `StatusCheckFailed` gửi email | Chỉ thấy máy, không thấy app (tỷ lệ lỗi, độ trễ) |
| `docker compose logs` | Đọc log khi có chuyện | Container bị tạo lại thì log cũ mất; phải vào tận máy mới đọc được |

Module này gom các mảnh đó thành một hệ thống: **thu thập liên tục → lưu lịch sử → xem trên dashboard → tự cảnh báo → tìm nguyên nhân**.

### 3.2. Time series — dạng dữ liệu của metric

Một **metric** (chỉ số) là một con số được đo lặp lại theo thời gian. Mỗi lần đo là một cặp `(thời điểm, giá trị)`. Chuỗi các cặp đó gọi là **time series** (chuỗi thời gian):

```text
http_server_requests_seconds_count{method="GET", uri="/api/tasks", status="200"}
  10:00:00 → 1520
  10:00:15 → 1538
  10:00:30 → 1561      ← bộ đếm tăng dần; tốc độ tăng = số request mỗi giây
```

Phần trong `{...}` là **label** (nhãn): cặp khóa–giá trị mô tả "chuỗi này đo cái gì". Mỗi tổ hợp label khác nhau là **một time series riêng**. Điều này quan trọng ở mục [4.9 — cardinality](#49--cardinality--một-label-sai-có-thể-làm-sập-prometheus).

### 3.3. Metric và log khác nhau thế nào

| | Metric | Log |
|---|---|---|
| Là gì | Con số đã **tổng hợp** (đếm, đo) | **Sự kiện** riêng lẻ, thường là một dòng văn bản |
| Ví dụ | "1561 request GET `/api/tasks` trả 200" | `2026-11-20T14:20:03 ERROR ... could not obtain connection` |
| Dung lượng | Nhỏ, gần như cố định dù traffic tăng | Tăng theo traffic |
| Giỏi trả lời | "Bao nhiêu? Nhanh hay chậm? Xu hướng thế nào?" | "Chuyện gì đã xảy ra, với request nào, chi tiết ra sao?" |
| Hợp để cảnh báo | ✅ Rất hợp | Hạn chế (đắt và chậm hơn) |

Quy tắc dễ nhớ: **metric cho bạn biết CÓ vấn đề; log cho bạn biết vấn đề LÀ GÌ.**

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Monitoring, logging, observability

| Khái niệm | Câu hỏi nó trả lời | Ví dụ với `taskhub` |
|---|---|---|
| **Monitoring** (giám sát) | "Những thứ tôi **đã biết** cần theo dõi có ổn không?" | Theo dõi tỷ lệ lỗi 5xx, độ trễ, ổ đĩa; cảnh báo khi vượt ngưỡng |
| **Logging** (ghi log) | "Chuyện gì đã xảy ra, theo thứ tự thời gian?" | Dòng `ERROR` kèm stack trace lúc 14:20:03 |
| **Observability** (khả năng quan sát) | "Tôi có thể hỏi **câu hỏi mới** về hệ thống — câu tôi chưa từng nghĩ tới — mà **không phải sửa code** để có câu trả lời không?" | "Request chậm có tập trung ở task có mô tả dài không?" — trả lời được nếu metric, log, trace đủ chi tiết |

Cách nói thường gặp: monitoring xử lý **known unknowns** (điều đã biết là có thể hỏng: đầy đĩa, app chết), còn observability giúp với **unknown unknowns** (điều chưa ai nghĩ tới). Observability là một **thuộc tính** của hệ thống (hệ thống của bạn quan sát được đến đâu), không phải một công cụ mua về. Monitoring và logging là **phương tiện** để đạt được nó.

> Ở mức Junior, bạn không cần tranh luận định nghĩa. Bạn cần làm được: hệ thống phát ra đủ tín hiệu (metric, log, trace), tín hiệu được thu thập về một chỗ, và khi có sự cố bạn đi từ **cảnh báo → dashboard → log** để tìm ra nguyên nhân.

### 4.2. 🟥 Ba trụ cột: metrics, logs, traces

| Trụ cột | Là gì | Trả lời câu hỏi | Chi phí lưu trữ | Công cụ trong module |
|---|---|---|---|---|
| **Metrics** | Con số theo thời gian, có label | Có vấn đề không? Bắt đầu từ lúc nào? Nặng đến đâu? | Thấp | Prometheus |
| **Logs** | Sự kiện có thời điểm | Chính xác chuyện gì xảy ra? Lỗi gì? | Trung bình–cao | Loki + Alloy |
| **Traces** | Đường đi của **một** request qua nhiều thành phần, chia thành các **span** | Request này chậm ở bước nào? | Cao (thường chỉ lấy mẫu) | Khái niệm ở [bài 05](05-tracing-overview.md) |
| 🟦 **Profiles** | Hàm nào trong code đang ăn CPU/RAM | Vì sao process này tốn CPU? | — | Học sau khi đi làm |

`taskhub` hiện là **một** service gọi **một** database — tracing ít giá trị hơn metric và log. Khi hệ thống có nhiều service gọi nhau, tracing trở nên quan trọng. Vì vậy module dạy sâu metric và log, còn tracing ở mức khái niệm.

### 4.3. 🟥 Push và pull

| | **Pull** (kéo) | **Push** (đẩy) |
|---|---|---|
| Cách làm | Hệ thống giám sát **chủ động gọi** tới từng target theo chu kỳ (**scrape**) | Ứng dụng/agent **gửi** dữ liệu tới hệ thống giám sát |
| Ví dụ | Prometheus gọi `GET /actuator/prometheus` của `taskhub` mỗi 15 giây | Alloy gửi log tới Loki; CloudWatch agent gửi metric lên AWS |
| Ưu điểm | Target chết → scrape thất bại → **biết ngay** (metric `up = 0`); dễ chạy thử bằng `curl` | Hợp với job chạy ngắn, máy sau NAT/firewall |
| Nhược điểm | Prometheus phải tìm được và kết nối được tới target | Không gửi nữa thì khó phân biệt "đã chết" hay "đang yên" |

Prometheus dùng **pull** cho metric (theo [tài liệu Prometheus](https://prometheus.io/docs/introduction/overview/)). Với job chạy rất ngắn (như script backup chạy 30 giây rồi thoát), không kịp scrape → Prometheus có **Pushgateway**. Dự án `taskhub` chọn cách khác cho script backup: ghi thời điểm backup thành công vào một file mà node_exporter đọc (**textfile collector**) — gặp lại ở [Lab 02](labs/lab-02-backup-restore.md).

Log thì ngược lại: gần như luôn là **push** (Alloy đọc log rồi đẩy sang Loki).

### 4.4. 🟥 White-box và black-box

Theo [Google SRE book, chương 6](https://sre.google/sre-book/monitoring-distributed-systems/):

| | **White-box** (hộp trắng) | **Black-box** (hộp đen) |
|---|---|---|
| Đo từ đâu | **Bên trong** hệ thống: metric app tự xuất | **Bên ngoài**, như người dùng thấy |
| Ví dụ `taskhub` | `/actuator/prometheus`: số request, độ trễ, JVM heap, connection pool | `curl` gọi `http://<host>/api/tasks` qua nginx, đo mã trả về và thời gian |
| Giỏi phát hiện | Vấn đề **sắp xảy ra** (pool gần cạn, heap gần đầy), lỗi bị retry che | Vấn đề **đang xảy ra** và người dùng **đang chịu** |
| Mù trước | Lỗi nằm **ngoài** app: nginx chết, DNS sai, Security Group chặn | Nguyên nhân — chỉ biết "hỏng", không biết vì sao |

Bạn cần **cả hai**. Bài thực hành mục 9 cho bạn tự thấy: dừng nginx thì metric của app vẫn đẹp, trong khi người dùng hoàn toàn không vào được.

### 4.5. 🟥 Bốn tín hiệu vàng (Four Golden Signals)

Google SRE book đề xuất: nếu chỉ đo được 4 thứ cho một hệ thống phục vụ người dùng, hãy đo:

| Tín hiệu | Định nghĩa | Với `taskhub` đo bằng | Ghi chú |
|---|---|---|---|
| **Latency** (độ trễ) | Thời gian phục vụ một request | Phân vị p95 của `http_server_requests_seconds` | Tách request **thành công** và **lỗi**: lỗi 500 trả về trong 2 ms làm độ trễ trung bình "đẹp" giả tạo |
| **Traffic** (lưu lượng) | Mức nhu cầu đặt lên hệ thống | Số request/giây (`rate(..._count[5m])`) | Traffic tụt về 0 lúc giờ cao điểm cũng là dấu hiệu hỏng |
| **Errors** (lỗi) | Tỷ lệ request thất bại | Tỷ lệ `status=~"5.."` trên tổng | Có lỗi **ngầm**: trả 200 nhưng nội dung sai |
| **Saturation** (độ bão hòa) | Hệ thống "đầy" đến đâu — tài nguyên hạn chế nhất gần giới hạn chưa | Heap JVM / giới hạn, connection pool HikariCP, % ổ đĩa, RAM container so với `mem_limit` | Thường báo trước sự cố |

Bài [02](02-metrics-prometheus.md) viết câu truy vấn PromQL cho từng tín hiệu; bài [03](03-grafana-dashboards-alerting.md) đưa chúng lên dashboard.

### 4.6. 🟥 RED và USE — hai cách nhớ nhanh

| Phương pháp | Dùng cho | Ba thứ cần đo | Nguồn |
|---|---|---|---|
| **RED** | **Service** (thứ nhận request): `taskhub`, nginx | **R**ate (request/giây), **E**rrors (request lỗi), **D**uration (thời gian xử lý) | Tom Wilkie, [Grafana blog](https://grafana.com/blog/the-red-method-how-to-instrument-your-services/) |
| **USE** | **Tài nguyên** (thứ bị dùng): CPU, RAM, ổ đĩa, network, connection pool | **U**tilization (đang bận bao nhiêu %), **S**aturation (việc phải xếp hàng), **E**rrors (lỗi của tài nguyên) | Brendan Gregg, [The USE Method](https://www.brendangregg.com/usemethod.html) |

RED gần như trùng 3/4 Golden Signals (thiếu saturation). USE bổ sung góc nhìn **máy**. Cách dùng thực tế: **dashboard của app theo RED, dashboard của máy theo USE**. Tom Wilkie tóm tắt: RED là quan tâm tới người dùng, USE là quan tâm tới máy.

Ví dụ USE cho ổ đĩa EC2 của `taskhub`:

| | Câu hỏi | Đo bằng |
|---|---|---|
| Utilization | Đã dùng bao nhiêu % dung lượng? | `node_filesystem_avail_bytes` / `node_filesystem_size_bytes` |
| Saturation | Có thao tác đọc/ghi đang phải chờ không? | Thời gian I/O của `node_disk_*` |
| Errors | Có lỗi đọc/ghi không? | Log kernel (`dmesg`) |

### 4.7. 🟥 SLI, SLO, SLA và error budget

Định nghĩa theo [Google SRE book, chương 4](https://sre.google/sre-book/service-level-objectives/):

| Thuật ngữ | Nghĩa | Ví dụ `taskhub` |
|---|---|---|
| **SLI** (Service Level Indicator — chỉ số mức dịch vụ) | Một **phép đo** định lượng về chất lượng dịch vụ | Tỷ lệ request `/api/*` **không** trả 5xx |
| **SLO** (Service Level Objective — mục tiêu mức dịch vụ) | **Mục tiêu** cho một SLI, trong một khoảng thời gian | ≥ 99,5% request không lỗi 5xx, tính trong 30 ngày |
| **SLA** (Service Level Agreement — thỏa thuận mức dịch vụ) | **Hợp đồng** với khách hàng, có **hậu quả** khi vi phạm (hoàn tiền…) | `taskhub` là dự án cá nhân → **không có SLA**. Công ty thật đặt SLA **lỏng hơn** SLO nội bộ để có khoảng an toàn |

**Error budget** (ngân sách lỗi) = 100% − SLO. Với SLO 99,5% trong 30 ngày, bạn được phép "hỏng" 0,5%:

| SLO (30 ngày) | Error budget | Tương đương thời gian ngừng hoàn toàn |
|---|---|---|
| 99% | 1% | 30 × 24 × 60 × 0,01 = **432 phút** (7,2 giờ) |
| 99,5% | 0,5% | **216 phút** (3,6 giờ) |
| 99,9% | 0,1% | **43,2 phút** |
| 99,99% | 0,01% | **4,32 phút** |

Mỗi "số 9" thêm vào khiến ngân sách nhỏ đi 10 lần — và chi phí để đạt nó tăng rất nhanh. `taskhub` chạy trên **một** EC2: mỗi lần deploy theo kiểu recreate đã mất vài chục giây ([CI/CD bài 05](../05-CICD/05-deployment-strategies-rollback.md)), một lần EC2 bảo trì có thể mất vài phút. Đặt 99,99% là tự lừa mình; **99,5%** là con số trung thực.

Error budget dùng để **ra quyết định**:

- Còn nhiều ngân sách → được phép phát hành nhanh, thử nghiệm.
- Ngân sách sắp hết → tạm dừng tính năng mới, ưu tiên sửa độ ổn định.

🟦 Cảnh báo theo **burn rate** (tốc độ đốt ngân sách) là kỹ thuật nâng cao — xem [SRE workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/). Ở module này, alert dùng ngưỡng đơn giản.

### 4.8. 🟥 Triết lý alert — cảnh báo cho con người

Một alert là một lời nói: "**có người cần làm gì đó, ngay bây giờ**". Nếu không đúng như vậy, alert đó đang lấy dần sự chú ý của bạn.

| Nguyên tắc | Nghĩa | Ví dụ với `taskhub` |
|---|---|---|
| **Cảnh báo theo triệu chứng**, không theo nguyên nhân | Báo điều người dùng **chịu** (lỗi, chậm, không vào được) | ✅ "Tỷ lệ 5xx > 5% trong 5 phút" · ❌ "CPU > 80%" (CPU cao mà app vẫn nhanh thì chẳng ai cần dậy) |
| **Mỗi alert phải hành động được** | SRE book: *every page should be actionable*. Nhận alert mà không biết làm gì → alert vô ích | Alert có trường `runbook_url` trỏ tới `docs/runbooks/...` |
| **Có thời gian chờ** (`for:`) | Chỉ bắn khi tình trạng kéo dài, tránh bắn vì một lần chập chờn | `up == 0` **trong 1 phút** mới báo `TaskhubDown` |
| **Phân mức** | Gọi người ngay (page) vs ghi phiếu xử lý trong giờ làm (ticket) | App chết → page; ổ đĩa 80% → ticket (còn thời gian xử lý) |
| **Tránh alert fatigue** | Quá nhiều alert vô nghĩa → người trực bắt đầu **phớt lờ** → bỏ sót alert thật | Mỗi alert từng bắn mà không ai cần làm gì → sửa ngưỡng hoặc xóa |
| **Biết khi nào đã hết** | Alert có trạng thái **resolved** để người trực biết đã ổn | Alertmanager gửi cả thông báo `RESOLVED` |

Hai alert bắt buộc của module là ví dụ cho cả hai mức:

- `TaskhubDown` — triệu chứng rõ ràng (người dùng không vào được), phải xử lý ngay.
- `HostDiskUsageHigh` (> 80%) — **cảnh báo sớm**: chưa ai bị ảnh hưởng, nhưng nếu để tới 100% thì PostgreSQL sẽ ngừng ghi được. Có thời gian để xử lý trong giờ làm.

### 4.9. 🟥 Cardinality — một label sai có thể làm sập Prometheus

Nhắc lại mục 3.2: **mỗi tổ hợp giá trị label là một time series**. Tài liệu Prometheus cảnh báo không dùng label có **nhiều giá trị khác nhau** như user ID hay email ([Prometheus — naming](https://prometheus.io/docs/practices/naming/)).

Tính thử cho `taskhub`:

| Label | Số giá trị | |
|---|---|---|
| `method` | 4 (GET, POST, PUT, DELETE) | |
| `uri` (dạng **mẫu** `/api/tasks/{id}`) | ~3 | |
| `status` | ~6 (200, 201, 204, 400, 404, 500) | |
| **Tổng** | 4 × 3 × 6 = **72 series** — không đáng kể | ✅ |
| Nếu `uri` là đường dẫn **thật** (`/api/tasks/1`, `/api/tasks/2`, …) với 100.000 task | 4 × 100.000 × 6 = **2,4 triệu series** | ❌ RAM Prometheus tăng vọt, truy vấn chậm, có thể bị OOM kill |

Spring Boot đã tránh bẫy này: label `uri` là **mẫu** của đường dẫn (`/api/tasks/{id}`), không phải đường dẫn thật — bạn sẽ tự kiểm chứng ở bước 7 của bài thực hành.

Quy tắc tương tự áp dụng cho **log trong Loki** ([bài 04](04-centralized-logging.md)): label chỉ dùng cho thứ ít giá trị (`container`, `level`); thứ nhiều giá trị (ID request, ID người dùng) để trong **nội dung** dòng log.

### 4.10. 🟥 Bộ công cụ của module — ai làm gì

| Công cụ | Vai trò một câu | Trụ cột |
|---|---|---|
| **Spring Boot Actuator + Micrometer** | App tự đếm và đo (request, độ trễ, JVM, connection pool) rồi xuất ở `/actuator/prometheus` | Metrics (nguồn) |
| **node_exporter** | Xuất metric của **máy**: CPU, RAM, ổ đĩa, network | Metrics (nguồn) |
| **Prometheus** | Định kỳ scrape các target, lưu time series, đánh giá alert rule | Metrics (lưu + cảnh báo) |
| **Alertmanager** | Nhận alert, gom nhóm, chặn trùng, tạm tắt (silence), gửi tới Telegram/webhook | Thông báo |
| **Grafana Alloy** | Đọc log của mọi container qua Docker API, gắn label, gửi đi | Logs (thu thập) |
| **Loki** | Lưu log, chỉ đánh chỉ mục theo label → rẻ và nhẹ | Logs (lưu) |
| **Grafana** | Một giao diện để xem dashboard, truy vấn metric (PromQL) và log (LogQL) | Hiển thị |

Promtail — công cụ thu log cũ của Loki — đã **hết vòng đời ngày 2/3/2026** theo [tài liệu Loki](https://grafana.com/docs/loki/latest/send-data/promtail/). Alloy là công cụ thay thế ("một bản phân phối OpenTelemetry Collector có sẵn pipeline Prometheus" — [Alloy introduction](https://grafana.com/docs/alloy/latest/introduction/)).

### 4.11. 🟨 CloudWatch, tự vận hành hay dịch vụ SaaS?

| Tiêu chí | CloudWatch ([AWS bài 10](../06-AWS/10-cloudwatch.md)) | Tự vận hành (Prometheus, Grafana, Loki) | SaaS (Grafana Cloud, Datadog, New Relic…) |
|---|---|---|---|
| Phải vận hành | Không | **Có** — chính bạn lo cập nhật, dung lượng, sao lưu | Không |
| Chi phí | Theo lượng dùng (log ingest, metric tùy chỉnh, alarm) | Tiền máy chạy nó (v5 phải nâng EC2 — xem [README module §5](README.md#5-chi-phí-khi-lên-aws-v5)) | Theo gói, có thể đắt khi dữ liệu lớn |
| Metric của app | Phải dùng agent/thư viện riêng | Chuẩn de facto, Spring Boot hỗ trợ sẵn | Có agent riêng |
| Gắn với nhà cung cấp | Chặt với AWS | Không | Chặt với nhà cung cấp SaaS |
| Giá trị học tập cho Junior | Cần biết (dùng nhiều ở công ty thuần AWS) | **Cao nhất** — hiểu từng mảnh, xuất hiện nhiều trong tin tuyển dụng | Dễ dùng, ít hiểu bên trong |
| Chết cùng máy chủ? | Không (dịch vụ của AWS) | **Có**, nếu chạy chung máy với app | Không |

`taskhub` chọn **tự vận hành** để học (ghi thành ADR-0010 ở [v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md)), nhưng **giữ lại** alarm CloudWatch `StatusCheckFailed` của v3 — lý do ở mục kế tiếp.

### 4.12. 🟥 Ai giám sát hệ thống giám sát?

Ở v5, Prometheus, Alertmanager và Grafana chạy **cùng EC2** với app. Nếu chính EC2 chết (lỗi phần cứng, kernel panic, hết RAM đến mức treo):

- App chết → lẽ ra `TaskhubDown` phải bắn…
- …nhưng Prometheus và Alertmanager **cũng chết theo** → **không ai gửi cảnh báo**.
- Bạn ngủ ngon, người dùng không vào được, sáng hôm sau mới biết.

Đây là câu hỏi kinh điển "**who watches the watcher?**". Cách giải quyết của dự án:

| Lớp | Ai canh | Chết cùng EC2? |
|---|---|---|
| App, tỷ lệ lỗi, độ trễ, ổ đĩa | Prometheus + Alertmanager trên EC2 | Có |
| Chính EC2 (máy còn sống không) | Alarm CloudWatch `StatusCheckFailed` → SNS email (từ v3) | **Không** — chạy ở hạ tầng AWS |
| 🟨 Từ bên ngoài, như người dùng | Một dịch vụ kiểm tra uptime bên ngoài gọi URL công khai | Không |
| 🟦 Dead man's switch | Một alert **luôn luôn bắn**; nếu bên nhận **ngừng** nhận được nó → biết hệ thống cảnh báo đã chết | Không |

Nguyên tắc chung: **ít nhất một đường cảnh báo phải nằm ngoài vùng có thể hỏng cùng lúc.**

### 4.13. Gặp lại ở đâu

| Kiến thức ở đây | Gặp lại ở |
|---|---|
| Golden Signals, PromQL cho từng tín hiệu | [Bài 02](02-metrics-prometheus.md), dashboard ở [bài 03](03-grafana-dashboards-alerting.md) |
| Triết lý alert, `for:`, runbook | Alert rule và Alertmanager ([bài 03](03-grafana-dashboards-alerting.md), [Lab 01](labs/lab-01-dashboard-alerts.md)) |
| Cardinality | Label trong Loki ([bài 04](04-centralized-logging.md)) |
| SLO, error budget | Postmortem: sự cố "đốt" bao nhiêu ngân sách ([bài 06](06-incident-response.md)) |
| Who watches the watcher | Thiết kế cảnh báo ở [v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md) |
| White-box vs black-box | Kubernetes liveness/readiness probe (Module 09) |

---

## 5. Ví dụ thực tế

*(Tình huống minh họa, dựng theo những gì hay xảy ra với hệ thống nhỏ chạy một máy.)*

**Không có observability.** Tối thứ Sáu, `taskhub` vẫn chạy. Sáng thứ Hai, một người bạn nhắn: "Cuối tuần tạo task không được". Bạn vào EC2, `docker compose ps` thấy mọi thứ đang `Up`. `docker compose logs taskhub` chỉ còn log từ lúc container khởi động lại sáng nay — log của cuối tuần đã mất. Bạn thử tạo task: chạy bình thường. Kết luận: "chắc mạng nhà bạn ấy có vấn đề". Ba tuần sau chuyện lặp lại.

**Có observability (v5).**

| Thời điểm | Chuyện gì xảy ra | Tín hiệu |
|---|---|---|
| T6 22:10 | Ổ đĩa vượt 80% (log Docker và dữ liệu Prometheus tăng dần) | Alert `HostDiskUsageHigh` → Telegram. Bạn xem lướt, định để thứ Hai xử lý |
| T7 03:40 | Ổ đĩa 100%. PostgreSQL không ghi được → `POST /api/tasks` trả 500 | Tỷ lệ 5xx vọt lên 60% → alert `HighErrorRate` |
| T7 08:00 | Bạn dậy, mở Grafana qua SSM port forwarding | Dashboard: lỗi bắt đầu 03:40, đúng lúc đĩa chạm 100% |
| T7 08:05 | Lọc log trên Loki: `{compose_service="postgres"} \|= "No space left on device"` | Thấy nguyên nhân ngay trong log của PostgreSQL |
| T7 08:20 | Dọn log cũ, giảm thời gian giữ dữ liệu, giải phóng ổ đĩa | Tỷ lệ lỗi về 0 → alert `RESOLVED` |
| T2 | Viết postmortem: lẽ ra phải xử lý từ alert 80% tối thứ Sáu; thêm giới hạn kích thước log | Error budget tháng này đã đốt ~4,5 giờ — vượt ngân sách 3,6 giờ của SLO 99,5% |

Cùng một sự cố, nhưng lần này bạn biết **khi nào bắt đầu**, **vì sao**, **ảnh hưởng bao nhiêu**, và **làm gì để không lặp lại**.

---

## 6. Sơ đồ kiến trúc

Bộ giám sát của `taskhub` ở v5 (trên EC2). Trên laptop, cấu trúc y hệt — chỉ khác là bạn mở Grafana trực tiếp ở `127.0.0.1`.

```text
 Người dùng ──HTTP 80──► Security Group (chỉ 80/443) ──► nginx ──► taskhub:8080 ──► postgres
                                                           │            │
 ┌─────────────────────── EC2 c7i-flex.large ──────────────┼────────────┼──────────────────────┐
 │  Project "taskhub" (network taskhub_default)            │            │                      │
 │                                                          │   /actuator/prometheus            │
 │  Project "taskhub-mon" ─────────────────────────────────────────────┼─ (chỉ trong network) │
 │                                                                      │                      │
 │   node_exporter ◄──scrape──┐                                         │                      │
 │                            │                                         │                      │
 │                       Prometheus ◄──────────── scrape ───────────────┘                      │
 │                            │ alert                                                          │
 │                            ▼                                                                │
 │                      Alertmanager ─────────────────────────────────────► Telegram           │
 │                                                                                             │
 │   Docker API ◄── Alloy ──push──► Loki                                                        │
 │   (log mọi container)                                                                        │
 │                                                                                             │
 │                       Grafana :3000 (bind 127.0.0.1) ◄── PromQL / LogQL ── Prometheus, Loki  │
 └──────────────────────────────▲──────────────────────────────────────────────────────────────┘
                                │ SSM port forwarding (không mở cổng nào ra Internet)
                        Laptop: http://localhost:3000

 Đường cảnh báo độc lập:  CloudWatch alarm StatusCheckFailed ──► SNS ──► email
```

Bài thực hành hôm nay chỉ dùng phần trên cùng của sơ đồ (người dùng → nginx → taskhub → postgres) và đo nó theo hai cách: từ ngoài vào (black-box) và từ trong ra (white-box).

---

## 7. Các câu lệnh cần biết

| Lệnh | Dùng để |
|---|---|
| `curl -o /dev/null -s -w '%{http_code} %{time_total}\n' <url>` | Kiểm tra black-box: mã trả về và tổng thời gian |
| `docker compose exec -T taskhub curl -s localhost:8080/actuator/metrics` | Liệt kê metric app tự đo (gọi **trong** container, không qua nginx) |
| `.../actuator/metrics/<tên>?tag=<khóa>:<giá trị>` | Xem một metric, lọc theo label |
| `jq '.measurements'`, `jq -r '.availableTags[]'` | Đọc JSON trả về |
| `docker compose stop <service>` / `start <service>` | Dàn dựng sự cố |
| `docker compose logs --since 5m <service>` | Đọc log trong khoảng thời gian gần |
| `docker stats --no-stream` | Xem nhanh CPU/RAM từng container (USE cho container) |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. `curl -w` — đo từ phía người dùng

Bạn đã gặp `curl -w` ở [Network 06](../02-NETWORKING/06-http-https-tls.md). Hôm nay dùng nó làm **probe** (đầu dò) black-box:

```bash
# [WSL]
curl -o /dev/null -s --max-time 10 -w '%{http_code} %{time_total}\n' http://localhost:8080/api/tasks
```

```text
200 0.012345
```

*(Đầu ra minh họa.)*

| Tham số | Ý nghĩa |
|---|---|
| `-o /dev/null` | Bỏ phần body, chỉ quan tâm mã và thời gian |
| `-s` | Không in thanh tiến trình |
| `--max-time 10` | Quá 10 giây thì bỏ cuộc — probe không được treo vô hạn |
| `-w '%{http_code} %{time_total}\n'` | In mã HTTP và tổng thời gian (giây) |
| Mã `000` | `curl` không nhận được phản hồi HTTP nào: không kết nối được, hoặc hết `--max-time` |

### 8.2. `/actuator/metrics` — đo từ bên trong app

Spring Boot Actuator có endpoint `metrics` để **duyệt** metric bằng JSON (dành cho con người; Prometheus dùng `/actuator/prometheus` ở bài 02). Theo [tài liệu Spring Boot](https://docs.spring.io/spring-boot/reference/actuator/metrics.html):

- `/actuator/metrics` → danh sách tên metric.
- `/actuator/metrics/<tên>` → giá trị của metric đó và các label có sẵn (`availableTags`).
- Thêm `?tag=KHÓA:GIÁ_TRỊ` (có thể lặp nhiều lần) để lọc theo label.
- Endpoint này **không mở** qua HTTP theo mặc định — phải thêm `metrics` vào `management.endpoints.web.exposure.include`. App `taskhub` hiện chỉ mở `health,info` ([hướng dẫn tạo app §5.2](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)).

```bash
# [WSL] gọi BÊN TRONG container taskhub (runtime image có curl), không đi qua nginx
docker compose exec -T taskhub curl -s 'localhost:8080/actuator/metrics/http.server.requests?tag=status:200' | jq
```

```json
{
  "name": "http.server.requests",
  "baseUnit": "seconds",
  "measurements": [
    { "statistic": "COUNT", "value": 152.0 },
    { "statistic": "TOTAL_TIME", "value": 1.873 },
    { "statistic": "MAX", "value": 0.041 }
  ],
  "availableTags": [
    { "tag": "method", "values": ["GET", "POST"] },
    { "tag": "uri", "values": ["/api/tasks", "/api/tasks/{id}"] },
    { "tag": "outcome", "values": ["SUCCESS"] }
  ]
}
```

*(Đầu ra minh họa — tên label và số liệu trên máy bạn có thể khác.)*

| Trường | Ý nghĩa |
|---|---|
| `COUNT` | Tổng số request khớp bộ lọc kể từ khi app khởi động |
| `TOTAL_TIME` | Tổng thời gian xử lý (giây). **Độ trễ trung bình** = `TOTAL_TIME / COUNT` ≈ 0,012 giây |
| `MAX` | Request chậm nhất trong một khoảng thời gian gần đây (không phải từ lúc khởi động) |
| `availableTags` | Các label còn lại có thể dùng để lọc tiếp |

| Tham số / cờ | Ý nghĩa |
|---|---|
| `exec -T` | Không cấp TTY — cần khi nối kết quả qua pipe sang `jq` |
| Dấu nháy `'...'` quanh URL | Shell không hiểu nhầm `?` và `&` |
| `jq` | Định dạng JSON cho dễ đọc. Chưa có thì cài: `sudo apt install -y jq` |

### 8.3. `docker stats --no-stream`

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
```

```text
NAME                 CPU %     MEM USAGE / LIMIT
taskhub-taskhub-1    0.45%     312MiB / 768MiB
taskhub-postgres-1   0.02%     38MiB / 7.6GiB
taskhub-nginx-1      0.00%     4MiB / 7.6GiB
```

*(Đầu ra minh họa.)* `--no-stream` in một lần rồi thoát. `MEM USAGE / LIMIT` chính là **utilization** của RAM theo USE: `taskhub` dùng 312 trên giới hạn 768 MiB. Container không đặt `mem_limit` thì LIMIT là toàn bộ RAM mà Docker Desktop cấp.

---

## 9. Bài thực hành từng bước

**Mục tiêu:** tự đo `taskhub` bằng hai cách — black-box (từ ngoài) và white-box (từ trong) — rồi dàn dựng 2 sự cố để thấy mỗi cách **mù** ở đâu. Cuối cùng viết `docs/slo.md`.

Thư mục làm việc ngoài repo:

```bash
mkdir -p ~/devops-lab/08-mon/01 && cd ~/devops-lab/08-mon/01
```

### Bước 0 — Chuẩn bị stack `taskhub` `[WSL]`

```bash
cd ~/projects/taskhub
docker compose ps
```

Cả `postgres`, `taskhub`, `nginx` phải `Up (healthy)`. Chưa chạy thì `docker compose up -d`.

**Cổng nginx:** máy bạn đã có container khác chiếm cổng `8000`. Thêm (hoặc sửa) dòng sau trong `.env` của repo (file không commit), rồi `docker compose up -d` lại:

```bash
NGINX_HOST_PORT=8080
```

Từ đây bài dùng biến `APP` để khỏi gõ lại:

```bash
export APP=http://localhost:8080
curl -s "$APP/actuator/health"      # {"groups":["liveness","readiness"],"status":"UP"}
```

### Bước 1 — Probe black-box chạy liên tục `[WSL]`

Mở **terminal thứ nhất**, tạo `~/devops-lab/08-mon/01/blackbox.sh`:

```bash
#!/usr/bin/env bash
# Probe black-box: mỗi 2 giây gọi API qua nginx như người dùng, ghi CSV.
set -uo pipefail          # KHÔNG dùng -e: probe phải chạy tiếp cả khi curl lỗi
url="${1:?Cách dùng: blackbox.sh <url>}"
out="${2:-blackbox.csv}"
echo "time,code,seconds" > "$out"
while true; do
  result=$(curl -o /dev/null -s --max-time 10 -w '%{http_code},%{time_total}' "$url")
  line="$(date +%H:%M:%S),$result"
  echo "$line" | tee -a "$out"
  sleep 2
done
```

```bash
chmod +x blackbox.sh
./blackbox.sh "$APP/api/tasks"
```

Để nó chạy suốt bài. Vì sao **không** có `set -e`: `curl` trả mã thoát khác 0 khi không kết nối được — với `-e`, probe sẽ tự thoát đúng lúc bạn cần nó nhất.

### Bước 2 — Mở endpoint `metrics` cho riêng buổi lab `[WSL]`

Không sửa `application.yml`. Dùng **biến môi trường** (relaxed binding — [hướng dẫn tạo app §5.1](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)) trong một file Compose tạm, **không commit**:

```bash
cd ~/projects/taskhub
cat > compose.lab-metrics.yaml <<'EOF'
# File tạm của bài 08-01 — KHÔNG commit. Xóa sau buổi lab.
services:
  taskhub:
    environment:
      MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE: health,info,metrics
EOF

docker compose -f compose.yaml -f compose.override.yaml -f compose.lab-metrics.yaml up -d taskhub
```

| Phần | Ý nghĩa |
|---|---|
| `-f ... -f ...` | Khi dùng `-f`, Compose **không** tự gộp `compose.override.yaml` nữa → phải liệt kê đủ. Repo của bạn còn ở cấu trúc v0 (chưa có `compose.override.yaml`)? Bỏ file đó khỏi lệnh |
| `MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE` | Ánh xạ tới `management.endpoints.web.exposure.include` |

> ⚠️ Lúc này `/actuator/metrics` cũng đi qua được nginx (nginx của v4 chưa chặn `/actuator/*`), và cổng nginx publish trên mọi địa chỉ của máy Windows. Đây là lý do bước dọn dẹp bắt buộc xóa file tạm, và lý do v5 thêm luật chặn `/actuator/*` ở nginx (chỉ chừa `health`).

Kiểm tra (gọi **bên trong** container):

```bash
docker compose exec -T taskhub curl -s localhost:8080/actuator/metrics | jq -r '.names[]' | head -30
```

Bạn sẽ thấy các nhóm tên: `http.server.requests`, `jvm.*`, `hikaricp.*`, `process.*`, `system.*`… Ghi vào `notes.md`: nhóm nào thuộc **RED** (service), nhóm nào thuộc **USE** (tài nguyên)?

### Bước 3 — Tạo traffic có cả request tốt lẫn lỗi `[WSL]`

Mở **terminal thứ hai**, tạo `gen-traffic.sh`:

```bash
#!/usr/bin/env bash
# Sinh traffic: request tốt (200/201), lỗi phía client (400, 404).
set -euo pipefail
app="${1:?Cách dùng: gen-traffic.sh <base-url>}"
for i in $(seq 1 50); do
  curl -s -o /dev/null "$app/api/tasks"                                       # 200
  curl -s -o /dev/null -X POST "$app/api/tasks" \
       -H 'Content-Type: application/json' -d "{\"title\":\"lab-08 task $i\"}"  # 201
  curl -s -o /dev/null "$app/api/tasks/$((i + 100000))"                       # 404
  curl -s -o /dev/null -X POST "$app/api/tasks" \
       -H 'Content-Type: application/json' -d '{"title":""}'                  # 400
done
echo "Xong: 200 request"
```

```bash
cd ~/devops-lab/08-mon/01
chmod +x gen-traffic.sh && ./gen-traffic.sh "$APP"
```

### Bước 4 — Đọc metric white-box `[WSL]`

```bash
cd ~/projects/taskhub
m() { docker compose exec -T taskhub curl -s "localhost:8080/actuator/metrics/$1"; }

m 'http.server.requests' | jq '.availableTags'
m 'http.server.requests?tag=status:201' | jq '.measurements'
m 'http.server.requests?tag=status:404' | jq '.measurements'
m 'http.server.requests?tag=uri:/api/tasks&tag=method:GET' | jq '.measurements'
m 'jvm.memory.used?tag=area:heap' | jq '.measurements'
m 'jvm.memory.max?tag=area:heap' | jq '.measurements'
m 'hikaricp.connections.active' | jq '.measurements'
```

Trả lời trong `notes.md`:

1. Có bao nhiêu request trả `201`, `400`, `404`? Khớp với 50/50/50 mà script đã gửi không? (Request `GET` ở bước 1 và 3 cũng được đếm — giải thích vì sao số `200` lớn hơn 50.)
2. Độ trễ trung bình của `GET /api/tasks` (`TOTAL_TIME / COUNT`)?
3. Heap đang dùng bao nhiêu % so với tối đa? Đây là tín hiệu nào trong 4 Golden Signals?
4. 404 và 400 có phải "lỗi" theo nghĩa SLO không? (Gợi ý: lỗi đó do ai gây ra — hệ thống hay người gọi?)

### Bước 5 — Sự cố A: database chết `[WSL]`

Để `blackbox.sh` chạy ở terminal 1. Ở terminal 2:

```bash
cd ~/projects/taskhub
docker compose stop postgres
sleep 60
```

Quan sát terminal 1 trong lúc chờ, rồi:

```bash
curl -s -w '\n%{http_code}\n' --max-time 40 "$APP/actuator/health"                          # qua nginx
docker compose exec -T taskhub curl -s -w '\n%{http_code}\n' --max-time 40 localhost:8080/actuator/health   # thẳng vào app
m 'hikaricp.connections.pending' | jq '.measurements'
m 'http.server.requests?tag=outcome:SERVER_ERROR' | jq '.measurements'
docker compose start postgres
```

Ghi vào `notes.md`:

- Black-box thấy gì (mã nào, mất bao lâu mỗi lần gọi)? So với kết quả thật đã ghi ở [lab Docker — thí nghiệm 3](../04-DOCKER/labs/lab-springboot-postgres-compose/README.md): request treo khoảng 30 giây (thời gian chờ mặc định của connection pool HikariCP) rồi nginx trả `504`.
- White-box thấy gì? Metric nào báo hiệu **trước** khi người dùng nhận lỗi?
- Sau khi `start postgres`, app có tự hồi phục không, mất bao lâu?

### Bước 6 — Sự cố B: nginx chết `[WSL]`

```bash
docker compose stop nginx
sleep 20
m 'http.server.requests' | jq '.measurements'
docker compose exec -T taskhub curl -s localhost:8080/actuator/health
docker compose start nginx
```

- Black-box: dòng `000` — người dùng **hoàn toàn** không vào được.
- White-box: app báo `UP`, metric không có gì bất thường (chỉ là không có request mới).

Viết một câu kết luận vào `notes.md`: "Nếu chỉ giám sát white-box, sự cố này sẽ…".

### Bước 7 — Cardinality trong thực tế `[WSL]`

```bash
for i in $(seq 1 30); do curl -s -o /dev/null "$APP/api/tasks/$i"; done
for p in abc xyz random-$RANDOM; do curl -s -o /dev/null "$APP/$p"; done
m 'http.server.requests' | jq -r '.availableTags[] | select(.tag=="uri") | .values[]'
```

Bạn vừa gọi hơn 30 đường dẫn khác nhau. Danh sách `uri` có hơn 30 giá trị không? Ghi lại giá trị `uri` của các request tới đường dẫn **không tồn tại** (`/abc`…) — Spring gom chúng vào một giá trị chung. Giải thích vì sao thiết kế này bảo vệ Prometheus (mục 4.9).

### Bước 8 — Viết `docs/slo.md` cho `taskhub` `[WSL]`

```bash
cd ~/projects/taskhub
git switch -c docs/slo
```

Tạo `docs/slo.md` theo khung dưới đây và **tự điền** phần trong `<...>`:

```markdown
# SLO của taskhub

- Ngày: <YYYY-MM-DD> · Cửa sổ đo: 30 ngày cuộn
- Không có SLA (dự án cá nhân). SLO dùng để quyết định: phát hành tiếp hay ưu tiên ổn định.

| # | SLI (đo cái gì, đo ở đâu) | SLO | Error budget / 30 ngày | Vì sao chọn con số này |
|---|---|---|---|---|
| 1 | Độ sẵn sàng: tỷ lệ request `/api/*` KHÔNG trả 5xx, đo ở app (`http_server_requests`) | <...>% | <... phút nếu ngừng hoàn toàn> | <...> |
| 2 | Độ trễ: tỷ lệ request `/api/*` thành công xử lý dưới <... ms> | <...>% | <...> | <...> |
| 3 | Black-box: tỷ lệ phút probe bên ngoài gọi `/actuator/health` qua URL công khai thành công | <...>% | <...> | <...> |

## Không tính vào SLI
- <ví dụ: lỗi 4xx do người gọi; request tới /actuator/*>

## Khi error budget còn dưới 25%
- <bạn sẽ làm gì>

## Hiện trạng đo được
- Chưa đo — sẽ có số liệu thật sau khi Prometheus chạy (bài 02, Lab 01).
```

Gợi ý tự kiểm tra: SLO 1 có thực tế với **một** EC2, deploy kiểu recreate không? SLI 3 đo được thứ gì mà SLI 1 bỏ sót (nhớ lại bước 6)?

```bash
git add docs/slo.md
git commit -m "docs: define initial SLOs for taskhub"
git push -u origin docs/slo
```

Mở PR, chờ CI xanh, squash merge — như mọi thay đổi khác từ tuần 6.

### Bước 9 — Ghi một mục nhật ký

Viết một mục `troubleshooting-journal.md` cho sự cố A (bước 5) theo [mẫu nhật ký](../00-ROADMAP/templates/troubleshooting-journal-template.md): triệu chứng nhìn từ black-box, bằng chứng từ white-box, nguyên nhân, cách khôi phục.

### Dọn dẹp

```bash
# Terminal 1: Ctrl+C để dừng blackbox.sh
cd ~/projects/taskhub
rm compose.lab-metrics.yaml
docker compose up -d                       # tạo lại taskhub với cấu hình gốc (không mở metrics)
docker compose exec -T taskhub curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/actuator/metrics   # 404
git status                                 # không còn file tạm nào
```

Các task `lab-08 task N` đã tạo nằm trong database dev — giữ lại cũng không sao, chúng sẽ thành dữ liệu cho dashboard ở bài sau.

---

## 10. Kết quả mong đợi

| Bước | Kết quả |
|---|---|
| 1 | `blackbox.csv` có một dòng mỗi 2 giây, mã `200`, thời gian vài chục mili giây |
| 2 | `/actuator/metrics` trả danh sách tên metric khi gọi trong container |
| 4 | Số request `201`, `400`, `404` mỗi loại 50; độ trễ trung bình `GET /api/tasks` cỡ mili giây đến vài chục mili giây; heap dùng một phần của tối đa |
| 5 | Black-box: request treo ~30 giây rồi `504` (từ nginx, vì `proxy_read_timeout` cũng là 30 giây). Health gọi **qua nginx** cũng thường nhận `504`; gọi **thẳng vào app** thì nhận `{"status":"DOWN"...}` + `503` sau khoảng 30 giây chờ pool. Sau `start postgres`, app tự kết nối lại, không cần khởi động lại |
| 6 | Black-box: `000`. White-box: `UP`, không có lỗi — minh chứng white-box mù trước lỗi ngoài app |
| 7 | Danh sách `uri` chỉ có vài giá trị dạng mẫu (`/api/tasks/{id}`…), đường dẫn lạ gom về một giá trị chung |
| 8 | `docs/slo.md` đã merge vào `main` qua PR, có 3 SLI với con số và lý do |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `/actuator/metrics` trả `404` | Endpoint chưa được mở, hoặc container chưa được tạo lại với biến mới | Kiểm tra `docker compose exec taskhub env \| grep MANAGEMENT`; chạy lại lệnh `up -d` ở bước 2 với đủ các `-f` |
| `docker compose up` báo `set TASKHUB_IMAGE_TAG in .env` | `compose.yaml` từ v2 bắt buộc biến này | Thêm `TASKHUB_IMAGE_TAG=dev` vào `.env` trên laptop (đã ghi chú trong `compose.override.yaml`) |
| Bước 2 kéo image từ GHCR thay vì dùng image build local | Quên `-f compose.override.yaml` nên mất phần `build:` | Liệt kê đủ cả ba file `-f` |
| `jq: command not found` | Chưa cài | `sudo apt install -y jq` |
| `the input device is not a TTY` | Dùng `exec` không có `-T` khi nối pipe | Thêm `-T` |
| `port is already allocated` khi đổi `NGINX_HOST_PORT` | Cổng mới cũng đã bị container khác chiếm | Chọn cổng khác, kiểm tra bằng `docker ps --format '{{.Ports}}'` |
| `blackbox.sh` tự thoát khi app lỗi | Thêm nhầm `set -e` | Bỏ `-e` (đã giải thích ở bước 1) |
| Số `200` ở bước 4 lớn hơn nhiều so với 50 | Probe bước 1 vẫn đang gọi `GET /api/tasks` mỗi 2 giây | Đúng như thiết kế — đây là câu hỏi 1 của bước 4 |

---

## 12. Đọc log và xử lý lỗi

Sự cố A (database chết) là dịp tập đi từ **triệu chứng black-box** → **bằng chứng white-box** → **log**:

```bash
docker compose logs --since 3m nginx | grep -i 'upstream'
docker compose logs --since 3m taskhub | grep -iE 'hikari|connection|ERROR' | tail -20
```

Những dòng nên tìm (chữ chính xác có thể khác theo phiên bản):

| Nơi | Dòng log | Nghĩa |
|---|---|---|
| nginx | `upstream timed out (110: Connection timed out) while reading response header from upstream` | nginx chờ `taskhub` quá `proxy_read_timeout` → trả `504` cho người dùng |
| taskhub | `HikariPool-1 - Connection is not available, request timed out after 30000ms` | Pool chờ đủ 30 giây mà không lấy được kết nối tới PostgreSQL |
| taskhub | `Connection to postgres:5432 refused` hoặc `UnknownHostException: postgres` | PostgreSQL đã dừng (container còn tồn tại nhưng không lắng nghe) hoặc đã bị xóa khỏi network |

**Thứ tự đọc khi có sự cố** — giữ nguyên thói quen này cho cả module:

1. **Triệu chứng** người dùng thấy (black-box): mã gì, từ lúc nào?
2. **Metric** (white-box): tín hiệu nào bất thường, bắt đầu cùng lúc không?
3. **Log** của thành phần nghi ngờ, **đúng khoảng thời gian đó** (`--since`).
4. Ghi giả thuyết → kiểm chứng → khắc phục → ghi nhật ký.

Bài [06](06-incident-response.md) biến thứ tự này thành quy trình xử lý sự cố đầy đủ.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Monitoring khác observability ở điểm nào? Cho một câu hỏi về `taskhub` mà monitoring thông thường không trả lời được.
2. Metric và log, cái nào hợp để **cảnh báo** hơn? Vì sao?
3. Prometheus dùng pull. Nêu một ưu điểm của pull khi một target chết. Khi nào cần Pushgateway (hoặc textfile collector)?
4. Trong bài thực hành, sự cố nào chỉ black-box phát hiện được? Sự cố nào white-box báo hiệu **sớm hơn** black-box?
5. Nêu 4 Golden Signals và một metric cụ thể của `taskhub` cho mỗi tín hiệu.
6. Vì sao nên tách độ trễ của request **thành công** và request **lỗi**?
7. RED và USE khác nhau thế nào? Áp dụng mỗi phương pháp cho thành phần nào của `taskhub`?
8. Định nghĩa SLI, SLO, SLA. Vì sao `taskhub` không có SLA? Ở công ty thật, SLA thường chặt hơn hay lỏng hơn SLO nội bộ?
9. SLO 99,9% trong 30 ngày cho phép ngừng hoàn toàn bao nhiêu phút? Trình bày phép tính.
10. Error budget dùng để ra quyết định gì?
11. "CPU > 80%" có phải alert tốt không? Viết lại thành alert theo triệu chứng.
12. `for: 1m` trong alert rule để làm gì? Nếu bỏ đi thì sao?
13. Giải thích cardinality. Tính số time series nếu thêm label `user_id` (10.000 người dùng) vào metric request ở mục 4.9.
14. Vì sao Prometheus chạy cùng EC2 với app không đủ để cảnh báo khi EC2 chết? Dự án xử lý thế nào?

---

## 14. Bài tập tự làm

**Bài 1 — Golden Signals cho nginx.** nginx là service đứng trước `taskhub`. Liệt kê 4 Golden Signals cho nginx, và với mỗi tín hiệu, nêu bạn sẽ lấy dữ liệu từ đâu (gợi ý: access log có mã trả về và thời gian; module `stub_status` 🟨). Tín hiệu nào hiện tại bạn **chưa** đo được?

**Bài 2 — Error budget đã đốt.** Với SLO 99,5% trong 30 ngày: tháng này đã có một sự cố database 18 phút, 12 lần deploy mỗi lần ngừng 40 giây, và một lần EC2 bảo trì 6 phút. Còn bao nhiêu phần trăm ngân sách? Theo `docs/slo.md` của bạn, có nên phát hành tính năng mới tuần này không?

**Bài 3 — Phân loại alert.** Phân loại từng alert sau thành *page* (gọi ngay), *ticket* (xử lý trong giờ làm) hay *xóa đi*, kèm lý do: (a) RAM container `taskhub` > 90% giới hạn trong 10 phút; (b) tỷ lệ 5xx > 10% trong 5 phút; (c) có một request mất hơn 2 giây; (d) chứng chỉ TLS hết hạn trong 14 ngày; (e) backup gần nhất cũ hơn 26 giờ; (f) CPU EC2 > 70% trong 1 phút.

**Bài 4 — Probe có ngưỡng.** Sửa `blackbox.sh` để in thêm cột `ok`/`slow`/`fail`: `fail` khi mã khác 2xx hoặc `000`, `slow` khi thành công nhưng quá 300 ms. Chạy lại sự cố A và đếm số dòng mỗi loại bằng `awk`. Từ đó tính "tỷ lệ probe thành công" trong khoảng thời gian thử nghiệm.

**Bài 5 — Lỗi ngầm.** Nghĩ ra một tình huống `taskhub` trả `200` nhưng kết quả **sai** (lỗi ngầm — implicit error). Monitoring theo mã HTTP có bắt được không? Đề xuất một cách phát hiện (gợi ý: probe black-box kiểm tra **nội dung** trả về).

**Bài 6 — So sánh ba hướng.** Viết nửa trang (đưa vào bản nháp ADR-0010 của v5): nếu `taskhub` là sản phẩm của một công ty 5 người, bạn chọn CloudWatch, tự vận hành hay SaaS? Nêu ít nhất 3 tiêu chí ở mục 4.11 và đánh đổi của lựa chọn.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được monitoring / logging / observability bằng ví dụ của `taskhub`, không đọc tài liệu.
- [ ] Nêu đúng 4 Golden Signals và một metric thật cho mỗi tín hiệu.
- [ ] Phân biệt RED và USE, biết dùng cái nào cho thành phần nào.
- [ ] Tính được error budget theo phút cho một SLO bất kỳ.
- [ ] Tự làm được probe black-box và đọc được metric white-box; giải thích được mỗi cách mù ở đâu (sự cố A và B).
- [ ] Giải thích được vì sao alert "CPU > 80%" thường là alert tệ, và viết được alert theo triệu chứng.
- [ ] Tính được số time series khi thêm một label; biết label nào không được dùng.
- [ ] Trả lời được "ai giám sát hệ thống giám sát" cho kiến trúc v5.
- [ ] `docs/slo.md` đã merge vào `main` với 3 SLI có con số và lý do.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Google SRE book — Chapter 6: Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) | Golden Signals, white-box/black-box, "every page should be actionable" | 2026-10-31 |
| [Google SRE book — Chapter 4: Service Level Objectives](https://sre.google/sre-book/service-level-objectives/) | Định nghĩa SLI, SLO, SLA | 2026-10-31 |
| [Google SRE book — Chapter 10: Practical Alerting](https://sre.google/sre-book/practical-alerting/) | Đọc thêm về alert từ dữ liệu time series | 2026-10-31 |
| [Google SRE workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) | Burn rate (🟦) | 2026-10-31 |
| [Brendan Gregg — The USE Method](https://www.brendangregg.com/usemethod.html) | Utilization, Saturation, Errors | 2026-10-31 |
| [Grafana blog — The RED Method](https://grafana.com/blog/the-red-method-how-to-instrument-your-services/) | Rate, Errors, Duration (Tom Wilkie) | 2026-10-31 |
| [Prometheus — Overview](https://prometheus.io/docs/introduction/overview/) | Mô hình pull, Pushgateway, thành phần | 2026-10-31 |
| [Prometheus — Metric and label naming](https://prometheus.io/docs/practices/naming/) | Cảnh báo về label có nhiều giá trị (cardinality) | 2026-10-31 |
| [Spring Boot — Metrics](https://docs.spring.io/spring-boot/reference/actuator/metrics.html) | `/actuator/metrics`, lọc bằng `tag=KEY:VALUE`, `http.server.requests` | 2026-10-31 |
| [Grafana Loki — Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Promtail EOL 2/3/2026 | 2026-10-31 |
| [Grafana Alloy — Introduction](https://grafana.com/docs/alloy/latest/introduction/) | Alloy là gì | 2026-10-31 |
