# 07. Docker Security — Bảo mật container

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc (phần 🟨/🟦 ghi riêng) · Kiến thức cần có trước: [03. Dockerfile & multi-stage](03-dockerfile-multistage.md), [04. Volumes, networks, env](04-volumes-networks-env.md), [Linux 03 — Permissions, Users & Groups](../01-LINUX/03-permissions-users-groups.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop, `[Container]` các container dùng xong bỏ

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

- Liệt kê được **4 nhóm rủi ro** chính khi chạy container: thoát khỏi container, image độc hại/lỗi thời, lộ secret, cấp quyền quá mức.
- Giải thích vì sao **ai điều khiển được Docker daemon thì gần như có quyền root trên máy** — và vì sao không bao giờ mount `/var/run/docker.sock` vào container ứng dụng.
- Chạy container theo nguyên tắc **đặc quyền tối thiểu (least privilege)**: non-root, read-only filesystem, bỏ capability, `no-new-privileges`, giới hạn tài nguyên.
- Chọn **image nền** an toàn: nhỏ, chính thức, ghim (pin) phiên bản.
- Quét lỗ hổng image bằng **Trivy**, đọc được báo cáo (CVE, severity, fixed version) và biết cách xử lý.
- Chứng minh được vì sao **không đưa secret vào `ENV`/`ARG`** trong Dockerfile, và biết cách truyền secret đúng.
- Tự đánh giá bảo mật của dự án `taskhub` bằng một checklist.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| Security team quét image của công ty, báo "image taskhub có 3 lỗ hổng CRITICAL" | Đọc báo cáo Trivy, biết lỗ hổng nằm ở base image hay ở thư viện Java, biết cập nhật cái gì |
| Một developer push image lên registry public, trong image có mật khẩu database | Biết `docker history` đọc được `ENV`, biết phải **đổi mật khẩu ngay**, không chỉ xóa image |
| Ai đó đề xuất "mount docker.sock vào container CI cho tiện" | Giải thích được đó là cho container quyền root trên máy chủ |
| Container bị chiếm quyền do lỗi trong ứng dụng | Nếu đã chạy non-root, read-only, bỏ capability → kẻ tấn công bị giới hạn rất nhiều |
| Phỏng vấn: "Bạn bảo mật Docker image thế nào?" | Câu hỏi gần như chắc chắn gặp ở vị trí Junior DevOps |

Bảo mật không phải một bước làm ở cuối. Mỗi dòng trong Dockerfile và `compose.yaml` đều là một quyết định bảo mật — bài này giúp bạn ra quyết định có chủ đích.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Container cô lập đến đâu?

Nhắc lại từ [bài 01](01-vm-vs-container-architecture.md): container **không có kernel riêng**. Nó là process Linux bình thường, được cô lập bằng:

- **Namespace** (không gian tên) — giới hạn những gì process **nhìn thấy**: process khác, mạng, filesystem, user.
- **cgroup** (nhóm kiểm soát) — giới hạn những gì process **được dùng**: RAM, CPU, số process.
- **Capability** (năng lực đặc quyền) — chia nhỏ quyền root thành nhiều mảnh, container chỉ được một phần.

Hệ quả quan trọng: **mọi container trên một máy dùng chung một kernel**. Nếu có lỗ hổng trong kernel hoặc container được cấu hình quá rộng quyền, process trong container có thể "thoát ra" và tác động lên máy chủ (host). Máy ảo (VM) có ranh giới mạnh hơn vì mỗi VM có kernel riêng.

### 3.2. Root trong container có phải root thật không?

Mặc định **có** — UID 0 trong container chính là UID 0 trên host (trừ khi bật user namespace / rootless, xem 🟦 ở mục 4.3). Điều đỡ cho bạn là Docker đã:

- Bỏ bớt nhiều capability nguy hiểm của root (theo cơ chế danh sách cho phép — allowlist).
- Chặn nhiều system call nguy hiểm.
- Cô lập filesystem: root trong container chỉ thấy filesystem của container.

Nhưng chỉ cần một cấu hình sai (mount thư mục host, `--privileged`, mount docker.sock), root trong container trở thành root trên host.

### 3.3. Least privilege — đặc quyền tối thiểu

Bạn đã gặp nguyên tắc này ở [Linux bài 03](../01-LINUX/03-permissions-users-groups.md): chỉ cấp đúng quyền cần thiết. Với container, câu hỏi luôn là:

> App Spring Boot của tôi **thực sự cần** gì? Nghe port 8080, đọc file jar, ghi vào `/tmp`, kết nối tới PostgreSQL. **Không cần** root, không cần ghi vào `/usr`, không cần đổi giờ hệ thống, không cần mount ổ đĩa.

Mọi thứ không cần → tắt đi. Khi bị tấn công, kẻ tấn công chỉ có được đúng những quyền mà app có.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Mô hình đe dọa (threat model) cho container

| Nhóm rủi ro | Ví dụ | Biện pháp chính | Mục |
|---|---|---|---|
| **Thoát container** (container escape) | Lỗ hổng kernel; container chạy `--privileged`; mount `/` của host vào container | Non-root, bỏ capability, không `--privileged`, cập nhật host | 4.3, 4.4 |
| **Image độc hại hoặc lỗi thời** | Image lạ trên Docker Hub chứa phần mềm đào coin; base image 2 năm chưa cập nhật có hàng trăm CVE | Image chính thức, pin version, quét lỗ hổng định kỳ | 4.6, 4.7 |
| **Lộ secret** | Mật khẩu DB nằm trong `ENV` của image public; file `.env` bị commit lên GitHub | Secret chỉ truyền lúc chạy, `.env` trong `.gitignore`, secret mount | 4.8 |
| **Quyền quá mức** | App chạy root, ghi được mọi nơi, không giới hạn RAM → một bug làm sập cả server | Non-root, read-only, giới hạn tài nguyên | 4.3, 4.5 |
| **Daemon bị lạm dụng** | User thuộc group `docker`; container CI mount docker.sock | Hạn chế ai điều khiển daemon | 4.2 |

### 4.2. 🟥 Docker daemon chạy root — và hệ quả

Docker daemon (`dockerd`) cần quyền root (trừ chế độ rootless). Tài liệu chính thức của Docker viết: *"only trusted users should be allowed to control your Docker daemon"* — chỉ người dùng tin cậy mới được điều khiển Docker daemon. Lý do: ai ra lệnh được cho daemon thì có thể chạy:

```bash
docker run --rm -it -v /:/host ubuntu:22.04 chroot /host bash
```

Lệnh trên mount **toàn bộ filesystem của host** vào container rồi `chroot` vào đó — bạn có shell root trên host. Không cần mật khẩu sudo.

Hai hệ quả thực tế:

1. **Group `docker` tương đương root.** Ở [Linux bài 03](../01-LINUX/03-permissions-users-groups.md) bạn đã đọc cảnh báo này từ trang [Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/) của Docker. Thêm ai vào group `docker` = cho họ quyền root. Trên server thật, chỉ thêm người thực sự cần.
2. **Không bao giờ mount `/var/run/docker.sock` vào container ứng dụng.** Socket này là "cửa" để ra lệnh cho daemon. Container nào có nó = container đó điều khiển được daemon = root trên host. Nếu app có lỗ hổng, kẻ tấn công chiếm luôn cả server.

> Ngoại lệ có cân nhắc: một số **công cụ tin cậy** (Trivy, CI runner, Portainer) cần socket để làm việc. Chấp nhận được khi: công cụ chính thức, ghim phiên bản, chạy ngắn trên máy của bạn. Ở lab mục 9 bạn sẽ dùng Trivy theo cách này — và cũng sẽ thấy cách khác không cần socket.

**Docker Desktop trên Windows** khác một chút: daemon chạy trong một máy ảo Linux riêng do Docker Desktop quản lý, không chạy trực tiếp trên Windows. Rủi ro vẫn tồn tại nhưng "host" bị chiếm là máy ảo đó. Trên server EC2 thật (tuần 12), daemon chạy thẳng trên server — rủi ro đầy đủ.

### 4.3. 🟥 Chạy non-root

**Cách 1 — trong Dockerfile (khuyến nghị):** tạo user riêng và chuyển sang user đó trước `ENTRYPOINT`/`CMD`. Dockerfile của taskhub ở [bài 03](03-dockerfile-multistage.md) đã làm việc này — tạo **system user** `taskhub` (UID < 1000, giống user dịch vụ ở [Linux bài 03](../01-LINUX/03-permissions-users-groups.md)), để file jar thuộc `root` (app chỉ đọc, không sửa được chính nó), rồi `USER taskhub`. Dạng tổng quát:

```dockerfile
RUN groupadd --system taskhub && useradd --system --gid taskhub --no-create-home taskhub
USER taskhub
```

> Image `eclipse-temurin:21-jre-noble` dựa trên `ubuntu:24.04`, vốn có sẵn user `ubuntu` UID 1000. Đừng tái sử dụng user này cho app — tạo user riêng có tên rõ ràng để đọc log, `ps`, `inspect` là biết ngay process thuộc ứng dụng nào.

🟨 **UID cố định**: system user được hệ thống tự cấp UID (thường 999, 998…). Khi cần cấp quyền cho volume hoặc chạy cùng image ở nhiều nơi, nên chỉ định UID rõ ràng (`useradd --uid ...`) để biết chắc con số đó (gặp lại ở [bài 08](08-container-troubleshooting.md#4-giải-thích-chi-tiết)).

**Cách 2 — lúc chạy:** `docker run --user 10001:10001 ...` hoặc `user: "10001:10001"` trong Compose. Dùng khi image không có sẵn `USER` (nhưng phải chắc app vẫn chạy được với UID đó — ví dụ đọc được file của nó).

**Kiểm tra:**

```bash
docker image inspect taskhub:local --format '{{.Config.User}}'   # rỗng = root
docker run --rm --entrypoint id taskhub:local                    # uid=999(taskhub) gid=999(taskhub) ...
```

> 🟦 **Rootless mode** và **user namespace remap**: hai cơ chế để root trong container **không** phải root trên host. Rootless chạy cả daemon lẫn container bằng user thường ([Docker docs — Rootless mode](https://docs.docker.com/engine/security/rootless/)). Junior chỉ cần biết chúng tồn tại; việc chạy non-root trong image quan trọng hơn và áp dụng được ở mọi nơi.

### 4.4. 🟥 Capability, `--privileged`, `no-new-privileges`

**Capability** chia quyền root thành khoảng 40 mảnh: `CAP_CHOWN` (đổi chủ file), `CAP_NET_BIND_SERVICE` (nghe port < 1024), `CAP_SYS_ADMIN` (gần như mọi thứ), `CAP_NET_ADMIN` (cấu hình mạng — bạn đã dùng ở lab iptables Module 02)…

Docker cấp cho container một **tập mặc định hạn chế**. Tài liệu Docker khuyến nghị đi xa hơn: **bỏ hết, chỉ thêm lại cái thật sự cần**.

```bash
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE ...
```

App Java chạy non-root nghe port 8080 thường **không cần capability nào** → `--cap-drop ALL` là đủ.

**`--privileged` — không dùng.** Cờ này cho container gần như mọi capability và quyền truy cập thiết bị của host. Docker docs viết thẳng: *"A container with `--privileged` is not a securely sandboxed process"*. Nếu một hướng dẫn trên mạng bảo thêm `--privileged` để "hết lỗi", hãy tìm capability cụ thể đang thiếu và chỉ thêm cái đó.

**`--security-opt no-new-privileges`**: ngăn process trong container **leo thang đặc quyền** qua chương trình setuid (như `sudo`, `su`, `passwd` — nhớ setuid ở [Linux bài 03](../01-LINUX/03-permissions-users-groups.md)). Bật mặc định cho container ứng dụng — app không có lý do gì để chạy `sudo`.

### 4.5. 🟥 Read-only filesystem và giới hạn tài nguyên

**Read-only root filesystem** (`--read-only`): filesystem của container chỉ đọc. Kẻ tấn công không thể tải mã độc về rồi ghi đè file trong container. App cần ghi ở đâu thì mở đúng chỗ đó:

- `--tmpfs /tmp` — thư mục tạm trong RAM (mất khi container dừng). Spring Boot/Tomcat cần ghi vào `/tmp`.
- Volume — cho dữ liệu cần giữ lại.

**Giới hạn tài nguyên** (nối với cgroup):

| Cờ `docker run` | Khóa Compose | Ý nghĩa |
|---|---|---|
| `--memory 512m` | `mem_limit: 512m` | RAM tối đa. Vượt → kernel giết process (OOM) → exit 137 |
| `--cpus 1.5` | `cpus: 1.5` | Tối đa 1,5 nhân CPU |
| `--pids-limit 200` | `pids_limit: 200` | Số process/thread tối đa — chặn "fork bomb" |

Không giới hạn RAM thì một bug rò rỉ bộ nhớ trong một container có thể làm cả server (và mọi container khác) chết theo.

> ⚠️ Với Java: JVM hiện đại tự đọc giới hạn RAM của container để tính kích thước heap. `ENTRYPOINT` của taskhub có `-XX:MaxRAMPercentage=75.0` — heap tối đa bằng 75% giới hạn RAM của container, phần còn lại cho bộ nhớ ngoài heap (thread, metaspace…). Vì vậy **phải** đặt `mem_limit` thì cờ này mới có ý nghĩa rõ ràng. Đặt quá thấp (ví dụ 128m cho Spring Boot) → app chết ngay khi khởi động. Bắt đầu từ 512m–768m rồi đo bằng `docker stats` ([bài 08](08-container-troubleshooting.md)).

### 4.6. 🟥 Chọn image nền an toàn

| Nguyên tắc | Vì sao | Áp dụng cho taskhub |
|---|---|---|
| **Image chính thức hoặc từ nhà phát hành đáng tin** | Image lạ có thể chứa mã độc; image chính thức được cập nhật vá lỗi | `eclipse-temurin`, `postgres`, `nginx` — đều là Docker Official Images |
| **Càng nhỏ càng tốt** | Ít gói = ít lỗ hổng = ít công cụ cho kẻ tấn công | Runtime dùng **JRE** (`21-jre-noble`), không dùng JDK — JRE không có trình biên dịch |
| **Pin version** | `latest` hôm nay khác `latest` tuần sau → build không lặp lại được, có thể kéo về bản lỗi | `eclipse-temurin:21-jre-noble`, `postgres:17`, `nginx:1.30-alpine` |
| **Pin digest** 🟨 | Tag có thể bị ghi đè; digest (`@sha256:...`) thì không bao giờ đổi | Dùng trong production nghiêm ngặt; đánh đổi: phải chủ động cập nhật |
| **Cập nhật định kỳ** | Pin version không có nghĩa là để yên mãi — bản vá ra liên tục | Rebuild hằng tuần/tháng, quét lại |

**Alpine** (dựa trên musl libc) rất nhỏ nhưng đôi khi gây khác biệt hành vi với ứng dụng quen glibc. Với Java, các bản `-noble` (Ubuntu 24.04) là lựa chọn an toàn, dễ debug; Alpine là tối ưu thêm khi đã hiểu rõ.

**Công cụ có sẵn trong image là con dao hai lưỡi.** `eclipse-temurin:21-jre-noble` cài sẵn `curl` và `wget` (xem [Dockerfile chính thức của Adoptium](https://github.com/adoptium/containers/blob/main/21/jre/ubuntu/noble/Dockerfile)). Tiện cho bạn: `HEALTHCHECK` của taskhub dùng `curl -fsS http://localhost:8080/actuator/health`, và bạn `exec` vào debug được. Nhưng cũng tiện cho **kẻ tấn công**: chiếm được app là có ngay công cụ tải mã độc về. Đây là đánh đổi có ý thức — ở mức Junior, giữ image `-noble` để dễ vận hành là hợp lý; khi cần siết chặt hơn thì có hai hướng 🟦:

🟦 **Distroless**: image chỉ chứa app và runtime, **không có shell, không có trình quản lý gói, không có curl** ([GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless)). Ví dụ Java 21: `gcr.io/distroless/java21-debian13`. Bảo mật rất tốt nhưng debug khó hơn (không `exec` vào shell được — [bài 08](08-container-troubleshooting.md) có cách xử lý) và healthcheck phải viết lại không dùng curl. Có biến thể `:debug` chứa busybox shell.

🟦 **jlink**: công cụ của JDK tạo ra một Java runtime **chỉ chứa các module app thật sự dùng**, đặt lên một base image tối thiểu — trang Docker Hub của `eclipse-temurin` cũng khuyến nghị cách này thay cho JRE đầy đủ. Đổi lại, Dockerfile phức tạp hơn.

### 4.7. 🟥 Quét lỗ hổng: CVE, severity, fixed version

**CVE** (Common Vulnerabilities and Exposures — mã lỗ hổng công khai) là mã định danh cho một lỗ hổng đã biết, dạng `CVE-<năm>-<số>`. Công cụ quét so danh sách gói trong image với cơ sở dữ liệu CVE.

**Trivy** (của Aqua Security) là công cụ quét mã nguồn mở phổ biến nhất, quét được:

| Lệnh | Quét gì | Dùng khi |
|---|---|---|
| `trivy image <image>` | Gói hệ điều hành + thư viện ứng dụng (jar) trong image | Trước khi push image, trong CI |
| `trivy fs <thư-mục>` | Dependency trong mã nguồn (`pom.xml`…), secret, cấu hình | Quét repo, trước cả khi build |
| `trivy config <thư-mục>` | Lỗi cấu hình trong Dockerfile, Kubernetes YAML, Terraform | Review hạ tầng dưới dạng code |

**Đọc một dòng báo cáo:**

| Cột | Ý nghĩa | Bạn hỏi gì |
|---|---|---|
| Library | Gói/thư viện có lỗ hổng | Gói này nằm ở base image hay do mình thêm? |
| Vulnerability | Mã CVE | Tra chi tiết khi cần |
| Severity | Mức độ: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `UNKNOWN` | Có phải xử lý ngay không? |
| Installed Version | Phiên bản đang có | |
| Fixed Version | Phiên bản đã vá — **rỗng nghĩa là chưa có bản vá** | Có cách sửa chưa? |
| Status | `fixed`, `affected`, `will_not_fix`… | |

**Xử lý thế nào?**

1. **Có fixed version, lỗ hổng ở base image** → rebuild với base image mới nhất cùng tag (`docker build --pull`), hoặc lên tag mới hơn. Đây là trường hợp phổ biến nhất.
2. **Có fixed version, lỗ hổng ở thư viện Java** → nâng phiên bản dependency trong `pom.xml` (thường bằng cách nâng phiên bản Spring Boot).
3. **Chưa có bản vá** → đánh giá: gói đó app có dùng không? Có đường tấn công không? Ghi nhận rủi ro, theo dõi; cân nhắc base image nhỏ hơn không chứa gói đó.
4. **Dương tính giả (false positive)** — công cụ báo nhầm (ví dụ nhận diện sai phiên bản) → xác minh rồi đưa vào danh sách bỏ qua (`.trivyignore`) **kèm lý do**.

> Mục tiêu thực tế **không phải** "0 CVE" — gần như không image nào đạt được. Mục tiêu là: **không có CRITICAL/HIGH có bản vá mà chưa vá**. Tuần 10 bạn đưa Trivy vào pipeline CI để build tự động **thất bại** khi có CRITICAL có bản vá; tuần 21 siết thêm mức HIGH.

**Docker Scout** 🟨: dịch vụ phân tích image của Docker, tích hợp sẵn trong Docker Desktop và Docker Hub — nó lập danh sách thành phần (SBOM) của image và đối chiếu với cơ sở dữ liệu lỗ hổng ([Docker Scout docs](https://docs.docker.com/scout/)). Bạn có thể thấy nó trong giao diện Docker Desktop. Giáo trình dùng Trivy làm công cụ chính vì miễn phí, chạy được ở mọi nơi (local, GitHub Actions, server).

### 4.8. 🟥 Secret: tuyệt đối không đưa vào image

**Sai lầm phổ biến nhất:**

```dockerfile
ENV DB_PASSWORD=SuperSecret123      # ❌
ARG GITHUB_TOKEN                     # ❌ nếu dùng để truyền secret
```

Vì sao sai? Image là một chuỗi layer **ai có image cũng đọc được**:

- `docker image inspect` hiện toàn bộ `ENV`.
- `docker history` hiện lệnh tạo từng layer, gồm cả giá trị `ARG` được dùng trong `RUN`.
- File secret bị `COPY` vào rồi `rm` ở layer sau **vẫn còn** trong layer cũ.

Docker docs khẳng định: *"Build arguments and environment variables are inappropriate for passing secrets"*.

**Cách đúng:**

| Thời điểm cần secret | Cách làm |
|---|---|
| **Lúc chạy** (app cần mật khẩu DB) — phổ biến nhất | Truyền biến môi trường lúc chạy: `docker run -e`, `--env-file`, hoặc `environment:` trong Compose lấy giá trị từ file `.env` **nằm ngoài Git** |
| **Lúc build** (cần token để tải dependency private) 🟨 | BuildKit secret mount: `RUN --mount=type=secret,id=token ...` + `docker build --secret id=token,src=...` — secret chỉ tồn tại trong lúc chạy lệnh `RUN` đó, không vào layer nào |
| **Lúc chạy, an toàn hơn biến môi trường** 🟦 | Compose secrets: secret được mount thành file `/run/secrets/<tên>` ([Compose docs — secrets](https://docs.docker.com/compose/how-tos/use-secrets/)). Biến môi trường có thể lộ qua `docker inspect`, log crash; file thì kiểm soát quyền được |

Quy tắc cho repo `taskhub`:

- `.env` chứa giá trị thật → **có trong `.gitignore`**.
- `.env.example` chứa tên biến với giá trị giả → commit để người khác biết cần đặt biến gì.
- Lỡ commit secret → coi như **đã lộ**: đổi (rotate) secret ngay, rồi mới dọn lịch sử Git ([Ôn tập Git](../03-GIT/00-git-quick-review.md)).

### 4.9. 🟨 Lint Dockerfile bằng Hadolint

**Hadolint** đọc Dockerfile và cảnh báo các thực hành chưa tốt: dùng `latest`, `apt-get install` không pin version, thiếu `--no-install-recommends`, quên `USER`… Mã quy tắc bắt đầu bằng `DL` là của Hadolint, `SC` là của ShellCheck (bạn đã gặp ở [Linux bài 06](../01-LINUX/06-bash-scripting.md)) dùng để kiểm tra lệnh shell trong `RUN`.

```bash
docker run --rm -i hadolint/hadolint < docker/Dockerfile
```

Coi cảnh báo của Hadolint là **gợi ý để suy nghĩ**, không phải luật tuyệt đối — có quy tắc bạn sẽ chủ động bỏ qua kèm lý do.

### 4.10. 🟥 Checklist bảo mật cho taskhub

| # | Biện pháp | Có ở v0? | Ghi chú |
|---|---|---|---|
| 1 | Runtime image JRE, không JDK | ✅ | Multi-stage, [bài 03](03-dockerfile-multistage.md) |
| 2 | Pin version mọi image | ✅ | `21-jre-noble`, `postgres:17`, `nginx:1.30-alpine` |
| 3 | App chạy non-root (system user `taskhub`), jar thuộc root | ✅ | `USER taskhub` trong Dockerfile |
| 3b | Runtime image không chứa công cụ thừa (curl, shell) | ⏳ Sau khi đi làm | 🟦 distroless/jlink — v0 giữ curl cho `HEALTHCHECK` |
| 4 | Secret trong `.env` ngoài Git, có `.env.example` | ✅ | |
| 5 | Chỉ nginx publish port; PostgreSQL không publish ra host | ✅ | [bài 05](05-docker-compose.md) |
| 6 | `no-new-privileges`, `cap_drop: [ALL]` cho `taskhub` | 🟨 Nên thêm ở v0 | Thử ở lab mục 9 |
| 7 | `read_only: true` + `tmpfs: /tmp` cho `taskhub` | 🟨 Nên thêm ở v0 | Kiểm thử kỹ: app có ghi chỗ nào khác ngoài `/tmp` không |
| 8 | Giới hạn `mem_limit`, `pids_limit` | 🟨 Nên thêm ở v0 | Đo bằng `docker stats` trước |
| 9 | Quét Trivy trong CI: chặn CRITICAL có bản vá (tuần 10), siết thêm HIGH (tuần 21) | ⏳ Tuần 10, 21 | Lý do chưa chặn HIGH ngay: [Module 05 bài 03](../05-CICD/03-github-actions-docker-registry.md) |
| 10 | Hadolint trong CI | 🟨 Tuần 10 (bài tập) | Bài tập 3 của [Module 05 bài 03](../05-CICD/03-github-actions-docker-registry.md) |
| 11 | Compose secrets thay biến môi trường | ⏳ Tuần 21 | 🟦 |
| 12 | Pin digest, ký image | ⏳ Sau khi đi làm | 🟦 |

### 4.11. Gặp lại ở đâu

| Ở đây | Gặp lại |
|---|---|
| Trivy | Bước quét trong GitHub Actions (tuần 10), DevSecOps (Module 10) |
| Secret lúc chạy | GitHub Secrets (Module 05), AWS SSM Parameter Store/Secrets Manager (Module 06), Kubernetes Secret (Module 09) |
| Non-root, capability, read-only | Kubernetes `securityContext`: `runAsNonRoot`, `capabilities.drop`, `readOnlyRootFilesystem` — cùng khái niệm, khác cú pháp |
| Giới hạn tài nguyên | Kubernetes `resources.limits`, ECS task size |
| Docker socket = root | CI runner tự host, Kubernetes node |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Image public chứa mật khẩu

Một bạn intern build image `taskhub` với `ENV SPRING_DATASOURCE_PASSWORD=prod-pass-2026` rồi push lên Docker Hub ở chế độ public để "demo cho nhanh". Ba ngày sau, database production bị truy cập lạ.

Chỉ cần một lệnh, ai cũng đọc được:

```bash
docker pull someone/taskhub:latest
docker image inspect someone/taskhub:latest --format '{{json .Config.Env}}'
```

```text
["PATH=/opt/java/openjdk/bin:...","SPRING_DATASOURCE_PASSWORD=prod-pass-2026", ...]
```

Xử lý đúng thứ tự: (1) **đổi mật khẩu database ngay**, (2) xóa/đặt private image, (3) sửa Dockerfile, (4) viết postmortem. Xóa image mà không đổi mật khẩu là vô nghĩa — ai đã pull rồi thì vẫn còn.

### Ví dụ 2: Container CI có docker.sock

Một team chạy Jenkins trong container và mount `/var/run/docker.sock` để Jenkins build được image. Một plugin Jenkins có lỗ hổng cho phép chạy lệnh từ xa. Kẻ tấn công chạy `docker run -v /:/host ...` qua socket đó → root trên server build, nơi chứa mọi credential deploy. Đây là kịch bản có thật trong nhiều báo cáo bảo mật. Cách giảm rủi ro: runner riêng, dùng một lần (ephemeral) — đúng cách GitHub Actions hosted runner hoạt động (tuần 9).

### Ví dụ 3: Không giới hạn RAM

Một container xử lý báo cáo bị rò rỉ bộ nhớ, dùng dần hết 8 GB RAM của server. Kernel kích hoạt OOM killer — và giết luôn container PostgreSQL vì nó chiếm nhiều RAM. Nếu container báo cáo có `mem_limit: 1g`, chỉ mình nó bị giết và khởi động lại.

---

## 6. Sơ đồ kiến trúc

### 6.1. Các lớp phòng thủ (defense in depth)

```text
 ┌───────────────────────────────────────────────────────────────┐
 │ HOST (EC2 / máy ảo Docker Desktop)                             │
 │   - Kernel cập nhật                                            │
 │   - Chỉ admin tin cậy thuộc group docker                       │
 │   - Không ai mount docker.sock vào container app               │
 │  ┌──────────────────────────────────────────────────────────┐ │
 │  │ CONTAINER taskhub                                          │ │
 │  │   cgroup: mem_limit 512m · cpus 1 · pids_limit 200         │ │
 │  │   capability: drop ALL      no-new-privileges              │ │
 │  │   filesystem: read-only  +  tmpfs /tmp                     │ │
 │  │  ┌──────────────────────────────────────────────────────┐ │ │
 │  │  │ PROCESS java (system user taskhub, không phải root)    │ │ │
 │  │  │   secret: biến môi trường lúc chạy, không nằm trong image│ │ │
 │  │  └──────────────────────────────────────────────────────┘ │ │
 │  │ IMAGE: eclipse-temurin:21-jre-noble (pin), đã quét Trivy   │ │
 │  └──────────────────────────────────────────────────────────┘ │
 └───────────────────────────────────────────────────────────────┘
```

Nếu kẻ tấn công vượt qua được một lớp (ví dụ tìm ra lỗi trong app), các lớp còn lại vẫn giới hạn những gì họ làm được.

### 6.2. Vì sao docker.sock = root

```text
 Container app (bị chiếm quyền)
        │  ghi lệnh vào /var/run/docker.sock (được mount vào)
        ▼
 dockerd (chạy ROOT trên host)
        │  "tạo container mới, mount / của host vào /host"
        ▼
 Container mới  ──chroot /host──►  shell root trên HOST
```

---

## 7. Các câu lệnh cần biết

| Lệnh / cờ | Mục đích | Mức |
|---|---|---|
| `docker image inspect --format '{{.Config.User}}'` | Image chạy bằng user nào | 🟥 |
| `docker run --user` | Chạy bằng UID/GID chỉ định | 🟥 |
| `docker run --read-only --tmpfs <path>` | Filesystem chỉ đọc, mở thư mục ghi tạm | 🟥 |
| `docker run --cap-drop ALL --cap-add <CAP>` | Bỏ mọi capability, thêm lại cái cần | 🟥 |
| `docker run --security-opt no-new-privileges` | Chặn leo thang đặc quyền | 🟥 |
| `docker run --memory --cpus --pids-limit` | Giới hạn tài nguyên | 🟥 |
| `docker history --no-trunc` | Xem lệnh tạo từng layer | 🟥 |
| `docker build --pull` | Luôn tải base image mới nhất của tag | 🟥 |
| `trivy image / fs / config` | Quét lỗ hổng, cấu hình | 🟥 |
| `docker build --secret` + `RUN --mount=type=secret` | Secret lúc build | 🟨 |
| `hadolint` | Lint Dockerfile | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu dưới đây là **minh họa** (Docker Desktop trên WSL, Ubuntu 24.04). ID, kích thước, số lượng CVE trên máy bạn sẽ khác.

### Kiểm tra user của image

```bash
docker image inspect nginx:1.30-alpine --format '{{.Config.User}}'
docker image inspect taskhub:local --format '{{.Config.User}}'
```

```text

taskhub
```

- Dòng trống với nginx → **không khai báo USER** → process chính chạy root. (Nginx khởi động master process bằng root rồi tạo worker process bằng user `nginx` — một thiết kế có chủ đích, nhưng master vẫn là root.)
- `taskhub` với image của bạn → đã chạy non-root nhờ `USER taskhub` trong Dockerfile.

`--format` dùng cú pháp Go template: `{{.Config.User}}` lấy trường `User` trong khối `Config` của JSON mà `inspect` trả về. Chạy `docker image inspect <image>` không có `--format` để thấy toàn bộ JSON.

### `--read-only` và `--tmpfs`

```bash
docker run --rm --read-only nginx:1.30-alpine
```

```text
... [emerg] 1#1: mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)
nginx: [emerg] mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)
```

Đọc lỗi theo cấu trúc quen thuộc ([Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md#12-đọc-thông-báo-lỗi-và-xử-lý)): chương trình `nginx`, đối tượng `/var/cache/nginx/client_temp`, mô tả `Read-only file system` (mã lỗi 30 = `EROFS`). Nginx cần ghi cache tạm — mở đúng chỗ đó:

```bash
docker run --rm -d --name ro-nginx --read-only \
  --tmpfs /var/cache/nginx --tmpfs /var/run \
  -p 18070:80 nginx:1.30-alpine
curl -sI http://localhost:18070 | head -1
docker rm -f ro-nginx
```

```text
HTTP/1.1 200 OK
```

| Tham số | Ý nghĩa |
|---|---|
| `--read-only` | Root filesystem của container chỉ đọc |
| `--tmpfs /var/cache/nginx` | Gắn một thư mục trong RAM, ghi được, mất khi container dừng |
| `--tmpfs /var/run` | Nginx ghi file PID (`nginx.pid`) ở đây |

Phương pháp: bật `--read-only`, chạy, **đọc lỗi để biết app cần ghi chỗ nào**, mở đúng chỗ đó. Không mở cả `/`.

### `--cap-drop` / `--cap-add`

```bash
docker run --rm --cap-drop ALL nginx:1.30-alpine
```

```text
... [emerg] 1#1: chown("/var/cache/nginx/client_temp", 101) failed (1: Operation not permitted)
```

Master process của nginx (root) cần đổi chủ thư mục cache cho user `nginx` (UID 101) → cần `CAP_CHOWN`. Thêm lại từng capability theo thông báo lỗi:

```bash
docker run --rm -d --name cap-nginx --cap-drop ALL \
  --cap-add CHOWN --cap-add SETUID --cap-add SETGID \
  -p 18071:80 nginx:1.30-alpine
curl -sI http://localhost:18071 | head -1
docker rm -f cap-nginx
```

- `SETUID`, `SETGID`: để master process chuyển worker sang user `nginx`.
- Tùy phiên bản và cấu hình, có thể cần thêm capability khác — **đọc log, thêm đúng cái được nhắc tới**. Đây chính là kỹ năng bài này muốn rèn.

Với app non-root như taskhub, `--cap-drop ALL` thường chạy được ngay mà không cần thêm gì — vì process không làm việc gì cần quyền root.

### `--security-opt no-new-privileges`

```bash
docker run --rm --security-opt no-new-privileges <image> ...
```

```yaml
# Compose
security_opt:
  - no-new-privileges:true
```

Cơ chế: kernel đặt cờ `no_new_privs` cho process đầu tiên của container, cờ này được **kế thừa** bởi mọi process con và không thể gỡ. Khi cờ bật, chạy một chương trình setuid (như `sudo`) **không** làm process nhận thêm quyền — `sudo` sẽ báo lỗi dù cấu hình sudoers cho phép. Bạn sẽ kiểm chứng điều này ở [bài tập 3](#14-bài-tập-tự-làm).

### Giới hạn tài nguyên

```bash
docker run --rm --memory 256m --cpus 0.5 --pids-limit 100 python:3.12-slim \
  python -c "print(open('/sys/fs/cgroup/memory.max').read())"
```

```text
268435456
```

`268435456` byte = 256 MiB — giới hạn được kernel áp dụng qua cgroup v2 và process bên trong đọc được. (Nếu file không tồn tại, máy đang dùng cgroup v1 — không ảnh hưởng tới việc giới hạn có hiệu lực.)

### `docker history` — chứng minh secret lộ

```bash
docker history --no-trunc leak-demo:1 --format '{{.CreatedBy}}' | head -5
```

```text
CMD ["sh" "-c" "echo app running"]
RUN |1 BUILD_TOKEN=ghp_FAKE_token_for_demo /bin/sh -c echo "dùng token để tải dependency..." # buildkit
ENV DB_PASSWORD=SuperSecret123
ARG BUILD_TOKEN
...
```

Cả `ENV` lẫn giá trị `ARG` dùng trong `RUN` đều hiện rõ. `--no-trunc` để không bị cắt ngắn.

### Trivy chạy bằng container

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.cache/trivy:/root/.cache/" \
  aquasec/trivy:0.76.1 image --severity HIGH,CRITICAL eclipse-temurin:21-jre-noble
```

| Phần | Ý nghĩa |
|---|---|
| `aquasec/trivy:0.76.1` | Image chính thức của Trivy, **pin version** (kiểm tra bản mới trên Docker Hub khi học) |
| `-v /var/run/docker.sock:...` | Cho Trivy đọc image **có sẵn trên máy** qua daemon. Đây là ngoại lệ có cân nhắc ở mục 4.2: công cụ tin cậy, chạy xong tự xóa (`--rm`) |
| `-v "$HOME/.cache/trivy:/root/.cache/"` | Giữ cơ sở dữ liệu lỗ hổng giữa các lần chạy — lần đầu tải vài trăm MB, các lần sau nhanh |
| `image` | Loại mục tiêu: image |
| `--severity HIGH,CRITICAL` | Chỉ hiện mức cao — đỡ nhiễu khi mới học |

Đầu ra minh họa (rút gọn, mã CVE là giả):

```text
eclipse-temurin:21-jre-noble (ubuntu 24.04)
Total: 2 (HIGH: 2, CRITICAL: 0)

┌──────────┬────────────────┬──────────┬──────────┬───────────────────┬───────────────┬──────────────────────────┐
│ Library  │ Vulnerability  │ Severity │ Status   │ Installed Version │ Fixed Version │ Title                    │
├──────────┼────────────────┼──────────┼──────────┼───────────────────┼───────────────┼──────────────────────────┤
│ libexamp │ CVE-2026-XXXXX │ HIGH     │ fixed    │ 1.2.3-1ubuntu1    │ 1.2.3-1ubuntu2│ heap overflow in ...     │
│ libother │ CVE-2026-YYYYY │ HIGH     │ affected │ 4.5.6-2           │               │ ...                      │
└──────────┴────────────────┴──────────┴──────────┴───────────────────┴───────────────┴──────────────────────────┘
```

- Dòng 1: `fixed` + có Fixed Version → rebuild với `--pull` có thể đã có bản vá.
- Dòng 2: `affected` + Fixed Version rỗng → chưa có bản vá, chỉ theo dõi và đánh giá.

**Cách không cần docker.sock** 🟨: xuất image ra file rồi cho Trivy đọc file:

```bash
docker save taskhub:local -o /tmp/taskhub.tar
docker run --rm -v /tmp:/scan -v "$HOME/.cache/trivy:/root/.cache/" \
  aquasec/trivy:0.76.1 image --input /scan/taskhub.tar --severity HIGH,CRITICAL
```

### Hadolint

```bash
docker run --rm -i hadolint/hadolint < docker/Dockerfile
```

```text
-:9 DL3008 warning: Pin versions in apt get install. ...
```

Định dạng: `<file>:<dòng> <mã quy tắc> <mức>: <mô tả>`. `-` nghĩa là đọc từ stdin.

---

## 9. Bài thực hành từng bước

**Lab: Kiểm tra và siết bảo mật cho taskhub** · `[WSL]` · ~75 phút

Chuẩn bị:

```bash
mkdir -p ~/devops-lab/04-docker/lab07 && cd ~/devops-lab/04-docker/lab07
docker image ls | grep -E 'taskhub|temurin'
```

Bạn cần image `taskhub` đã build ở [bài 03](03-dockerfile-multistage.md). Bài này gọi nó là `taskhub:local` — nếu tag của bạn khác, thay cho đúng.

### Bước 1 — Image chạy bằng user nào?

```bash
docker image inspect taskhub:local --format 'User={{.Config.User}}'
docker run --rm --entrypoint id taskhub:local
docker image inspect postgres:17 nginx:1.30-alpine --format '{{.RepoTags}} User={{.Config.User}}'
```

❓ taskhub chạy bằng UID nào? postgres và nginx khai báo USER gì? Đọc log khởi động của `postgres` trong compose của bạn (`docker compose logs postgres | head`) — entrypoint của postgres làm gì để không chạy server bằng root? (Gợi ý: nó dùng `gosu`/chuyển sang user `postgres`.)

### Bước 2 — Read-only và capability với nginx

Làm lại hai thí nghiệm ở mục 8 (`--read-only` rồi `--cap-drop ALL`). Ghi lại:

- Thông báo lỗi nguyên văn mỗi lần.
- Danh sách `--tmpfs` và `--cap-add` tối thiểu để nginx chạy được.

### Bước 3 — Siết bảo mật cho taskhub trong Compose

Trong thư mục dự án `taskhub`, tạo nhánh mới (quy trình ở [Git bài 02](../03-GIT/02-branching-merging-conflicts.md)):

```bash
cd ~/projects/taskhub
git switch -c feat/harden-container
```

Thêm vào service `taskhub` trong `compose.yaml`:

```yaml
  taskhub:
    # ... giữ nguyên cấu hình cũ ...
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    mem_limit: 768m
    pids_limit: 200
```

```bash
docker compose up -d
docker compose ps
docker compose logs taskhub --tail 30
curl -s http://localhost:8000/actuator/health
```

❓ App có lên `UP` không? Nếu không, đọc log: app đang cố ghi vào đâu? Mở đúng chỗ đó (thêm `tmpfs` hoặc volume) — **không** gỡ `read_only`.

### Bước 4 — Đo RAM thực tế

```bash
docker stats --no-stream
```

❓ taskhub đang dùng bao nhiêu RAM so với giới hạn 768m? Giới hạn này có hợp lý không? (Chi tiết về `docker stats` ở [bài 08](08-container-troubleshooting.md).)

### Bước 5 — Quét lỗ hổng JDK vs JRE

```bash
mkdir -p "$HOME/.cache/trivy"
for img in eclipse-temurin:21-jdk-noble eclipse-temurin:21-jre-noble; do
  echo "===== $img"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME/.cache/trivy:/root/.cache/" \
    aquasec/trivy:0.76.1 image --quiet --severity HIGH,CRITICAL "$img" | grep -E '^Total|^eclipse'
done
docker image ls eclipse-temurin
```

❓ So sánh số lỗ hổng HIGH/CRITICAL và kích thước của hai image. Kết luận gì về việc dùng JRE ở stage runtime?

### Bước 6 — Quét image taskhub

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.cache/trivy:/root/.cache/" \
  aquasec/trivy:0.76.1 image --severity HIGH,CRITICAL taskhub:local > trivy-taskhub.txt
less trivy-taskhub.txt
```

Báo cáo có nhiều phần: phần hệ điều hành (`ubuntu 24.04`) và phần thư viện Java (`Java (jar)`). Với **3 lỗ hổng** bất kỳ, điền bảng:

| CVE | Gói | Ở base image hay thư viện Java? | Có Fixed Version? | Hướng xử lý |
|---|---|---|---|---|

Nếu báo cáo sạch (0 HIGH/CRITICAL) — tốt! Chạy lại không có `--severity` và làm bảng với 3 lỗ hổng mức MEDIUM/LOW.

### Bước 7 — Chứng minh secret lộ qua image

```bash
cd ~/devops-lab/04-docker/lab07
docker build -t leak-demo:1 --build-arg BUILD_TOKEN=ghp_FAKE_token_for_demo - <<'EOF'
FROM alpine:3.20
ARG BUILD_TOKEN
ENV DB_PASSWORD=SuperSecret123
RUN echo "dùng token để tải dependency..." && test -n "$BUILD_TOKEN"
CMD ["sh", "-c", "echo app running"]
EOF
docker image inspect leak-demo:1 --format '{{json .Config.Env}}'
docker history --no-trunc leak-demo:1 --format '{{.CreatedBy}}'
```

❓ Bạn tìm thấy `DB_PASSWORD` ở đâu? `BUILD_TOKEN` ở đâu? Người khác chỉ cần quyền gì để đọc được chúng?

> `docker build ... -` đọc Dockerfile từ stdin (here-document ở [Linux bài 06](../01-LINUX/06-bash-scripting.md)), không cần tạo file.

### Bước 8 — 🟨 Lint Dockerfile

```bash
cd ~/projects/taskhub
docker run --rm -i hadolint/hadolint < docker/Dockerfile
```

Với mỗi cảnh báo: sửa, hoặc ghi lý do chấp nhận.

### Bước 9 — Checklist và commit

Sao chép bảng checklist ở mục 4.10 vào `~/projects/taskhub/docs/security-checklist.md`, cập nhật cột trạng thái theo thực tế dự án của bạn. Commit và mở Pull Request:

```bash
git add compose.yaml docs/security-checklist.md
git commit -m "chore(docker): harden taskhub container (read-only, cap_drop, limits)"
git push -u origin feat/harden-container
```

Lưu kết quả lab (lỗi nguyên văn, bảng CVE, câu trả lời ❓) vào `~/devops-journey/week08/lab07-security.md`.

Dọn dẹp: `docker image rm leak-demo:1`.

---

## 10. Kết quả mong đợi

- **Bước 1:** taskhub chạy bằng system user `taskhub` (UID < 1000, thường là `999`), **không phải** `ubuntu` (UID 1000) có sẵn trong base image. `postgres:17` và `nginx:1.30-alpine` không khai báo `USER` — entrypoint của postgres khởi động bằng root để chuẩn bị thư mục dữ liệu rồi **chuyển sang user `postgres`** trước khi chạy server; nginx giữ master là root, worker chạy user `nginx`.
- **Bước 2:** nginx cần `tmpfs` cho `/var/cache/nginx` và `/var/run`; với `--cap-drop ALL` cần thêm ít nhất `CHOWN`, `SETUID`, `SETGID` (có thể khác theo phiên bản — đọc log).
- **Bước 3:** taskhub thường chạy được với `read_only` + `tmpfs: /tmp` + `cap_drop: ALL`, vì Spring Boot/Tomcat chỉ cần ghi thư mục tạm. Nếu không, log sẽ chỉ rõ đường dẫn bị `Read-only file system`.
- **Bước 4:** Spring Boot nhỏ thường dùng vài trăm MB. Giới hạn nên cao hơn mức sử dụng ổn định một khoảng an toàn.
- **Bước 5:** JDK image lớn hơn JRE đáng kể và **thường** có nhiều lỗ hổng hơn (nhiều gói hơn). Kết luận: stage runtime dùng JRE vừa nhỏ vừa giảm bề mặt tấn công.
- **Bước 7:** `DB_PASSWORD` hiện trong `Config.Env` (inspect) và trong history; `BUILD_TOKEN` hiện trong history ở dòng `RUN |1 BUILD_TOKEN=...`. Chỉ cần **có image** (pull được) là đọc được — không cần quyền gì đặc biệt.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `Read-only file system` sau khi bật `read_only` | App ghi vào thư mục không được mở | Đọc đường dẫn trong log, thêm `tmpfs` hoặc volume đúng chỗ đó |
| `Operation not permitted` sau `cap_drop: ALL` | Process cần một capability cụ thể | Thêm đúng capability (`CHOWN`, `SETUID`…). **Không** quay về `--privileged` |
| Container bị giết ngay, exit 137, `OOMKilled: true` | `mem_limit` quá thấp so với JVM | Tăng giới hạn, đo bằng `docker stats` ([bài 08](08-container-troubleshooting.md)) |
| `permission denied` khi app non-root ghi vào volume | Volume thuộc root | Tạo thư mục và `chown` cho UID của app trong Dockerfile trước khi khai báo volume ([bài 08](08-container-troubleshooting.md)) |
| `permission denied while trying to connect to the Docker daemon socket` khi chạy Trivy | User WSL chưa có quyền dùng Docker | Kiểm tra Docker Desktop đang chạy và đã bật WSL integration |
| Trivy chạy rất lâu lần đầu | Tải cơ sở dữ liệu lỗ hổng | Bình thường; mount thư mục cache để lần sau nhanh |
| `.env` xuất hiện trong `git status` | Chưa có trong `.gitignore` | Thêm `.env` vào `.gitignore` **trước** khi `git add` |
| Đã xóa secret khỏi Dockerfile nhưng image cũ vẫn chứa | Layer cũ vẫn còn trong image và registry | Đổi secret, xóa image/tag cũ trên registry |

---

## 12. Đọc log và xử lý lỗi

Các lỗi bảo mật container có dạng rất đặc trưng — nhận ra mã lỗi là biết ngay nguyên nhân:

| Thông báo | Mã errno | Nghĩa trong bối cảnh bài này |
|---|---|---|
| `Read-only file system` | 30 (`EROFS`) | Đang chạy `--read-only`, ghi vào chỗ chưa mở |
| `Operation not permitted` | 1 (`EPERM`) | Thiếu capability, hoặc bị `no-new-privileges` chặn |
| `Permission denied` | 13 (`EACCES`) | Quyền file/thư mục thông thường — user không có quyền (thường do non-root + volume thuộc root) |

Phân biệt `EPERM` và `EACCES` (đã gặp ở [Linux bài 03](../01-LINUX/03-permissions-users-groups.md)): `EACCES` = quyền rwx không cho phép; `EPERM` = thao tác cần **đặc quyền** mà process không có — trong container thường là capability.

**Quy trình khi container "siết bảo mật xong thì không chạy":**

1. `docker compose logs <service> --tail 50` — tìm dòng có `EROFS`/`EPERM`/`EACCES` và **đường dẫn hoặc thao tác** đi kèm.
2. Nới **đúng một thứ**: thêm một `tmpfs`, một capability, hoặc sửa quyền một thư mục.
3. `docker compose up -d` rồi kiểm tra lại.
4. Ghi vào nhật ký debug: thứ đã nới và **lý do** app cần nó. Danh sách này chính là tài liệu bảo mật của dự án.

Đọc báo cáo Trivy cũng là một dạng "đọc log": luôn nhìn cột **Fixed Version** trước — nó quyết định bạn có hành động được ngay hay không.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Container và máy ảo khác nhau thế nào về **ranh giới bảo mật**? Vì sao một lỗ hổng kernel nguy hiểm với container hơn với máy ảo?
2. Root trong container có phải root trên host không? Docker đã làm gì để giảm rủi ro, và cấu hình nào có thể phá vỡ các biện pháp đó?
3. Giải thích vì sao thêm một user vào group `docker` tương đương cấp quyền root. Viết lệnh minh họa.
4. Vì sao không mount `/var/run/docker.sock` vào container ứng dụng? Trường hợp nào chấp nhận được và cần điều kiện gì?
5. `--cap-drop ALL` làm gì? Vì sao app Java non-root nghe port 8080 thường không cần thêm capability nào?
6. `--privileged` khác `--cap-add NET_ADMIN` thế nào? Khi gặp hướng dẫn bảo thêm `--privileged`, bạn làm gì?
7. `no-new-privileges` chặn điều gì? Liên hệ với setuid ở Linux bài 03.
8. `read_only: true` bảo vệ khỏi kiểu tấn công nào? Tại sao Spring Boot cần `tmpfs: /tmp` khi bật read-only?
9. Không đặt `mem_limit` có thể gây hậu quả gì cho **các container khác** trên cùng server?
10. Kể 4 tiêu chí chọn base image. Vì sao stage runtime nên dùng JRE thay vì JDK?
11. Trong báo cáo Trivy, cột Fixed Version rỗng nghĩa là gì? Bạn xử lý lỗ hổng CRITICAL đó thế nào?
12. Vì sao "0 CVE" không phải mục tiêu thực tế? Mục tiêu hợp lý là gì?
13. Chứng minh `ENV DB_PASSWORD=...` trong Dockerfile làm lộ mật khẩu bằng 2 lệnh. Nếu lỡ push image đó lên registry public, các bước xử lý theo thứ tự là gì?
14. Secret cần lúc build và secret cần lúc chạy được xử lý khác nhau thế nào?
15. Phân biệt `Read-only file system`, `Operation not permitted`, `Permission denied` trong bối cảnh container.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/07-solutions.md](solutions/07-solutions.md) — chỉ mở sau khi đã tự làm và ghi câu trả lời.

**Bài 1 — Escape bằng cấu hình sai.** Chạy `docker run --rm -it -v /:/host ubuntu:22.04 bash`. Bên trong, chạy `ls /host`, `cat /host/etc/os-release`. Bạn đang thấy filesystem của máy nào (trên Docker Desktop)? Viết 5 câu giải thích vì sao đây là lý do "group docker = root", và trên một server EC2 thật thì hậu quả là gì. ⚠️ Không sửa/xóa gì trong `/host`. Gõ `exit` ngay sau khi quan sát.

**Bài 2 — Capability tối thiểu cho postgres.** Thử chạy `postgres:17` với `--cap-drop ALL` (kèm `-e POSTGRES_PASSWORD=x`). Đọc lỗi, thêm lại từng capability cho đến khi chạy được. Ghi danh sách tối thiểu và giải thích vì sao entrypoint của postgres cần mỗi capability đó.

**Bài 3 — Kiểm chứng no-new-privileges.** Trong container `ubuntu:22.04`, cài `sudo`, tạo user `u` có quyền `NOPASSWD: ALL` trong `/etc/sudoers.d/u` (nhớ quyền file 0440 — Linux bài 03). Chạy `su u -c "sudo -n id"` trong hai trường hợp: không có và có `--security-opt no-new-privileges`. So sánh kết quả, giải thích cơ chế.

**Bài 4 — Secret lúc build đúng cách.** Viết Dockerfile dùng `RUN --mount=type=secret,id=token` để đọc một token giả từ file `token.txt` (in ra độ dài token, không in token). Build bằng `docker build --secret id=token,src=token.txt`. Chứng minh bằng `docker history --no-trunc` và `docker image inspect` rằng token không nằm trong image.

**Bài 5 — Báo cáo bảo mật.** Viết `~/devops-journey/week08/security-report-taskhub.md` (tối đa 1 trang) như gửi cho trưởng nhóm: tóm tắt kết quả Trivy (số lượng theo mức, bao nhiêu có bản vá), 3 hành động ưu tiên, các biện pháp đã áp dụng ở v0, rủi ro còn lại và kế hoạch.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Giải thích được sơ đồ 6.2 (docker.sock = root) cho người khác mà không nhìn tài liệu.
- [ ] Container `taskhub` của bạn chạy non-root, `read_only`, `cap_drop: ALL`, `no-new-privileges`, có giới hạn RAM — và **vẫn healthy**.
- [ ] Gặp `EROFS`/`EPERM`/`EACCES`, bạn biết ngay nên nới cái gì mà không cần đoán.
- [ ] Đọc được báo cáo Trivy và phân loại được lỗ hổng nào xử lý được ngay.
- [ ] Chứng minh được (bằng lệnh) vì sao không đưa secret vào `ENV`/`ARG`.
- [ ] Làm xong Bài tập 2 và 4 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Docker docs — Docker Engine security](https://docs.docker.com/engine/security/) | Daemon attack surface, capability | 2026-10-31 |
| [Docker docs — Rootless mode](https://docs.docker.com/engine/security/rootless/) | 🟦 Rootless | 2026-10-31 |
| [Docker docs — `docker container run`](https://docs.docker.com/reference/cli/docker/container/run/) | `--read-only`, `--cap-drop`, `--privileged`, `--pids-limit`, `--security-opt` | 2026-10-31 |
| [Docker docs — Resource constraints](https://docs.docker.com/engine/containers/resource_constraints/) | `--memory`, `--cpus`, OOM | 2026-10-31 |
| [Docker docs — Build secrets](https://docs.docker.com/build/building/secrets/) | Secret mount lúc build | 2026-10-31 |
| [Docker docs — Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/) | 🟦 Compose secrets | 2026-10-31 |
| [Docker docs — Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/) | Cảnh báo group `docker` | 2026-10-31 |
| [Docker Scout docs](https://docs.docker.com/scout/) | 🟨 Docker Scout | 2026-10-31 |
| [Trivy docs — First steps](https://trivy.dev/docs/latest/getting-started/) và [Installation](https://trivy.dev/docs/latest/getting-started/installation/) | Lệnh Trivy, chạy bằng Docker | 2026-10-31 |
| [Hadolint (GitHub)](https://github.com/hadolint/hadolint) | 🟨 Lint Dockerfile | 2026-10-31 |
| [GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless) | 🟦 Distroless | 2026-10-31 |
