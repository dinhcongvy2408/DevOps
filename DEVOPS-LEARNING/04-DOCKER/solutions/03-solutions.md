# Lời giải — Bài 03: Dockerfile & Multi-stage build

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [03-dockerfile-multistage.md](../03-dockerfile-multistage.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)
- [Phần C — Phân tích Bước 8 của lab](#phần-c--phân-tích-bước-8-của-lab)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Build context là tập file Docker CLI gửi cho builder (thư mục cuối lệnh `docker build`). Builder **chỉ** đọc được file trong context. `../config.yml` nằm ngoài context nên không tồn tại đối với builder → lỗi `not found`. Muốn dùng file đó: đưa nó vào trong context, hoặc chạy build với context là thư mục cha (`docker build -f sub/Dockerfile ..`).

**2.** Tốc độ: không gửi `target/`, `.git`… (có thể hàng trăm MB) → build bắt đầu nhanh, `COPY .` không vô tình phá cache vì file rác thay đổi. Bảo mật: `.env`, khóa, `.git` (chứa lịch sử có thể có secret cũ) không lọt vào image qua `COPY . .`.

**3.** Chưa an toàn. Mỗi instruction tạo một layer; layer chỉ được **thêm chồng lên**, không sửa layer cũ. `COPY . .` tạo layer chứa `.env`; `RUN rm .env` tạo layer mới ghi "file đã bị xóa" (whiteout). Container không thấy file, nhưng layer cũ vẫn nằm trong image — ai có image (`docker save` rồi giải nén từng layer) là lấy được.

**4.** `ARG` chỉ tồn tại lúc build, đặt bằng `--build-arg`. `ENV` tồn tại lúc build **và** được ghi vào metadata image → có trong mọi container. Biến còn khi chạy: `ENV`. (Cả hai đều có thể lộ: `ENV` qua `inspect`, `ARG` qua `history`.)

**5.** Không. `EXPOSE` chỉ là tài liệu. Cần `docker run -p 8080:8080` (hoặc `-P`), và trong dự án là Nginx publish port rồi proxy vào app.

**6.** Layer cache: một layer đổi thì mọi layer sau build lại. `pom.xml` ít đổi, `src/` đổi liên tục. Copy `pom.xml` + tải dependency trước → khi sửa code, layer dependency vẫn `CACHED`, chỉ biên dịch lại.

**7.** Tách môi trường build (JDK, Maven, source, cache thư viện) khỏi môi trường chạy (JRE + jar). Image cuối chỉ gồm **stage cuối cùng** (hoặc stage chỉ định bằng `--target`) — các stage trước chỉ là nơi tạo ra file để `COPY --from`.

**8.** Shell form chạy qua `/bin/sh -c`, `sh` là PID 1 và không chuyển tiếp tín hiệu. Exec form chạy thẳng chương trình làm PID 1. Hậu quả với Spring Boot shell form: `docker stop` gửi `SIGTERM` cho `sh`, Spring Boot không biết để tắt nhẹ nhàng; sau 10 giây Docker gửi `SIGKILL` → request đang xử lý bị cắt, kết nối DB không đóng sạch, exit code 137, mỗi lần deploy chậm thêm 10 giây.

**9.** 137 = 128 + 9 → bị `SIGKILL` (do `docker stop` hết giờ chờ hoặc OOM killer). 143 = 128 + 15 → process thoát sau khi nhận `SIGTERM` (tắt bình thường theo yêu cầu).

**10.** Ubuntu 24.04 đã có user `ubuntu` UID 1000 → `useradd -u 1000` báo `UID 1000 is not unique`. `--system` cấp UID trong dải system user (< 1000), không xung đột, và đúng ngữ nghĩa "user chạy dịch vụ".

**11.** Nguyên tắc least privilege: app cần **đọc** jar, không cần **sửa**. Nếu app bị khai thác, kẻ tấn công không ghi đè được code để cài mã độc tồn tại lâu. Cùng thiết kế với `/opt/taskhub` ở Linux bài 03.

**12.** Lệnh healthcheck trả `0` = healthy, `1` = unhealthy (không dùng `2`). Sau `retries` lần thất bại liên tiếp → `unhealthy`. `--start-period`: khoảng thời gian khởi động, thất bại trong giai đoạn này không bị tính vào số lần thử — tránh đánh dấu unhealthy một app Spring Boot đang khởi động 30–40 giây.

**13.** Chính container đó — lệnh `HEALTHCHECK` chạy **bên trong** container, trong network namespace của nó. App nghe port 8080 của container nên `localhost:8080` đúng.

**14.** Mặc định heap tối đa chỉ ~25% RAM của container → lãng phí RAM được cấp hoặc `OutOfMemoryError` sớm. `MaxRAMPercentage=75` dùng phần lớn RAM cho heap, chừa phần còn lại cho bộ nhớ ngoài heap. Vượt giới hạn RAM của container → kernel OOM killer giết process → container thoát với exit code 137.

**15.** Alpine dùng musl thay glibc; một số thư viện native (driver, thư viện nén, font…) có thể lỗi hoặc chậm hơn. `jre-noble` cùng nền Ubuntu với EC2, có công cụ debug cơ bản, ít bất ngờ — phù hợp người mới. Tối ưu kích thước chỉ đáng làm khi có lý do đo được.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Review Dockerfile

Các vấn đề:

| # | Dòng | Vấn đề |
|---|---|---|
| 1 | `FROM eclipse-temurin:latest` | Tag `latest`: không cố định phiên bản Java và nền OS; là JDK nên image to |
| 2 | `RUN apt-get update` tách riêng | Layer `update` bị cache cũ; danh mục gói nằm vĩnh viễn trong image |
| 3 | `apt-get install curl vim git` | Thiếu `-y` → build treo/fail; thiếu `--no-install-recommends`; `vim`, `git` không cần lúc chạy; không xóa `/var/lib/apt/lists` |
| 4 | `ADD . /app` | Dùng `ADD` thay `COPY`; copy toàn bộ context (không thấy `.dockerignore`) → mất cache, có thể lọt `.env`/`.git` |
| 5 | `RUN cd /app && ./mvnw package` | Không tách tải dependency → mất cache; chạy test trong build (chậm); nên dùng `WORKDIR` |
| 6 | `ENV SPRING_DATASOURCE_PASSWORD=...` | Secret trong image |
| 7 | Không có `USER` | Chạy bằng root |
| 8 | `CMD java -jar ...` | Shell form → không nhận `SIGTERM`; hard-code tên jar có version |
| 9 | Không multi-stage | Image chạy chứa JDK, source, `~/.m2` |

Bản viết lại: chính là Dockerfile ở mục 4.12 của bài. Mật khẩu chuyển sang truyền lúc chạy (`--env-file`).

### Bài 2 — Thứ tự cache (Node.js)

```dockerfile
FROM node:22-bookworm-slim
WORKDIR /app
# File mô tả dependency — ít đổi
COPY package.json package-lock.json ./
# Cài đúng theo lock file — layer được cache cho tới khi lock file đổi
RUN npm ci --omit=dev
# Code — đổi thường xuyên, đặt sau
COPY app/src/ src/
USER node
CMD ["node", "src/index.js"]
```

Lý do: giống hệt Maven — `npm ci` (tương đương `dependency:go-offline`) chỉ chạy lại khi `package*.json` đổi. Image `node` có sẵn user `node` nên dùng luôn làm non-root. `CMD` exec form. Đạt nếu bạn có đúng thứ tự "manifest → cài → code" và exec form; `--omit=dev`, `USER` là điểm cộng.

### Bài 3 — Tìm secret trong image

```bash
docker image inspect leaky --format '{{json .Config.Env}}'
# ["PATH=...","API_TOKEN=tok_123456"]

docker history --no-trunc leaky
# ... RUN |1 BUILD_SECRET=s3cr3t /bin/sh -c echo "secret is $BUILD_SECRET" > /dev/null
```

Kết luận: `ENV` nằm thẳng trong cấu hình image. `ARG` không thành biến môi trường của container, nhưng khi một `RUN` dùng nó, giá trị xuất hiện trong lịch sử build (dòng `RUN |1 BUILD_SECRET=...`). Cả hai đều đọc được **không cần chạy container**. (Định dạng chính xác của dòng history có thể khác theo phiên bản BuildKit — điều quan trọng là bạn tìm thấy giá trị.) Cách đúng cho secret lúc build: `RUN --mount=type=secret` (docs Dockerfile khuyến nghị); lúc chạy: biến môi trường/secret truyền vào container.

### Bài 4 — Stage test

```dockerfile
FROM eclipse-temurin:21-jdk-noble AS build
# ... như mục 4.12 (go-offline, COPY src, package)

FROM build AS test
RUN ./mvnw -B test

FROM eclipse-temurin:21-jre-noble AS runtime
# ... COPY --from=build ...
```

- `docker build -f docker/Dockerfile -t taskhub:dev .` → build stage cuối (`runtime`). `runtime` chỉ phụ thuộc `build` (qua `COPY --from=build`), **không** phụ thuộc `test` → BuildKit bỏ qua `test`. Docs: BuildKit *"only builds the stages that the target stage depends on"*.
- `docker build --target test ...` → build `build` rồi `test`, chạy test; lỗi test làm build thất bại (exit code khác 0) — hữu ích trong CI.

Lưu ý thứ tự: stage `runtime` phải là stage **cuối cùng** trong file để là mặc định.

### Bài 5 — Layered jar

```dockerfile
# syntax=docker/dockerfile:1
FROM eclipse-temurin:21-jdk-noble AS build
WORKDIR /workspace
COPY app/mvnw app/pom.xml ./
COPY app/.mvn/ .mvn/
RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline
COPY app/src/ src/
RUN ./mvnw -B -q package -DskipTests && cp target/*.jar application.jar \
 && java -Djarmode=tools -jar application.jar extract --layers --destination extracted

FROM eclipse-temurin:21-jre-noble AS runtime
RUN groupadd --system taskhub \
 && useradd --system --gid taskhub --no-create-home --shell /usr/sbin/nologin taskhub
WORKDIR /app
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/spring-boot-loader/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./
USER taskhub
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "application.jar"]
```

Kết quả mong đợi khi chỉ sửa code:

- Dockerfile thường: layer `COPY app.jar` thay đổi toàn bộ (~50MB).
- Dockerfile layered: chỉ layer `application/` thay đổi (thường vài chục đến vài trăm KB); `dependencies/` (lớn nhất) giữ nguyên digest. Khi push lên registry (bài 06), chỉ layer nhỏ được đẩy.

`application.jar` sau khi extract không phải fat jar — nó chỉ chứa code của bạn và tham chiếu tới thư viện đã tách ra (theo tài liệu Spring Boot). Cú pháp `-Djarmode=tools ... extract --layers --destination` lấy từ tài liệu Spring Boot hiện hành; tutorial cũ dùng `layertools`.

---

## Phần C — Phân tích Bước 8 của lab

**`execform`:** `jwebserver` (một process Java) là PID 1. JVM cài sẵn bộ xử lý (handler) cho `SIGTERM` → nhận tín hiệu, chạy shutdown hook, thoát. Exit code `143`. Spring Boot hoạt động y hệt — và còn tắt nhẹ nhàng (graceful shutdown): ngừng nhận request mới, chờ request đang chạy xong ([Linux bài 04](../../01-LINUX/04-processes-systemd.md)).

**`shellform`:** `sh` là PID 1, `java` là process con. Hai điều cùng xảy ra:

1. `sh` không chuyển tiếp `SIGTERM` cho process con.
2. Kernel đối xử đặc biệt với **PID 1 của một PID namespace**: tín hiệu mà process không cài handler sẽ **bị bỏ qua** thay vì áp dụng hành động mặc định (chết). `sh` không cài handler cho `SIGTERM` → phớt lờ hoàn toàn.

Docker chờ hết thời gian (mặc định 10 giây) rồi gửi `SIGKILL` (không thể bỏ qua, kể cả PID 1) → exit code `137`.

Vì sao lab thêm `; echo stopped`? Với lệnh đơn `sh -c 'jwebserver ...'`, một số shell tối ưu bằng cách `exec` thẳng chương trình (thay chính nó), khiến java vẫn thành PID 1 và thí nghiệm không còn ý nghĩa. Thêm lệnh thứ hai buộc `sh` phải ở lại để chạy tiếp sau khi java kết thúc.

**Bài học:** đừng chỉ dựa vào "app của tôi xử lý `SIGTERM`" — phải chắc app **nhận được** `SIGTERM`, tức là app phải là PID 1 (exec form), hoặc có một init process nhỏ chuyên chuyển tiếp tín hiệu (🟦 `docker run --init`).
