# Checkpoint Giai đoạn 3–4 — Git & Docker

> ⏱️ Tổng ~4 giờ (có thể chia 2 buổi) · Làm vào cuối tuần 8
> Bao phủ: [Module 03 — Git](../03-GIT/README.md) bài 01–05 và Module 04 — Docker bài [01](01-vm-vs-container-architecture.md)–[08](08-container-troubleshooting.md)
> Lời giải: [solutions/checkpoint-solutions.md](solutions/checkpoint-solutions.md) — **chỉ mở sau khi đã nộp bài cho chính mình** (commit vào repo).

## Mục lục

- [Quy tắc](#quy-tắc)
- [Phần A — Lý thuyết (50 phút)](#phần-a--lý-thuyết-50-phút)
- [Phần B — Thực hành (90 phút)](#phần-b--thực-hành-90-phút)
- [Phần C — Break-fix (90 phút)](#phần-c--break-fix-90-phút)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [Nếu chưa đạt](#nếu-chưa-đạt)

---

## Quy tắc

1. **Không dùng AI và không xem lời giải** trong lúc làm.
2. **Được phép**: `man`, `--help`, `git help <lệnh>`, [Pro Git](https://git-scm.com/book/en/v2), tài liệu Docker chính thức, các bài học trong Module 03 và 04.
3. Tự bấm giờ cho từng phần. Hết giờ thì dừng và ghi lại mình đang ở đâu — đó cũng là dữ liệu đánh giá.
4. Nộp bài: tạo thư mục `~/devops-journey/week08/checkpoint/` gồm `part-a.md`, `part-b.md` (link repo/kết quả kiểm thử), `part-c.md` (nhật ký debug). Commit **trước** khi mở lời giải.

---

## Phần A — Lý thuyết (50 phút)

Trả lời ngắn gọn bằng lời của bạn (2–6 câu mỗi câu). Mục tiêu là giải thích **bản chất**, không chép định nghĩa.

### Git

1. Bạn lỡ commit một thay đổi sai lên `main` **đã push** và đồng nghiệp đã pull về. `git reset --hard HEAD~1` và `git revert HEAD` khác nhau thế nào? Bạn chọn lệnh nào, vì sao? Nếu commit đó **chưa push** thì sao?
2. `git merge` và `git rebase` khác nhau thế nào về lịch sử commit? Quy tắc "không rebase nhánh đã chia sẻ" xuất phát từ đâu? Repo taskhub dùng **squash merge** khi merge Pull Request — lịch sử `main` trông thế nào?
3. Merge conflict xảy ra khi nào? Mô tả ý nghĩa của các dấu `<<<<<<<`, `=======`, `>>>>>>>` và các bước giải quyết một conflict cho đến khi hoàn tất merge.
4. Theo Semantic Versioning, từ `v1.4.2`: sửa một bug → phiên bản gì? Thêm endpoint mới không phá vỡ API cũ → ? Đổi tên một trường JSON mà client đang dùng → ? Annotated tag khác lightweight tag ở điểm nào, và vì sao release nên dùng annotated tag?
5. Mô tả quy trình từ lúc nhận một task đến khi code vào `main` theo GitHub Flow của taskhub: nhánh, commit, Pull Request, review, CI, merge. Branch protection trên `main` ngăn được những gì?

### Docker

6. Container khác máy ảo thế nào? Namespace và cgroup lần lượt giới hạn điều gì? Vì sao `uname -r` trong container cho kết quả giống host?
7. Image layer là gì? Vì sao trong Dockerfile của taskhub, bước tải dependency Maven được đặt **trước** bước `COPY` mã nguồn? Điều gì xảy ra với cache khi bạn chỉ sửa một file `.java`?
8. Multi-stage build giải quyết vấn đề gì? Image runtime của taskhub chứa gì và **không** chứa gì so với stage build? Nêu 2 lợi ích về bảo mật.
9. Phân biệt named volume, bind mount và anonymous volume. Dữ liệu PostgreSQL của taskhub nên dùng loại nào? Vì sao `docker compose down` không mất dữ liệu nhưng `docker compose down -v` thì mất?
10. Trong `compose.yaml` của taskhub, vì sao `SPRING_DATASOURCE_URL` dùng `postgres:5432` chứ không phải `localhost:5432`? Port publish `8000:80` của nginx và port `5432` của postgres khác nhau thế nào về **ai** truy cập được?
11. `depends_on` dạng ngắn và `depends_on` với `condition: service_healthy` khác nhau thế nào? Vì sao thiếu healthcheck khiến hệ thống "lúc chạy lúc không"?
12. Vì sao không đưa secret vào `ENV` hoặc `ARG` của Dockerfile? Chứng minh bằng lệnh nào? Cách đúng để truyền mật khẩu database cho taskhub là gì?
13. Kể 5 biện pháp bảo mật container áp dụng được cho taskhub. Vì sao thêm user vào group `docker` tương đương cấp quyền root?
14. Container dừng với `Exited (137)`. Hai nguyên nhân có thể là gì và lệnh nào phân biệt? Còn `Exited (127)` và `Exited (0)` với một app server?
15. Vì sao dùng tag `latest` trong `compose.yaml` là rủi ro? Cho một kịch bản cụ thể `latest` khiến hai máy chạy hai phiên bản khác nhau của cùng một service, và cách phòng tránh.

---

## Phần B — Thực hành (90 phút)

### Bối cảnh

Team nhận một dịch vụ nhỏ tên `notes` (Python, chỉ dùng thư viện chuẩn, lưu dữ liệu SQLite) và cần **container hóa** nó theo đúng chuẩn của taskhub. Mã nguồn ở [labs/checkpoint/part-b/](labs/checkpoint/part-b/README.md).

### Chuẩn bị

```bash
mkdir -p ~/devops-lab/04-docker && cd ~/devops-lab/04-docker
cp -r /mnt/d/HocDepOps/DEVOPS-LEARNING/04-DOCKER/labs/checkpoint .
find checkpoint -type f -exec sed -i 's/\r$//' {} +
cp -r checkpoint/part-b ~/notes-service
cd ~/notes-service
git init -b main
git add . && git commit -m "chore: import notes service"
```

Nếu muốn làm Pull Request thật: tạo repo `notes-service` trên GitHub, `git remote add origin ...`, `git push -u origin main`. Nếu không, làm các bước nhánh/merge **trên máy** (vẫn được tính điểm).

### Đề bài

Làm việc trên nhánh `feat/containerize`. Tạo:

**1. `Dockerfile`** — multi-stage, gồm ít nhất:

- Stage `test`: từ `python:3.12-slim`, chạy unit test (`python -m unittest discover -s tests`). **Build phải thất bại nếu test thất bại.**
- Stage cuối (runtime): từ `python:3.12-slim`, **chỉ chứa `notes.py`** (không chứa thư mục `tests/`).
- Chạy bằng user **non-root** có UID cố định.
- App ghi được vào `/data` khi `/data` là một named volume mới.
- `HEALTHCHECK` gọi `/health` — lưu ý image `python:3.12-slim` **không có** `curl`.
- `CMD` dạng exec.

**2. `.dockerignore`** — không đưa `.git`, `__pycache__`, file rác vào build context, nhưng **không** làm mất file cần thiết.

**3. `compose.yaml`** — một service `notes`, publish `18002:8080`, named volume `notes-data` gắn vào `/data`, có giới hạn RAM.

**4. Git** — commit theo Conventional Commits trên nhánh `feat/containerize`; mở Pull Request (hoặc merge trên máy) bằng **squash merge** vào `main`; tạo **annotated tag** `v1.0.0` trên `main`.

### Kiểm thử bắt buộc

Ghi lệnh và kết quả vào `part-b.md`:

| # | Kiểm thử | Kết quả mong đợi |
|---|---|---|
| 1 | `docker compose up -d --build` rồi `docker compose ps` sau tối đa 30 giây | `notes` ở trạng thái `(healthy)` |
| 2 | `docker run --rm --entrypoint id <image>` | UID khác 0 |
| 3 | `docker run --rm --entrypoint ls <image> /app` | Chỉ có `notes.py` (không có `tests`) |
| 4 | `docker image ls <image>` | Kích thước < 200MB |
| 5 | `curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"ghi chu 1"}' http://localhost:18002/notes`, rồi `docker compose down`, `docker compose up -d`, `curl -s http://localhost:18002/notes` | Ghi chú vẫn còn |
| 6 | Sửa tạm một test cho sai (ví dụ đổi `"mua sua"` thành `"mua"` trong `test_strips_whitespace`), chạy `docker compose build` | Build **thất bại** ở stage test. Khôi phục test sau đó |
| 7 | `git log --oneline --graph --all` và `git show v1.0.0` | `main` có commit squash; tag `v1.0.0` là annotated (có người tạo, ngày, lời nhắn) |

Dọn dẹp sau khi xong: `docker compose down -v` (trong `~/notes-service`).

---

## Phần C — Break-fix (90 phút)

### Khởi tạo

```bash
cd ~/devops-lab/04-docker/checkpoint
chmod +x verify.sh
docker compose up -d --build
./verify.sh                 # kiểm tra tiến độ bất cứ lúc nào
```

> Lệnh `up` ở lần đầu **sẽ báo lỗi** — đó là một phần của đề bài. Đọc kỹ thông báo.
> Nếu `18001` bị chiếm: đổi port publish của `web` trong `compose.yaml`.

### Bối cảnh

Hệ thống `reports` gồm 3 service: `web` (nginx, mở `http://localhost:18001`), `api` (nhận và lưu báo cáo vào volume `/data`), `worker` (cứ 5 giây tự gửi một báo cáo tới `api`). Tuần trước, một đồng nghiệp đã "tối ưu image và siết bảo mật": thêm `.dockerignore`, chuyển app sang user non-root, thêm healthcheck, tách mạng cho worker. Từ đó hệ thống không chạy nữa.

### Các ticket

| Ticket | Mô tả | Kết quả mong đợi |
|---|---|---|
| 🎫 #6001 | `docker compose up -d` báo lỗi, `api` không lên | `api` chạy ổn định |
| 🎫 #6002 | `web` không bao giờ khởi động — Compose báo `api` không healthy, dù app trong `api` đang chạy | `api` ở trạng thái `healthy`, `web` khởi động |
| 🎫 #6003 | `POST /api/reports` qua web trả `500` | Trả `201`, báo cáo được lưu trong volume |
| 🎫 #6004 | Không có báo cáo tự động nào từ `worker` | `GET /api/reports` có báo cáo với `"source": "worker"` |

### Luật chơi

- **Không sửa** `api/app.py`, `worker/worker.py` và **không đọc** `verify.sh`.
- **Không** bỏ healthcheck, **không** chuyển app về chạy root, **không** gộp mọi service vào một network chỉ để "cho chắc" — sửa đúng chỗ, tối thiểu cần thiết, giải thích được.
- Được sửa: `compose.yaml`, `api/Dockerfile`, `api/.dockerignore`, `worker/Dockerfile`.
- Cách áp dụng: sửa Dockerfile/`.dockerignore` → `docker compose up -d --build`; sửa `compose.yaml` → `docker compose up -d`. Được phép `docker compose down -v` khi cần — ghi lý do.
- Ghi nhật ký debug cho **từng ticket** theo mẫu của [break-fix #1](labs/break-fix-01/README.md#7-sản-phẩm-phải-nộp) vào `part-c.md`, nêu rõ bước nào trong [quy trình 7 bước](08-container-troubleshooting.md#41--quy-trình-7-bước) giúp bạn tìm ra.

Dọn dẹp sau khi xong: `docker compose down -v --rmi local` (trong `checkpoint`).

---

## Tiêu chí đạt

| Phần | Đạt khi | Trọng số |
|---|---|---|
| A | ≥ 12/15 câu đúng **bản chất** (tự chấm theo lời giải, trung thực). Câu 1, 9 và 14 **bắt buộc đúng** | 30% |
| B | Qua cả 7 kiểm thử trong 90 phút; Dockerfile và `compose.yaml` có comment giải thích các quyết định chính | 35% |
| C | `./verify.sh` đạt 4/4 trong 90 phút **và** nhật ký nêu được **cách tìm ra** từng lỗi (lệnh nào, thấy gì) | 35% |

**Đạt Checkpoint** khi đạt cả 3 phần → tick vào checklist [Module 04](README.md) và cập nhật [ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#docker) (cả phần [Git](../00-ROADMAP/skill-matrix.md#git)).

---

## Nếu chưa đạt

Không chuyển sang Module 05 ngay (xem [quy tắc khi chậm tiến độ](../00-ROADMAP/weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ)):

| Sai ở | Ôn lại |
|---|---|
| Câu A1 | [Git bài 01](../03-GIT/01-git-fundamentals-internals.md), [Git bài 02](../03-GIT/02-branching-merging-conflicts.md) |
| Câu A2–A3 | [Git bài 02](../03-GIT/02-branching-merging-conflicts.md) |
| Câu A4, kiểm thử B7 (tag) | [Git bài 05](../03-GIT/05-tags-releases-versioning.md) |
| Câu A5, kiểm thử B7 (PR, squash) | [Git bài 03](../03-GIT/03-github-pull-request-code-review.md), [Git bài 04](../03-GIT/04-team-workflows.md) |
| Câu A6 | [Docker bài 01](01-vm-vs-container-architecture.md) |
| Câu A7, A15 | [Docker bài 02](02-images-containers.md), [bài 06](06-registry.md) |
| Câu A8, kiểm thử B3, B4, B6 | [Docker bài 03](03-dockerfile-multistage.md) |
| Câu A9, A10, kiểm thử B5, ticket #6003, #6004 | [Docker bài 04](04-volumes-networks-env.md) |
| Câu A11, kiểm thử B1, ticket #6002 | [Docker bài 05](05-docker-compose.md) |
| Câu A12, A13, kiểm thử B2 | [Docker bài 07](07-docker-security.md) |
| Câu A14, ticket #6001, không biết bắt đầu Phần C từ đâu | [Docker bài 08](08-container-troubleshooting.md) |

Ôn xong 2–3 ngày rồi làm lại phần chưa đạt (Phần C: copy lại thư mục lab từ giáo trình để có lỗi ban đầu).
