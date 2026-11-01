# Milestone v-pre — Nền móng dự án (tuần 1–6)

> Mục tiêu: trước khi học Docker, repo `taskhub` đã có cấu trúc rõ ràng, script vận hành đầu tiên, kế hoạch mạng, cấu hình Nginx thử nghiệm và **ứng dụng Spring Boot chạy được trên máy**.
> Kết thúc bằng release `v0.1.0`.

## Mục lục

- [Tổng quan](#tổng-quan)
- [Tuần 1 — Tạo repo taskhub](#tuần-1--tạo-repo-taskhub)
- [Tuần 2 — Tài liệu user và quyền](#tuần-2--tài-liệu-user-và-quyền)
- [Tuần 3 — Script healthcheck](#tuần-3--script-healthcheck)
- [Tuần 4 — Kế hoạch mạng](#tuần-4--kế-hoạch-mạng)
- [Tuần 5 — Nginx reverse proxy thử nghiệm](#tuần-5--nginx-reverse-proxy-thử-nghiệm)
- [Tuần 6 — Đặc tả ứng dụng Spring Boot](#tuần-6--đặc-tả-ứng-dụng-spring-boot)
- [Definition of Done của cả milestone](#definition-of-done-của-cả-milestone)

Quay lại: [Module 12 — Dự án](../README.md)

---

## Tổng quan

| Tuần | Việc của dự án | Đến từ bài học | Thời gian |
|---|---|---|---|
| 1 | Tạo repo, README, `.gitignore` | [Ôn tập Git](../../03-GIT/00-git-quick-review.md) | ~1h |
| 2 | `docs/runtime-user-and-permissions.md` | [Bài 03](../../01-LINUX/03-permissions-users-groups.md), [Bài 04](../../01-LINUX/04-processes-systemd.md) | ~1h |
| 3 | `scripts/healthcheck.sh` | [Lab 03](../../01-LINUX/labs/lab-03-healthcheck-cron.md) | ~2h |
| 4 | `docs/network-plan.md` (khung) | Module 02 | ~1–2h |
| 5 | `docs/experiments/nginx-wsl.conf` | Module 02 | ~2h |
| 6 | Ứng dụng Spring Boot + branch protection + release `v0.1.0` | Module 03 (tuần 6) | ~3–4h |

> Phần dự án mỗi tuần nằm trong buổi Chủ nhật (2–3h) của [kế hoạch tuần](../../00-ROADMAP/weekly-study-plan.md#1-nhịp-học-mỗi-tuần). Làm sau khi đã học bài của tuần đó.

---

## Tuần 1 — Tạo repo taskhub

**Việc cần làm** `[WSL]`

1. Tạo repo `taskhub` trên GitHub (Public — để nhà tuyển dụng xem được; nhớ: **không bao giờ** commit secret).
2. Clone về `~/projects/taskhub` (trong WSL, không phải `/mnt/c`).
3. Tạo `README.md` ban đầu: tên dự án, mô tả 2–3 câu, mục "Trạng thái: đang xây dựng — v-pre", mục "Lộ trình" liệt kê các phiên bản v0 → v1.0.
4. Tạo `.gitignore` cho Java/Maven/IntelliJ + `.env` (tham khảo bài tập 2 trong [Ôn tập Git](../../03-GIT/00-git-quick-review.md#14-bài-tập-tự-làm)).
5. Tạo `.gitattributes` với `* text=auto eol=lf` (lý do: [Ôn tập Git §4.3](../../03-GIT/00-git-quick-review.md#43--crlf-và-lf--nối-với-bài-01)).
6. 🟨 Tùy chọn: thêm `LICENSE` (ví dụ MIT) — GitHub có sẵn mẫu khi bấm *Add file → Create new file → LICENSE*.

**Definition of Done**

- [ ] Repo `taskhub` có trên GitHub, push bằng SSH.
- [ ] Có `README.md`, `.gitignore`, `.gitattributes`.
- [ ] Commit message theo Conventional Commits.

---

## Tuần 2 — Tài liệu user và quyền

Áp dụng bài 03 và 04 vào dự án: quyết định **trước** ứng dụng sẽ chạy bằng user nào, file nằm ở đâu, ai được đọc/ghi gì. Đây là cách làm của kỹ sư vận hành — thiết kế trước, triển khai sau.

**Việc cần làm** — tạo `docs/runtime-user-and-permissions.md` trả lời:

| Câu hỏi | Gợi ý hướng trả lời |
|---|---|
| App chạy bằng user nào? Vì sao không chạy bằng root? | User hệ thống riêng, ví dụ `taskhub`, không có shell đăng nhập |
| File chương trình nằm đâu, quyền gì? | `/opt/taskhub/` — root sở hữu, app chỉ đọc |
| Cấu hình nằm đâu, quyền gì? | `/etc/taskhub/` — có thể chứa mật khẩu → chỉ root và group `taskhub` đọc được |
| Log ghi ở đâu? | `/var/log/taskhub/` hoặc stdout → journald. Ghi chú: khi chạy bằng Docker (v0), log sẽ ra stdout |
| Dữ liệu ghi ở đâu? | `/var/lib/taskhub/` (nếu có) |
| Service quản lý thế nào? | systemd unit, `Restart=on-failure`, `User=taskhub` |

Viết dưới dạng bảng: đường dẫn · owner:group · quyền dạng số · lý do.

> Đến v0 bạn sẽ chuyển sang Docker, nhưng **nguyên tắc giữ nguyên**: container vẫn phải chạy bằng user không phải root, cấu hình bí mật vẫn phải giới hạn quyền đọc. Tài liệu này sẽ được cập nhật thay vì vứt đi.

**Definition of Done**

- [ ] File `docs/runtime-user-and-permissions.md` có bảng đầy đủ 5 dòng trở lên.
- [ ] Mỗi quyền có lý do, giải thích được vì sao không dùng `777`.

---

## Tuần 3 — Script healthcheck

**Việc cần làm**

1. Hoàn thành [Lab 03 — Script healthcheck chạy bằng cron](../../01-LINUX/labs/lab-03-healthcheck-cron.md).
2. Đưa script vào `scripts/healthcheck.sh` của repo `taskhub`.
3. Thêm phần đầu script: mô tả, cách dùng, exit code trả về.
4. Thêm vào README mục "Scripts" mô tả ngắn từng script.

Script này sẽ được dùng lại: kiểm tra server EC2 (v2) và làm cơ sở so sánh khi chuyển sang Prometheus (v5) — bạn sẽ tự thấy vì sao công ty dùng hệ thống monitoring chứ không viết script.

**Definition of Done**

- [ ] `scripts/healthcheck.sh` có quyền thực thi trong Git (`git ls-files -s scripts/healthcheck.sh` hiện mode `100755`).
- [ ] Script dùng `set -euo pipefail`, đường dẫn tuyệt đối, trả exit code khác 0 khi có vấn đề.
- [ ] File có xuống dòng LF (`file scripts/healthcheck.sh` không có chữ CRLF).

---

## Tuần 4 — Kế hoạch mạng

**Việc cần làm** — tạo `docs/network-plan.md`. Tuần này chỉ dựng **khung**; số liệu cụ thể điền theo kiến thức Module 02 (bài IPv4/CIDR). Tuần 11 bạn sẽ tạo VPC trên AWS đúng theo bảng này.

Khung gợi ý:

```markdown
# Network plan — taskhub

## VPC
| Thuộc tính | Giá trị | Lý do |
|---|---|---|
| CIDR | 10.?.0.0/16 | ... |
| Region | ap-southeast-1 | gần Việt Nam |

## Subnets
| Tên | AZ | CIDR | Public/Private | Số IP dùng được | Chứa gì |
|---|---|---|---|---|---|
| public-a | ap-southeast-1a | ... | Public | ... | EC2 taskhub |
| private-a | ap-southeast-1a | ... | Private | ... | (dự phòng: RDS ở lab tuần 14) |
| public-b | ap-southeast-1b | ... | Public | ... | (lab ALB tuần 14) |
| private-b | ap-southeast-1b | ... | Private | ... | (lab RDS tuần 14) |

## Port cần mở
| Port | Giao thức | Từ đâu | Đến đâu | Lý do |
|---|---|---|---|---|

## Câu hỏi còn mở
- ...
```

> Ghi chú: AWS giữ lại một số địa chỉ trong mỗi subnet nên "số IP dùng được" không bằng số IP của CIDR — Module 02 và 06 sẽ giải thích. Ghi câu hỏi vào mục "Câu hỏi còn mở" nếu chưa chắc.

**Definition of Done**

- [ ] `docs/network-plan.md` có VPC CIDR, 4 subnet không chồng lấn nhau, tính đúng số địa chỉ.
- [ ] Bảng port có ít nhất: 80, 443 từ Internet; 5432 chỉ nội bộ; giải thích vì sao **không** mở 22 ra Internet.

---

## Tuần 5 — Nginx reverse proxy thử nghiệm

**Việc cần làm** `[WSL]`

1. Làm lab Nginx reverse proxy của Module 02 (cài Nginx trên WSL, đặt trước một ứng dụng đơn giản).
2. Lưu cấu hình server block bạn viết vào `docs/experiments/nginx-wsl.conf`, kèm comment giải thích **từng directive**.
3. Ghi lại trong `docs/experiments/README.md`: Nginx chạy ở port nào, upstream là gì, khi tắt ứng dụng phía sau thì Nginx trả mã lỗi gì (gợi ý: 502) và log lỗi ghi gì.

> Vì sao lưu vào `docs/experiments/` mà không phải `docker/nginx/`? Ở v0, upstream sẽ đổi từ `127.0.0.1:8080` sang tên service trong Docker network (`taskhub:8080`). Giữ bản thử nghiệm riêng giúp bạn so sánh và hiểu vì sao phải đổi.

**Definition of Done**

- [ ] `curl -I http://localhost` trả về response từ ứng dụng phía sau, đi qua Nginx.
- [ ] Đã quan sát và ghi lại lỗi 502 khi tắt ứng dụng, kèm dòng log trong `/var/log/nginx/error.log`.
- [ ] File cấu hình có comment giải thích mọi directive.

---

## Tuần 6 — Đặc tả ứng dụng Spring Boot

> Đây là **đặc tả** (cần xây cái gì và tiêu chí chấp nhận), không phải hướng dẫn từng bước. 👉 Hướng dẫn chi tiết: [v-pre-week6-springboot-app.md](v-pre-week6-springboot-app.md). Mục tiêu DevOps ở đây là có một ứng dụng **chuẩn để vận hành**: cấu hình qua biến môi trường, có health check, log ra stdout, schema database được quản lý bằng migration.

### Khởi tạo

- Tạo bằng [start.spring.io](https://start.spring.io): **Maven**, **Java 21**, **phiên bản Spring Boot ổn định hiện tại** (không chọn bản SNAPSHOT/M/RC).
- Dependencies: *Spring Web*, *Spring Data JPA*, *PostgreSQL Driver*, *Flyway Migration*, *Spring Boot Actuator*, *Validation*.
- Đặt project trong thư mục `app/` của repo `taskhub`. Commit cả Maven Wrapper (`mvnw`, `.mvn/`) để mọi máy (và CI ở tuần 9) build giống nhau.

> ⚠️ Spring Boot đã lên 4.x. Nhiều tutorial trên mạng vẫn viết cho 3.x — tên một số thuộc tính cấu hình, dependency hoặc package có thể khác. Khi tutorial không khớp, ưu tiên tài liệu chính thức của đúng phiên bản bạn dùng. Ghi lại mọi khác biệt gặp phải vào nhật ký debug.

### Mô hình dữ liệu: `Task`

| Trường | Kiểu | Ràng buộc |
|---|---|---|
| `id` | Long (hoặc UUID) | Khóa chính, tự sinh |
| `title` | String | Bắt buộc, 1–200 ký tự |
| `description` | String | Tùy chọn, tối đa 2000 ký tự |
| `status` | Enum `TODO`, `IN_PROGRESS`, `DONE` | Bắt buộc, mặc định `TODO` |
| `createdAt` | Thời điểm | Tự gán khi tạo |
| `updatedAt` | Thời điểm | Tự cập nhật khi sửa |

Bảng được tạo bằng **Flyway migration** (`V1__create_tasks_table.sql`), **không** dùng `ddl-auto=update`. Lý do: trên production, thay đổi schema phải có kiểm soát, có phiên bản và review được — giống như code.

### API

| Method | Đường dẫn | Mô tả | Mã trả về |
|---|---|---|---|
| `GET` | `/api/tasks` | Danh sách task, lọc tùy chọn `?status=TODO` | 200 |
| `GET` | `/api/tasks/{id}` | Một task | 200, 404 nếu không có |
| `POST` | `/api/tasks` | Tạo task | 201 + header `Location`, 400 nếu dữ liệu sai |
| `PUT` | `/api/tasks/{id}` | Sửa task | 200, 400, 404 |
| `DELETE` | `/api/tasks/{id}` | Xóa task | 204, 404 |
| `GET` | `/actuator/health` | Tình trạng ứng dụng và kết nối database | 200 `{"status":"UP"}` |

Lỗi trả về JSON có cấu trúc thống nhất (gợi ý: định dạng *Problem Details* mà Spring hỗ trợ sẵn).

### Cấu hình — theo yêu cầu vận hành

| Yêu cầu | Vì sao (góc nhìn DevOps) |
|---|---|
| Thông tin database lấy từ **biến môi trường**: `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` | Cùng một artifact chạy được ở mọi môi trường (máy bạn, Docker, EC2) chỉ bằng cách đổi biến; không có mật khẩu trong code |
| Port qua `SERVER_PORT` (mặc định 8080) | Linh hoạt khi triển khai |
| Không commit `application-local.*` hoặc `.env` chứa mật khẩu | Bảo mật (đã có trong `.gitignore`) |
| Log ra **stdout**, không ghi file | Docker, systemd/journald và Loki đều thu log từ stdout |
| Actuator chỉ công khai `health` và `info` | Các endpoint khác có thể lộ thông tin nhạy cảm. Endpoint `prometheus` sẽ bật ở v5 |
| Ứng dụng tắt nhẹ nhàng (graceful shutdown) khi nhận SIGTERM | Liên quan bài 04 (signal) và rolling update ở Kubernetes (v6) |

### PostgreSQL trên máy (trước khi học Docker)

Chọn một trong hai cách:

- **A (khuyến nghị):** cài PostgreSQL bằng `apt` trong WSL. Bạn sẽ ôn lại package management (bài 05) và systemd (bài 04): service `postgresql`, log qua `journalctl`, file cấu hình trong `/etc/postgresql/`.
- **B:** chạy PostgreSQL bằng một lệnh `docker run` — nhanh hơn, nhưng bạn sẽ chỉ hiểu đầy đủ ở tuần 7.

Tạo database `taskhub` và user `taskhub` riêng — **không** dùng user `postgres` (superuser) cho ứng dụng.

### Test

- Ít nhất: 1 test context load, test cho controller (tạo task hợp lệ → 201, thiếu `title` → 400, id không tồn tại → 404).
- 🟨 Nên biết: test với PostgreSQL thật bằng Testcontainers (cần Docker) — sẽ quay lại khi viết CI ở tuần 9.
- `./mvnw verify` phải chạy xanh. Đây là lệnh CI sẽ chạy ở tuần 9.

### Quy trình Git (áp dụng bài tuần 6)

- Bật **branch protection** cho `main`: bắt buộc Pull Request, không cho push thẳng.
- Làm ứng dụng trên nhánh `feat/task-api`, mở Pull Request, tự review diff trước khi merge.
- Sau khi merge: tạo tag `v0.1.0` và GitHub Release mô tả những gì đã có.

### Definition of Done

- [ ] `./mvnw spring-boot:run` (với biến môi trường đúng) khởi động thành công, Flyway tạo bảng `tasks`.
- [ ] Gọi đủ 5 endpoint bằng `curl` với kết quả đúng mã trả về trong bảng API.
- [ ] `curl localhost:8080/actuator/health` trả `UP`; tắt PostgreSQL thì trả `DOWN` (giải thích được vì sao).
- [ ] Không có mật khẩu nào trong repo (`git grep -i password` chỉ ra tên biến/placeholder).
- [ ] `./mvnw verify` xanh.
- [ ] `main` được bảo vệ; code vào `main` qua Pull Request; có tag và Release `v0.1.0`.
- [ ] README có mục "Chạy trên máy" với các bước và biến môi trường cần thiết.

---

## Definition of Done của cả milestone

- [ ] Hoàn thành DoD của cả 6 tuần.
- [ ] README phản ánh đúng trạng thái hiện tại (không mô tả thứ chưa làm).
- [ ] Mọi lỗi gặp phải trong 6 tuần đã được ghi vào `troubleshooting-journal.md` của repo `devops-journey`.
- [ ] Bạn giải thích được từng file trong repo `taskhub` cho người khác.

➡️ Tiếp theo: [**v0 — Docker Compose**](v0-docker-compose.md) (tuần 7–8).
