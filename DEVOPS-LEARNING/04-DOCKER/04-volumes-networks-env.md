# 04. Volumes, Networks & biến môi trường

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [03. Dockerfile & Multi-stage](03-dockerfile-multistage.md), [Network 03 — DNS](../02-NETWORKING/03-dns-dhcp.md), [Network 05 — Port & bind address](../02-NETWORKING/05-tcp-udp-ports-firewall.md), [Linux 06 — Biến môi trường](../01-LINUX/06-bash-scripting.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop, `[Container]` bên trong container

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

- Giải thích vì sao dữ liệu trong container **mất khi xóa container**, và chọn đúng giữa **named volume**, **bind mount**, **tmpfs**.
- Chạy PostgreSQL bằng container với volume để dữ liệu sống sót qua `docker rm` — và tránh cạm bẫy đổi đường dẫn dữ liệu ở `postgres:18`.
- Phân biệt **default bridge** và **user-defined bridge**; giải thích vì sao container gọi nhau được bằng **tên**.
- Giải thích lỗi kinh điển: app trong container gọi `localhost:5432` mà không tới được database.
- Truyền cấu hình bằng biến môi trường (`-e`, `--env-file`) và hiểu cách Spring Boot đọc `SPRING_DATASOURCE_URL`.
- Chứng minh vì sao không được đặt mật khẩu trong `ENV` của Dockerfile.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Kiến thức cần |
|---|---|
| "Tôi restart lại container database thì mất hết dữ liệu!" | Volume — dữ liệu phải nằm ngoài layer của container |
| "App báo `Connection refused` tới database dù cả hai container đều chạy" | `localhost` trong container là chính nó; phải gọi bằng tên container trên cùng network |
| "Chạy trên máy dev được, lên server thì app không thấy database" | Cấu hình truyền bằng biến môi trường, không hard-code trong code hay image |
| "Nâng `postgres` lên bản mới, dữ liệu biến mất" | Đọc tài liệu image: đường dẫn dữ liệu có thể thay đổi giữa các phiên bản |
| "Mật khẩu DB bị lộ trong registry" | Secret không bao giờ nằm trong `ENV` của Dockerfile |

Ba chủ đề trong bài này — **dữ liệu, mạng, cấu hình** — là ba thứ biến một image "chạy được trên máy tôi" thành một hệ thống thật. Docker Compose ở [bài 05](05-docker-compose.md) chỉ là cách viết gọn lại chính những thứ bạn học ở đây.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Container là tạm thời (ephemeral)

Nhắc lại [bài 02](02-images-containers.md): container = các layer **chỉ đọc** của image + một **layer ghi được** (writable layer) mỏng ở trên cùng. Mọi file app ghi ra (dữ liệu database, file upload, log ghi ra file) nằm trong layer ghi được đó.

```text
 docker rm postgres  ──►  layer ghi được bị XÓA cùng container
                          → toàn bộ dữ liệu database biến mất
```

Đây không phải lỗi mà là **thiết kế**: container phải thay thế được bất cứ lúc nào (deploy bản mới = xóa container cũ, tạo container mới). Vì vậy thứ gì cần giữ lại phải được đặt **ra ngoài** container.

### 3.2. Mỗi container là một "máy" trong mạng riêng

Nhờ network namespace (bài 01), mỗi container có **interface mạng riêng, IP riêng, loopback `127.0.0.1` riêng**. Docker nối chúng vào một switch ảo gọi là **bridge** — đúng khái niệm switch tầng 2 ở [Network bài 04](../02-NETWORKING/04-routing-nat-switching.md).

### 3.3. Cấu hình nằm ngoài image

Nguyên tắc: **cùng một image** chạy được ở máy dev, staging, production — chỉ khác **cấu hình truyền vào lúc chạy**. Cách phổ biến nhất để truyền cấu hình cho container là **biến môi trường** — khái niệm bạn đã học ở [Linux bài 06](../01-LINUX/06-bash-scripting.md): process con kế thừa biến môi trường, và process chính trong container nhận biến do Docker đặt.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Ba cách lưu dữ liệu ra ngoài container

| | **Named volume** | **Bind mount** | **tmpfs** |
|---|---|---|---|
| Dữ liệu nằm ở | Vùng Docker quản lý (bạn không cần biết đường dẫn) | Một thư mục **bạn chọn** trên máy host | RAM — không ghi xuống đĩa |
| Cú pháp `docker run` | `-v pgdata:/var/lib/postgresql/data` | `-v ~/projects/taskhub/config:/app/config` | `--tmpfs /tmp` |
| Sống sót khi xóa container | ✅ | ✅ (là file của host) | ❌ mất khi container dừng |
| Quyền file | Docker lo | Theo **UID số** của host — dễ lệch | — |
| Khi nào dùng | **Dữ liệu database**, dữ liệu app cần giữ | Đưa file cấu hình/code từ máy vào container (dev); đọc log ra ngoài | File tạm, dữ liệu nhạy cảm không muốn nằm trên đĩa |

Docs Docker: volume là *"the preferred mechanism for persisting data generated by and used by Docker containers"* — dễ backup, dễ di chuyển, không phụ thuộc cấu trúc thư mục của host.

**Hai điều cần nhớ về vòng đời volume:**

- Volume **không tự bị xóa** khi xóa container. Muốn xóa phải `docker volume rm` hoặc `docker volume prune` (⚠️ xóa dữ liệu vĩnh viễn).
- Gắn một volume **rỗng** vào thư mục đang có file trong image → Docker **copy** file từ image vào volume. Gắn **bind mount** thì ngược lại: thư mục của host **che khuất** nội dung image ở đường dẫn đó.

### 4.2. 🟥 PostgreSQL với volume — và cạm bẫy `postgres:18`

Image `postgres` lưu dữ liệu tại một thư mục cố định (biến `PGDATA`). Bạn phải gắn volume **đúng chỗ đó**:

| Phiên bản image | Gắn volume vào | Ghi chú |
|---|---|---|
| `postgres:17` trở xuống (**giáo trình dùng 17**) | `/var/lib/postgresql/data` | Cách mọi tutorial bạn đọc trên mạng đang dùng |
| `postgres:18` trở lên | `/var/lib/postgresql` | Docs Docker Hub: `PGDATA` đổi thành `/var/lib/postgresql/18/docker`, và volume khai báo chuyển lên `/var/lib/postgresql` |

```bash
docker run -d --name postgres \
  -e POSTGRES_DB=taskhub -e POSTGRES_USER=taskhub -e POSTGRES_PASSWORD=dev-only-pass \
  -v taskhub-pgdata:/var/lib/postgresql/data \
  postgres:17
```

Nếu sau này bạn nâng lên `postgres:18` mà **vẫn** gắn `/var/lib/postgresql/data` theo thói quen, dữ liệu sẽ không nằm trong volume bạn nghĩ (hoặc image từ chối khởi động, tùy phiên bản) — nghĩa là có thể mất dữ liệu khi tạo lại container. Bài học lớn hơn: **trước khi đổi phiên bản image, đọc tài liệu của image** — đặc biệt mục về biến môi trường và đường dẫn dữ liệu.

> Nâng major version PostgreSQL (17 → 18) không chỉ là đổi tag: định dạng dữ liệu khác nhau, cần `pg_upgrade` hoặc dump/restore. Module 08 dạy backup/restore bằng `pg_dump`.

Biến môi trường của image `postgres`: **chỉ `POSTGRES_PASSWORD` là bắt buộc**. `POSTGRES_USER` (mặc định `postgres`) và `POSTGRES_DB` là tùy chọn. Các biến này **chỉ có tác dụng ở lần khởi động đầu** khi thư mục dữ liệu còn trống — sau đó đổi `POSTGRES_PASSWORD` cũng không đổi được mật khẩu của database đã tạo (lỗi rất hay gặp, xem mục 11).

### 4.3. 🟥 Bind mount trên WSL — đường dẫn và quyền

**Đường dẫn:** dùng thư mục trong `~` của WSL, không dùng `/mnt/c/...` — cùng lý do ở [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md): chậm và quyền file hiển thị sai.

**Quyền file — kernel chỉ thấy UID số:** đây là ứng dụng trực tiếp của [Linux bài 03](../01-LINUX/03-permissions-users-groups.md). Tên user chỉ là nhãn; kernel kiểm tra quyền bằng **UID**. Container và WSL dùng **chung kernel** nhưng có `/etc/passwd` **riêng**, nên cùng một UID có thể mang tên khác nhau ở hai bên:

```text
 WSL:        /home/phuong/logs  owner UID 1000 (phuong)  quyền 755
 Container:  chạy bằng user taskhub UID 999
             ghi vào /app/logs (bind mount tới /home/phuong/logs)
             → kernel: UID 999 không phải owner, không thuộc group → chỉ có quyền "others" r-x
             → Permission denied
```

Ngược lại, container chạy bằng **root** tạo file trong bind mount → trên WSL file thuộc `root`, user `phuong` không xóa được nếu không `sudo`. Cách xử lý: tạo thư mục với owner/quyền phù hợp UID của container, hoặc chạy container với `--user $(id -u):$(id -g)` khi dev, hoặc dùng named volume.

### 4.4. 🟨 Backup một volume bằng container tạm

Volume do Docker quản lý — muốn lấy dữ liệu ra, chạy một container tạm gắn **cả volume lẫn một thư mục host**, rồi `tar`:

```bash
docker run --rm \
  -v taskhub-pgdata:/source:ro \
  -v "$PWD":/backup \
  ubuntu:24.04 tar czf /backup/pgdata-$(date +%F).tar.gz -C /source .
```

- `:ro` — gắn chỉ đọc (read-only), tránh lỡ tay sửa dữ liệu.
- `-C /source .` — `tar` các file bên trong `/source`, không kèm đường dẫn `/source`.

> ⚠️ Copy file dữ liệu khi PostgreSQL **đang chạy** có thể cho ra bản backup không nhất quán. Cách này chỉ an toàn khi đã dừng container database. Cách backup đúng cho database là **`pg_dump`** — Module 08 sẽ dạy và tự động hóa bằng cron.

### 4.5. 🟥 Network: default bridge và user-defined bridge

Khi cài Docker có sẵn một network tên `bridge` (default bridge). Container chạy không chỉ định `--network` sẽ vào đây.

| | Default bridge (`bridge`) | User-defined bridge (`docker network create ...`) |
|---|---|---|
| Gọi nhau bằng **tên container** | ❌ Chỉ bằng IP | ✅ DNS tự động |
| Cô lập | Mọi container "không chỉ định network" đều chung một mạng | Chỉ các container được gắn vào mới nói chuyện được với nhau |
| Dùng khi | Thử nhanh một container | **Luôn dùng cho ứng dụng nhiều container** |

Docs Docker: *"User-defined bridges provide automatic DNS resolution between containers"*, còn trên default bridge *"Containers … can only access each other by IP addresses"*.

**DNS nội bộ hoạt động thế nào?** Trên user-defined network, file `/etc/resolv.conf` của container trỏ tới `127.0.0.11` — một DNS server nhúng (embedded DNS) do Docker cung cấp. Nó trả lời IP của các container cùng network theo tên (và tên alias); câu hỏi về tên khác (ví dụ `github.com`) được chuyển tiếp ra DNS bên ngoài. Đây là mô hình **resolver** đúng như [Network bài 03](../02-NETWORKING/03-dns-dhcp.md).

### 4.6. 🟥 Gọi nhau bằng tên + **port của container**

```text
 user-defined network "taskhub-net"
 ┌──────────────────────────────────────────────────────────┐
 │  taskhub (172.20.0.3)  ── jdbc:postgresql://postgres:5432 ──►  postgres (172.20.0.2)  │
 │                                                    nghe 0.0.0.0:5432  │
 └──────────────────────────────────────────────────────────┘
```

Hai quy tắc:

1. Tên `postgres` được DNS nội bộ phân giải thành IP của container `postgres`.
2. Port dùng là port **container đang nghe** (`5432`), **không phải** port publish ra host. Publish (`-p`) chỉ dành cho truy cập **từ ngoài vào** host (DNAT — [Network bài 04](../02-NETWORKING/04-routing-nat-switching.md)). Container nói chuyện với nhau **không cần** `-p` chút nào.

> Vì vậy trong dự án, chỉ `nginx` publish port ra ngoài; `taskhub` và `postgres` không publish gì — chúng vẫn nói chuyện được với nhau qua network nội bộ, và người ngoài không chạm được vào database. Đó là thiết kế bảo mật, không chỉ là tiện lợi.

### 4.7. 🟥 Lỗi kinh điển: `localhost` trong container

Bạn chạy PostgreSQL trên WSL hoặc trong container khác, cấu hình app `jdbc:postgresql://localhost:5432/taskhub`. Chạy app trên WSL thì được, cho app vào container thì:

```text
Caused by: java.net.ConnectException: Connection refused
```

Vì sao? Mỗi container có **loopback riêng**. Bên trong container `taskhub`, `localhost` = `127.0.0.1` = **chính container `taskhub`** — nơi không có ai nghe port 5432. Kernel trả RST → `Connection refused` (đúng phân loại lỗi ở [Network bài 05](../02-NETWORKING/05-tcp-udp-ports-firewall.md)).

| Muốn gọi tới | Dùng địa chỉ |
|---|---|
| Container khác cùng user-defined network | **Tên container** (`postgres`) |
| Một dịch vụ chạy trên chính máy host (Windows/WSL) khi dùng Docker Desktop | 🟨 `host.docker.internal` |
| Chính container đó | `localhost` |

🟨 `host.docker.internal`: docs Docker Desktop mô tả tên này *"resolves to the internal IP address of your host"* — tiện khi dev (ví dụ app trong container gọi PostgreSQL chạy thẳng trên WSL). Trên Docker Engine của Linux thuần (như EC2), tên này **không có sẵn**; đừng đưa nó vào cấu hình production.

### 4.8. 🟨 Network `host` và `none`

- `--network host`: container dùng chung network namespace với host — không cô lập mạng, không cần `-p`. Hành vi trên Docker Desktop khác Linux thuần; giáo trình không dùng.
- `--network none`: chỉ có loopback, không ra ngoài được — dùng cho tác vụ xử lý dữ liệu cần cô lập tuyệt đối.

### 4.9. 🟥 Biến môi trường: `-e` và `--env-file`

```bash
docker run -e SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/taskhub ...
docker run --env-file taskhub.env ...
```

File `taskhub.env` (định dạng `KEY=value`, mỗi dòng một biến, **không** có `export`, **không** quote trừ khi bạn muốn dấu nháy nằm trong giá trị):

```text
SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/taskhub
SPRING_DATASOURCE_USERNAME=taskhub
SPRING_DATASOURCE_PASSWORD=dev-only-pass
```

> ⚠️ File `.env` / `*.env` chứa mật khẩu: đưa vào `.gitignore` (đã có trong `.gitignore` ở bài Ôn tập Git) **và** `.dockerignore` (bài 03). Commit một file mẫu `taskhub.env.example` với giá trị giả để người khác biết cần những biến nào.

**Thứ tự ưu tiên:** giá trị `-e`/`--env-file` lúc chạy **ghi đè** giá trị `ENV` mặc định trong Dockerfile. Tránh khai báo cùng một biến ở nhiều nơi; khi nghi ngờ, xem giá trị thật container đang dùng bằng `docker inspect` hoặc `docker exec <c> env`.

### 4.10. 🟥 Spring Boot đọc biến môi trường thế nào? (relaxed binding)

Spring Boot đọc cấu hình từ nhiều nguồn. Theo tài liệu chính thức, **biến môi trường của hệ điều hành ghi đè** giá trị trong `application.properties`/`application.yaml` (tham số dòng lệnh `--spring.datasource.url=...` còn ưu tiên cao hơn nữa).

Biến môi trường không được chứa dấu chấm, nên Spring Boot có quy tắc chuyển đổi (*relaxed binding*). Trích tài liệu: thay dấu chấm `.` bằng gạch dưới `_`, **bỏ** dấu gạch ngang `-`, chuyển thành chữ hoa.

| Thuộc tính trong `application.properties` | Biến môi trường tương ứng |
|---|---|
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `spring.datasource.username` | `SPRING_DATASOURCE_USERNAME` |
| `spring.datasource.password` | `SPRING_DATASOURCE_PASSWORD` |
| `server.port` | `SERVER_PORT` |
| `spring.main.log-startup-info` | `SPRING_MAIN_LOGSTARTUPINFO` (ví dụ của tài liệu — dấu `-` bị bỏ) |

Vì vậy app taskhub **không cần sửa code** để chạy ở môi trường khác: `application.properties` chứa giá trị mặc định cho dev, còn container nhận giá trị thật qua biến môi trường.

### 4.11. 🟥 Vì sao không đặt secret trong `ENV` của Dockerfile

```dockerfile
ENV SPRING_DATASOURCE_PASSWORD=SuperSecret123   # ❌
```

Giá trị này được ghi vào **metadata của image**. Bất kỳ ai có image đều đọc được — không cần chạy container:

```bash
docker image inspect leaky --format '{{json .Config.Env}}'
docker history --no-trunc leaky | grep -i password
```

`ARG` cũng không an toàn: tài liệu Docker cảnh báo giá trị build-arg có thể hiện trong `docker history`. Lab Bước 7 sẽ cho bạn tự chứng minh.

Truyền secret **lúc chạy** (`--env-file` với file không commit) là mức tối thiểu cho môi trường học. 🟦 Cấp cao hơn: Compose secrets (gắn secret thành file trong container), và ở Module 06/10 — AWS Systems Manager Parameter Store / Secrets Manager.

> Lưu ý: biến môi trường truyền lúc chạy vẫn hiện trong `docker inspect <container>` với ai có quyền dùng Docker trên máy đó. Đó là lý do quyền dùng Docker tương đương root ([Linux bài 03](../01-LINUX/03-permissions-users-groups.md)) và vì sao production dùng hệ thống quản lý secret chuyên dụng.

### 4.12. Gặp lại ở đâu

| Kiến thức ở bài này | Gặp lại ở |
|---|---|
| Named volume cho postgres, network riêng, env | `volumes:`, `networks:`, `environment:`/`env_file:` trong `compose.yaml` (bài 05), dự án v0 |
| Gọi nhau bằng tên service | Upstream Nginx `taskhub:8080` thay cho `127.0.0.1:8080` ([milestone tuần 5](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-5--nginx-reverse-proxy-thử-nghiệm)); Kubernetes Service DNS (Module 09) |
| Chỉ publish port cần thiết | Security Group chỉ mở 80/443 (Module 06) |
| Secret ngoài image | GitHub Secrets (Module 05), Parameter Store/Secrets Manager (Module 06), Kubernetes Secret (Module 09) |
| Backup volume | Backup `pg_dump` lên S3 bằng cron (Module 08) |
| Persistent data | EBS volume cho EC2 (Module 06), PersistentVolume trong Kubernetes (Module 09) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Mật khẩu mới không có tác dụng"

Một kỹ sư đổi `POSTGRES_PASSWORD` trong file env, chạy lại container postgres với volume cũ, rồi app báo `password authentication failed for user "taskhub"`. Nguyên nhân: các biến `POSTGRES_*` chỉ được đọc lúc **khởi tạo** thư mục dữ liệu lần đầu. Volume cũ đã có database với mật khẩu cũ. Cách đúng: đổi mật khẩu bên trong database (`ALTER USER taskhub WITH PASSWORD '...'`), hoặc — chỉ ở môi trường dev, chấp nhận mất dữ liệu — xóa volume để khởi tạo lại.

### Ví dụ 2: Database bị lộ ra Internet

Một team chạy `docker run -p 5432:5432 postgres` trên server cloud "để tiện kết nối bằng DBeaver". Port 5432 mở ra mọi địa chỉ của host; nếu firewall/Security Group cũng mở, database với mật khẩu yếu bị quét và chiếm chỉ trong vài giờ. Cách đúng: **không publish** port database; nếu cần truy cập từ máy cá nhân khi debug, chỉ publish trên loopback `-p 127.0.0.1:5432:5432` rồi đi qua SSH tunnel (`ssh -L` ở [Linux bài 05](../01-LINUX/05-packages-ssh.md)). Đây là kiến thức bind address `0.0.0.0` vs `127.0.0.1` ở [Network bài 05](../02-NETWORKING/05-tcp-udp-ports-firewall.md), áp dụng cho Docker.

---

## 6. Sơ đồ kiến trúc

### 6.1. Dữ liệu: layer container vs volume

```text
 Container "postgres"
 ┌────────────────────────────────────────────┐
 │ Layer ghi được  (mất khi docker rm)        │
 │   /tmp, file tạm ...                        │
 │ ───────────────────────────────────────────│
 │ /var/lib/postgresql/data ──── mount ───────┼───►  Volume "taskhub-pgdata"
 │ ───────────────────────────────────────────│      (Docker quản lý, sống độc lập
 │ Các layer chỉ đọc của image postgres:17    │       với container)
 └────────────────────────────────────────────┘
```

### 6.2. Mạng: taskhub + postgres trên user-defined bridge

```text
  Trình duyệt Windows
        │ http://localhost:8080   (chỉ trong lab này — dự án thật đi qua nginx)
        ▼
  ┌─ Host (WSL / Docker Desktop) ──────────────────────────────────────┐
  │   -p 8080:8080  (DNAT)                                             │
  │        │                                                           │
  │  ┌─────▼──── network "taskhub-net" (bridge, DNS 127.0.0.11) ────┐  │
  │  │  ┌───────────────┐   postgres:5432    ┌──────────────────┐   │  │
  │  │  │ taskhub        │ ─────────────────► │ postgres          │   │  │
  │  │  │ nghe 0.0.0.0:  │   (tên → IP qua    │ nghe 0.0.0.0:5432 │   │  │
  │  │  │ 8080           │    DNS nội bộ)     │ (KHÔNG publish)   │   │  │
  │  │  └───────────────┘                    └────────┬─────────┘   │  │
  │  └────────────────────────────────────────────────┼─────────────┘  │
  │                                         volume taskhub-pgdata      │
  └────────────────────────────────────────────────────────────────────┘
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `docker volume create / ls / inspect / rm` | Quản lý volume | 🟥 |
| `docker volume prune` | ⚠️ Xóa mọi volume không được container nào dùng | 🟨 |
| `docker run -v <volume>:<path>` | Gắn named volume | 🟥 |
| `docker run -v <đường-dẫn-host>:<path>` | Bind mount | 🟥 |
| `docker run --mount type=...,src=...,dst=...` | Cú pháp dài, rõ ràng hơn `-v` | 🟨 |
| `docker run --tmpfs <path>` | Gắn tmpfs | 🟨 |
| `docker network create / ls / inspect / rm` | Quản lý network | 🟥 |
| `docker network connect / disconnect` | Gắn/gỡ container khỏi network khi đang chạy | 🟨 |
| `docker run --network <tên>` | Chạy container trong network chỉ định | 🟥 |
| `docker run -e K=V`, `--env-file <file>` | Truyền biến môi trường | 🟥 |
| `docker exec <c> env` | Xem biến môi trường container đang có | 🟥 |
| `docker exec <c> getent hosts <tên>` | Kiểm tra DNS nội bộ từ trong container | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra là **minh họa** — ID, IP, đường dẫn trên máy bạn sẽ khác.

### `docker volume`

```bash
docker volume create taskhub-pgdata
docker volume ls
docker volume inspect taskhub-pgdata
```

```text
DRIVER    VOLUME NAME
local     taskhub-pgdata

[
    {
        "CreatedAt": "2026-11-20T09:15:02Z",
        "Driver": "local",
        "Mountpoint": "/var/lib/docker/volumes/taskhub-pgdata/_data",
        "Name": "taskhub-pgdata",
        "Scope": "local"
    }
]
```

`Mountpoint` là đường dẫn **bên trong máy ảo Linux của Docker Desktop**, không phải trong WSL của bạn — đừng cố `cd` vào đó. Muốn xem nội dung volume, gắn nó vào một container (`docker run --rm -v taskhub-pgdata:/data ubuntu:24.04 ls /data`).

> `docker run -v` với tên volume chưa tồn tại → Docker **tự tạo**. Gõ sai tên (`taskhub-pgdat`) = âm thầm tạo volume mới rỗng → database "mất dữ liệu". Luôn `docker volume ls` khi nghi ngờ.

### `-v` và `--mount`

```bash
# Named volume
-v taskhub-pgdata:/var/lib/postgresql/data
# Bind mount — có dấu / hoặc ~ ở đầu nên Docker hiểu là đường dẫn host
-v ~/devops-lab/04-docker/init:/docker-entrypoint-initdb.d:ro
# Cú pháp --mount tương đương, rõ ràng hơn (lỗi đường dẫn sẽ báo thay vì tự tạo)
--mount type=volume,src=taskhub-pgdata,dst=/var/lib/postgresql/data
--mount type=bind,src="$HOME/devops-lab/04-docker/init",dst=/docker-entrypoint-initdb.d,readonly
```

Phần sau dấu `:` thứ hai là tùy chọn, `ro` = read-only.

### `docker network`

```bash
docker network create taskhub-net
docker network ls
docker network inspect taskhub-net --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```

```text
NETWORK ID     NAME          DRIVER    SCOPE
5b1c...        bridge        bridge    local
a93f...        host          host      local
0c2e...        none          null      local
e7d4...        taskhub-net   bridge    local

postgres 172.20.0.2/16
taskhub 172.20.0.3/16
```

Mỗi user-defined network nhận một dải IP riêng (ví dụ `172.20.0.0/16`) — chính là "subnet" bạn học ở [Network bài 02](../02-NETWORKING/02-ipv4-subnet-cidr.md), kể cả vấn đề trùng dải với mạng công ty/VPN đã nêu ở bài đó.

### Kiểm tra DNS nội bộ từ trong container

```bash
docker exec taskhub getent hosts postgres
docker exec taskhub cat /etc/resolv.conf
```

```text
172.20.0.2      postgres
nameserver 127.0.0.11
options ndots:0
```

`getent hosts` đi qua cơ chế phân giải của hệ điều hành (giống app Java) — khác `dig` như đã học ở Network bài 03. Image `eclipse-temurin` có `getent` (thuộc libc), nên dùng được ngay.

### `--env-file` và kiểm tra biến

```bash
docker run -d --name taskhub --network taskhub-net --env-file taskhub.env -p 8080:8080 taskhub:dev
docker exec taskhub env | grep SPRING_
```

```text
SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/taskhub
SPRING_DATASOURCE_USERNAME=taskhub
SPRING_DATASOURCE_PASSWORD=dev-only-pass
```

Đường dẫn `--env-file` tính từ thư mục bạn đang đứng khi chạy lệnh.

---

## 9. Bài thực hành từng bước

**Lab: taskhub + PostgreSQL bằng `docker run` (chưa dùng Compose)** · `[WSL]` · ~90 phút

Cần image `taskhub:dev` từ [bài 03](03-dockerfile-multistage.md). Làm trong `~/devops-lab/04-docker`. Ghi kết quả vào `~/devops-journey/week07/lab04-volumes-networks.md`.

```bash
mkdir -p ~/devops-lab/04-docker && cd ~/devops-lab/04-docker
```

### Bước 1 — Chứng minh container là tạm thời

```bash
docker run -d --name pg-temp -e POSTGRES_PASSWORD=dev-only-pass postgres:17
sleep 5
docker exec pg-temp psql -U postgres -c "CREATE TABLE note(t text); INSERT INTO note VALUES ('hello');"
docker exec pg-temp psql -U postgres -c "SELECT * FROM note;"
docker rm -f pg-temp
docker run -d --name pg-temp -e POSTGRES_PASSWORD=dev-only-pass postgres:17
sleep 5
docker exec pg-temp psql -U postgres -c "SELECT * FROM note;"
docker rm -f pg-temp
docker volume ls
```

❓ Lần `SELECT` thứ hai báo gì? `docker volume ls` có thấy volume tên ngẫu nhiên (anonymous volume) nào không — nó từ đâu ra? (Gợi ý: image postgres khai báo `VOLUME`.)

### Bước 2 — Named volume

```bash
docker volume create taskhub-pgdata
docker run -d --name postgres \
  -e POSTGRES_DB=taskhub -e POSTGRES_USER=taskhub -e POSTGRES_PASSWORD=dev-only-pass \
  -v taskhub-pgdata:/var/lib/postgresql/data postgres:17
sleep 5
docker exec postgres psql -U taskhub -d taskhub -c "CREATE TABLE note(t text); INSERT INTO note VALUES ('survived');"
docker rm -f postgres
docker run -d --name postgres \
  -e POSTGRES_DB=taskhub -e POSTGRES_USER=taskhub -e POSTGRES_PASSWORD=dev-only-pass \
  -v taskhub-pgdata:/var/lib/postgresql/data postgres:17
sleep 5
docker exec postgres psql -U taskhub -d taskhub -c "SELECT * FROM note;"
```

❓ Dữ liệu còn không? Container `postgres` này đang ở network nào?

### Bước 3 — Default bridge: không gọi nhau bằng tên được

```bash
docker run --rm eclipse-temurin:21-jre-noble getent hosts postgres; echo "exit=$?"
docker inspect postgres --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{end}}'
```

❓ `getent` trả gì, exit code bao nhiêu? `postgres` có IP gì trên default bridge?

### Bước 4 — User-defined network

```bash
docker network create taskhub-net
docker network connect taskhub-net postgres
docker run --rm --network taskhub-net eclipse-temurin:21-jre-noble getent hosts postgres
docker run --rm --network taskhub-net eclipse-temurin:21-jre-noble cat /etc/resolv.conf
```

❓ Lần này `getent` trả gì? `nameserver` trong `resolv.conf` là gì?

### Bước 5 — Tái hiện lỗi `localhost:5432`

Tạo `taskhub-wrong.env`:

```text
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/taskhub
SPRING_DATASOURCE_USERNAME=taskhub
SPRING_DATASOURCE_PASSWORD=dev-only-pass
```

```bash
docker run -d --name taskhub --network taskhub-net --env-file taskhub-wrong.env -p 8080:8080 taskhub:dev
sleep 20
docker ps -a --filter name=taskhub
docker logs taskhub 2>&1 | grep -E "Caused by|ERROR" | head -5
docker rm -f taskhub
```

❓ Container còn chạy không, exit code bao nhiêu? Dòng `Caused by` cuối cùng nói gì? Giải thích bằng sơ đồ mục 4.7.

### Bước 6 — Sửa: gọi bằng tên container

Tạo `taskhub.env` (giống trên nhưng `jdbc:postgresql://postgres:5432/taskhub`), rồi:

