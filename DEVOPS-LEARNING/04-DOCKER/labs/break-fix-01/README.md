# Break-fix Docker #1 — Bàn giao môi trường staging taskhub-lite

> ⏱️ 90–150 phút · Môi trường: `[WSL]` + Docker Desktop · Kiến thức cần có: Docker bài [01](../../01-vm-vs-container-architecture.md) → [08](../../08-container-troubleshooting.md)
> Lời giải: [solutions/break-fix-01-solution.md](../../solutions/break-fix-01-solution.md) — **chỉ mở khi đã hoàn thành hoặc đã bị kẹt quá 30 phút sau khi xem hết gợi ý.**

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
- [2. Sơ đồ hệ thống](#2-sơ-đồ-hệ-thống)
- [3. Khởi tạo môi trường](#3-khởi-tạo-môi-trường)
- [4. Các lệnh bạn được dùng](#4-các-lệnh-bạn-được-dùng)
- [5. Các ticket](#5-các-ticket)
- [6. Luật chơi](#6-luật-chơi)
- [7. Sản phẩm phải nộp](#7-sản-phẩm-phải-nộp)
- [8. Gợi ý](#8-gợi-ý)
- [9. Dọn dẹp](#9-dọn-dẹp)

---

## 1. Bối cảnh

`taskhub-lite` là bản rút gọn của taskhub mà team dùng để demo cho khách hàng: một API nhỏ lưu danh sách công việc vào PostgreSQL, Nginx đứng trước làm reverse proxy. Người dựng môi trường này bằng Docker Compose vừa chuyển sang team khác, chỉ để lại một dòng: *"chạy được rồi, có vài chỗ hơi chập chờn"*.

Bạn được giao tiếp quản. Trước buổi demo thứ Sáu, trưởng nhóm muốn môi trường **chạy ổn định, dữ liệu không mất, deploy nhanh và qua được rà soát bảo mật**. Có 5 ticket đang chờ.

Lần này **bạn đã học Docker** — được phép và nên đọc `compose.yaml`, `Dockerfile`, cấu hình nginx, dùng mọi lệnh Docker đã học.

---

## 2. Sơ đồ hệ thống

```text
 Trình duyệt Windows / curl trên WSL
   http://localhost:18000
          │
          ▼  (port publish 18000 → 80)
 ┌────────────────────┐
 │ nginx              │  nginx:1.30-alpine
 │ reverse proxy      │  /api/...  →  api:8000
 └─────────┬──────────┘
           │ mạng mặc định của project bf04
           ▼
 ┌────────────────────┐        ┌────────────────────┐
 │ api                │───────►│ postgres           │
 │ Python, port 8000  │  5432  │ postgres:17        │
 │ build từ ./api     │        │ volume pgdata      │
 └────────────────────┘        └────────────────────┘
```

| Endpoint (qua nginx) | Kết quả mong đợi |
|---|---|
| `GET /api/health` | `{"status": "UP", "db": "ok"}` |
| `GET /api/tasks` | Danh sách công việc (JSON) |
| `POST /api/tasks` với body `{"title": "..."}` | `201` + công việc vừa tạo |

---

## 3. Khởi tạo môi trường

Trong WSL:

```bash
mkdir -p ~/devops-lab/04-docker && cd ~/devops-lab/04-docker
# Copy thư mục lab từ giáo trình về (đổi đường dẫn cho đúng nơi bạn lưu DEVOPS-LEARNING)
cp -r /mnt/d/HocDepOps/DEVOPS-LEARNING/04-DOCKER/labs/break-fix-01 .
cd break-fix-01
find . -type f -exec sed -i 's/\r$//' {} +   # phòng trường hợp file bị đổi sang CRLF khi copy từ Windows
chmod +x verify.sh
docker compose up -d --build
```

Lần đầu mất 1–3 phút để tải image và cài thư viện Python. Kiểm tra tiến độ bất cứ lúc nào:

```bash
./verify.sh
```

> **Gặp lỗi khi `docker compose up`?**
> - `port is already allocated` cho `18000` → sửa `18000` trong `compose.yaml` thành port khác. Nếu lỗi ở `5432` → có PostgreSQL khác đang chạy trên máy; ghi lại điều này, nó liên quan tới một ticket bên dưới.
> - Lỗi tải `psycopg` khi build → kiểm tra kết nối Internet, chạy lại `docker compose build api`.

---

## 4. Các lệnh bạn được dùng

Mọi lệnh chạy trong thư mục `break-fix-01` trên WSL. Ngoài các lệnh dưới đây, bạn được dùng **mọi lệnh Docker** đã học ở bài 01–08.

| Mục đích | Lệnh |
|---|---|
| Trạng thái, exit code | `docker compose ps -a` |
| Log | `docker compose logs <service> --tail 50` (thêm `-t`, `-f`) |
| Cấu hình đã resolve | `docker compose config` |
| Chi tiết container | `docker inspect "$(docker compose ps -q <service>)"` |
| Vào container | `docker compose exec <service> sh` |
| Gọi API | `curl -s http://localhost:18000/api/health` |
| Tạo một công việc | `curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"demo"}' http://localhost:18000/api/tasks` |
| Đo thời gian dừng | `time docker compose stop api` |

**Cách áp dụng thay đổi:**

| Bạn sửa | Áp dụng bằng |
|---|---|
| `compose.yaml`, `.env` | `docker compose up -d` |
| `api/Dockerfile`, `api/start.sh` | `docker compose up -d --build` |
| `nginx/default.conf` | `docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload` (hoặc `docker compose up -d` nếu sửa cả đường dẫn mount) |

> Dữ liệu trong lab là dữ liệu thử. Khi cần, bạn **được phép** chạy `docker compose down -v` để xóa volume và khởi tạo lại database từ đầu — nhưng hãy ghi vào nhật ký **vì sao** bạn cần làm vậy. Trên hệ thống thật, đó là thao tác phải xin phép và có backup.

---

## 5. Các ticket

### 🎫 Ticket #5001 — P1 — Môi trường không lên

> **Người báo:** Trưởng nhóm
> **Mô tả:** Chạy `docker compose up -d` xong, mở `http://localhost:18000/api/health` không được gì. `docker compose ps -a` thấy có container đã dừng.
> **Kết quả mong đợi:** `api` chạy ổn định, **kể cả khi chạy `docker compose down` rồi `docker compose up -d` nhiều lần liên tiếp** (không còn "chập chờn"). Ticket này có **2 lỗi** nối tiếp nhau.

### 🎫 Ticket #5002 — P1 — Trang trả về "Welcome to nginx!"

> **Người báo:** QA
> **Mô tả:** Sau khi api đã chạy, `http://localhost:18000/` hiện trang mặc định "Welcome to nginx!", còn `/api/health` trả `404 Not Found` của nginx. Đồng nghiệp khẳng định file `nginx/default.conf` đã viết đúng.
> **Kết quả mong đợi:** `/api/health` trả `{"status": "UP", ...}` qua nginx. File cấu hình phải được nginx thật sự sử dụng.

### 🎫 Ticket #5003 — P1 — Mất dữ liệu sau bảo trì

> **Người báo:** Khách hàng demo
> **Mô tả:** Hôm qua tạo 5 công việc. Sáng nay sau khi team "bảo trì" (`docker compose down` rồi `docker compose up -d`), danh sách trống trơn. Đồng nghiệp: "Volume `pgdata` có khai báo rồi mà?"
> **Kết quả mong đợi:** Tạo công việc → `docker compose down` (không có `-v`) → `docker compose up -d` → công việc **vẫn còn**.

### 🎫 Ticket #5004 — P2 — Deploy chậm, log bị cắt

> **Người báo:** Team vận hành
> **Mô tả:** Mỗi lần deploy, bước dừng `api` luôn mất đúng khoảng 10 giây. `docker compose ps -a` sau khi dừng hiện `Exited (137)`. Log không bao giờ có dòng `received SIGTERM, shutting down gracefully` mà app được viết để in ra khi tắt.
> **Kết quả mong đợi:** `time docker compose stop api` dưới 2 giây, log có dòng `shutting down gracefully`.

### 🎫 Ticket #5005 — P2 — Rà soát bảo mật trước demo

> **Người báo:** Security team
> **Mô tả:** Checklist rà soát báo 3 điểm không đạt: (a) database lộ ra ngoài máy chủ, (b) mật khẩu nằm trong file được commit lên Git, (c) có container ứng dụng chạy bằng root.
> **Kết quả mong đợi:** Cả 3 điểm đạt. Hệ thống vẫn chạy bình thường sau khi sửa. Tham khảo [bài 07](../../07-docker-security.md).

---

## 6. Luật chơi

1. **Không sửa** `api/app.py` — đó là code của team dev. Bạn sửa **hạ tầng**: `compose.yaml`, `api/Dockerfile`, `api/start.sh`, cấu hình nginx, `.env`, `.gitignore`.
2. **Không đọc** `verify.sh` trước khi xong — nó chứa đáp án.
3. **Không dùng AI.** Được dùng: `docker --help`, `man`, các bài học trong giáo trình, tài liệu Docker chính thức.
4. **Đi theo quy trình 7 bước** của [bài 08](../../08-container-troubleshooting.md#41--quy-trình-7-bước): trạng thái → log → cấu hình → bên trong → mạng → tài nguyên → sự kiện. Ghi lại bằng chứng ở mỗi bước.
5. **Không có lời giải "tắt"**: không thêm `restart: always` để che lỗi, không chạy `--privileged`, không xóa healthcheck/volume để "hết lỗi". Mọi thay đổi phải giải thích được.
6. Dùng **image và tag đã có** trong lab — không đổi sang phiên bản PostgreSQL/Nginx khác.

---

## 7. Sản phẩm phải nộp

Tạo file `~/devops-journey/week08/break-fix-docker-01.md` gồm:

1. **Timeline** các lỗi theo đúng thứ tự bạn phát hiện.
2. Với **mỗi lỗi**, theo [mẫu nhật ký debug](../../../00-ROADMAP/templates/troubleshooting-journal-template.md):

   ```markdown
   ### Lỗi N: <tên ngắn>
   - Triệu chứng (dán nguyên thông báo lỗi, exit code, STATUS):
   - Bước nào trong quy trình 7 bước giúp bạn tìm ra:
   - Lệnh quan sát đã dùng và kết quả:
   - Nguyên nhân gốc:
   - Cách sửa (file nào, dòng nào, trước/sau):
   - Cách phòng tránh lần sau:
   - Gặp lại ở đâu (taskhub thật / AWS / Kubernetes):
   ```

3. Phép thử dữ liệu bền của ticket #5003: lệnh và kết quả.
4. Thời gian `docker compose stop api` trước và sau khi sửa ticket #5004.
5. Kết quả `./verify.sh` cuối cùng (dán vào).
6. Một đoạn ngắn: **3 bài học** bạn sẽ áp dụng ngay vào `compose.yaml` và `Dockerfile` của taskhub.

---

## 8. Gợi ý

Chỉ mở từng cấp khi đã thử ít nhất 15 phút ở cấp trước.

<details>
<summary>💡 Gợi ý cấp 1 — Hướng tiếp cận</summary>

- Bắt đầu bằng `docker compose ps -a`: service nào dừng, **exit code** bao nhiêu? Tra bảng exit code ở [bài 08](../../08-container-troubleshooting.md#32-exit-code--ngôn-ngữ-chung-của-linux-và-docker).
- Đọc log của **từng** service, không chỉ service bạn nghi ngờ. Log nginx khi khởi động thường có cảnh báo (`[warn]`) rất đáng đọc.
- Với ticket #5001: hỏi lại câu "trong container, `localhost` là ai?". Sau khi qua được lỗi đầu, chạy `down`/`up` vài lần và để ý **thứ tự** các dòng log của postgres và api (`docker compose logs -t`).
- Với ticket #5003: dữ liệu của PostgreSQL **thật sự** nằm ở đâu bên trong container? So với chỗ volume `pgdata` được gắn vào.
- Với ticket #5004: process số 1 trong container `api` là gì? Ai nhận tín hiệu SIGTERM khi bạn chạy `docker compose stop`?

</details>

<details>
<summary>💡 Gợi ý cấp 2 — Lệnh nên dùng</summary>

- Biến môi trường thật của api: `docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$(docker compose ps -q api)"`.
- Các file cấu hình nginx đang có: `docker compose exec nginx ls -l /etc/nginx/conf.d/`; cấu hình nginx đang dùng: `docker compose exec nginx nginx -T | less`.
- Mount của postgres: `docker inspect -f '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}}{{println}}{{end}}' "$(docker compose ps -q postgres)"`. Chú ý tên volume nào là chuỗi hex dài 64 ký tự. Biến `PGDATA` của image: `docker image inspect postgres:17 -f '{{range .Config.Env}}{{println .}}{{end}}' | grep PGDATA`, và khai báo `VOLUME` của image: `docker image inspect postgres:17 -f '{{json .Config.Volumes}}'`.
- PID 1 của api: `docker compose exec api cat /proc/1/cmdline | tr '\0' ' '; echo`. So với `docker compose exec api ps` — nếu không có `ps`, dùng `ls /proc | grep -E '^[0-9]+$'` rồi đọc `cmdline` từng PID.
- Port của postgres trên host: `docker compose ps` (cột PORTS) — `0.0.0.0:5432` nghĩa là gì ([Network bài 05](../../../02-NETWORKING/05-tcp-udp-ports-firewall.md))?
- User của api: `docker compose exec api id`.

</details>

<details>
<summary>💡 Gợi ý cấp 3 — Gần như đáp án</summary>

- #5001: (1) `DB_HOST` trỏ tới `localhost` thay vì tên service; (2) `depends_on` dạng ngắn chỉ chờ container postgres **được tạo**, không chờ PostgreSQL **sẵn sàng nhận kết nối**, còn app thì thoát ngay nếu kết nối thất bại. Cần healthcheck cho postgres và điều kiện chờ `service_healthy`.
- #5002: file cấu hình được mount với tên `taskhub.conf`, nằm **cạnh** file `default.conf` có sẵn của image. Cả hai cùng khai báo `server_name localhost` trên port 80 — nginx cảnh báo xung đột và dùng file nào được nạp trước.
- #5003: hướng dẫn trên mạng viết cho PostgreSQL 18 (mount `/var/lib/postgresql`), còn image là 17 với `PGDATA` = `/var/lib/postgresql/data` và image tự khai báo `VOLUME` ở đó → dữ liệu rơi vào một **anonymous volume** mới sau mỗi lần `down`/`up`. Sau khi sửa đường dẫn, nếu postgres báo thư mục dữ liệu "exists but is not empty", volume cũ đang chứa rác của cách mount cũ — xóa volume cũ (được phép trong lab) và giải thích trong nhật ký.
- #5004: `start.sh` chạy `python` như một process con và chờ nó; `sh` là PID 1 và không chuyển SIGTERM cho con → Docker chờ 10 giây rồi SIGKILL. Dùng `exec` trong script (hoặc gọi thẳng python trong `CMD`).
- #5005: bỏ publish port 5432 (hoặc chỉ bind `127.0.0.1` nếu thật sự cần truy cập từ host); chuyển mật khẩu sang `.env` + tham chiếu `${...}` trong `compose.yaml`, thêm `.env` vào `.gitignore`, tạo `.env.example`; tạo user non-root trong `api/Dockerfile`. Lưu ý: PostgreSQL chỉ đặt mật khẩu **lúc khởi tạo volume lần đầu** — đổi giá trị trong `.env` khi volume đã có dữ liệu thì api sẽ báo `password authentication failed`.

</details>

---

## 9. Dọn dẹp

Khi xong (hoặc muốn làm lại từ đầu):

```bash
docker compose down -v --rmi local
```

Lệnh này xóa container, network, volume và image `api` do lab build. Muốn làm lại với lỗi ban đầu: copy lại thư mục lab từ giáo trình (vì bạn đã sửa các file).

⚠️ Lỗi của ticket #5003 để lại **anonymous volume mồ côi** — mỗi lần `down`/`up` trước khi sửa tạo thêm một volume tên 64 ký tự hex mà `down -v` không còn biết tới. Liệt kê: `docker volume ls -f dangling=true`. Chỉ xóa (`docker volume rm <tên>`) những volume bạn chắc chắn do lab tạo ra (xem `CreatedAt` bằng `docker volume inspect <tên>`) — máy bạn có thể có volume mồ côi của dự án khác mà bạn vẫn cần.
