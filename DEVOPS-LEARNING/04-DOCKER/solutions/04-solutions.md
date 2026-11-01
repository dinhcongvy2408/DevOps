# Lời giải — Bài 04: Volumes, Networks & biến môi trường

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [04-volumes-networks-env.md](../04-volumes-networks-env.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Dữ liệu ghi vào layer ghi được của container; layer đó bị xóa cùng container. Không phải lỗi: container được thiết kế để thay thế được bất cứ lúc nào (deploy = thay container). Dữ liệu cần giữ phải nằm ngoài (volume).

**2.** Named volume: Docker quản lý, độc lập host, dễ backup → **database**. Bind mount: thư mục host chọn sẵn, chia sẻ file hai chiều → **file cấu hình/code khi dev**. tmpfs: trong RAM, mất khi dừng → file tạm, dữ liệu nhạy cảm không muốn ghi đĩa.

**3.** `postgres:18` lưu dữ liệu ở `/var/lib/postgresql/18/docker` và khai báo volume ở `/var/lib/postgresql`. Gắn vào `.../data` theo thói quen → dữ liệu thật không nằm trong volume của bạn (hoặc image báo lỗi, tùy phiên bản) → mất dữ liệu khi tạo lại container. Ngoài ra nâng major version cần `pg_upgrade` hoặc dump/restore. Phải đọc trang image trên Docker Hub (mục `PGDATA`, biến môi trường) và release notes của PostgreSQL.

**4.** Script khởi tạo của image chỉ chạy khi thư mục dữ liệu **trống**. Volume cũ đã có database → bỏ qua khởi tạo → các biến `POSTGRES_*` bị phớt lờ. Mật khẩu nằm trong dữ liệu database, không phải trong biến.

**5.** Kernel kiểm tra quyền bằng UID số. Thư mục thuộc UID 1000 (`phuong` trên WSL) quyền `755`; process trong container UID 999 không phải owner, không thuộc group → chỉ có quyền "others" `r-x` → không ghi được. Tên user hai bên khác nhau không quan trọng; chỉ số UID quan trọng.

**6.** (1) User-defined có DNS phân giải tên container; default chỉ dùng IP. (2) User-defined cô lập: chỉ container được gắn vào mới nói chuyện với nhau; default chứa mọi container không chỉ định network.

**7.** Địa chỉ DNS server nhúng của Docker trên user-defined network: trả lời tên container/service cùng network, chuyển tiếp câu hỏi khác ra DNS bên ngoài.

**8.** `localhost` trong container `taskhub` là loopback riêng của chính nó; không có ai nghe 5432 ở đó → `Connection refused`. Sửa: đặt hai container cùng user-defined network, dùng `jdbc:postgresql://postgres:5432/taskhub`.

**9.** Port `5432` — port mà process postgres nghe bên trong container. `5433` chỉ là port trên **host** được DNAT tới container, dùng cho truy cập từ ngoài host.

**10.** Giảm bề mặt tấn công: chỉ một điểm vào (reverse proxy) — nơi đặt TLS, giới hạn request, log tập trung. App và DB không publish → không ai từ ngoài chạm trực tiếp được; chúng vẫn nói chuyện qua network nội bộ.

**11.** `SPRING_DATASOURCE_PASSWORD`. Quy tắc: thay `.` bằng `_`, bỏ `-`, viết hoa.

**12.** Biến môi trường thắng (nằm trên file cấu hình trong thứ tự ưu tiên của Spring Boot). Tham số dòng lệnh `--spring.datasource.url=...` còn thắng cả biến môi trường.

**13.** `docker image inspect <image>` (trường `Config.Env`) và `docker history --no-trunc <image>`. Không cần chạy container.

**14.** Tên DNS đặc biệt của Docker Desktop trỏ tới IP nội bộ của máy host, để container gọi dịch vụ chạy trên host. Không dùng ở production vì Docker Engine trên Linux (EC2) không có sẵn tên này, và kiến trúc production không nên phụ thuộc dịch vụ chạy ngoài container theo cách đó.

**15.** PostgreSQL đang ghi dở các file dữ liệu và WAL; `tar` copy từng file ở các thời điểm khác nhau → bản backup có thể không nhất quán, restore ra database hỏng. Phải dừng postgres trước, hoặc dùng `pg_dump` (backup logic nhất quán khi DB đang chạy).

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Ba lỗi, một hệ thống

Vấn đề:

1. **Không có user-defined network**: cả hai ở default bridge → `app` không phân giải được tên `db` (`UnknownHostException`).
2. **Sai port**: app gọi `db:5433` — đó là port publish trên host; container ↔ container phải dùng `5432`.
3. **Không có volume**: dữ liệu DB mất khi xóa container (vấn đề dữ liệu).
4. **Publish port DB ra mọi địa chỉ** (`-p 5433:5432`): không cần thiết và nguy hiểm trên server thật.
5. Điểm phụ: mật khẩu yếu đặt thẳng trên dòng lệnh (lọt vào lịch sử shell); dùng user `postgres` (superuser) cho app thay vì user riêng.

Lệnh đúng:

```bash
docker network create taskhub-net
docker run -d --name db --network taskhub-net \
  -e POSTGRES_DB=taskhub -e POSTGRES_USER=taskhub -e POSTGRES_PASSWORD="$DB_PASS" \
  -v taskhub-pgdata:/var/lib/postgresql/data postgres:17
docker run -d --name app --network taskhub-net --env-file taskhub.env -p 8080:8080 taskhub:dev
# taskhub.env: SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/taskhub (+ username/password)
```

### Bài 2 — Hai network

```bash
docker network create frontend
docker network create backend
docker run -d --name postgres --network backend -e POSTGRES_PASSWORD=dev-only-pass postgres:17
docker run -d --name taskhub --network backend --env-file taskhub.env taskhub:dev
docker network connect frontend taskhub          # taskhub ở cả hai network
docker run -d --name nginx --network frontend nginx:1.30-alpine

# Kiểm chứng (getent có trong image nginx alpine — musl libc)
docker exec nginx getent hosts taskhub      # có IP → OK
docker exec taskhub getent hosts postgres   # có IP → OK
docker exec nginx getent hosts postgres     # không in gì, exit code khác 0 → bị cô lập
```

`taskhub` là "cầu nối" duy nhất. Đây chính là mô hình public/private subnet thu nhỏ (Network bài 04, Module 06): web tier ra ngoài được, DB chỉ app tier chạm được. Nếu `getent` không có trong image nào đó, dùng `nslookup` (BusyBox trong Alpine) hoặc chạy container tạm `docker run --rm --network frontend eclipse-temurin:21-jre-noble getent hosts postgres`.

### Bài 3 — Backup và restore volume

```bash
# (a) Dừng để dữ liệu nhất quán, rồi backup
docker stop postgres
docker run --rm -v taskhub-pgdata:/source:ro -v "$PWD":/backup ubuntu:24.04 \
  tar czf /backup/pgdata.tar.gz -C /source .
docker start postgres

# (b) Restore vào volume mới
docker volume create taskhub-pgdata-restore
docker run --rm -v taskhub-pgdata-restore:/target -v "$PWD":/backup ubuntu:24.04 \
  tar xzf /backup/pgdata.tar.gz -C /target

# (c) Chạy postgres với volume mới (không cần POSTGRES_* vì volume đã có dữ liệu)
docker run -d --name pg-restore -v taskhub-pgdata-restore:/var/lib/postgresql/data postgres:17
sleep 5
docker exec pg-restore psql -U taskhub -d taskhub -c "SELECT * FROM note;"
```

`tar` (chạy bằng root trong container) giữ nguyên owner/quyền số của file → postgres đọc được dữ liệu. Phải dừng postgres trước vì lý do ở câu A15. Lưu ý: `POSTGRES_PASSWORD` không cần ở bước (c) vì script khởi tạo bị bỏ qua — nhưng một số phiên bản image vẫn kiểm tra biến; nếu báo lỗi thiếu mật khẩu, thêm `-e POSTGRES_PASSWORD=...` (giá trị không ảnh hưởng database đã có).

### Bài 4 — Init script

```bash
mkdir -p ~/devops-lab/04-docker/init
cat > ~/devops-lab/04-docker/init/01-audit.sql <<'EOF'
CREATE TABLE audit_log (id serial PRIMARY KEY, msg text, at timestamptz DEFAULT now());
EOF
docker run -d --name pg-init -e POSTGRES_PASSWORD=dev-only-pass \
  -v pginit-data:/var/lib/postgresql/data \
  -v ~/devops-lab/04-docker/init:/docker-entrypoint-initdb.d:ro postgres:17
sleep 5
docker exec pg-init psql -U postgres -c '\dt'
```

Sửa file `.sql` (thêm bảng khác), `docker rm -f pg-init`, chạy lại với **cùng volume** → file mới **không** chạy. Lý do giống câu A4: thư mục init chỉ được xử lý khi khởi tạo database lần đầu (thư mục dữ liệu trống). Thay đổi schema sau đó phải dùng công cụ migration — taskhub dùng **Flyway** cho việc này (đặc tả tuần 6).

### Bài 5 — Profile cấu hình

| Thuộc tính | Biến môi trường |
|---|---|
| `server.port` | `SERVER_PORT=9090` |
| `logging.level.com.taskhub` | `LOGGING_LEVEL_COM_TASKHUB=DEBUG` |

```bash
docker run -d --name taskhub --network taskhub-net --env-file taskhub.env \
  -e SERVER_PORT=9090 -e LOGGING_LEVEL_COM_TASKHUB=DEBUG -p 9090:9090 taskhub:dev
docker logs taskhub 2>&1 | grep -E "Tomcat started on port|DEBUG" | head
curl -s localhost:9090/actuator/health
```

Lưu ý: đổi port app thì phải đổi cả `-p` (vế phải là port container) **và** `HEALTHCHECK` trong Dockerfile đang gọi cứng `localhost:8080` → container sẽ báo `unhealthy` dù app chạy tốt. Đây là bài học về việc giữ cấu hình nhất quán ở mọi nơi (ở Compose/Kubernetes, healthcheck thường được khai báo cùng chỗ với port). Dòng log khởi động Tomcat có thể khác chữ giữa các phiên bản Spring Boot — tìm chuỗi chứa số port.
