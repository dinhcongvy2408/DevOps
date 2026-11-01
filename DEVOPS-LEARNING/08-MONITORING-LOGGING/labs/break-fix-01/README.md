# Break-fix Observability #1 — "Hệ thống giám sát im lặng"

> ⏱️ 90–150 phút · Chi phí: **0 USD** (chỉ dùng Docker trên máy bạn) · Môi trường: `[WSL]` + Docker Desktop (đã bật WSL integration), `[Browser]`
> Kiến thức cần có: Module 08 bài [02](../../02-metrics-prometheus.md), [03](../../03-grafana-dashboards-alerting.md), [04](../../04-centralized-logging.md)
> Lời giải: [solutions/break-fix-01-solution.md](../../solutions/break-fix-01-solution.md) — **chỉ mở khi đã xong, hoặc đã kẹt quá 30 phút sau khi xem hết gợi ý.**

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
- [2. Vì sao bài này không dùng taskhub](#2-vì-sao-bài-này-không-dùng-taskhub)
- [3. Khởi tạo môi trường](#3-khởi-tạo-môi-trường)
- [4. Công cụ bạn được dùng](#4-công-cụ-bạn-được-dùng)
- [5. Các ticket](#5-các-ticket)
- [6. Luật chơi](#6-luật-chơi)
- [7. Tiêu chí hoàn thành](#7-tiêu-chí-hoàn-thành)
- [8. Sản phẩm phải nộp](#8-sản-phẩm-phải-nộp)
- [9. Gợi ý](#9-gợi-ý)
- [10. Liên hệ với taskhub v5](#10-liên-hệ-với-taskhub-v5)
- [11. Dọn dẹp](#11-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Bối cảnh

Đồng nghiệp vừa dựng xong bộ giám sát cho một dịch vụ nhỏ (`bf08`) rồi chuyển team. Bộ giám sát gồm:

```text
 app demo ──/metrics (8000)──► Prometheus ──rules──► Alertmanager ──► webhook-debug (thay cho Telegram)
   │                              ▲  ▲
   │ log JSON ra stdout           │  └── node-exporter, loki, alloy, alertmanager (tự giám sát)
   ▼                              │
 Docker ──► Alloy ──push──► Loki ─┴──► Grafana (Explore, data source Prometheus + Loki)
```

Trên giấy mọi thứ đều có. Thực tế thì **không ai nhận được cảnh báo nào**, và hôm qua dịch vụ bị dừng để bảo trì 20 phút mà hệ thống giám sát "im lặng". Trưởng nhóm giao cho bạn ba ticket ở [mục 5](#5-các-ticket).

Đây là kiểu sự cố đặc biệt nguy hiểm: **hệ thống giám sát hỏng không tự báo là nó hỏng**. Bạn sẽ luyện thói quen quan trọng nhất của người vận hành: không tin "không có cảnh báo = không có sự cố", mà **chứng minh** từng khâu trong đường đi của dữ liệu.

---

## 2. Vì sao bài này không dùng taskhub

- **Tự chứa, dựng lại trong 2 phút.** App demo là một file Python ~70 dòng (thư viện `prometheus_client`), không cần build Spring Boot hay PostgreSQL.
- **Cùng cơ chế.** Prometheus, Alertmanager, Loki, Alloy, Grafana ở đây là **cùng phiên bản** với bộ giám sát taskhub v5. Mọi lỗi trong bài đều có bản tương đương ở v5 ([mục 10](#10-liên-hệ-với-taskhub-v5)).
- **Miễn phí, làm lại vô hạn.**

---

## 3. Khởi tạo môi trường

**Điều kiện:**

- `docker ps` chạy được **trong WSL**. Nếu báo `Cannot connect to the Docker daemon`, bật WSL integration theo [Docker bài 01](../../../04-DOCKER/01-vm-vs-container-architecture.md).
- Máy còn ~1 GB RAM trống (8 container nhỏ, có `mem_limit`).
- Các cổng mặc định còn trống: 13000 (Grafana), 19090 (Prometheus), 19093 (Alertmanager), 15001 (webhook-debug), 13100 (Loki), 18088 (app). Tất cả chỉ mở trên `127.0.0.1`. Nếu cổng nào bị chiếm (lỗi `port is already allocated`), dọn dẹp rồi chạy lại với cổng khác, ví dụ `BF08_GRAFANA_PORT=23000 bash setup.sh`. Script ghi các cổng vào file `.env` của lab để mọi lệnh `docker compose` sau đó dùng lại.

`[WSL]` — copy script về và chạy:

```bash
mkdir -p ~/devops-lab/08-monitoring/tools && cd ~/devops-lab/08-monitoring/tools
# Đổi đường dẫn cho đúng nơi bạn lưu DEVOPS-LEARNING
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/08-MONITORING-LOGGING/labs/break-fix-01/setup.sh .
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/08-MONITORING-LOGGING/labs/break-fix-01/verify.sh .
sed -i 's/\r$//' setup.sh verify.sh     # phòng file bị đổi sang CRLF khi copy từ Windows
bash setup.sh
```

Script tạo thư mục `~/devops-lab/08-monitoring/bf08` (mọi file cấu hình nằm ở đây), build 2 image nhỏ (`bf08-app:local`, `bf08-webhook:local`) và chạy `docker compose up -d`. Nó **từ chối chạy** nếu thư mục hoặc container của project `bf08` đã tồn tại.

> 🚫 **Đừng đọc `setup.sh` trước khi làm xong.** Cấu hình có lỗi nằm trong thư mục `bf08` — đọc, sửa ở đó như một người vận hành thật.

Kiểm tra tiến độ bất kỳ lúc nào (chỉ đọc):

```bash
bash ~/devops-lab/08-monitoring/tools/verify.sh          # 7 mục, vài giây
bash ~/devops-lab/08-monitoring/tools/verify.sh --e2e    # thêm thử nghiệm thật: dừng app ~3–4 phút
```

---

## 4. Công cụ bạn được dùng

| Mục đích | Công cụ |
|---|---|
| Trạng thái scrape | Prometheus UI → **Status → Targets** (cột *State*, *Error*) · `curl -s 127.0.0.1:19090/api/v1/targets` |
| Rule đã nạp, đang pending/firing | Prometheus UI → **Alerts** và **Status → Rules** |
| Chạy thử PromQL | Prometheus UI → **Query** (thử từng phần của biểu thức) |
| Cảnh báo Alertmanager đang giữ | Alertmanager UI (cổng 19093) · `docker compose exec alertmanager amtool alert query --alertmanager.url=http://localhost:9093` |
| Alert sẽ đi tới receiver nào | `docker compose exec alertmanager amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml <nhãn>=<giá-trị> ...` |
| Kiểm tra cú pháp cấu hình | `docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml` · `... amtool check-config /etc/alertmanager/alertmanager.yml` |
| Webhook đã nhận gì | `curl -s 127.0.0.1:15001/ \| python3 -m json.tool` · `docker compose logs webhook-debug` |
| Log của từng thành phần | `docker compose logs --tail 50 <service>` (đặc biệt `alloy`, `loki`, `grafana`) |
| Truy vấn Loki trực tiếp | `curl -sG 127.0.0.1:13100/loki/api/v1/query_range --data-urlencode 'query={compose_service="app"}'` · `curl -s 127.0.0.1:13100/loki/api/v1/labels` |
| Grafana | Connections → Data sources → **Save & test** · Explore |
| Áp dụng cấu hình đã sửa | Prometheus: `curl -X POST 127.0.0.1:19090/-/reload` (đã bật `--web.enable-lifecycle`) · thành phần khác: `docker compose restart <service>` · đổi `compose.yaml`: `docker compose up -d` |

Mọi lệnh `docker compose` chạy **trong thư mục** `~/devops-lab/08-monitoring/bf08`.

**Được phép:** sửa mọi file trong thư mục `bf08` (kể cả `compose.yaml`), restart container.

**Không được phép:** sửa `app/app.py` (app không có lỗi), sửa `verify.sh`, tắt bớt thành phần để "cho xanh".

---

## 5. Các ticket

### 🎫 Ticket #8001 — P2 — Grafana không vẽ được gì

> **Người báo:** Trưởng nhóm
> **Mô tả:** "Mở Grafana → Explore → chọn Prometheus → query `up` thì báo lỗi. Mà sao trên trang Prometheus thì `up` của app lại bằng 0?"
> **Kết quả mong đợi:** Data source Prometheus và Loki trong Grafana đều **Save & test** thành công. Trên Prometheus, **mọi** target đều UP.
> **Ghi chú:** Hai nguyên nhân độc lập, ở hai thành phần khác nhau.

### 🎫 Ticket #8002 — P1 — Dừng dịch vụ 20 phút mà không ai được báo

> **Người báo:** Trưởng nhóm (sau khi #8001 xong)
> **Mô tả:** "Rule `AppDown` có sẵn trong file rule. Mình thử `docker compose stop app` 5 phút: trang Alerts của Prometheus không có gì đỏ. Lạ hơn nữa: cái `Watchdog` thì webhook vẫn nhận đều."
> **Kết quả mong đợi:** Dừng app quá 1 phút → `AppDown` **firing** trên Prometheus **và** tới được `webhook-debug`. Bật app lại → webhook nhận bản tin `resolved`.
> **Ghi chú:** Sửa xong nguyên nhân đầu, `AppDown` sẽ đỏ trên Prometheus nhưng **vẫn** chưa tới webhook. Có nguyên nhân thứ hai.

### 🎫 Ticket #8003 — P2 — Không tìm được log

> **Người báo:** Lập trình viên
> **Mô tả:** "Cần tìm log lỗi 500 hôm qua mà Explore → Loki trống trơn, label browser không có `compose_service`."
> **Kết quả mong đợi:** Query `{compose_service="app"}` trong Grafana Explore trả log của app; query `{compose_service="app", level="error"}` lọc được dòng lỗi (tạo lỗi bằng `curl 127.0.0.1:18088/fail`).
> **Ghi chú:** Lại hai nguyên nhân nối tiếp nhau. Sửa cái đầu thì lỗi thứ hai mới lộ ra **trong log của chính Alloy**.

---

## 6. Luật chơi

1. **Đi theo đường đi của dữ liệu**, từng khâu một: nguồn phát → nơi thu → nơi lưu → nơi truy vấn/gửi đi. Ở mỗi khâu, tự hỏi "làm sao chứng minh dữ liệu **đã tới** đây?".
2. Mỗi lần sửa: sửa → áp dụng → **chứng minh** bằng lệnh/màn hình → ghi nhật ký. Không sửa nhiều chỗ cùng lúc.
3. Đọc log của thành phần nghi ngờ **trước** khi sửa (`docker compose logs --tail 50 <service>`). Các công cụ này ghi lỗi khá rõ — kỹ năng là biết tìm ở đâu.
4. Ghi mọi bước vào `troubleshooting-journal.md` theo [mẫu](../../../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 7. Tiêu chí hoàn thành

`verify.sh` báo **7/7 đạt**, và `verify.sh --e2e` báo **8/8**:

1. Mọi target của Prometheus đều UP.
2. Data source `prometheus` trong Grafana khỏe.
3. Data source `loki` trong Grafana khỏe.
4. Selector trong biểu thức `AppDown` khớp ít nhất một series thật.
5. Nhãn của `AppDown` được Alertmanager route tới `webhook-debug`.
6. `webhook-debug` đã nhận `Watchdog`.
7. Loki có log với `{compose_service="app"}`.
8. (`--e2e`) Dừng app thật → `AppDown` firing tới được `webhook-debug`.

---

## 8. Sản phẩm phải nộp

Một mục trong `troubleshooting-journal.md` cho **mỗi** nguyên nhân bạn tìm ra (dự kiến 6), mỗi mục gồm:

- **Triệu chứng** nhìn thấy (chép nguyên văn dòng lỗi / ảnh chụp màn hình).
- **Khâu** trong đường đi dữ liệu bị đứt, và **bằng chứng** (lệnh nào, thấy gì).
- **Nguyên nhân gốc** và **cách sửa** (diff của file cấu hình).
- **Vì sao lỗi này im lặng** — tại sao không có cảnh báo nào báo nó.
- **Cách phòng tránh**: kiểm tra nào trong CI, hoặc alert nào, sẽ bắt được lỗi này sớm?

Cuối cùng, trả lời: *"Nếu chỉ được thêm **một** alert để phát hiện cả nhóm lỗi 'hệ thống giám sát hỏng mà không ai biết', bạn chọn alert nào và gửi nó đi đâu?"*

---

## 9. Gợi ý

Mở từng cấp **chỉ khi** đã thử ít nhất 15 phút ở cấp trước.

### Ticket #8001

<details><summary>Gợi ý cấp 1</summary>

Hai triệu chứng, hai nơi: Grafana nói chuyện với Prometheus **từ bên trong container Grafana**; Prometheus nói chuyện với app **từ bên trong container Prometheus**. Mở Status → Targets: cột *Error* của job `app` viết gì? Ở Grafana, bấm **Save & test** của data source Prometheus và đọc thông báo.

</details>

<details><summary>Gợi ý cấp 2</summary>

- Grafana: trong một container, `localhost` là **chính container đó** (đã học ở [Docker bài 04](../../../04-DOCKER/04-volumes-networks-env.md)). Data source khai báo trong `grafana/provisioning/datasources/datasources.yaml`.
- Prometheus: lỗi `404 Not Found` nghĩa là **có** máy trả lời, nhưng sai đường dẫn hoặc sai cổng. App demo phục vụ HTTP ở một cổng và metrics ở một cổng **khác**. Thử từ trong mạng của project: `docker compose exec prometheus wget -qO- http://app:8000/metrics | head` và cùng lệnh với cổng `8080`.

</details>

<details><summary>Gợi ý cấp 3</summary>

- Đổi `url` của data source Prometheus thành tên service trong mạng Compose (`http://prometheus:9090`), rồi `docker compose restart grafana` (file provisioning chỉ được đọc lúc Grafana khởi động).
- Đổi target của job `app` trong `prometheus/prometheus.yml` sang cổng metrics, kiểm tra bằng `promtool check config`, rồi reload Prometheus (`curl -X POST 127.0.0.1:19090/-/reload`). Target phải chuyển UP trong vòng một chu kỳ scrape (15 giây).

</details>

### Ticket #8002

<details><summary>Gợi ý cấp 1</summary>

Một alert đi qua 3 cửa: (1) biểu thức PromQL **trả về kết quả**, (2) giữ đủ thời gian `for` để chuyển **pending → firing**, (3) Alertmanager **route** nó tới đúng receiver. `Watchdog` qua được cả 3 cửa — vậy so sánh `AppDown` với `Watchdog` xem nó khác ở cửa nào.

</details>

<details><summary>Gợi ý cấp 2</summary>

- Cửa 1: dán **riêng phần selector** của `AppDown` vào Prometheus → Query. Có series nào không? So các nhãn trong selector với nhãn **thật** của series `up` (query `up` không lọc).
- Cửa 3: Alertmanager UI có thấy `AppDown` không? Nếu **có** mà webhook không nhận, cảnh báo đã bị route sang receiver khác. Dùng `amtool config routes test` với **đúng các nhãn** của `AppDown`.

</details>

<details><summary>Gợi ý cấp 3</summary>

- Biểu thức lọc theo một `job` không tồn tại → kết quả rỗng → rule không bao giờ pending, không lỗi, không cảnh báo. Sửa nhãn `job` cho khớp `scrape_configs`.
- Nhãn `severity` của `AppDown` có một giá trị mà route con không khớp (`severity =~ "critical|warning"`) → alert rơi về receiver mặc định `blackhole` (receiver không có cấu hình gửi đi). Sửa **nhãn trong rule** cho đúng quy ước, đừng nới route để "hứng" mọi thứ. Reload Prometheus, rồi chạy `verify.sh --e2e`.

</details>

### Ticket #8003

<details><summary>Gợi ý cấp 1</summary>

Đường đi của log: app in ra stdout → Docker lưu → **Alloy đọc qua Docker API** → Alloy đẩy (push) sang Loki → Grafana truy vấn Loki. Bắt đầu từ khâu giữa: `docker compose logs --tail 50 alloy`. Alloy cũng có giao diện ở cổng 12345 trong container — nhưng cổng đó không được publish; log là đủ.

</details>

<details><summary>Gợi ý cấp 2</summary>

- Lỗi đầu tiên: Alloy cố kết nối tới `unix:///var/run/docker.sock`. File socket đó có tồn tại **bên trong container Alloy** không? (`docker compose exec alloy ls -l /var/run/docker.sock`). Container chỉ thấy file của host khi được **mount** vào.
- Sửa xong, đọc lại log Alloy: giờ lỗi nằm ở khâu **đẩy sang Loki**, có mã HTTP. So URL trong `loki.write` với đường dẫn API push trong tài liệu Loki.

</details>

<details><summary>Gợi ý cấp 3</summary>

- Thêm volume `/var/run/docker.sock:/var/run/docker.sock:ro` cho service `alloy` trong `compose.yaml`, rồi `docker compose up -d alloy`. Ghi vào nhật ký: socket Docker cho quyền **tương đương root** trên host — vì sao vẫn chấp nhận ở đây, và có cách nào khác (đọc file log JSON của Docker).
- Đường dẫn push đúng của Loki là `/loki/api/v1/push`. Sửa `alloy/config.alloy`, `docker compose restart alloy`. Sau ~10 giây query `{compose_service="app"}` phải có log (app in heartbeat mỗi 5 giây).

</details>

---

## 10. Liên hệ với taskhub v5

| Trong bài (bf08) | Ở taskhub v5 sẽ trông như |
|---|---|
| Data source Grafana dùng `localhost` | Grafana trong project `taskhub-mon` gọi `localhost:9090` thay vì `prometheus:9090` → dashboard trống dù Prometheus vẫn chạy |
| Scrape nhầm cổng HTTP thay vì cổng metrics | Scrape `taskhub:8080/metrics` thay vì `/actuator/prometheus` → `404`, target DOWN |
| Rule lọc theo `job` không tồn tại | Đổi `job_name` trong `prometheus.yml` (ví dụ `taskhub` → `taskhub-app`) mà quên sửa rule `TaskhubDown` → rule im lặng vĩnh viễn |
| `severity` sai quy ước → rơi vào `blackhole` | Thêm rule mới với `severity: page` trong khi route chỉ biết `critical|warning` → Telegram không bao giờ nhận |
| Alloy thiếu Docker socket | Role Ansible `monitoring` quên volume socket → Loki trống sau mỗi lần dựng lại máy |
| URL push Loki sai | Đổi cách triển khai Loki (thêm reverse proxy/đường dẫn) mà quên sửa `loki.write` |

Bài học chung cho v5: **Watchdog** (alert luôn firing) chứng minh khâu Alertmanager → receiver còn sống; còn **mỗi rule quan trọng phải được thử thật ít nhất một lần** (dừng dịch vụ có kiểm soát) và có **unit test** (`promtool test rules`). Và vì bộ giám sát chạy **cùng máy** với app, cần một "người canh" độc lập bên ngoài (CloudWatch alarm ở v3/v5).

---

## 11. Dọn dẹp

⚠️ Xóa toàn bộ môi trường bài này (chỉ project `bf08`, không đụng container khác):

```bash
cd ~/devops-lab/08-monitoring/bf08
docker compose down -v                  # xóa container, network, volume của project bf08
docker rmi bf08-app:local bf08-webhook:local   # 2 image build tại chỗ (--rmi local không xóa image có tag tự đặt)
cd .. && rm -rf bf08
```

Kiểm tra sạch: `docker ps -a --filter label=com.docker.compose.project=bf08` và `docker images 'bf08-*'` không in dòng nào. Các image tải về (prometheus, grafana…) được giữ lại để dùng cho các bài khác; xóa bằng `docker rmi <image>` nếu cần chỗ.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Prometheus — Alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/) | `expr`, `for`, `labels`, pending/firing | 2026-10-31 |
| [Prometheus — Unit testing for rules](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/) | `promtool test rules` | 2026-10-31 |
| [Alertmanager — Configuration](https://prometheus.io/docs/alerting/latest/configuration/) | `route`, `matchers`, `receivers`, `webhook_config` | 2026-10-31 |
| [Grafana Alloy — `loki.source.docker`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/) | Đọc log container qua Docker API, tham số `host`, `relabel_rules` | 2026-10-31 |
| [Grafana Alloy — `discovery.docker`](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.docker/) | Khối `filter`, nhãn `__meta_docker_*` | 2026-10-31 |
| [Grafana Alloy — `loki.process`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.process/) | `stage.json`, `stage.labels` | 2026-10-31 |
| [Grafana — Data source HTTP API](https://grafana.com/docs/grafana/latest/developers/http_api/data_source/) | `GET /api/datasources/uid/:uid/health` | 2026-10-31 |
| [prometheus-client trên PyPI](https://pypi.org/project/prometheus-client/) | Thư viện của app demo, phiên bản 0.26.0 | 2026-10-31 |
