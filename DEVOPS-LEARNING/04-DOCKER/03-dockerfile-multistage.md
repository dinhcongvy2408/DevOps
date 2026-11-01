# 03. Dockerfile & Multi-stage build

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. VM vs Container](01-vm-vs-container-architecture.md), [02. Images & Containers](02-images-containers.md), [Linux 04 — Processes & systemd](../01-LINUX/04-processes-systemd.md), [Linux 05 — Packages & SSH](../01-LINUX/05-packages-ssh.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (WSL integration), `[Container]` bên trong container

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

- Giải thích **build context** là gì và viết `.dockerignore` để không đưa `.git`, `.env`, `target/` vào image.
- Dùng đúng các instruction chính: `FROM`, `WORKDIR`, `COPY`, `RUN`, `ENV`, `ARG`, `EXPOSE`, `USER`, `ENTRYPOINT`, `CMD`, `HEALTHCHECK`.
- Giải thích vì sao **thứ tự instruction** quyết định tốc độ build (layer cache).
- Viết **Dockerfile multi-stage** cho `taskhub`: build bằng JDK, chạy bằng JRE, chạy bằng **user không phải root**.
- Phân biệt **shell form** và **exec form** — và hiểu vì sao sai cách khiến app không nhận được `SIGTERM`.
- Đo và so sánh kích thước, thời gian build giữa các phiên bản Dockerfile.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Dockerfile là thứ DevOps viết, review và sửa **hằng ngày**. Một Dockerfile tồi gây ra hậu quả rất thật:

| Dockerfile tồi | Hậu quả khi đi làm |
|---|---|
| Copy toàn bộ source trước khi tải dependency | Mỗi lần sửa 1 dòng code, pipeline CI tải lại hàng trăm MB thư viện Maven → build 8 phút thay vì 40 giây |
| Image runtime chứa cả JDK, Maven, source code | Image 700MB+, kéo (pull) chậm khi deploy, nhiều phần mềm hơn = nhiều lỗ hổng hơn khi quét bảo mật |
| `COPY . .` không có `.dockerignore` | File `.env` chứa mật khẩu DB và thư mục `.git` nằm trong image — ai pull được image là đọc được |
| `ENTRYPOINT java -jar app.jar` (shell form) | `docker stop` phải chờ 10 giây rồi kill cứng → request đang xử lý bị cắt, transaction dở dang |
| Chạy bằng root | Nếu app bị khai thác lỗ hổng, kẻ tấn công có root trong container — gần hơn một bước tới host |

Phỏng vấn Junior DevOps rất hay có câu: *"Viết Dockerfile cho một app Spring Boot và giải thích từng dòng"*. Sau bài này bạn làm được điều đó.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Dockerfile là "công thức nấu ăn"

**Dockerfile** (tệp mô tả image) là một file văn bản liệt kê **từng bước** để tạo ra một image. Lệnh `docker build` đọc công thức này và thực hiện từng bước theo thứ tự.

Ở [bài 02](02-images-containers.md) bạn đã biết: image gồm nhiều **layer** (lớp) xếp chồng, mỗi layer là một tập thay đổi trên filesystem. Bài này trả lời câu hỏi: **các layer đó từ đâu ra?** — Phần lớn instruction trong Dockerfile tạo ra một layer.

```text
Dockerfile                         Image
─────────────────────────          ──────────────────────────
FROM eclipse-temurin:21-jre  ───►  layer của image gốc (nhiều layer)
WORKDIR /app                 ───►  layer: tạo thư mục /app
COPY app.jar app.jar         ───►  layer: thêm file app.jar
ENTRYPOINT ["java","-jar"…]  ───►  (chỉ ghi metadata, không thêm file)
```

### 3.2. Build context — "nguyên liệu" được gửi cho builder

Khi chạy `docker build -f docker/Dockerfile .`, dấu `.` ở cuối là **build context** (ngữ cảnh build): tập file mà quá trình build **được phép đọc**. Docker CLI gửi toàn bộ thư mục này cho builder (BuildKit) trước khi build.

Hệ quả quan trọng:

- `COPY` chỉ copy được file **nằm trong build context**. `COPY ../secret.txt .` không hoạt động.
- Context càng to (có `target/`, `.git`, `node_modules`…) thì build càng chậm và càng dễ lỡ tay copy thứ không nên copy.

### 3.3. Hai "thời điểm" cần phân biệt

| Thời điểm | Khi nào | Instruction liên quan |
|---|---|---|
| **Build time** (lúc build) | `docker build` — tạo image | `FROM`, `COPY`, `RUN`, `ARG` |
| **Run time** (lúc chạy) | `docker run` — tạo container từ image | `ENTRYPOINT`, `CMD`, `USER`, `ENV`, `HEALTHCHECK`, `EXPOSE` (ghi vào metadata để dùng lúc chạy) |

Nhầm hai thời điểm này là nguồn gốc của rất nhiều câu hỏi "sao tôi đặt biến rồi mà app không thấy?".

---

## 4. Giải thích chi tiết

### 4.1. 🟥 `.dockerignore` — loại bỏ file khỏi build context

`.dockerignore` đặt ở **gốc build context** (với dự án taskhub là gốc repo). Cú pháp giống glob của shell, mỗi dòng một mẫu, `#` là comment, `!` là ngoại lệ, `**` khớp nhiều cấp thư mục.

`.dockerignore` cho taskhub:

```text
# Kết quả build trên máy — image sẽ tự build lại bên trong.
# "**/" để khớp ở mọi cấp: code nằm trong app/ nên thư mục build là app/target/,
# mẫu "target/" (không có **/) chỉ khớp target/ ở GỐC context.
**/target/

# Lịch sử Git: to, không cần, có thể chứa thông tin nhạy cảm cũ
.git/
.gitignore

# Bí mật — TUYỆT ĐỐI không được vào image
**/.env
**/*.env
*.pem
*.key

# File của IDE / hệ điều hành
.idea/
.vscode/
*.iml
.DS_Store

# Tài liệu, hạ tầng — không cần để build app
docs/
infra/
monitoring/
k8s/
```

> Docs Docker lưu ý: chính `Dockerfile` và `.dockerignore` vẫn được gửi cho builder, nhưng không `COPY` vào image được.

**Vì sao `.dockerignore` là vấn đề bảo mật, không chỉ tốc độ?** Lệnh `COPY . .` copy **mọi thứ** trong context. Nếu `.env` có trong context, nó nằm trong một layer của image — kể cả khi bước sau bạn `RUN rm .env` thì layer cũ **vẫn còn** file đó (layer chỉ được thêm, không bị sửa). Ai `docker pull` được image là trích xuất được.

### 4.2. 🟥 Các instruction cốt lõi

#### `FROM` — chọn image gốc

```dockerfile
FROM eclipse-temurin:21-jre-noble
```

Mọi Dockerfile bắt đầu bằng `FROM`. Image `eclipse-temurin` là bản build OpenJDK của dự án Eclipse Adoptium. Đọc tag:

| Phần tag | Nghĩa |
|---|---|
| `21` | Java 21 |
| `jre` / `jdk` | Chỉ môi trường chạy (JRE) / bộ công cụ phát triển đầy đủ có `javac` (JDK) |
| `noble` | Dựa trên Ubuntu 24.04 (codename Noble). Cùng bản Ubuntu với EC2 ở tuần 11 |

> 🟥 **Luôn ghi tag cụ thể**, không dùng `latest` — để hôm nay và 3 tháng sau build ra cùng một nền.

#### `WORKDIR` — thư mục làm việc

```dockerfile
WORKDIR /app
```

Tạo thư mục nếu chưa có và `cd` vào đó cho mọi instruction phía sau (và cho process lúc chạy). Không dùng `RUN cd /app` — mỗi `RUN` chạy trong một shell mới, `cd` không "giữ" sang dòng sau.

#### `COPY` và `ADD`

```dockerfile
COPY pom.xml ./              # từ build context vào image
COPY --from=build /workspace/app.jar app.jar   # từ stage khác (mục 4.4)
```

`ADD` làm được thêm vài việc: tải từ URL, lấy từ Git, **tự giải nén** file tar. Chính vì nó "làm nhiều hơn bạn nghĩ" nên quy tắc thực tế: **dùng `COPY`**, chỉ dùng `ADD` khi thật sự cần giải nén tar.

#### `RUN` — chạy lệnh lúc build

```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*
```

Đây đúng là mẫu `apt-get` bạn đã gặp ở [Linux bài 05](../01-LINUX/05-packages-ssh.md):

- `apt-get` (không phải `apt`) vì `apt-get` có giao diện ổn định cho script.
- `-y`: không hỏi xác nhận — build không có ai ngồi gõ "Y".
- `--no-install-recommends`: không cài gói "gợi ý" → image nhỏ hơn.
- `rm -rf /var/lib/apt/lists/*`: xóa danh mục gói vừa tải **trong cùng `RUN`**.

> Vì sao phải gộp bằng `&&` trong **một** `RUN`? Mỗi `RUN` là một layer. Nếu `apt-get update` ở một `RUN` và `rm -rf …lists` ở `RUN` khác, danh mục gói vẫn nằm vĩnh viễn trong layer đầu → image không nhỏ đi. Thêm nữa, `update` ở layer riêng có thể bị cache cũ, khiến `install` sau đó cài phiên bản lỗi thời.

#### `ENV` và `ARG`

| | `ARG` | `ENV` |
|---|---|---|
| Có hiệu lực | Chỉ lúc **build** | Lúc build **và** lúc container chạy |
| Lưu trong image cuối? | Không là biến môi trường của container | **Có** — ai `docker inspect` image cũng thấy |
| Đặt giá trị từ ngoài | `docker build --build-arg NAME=value` | `docker run -e NAME=value` (ghi đè giá trị mặc định) |
| Ví dụ hợp lý | `ARG JAR_FILE=target/*.jar` | `ENV TZ=Asia/Ho_Chi_Minh` |

> ⚠️ **Không bao giờ** đặt mật khẩu, token vào `ENV` hay `ARG`. Docs Docker cảnh báo giá trị build-arg có thể hiện trong `docker history`. `ENV` thì nằm thẳng trong metadata image. Bài 04 sẽ chứng minh bằng lệnh. Bí mật được truyền **lúc chạy** (`-e`, `--env-file`) hoặc bằng cơ chế secret (Module 10).

#### `EXPOSE` — chỉ là tài liệu

```dockerfile
EXPOSE 8080
```

Docs Docker nói rõ: `EXPOSE` **không thực sự publish port**. Nó chỉ ghi chú "app trong image này nghe ở 8080". Muốn truy cập từ ngoài vẫn phải `docker run -p` (bài 02). Vẫn nên viết `EXPOSE` vì người đọc Dockerfile biết ngay app dùng port nào.

#### `USER` — chạy bằng user nào

```dockerfile
USER taskhub
```

Mọi `RUN` phía sau và process lúc chạy (`ENTRYPOINT`/`CMD`) dùng user này. Mặc định nếu không có `USER`, container chạy bằng **root** (UID 0). Bài 07 phân tích sâu rủi ro; ở bài này ta áp dụng: **image runtime phải chạy non-root**.

#### `ENTRYPOINT` và `CMD`

- `ENTRYPOINT`: chương trình chính của container.
- `CMD`: tham số mặc định (có thể bị ghi đè khi `docker run <image> <tham-số-khác>`).

Với ứng dụng Java, cách đơn giản và rõ ràng nhất:

```dockerfile
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

### 4.3. 🟥 Shell form và exec form — chuyện của PID 1 và `SIGTERM`

Hai cách viết nhìn giống nhau nhưng chạy rất khác:

```dockerfile
ENTRYPOINT java -jar /app/app.jar          # shell form
ENTRYPOINT ["java", "-jar", "/app/app.jar"] # exec form (mảng JSON)
```

| | Shell form | Exec form |
|---|---|---|
| Docker chạy | `/bin/sh -c "java -jar /app/app.jar"` | `java -jar /app/app.jar` trực tiếp |
| PID 1 trong container | `sh` | `java` |
| `docker stop` gửi `SIGTERM` tới | `sh` — mà `sh` **không chuyển tiếp** tín hiệu cho `java` | `java` — Spring Boot nhận tín hiệu và tắt nhẹ nhàng (graceful shutdown) |
| Kết quả | Chờ hết thời gian chờ (mặc định 10 giây) rồi bị `SIGKILL` → exit code 137 | Tắt sạch trong vài giây → exit code 143 (128 + 15) |

Docs Dockerfile ghi rõ: với shell form, "the executable will not be the container's `PID 1`" — nên không nhận được tín hiệu.

Đây chính là kiến thức `SIGTERM` vs `SIGKILL` và exit code 137/143 ở [Linux bài 04](../01-LINUX/04-processes-systemd.md). Docker chỉ đóng vai systemd: gửi `SIGTERM`, chờ, rồi `SIGKILL`.

> **Quy tắc:** `ENTRYPOINT` và `CMD` luôn viết **exec form** (mảng JSON, dùng nháy kép `"`). Nháy đơn `'` không phải JSON hợp lệ → Docker hiểu thành shell form.

### 4.4. 🟥 Layer cache — vì sao thứ tự instruction quan trọng

Docs Docker: *"If a layer changes, all other layers that come after it are also affected."* — Một layer thay đổi thì **mọi layer phía sau phải build lại**, dù bản thân chúng không đổi.

So sánh hai cách:

```dockerfile
# ❌ Cách ngây thơ
COPY . .
RUN cd app && ./mvnw package   # tải dependency + biên dịch
```

Sửa 1 dòng trong `TaskController.java` → layer `COPY . .` đổi → `RUN ./mvnw package` chạy lại → **tải lại toàn bộ dependency Maven** (hàng trăm MB, vài phút).

```dockerfile
# ✅ Cách tối ưu cache
COPY app/mvnw app/pom.xml ./
COPY app/.mvn/ .mvn/
RUN ./mvnw -B dependency:go-offline   # chỉ chạy lại khi pom.xml đổi
COPY app/src/ src/
RUN ./mvnw -B package -DskipTests     # chỉ biên dịch lại code
```

Sửa code → chỉ 2 layer cuối build lại; layer dependency lấy từ cache (`CACHED` trong output). Nguyên tắc: **thứ ít thay đổi đặt trên, thứ hay thay đổi đặt dưới**.

> `dependency:go-offline` tải phần lớn dependency và plugin, nhưng đôi khi bước `package` vẫn phải tải thêm vài plugin. Đó là bình thường — mục tiêu là cache phần nặng nhất.

🟨 BuildKit còn có **cache mount**: `RUN --mount=type=cache,target=/root/.m2 ./mvnw package` giữ thư mục `~/.m2` giữa các lần build mà không đưa vào image. Cách này nâng cao hơn; giáo trình dùng `go-offline` cho dễ hiểu.

### 4.5. 🟥 Multi-stage build — build bằng JDK, chạy bằng JRE

Vấn đề: để **build** cần JDK + Maven + source + thư viện tải về. Để **chạy** chỉ cần JRE + một file jar. Nếu dùng một image cho cả hai, image chạy production mang theo mọi thứ thừa.

**Multi-stage build** (build nhiều giai đoạn): một Dockerfile có nhiều `FROM`, mỗi `FROM` bắt đầu một **stage** mới. Stage sau chỉ lấy đúng thứ cần từ stage trước bằng `COPY --from=<tên-stage>`. Image cuối chỉ gồm stage cuối.

```dockerfile
FROM eclipse-temurin:21-jdk-noble AS build    # stage 1: đặt tên "build"
...                                            # biên dịch ra app.jar

FROM eclipse-temurin:21-jre-noble AS runtime  # stage 2: image cuối
COPY --from=build /workspace/app.jar /app/app.jar
```

Mọi thứ ở stage `build` (JDK, `~/.m2`, source) **không** nằm trong image cuối. Đặt tên stage bằng `AS` để `COPY --from` không bị hỏng khi thêm/bớt stage. Có thể build dừng ở một stage cụ thể bằng `docker build --target build` (hữu ích khi debug).

### 4.6. 🟥 Non-root user

Ubuntu 24.04 (nền của image `noble`) đã có sẵn user `ubuntu` với UID 1000. Thay vì dùng user chung chung đó, ta tạo **system user riêng cho ứng dụng** — đúng như cách tạo user `taskhub` ở [Linux bài 03](../01-LINUX/03-permissions-users-groups.md):

```dockerfile
RUN groupadd --system taskhub \
 && useradd --system --gid taskhub --no-create-home --shell /usr/sbin/nologin taskhub
```

- `--system`: UID nằm trong dải system user (< 1000), không đụng UID 1000 của user `ubuntu`.
- `--shell /usr/sbin/nologin`: không đăng nhập tương tác được.
- File `app.jar` copy vào thuộc `root` (mặc định của `COPY`), quyền đọc cho mọi người → app **đọc được nhưng không sửa được** chính code của nó — cùng nguyên tắc thiết kế quyền `/opt/taskhub` ở Linux bài 03.

> Lưu ý thực tế: image Ubuntu 22.04 không có user UID 1000, còn 24.04 thì có. Dockerfile cũ dùng `useradd -u 1000 ...` sẽ báo lỗi `UID 1000 is not unique` khi đổi sang nền noble. Đây là lý do nên dùng `--system` thay vì cố định UID 1000.

### 4.7. 🟨 `HEALTHCHECK` — container tự báo "tôi còn khỏe"

`HEALTHCHECK` khai báo một lệnh Docker chạy định kỳ **bên trong** container. Exit code `0` = healthy, `1` = unhealthy (đúng tinh thần exit code ở Linux bài 01). Giá trị mặc định theo docs: `--interval=30s`, `--timeout=30s`, `--start-period=0s`, `--retries=3`.

Với Spring Boot, endpoint `/actuator/health` trả `{"status":"UP"}` khi app sẵn sàng. Câu hỏi là: **dùng công cụ gì để gọi HTTP từ trong container?**

| Lựa chọn | Ưu | Nhược |
|---|---|---|
| **Dùng `curl` có sẵn trong image Temurin** ✅ (giáo trình chọn) | Không phải cài thêm gì | Phụ thuộc vào việc image gốc còn giữ `curl` |
| Cài thêm `curl`/`wget` | Chủ động | Image to hơn, thêm phần mềm phải vá lỗi |
| Không đặt trong Dockerfile, để Compose/Kubernetes kiểm tra | Image tối giản | Phải cấu hình ở nơi khác |

Dockerfile chính thức của image Temurin noble cài `curl` (có comment *"curl required for historical reasons"*). Vì vậy giáo trình dùng luôn `curl`. **Đừng tin mù quáng** — hãy kiểm chứng trên máy bạn:

```bash
docker run --rm --entrypoint which eclipse-temurin:21-jre-noble curl
```

```text
/usr/bin/curl
```

Nếu sau này image gốc bỏ `curl`, bạn sẽ chuyển sang để healthcheck ở Compose/Kubernetes (Module 09).

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1
```

- `--start-period=60s`: Spring Boot cần thời gian khởi động; trong 60 giây đầu, lần kiểm tra thất bại **không bị tính**.
- `curl -f`: trả exit code khác 0 khi HTTP status ≥ 400 (ví dụ 503 khi DB chết).
- `|| exit 1`: ép mọi lỗi thành exit code `1` (docs dặn không dùng code `2`).
- Ở đây `localhost` là **chính container** — đúng, vì lệnh chạy bên trong container (bài 04 giải thích sâu).

### 4.8. 🟨 `LABEL` — metadata cho image

```dockerfile
LABEL org.opencontainers.image.title="taskhub" \
      org.opencontainers.image.source="https://github.com/<github-user>/taskhub"
```

Nhãn theo chuẩn OCI giúp registry (như GHCR ở bài 06) liên kết image với repo. Không ảnh hưởng tới cách chạy.

### 4.9. 🟨 JVM trong container

JVM hiện đại tự nhận biết giới hạn RAM/CPU của container (tính năng *container support*, bật mặc định). Mặc định heap tối đa chỉ khoảng **25%** RAM được cấp — với container 512MB thì heap chỉ ~128MB. Thêm `-XX:MaxRAMPercentage=75.0` cho phép heap dùng tới 75% RAM của container, phần còn lại cho metaspace, thread stack, bộ nhớ ngoài heap.

```dockerfile
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
```

Khi container vượt giới hạn RAM, kernel giết process — **OOM killer** bạn đã gặp ở [Linux bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md), exit code 137.

### 4.10. 🟨 Spring Boot layered jar

Jar của Spring Boot gồm cả **dependency** (ít thay đổi) và **code của bạn** (thay đổi mỗi lần build). Đóng cả jar vào một layer nghĩa là mỗi lần deploy phải đẩy lại toàn bộ ~50MB dù chỉ sửa 1 class.

Spring Boot có công cụ tách jar thành các thư mục theo layer (cú pháp theo tài liệu chính thức hiện hành):

```bash
java -Djarmode=tools -jar application.jar extract --layers --destination extracted
```

Kết quả gồm 4 thư mục: `dependencies/`, `spring-boot-loader/`, `snapshot-dependencies/`, `application/`. Dockerfile copy từng thư mục thành một layer riêng → lần deploy sau chỉ layer `application/` (vài trăm KB) thay đổi. Bài tập 5 sẽ cho bạn thử. Lưu ý: tutorial cũ dùng `-Djarmode=layertools ... extract` — cú pháp đó thuộc phiên bản cũ.

### 4.11. 🟦 So sánh image nền

| Nền | Đặc điểm | Khi nào dùng |
|---|---|---|
| `21-jdk-noble` | Có `javac`, công cụ debug — lớn nhất | Stage build |
| `21-jre-noble` | Chỉ JRE, Ubuntu 24.04 (glibc) | **Runtime mặc định của giáo trình** |
| `21-jre-alpine` | Alpine Linux, dùng thư viện C **musl** thay cho glibc — nhỏ hơn | Khi rất cần nhỏ; một số thư viện native có thể lỗi vì musl |
| Distroless | Không shell, không package manager | Bảo mật cao, nhưng khó debug (không `exec` vào được bằng `bash`) |

Không có lựa chọn "tốt nhất cho mọi trường hợp" — chọn `jre-noble` vì cân bằng giữa kích thước, độ tương thích và khả năng debug cho người mới.

### 4.12. Dockerfile hoàn chỉnh cho taskhub

File `docker/Dockerfile` trong repo taskhub (build context là **gốc repo**):

```dockerfile
# syntax=docker/dockerfile:1

# ============ Stage 1: build — có JDK + Maven wrapper ============
FROM eclipse-temurin:21-jdk-noble AS build
# Thư mục làm việc của stage build
WORKDIR /workspace

# (1) Chỉ copy file mô tả dependency — ít thay đổi → layer được cache lâu
COPY app/mvnw app/pom.xml ./
COPY app/.mvn/ .mvn/
# chmod phòng trường hợp mvnw mất quyền thực thi khi checkout trên Windows
# go-offline: tải dependency + plugin trước, tách khỏi bước biên dịch
RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline

# (2) Copy source — thay đổi thường xuyên → đặt sau để không phá cache ở trên
COPY app/src/ src/
# Đóng gói jar (test chạy ở pipeline CI — Module 05), đổi tên cho cố định
RUN ./mvnw -B -q package -DskipTests && cp target/*.jar app.jar

# ============ Stage 2: runtime — chỉ JRE + app.jar ============
FROM eclipse-temurin:21-jre-noble AS runtime
# Metadata OCI: registry liên kết image với repo
LABEL org.opencontainers.image.title="taskhub" \
      org.opencontainers.image.source="https://github.com/<github-user>/taskhub"

# System user riêng cho app: UID < 1000, không có home, không đăng nhập được
RUN groupadd --system taskhub \
 && useradd --system --gid taskhub --no-create-home --shell /usr/sbin/nologin taskhub

WORKDIR /app
# Chỉ lấy file jar từ stage build; thuộc root → app đọc được, không sửa được
COPY --from=build /workspace/app.jar /app/app.jar

# Từ đây trở đi (và lúc chạy) dùng user taskhub, không phải root
USER taskhub
# Tài liệu: app nghe port 8080 (không tự publish)
EXPOSE 8080

# Docker gọi Actuator mỗi 30s; 60s đầu để app khởi động không bị tính lỗi
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1

# Exec form → java là PID 1, nhận SIGTERM để tắt nhẹ nhàng
# MaxRAMPercentage: heap tối đa 75% RAM được cấp cho container
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
```

Build từ gốc repo:

```bash
docker build -f docker/Dockerfile -t taskhub:dev .
```

### 4.13. Gặp lại ở đâu

| Kiến thức ở bài này | Gặp lại ở |
|---|---|
| Dockerfile của taskhub | `compose.yaml` build image này (bài 05), dự án v0 |
| Layer cache | Cache trong GitHub Actions — build image nhanh trong CI (Module 05) |
| Tag image, LABEL OCI | Đẩy image lên GHCR (bài 06), deploy theo tag commit SHA (Module 05–06) |
| Non-root, ít phần mềm | Quét lỗ hổng image bằng công cụ scan (bài 07, Module 10), `securityContext` trong Kubernetes (Module 09) |
| `HEALTHCHECK`, exec form | `healthcheck` trong Compose, liveness/readiness probe trong Kubernetes, graceful shutdown khi rolling update |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Sửa một dòng code mà pipeline build mất 7 phút"

Một team có Dockerfile:

```dockerfile
FROM maven:3-eclipse-temurin-21
COPY . /app
WORKDIR /app
RUN mvn package
CMD java -jar target/app.jar
```

Bốn vấn đề trong 5 dòng: (1) `COPY .` trước khi tải dependency → mất cache; (2) image runtime chứa cả Maven + source → ~800MB; (3) không `.dockerignore` → `target/` và `.git` cũ bị gửi vào context; (4) `CMD` shell form → `docker stop` chờ 10 giây rồi kill. Viết lại theo mục 4.12: build còn ~40 giây khi chỉ sửa code, image nhỏ hơn đáng kể, tắt sạch trong 1–2 giây.

### Ví dụ 2: Mật khẩu nằm trong image public

Một developer viết `ENV DB_PASSWORD=SuperSecret123` trong Dockerfile "cho tiện test", push image lên registry public. Bất kỳ ai chạy `docker inspect` hoặc `docker history` trên image đều đọc được mật khẩu. Xóa dòng đó ở bản build sau **không cứu được** image cũ đã bị kéo về. Cách xử lý đúng: coi mật khẩu đã lộ → **đổi mật khẩu** (rotate), xóa image cũ, truyền secret lúc chạy. (Đúng nguyên tắc "lỡ commit secret thì coi như đã lộ" ở bài [Ôn tập Git](../03-GIT/00-git-quick-review.md).)

---

## 6. Sơ đồ kiến trúc

### 6.1. Luồng `docker build` multi-stage

```text
 Repo taskhub (build context)          BuildKit
 ┌─────────────────────────┐   gửi    ┌──────────────────────────────────────────────┐
 │ pom.xml  mvnw  .mvn/    │ ───────► │ Stage "build"  (eclipse-temurin:21-jdk-noble) │
 │ src/                    │  (trừ    │   COPY pom.xml mvnw .mvn  ── layer [cache]   │
 │ docker/Dockerfile       │  file    │   RUN dependency:go-offline ─ layer [cache]  │
 │ .dockerignore           │  trong   │   COPY src/               ── layer [mới]     │
 │ (target/, .git, .env    │ .docker- │   RUN package → app.jar    ── layer [mới]     │
 │  bị loại)               │  ignore) │                     │                        │
 └─────────────────────────┘          │                     │ COPY --from=build      │
                                      │                     ▼                        │
                                      │ Stage "runtime" (eclipse-temurin:21-jre-noble)│
                                      │   useradd taskhub · /app/app.jar · USER      │
                                      │   HEALTHCHECK · ENTRYPOINT (exec form)        │
                                      └─────────────────────┬────────────────────────┘
                                                            ▼
                                             Image taskhub:dev  (chỉ stage runtime)
```

### 6.2. Cache bị phá từ đâu

```text
 Bạn sửa src/.../TaskController.java

 COPY app/mvnw app/pom.xml ./      ✔ CACHED
 COPY app/.mvn/ .mvn/          ✔ CACHED
 RUN go-offline            ✔ CACHED   ← phần nặng nhất được giữ nguyên
 COPY app/src/ src/            ✖ thay đổi → từ đây trở xuống build lại
 RUN package               ✖ build lại
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `docker build -t <tên:tag> .` | Build image từ Dockerfile trong context `.` | 🟥 |
| `docker build -f docker/Dockerfile .` | Chỉ định đường dẫn Dockerfile | 🟥 |
| `docker build --no-cache` | Build lại từ đầu, bỏ qua cache | 🟥 |
| `docker build --progress=plain` | In đầy đủ output từng bước (để debug) | 🟥 |
| `docker build --target <stage>` | Dừng ở một stage | 🟨 |
| `docker build --build-arg K=V` | Truyền giá trị cho `ARG` | 🟨 |
| `docker image ls` | Xem kích thước image | 🟥 |
| `docker history <image>` | Xem các layer và lệnh tạo ra chúng | 🟥 |
| `docker image inspect <image>` | Xem metadata: `User`, `Env`, `Entrypoint`, `Healthcheck` | 🟥 |
| `docker inspect --format '{{.State.Health.Status}}' <container>` | Xem trạng thái healthcheck | 🟨 |
| `docker buildx` | Công cụ build mở rộng (BuildKit) — build đa kiến trúc | 🟦 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra dưới đây là **minh họa**. Thời gian, kích thước, ID image trên máy bạn sẽ khác.

### `docker build`

```bash
cd ~/projects/taskhub
docker build -f docker/Dockerfile -t taskhub:dev .
```

```text
[+] Building 94.2s (15/15) FINISHED                             docker:default
 => [internal] load build definition from Dockerfile                       0.0s
 => [internal] load metadata for docker.io/library/eclipse-temurin:21-jre  1.8s
 => [internal] load .dockerignore                                          0.0s
 => [internal] load build context                                          0.1s
 => => transferring context: 48.3kB                                        0.0s
 => [build 1/6] FROM docker.io/library/eclipse-temurin:21-jdk-noble       12.4s
 => [build 2/6] WORKDIR /workspace                                         0.2s
 => [build 3/6] COPY app/mvnw app/pom.xml ./                                       0.0s
 => [build 4/6] COPY app/.mvn/ .mvn/                                           0.0s
 => [build 5/6] RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline   58.1s
 => [build 6/6] COPY app/src/ src/ ...
 => [runtime 2/5] RUN groupadd --system taskhub && useradd ...             0.6s
 => exporting to image                                                     0.4s
 => => naming to docker.io/library/taskhub:dev                             0.0s
```

| Tham số | Ý nghĩa |
|---|---|
| `-f docker/Dockerfile` | Dockerfile nằm ở `docker/`, không phải gốc |
| `-t taskhub:dev` | Đặt tên (repository) `taskhub` và tag `dev` |
| `.` | **Build context** = thư mục hiện tại (gốc repo). Đây là tham số bắt buộc, hay bị quên |

Đọc output:

- `transferring context: 48.3kB` — kích thước context. Nếu thấy hàng trăm MB → `.dockerignore` chưa loại `target/` hoặc `.git`.
- `[build 5/6]`, `[runtime 2/5]` — tên stage và thứ tự bước.
- Chạy lại lần 2 mà không sửa gì → các bước hiện `CACHED`.

Sửa một file trong `src/` rồi build lại:

```text
 => CACHED [build 3/6] COPY app/mvnw app/pom.xml ./                                0.0s
 => CACHED [build 4/6] COPY app/.mvn/ .mvn/                                    0.0s
 => CACHED [build 5/6] RUN chmod +x mvnw && ./mvnw -B -q dependency:go...  0.0s
 => [build 6/6] COPY app/src/ src/                                             0.1s
```

### `--progress=plain` và `--no-cache`

```bash
docker build --progress=plain --no-cache -f docker/Dockerfile -t taskhub:dev . 2>&1 | tee build.log
```

- `--progress=plain`: mặc định BuildKit thu gọn output; `plain` in đầy đủ log của từng `RUN` — **bắt buộc khi debug lỗi Maven trong build**.
- `--no-cache`: build lại từ đầu — dùng để đo thời gian build "lạnh" hoặc khi nghi cache cũ gây lỗi.
- `2>&1 | tee build.log`: BuildKit in tiến trình ra stderr; gộp vào stdout và vừa xem vừa lưu file (redirect ở [Linux bài 02](../01-LINUX/02-essential-commands-text.md)).

### `docker image ls` — so sánh kích thước

```bash
docker image ls | grep -E 'taskhub|temurin'
```

```text
taskhub           dev          3f1c9a2b7d10   2 minutes ago   312MB
taskhub           naive        9ab4e01c55f2   15 minutes ago  786MB
eclipse-temurin   21-jre-noble 1e2d...        2 weeks ago     268MB
eclipse-temurin   21-jdk-noble 7c8b...        2 weeks ago     452MB
```

Image `taskhub:dev` ≈ kích thước `jre-noble` + jar (~40–60MB) + vài KB của user.

### `docker history` — layer nào nặng?

```bash
docker history taskhub:dev
```

```text
IMAGE          CREATED         CREATED BY                                      SIZE
3f1c9a2b7d10   2 minutes ago   ENTRYPOINT ["java" "-XX:MaxRAMPercentage=75…   0B
<missing>      2 minutes ago   HEALTHCHECK &{["CMD-SHELL" "curl -fsS http:…   0B
<missing>      2 minutes ago   EXPOSE map[8080/tcp:{}]                         0B
<missing>      2 minutes ago   USER taskhub                                    0B
<missing>      2 minutes ago   COPY /workspace/app.jar /app/app.jar # build…   52.1MB
<missing>      2 minutes ago   WORKDIR /app                                    0B
<missing>      2 minutes ago   RUN /bin/sh -c groupadd --system taskhub && …   9.6kB
...  (các layer của eclipse-temurin:21-jre-noble)
```

- Instruction như `USER`, `EXPOSE`, `ENTRYPOINT` có `SIZE 0B` — chỉ ghi metadata.
- `<missing>` là bình thường: các layer trung gian không có ID image riêng.
- Không thấy JDK, `.m2`, `src/` → multi-stage hoạt động đúng.

### `docker image inspect` — kiểm tra user, entrypoint, healthcheck

```bash
docker image inspect taskhub:dev --format 'User={{.Config.User}} Entrypoint={{.Config.Entrypoint}}'
docker image inspect taskhub:dev --format '{{json .Config.Healthcheck}}'
```

```text
User=taskhub Entrypoint=[java -XX:MaxRAMPercentage=75.0 -jar /app/app.jar]
{"Test":["CMD-SHELL","curl -fsS http://localhost:8080/actuator/health || exit 1"],"Interval":30000000000,"Timeout":3000000000,"StartPeriod":60000000000,"Retries":3}
```

`--format` dùng cú pháp Go template để lấy đúng trường cần xem thay vì đọc cả trang JSON. `Interval` tính bằng nanosecond (30 000 000 000 ns = 30 s).

### Kiểm tra user lúc chạy

```bash
docker run --rm --entrypoint id taskhub:dev
```

```text
uid=999(taskhub) gid=999(taskhub) groups=999(taskhub)
```

`--entrypoint id` thay `ENTRYPOINT` bằng lệnh `id` cho lần chạy này — mẹo hữu ích để "nhìn vào trong" image mà không khởi động app.

### Trạng thái healthcheck

```bash
docker inspect --format '{{.State.Health.Status}}' taskhub-test
```

```text
starting      # trong start-period
healthy       # /actuator/health trả 200
unhealthy     # thất bại liên tiếp đủ số retries
```

`docker ps` cũng hiện `(healthy)` / `(unhealthy)` ở cột `STATUS`.

---

## 9. Bài thực hành từng bước

**Lab: Từ Dockerfile ngây thơ đến Dockerfile production** · `[WSL]` · ~120 phút

Chuẩn bị: repo `taskhub` có ứng dụng Spring Boot từ tuần 6 (xem [milestone v-pre, tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-6--đặc-tả-ứng-dụng-spring-boot)). App cần kết nối PostgreSQL mới khởi động thành công — bài này chỉ build và kiểm tra image; chạy app với database thật ở [bài 04](04-volumes-networks-env.md).

Ghi kết quả vào `~/devops-journey/week07/lab03-dockerfile.md`.

### Bước 1 — Kiểm tra môi trường

```bash
cd ~/projects/taskhub
docker version --format '{{.Server.Version}}'
ls app/mvnw app/pom.xml app/.mvn app/src
file app/mvnw                   # phải là "... script ... text executable", không có "CRLF"
```

Nếu `file app/mvnw` báo `with CRLF line terminators`: sửa bằng `sed -i 's/\r$//' app/mvnw` (lỗi CRLF ở [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md)) và kiểm tra `git config core.autocrlf`.

### Bước 2 — Dockerfile ngây thơ (để đo, không dùng thật)

Tạo `docker/Dockerfile.naive`:

```dockerfile
FROM eclipse-temurin:21-jdk-noble
WORKDIR /src
COPY . .
RUN cd app && ./mvnw -B package -DskipTests
CMD java -jar app/target/*.jar
```

Build và đo thời gian:

```bash
time docker build -f docker/Dockerfile.naive -t taskhub:naive .
```

❓ Ghi lại: thời gian `real`, dòng `transferring context` (bao nhiêu MB?).

### Bước 3 — Đo tác động của việc sửa code

Sửa một chuỗi bất kỳ trong một file `.java` (ví dụ thêm comment), build lại:

```bash
time docker build -f docker/Dockerfile.naive -t taskhub:naive .
```

❓ Bước `RUN ./mvnw package` có `CACHED` không? Thời gian lần 2 so với lần 1?

### Bước 4 — Thêm `.dockerignore`

Tạo `.dockerignore` ở **gốc repo** với nội dung ở mục 4.1. Build lại với Dockerfile ngây thơ:

```bash
docker build -f docker/Dockerfile.naive -t taskhub:naive .
```

❓ Dòng `transferring context` thay đổi thế nào?

### Bước 5 — Dockerfile multi-stage

Tạo `docker/Dockerfile` theo mục 4.12 (thay `<github-user>` bằng tên GitHub của bạn). Build lần đầu và lần thứ hai sau khi sửa code:

```bash
time docker build -f docker/Dockerfile -t taskhub:dev .
# sửa 1 file .java
time docker build -f docker/Dockerfile -t taskhub:dev .
```

❓ Lần 2, những bước nào `CACHED`? Thời gian giảm bao nhiêu so với Bước 3?

### Bước 6 — So sánh kích thước và layer

```bash
docker image ls | grep taskhub
docker history taskhub:naive | head -5
docker history taskhub:dev | head -10
```

❓ Hai image chênh nhau bao nhiêu MB? Trong `taskhub:naive` có thư mục `src/` và `/root/.m2` không? Kiểm chứng:

```bash
docker run --rm --entrypoint ls taskhub:naive /app
docker run --rm --entrypoint sh taskhub:naive -c 'du -sh /root/.m2'
docker run --rm --entrypoint ls taskhub:dev /app
```

### Bước 7 — Non-root

```bash
docker run --rm --entrypoint id taskhub:naive
docker run --rm --entrypoint id taskhub:dev
docker run --rm --entrypoint sh taskhub:dev -c 'touch /app/hack.txt'
```

❓ Ghi lại kết quả `id` của 2 image. Lệnh `touch` thứ ba báo gì? Vì sao đó là điều **tốt**?

### Bước 8 — Shell form vs exec form: đo thời gian tắt

App taskhub chưa có database nên sẽ tự thoát sau vài giây — không dùng để đo được. Thay vào đó dùng `jwebserver`, một web server tối giản viết bằng Java có sẵn trong JDK 18+. Nó là một process **Java** thật, xử lý `SIGTERM` giống hệt Spring Boot:

```bash
# Exec form: java (jwebserver) là PID 1
docker run -d --name execform --entrypoint jwebserver eclipse-temurin:21-jdk-noble -b 0.0.0.0

# Shell form: sh là PID 1, java là process con.
# Có thêm "; echo stopped" để sh không thể "nhường chỗ" (exec) cho java
docker run -d --name shellform --entrypoint sh eclipse-temurin:21-jdk-noble -c 'jwebserver -b 0.0.0.0; echo stopped'

docker top shellform            # thấy cả sh và java
time docker stop execform
time docker stop shellform
docker inspect --format '{{.Name}} exit={{.State.ExitCode}}' execform shellform
docker rm execform shellform
```

❓ Lệnh `stop` nào mất ~10 giây? Exit code của từng container? Liên hệ với `ENTRYPOINT java ...` viết shell form.

### Bước 9 — Commit

```bash
cd ~/projects/taskhub
git checkout -b feat/dockerfile
git add .dockerignore docker/Dockerfile
git commit -m "build(docker): add multi-stage Dockerfile and .dockerignore"
git push -u origin feat/dockerfile
# tạo Pull Request trên GitHub theo quy trình tuần 6
```

Không commit `docker/Dockerfile.naive` (xóa đi hoặc giữ trong `week07/` của devops-journey làm tư liệu so sánh).

---

## 10. Kết quả mong đợi

- **Bước 2–3:** context có thể lên vài chục đến hàng trăm MB (có `target/`, `.git`). Sửa code → `RUN ./mvnw package` chạy lại từ đầu, tải lại dependency → thời gian gần như bằng lần đầu.
- **Bước 4:** context giảm xuống còn vài chục KB đến vài MB.
- **Bước 5:** lần build thứ hai sau khi sửa code, các bước `COPY mvnw pom.xml`, `COPY .mvn/`, `RUN go-offline` đều `CACHED`; thời gian giảm mạnh (chỉ còn biên dịch).
- **Bước 6:** `taskhub:dev` nhỏ hơn `taskhub:naive` hàng trăm MB (ví dụ minh họa: ~310MB so với ~790MB). `taskhub:naive` chứa `src/`, `pom.xml`, `/root/.m2`; `taskhub:dev` trong `/app` chỉ có `app.jar`.
- **Bước 7:** `naive` → `uid=0(root)`; `dev` → `uid=999(taskhub)` (số UID có thể khác, miễn < 1000 và khác 0). `touch /app/hack.txt` báo `Permission denied` — app bị chiếm quyền cũng không sửa được thư mục code.
- **Bước 8:** `execform` dừng gần như ngay lập tức, exit code `143` (128 + 15: JVM nhận `SIGTERM` và tự thoát). `shellform` mất ~10 giây, exit code `137` (128 + 9: `sh` là PID 1 không chuyển `SIGTERM` cho java, hết thời gian chờ Docker gửi `SIGKILL`). Chi tiết vì sao `sh` ở vị trí PID 1 "phớt lờ" `SIGTERM` có trong lời giải.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `"docker build" requires exactly 1 argument` | Quên dấu `.` (build context) cuối lệnh | `docker build -t taskhub:dev .` |
| `failed to compute cache key: "/pom.xml": not found` | File không nằm trong build context, hoặc bị `.dockerignore` loại, hoặc chạy build sai thư mục | `pwd` phải là gốc repo; kiểm tra `.dockerignore` |
| `/bin/sh: 1: ./mvnw: Permission denied` | `mvnw` mất quyền thực thi (checkout trên Windows) | `RUN chmod +x mvnw` (đã có trong Dockerfile mẫu); trên máy: `git update-index --chmod=+x mvnw` |
| `./mvnw: not found` dù file có tồn tại | Dòng shebang của `mvnw` có CRLF — kernel tìm `/bin/sh\r` | `sed -i 's/\r$//' app/mvnw`, commit lại; xem Linux bài 01 |
| `cp: target/*.jar: No such file or directory` hoặc copy ra nhiều file | Build Maven thất bại (cuộn lên xem log), hoặc có nhiều jar khớp mẫu | Build với `--progress=plain`; kiểm tra `ls target/` |
| `useradd: UID 1000 is not unique` | Dockerfile tạo user cố định UID 1000 trên nền Ubuntu 24.04 (đã có user `ubuntu`) | Dùng `--system` hoặc UID khác |
| `docker stop` mất đúng 10 giây, exit code 137 | `ENTRYPOINT`/`CMD` viết shell form | Đổi sang exec form `["java", ...]` |
| Healthcheck luôn `unhealthy` dù app chạy | Endpoint sai, Actuator chưa có dependency, hoặc app cần lâu hơn `start-period` | `docker exec <c> curl -v localhost:8080/actuator/health`; xem mục 12 |
| Image vẫn to dù đã multi-stage | `FROM` stage cuối vẫn là JDK, hoặc copy nhầm cả thư mục | `docker history` xem layer nào to |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Log build là "stack trace" của Dockerfile

Khi build lỗi, BuildKit chỉ rõ **bước nào** lỗi và in lại Dockerfile quanh dòng đó:

```text
 => ERROR [build 6/6] RUN ./mvnw -B -q package -DskipTests && cp target/*.jar app.jar   14.2s
------
 > [build 6/6] RUN ./mvnw -B -q package -DskipTests && cp target/*.jar app.jar:
12.87 [ERROR] COMPILATION ERROR :
12.87 [ERROR] /workspace/src/main/java/com/taskhub/task/TaskController.java:[27,9] cannot find symbol
------
Dockerfile:19
--------------------
  17 |     COPY app/src/ src/
  18 |     # Đóng gói jar ...
  19 | >>> RUN ./mvnw -B -q package -DskipTests && cp target/*.jar app.jar
--------------------
ERROR: failed to solve: process "/bin/sh -c ./mvnw -B -q package -DskipTests && cp target/*.jar app.jar" did not complete successfully: exit code: 1
```

Đọc từ dưới lên, giống đọc stack trace Java ([Linux bài 07](../01-LINUX/07-logs-monitoring-troubleshooting.md)):

1. Dòng cuối: lệnh nào thất bại, exit code bao nhiêu → `RUN ... package` trả `1`.
2. Khung `Dockerfile:19`: dòng nào trong Dockerfile.
3. Phần log ở giữa: **nguyên nhân thật** — ở đây là lỗi biên dịch Java, không phải lỗi Docker.

> Quy tắc: lỗi trong bước `RUN` thường **không phải lỗi Docker** mà là lỗi của chính lệnh đó (Maven, apt, script). Hãy thử chạy lệnh ấy ngoài Docker trước: `./mvnw -B package` trên WSL. Nếu ngoài cũng lỗi → sửa code; nếu chỉ lỗi trong Docker → khác biệt môi trường (thiếu file do `.dockerignore`, CRLF, quyền).

Output bị thu gọn? Thêm `--progress=plain` để thấy log đầy đủ.

### 12.2. Debug một stage bằng `--target`

```bash
docker build -f docker/Dockerfile --target build -t taskhub:buildstage .
docker run --rm -it --entrypoint bash taskhub:buildstage
# [Container] — đang ở /workspace của stage build
ls -la target/
```

Dừng ở stage `build` và vào bên trong xem có gì — giống đặt breakpoint.

### 12.3. Container healthcheck `unhealthy`

```bash
docker inspect --format '{{json .State.Health}}' taskhub-test | python3 -m json.tool
```

```text
{
    "Status": "unhealthy",
    "FailingStreak": 3,
    "Log": [
        { "ExitCode": 1, "Output": "curl: (22) The requested URL returned error: 503\n" }
    ]
}
```

`Log` lưu output của vài lần kiểm tra gần nhất. `503` → Actuator báo app chưa sẵn sàng (thường do mất kết nối DB). `(7) Failed to connect` → app chưa nghe port 8080 (chưa khởi động xong hoặc đã chết). Dùng mã lỗi curl và HTTP status để khoanh vùng — đúng phương pháp debug theo tầng ở [Network bài 08](../02-NETWORKING/08-network-troubleshooting-tools.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Build context là gì? Vì sao `COPY ../config.yml .` không hoạt động?
2. Nêu 2 lý do (một về tốc độ, một về bảo mật) phải có `.dockerignore`.
3. Bạn thêm `RUN rm .env` ngay sau `COPY . .`. File `.env` đã an toàn chưa? Giải thích bằng khái niệm layer.
4. `ARG` và `ENV` khác nhau thế nào? Biến nào còn tồn tại khi container chạy?
5. `EXPOSE 8080` có cho phép truy cập app từ trình duyệt không? Cần thêm gì?
6. Vì sao copy `pom.xml` và tải dependency **trước** khi copy `src/`?
7. Multi-stage build giải quyết vấn đề gì? Image cuối gồm những stage nào?
8. Shell form và exec form khác nhau thế nào? Hậu quả cụ thể khi `docker stop` một app Spring Boot viết bằng shell form?
9. Exit code 137 và 143 nghĩa là gì?
10. Vì sao tạo user bằng `useradd --system` thay vì `useradd -u 1000` trên nền `noble`?
11. Vì sao để `app.jar` thuộc `root` trong khi app chạy bằng `taskhub`?
12. `HEALTHCHECK` dùng exit code thế nào? `--start-period` để làm gì?
13. Trong `HEALTHCHECK`, `localhost` trỏ tới đâu?
14. Vì sao JVM trong container nên đặt `MaxRAMPercentage`? Chuyện gì xảy ra khi container vượt giới hạn RAM?
15. Image `jre-alpine` nhỏ hơn `jre-noble`. Vì sao giáo trình vẫn chọn `jre-noble`?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/03-solutions.md](solutions/03-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Review Dockerfile.** Liệt kê **tất cả** vấn đề trong Dockerfile sau và viết lại cho đúng:

```dockerfile
FROM eclipse-temurin:latest
RUN apt-get update
RUN apt-get install curl vim git
ADD . /app
RUN cd /app && ./mvnw package
ENV SPRING_DATASOURCE_PASSWORD=taskhub123
EXPOSE 8080
CMD java -jar /app/target/taskhub-0.0.1-SNAPSHOT.jar
```

**Bài 2 — Thứ tự cache.** Một dự án Node.js có `package.json`, `package-lock.json`, `src/`. Lệnh cài dependency là `npm ci`, chạy app là `node src/index.js`. Viết Dockerfile tối ưu cache (dùng `node:22-bookworm-slim`), giải thích vì sao bạn xếp như vậy. (Không cần biết Node.js — nguyên tắc giống hệt Maven.)

**Bài 3 — Tìm secret trong image.** Build image sau rồi tìm cách đọc được cả `API_TOKEN` và `BUILD_SECRET` **chỉ từ image**, không xem Dockerfile:

```dockerfile
FROM ubuntu:24.04
ARG BUILD_SECRET
ENV API_TOKEN=tok_123456
RUN echo "secret is $BUILD_SECRET" > /dev/null
```

Build bằng `docker build --build-arg BUILD_SECRET=s3cr3t -t leaky .`. Ghi lại lệnh bạn dùng và kết luận.

**Bài 4 — `--target` cho stage test.** Thêm vào Dockerfile của taskhub một stage `test` (kế thừa từ stage `build` bằng `FROM build AS test`) chạy `./mvnw -B test`. Đảm bảo `docker build -f docker/Dockerfile -t taskhub:dev .` **không** chạy test (build nhanh), còn `docker build --target test ...` thì chạy test. Giải thích vì sao BuildKit không chạy stage `test` khi build mặc định.

**Bài 5 — 🟨 Layered jar.** Viết phiên bản `docker/Dockerfile.layered` dùng `java -Djarmode=tools -jar app.jar extract --layers --destination extracted` để tách jar thành 4 layer. Sửa 1 dòng code, build lại cả hai Dockerfile, dùng `docker history` so sánh: layer nào thay đổi và kích thước bao nhiêu trong từng trường hợp?

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Viết được Dockerfile multi-stage cho taskhub **không nhìn tài liệu** và giải thích được từng dòng.
- [ ] Nhìn một Dockerfile, chỉ ra được ngay vấn đề về cache, kích thước, bảo mật, tín hiệu.
- [ ] Giải thích được vì sao `RUN rm secret` không xóa được secret khỏi image.
- [ ] Đọc output build, chỉ ra bước nào `CACHED`, bước nào lỗi và nguyên nhân thật.
- [ ] Chứng minh được image chạy non-root bằng lệnh.
- [ ] Làm xong Bài tập 1 và 3 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Dockerfile reference](https://docs.docker.com/reference/dockerfile/) | Cú pháp mọi instruction, shell/exec form, `HEALTHCHECK`, `USER`, `ARG`/`ENV` | 2026-10-31 |
| [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/) | `FROM ... AS`, `COPY --from`, `--target` | 2026-10-31 |
| [Docker build cache](https://docs.docker.com/build/cache/) | Cơ chế vô hiệu hóa cache theo layer | 2026-10-31 |
| [Build context & .dockerignore](https://docs.docker.com/build/concepts/context/) | Build context, cú pháp `.dockerignore` | 2026-10-31 |
| [Spring Boot — Dockerfiles](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html) | Cú pháp `-Djarmode=tools ... extract --layers` | 2026-10-31 |
| [Spring Boot — Efficient container images](https://docs.spring.io/spring-boot/reference/packaging/container-images/efficient-images.html) | 4 layer mặc định của jar | 2026-10-31 |
| [Spring Boot with Docker (guide)](https://spring.io/guides/gs/spring-boot-docker) | Non-root user, ENTRYPOINT exec form | 2026-10-31 |
| [Adoptium — Dockerfile Temurin 21 JRE noble](https://github.com/adoptium/containers/blob/main/21/jre/ubuntu/noble/Dockerfile) | Image nền dựa trên `ubuntu:24.04`, có cài `curl` | 2026-10-31 |
| [Eclipse Temurin tags](https://github.com/docker-library/docs/tree/master/eclipse-temurin/README.md) | Tag `21-jdk-noble`, `21-jre-noble`, `21-jre-alpine` | 2026-10-31 |
