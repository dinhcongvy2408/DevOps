# Lời giải — Break-fix Docker #1

> ⚠️ Chỉ đọc khi đã hoàn thành, hoặc đã kẹt quá 30 phút sau khi xem hết gợi ý. Trọng tâm của lời giải là **cách tìm ra** từng lỗi — cách sửa chỉ là phần nhỏ.

Quay lại đề: [labs/break-fix-01/README.md](../labs/break-fix-01/README.md)

## Mục lục

- [Tổng quan 7 lỗi](#tổng-quan-7-lỗi)
- [Ticket #5001 — Môi trường không lên (2 lỗi)](#ticket-5001--môi-trường-không-lên-2-lỗi)
- [Ticket #5002 — Welcome to nginx](#ticket-5002--welcome-to-nginx)
- [Ticket #5003 — Mất dữ liệu sau bảo trì](#ticket-5003--mất-dữ-liệu-sau-bảo-trì)
- [Ticket #5004 — Dừng mất 10 giây](#ticket-5004--dừng-mất-10-giây)
- [Ticket #5005 — Rà soát bảo mật (3 lỗi)](#ticket-5005--rà-soát-bảo-mật-3-lỗi)
- [Các file sau khi sửa](#các-file-sau-khi-sửa)
- [Bài học mang về taskhub](#bài-học-mang-về-taskhub)

---

## Tổng quan 7 lỗi

| # | Ticket | Lỗi | Bước tìm ra (quy trình bài 08) | verify |
|---|---|---|---|---|
| 1 | #5001 | `DB_HOST: localhost` | 1 (exit 1) → 2 (log) → 3 (env) | [1] |
| 2 | #5001 | `depends_on` dạng ngắn, postgres không có healthcheck | 2 (log có `-t`, so thứ tự) → 3 (`compose config`) | [2] |
| 3 | #5002 | nginx config mount thành `taskhub.conf`, xung đột với `default.conf` của image | 2 (log nginx `[warn]`) → 4 (`ls conf.d`, `nginx -T`) | [3] |
| 4 | #5003 | Volume mount `/var/lib/postgresql` (kiểu PostgreSQL 18) trên image 17 | 3 (`inspect` Mounts, `PGDATA`, `VOLUME`) | [4] |
| 5 | #5004 | `start.sh` không `exec` → `sh` là PID 1, không chuyển SIGTERM | 1 (exit 137) → 4 (`/proc/1/cmdline`) | [5] |
| 6 | #5005 | Postgres publish `5432:5432` ra mọi địa chỉ | 1 (`ps` cột PORTS) | [6] |
| 7 | #5005 | Mật khẩu hard-code trong `compose.yaml` + container api chạy root | Đọc file + 4 (`id`) | [7], [8] |

Thứ tự phát hiện tự nhiên: #5001 (lỗi 1 → 2) → #5002 → #5003 → #5004 → #5005. Một số lỗi **che** lỗi khác: khi api chết, nginx có thể cũng không khởi động được (xem lỗi 1), nên bạn chỉ thấy lỗi 3 sau khi đã sửa lỗi 1.

---

## Ticket #5001 — Môi trường không lên (2 lỗi)

### Lỗi 1: `DB_HOST` trỏ tới `localhost`

**Bước 1 — trạng thái:**

```bash
docker compose ps -a
```

```text
NAME             SERVICE    STATUS
bf04-api-1       api        Exited (0) 8 seconds ago
bf04-nginx-1     nginx      Up 9 seconds    0.0.0.0:18000->80/tcp
bf04-postgres-1  postgres   Up 9 seconds    0.0.0.0:5432->5432/tcp
```

(Kết quả thật khi chạy lab trên Docker Desktop, kiểm chứng 2026-10-31.)

**Bẫy đầu tiên: `Exited (0)`** — exit 0 nghĩa là "thoát bình thường", vậy mà api không chạy. Đọc log sẽ thấy lý do: process chính của container là `start.sh`, và dòng cuối của nó (`echo "[start.sh] api exited with code $?"`) chạy thành công → script thoát với mã của lệnh `echo` = 0. **Script bọc ngoài đã nuốt mất exit code thật (1) của app.** Đừng tin exit code khi PID 1 là một script — đọc log ([bài 08 §3.2](../08-container-troubleshooting.md#32-exit-code--ngôn-ngữ-chung-của-linux-và-docker)). Bạn sẽ gặp lại chính `start.sh` này ở ticket #5004.

**Bước 2 — log:**

```bash
docker compose logs api --tail 20
docker compose logs nginx --tail 20
```

```text
api-1  | [start.sh] starting api (pid of this shell: 1)
api-1  | [api] connecting to database taskhub@localhost:5432/taskhub ...
api-1  | [api] FATAL cannot connect to database at localhost:5432: connection failed: ... Connection refused
api-1  | [start.sh] api exited with code 1
```

- api: kết nối tới `localhost:5432` bị **refused**. Trong container `api`, `localhost` là chính nó — không có PostgreSQL nào nghe ở đó. Dòng cuối cho thấy app thoát với mã **1** — nhưng `docker compose ps` lại ghi `Exited (0)` (xem bẫy ở trên).
- nginx vẫn `Up` vì nó khởi động **trong lúc** container api còn đang chạy (api cần vài giây mới thất bại), nên lúc đó tên `api` vẫn phân giải được. Nếu sau này bạn khởi động lại riêng nginx khi api đã dừng, nginx sẽ chết với `[emerg] host not found in upstream "api"` — đó là **hệ quả** của lỗi api, không phải lỗi riêng của nginx. Nhận ra quan hệ nhân quả này giúp bạn không sửa nhầm nginx.

**Bước 3 — cấu hình thật:**

```bash
docker compose config | grep -A6 'api:' | grep DB_HOST
```

```text
      DB_HOST: localhost
```

**Sửa** trong `compose.yaml`: `DB_HOST: postgres` — tên service. Áp dụng: `docker compose up -d`.

### Lỗi 2: Không chờ PostgreSQL sẵn sàng

Sau khi sửa lỗi 1, api lên được — **nhưng không phải lúc nào cũng lên**. Ticket yêu cầu thử `down`/`up` nhiều lần:

```bash
for i in 1 2 3; do docker compose down; docker compose up -d; sleep 8; docker compose ps -a --format '{{.Service}} {{.Status}}'; echo ---; done
```

api vẫn `Exited` — có thể **lần nào cũng chết**, chứ không chỉ thỉnh thoảng. Lý do: lỗi 4 (ticket #5003) khiến **mỗi** lần `up` postgres nhận một volume rỗng mới và phải khởi tạo lại database từ đầu (mất vài giây), nên api gần như luôn đến sớm hơn. Sau khi sửa lỗi 4, database không phải khởi tạo lại nữa và triệu chứng trở thành "lúc được lúc không" mà đồng nghiệp nhắc tới. Cả hai đều là dấu hiệu kinh điển của **race condition** (tranh chấp thứ tự).

**Bước 2 — log có thời gian:**

```bash
docker compose logs -t postgres api | sort -k3 | head -30
```

```text
api-1      | 2026-...T07:14:07.92Z [api] FATAL cannot connect to database at postgres:5432: ... Connection refused
postgres-1 | 2026-...T07:14:08.61Z ... database system is ready to accept connections
postgres-1 | 2026-...T07:14:09.06Z ... database system is ready to accept connections
```

api thử kết nối **trước** khi postgres sẵn sàng, và app được viết để thoát ngay khi thất bại. (Thông báo có thể là `Connection refused` — khi postgres đang khởi tạo, server tạm chỉ nghe qua Unix socket — hoặc `the database system is starting up`. Hai dòng `ready to accept connections` là của server tạm trong lúc khởi tạo và của server thật.)

**Bước 3 — cấu hình:**

```bash
docker compose config --format json | python3 -c 'import json,sys; c=json.load(sys.stdin)["services"]; print(c["api"]["depends_on"]); print("postgres healthcheck:", "healthcheck" in c["postgres"])'
```

```text
{'postgres': {'condition': 'service_started', 'required': True}}
postgres healthcheck: False
```

`depends_on` dạng ngắn = `condition: service_started`: Compose chỉ chờ container postgres **được khởi chạy**, không chờ PostgreSQL bên trong **nhận kết nối**. Và postgres không có healthcheck nên Compose cũng không có cách nào biết khi nào nó sẵn sàng.

**Sửa:**

```yaml
  api:
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s
```

- `pg_isready` có sẵn trong image `postgres` — không cần cài thêm.
- `$$` trong Compose = ký tự `$` thật: Compose không thay biến lúc đọc file, để **shell trong container** thay `$POSTGRES_USER` bằng biến môi trường của container.

Kiểm chứng: lặp lại vòng `down`/`up` 3 lần — api luôn lên, `docker compose up -d` hiện `Waiting` cho postgres rồi `Healthy`.

> Ghi chú: app tự thử kết nối lại (retry) cũng là cách tốt và nên có ở app thật (Spring Boot + HikariCP có cơ chế chờ kết nối). Nhưng luật chơi không cho sửa app — và **cả hai** lớp (hạ tầng chờ + app retry) đều nên có.

---

## Ticket #5002 — Welcome to nginx

### Lỗi 3: File cấu hình không phải là file nginx dùng

**Bước 2 — log khởi động của nginx:**

```bash
docker compose logs nginx | grep -E 'warn|emerg'
```

```text
nginx-1 | ... [warn] 1#1: conflicting server name "localhost" on 0.0.0.0:80, ignored
```

Đây là manh mối chính: có **hai** server block cùng `server_name localhost` trên port 80, nginx bỏ qua cái sau.

**Bước 4 — vào bên trong:**

```bash
docker compose exec nginx ls -l /etc/nginx/conf.d/
docker compose exec nginx nginx -T 2>/dev/null | grep -E '^# configuration file|server_name|location'
```

```text
-rw-r--r--    1 root     root     1093 ... default.conf
-rw-r--r--    1 root     root      612 ... taskhub.conf

# configuration file /etc/nginx/conf.d/default.conf:
    server_name  localhost;
    location / {
# configuration file /etc/nginx/conf.d/taskhub.conf:
    server_name localhost;
    location = /nginx-health {
    location /api/ {
```

`compose.yaml` mount `./nginx/default.conf` vào đường dẫn **`/etc/nginx/conf.d/taskhub.conf`** — tức là **thêm** một file, không **thay** file `default.conf` có sẵn trong image. nginx nạp `conf.d/*.conf` theo thứ tự tên: `default.conf` trước → server block mặc định thắng → trả "Welcome to nginx!" cho `/` và 404 cho `/api/...`.

**Sửa** — mount đè đúng file mặc định:

```yaml
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
```

Áp dụng bằng `docker compose up -d` (đổi mount → phải tạo lại container; `nginx -s reload` không đủ). Kiểm chứng: `curl -s http://localhost:18000/api/health` → `{"status": "UP", "db": "ok"}`, log nginx không còn `[warn]`.

Cách khác cũng đúng: giữ tên `taskhub.conf` và đặt `listen 80 default_server;`, hoặc xóa `default.conf` trong một image nginx tự build. Mount đè là cách đơn giản và rõ ràng nhất.

---

## Ticket #5003 — Mất dữ liệu sau bảo trì

### Lỗi 4: Dữ liệu nằm trong anonymous volume

**Tái hiện:**

```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"truoc bao tri"}' http://localhost:18000/api/tasks
docker compose down && docker compose up -d && sleep 10
curl -s http://localhost:18000/api/tasks
```

```text
{"id": 1, "title": "truoc bao tri"}
[]
```

**Bước 3 — mount thật của postgres:**

```bash
docker inspect -f '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}}{{println}}{{end}}' "$(docker compose ps -q postgres)"
```

```text
volume bf04_pgdata -> /var/lib/postgresql
volume 3f9c2a7e1b...(64 ký tự hex) -> /var/lib/postgresql/data
```

Có **hai** mount. Cái thứ hai không có tên dễ đọc — đó là **anonymous volume** (volume ẩn danh). Nó từ đâu ra?

```bash
docker image inspect postgres:17 -f '{{json .Config.Volumes}}'
docker image inspect postgres:17 -f '{{range .Config.Env}}{{println .}}{{end}}' | grep PGDATA
```

```text
{"/var/lib/postgresql/data":{}}
PGDATA=/var/lib/postgresql/data
```

- Image `postgres:17` khai báo `VOLUME /var/lib/postgresql/data` và đặt `PGDATA` ở đó.
- `compose.yaml` gắn named volume `pgdata` vào thư mục **cha** `/var/lib/postgresql` (cách viết dành cho PostgreSQL 18 trở lên, nơi `PGDATA` đổi thành `/var/lib/postgresql/18/docker`).
- Vì không có mount nào ở đúng `/var/lib/postgresql/data`, Docker tạo một anonymous volume cho đường dẫn đó, **đè lên** bên trong named volume. Dữ liệu thật đi vào anonymous volume.
- `docker compose down` xóa container; `up` tạo container mới với **anonymous volume mới, rỗng** → PostgreSQL khởi tạo database trống. Volume cũ vẫn còn đâu đó trong `docker volume ls`, mồ côi.

**Sửa:**

```yaml
    volumes:
      - pgdata:/var/lib/postgresql/data
```

Có thể gặp lỗi tiếp theo khi áp dụng:

```text
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
```

Named volume `pgdata` cũ đang chứa thư mục `data/` rỗng (mount point được tạo từ cách mount cũ), nên không còn "trống" để khởi tạo database. Vì dữ liệu thật đã nằm ở anonymous volume (đã mất theo thiết kế sai), cách xử lý trong lab là xóa volume cũ và khởi tạo lại — ghi rõ vào nhật ký:

```bash
docker compose down -v
docker compose up -d
docker volume ls          # dọn các anonymous volume mồ côi nếu muốn: docker volume rm <tên>
```

**Kiểm chứng** — đúng phép thử của ticket:

```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"sau khi sua"}' http://localhost:18000/api/tasks
docker compose down && docker compose up -d && sleep 10
curl -s http://localhost:18000/api/tasks      # vẫn còn "sau khi sua"
```

> Bài học: copy cấu hình volume từ hướng dẫn trên mạng phải kiểm tra **phiên bản image** của hướng dẫn đó. Luôn đọc trang Docker Hub của đúng tag bạn dùng.

---

## Ticket #5004 — Dừng mất 10 giây

### Lỗi 5: `sh` là PID 1 và không chuyển SIGTERM

**Bước 1 — đo và xem exit code:**

```bash
time docker compose stop api
docker compose ps -a --format '{{.Service}} {{.Status}}' | grep api
docker compose logs api --tail 5
```

```text
real    0m10.4s
api Exited (137) 3 seconds ago
api-1  | [api] listening on 0.0.0.0:8000 (pid=7, uid=0)
```

- Đúng ~10 giây = thời gian chờ mặc định của `docker stop` trước khi gửi SIGKILL.
- Exit 137 = 128 + 9 → bị **SIGKILL**, không phải tự thoát.
- Log ghi `pid=7` — app **không phải** PID 1. Dòng `received SIGTERM` không xuất hiện, dòng `[start.sh] api exited` cũng không.

**Bước 4 — PID 1 là ai:**

```bash
docker compose up -d
docker compose exec api cat /proc/1/cmdline | tr '\0' ' '; echo
```

```text
/bin/sh /app/start.sh
```

Cơ chế ([Linux bài 04](../../01-LINUX/04-processes-systemd.md)):

1. `docker stop` gửi SIGTERM cho **PID 1** = `sh`.
2. Kernel không áp dụng hành động mặc định "kết thúc" cho PID 1 của một namespace khi process đó không tự cài bộ xử lý tín hiệu — `sh` bỏ qua SIGTERM. `sh` cũng không chuyển tiếp tín hiệu cho process con `python`.
3. Hết 10 giây, Docker gửi SIGKILL → mọi thứ chết ngay, app không kịp đóng kết nối DB.

**Sửa** `api/start.sh`:

```sh
#!/bin/sh
echo "[start.sh] starting api (pid of this shell: $$)"
exec python /app/app.py
```

`exec` **thay thế** process `sh` bằng `python` (cùng PID 1) thay vì tạo process con. Dòng `echo` sau đó bị bỏ vì không bao giờ chạy tới. Cách khác cũng đúng: `CMD ["python", "/app/app.py"]` trong Dockerfile và bỏ `start.sh`.

Áp dụng: `docker compose up -d --build`. Kiểm chứng:

```bash
time docker compose stop api        # < 2 giây
docker compose logs api --tail 3    # có "received SIGTERM, shutting down gracefully" và "bye"
docker compose ps -a | grep api     # Exited (0)
```

App này tự cài bộ xử lý SIGTERM nên khi là PID 1 nó nhận được tín hiệu. Với app không làm vậy, dùng `init: true` trong Compose (tương đương `docker run --init`) để có một init process nhỏ làm PID 1 chuyển tiếp tín hiệu.

> Liên hệ taskhub thật: Dockerfile của taskhub dùng dạng exec `ENTRYPOINT ["java", ...]` — Java là PID 1 và Spring Boot xử lý SIGTERM để tắt nhẹ nhàng (graceful shutdown). Đừng bao giờ bọc nó trong một script không có `exec`.

---

## Ticket #5005 — Rà soát bảo mật (3 lỗi)

### Lỗi 6: Database lộ ra mọi địa chỉ của máy

```bash
docker compose ps --format '{{.Service}}\t{{.Ports}}'
```

```text
postgres  0.0.0.0:5432->5432/tcp
```

`0.0.0.0:5432` = nghe trên **mọi** địa chỉ của host ([Network bài 05](../../02-NETWORKING/05-tcp-udp-ports-firewall.md)). Trên một server thật có IP public, bất kỳ ai cũng thử đăng nhập được vào database. Mà api gọi postgres **qua network nội bộ của Docker** — không cần publish gì cả.

**Sửa:** xóa khối `ports` của postgres. Nếu thật sự cần dùng công cụ trên host (DBeaver, psql) để xem dữ liệu: `"127.0.0.1:5432:5432"` — chỉ máy local truy cập được.

### Lỗi 7a: Mật khẩu hard-code trong `compose.yaml`

`compose.yaml` được commit lên Git → mật khẩu `taskhub123` nằm trong lịch sử Git vĩnh viễn.

**Sửa:**

`.env` (không commit):

```dotenv
POSTGRES_DB=taskhub
POSTGRES_USER=taskhub
POSTGRES_PASSWORD=doi-mat-khau-moi-dai-hon
```

`.env.example` (commit — cho người khác biết cần đặt biến gì):

```dotenv
POSTGRES_DB=taskhub
POSTGRES_USER=taskhub
POSTGRES_PASSWORD=change-me
```

`.gitignore` thêm dòng `.env`.

Trong `compose.yaml`, tham chiếu biến: `${POSTGRES_PASSWORD:?...}` — cú pháp `:?` làm Compose **báo lỗi và dừng** nếu biến chưa được đặt, thay vì âm thầm dùng chuỗi rỗng.

⚠️ Bẫy: PostgreSQL chỉ dùng `POSTGRES_PASSWORD` **khi khởi tạo volume lần đầu**. Đổi mật khẩu trong `.env` khi volume đã có dữ liệu → postgres vẫn giữ mật khẩu cũ, api báo `password authentication failed`. Trong lab: `docker compose down -v` để khởi tạo lại. Trên hệ thống thật: đổi mật khẩu bằng lệnh SQL `ALTER USER`, rồi mới cập nhật `.env`. Và vì `taskhub123` đã nằm trong Git, mật khẩu đó phải coi như **đã lộ** — phải đổi, không chỉ xóa khỏi file.

### Lỗi 7b: Container api chạy root

```bash
docker compose exec api id
```

```text
uid=0(root) gid=0(root) groups=0(root)
```

Log khởi động cũng ghi `uid=0`. `api/Dockerfile` không có `USER`.

**Sửa** `api/Dockerfile` — tạo user hệ thống, chuyển sang user đó **sau** các bước cần root (`pip install`, `chmod`):

```dockerfile
RUN groupadd --system app && useradd --system --gid app --no-create-home app
USER app
```

File `app.py`, `start.sh` vẫn thuộc root (chỉ đọc/thực thi được) — app không sửa được chính code của nó.

---

## Các file sau khi sửa

`compose.yaml`:

```yaml
name: bf04

services:
  nginx:
    image: nginx:1.30-alpine
    ports:
      - "18000:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api

  api:
    build: ./api
    environment:
      DB_HOST: postgres
      DB_PORT: "5432"
      DB_NAME: ${POSTGRES_DB}
      DB_USER: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD:?Chưa đặt POSTGRES_PASSWORD trong .env}
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:17
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?Chưa đặt POSTGRES_PASSWORD trong .env}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

`api/Dockerfile`:

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN groupadd --system app && useradd --system --gid app --no-create-home app

COPY app.py start.sh ./
RUN chmod +x start.sh

USER app
EXPOSE 8000
CMD ["/app/start.sh"]
```

`api/start.sh`:

```sh
#!/bin/sh
echo "[start.sh] starting api (pid of this shell: $$)"
exec python /app/app.py
```

Kết quả `./verify.sh`: `8/8`.

---

## Bài học mang về taskhub

| Lỗi trong lab | Kiểm tra trong taskhub thật |
|---|---|
| `localhost` trong container | `SPRING_DATASOURCE_URL` dùng `postgres:5432` |
| Không chờ DB healthy | postgres có healthcheck, taskhub có `depends_on: condition: service_healthy` |
| Mount config nginx sai | `docker compose exec nginx nginx -T` sau mỗi lần đổi cấu hình |
| Volume sai đường dẫn | Volume postgres:17 ở `/var/lib/postgresql/data`; làm phép thử `down`/`up` |
| PID 1 không nhận SIGTERM | `ENTRYPOINT` dạng exec; đo `time docker compose stop taskhub` |
| Port DB publish ra ngoài | Chỉ nginx publish port |
| Secret trong file commit | `.env` trong `.gitignore`, có `.env.example` |
| Container root | `USER taskhub` trong Dockerfile |
