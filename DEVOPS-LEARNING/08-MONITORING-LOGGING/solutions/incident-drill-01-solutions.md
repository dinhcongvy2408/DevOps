# Lời giải — Incident drill #1

> Chỉ mở **sau khi** đã viết xong postmortem. Các triệu chứng dưới đây là **dự kiến** dựa trên cấu hình tham khảo (rule trong [alerts.yml](../labs/reference/prometheus/rules/alerts.yml), nginx `proxy_read_timeout` 30 giây, HikariCP mặc định); chữ chính xác của log và thời điểm alert trên máy bạn có thể khác — ghi lại cái **bạn** thấy.

## Tổng quan ba kịch bản

| | A — Database dừng | B — "Deploy" cấu hình lỗi | C — Database treo |
|---|---|---|---|
| Inject làm gì | `docker stop` container postgres sau 1–10 phút | Tạo lại container app với `SPRING_DATASOURCE_PASSWORD` sai (qua file override của drill) + ghi một dòng "deploy" vào `deploy-history.log` | `docker pause` container postgres sau 1–5 phút |
| `docker compose ps` | postgres `Exited` | taskhub `Restarting` / không healthy | postgres hiện "Up (Paused)"; taskhub có thể chuyển `unhealthy` |
| `up{job="taskhub"}` | 1 (endpoint metric không cần database) | **0** | 1 |
| `traffic.sh` thấy | `000` (curl hết 10s) và/hoặc 5xx | 502 | `000` |
| Alert dự kiến | `TaskhubHighErrorRate` sau khoảng 5 phút có traffic (request kết thúc bằng 500 sau ~30s chờ kết nối) | `TaskhubDown` sau khoảng 1 phút; `TaskhubHighErrorRate` bị inhibit | Có thể **không có** alert nào (request treo không kết thúc → không có metric HTTP) |
| Log then chốt | App: lỗi lấy kết nối từ pool sau ~30s; nguyên nhân bên trong: không phân giải được / không kết nối được host `postgres` | App: `FATAL: password authentication failed for user "taskhub"` lúc khởi động (Flyway/Hikari) | App: không có lỗi cho tới khi request hết hạn; nginx: `upstream timed out` (504) |
| "Gần đây có gì đổi?" | Không có deploy | **Có**: `deploy-history.log`, `docker inspect` thấy container app mới tạo, biến môi trường khác `.env` | Không có deploy |
| Giảm thiểu | `docker compose start postgres` | Rollback cấu hình: `docker compose up -d --no-build taskhub` (không có file override) | `docker unpause <postgres>` |
| Dữ liệu | Không mất (volume còn nguyên) | Không mất | Không mất |

## Cách phân biệt nhanh (thứ tự hỏi đúng)

1. `up{job="taskhub"}` = 0? → app không chạy được → nhìn **thay đổi gần nhất** trước (B).
2. `up` = 1 mà người dùng lỗi → app chạy nhưng phụ thuộc hỏng → `docker compose ps -a` cho **cả** postgres.
3. Postgres `Exited` (A) hay `Paused` (C)? Cột STATUS trả lời trong 2 giây — nhiều người bỏ qua vì chỉ nhìn container app.

## Postmortem mẫu — Kịch bản B

