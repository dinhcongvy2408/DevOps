# Lời giải — Bài 05: Docker Compose

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa.

Quay lại bài: [05-docker-compose.md](../05-docker-compose.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Compose giải quyết vấn đề gì? Có phải orchestrator không?**
Compose mô tả cả hệ thống nhiều container trong **một file khai báo** nằm trong Git: không phải nhớ thứ tự lệnh, tự tạo network/volume, chạy lại `up -d` là tự đồng bộ trạng thái, có `depends_on` + healthcheck để khởi động đúng thứ tự, ai cũng dựng được môi trường giống nhau bằng một lệnh. Compose **không** phải orchestrator: nó chỉ quản lý container trên **một** Docker Engine, không tự chuyển container sang máy khác khi máy chết, không tự scale theo tải. Kubernetes/ECS làm những việc đó.

**2. Project, service, container? Tên volume thật?**
Project = toàn bộ những gì một file Compose mô tả, có một tên. Service = mô tả một loại container (image, biến, port…). Container = instance đang chạy của service (một service có thể có nhiều container khi scale). Volume `pgdata` trong project `taskhub` có tên thật `taskhub_pgdata` (kiểm tra bằng `docker volume ls`).

**3. Vì sao không viết `version: "3.8"`?**
Theo tài liệu Compose hiện tại, `version` chỉ còn để tương thích ngược, **không có tác dụng** gì ngoài việc in cảnh báo "obsolete". Compose luôn dùng Compose Specification mới nhất. Viết nó chỉ gây nhiễu và làm người đọc tưởng có ý nghĩa.

**4. `.env` và `env_file`?**
`.env` ở thư mục project dùng cho **interpolation**: Compose thay `${VAR}` trong `compose.yaml` bằng giá trị trong file **trước khi** tạo container. Nó **không** tự vào container. `env_file:` là thuộc tính của service: mọi biến trong file đó được đưa **vào môi trường của container**. Muốn biến trong `.env` vào container phải tham chiếu nó: `environment: { DB_PASS: ${DB_PASS} }`.

**5. `${DB_PASSWORD:?missing}` và `${WEB_PORT:-8000}`?**
`:?` — nếu biến chưa đặt hoặc rỗng, Compose **dừng với lỗi** in "missing". Dùng cho giá trị **bắt buộc**, nhất là secret (không để database chạy với mật khẩu rỗng). `:-` — nếu chưa đặt/rỗng thì dùng **giá trị mặc định** `8000`. Dùng cho giá trị có mặc định hợp lý (port, log level).

**6. Vì sao `depends_on: [postgres]` không đủ?**
Cú pháp ngắn chỉ đảm bảo **container** `postgres` được khởi động trước, không chờ PostgreSQL **sẵn sàng nhận kết nối**. PostgreSQL cần vài giây (lần đầu lâu hơn vì khởi tạo database) → Spring Boot kết nối sớm, nhận `Connection refused`, crash. Sửa: thêm `healthcheck` cho `postgres` (`pg_isready`) và dùng `depends_on: postgres: condition: service_healthy` ở `taskhub`.

**7. `Up (unhealthy)` — Docker có tự restart không?**
**Không.** Healthcheck chỉ cập nhật trạng thái. Restart policy chỉ phản ứng khi **process chính thoát**. (Kubernetes liveness probe thì có restart.)

**8. `restart` vs `up -d` sau khi sửa biến?**
`restart` dừng rồi chạy lại **container cũ với cấu hình cũ** → biến mới không có hiệu lực. `up -d` so sánh cấu hình → phát hiện thay đổi → **tạo lại** container với biến mới.

**9. `down` vs `down -v`?**
`down` xóa container và network, **giữ** named volume. `down -v` xóa thêm named volume → **mất dữ liệu database**. `down -v` nguy hiểm.

**10. Vì sao chỉ publish nginx?**
Nguyên tắc **giảm bề mặt tấn công** và một cửa vào duy nhất: mọi request đi qua reverse proxy (nơi làm TLS, giới hạn request, ghi log). `taskhub` và `postgres` không cần nhận kết nối từ ngoài — container trong cùng network vẫn gọi nhau được mà không cần `ports`. Database lộ ra ngoài là rủi ro bảo mật lớn (dò mật khẩu, khai thác lỗ hổng).

**11. App trong container kết nối `localhost:5432` sai ở đâu?**
Mỗi container có network namespace riêng; `localhost` trong container `taskhub` là **chính container đó**, nơi không có PostgreSQL. Phải dùng tên service `postgres:5432` để DNS nội bộ của Docker phân giải ra IP của container `postgres`.

**12. `unless-stopped` vs `always`?**
Cả hai đều restart khi process thoát và chạy lại khi Docker Engine khởi động. Khác biệt: container bạn **đã dừng thủ công** — với `always`, nó **chạy lại** khi Engine khởi động lại (ví dụ reboot máy); với `unless-stopped`, nó **giữ trạng thái dừng**.

**13. Vì sao đặt `name:` cố định?**
Không có `name:`, tên project = tên thư mục. Đổi tên/di chuyển thư mục → project mới → network và **volume mới, rỗng** → tưởng mất dữ liệu. `name: taskhub` giữ tên ổn định ở mọi nơi (laptop, EC2).

**14. Lệnh đầu tiên khi nghi `compose.yaml` có vấn đề?**
`docker compose config`. Nó cho thấy Compose **thực sự hiểu** file thế nào sau khi gộp file override và thay biến, báo lỗi YAML/biến bắt buộc ngay mà không tạo gì. Phần lớn lỗi "sao không chạy như tôi nghĩ" lộ ra ở đây.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Dịch ngược

```yaml
services:
  cache:
    image: redis:7-alpine
    volumes:
      - redisdata:/data
    restart: unless-stopped
    networks: [shop]
  api:
    image: python:3.12-slim
    command: ["python", "-m", "http.server", "8000"]
    ports:
      - "127.0.0.1:9000:8000"
    environment:
      CACHE_HOST: cache
      CACHE_PORT: "6379"
    networks: [shop]

volumes:
  redisdata:

networks:
  shop:
```

Ghi chú:

- `--name cache` không cần dịch: tên **service** `cache` chính là tên DNS mà `api` dùng. (Có thể thêm `container_name: cache` nhưng không nên — nó ngăn scale và dễ trùng tên với project khác.)
- Có thể bỏ khai báo `networks` và dùng network mặc định — kết quả tương đương. Viết ra để khớp chính xác với lệnh gốc.
- `CACHE_PORT: "6379"` đặt trong nháy để chắc chắn là chuỗi (biến môi trường luôn là chuỗi).
- Tên volume thật sẽ là `<project>_redisdata`, không phải `redisdata` như khi tạo tay. Muốn dùng volume đã tạo bằng tay: `volumes: { redisdata: { external: true } }` (🟨).

### Bài 2 — Bắt lỗi file

| # | Lỗi | Sửa |
|---|---|---|
| 1 | `version: "3.8"` — lỗi thời | Xóa |
| 2 | `postgres:latest` — không cố định phiên bản; lần pull sau có thể lên bản major mới (ví dụ 18 đổi thư mục dữ liệu) | `postgres:17` |
| 3 | Mật khẩu `admin123` viết thẳng trong file (sẽ bị commit) | `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?...}` + `.env` không commit |
| 4 | `ports: - 5432:5432` publish database ra mọi interface; viết không nháy | Bỏ hẳn; nếu cần debug: `"127.0.0.1:5432:5432"` trong override |
| 5 | `jdbc:postgresql://localhost:5432/...` — `localhost` trong container là chính backend | Host là tên service `db` |
| 6 | `depends_on: - database` — service tên `database` không tồn tại (tên là `db`); và chỉ là thứ tự khởi động | `depends_on: db: condition: service_healthy` + healthcheck cho `db` |
| 7 | Dòng `ports:` của `backend` bắt đầu bằng **Tab** → lỗi YAML | Thay bằng dấu cách, cùng mức thụt lề với `depends_on` |
| 8 (thêm) | Thiếu `volumes` cho `db` → dữ liệu mất khi xóa container | `pgdata:/var/lib/postgresql/data` + khai báo volume |
| 9 (thêm) | `backend` publish 8080 trực tiếp, không qua reverse proxy (tùy thiết kế) | Chấp nhận được cho dev; production nên qua nginx |

Bản sửa:

```yaml
services:
  db:
    image: postgres:17
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "app", "-d", "app"]
      interval: 5s
      retries: 10
  backend:
    build: .
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/app
      SPRING_DATASOURCE_USERNAME: app
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "8080:8080"

volumes:
  pgdata:
```

### Bài 3 — Biến bắt buộc

```yaml
  app:
    environment:
      APP_MODE: "lab"
      API_KEY: ${API_KEY:?API_KEY is required - add it to .env}
```

`.env`:

```text
WEB_PORT=8000
API_KEY=demo-key-123
```

Xóa dòng `API_KEY` khỏi `.env`:

```text
$ docker compose config
error while interpolating services.app.environment.API_KEY: required variable API_KEY is missing a value: API_KEY is required - add it to .env
```

(Chữ chính xác có thể khác theo phiên bản Compose; ý chính: Compose dừng trước khi tạo container.) Kiểm tra biến vào container: `docker compose exec app sh -c 'echo $API_KEY'`.

### Bài 4 — Override cho dev

`compose.override.yaml`:

```yaml
services:
  app:
    ports:
      - "127.0.0.1:8001:8000"
    environment:
      APP_MODE: "dev"
```

```bash
docker compose config | grep -A4 'ports:'          # thấy cả 8001 (app) và 8000 (web)
docker compose config | grep APP_MODE              # APP_MODE: dev
docker compose up -d
curl -s http://127.0.0.1:8001 | head -1            # truy cập thẳng app, không qua nginx

docker compose -f compose.yaml config | grep 8001 || echo "không có 8001 khi chỉ dùng compose.yaml"
docker compose -f compose.yaml up -d               # container app bị tạo lại, không còn port 8001
```

Giải thích: khi có `compose.override.yaml` cạnh `compose.yaml` và **không** dùng `-f`, Compose tự gộp hai file. Danh sách `ports` được **nối thêm**, còn giá trị đơn như `APP_MODE` bị **ghi đè**. Khi chỉ định `-f compose.yaml`, file override không được đọc.

### Bài 5 — Job khởi tạo

```yaml
services:
  init:
    image: busybox:1.36
    command: ["sh", "-c", "echo seeded-at-$$(date +%s) > /data/seed.txt"]
    volumes:
      - appdata:/data
    restart: "no"                      # job chạy một lần, không restart

  app:
    # ...giữ nguyên...
    depends_on:
      init:
        condition: service_completed_successfully
```

Lưu ý `$$(date +%s)`: `$$` để Compose **không** coi `$(` là interpolation; shell **trong container** mới thực thi `$(date +%s)`.

Kiểm tra:

```bash
docker compose up -d
docker compose ps -a                   # init: Exited (0)
docker compose exec app cat /data/seed.txt
```

Nếu `init` thoát với mã 1 (thử `command: ["sh", "-c", "exit 1"]`): `docker compose up` báo lỗi kiểu `service "init" didn't complete successfully: exit 1` và **không tạo** `app` (kéo theo `web` cũng không được tạo vì phụ thuộc `app`). Đây chính là hành vi mong muốn cho job migration: migration lỗi thì không khởi động app trên schema sai.

### Bài 6 — Điều tra thứ tự ưu tiên

```bash
export WEB_PORT=9999
docker compose config | grep published      # published: "9999"
docker compose config --environment | grep WEB_PORT
unset WEB_PORT
docker compose config | grep published      # published: "8000"
```

Biến trong **shell** có độ ưu tiên cao hơn file `.env` khi interpolation, nên `.env` bị bỏ qua mà không có cảnh báo nào.

Mục nhật ký mẫu:

```markdown
## 2026-12-12 — Sửa .env nhưng port của nginx không đổi
- Triệu chứng: đổi WEB_PORT=8080 trong .env, `docker compose up -d`, nginx vẫn ở 9999.
- Giả thuyết: Compose không đọc .env / đọc sai file.
- Kiểm tra: `docker compose config --environment | grep WEB_PORT` → 9999; `env | grep WEB_PORT` → WEB_PORT=9999.
- Nguyên nhân gốc: shell còn biến WEB_PORT do `export` từ hôm trước; biến shell ưu tiên hơn .env.
- Cách sửa: `unset WEB_PORT`, chạy lại `docker compose up -d`.
- Phòng ngừa: không export biến trùng tên với biến của project; luôn kiểm tra bằng `docker compose config` trước khi `up`.
```