```bash
docker run -d --name taskhub --network taskhub-net --env-file taskhub.env -p 8080:8080 taskhub:dev
sleep 30
docker ps --filter name=taskhub          # chờ tới khi STATUS có (healthy)
curl -s localhost:8080/actuator/health; echo
curl -s -X POST localhost:8080/api/tasks -H 'Content-Type: application/json' -d '{"title":"học Docker"}'; echo
curl -s localhost:8080/api/tasks; echo
```

Mở trình duyệt Windows: `http://localhost:8080/actuator/health`.

Xóa và tạo lại **cả hai** container (giữ volume) → `curl localhost:8080/api/tasks` — task còn không?

> Lab này tạm publish port 8080 của app để test. Trong dự án v0 (bài 05), chỉ `nginx` publish port; app không publish.

### Bước 7 — Chứng minh secret trong `ENV` bị lộ

```bash
mkdir -p leaky && cd leaky
cat > Dockerfile <<'EOF'
FROM ubuntu:24.04
ENV SPRING_DATASOURCE_PASSWORD=SuperSecret123
EOF
docker build -t leaky .
docker image inspect leaky --format '{{json .Config.Env}}'
docker history --no-trunc leaky | grep -i password
cd .. && docker image rm leaky
```

❓ Bạn đọc được mật khẩu bằng những lệnh nào? Có cần chạy container không?

