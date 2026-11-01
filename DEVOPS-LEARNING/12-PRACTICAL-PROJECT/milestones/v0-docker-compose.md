# Milestone v0 — taskhub chạy bằng Docker Compose (tuần 7–8)

> Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 04 — Docker](../../04-DOCKER/README.md), ứng dụng `v0.1.0` từ [tuần 6](v-pre-week6-springboot-app.md)
> Môi trường: `[WSL]` + Docker Desktop (bật WSL integration)
> Đây là **việc cần nộp + tiêu chí chấp nhận**. Các bước làm chi tiết nằm ở [lab Spring Boot + PostgreSQL + Nginx](../../04-DOCKER/labs/lab-springboot-postgres-compose/README.md) — làm lab trước, rồi đưa kết quả vào repo `taskhub`.

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc v0](#2-kiến-trúc-v0)
- [3. File phải có trong repo](#3-file-phải-có-trong-repo)
- [4. Yêu cầu chất lượng](#4-yêu-cầu-chất-lượng)
- [5. Thử nghiệm bắt buộc](#5-thử-nghiệm-bắt-buộc)
- [6. Câu hỏi tự kiểm](#6-câu-hỏi-tự-kiểm)
- [7. Definition of Done và release v0.2.0](#7-definition-of-done-và-release-v020)

---

## 1. Mục tiêu

Một lệnh duy nhất dựng toàn bộ hệ thống trên bất kỳ máy nào có Docker:

```bash
cp .env.example .env      # rồi sửa mật khẩu
docker compose up -d --build
```

Sau đó `http://localhost:8000/api/tasks` hoạt động, dữ liệu sống sót qua khởi động lại, và bạn giải thích được **từng dòng** trong `Dockerfile`, `compose.yaml`, `default.conf`.

Vì sao milestone này quan trọng: image tạo ra ở đây chính là thứ CI sẽ build (v1), EC2 sẽ chạy (v2) và Kubernetes sẽ triển khai (v6). Làm đúng ở đây thì các bước sau chỉ là "chạy cùng một image ở chỗ khác".

---

## 2. Kiến trúc v0

```text
 Trình duyệt / curl (Windows hoặc WSL)
        │  http://localhost:8000
        ▼
 ┌──────────────────────── Docker (máy của bạn) ─────────────────────────┐
 │  port 8000 của máy ──► nginx:80          (chỉ service này publish)    │
 │                          │ proxy_pass http://taskhub:8080             │
 │   network "default"      ▼   (DNS nội bộ của Docker phân giải tên)     │
 │   của project       taskhub:8080   ── Spring Boot, user không phải root│
 │                          │ jdbc:postgresql://postgres:5432/taskhub    │
 │                          ▼                                            │
 │                     postgres:5432  ── không publish ra máy            │
 │                          │                                            │
 │                     volume "pgdata" ── dữ liệu sống sót qua down/up    │
 └───────────────────────────────────────────────────────────────────────┘
```

| Service | Image | Publish ra máy | Ghi chú |
|---|---|---|---|
| `nginx` | `nginx:1.30-alpine` | `${NGINX_HOST_PORT:-8000}:80` | Cổng vào duy nhất |
| `taskhub` | build từ `docker/Dockerfile` (runtime `eclipse-temurin:21-jre-noble`) | Không | Chỉ nginx gọi tới |
| `postgres` | `postgres:17` | Không (debug tạm: `127.0.0.1:5432:5432`) | Mật khẩu từ `.env` |

**Vì sao upstream đổi từ `127.0.0.1:8080` (tuần 5) sang `taskhub:8080`?** Ở tuần 5, Nginx và ứng dụng chạy trên **cùng một máy** (WSL) nên `127.0.0.1` trỏ đúng. Trong Docker, mỗi container có **network namespace riêng**: `127.0.0.1` bên trong container `nginx` là chính container `nginx`, nơi không có gì nghe port 8080 → 502. Các service cùng project Compose nằm chung một network và gọi nhau bằng **tên service**, do DNS nội bộ của Docker phân giải (nối [Networking bài 03](../../02-NETWORKING/03-dns-dhcp.md) và [bài 05](../../02-NETWORKING/05-tcp-udp-ports-firewall.md)). Giữ file `docs/experiments/nginx-wsl.conf` của tuần 5 để so sánh.

---

## 3. File phải có trong repo

Theo [cấu trúc repo](../../00-ROADMAP/curriculum-structure.md#4-cấu-trúc-repo-dự-án-taskhub):

```text
taskhub/
├── app/                      # đã có từ tuần 6
├── docker/
│   ├── Dockerfile            # MỚI — multi-stage
│   └── nginx/
│       └── default.conf      # MỚI — reverse proxy tới taskhub:8080
├── compose.yaml              # MỚI — ở GỐC repo
├── .dockerignore             # MỚI — ở GỐC repo (gốc của build context)
├── .env.example              # CẬP NHẬT — thêm biến cho Compose
└── README.md                 # CẬP NHẬT — mục "Chạy bằng Docker Compose"
```

**Quyết định: `Dockerfile` đặt ở `docker/Dockerfile`, không đặt ở gốc.** Lý do: gom mọi thứ liên quan đến container vào một chỗ, gốc repo gọn. Hệ quả cần hiểu:

- *Build context* (thư mục gửi cho Docker khi build) vẫn là **gốc repo**, vì Dockerfile cần `COPY app/ ...`. Trong `compose.yaml`: `build: { context: ., dockerfile: docker/Dockerfile }`.
- Vì context là gốc repo, `.dockerignore` phải nằm ở **gốc repo**. Nó loại `.git/`, `app/target/`, `.env`, `.idea/`… khỏi context → build nhanh hơn và **không lọt secret vào image**.

**`.env.example`** (commit) — các biến Compose cần:

```bash
POSTGRES_DB=taskhub
POSTGRES_USER=taskhub
POSTGRES_PASSWORD=change-me
NGINX_HOST_PORT=8000
```

`compose.yaml` truyền cho `taskhub`: `SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/taskhub`, `SPRING_DATASOURCE_USERNAME=${POSTGRES_USER}`, `SPRING_DATASOURCE_PASSWORD=${POSTGRES_PASSWORD}` — cùng tên biến ứng dụng đã đọc từ tuần 6, chỉ đổi giá trị. Đây chính là lý do ta cấu hình bằng biến môi trường.

> File `.env` ở gốc repo dùng cho máy dev ở tuần 6 chứa `SPRING_DATASOURCE_URL=...localhost...`. Từ v0, Compose tự đọc file `.env` ở thư mục chứa `compose.yaml` để thay các `${...}`. Hãy cập nhật `.env` của bạn theo `.env.example` mới (giữ dòng cũ nếu vẫn muốn chạy `./mvnw spring-boot:run` ngoài Docker).

---

## 4. Yêu cầu chất lượng

| # | Yêu cầu | Vì sao | Học ở |
|---|---|---|---|
| Q1 | **Multi-stage build**: stage build dùng `eclipse-temurin:21-jdk-noble` chạy `./mvnw package`; stage runtime dùng `eclipse-temurin:21-jre-noble` chỉ chứa file `.jar` | Image chạy không chứa JDK, Maven, mã nguồn → nhỏ hơn, ít lỗ hổng hơn | Docker bài 03 |
| Q2 | Ứng dụng chạy bằng **user không phải root** (tạo user `taskhub` trong Dockerfile, `USER taskhub`) | Bị chiếm quyền app thì kẻ tấn công không có root trong container | Linux bài 03, Docker bài 07 |
| Q3 | Thứ tự lệnh tận dụng **cache layer**: copy `pom.xml` + `.mvn/` + `mvnw` và tải dependency **trước** khi copy `src/` | Sửa code không phải tải lại toàn bộ dependency | Docker bài 02, 03 |
| Q4 | **Ghi lại kích thước image** (`docker image ls`) vào README và so sánh với bản build một stage | Thấy rõ lợi ích của Q1. Với `jre-noble` + ứng dụng có JPA/Flyway, image thường vào khoảng vài trăm MB. 🟨 Muốn đạt mục tiêu < 300MB của [ma trận kỹ năng](../../00-ROADMAP/skill-matrix.md#docker), thử `21-jre-alpine` hoặc 🟦 `jlink` và ghi lại đánh đổi | Docker bài 03 |
| Q5 | `postgres` có **healthcheck** (`pg_isready -U ... -d ...`); `taskhub` có `depends_on: postgres: condition: service_healthy` | App không khởi động khi database chưa sẵn sàng (tránh lỗi `Connection refused` lúc khởi động) | Docker bài 05 |
| Q6 | `taskhub` có **healthcheck** gọi `/actuator/health` | Docker biết app "sống thật" chứ không chỉ "process còn chạy" | Docker bài 05, 08 |
| Q7 | **Restart policy** (`restart: unless-stopped`) cho cả 3 service | Tự khởi động lại khi app chết hoặc khi Docker khởi động lại | Docker bài 05 |
| Q8 | **Chỉ nginx publish port**. Postgres không publish (nếu cần debug thì tạm thêm `127.0.0.1:5432:5432`, xóa trước khi commit) | Thu nhỏ bề mặt tấn công; tập thói quen trước khi lên AWS | Networking bài 05 |
| Q9 | **Không có secret trong image**: không `COPY .env`, không `ENV ...PASSWORD=...` trong Dockerfile; kiểm tra bằng `docker history` và `docker image inspect` | Image có thể bị đẩy lên registry công khai (GHCR ở v1) | Docker bài 07 |
| Q10 | Dữ liệu PostgreSQL nằm trong **named volume** `pgdata` gắn vào `/var/lib/postgresql/data` (đúng cho `postgres:17`; bản 18 đổi đường dẫn — xem [tuần 6, mục 4](v-pre-week6-springboot-app.md#cách-b--chạy-bằng-một-lệnh-docker-run)) | Xóa container không mất dữ liệu | Docker bài 04 |
| Q11 | Ghim **phiên bản cụ thể** cho mọi image, không dùng `latest` | Build lặp lại được; nâng cấp có chủ đích | Docker bài 02 |

**Lưu ý cho Q6 — image `jre-noble` có `curl` không?** Đừng đoán, **kiểm tra**:

```bash
docker run --rm eclipse-temurin:21-jre-noble sh -c 'command -v curl wget bash || true'
```

> Tại thời điểm viết (2026-10-31), [Dockerfile chính thức của Adoptium](https://github.com/adoptium/containers/blob/main/21/jre/ubuntu/noble/Dockerfile) cài sẵn `curl` và `wget` trong image này, nên Dockerfile mẫu ở [Docker bài 03](../../04-DOCKER/03-dockerfile-multistage.md) dùng thẳng `curl` cho `HEALTHCHECK`. Vẫn chạy lệnh trên để tự xác nhận — nội dung image gốc có thể đổi khi nâng phiên bản.

Tùy kết quả, chọn một trong các cách và **ghi lý do vào README**:

| Cách | Ưu | Nhược |
|---|---|---|
| Dùng công cụ đã có sẵn trong image (nếu lệnh trên tìm thấy) | Không thêm gì | Phụ thuộc vào nội dung image gốc, có thể đổi khi nâng phiên bản |
| Cài `curl` trong stage runtime (`apt-get install -y --no-install-recommends curl`) | Rõ ràng, dễ đọc | Image to hơn, thêm phần mềm có thể có lỗ hổng |
| Dùng `bash` với `/dev/tcp` để gửi một request HTTP thô (nếu image có `bash`) | Không cài thêm gì | Khó đọc; cần giải thích được từng phần |

**Nginx và DNS** 🟨: Nginx phân giải tên `taskhub` **một lần lúc khởi động**. Nếu container `taskhub` bị tạo lại và đổi IP, Nginx có thể vẫn gọi IP cũ → 502 cho tới khi reload. Quan sát hiện tượng này trong thử nghiệm T5 và ghi lại cách xử lý bạn chọn.

---

## 5. Thử nghiệm bắt buộc

Làm từng thử nghiệm, ghi **lệnh + kết quả quan sát + giải thích** vào `docs/experiments/v0-tests.md` trong repo.

| # | Thử nghiệm | Lệnh gợi ý | Kết quả mong đợi — bạn phải giải thích được |
|---|---|---|---|
| T1 | Dữ liệu sống sót qua `down`/`up` | Tạo vài task → `docker compose down` → `docker compose up -d` → `GET /api/tasks` | Task vẫn còn. Vì sao? (`down` xóa container và network, **không** xóa named volume) |
| T2 | `down -v` xóa dữ liệu | `docker compose down -v` → `up -d` → `GET /api/tasks` | Danh sách rỗng; log có Flyway chạy lại migration V1. ⚠️ Lệnh này xóa dữ liệu thật |
| T3 | App chết thì tự sống lại | `docker compose exec taskhub sh -c 'kill 1'` rồi `docker compose ps` và `docker compose logs taskhub --tail 30` | Container khởi động lại; ghi lại exit code. Vì sao `docker compose stop taskhub` thì **không** tự khởi động lại? |
| T4 | Database chết | `docker compose stop postgres` → `curl -s -w '\n%{http_code}\n' localhost:8000/actuator/health` → `GET /api/tasks` → `docker compose start postgres` Treo ~30 giây (timeout mặc định của HikariCP) rồi **504 từ nginx** (`proxy_read_timeout 30s` hết trước) — gọi thẳng app trong container thì thấy health `DOWN` + 503, API 500 (xem TN 3 của [lab](../../04-DOCKER/labs/lab-springboot-postgres-compose/README.md)). Giải thích dây chuyền timeout; trạng thái healthcheck của `taskhub` trong `docker compose ps` đổi thế nào? Bật lại thì app tự hồi phục |
| T5 | Tạo lại app, Nginx còn gọi được không? | `docker compose up -d --force-recreate taskhub` → gọi qua nginx ngay | Ghi lại có 502 hay không; nếu có, vì sao (xem lưu ý Nginx và DNS ở mục 4) |
| T6 | Không có secret trong image | `docker history <image>`, `docker image inspect <image>` (xem `Config.Env`) | Không thấy mật khẩu |
| T7 | Chạy bằng user nào? | `docker compose exec taskhub id` | Không phải `uid=0(root)` |
| T8 | Postgres không lộ ra ngoài | `ss -ltn \| grep 5432` trên WSL; `nc -zv localhost 5432` | Không có ai nghe 5432 trên máy (nếu bạn không bật dòng debug) |

---

## 6. Câu hỏi tự kiểm

1. Build context là gì? Vì sao `.dockerignore` phải nằm ở gốc repo dù Dockerfile nằm trong `docker/`?
2. Nếu đổi thứ tự thành `COPY app/ .` rồi mới tải dependency, mỗi lần sửa một dòng code thì build chậm đi thế nào? Vì sao?
3. `depends_on` không có `condition: service_healthy` thì đảm bảo được gì và **không** đảm bảo được gì?
4. Trong container `nginx`, `curl http://127.0.0.1:8080` trả về gì? `curl http://taskhub:8080/actuator/health` thì sao? Giải thích bằng network namespace.
5. `docker compose down` và `docker compose down -v` khác nhau thế nào? Lệnh nào bạn **không bao giờ** chạy trên production mà không có backup?
6. Biến `POSTGRES_PASSWORD` đi từ đâu đến ứng dụng Spring Boot? Vẽ đường đi: `.env` → Compose → container `postgres` và container `taskhub` → `spring.datasource.password`.
7. Exit code ở thử nghiệm T3 là bao nhiêu? Nối với [Linux bài 04](../../01-LINUX/04-processes-systemd.md) (128 + số hiệu signal).
8. Vì sao image chạy không nên chứa JDK và Maven?

---

## 7. Definition of Done và release v0.2.0

- [ ] `docker compose up -d --build` từ một bản clone mới (chỉ thêm `.env`) dựng thành công cả 3 service; `docker compose ps` cho thấy `postgres` và `taskhub` ở trạng thái `healthy`.
- [ ] `curl -i http://localhost:8000/api/tasks` và `/actuator/health` trả đúng, **đi qua nginx** (header `Server: nginx`).
- [ ] Đạt đủ yêu cầu chất lượng Q1–Q11; kích thước image và lý do chọn cách healthcheck được ghi trong README.
- [ ] Hoàn thành T1–T8 và ghi lại trong `docs/experiments/v0-tests.md`.
- [ ] `git grep -n -i password` chỉ ra tên biến/placeholder; `.env` không có trong repo, `.env.example` có.
- [ ] README có mục **"Chạy bằng Docker Compose"**: yêu cầu, các bước, bảng biến môi trường, cách xem log, cách dọn dẹp (`down` vs `down -v`).
- [ ] Code vào `main` qua Pull Request (ví dụ nhánh `feat/docker-compose`); tag và GitHub Release **`v0.2.0`**.
- [ ] Ít nhất một lỗi gặp phải trong lúc làm đã được ghi vào nhật ký debug.

➡️ Tiếp theo: [**v1 — CI với GitHub Actions**](v1-ci.md) (tuần 9–10): pipeline sẽ build chính `docker/Dockerfile` này và đẩy image lên GHCR (`ghcr.io/<github-user>/taskhub`).
