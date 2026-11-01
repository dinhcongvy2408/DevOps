# 08. Container Troubleshooting — Quy trình debug container

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Docker bài 01–07](README.md), [Linux 04 — Processes & systemd](../01-LINUX/04-processes-systemd.md), [Linux 07 — Logs & troubleshooting](../01-LINUX/07-logs-monitoring-troubleshooting.md), [Network 08 — Bộ công cụ chẩn đoán mạng](../02-NETWORKING/08-network-troubleshooting-tools.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop, `[Container]` container dùng xong bỏ

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

- Đi theo một **quy trình 7 bước có thứ tự** khi container "không chạy" thay vì đoán mò.
- Đọc **exit code** của container và suy ra ngay nhóm nguyên nhân (0, 1, 125, 126, 127, 137, 139, 143).
- Dùng `docker inspect` để xem trạng thái thật: `OOMKilled`, health log, biến môi trường, mount, network.
- Debug container **không có shell** (image tối giản, distroless) bằng `--entrypoint`, container phụ dùng chung network namespace, hoặc `docker debug`.
- Dùng `docker stats`, `docker events`, `docker system df` để quan sát tài nguyên và sự kiện.
- Nhận diện và xử lý 10 tình huống kinh điển: thoát ngay, restart liên tục, unhealthy, port bị chiếm, permission denied trên volume, không kết nối được DB, sửa code không thấy thay đổi, đầy ổ, pull lỗi, `exec format error`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

"Container của em không chạy" là câu bạn sẽ nghe nhiều nhất khi làm DevOps — từ developer, từ tester, từ chính bạn lúc 11 giờ đêm.

| Tình huống | Người thiếu quy trình | Người có quy trình |
|---|---|---|
| `docker compose ps` thấy `Exited (137)` | Rebuild lại image, xóa volume, khởi động lại máy… | Exit 137 = SIGKILL → kiểm tra `OOMKilled` trong inspect → tăng `mem_limit` |
| App báo "Connection refused" tới DB | Sửa code Java | Kiểm tra `DB_HOST` có phải `localhost` không → đổi thành tên service |
| Container `unhealthy` | Gỡ healthcheck cho "hết lỗi" | Đọc health log → lệnh healthcheck gọi sai port, hoặc dùng `curl` trong image không có `curl` |

Kỹ năng debug container chiếm phần lớn bài thực hành phỏng vấn DevOps: người phỏng vấn đưa một `compose.yaml` hỏng và xem **cách bạn tìm lỗi**, không chỉ kết quả.

Bài này **không dạy lại** các lệnh đã học ở bài 02–06 (`ps`, `logs`, `exec`, `inspect` cơ bản, `compose config`…). Nó **ghép chúng thành một quy trình** và bổ sung các công cụ nâng cao.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Container sống bao lâu? — Bằng PID 1

Nhớ lại [Linux bài 01, bài tập 3](../01-LINUX/solutions/01-solutions.md#bài-3--không-có-công-cụ): **process số 1 trong container chính là lệnh bạn yêu cầu container chạy** (`ENTRYPOINT` + `CMD`). Quy tắc nền tảng:

> **Container chạy chừng nào PID 1 còn chạy. PID 1 kết thúc → container dừng.** Exit code của container = exit code của PID 1.

Hệ quả: "container thoát ngay" luôn có nghĩa là **PID 1 đã kết thúc** — vì lỗi, vì làm xong việc, hoặc vì bị giết.

### 3.2. Exit code — ngôn ngữ chung của Linux và Docker

Bạn đã học ở [Linux bài 04](../01-LINUX/04-processes-systemd.md): exit code > 128 nghĩa là process bị **signal** giết, với số signal = exit code − 128.

| Exit code | Ý nghĩa | Nguyên nhân thường gặp trong container |
|---|---|---|
| `0` | Kết thúc bình thường | Lệnh làm xong việc rồi thoát (ví dụ `ubuntu` chạy `bash` không có terminal) — với app server, đây là dấu hiệu CMD sai |
| `1` | Lỗi chung của ứng dụng | App crash: không kết nối được DB, thiếu file cấu hình, exception lúc khởi động |
| `2` | Dùng sai lệnh / không mở được file | `python: can't open file '/app/main.py'` |
| `125` | **Docker** không chạy được container | Cờ `docker run` sai, xung đột tên container, port bị chiếm |
| `126` | Lệnh tồn tại nhưng **không thực thi được** | Script thiếu quyền `x`, sai định dạng (CRLF ở shebang — [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp)) |
| `127` | **Không tìm thấy lệnh** | Sai tên chương trình trong `CMD`, chương trình chưa được cài trong image |
| `137` | 128 + 9 = **SIGKILL** | Hết RAM (OOM killer) **hoặc** `docker stop` chờ hết 10 giây mà app không dừng |
| `139` | 128 + 11 = **SIGSEGV** | Lỗi truy cập bộ nhớ (segmentation fault) — thư viện native lỗi, sai kiến trúc CPU |
| `143` | 128 + 15 = **SIGTERM** | Bị yêu cầu dừng (`docker stop`) và app thoát theo tín hiệu — thường là bình thường |

Exit 137 có **hai** nguyên nhân rất khác nhau — luôn kiểm tra `OOMKilled` trong `docker inspect` để phân biệt.

### 3.3. Ba câu hỏi phân tầng

Giống quy trình debug mạng theo tầng ([Network bài 08](../02-NETWORKING/08-network-troubleshooting-tools.md)), debug container đi từ ngoài vào trong:

1. **Container có tồn tại và đang chạy không?** (tầng Docker)
2. **Process bên trong có làm đúng việc không?** (tầng ứng dụng — log, cấu hình)
3. **Nó có nói chuyện được với thứ nó cần không?** (tầng mạng, volume, tài nguyên)

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Quy trình 7 bước

| Bước | Câu hỏi | Lệnh chính | Đã học ở |
|---|---|---|---|
| 1 | Container có chạy không? Exit code bao nhiêu? | `docker compose ps -a`, `docker ps -a` | [bài 02](02-images-containers.md) |
| 2 | Log nói gì? | `docker compose logs <svc> --tail 50` | [bài 02](02-images-containers.md) |
| 3 | Cấu hình **thật sự** được áp dụng là gì? | `docker compose config`, `docker inspect` | [bài 05](05-docker-compose.md) |
| 4 | Bên trong container có gì? | `docker compose exec <svc> sh`, hoặc cách cho image không có shell (4.4) | [bài 02](02-images-containers.md) |
| 5 | Mạng có thông không? | DNS tên service, port container vs port publish | [bài 04](04-volumes-networks-env.md), [Network 08](../02-NETWORKING/08-network-troubleshooting-tools.md) |
| 6 | Có thiếu tài nguyên không? | `docker stats`, `OOMKilled`, `docker system df` | 4.5 |
| 7 | Chuyện gì đã xảy ra theo thời gian? | `docker events` | 4.6 |

**Nguyên tắc:** đi đúng thứ tự, **không bỏ bước 2**. Hơn một nửa sự cố được giải quyết ngay khi đọc kỹ 20 dòng log cuối.

### 4.2. 🟥 Bước 1–2: trạng thái và log

`docker compose ps -a` (có `-a` để thấy cả container đã dừng) cho cột **STATUS**:

| STATUS | Ý nghĩa | Làm gì tiếp |
|---|---|---|
| `Up 5 minutes` | Đang chạy | Lỗi nằm ở bước 3–5 |
| `Up 5 minutes (healthy)` / `(unhealthy)` / `(health: starting)` | Có healthcheck | `unhealthy` → xem health log (4.3) |
| `Exited (1) 10 seconds ago` | Đã dừng với exit code 1 | Đọc log |
| `Restarting (1) 3 seconds ago` | Restart policy đang khởi động lại liên tục | Đọc log — mỗi lần restart là một lần crash |
| `Created` | Đã tạo nhưng chưa bao giờ chạy | Thường do lỗi lúc start (port, mount) — đọc thông báo của `docker compose up` |

**Log nâng cao:**

| Cờ | Dùng khi |
|---|---|
| `--tail 50` | Chỉ cần đoạn cuối — luôn dùng, log có thể rất dài |
| `--since 10m` | Chỉ xem log 10 phút gần đây |
| `-f` | Theo dõi trực tiếp trong khi tái hiện lỗi |
| `-t` | Thêm thời gian — để đối chiếu giữa các service |

🟨 **Log lưu ở đâu?** Mặc định Docker dùng log driver `json-file`: mọi thứ app in ra stdout/stderr được ghi vào file JSON trên host. Mặc định **không giới hạn kích thước** (`max-size` mặc định là không giới hạn) — một app ghi log nhiều có thể làm đầy ổ đĩa server. Giới hạn cho từng service trong Compose:

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

Đây là phiên bản "logrotate" ([Linux bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md)) cho container. App trong container nên **ghi log ra stdout**, không ghi file bên trong container.

### 4.3. 🟥 Bước 3: `docker inspect` nâng cao

`docker inspect` trả về JSON rất dài. Dùng `--format` để lấy đúng phần cần:

| Muốn biết | Lệnh |
|---|---|
| Trạng thái, exit code, có bị OOM không | `docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' <ctr>` |
| Số lần đã restart | `docker inspect -f '{{.RestartCount}}' <ctr>` |
| Biến môi trường thật | `docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' <ctr>` |
| Mount (volume/bind) | `docker inspect -f '{{range .Mounts}}{{.Type}} {{.Name}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' <ctr>` |
| Network và IP | `docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{println}}{{end}}' <ctr>` |
| Health log (5 lần kiểm tra gần nhất) | `docker inspect -f '{{json .State.Health}}' <ctr>` |
| Lệnh thật sự chạy | `docker inspect -f '{{json .Config.Entrypoint}} {{json .Config.Cmd}}' <ctr>` |

Với Compose, lấy ID container của service bằng `docker compose ps -q <service>`:

```bash
docker inspect -f '{{.State.OOMKilled}}' "$(docker compose ps -q taskhub)"
```

**Hai nguồn sự thật cần đối chiếu:** `docker compose config` cho biết Compose **định** tạo gì (sau khi thay biến `.env`); `docker inspect` cho biết container **thật sự** đang có gì. Khác nhau → container chưa được tạo lại sau khi bạn sửa cấu hình (`docker compose up -d` để áp dụng).

### 4.4. 🟥 Bước 4: vào bên trong — kể cả khi không có shell

**Có shell:** `docker compose exec taskhub sh` (image `-noble` có `bash`, Alpine chỉ có `sh`).

**Container đã dừng** — không `exec` được. Chạy một container **mới** từ cùng image nhưng thay lệnh:

```bash
docker compose run --rm --entrypoint sh taskhub     # Compose
docker run --rm -it --entrypoint sh taskhub:local   # Docker thường
```

Bạn có shell trong môi trường giống hệt (cùng image, cùng biến môi trường, cùng volume nếu dùng `compose run`) để kiểm tra file, quyền, cấu hình — mà app không tự khởi động.

**Image không có shell** (distroless, image tối giản — [bài 07](07-docker-security.md)):

| Cách | Lệnh | Khi nào |
|---|---|---|
| Container phụ dùng chung network namespace | `docker run --rm -it --network container:<ctr> nicolaka/netshoot` | Debug **mạng** từ "góc nhìn" của container: `ss`, `curl localhost:8080`, `dig` |
| Biến thể debug của image | `gcr.io/distroless/java21-debian13:debug` có busybox shell | Distroless |
| `docker debug` 🟨 | `docker debug <ctr>` | Docker Desktop có lệnh này: mở shell kèm bộ công cụ riêng vào bất kỳ container/image nào, không sửa image ([docs](https://docs.docker.com/reference/cli/docker/debug/)) |

`--network container:<tên>` là kỹ thuật rất mạnh: container phụ **không có mạng riêng** mà dùng chung network namespace của container đích → `localhost` trong container phụ chính là `localhost` của container đích. Trong Compose, tương đương là `network_mode: service:<tên>`. Image `nicolaka/netshoot` là image cộng đồng phổ biến chứa sẵn gần như mọi công cụ mạng ([GitHub](https://github.com/nicolaka/netshoot)); nếu không muốn dùng image bên thứ ba, dùng `ubuntu:22.04` rồi tự cài `iproute2 curl dnsutils`.

### 4.5. 🟥 Bước 5–6: mạng và tài nguyên

**Mạng — ba câu hỏi luôn hỏi** (chi tiết ở [bài 04](04-volumes-networks-env.md)):

1. Hai container có **chung network** không? (`docker inspect` phần Networks). Khác network → không phân giải được tên nhau → `Name or service not known`.
2. App gọi tới **tên service** hay `localhost`? Trong container, `localhost` là **chính container đó**.
3. Dùng **port container** hay **port publish**? Container gọi nhau bằng port bên trong (`postgres:5432`). Port publish (`8000:80`) chỉ dùng từ **host** vào.

**Tài nguyên:**

```bash
docker stats --no-stream
```

Cột `MEM USAGE / LIMIT` cho biết container dùng bao nhiêu so với giới hạn; `PIDS` cho biết số process/thread. App Java gần chạm `LIMIT` → sắp bị OOM.

**Ổ đĩa của Docker:**

```bash
docker system df
```

Hiện dung lượng của image, container, volume, build cache, kèm cột `RECLAIMABLE` (có thể thu hồi). Dọn dẹp:

| Lệnh | Xóa gì | Mức nguy hiểm |
|---|---|---|
| `docker container prune` | Container đã dừng | Thấp |
| `docker image prune` | Image "lơ lửng" (dangling — không còn tag) | Thấp |
| `docker builder prune` | Build cache | Thấp (build sau chậm hơn) |
| `docker image prune -a` | **Mọi** image không có container nào dùng | Trung bình — phải pull/build lại |
| ⚠️ `docker volume prune` | Volume không có container nào dùng | **Cao — mất dữ liệu database** |
| ⚠️ `docker system prune -a --volumes` | Gần như mọi thứ | **Rất cao** |

> ⚠️ Không bao giờ chạy `volume prune` hoặc `system prune --volumes` trên server có dữ liệu thật mà chưa kiểm tra danh sách volume (`docker volume ls`) và chưa có backup.

### 4.6. 🟨 Bước 7: `docker events` — dòng thời gian

`docker events` phát trực tiếp mọi sự kiện của daemon: container create, start, die, kill, oom, health_status… Hữu ích khi lỗi xảy ra **chớp nhoáng** (container restart liên tục, bị OOM rồi khởi động lại).

```bash
docker events --since 10m --filter type=container --filter event=die --filter event=oom
```

- Nhiều `--filter` cùng khóa (`event=die`, `event=oom`) → kết hợp kiểu **HOẶC**; khác khóa (`type`, `event`) → kiểu **VÀ**.
- Không có `--since` → chỉ hiện sự kiện **mới** từ giờ trở đi (mở ở một terminal, tái hiện lỗi ở terminal khác).

### 4.7. 🟥 10 tình huống kinh điển

| # | Triệu chứng | Chẩn đoán | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|---|---|
| 1 | Container **thoát ngay** sau khi start | Exit code + log | Exit 0: lệnh làm xong việc (CMD sai, chạy shell không TTY). Exit 1: app crash. Exit 127: sai tên lệnh | Sửa `CMD`/`ENTRYPOINT`; đọc log crash |
| 2 | **Restart liên tục** (`Restarting`) | `RestartCount`, log với `--since` | App crash, restart policy khởi động lại mãi | Tìm lỗi gốc trong log — restart policy chỉ che giấu triệu chứng |
| 3 | **unhealthy** | `docker inspect -f '{{json .State.Health}}'` | Lệnh healthcheck dùng công cụ không có trong image (`curl` trong image `-slim`/distroless), sai port/path, `start_period` quá ngắn với Spring Boot | Sửa lệnh healthcheck; tăng `start_period` |
| 4 | **`port is already allocated`** | Đọc thông báo của `up`; `docker ps --format '{{.Names}} {{.Ports}}'`; `ss -tlnp` trên host | Container khác hoặc chương trình khác (nginx cài ở WSL tuần 5!) đang dùng port đó trên host | Đổi port publish hoặc dừng thứ đang chiếm |
| 5 | **Permission denied** khi ghi vào volume | `exec` vào: `id`, `ls -ln /data` | App chạy non-root (ví dụ user `taskhub`) nhưng volume thuộc root | Trong Dockerfile: `mkdir /data && chown taskhub:taskhub /data` **trước** khi mount — volume mới tạo sẽ kế thừa quyền của thư mục trong image |
| 6 | App **không kết nối được DB** | Log app; `exec` vào app thử `getent hosts postgres`, `nc -zv postgres 5432` | `DB_HOST=localhost`; khác network; DB chưa sẵn sàng khi app khởi động | Dùng tên service; chung network; `depends_on` + `condition: service_healthy` |
| 7 | **Sửa code mà không thấy thay đổi** | So `docker image ls` (thời gian tạo) với lúc bạn sửa; `docker compose config` | Quên `--build`; Compose dùng image cũ | `docker compose up -d --build`; nghi cache thì `--no-cache` |
| 8 | **Ổ đĩa đầy** / build báo `no space left on device` | `docker system df`; `df -h` | Image cũ, build cache, log `json-file` không giới hạn | Prune có chọn lọc (bảng 4.5); đặt `max-size` cho log |
| 9 | **Pull image lỗi** | Đọc thông báo nguyên văn | `manifest unknown` → tag không tồn tại; `unauthorized`/`denied` → chưa `docker login` hoặc image private; `toomanyrequests` → giới hạn tần suất pull của Docker Hub | Sửa tag; login; đăng nhập để có giới hạn cao hơn / dùng registry khác |
| 10 | **`exec format error`** | `docker image inspect -f '{{.Architecture}}'`; `uname -m` trên máy chạy | Image build cho `amd64` chạy trên máy `arm64` (hoặc ngược lại) | Build đa kiến trúc (`--platform`), hoặc dùng image có bản cho kiến trúc đó |

Tình huống 10 sẽ quan trọng ở tuần 11–12: EC2 loại **Graviton** (`t4g`, `m7g`…) dùng CPU **ARM64**, rẻ hơn — image build trên laptop x86_64 của bạn sẽ không chạy trên đó nếu không build đa kiến trúc. Docker Desktop có sẵn trình giả lập nên trên laptop bạn có thể **không** thấy lỗi này — chỉ thấy khi lên server thật.

### 4.8. Gặp lại ở đâu

| Ở đây | Gặp lại |
|---|---|
| Exit code 137, OOMKilled | Kubernetes: Pod `OOMKilled`, `CrashLoopBackOff` (Module 09) |
| Health log | Kubernetes liveness/readiness probe; ALB target health (Module 06) |
| `docker logs` → `json-file` | CloudWatch Logs, Loki (Module 08) |
| `docker events` | `kubectl get events` |
| `--network container:` | Kubernetes: các container trong cùng Pod chung network namespace; `kubectl debug` |
| ARM64 vs AMD64 | EC2 Graviton, build multi-arch trong CI |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Deploy xong, container cứ restart"

Ticket: sau khi deploy bản mới, `taskhub` liên tục `Restarting`. Kỹ sư áp dụng quy trình:

```bash
docker compose ps -a
```

```text
NAME                IMAGE           STATUS
taskhub-taskhub-1   taskhub:1.4.0   Restarting (137) 4 seconds ago
```

Exit 137 → SIGKILL. Bước tiếp theo **bắt buộc**: kiểm tra OOM.

```bash
docker inspect -f 'oom={{.State.OOMKilled}} restarts={{.RestartCount}}' taskhub-taskhub-1
```

```text
oom=true restarts=12
```

Bị OOM. So với bản cũ: bản 1.4.0 thêm tính năng xuất báo cáo nạp toàn bộ dữ liệu vào RAM, còn `mem_limit` vẫn là 512m. Hai lựa chọn: tăng giới hạn (ngắn hạn) và báo team dev sửa cách xuất báo cáo (dài hạn). Không cần đọc một dòng code nào để tìm ra nguyên nhân.

### Ví dụ 2: "Chạy trên máy em được mà"

Developer chạy `taskhub` bằng IntelliJ, kết nối PostgreSQL trong Docker qua `localhost:5432` — chạy tốt. Đưa app vào container, giữ nguyên `SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/taskhub` → app crash:

```text
Caused by: java.net.ConnectException: Connection refused
```

Trong container, `localhost` là chính container `taskhub` — không có PostgreSQL nào ở đó. Sửa thành `postgres:5432` (tên service). Đây là lỗi số 1 khi đưa app vào Docker.

### Ví dụ 3: Healthcheck luôn unhealthy sau khi "tối ưu image"

Để giảm bề mặt tấn công ([bài 07](07-docker-security.md)), một bạn trong team chuyển service `reports` (viết bằng Python) từ `python:3.12` sang `python:3.12-slim`, giữ nguyên healthcheck cũ `curl -fsS http://localhost:8000/health`. Sau deploy, service `unhealthy` và nginx (có `depends_on: condition: service_healthy`) không khởi động.

```bash
docker inspect -f '{{json .State.Health}}' taskhub-reports-1 | python3 -m json.tool
```

```text
{
    "Status": "unhealthy",
    "FailingStreak": 5,
    "Log": [
        {
            "ExitCode": 127,
            "Output": "/bin/sh: 1: curl: not found\n"
        }
    ]
}
```

Exit 127 trong health log = lệnh không tồn tại. Image `-slim` bỏ bớt công cụ, trong đó có `curl`. App vẫn chạy tốt suốt thời gian đó — chỉ có cái "cảm biến" bị hỏng. Lựa chọn: viết healthcheck bằng chính runtime có sẵn (`python -c "import urllib.request; ..."`), hoặc cài lại một công cụ nhỏ có chủ đích.

> So sánh với taskhub: `eclipse-temurin:21-jre-noble` **có sẵn** `curl` nên `HEALTHCHECK` của taskhub chạy được. Nếu sau này bạn chuyển taskhub sang distroless (🟦 [bài 07](07-docker-security.md)), bạn sẽ gặp đúng tình huống này — mọi thay đổi base image đều phải kiểm tra lại healthcheck.

---

## 6. Sơ đồ kiến trúc

### 6.1. Cây quyết định debug container

```text
                    "Container không chạy / app không truy cập được"
                                       │
                         docker compose ps -a
                                       │
           ┌───────────────────────────┼─────────────────────────────┐
           ▼                           ▼                             ▼
   Exited / Restarting           Up (unhealthy)                     Up
           │                           │                             │
   Exit code bao nhiêu?        inspect .State.Health          Truy cập từ host được không?
   ├─ 0   → CMD làm xong việc   → Output của lệnh check         ├─ không → port publish? (ps)
   ├─ 1   → đọc log (crash)       ├─ exit 127 → thiếu công cụ   │          app nghe 0.0.0.0?
   ├─ 125 → đọc thông báo `up`    ├─ connection refused         ├─ được nhưng lỗi → logs app
   ├─ 126/127 → CMD sai/thiếu x   │    → sai port/app chưa lên   │
   ├─ 137 → OOMKilled?            └─ timeout → start_period?    Service A gọi B lỗi?
   │   ├─ true  → tăng mem_limit                                  ├─ Name not known → network
   │   └─ false → stop timeout (PID 1 bỏ qua SIGTERM)             ├─ refused → port/bind/app chưa lên
   └─ 139 → segfault / sai kiến trúc                              └─ localhost? → dùng tên service
                                       │
                 Vẫn chưa ra?  → exec / run --entrypoint sh  → stats → events
```

### 6.2. `--network container:` hoạt động thế nào

```text
 ┌──────────── network namespace của container "taskhub" ─────────────┐
 │   eth0: 172.20.0.3        lo: 127.0.0.1                              │
 │                                                                      │
 │   ┌─────────────────────┐        ┌─────────────────────────────┐    │
 │   │ taskhub (distroless)│        │ netshoot (container phụ)    │    │
 │   │ java nghe :8080     │◄───────│ curl localhost:8080         │    │
 │   │ không có shell      │        │ ss -tlnp  dig  tcpdump      │    │
 │   └─────────────────────┘        └─────────────────────────────┘    │
 │        (filesystem riêng)               (filesystem riêng)           │
 └──────────────────────────────────────────────────────────────────────┘
```

Hai container có **filesystem riêng** nhưng **chung mạng**: container phụ thấy đúng những gì app thấy về mạng.

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `docker compose ps -a` | Trạng thái, exit code mọi container | 🟥 |
| `docker compose logs <svc> --tail N --since T -f -t` | Đọc log có chọn lọc | 🟥 |
| `docker inspect -f '<template>'` | Lấy đúng trường trạng thái/cấu hình | 🟥 |
| `docker compose run --rm --entrypoint sh <svc>` | Shell trong môi trường giống hệt, app không tự chạy | 🟥 |
| `docker run --network container:<ctr> <image-công-cụ>` | Debug mạng từ góc nhìn của container | 🟨 |
| `docker stats --no-stream` | Ảnh chụp CPU/RAM/PIDS | 🟥 |
| `docker events --since --filter` | Dòng thời gian sự kiện | 🟨 |
| `docker system df` | Dung lượng Docker dùng | 🟥 |
| `docker ... prune` | Dọn dẹp (⚠️ cẩn thận với volume) | 🟥 |
| `docker debug` | Shell kèm công cụ vào container bất kỳ | 🟦 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa** (Docker Desktop trên WSL). Tên, ID, số liệu trên máy bạn sẽ khác.

### `docker inspect -f` — lấy đúng thông tin

```bash
docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}' s2
```

```text
exited exit=137 oom=true restarts=0
```

| Phần template | Lấy từ JSON |
|---|---|
| `{{.State.Status}}` | `running`, `exited`, `restarting`, `created`… |
| `{{.State.ExitCode}}` | Exit code của PID 1 |
| `{{.State.OOMKilled}}` | `true` nếu bị kernel giết vì vượt giới hạn RAM |
| `{{.RestartCount}}` | Số lần restart policy đã khởi động lại |

Template `range` để lặp qua danh sách:

```bash
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' bf-api-1
```

```text
DB_HOST=postgres
DB_PORT=5432
PATH=/usr/local/bin:/usr/local/sbin:...
```

Khi không nhớ cấu trúc JSON: chạy `docker inspect <ctr> | less` rồi gõ `/` để tìm từ khóa.

### `docker compose run --rm --entrypoint sh`

```bash
docker compose run --rm --entrypoint sh taskhub
```

| Tham số | Ý nghĩa |
|---|---|
| `run` | Tạo **container mới** từ cấu hình service (khác `exec` — vào container **đang chạy**) |
| `--rm` | Xóa container khi thoát |
| `--entrypoint sh` | Thay `ENTRYPOINT` của image bằng `sh` — app không tự khởi động |

Bên trong, kiểm tra: `id` (chạy bằng user nào), `ls -la /app` (file có đủ không), `env` (biến môi trường), `cat` file cấu hình.

### `--network container:<tên>`

```bash
docker run --rm -it --network container:bf-api-1 nicolaka/netshoot
```

Bên trong container phụ:

```bash
ss -tlnp                       # app trong bf-api-1 đang nghe port nào, trên địa chỉ nào?
curl -s localhost:8000/health  # gọi app qua localhost CỦA bf-api-1
getent hosts postgres          # bf-api-1 phân giải "postgres" ra IP nào?
```

```text
State   Recv-Q  Send-Q   Local Address:Port   Peer Address:Port
LISTEN  0       5              0.0.0.0:8000        0.0.0.0:*
```

Không cần cài gì vào image của app.

### `docker stats --no-stream`

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}'
```

```text
NAME                 CPU %     MEM USAGE / LIMIT     MEM %     PIDS
taskhub-taskhub-1    0.85%     312.4MiB / 768MiB     40.68%    41
taskhub-postgres-1   0.02%     28.1MiB / 7.6GiB      0.36%     7
taskhub-nginx-1      0.00%     3.9MiB / 7.6GiB       0.05%     5
```

- `LIMIT` = `7.6GiB` (toàn bộ RAM Docker Desktop được dùng) → container **không có giới hạn** — cân nhắc đặt `mem_limit` ([bài 07](07-docker-security.md)).
- `PIDS` của Java khoảng vài chục là bình thường (mỗi thread tính là một).
- Không có `--no-stream`, lệnh cập nhật liên tục như `top` — nhấn `Ctrl+C` để thoát.

### `docker events`

Mở terminal 1:

```bash
docker events --filter type=container --format '{{.Time}} {{.Actor.Attributes.name}} {{.Action}}'
```

Terminal 2: `docker run --rm --name ev-demo alpine:3.20 sh -c 'exit 3'`

Terminal 1 hiện:

```text
1761900000 ev-demo create
1761900000 ev-demo attach
1761900001 ev-demo start
1761900001 ev-demo die
1761900001 ev-demo destroy
```

Sự kiện `die` kèm thuộc tính `exitCode` (xem bằng `--format '{{json .}}'`).

### `docker system df`

```bash
docker system df
```

```text
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          14        4         5.2GB     3.6GB (69%)
Containers      6         3         120MB     80MB (66%)
Local Volumes   5         2         780MB     410MB (52%)
Build Cache     63        0         2.1GB     2.1GB
```

`RECLAIMABLE` của Local Volumes **có thể chứa dữ liệu bạn cần** (volume của một project đang tạm dừng) — đó là lý do không prune volume khi chưa kiểm tra.

---

## 9. Bài thực hành từng bước

**Lab: Tái hiện và chẩn đoán 6 tình huống kinh điển** · `[WSL]` · ~75 phút

Mỗi tình huống: **chạy lệnh tạo lỗi → chẩn đoán bằng quy trình 7 bước → ghi lại → dọn dẹp**. Không cần app taskhub — chỉ dùng image công khai.

```bash
mkdir -p ~/devops-lab/04-docker/lab08 && cd ~/devops-lab/04-docker/lab08
```

Ghi kết quả vào `~/devops-journey/week08/lab08-troubleshooting.md` theo mẫu: *Triệu chứng → Lệnh chẩn đoán → Bằng chứng → Nguyên nhân → Cách sửa*.

### Tình huống 1 — Container thoát ngay

```bash
docker run -d --name s1a ubuntu:22.04
docker run -d --name s1b nginx:1.30-alpine nginxx -g 'daemon off;'
docker ps -a --filter name=s1 --format '{{.Names}}\t{{.Status}}'
docker logs s1a; docker logs s1b
```

❓ Exit code của từng container? Vì sao `s1a` thoát dù không có lỗi gì? (Gợi ý: PID 1 là `bash`, không có terminal gắn vào.) `s1b` báo gì? Thông báo lỗi xuất hiện ở đâu — log container hay output của lệnh `docker run`?

```bash
docker rm -f s1a s1b
```

### Tình huống 2 — OOMKilled

```bash
docker run -d --name s2 --memory 64m python:3.12-slim \
  python -c "data = b'x' * (200 * 1024 * 1024); print('allocated', len(data))"
sleep 5
docker ps -a --filter name=s2 --format '{{.Names}}\t{{.Status}}'
docker inspect -f 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' s2
docker logs s2
```

❓ Exit code? `OOMKilled`? Log có dòng `allocated` không, vì sao? Nếu không có dòng `oom=true`, bạn sẽ nghĩ tới nguyên nhân nào khác của exit 137?

```bash
docker rm -f s2
```

### Tình huống 3 — Healthcheck luôn unhealthy

```bash
docker run -d --name s3 \
  --health-cmd 'curl -fsS http://localhost:8000/ || exit 1' \
  --health-interval 5s --health-retries 2 \
  python:3.12-slim python -m http.server 8000
sleep 20
docker ps --filter name=s3 --format '{{.Names}}\t{{.Status}}'
docker inspect -f '{{json .State.Health}}' s3 | python3 -m json.tool | head -20
```

❓ App (http.server) có chạy không? Vì sao vẫn `unhealthy`? Exit code trong health log là bao nhiêu và nghĩa là gì?

Sửa: viết lại healthcheck chỉ dùng thứ có sẵn trong image (gợi ý: `python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')"`), chạy container `s3b`, xác nhận `healthy`.

```bash
docker rm -f s3 s3b
```

### Tình huống 4 — Port đã bị chiếm

```bash
docker run -d --name s4a -p 18080:80 nginx:1.30-alpine
docker run -d --name s4b -p 18080:80 nginx:1.30-alpine
echo "exit code của lệnh trên: $?"
docker ps -a --filter name=s4 --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
```

❓ Thông báo lỗi nguyên văn? Trạng thái của `s4b` là gì (`Created`?) và exit code của **lệnh** `docker run`? Tìm "ai" đang giữ port 18080 bằng **hai** cách: `docker ps --format '{{.Names}} {{.Ports}}'` và `ss -tlnp | grep 18080` (trên WSL có thể không thấy process vì Docker Desktop publish port từ máy ảo của nó — ghi lại bạn thấy gì).

```bash
docker rm -f s4a s4b
```

### Tình huống 5 — localhost vs tên service

```bash
docker network create lab08-net
docker run -d --name db --network lab08-net -e POSTGRES_PASSWORD=lab postgres:17
sleep 8
docker run --rm --network lab08-net postgres:17 pg_isready -h localhost -p 5432
docker run --rm --network lab08-net postgres:17 pg_isready -h db -p 5432
docker run --rm postgres:17 pg_isready -h db -p 5432
```

❓ Ba lệnh `pg_isready` cho kết quả gì? Giải thích từng kết quả bằng kiến thức về `localhost` trong container và DNS nội bộ của network ([bài 04](04-volumes-networks-env.md)). Lệnh thứ ba khác lệnh thứ hai ở điểm nào?

Thêm: chạy lệnh thứ hai **ngay** sau khi tạo một container `db2` mới (không `sleep`). Kết quả? Đây là lý do cần `depends_on` + `condition: service_healthy`.

```bash
docker rm -f db db2 2>/dev/null; docker network rm lab08-net
```

### Tình huống 6 — Permission denied trên volume

```bash
docker run --rm --user 10001:10001 -v lab08-data:/data python:3.12-slim \
  sh -c 'id; ls -ld /data; echo hello > /data/test.txt'
```

❓ Lỗi gì? `/data` thuộc user nào? Vì sao?

Sửa đúng cách — build một image tạo sẵn thư mục với đúng chủ sở hữu:

```bash
docker build -t lab08-writer - <<'EOF'
FROM python:3.12-slim
RUN mkdir /data && chown 10001:10001 /data
USER 10001:10001
EOF
docker volume rm lab08-data
docker run --rm -v lab08-data2:/data lab08-writer sh -c 'id; ls -ld /data; echo hello > /data/test.txt && echo OK'
```

❓ Vì sao volume **mới** `lab08-data2` thuộc UID 10001, còn nếu dùng lại `lab08-data` cũ thì không? (Gợi ý: khi một volume **rỗng** được mount vào một thư mục có sẵn trong image, Docker sao chép nội dung và quyền của thư mục đó vào volume.)

```bash
docker volume rm lab08-data2; docker image rm lab08-writer
```

### Tình huống 7 — Pull lỗi và dọn dẹp

```bash
docker pull nginx:1.99-khongtontai
docker system df
docker image prune          # trả lời y — chỉ xóa image dangling
```

❓ Thông báo khi pull tag không tồn tại? `docker system df` trước và sau prune khác gì?

---

## 10. Kết quả mong đợi

- **TH1:** `s1a` — `Exited (0)`: PID 1 là `bash`, không có terminal (`-it`) nên đọc stdin thấy kết thúc và thoát bình thường. `s1b` — exit `127`; thông báo `executable file not found in $PATH` xuất hiện ngay ở output của `docker run` (Docker không chạy được lệnh), log container rỗng.
- **TH2:** `exit=137 oom=true`, không có dòng `allocated` — process bị giết trong lúc cấp phát, trước khi kịp in. Nếu `oom=false` với exit 137 → nghĩ tới `docker stop`/`kill` (PID 1 không dừng khi nhận SIGTERM).
- **TH3:** http.server chạy bình thường; health log có `ExitCode: 127` và `curl: not found` (hoặc thông báo tương tự) — image `slim` không có `curl`. Healthcheck bằng `python -c "import urllib.request..."` chuyển sang `healthy`.
- **TH4:** `Bind for 0.0.0.0:18080 failed: port is already allocated` (chữ có thể khác đôi chút theo phiên bản); `s4b` ở trạng thái `Created`; lệnh `docker run` trả exit code khác 0 (thường `125`).
- **TH5:** `localhost:5432 - no response` (trong container client không có postgres); `db:5432 - accepting connections`; lệnh thứ ba không có `--network` → nằm ở bridge mặc định, không phân giải được tên `db` → báo lỗi phân giải tên/`no response`. Không `sleep` → `rejecting connections` hoặc `no response` vì postgres đang khởi tạo.
- **TH6:** `Permission denied`; `/data` thuộc `root` vì volume rỗng được tạo cho một đường dẫn **không có sẵn** trong image → Docker tạo thư mục bằng root. Với image có `/data` thuộc 10001, volume **mới** được sao chép quyền đó. Volume cũ đã có nội dung/quyền thì Docker **không** sao chép lại.
- **TH7:** `manifest unknown` (hoặc `not found`) — tag không tồn tại trên registry.

---

## 11. Các lỗi thường gặp

| Lỗi khi debug | Hậu quả | Cách làm đúng |
|---|---|---|
| Đọc log của **nginx** khi lỗi nằm ở **app** (hoặc ngược lại) | Mất thời gian | Xác định service lỗi từ `ps -a` trước; với 502, đọc log nginx để biết nó gọi **ai**, rồi đọc log service đó |
| Thấy exit 137 là kết luận "hết RAM" | Tăng RAM không giải quyết được | Luôn kiểm tra `OOMKilled` |
| Sửa `compose.yaml` rồi chỉ `docker compose restart` | `restart` **không** áp dụng cấu hình mới | `docker compose up -d` (tạo lại container khi cấu hình đổi) |
| Sửa code rồi `docker compose up -d` | Vẫn chạy image cũ | `docker compose up -d --build` |
| Gỡ healthcheck / thêm `restart: always` để "hết lỗi" | Che giấu lỗi, sự cố thật sẽ xảy ra lúc tệ nhất | Tìm nguyên nhân gốc |
| `docker system prune -a --volumes` để "dọn sạch làm lại" | Mất dữ liệu database | Prune có chọn lọc; `docker volume ls` trước |
| `exec` vào container đã dừng | `container ... is not running` | `docker compose run --rm --entrypoint sh <svc>` |
| Debug trong container rồi quên sửa file cấu hình | Container được tạo lại → lỗi quay lại | Sửa trong container chỉ để **thử giả thuyết**; cách sửa thật nằm ở Dockerfile/`compose.yaml` |

---

## 12. Đọc log và xử lý lỗi

### Thông báo đến từ đâu?

Một kỹ năng quan trọng là phân biệt **ai** in ra thông báo lỗi:

| Nguồn | Bạn thấy ở | Ví dụ |
|---|---|---|
| **Docker CLI / daemon** | Output của `docker run` / `docker compose up`, không phải log container | `port is already allocated`, `executable file not found in $PATH`, `manifest unknown`, `dependency failed to start` |
| **Ứng dụng** (PID 1) | `docker logs` | Stack trace Java, `Connection refused`, `FATAL: password authentication failed` |
| **Kernel** | `docker inspect` (`OOMKilled`), không có trong log app | Process biến mất không một dòng log |
| **Healthcheck** | `docker inspect` → `.State.Health.Log` | `curl: not found` |

Container chết mà log **trống trơn** → lỗi không nằm ở app: xem output của lệnh `up`, xem `OOMKilled`, xem `docker events`.

### Đọc log Compose khi nhiều service

```bash
docker compose logs --tail 20 -t
```

Mỗi dòng có tiền tố tên service. Với `-t`, sắp theo thời gian để thấy **thứ tự nhân quả**: `postgres` còn đang `database system is starting up` thì `taskhub` đã báo `Connection refused` → vấn đề thứ tự khởi động.

### Log của Spring Boot trong container

Áp dụng cách đọc stack trace từ [Linux bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md): tìm `APPLICATION FAILED TO START`, đọc dòng `Caused by:` **cuối cùng**. Ba nguyên nhân phổ biến nhất khi chạy taskhub trong Compose:

| `Caused by` chứa | Nghĩa là |
|---|---|
| `Connection refused` | `SPRING_DATASOURCE_URL` sai host (localhost) hoặc DB chưa sẵn sàng |
| `UnknownHostException: postgres` | Khác network hoặc sai tên service |
| `password authentication failed` | Mật khẩu trong `.env` khác mật khẩu lúc volume PostgreSQL được **khởi tạo lần đầu** (đổi `POSTGRES_PASSWORD` sau khi volume đã có dữ liệu **không** đổi mật khẩu trong DB) |

---

## 13. Câu hỏi kiểm tra kiến thức

1. Container sống bao lâu? Vì sao `docker run -d ubuntu:22.04` thoát ngay với exit code 0?
2. Giải thích ý nghĩa của các exit code 1, 125, 126, 127, 137, 143. Exit code nào do **Docker** sinh ra thay vì do ứng dụng?
3. Exit 137 có hai nguyên nhân phổ biến. Đó là gì, và lệnh nào phân biệt chúng?
4. Liệt kê 7 bước của quy trình debug container theo đúng thứ tự. Vì sao không nên nhảy thẳng vào bước "exec vào container"?
5. `docker compose config` và `docker inspect` khác nhau thế nào? Khi chúng cho kết quả khác nhau, điều đó nói lên gì?
6. Container đã dừng thì không `exec` được. Bạn làm gì để có shell trong môi trường giống hệt container đó?
7. Image của app không có shell. Kể 2 cách để debug mạng của nó. `--network container:<tên>` hoạt động thế nào?
8. App non-root báo `Permission denied` khi ghi vào volume `/data`. Giải thích nguyên nhân và cách sửa trong Dockerfile. Vì sao cách sửa chỉ có tác dụng với volume mới?
9. App báo `Connection refused` khi kết nối `localhost:5432` trong Compose. Giải thích và sửa.
10. Bạn sửa `compose.yaml` rồi chạy `docker compose restart`, nhưng không thấy thay đổi. Vì sao? Lệnh đúng là gì? Còn khi sửa code Java?
11. Log driver mặc định của Docker là gì? Rủi ro gì trên server chạy lâu, và cách hạn chế?
12. `docker system df` báo Local Volumes có 400MB RECLAIMABLE. Có nên chạy `docker volume prune` ngay không? Vì sao?
13. Container chết mà `docker logs` trống. Bạn nghĩ tới những nguyên nhân nào và kiểm tra ở đâu?
14. `exec format error` là gì? Vì sao trên laptop có Docker Desktop bạn có thể không gặp, nhưng lên EC2 Graviton lại gặp?
15. Healthcheck báo unhealthy với exit code 127 trong health log. Nguyên nhân là gì và cách sửa nào **không** làm image to thêm?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/08-solutions.md](solutions/08-solutions.md) — chỉ mở sau khi đã tự làm và ghi câu trả lời.

**Bài 1 — PID 1 bỏ qua SIGTERM.** Chạy `docker run -d --name sig1 alpine:3.20 sh -c 'while true; do sleep 1; done'`. Đo thời gian `time docker stop sig1` và xem exit code. Lặp lại với `docker run -d --init --name sig2 ...` (cùng lệnh). So sánh và giải thích vai trò của `--init`. Liên hệ: vì sao Dockerfile nên dùng dạng exec `CMD ["java", "-jar", "app.jar"]` thay vì dạng shell?

**Bài 2 — Restart loop.** Chạy `docker run -d --name loop --restart on-failure:5 alpine:3.20 sh -c 'echo starting; sleep 2; exit 1'`. Quan sát `docker ps` nhiều lần, đọc `RestartCount`, đọc log. Dùng `docker events` để ghi lại dòng thời gian các lần `die`/`start`. Sau 5 lần thì sao?

**Bài 3 — Debug mạng container không có shell.** Chạy một container nginx bằng image `nginx:1.30-alpine` nhưng giả định nó không có shell (không được dùng `exec`). Dùng `--network container:` với một image có công cụ để: liệt kê port đang nghe, gọi `curl localhost:80`, xem IP. Viết lại các lệnh và kết quả.

**Bài 4 — Runbook.** Viết `~/projects/taskhub/docs/runbooks/container-troubleshooting.md` cho dự án taskhub: một trang, gồm bảng exit code, 5 lệnh đầu tiên chạy khi có sự cố, và 5 lỗi hay gặp nhất **của chính taskhub** (từ lab bài 05–07 của bạn) kèm cách sửa.

**Bài 5 — Log không giới hạn.** Chạy `docker run -d --name noisy alpine:3.20 sh -c 'while true; do echo "$(date) log line $RANDOM"; done'` trong 30 giây rồi kiểm tra kích thước log bằng `docker inspect -f '{{.LogPath}}' noisy` (đường dẫn nằm trong máy ảo Docker Desktop — giải thích vì sao bạn có thể không mở được nó từ WSL) và `docker logs noisy | wc -l`. Chạy lại với `--log-opt max-size=1m --log-opt max-file=2`. Giải thích kết quả. ⚠️ Nhớ `docker rm -f noisy`.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Nhìn exit code bất kỳ trong bảng 3.2, bạn nói được nhóm nguyên nhân và lệnh kiểm tra tiếp theo.
- [ ] Đọc thông báo lỗi, bạn phân biệt được nó đến từ Docker, từ app, từ kernel hay từ healthcheck.
- [ ] Debug được container đã dừng và container không có shell.
- [ ] Hoàn thành 7 tình huống ở mục 9 và giải thích được từng kết quả.
- [ ] Không bao giờ chạy prune volume mà không kiểm tra trước.
- [ ] Hoàn thành [Break-fix Docker #1](labs/break-fix-01/README.md) theo đúng quy trình 7 bước.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Docker docs — `docker container logs`](https://docs.docker.com/reference/cli/docker/container/logs/) | Cờ `--tail`, `--since`, `-f`, `-t` | 2026-10-31 |
| [Docker docs — JSON File logging driver](https://docs.docker.com/engine/logging/drivers/json-file/) | Log driver mặc định, `max-size`, `max-file` | 2026-10-31 |
| [Docker docs — `docker container stats`](https://docs.docker.com/reference/cli/docker/container/stats/) | Cột, `--no-stream`, `--format` | 2026-10-31 |
| [Docker docs — `docker system events`](https://docs.docker.com/reference/cli/docker/system/events/) | Bộ lọc, `--since` | 2026-10-31 |
| [Docker docs — `docker debug`](https://docs.docker.com/reference/cli/docker/debug/) | 🟦 Debug container không có shell | 2026-10-31 |
| [Docker docs — `docker container run`](https://docs.docker.com/reference/cli/docker/container/run/) | `--init`, `--entrypoint` | 2026-10-31 |
| [Docker docs — Compose services reference](https://docs.docker.com/reference/compose-file/services/) | `healthcheck`, `depends_on`, `logging`, `restart` | 2026-10-31 |
| [nicolaka/netshoot (GitHub)](https://github.com/nicolaka/netshoot) | Container công cụ mạng, `--net container:` | 2026-10-31 |