### Bước 8 — Quyền khi bind mount

```bash
mkdir -p ~/devops-lab/04-docker/applogs
ls -ld ~/devops-lab/04-docker/applogs
docker run --rm --entrypoint sh -v ~/devops-lab/04-docker/applogs:/logs taskhub:dev -c 'id; touch /logs/app.log'
docker run --rm --entrypoint sh -u 0 -v ~/devops-lab/04-docker/applogs:/logs taskhub:dev -c 'touch /logs/root.log'
ls -l ~/devops-lab/04-docker/applogs
```

❓ Lệnh thứ nhất báo gì? Vì sao? File `root.log` thuộc ai khi nhìn từ WSL? Bạn có xóa được nó bằng user `phuong` không — vì sao? (Gợi ý: quyền xóa file phụ thuộc quyền trên **thư mục**, [Linux bài 03](../01-LINUX/03-permissions-users-groups.md).)

### Bước 9 — Dọn dẹp

```bash
docker rm -f taskhub postgres
docker network rm taskhub-net
docker volume ls
# ⚠️ Lệnh sau xóa dữ liệu vĩnh viễn — chỉ chạy khi không cần dữ liệu lab nữa
docker volume rm taskhub-pgdata
```

Đưa `taskhub.env.example` (giá trị giả) vào ghi chú; **không** commit `taskhub.env`.

