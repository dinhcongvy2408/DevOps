# Lời giải — Checkpoint Giai đoạn 3–4 (Git & Docker)

> ⚠️ Chỉ đọc sau khi đã commit bài làm. Câu trả lời của bạn khác nhưng lập luận đúng bản chất vẫn tính là đúng.

Quay lại đề: [checkpoint.md](../checkpoint.md)

## Mục lục

- [Phần A — Lý thuyết](#phần-a--lý-thuyết)
- [Phần B — Thực hành](#phần-b--thực-hành)
- [Phần C — Break-fix](#phần-c--break-fix)

---

## Phần A — Lý thuyết

**1. reset vs revert.** `git reset --hard HEAD~1` **xóa** commit khỏi nhánh (di chuyển con trỏ nhánh lùi lại) — viết lại lịch sử. Với commit đã push và người khác đã pull, muốn đẩy lên phải `push --force`, làm lịch sử của đồng nghiệp lệch với remote. `git revert HEAD` **tạo commit mới** đảo ngược thay đổi — lịch sử chỉ được thêm vào, an toàn cho nhánh chung. → Đã push: dùng **revert**. Chưa push (chỉ có ở máy mình): `reset` được (`--soft`/`--mixed` để giữ thay đổi và sửa lại, `--hard` để bỏ hẳn).

**2. merge vs rebase.** Merge giữ nguyên lịch sử hai nhánh và tạo merge commit (lịch sử dạng nhánh). Rebase **viết lại** các commit của nhánh mình thành commit mới (hash mới) đặt lên đầu nhánh đích — lịch sử thẳng. Vì rebase tạo commit mới, nếu nhánh đã được người khác dùng, lịch sử của họ sẽ tham chiếu tới các commit "cũ" không còn trên remote → rối. Squash merge gộp mọi commit của Pull Request thành **một** commit trên `main` → `main` thẳng, mỗi commit tương ứng một PR/một tính năng, dễ revert cả tính năng.

**3. Conflict.** Xảy ra khi hai nhánh sửa **cùng vùng** của cùng file (hoặc một bên sửa, một bên xóa file) và Git không tự quyết định được. `<<<<<<< HEAD` → phần của nhánh hiện tại; `=======` phân cách; `>>>>>>> <nhánh>` → phần của nhánh đang merge vào. Các bước: `git status` xem file conflict → sửa file, chọn/kết hợp nội dung, **xóa các dấu** → chạy lại test/build → `git add <file>` → `git commit` (hoặc `git merge --continue`; với rebase là `git rebase --continue`). Muốn hủy: `git merge --abort`.

**4. SemVer và tag.** Sửa bug: `v1.4.3` (PATCH). Thêm endpoint tương thích ngược: `v1.5.0` (MINOR, PATCH về 0). Đổi tên trường JSON client đang dùng = phá vỡ tương thích: `v2.0.0` (MAJOR). Annotated tag là một đối tượng riêng trong Git có người tạo, ngày, lời nhắn (và có thể ký); lightweight tag chỉ là một con trỏ tới commit. Release dùng annotated vì có thông tin ai phát hành, khi nào, vì sao — và `git describe` mặc định dùng annotated tag.

**5. GitHub Flow.** Từ `main` cập nhật, tạo nhánh `feat/...`/`fix/...` → commit nhỏ theo Conventional Commits → push → mở Pull Request mô tả thay đổi → CI chạy (build/test) → review, sửa theo góp ý → merge bằng squash khi CI xanh và đã được duyệt → xóa nhánh. Branch protection chặn: push thẳng lên `main`, merge khi chưa có review bắt buộc, merge khi CI chưa xanh, force push và xóa nhánh `main`.

**6. Container vs VM.** VM có kernel riêng trên phần cứng ảo (hypervisor); container là process dùng **chung kernel** host, được cô lập. Namespace giới hạn những gì process **thấy** (PID, mạng, mount, hostname, user); cgroup giới hạn những gì process **dùng** (RAM, CPU, số process). `uname -r` hỏi kernel — mà kernel là của host.

**7. Layer và cache.** Mỗi lệnh tạo thay đổi filesystem (`RUN`, `COPY`, `ADD`) tạo một layer chỉ đọc; Docker cache layer và tái sử dụng nếu lệnh và mọi đầu vào **không đổi** — nhưng một layer thay đổi thì **mọi layer phía sau** phải build lại. Dependency (pom.xml) ít thay đổi hơn mã nguồn → đặt bước tải dependency trước `COPY src` để sửa code không làm tải lại toàn bộ dependency. Sửa một file `.java`: layer `COPY src` và các layer sau (build jar) chạy lại; layer dependency dùng cache.

**8. Multi-stage.** Tách môi trường **build** (JDK, Maven, mã nguồn, cache) khỏi môi trường **chạy**. Runtime image của taskhub chỉ có JRE + file jar (+ user, healthcheck); không có JDK/trình biên dịch, Maven, mã nguồn, file test. Lợi ích bảo mật: ít gói → ít CVE; không có công cụ build để kẻ tấn công lợi dụng; không lộ mã nguồn trong image. Thêm lợi ích: image nhỏ, pull nhanh.

**9. Volume.** Named volume: Docker quản lý, có tên, tồn tại độc lập với container. Bind mount: gắn một đường dẫn cụ thể của host vào container (hợp với file cấu hình, mã nguồn khi dev). Anonymous volume: volume không tên, thường do `VOLUME` trong image tạo ra khi không có mount tương ứng — dễ "mồ côi" và mất theo container. PostgreSQL → **named volume** ở đúng `PGDATA` (`/var/lib/postgresql/data` với postgres:17). `down` xóa container và network, giữ named volume; `down -v` xóa cả volume khai báo trong file.

**10. Tên service và port.** Trong container, `localhost` là chính container đó; Compose tạo network riêng với DNS nội bộ, tên service (`postgres`) phân giải ra IP container postgres. Port publish `8000:80` mở port **trên host** → máy host (và mọi máy truy cập được host) gọi vào nginx. Postgres không publish → chỉ container **cùng network** gọi được qua `postgres:5432`; từ ngoài không vào được — đúng ý đồ bảo mật.

**11. depends_on.** Dạng ngắn (`service_started`) chỉ chờ container phụ thuộc **được khởi chạy**; `service_healthy` chờ healthcheck của nó báo `healthy`. PostgreSQL cần vài giây (lần đầu còn lâu hơn vì khởi tạo) từ lúc process chạy đến lúc nhận kết nối. Không có healthcheck, app có thể kết nối trước khi DB sẵn sàng → crash; tùy tốc độ máy và thứ tự, có lần chạy có lần không → "chập chờn" (race condition).

**12. Secret.** `ENV` lưu trong cấu hình image (`docker image inspect`), giá trị `ARG` dùng trong `RUN` hiện trong `docker history --no-trunc`; ai có image là đọc được. Mật khẩu DB của taskhub: giữ trong `.env` (có trong `.gitignore`, kèm `.env.example`), `compose.yaml` tham chiếu `${POSTGRES_PASSWORD}`, truyền vào container **lúc chạy**. Secret lúc build dùng BuildKit secret mount.

**13. Bảo mật.** Bất kỳ 5 trong: runtime JRE thay JDK; pin version image; chạy non-root (`USER taskhub`); không publish port DB; secret qua `.env` ngoài Git; `cap_drop: [ALL]`; `no-new-privileges`; `read_only` + `tmpfs /tmp`; `mem_limit`/`pids_limit`; quét Trivy. Group `docker` điều khiển được daemon chạy root → `docker run -v /:/host ...` mount toàn bộ filesystem host và có shell root, không cần sudo.

**14. Exit code.** `137` = SIGKILL: (a) bị OOM killer giết vì vượt giới hạn RAM; (b) `docker stop` hết 10 giây chờ mà PID 1 không dừng. Phân biệt: `docker inspect -f '{{.State.OOMKilled}}' <ctr>`. `127`: lệnh trong `CMD`/`ENTRYPOINT` không tìm thấy (sai tên, chưa cài). `0` với app server: PID 1 kết thúc "bình thường" — thường do `CMD` sai (chạy lệnh làm xong việc rồi thoát, ví dụ shell không có terminal) hoặc app chạy nền (daemonize) nên PID 1 thoát.

**15. `latest`.** `latest` chỉ là một tag bình thường, bị ghi đè mỗi lần ai đó push. Máy A pull `latest` tuần trước (bản 1.3), máy B pull hôm nay (bản 1.4 vừa push, có bug) → cùng `compose.yaml`, hai môi trường chạy hai phiên bản; lỗi chỉ xuất hiện ở máy B, không tái hiện được ở A. Ngoài ra Docker không tự pull lại `latest` nếu đã có image cùng tag trên máy. Phòng tránh: tag theo phiên bản/commit SHA (`taskhub:1.4.0`, `taskhub:sha-a1b2c3d`), pin version cho image bên thứ ba, 🟨 pin digest.

---

## Phần B — Thực hành

### Dockerfile tham khảo

```dockerfile
# ---------- Stage 1: chạy unit test ----------
FROM python:3.12-slim AS test
WORKDIR /app
COPY notes.py .
COPY tests/ tests/
# Build dừng ở đây nếu có test thất bại (exit code khác 0)
RUN python -m unittest discover -s tests -v

# ---------- Stage 2: runtime ----------
FROM python:3.12-slim AS runtime
# User hệ thống với UID cố định, không có home, không shell đăng nhập
RUN groupadd --system --gid 10001 notes \
 && useradd --system --uid 10001 --gid notes --no-create-home --shell /usr/sbin/nologin notes \
 && mkdir /data && chown notes:notes /data
WORKDIR /app
# Lấy notes.py TỪ STAGE TEST: buộc BuildKit phải chạy stage test trước
COPY --from=test /app/notes.py .
USER notes
ENV NOTES_DB=/data/notes.db
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/health', timeout=2).status == 200 else 1)"]
CMD ["python", "notes.py"]
```

Ba điểm quan trọng:

1. **`COPY --from=test`** — BuildKit (mặc định trong Docker hiện nay) chỉ build những stage mà stage đích **cần tới**. Nếu stage runtime chỉ `COPY notes.py .` từ build context, stage `test` bị **bỏ qua hoàn toàn** và kiểm thử B6 (build phải thất bại khi test sai) sẽ không đạt. Lấy file từ stage test tạo ra sự phụ thuộc → test luôn chạy. Đây là chi tiết nhiều người bỏ sót.
2. **`mkdir /data && chown`** trước khi khai báo user — volume **mới** gắn vào `/data` được sao chép quyền của thư mục có sẵn trong image ([bài 08, tình huống 6](../08-container-troubleshooting.md#9-bài-thực-hành-từng-bước)). Thiếu bước này → `sqlite3.OperationalError: unable to open database file`.
3. **Healthcheck không dùng curl** — `python:3.12-slim` không có `curl`; dùng chính Python.

### `.dockerignore`

```text
.git
**/__pycache__
**/*.pyc
*.md
compose.yaml
Dockerfile
.dockerignore
```

Không đưa `tests/` vào `.dockerignore` — stage test **cần** nó. Thư mục `tests/` không xuất hiện trong image cuối nhờ multi-stage, không phải nhờ `.dockerignore`.

### `compose.yaml`

```yaml
services:
  notes:
    build: .
    image: notes:1.0.0
    ports:
      - "18002:8080"
    volumes:
      - notes-data:/data          # named volume — dữ liệu SQLite tồn tại qua down/up
    mem_limit: 128m               # app Python nhỏ; đo lại bằng docker stats
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped

volumes:
  notes-data:
```

### Git

```bash
git switch -c feat/containerize
git add Dockerfile .dockerignore compose.yaml
git commit -m "feat(docker): containerize notes service with multi-stage build"
# (PR trên GitHub → Squash and merge)  hoặc trên máy:
git switch main
git merge --squash feat/containerize
git commit -m "feat(docker): containerize notes service (#1)"
git tag -a v1.0.0 -m "notes v1.0.0: first containerized release"
git log --oneline --graph --all
git show v1.0.0 | head -8
```

`git show v1.0.0` của annotated tag bắt đầu bằng `tag v1.0.0`, `Tagger: ...`, ngày và lời nhắn, rồi mới đến commit. Lightweight tag thì `git show` hiện thẳng commit.

### Tự chấm

- Kiểm thử 4: image tham khảo ở trên đo được **119MB** (Docker Desktop, 2026-10-31) — gần như toàn bộ là `python:3.12-slim`; phần của bạn chỉ thêm vài KB. Con số trên máy bạn có thể lệch vài MB theo bản vá mới nhất của image nền.
- Kiểm thử 6: nếu build **không** thất bại → bạn đang bị BuildKit bỏ qua stage test (xem điểm 1).

---

## Phần C — Break-fix

Thứ tự lỗi lộ ra: #6001 → #6002 → #6003 và #6004 (độc lập nhau).

### #6001 — `.dockerignore` loại mất file cấu hình

**Bước 1–2:**

```bash
docker compose up -d --build
```

```text
 ✘ Container ck04-api-1  Error
dependency failed to start: container ck04-api-1 exited (1)
```

```bash
docker compose ps -a
docker compose logs api
```

```text
[reports-api] FATAL config file not found: /app/config/settings.json
```

File có trong thư mục `api/config/` trên máy, nhưng không có trong image. **Bước 4** — kiểm tra bên trong image:

```bash
docker compose run --rm --entrypoint ls api -R /app
```

```text
/app:
Dockerfile
app.py
config

/app/config:
```

Thư mục `config` **rỗng**. Thứ quyết định file nào vào build context: `api/.dockerignore` có dòng `**/*.json` — loại **mọi** file `.json` ở mọi cấp, kể cả `config/settings.json`.

**Sửa** — loại trừ chính xác hơn, hoặc thêm ngoại lệ:

```text
**/*.json
!config/settings.json
```

(hoặc bỏ hẳn dòng `**/*.json` nếu dự án không có file JSON rác nào). `docker compose up -d --build`.

> Lưu ý: `*.json` (không có `**/`) chỉ khớp file ở **gốc** build context; `**/*.json` khớp mọi cấp. Đồng nghiệp đã "sửa cho chắc" thành `**/*.json` — và làm hỏng app.

### #6002 — Healthcheck dùng công cụ không có trong image

Sau #6001, `api` chạy nhưng `web` không lên:

```text
dependency failed to start: container ck04-api-1 is unhealthy
```

```bash
docker inspect -f '{{json .State.Health}}' "$(docker compose ps -q api)" | python3 -m json.tool
```

```text
"Status": "unhealthy",
"Log": [ { "ExitCode": -1, "Output": "... exec: \"curl\": executable file not found in $PATH ..." } ]
```

(Exit code và chữ có thể khác — minh họa.) Healthcheck dạng `["CMD", "curl", ...]` chạy trực tiếp chương trình `curl` — image `python:3.12-slim` không có. App vẫn chạy tốt (`docker compose exec api python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8000/health').read())"` trả `ok`).

**Sửa** trong `compose.yaml`:

```yaml
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=2).status == 200 else 1)"]
```

Không cài `curl` vào image chỉ để healthcheck — tăng kích thước và bề mặt tấn công ([bài 07](../07-docker-security.md)).

### #6003 — Volume thuộc root, app chạy non-root

```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"t"}' http://localhost:18001/api/reports
docker compose logs api --tail 5
docker compose exec api sh -c 'id; ls -ld /data'
```

```text
{"error": "cannot write report: [Errno 13] Permission denied: '/data/reports.jsonl'"}
uid=10001(reporter) gid=999(reporter) groups=999(reporter)
drwxr-xr-x 2 root root 4096 ... /data
```

`Errno 13` = `EACCES`. Image không có sẵn thư mục `/data` → Docker tạo mount point bằng root, volume rỗng thuộc root; app chạy UID 10001 không ghi được.

**Sửa** `api/Dockerfile`:

```dockerfile
RUN useradd --system --uid 10001 --no-create-home reporter \
 && mkdir /data && chown reporter /data
USER reporter
```

Volume `reports` **đã tồn tại** thuộc root sẽ không được sao chép quyền lại → cần xóa để Docker tạo volume mới (dữ liệu thử, được phép):

```bash
docker compose down -v
docker compose up -d --build
```

Cách sai cần tránh: chạy api bằng root, hoặc `chmod 777` volume.

### #6004 — Worker khác network

```bash
docker compose logs worker --tail 5
```

```text
[worker] error sending report #12: <urlopen error [Errno -3] Temporary failure in name resolution>
```

`Temporary failure in name resolution` (có máy hiện `[Errno -2] Name or service not known`) = không phân giải được tên `api` → DNS, không phải port. Với Docker Desktop, DNS nội bộ không biết tên `api` trong network `jobs` nên chuyển câu hỏi ra DNS bên ngoài — và thất bại. **Bước 5 — network:**

```bash
docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$(docker compose ps -q worker)"
docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$(docker compose ps -q api)"
```

```text
ck04_jobs
ck04_backend
```

DNS nội bộ của Docker chỉ phân giải tên các container **cùng network**. worker ở `jobs`, api ở `backend`.

**Sửa** — tối thiểu và có chủ đích: cho api tham gia **thêm** network `jobs` (api là thứ worker cần gọi; web vẫn không thấy worker):

```yaml
  api:
    networks:
      - backend
      - jobs
```

Cách khác chấp nhận được: đưa worker vào `backend`, kèm giải thích. Kiểm chứng: sau vài giây, `docker compose logs worker --tail 3` có `sent report #N -> HTTP 201`, `./verify.sh` đạt 4/4.

### Bảng tổng kết

| Ticket | Bằng chứng then chốt | Bước trong quy trình 7 bước |
|---|---|---|
| #6001 | `config file not found` + `ls -R /app` thấy `config/` rỗng | 2 (log) → 4 (bên trong) |
| #6002 | Health log: `curl` not found | 3 (inspect `.State.Health`) |
| #6003 | `Errno 13` + `/data` thuộc root, app UID 10001 | 2 → 4 (`id`, `ls -ld`) |
| #6004 | `Temporary failure in name resolution` + hai network khác nhau | 2 → 5 (mạng) |
