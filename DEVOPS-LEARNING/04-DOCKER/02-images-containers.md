# 02. Images & Containers

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. VM vs Container & kiến trúc Docker](01-vm-vs-container-architecture.md), [Network 05 — TCP/UDP, port](../02-NETWORKING/05-tcp-udp-ports-firewall.md)
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

- Giải thích **image** là gì (các layer chỉ đọc + metadata) và **container** khác image ở đâu (thêm một layer ghi được).
- Đọc và viết đúng tên image đầy đủ: `registry/namespace/repository:tag@digest`; biết vì sao **không dùng `latest`** cho hệ thống thật.
- Dùng thành thạo các lệnh hằng ngày: `pull`, `images`, `run`, `ps`, `logs`, `exec`, `stop`, `start`, `rm`, `rmi`, `inspect`, `history`, `stats`, `system df`.
- **Publish port** đúng cách (`-p 8080:80`, `-p 127.0.0.1:8080:80`) và giải thích nó bằng kiến thức NAT và bind address đã học.
- Hiểu vì sao app trong container phải là **PID 1 xử lý được SIGTERM**.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Hôm qua deploy vẫn chạy, hôm nay deploy lại cùng image `latest` thì lỗi" | `latest` là một nhãn **di động**, không phải phiên bản cố định |
| "Tôi sửa file trong container rồi, sao restart lại mất?" | Không mất khi *restart*; mất khi **xóa và tạo lại** container — layer ghi được chết theo container |
| "Mở `localhost:8080` không vào được app trong container" | Chưa publish port, hoặc app nghe trên `127.0.0.1` bên trong container |
| "Ổ đĩa server đầy 90%" | `docker system df` — image cũ, container đã dừng, build cache |
| "Container đang chạy, tôi cần xem file cấu hình bên trong" | `docker exec` |
| Pipeline CI cần biết chính xác image nào đang chạy production | Tag theo commit SHA, digest `sha256` |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Image giống cái gì?

Một phép so sánh với Java mà bạn đã quen:

| Java | Docker |
|---|---|
| Class (bản thiết kế) | **Image** |
| Object (thực thể đang sống, tạo từ class) | **Container** |
| Tạo nhiều object từ một class | Chạy nhiều container từ một image |
| Object có trạng thái riêng, class không đổi | Container có layer ghi được riêng, image không đổi |

Hoặc so với ổ cài hệ điều hành: image là **đĩa cài đặt chỉ đọc**, container là **máy đã cài từ đĩa đó**, có thể ghi thêm file.

### 3.2. Image chứa gì?

- **Filesystem** dưới dạng nhiều **layer** (lớp) xếp chồng: ví dụ layer Ubuntu cơ bản → layer cài Java → layer chứa file `app.jar`.
- **Metadata** (siêu dữ liệu): lệnh mặc định khi chạy (`CMD`/`ENTRYPOINT`), biến môi trường mặc định, port khai báo (`EXPOSE`), user chạy, thư mục làm việc.

Image **không** chứa kernel (bài 01) và **không** chứa process đang chạy.

### 3.3. Copy-on-write (sao chép khi ghi)

Container chạy trên các layer **chỉ đọc** của image, cộng thêm **một layer ghi được** riêng ở trên cùng:

- Đọc file → đọc từ layer cao nhất có file đó.
- Sửa file của image → file được **chép lên layer ghi được** rồi mới sửa (copy-on-write). Layer của image không bao giờ đổi.
- Xóa file của image → layer ghi được đánh dấu "đã xóa"; file vẫn nằm trong layer image (dung lượng image không giảm).

Hệ quả: 10 container từ cùng một image **dùng chung** các layer image trên đĩa, mỗi container chỉ tốn thêm phần mình ghi. Cơ chế này do **storage driver** của Docker thực hiện, phổ biến nhất là `overlay2` (union filesystem — filesystem hợp nhất nhiều lớp).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Tên image đầy đủ

```text
ghcr.io/phuong-dev/taskhub:1.2.0@sha256:3b4f...e91a
└──┬──┘ └───┬────┘ └──┬──┘ └─┬─┘ └──────┬──────────┘
registry namespace  repository tag     digest
```

| Thành phần | Ý nghĩa | Mặc định nếu bỏ trống |
|---|---|---|
| Registry (kho chứa image) | Máy chủ lưu image: Docker Hub, GHCR (GitHub), ECR (AWS) | `docker.io` (Docker Hub) |
| Namespace | Tài khoản/tổ chức | `library` cho image chính thức (`nginx` = `docker.io/library/nginx`) |
| Repository | Tên image | — (bắt buộc) |
| Tag (nhãn) | Phiên bản do người đặt | `latest` |
| Digest | Mã băm SHA-256 của nội dung image — định danh **bất biến** | — |

Ví dụ: `nginx:1.30-alpine` thực chất là `docker.io/library/nginx:1.30-alpine`.

### 4.2. 🟥 Tag `latest` là cạm bẫy

`latest` **không** có nghĩa "mới nhất". Nó chỉ là tag mặc định khi người push không ghi tag. Tag **có thể bị gán lại** cho image khác bất cứ lúc nào:

- Thứ Hai: `myapp:latest` → image A.
- Thứ Ba: ai đó push bản mới → `myapp:latest` → image B.
- Server cũ vẫn chạy A (đã kéo về), server mới kéo được B → **hai server chạy hai phiên bản khác nhau dưới cùng một tên**.

Quy tắc cho dự án `taskhub` (sẽ áp dụng ở bài 06 và Module 05):

| Loại tag | Ví dụ | Dùng để |
|---|---|---|
| SemVer | `1.2.0` | Phiên bản phát hành cho người dùng/đội vận hành |
| Commit SHA | `sha-3f2a9c1` | Truy ngược chính xác image ↔ commit Git |
| `latest` | — | Chỉ để tiện thử nghiệm local, **không bao giờ** dùng khi deploy |

### 4.3. 🟨 Digest: định danh bất biến

Tag có thể bị gán lại, **digest thì không**: nội dung đổi một byte → digest đổi. Kéo image bằng digest đảm bảo đúng từng byte:

```bash
docker pull nginx@sha256:<digest>
```

Hệ thống nghiêm ngặt (ngân hàng, hệ thống cần kiểm toán) pin image bằng digest. Ở mức Junior: **biết digest tồn tại, biết lấy nó** (`docker images --digests`, `docker inspect`), và hiểu vì sao nó an toàn hơn tag.

### 4.4. 🟥 Image chính thức, base image và biến thể

Một image thường có nhiều **biến thể** (variant) qua tag:

| Tag ví dụ | Dựa trên | Kích thước | Ghi chú |
|---|---|---|---|
| `eclipse-temurin:21-jdk-noble` | Ubuntu 24.04 (noble) | Lớn | Có JDK đầy đủ — dùng để **build** |
| `eclipse-temurin:21-jre-noble` | Ubuntu 24.04 | Vừa | Chỉ JRE — dùng để **chạy** |
| `eclipse-temurin:21-jre-alpine` | Alpine Linux | Nhỏ | Dùng thư viện C `musl` thay vì `glibc` — đôi khi khác hành vi |
| `nginx:1.30-alpine` | Alpine | Rất nhỏ | |
| `postgres:17` | Debian | Lớn | |

Dự án dùng **noble** cho Java vì cùng nền Ubuntu với server EC2 (Ubuntu 24.04) — ít bất ngờ hơn. Alpine là lựa chọn hợp lý khi đã hiểu khác biệt `musl`.

> Ưu tiên **image chính thức** (Docker Official Images — namespace `library`) hoặc image do chính nhà phát triển phát hành. Image lạ của cá nhân có thể chứa mã độc (bài 07).

### 4.5. 🟥 Publish port: nối kiến thức NAT và bind address

Mặc định container ở trong mạng bridge riêng (bài 04), **máy bạn không truy cập được** port của nó qua `localhost`. Phải **publish**:

```bash
docker run -d -p 8080:80 nginx:1.30-alpine
#              │    └── port BÊN TRONG container (nginx nghe 80)
#              └─────── port trên HOST
```

Bản chất: Docker tạo luật **DNAT** — gói tin tới `host:8080` bị đổi đích thành `IP-container:80` ([Network bài 04](../02-NETWORKING/04-routing-nat-switching.md)).

| Cú pháp | Nghe trên host | Ai truy cập được |
|---|---|---|
| `-p 8080:80` | `0.0.0.0:8080` (mọi interface) | Mọi máy tới được host — trên server thật là cả Internet nếu firewall mở |
| `-p 127.0.0.1:8080:80` | Chỉ loopback của host | Chỉ chính host — **an toàn** cho database, công cụ quản trị |
| `-p 80` | Port ngẫu nhiên trên host | Xem bằng `docker port` |

> ⚠️ **Hai cái bẫy bind address** ([Network bài 05](../02-NETWORKING/05-tcp-udp-ports-firewall.md)):
> 1. `-p 5432:5432` cho PostgreSQL trên server thật = mở database ra mọi interface. Dùng `127.0.0.1:5432:5432` hoặc không publish.
> 2. App **bên trong** container nghe trên `127.0.0.1` → publish cũng vô ích, vì gói tin DNAT tới `eth0` của container chứ không tới loopback. App trong container phải nghe `0.0.0.0`.

`EXPOSE 80` trong image **chỉ là ghi chú** (tài liệu hóa port app dùng) — không tự publish gì cả.

### 4.6. 🟥 PID 1 và tín hiệu dừng

Từ bài 01: `docker stop` gửi SIGTERM, chờ 10 giây, rồi SIGKILL. Để container dừng **nhẹ nhàng** (graceful shutdown — Spring Boot kịp trả lời các request dở dang, đóng kết nối database):

1. Process của app phải **là PID 1** (hoặc PID 1 phải chuyển tiếp signal cho app).
2. App phải **xử lý SIGTERM** (Spring Boot, nginx, PostgreSQL đều xử lý).

Cạm bẫy phổ biến: image chạy app qua `sh -c "java -jar app.jar"` → PID 1 là `sh`, `sh` **không chuyển** SIGTERM cho `java` → chờ 10 giây → SIGKILL → mất request đang xử lý. Bài 03 sẽ giải quyết bằng **exec form** `ENTRYPOINT ["java", "-jar", "app.jar"]`.