---

## 10. Kết quả mong đợi

- **Bước 1:** lần `SELECT` thứ hai báo `ERROR: relation "note" does not exist` — container mới, dữ liệu mới. `docker volume ls` có thể thấy volume tên dài ngẫu nhiên: image `postgres` khai báo `VOLUME` cho thư mục dữ liệu nên Docker tạo **anonymous volume**; nó không bị xóa khi `docker rm -f` (chỉ `--rm` hoặc `docker rm -v` mới xóa anonymous volume kèm theo). Đó là "rác" cần dọn bằng `docker volume rm`.
- **Bước 2:** `SELECT` trả về `survived` — dữ liệu nằm trong volume, độc lập với container. Container đang ở default bridge.
- **Bước 3:** `getent` không in gì, exit code `2` (không tìm thấy). Container `postgres` có IP dạng `172.17.0.x`.
- **Bước 4:** `getent` in `172.x.y.z  postgres`; `nameserver 127.0.0.11`.
- **Bước 5:** container `taskhub` dừng (`Exited (1)`). Dòng `Caused by` cuối cùng chứa `java.net.ConnectException: Connection refused`. Vì `localhost` là chính container `taskhub`.
- **Bước 6:** `/actuator/health` trả `{"status":"UP"}` (có thể kèm chi tiết). Task tạo bằng `POST` vẫn còn sau khi tạo lại cả hai container.
- **Bước 7:** cả `docker image inspect` và `docker history` đều hiện `SuperSecret123` — không cần chạy container.
- **Bước 8:** lệnh thứ nhất in `uid=999(taskhub)...` rồi `touch: cannot touch '/logs/app.log': Permission denied` — thư mục thuộc UID 1000 quyền `755`, UID 999 chỉ có quyền "others". `root.log` thuộc `root`. User `phuong` **xóa được** nó vì `phuong` có quyền `w` trên **thư mục** chứa file — nhưng không sửa được nội dung file.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Restart container database thì mất dữ liệu | Không gắn volume, hoặc gắn sai đường dẫn dữ liệu | Gắn named volume đúng `PGDATA` của phiên bản image |
| Dữ liệu "biến mất" sau khi sửa lệnh `docker run` | Gõ sai tên volume → Docker tạo volume mới rỗng | `docker volume ls`; dùng `--mount` để lỗi rõ ràng hơn |
| `Error: Database is uninitialized and superuser password is not specified` | Thiếu `POSTGRES_PASSWORD` | Thêm biến (bắt buộc) |
| `password authentication failed` sau khi đổi `POSTGRES_PASSWORD` | Biến chỉ có tác dụng lần khởi tạo đầu, volume cũ giữ mật khẩu cũ | `ALTER USER` trong DB, hoặc (dev) xóa volume |
| `Connection refused` tới `localhost:5432` từ app trong container | `localhost` là chính container app | Dùng tên container trên cùng user-defined network |
| `UnknownHostException: postgres` | Hai container không cùng user-defined network, hoặc đang ở default bridge, hoặc sai tên | `docker network inspect`; `docker network connect` |
| App gọi `postgres:5433` vì publish `-p 5433:5432` | Nhầm port publish với port container | Container ↔ container luôn dùng port container (`5432`) |
| `Permission denied` khi app ghi vào bind mount | Lệch UID giữa container và owner thư mục host | Chỉnh owner/quyền thư mục, hoặc dùng named volume |
| Biến môi trường có dấu `"` thừa trong giá trị | Viết `KEY="value"` trong `--env-file` | Bỏ dấu nháy; kiểm tra bằng `docker exec <c> env` |
| `--env-file`: `no such file or directory` | Đường dẫn tương đối tính từ thư mục hiện tại | `pwd`, dùng đường dẫn đúng |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Quy trình khi app không kết nối được database

