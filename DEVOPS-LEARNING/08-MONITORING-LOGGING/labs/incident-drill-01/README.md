# Incident drill #1 — một ca trực có sự cố thật trên laptop

> ⏱️ ~2 giờ (45–60 phút xử lý + 45 phút viết postmortem) · Mức độ: 🟥 **Bắt buộc tuần 18**
> Kiến thức cần có trước: [Bài 03 — Grafana & alert](../../03-grafana-dashboards-alerting.md), [Bài 04 — Log tập trung](../../04-centralized-logging.md), [Bài 06 — Incident response](../../06-incident-response.md) (làm xong bài thực hành của bài 06: runbook `taskhub-down.md` + `docs/postmortems/TEMPLATE.md`)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL integration) · Chi phí: 0 USD

## Mục lục

- [Ý tưởng](#ý-tưởng)
- [Luật chơi](#luật-chơi)
- [Chuẩn bị](#chuẩn-bị)
- [Bắt đầu ca trực](#bắt-đầu-ca-trực)
- [Trong lúc xử lý](#trong-lúc-xử-lý)
- [Kết thúc và viết postmortem](#kết-thúc-và-viết-postmortem)
- [Gợi ý theo cấp độ](#gợi-ý-theo-cấp-độ)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [An toàn của script](#an-toàn-của-script)

---

## Ý tưởng

`inject.sh` chọn **ngẫu nhiên** một trong ba kịch bản và gây sự cố trên stack `taskhub` của bạn — có khi ngay lập tức, có khi vài phút sau. Bạn **không biết** đó là kịch bản nào. Việc của bạn là làm đúng như một on-call thật: nhận alert → xác nhận → tìm thành phần hỏng → giảm thiểu → kiểm chứng → viết postmortem.

Điểm của drill **không** nằm ở chỗ sửa được (sửa rất dễ), mà ở **quy trình** và **ghi chép**: timeline có giờ UTC, bằng chứng từ metric và log, quyết định có lý do.

## Luật chơi

1. **Không** mở `~/devops-lab/08-monitoring/drill/active` và không đọc kỹ phần `case` của `inject.sh` trước khi xong (đọc lướt phần hàng rào an toàn thì được — xem cuối trang).
2. Chỉ được dùng: alert, Grafana, Prometheus, Loki (Grafana Explore), `docker`/`docker compose`, runbook của bạn. Được xem tài liệu chính thức; **không** dùng AI.
3. Mọi quan sát và hành động ghi vào `incident-notes.md` **ngay lúc làm**, giờ UTC (`date -u +%TZ`).
4. Mục tiêu theo thứ tự: (1) người dùng hết lỗi, (2) hiểu nguyên nhân, (3) ghi lại.
5. Đặt đồng hồ: sau **15 phút** chưa tìm ra nguyên nhân → ưu tiên giảm thiểu bằng cách an toàn nhất bạn có.

## Chuẩn bị

`[WSL]` Ba thứ phải chạy: stack app, stack giám sát, và đích nhận alert.

```bash
# 1. App (cổng 8000 trên máy bạn đã bị chiếm → dùng cổng khác, ví dụ 8088)
cd ~/projects/taskhub
grep -q '^NGINX_HOST_PORT=' .env || echo 'NGINX_HOST_PORT=8088' >> .env
docker compose up -d --wait

# 2. Giám sát (Module 08). Trên laptop dùng receiver webhook-debug thay cho Telegram:
#    profile "debug" bật container webhook-debug, ALERTMANAGER_CONFIG chọn file route tới nó.
#    (monitoring/secrets/grafana_admin_password phải tồn tại — như khi bạn dựng stack ở bài 03)
COMPOSE_PROFILES=debug ALERTMANAGER_CONFIG=alertmanager.laptop.yml \
  docker compose -p taskhub-mon -f monitoring/compose.yaml up -d

# 3. Kiểm tra
docker compose ps
docker compose -p taskhub-mon -f monitoring/compose.yaml ps
```

Xác nhận trước khi bắt đầu (nếu thiếu, quay lại bài 02–04):

- [ ] Prometheus → Status → Targets: `taskhub`, `node` **UP**.
- [ ] Grafana dashboard `taskhub-overview` có dữ liệu.
- [ ] Bạn biết xem alert đến ở đâu: log của container `webhook-debug` (`docker logs -f taskhub-mon-webhook-debug-1`), hoặc Telegram nếu đã cấu hình. Trang Alerts của Prometheus cho thấy trạng thái pending/firing trước khi tin nhắn tới.
- [ ] Rule của bạn có ít nhất: `TaskhubDown`, `TaskhubHighErrorRate`, `TaskhubHighLatencyP95` (tên có thể khác nếu bạn tự đặt).

Chép ba script vào máy (từ thư mục giáo trình này) và cấp quyền chạy:

```bash
mkdir -p ~/devops-lab/08-monitoring/drill-scripts
cp <đường-dẫn-giáo-trình>/08-MONITORING-LOGGING/labs/incident-drill-01/*.sh ~/devops-lab/08-monitoring/drill-scripts/
cd ~/devops-lab/08-monitoring/drill-scripts && chmod +x *.sh
```

Tạo file ghi chép:

```bash
cd ~/projects/taskhub
printf '# Incident notes — %s\n\n| Giờ (UTC) | Quan sát / hành động |\n|---|---|\n' "$(date -u +%F)" > incident-notes.md
```

(`incident-notes.md` là nháp — đừng commit; postmortem mới là thứ được commit.)

## Bắt đầu ca trực

Terminal 1 — giả lập người dùng (không có traffic thì alert dựa trên tỷ lệ lỗi/latency không thể kích hoạt):

```bash
~/devops-lab/08-monitoring/drill-scripts/traffic.sh
```

```text
Gửi traffic tới http://localhost:8088 (Ctrl+C để dừng)
09:30:10Z  200=17  201=4
09:30:20Z  200=18  201=3
```
(minh họa)

Terminal 2 — gây sự cố:

```bash
~/devops-lab/08-monitoring/drill-scripts/inject.sh random
```

Rồi làm việc khác (đọc tài liệu, uống nước). On-call thật không ngồi nhìn dashboard — họ **chờ alert**. Nhưng cứ vài phút liếc Terminal 1 một lần: đó là "người dùng gọi điện phàn nàn". Có kịch bản mà alert của bạn **có thể không kêu** — nếu người dùng phát hiện trước alert, đó là một phát hiện quan trọng cho postmortem, không phải thất bại của bạn.

## Trong lúc xử lý

Khung suy nghĩ gợi ý (từ bài 06 §3.3 và §12.2):

1. **Alert nói gì?** Tên alert, `startsAt`, label nào. Ghi giờ nhận. Lưu ý: Alertmanager có thể **ẩn** (inhibit) alert phụ khi alert gốc đang firing — ví dụ cấu hình tham khảo ẩn `TaskhubHighErrorRate` khi `TaskhubDown` đang kêu. Không thấy alert phụ chưa chắc là nó không xảy ra.
2. **Có thật không, ảnh hưởng tới đâu?** Terminal `traffic.sh` đang thấy mã gì? Dashboard: rate, 5xx, p95, `up`.
3. **Thành phần nào hỏng trước?** `docker compose ps` (trạng thái, health), panel theo thời gian.
4. **Log nói gì?** Grafana Explore → Loki, lọc `{compose_service="taskhub"}` quanh thời điểm bắt đầu; tìm dòng `ERROR` **đầu tiên**. Đừng quên log của `postgres` và `nginx`.
5. **Gần đây có gì thay đổi?** Lịch sử deploy (`~/devops-lab/08-monitoring/drill/deploy-history.log` đóng vai trò lịch sử workflow Deploy), `docker inspect` (thời điểm tạo container, biến môi trường, image).
6. **Giảm thiểu** bằng cách an toàn nhất, **kiểm chứng** (alert resolved, `traffic.sh` toàn 2xx), ghi giờ.

Khi bạn tin là đã ổn định, chạy:

```bash
~/devops-lab/08-monitoring/drill-scripts/reset.sh
```

`reset.sh` dọn những gì còn sót (lệnh hẹn giờ chưa chạy, cấu hình drill) và in ra kịch bản đã chạy để bạn đối chiếu. Nếu nó báo "Đã unpause/Đã start…" nghĩa là bạn **chưa** thực sự giảm thiểu xong — ghi điều đó vào postmortem một cách trung thực.

## Kết thúc và viết postmortem

Viết `docs/postmortems/YYYY-MM-DD-<slug>.md` trong repo `taskhub` từ `docs/postmortems/TEMPLATE.md` (mẫu ở bài 06 §4.10). Bắt buộc có:

- **Timeline** từ `incident-notes.md`, giờ UTC, mỗi dòng có **nguồn** (alert, panel, dòng log, lệnh).
- **MTTD** (từ lúc sự cố bắt đầu — xem metric/log để xác định — đến lúc alert firing) và **thời gian ảnh hưởng** (đến lúc `traffic.sh` toàn 2xx).
- **Nguyên nhân trực tiếp** và ít nhất **2 yếu tố góp phần** ở mức hệ thống (ví dụ: "không có alert cho health `DOWN` khi app vẫn trả metric", "không có lịch sử deploy dễ tra").
- **Ảnh chụp** hoặc truy vấn PromQL/LogQL đã dùng làm bằng chứng.
- **Hành động**: ít nhất 3, mỗi cái có owner (bạn), hạn, và cách kiểm chứng (một alert mới, một panel mới, một dòng runbook).

Mở PR `docs: postmortem incident drill #1`. Sau đó cập nhật `docs/runbooks/taskhub-down.md` theo những gì bạn học được.

**Lặp lại**: chạy thêm 2 lần nữa với `inject.sh random` (mỗi lần một postmortem ngắn hơn) cho tới khi bạn đã gặp đủ A, B, C. Lần nào MTTD/thời gian ảnh hưởng giảm, ghi lại.

## Gợi ý theo cấp độ

Chỉ mở khi đã kẹt **ít nhất 15 phút**.

<details>
<summary>Gợi ý cấp 1 — nhìn ở đâu</summary>

So sánh ba thứ cùng lúc: `docker compose ps` (cột STATUS và health của **cả ba** service, không chỉ `taskhub`), panel `up`/5xx/p95 trên dashboard, và log của **postgres** lẫn `taskhub` ở đúng phút đầu tiên có lỗi. Một service "Up" chưa chắc đang hoạt động.

</details>

<details>
<summary>Gợi ý cấp 2 — phân biệt các kịch bản bằng triệu chứng</summary>

- App khởi động lại liên tục, `up{job="taskhub"} == 0`, nginx trả 502, log có lỗi xác thực database ngay lúc khởi động → có gì đó **đổi cấu hình** app. Xem lịch sử deploy và `docker inspect` biến môi trường.
- App vẫn chạy (`up` vẫn 1 — endpoint metric không cần database), request chậm khoảng 30 giây rồi lỗi; log có lỗi lấy kết nối, nguyên nhân sâu bên trong là không phân giải được/không kết nối được tới `postgres` → database **không còn chạy**. `docker compose ps -a`.
- App vẫn chạy, request **treo** (không trả lời, không có lỗi trong log app vì request chưa kết thúc), container postgres vẫn hiện "Up" → database **không phản hồi**. Xem kỹ cột STATUS của `docker ps`, hoặc `docker inspect -f '{{.State.Status}}'`.

</details>

<details>
<summary>Gợi ý cấp 2b — "sao không có alert nào?"</summary>

Metric HTTP của app (`http_server_requests_seconds_*`) chỉ được ghi khi request **kết thúc**. Request treo vô thời hạn thì không có tỷ lệ lỗi, không có latency — alert dựa trên chúng im lặng. Người "phát hiện" lúc đó là người dùng (`traffic.sh` thấy mã `000` = curl hết thời gian chờ). Ghi điều này vào postmortem: đây là **lỗ hổng giám sát**, và hành động khắc phục có thể là một phép thử từ bên ngoài (blackbox probe) hoặc alert dựa trên số request đang xử lý.

</details>

<details>
<summary>Gợi ý cấp 3 — lệnh giảm thiểu</summary>

- Cấu hình lỗi sau deploy → **rollback cấu hình**: tạo lại service app với cấu hình chuẩn của repo: `cd ~/projects/taskhub && docker compose up -d --no-build taskhub`.
- Database bị dừng → `docker compose start postgres` (dữ liệu nằm trong volume, không mất).
- Database bị đóng băng → `docker unpause <container postgres>`.

Sau đó: alert resolved? `traffic.sh` toàn 2xx? Ghi giờ.

</details>

## Tiêu chí đạt

- [ ] Phát hiện sự cố **qua alert**, không phải vì đang nhìn dashboard.
- [ ] Giảm thiểu đúng cách trước khi `reset.sh` phải làm hộ.
- [ ] Postmortem có timeline đủ nguồn, MTTD, thời gian ảnh hưởng, ≥ 2 yếu tố góp phần, ≥ 3 hành động có owner/hạn.
- [ ] Ít nhất một hành động đã **thực hiện xong** (ví dụ alert mới) và được kiểm chứng bằng cách chạy lại đúng kịch bản đó (`inject.sh A|B|C`).
- [ ] Đã gặp đủ ba kịch bản qua các lần chạy.

So sánh với [lời giải](../../solutions/incident-drill-01-solutions.md) — **sau khi** đã viết xong postmortem.

## An toàn của script

Đọc phần này trước khi chạy script của người khác (thói quen tốt):

- `inject.sh` chỉ làm việc với container có nhãn `com.docker.compose.project=taskhub` **và** tên bắt đầu bằng `taskhub-`; không thấy → dừng. Khoảng 36 container khác trên máy bạn không bị đụng tới.
- Không ghi gì lên ổ đĩa host ngoài thư mục `~/devops-lab/08-monitoring/drill/` (file trạng thái, file override, lịch sử deploy giả).
- Không xóa volume, không xóa dữ liệu: các thao tác chỉ là `docker stop`, `docker pause`, và tạo lại container app với biến môi trường khác.
- Mọi lệnh hẹn giờ chạy trong process group riêng; `reset.sh` hủy hết. Kịch bản "treo" còn có lưới an toàn tự gỡ sau khoảng 20 phút.
- `reset.sh` chạy lại bao nhiêu lần cũng được.
