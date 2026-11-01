# Lời giải — Bài 01: Monitoring, logging, observability

> ⚠️ Chỉ mở sau khi đã tự làm. Bài: [01-monitoring-logging-observability.md](../01-monitoring-logging-observability.md)

## Mục lục

- [Câu hỏi trong bài thực hành](#câu-hỏi-trong-bài-thực-hành)
- [Câu hỏi kiểm tra kiến thức (mục 13)](#câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Bài tập tự làm (mục 14)](#bài-tập-tự-làm-mục-14)

---

## Câu hỏi trong bài thực hành

**Bước 2 — RED hay USE?**
- RED (service): `http.server.requests` (rate, lỗi theo `status`/`outcome`, thời gian).
- USE (tài nguyên): `jvm.memory.*`, `jvm.gc.*`, `jvm.threads.*` (RAM/luồng của JVM), `hikaricp.connections.*` (connection pool — `active` là utilization, `pending` là saturation, `timeout` là errors), `process.cpu.usage`, `system.cpu.usage`, `disk.free`/`disk.total`.

**Bước 4.**
1. `201`, `400`, `404` mỗi loại 50 (script gửi đúng 50 mỗi loại). Số `200` lớn hơn 50 vì probe ở bước 1 gọi `GET /api/tasks` mỗi 2 giây suốt buổi, và chính bạn cũng gọi thử. Nhận xét: **metric đếm mọi request**, không phân biệt ai gọi — probe cũng là traffic.
2. Độ trễ trung bình = `TOTAL_TIME / COUNT` của bộ lọc `uri:/api/tasks&method:GET`. Trên laptop thường vài mili giây đến vài chục mili giây; con số cụ thể tùy máy. Lưu ý trung bình che giấu request chậm — bài 02 dùng phân vị (p95).
3. Heap used / heap max — tín hiệu **saturation**. Với `mem_limit: 768m` và `-XX:MaxRAMPercentage=75.0`, heap tối đa khoảng 75% của 768 MiB.
4. Thường **không**. 400 (dữ liệu sai) và 404 (không tồn tại) là lỗi do **người gọi**; hệ thống đã xử lý đúng. SLI độ sẵn sàng đếm lỗi **của hệ thống** (5xx). Ngoại lệ: nếu 404 tăng vọt sau một lần deploy (do đổi đường dẫn API), đó là lỗi của bạn — đáng có một alert riêng, nhưng không tính vào SLI sẵn sàng.

**Bước 5 — database chết.**
- Black-box: mỗi request treo khoảng 30 giây rồi nhận `504` (nginx bỏ cuộc vì `proxy_read_timeout 30s`, cùng lúc HikariCP hết `connection-timeout` 30 giây). Probe in thời gian ~30 giây thay vì ~0,01 giây.
- White-box báo **sớm hơn**: `hikaricp.connections.pending` > 0 (request đang xếp hàng chờ kết nối) và độ trễ tăng ngay lập tức, trước khi người dùng nhận mã lỗi; sau đó `outcome:SERVER_ERROR` tăng. Gọi thẳng `/actuator/health` trong container nhận `DOWN` + `503`.
- Sau `start postgres`, app tự hồi phục (pool tạo lại kết nối), thường trong vài giây sau khi PostgreSQL healthy. Không cần restart app.

**Bước 6 — nginx chết.** Kết luận mẫu: "Nếu chỉ giám sát white-box, sự cố này sẽ **không bị phát hiện**: app báo `UP`, không có request lỗi nào (vì không có request nào tới được app), trong khi 100% người dùng không vào được. Cần probe black-box đi qua đúng đường của người dùng."

**Bước 7 — cardinality.** Dù gọi hơn 30 đường dẫn, `uri` chỉ có vài giá trị dạng **mẫu**: `/api/tasks`, `/api/tasks/{id}`… Request tới đường dẫn không khớp handler nào được gom vào một giá trị chung (Spring Boot dùng giá trị kiểu `UNKNOWN` hoặc `/**` tùy phiên bản và cấu hình — ghi lại đúng giá trị bạn thấy). Nhờ vậy số time series **không phụ thuộc** vào số task hay số đường dẫn rác mà bot quét gửi tới — Prometheus được bảo vệ khỏi bùng nổ cardinality.

**Bước 8 — `docs/slo.md` mẫu** (một cách điền hợp lý, không phải đáp án duy nhất):

| # | SLI | SLO | Error budget / 30 ngày | Lý do |
|---|---|---|---|---|
| 1 | Tỷ lệ request `/api/*` không trả 5xx, đo ở app | 99,5% | 216 phút nếu ngừng hoàn toàn | Một EC2, deploy recreate mất vài chục giây mỗi lần; 99,9% (43 phút) là không thực tế |
| 2 | Tỷ lệ request `/api/*` thành công xử lý dưới 300 ms | 95% | 5% request được phép chậm hơn | Laptop đo được vài chục ms; 300 ms để dư cho EC2 và lúc JVM mới khởi động |
| 3 | Tỷ lệ phút probe bên ngoài gọi `/actuator/health` qua URL công khai thành công | 99% | 432 phút | Đo cả nginx, Security Group, mạng — thứ SLI 1 không thấy (bước 6). Đặt lỏng hơn vì probe bên ngoài còn chịu lỗi mạng của chính nó |

Không tính: 4xx; `/actuator/*`; request trong cửa sổ bảo trì đã báo trước (nếu bạn quyết định có). Khi ngân sách còn dưới 25%: dừng tính năng mới, ưu tiên các việc như giảm downtime khi deploy, thêm alert còn thiếu.

---

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Monitoring theo dõi những thứ **đã biết** cần theo dõi (known unknowns) và cảnh báo khi vượt ngưỡng. Observability là khả năng **đặt câu hỏi mới** cho hệ thống mà không cần sửa code. Ví dụ: "Request chậm có tập trung ở những task có mô tả rất dài không?" — dashboard tỷ lệ lỗi/độ trễ chung không trả lời được; cần log hoặc trace đủ chi tiết (độ dài mô tả, thời gian truy vấn) để lọc và so sánh.

**2.** Metric. Metric là con số đã tổng hợp, rẻ để lưu và truy vấn liên tục, dễ so với ngưỡng theo thời gian (`rate`, `for: 5m`). Log phải quét nhiều dữ liệu hơn, đắt và chậm hơn khi đánh giá mỗi 15–30 giây. Log dùng để **tìm nguyên nhân** sau khi metric báo có vấn đề.

**3.** Target chết thì lần scrape thất bại → Prometheus tự sinh `up{job=...} = 0` → biết ngay, không cần target "báo tin". Với push, target im lặng có thể là đã chết hoặc chỉ là không có gì để gửi. Pushgateway (hoặc textfile collector của node_exporter) dùng cho **job chạy ngắn** kết thúc trước khi kịp bị scrape — như script backup.

**4.** Chỉ black-box phát hiện: sự cố B (nginx chết — app vẫn `UP`). White-box báo sớm hơn: sự cố A — `hikaricp.connections.pending` và độ trễ tăng ngay khi database mất, trước khi người dùng nhận `504` sau 30 giây.

**5.**
- Latency: p95 của `http_server_requests_seconds` (từ histogram).
- Traffic: `rate(http_server_requests_seconds_count[5m])`.
- Errors: tỷ lệ `status=~"5.."` trên tổng request.
- Saturation: heap JVM / max, `hikaricp_connections_pending`, % ổ đĩa (node_exporter), RAM container so với `mem_limit`.

**6.** Request lỗi thường trả về **rất nhanh** (ví dụ 500 sau 2 ms vì ném exception ngay). Gộp chung thì độ trễ trung bình/phân vị **giảm** đúng lúc hệ thống đang hỏng — dashboard trông "nhanh hơn" khi tình hình tệ hơn. Ngược lại, timeout làm request lỗi rất chậm và kéo lệch độ trễ của request thành công.

**7.** RED (Rate, Errors, Duration) cho **service** nhận request: `taskhub`, nginx. USE (Utilization, Saturation, Errors) cho **tài nguyên**: CPU, RAM, ổ đĩa của EC2; heap JVM; connection pool HikariCP. RED trả lời "người dùng có vui không", USE trả lời "máy có ổn không".

**8.** SLI: phép đo chất lượng dịch vụ. SLO: mục tiêu cho SLI trong một khoảng thời gian. SLA: hợp đồng với khách hàng có hậu quả (thường là hoàn tiền) khi vi phạm. `taskhub` là dự án cá nhân, không có khách hàng trả tiền, không có hợp đồng → không có SLA. Ở công ty, SLA thường **lỏng hơn** SLO nội bộ (ví dụ SLO 99,9%, SLA 99,5%): đội ngũ được cảnh báo và xử lý trước khi chạm ngưỡng phải bồi thường.

**9.** 30 ngày × 24 giờ × 60 phút = 43.200 phút. Error budget 0,1% → 43.200 × 0,001 = **43,2 phút**.

**10.** Cân bằng giữa **tốc độ phát hành** và **độ ổn định**. Còn ngân sách → được phát hành, thử nghiệm. Gần hết hoặc hết → dừng tính năng mới, ưu tiên sửa nguyên nhân gây lỗi. Nó biến tranh luận "ổn định hay tính năng" thành quyết định dựa trên số liệu.

**11.** Không tốt: CPU cao không có nghĩa người dùng bị ảnh hưởng (có thể app vẫn nhanh), và CPU bình thường không có nghĩa mọi thứ ổn. Viết lại theo triệu chứng: "p95 độ trễ của `/api/*` > 500 ms trong 10 phút" hoặc "tỷ lệ 5xx > 5% trong 5 phút". CPU cao chuyển thành metric trên dashboard để **tìm nguyên nhân**, cùng lắm là ticket.

**12.** `for: 1m`: điều kiện phải **đúng liên tục 1 phút** thì alert mới chuyển từ `pending` sang `firing`. Mục đích là tránh báo động vì một lần scrape lỗi hay app khởi động lại vài giây. Bỏ đi thì mỗi lần chập chờn (một lần scrape timeout, một lần deploy recreate) đều gửi thông báo → alert fatigue.

**13.** Cardinality là số lượng time series riêng biệt = số tổ hợp giá trị label. Hiện tại 4 × 3 × 6 = 72 series. Thêm `user_id` với 10.000 giá trị: 72 × 10.000 = **720.000 series** cho riêng metric này (thực tế có nhiều series hơn nữa vì histogram có thêm series cho mỗi bucket) — RAM và thời gian truy vấn của Prometheus tăng theo.

**14.** Prometheus và Alertmanager chạy **trên chính EC2 đó**: EC2 chết thì chúng chết theo, không còn ai đánh giá rule hay gửi thông báo. Dự án giữ alarm CloudWatch `StatusCheckFailed` → SNS email từ v3: nó chạy trên hạ tầng của AWS, độc lập với EC2. (Thêm được: dịch vụ uptime check bên ngoài, dead man's switch.)

---

## Bài tập tự làm (mục 14)

**Bài 1 — Golden Signals cho nginx.**

| Tín hiệu | Nguồn dữ liệu |
|---|---|
| Latency | Access log với biến `$request_time` (và `$upstream_response_time` để tách thời gian của `taskhub`) |
| Traffic | Đếm dòng access log theo thời gian; hoặc `stub_status` (🟨 — tổng request, kết nối đang mở) |
| Errors | Mã trả về trong access log (`5xx` do nginx tự sinh như `502`/`504`) |
| Saturation | Số kết nối đang hoạt động so với `worker_connections` (`stub_status`); CPU/RAM container |

Hiện tại chưa đo được gì trong số này thành **metric** — chỉ có log. Bài 04 đưa access log vào Loki (có thể đếm bằng LogQL); 🟨 một exporter cho nginx là bước tiếp theo nếu muốn có metric.

**Bài 2 — Error budget đã đốt.**
- Ngân sách: 216 phút.
- Đã dùng: 18 + 12 × 40 giây (= 480 giây = 8 phút) + 6 = **32 phút**.
- Còn: 216 − 32 = 184 phút = **85,2%** ngân sách.
- Còn nhiều hơn ngưỡng 25% → được phép phát hành. Nhận xét thêm: deploy chiếm 8 phút/tháng — nếu số lần deploy tăng gấp 5, riêng deploy đã tiêu 40 phút; đây là lý do để cân nhắc blue/green ([CI/CD bài 05](../../05-CICD/05-deployment-strategies-rollback.md)).

**Bài 3 — Phân loại alert.**
- (a) RAM container > 90% giới hạn 10 phút: **ticket** — dấu hiệu saturation, có nguy cơ OOM, nhưng người dùng chưa bị ảnh hưởng. Nếu thường xuyên OOM kill → xem lại `mem_limit`.
- (b) 5xx > 10% trong 5 phút: **page** — triệu chứng người dùng chịu trực tiếp.
- (c) Một request > 2 giây: **xóa đi** — một request đơn lẻ không nói lên gì; dùng phân vị (p95) trong một khoảng thời gian.
- (d) Chứng chỉ TLS hết hạn trong 14 ngày: **ticket** — còn thời gian, nhưng nếu bỏ qua sẽ thành sự cố toàn bộ.
- (e) Backup cũ hơn 26 giờ: **ticket** (ưu tiên cao) — chưa ai bị ảnh hưởng, nhưng nếu database hỏng lúc này thì mất dữ liệu nhiều hơn RPO cho phép.
- (f) CPU > 70% trong 1 phút: **xóa đi** — vừa là nguyên nhân chứ không phải triệu chứng, vừa quá ngắn để có ý nghĩa.

**Bài 4 — Probe có ngưỡng.** Một cách viết:

```bash
#!/usr/bin/env bash
set -uo pipefail
url="${1:?Cách dùng: blackbox.sh <url>}"
out="${2:-blackbox.csv}"
echo "time,code,seconds,state" > "$out"
while true; do
  read -r code secs < <(curl -o /dev/null -s --max-time 10 -w '%{http_code} %{time_total}' "$url")
  if [[ "$code" != 2* ]]; then
    state=fail
  elif awk -v s="$secs" 'BEGIN { exit !(s > 0.3) }'; then
    state=slow
  else
    state=ok
  fi
  echo "$(date +%H:%M:%S),$code,$secs,$state" | tee -a "$out"
  sleep 2
done
```

Đếm và tính tỷ lệ:

```bash
awk -F, 'NR > 1 { n[$4]++; total++ } END { for (s in n) printf "%s=%d\n", s, n[s]; printf "ok_ratio=%.1f%%\n", 100 * n["ok"] / total }' blackbox.csv
```

Bash không so sánh được số thực, nên phần so sánh `> 0.3` giao cho `awk` (mã thoát 0 khi điều kiện đúng). Trong sự cố A, các dòng lúc database chết là `fail` (mã `504` sau ~30 giây). Tỷ lệ `ok` phụ thuộc thời gian bạn để sự cố kéo dài.

**Bài 5 — Lỗi ngầm.** Ví dụ: sau một thay đổi code, `GET /api/tasks` trả `200` với danh sách **rỗng** dù database có dữ liệu (lỗi truy vấn, sai điều kiện lọc); hoặc trả dữ liệu của bộ lọc sai. Monitoring theo mã HTTP không bắt được (mọi thứ đều 200). Cách phát hiện: probe black-box kiểm tra **nội dung** — ví dụ tạo một task "canary" cố định rồi probe gọi `GET /api/tasks/<id-canary>` và kiểm tra trường `title` đúng giá trị mong đợi (`jq -e '.title == "canary"'`); hoặc smoke test sau deploy kiểm tra nội dung chứ không chỉ mã.

**Bài 6 — So sánh ba hướng.** Không có đáp án duy nhất. Bài đạt khi:
- Dùng ít nhất 3 tiêu chí (công vận hành, chi phí, gắn với nhà cung cấp, chết cùng máy chủ, kỹ năng của đội).
- Có kết luận rõ và **đánh đổi trung thực**. Ví dụ: "Công ty 5 người, không ai chuyên vận hành → chọn SaaS hoặc CloudWatch để không tốn công nuôi Prometheus/Loki; đánh đổi là chi phí tăng theo dữ liệu và gắn với nhà cung cấp. Dự án học tập `taskhub` thì ngược lại: chọn tự vận hành vì mục tiêu là hiểu từng thành phần."
- Nhắc tới việc cần một đường cảnh báo độc lập (mục 4.12) dù chọn hướng nào.