Áp dụng quy trình theo tầng của [Network bài 08](../02-NETWORKING/08-network-troubleshooting-tools.md), từ trong container app:

```bash
# 1. App đang dùng cấu hình gì?
docker exec taskhub env | grep SPRING_DATASOURCE
# 2. DNS: tên có phân giải được không?
docker exec taskhub getent hosts postgres
# 3. Hai container có cùng network không?
docker inspect taskhub postgres --format '{{.Name}}: {{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
# 4. Port: postgres có đang nghe không? (pg_isready có sẵn trong image postgres)
docker exec postgres pg_isready -h localhost -p 5432
# 5. Log của cả hai phía
docker logs taskhub 2>&1 | grep -A3 "Caused by" | tail -8
docker logs postgres --tail 20
```

> Nếu container app đã thoát, `docker exec` không chạy được. Khi đó dùng `docker logs` (vẫn đọc được log của container đã dừng) và chạy một container tạm **cùng network** để kiểm tra: `docker run --rm --network taskhub-net eclipse-temurin:21-jre-noble getent hosts postgres`.

### 12.2. Đọc lỗi kết nối JDBC

Phân loại theo dòng `Caused by` cuối cùng (cách đọc stack trace ở [Linux bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md)) — các dòng sau là minh họa:

| Dòng lỗi | Tầng | Nghĩa |
|---|---|---|
| `java.net.UnknownHostException: postgres` | DNS | Không phân giải được tên → sai network/tên |
| `java.net.ConnectException: Connection refused` | TCP | Tới được IP nhưng không ai nghe port → sai host (`localhost`), sai port, hoặc postgres chưa khởi động xong |
| `java.net.SocketTimeoutException` / `connect timed out` | Mạng/firewall | Gói tin bị vứt — hiếm khi gặp giữa hai container cùng bridge |
| `FATAL: password authentication failed for user "taskhub"` | Ứng dụng (PostgreSQL) | Mạng **ổn**, sai thông tin đăng nhập |
| `FATAL: database "taskhub" does not exist` | Ứng dụng | Sai tên DB, hoặc volume đã khởi tạo trước khi đặt `POSTGRES_DB` |

