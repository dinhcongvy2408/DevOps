# Thuật ngữ Module 04 — Docker & Container

> Mỗi nhóm ghi bài học giải thích kỹ thuật ngữ đó. Namespace, cgroup, signal, exit code đã gặp ở [glossary Linux](../01-LINUX/glossary.md); DNAT, bind address, DNS ở [glossary Networking](../02-NETWORKING/glossary.md).

## Mục lục

- [Kiến trúc (bài 01)](#kiến-trúc-bài-01)
- [Image và container (bài 02)](#image-và-container-bài-02)
- [Dockerfile (bài 03)](#dockerfile-bài-03)
- [Volume, network, biến môi trường (bài 04)](#volume-network-biến-môi-trường-bài-04)
- [Docker Compose (bài 05)](#docker-compose-bài-05)
- [Registry (bài 06)](#registry-bài-06)
- [Bảo mật (bài 07)](#bảo-mật-bài-07)
- [Xử lý sự cố (bài 08)](#xử-lý-sự-cố-bài-08)

---

## Kiến trúc (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Container | Vùng chứa | Process Linux cô lập bằng namespace, giới hạn bằng cgroup, chạy trên filesystem của image. |
| Virtual Machine (VM) | Máy ảo | Máy giả lập có kernel riêng, chạy trên hypervisor. |
| Hypervisor | Trình quản lý máy ảo | Phần mềm giả lập phần cứng cho VM (KVM, ESXi, Hyper-V). |
| Namespace | Không gian tên | Giới hạn những gì process nhìn thấy (pid, net, mnt, uts, ipc, user, cgroup). |
| cgroup | Nhóm kiểm soát | Giới hạn RAM, CPU, số process cho nhóm process. |
| OOMKilled | Bị giết vì hết RAM | Kernel giết container vượt giới hạn RAM; exit 137, cờ trong `docker inspect`. |
| Throttling | Bóp CPU | Process vượt `--cpus` bị làm chậm, không bị giết. |
| Docker CLI / dockerd | Giao diện dòng lệnh / tiến trình nền | Client gửi yêu cầu REST / server quản lý image, container, network, volume. |
| containerd / runc | Trình quản lý container / runtime OCI | Quản lý vòng đời container / tạo namespace, cgroup rồi exec process. |
| OCI | Sáng kiến container mở | Chuẩn image và runtime giúp image chạy được trên mọi công cụ. |
| Docker socket | Socket Docker | `/var/run/docker.sock` — ai truy cập được là có quyền ngang root. |

## Image và container (bài 02)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Image | Ảnh container | Tập layer filesystem chỉ đọc kèm metadata (CMD, ENV, USER…). |
| Layer | Lớp | Một tầng filesystem của image, dùng chung giữa các image/container. |
| Copy-on-write | Sao chép khi ghi | File của image chỉ được chép lên layer ghi được khi bị sửa. |
| Writable layer | Layer ghi được | Lớp trên cùng của container, mất khi container bị xóa. |
| Storage driver / overlay2 | Trình điều khiển lưu trữ | Cơ chế xếp chồng layer thành một filesystem. |
| Repository / Tag | Kho / nhãn | Tên image / nhãn phiên bản — có thể bị gán lại. |
| Digest | Mã băm nội dung | `sha256:...` gắn với nội dung image, bất biến. |
| Base image / variant | Image nền / biến thể | Image làm nền; `-jdk-noble`, `-jre-alpine` là biến thể. |
| Publish port | Công bố cổng | Ánh xạ port host vào port container bằng DNAT (`-p host:container`). |
| Restart policy | Chính sách khởi động lại | `no`, `on-failure`, `always`, `unless-stopped`; không áp dụng khi dừng thủ công. |
| Ephemeral | Dùng xong bỏ | Container có thể bị xóa và tạo lại bất cứ lúc nào. |
| Dangling image | Image lơ lửng | Image không còn tag nào (`<none>:<none>`). |
| STOPSIGNAL | Tín hiệu dừng | Tín hiệu `docker stop` gửi trước SIGKILL. |

## Dockerfile (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Dockerfile | Tệp mô tả image | Công thức từng bước để `docker build` tạo image. |
| Build context | Ngữ cảnh build | Tập file gửi cho builder; `COPY` chỉ lấy được file trong đây. |
| .dockerignore | Danh sách loại trừ | Mẫu file loại khỏi build context — vì tốc độ và bảo mật. |
| Build time / run time | Lúc build / lúc chạy | Thời điểm tạo image / thời điểm chạy container. |
| Layer cache | Bộ nhớ đệm layer | Một layer đổi thì mọi layer sau build lại. |
| Multi-stage build / stage | Build nhiều giai đoạn / giai đoạn | Nhiều `FROM` trong một file; image cuối chỉ gồm stage cuối. |
| Shell form / exec form | Dạng shell / dạng thực thi | `java -jar` (qua `sh -c`) / `["java","-jar"]` (chạy trực tiếp, nhận SIGTERM). |
| PID 1 | Process số 1 | Process đầu tiên trong container — phải tự xử lý tín hiệu. |
| Healthcheck | Kiểm tra sức khỏe | Lệnh chạy định kỳ: exit 0 healthy, 1 unhealthy. |
| Non-root user | User không phải root | User UID khác 0 dùng để chạy app. |
| OCI label | Nhãn OCI | Metadata chuẩn gắn vào image (`org.opencontainers.image.source`). |
| Layered jar | Jar phân lớp | Jar Spring Boot tách thành nhiều thư mục, mỗi thư mục một layer. |
| musl / glibc | Thư viện C | Alpine dùng musl, Ubuntu dùng glibc. |
| Distroless | Image không distro | Chỉ có app + runtime, không shell, không package manager. |

## Volume, network, biến môi trường (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Named volume | Volume có tên | Vùng lưu trữ do Docker quản lý, sống độc lập với container. |
| Anonymous volume | Volume vô danh | Volume tên ngẫu nhiên, thường do `VOLUME` của image tạo — dễ mồ côi. |
| Bind mount | Gắn thư mục host | Gắn thư mục cụ thể của host vào container. |
| tmpfs | Mount trong RAM | Mất khi container dừng. |
| PGDATA | Thư mục dữ liệu PostgreSQL | Đổi đường dẫn từ bản 18 — tutorial cũ mount sai. |
| Default / user-defined bridge | Bridge mặc định / tự tạo | Bridge tự tạo có DNS theo tên và cô lập tốt hơn. |
| Embedded DNS (127.0.0.11) | DNS nhúng | Resolver của Docker trên user-defined network. |
| host.docker.internal | — | Tên của Docker Desktop trỏ tới máy host. |
| Relaxed binding | Ràng buộc nới lỏng | Spring Boot ánh xạ `SPRING_DATASOURCE_URL` ↔ `spring.datasource.url`. |
| Env file | Tệp biến môi trường | File `KEY=value` truyền bằng `--env-file` / `env_file`. |

## Docker Compose (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Docker Compose | Điều phối nhiều container trên một máy | Đọc YAML mô tả nhiều container và tạo đúng như mô tả. |
| Project | Dự án Compose | Tên project làm tiền tố cho network, volume. |
| Service | Dịch vụ | Mô tả một loại container; đồng thời là tên DNS nội bộ. |
| Interpolation / `.env` | Thay biến / file biến | Compose thay `${VAR}` bằng giá trị từ shell hoặc `.env` — không tự đưa vào container. |
| `env_file` | File biến cho container | Đưa biến vào môi trường của container. |
| depends_on / condition | Phụ thuộc / điều kiện | Thứ tự khởi động; `service_healthy` chờ service phụ thuộc healthy. |
| start_period | Thời gian ân hạn | Lỗi healthcheck lúc khởi động không bị tính. |
| Profile | Hồ sơ | Nhóm service chỉ chạy khi bật `--profile`. |
| Override file | File ghi đè | `compose.override.yaml` tự gộp với `compose.yaml`, dùng cho dev. |
| Race condition | Tranh chấp thứ tự | Kết quả phụ thuộc tốc độ khởi động — lúc chạy lúc không. |

## Registry (bài 06)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Registry | Kho image | Server lưu và phân phối image (Docker Hub, GHCR, ECR). |
| PAT (classic) / scope | Token truy cập cá nhân / phạm vi | Mật khẩu thay thế có quyền giới hạn (`read:packages`, `write:packages`). |
| Credential helper | Trình lưu thông tin đăng nhập | Lưu token trong kho bảo mật của hệ điều hành. |
| Visibility | Chế độ hiển thị | Package public/private; GHCR mặc định private. |
| Immutable tag | Tag bất biến | Không bao giờ push đè (SHA, SemVer) — dùng để deploy và rollback. |
| Rate limit | Giới hạn tần suất | Docker Hub giới hạn số lần pull theo thời gian. |
| Lifecycle policy | Chính sách vòng đời | Quy tắc tự xóa image cũ (ECR). |

## Bảo mật (bài 07)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Threat model | Mô hình đe dọa | Liệt kê cách hệ thống có thể bị tấn công để chọn biện pháp phòng thủ. |
| Container escape | Thoát container | Process trong container tác động được lên host. |
| Capability | Năng lực đặc quyền | Một mảnh quyền root cấp/bỏ riêng lẻ (`CHOWN`, `NET_ADMIN`…). |
| `--privileged` | Chế độ đặc quyền | Gần như mọi capability và thiết bị host — gần như không còn cô lập. |
| no-new-privileges | Cấm leo thang đặc quyền | Kernel bỏ qua setuid/setgid trong container. |
| Read-only root filesystem | Filesystem gốc chỉ đọc | Container không ghi được trừ tmpfs/volume mở riêng. |
| Rootless mode | Chế độ không root | Chạy cả daemon lẫn container bằng user thường. |
| CVE / severity / fixed version | Mã lỗ hổng / mức độ / bản đã vá | Định danh lỗ hổng, độ nghiêm trọng, phiên bản đã sửa. |
| False positive | Dương tính giả | Công cụ báo lỗ hổng không có thật. |
| SBOM | Danh sách thành phần phần mềm | Kê khai mọi gói/thư viện trong image. |
| jlink | Tạo runtime Java tối thiểu | JRE chỉ chứa module app cần. |
| Pin digest | Ghim theo mã băm | Tham chiếu image bằng `@sha256:...`. |
| BuildKit secret mount | Gắn secret lúc build | Secret chỉ có trong một lệnh `RUN`, không vào layer. |
| Hadolint | Công cụ lint Dockerfile | Cảnh báo thực hành chưa tốt. |
| Defense in depth | Phòng thủ nhiều lớp | Nhiều biện pháp chồng lên nhau. |

## Xử lý sự cố (bài 08)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Exit code 125/126/127/137/139/143 | Mã thoát | Docker lỗi / không thực thi được / không tìm thấy lệnh / SIGKILL / SIGSEGV / SIGTERM. |
| Health log | Nhật ký healthcheck | 5 lần kiểm tra gần nhất trong `.State.Health`. |
| Log driver json-file | Trình ghi log mặc định | Lưu stdout/stderr thành file JSON; mặc định không giới hạn kích thước. |
| Network namespace sharing | Chung không gian mạng | `--network container:<tên>` — container phụ dùng mạng của container đích để debug. |
| `docker events` | Dòng sự kiện | Luồng sự kiện của daemon: create/start/die/oom/health_status. |
| `exec format error` | Lỗi định dạng thực thi | Chạy image khác kiến trúc CPU (amd64 vs arm64). |