### 4.7. 🟨 Restart policy (chính sách khởi động lại)

```bash
docker run -d --restart unless-stopped nginx:1.30-alpine
```

| Giá trị | Hành vi |
|---|---|
| `no` (mặc định) | Không tự khởi động lại |
| `on-failure[:N]` | Khởi động lại khi exit code khác 0 (tối đa N lần) |
| `always` | Luôn khởi động lại, kể cả khi Docker Engine khởi động lại |
| `unless-stopped` | Như `always`, trừ khi bạn chủ động `docker stop` |

Tương đương `Restart=on-failure` của systemd ([Linux bài 04](../01-LINUX/04-processes-systemd.md)). Trên EC2 (tuần 12), `taskhub` sẽ dùng `unless-stopped` trong Compose.

---

## 5. Ví dụ thực tế

### Ví dụ 1: Xem nhanh file cấu hình trong container đang chạy

```bash
docker exec web cat /etc/nginx/conf.d/default.conf
docker exec -it web sh        # vào shell tương tác để xem kỹ hơn
```

Thói quen tốt: **xem** bằng `exec` thoải mái; **sửa** trong container chỉ để thử nghiệm. Thay đổi thật phải nằm trong Dockerfile hoặc file cấu hình được mount (bài 03, 04) — nếu không, lần tạo lại container sẽ mất.

### Ví dụ 2: Ổ đĩa server đầy

```bash
docker system df
```

```text
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          42        5         11.3GB    9.8GB (86%)
Containers      17        5         210MB     180MB (85%)
Local Volumes   8         3         2.1GB     1.4GB (66%)
Build Cache     120       0         4.6GB     4.6GB
```

Đọc: 42 image nhưng chỉ 5 đang dùng, có thể thu hồi 9.8GB. Dọn image không dùng và build cache trước; **cân nhắc rất kỹ** trước khi đụng vào volume (có thể chứa database).

### Ví dụ 3: "Cùng image, sao container này có file lạ?"

Một kỹ sư `exec` vào container sửa tay file cấu hình để "chữa cháy" lúc 2 giờ sáng. Container đó chạy khác với 3 container còn lại. Một tuần sau, container bị tạo lại khi deploy → bản sửa tay biến mất → lỗi cũ quay lại. Bài học: **container là thứ dùng xong vứt (ephemeral)**; mọi thay đổi phải nằm trong image hoặc cấu hình được quản lý bằng Git.

### Gặp lại ở đâu

| Khái niệm | Gặp lại |
|---|---|
| Tag SemVer + SHA, digest | Pipeline đẩy image (Module 05), ECR (Module 06), `image:` trong manifest Kubernetes (Module 09) |
| Publish port, bind address | Security Group mở port (Module 06), Kubernetes Service (Module 09) |
| Restart policy | `restartPolicy` của Pod, `restart:` trong Compose (bài 05) |
| Container ephemeral | Pod bị tạo lại liên tục trong Kubernetes — không bao giờ sửa tay trong Pod |

---

## 6. Sơ đồ kiến trúc

### 6.1. Layer của image và container

```text
          container "web1"          container "web2"
        ┌─────────────────────┐   ┌─────────────────────┐
        │ Layer GHI ĐƯỢC riêng │   │ Layer GHI ĐƯỢC riêng │  ← mất khi docker rm
        └──────────┬──────────┘   └──────────┬──────────┘
                   └────────────┬────────────┘
        ┌───────────────────────▼──────────────────────┐
        │ Layer 3 (chỉ đọc): cấu hình nginx             │
        │ Layer 2 (chỉ đọc): cài nginx                  │   ← image nginx:1.30-alpine
        │ Layer 1 (chỉ đọc): Alpine base filesystem     │     DÙNG CHUNG trên đĩa
        └──────────────────────────────────────────────┘
        + metadata: CMD, ENV, EXPOSE, USER, WORKDIR
```

### 6.2. Publish port

```text
  Trình duyệt Windows / curl
          │  http://localhost:8080
          ▼
  ┌──────────────────── host của Docker Engine ─────────────────────┐
  │  0.0.0.0:8080 ──DNAT──► 172.17.0.2:80                            │
  │                          ┌─────────────────────────────┐        │
  │                          │ container: nginx nghe 0.0.0.0:80 ✅  │
  │                          │ (nếu nghe 127.0.0.1:80 ❌ — gói tin   │
  │                          │  tới eth0, không tới loopback)       │
  │                          └─────────────────────────────┘        │
  └──────────────────────────────────────────────────────────────────┘
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `docker pull` | Kéo image về máy | 🟥 |
| `docker images` (`docker image ls`) | Liệt kê image | 🟥 |
| `docker run` (`-d`, `-it`, `--rm`, `--name`, `-p`, `-e`, `--restart`) | Tạo + chạy container | 🟥 |
| `docker ps` (`-a`, `--format`, `--filter`) | Liệt kê container | 🟥 |
| `docker logs` (`-f`, `--tail`, `--since`, `-t`) | Xem output của process chính | 🟥 |
| `docker exec` (`-it`) | Chạy lệnh trong container đang chạy | 🟥 |
| `docker stop` / `docker kill` / `docker start` / `docker restart` | Điều khiển | 🟥 |
| `docker rm` / `docker rmi` | Xóa container / image | 🟥 |
| `docker inspect` (`--format`) | Xem cấu hình và trạng thái chi tiết | 🟥 |
| `docker port` | Xem port đã publish | 🟥 |
| `docker history` | Xem các layer của image | 🟥 |
| `docker stats` | Tài nguyên theo thời gian thực | 🟥 |
| `docker system df`, `docker ... prune` | Dung lượng và dọn dẹp | 🟥 |
| `docker cp` | Chép file giữa host và container | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa**. ID, kích thước, ngày giờ trên máy bạn sẽ khác.

### `docker pull` và `docker images`

```bash
docker pull nginx:1.30-alpine
docker images
```

```text
1.30-alpine: Pulling from library/nginx
a1b2c3d4e5f6: Pull complete
...
Digest: sha256:9f2e...c41b
Status: Downloaded newer image for nginx:1.30-alpine
docker.io/library/nginx:1.30-alpine

