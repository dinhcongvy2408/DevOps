# Lời giải — Bài 08: Container Troubleshooting

> ⚠️ Chỉ đọc sau khi đã tự làm và ghi câu trả lời của bạn. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [08-container-troubleshooting.md](../08-container-troubleshooting.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Container sống chừng nào PID 1 còn sống. `ubuntu:22.04` mặc định chạy `bash`; không có `-it` thì bash không có terminal, stdin kết thúc ngay → bash thoát bình thường → exit 0 → container dừng.

**2.** `1`: lỗi chung của app. `125`: lỗi của chính Docker khi tạo/chạy container (cờ sai, port bị chiếm, xung đột tên). `126`: lệnh tồn tại nhưng không thực thi được (thiếu quyền `x`, sai định dạng). `127`: không tìm thấy lệnh. `137`: SIGKILL (128+9). `143`: SIGTERM (128+15) — thường là dừng có chủ đích. Do Docker sinh ra: `125` (và `126`/`127` khi Docker không exec được lệnh).

**3.** (a) OOM killer — vượt giới hạn RAM; (b) `docker stop` hết thời gian chờ (mặc định 10 giây) mà PID 1 không dừng nên bị SIGKILL. Phân biệt bằng `docker inspect -f '{{.State.OOMKilled}}' <ctr>`; bổ sung bằng `docker events --filter event=oom` và việc lỗi xảy ra lúc bạn chủ động dừng hay tự phát.

**4.** (1) Trạng thái/exit code → (2) log → (3) cấu hình đã áp dụng → (4) vào bên trong → (5) mạng → (6) tài nguyên → (7) sự kiện. Exec ngay là bỏ qua thông tin rẻ và nhanh nhất (exit code, log) — thường đã đủ để biết nguyên nhân; hơn nữa container đã dừng thì không exec được, và thao tác tay bên trong dễ làm thay đổi hiện trường.

**5.** `compose config` = cấu hình Compose **định** áp dụng (đã thay biến `.env`, hợp nhất file); `inspect` = cấu hình **container đang chạy thật sự có**. Khác nhau nghĩa là container được tạo từ cấu hình cũ — bạn đã sửa file nhưng chưa `docker compose up -d` để tạo lại container.

**6.** `docker compose run --rm --entrypoint sh <service>` (hoặc `docker run --rm -it --entrypoint sh <image>`): container mới từ cùng image và cấu hình service, app không tự chạy, bạn có shell để kiểm tra file, quyền, biến môi trường.

**7.** (a) Container phụ chung network namespace: `docker run --rm -it --network container:<tên> <image-có-công-cụ>` — container phụ không có mạng riêng mà dùng chính interface, IP, port, `localhost` của container đích, nên `ss`, `curl localhost:...` thấy đúng những gì app thấy. (b) `docker debug <tên>` (Docker Desktop) hoặc biến thể `:debug` của distroless. Thêm: `docker cp` để lấy file ra phân tích.

**8.** Image không có sẵn `/data` (hoặc có nhưng thuộc root) → Docker tạo mount point bằng root, volume rỗng thuộc root; app UID không phải 0 không có quyền `w`. Sửa: trong Dockerfile `RUN mkdir /data && chown <user>:<group> /data` trước `USER`. Khi volume **rỗng** lần đầu được gắn vào đường dẫn có sẵn trong image, Docker sao chép nội dung và quyền của thư mục đó vào volume. Volume đã tồn tại (đã có nội dung/quyền) thì không được sao chép lại → phải tạo volume mới (hoặc chown thủ công bằng một container root chạy một lần).

**9.** Trong container, `localhost` là chính container app — PostgreSQL ở container khác. Đổi host thành **tên service** (`postgres:5432`), đảm bảo hai service chung network, và chờ DB healthy trước khi app khởi động.

**10.** `restart` chỉ dừng và chạy lại **container hiện có** với cấu hình cũ. Sửa `compose.yaml` → `docker compose up -d` (Compose phát hiện cấu hình đổi và tạo lại container). Sửa code → image phải build lại: `docker compose up -d --build`.

**11.** `json-file`. Mặc định không giới hạn kích thước → log của app ghi nhiều chạy lâu ngày có thể làm đầy ổ đĩa server. Hạn chế: `max-size`/`max-file` trong `logging.options` của Compose hoặc cấu hình mặc định trong `daemon.json`; đẩy log về hệ thống tập trung (Module 08).

**12.** Không. RECLAIMABLE chỉ có nghĩa là "hiện không có container nào dùng" — có thể là volume database của một project đang tạm dừng. Kiểm tra `docker volume ls`, xác định volume nào thuộc project nào, backup nếu cần, rồi xóa **có chọn lọc** bằng `docker volume rm <tên>`.

**13.** Lỗi không đến từ app: (a) Docker không chạy được lệnh (`executable file not found`, `permission denied`) — xem output của `docker run`/`compose up`; (b) bị kernel giết — `OOMKilled` trong inspect; (c) bị `docker stop`/`kill` — `docker events`; (d) app ghi log vào file thay vì stdout — `exec`/`run --entrypoint sh` vào xem file log; (e) app tự chạy nền nên PID 1 thoát ngay.

**14.** Kernel không chạy được file thực thi vì nó được biên dịch cho kiến trúc CPU khác (ví dụ image `amd64` trên máy `arm64`). Docker Desktop cài sẵn trình giả lập (QEMU/binfmt) nên chạy được image khác kiến trúc (chậm hơn) — lỗi bị che. EC2 Graviton (ARM64) không có giả lập → image `amd64` báo `exec format error`. Giải pháp: build đa kiến trúc (`docker buildx build --platform linux/amd64,linux/arm64`) hoặc build trên/cho đúng kiến trúc.

**15.** Lệnh healthcheck gọi một chương trình không có trong image (thường `curl` trong image `-slim`, Alpine, distroless). Sửa không làm image to: viết healthcheck bằng thứ có sẵn — runtime của app (`python -c "import urllib.request..."`, Java thì dùng endpoint qua công cụ có sẵn, hoặc `wget` của busybox trong Alpine). Image `eclipse-temurin:21-jre-noble` của taskhub có sẵn `curl` nên không gặp vấn đề này — trừ khi đổi base image.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — PID 1 bỏ qua SIGTERM

```bash
docker run -d --name sig1 alpine:3.20 sh -c 'while true; do sleep 1; done'
time docker stop sig1
docker inspect -f 'exit={{.State.ExitCode}}' sig1

docker run -d --init --name sig2 alpine:3.20 sh -c 'while true; do sleep 1; done'
time docker stop sig2
docker inspect -f 'exit={{.State.ExitCode}}' sig2
docker rm sig1 sig2
```

Kết quả mong đợi (minh họa): `sig1` mất khoảng **10 giây**, exit `137`; `sig2` dừng gần như ngay, exit `143`.

Giải thích: ở `sig1`, PID 1 là `sh`. Kernel không áp dụng hành động mặc định "kết thúc" cho PID 1 trong namespace khi process không tự cài bộ xử lý tín hiệu → SIGTERM bị bỏ qua → Docker chờ hết hạn rồi SIGKILL (137). Với `--init`, PID 1 là `docker-init` (dựa trên tini) — nó chuyển tiếp SIGTERM cho `sh` (giờ là process thường, không phải PID 1) → `sh` bị kết thúc theo hành động mặc định → init thoát với mã tương ứng 143. `--init` cũng dọn process zombie.

Liên hệ Dockerfile: dạng shell `CMD java -jar app.jar` chạy thành `/bin/sh -c "java -jar app.jar"` — `sh` có thể là PID 1 và giữ SIGTERM lại. Dạng exec `CMD ["java", "-jar", "app.jar"]` chạy thẳng `java` làm PID 1, JVM nhận SIGTERM và Spring Boot tắt nhẹ nhàng.

### Bài 2 — Restart loop

Quan sát: STATUS luân phiên `Up 1 second` → `Restarting (1) ...`; `RestartCount` tăng dần 1…5; log lặp lại `starting` nhiều lần (log của mọi lần chạy được nối tiếp trong cùng container). `docker events` cho thấy cặp `die` (exitCode=1) → `start`, khoảng cách giữa các lần **tăng dần** (Docker giãn thời gian chờ để tránh khởi động liên tục). Sau 5 lần thử lại, Docker **dừng hẳn**: `Exited (1)`, `RestartCount` = 5. Bài học: restart policy giúp tự phục hồi lỗi thoáng qua, nhưng với lỗi cố định nó chỉ lặp lại cái chết — phải đọc log để tìm nguyên nhân gốc.

### Bài 3 — Debug mạng container không có shell

```bash
docker run -d --name web3 nginx:1.30-alpine
docker run --rm -it --network container:web3 nicolaka/netshoot
# bên trong netshoot:
ss -tlnp
curl -sI localhost:80 | head -1
ip -4 addr show eth0
exit
docker rm -f web3
```

- `ss` hiện nginx nghe `0.0.0.0:80` (cột process có thể không hiện tên vì process thuộc container khác — namespace PID khác).
- `curl localhost:80` trả `HTTP/1.1 200 OK` — `localhost` của netshoot chính là `localhost` của web3.
- IP của `eth0` trùng với IP của web3 (`docker inspect web3`).

Không muốn dùng image bên thứ ba: `docker run --rm -it --network container:web3 ubuntu:22.04 bash -c 'apt-get -qq update && apt-get -qq install -y iproute2 curl >/dev/null && ss -tln && curl -sI localhost | head -1'`.

### Bài 4 — Runbook

Không có đáp án duy nhất. Runbook đạt khi: vừa một trang, người khác làm theo được không cần hỏi; có bảng exit code; 5 lệnh đầu tiên theo đúng thứ tự quy trình (`compose ps -a` → `logs --tail` → `inspect` State/Health → `compose config` → `exec`/`run --entrypoint`); 5 lỗi lấy từ trải nghiệm **thật** của bạn với taskhub (ví dụ: `UnknownHostException: postgres`, `password authentication failed` sau khi đổi `.env`, unhealthy do `start_period` ngắn, port 8000 bị nginx của WSL chiếm, quên `--build`), mỗi lỗi có triệu chứng nguyên văn → lệnh xác nhận → cách sửa.

### Bài 5 — Log không giới hạn

- `docker inspect -f '{{.LogPath}}' noisy` trả một đường dẫn kiểu `/var/lib/docker/containers/<id>/<id>-json.log` — nằm **trong máy ảo của Docker Desktop**, không nằm trong filesystem WSL của bạn, nên `ls` từ WSL thường không thấy. Đây cũng là minh họa: Docker Desktop ≠ Docker cài thẳng trên server.
- Sau 30 giây không giới hạn: hàng trăm nghìn tới hàng triệu dòng (`docker logs noisy | wc -l`) — tùy tốc độ máy.
- Với `--log-opt max-size=1m --log-opt max-file=2`: số dòng `docker logs` trả về bị chặn ở mức tương ứng khoảng 2 file × 1MB (vài chục nghìn dòng); các dòng cũ hơn bị xóa khi file xoay vòng. Đánh đổi: tiết kiệm ổ đĩa nhưng mất log cũ → cần đẩy log về hệ thống tập trung nếu muốn giữ lâu (Module 08).
