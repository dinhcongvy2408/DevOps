# Lab — Spring Boot + PostgreSQL + Nginx bằng Docker Compose

> Tuần 8 · ⏱️ ~4 giờ · Mức độ: 🟥 **Lab bắt buộc** của giáo trình · Môi trường: `[WSL]` + Docker Desktop
> Kiến thức cần có: [03. Dockerfile & multi-stage build](../../03-dockerfile-multistage.md), [04. Volumes, networks & biến môi trường](../../04-volumes-networks-env.md), [05. Docker Compose](../../05-docker-compose.md), [Networking 07 — Reverse proxy](../../../02-NETWORKING/07-load-balancing-reverse-proxy.md)

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc lab](#2-kiến-trúc-lab)
- [3. Chuẩn bị](#3-chuẩn-bị)
- [4. Các bước thực hiện](#4-các-bước-thực-hiện)
- [5. Thí nghiệm bắt buộc](#5-thí-nghiệm-bắt-buộc)
- [6. Kết quả mong đợi](#6-kết-quả-mong-đợi)
- [7. Lỗi thường gặp](#7-lỗi-thường-gặp)
- [8. Dọn dẹp](#8-dọn-dẹp)
- [9. Câu hỏi sau lab](#9-câu-hỏi-sau-lab)

---

## 1. Mục tiêu

Đóng gói ứng dụng `taskhub` (Spring Boot) và chạy cùng PostgreSQL + Nginx bằng **một lệnh**, theo đúng cách làm ở công ty:

- Image app build bằng **multi-stage**, chạy bằng **user non-root**.
- Database lưu dữ liệu trong **named volume**, **không** publish ra ngoài.
- App lấy cấu hình kết nối từ **biến môi trường**; mật khẩu nằm trong `.env` — **không commit**.
- Khởi động **đúng thứ tự** nhờ healthcheck: `postgres` healthy → `taskhub` healthy → `nginx`.
- Chỉ **nginx** nhận request từ bên ngoài, ở `http://localhost:8000`.

Kết quả của lab chính là **dự án taskhub v0** — xem [milestone v0](../../../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md).

> Đầu ra mẫu trong lab là **minh họa**. ID, thời gian, dung lượng, số phiên bản trên máy bạn sẽ khác. Các bước của lab **chưa được chạy thử** trên máy thật — nếu kết quả khác, hãy ghi lại vào nhật ký debug: đó cũng là luyện tập.

---

## 2. Kiến trúc lab

```text
  curl / trình duyệt Windows
          │  http://localhost:8000
          ▼
┌───────────────────────── project "taskhub" — network taskhub_default ─────────────────────────┐
│                                                                                               │
│  nginx (nginx:1.30-alpine)         taskhub (image build từ docker/Dockerfile)                 │
│  publish 8000 → 80        ───────► taskhub:8080   Spring Boot, user "taskhub" (non-root)      │
│  docker/nginx/default.conf         SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/...  │
│  (bind mount, chỉ đọc)                    │                                                   │
│                                           ▼                                                   │
│                                    postgres (postgres:17) ──► volume taskhub_pgdata           │
│                                    KHÔNG publish port                                         │
│                                                                                               │
│  Healthcheck:  postgres: pg_isready   taskhub: curl /actuator/health                          │
│  Khởi động:    postgres (healthy) → taskhub (healthy) → nginx                                 │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

Cấu trúc repo sau lab (chỉ những phần liên quan):

```text
~/projects/taskhub/
├── app/                      # mã Spring Boot từ tuần 6 (mvnw, .mvn/, pom.xml, src/)
├── docker/
│   ├── Dockerfile
│   └── nginx/default.conf
├── compose.yaml
├── .dockerignore
├── .env.example              # commit
├── .env                      # KHÔNG commit (đã có trong .gitignore)
└── .gitignore
```

---

## 3. Chuẩn bị

### 3.1. Điều kiện

- [ ] Ứng dụng `taskhub` ở `~/projects/taskhub/app/` đã chạy được trên máy với PostgreSQL theo [đặc tả tuần 6](../../../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-6--đặc-tả-ứng-dụng-spring-boot) và [hướng dẫn tạo app](../../../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md): có Actuator, Flyway, đọc `SPRING_DATASOURCE_*` từ biến môi trường, log ra stdout.
- [ ] Docker Desktop đang chạy, `docker version` trong WSL thấy cả Client và Server ([README module, mục 3.2](../../README.md#32-kiểm-tra-môi-trường-trước-khi-học-wsl)).
- [ ] Port `8000` trên máy đang trống: `ss -tlnp | grep ':8000 '` không in gì.
- [ ] Nếu đã cài nginx trên WSL ở lab Networking tuần 5, nó dùng port 80 — **không** xung đột với port 8000 của lab này.

### 3.2. Tạo nhánh làm việc

```bash
cd ~/projects/taskhub
git switch main && git pull
git switch -c feat/docker-compose
```

Làm việc trên nhánh rồi mở Pull Request — đúng quy trình ở [Module 03](../../../03-GIT/README.md).

### 3.3. Về các file tham khảo

Thư mục [reference/](reference/) có bản hoàn chỉnh của mọi file trong lab. **Chỉ mở sau khi đã tự viết** và chạy thử — tự viết rồi so sánh mới là cách học. Các bước dưới đây có đủ nội dung để bạn làm theo, kèm giải thích từng dòng.

---

## 4. Các bước thực hiện

### Bước 1 — `.dockerignore`

Build context là **gốc repo** (để Dockerfile lấy được `app/`). Không có `.dockerignore`, Docker gửi cả `.git`, `app/target/` và `.env` vào context — vừa chậm, vừa có nguy cơ secret lọt vào image.

Tạo `~/projects/taskhub/.dockerignore`:

```text
.git
.github
.idea
.vscode
**/*.iml
**/target/
**/*.log
.env
.env.*
!.env.example
docker/nginx/
compose*.yaml
docs/
```

| Dòng | Lý do |
|---|---|
| `.git` | Lịch sử Git có thể hàng trăm MB, không cần cho build |
| `**/target/` | Kết quả build trên máy — image tự build lại bên trong, không dùng bản trên máy |
| `.env`, `.env.*` | **Secret** — không bao giờ được vào build context |
| `!.env.example` | Dấu `!` = ngoại lệ: không loại file mẫu (dù image cũng không cần nó) |
| `docker/nginx/`, `compose*.yaml` | Không liên quan tới image app; sửa chúng không nên làm mất cache build |

### Bước 2 — `docker/Dockerfile`

Dockerfile multi-stage đã học ở [bài 03](../../03-dockerfile-multistage.md). Bản đầy đủ cho repo có code trong `app/`:

```dockerfile
# syntax=docker/dockerfile:1

# ---------- Stage 1: build ----------
FROM eclipse-temurin:21-jdk-noble AS build
WORKDIR /workspace
COPY app/.mvn/ .mvn/
COPY app/mvnw app/pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline
COPY app/src/ src/
RUN ./mvnw -B -q package -DskipTests \
 && cp target/*.jar app.jar

# ---------- Stage 2: runtime ----------
FROM eclipse-temurin:21-jre-noble
RUN groupadd --system taskhub \
 && useradd --system --gid taskhub --no-create-home --shell /usr/sbin/nologin taskhub
WORKDIR /app
COPY --from=build --chown=root:taskhub /workspace/app.jar /app/app.jar
LABEL org.opencontainers.image.source="https://github.com/<username>/taskhub"
USER taskhub
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
```

| Phần | Giải thích ngắn (chi tiết ở bài 03) |
|---|---|
| `COPY app/.mvn/` + `app/mvnw app/pom.xml` trước, `app/src/` sau | Đổi code không làm mất cache của bước tải dependency |
| `dependency:go-offline` | Tải dependency vào layer riêng. Một số plugin vẫn có thể tải thêm ở bước `package` — chấp nhận được |
| `-DskipTests` | Test chạy ở pipeline CI (Module 05), không chạy lúc build image |
| `cp target/*.jar app.jar` | Đổi tên file jar về tên cố định để stage sau không phụ thuộc phiên bản trong `pom.xml` |
| Stage 2 từ `jre-noble` | Không có JDK, Maven, mã nguồn → image nhỏ hơn và ít công cụ cho kẻ tấn công |
| `--chown=root:taskhub` + `USER taskhub` | App đọc được jar nhưng không sửa được; process không chạy bằng root |
| `HEALTHCHECK ... curl` | Image `jre-noble` có sẵn `curl`. Healthcheck trong `compose.yaml` (Bước 5) sẽ ghi đè cái này khi chạy bằng Compose |
| `ENTRYPOINT [...]` dạng exec | `java` là PID 1, nhận SIGTERM trực tiếp → graceful shutdown |
| `-XX:MaxRAMPercentage=75.0` | JVM nhận biết giới hạn RAM của container; heap tối đa 75%, để lại 25% cho bộ nhớ ngoài heap (metaspace, thread stack…). Có tác dụng khi container bị giới hạn RAM — sẽ đặt ở [bài 07](../../07-docker-security.md) và trên EC2 |

Build thử riêng image:

```bash
cd ~/projects/taskhub
docker build -f docker/Dockerfile -t taskhub:local .
docker image ls taskhub
```

```text
REPOSITORY   TAG     IMAGE ID       CREATED          SIZE
taskhub      local   3f2a9c81d0e4   10 seconds ago   312MB
```

❓ Lần build đầu mất bao lâu? Sửa một dòng trong `app/src/` rồi build lại — bước `dependency:go-offline` có chạy lại không (tìm chữ `CACHED` trong output)?

### Bước 3 — `docker/nginx/default.conf`

Đây là bản container của cấu hình bạn viết ở lab Networking tuần 5 — chỉ khác **upstream**: `127.0.0.1:8080` → `taskhub:8080`.

```bash
mkdir -p docker/nginx
```

```nginx
upstream taskhub_backend {
    server taskhub:8080;          # tên service trong compose.yaml, DNS nội bộ Docker phân giải
}

server {
    listen 80;
    server_name _;
    client_max_body_size 2m;

    location / {
        proxy_pass http://taskhub_backend;
        proxy_set_header Host              $http_host;   # giữ cả port client gõ (localhost:8000)
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout    30s;
    }
}
```

> **`$http_host` hay `$host`?** `$host` chỉ có tên máy (`localhost`), **mất port**. Spring Boot dựng header `Location` từ header `Host` nhận được → với `$host`, `POST` trả `Location: http://localhost/api/tasks/1` — thiếu `:8000`, client đi theo link sẽ hỏng. `$http_host` là nguyên văn header `Host` client gửi (`localhost:8000`). Trên server thật dùng port 80/443 thì hai biến cho cùng kết quả, nên nhiều tài liệu viết `$host`. (Đã kiểm chứng khi chạy lab ngày 2026-10-31.)

❓ Vì sao `127.0.0.1:8080` (đúng ở tuần 5) lại sai khi nginx chạy trong container? (Gợi ý: network namespace — [bài 01](../../01-vm-vs-container-architecture.md).)

### Bước 4 — `.env.example` và `.env`

```bash
cat > .env.example <<'EOF'
# Mẫu biến cho compose.yaml. Dùng: cp .env.example .env rồi đổi giá trị. KHÔNG commit .env
POSTGRES_PASSWORD=change-me-to-a-long-random-password
NGINX_HOST_PORT=8000
EOF

cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
grep -n '^\.env$' .gitignore || echo ".env" >> .gitignore
git status --short
```

| Lệnh | Ý nghĩa |
|---|---|
| `openssl rand -hex 16` | Sinh mật khẩu ngẫu nhiên 32 ký tự hex — không tự nghĩ mật khẩu |
| `sed -i "s/^POSTGRES_PASSWORD=.*/.../"` | Thay dòng mật khẩu trong `.env` ([Linux bài 02](../../../01-LINUX/02-essential-commands-text.md)) |
| `grep ... \|\| echo ... >> .gitignore` | Đảm bảo `.env` có trong `.gitignore` (thêm nếu chưa có) |

❓ `git status --short` có liệt kê `.env` không? (Phải **không** — nếu có, dừng lại và sửa `.gitignore` trước khi làm tiếp.)

### Bước 5 — `compose.yaml`

Tạo `~/projects/taskhub/compose.yaml`. Đọc comment từng dòng:

```yaml
name: taskhub                       # tên project cố định → volume luôn là taskhub_pgdata

services:
  postgres:
    image: postgres:17              # bản 18 đổi thư mục dữ liệu (xem README module 04)
    restart: unless-stopped         # tự chạy lại khi Docker/máy khởi động lại
    environment:
      POSTGRES_DB: taskhub          # tạo database "taskhub" lần khởi tạo đầu tiên
      POSTGRES_USER: taskhub        # tạo user "taskhub"
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}   # bắt buộc, lấy từ .env
    volumes:
      - pgdata:/var/lib/postgresql/data    # dữ liệu sống ngoài vòng đời container
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "taskhub", "-d", "taskhub"]   # công cụ có sẵn trong image postgres
      interval: 5s
      timeout: 3s
      retries: 10
    # KHÔNG có "ports": chỉ container trong network này kết nối được tới 5432

  taskhub:
    build:
      context: .                    # gốc repo — Dockerfile cần lấy app/
      dockerfile: docker/Dockerfile # tính từ context
    image: taskhub:local            # tên gán cho image build ra (dùng khi tag/push — bài 06)
    restart: unless-stopped
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/taskhub   # "postgres" = tên service
      SPRING_DATASOURCE_USERNAME: taskhub
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
    depends_on:
      postgres:
        condition: service_healthy  # chờ PostgreSQL nhận kết nối được, không chỉ "đã khởi động"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 60s             # JVM + Spring + Flyway cần thời gian khởi động

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    ports:
      - "${NGINX_HOST_PORT:-8000}:80"   # service DUY NHẤT publish ra máy host
    volumes:
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro   # cấu hình từ repo, chỉ đọc
    depends_on:
      taskhub:
        condition: service_healthy  # nginx khởi động khi upstream đã sẵn sàng

volumes:
  pgdata:                           # named volume do Docker quản lý
```

**Về healthcheck của `taskhub`:** lệnh dùng `curl`. Image `eclipse-temurin:21-jre-noble` có cài sẵn `curl` và `wget` (theo [Dockerfile chính thức của image](https://github.com/adoptium/containers/blob/main/21/jre/ubuntu/noble/Dockerfile)), nên không cần cài thêm. Tự kiểm chứng trước khi tin:

```bash
docker run --rm --entrypoint which eclipse-temurin:21-jre-noble curl    # in ra /usr/bin/curl
```

Healthcheck trong `compose.yaml` **ghi đè** `HEALTHCHECK` trong Dockerfile — ở đây dùng `interval` ngắn hơn để thứ tự khởi động nhanh hơn. Nếu sau này bạn đổi sang image tối giản không có `curl`, healthcheck sẽ báo `unhealthy` dù app vẫn khỏe — xem [bài 05, mục 12.3](../../05-docker-compose.md#123-healthcheck-thất-bại-vì-chính-lệnh-healthcheck).

### Bước 6 — Kiểm tra cấu hình trước khi chạy

```bash
docker compose config --quiet && echo "compose.yaml hợp lệ"
docker compose config --services
docker compose config | grep -A3 'SPRING_DATASOURCE_URL'
```

```text
compose.yaml hợp lệ
postgres
taskhub
nginx
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/taskhub
      SPRING_DATASOURCE_USERNAME: taskhub
      SPRING_DATASOURCE_PASSWORD: 3c9e...
```

⚠️ `docker compose config` in **mật khẩu thật**. Không dán output này lên chat hay issue.

Thử đổi tên `.env` thành `.env.bak` rồi chạy lại `docker compose config --quiet` — đọc thông báo lỗi, rồi đổi tên lại.

### Bước 7 — Dựng toàn bộ hệ thống

```bash
docker compose up -d --build
docker compose ps
```

```text
[+] Running 6/6
 ✔ taskhub                       Built
 ✔ Network taskhub_default       Created
 ✔ Volume "taskhub_pgdata"       Created
 ✔ Container taskhub-postgres-1  Healthy
 ✔ Container taskhub-taskhub-1   Healthy
 ✔ Container taskhub-nginx-1     Started

NAME                 IMAGE               SERVICE    STATUS                    PORTS
taskhub-nginx-1      nginx:1.30-alpine   nginx      Up 5 seconds              0.0.0.0:8000->80/tcp
taskhub-postgres-1   postgres:17         postgres   Up 50 seconds (healthy)   5432/tcp
taskhub-taskhub-1    taskhub:local       taskhub    Up 40 seconds (healthy)   8080/tcp
```

Theo dõi quá trình khởi động của app nếu muốn:

```bash
docker compose logs -f taskhub
```

Tìm các dòng: Flyway áp dụng migration `V1__create_tasks_table`, `Tomcat started on port 8080`, `Started TaskhubApplication in ... seconds`. Nhấn Ctrl+C để thoát xem log (container vẫn chạy).

❓ Cột `PORTS` của `postgres` và `taskhub` có mũi tên `->` không? Điều đó nghĩa là gì?

### Bước 8 — Gọi API qua nginx

```bash
curl -s http://localhost:8000/actuator/health; echo

curl -s -i -X POST http://localhost:8000/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Viết compose.yaml","description":"Lab tuần 8"}'

curl -s http://localhost:8000/api/tasks; echo
```

```text
{"groups":["liveness","readiness"],"status":"UP"}

HTTP/1.1 201
Server: nginx/1.30.6
Location: http://localhost:8000/api/tasks/1
Content-Type: application/json
...
{"id":1,"title":"Viết compose.yaml","description":"Lab tuần 8","status":"TODO",...}

[{"id":1,"title":"Viết compose.yaml",...}]
```

Mở `http://localhost:8000/api/tasks` trên trình duyệt Windows.

❓ Header `Server:` cho biết ai trả lời trực tiếp cho `curl`? Header `Location` có đúng host và port `localhost:8000` không? (Nếu nó ghi `taskhub:8080`, app chưa dùng header `Host`/`X-Forwarded-*` — ghi lại làm việc cần sửa.)

### Bước 9 — Kiểm tra dữ liệu trong PostgreSQL

```bash
docker compose exec postgres psql -U taskhub -d taskhub -c '\dt'
docker compose exec postgres psql -U taskhub -d taskhub -c 'SELECT id, title, status FROM tasks;'
```

```text
                 List of relations
 Schema |         Name          | Type  |  Owner
--------+-----------------------+-------+---------
 public | flyway_schema_history | table | taskhub
 public | tasks                 | table | taskhub

 id |       title       | status
----+-------------------+--------
  1 | Viết compose.yaml | TODO
```

> Tên bảng phụ thuộc migration của bạn — đặc tả tuần 6 dùng `V1__create_tasks_table.sql` nên thường là `tasks`.

### Bước 10 — Commit (chưa có `.env`)

```bash
git status --short
git add .dockerignore docker/ compose.yaml .env.example .gitignore
git commit -m "feat(docker): containerize taskhub with compose (nginx, app, postgres)"
git push -u origin feat/docker-compose
```

Mở Pull Request trên GitHub. Trước khi merge, kiểm tra tab **Files changed**: không có `.env`, không có mật khẩu thật.

---

## 5. Thí nghiệm bắt buộc

Mỗi thí nghiệm ghi lại: **dự đoán trước** → lệnh → kết quả thật → giải thích. Lưu vào `~/devops-journey/week08/lab-compose-experiments.md`.

### Thí nghiệm 1 — Dữ liệu sống qua `down`, mất khi `down -v`

```bash
docker compose down
docker volume ls | grep taskhub
docker compose up -d
docker compose ps                                   # chờ cả 3 healthy/Up
curl -s http://localhost:8000/api/tasks; echo
```

Dữ liệu có còn không? Tiếp theo:

```bash
docker compose down -v                              # ⚠️ xóa volume — mất dữ liệu
docker volume ls | grep taskhub || echo "không còn volume taskhub"
docker compose up -d
curl -s http://localhost:8000/api/tasks; echo
```

Task cũ còn không? Trong log của `postgres` lần này có dòng về việc khởi tạo database mới không (`docker compose logs postgres | head -20`)?

### Thí nghiệm 2 — App chết thì có tự sống lại không?

Tạo lại một task, rồi làm process Java **tự thoát** (không phải bạn dừng container bằng lệnh Docker):

```bash
docker compose exec taskhub kill -TERM 1
sleep 3; docker compose ps taskhub
sleep 60; docker compose ps taskhub
docker inspect --format 'RestartCount={{.RestartCount}}' taskhub-taskhub-1
docker compose logs taskhub --tail 30
```

| Lệnh | Ý nghĩa |
|---|---|
| `kill -TERM 1` (chạy **trong** container) | Gửi SIGTERM tới PID 1 — chính là `java`. Spring Boot tắt nhẹ nhàng rồi JVM thoát với mã 143 (128 + 15) |
| `RestartCount` | Số lần Docker đã khởi động lại container này theo restart policy |

Docker coi đây là **process tự thoát** (không phải bạn dừng thủ công qua Docker), nên `restart: unless-stopped` khởi động lại container. Container đã chạy hơn 10 giây nên quy tắc "10 giây" ([bài 05, mục 4.10](../../05-docker-compose.md#410--restart--restart-policy)) không chặn việc restart.

So sánh với dừng thủ công:

```bash
docker compose stop taskhub
sleep 20; docker compose ps -a taskhub
docker compose start taskhub
```

Container có tự chạy lại không?

🟨 **Tự khám phá:** `docker compose kill taskhub` (gửi SIGKILL từ phía Docker) — container có được restart không? Tài liệu chính thức về restart policy **không nói rõ** trường hợp `kill`. Đây là dịp luyện thói quen của kỹ sư: **thử, quan sát, ghi lại**, thay vì đoán. Ghi phiên bản Docker (`docker version --format '{{.Server.Version}}'`) cạnh kết quả.

### Thí nghiệm 3 — Database chết thì app báo gì?

```bash
docker compose stop postgres
sleep 15
curl -s -i http://localhost:8000/actuator/health | head -5
docker compose ps
docker compose logs taskhub --tail 20
```

Sau đó:

```bash
sleep 60; docker compose ps taskhub     # trạng thái health của taskhub giờ là gì?
docker compose start postgres
sleep 30
curl -s http://localhost:8000/actuator/health; echo
docker compose ps
```

> ⏱️ Lệnh `curl` đầu tiên sẽ **treo khoảng 30 giây** — đó là một phần của thí nghiệm, đừng Ctrl+C. Đo bằng `time curl ...`.

Trả lời: (1) `/actuator/health` trả mã HTTP gì và nội dung gì khi database dừng? Vì sao phải chờ lâu như vậy? (2) Mã đó do ai sinh ra — nginx hay app? (Gợi ý: nhìn body JSON.) (3) Container `taskhub` chuyển sang `unhealthy` sau bao lâu — Docker có **khởi động lại** nó không? (4) Sau khi `postgres` chạy lại, app có tự kết nối lại mà không cần restart không?

### Thí nghiệm 4 — PostgreSQL có lộ ra ngoài không?

```bash
ss -tlnp | grep ':5432 ' || echo "WSL: không có gì nghe 5432"
docker compose port postgres 5432 || echo "postgres không publish port nào"
docker compose exec taskhub bash -c 'echo > /dev/tcp/postgres/5432 && echo "từ taskhub: 5432 MỞ"'
```

Từ `[PowerShell]` trên Windows:

```powershell
Test-NetConnection -ComputerName localhost -Port 5432
Test-NetConnection -ComputerName localhost -Port 8000
```

| Lệnh | Ý nghĩa |
|---|---|
| `docker compose port postgres 5432` | Port host nào đang được map tới port 5432 của container (không có = không publish) |
| `echo > /dev/tcp/postgres/5432` | Tính năng của **bash**: mở kết nối TCP tới host:port; thành công = port mở. Image `jre-noble` (Ubuntu) có bash |
| `Test-NetConnection` | Công cụ PowerShell kiểm tra kết nối TCP; `TcpTestSucceeded : True/False` |

Kết luận: ai kết nối được tới PostgreSQL, ai không? Đây là tư duy **Security Group** ở Module 06: database chỉ nhận kết nối từ app.

---

## 6. Kết quả mong đợi

| Bước / thí nghiệm | Kết quả đúng |
|---|---|
| Bước 2 | Image ~300 MB (JRE + Ubuntu + app). Build lại sau khi sửa code: bước `dependency:go-offline` hiện `CACHED` |
| Bước 3 | `127.0.0.1` trong container nginx là **chính container nginx** — không có gì nghe 8080 ở đó |
| Bước 4 | `.env` **không** xuất hiện trong `git status` |
| Bước 6 | Thiếu `.env` → lỗi `required variable POSTGRES_PASSWORD is missing a value: set POSTGRES_PASSWORD in .env` |
| Bước 7 | Ba container; chỉ `nginx` có `0.0.0.0:8000->80/tcp`. `postgres` và `taskhub` chỉ hiện `5432/tcp`, `8080/tcp` (không publish) |
| Bước 8 | `{"status":"UP"}`; POST trả `201` với `Location`; header `Server: nginx/...` — nginx trả lời trực tiếp cho client |
| TN 1 | Sau `down`: dữ liệu **còn**. Sau `down -v`: dữ liệu **mất**, log postgres cho thấy khởi tạo database mới |
| TN 2 | Sau `kill -TERM 1`: container dừng rồi **tự chạy lại**, `RestartCount` tăng lên 1, log có dấu hiệu graceful shutdown rồi khởi động lại. Sau `docker compose stop`: **không** tự chạy lại |
| TN 3 | (Kết quả thật khi chạy lab, 2026-10-31.) `curl` treo **~30 giây** rồi nhận **504 Gateway Time-out** của **nginx** (body HTML, có dòng `nginx/1.30.6`). Lý do — **dây chuyền timeout**: connection pool HikariCP chờ tối đa `connection-timeout` = **30 giây** (mặc định) để lấy kết nối rồi mới báo `DOWN`; nginx chỉ chờ `proxy_read_timeout 30s` → nginx bỏ cuộc trước hoặc cùng lúc. Gọi thẳng app (`docker compose exec taskhub curl -s -w '
%{http_code}
' localhost:8080/actuator/health`) sẽ thấy **503** `{"groups":[...],"status":"DOWN"}` sau 30 giây — mã do **app** sinh. `taskhub` chuyển `unhealthy` (healthcheck có `timeout: 3s` nên hết giờ trước khi app trả lời) nhưng Docker **không restart** nó. Khi `postgres` chạy lại, app tự kết nối lại, health về `UP`. 🟨 Muốn app báo `DOWN` nhanh: thêm biến `SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT: "5000"` (5 giây) cho service `taskhub` — đã thử với 3000: nhận 503 qua nginx sau 3 giây. Bài học: **timeout của các tầng phải được thiết kế cùng nhau** |
| TN 4 | WSL và Windows **không** kết nối được 5432; `taskhub` kết nối được. Port 8000 thì Windows kết nối được |

---

## 7. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `taskhub` crash, log: `Connection to localhost:5432 refused` | App dùng `localhost` (cấu hình cứng trong `application.properties` hoặc biến môi trường không được đọc) | Dùng `SPRING_DATASOURCE_URL` với host `postgres`; kiểm tra `docker compose exec taskhub env \| grep SPRING` |
| `taskhub` crash, log: `Connection to postgres:5432 refused` ngay lúc khởi động | App khởi động trước khi PostgreSQL sẵn sàng (thiếu `condition: service_healthy` hoặc thiếu healthcheck ở `postgres`) | Thêm healthcheck cho `postgres` và `depends_on ... condition: service_healthy` |
| `FATAL: password authentication failed for user "taskhub"` | Đã đổi `POSTGRES_PASSWORD` trong `.env` **sau khi** volume được khởi tạo. Image postgres chỉ dùng biến này **lần khởi tạo đầu tiên** (khi thư mục dữ liệu trống) | Dữ liệu thử nghiệm: `docker compose down -v` rồi `up -d` (⚠️ mất dữ liệu). Dữ liệu cần giữ: đổi mật khẩu bằng `ALTER USER taskhub PASSWORD '...'` trong `psql` |
| `Bind for 0.0.0.0:8000 failed: port is already allocated` | Port 8000 đã bị chiếm | `docker ps` và `ss -tlnp \| grep 8000` tìm thủ phạm; hoặc đổi `NGINX_HOST_PORT=8001` trong `.env` |
| nginx: `host not found in upstream "taskhub:8080"` rồi thoát | nginx khởi động khi tên `taskhub` chưa phân giải được (service chưa tồn tại / gõ sai tên) | Kiểm tra tên service; giữ `depends_on: taskhub: condition: service_healthy` |
| nginx trả `502 Bad Gateway` sau khi `taskhub` được tạo lại | nginx phân giải tên `taskhub` **một lần lúc khởi động** và giữ IP cũ; container mới có thể có IP khác | `docker compose restart nginx` (hoặc `exec nginx nginx -s reload`). Cách triệt để dùng `resolver 127.0.0.11` — xem [bài 08](../../08-container-troubleshooting.md) |
| `taskhub` mãi `(health: starting)` rồi `unhealthy` dù app chạy | Lệnh healthcheck lỗi: sai port/đường dẫn, Actuator chưa có, hoặc image không có `curl` | `docker inspect --format '{{json .State.Health}}' taskhub-taskhub-1` xem output của healthcheck |
| Build lỗi `./mvnw: not found` hoặc `/bin/sh^M: bad interpreter` | `mvnw` có xuống dòng CRLF (sửa trên Windows) | `sed -i 's/\r$//' app/mvnw`; thêm `.gitattributes` với `mvnw text eol=lf` ([Linux bài 01](../../../01-LINUX/01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp)) |
| Build lỗi `COPY failed: ... app/pom.xml: not found` | Sai build context hoặc code không nằm trong `app/` | `context: .` (gốc repo); kiểm tra `ls app/pom.xml` |
| Build rất chậm, `Sending build context ... 800MB` / `transferring context` lâu | Thiếu `.dockerignore` hoặc thư mục dự án nằm trong `/mnt/c`, `/mnt/d` | Thêm `.dockerignore`; để repo trong `~/projects` |
| nginx lỗi đọc cấu hình, log có ký tự lạ `^M` | File `default.conf` bị CRLF | `sed -i 's/\r$//' docker/nginx/default.conf`, chuyển VS Code sang LF |
| App không đọc được `SPRING_DATASOURCE_*` (vẫn dùng giá trị mặc định trong code) | Biến môi trường không vào container (thụt lề sai dưới `environment`) | `docker compose config` để xem Compose hiểu thế nào; `docker compose exec taskhub env \| grep SPRING` |

---

## 8. Dọn dẹp

Giữ hệ thống nếu bạn còn làm [bài 06](../../06-registry.md) và [bài 08](../../08-container-troubleshooting.md). Khi muốn dọn:

```bash
cd ~/projects/taskhub
docker compose down             # xóa container + network, GIỮ dữ liệu
# hoặc
docker compose down -v          # ⚠️ xóa cả volume dữ liệu
docker image rm taskhub:local   # xóa image app (build lại được bất cứ lúc nào)
docker system df                # kiểm tra dung lượng Docker còn dùng
```

`.env` vẫn ở lại trong thư mục repo (không bị Git theo dõi) — đó là điều mong muốn.

---

## 9. Câu hỏi sau lab

1. Vẽ lại sơ đồ mục 2 **không nhìn tài liệu**, ghi rõ port nào publish, tên DNS nào được dùng ở đâu.
2. Nếu xóa `condition: service_healthy` ở `taskhub`, chuyện gì có thể xảy ra lúc khởi động? Vì sao lỗi đó **không** xảy ra mọi lần?
3. Vì sao healthcheck của `postgres` dùng `pg_isready` mà không dùng `curl`?
4. Bạn đổi `POSTGRES_PASSWORD` trong `.env` và app báo lỗi xác thực. Giải thích nguyên nhân bằng một câu, và nêu 2 cách xử lý tùy theo dữ liệu có cần giữ hay không.
5. Ở Thí nghiệm 3, container `taskhub` `unhealthy` nhưng không bị restart. Hệ thống nào bạn sẽ học sau này **có** restart container khi health check thất bại?
6. Một đồng nghiệp đề nghị thêm `ports: ["5432:5432"]` cho `postgres` "để tiện debug". Bạn trả lời thế nào? Có cách nào an toàn hơn?
7. So sánh cách chạy `taskhub` ở lab này với [Lab 02 — systemd service](../../../01-LINUX/labs/lab-02-java-systemd-service.md): user non-root, restart policy, log, cấu hình qua biến môi trường được thể hiện ở đâu trong mỗi cách?

> Câu trả lời tham khảo cho câu 2–6 nằm rải rác trong [bài 05](../../05-docker-compose.md) và mục 6–7 của lab này. Tự trả lời trước, rồi đối chiếu.