REPOSITORY   TAG           IMAGE ID       CREATED       SIZE
nginx        1.30-alpine   4b7a2f0c9d11   2 weeks ago   52.1MB
postgres     17            8c1e5d2a7b33   3 weeks ago   438MB
alpine       3.20          91ef0af61f39   5 weeks ago   7.8MB
```

- Mỗi dòng `Pull complete` là **một layer**. Kéo image khác có chung layer → dòng đó báo `Already exists` (không tải lại).
- `IMAGE ID` là 12 ký tự đầu của ID nội dung image. Dùng thay cho tên trong mọi lệnh.
- `docker images --digests` hiện thêm cột digest.

### `docker run` — các cờ quan trọng

```bash
docker run -d --name web -p 8080:80 -e TZ=Asia/Ho_Chi_Minh --restart unless-stopped nginx:1.30-alpine
```

| Cờ | Ý nghĩa |
|---|---|
| `-d` | Chạy nền (detached) |
| `-it` | `-i` giữ stdin mở + `-t` cấp terminal giả — dùng khi cần shell tương tác: `docker run -it ubuntu:22.04 bash` |
| `--rm` | Tự xóa container khi dừng — dùng cho lệnh chạy một lần |
| `--name web` | Tên container (duy nhất trên host) |
| `-p 8080:80` | Publish port host 8080 → container 80 |
| `-e KEY=VALUE` | Đặt biến môi trường (bài 04 dạy kỹ, kèm `--env-file`) |
| `--restart unless-stopped` | Chính sách khởi động lại |
| `nginx:1.30-alpine` | Image |
| (sau image) | Lệnh thay cho lệnh mặc định, ví dụ `... alpine:3.20 echo hi` |

> **Thứ tự quan trọng:** mọi cờ của Docker phải đặt **trước** tên image. Mọi thứ **sau** tên image là lệnh và tham số cho process trong container. `docker run nginx:1.30-alpine -p 8080:80` là **sai** — `-p 8080:80` bị coi là tham số gửi cho nginx.

### `docker ps`

```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

```text
NAMES   IMAGE               STATUS                     PORTS
web     nginx:1.30-alpine   Up 3 minutes               0.0.0.0:8080->80/tcp
db      postgres:17         Exited (1) 2 minutes ago
```

| Cờ | Ý nghĩa |
|---|---|
| `-a` | Cả container đã dừng (mặc định chỉ hiện đang chạy) |
| `--format` | Chọn cột (Go template) |
| `--filter status=exited` | Lọc theo trạng thái, tên, image… |
| `-q` | Chỉ in ID — dùng trong script: `docker rm $(docker ps -aq --filter status=exited)` |