```markdown
# Postmortem: taskhub không phục vụ sau thay đổi cấu hình datasource — 2026-11-20

- Trạng thái: Đã review · Mức: SEV-2 · Người viết: phuong-dev
- Thời gian ảnh hưởng: 09:41:05–09:52:40 UTC (11 phút 35 giây)

## Tóm tắt
Một thay đổi cấu hình "tune datasource settings" đặt sai mật khẩu database cho app. App không khởi động được,
nginx trả 502 cho mọi request trong ~12 phút. Giảm thiểu bằng cách tạo lại container app với cấu hình chuẩn của repo.

## Tác động
- Người dùng: 100% request lỗi 502 trong 11 phút 35 giây.
- Dữ liệu: không mất.

## Timeline (UTC)
| Giờ | Sự kiện | Nguồn |
|---|---|---|
| 09:41:05 | "Deploy" cấu hình bởi ci-bot (drill PR #42) | deploy-history.log |
| 09:41:20 | Log app: `FATAL: password authentication failed for user "taskhub"`, container khởi động lại | Loki `{compose_service="taskhub"}` |
| 09:41:25 | traffic.sh bắt đầu thấy 502 | Terminal |
| 09:42:35 | Alert TaskhubDown firing | webhook-debug |
| 09:44:10 | Ack; dashboard: up=0, không còn request rate từ app | Grafana |
| 09:47:30 | Thấy dòng deploy 09:41:05 trùng thời điểm; `docker inspect` thấy SPRING_DATASOURCE_PASSWORD khác `.env` | deploy-history.log, docker inspect |
| 09:50:55 | Rollback cấu hình: `docker compose up -d --no-build taskhub` | Lệnh |
| 09:52:40 | App healthy, traffic.sh toàn 200/201, alert resolved | Terminal, webhook-debug |

## Nguyên nhân gốc và yếu tố góp phần
- Trực tiếp: biến SPRING_DATASOURCE_PASSWORD của app bị đặt khác mật khẩu PostgreSQL.
- Góp phần:
  1. Thay đổi cấu hình đi **ngoài** pipeline (không qua PR/CI), không có kiểm tra trước khi áp.
  2. Không có smoke test sau thay đổi — cấu hình được coi là "đã deploy" dù app không lên.
  3. On-call mất 3 phút 20 giây (09:44 → 09:47) mới nghĩ tới "gần đây có gì đổi" — runbook chưa đưa câu hỏi này lên đầu.

## Phát hiện
Alert TaskhubDown sau ~90 giây — tốt. MTTD từ lỗi đầu tiên (09:41:20) tới alert: 1 phút 15 giây.

## Điều gì làm tốt / chưa tốt / gặp may
- Tốt: alert đúng và nhanh; log có dòng lỗi rõ ràng.
- Chưa tốt: mất thời gian xem dashboard trước khi xem lịch sử thay đổi.
- Gặp may: mật khẩu sai chứ không phải trỏ nhầm sang database khác (có thể ghi dữ liệu sai chỗ).

## Hành động
| Hành động | Loại | Owner | Hạn | Kiểm chứng |
|---|---|---|---|---|
| Đưa "Gần đây có gì đổi?" thành bước 1 của runbook taskhub-down | Giảm thiểu | phuong-dev | 2026-11-22 | PR runbook |
| Mọi thay đổi cấu hình app đi qua Git + Ansible/Deploy, không sửa tay trên máy | Phòng ngừa | phuong-dev | 2026-11-30 | Chạy lại `inject.sh B`: thay đổi phải hiện trong lịch sử Git/Actions |
| Smoke test `POST /api/tasks` sau mọi lần deploy (deploy.sh + workflow Deploy) | Phát hiện | phuong-dev | 2026-11-30 | Deploy thử cấu hình lỗi trên laptop → deploy.sh tự rollback |

## Bài học
Khi alert trùng với một thay đổi, rollback thay đổi trước rồi mới điều tra.
```

## Hành động gợi ý cho kịch bản A và C

- **A:** alert dựa trên health thực của app (ví dụ một phép thử từ bên ngoài — blackbox exporter 🟨 — gọi `/actuator/health` qua nginx; hoặc metric health của Actuator nếu bạn bật), alert `postgres` container không chạy (cAdvisor/postgres_exporter 🟨); giảm `SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT` để lỗi trả về nhanh thay vì treo 30 giây (đã thấy ở Module 04).
- **C:** đây là kịch bản cho thấy **lỗ hổng giám sát**: alert dựa trên request đã hoàn thành không thấy request treo. Hành động: phép thử từ bên ngoài có timeout; alert trên số request đang xử lý (Micrometer có metric cho request **đang** chạy — kiểm tra tên trong `/actuator/prometheus` của bạn); đặt timeout truy vấn/socket cho JDBC để request không treo vô hạn; alert `TaskhubHighLatencyP95` của bạn có `for: 10m` — cân nhắc lại.

## Tiêu chí chấm postmortem

| Tiêu chí | Đạt khi |
|---|---|
| Timeline | Giờ UTC, mỗi dòng có nguồn, có mốc bắt đầu ảnh hưởng / phát hiện / giảm thiểu / kết thúc |
| Con số | MTTD và thời gian ảnh hưởng tính đúng từ timeline |
| Nguyên nhân | Phân biệt trigger và yếu tố góp phần; không có câu "do X sơ suất" |
| Trung thực | Ghi cả những bước sai hướng, và việc `reset.sh` phải làm hộ (nếu có) |
| Hành động | ≥ 3, có owner, hạn, cách kiểm chứng; ít nhất một cái đã làm và chạy lại kịch bản để chứng minh |
