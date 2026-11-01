# Module 04 — Docker & Container

> Tuần 7–8 · ~32 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 01 — Linux](../01-LINUX/README.md), [Module 02 — Networking](../02-NETWORKING/README.md), [Module 03 — Git](../03-GIT/README.md)

## Mục lục

- [1. Vì sao DevOps phải thạo container?](#1-vì-sao-devops-phải-thạo-container)
- [2. Junior cần biết Docker đến mức nào?](#2-junior-cần-biết-docker-đến-mức-nào)
- [3. Môi trường: Docker Desktop + WSL hoạt động thế nào](#3-môi-trường-docker-desktop--wsl-hoạt-động-thế-nào)
- [4. Thứ tự bài học](#4-thứ-tự-bài-học)
- [5. Lab bắt buộc, break-fix và dự án](#5-lab-bắt-buộc-break-fix-và-dự-án)
- [6. Dọn dẹp tài nguyên Docker](#6-dọn-dẹp-tài-nguyên-docker)
- [7. Docker trong các module sau](#7-docker-trong-các-module-sau)
- [8. Checklist hoàn thành module](#8-checklist-hoàn-thành-module)
- [9. Nguồn học](#9-nguồn-học)

---

## 1. Vì sao DevOps phải thạo container?

Trước container, triển khai một app Java lên server nghĩa là: cài đúng phiên bản JDK, đúng biến môi trường, đúng thư mục, đúng user (đúng như bạn đã làm tay ở [Lab 02 — Java systemd service](../01-LINUX/labs/lab-02-java-systemd-service.md)). Mỗi server một chút khác nhau → "chạy trên máy tôi nhưng lỗi trên server".

Container đóng gói **app + runtime + thư viện + cấu hình mặc định** thành một **image**. Image đó chạy giống nhau trên laptop của bạn, trên runner của GitHub Actions, trên EC2 và trên Kubernetes.

| Bạn sẽ làm ở công việc thật | Cần kiến thức của module này |
|---|---|
| Viết Dockerfile cho app Spring Boot của team | Bài 03 |
| "Container cứ khởi động là chết" | Bài 08 (đọc log, exit code) |
| "App trong container không kết nối được database" | Bài 04 (network, DNS nội bộ) |
| "Mất hết dữ liệu sau khi xóa container" | Bài 04 (volume) |
| Dựng môi trường dev cho cả team bằng một lệnh | Bài 05 (Compose) |
| Pipeline build image và đẩy lên registry | Bài 06, rồi Module 05 |
| Bảo mật: image nhỏ, không chạy root, không chứa secret | Bài 07 |

> **Container không phải là máy ảo nhỏ.** Container là **process Linux bình thường** được kernel cô lập — bạn đã chứng minh điều này ở [Linux bài 01, Bước 7](../01-LINUX/01-linux-architecture-filesystem.md#bước-7--so-sánh-với-container-sandbox) (kernel container = kernel WSL). Bài 01 của module này sẽ giải thích cơ chế đằng sau.

---

## 2. Junior cần biết Docker đến mức nào?

| Chủ đề | Mức cần cho Junior | Có thể học sau |
|---|---|---|
| VM vs container, namespace, cgroup | 🟥 Giải thích được bằng lời và chứng minh bằng lệnh | Tự dựng container bằng `unshare`, viết runtime |
| Image, layer, tag, digest | 🟥 Hiểu layer và cache; không dùng `latest` trong production | Định dạng OCI chi tiết |
| `docker run/ps/logs/exec/inspect/stop/rm` | 🟥 Thuộc và dùng được không cần tra | — |
| Dockerfile, multi-stage build | 🟥 **Tự viết** Dockerfile cho app Java, tối ưu cache, non-root | BuildKit nâng cao, cache mount, build đa kiến trúc |
| Volume, bind mount | 🟥 Biết dữ liệu nằm ở đâu, khi nào mất | Volume driver, NFS |
| Network bridge, DNS nội bộ, publish port | 🟥 Giải thích vì sao gọi `postgres:5432` chứ không phải `localhost:5432` | macvlan, overlay, IPv6 |
| Docker Compose | 🟥 Viết `compose.yaml` nhiều service có healthcheck, volume, `.env` | Compose profile, extends, watch |
| Registry (GHCR, ECR) | 🟥 Push/pull, đặt tag có ý nghĩa | Registry tự host, chính sách xóa image |
| Docker security | 🟨 Non-root, image tối giản, không nhúng secret, quét lỗ hổng | Rootless Docker, seccomp/AppArmor profile |
| Troubleshooting | 🟥 Exit code, log, `inspect`, vào container debug | Debug bằng `nsenter`, container sidecar |
| Swarm, Docker in Docker | 🟦 Nhận biết | — |

**Quy tắc vàng:** bạn phải tự viết được Dockerfile + `compose.yaml` cho Spring Boot + PostgreSQL + Nginx **không cần copy**, và khi container chết, **tự tìm ra nguyên nhân từ log và exit code**.

---

## 3. Môi trường: Docker Desktop + WSL hoạt động thế nào

### 3.1. Kiến trúc trên máy bạn

```text
 Windows 11
 ├── Docker Desktop (ứng dụng Windows: giao diện, cài đặt)
 └── WSL 2 (một máy ảo tiện ích nhẹ, chạy kernel Linux thật)
      ├── distro "docker-desktop"  ← Docker Engine (dockerd, containerd) chạy ở đây
      │      └── các container của bạn
      └── distro "Ubuntu"          ← nơi bạn gõ lệnh `docker ...` (CLI)
             │
             └── CLI gửi yêu cầu tới Docker Engine qua socket
                 (tích hợp "WSL Integration" của Docker Desktop lo phần nối này)
```

Những điều quan trọng rút ra:

- **Docker Engine không chạy trong Ubuntu của bạn**, mà trong distro riêng `docker-desktop`. Lệnh `docker` trong Ubuntu chỉ là **client** gửi yêu cầu qua API.
- Hệ quả 1: chạy `ps aux` trong Ubuntu **không thấy** process của container (khác với server Linux thật, nơi container hiện ngay trong `ps`). Bài 01 sẽ chỉ cách quan sát process container đúng cách.
- Hệ quả 2: Docker Desktop **phải đang chạy** thì lệnh `docker` mới dùng được. Lỗi hay gặp nhất:

  ```text
  Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
  ```

  → Mở Docker Desktop, chờ trạng thái *Engine running*.
- Tích hợp với distro Ubuntu bật/tắt tại **Docker Desktop → Settings → Resources → WSL Integration** (theo [tài liệu Docker Desktop WSL 2](https://docs.docker.com/desktop/features/wsl/)).

> Trên **EC2 (tuần 12)** bạn sẽ cài Docker Engine trực tiếp lên Ubuntu — không có Docker Desktop. Khi đó `dockerd` chạy như một systemd service (Linux bài 04) và process container hiện ngay trong `ps`.

### 3.2. Kiểm tra môi trường trước khi học `[WSL]`

```bash
docker version          # phải thấy cả phần "Client" và "Server"
docker info | head -20  # thông tin Engine: số container, image, storage driver
docker context ls       # đang nói chuyện với Engine nào (dấu * là context hiện tại)
docker run --rm hello-world
```

| Kết quả | Ý nghĩa |
|---|---|
| `docker version` chỉ có phần **Client**, phần Server báo lỗi | CLI có nhưng không kết nối được Engine → Docker Desktop chưa chạy hoặc chưa bật WSL Integration cho Ubuntu |
| `docker: command not found` | WSL Integration chưa bật cho distro này |
| `hello-world` in ra "Hello from Docker!" | Mọi thứ sẵn sàng |

**Thư mục làm việc** của module:

```bash
mkdir -p ~/devops-lab/04-docker && cd ~/devops-lab/04-docker
```

> ⚠️ Như mọi module: làm việc trong `~` của WSL, **không** trong `/mnt/c` hoặc `/mnt/d` — build image từ `/mnt/...` chậm hơn nhiều (lý do ở [Linux bài 01 mục 11](../01-LINUX/01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp)).

---

## 4. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 01 | [VM vs Container & kiến trúc Docker](01-vm-vs-container-architecture.md) | 7 | 3h | 🟥 |
| 02 | [Images & Containers](02-images-containers.md) | 7 | 3h | 🟥 |
| 03 | [Dockerfile & multi-stage build](03-dockerfile-multistage.md) | 7 | 4h | 🟥 |
| 04 | [Volumes, networks & biến môi trường](04-volumes-networks-env.md) | 7 | 4h | 🟥 |
| 05 | [Docker Compose](05-docker-compose.md) | 8 | 4h | 🟥 |
| 06 | [Container registry](06-registry.md) | 8 | 2h | 🟥 |
| 07 | [Docker security](07-docker-security.md) | 8 | 3h | 🟨 |
| 08 | [Troubleshooting container](08-container-troubleshooting.md) | 8 | 3h | 🟥 |

---

## 5. Lab bắt buộc, break-fix và dự án

| Hạng mục | Tuần | Mô tả |
|---|---|---|
| [Lab: Spring Boot + PostgreSQL bằng Docker Compose](labs/lab-springboot-postgres-compose/README.md) | 8 | **Lab bắt buộc** theo yêu cầu giáo trình — đóng gói `taskhub` và chạy cùng PostgreSQL + Nginx |
| [Break-fix Docker #1](labs/break-fix-01/README.md) | 8 | Hệ thống container có lỗi cài sẵn — tự tìm và sửa |
| [Checkpoint Git + Docker](checkpoint.md) | 8 | Kiểm tra chung Giai đoạn 3–4 |
| [Dự án: taskhub v0](../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md) | 7–8 | Dockerfile multi-stage, `compose.yaml` gồm `nginx` + `taskhub` + `postgres` |

Quy ước dùng chung cho dự án (mọi bài trong module dùng giống nhau):

| Thành phần | Giá trị |
|---|---|
| Image build | `eclipse-temurin:21-jdk-noble` |
| Image chạy | `eclipse-temurin:21-jre-noble` |
| Database | `postgres:17` |
| Reverse proxy | `nginx:1.30-alpine` |
| Service trong Compose | `nginx`, `taskhub`, `postgres` |
| Port publish ra máy | Chỉ `nginx`: `${NGINX_HOST_PORT:-8000}:80` |
| Bí mật | File `.env` — **không commit** |

> **Vì sao `postgres:17` chứ không phải bản mới nhất 18?** Từ PostgreSQL 18, image chính thức đổi thư mục dữ liệu thành `/var/lib/postgresql/18/docker` và volume khai báo ở `/var/lib/postgresql`. Phần lớn tutorial trên mạng vẫn mount `/var/lib/postgresql/data` — làm vậy với bản 18 sẽ sai. Dùng 17 để bám theo tài liệu phổ biến; khi nâng cấp lên 18 bạn sẽ biết cần đổi gì (theo [trang image postgres trên Docker Hub](https://hub.docker.com/_/postgres)).

---

## 6. Dọn dẹp tài nguyên Docker

Image, container đã dừng, volume và build cache tích tụ rất nhanh — vài tuần học có thể chiếm hàng chục GB. Tập thói quen kiểm tra mỗi tuần:

```bash
docker system df          # dung lượng theo loại: Images, Containers, Local Volumes, Build Cache
docker container prune    # xóa mọi container đã dừng
docker image prune        # xóa image "lơ lửng" (dangling — không còn tag nào)
docker builder prune      # xóa build cache
```

> ⚠️ `docker system prune -a --volumes` xóa **mọi** image không được container nào dùng và **mọi volume** không gắn với container — kể cả dữ liệu database của dự án. Chỉ chạy khi bạn hiểu rõ nó xóa gì. Volume dữ liệu quan trọng: xem bằng `docker volume ls` trước.

Dung lượng của Docker Desktop nằm trong một file ổ đĩa ảo trên Windows; xóa image trong Docker không phải lúc nào cũng trả lại ngay dung lượng cho ổ `C:`. Xem mục *Resources* trong cài đặt Docker Desktop nếu ổ `C:` đầy.

---

## 7. Docker trong các module sau

| Khái niệm ở đây | Gặp lại ở |
|---|---|
| Image, tag, registry | Pipeline build/push image (Module 05), ECR (Module 06), Kubernetes kéo image (Module 09) |
| Compose | Triển khai `taskhub` trên EC2 (Module 06) |
| Healthcheck | Health check của ALB (Module 06), probe của Kubernetes (Module 09) |
| Network, DNS nội bộ | Kubernetes Service và CoreDNS (Module 09) |
| Volume | Persistent Volume (Module 09), backup PostgreSQL (Module 08) |
| Security, quét image | DevSecOps (Module 10) |

---

## 8. Checklist hoàn thành module

- [ ] 🟥 Giải thích được container khác VM ở đâu và chứng minh bằng lệnh (kernel, PID, network).
- [ ] 🟥 Giải thích được image layer, vì sao thứ tự lệnh trong Dockerfile ảnh hưởng tốc độ build.
- [ ] 🟥 Tự viết Dockerfile multi-stage cho `taskhub`, chạy bằng non-root user.
- [ ] 🟥 Giải thích được vì sao app gọi `postgres:5432` chứ không phải `localhost:5432`.
- [ ] 🟥 Biết dữ liệu PostgreSQL nằm ở đâu và khi nào thì mất.
- [ ] 🟥 Viết `compose.yaml` có healthcheck, volume, `.env`; dựng toàn bộ hệ thống bằng một lệnh.
- [ ] 🟥 Đẩy được image lên GHCR với tag có ý nghĩa.
- [ ] 🟥 Container chết → tìm được nguyên nhân từ `docker logs`, `docker inspect`, exit code.
- [ ] 🟨 Image không chứa secret, không chạy root, đã quét lỗ hổng.
- [ ] 🟥 Đạt [Checkpoint Git + Docker](checkpoint.md).
- [ ] 🟥 Hoàn thành [taskhub v0](../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md).
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#docker).

---

## 9. Nguồn học

| Vai trò | Nguồn | Ghi chú |
|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt |
| Chính | [Docker docs — Get started workshop](https://docs.docker.com/get-started/workshop/) | Tài liệu chính thức, có bài thực hành |
| Chính | [Docker Compose quickstart](https://docs.docker.com/compose/gettingstarted/) | Dùng `compose.yaml`, healthcheck, volume |
| Bổ sung | [Spring Boot with Docker](https://spring.io/guides/gs/spring-boot-docker) | Non-root user, layering, Buildpacks (không dạy multi-stage) |
| Tra cứu | [Docker Desktop — WSL 2 backend](https://docs.docker.com/desktop/features/wsl/) | Bật WSL Integration |
| Bổ sung | [iximiuz Labs](https://labs.iximiuz.com/) | Lab thật về container internals, có gói miễn phí |

Thuật ngữ của module: [glossary.md](glossary.md).
