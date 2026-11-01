# Lời giải — Bài 02: Images & Containers

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [02-images-containers.md](../02-images-containers.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Image vs container (class/object)?**
Image là bản thiết kế bất biến (class); container là thực thể đang sống tạo từ image (object), có trạng thái riêng ở layer ghi được. Một image → nhiều container độc lập.

**2. Image gồm gì, không gồm gì?**
Gồm: các layer filesystem chỉ đọc + metadata (CMD, ENTRYPOINT, ENV, EXPOSE, USER, WORKDIR, STOPSIGNAL…). Không gồm: kernel, process đang chạy, dữ liệu sinh ra khi container chạy (trừ khi nằm trong volume — mà volume cũng không thuộc image).

**3. Copy-on-write?**
Container đọc trực tiếp từ layer chỉ đọc của image; chỉ khi sửa một file thì file đó được chép lên layer ghi được riêng của container rồi mới sửa. 10 container dùng chung một bản layer image trên đĩa, mỗi cái chỉ tốn thêm phần đã ghi.

**4. Phân tích tên:**
`ghcr.io` (registry GitHub Container Registry) / `phuong-dev` (namespace — tài khoản) / `taskhub` (repository) : `1.2.0` (tag). `nginx:1.30-alpine` = `docker.io/library/nginx:1.30-alpine`.

**5. Vì sao không dùng `latest`?**
`latest` là nhãn có thể bị gán lại; cùng tên có thể trỏ tới image khác nhau theo thời gian → các server chạy phiên bản khác nhau, không rollback chắc chắn được, không biết đang chạy code nào. `taskhub` dùng tag SemVer (`1.2.0`) cho phát hành và tag SHA commit (`sha-3f2a9c1`) để truy ngược code.

**6. Tag vs digest?**
Tag do người đặt, có thể bị gán lại. Digest là SHA-256 của nội dung, bất biến. Pin bằng digest khi cần đảm bảo tuyệt đối đúng từng byte: môi trường cần kiểm toán, chống việc image upstream bị thay thế, base image trong Dockerfile production.

**7. `-p 8080:80` vs `-p 127.0.0.1:8080:80`?**
Cả hai tạo DNAT host:8080 → container:80 (Network bài 04). Bản đầu nghe trên mọi interface của host (0.0.0.0) — máy khác tới được nếu firewall cho phép; bản sau chỉ nghe loopback — chỉ chính host truy cập (Network bài 05).

**8. `EXPOSE` có publish không?**
Không. Chỉ là metadata ghi chú port app dùng (và gợi ý cho `-P` publish ngẫu nhiên). Muốn truy cập từ host phải `-p`.

**9. App nghe `127.0.0.1:8080` trong container + `-p 8080:8080`?**
Không truy cập được. Gói tin DNAT đi tới `eth0` của container (ví dụ `172.17.0.2:8080`), nhưng app chỉ nghe trên loopback của namespace mạng container → kernel trả RST, curl thường báo `Connection reset by peer` hoặc `Empty reply`. App trong container phải nghe `0.0.0.0`.

**10. File sửa trong container?**
Còn sau `restart` (cùng container, cùng layer ghi được). Mất sau `rm` + `run` (container mới, layer ghi được mới).

**11. `docker logs` lấy từ đâu?**
Từ stdout/stderr của process chính, Engine thu lại qua log driver. App ghi log ra stdout thì Docker, Compose, Kubernetes, CloudWatch agent… đều thu được thống nhất; log ghi vào file trong container thì bị kẹt trong layer ghi được và mất theo container.

**12. `CMD sh -c "java -jar app.jar"`?**
PID 1 là `sh`, `java` là process con. `docker stop` gửi SIGTERM cho PID 1 (`sh`), `sh` không chuyển tiếp cho `java` và (là init của namespace) bỏ qua SIGTERM → hết 10 giây bị SIGKILL → Spring Boot không graceful shutdown, request dở dang bị cắt, exit 137.

**13. Cờ đặt sau tên image?**
Bị coi là lệnh/tham số cho process trong container, không phải cờ của Docker.

**14. Đọc `docker history`?**
Từ dưới lên (dưới cùng là layer đầu tiên). `0B` là bước chỉ thay đổi metadata (CMD, ENV, EXPOSE…), không thêm dữ liệu.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — So sánh biến thể

```bash
for t in 21-jdk-noble 21-jre-noble 21-jre-alpine; do docker pull -q eclipse-temurin:$t; done
docker images eclipse-temurin
for t in 21-jdk-noble 21-jre-noble 21-jre-alpine; do
  echo "== $t"; docker run --rm eclipse-temurin:$t javac -version 2>&1 | head -1
done
```

Kết quả dạng (kích thước minh họa — xem số thật trên máy bạn):

| Image | Kích thước tương đối | `javac` |
|---|---|---|
| `21-jdk-noble` | Lớn nhất (vài trăm MB) | Có |
| `21-jre-noble` | Khoảng một nửa JDK | Không — lỗi `executable file not found` (exit 127) |
| `21-jre-alpine` | Nhỏ nhất | Không |

- Build (`./mvnw package` cần `javac`) → `21-jdk-noble`. Chạy (chỉ cần `java`) → `21-jre-noble`. Đây chính là ý tưởng của multi-stage build (bài 03): build ở image lớn, chỉ chép `app.jar` sang image nhỏ.
- Chọn noble thay vì alpine: cùng nền Ubuntu 24.04 với EC2 và với `glibc`, tránh khác biệt hành vi của `musl` (DNS resolver, một số thư viện native); tài liệu và kinh nghiệm cộng đồng nhiều hơn. Alpine nhỏ hơn — có thể cân nhắc khi đã kiểm thử kỹ.

### Bài 2 — Thám tử layer

```bash
docker run -d --name layertest ubuntu:22.04 sleep 3600
docker ps -s --filter name=layertest --format '{{.Size}}'      # ~0B
docker exec layertest sh -c 'apt-get update && apt-get install -y openjdk-17-jdk-headless'
docker ps -s --filter name=layertest --format '{{.Size}}'      # vài trăm MB
docker exec layertest sh -c 'apt-get remove -y --purge openjdk-17-jdk-headless && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*'
docker ps -s --filter name=layertest --format '{{.Size}}'      # giảm lại
docker rm -f layertest
```

Trong **cùng một layer ghi được**, xóa file thì dung lượng giảm thật vì file nằm ngay ở layer đó. Nhưng với **image**: nếu một lệnh Dockerfile cài gói (layer N) và một lệnh **sau** xóa gói (layer N+1), layer N vẫn nằm nguyên trong image — layer N+1 chỉ thêm dấu "đã xóa" (whiteout). Image không nhỏ đi.

Ý nghĩa cho bài 03: cài đặt và dọn dẹp phải nằm **trong cùng một lệnh `RUN`**, ví dụ:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
```

### Bài 3 — Script dọn dẹp an toàn

```bash
#!/usr/bin/env bash
# docker-cleanup.sh — dọn container dừng >24h và image dangling. KHÔNG đụng volume.
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

log() { echo "[$(date '+%F %T')] $*"; }

log "Dung lượng TRƯỚC khi dọn:"
docker system df

if $DRY_RUN; then
  log "[dry-run] Container đã dừng sẽ bị xóa (tạo hơn 24h trước):"
  docker ps -a --filter status=exited --filter "until=24h" \
    --format '  {{.ID}}  {{.Names}}  {{.Status}}' 2>/dev/null \
    || docker ps -a --filter status=exited --format '  {{.ID}}  {{.Names}}  {{.Status}}  (bản Docker này không hỗ trợ lọc until cho ps)'
  log "[dry-run] Image dangling sẽ bị xóa:"
  docker images --filter dangling=true --format '  {{.ID}}  {{.Size}}'
  exit 0
fi

docker container prune -f --filter "until=24h"
docker image prune -f
log "Dung lượng SAU khi dọn:"
docker system df
```

Điểm chấm:
- `set -euo pipefail` ([Linux bài 06](../../01-LINUX/06-bash-scripting.md)).
- `prune -f` bỏ hỏi xác nhận — chấp nhận được trong script **vì** phạm vi đã giới hạn rõ (`until=24h`, chỉ dangling) và có chế độ `--dry-run`.
- Không có `docker volume prune`, không có `--volumes`, không có `image prune -a`.
- `docker ps` có thể không hỗ trợ bộ lọc `until` trên mọi phiên bản — lời giải có nhánh dự phòng. Bạn tự kiểm tra với `docker ps --help`/tài liệu phiên bản của mình; `docker container prune --filter until=24h` thì có hỗ trợ.

### Bài 4 — Ba lỗi kết nối

| Trường hợp | Lệnh tái hiện | `curl` báo (minh họa) | Chẩn đoán |
|---|---|---|---|
| (a) Không publish | `docker run -d --name a nginx:1.30-alpine` → `curl localhost:8080` | `curl: (7) Failed to connect to localhost port 8080 ... Connection refused` | `docker ps` → cột PORTS trống; `docker port a` không in gì |
| (b) Sai port bên trong | `docker run -d --name b -p 8080:8080 nginx:1.30-alpine` | `curl: (56) Recv failure: Connection reset by peer` hoặc `Empty reply from server` | `docker port b` → `8080/tcp -> 0.0.0.0:8080`; `docker inspect --format '{{json .Config.ExposedPorts}}' nginx:1.30-alpine` → nginx nghe 80 |
| (c) App nghe loopback | `docker run -d --name c -p 8000:8000 python:3.12-slim python -m http.server 8000 --bind 127.0.0.1` | Giống (b): reset/empty reply | `docker logs c` → `Serving HTTP on 127.0.0.1 port 8000`; `docker exec c python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000').status)"` → 200 (bên trong được, bên ngoài không) |

Ghi chú: ở (b) và (c), trên Docker Desktop kết nối tới cổng host **có** được chấp nhận bởi tiến trình chuyển tiếp port của Docker, nên lỗi thường là "reset"/"empty reply" chứ không phải "refused". Trên Linux thuần với DNAT kernel, có thể thấy `Connection refused` thay vì reset. Câu chữ chính xác phụ thuộc môi trường — điều cần nắm là **phân biệt được (a) với (b)/(c)** và biết lệnh để xác nhận.

Dọn: `docker rm -f a b c`.

### Bài 5 — Tag và digest

```bash
docker pull nginx:1.31-alpine
docker tag nginx:1.30-alpine mynginx:latest
docker images mynginx            # IMAGE ID trùng với nginx:1.30-alpine
docker tag nginx:1.31-alpine mynginx:latest
docker images mynginx            # IMAGE ID giờ trùng với nginx:1.31-alpine
```

- `docker tag` không chép image, chỉ thêm một **nhãn** trỏ vào image ID. Gán lại `mynginx:latest` chỉ chuyển nhãn sang image khác.
- Image 1.30 không mất vì vẫn còn tag `nginx:1.30-alpine`. Nếu image cũ **không còn tag nào khác**, nó sẽ hiện thành `<none>:<none>` (dangling) — chính loại image mà `docker image prune` dọn.
- Giải thích cho đồng đội: "Hôm qua `mynginx:latest` là 1.30, hôm nay là 1.31. Server nào kéo hôm qua chạy 1.30, server kéo hôm nay chạy 1.31 — cùng một dòng cấu hình `mynginx:latest`. Rollback về 'latest hôm qua' là không thể vì nhãn đã đổi. Dùng tag cố định (SemVer/SHA) hoặc digest."
