# 05. Docker Compose

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [03. Dockerfile & multi-stage build](03-dockerfile-multistage.md), [04. Volumes, networks & biến môi trường](04-volumes-networks-env.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (WSL Integration bật), `[Container]` bên trong container

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

- Giải thích được **Docker Compose** giải quyết vấn đề gì so với một chuỗi lệnh `docker run` dài.
- Đọc và tự viết `compose.yaml` gồm nhiều service với `build`, `ports`, `environment`, `env_file`, `volumes`, `networks`, `depends_on`, `healthcheck`, `restart`.
- Phân biệt rõ **file `.env` dùng để thay biến trong `compose.yaml`** (interpolation) và **thuộc tính `env_file` đưa biến vào container** — hai thứ người mới hay nhầm nhất.
- Hiểu vì sao `depends_on` **không** đảm bảo service phụ thuộc đã **sẵn sàng**, và dùng `condition: service_healthy` để khắc phục.
- Dùng thành thạo vòng đời `docker compose up / ps / logs / exec / down`, và dùng `docker compose config` làm công cụ debug đầu tiên.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Ở [bài 04](04-volumes-networks-env.md) bạn đã dựng app + database bằng tay: tạo network, tạo volume, rồi gõ hai lệnh `docker run` dài với hàng chục tham số. Thử tưởng tượng:

| Tình huống thật | Không có Compose | Có Compose |
|---|---|---|
| Đồng nghiệp mới cần chạy dự án trên laptop | Gửi họ một file ghi chú 15 lệnh, hy vọng họ gõ đúng thứ tự | `git clone` → `docker compose up -d` |
| Đổi port của Nginx | Tìm và sửa trong mọi script, nhớ xóa container cũ | Sửa một dòng trong `compose.yaml`, chạy lại `up -d` |
| App khởi động trước database → crash | Thêm `sleep 30` vào script và cầu nguyện | `depends_on` + `condition: service_healthy` |
| Triển khai lên một EC2 duy nhất (dự án v2, tuần 12) | Viết script Bash dài, khó bảo trì | Copy `compose.yaml` + `.env` lên server, chạy `docker compose up -d` |
| Review thay đổi hạ tầng của đồng nghiệp | Không có gì để review | `compose.yaml` nằm trong Git → review qua Pull Request |

`compose.yaml` là **hạ tầng dạng code đầu tiên** bạn viết trong khóa học. Tư duy "mô tả trạng thái mong muốn trong một file, để công cụ tự làm cho đúng" sẽ gặp lại ở Terraform (Module 07) và Kubernetes manifest (Module 09).

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Compose là gì — và không phải là gì

**Docker Compose** là công cụ đọc một file YAML mô tả **nhiều container chạy cùng nhau** (gọi là một **project**), rồi gọi Docker Engine để tạo đúng những gì được mô tả: network, volume, container.

- Compose **không** phải engine riêng. Nó chỉ là một **client** gọi cùng API mà lệnh `docker run` gọi. Mọi container Compose tạo ra đều thấy được bằng `docker ps`.
- Compose **không** phải hệ thống điều phối nhiều máy (orchestrator) như Kubernetes. Nó quản lý container trên **một** Docker Engine. Với một server EC2 nhỏ, vậy là đủ.
- Lệnh hiện đại là `docker compose` (có dấu cách, là plugin của Docker CLI). Lệnh cũ `docker-compose` (có gạch nối, viết bằng Python) đã ngừng phát triển — gặp trong tutorial cũ thì hiểu là cùng ý.

### 3.2. Ba khái niệm cốt lõi

| Khái niệm | Tiếng Việt | Là gì | Tương ứng khi làm tay ở bài 04 |
|---|---|---|---|
| **Project** | Dự án | Tập hợp mọi thứ trong một file Compose, có một **tên project** | — |
| **Service** | Dịch vụ | Mô tả **một loại container**: image nào, biến gì, port nào | Một lệnh `docker run ...` |
| **Container** | Container | Instance thật đang chạy của một service | Container tạo ra từ `docker run` |

Ngoài ra Compose tự quản lý **network** và **volume** của project. Tên thật của chúng có tiền tố là tên project, ví dụ project `taskhub` có network `taskhub_default` và volume `taskhub_pgdata`.

### 3.3. YAML đủ dùng

`compose.yaml` viết bằng **YAML** — định dạng dữ liệu dựa vào **thụt lề**. Ba quy tắc tránh 90% lỗi:

```yaml
services:              # key: value — "services" chứa một map con
  web:                 # thụt lề bằng DẤU CÁCH (thường 2), KHÔNG dùng Tab
    image: nginx:1.30-alpine
    ports:             # danh sách: mỗi phần tử bắt đầu bằng "- "
      - "8000:80"      # chuỗi có dấu ":" nên đặt trong nháy kép
    environment:
      DEBUG: "false"   # true/false/yes/no không nháy sẽ thành boolean — đặt nháy nếu muốn là chuỗi
```

> ⚠️ YAML **cấm Tab** để thụt lề. VS Code mặc định thay Tab bằng dấu cách với file `.yaml`, nhưng nếu copy từ nơi khác, kiểm tra bằng `cat -A compose.yaml | grep -P '\t'` (Tab hiện thành `^I`).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Từ chuỗi `docker run` sang `compose.yaml`

Hai lệnh bạn đã gõ ở bài 04 (rút gọn):

```bash
docker network create appnet
docker volume create pgdata
docker run -d --name db --network appnet \
  -e POSTGRES_PASSWORD=secret -v pgdata:/var/lib/postgresql/data postgres:17
docker run -d --name web --network appnet -p 8000:80 nginx:1.30-alpine
```

Viết lại bằng Compose:

```yaml
services:
  db:
    image: postgres:17
    environment:
      POSTGRES_PASSWORD: secret        # (bài này sẽ sửa: không viết mật khẩu thẳng vào file)
    volumes:
      - pgdata:/var/lib/postgresql/data
  web:
    image: nginx:1.30-alpine
    ports:
      - "8000:80"

volumes:
  pgdata:                              # khai báo named volume ở cấp cao nhất
```

Để ý những gì **biến mất**: không cần `docker network create` (Compose tự tạo network mặc định cho project và nối mọi service vào), không cần `--name` (Compose tự đặt tên container), không cần nhớ thứ tự tạo.

### 4.2. 🟥 Cấu trúc cấp cao nhất của file

| Key cấp cao nhất | Bắt buộc? | Chứa gì |
|---|---|---|
| `services` | **Có** | Các service |
| `volumes` | Khi dùng named volume | Khai báo named volume |
| `networks` | Khi cần network tự đặt | Khai báo network |
| `name` | Không | Tên project (nếu không có, lấy tên thư mục) |
| `version` | **Không — đã lỗi thời** | Tutorial cũ hay viết `version: "3.8"`. Tài liệu Compose hiện nay ghi rõ trường này chỉ để tương thích ngược, **không có tác dụng** ngoài việc in cảnh báo "obsolete". Đừng viết |

Tên file chuẩn hiện nay là `compose.yaml` (Compose vẫn đọc được `docker-compose.yml` cũ).

### 4.3. 🟥 `image` và `build`

```yaml
services:
  taskhub:
    build:
      context: .                     # thư mục gửi cho Docker làm build context (nơi COPY lấy file)
      dockerfile: docker/Dockerfile  # đường dẫn Dockerfile, TÍNH TỪ context
    image: taskhub:local             # tên + tag gán cho image vừa build
```

- Chỉ có `image` → Compose **kéo** image có sẵn từ registry.
- Có `build` → Compose **build** image từ Dockerfile. Nếu có thêm `image`, image build xong được gắn tên đó (tiện khi muốn tag và push sau này — [bài 06](06-registry.md)).
- `context` và `.dockerignore` hoạt động đúng như `docker build` ở [bài 03](03-dockerfile-multistage.md).

> Compose **không tự build lại** khi bạn sửa code. `docker compose up -d` thấy image `taskhub:local` đã tồn tại thì dùng luôn. Muốn build lại: `docker compose up -d --build` hoặc `docker compose build`.

### 4.4. 🟥 `ports` — publish ra máy host

```yaml
    ports:
      - "8000:80"              # HOST:CONTAINER — mọi interface của host
      - "127.0.0.1:5432:5432"  # chỉ loopback của host — máy khác không vào được
```

Đây chính là DNAT bạn đã học ở [Networking bài 04](../02-NETWORKING/04-routing-nat-switching.md) và bind address ở [Networking bài 05](../02-NETWORKING/05-tcp-udp-ports-firewall.md).

**Nguyên tắc:** chỉ publish service **cần được truy cập từ ngoài** (reverse proxy). Database và app phía sau **không publish** — các container trong cùng network vẫn nói chuyện với nhau qua port nội bộ mà không cần `ports`.

`expose:` chỉ là ghi chú tài liệu (không publish gì ra host) — container cùng network vốn đã truy cập được mọi port của nhau.

### 4.5. 🟥 Biến môi trường: `environment`, `env_file`, `.env` và interpolation

Đây là phần **người mới nhầm nhiều nhất**, vì có hai cơ chế khác nhau dùng chữ "env":

| Cơ chế | Tác động lên | Ai đọc | Ví dụ |
|---|---|---|---|
| **Interpolation** (thay biến) + file **`.env`** ở thư mục project | **Chính file `compose.yaml`** — Compose thay `${VAR}` bằng giá trị **trước khi** tạo container | Docker Compose CLI | `ports: ["${NGINX_HOST_PORT:-8000}:80"]` |
| **`environment:`** | **Biến môi trường bên trong container** | Process trong container (app Spring Boot) | `SPRING_DATASOURCE_URL: jdbc:...` |
| **`env_file:`** | **Biến môi trường bên trong container**, lấy từ một file | Process trong container | `env_file: [app.env]` |

Hãy đọc lại hàng đầu tiên: **file `.env` không tự động được đưa vào container.** Compose chỉ dùng nó để điền chỗ trống `${...}` trong `compose.yaml`. Muốn một biến trong `.env` vào được container, bạn phải **tham chiếu nó** trong `environment:`:

```yaml
# .env (nằm cạnh compose.yaml)
POSTGRES_PASSWORD=MatKhauDai-123

# compose.yaml
services:
  postgres:
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}   # interpolation: Compose điền giá trị từ .env vào đây
```

**Cú pháp interpolation:**

| Cú pháp | Ý nghĩa |
|---|---|
| `${VAR}` | Giá trị của `VAR` (rỗng nếu chưa đặt — kèm cảnh báo) |
| `${VAR:-mặc_định}` | `VAR` nếu đã đặt **và khác rỗng**, ngược lại dùng `mặc_định` |
| `${VAR:?thông báo}` | `VAR` nếu đã đặt và khác rỗng, ngược lại **Compose dừng với lỗi** in ra thông báo |
| `$$` | Ký tự `$` thật (khi muốn shell **trong container** tự thay biến) |

`${VAR:?...}` rất hữu ích cho secret: quên tạo `.env` → Compose báo lỗi rõ ràng ngay, thay vì chạy database với mật khẩu rỗng.

**Thứ tự ưu tiên khi interpolation** (cao → thấp, theo tài liệu Docker): biến đã có trong **shell** của bạn → file truyền bằng `--env-file` → file `.env` trong thư mục project. Hệ quả: nếu shell của bạn lỡ `export POSTGRES_PASSWORD=abc`, giá trị trong `.env` bị **bỏ qua** — một nguồn lỗi khó thấy. `docker compose config --environment` cho biết Compose đang dùng giá trị nào.

**`environment` và `env_file` cùng có một biến** → giá trị trong `environment` thắng.

> 🔐 `.env` chứa secret → thêm vào `.gitignore` **ngay khi tạo repo**, và commit một file `.env.example` có cùng tên biến nhưng giá trị giả. Người khác clone về: `cp .env.example .env` rồi điền giá trị thật.

### 4.6. 🟥 `volumes` trong Compose

```yaml
services:
  postgres:
    volumes:
      - pgdata:/var/lib/postgresql/data                          # named volume (Docker quản lý)
  nginx:
    volumes:
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro   # bind mount file từ host, chỉ đọc

volumes:
  pgdata:
```

- Bắt đầu bằng `./` hoặc `/` → **bind mount** (đường dẫn host, tương đối tính từ thư mục chứa `compose.yaml`).
- Chỉ là một tên → **named volume**, phải khai báo ở `volumes:` cấp cao nhất.
- `:ro` → read-only (chỉ đọc) — nên dùng cho file cấu hình.

Vòng đời dữ liệu — **thuộc lòng**:

| Lệnh | Container | Network | Named volume (dữ liệu DB) |
|---|---|---|---|
| `docker compose stop` | Dừng (còn đó) | Còn | Còn |
| `docker compose down` | **Xóa** | **Xóa** | **Còn** |
| `docker compose down -v` ⚠️ | Xóa | Xóa | **XÓA — mất dữ liệu** |

### 4.7. 🟥 Network trong Compose — DNS theo tên service

Mặc định Compose tạo **một network** tên `<project>_default` và nối mọi service vào. Trong network đó, mỗi service **phân giải được tên của service khác** qua DNS nội bộ của Docker (`127.0.0.11` — [Networking bài 03](../02-NETWORKING/03-dns-dhcp.md)).

Đây là lý do app trong container kết nối database bằng `postgres:5432` chứ **không phải** `localhost:5432`: `localhost` trong container `taskhub` là **chính container `taskhub`** (mỗi container có network namespace riêng — [bài 01](01-vm-vs-container-architecture.md)).

Tự đặt network khi cần **tách lớp** (giống ý tưởng public/private subnet):

```yaml
services:
  nginx:
    networks: [frontend, backend]   # nginx đứng ở cả hai mạng
  taskhub:
    networks: [backend]
  postgres:
    networks: [backend]             # postgres không cùng mạng với thứ gì "phía ngoài"

networks:
  frontend:
  backend:
```

Với dự án v0, network mặc định là đủ. Tách network sẽ có ích khi hệ thống lớn hơn.

### 4.8. 🟥 `depends_on`: thứ tự khởi động ≠ sẵn sàng

```yaml
services:
  taskhub:
    depends_on:
      - postgres        # cú pháp ngắn
```

Cú pháp ngắn chỉ đảm bảo **container `postgres` được khởi động trước** container `taskhub`. Nó **không chờ PostgreSQL sẵn sàng nhận kết nối**. PostgreSQL cần vài giây để khởi tạo (lần đầu còn lâu hơn vì phải tạo database). Trong lúc đó Spring Boot đã khởi động, thử kết nối và nhận `Connection refused` → crash.

Cách đúng — cú pháp dài với **điều kiện**:

```yaml
services:
  postgres:
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "taskhub", "-d", "taskhub"]
      interval: 5s
      timeout: 3s
      retries: 10
  taskhub:
    depends_on:
      postgres:
        condition: service_healthy   # chờ đến khi healthcheck của postgres báo healthy
```

| `condition` | Chờ đến khi |
|---|---|
| `service_started` | Container phụ thuộc đã chạy (giống cú pháp ngắn) |
| `service_healthy` | Container phụ thuộc **healthy** theo `healthcheck` của nó |
| `service_completed_successfully` | Container phụ thuộc **chạy xong và thoát với mã 0** — hợp cho job khởi tạo (ví dụ chạy migration một lần) |

🟨 Thêm hai tùy chọn: `restart: true` (Compose khởi động lại service này khi nó cập nhật service phụ thuộc) và `required: false` (chỉ cảnh báo nếu service phụ thuộc không có).

> `depends_on` chỉ có tác dụng **lúc Compose khởi động**. Nếu PostgreSQL chết giữa chừng, app vẫn phải tự xử lý (Spring Boot sẽ báo lỗi kết nối và thử lại khi có request mới). Đây là lý do app thật nên **chịu được lỗi tạm thời** của phụ thuộc.

### 4.9. 🟥 `healthcheck` — container "sống" chưa chắc đã "khỏe"

Trạng thái `Up` chỉ có nghĩa là **process chính còn chạy**. Spring Boot có thể còn sống nhưng mất kết nối database, hoặc đang khởi động dở. **Healthcheck** là lệnh Docker chạy định kỳ **bên trong container**; exit code `0` = healthy, `1` = unhealthy.

| Trường | Ý nghĩa | Mặc định (giống lệnh `HEALTHCHECK` trong Dockerfile) |
|---|---|---|
| `test` | Lệnh kiểm tra. Dạng list: phần tử đầu là `CMD` (chạy trực tiếp) hoặc `CMD-SHELL` (chạy qua `/bin/sh`) | — |
| `interval` | Bao lâu kiểm tra một lần | 30s |
| `timeout` | Lệnh chạy quá lâu → coi là thất bại | 30s |
| `retries` | Thất bại bao nhiêu lần liên tiếp thì chuyển `unhealthy` | 3 |
| `start_period` | Thời gian "ân hạn" lúc khởi động: thất bại trong giai đoạn này không bị tính | 0s |

Trạng thái hiện trong cột `STATUS` của `docker compose ps`: `(health: starting)` → `(healthy)` hoặc `(unhealthy)`.

Healthcheck cho Spring Boot: gọi endpoint Actuator `/actuator/health` (trả HTTP 200 khi `UP`, 503 khi `DOWN`):

```yaml
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 60s       # JVM + Spring cần thời gian khởi động
```

`curl -f` trả exit code khác 0 khi HTTP status ≥ 400 → healthcheck thất bại đúng lúc app `DOWN`. Image `eclipse-temurin:21-jre-noble` **có sẵn `curl`** (Dockerfile chính thức của image cài `curl` và `wget`) nên lệnh trên dùng được — tự kiểm chứng: `docker run --rm --entrypoint which eclipse-temurin:21-jre-noble curl`. Healthcheck trong `compose.yaml` **ghi đè** `HEALTHCHECK` khai báo trong Dockerfile ([bài 03](03-dockerfile-multistage.md)). Với image tối giản không có `curl` (distroless, alpine thuần), bạn phải chọn cách khác — xem [bài 03](03-dockerfile-multistage.md).

> ⚠️ **Docker không tự khởi động lại container `unhealthy`.** Healthcheck chỉ **báo trạng thái** (cho `depends_on`, cho bạn nhìn, cho công cụ giám sát). Restart policy chỉ phản ứng khi **process chính thoát**. Kubernetes thì khác — liveness probe thất bại sẽ restart container (Module 09).

### 4.10. 🟥 `restart` — restart policy

| Giá trị | Hành vi |
|---|---|
| `no` | Mặc định. Không bao giờ tự khởi động lại |
| `on-failure[:N]` | Khởi động lại khi process thoát với **mã khác 0**, tối đa N lần nếu có |
| `always` | Luôn khởi động lại khi dừng. Nếu bạn dừng thủ công, nó chỉ chạy lại khi Docker Engine khởi động lại hoặc bạn tự start |
| `unless-stopped` | Như `always`, nhưng container bạn đã dừng thủ công thì **giữ nguyên trạng thái dừng**, kể cả khi Engine khởi động lại |

Hai quy tắc quan trọng từ tài liệu Docker:

1. **Dừng thủ công thì restart policy bị bỏ qua** (để tránh vòng lặp khởi động lại ngoài ý muốn). `docker compose stop taskhub` sẽ **không** kích hoạt restart.
2. Restart policy chỉ có hiệu lực sau khi container **chạy thành công ít nhất 10 giây**. Container chết ngay khi khởi động sẽ không bị khởi động lại vô hạn theo kiểu dồn dập.

Dự án `taskhub` dùng `unless-stopped` cho cả ba service: server khởi động lại → mọi thứ tự chạy lại; bạn chủ động dừng để bảo trì → nó không tự bật lên.

Liên hệ: đây là phiên bản container của `Restart=on-failure` trong systemd ([Linux bài 04](../01-LINUX/04-processes-systemd.md)).

### 4.11. 🟨 `profiles` — service chỉ chạy khi cần

```yaml
services:
  pgadmin:
    image: dpage/pgadmin4      # ví dụ: công cụ quản trị DB, chỉ dùng khi debug
    profiles: [debug]
```

Service có `profiles` **không chạy** với `docker compose up` thông thường; chỉ chạy khi bật profile: `docker compose --profile debug up -d`. Service không gán profile thì luôn chạy.

### 4.12. 🟨 `compose.override.yaml` — cấu hình riêng cho máy dev

Nếu trong thư mục có cả `compose.yaml` và `compose.override.yaml`, Compose **tự động gộp** hai file (file override ghi đè/bổ sung). Dùng để thêm những thứ chỉ cần trên laptop, không muốn có trên server:

```yaml
# compose.override.yaml — chỉ trên máy dev, có thể không commit
services:
  postgres:
    ports:
      - "127.0.0.1:5432:5432"   # mở DB cho công cụ trên WSL (psql, IntelliJ) — chỉ loopback
```

Xem kết quả gộp bằng `docker compose config`. Muốn chỉ định file rõ ràng: `docker compose -f compose.yaml -f compose.prod.yaml up -d`.

### 4.13. 🟨 Tên project

Compose xác định tên project theo thứ tự ưu tiên: cờ `-p` → biến `COMPOSE_PROJECT_NAME` → key `name:` trong file → **tên thư mục** chứa `compose.yaml`. Tên chỉ được gồm chữ thường, số, `-`, `_`.

Vì sao quan trọng: tên volume thật là `<project>_pgdata`. Đổi tên thư mục dự án (ví dụ từ `taskhub` sang `taskhub-v2`) mà không có `name:` → Compose coi là **project khác**, tạo volume mới rỗng → "mất" dữ liệu (thật ra volume cũ vẫn còn, chỉ không được dùng). Dự án `taskhub` đặt `name: taskhub` cố định để tránh chuyện này.

### 4.14. 🟦 Compose watch

`docker compose watch` (hoặc `up --watch`) theo dõi thư mục code và tự đồng bộ file vào container hoặc build lại khi bạn sửa code. Tiện cho phát triển app; với vai trò DevOps, bạn chỉ cần biết nó tồn tại.

### 4.15. Gặp lại ở đâu

| Khái niệm Compose | Gặp lại ở |
|---|---|
| Service + DNS theo tên | Kubernetes **Service** + CoreDNS (Module 09): `taskhub` gọi `postgres` theo tên y như vậy |
| `healthcheck` | Health check của ALB (Module 06), **liveness/readiness probe** của Kubernetes (Module 09) |
| `depends_on: service_healthy` | Kubernetes không có `depends_on` — app phải tự chịu lỗi tạm thời, hoặc dùng init container |
| `.env` + `.env.example` | GitHub Secrets (Module 05), Secrets Manager/SSM Parameter Store (Module 06), Kubernetes Secret (Module 09) |
| `restart: unless-stopped` | `Restart=` của systemd (Linux bài 04), `restartPolicy` của Kubernetes |
| Compose file trong Git | Triển khai lên EC2 (dự án v2, v3) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Trên máy em chạy được mà"

Một developer báo: app chạy tốt khi chạy bằng IntelliJ, nhưng `docker compose up` thì app crash với:

```text
org.postgresql.util.PSQLException: Connection to localhost:5432 refused.
```

Kỹ sư DevOps nhìn ngay thấy chữ `localhost`: trong IntelliJ, app chạy trên WSL nên `localhost:5432` là PostgreSQL publish ra host. Trong Compose, app chạy trong container → `localhost` là chính container app. Sửa: `SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/taskhub` (tên service). Bài học: **cấu hình kết nối phải đến từ biến môi trường**, không cứng trong `application.properties`.

### Ví dụ 2: Đổi mật khẩu trong `.env` nhưng database vẫn đòi mật khẩu cũ

Một kỹ sư đổi `POSTGRES_PASSWORD` trong `.env`, chạy `docker compose up -d`, app báo `password authentication failed`. Nguyên nhân: image `postgres` chỉ dùng `POSTGRES_PASSWORD` **lúc khởi tạo database lần đầu** (khi thư mục dữ liệu còn trống). Volume `pgdata` đã có dữ liệu → biến bị bỏ qua, mật khẩu cũ vẫn có hiệu lực. Cách xử lý: đổi mật khẩu bằng SQL (`ALTER USER ...`) trong database, hoặc nếu là dữ liệu thử nghiệm thì `docker compose down -v` để khởi tạo lại (⚠️ mất dữ liệu).

### Ví dụ 3: Compose trên một server duy nhất

Nhiều công ty nhỏ chạy production bằng Compose trên một hoặc vài VM: đủ đơn giản, dễ hiểu, dễ debug. Dự án `taskhub` cũng vậy ở v2–v5 (EC2 + Compose). Khi cần nhiều server, tự phục hồi khi node chết, scale tự động → chuyển sang Kubernetes hoặc ECS. Biết **khi nào Compose là đủ** là một câu trả lời phỏng vấn tốt.

---

## 6. Sơ đồ kiến trúc

### 6.1. Compose biến file thành tài nguyên Docker

```text
 compose.yaml + .env
        │
        │  docker compose up -d
        ▼
 ┌─ Docker Compose (client) ──────────────────────────────────────┐
 │ 1. Đọc file, thay ${VAR} bằng giá trị từ shell / .env           │
 │ 2. Tạo network  taskhub_default                                 │
 │ 3. Tạo volume   taskhub_pgdata                                  │
 │ 4. Build/pull image                                             │
 │ 5. Tạo container theo thứ tự depends_on (chờ healthy nếu cần)   │
 └───────────────────────┬─────────────────────────────────────────┘
                         │ Docker API (giống lệnh docker run)
                         ▼
                  Docker Engine
```

### 6.2. Dự án taskhub v0 (lab bắt buộc)

```text
  Trình duyệt / curl (Windows hoặc WSL)
        │  http://localhost:8000
        ▼
 ┌──────────── network: taskhub_default ────────────────────────────┐
 │                                                                  │
 │  nginx  (publish 8000→80) ──proxy_pass──► taskhub:8080           │
 │                                            │ (Spring Boot)       │
 │                                            │ jdbc:postgresql://  │
 │                                            ▼   postgres:5432     │
 │                                          postgres ── volume pgdata│
 │                                                                  │
 │  Thứ tự khởi động: postgres (healthy) → taskhub (healthy) → nginx│
 └──────────────────────────────────────────────────────────────────┘
```

Chỉ `nginx` có mũi tên từ bên ngoài vào. `taskhub` và `postgres` không publish port.

---

## 7. Các câu lệnh cần biết

Mọi lệnh chạy trong **thư mục chứa `compose.yaml`** (hoặc dùng `-f <file>`).

| Lệnh | Mục đích | Mức |
|---|---|---|
| `docker compose config` | In cấu hình **sau khi** đã gộp file và thay biến — công cụ debug số 1 | 🟥 |
| `docker compose up -d` | Tạo/cập nhật và chạy nền mọi service | 🟥 |
| `docker compose up -d --build` | Build lại image rồi chạy | 🟥 |
| `docker compose ps` | Trạng thái các container của project (gồm health) | 🟥 |
| `docker compose logs -f <service>` | Xem log, theo dõi liên tục | 🟥 |
| `docker compose exec <service> <lệnh>` | Chạy lệnh trong container đang chạy | 🟥 |
| `docker compose stop` / `start` | Dừng / chạy lại container (không xóa) | 🟥 |
| `docker compose restart <service>` | Khởi động lại container (không đọc lại cấu hình mới) | 🟥 |
| `docker compose down` | Xóa container + network (giữ volume) | 🟥 |
| `docker compose down -v` ⚠️ | Xóa luôn named volume — **mất dữ liệu** | 🟥 |
| `docker compose build` | Chỉ build image | 🟥 |
| `docker compose pull` | Kéo phiên bản mới của image | 🟨 |
| `docker compose up -d --force-recreate <service>` | Tạo lại container dù cấu hình không đổi | 🟨 |
| `docker compose ls` | Liệt kê các project đang chạy | 🟨 |
| `docker compose --profile <tên> up -d` | Chạy cả service thuộc profile | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu dưới đây là **minh họa** (Docker Desktop trên WSL, project tên `compose-intro`). Tên container, ID, thời gian trên máy bạn sẽ khác.

### `docker compose config` — xem file "thật" mà Compose dùng

```bash
docker compose config
```

```text
name: compose-intro
services:
  web:
    image: nginx:1.30-alpine
    networks:
      default: null
    ports:
      - mode: ingress
        target: 80
        published: "8000"
        protocol: tcp
...
```

- Đây là cấu hình **sau khi** thay `${VAR}`, gộp `compose.override.yaml`, chuẩn hóa cú pháp ngắn thành dạng đầy đủ.
- Có lỗi YAML hoặc biến bắt buộc chưa đặt → lệnh này báo lỗi ngay, **trước khi** tạo bất cứ thứ gì.
- `--environment`: in các biến dùng cho interpolation và nguồn của chúng. `--services`: chỉ in tên service.
- ⚠️ Kết quả **in cả secret** đã thay vào (mật khẩu). Đừng dán nguyên văn lên chat/issue.

**Quy tắc:** sửa `compose.yaml` xong → chạy `docker compose config` trước, rồi mới `up`.

### `docker compose up -d`

```bash
docker compose up -d
```

```text
[+] Running 4/4
 ✔ Network compose-intro_default    Created
 ✔ Volume "compose-intro_appdata"   Created
 ✔ Container compose-intro-app-1    Healthy
 ✔ Container compose-intro-web-1    Started
```

| Tham số | Ý nghĩa |
|---|---|
| `-d` | Detached — chạy nền, trả lại terminal. Không có `-d`, log mọi service đổ ra màn hình, Ctrl+C sẽ dừng tất cả |
| `--build` | Build lại image trước khi chạy |
| `--force-recreate` | Tạo lại container kể cả khi cấu hình không đổi |
| `--no-deps` | Chỉ tác động lên service được nêu, không đụng service phụ thuộc |
| `--wait` | Chờ đến khi các service running/healthy rồi mới trả lại terminal — tiện trong script |

**`up -d` là lệnh "đồng bộ trạng thái"**: chạy lại khi đã có container, Compose chỉ **tạo lại** những service có cấu hình thay đổi, giữ nguyên phần còn lại. Đổi port của `web` rồi `up -d` → chỉ `web` bị tạo lại.

Tên container dạng `<project>-<service>-<số thứ tự>`.

### `docker compose ps`

```bash
docker compose ps
```

```text
NAME                  IMAGE               COMMAND                  SERVICE   CREATED          STATUS                    PORTS
compose-intro-app-1   python:3.12-slim    "python -m http.serv…"   app       2 minutes ago    Up 2 minutes (healthy)    8000/tcp
compose-intro-web-1   nginx:1.30-alpine   "/docker-entrypoint.…"   web       2 minutes ago    Up 2 minutes              0.0.0.0:8000->80/tcp
```

- `STATUS`: `Up ... (healthy)` / `(unhealthy)` / `(health: starting)` / `Exited (1) ...` / `Restarting`.
- `PORTS`: `0.0.0.0:8000->80/tcp` = đã publish; `8000/tcp` không có mũi tên = chỉ là port container, **không** publish.
- `-a`: hiện cả container đã dừng (mặc định chỉ hiện đang chạy).

### `docker compose logs`

```bash
docker compose logs -f --tail 50 app
```

| Tham số | Ý nghĩa |
|---|---|
| `<service>` | Chỉ log của service đó. Bỏ trống = mọi service, có tiền tố màu theo tên |
| `-f` | Theo dõi liên tục (như `tail -f`) — Ctrl+C chỉ thoát xem log, **không dừng** container |
| `--tail N` | Chỉ N dòng cuối |
| `-t` | Thêm timestamp |
| `--since 10m` | Chỉ log 10 phút gần nhất |

Log ở đây là **stdout/stderr** của process chính trong container. App ghi log vào file trong container thì `logs` không thấy — đó là lý do ứng dụng container nên log ra stdout.

### `docker compose exec`

```bash
docker compose exec app sh -c 'echo $GREETING'
docker compose exec web nginx -t
docker compose exec postgres psql -U taskhub -d taskhub
```

- Chạy lệnh **trong container đang chạy** của service. Mặc định có TTY, dùng được lệnh tương tác (`bash`, `psql`).
- Container không có `bash` (alpine) → dùng `sh`.
- `-u <user>`: chạy bằng user khác (ví dụ `-u root` để debug khi image chạy non-root).
- Khác `docker compose run <service>`: `run` **tạo container mới** một lần (cho tác vụ một lần), `exec` vào container **đang chạy**.

### `docker compose down`

```bash
docker compose down
docker compose down -v      # ⚠️ xóa cả named volume
```

```text
[+] Running 3/3
 ✔ Container compose-intro-web-1  Removed
 ✔ Container compose-intro-app-1  Removed
 ✔ Network compose-intro_default  Removed
```

Để ý: không có dòng `Volume ... Removed` khi thiếu `-v`. `--rmi local` xóa thêm image được build bởi project (🟨).

### `docker compose restart` khác `up -d` thế nào?

- `restart`: dừng rồi chạy lại **container hiện có** với **cấu hình cũ**. Sửa `compose.yaml` rồi `restart` → thay đổi **không** có hiệu lực.
- `up -d`: so sánh cấu hình mới với container hiện có → **tạo lại** nếu khác.

Sai lầm kinh điển: sửa biến môi trường trong `compose.yaml`, chạy `restart`, thấy app vẫn dùng giá trị cũ.

Ngoại lệ: file được **bind mount** (ví dụ cấu hình nginx) thì nội dung mới đã nằm trong container ngay; chỉ cần app đọc lại (`docker compose exec nginx nginx -s reload`) hoặc `restart`.

### `docker compose pull` và `build`

- `pull`: kéo bản mới nhất của **tag** đang dùng (hữu ích khi tag trỏ tới image mới — ví dụ tag `1.30-alpine` có bản vá mới). Sau đó `up -d` để tạo lại container với image mới.
- `build`: build image cho service có `build:`. `--no-cache` build lại từ đầu, không dùng cache.

---

## 9. Bài thực hành từng bước

**Lab: Compose nhập môn — nginx + app Python** · `[WSL]` · ~75 phút

Mục tiêu: luyện mọi lệnh Compose trên một hệ thống nhỏ, nhẹ, trước khi vào [lab bắt buộc Spring Boot + PostgreSQL](labs/lab-springboot-postgres-compose/README.md). Hệ thống gồm `web` (nginx reverse proxy, giống [Networking bài 07](../02-NETWORKING/07-load-balancing-reverse-proxy.md)) và `app` (server Python đơn giản).

### Bước 1 — Chuẩn bị thư mục

```bash
mkdir -p ~/devops-lab/04-docker/compose-intro/{site,nginx}
cd ~/devops-lab/04-docker/compose-intro
echo "<h1>Hello from app container</h1>" > site/index.html
```

### Bước 2 — Cấu hình nginx

Tạo `nginx/default.conf`:

```nginx
server {
    listen 80;
    location / {
        proxy_pass http://app:8000;          # "app" là TÊN SERVICE — DNS nội bộ của Docker phân giải
        proxy_set_header Host $http_host;    # $http_host giữ cả port (localhost:8000); $host làm mất port
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### Bước 3 — File `.env` và `app.env`

```bash
cat > .env <<'EOF'
WEB_PORT=8000
EOF

cat > app.env <<'EOF'
GREETING=xin-chao-tu-env-file
EOF
```

`.env` sẽ được dùng cho **interpolation** (`${WEB_PORT}`). `app.env` sẽ được đưa **vào container** qua `env_file`.

### Bước 4 — Viết `compose.yaml`

```yaml
name: compose-intro

services:
  app:
    image: python:3.12-slim
    command: ["python", "-m", "http.server", "8000", "--directory", "/srv"]
    env_file:
      - app.env                              # biến vào TRONG container
    environment:
      APP_MODE: "lab"                        # biến khai báo trực tiếp
    volumes:
      - ./site:/srv:ro                       # bind mount, chỉ đọc
      - appdata:/data                        # named volume
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/')"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  web:
    image: nginx:1.30-alpine
    ports:
      - "${WEB_PORT:-8000}:80"               # interpolation từ .env
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      app:
        condition: service_healthy
    restart: unless-stopped

volumes:
  appdata:
```

> Healthcheck của `app` dùng chính `python` có sẵn trong image (image `python:3.12-slim` không có `curl`). Đây là cách làm chung: **dùng công cụ mà image chắc chắn có**.

### Bước 5 — Kiểm tra trước khi chạy

```bash
docker compose config
docker compose config --environment | grep WEB_PORT
```

❓ Trong output của `config`, dòng `published:` của `web` là bao nhiêu? Đổi `WEB_PORT=8080` trong `.env`, chạy lại `config` — giá trị đổi theo chưa? (Đổi lại `8000` sau khi thử.)

### Bước 6 — Chạy và quan sát thứ tự khởi động

```bash
docker compose up -d
docker compose ps
curl -s http://localhost:8000 | head -3
```

❓ Container `web` bắt đầu chạy trước hay sau khi `app` chuyển sang `healthy`? Mở `http://localhost:8000` trên trình duyệt Windows.

### Bước 7 — `.env` có vào container không?

```bash
docker compose exec app sh -c 'echo "GREETING=$GREETING"; echo "APP_MODE=$APP_MODE"; echo "WEB_PORT=$WEB_PORT"'
```

❓ Biến nào có giá trị, biến nào rỗng? Giải thích bằng bảng ở mục 4.5.

### Bước 8 — DNS theo tên service

```bash
docker compose exec web nslookup app 127.0.0.11
docker compose exec web wget -qO- http://app:8000 | head -1
docker compose exec web wget -qO- http://localhost:8000 2>&1 | head -1
```

❓ Vì sao `http://app:8000` thành công còn `http://localhost:8000` từ trong container `web` thất bại?

### Bước 9 — `restart` vs `up -d` khi sửa cấu hình

Sửa `app.env` thành `GREETING=da-sua`. Sau đó:

```bash
docker compose restart app
docker compose exec app sh -c 'echo $GREETING'
docker compose up -d
docker compose exec app sh -c 'echo $GREETING'
```

❓ Sau `restart`, giá trị mới hay cũ? Sau `up -d` thì sao? Container `app` có bị tạo lại không (xem cột `CREATED` của `docker compose ps`)?

### Bước 10 — Dữ liệu trong volume sống qua `down`

```bash
docker compose exec app sh -c 'date > /data/created.txt; cat /data/created.txt'
docker compose down
docker volume ls | grep compose-intro
docker compose up -d
docker compose exec app cat /data/created.txt
```

Sau đó:

```bash
docker compose down -v
docker volume ls | grep compose-intro || echo "volume đã bị xóa"
```

❓ Sau `down` (không `-v`), file còn không? Sau `down -v` thì sao?

### Bước 11 — Restart policy

```bash
docker compose up -d
docker compose stop app
sleep 15; docker compose ps -a
docker compose start app
```

❓ Sau `stop`, `app` có tự chạy lại sau 15 giây không? Vì sao (gợi ý: quy tắc "dừng thủ công" ở mục 4.10)?

### Bước 12 — Dọn dẹp và commit

```bash
docker compose down -v
mkdir -p ~/devops-journey/week08
cp compose.yaml nginx/default.conf ~/devops-journey/week08/
cd ~/devops-journey
git add week08/
git commit -m "docs(docker): lab 05 - compose intro"
git push
```

Ghi câu trả lời các câu ❓ vào `week08/lab05-answers.md`. **Không** commit `.env` hay `app.env` (thói quen tốt dù lab này không có secret).

---

## 10. Kết quả mong đợi

- **Bước 5:** `published: "8000"`; đổi `.env` → `config` hiện giá trị mới ngay. `.env` tác động lên **file Compose**.
- **Bước 6:** `web` chỉ được tạo sau khi `app` báo `Healthy` (output của `up` hiện `Container compose-intro-app-1 Healthy` trước dòng `web ... Started`). `curl` trả về `<h1>Hello from app container</h1>`.
- **Bước 7:** `GREETING` có giá trị (từ `env_file`), `APP_MODE=lab` (từ `environment`), `WEB_PORT` **rỗng** — vì `.env` chỉ dùng cho interpolation, không được đưa vào container.
- **Bước 8:** `nslookup` trả về IP nội bộ của `app` (dải `172.x.x.x`). Từ `web`, `localhost:8000` là chính container `web` — nơi không có gì nghe port 8000 → `Connection refused`.
- **Bước 9:** sau `restart`: vẫn giá trị **cũ** (container cũ, cấu hình cũ). Sau `up -d`: giá trị **mới**, container `app` có `CREATED` mới — Compose phát hiện `env_file` thay đổi nên tạo lại.
- **Bước 10:** sau `down`: file **còn**. Sau `down -v`: volume **mất**.
- **Bước 11:** `app` ở trạng thái `Exited` và **không** tự chạy lại — dừng thủ công làm restart policy bị bỏ qua.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `yaml: line 12: found character that cannot start any token` | Có Tab trong file YAML | Thay Tab bằng dấu cách. Kiểm tra: `cat -A compose.yaml \| grep -n '\^I'` |
| `services.web.ports must be a list` hoặc giá trị bị hiểu sai | Thụt lề sai, thiếu `- ` | Chạy `docker compose config` để thấy Compose hiểu file thế nào |
| `the attribute 'version' is obsolete` (cảnh báo) | Copy từ tutorial cũ có `version: "3.x"` | Xóa dòng `version` |
| `required variable POSTGRES_PASSWORD is missing a value` | Dùng `${VAR:?}` nhưng chưa có `.env` hoặc chạy lệnh ở thư mục khác | Tạo `.env` cạnh `compose.yaml`; chạy lệnh trong đúng thư mục |
| `Bind for 0.0.0.0:8000 failed: port is already allocated` | Port host đã bị chiếm (container khác, app trên WSL/Windows) | `docker ps` xem container nào giữ port; `ss -tlnp \| grep 8000`; đổi port trong `.env` |
| App báo `Connection refused` tới `localhost:5432` | Dùng `localhost` trong container | Dùng tên service: `postgres:5432` |
| Sửa `compose.yaml` nhưng không thấy thay đổi | Dùng `restart` thay vì `up -d`; hoặc sửa code nhưng quên `--build` | `docker compose up -d` (thêm `--build` nếu sửa code/Dockerfile) |
| Giá trị trong `.env` bị "phớt lờ" | Shell đang có biến cùng tên (`export ...`), ưu tiên cao hơn `.env` | `docker compose config --environment`; `unset <VAR>` |
| `no configuration file provided: not found` | Chạy lệnh ngoài thư mục có `compose.yaml` | `cd` đúng thư mục hoặc `-f đường/dẫn/compose.yaml` |
| Đổi tên thư mục → database rỗng | Tên project đổi theo tên thư mục → volume mới | Đặt `name:` cố định trong `compose.yaml` |
| `service "x" depends on undefined service "y"` | Gõ sai tên service trong `depends_on` | Đối chiếu với tên dưới `services:` |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Ba tầng thông tin

Khi một hệ thống Compose không chạy, đọc theo thứ tự:

1. **Cấu hình**: `docker compose config` — Compose có hiểu file đúng như bạn nghĩ không? Biến đã được thay đúng chưa?
2. **Trạng thái**: `docker compose ps -a` — container nào `Exited`? Exit code bao nhiêu? Container nào `unhealthy`?
3. **Log**: `docker compose logs <service>` — process trong container nói gì trước khi chết?

### 12.2. Đọc output khi `up` thất bại

```text
[+] Running 2/3
 ✔ Network taskhub_default      Created
 ✘ Container taskhub-postgres-1  Error
dependency failed to start: container taskhub-postgres-1 is unhealthy
```

Đọc: `taskhub` (và `nginx`) **không được tạo** vì `postgres` không đạt điều kiện `service_healthy`. Lỗi gốc nằm ở `postgres`, không phải `taskhub`:

```bash
docker compose logs postgres --tail 30
docker inspect --format '{{json .State.Health}}' taskhub-postgres-1
```

Lệnh thứ hai cho thấy **output của các lần healthcheck gần nhất** — thường chỉ rõ healthcheck thất bại vì sao (lệnh không tồn tại trong image, sai user, sai port…). Đọc kỹ `docker inspect` ở [bài 08](08-container-troubleshooting.md).

### 12.3. Healthcheck thất bại vì chính lệnh healthcheck

```text
"Output": "OCI runtime exec failed: exec failed: unable to start container process: exec: \"curl\": executable file not found in $PATH"
```

App có thể hoàn toàn khỏe, nhưng **lệnh kiểm tra** không chạy được vì image không có `curl`. Luôn kiểm tra công cụ tồn tại: `docker compose exec <service> which curl`.

### 12.4. Phân biệt lỗi Compose và lỗi app

| Thông báo đến từ | Dấu hiệu | Ví dụ |
|---|---|---|
| **Compose** (trước khi tạo container) | Lệnh `up` dừng ngay, không có container nào được tạo | Lỗi YAML, thiếu biến bắt buộc, sai tên service |
| **Docker Engine** | Container không tạo/start được | Port đã bị chiếm, image không tồn tại, mount đường dẫn sai |
| **App trong container** | Container được tạo, chạy một lúc rồi `Exited` hoặc `unhealthy` | Stack trace Java trong `docker compose logs taskhub` |

Với lỗi app: áp dụng cách đọc stack trace ở [Linux bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md) — tìm dòng `Caused by:` cuối cùng.

Ghi mỗi lỗi gặp phải vào `troubleshooting-journal.md` theo [mẫu nhật ký](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Docker Compose giải quyết vấn đề gì so với một script gồm nhiều lệnh `docker run`? Compose có phải orchestrator như Kubernetes không?
2. Project, service, container khác nhau thế nào? Tên volume thật của volume `pgdata` trong project `taskhub` là gì?
3. Vì sao không nên viết `version: "3.8"` trong `compose.yaml` hiện nay?
4. File `.env` và thuộc tính `env_file` khác nhau thế nào? Biến trong `.env` có tự vào container không?
5. `${DB_PASSWORD:?missing}` và `${WEB_PORT:-8000}` khác nhau thế nào? Khi nào dùng loại nào?
6. Vì sao `depends_on: [postgres]` không đủ để app Spring Boot khởi động ổn định? Sửa thế nào?
7. Container ở trạng thái `Up (unhealthy)` — Docker có tự khởi động lại nó không?
8. `docker compose restart` và `docker compose up -d` khác nhau thế nào khi bạn vừa sửa biến môi trường?
9. `down` và `down -v` khác nhau thế nào? Lệnh nào nguy hiểm với database?
10. Vì sao chỉ nên publish port cho nginx mà không publish cho `taskhub` và `postgres`?
11. App trong container kết nối `localhost:5432` thì sai ở đâu?
12. `restart: unless-stopped` khác `restart: always` ở điểm nào?
13. Vì sao nên đặt `name:` cố định cho project?
14. Lệnh đầu tiên bạn chạy khi nghi ngờ `compose.yaml` có vấn đề là gì? Vì sao?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/05-solutions.md](solutions/05-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Dịch ngược.** Viết `compose.yaml` tương đương chính xác với các lệnh sau, rồi dùng `docker compose config` để kiểm tra:

```bash
docker network create shop
docker volume create redisdata
docker run -d --name cache --network shop -v redisdata:/data --restart unless-stopped redis:7-alpine
docker run -d --name api --network shop -p 127.0.0.1:9000:8000 -e CACHE_HOST=cache -e CACHE_PORT=6379 python:3.12-slim python -m http.server 8000
```

**Bài 2 — Bắt lỗi file.** File dưới đây có **ít nhất 5 lỗi** (cú pháp, logic, bảo mật). Tìm và sửa, giải thích từng lỗi:

```yaml
version: "3.8"
services:
  db:
    image: postgres:latest
    environment:
      POSTGRES_PASSWORD: admin123
    ports:
      - 5432:5432
  backend:
    build: .
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/postgres
    depends_on:
      - database
	ports:
      - "8080:8080"
```

**Bài 3 — Biến bắt buộc.** Sửa lab ở mục 9 để `app` nhận biến `API_KEY` lấy từ `.env`, và Compose **từ chối chạy** với thông báo rõ ràng nếu `.env` không có `API_KEY`. Chứng minh bằng cách xóa dòng đó khỏi `.env` rồi chạy `docker compose config`.

**Bài 4 — Override cho dev.** Tạo `compose.override.yaml` cho lab để: (a) publish thêm port 8000 của `app` ra `127.0.0.1:8001`, (b) thêm biến `APP_MODE=dev` ghi đè giá trị `lab`. Dùng `docker compose config` chứng minh hai file được gộp đúng. Sau đó chạy với **chỉ** `compose.yaml` (không override) bằng cờ `-f` và chứng minh port 8001 không còn.

**Bài 5 — Job khởi tạo.** Thêm service `init` (image `busybox` hoặc `python:3.12-slim`) chạy một lần để ghi file `/data/seed.txt` vào volume `appdata`, rồi thoát với mã 0. Cấu hình để `app` chỉ khởi động **sau khi** `init` chạy xong thành công. Gợi ý: một `condition` ở mục 4.8. Điều gì xảy ra nếu `init` thoát với mã 1?

**Bài 6 — Điều tra thứ tự ưu tiên.** Trong lab, chạy `export WEB_PORT=9999` trong shell, rồi `docker compose config | grep published`. Giải thích kết quả. Viết một mục `troubleshooting-journal.md` như thể đây là sự cố thật ("đã sửa `.env` mà port không đổi").

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Tự viết `compose.yaml` cho 2–3 service mà không cần copy, `docker compose config` không báo lỗi.
- [ ] Giải thích được cho người khác `.env` khác `env_file` thế nào, có ví dụ.
- [ ] Giải thích được vì sao cần `condition: service_healthy` và healthcheck tốt trông như thế nào.
- [ ] Biết chính xác lệnh nào giữ, lệnh nào xóa dữ liệu trong volume.
- [ ] Khi `up` thất bại, xác định được lỗi thuộc tầng Compose, Engine hay app trong dưới 5 phút.
- [ ] Làm xong Bài tập 2 và 5 không xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Docker Compose quickstart](https://docs.docker.com/compose/gettingstarted/) | Bài thực hành chính thức: healthcheck, volume, `config`, `logs`, `exec` | 2026-10-31 |
| [Compose file reference — Services](https://docs.docker.com/reference/compose-file/services/) | `depends_on`, `healthcheck`, `restart`, `env_file`, `profiles` | 2026-10-31 |
| [Compose file reference — Version and name](https://docs.docker.com/reference/compose-file/version-and-name/) | `version` đã lỗi thời, `name` | 2026-10-31 |
| [Compose — Variable interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) | `.env`, `${VAR:-}`, `${VAR:?}`, thứ tự ưu tiên | 2026-10-31 |
| [Compose — Set environment variables](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/) | `environment` và `env_file` | 2026-10-31 |
| [docker compose CLI reference](https://docs.docker.com/reference/cli/docker/compose/) | Các lệnh con, cách xác định tên project | 2026-10-31 |
| [Start containers automatically (restart policies)](https://docs.docker.com/engine/containers/start-containers-automatically/) | Restart policy, quy tắc dừng thủ công và 10 giây | 2026-10-31 |
| [Dockerfile reference — HEALTHCHECK](https://docs.docker.com/reference/dockerfile/) | Giá trị mặc định của healthcheck, ý nghĩa exit code | 2026-10-31 |