### 12.3. Log của postgres khi khởi tạo

```bash
docker logs postgres 2>&1 | head -30
```

Lần đầu với volume rỗng bạn sẽ thấy các dòng về `initdb` và tạo database. Lần sau (volume đã có dữ liệu) sẽ thấy dòng kiểu *"PostgreSQL Database directory appears to contain a database; Skipping initialization"* — dấu hiệu chắc chắn rằng các biến `POSTGRES_*` **không được áp dụng lại**. Dòng `database system is ready to accept connections` cho biết postgres đã sẵn sàng; app khởi động trước dòng này sẽ gặp `Connection refused` — vấn đề thứ tự khởi động mà Compose giải quyết bằng `healthcheck` + `depends_on` ở bài 05.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Vì sao dữ liệu ghi trong container mất khi `docker rm`? Đó có phải lỗi thiết kế không?
2. So sánh named volume, bind mount, tmpfs. Database nên dùng loại nào? File cấu hình khi dev?
3. Bạn nâng `postgres:17` lên `postgres:18` và giữ nguyên `-v pgdata:/var/lib/postgresql/data`. Rủi ro là gì? Bạn phải đọc gì trước khi nâng?
4. Vì sao đổi `POSTGRES_PASSWORD` rồi chạy lại container với volume cũ thì mật khẩu không đổi?
5. Container chạy bằng UID 999 không ghi được vào bind mount thuộc user `phuong`. Giải thích bằng khái niệm UID.
6. Default bridge và user-defined bridge khác nhau ở 2 điểm nào?
7. `127.0.0.11` trong `/etc/resolv.conf` của container là gì?
8. App trong container `taskhub` cấu hình `localhost:5432`. Vì sao lỗi? Sửa thế nào?
9. Postgres publish `-p 5433:5432`. App trong container khác cùng network nên gọi port nào? Vì sao?
10. Vì sao trong dự án chỉ `nginx` publish port?
11. `spring.datasource.password` tương ứng với biến môi trường nào? Quy tắc chuyển đổi là gì?
12. Giá trị trong `application.properties` và biến môi trường cùng đặt `spring.datasource.url` — giá trị nào thắng?
13. Bằng những lệnh nào một người có image đọc được `ENV` trong Dockerfile?
14. `host.docker.internal` là gì? Vì sao không dùng trong cấu hình production?
15. Backup volume database bằng `tar` khi postgres đang chạy có rủi ro gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/04-solutions.md](solutions/04-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Ba lỗi, một hệ thống.** Đồng nghiệp chạy:

```bash
docker run -d --name db -e POSTGRES_PASSWORD=pass -p 5433:5432 postgres:17
docker run -d --name app -e SPRING_DATASOURCE_URL=jdbc:postgresql://db:5433/postgres \
  -e SPRING_DATASOURCE_USERNAME=postgres -e SPRING_DATASOURCE_PASSWORD=pass -p 8080:8080 taskhub:dev
```

App không kết nối được DB. Liệt kê **tất cả** vấn đề (gợi ý: có ít nhất 3, gồm cả một vấn đề về dữ liệu) và viết lại các lệnh đúng.

**Bài 2 — Hai network.** Thiết kế (bằng lệnh `docker network create/run`) hệ thống: `nginx` nói chuyện được với `taskhub`; `taskhub` nói chuyện được với `postgres`; `nginx` **không** nói chuyện được với `postgres`. Viết lệnh kiểm chứng cả 3 điều kiện. (Gợi ý: một container có thể gắn vào nhiều network.)

**Bài 3 — Backup và restore volume.** Với volume `taskhub-pgdata` có dữ liệu: (a) dừng postgres, backup volume ra file `.tar.gz` bằng container tạm; (b) tạo volume mới `taskhub-pgdata-restore`, giải nén vào; (c) chạy postgres với volume mới và chứng minh dữ liệu còn. Viết lại các lệnh và giải thích vì sao phải dừng postgres trước bước (a).

**Bài 4 — Init script.** Image `postgres` chạy các file `.sql` trong `/docker-entrypoint-initdb.d/` ở lần khởi tạo đầu. Dùng **bind mount** để tạo sẵn bảng `audit_log` khi khởi động postgres lần đầu. Sau đó sửa file `.sql` và tạo lại container (giữ volume) — file mới có chạy không? Vì sao? Liên hệ với câu hỏi 4.

**Bài 5 — Profile cấu hình.** Không sửa code, không build lại image, chạy taskhub với `server.port` = 9090 và log level của package `com.taskhub` là `DEBUG` chỉ bằng biến môi trường. Viết tên biến, chứng minh bằng log và `curl`. (Gợi ý: tra cách đặt log level qua thuộc tính `logging.level.<package>` trong tài liệu Spring Boot, rồi áp dụng quy tắc relaxed binding.)

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Chạy được postgres với named volume và chứng minh dữ liệu sống sót qua `docker rm`.
- [ ] Giải thích được bằng sơ đồ vì sao `localhost` trong container không phải host.
- [ ] Tự dựng được taskhub + postgres bằng `docker run` trên user-defined network, không xem hướng dẫn.
- [ ] Phân loại được lỗi kết nối DB theo tầng chỉ từ dòng `Caused by`.
- [ ] Chứng minh được `ENV` trong Dockerfile lộ secret.
- [ ] Làm xong Bài tập 1 và 2 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Docker volumes](https://docs.docker.com/engine/storage/volumes/) | Volume vs bind mount, vòng đời, copy nội dung image vào volume rỗng, backup bằng `tar` | 2026-10-31 |
| [Docker bridge network driver](https://docs.docker.com/engine/network/drivers/bridge/) | Default vs user-defined bridge, DNS theo tên | 2026-10-31 |
| [Docker Engine networking](https://docs.docker.com/engine/network/) | Tổng quan network | 2026-10-31 |
| [Docker Desktop — networking how-tos](https://docs.docker.com/desktop/features/networking/networking-how-tos/) | `host.docker.internal` | 2026-10-31 |
| [postgres — Docker Hub](https://hub.docker.com/_/postgres) | `POSTGRES_PASSWORD` bắt buộc, `PGDATA` thay đổi ở bản 18 | 2026-10-31 |
| [Spring Boot — Externalized Configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html) | Thứ tự ưu tiên nguồn cấu hình, quy tắc biến môi trường | 2026-10-31 |
| [Dockerfile reference](https://docs.docker.com/reference/dockerfile/) | Cảnh báo secret trong `ARG`/`ENV` | 2026-10-31 |
