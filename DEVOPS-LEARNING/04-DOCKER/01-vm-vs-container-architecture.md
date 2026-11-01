# 01. VM vs Container & kiến trúc Docker

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Linux 01 — Kiến trúc & Filesystem](../01-LINUX/01-linux-architecture-filesystem.md), [Linux 04 — Processes & systemd](../01-LINUX/04-processes-systemd.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL Integration — xem [README module §3](README.md#3-môi-trường-docker-desktop--wsl-hoạt-động-thế-nào)), `[Container]` bên trong container

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

- Giải thích được container giải quyết vấn đề gì, và **khác máy ảo (VM) ở đâu** — bằng sơ đồ và bằng lệnh chứng minh.
- Hiểu container = **process Linux** + **namespace** (cô lập cái nó *nhìn thấy*) + **cgroup** (giới hạn cái nó *được dùng*).
- Mô tả chuỗi thành phần khi bạn gõ `docker run`: CLI → `dockerd` → `containerd` → `runc` → process.
- Biết vòng đời của container: created, running, paused, exited, removed.
- Giới hạn RAM/CPU cho container và nhận ra container bị kernel giết vì hết bộ nhớ (exit code `137`).

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Container cứ chạy được vài phút là chết, exit code 137" | 137 = 128 + 9 (SIGKILL) — thường do vượt giới hạn RAM của cgroup ([Linux bài 04](../01-LINUX/04-processes-systemd.md)) |
| "Sao trong container `free -h` báo 16GB mà app lại bị kill ở 512MB?" | Namespace không che thông tin RAM của host; giới hạn thật nằm ở **cgroup** |
| Sếp hỏi: "Sao không chạy mỗi app một VM cho an toàn?" | So sánh chi phí, tốc độ khởi động, mức cô lập giữa VM và container |
| "Container có cần cài kernel không? Image Ubuntu có chạy trên host CentOS được không?" | Container dùng chung kernel host — image chỉ mang userspace |
| Kubernetes báo lỗi liên quan tới `containerd` | Hiểu Docker chỉ là một trong nhiều công cụ dùng chung chuẩn OCI |

Không hiểu bản chất, bạn sẽ coi container là "hộp đen" và debug bằng cách thử-sai. Hiểu bản chất, mọi lỗi container đều quy về những thứ bạn đã học: **process, signal, filesystem, network, quyền**.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Vấn đề "chạy trên máy tôi"

Ứng dụng `taskhub` cần: Java 21 (đúng bản), biến môi trường kết nối database, user không phải root, thư mục log có quyền ghi… Ở [Lab 02 Linux](../01-LINUX/labs/lab-02-java-systemd-service.md), bạn đã làm tay toàn bộ việc đó. Giờ tưởng tượng:

- Đồng nghiệp dùng Java 17 → app lỗi.
- Server production cài thêm một thư viện hệ thống khác phiên bản → app lỗi theo kiểu khác.
- Mỗi lần thêm server, phải làm lại từng bước bằng tay.

Hai cách giải quyết lịch sử:

1. **Máy ảo (Virtual Machine — VM)**: đóng gói **cả một hệ điều hành** (kernel + userspace + app). Chắc chắn giống nhau, nhưng nặng (vài GB), khởi động mất hàng chục giây đến vài phút.
2. **Container**: đóng gói **chỉ userspace + app**, dùng chung kernel với máy chủ. Nhẹ (vài chục đến vài trăm MB), khởi động trong khoảng một giây.

### 3.2. Nhắc lại: kernel và userspace

Từ [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md#32-ba-lớp-của-linux): kernel quản lý phần cứng; mọi chương trình (bash, java, nginx) chạy ở userspace và nhờ kernel qua system call.

Ý tưởng then chốt của container: **nếu kernel có thể "nói dối" một process về thế giới xung quanh nó** — chỉ cho nó thấy một số process, một filesystem riêng, một card mạng riêng — thì process đó **tưởng** mình đang ở một máy riêng. Đó chính là container.

### 3.3. Bạn đã thấy điều này rồi

Ở [Linux bài 01, Bước 7](../01-LINUX/01-linux-architecture-filesystem.md#bước-7--so-sánh-với-container-sandbox) bạn đã quan sát:

- `uname -r` trong container **giống hệt** WSL → dùng chung kernel.
- Container có `/etc/os-release` riêng, không thấy `/mnt/c`, chỉ có 1–2 process → filesystem riêng, danh sách process riêng.

Bài này giải thích **cơ chế** tạo ra những điều đó.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 VM và container khác nhau thế nào?

| Tiêu chí | Máy ảo (VM) | Container |
|---|---|---|
| Đóng gói gì | Kernel + hệ điều hành đầy đủ + app | Userspace tối thiểu + app |
| Kernel | Mỗi VM một kernel riêng | **Dùng chung kernel host** |
| Thành phần cô lập | **Hypervisor** (trình quản lý máy ảo — VMware ESXi, KVM, Hyper-V) giả lập phần cứng | Tính năng của kernel Linux: namespace + cgroup |
| Kích thước điển hình | Vài GB | Vài chục – vài trăm MB |
| Thời gian khởi động | Hàng chục giây – phút | Mili giây – vài giây |
| Mức cô lập | Rất mạnh (lỗi kernel VM không ảnh hưởng VM khác) | Yếu hơn: lỗ hổng kernel có thể ảnh hưởng mọi container trên host |
| Chạy hệ điều hành khác | Được (Windows VM trên host Linux) | Container Linux cần kernel Linux |
| Dùng khi | Cần cô lập mạnh, khác hệ điều hành, hạ tầng truyền thống | Đóng gói và triển khai ứng dụng, microservice, CI/CD |

> **Container và VM không loại trừ nhau.** Trên AWS, EC2 là VM; bạn chạy container **bên trong** EC2. Docker Desktop trên máy bạn cũng chạy Docker Engine **bên trong** VM của WSL 2. Module 11 sẽ bàn thêm về ảo hóa.

### 4.2. 🟥 Container = process + namespace + cgroup

Một container, xét từ phía kernel, chỉ là **một (hoặc vài) process bình thường** được gắn thêm hai thứ:

| Cơ chế | Câu hỏi nó trả lời | Ví von |
|---|---|---|
| **Namespace** (không gian tên) | Process này **nhìn thấy** gì? | Rèm che: chỉ thấy phần thế giới được phép thấy |
| **cgroup** (control group — nhóm kiểm soát) | Process này **được dùng** bao nhiêu tài nguyên? | Đồng hồ điện có cầu dao: vượt mức thì ngắt |

Thêm vào đó là một **filesystem gốc riêng** (lấy từ image — bài 02) để process thấy `/` của riêng nó.

### 4.3. 🟥 Các loại namespace

| Namespace | Cô lập cái gì | Hệ quả bạn thấy trong container |
|---|---|---|
| `pid` | Danh sách process | App của bạn là **PID 1**; `ps` chỉ thấy process trong container |
| `net` | Card mạng, IP, bảng route, port | Container có `eth0` và IP riêng (ví dụ `172.17.0.2`); hai container cùng nghe port 80 không đụng nhau |
| `mnt` | Điểm mount, cây thư mục | `/` là filesystem của image, không thấy file của host |
| `uts` | Hostname | `hostname` trả về ID container |
| `ipc` | Bộ nhớ chia sẻ, hàng đợi thông điệp giữa process | Ít gặp ở mức Junior |
| `user` | Ánh xạ UID/GID | Root trong container có thể không phải root ngoài host (Docker mặc định **không** bật — bài 07) |
| `cgroup` | Cây cgroup nhìn thấy được | Container thấy cgroup của nó như gốc |

> **Điều namespace KHÔNG cô lập:** kernel, thời gian hệ thống, và một số thông tin trong `/proc` như `/proc/meminfo`. Vì vậy `free -h` trong container hiện RAM của **cả máy** chứ không phải giới hạn của container — một cái bẫy kinh điển khi debug Java bị OOM.

### 4.4. 🟥 cgroup: giới hạn tài nguyên

Ở [Linux bài 04](../01-LINUX/04-processes-systemd.md), bạn đã biết systemd dùng cgroup để gom process của một service. Docker dùng đúng cơ chế đó để giới hạn container:

| Tài nguyên | Tùy chọn `docker run` | Khi vượt giới hạn |
|---|---|---|
| RAM | `--memory 512m` (`-m`) | Kernel **OOM killer** giết process trong container → exit code **137** |
| Swap | `--memory-swap` (đặt bằng `--memory` = không cho swap) | — |
| CPU | `--cpus 1.5` | Process bị **làm chậm lại** (throttle), không bị giết |
| Số process | `--pids-limit 100` | Không tạo thêm process được (`fork` thất bại) |

Lưu ý quan trọng: **RAM vượt mức → chết; CPU vượt mức → chậm.** Đây là lý do triệu chứng của hai loại thiếu tài nguyên rất khác nhau.

Theo [tài liệu Docker về giới hạn tài nguyên](https://docs.docker.com/engine/containers/resource_constraints/), mặc định container **không bị giới hạn** — có thể dùng hết RAM/CPU của máy. Trên production, luôn đặt giới hạn.

### 4.5. 🟥 Kiến trúc Docker: chuyện gì xảy ra khi gõ `docker run`

Docker không phải một chương trình duy nhất, mà là một chuỗi thành phần:

| Thành phần | Vai trò |
|---|---|
| **Docker CLI** (`docker`) | Client: nhận lệnh bạn gõ, gửi yêu cầu qua REST API |
| **dockerd** (Docker daemon) | Server chính: quản lý image, network, volume; nhận API qua socket `/var/run/docker.sock` |
| **containerd** | Quản lý vòng đời container ở mức thấp hơn: kéo image, tạo/xóa container |
| **containerd-shim** | Process trung gian giữ container sống kể cả khi containerd khởi động lại |
| **runc** | Công cụ nhỏ thực sự gọi kernel tạo namespace + cgroup rồi chạy process của bạn, sau đó thoát |

Hai chuẩn **OCI** (Open Container Initiative — sáng kiến container mở) giúp mọi công cụ dùng chung:

- **OCI Image Spec**: định dạng image. Image build bằng Docker chạy được trên Podman, containerd, Kubernetes.
- **OCI Runtime Spec**: cách chạy container. `runc` là bản cài đặt tham chiếu.

> 🟦 **Docker không phải là duy nhất.** **Podman** chạy container không cần daemon. **Kubernetes** từ lâu đã nói chuyện thẳng với **containerd** (không cần dockerd). Nhờ chuẩn OCI, image bạn build bằng Docker vẫn chạy được ở đó. Đây là lý do khi đọc tài liệu Kubernetes, bạn sẽ thấy `containerd` nhiều hơn `docker`.

> **Socket `/var/run/docker.sock` là cửa quyền lực.** Ai gửi được lệnh vào socket này thì điều khiển được Docker — tức là có quyền tương đương root trên host. Đó là lý do nhóm `docker` tương đương root ([Linux bài 03](../01-LINUX/03-permissions-users-groups.md)) và không bao giờ mount socket này vào container lạ (bài 07).

### 4.6. 🟥 Vòng đời container

| Trạng thái | Nghĩa | Đến từ lệnh |
|---|---|---|
| `created` | Đã tạo (có filesystem, cấu hình) nhưng process chưa chạy | `docker create` |
| `running` | Process chính đang chạy | `docker start`, `docker run` (= create + start) |
| `paused` | Process bị đóng băng (cgroup freezer), vẫn giữ RAM | `docker pause` / `docker unpause` |
| `exited` | Process chính đã kết thúc — container **vẫn còn** (log, filesystem ghi được) | Process tự thoát, `docker stop`, `docker kill` |
| (đã xóa) | Mọi thứ của container biến mất | `docker rm` |

Quy tắc quan trọng nhất: **container sống khi và chỉ khi process PID 1 của nó còn sống.** App thoát → container `exited`. Đây là nguyên nhân của câu hỏi muôn thuở "sao container của tôi chạy xong là tắt ngay?" — vì process chính đã chạy xong.

### 4.7. 🟨 Docker Desktop: process container nằm ở đâu?

Trên **server Linux thật**, chạy `ps aux` trên host sẽ thấy process `nginx` của container như mọi process khác — vì container chỉ là process.

Trên **máy bạn**, Docker Engine chạy trong distro `docker-desktop` (xem [README §3](README.md#31-kiến-trúc-trên-máy-bạn)), **không phải** trong Ubuntu. Nên `ps aux` trong Ubuntu **không thấy** process container. Cách quan sát đúng:

- `docker top <container>` — hỏi Docker Engine danh sách process của container.
- `docker inspect --format '{{.State.Pid}}' <container>` — PID của process chính **nhìn từ phía host của Engine**.
- 🟨 `docker run --rm -it --pid=host alpine ps aux` — chạy một container **dùng chung namespace PID với host của Engine** để nhìn thấy mọi process ở đó, kể cả process của các container khác.

---

## 5. Ví dụ thực tế

### Ví dụ 1: Java bị OOM trong container

Một team chạy Spring Boot với `--memory 512m`. App chết sau vài giờ, `docker ps -a` hiện `Exited (137)`. Người mới tìm lỗi trong log Java — không thấy gì, vì **kernel giết process bằng SIGKILL**, app không kịp ghi log. Người có kinh nghiệm:

1. Thấy 137 = 128 + 9 → SIGKILL.
2. `docker inspect --format '{{.State.OOMKilled}}' taskhub` → `true` → vượt giới hạn RAM cgroup.
3. Kiểm tra cấu hình heap Java so với giới hạn container (JVM hiện đại tự nhận biết giới hạn cgroup, nhưng heap + bộ nhớ ngoài heap vẫn có thể vượt mức).

### Ví dụ 2: Hai app cùng nghe port 8080 trên một server

Không có container: app thứ hai báo `Address already in use`. Có container: mỗi container có **network namespace riêng** nên cả hai cùng nghe `8080` bên trong được. Chỉ khi **publish** ra host mới cần hai port host khác nhau (`-p 8081:8080`, `-p 8082:8080`) — bài 02.

### Ví dụ 3: "Image Ubuntu chạy trên host Amazon Linux có được không?"

Được. Image `ubuntu:22.04` chỉ chứa userspace của Ubuntu (bash, apt, thư viện). Khi chạy trên EC2 Amazon Linux, process dùng kernel của Amazon Linux. Điều duy nhất cần khớp là **kiến trúc CPU** (`x86_64` vs `aarch64` — nhắc lại `uname -m` ở Linux bài 01).

### Gặp lại ở đâu

| Khái niệm | Gặp lại |
|---|---|
| cgroup giới hạn RAM/CPU | `resources.limits` của Pod Kubernetes (Module 09), task size của ECS |
| PID 1, signal, exit code 137/143 | Pod bị `OOMKilled`, graceful shutdown khi deploy (Module 05, 09) |
| containerd, OCI | Node Kubernetes dùng containerd (Module 09) |
| Container chạy trong VM | Container trên EC2 (Module 06), runner GitHub Actions (Module 05) |

---

## 6. Sơ đồ kiến trúc

### 6.1. VM và container

```text
        MÁY ẢO (VM)                              CONTAINER
 ┌──────────┐ ┌──────────┐            ┌──────────┐ ┌──────────┐ ┌──────────┐
 │  App A   │ │  App B   │            │  App A   │ │  App B   │ │  App C   │
 │ Thư viện │ │ Thư viện │            │ Thư viện │ │ Thư viện │ │ Thư viện │
 │ Guest OS │ │ Guest OS │            └────┬─────┘ └────┬─────┘ └────┬─────┘
 │ (kernel) │ │ (kernel) │                 │ namespace + cgroup      │
 └────┬─────┘ └────┬─────┘            ┌────▼────────────▼────────────▼─────┐
 ┌────▼────────────▼─────┐            │  Container runtime (containerd/runc) │
 │      Hypervisor        │            ├──────────────────────────────────────┤
 ├────────────────────────┤            │    Hệ điều hành host (MỘT kernel)    │
 │   Phần cứng / Host OS  │            ├──────────────────────────────────────┤
 └────────────────────────┘            │              Phần cứng               │
                                       └──────────────────────────────────────┘
  Mỗi VM: một kernel riêng             Mọi container: dùng chung một kernel
```

### 6.2. Chuỗi thành phần khi chạy `docker run nginx:1.30-alpine`

```text
 [WSL Ubuntu]                         [distro docker-desktop — host của Engine]
  docker run ...  ──REST API qua──►  dockerd
   (CLI)            socket            │ (1) có image chưa? chưa → kéo từ registry
                                      ▼
                                    containerd
                                      │ (2) chuẩn bị filesystem từ các layer image
                                      ▼
                                    containerd-shim ──► runc
                                                         │ (3) tạo namespace + cgroup
                                                         │ (4) exec "nginx" thành PID 1
                                                         ▼   rồi runc thoát
                                                    ┌──────────────────────┐
                                                    │ process nginx        │
                                                    │ PID 1 (trong ns pid) │
                                                    │ eth0 172.17.0.2      │
                                                    └──────────────────────┘
```

### 6.3. Vòng đời

```text
            docker create          docker start
   (image) ───────────────► created ───────────► running ◄──── docker unpause
                                                  │  │  │
                                     docker pause │  │  └─────► paused
                                                  │  │
              process tự thoát / docker stop / kill │
                                                  ▼
                              docker start ◄── exited ── docker rm ──► (đã xóa)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `docker version`, `docker info` | Kiểm tra CLI, Engine, cấu hình | 🟥 |
| `docker run` | Tạo + chạy container | 🟥 |
| `docker ps`, `docker ps -a` | Liệt kê container đang chạy / tất cả | 🟥 |
| `docker top` | Process bên trong một container | 🟥 |
| `docker inspect --format` | Lấy một thông tin cụ thể (PID, trạng thái, exit code, OOMKilled) | 🟥 |
| `docker stats` | Theo dõi CPU/RAM của container theo thời gian thực | 🟥 |
| `docker create`, `start`, `pause`, `unpause`, `stop`, `kill`, `rm` | Điều khiển vòng đời | 🟥 |
| `--memory`, `--memory-swap`, `--cpus`, `--pids-limit` | Giới hạn tài nguyên (cgroup) | 🟥 |
| `--pid=host` | Dùng chung namespace PID với host (chỉ để quan sát/debug) | 🟨 |

Bài 02 sẽ đi sâu `run`, `logs`, `exec`, `rm`, `inspect`, image. Bài này tập trung vào **chứng minh bản chất**.

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu dưới đây là **minh họa** trên Docker Desktop + WSL. ID container, IP, phiên bản kernel trên máy bạn sẽ khác — **cấu trúc** mới là thứ cần hiểu.

### `docker version` — client và server

```bash
docker version
```

```text
Client:
 Version:           28.x.x
 API version:       1.5x
 OS/Arch:           linux/amd64
 Context:           default

Server: Docker Desktop 4.xx.x
 Engine:
  Version:          28.x.x
  OS/Arch:          linux/amd64
 containerd:
  Version:          1.7.x
 runc:
  Version:          1.x.x
```

Để ý: phần **Server** liệt kê đúng các thành phần ở mục 4.5 — Engine (dockerd), containerd, runc. Nếu chỉ có phần Client và báo lỗi kết nối → Engine chưa chạy.

### `docker run` với các cờ của bài này

```bash
docker run -d --name web nginx:1.30-alpine
```

| Tham số | Ý nghĩa |
|---|---|
| `-d` | Detached — chạy nền, trả lại dấu nhắc lệnh, in ID container |
| `--name web` | Đặt tên dễ nhớ thay cho tên ngẫu nhiên |
| `nginx:1.30-alpine` | Image và tag (bài 02) |

```bash
docker run --rm alpine:3.20 uname -r
```

| Tham số | Ý nghĩa |
|---|---|
| `--rm` | Xóa container ngay khi process chính kết thúc |
| `alpine:3.20` | Image Alpine Linux rất nhỏ (~vài MB) — tiện cho thí nghiệm |
| `uname -r` | Lệnh chạy làm process chính (ghi đè lệnh mặc định của image) |

### `docker top` — process trong container

```bash
docker top web
```

```text
UID     PID     PPID    C   STIME   TTY   TIME       CMD
root    2541    2519    0   09:12   ?     00:00:00   nginx: master process nginx -g daemon off;
101     2589    2541    0   09:12   ?     00:00:00   nginx: worker process
101     2590    2541    0   09:12   ?     00:00:00   nginx: worker process
```

Các PID ở đây là PID **nhìn từ host của Engine**, không phải PID trong container. Bên trong container, master process là PID 1.

### `docker inspect --format` — lấy đúng thông tin cần

```bash
docker inspect --format '{{.State.Status}} pid={{.State.Pid}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' web
```

```text
running pid=2541 exit=0 oom=false
```

`--format` dùng cú pháp Go template: `{{.State.Pid}}` đi vào khóa `State` rồi lấy `Pid` trong JSON mà `docker inspect` trả về. Không có `--format`, bạn nhận cả một JSON dài — bài 02 sẽ khám phá.

### `docker stats` — tài nguyên theo thời gian thực

```bash
docker stats --no-stream
```

```text
CONTAINER ID   NAME   CPU %   MEM USAGE / LIMIT     MEM %   NET I/O       BLOCK I/O   PIDS
3f2a9c1d7e44   web    0.00%   7.8MiB / 7.7GiB       0.10%   1.2kB / 0B    0B / 0B     3
```

| Cột | Ý nghĩa |
|---|---|
| `MEM USAGE / LIMIT` | RAM đang dùng / giới hạn. Không đặt `--memory` → LIMIT là RAM Engine thấy (của VM WSL) |
| `CPU %` | 100% = một nhân CPU. Container dùng 2 nhân đầy có thể hiện 200% |
| `PIDS` | Số process/thread trong container |
| `--no-stream` | In một lần rồi thoát (bỏ đi để theo dõi liên tục, Ctrl+C để dừng) |

### Giới hạn tài nguyên

```bash
docker run -d --name limited --memory 64m --memory-swap 64m --cpus 0.5 nginx:1.30-alpine
docker stats --no-stream limited
```

```text
NAME      CPU %   MEM USAGE / LIMIT   MEM %
limited   0.00%   3.1MiB / 64MiB      4.84%
```

| Tham số | Ý nghĩa |
|---|---|
| `--memory 64m` | Giới hạn cứng 64 MiB RAM |
| `--memory-swap 64m` | Tổng RAM + swap = 64 MiB → không cho dùng swap, vượt RAM là bị giết ngay |
| `--cpus 0.5` | Tối đa nửa nhân CPU |

### Vòng đời: `create`, `start`, `pause`, `stop`, `kill`, `rm`

```bash
docker create --name demo alpine:3.20 sleep 300
docker ps -a --filter name=demo --format '{{.Names}}: {{.Status}}'
docker start demo
docker pause demo
docker ps --filter name=demo --format '{{.Names}}: {{.Status}}'
docker unpause demo
docker stop demo
docker ps -a --filter name=demo --format '{{.Names}}: {{.Status}}'
docker rm demo
```

```text
demo: Created
demo: Up 2 seconds (Paused)
demo: Exited (137) 1 second ago
```

Vì sao `docker stop` lại cho exit **137** ở đây? `docker stop` gửi SIGTERM, chờ **10 giây** rồi mới gửi SIGKILL ([tài liệu `docker stop`](https://docs.docker.com/reference/cli/docker/container/stop/)). `sleep` chạy làm PID 1 trong container **không xử lý SIGTERM** (PID 1 bị kernel bỏ qua các signal mà nó không đăng ký xử lý), nên phải chờ đủ 10 giây và bị SIGKILL → 137. Đây là hiện tượng thật sẽ quay lại ở bài 02 và bài 03 (vì sao dùng exec form trong Dockerfile).

| Lệnh | Signal / hành động |
|---|---|
| `docker stop` | SIGTERM → chờ (mặc định 10s, đổi bằng `-t`) → SIGKILL |
| `docker kill` | SIGKILL ngay (đổi bằng `-s`) |
| `docker pause` | Đóng băng bằng cgroup freezer — process không nhận signal nào cả |
| `docker rm` | Xóa container đã dừng. ⚠️ `docker rm -f` dừng (SIGKILL) **và** xóa container đang chạy |

---

## 9. Bài thực hành từng bước

**Lab: Chứng minh "container là process bị cô lập"** · `[WSL]` + `[Container]` · ~75 phút

Ghi câu trả lời vào `~/devops-lab/04-docker/lab01-answers.md`, cuối lab commit vào `~/devops-journey/week07/`.

### Bước 1 — Kiểm tra môi trường

```bash
docker version
docker run --rm hello-world
```

❓ Ghi lại phiên bản Engine, containerd, runc.

### Bước 2 — So sánh kernel, hostname, hệ điều hành

```bash
# Trên WSL
uname -r; hostname; grep PRETTY_NAME /etc/os-release

# Trong container
docker run --rm alpine:3.20 sh -c 'uname -r; hostname; grep PRETTY_NAME /etc/os-release'
docker run --rm ubuntu:22.04 sh -c 'uname -r; hostname; grep PRETTY_NAME /etc/os-release'
```

❓ Kernel của 3 nơi có giống nhau không? Hostname và hệ điều hành thì sao? Namespace nào tạo ra khác biệt về hostname? Về `/etc/os-release`?

### Bước 3 — Namespace PID: app là PID 1

```bash
docker run --rm alpine:3.20 ps aux
docker run --rm alpine:3.20 sh -c 'echo "PID của shell: $$"; sleep 1 & ps'
```

❓ Container thấy bao nhiêu process? Process nào là PID 1? So với `ps aux | wc -l` trên WSL.

### Bước 4 — Namespace net: card mạng riêng

```bash
ip -4 addr show eth0                              # trên WSL
docker run --rm alpine:3.20 ip -4 addr show eth0  # trong container
docker run --rm alpine:3.20 ip route
```

❓ IP của container thuộc dải nào? Default gateway của container là gì? (Nối với [Network bài 04](../02-NETWORKING/04-routing-nat-switching.md): container ra Internet qua NAT của host.)

### Bước 5 — Process container nằm ở đâu?

```bash
docker run -d --name web nginx:1.30-alpine
ps aux | grep -c "[n]ginx"                       # trên WSL: có thấy nginx không?
docker top web
docker inspect --format 'PID trên host của Engine: {{.State.Pid}}' web
docker exec web ps                               # nhìn từ BÊN TRONG container
docker run --rm --pid=host alpine:3.20 ps aux | grep "[n]ginx"
```

❓ `ps aux` trên WSL có thấy nginx không? Vì sao (gợi ý: [README §3.1](README.md#31-kiến-trúc-trên-máy-bạn))? Lệnh cuối cùng cho thấy điều gì về bản chất của container? PID của master nginx trong container và ngoài host khác nhau thế nào?

### Bước 6 — Hai container cùng nghe port 80

```bash
docker run -d --name web2 nginx:1.30-alpine
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
docker exec web  sh -c 'netstat -tln 2>/dev/null || ss -tln'
docker exec web2 sh -c 'netstat -tln 2>/dev/null || ss -tln'
```

❓ Cả hai cùng nghe port 80 mà không lỗi `Address already in use` — vì sao? Từ máy bạn đã truy cập được chúng chưa (gợi ý: chưa publish port — bài 02)?

### Bước 7 — cgroup giới hạn CPU

```bash
docker run -d --name cpuhog --cpus 0.5 alpine:3.20 sh -c 'while :; do :; done'
docker stats --no-stream cpuhog
docker exec cpuhog cat /sys/fs/cgroup/cpu.max 2>/dev/null
docker rm -f cpuhog      # ⚠️ dừng và xóa ngay
```

❓ `CPU %` dừng ở khoảng bao nhiêu dù vòng lặp vô hạn? `cpu.max` cho thấy gì? (Nếu file không tồn tại, máy bạn có thể dùng cgroup v1 — ghi chú lại.)

### Bước 8 — cgroup giới hạn RAM và OOM

```bash
docker run --name oomtest --memory 64m --memory-swap 64m python:3.12-slim \
  python -c "x = bytearray(200 * 1024 * 1024); print('cấp phát xong')"
echo "exit code của docker run: $?"
docker inspect --format 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' oomtest
docker logs oomtest
docker rm oomtest
```

❓ Có dòng "cấp phát xong" không? Exit code bao nhiêu, phân tích 128 + ? Trường `OOMKilled`? Log có thông báo lỗi nào từ Python không — vì sao?

### Bước 9 — Vòng đời và signal

Làm lại chuỗi lệnh ở mục 8 phần "Vòng đời", đo thời gian `docker stop`:

```bash
docker run -d --name sleeper alpine:3.20 sleep 300
time docker stop sleeper
docker ps -a --filter name=sleeper --format '{{.Status}}'

docker run -d --name web3 nginx:1.30-alpine
time docker stop web3
docker ps -a --filter name=web3 --format '{{.Status}}'
```

❓ `docker stop` mất bao lâu với mỗi container? Exit code mỗi container là bao nhiêu? Giải thích sự khác nhau (gợi ý: nginx có xử lý SIGTERM — [Linux bài 04](../01-LINUX/04-processes-systemd.md)).

### Bước 10 — Dọn dẹp và commit

```bash
docker rm -f web web2 web3 sleeper limited 2>/dev/null   # ⚠️ xóa các container của lab
docker ps -a
cd ~/devops-journey && mkdir -p week07
cp ~/devops-lab/04-docker/lab01-answers.md week07/
git add week07/lab01-answers.md
git commit -m "docs(docker): lab 01 - container is an isolated process"
git push
```

---

## 10. Kết quả mong đợi

- **Bước 2:** kernel giống nhau ở cả 3 nơi (dùng chung kernel). Hostname trong container là chuỗi ID ngắn (namespace `uts`). `/etc/os-release` là của image (namespace `mnt` + filesystem của image).
- **Bước 3:** container chỉ thấy vài process; PID 1 là chính lệnh bạn chạy (`ps` hoặc `sh`).
- **Bước 4:** IP container thường thuộc `172.17.0.0/16`, gateway `172.17.0.1` (mạng bridge mặc định — bài 04).
- **Bước 5:** `ps aux` trên WSL **không** thấy nginx (Engine chạy trong distro khác). `--pid=host` thấy nginx như **process bình thường** với PID khác — chứng minh container chỉ là process được cô lập. Master nginx là PID 1 bên trong, nhưng là một PID lớn bên ngoài.
- **Bước 6:** mỗi container có network namespace riêng → port 80 riêng. Chưa publish nên từ Windows/WSL chưa truy cập bằng `localhost` được.
- **Bước 7:** `CPU %` dao động quanh **50%**; `cpu.max` dạng `50000 100000` (được 50 ms mỗi 100 ms).
- **Bước 8:** không có dòng "cấp phát xong", exit code **137** = 128 + 9 (SIGKILL), `OOMKilled=true`, log không có lỗi Python vì process bị kernel giết **trước khi** kịp in gì.
- **Bước 9:** `sleeper` mất ~10 giây, exit 137 (bị SIGKILL sau khi hết thời gian chờ). `web3` dừng gần như ngay, exit 0 (nginx nhận SIGTERM và tắt nhẹ nhàng).

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `Cannot connect to the Docker daemon at unix:///var/run/docker.sock` | (1) Docker Desktop chưa chạy; **hoặc** (2) Docker Desktop đang chạy (lệnh `docker` trong PowerShell vẫn chạy) nhưng WSL Integration cho distro Ubuntu đang **tắt** — lệnh `docker` trong Ubuntu vẫn còn (`ls -l /usr/bin/docker` trỏ vào `/mnt/wsl/docker-desktop/...`) nhưng không có `/var/run/docker.sock` | (1) Mở Docker Desktop, chờ *Engine running*. (2) Kiểm tra `ls -l /var/run/docker.sock` trong WSL; không có → Docker Desktop → **Settings → Resources → WSL Integration** → bật distro Ubuntu → **Apply**, rồi mở terminal WSL mới |
| `docker: command not found` trong Ubuntu | Chưa bật WSL Integration cho distro | Docker Desktop → Settings → Resources → WSL Integration → bật Ubuntu → Apply |
| `permission denied while trying to connect to the Docker daemon socket` | User không có quyền với socket (hay gặp trên server Linux thật) | Trên EC2: thêm user vào nhóm `docker` (hiểu rõ rủi ro — tương đương root) hoặc dùng `sudo` |
| Container `Exited (0)` ngay sau khi chạy | Process chính chạy xong (ví dụ `docker run ubuntu:22.04` không có lệnh giữ chạy) | Đúng như thiết kế. Container sống khi PID 1 còn sống |
| `Exited (137)` không có log lỗi | OOM (vượt `--memory`) hoặc bị SIGKILL do `docker stop` hết thời gian chờ | Kiểm tra `OOMKilled` bằng `docker inspect` |
| `docker stop` mất đúng 10 giây | PID 1 không xử lý SIGTERM | Bài 03: dùng exec form `ENTRYPOINT ["java", ...]`; app phải xử lý SIGTERM |
| `Conflict. The container name "/web" is already in use` | Đã có container (kể cả đã dừng) trùng tên | `docker ps -a`, xóa container cũ hoặc đặt tên khác |
| `ps aux` trên WSL không thấy process container | Engine chạy trong distro `docker-desktop` | Dùng `docker top`, `docker exec ... ps`, hoặc `--pid=host` |

---

## 12. Đọc log và xử lý lỗi

Với container, "log" có 3 nguồn — học cách chọn đúng nguồn:

| Nguồn | Lệnh | Cho biết |
|---|---|---|
| Output của process chính (stdout/stderr) | `docker logs <container>` | App nói gì: lỗi khởi động, exception… |
| Trạng thái do Engine ghi nhận | `docker inspect --format '{{json .State}}' <container>` | Exit code, OOMKilled, thời điểm bắt đầu/kết thúc, lỗi khởi tạo |
| Sự kiện của Engine | `docker events --since 10m` | Chuỗi sự kiện: create, start, die, oom, kill… |

Ví dụ đọc trạng thái của container bị OOM:

```bash
docker inspect --format '{{json .State}}' oomtest
```

```json
{"Status":"exited","Running":false,"Paused":false,"Restarting":false,
 "OOMKilled":true,"Dead":false,"Pid":0,"ExitCode":137,"Error":"",
 "StartedAt":"2026-11-15T09:30:01.1Z","FinishedAt":"2026-11-15T09:30:02.4Z"}
```

Cách đọc:

- `ExitCode: 137` → 128 + 9 → SIGKILL ([Linux bài 04](../01-LINUX/04-processes-systemd.md)).
- `OOMKilled: true` → người giết là OOM killer của kernel vì vượt giới hạn cgroup.
- `StartedAt` → `FinishedAt` chỉ ~1 giây → chết ngay khi khởi động, không phải sau một thời gian dài (gợi ý về nguyên nhân: cấp phát lớn ngay từ đầu vs rò rỉ bộ nhớ dần).
- `Error` có nội dung → lỗi do Engine không tạo được container (ví dụ không tìm thấy lệnh) — khác với lỗi của app.

**Bảng exit code hay gặp ở container:**

| Exit code | Nghĩa thường gặp |
|---|---|
| `0` | Process kết thúc bình thường |
| `1` | App tự báo lỗi (exception không bắt, lỗi cấu hình) — xem `docker logs` |
| `125` | Lỗi của chính lệnh `docker run` (tham số sai…) |
| `126` | Lệnh tồn tại nhưng không chạy được (thiếu quyền thực thi) |
| `127` | Không tìm thấy lệnh trong container |
| `137` | SIGKILL — OOM hoặc `docker stop` hết thời gian chờ, hoặc `docker kill` |
| `143` | SIGTERM — dừng bình thường bằng `docker stop` và app thoát với mã 128 + 15 |

Quy trình 4 bước của [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md#12-đọc-thông-báo-lỗi-và-xử-lý) vẫn áp dụng nguyên vẹn — chỉ thêm `docker logs` và `docker inspect` vào bước "kiểm tra giả thuyết". Bài 08 sẽ dạy quy trình đầy đủ cho container.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Container giải quyết vấn đề gì mà cài đặt trực tiếp lên server không giải quyết được?
2. Nêu 4 khác biệt giữa VM và container. Khi nào bạn vẫn chọn VM?
3. "Container là một máy ảo nhẹ" — câu này sai ở đâu?
4. Namespace và cgroup khác nhau thế nào? Mỗi cái trả lời câu hỏi gì?
5. Kể tên 4 loại namespace và hệ quả quan sát được của mỗi loại.
6. Vì sao `free -h` trong container có thể báo sai lượng RAM container được dùng?
7. Container vượt giới hạn RAM và vượt giới hạn CPU — triệu chứng khác nhau thế nào?
8. Mô tả chuỗi CLI → dockerd → containerd → runc khi chạy `docker run`.
9. OCI là gì và vì sao nó quan trọng khi chuyển từ Docker sang Kubernetes?
10. Vì sao truy cập được `/var/run/docker.sock` tương đương quyền root?
11. Container ở trạng thái `exited` còn lại những gì? Khi nào thì mất hẳn?
12. Vì sao `docker stop` với container chạy `sleep 300` mất 10 giây và trả exit 137?
13. Vì sao trên máy bạn `ps aux` trong Ubuntu không thấy process của container, còn trên EC2 thì thấy?
14. Image `ubuntu:22.04` chạy được trên host Amazon Linux không? Điều kiện cần khớp là gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/01-solutions.md](solutions/01-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Bảng so sánh của bạn.** Không nhìn bài, viết bảng so sánh VM và container gồm ít nhất 6 tiêu chí. Thêm một cột "Ví dụ trên AWS" cho mỗi tiêu chí.

**Bài 2 — Đếm namespace.** Dùng `docker run --rm --pid=host alpine:3.20 ...` hoặc `docker run --rm alpine:3.20 ls -l /proc/1/ns`, liệt kê các namespace của một process trong container. So sánh ID namespace (`net:[4026...]`) của hai container khác nhau và của một container chạy với `--network host`. Rút ra kết luận.

**Bài 3 — Giới hạn số process.** Chạy một container với `--pids-limit 20` và thử tạo nhiều process bên trong (gợi ý: vòng lặp `sleep 100 &` trong `sh`). Ghi lại thông báo lỗi và giải thích vì sao giới hạn này giúp chống "fork bomb".

**Bài 4 — Exit code detective.** Tạo ra **mỗi** exit code sau bằng một lệnh `docker run`: `0`, `1`, `125`, `126`, `127`, `137`, `143`. Với mỗi cái, ghi lệnh, exit code, và giải thích. (Gợi ý cho 143: cần một process biết thoát với mã 143 khi nhận SIGTERM — thử `sh -c 'trap "exit 143" TERM; sleep 300 & wait'`.)

**Bài 5 — Java và giới hạn RAM.** Chạy `docker run --rm --memory 256m eclipse-temurin:21-jre-noble java -XX:+PrintFlagsFinal -version | grep -E 'MaxHeapSize|UseContainerSupport'`, rồi chạy lại không có `--memory`. So sánh `MaxHeapSize`. JVM biết giới hạn của container bằng cách nào? Điều này quan trọng thế nào khi chạy `taskhub`?

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Vẽ lại được sơ đồ 6.1 và 6.2 không nhìn tài liệu, giải thích từng khối.
- [ ] Chứng minh được bằng lệnh: container dùng chung kernel, có PID 1 riêng, có IP riêng.
- [ ] Thấy `Exited (137)` là nghĩ ngay tới SIGKILL và kiểm tra `OOMKilled`.
- [ ] Giải thích được vì sao `docker stop` có lúc mất 10 giây.
- [ ] Giải thích được cho người khác vì sao "container không phải VM nhẹ".
- [ ] Làm xong Bài tập 2 và 4 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Docker docs — Get started workshop](https://docs.docker.com/get-started/workshop/) | Thực hành chính thức | 2026-10-31 |
| [Docker docs — Resource constraints](https://docs.docker.com/engine/containers/resource_constraints/) | `--memory`, `--memory-swap`, `--cpus`, OOM | 2026-10-31 |
| [Docker docs — `docker container stop`](https://docs.docker.com/reference/cli/docker/container/stop/) | SIGTERM, thời gian chờ 10 giây | 2026-10-31 |
| [Docker Desktop — WSL 2 backend](https://docs.docker.com/desktop/features/wsl/) | Kiến trúc Docker Desktop trên Windows | 2026-10-31 |
| [iximiuz Labs](https://labs.iximiuz.com/) | Thực hành sâu về container internals | 2026-10-31 |