Cột `STATUS` rất có giá trị: `Exited (1)` → app tự báo lỗi; `Exited (137)` → SIGKILL ([bài 01 mục 12](01-vm-vs-container-architecture.md#12-đọc-log-và-xử-lý-lỗi)).

### `docker logs`

```bash
docker logs --tail 20 -f -t web
```

| Cờ | Ý nghĩa |
|---|---|
| `--tail 20` | Chỉ 20 dòng cuối |
| `-f` | Theo dõi liên tục (như `tail -f` ở [Linux bài 02](../01-LINUX/02-essential-commands-text.md)) |
| `-t` | Thêm timestamp |
| `--since 10m` | Chỉ log trong 10 phút gần nhất |

`docker logs` chỉ thấy những gì process chính ghi ra **stdout/stderr**. App ghi log vào file trong container thì `docker logs` không thấy — đây là lý do quy ước của container là **log ra stdout** (image nginx chính thức trỏ `access.log`/`error.log` về stdout/stderr). `docker logs` vẫn đọc được với container đã `exited` — rất quý khi debug container chết.

### `docker exec`

```bash
docker exec web nginx -v                      # chạy một lệnh, in kết quả, thoát
docker exec -it web sh                        # mở shell tương tác (Alpine có sh, không có bash)
docker exec -u root -it taskhub bash          # vào bằng user root (bài 07: image chạy non-root)
docker exec -e DEBUG=1 web env | grep DEBUG   # thêm biến môi trường cho lệnh exec
```

`exec` chạy một process **mới** trong cùng namespace của container đang chạy. Container phải đang `running`; container đã dừng thì dùng `docker logs` hoặc `docker cp` để lấy file ra.

### `docker stop`, `kill`, `start`, `restart`, `rm`, `rmi`

```bash
docker stop web            # SIGTERM, chờ 10s, SIGKILL
docker stop -t 30 web      # chờ 30s — cho app cần nhiều thời gian tắt
docker start web           # chạy lại container đã dừng (giữ nguyên layer ghi được)
docker restart web         # stop + start
docker rm web              # xóa container đã dừng
docker rm -f web           # ⚠️ SIGKILL + xóa container đang chạy
docker rmi nginx:1.30-alpine   # xóa image (lỗi nếu còn container dùng nó)
```

Phân biệt quan trọng:

| Hành động | Layer ghi được (file bạn đã sửa trong container) |
|---|---|
| `stop` → `start`, `restart` | **Còn** |
| `rm` rồi `run` lại | **Mất** |

### `docker inspect`

```bash
docker inspect web | less
docker inspect --format '{{.NetworkSettings.IPAddress}}' web
docker inspect --format '{{json .Config.Env}}' web
docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' web
docker inspect --format '{{json .Config.Cmd}} {{json .Config.Entrypoint}}' nginx:1.30-alpine
```

```text
172.17.0.2
["PATH=/usr/local/sbin:...","NGINX_VERSION=1.30.6","TZ=Asia/Ho_Chi_Minh"]
unless-stopped
["nginx","-g","daemon off;"] ["/docker-entrypoint.sh"]
```

`inspect` dùng được cho container **và** image. Các khóa hay dùng nhất:

| Khóa | Cho biết |
|---|---|
| `.State` | Trạng thái, exit code, OOMKilled (bài 01) |
| `.Config.Env`, `.Config.Cmd`, `.Config.Entrypoint`, `.Config.User` | Cấu hình process |
| `.NetworkSettings` | IP, network, port |
| `.Mounts` | Volume, bind mount (bài 04) |
| `.HostConfig` | Giới hạn tài nguyên, restart policy, port binding |

### `docker port` và `docker history`

```bash
docker port web
docker history nginx:1.30-alpine
```

```text
80/tcp -> 0.0.0.0:8080

IMAGE          CREATED       CREATED BY                                      SIZE
4b7a2f0c9d11   2 weeks ago   CMD ["nginx" "-g" "daemon off;"]                0B
<missing>      2 weeks ago   STOPSIGNAL SIGQUIT                              0B
<missing>      2 weeks ago   EXPOSE map[80/tcp:{}]                           0B
<missing>      2 weeks ago   COPY docker-entrypoint.sh / # buildkit          1.62kB
<missing>      2 weeks ago   RUN /bin/sh -c set -x && apk add ...            40.2MB
<missing>      5 weeks ago   ADD alpine-minirootfs-...tar.gz / # buildkit    7.8MB
```

Đọc từ **dưới lên**: dòng dưới cùng là layer đầu tiên (base Alpine), dòng trên cùng là bước cuối. Dòng có `SIZE 0B` chỉ đổi metadata (`CMD`, `EXPOSE`), không tạo dữ liệu. Dòng lớn (`apk add` 40MB) là nơi nên tối ưu nếu image quá to. `<missing>` chỉ có nghĩa layer đó được build ở máy khác — không phải lỗi.

Để ý `STOPSIGNAL SIGQUIT`: image nginx đổi tín hiệu dừng thành SIGQUIT (nginx dùng SIGQUIT để tắt nhẹ nhàng) — `docker stop` sẽ gửi tín hiệu này thay vì SIGTERM.

### `docker cp`

```bash
docker cp web:/etc/nginx/nginx.conf ./nginx.conf     # container → host
docker cp ./index.html web:/usr/share/nginx/html/    # host → container (chỉ để thử nghiệm)
```

Hoạt động cả với container đã dừng — cách lấy file log/dump ra khỏi container đã chết.

### `docker system df` và `prune`

```bash
docker system df
docker container prune     # xóa container đã dừng (hỏi xác nhận)
docker image prune         # xóa image dangling (không còn tag)
docker image prune -a      # ⚠️ xóa MỌI image không có container nào dùng
docker system prune        # container dừng + network không dùng + image dangling + build cache
```

> ⚠️ Mọi lệnh `prune` đều hỏi xác nhận — **đọc kỹ** danh sách trước khi gõ `y`. Thêm `--volumes` hoặc dùng `docker volume prune` có thể xóa dữ liệu database.

---

## 9. Bài thực hành từng bước

**Lab: Làm chủ vòng đời image và container** · `[WSL]` · ~75 phút

Ghi câu trả lời vào `~/devops-lab/04-docker/lab02-answers.md`.

### Bước 1 — Kéo image và đọc layer

```bash
cd ~/devops-lab/04-docker
docker pull nginx:1.30-alpine
docker pull postgres:17
docker images
docker history nginx:1.30-alpine
docker history postgres:17 | head -15
```

❓ Mỗi image có bao nhiêu layer có dung lượng khác 0? Layer lớn nhất của mỗi image do lệnh gì tạo ra? Vì sao `postgres:17` lớn hơn nhiều so với `nginx:1.30-alpine`?

### Bước 2 — Metadata của image

```bash
docker inspect --format 'CMD={{json .Config.Cmd}} ENTRYPOINT={{json .Config.Entrypoint}} USER={{.Config.User}} PORTS={{json .Config.ExposedPorts}}' nginx:1.30-alpine
docker inspect --format 'CMD={{json .Config.Cmd}} ENTRYPOINT={{json .Config.Entrypoint}} PORTS={{json .Config.ExposedPorts}}' postgres:17
docker images --digests nginx
```

❓ Khi chạy container, process chính của mỗi image là gì? Digest của `nginx:1.30-alpine` là gì?

### Bước 3 — Chạy nginx, publish port, truy cập

```bash
docker run -d --name web -p 8080:80 nginx:1.30-alpine
docker ps
docker port web
curl -I http://localhost:8080
```

Mở trình duyệt Windows: `http://localhost:8080`.

❓ `curl` trả mã gì? Header `Server` là gì? Trong `docker ps`, cột `PORTS` hiện gì?

### Bước 4 — Log, exec, sửa thử trong container

```bash
docker logs web
docker exec web sh -c 'echo "<h1>Sửa tay trong container</h1>" > /usr/share/nginx/html/index.html'
curl -s http://localhost:8080
docker logs --tail 3 web
```

❓ Mỗi lần `curl`, log có thêm dòng gì? (Đó là access log — nginx ghi ra stdout.)

### Bước 5 — `restart` giữ dữ liệu, `rm` thì mất

```bash
docker restart web
curl -s http://localhost:8080          # trang sửa tay còn không?

docker rm -f web                       # ⚠️ xóa container
docker run -d --name web -p 8080:80 nginx:1.30-alpine
curl -s http://localhost:8080 | head -5
```

❓ Sau `restart` thì sao? Sau `rm` + `run` thì sao? Giải thích bằng sơ đồ 6.1.

### Bước 6 — Bind address khi publish

```bash
docker run -d --name web-local -p 127.0.0.1:8081:80 nginx:1.30-alpine
docker port web web-local
curl -sI http://localhost:8081 | head -1
```

❓ `docker port` hiện khác nhau thế nào giữa `web` và `web-local`? Trên một server EC2 có IP public, ai truy cập được port 8080 và 8081?

### Bước 7 — Hai container độc lập từ cùng một image

```bash
docker run -d --name web-a -p 8082:80 nginx:1.30-alpine
docker run -d --name web-b -p 8083:80 nginx:1.30-alpine
docker exec web-a sh -c 'echo A > /usr/share/nginx/html/index.html'
docker exec web-b sh -c 'echo B > /usr/share/nginx/html/index.html'
curl -s localhost:8082; curl -s localhost:8083
docker ps -s --format 'table {{.Names}}\t{{.Size}}'
```

❓ Hai container có ảnh hưởng nhau không? Cột `SIZE` (dạng `xB (virtual 52MB)`) nghĩa là gì?

### Bước 8 — PostgreSQL: biến môi trường bắt buộc và đọc log

```bash
docker run -d --name db postgres:17
sleep 3; docker ps -a --filter name=db --format '{{.Status}}'
docker logs db
```

❓ Container `db` còn chạy không? Log nói gì? Sửa lại:

```bash
docker rm db
docker run -d --name db -e POSTGRES_PASSWORD=devpass -e POSTGRES_DB=taskhub postgres:17
sleep 5; docker logs --tail 5 db
docker exec -it db psql -U postgres -d taskhub -c 'SELECT version();'
```

❓ Dòng log nào cho biết PostgreSQL đã sẵn sàng nhận kết nối? Vì sao ta **không** publish port 5432 ở đây mà vẫn truy vấn được?

> ⚠️ `devpass` chỉ dùng cho lab trên máy cá nhân. Bài 04 sẽ chuyển mật khẩu ra file `.env` và giải thích vì sao không ghi mật khẩu trong lệnh.

### Bước 9 — Thời gian dừng và tín hiệu

```bash
time docker stop db
docker inspect --format '{{.State.ExitCode}}' db
docker inspect --format 'STOPSIGNAL={{.Config.StopSignal}}' nginx:1.30-alpine
```

❓ PostgreSQL dừng nhanh hay mất 10 giây? Exit code bao nhiêu? Nginx dùng tín hiệu dừng nào?

### Bước 10 — Tài nguyên, dung lượng, dọn dẹp

```bash
docker stats --no-stream
docker system df
docker rm -f web web-local web-a web-b db    # ⚠️ xóa container của lab
docker container prune
docker system df
```

Commit `lab02-answers.md` vào `~/devops-journey/week07/`.

---

## 10. Kết quả mong đợi

- **Bước 1:** layer lớn nhất là layer base hệ điều hành và layer cài phần mềm (`apk add`/`apt-get install`). `postgres:17` dựa trên Debian và chứa cả bộ PostgreSQL nên lớn hơn nhiều so với nginx trên Alpine.
- **Bước 2:** nginx: ENTRYPOINT `/docker-entrypoint.sh`, CMD `nginx -g daemon off;`. postgres: ENTRYPOINT `docker-entrypoint.sh`, CMD `postgres`. Entry point là script chuẩn bị rồi `exec` chương trình chính để nó thành PID 1.
- **Bước 3:** `HTTP/1.1 200 OK`, `Server: nginx/1.30.x`, `PORTS 0.0.0.0:8080->80/tcp` (có thể kèm dòng `[::]:8080->80/tcp`).
- **Bước 5:** sau `restart` trang sửa tay **còn**; sau `rm` + `run` trang trở về mặc định — layer ghi được đã bị xóa cùng container cũ.
- **Bước 6:** `web` nghe `0.0.0.0:8080` → trên EC2 ai tới được IP public (và Security Group cho phép) đều truy cập được; `web-local` nghe `127.0.0.1:8081` → chỉ chính server.
- **Bước 7:** hai container độc lập. `SIZE` = phần layer ghi được riêng (vài byte), `virtual` = cả image dùng chung.
- **Bước 8:** lần đầu container **chết ngay**, log báo database chưa khởi tạo vì thiếu mật khẩu superuser và yêu cầu đặt `POSTGRES_PASSWORD` (theo [trang image postgres](https://hub.docker.com/_/postgres), đây là biến bắt buộc duy nhất). Lần hai log có dòng `database system is ready to accept connections`. Không cần publish vì `docker exec` chạy `psql` **bên trong** container — kết nối qua socket nội bộ.
- **Bước 9:** PostgreSQL dừng nhanh (xử lý tín hiệu dừng), exit code 0. Nginx dùng `SIGQUIT`.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `Bind for 0.0.0.0:8080 failed: port is already allocated` | Port host đã có container khác (hoặc chương trình khác) dùng | `docker ps` tìm container đang giữ port; đổi port host (`-p 8090:80`); trên WSL có thể là nginx bạn cài ở [Network bài 07](../02-NETWORKING/07-load-balancing-reverse-proxy.md) |
| `Unable to find image 'ngnix:1.30-alpine' locally ... pull access denied ... repository does not exist` | Gõ sai tên image (hoặc image private chưa login) | Kiểm tra chính tả; image private: `docker login` (bài 06) |
| `manifest for nginx:1.30-alpin not found` | Tag không tồn tại | Tra tag trên Docker Hub |
| `curl: (7) Failed to connect to localhost port 8080` | Chưa publish port, container đã chết, hoặc publish nhầm port bên trong | `docker ps` (cột PORTS, STATUS), `docker logs` |
| `curl: (56) Recv failure: Connection reset by peer` | Port đã publish nhưng **app trong container nghe 127.0.0.1** hoặc nghe port khác | `docker exec <c> ss -tln` (nếu có) hoặc xem log khởi động của app |
| `Error response from daemon: container ... is not running` khi `exec` | Container đã dừng | `docker logs` để xem vì sao nó dừng |
| `conflict: unable to remove repository reference ... image is being used by stopped container` | Còn container (kể cả đã dừng) dùng image | `docker ps -a --filter ancestor=<image>`, xóa container trước |
| `OCI runtime exec failed: exec: "bash": executable file not found` | Image không có bash (Alpine, image tối giản) | Dùng `sh` |
| Cờ đặt sau tên image không có tác dụng | Cờ sau image là tham số cho process | Đặt mọi cờ Docker **trước** tên image |

---

## 12. Đọc log và xử lý lỗi

**Quy trình khi một container không chạy như mong đợi:**

```text
docker ps -a  ──► container còn chạy không? STATUS là gì?
   │
   ├─ Exited (N) ──► docker logs <c>           (app nói gì trước khi chết?)
   │                 docker inspect --format '{{json .State}}' <c>   (exit code, OOMKilled, Error)
   │
   └─ Up nhưng không truy cập được
          ├─► docker port <c>                   (đã publish chưa? đúng port bên trong chưa?)
          ├─► docker logs <c>                   (app nghe ở địa chỉ/port nào?)
          └─► docker exec <c> ...               (gọi thử từ bên trong: wget -qO- localhost:80)
```

Ví dụ log của PostgreSQL khi thiếu mật khẩu (Bước 8, minh họa — câu chữ có thể khác theo phiên bản):

```text
Error: Database is uninitialized and superuser password is not specified.
       You must specify POSTGRES_PASSWORD to a non-empty value for the
       superuser. For example, "-e POSTGRES_PASSWORD=password" on "docker run".
```

Cách đọc: ai báo lỗi? → script khởi tạo của image (chưa đến PostgreSQL). Lỗi gì? → thiếu biến môi trường. Cách sửa nằm ngay trong thông báo. **Rất nhiều lỗi container có lời giải ngay trong `docker logs`** — đọc hết trước khi tìm trên mạng.

Ví dụ phân biệt "app chưa sẵn sàng" và "app lỗi": PostgreSQL mất vài giây khởi tạo lần đầu. Kết nối ngay sau `docker run` có thể báo `connection refused` dù vài giây sau lại được — đây là lý do bài 05 dùng **healthcheck** + `depends_on: condition: service_healthy` thay vì `sleep`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Image và container khác nhau thế nào? Dùng phép so sánh với Java class/object.
2. Image gồm những gì? Không gồm những gì?
3. Copy-on-write là gì? Vì sao 10 container nginx không tốn gấp 10 lần dung lượng image?
4. Phân tích tên `ghcr.io/phuong-dev/taskhub:1.2.0`. `nginx:1.30-alpine` thực chất là tên đầy đủ nào?
5. Vì sao không dùng tag `latest` khi deploy? Dự án `taskhub` sẽ tag image thế nào?
6. Tag và digest khác nhau thế nào? Khi nào cần pin bằng digest?
7. `-p 8080:80` và `-p 127.0.0.1:8080:80` khác nhau thế nào? Liên hệ với Network bài 04 và 05.
8. `EXPOSE` trong image có tự publish port không?
9. App trong container nghe `127.0.0.1:8080`, bạn đã `-p 8080:8080` — truy cập từ host có được không? Vì sao?
10. File bạn sửa trong container còn không sau `restart`? Sau `rm` + `run`?
11. `docker logs` lấy dữ liệu từ đâu? Vì sao app trong container nên log ra stdout?
12. Vì sao `CMD sh -c "java -jar app.jar"` gây vấn đề khi `docker stop`?
13. Cờ đặt sau tên image trong `docker run` được hiểu thế nào?
14. Đọc `docker history` theo chiều nào? Dòng `0B` nghĩa là gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/02-solutions.md](solutions/02-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — So sánh biến thể.** Kéo `eclipse-temurin:21-jdk-noble`, `eclipse-temurin:21-jre-noble`, `eclipse-temurin:21-jre-alpine`. Lập bảng kích thước. Kiểm tra trong mỗi image có `javac` không (`docker run --rm <image> javac -version`). Image nào nên dùng để build, image nào để chạy `taskhub`? Vì sao dự án chọn noble thay vì alpine?

**Bài 2 — Thám tử layer.** Chạy một container `ubuntu:22.04`, cài một gói lớn bằng `apt-get` bên trong, rồi xóa gói đó. So sánh `docker ps -s` trước và sau khi xóa. Giải thích bằng copy-on-write vì sao "xóa trong layer trên không làm nhỏ layer dưới" — và điều này có ý nghĩa gì khi viết Dockerfile (báo trước bài 03).

**Bài 3 — Script dọn dẹp an toàn.** Viết `docker-cleanup.sh` (áp dụng [Linux bài 06](../01-LINUX/06-bash-scripting.md)): in `docker system df` trước và sau; xóa container đã dừng **quá 24 giờ** (gợi ý: `docker container prune --filter "until=24h"`); xóa image dangling; **không bao giờ** đụng vào volume; có `set -euo pipefail`; có chế độ `--dry-run` chỉ in ra những gì sẽ xóa.

**Bài 4 — Ba lỗi kết nối.** Tái hiện và giải thích từng trường hợp: (a) container chạy nhưng không publish port; (b) publish sai port bên trong (`-p 8080:8080` cho nginx nghe 80); (c) container nghe đúng nhưng app chỉ nghe loopback (gợi ý: `python:3.12-slim` với `python -m http.server 8000 --bind 127.0.0.1` và `-p 8000:8000`). Với mỗi trường hợp ghi thông báo lỗi của `curl` và lệnh bạn dùng để chẩn đoán.

**Bài 5 — Tag và digest.** Tag lại image nginx bạn có: `docker tag nginx:1.30-alpine mynginx:latest`, rồi tag một image khác (ví dụ `nginx:1.31-alpine`) thành `mynginx:latest`. `docker images` thay đổi thế nào? Image cũ còn không (gợi ý: `<none>`)? Dùng ví dụ này để giải thích cho đồng đội vì sao `latest` nguy hiểm.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Gõ được không cần tra: chạy nginx nền có tên, publish port, xem log, vào shell, dừng, xóa.
- [ ] Giải thích được bằng sơ đồ vì sao file sửa trong container mất sau `rm`.
- [ ] Đọc được `docker history` và chỉ ra layer nên tối ưu.
- [ ] Không bao giờ publish database bằng `-p 5432:5432` trên server thật, và giải thích được vì sao.
- [ ] Khi container chết, việc đầu tiên bạn làm là `docker ps -a` rồi `docker logs`.
- [ ] Làm xong Bài tập 3 và 4 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Docker docs — Get started workshop](https://docs.docker.com/get-started/workshop/) | Run container, build, share image | 2026-10-31 |
| [Docker docs — `docker container stop`](https://docs.docker.com/reference/cli/docker/container/stop/) | Tín hiệu dừng, `-t`, `--stop-timeout` | 2026-10-31 |
| [Docker Hub — postgres](https://hub.docker.com/_/postgres) | Biến bắt buộc `POSTGRES_PASSWORD`, tag, thay đổi PGDATA ở bản 18 | 2026-10-31 |
| [Docker Hub — nginx](https://hub.docker.com/_/nginx) | Tag stable `1.30` / mainline `1.31` | 2026-10-31 |
| [GitHub — docker-library/docs: eclipse-temurin](https://github.com/docker-library/docs/tree/master/eclipse-temurin/README.md) | Danh sách tag `21-jdk-noble`, `21-jre-noble`, `21-jre-alpine` | 2026-10-31 |
